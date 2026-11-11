"""
Routes CRUD du profil élève (SQLModel / SQLite).

Identification : l'UID Firebase est transmis dans l'en-tête `X-User-Id`.
⚠️ En production, remplacer `get_current_uid` par une vérification du jeton
Firebase ID (firebase_admin.auth.verify_id_token) : en l'état, l'en-tête n'est
pas authentifié.
"""

import re
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field as PField, field_validator
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlmodel import Session, select

try:
    from database import get_session
    from models.student import (
        AcademicRecord, GradeLevel, MonthlyCheckpoint, StudentProfile,
        TargetTrack, WeeklyPlan, current_school_year,
    )
except ImportError:
    from backend.database import get_session
    from backend.models.student import (
        AcademicRecord, GradeLevel, MonthlyCheckpoint, StudentProfile,
        TargetTrack, WeeklyPlan, current_school_year,
    )

router = APIRouter(prefix="/profile", tags=["profile"])

RIASEC_KEYS = {"R", "I", "A", "S", "E", "C"}
MAX_SPECIALTIES = 3  # 3 en Première, 2 conservées en Terminale


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _dedupe(items: List[str]) -> List[str]:
    """Nettoie et dédoublonne (insensible à la casse) en conservant l'ordre."""
    seen, out = set(), []
    for raw in items:
        val = (raw or "").strip()
        if val and val.lower() not in seen:
            seen.add(val.lower())
            out.append(val)
    return out


# ---------------------------------------------------------------------------
# Authentification (UID Firebase)
# ---------------------------------------------------------------------------
def get_current_uid(x_user_id: str = Header(..., alias="X-User-Id")) -> str:
    uid = x_user_id.strip()
    if not uid or len(uid) > 128:
        raise HTTPException(status_code=401, detail="En-tête X-User-Id (UID Firebase) manquant ou invalide.")
    return uid


def _get_profile_or_404(session: Session, uid: str) -> StudentProfile:
    profile = session.exec(select(StudentProfile).where(StudentProfile.user_id == uid)).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profil élève introuvable. Créez-le via POST /api/profile.")
    return profile


# ---------------------------------------------------------------------------
# Schémas d'entrée
# ---------------------------------------------------------------------------
class ProfileUpsert(BaseModel):
    grade_level: GradeLevel
    target_domain: Optional[str] = PField(default=None, max_length=120)
    interests: Optional[List[str]] = None
    specialties: Optional[List[str]] = None
    riasec_scores: Optional[Dict[str, float]] = None

    @field_validator("interests")
    @classmethod
    def _clean_interests(cls, v):
        if v is None:
            return v
        v = _dedupe(v)
        if len(v) > 15:
            raise ValueError("15 centres d'intérêt maximum.")
        return v

    @field_validator("specialties")
    @classmethod
    def _clean_specialties(cls, v):
        if v is None:
            return v
        v = _dedupe(v)
        if len(v) > MAX_SPECIALTIES:
            raise ValueError(f"{MAX_SPECIALTIES} spécialités maximum.")
        return v

    @field_validator("riasec_scores")
    @classmethod
    def _check_riasec(cls, v):
        if v is None:
            return v
        cleaned = {}
        for key, score in v.items():
            k = key.strip().upper()
            if k not in RIASEC_KEYS:
                raise ValueError(f"Dimension RIASEC inconnue : {key} (attendu : R, I, A, S, E, C).")
            if not 0 <= score <= 10:
                raise ValueError(f"Score RIASEC {k} hors de l'échelle 0-10.")
            cleaned[k] = round(float(score), 2)
        return cleaned


class GradeEntry(BaseModel):
    subject: str = PField(min_length=1, max_length=80)
    grade: float = PField(ge=0, le=20)
    class_average: Optional[float] = PField(default=None, ge=0, le=20)

    @field_validator("subject")
    @classmethod
    def _strip_subject(cls, v):
        v = v.strip()
        if not v:
            raise ValueError("Nom de matière vide.")
        return v


class GradesUpsert(BaseModel):
    school_year: Optional[str] = None  # Par défaut : année scolaire en cours
    trimester: int = PField(ge=1, le=3)
    grades: List[GradeEntry] = PField(min_length=1, max_length=30)

    @field_validator("school_year")
    @classmethod
    def _check_school_year(cls, v):
        if v is None:
            return v
        m = re.fullmatch(r"(\d{4})-(\d{4})", v.strip())
        if not m or int(m.group(2)) != int(m.group(1)) + 1:
            raise ValueError("Format attendu : 'AAAA-AAAA' avec deux années consécutives (ex: 2026-2027).")
        return v.strip()

    @field_validator("grades")
    @classmethod
    def _no_duplicate_subjects(cls, v):
        subjects = [g.subject.lower() for g in v]
        if len(subjects) != len(set(subjects)):
            raise ValueError("Une matière apparaît plusieurs fois dans le même trimestre.")
        return v


# ---------------------------------------------------------------------------
# Sérialisation
# ---------------------------------------------------------------------------
def _profile_dict(p: StudentProfile) -> Dict[str, Any]:
    return {
        "id": p.id,
        "user_id": p.user_id,
        "grade_level": p.grade_level,
        "target_domain": p.target_domain,
        "interests": p.interests,
        "specialties": p.specialties,
        "riasec_scores": p.riasec_scores,
        "created_at": p.created_at,
        "updated_at": p.updated_at,
    }


def _avg(values: List[float]) -> Optional[float]:
    return round(sum(values) / len(values), 2) if values else None


def _aggregate_grades(records: List[AcademicRecord]) -> Dict[str, Any]:
    """Moyennes non pondérées (les coefficients ne sont pas encore modélisés)."""
    if not records:
        return {"latest": None, "subject_averages_current_year": {}, "by_year": {}}

    by_year: Dict[str, Dict[int, List[AcademicRecord]]] = defaultdict(lambda: defaultdict(list))
    for r in records:
        by_year[r.school_year][r.trimester].append(r)

    by_year_out: Dict[str, Any] = {}
    for year in sorted(by_year):
        by_year_out[year] = {}
        for tri in sorted(by_year[year]):
            recs = sorted(by_year[year][tri], key=lambda x: x.subject.lower())
            by_year_out[year][str(tri)] = {
                "grade_level": recs[0].grade_level,
                "general_average": _avg([r.grade for r in recs]),
                "subjects": [
                    {
                        "subject": r.subject,
                        "grade": r.grade,
                        "class_average": r.class_average,
                        "delta_vs_class": round(r.grade - r.class_average, 2)
                        if r.class_average is not None else None,
                    }
                    for r in recs
                ],
            }

    latest_year = max(by_year)
    latest_tri = max(by_year[latest_year])
    per_subject: Dict[str, List[float]] = defaultdict(list)
    for tri_recs in by_year[latest_year].values():
        for r in tri_recs:
            per_subject[r.subject].append(r.grade)

    return {
        "latest": {
            "school_year": latest_year,
            "trimester": latest_tri,
            "general_average": by_year_out[latest_year][str(latest_tri)]["general_average"],
        },
        "subject_averages_current_year": {s: _avg(g) for s, g in sorted(per_subject.items())},
        "by_year": by_year_out,
    }


def _fetch_formations(session: Session, ids: List[str]) -> Dict[str, Dict[str, Any]]:
    """Lecture SQL des formations Parcoursup référencées (données Open Data)."""
    if not ids:
        return {}
    placeholders = ", ".join(f":id{i}" for i in range(len(ids)))
    params = {f"id{i}": fid for i, fid in enumerate(ids)}
    try:
        rows = session.execute(
            text(
                "SELECT formation_id, etablissement, filiere_detail, ville, taux_acces, "
                "seuil_moyenne_estime, mention_tres_bien_pct, bac_general_pct "
                f"FROM parcoursup_formations WHERE formation_id IN ({placeholders})"
            ),
            params,
        ).mappings().all()
    except OperationalError:
        return {}  # Données Open Data pas encore ingérées
    return {r["formation_id"]: dict(r) for r in rows}


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@router.post("")
def upsert_profile(
    payload: ProfileUpsert,
    uid: str = Depends(get_current_uid),
    session: Session = Depends(get_session),
):
    """Crée ou met à jour le profil. Les champs omis (None) ne sont pas écrasés."""
    profile = session.exec(select(StudentProfile).where(StudentProfile.user_id == uid)).first()
    created = profile is None

    if created:
        profile = StudentProfile(user_id=uid, grade_level=payload.grade_level)

    profile.grade_level = payload.grade_level
    if payload.target_domain is not None:
        profile.target_domain = payload.target_domain.strip() or None
    # Réassignation (et non mutation) pour que SQLAlchemy détecte le changement JSON.
    if payload.interests is not None:
        profile.interests = list(payload.interests)
    if payload.specialties is not None:
        profile.specialties = list(payload.specialties)
    if payload.riasec_scores is not None:
        profile.riasec_scores = dict(payload.riasec_scores)
    profile.updated_at = _utcnow()

    session.add(profile)
    session.commit()
    session.refresh(profile)
    return {"created": created, "profile": _profile_dict(profile)}


@router.post("/grades")
def upsert_grades(
    payload: GradesUpsert,
    uid: str = Depends(get_current_uid),
    session: Session = Depends(get_session),
):
    """Ajoute ou met à jour les notes d'un trimestre (upsert par matière)."""
    profile = _get_profile_or_404(session, uid)
    school_year = payload.school_year or current_school_year()

    existing = session.exec(
        select(AcademicRecord).where(
            AcademicRecord.student_profile_id == profile.id,
            AcademicRecord.school_year == school_year,
            AcademicRecord.trimester == payload.trimester,
        )
    ).all()
    by_subject = {r.subject.lower(): r for r in existing}

    inserted, updated = 0, 0
    now = _utcnow()
    for entry in payload.grades:
        rec = by_subject.get(entry.subject.lower())
        if rec is None:
            rec = AcademicRecord(
                student_profile_id=profile.id,
                school_year=school_year,
                grade_level=profile.grade_level,
                trimester=payload.trimester,
                subject=entry.subject,
            )
            inserted += 1
        else:
            updated += 1
        rec.grade = round(entry.grade, 2)
        rec.class_average = round(entry.class_average, 2) if entry.class_average is not None else None
        rec.updated_at = now
        session.add(rec)

    session.commit()

    records = session.exec(
        select(AcademicRecord).where(
            AcademicRecord.student_profile_id == profile.id,
            AcademicRecord.school_year == school_year,
            AcademicRecord.trimester == payload.trimester,
        )
    ).all()
    return {
        "school_year": school_year,
        "trimester": payload.trimester,
        "inserted": inserted,
        "updated": updated,
        "general_average": _avg([r.grade for r in records]),
        "subjects": sorted(
            ({"subject": r.subject, "grade": r.grade, "class_average": r.class_average} for r in records),
            key=lambda x: x["subject"].lower(),
        ),
    }


@router.get("/me")
def get_my_profile(
    uid: str = Depends(get_current_uid),
    session: Session = Depends(get_session),
):
    """Profil complet + notes agrégées + pistes actives (écart recalculé en direct)."""
    profile = _get_profile_or_404(session, uid)

    records = session.exec(
        select(AcademicRecord).where(AcademicRecord.student_profile_id == profile.id)
    ).all()
    grades = _aggregate_grades(list(records))
    current_avg = grades["latest"]["general_average"] if grades["latest"] else None

    tracks = session.exec(
        select(TargetTrack).where(TargetTrack.student_profile_id == profile.id)
    ).all()
    formations = _fetch_formations(session, [t.formation_id for t in tracks if t.formation_id])

    tracks_out = []
    for t in sorted(tracks, key=lambda x: x.type != "AMBITION"):  # AMBITION en premier
        f = formations.get(t.formation_id) if t.formation_id else None
        seuil = f["seuil_moyenne_estime"] if f else None
        tracks_out.append({
            "id": t.id,
            "type": t.type,
            "formation_id": t.formation_id,
            "referentiel_filiere_id": t.referentiel_filiere_id,
            "formation_name": t.formation_name,
            "requirements": t.requirements,
            "action_plan": t.action_plan,
            "estimated_gap_snapshot": t.estimated_gap,
            "gap_computed_at": t.gap_computed_at,
            # Écart déterministe recalculé à chaque lecture : moyenne actuelle - seuil estimé.
            "live_gap": round(current_avg - seuil, 2) if (current_avg is not None and seuil is not None) else None,
            "parcoursup": f,
        })

    plan = session.exec(
        select(WeeklyPlan)
        .where(WeeklyPlan.student_profile_id == profile.id)
        .order_by(WeeklyPlan.week_start.desc())
    ).first()
    checkpoints = session.exec(
        select(MonthlyCheckpoint)
        .where(MonthlyCheckpoint.student_profile_id == profile.id)
        .order_by(MonthlyCheckpoint.month.desc())
        .limit(6)
    ).all()

    return {
        "profile": _profile_dict(profile),
        "grades": grades,
        "target_tracks": tracks_out,
        "current_weekly_plan": plan.model_dump() if plan else None,
        "recent_checkpoints": [c.model_dump() for c in checkpoints],
    }
