# -*- coding: utf-8 -*-
"""
Service Métier Phase 3 : Bilan d'Orientation & Sélectivité, Double Trajectoire & Persistance TargetTrack
===========================================================================================

Implémente `run_student_diagnostic(user_id, db, target_domain)` en 4 étapes :
  - Étape A : Calcul déterministe SQL (zéro LLM) sur `AcademicRecord`, `v_voie_a_ambition` et `v_voie_b_secours`.
  - Étape B : Persistance transactionnelle dans `target_tracks` (AMBITION + REALISTE).
  - Étape C : Extraction du contexte RAG depuis `data/processed/rag_corpus/metiers_formations_chunks.jsonl`.
  - Étape D : Synthèse stratégique & déconstruction des mythes (LLM local + structuration Pydantic garantie).
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlmodel import Session, select

try:
    from database import unaccent_lower
    from models.student import AcademicRecord, StudentProfile, TargetTrack, TrackType
    from services.ai_engine import query_local_llm
except ImportError:
    from backend.database import unaccent_lower
    from backend.models.student import AcademicRecord, StudentProfile, TargetTrack, TrackType
    from backend.services.ai_engine import query_local_llm

ROOT_DIR = Path(__file__).resolve().parents[2]
FILIERES_REF_PATH = ROOT_DIR / "backend" / "data" / "filieres_selectives.json"
RAG_CHUNKS_PATH = ROOT_DIR / "data" / "processed" / "rag_corpus" / "metiers_formations_chunks.jsonl"


# ---------------------------------------------------------------------------
# SCHÉMAS PYDANTIC DE SORTIE (CONTRAT API STRICT)
# ---------------------------------------------------------------------------
class SubjectGapItem(BaseModel):
    subject: str
    student_grade: float
    expected_grade: float
    delta: float
    status: str  # "OK", "VIGILANCE", "CRITIQUE"


class TrackDiagnosticDetail(BaseModel):
    track_id: str
    type: TrackType
    formation_id: str
    referentiel_filiere_id: str
    formation_name: str
    etablissement: str
    ville: str
    filiere: str
    taux_acces_pct: float
    seuil_moyenne_estime: float
    estimated_gap: float
    selectivity_group: int = 2
    ranking_label: str = "Groupe 2 : Cibles Grandes Écoles Nationales"
    source_citation: str = "Source : Données MESR Open Data / Classement L'Étudiant"
    verdict_accessibilite: str
    requirements: List[str]
    subject_gaps: List[SubjectGapItem] = Field(default_factory=list)
    casseur_de_mythes: Dict[str, Any] = Field(default_factory=dict)


class PassionValorisationItem(BaseModel):
    passion_brute: str
    competence_academique: str
    competence_pro: str
    argument_parcoursup: str


class PriorityActionItem(BaseModel):
    ordre: int
    matiere_ou_axe: str
    objectif_chiffre: str
    action_concrete_hebdo: str
    duree_hebdo_recommandee: str


class RagChunkSummary(BaseModel):
    chunk_id: str
    doc_type: str
    titre: str
    extrait: str


class StrategicSynthesis(BaseModel):
    diagnostic_lucidite_gap: str
    conditions_non_negociables: List[str]
    analyse_exigences_terrain: str
    valorisation_passions: List[PassionValorisationItem]
    actions_prioritaires: List[PriorityActionItem]
    discours_coach_llm: str


class StudentDiagnosticSummary(BaseModel):
    user_id: str
    profile_id: str
    grade_level: str
    target_domain: str
    general_average: float
    specialties: List[str]
    interests: List[str]
    subjects_count: int


class DiagnosticRunResponse(BaseModel):
    success: bool = True
    computed_at: datetime
    resume_eleve: StudentDiagnosticSummary
    parcours_ambition: TrackDiagnosticDetail
    parcours_realiste: TrackDiagnosticDetail
    contexte_rag: List[RagChunkSummary]
    actions_prioritaires: List[PriorityActionItem]
    synthese_strategique: StrategicSynthesis


# ---------------------------------------------------------------------------
# MAPPING DOMAINE VISÉ -> MOTS-CLÉS SQL & RÉFÉRENTIEL STRATÉGIQUE
# ---------------------------------------------------------------------------
DOMAIN_PROFILES: List[Dict[str, Any]] = [
    {
        "label": "Ingénierie & Sciences",
        "keys": ["ing", "math", "physique", "info", "nsi", "cyber", "ia", "robot", "mpsi", "pcsi", "mp2i", "science", "tech"],
        "ambition_ref_id": "cpge_mpsi_pcsi",
        "realiste_ref_id": "but_info_geii",
        "ambition_sql_keywords": ["mpsi", "pcsi", "mp2i", "ingenieur", "cpge"],
        "realiste_sql_keywords": ["informatique", "electronique", "sciences", "technologie", "mathematiques", "physique"],
        "rag_keywords": ["cpge_mpsi_pcsi", "but_info_geii", "ingenieur", "robotique", "informatique"],
    },
    {
        "label": "Santé & Biologie",
        "keys": ["sante", "medecine", "pass", "las", "bio", "svt", "soin", "infirm", "pharma", "kine"],
        "ambition_ref_id": "pass_las_medecine",
        "realiste_ref_id": "but_genie_bio_ifsi",
        "ambition_sql_keywords": ["pass", "sante", "biomedical", "medecine", "bcpst"],
        "realiste_sql_keywords": ["biologie", "sante", "sciences de la vie", "chimie", "infirm"],
        "rag_keywords": ["pass_las_medecine", "but_genie_bio_ifsi", "medecin", "biologie", "sante"],
    },
    {
        "label": "Économie, Commerce & Management",
        "keys": ["commerce", "eco", "ses", "gestion", "finance", "marketing", "ecg", "management", "entreprise", "sneakers", "achat"],
        "ambition_ref_id": "cpge_ecg_commerce",
        "realiste_ref_id": "but_gea_eco_gestion",
        "ambition_sql_keywords": ["ecg", "commerce", "economie", "gestion", "management"],
        "realiste_sql_keywords": ["economie", "gestion", "administration", "commerce", "aes"],
        "rag_keywords": ["cpge_ecg_commerce", "but_gea_eco_gestion", "commerce", "finance", "marketing"],
    },
    {
        "label": "Droit, Sciences Po & Humanités",
        "keys": [
            "droit", "politique", "sciences po", "iep", "histoire", "hggsp", "geopolitique",
            "eloquence", "debat", "avocat", "francais", "lettres", "litterature", "litteraire",
            "philosophie", "hlp", "humanites", "llce", "geographie", "langues", "journalisme",
        ],
        "ambition_ref_id": "sciences_po_bl_droit",
        "realiste_ref_id": "licence_droit_but_cj",
        "ambition_sql_keywords": ["sciences po", "études politiques", "droit", "b/l", "ens", "lettres"],
        "realiste_sql_keywords": ["droit", "science politique", "histoire", "lettres"],
        "rag_keywords": ["sciences_po_bl_droit", "licence_droit_but_cj", "droit", "juriste", "journaliste"],
    },
    {
        "label": "Arts, Design & Architecture",
        "keys": ["archi", "design", "art", "crea", "graphisme", "3d", "manga", "dessin", "video", "cinema", "animation"],
        "ambition_ref_id": "ensa_archi_gobelins",
        "realiste_ref_id": "dnmade_but_mmi",
        "ambition_sql_keywords": ["art", "design", "architecture", "communication"],
        "realiste_sql_keywords": ["art", "design", "communication", "multimedia", "lettres"],
        "rag_keywords": ["ensa_archi_gobelins", "dnmade_but_mmi", "design", "architecte"],
    },
]


def _load_referentiel() -> Dict[str, Any]:
    if not FILIERES_REF_PATH.exists():
        return {"filieres": [], "decodeur_talents": {}, "matrice_specialites": {}}
    return json.loads(FILIERES_REF_PATH.read_text(encoding="utf-8"))


def _resolve_domain_profile(
    target_domain: Optional[str],
    specialties: List[str],
    interests: List[str],
    subject_grades: Optional[Dict[str, float]] = None,
) -> Dict[str, Any]:
    """Détermine de façon déterministe le profil de domaine à partir de la cible, des spécialités, des intérêts et des notes."""
    td_norm = unaccent_lower(target_domain or "")
    corpus = unaccent_lower(
        " ".join(
            [target_domain or ""]
            + list(specialties or [])
            + list(interests or [])
        )
    )
    best_profile = DOMAIN_PROFILES[0]
    best_score = 0
    for prof in DOMAIN_PROFILES:
        score = sum(3 if (td_norm and k in td_norm) else 1 for k in prof["keys"] if k in corpus)
        if score > best_score:
            best_score = score
            best_profile = prof

    # Si aucune spécialité ni cible explicite ne matche, déduire à partir des meilleures matières du bulletin
    if best_score == 0 and subject_grades:
        top_subjects = [
            k for k, _ in sorted(subject_grades.items(), key=lambda kv: kv[1], reverse=True)[:3]
        ]
        grades_corpus = unaccent_lower(" ".join(top_subjects))
        for prof in DOMAIN_PROFILES:
            score = sum(1 for k in prof["keys"] if k in grades_corpus)
            if score > best_score:
                best_score = score
                best_profile = prof

    return best_profile


# ---------------------------------------------------------------------------
# ÉTAPE A : CALCUL DÉTERMINISTE SQL (ZÉRO LLM)
# ---------------------------------------------------------------------------
def _compute_student_grades(db: Session, profile_id: str) -> Tuple[float, Dict[str, float]]:
    """
    Récupère les notes du dernier trimestre enregistré pour l'élève et calcule :
      - la moyenne générale exacte (/20)
      - le dictionnaire {matière: note}
    """
    records = db.exec(
        select(AcademicRecord).where(AcademicRecord.student_profile_id == profile_id)
    ).all()

    if not records:
        # Valeur neutre par défaut si l'élève n'a pas encore saisi de bulletin
        return 12.5, {}

    # Isoler le couple (school_year, trimester) le plus récent
    latest_year = max(r.school_year for r in records)
    year_records = [r for r in records if r.school_year == latest_year]
    latest_trimester = max(r.trimester for r in year_records)
    active_records = [r for r in year_records if r.trimester == latest_trimester]

    subject_grades: Dict[str, float] = {}
    for r in active_records:
        subject_grades[r.subject] = round(float(r.grade), 2)

    general_avg = round(sum(subject_grades.values()) / len(subject_grades), 2)
    return general_avg, subject_grades


def _select_formation_from_view(
    db: Session,
    view_name: str,
    keywords: List[str],
    moyenne_eleve: float,
    is_ambition: bool,
) -> Dict[str, Any]:
    """
    Interroge en SQL strict la vue `v_voie_a_ambition` ou `v_voie_b_secours`
    en utilisant `unaccent_lower()` pour trouver la formation la plus pertinente.
    """
    like_clauses = []
    params: Dict[str, Any] = {"moyenne": moyenne_eleve}
    for idx, kw in enumerate(keywords):
        pname = f"kw{idx}"
        params[pname] = f"%{unaccent_lower(kw)}%"
        like_clauses.append(
            f"(unaccent_lower(nom) LIKE :{pname} "
            f"OR unaccent_lower(filiere) LIKE :{pname} "
            f"OR unaccent_lower(filiere_detail) LIKE :{pname})"
        )

    where_domain = " OR ".join(like_clauses) if like_clauses else "1=1"

    if is_ambition:
        # Pour Voie A Ambition : on privilégie une formation sélective (Groupe 1 si moyenne >= 15.2, sinon Groupe 2/1)
        # dont le seuil est proche ou supérieur à la moyenne de l'élève (défi réaliste mais exigeant).
        sql = text(
            f"""
            SELECT
                formation_id, nom, etablissement, filiere, filiere_detail, ville,
                taux_acces, mention_tres_bien_pct, mention_bien_pct, bac_general_pct,
                seuil_moyenne_estime, capacite_accueil,
                selectivity_group, ranking_label, source_citation,
                ROUND(:moyenne - seuil_moyenne_estime, 2) AS estimated_gap
            FROM {view_name}
            WHERE ({where_domain})
            ORDER BY
                CASE
                    WHEN :moyenne >= 15.2 AND selectivity_group = 1 THEN 0
                    WHEN :moyenne < 15.2 AND selectivity_group = 2 THEN 0
                    ELSE 1
                END ASC,
                ABS(seuil_moyenne_estime - (:moyenne + 2.5)) ASC,
                seuil_moyenne_estime DESC
            LIMIT 1
            """
        )
    else:
        # Pour Voie B Secours : on privilégie une formation Groupe 3 à taux d'accès >= 45%
        # où la moyenne de l'élève offre une marge de sécurité positive ou très proche du seuil.
        sql = text(
            f"""
            SELECT
                formation_id, nom, etablissement, filiere, filiere_detail, ville,
                taux_acces, mention_bien_pct, mention_assez_bien_pct, bac_general_pct,
                seuil_moyenne_estime, capacite_accueil,
                selectivity_group, ranking_label, source_citation,
                ROUND(:moyenne - seuil_moyenne_estime, 2) AS estimated_gap
            FROM {view_name}
            WHERE ({where_domain})
            ORDER BY
                CASE WHEN seuil_moyenne_estime <= (:moyenne + 0.5) THEN 0 ELSE 1 END ASC,
                taux_acces DESC,
                seuil_moyenne_estime ASC
            LIMIT 1
            """
        )

    row = db.execute(sql, params).mappings().first()

    # Fallback SQL sur toute la vue si aucun mot-clé du domaine n'a matché dans l'échantillon
    if row is None:
        fallback_sql = text(
            f"""
            SELECT
                formation_id, nom, etablissement, filiere, filiere_detail, ville,
                taux_acces, bac_general_pct, seuil_moyenne_estime, capacite_accueil,
                selectivity_group, ranking_label, source_citation,
                ROUND(:moyenne - seuil_moyenne_estime, 2) AS estimated_gap
            FROM {view_name}
            ORDER BY {"seuil_moyenne_estime DESC" if is_ambition else "taux_acces DESC"}
            LIMIT 1
            """
        )
        row = db.execute(fallback_sql, {"moyenne": moyenne_eleve}).mappings().first()

    if row is None:
        raise RuntimeError(f"Aucune formation disponible dans la vue SQL {view_name}.")

    return dict(row)


def _compute_subject_gaps(
    subject_grades: Dict[str, float],
    expected_thresholds: Dict[str, float],
) -> List[SubjectGapItem]:
    """Compare matière par matière les notes de l'élève aux seuils attendus de la filière."""
    normalized_student: Dict[str, Tuple[str, float]] = {
        unaccent_lower(k): (k, v) for k, v in subject_grades.items()
    }
    gaps: List[SubjectGapItem] = []

    for exp_subj, exp_val in expected_thresholds.items():
        exp_norm = unaccent_lower(exp_subj)
        matched_grade: Optional[float] = None
        for stud_norm, (_, grade_val) in normalized_student.items():
            if exp_norm in stud_norm or stud_norm in exp_norm:
                matched_grade = grade_val
                break

        if matched_grade is None and subject_grades:
            matched_grade = round(sum(subject_grades.values()) / len(subject_grades), 2)
        elif matched_grade is None:
            matched_grade = 12.0

        delta = round(matched_grade - float(exp_val), 2)
        if delta >= 0:
            status = "OK"
        elif delta >= -1.5:
            status = "VIGILANCE"
        else:
            status = "CRITIQUE"

        gaps.append(
            SubjectGapItem(
                subject=exp_subj,
                student_grade=matched_grade,
                expected_grade=float(exp_val),
                delta=delta,
                status=status,
            )
        )

    # Trier des lacunes les plus critiques aux matières maîtrisées
    gaps.sort(key=lambda x: x.delta)
    return gaps


# ---------------------------------------------------------------------------
# ÉTAPE B : PERSISTANCE DANS TARGET_TRACK
# ---------------------------------------------------------------------------
def _upsert_target_track(
    db: Session,
    profile_id: str,
    track_type: TrackType,
    sql_row: Dict[str, Any],
    referentiel_filiere_id: str,
    requirements: List[str],
    action_plan: str,
    now: datetime,
) -> TargetTrack:
    existing = db.exec(
        select(TargetTrack).where(
            TargetTrack.student_profile_id == profile_id,
            TargetTrack.type == track_type,
        )
    ).first()

    if existing is None:
        existing = TargetTrack(
            student_profile_id=profile_id,
            type=track_type,
            formation_name=str(sql_row["nom"]),
        )

    existing.formation_id = str(sql_row["formation_id"])
    existing.referentiel_filiere_id = referentiel_filiere_id
    existing.formation_name = str(sql_row["nom"])
    existing.estimated_gap = float(sql_row["estimated_gap"])
    existing.gap_computed_at = now
    existing.requirements = list(requirements)
    existing.action_plan = action_plan
    existing.updated_at = now

    db.add(existing)
    db.flush()
    return existing


# ---------------------------------------------------------------------------
# ÉTAPE C : CONTEXTE RAG (CHUNKS MÉTIERS & ATTENDUS PARCOURSUP)
# ---------------------------------------------------------------------------
def _retrieve_rag_context(rag_keywords: List[str], limit: int = 4) -> List[RagChunkSummary]:
    if not RAG_CHUNKS_PATH.exists():
        return []

    scored_chunks: List[Tuple[int, Dict[str, Any]]] = []
    norm_keywords = [unaccent_lower(k) for k in rag_keywords if k]

    with RAG_CHUNKS_PATH.open("r", encoding="utf-8") as fp:
        for line in fp:
            if not line.strip():
                continue
            chunk = json.loads(line)
            haystack = unaccent_lower(
                f"{chunk.get('chunk_id', '')} {chunk.get('titre', '')} "
                f"{chunk.get('domaine', '')} {chunk.get('text_for_embedding', '')}"
            )
            score = sum(
                3 if kw in unaccent_lower(chunk.get("chunk_id", "")) else 1
                for kw in norm_keywords
                if kw in haystack
            )
            if score > 0:
                scored_chunks.append((score, chunk))

    scored_chunks.sort(key=lambda item: item[0], reverse=True)
    results: List[RagChunkSummary] = []
    for _, c in scored_chunks[:limit]:
        results.append(
            RagChunkSummary(
                chunk_id=str(c.get("chunk_id", "")),
                doc_type=str(c.get("doc_type", "")),
                titre=str(c.get("titre", "")),
                extrait=str(c.get("text_for_embedding", ""))[:320],
            )
        )
    return results


# ---------------------------------------------------------------------------
# ÉTAPE D : SYNTHÈSE STRATÉGIQUE, DÉCODAGE DES PASSIONS & ACTIONS PRIORITAIRES
# ---------------------------------------------------------------------------
def _decode_student_passions(
    interests: List[str],
    decodeur_ref: Dict[str, Any],
) -> List[PassionValorisationItem]:
    """Traduit les centres d'intérêt réels de l'élève en compétences valorisables (Skill 2)."""
    decoded: List[PassionValorisationItem] = []
    used_keys = set()

    for interest in interests:
        interest_norm = unaccent_lower(interest)
        matched_key = None
        for ref_key in decodeur_ref.keys():
            ref_tokens = [t for t in re.split(r"[\s/,()-]+", unaccent_lower(ref_key)) if len(t) >= 3]
            if interest_norm in unaccent_lower(ref_key) or any(t in interest_norm for t in ref_tokens):
                matched_key = ref_key
                break

        if matched_key and matched_key not in used_keys:
            used_keys.add(matched_key)
            info = decodeur_ref[matched_key]
            decoded.append(
                PassionValorisationItem(
                    passion_brute=interest,
                    competence_academique=str(info.get("competence_academique", "")),
                    competence_pro=str(info.get("competence_pro", "")),
                    argument_parcoursup=str(info.get("argument_parcoursup", "")),
                )
            )
        else:
            decoded.append(
                PassionValorisationItem(
                    passion_brute=interest,
                    competence_academique="Autonomie d'apprentissage, régularité et curiosité active",
                    competence_pro="Persévérance, capacité d'adaptation et investissement personnel",
                    argument_parcoursup=(
                        f"« Ma pratique régulière de {interest} m'a appris la discipline personnelle, "
                        "la recherche de progression constante et l'ouverture d'esprit. »"
                    ),
                )
            )
    return decoded


def _build_priority_actions(
    subject_gaps: List[SubjectGapItem],
    ambition_name: str,
    specialties: List[str],
) -> List[PriorityActionItem]:
    """Génère 3 actions hebdomadaires concrètes et chiffrées ciblant les lacunes prioritaires."""
    actions: List[PriorityActionItem] = []

    for idx, gap in enumerate(subject_gaps[:2], start=1):
        if gap.delta < 0:
            gain_cible = round(min(2.5, abs(gap.delta)), 1)
            cible_note = round(min(20.0, gap.student_grade + gain_cible), 1)
            actions.append(
                PriorityActionItem(
                    ordre=idx,
                    matiere_ou_axe=gap.subject,
                    objectif_chiffre=(
                        f"Passer de {gap.student_grade}/20 à {cible_note}/20 "
                        f"(seuil attendu : {gap.expected_grade}/20, écart actuel : {gap.delta:+.2f} pt)"
                    ),
                    action_concrete_hebdo=(
                        f"2 créneaux de 45 min d'exercices types corrigés en {gap.subject} "
                        "en refaisant systématiquement chaque question ratée au dernier DS sans regarder le cours."
                    ),
                    duree_hebdo_recommandee="1h30 / semaine",
                )
            )
        else:
            actions.append(
                PriorityActionItem(
                    ordre=idx,
                    matiere_ou_axe=gap.subject,
                    objectif_chiffre=f"Verrouiller {gap.student_grade}/20 (au-dessus du seuil de {gap.expected_grade}/20)",
                    action_concrete_hebdo=(
                        f"1 séance de 45 min d'approfondissement (sujets de niveau supérieur / annales) en {gap.subject}."
                    ),
                    duree_hebdo_recommandee="45 min / semaine",
                )
            )

    # 3ème action : consolidation stratégique du dossier Parcoursup / méthode
    spe_str = ", ".join(specialties) if specialties else "spécialités scientifiques/majeures"
    actions.append(
        PriorityActionItem(
            ordre=len(actions) + 1,
            matiere_ou_axe="Méthode & Dossier Parcoursup",
            objectif_chiffre=f"Sécuriser les appréciations de {spe_str} pour {ambition_name[:45]}",
            action_concrete_hebdo=(
                "Préparer chaque fin de semaine une fiche d'erreurs-types sur les contrôles rendus "
                "et participer activement à l'oral en cours pour renforcer les appréciations du bulletin."
            ),
            duree_hebdo_recommandee="45 min / semaine",
        )
    )

    return actions[:3]


def _generate_coach_synthesis(
    moyenne_eleve: float,
    ambition_row: Dict[str, Any],
    realiste_row: Dict[str, Any],
    ambition_ref: Dict[str, Any],
    subject_gaps: List[SubjectGapItem],
    passions_decoded: List[PassionValorisationItem],
    actions: List[PriorityActionItem],
    rag_chunks: List[RagChunkSummary],
) -> StrategicSynthesis:
    gap_amb = float(ambition_row["estimated_gap"])
    seuil_amb = float(ambition_row["seuil_moyenne_estime"])
    taux_amb = float(ambition_row["taux_acces"])

    if gap_amb < -1.5:
        lucidite = (
            f"Bilan chiffré : avec {moyenne_eleve}/20 de moyenne actuelle face à un seuil estimé de "
            f"{seuil_amb}/20 pour « {ambition_row['nom']} » (taux d'accès {taux_amb}%), ton écart est de "
            f"{gap_amb:+.2f} points. Aujourd'hui, ce vœu d'Ambition serait refusé au premier tri algorithmique "
            f"si tu maintiens ce rythme. La bonne nouvelle : ce retard est rattrapable à condition de traiter "
            f"immédiatement tes matières déficitaires tout en sécurisant ton Plan B (« {realiste_row['nom']} », "
            f"taux d'accès {realiste_row['taux_acces']}%)."
        )
    elif gap_amb < 0:
        lucidite = (
            f"Tu es en zone de tangence : {moyenne_eleve}/20 contre un seuil estimé de {seuil_amb}/20 "
            f"(écart : {gap_amb:+.2f} pt) sur « {ambition_row['nom']} ». Le dossier est jouable mais "
            f"dépendra de ta progression sur les prochains bulletins et de la solidité de tes spécialités."
        )
    else:
        lucidite = (
            f"Position favorable : ta moyenne de {moyenne_eleve}/20 dépasse le seuil estimé de {seuil_amb}/20 "
            f"({gap_amb:+.2f} pt) pour « {ambition_row['nom']} ». L'enjeu est de maintenir cette régularité "
            f"sans relâchement."
        )

    casseur = ambition_ref.get("casseur_de_mythes") or {}
    if isinstance(casseur, dict) and casseur.get("mythe"):
        mythe_str = (
            f"Mythe : {casseur.get('mythe')} — "
            f"Réalité du terrain : {casseur.get('realite_terrain', '')} "
            f"({casseur.get('conseil_survie', '')})"
        ).strip()
    else:
        mythe_str = (
            "Idée reçue : « Tout se joue uniquement au dernier trimestre de Terminale. » — "
            "Réalité : Les commissions Parcoursup examinent la trajectoire complète depuis la Première "
            "et valorisent avant tout une courbe de progression ascendante."
        )

    conditions = list(ambition_ref.get("conditions_acces") or [
        f"Atteindre au moins {seuil_amb}/20 de moyenne générale sur les prochains bulletins",
        "Soigner les appréciations des professeurs dans les spécialités majeures",
    ])

    # Prompt système strict pour le LLM local (ton préparateur de haut niveau)
    system_prompt = (
        "Tu es un préparateur stratégique d'orientation de haut niveau pour lycéens. "
        "Ton ton est lucide, exigeant, bienveillant et orienté exécution quotidienne (zéro complaisance, zéro jargon). "
        "En 4 phrases percutantes maximum : "
        "1) Analyse avec rigueur l'écart chiffré vers la voie Ambition, "
        "2) Valorise une passion réelle de l'élève comme force transférable, "
        "3) Donne le cap d'action immédiat de la semaine."
    )
    rag_brief = " | ".join(f"{c.titre}: {c.extrait[:110]}" for c in rag_chunks[:2])
    passions_brief = ", ".join(p.passion_brute for p in passions_decoded) or "aucune passion renseignée"
    gaps_brief = ", ".join(f"{g.subject} ({g.student_grade}/20 vs {g.expected_grade}/20)" for g in subject_gaps[:3])

    user_prompt = (
        f"Élève avec {moyenne_eleve}/20 de moyenne. "
        f"Voie Ambition : {ambition_row['nom']} (seuil {seuil_amb}/20, gap {gap_amb:+.2f} pts). "
        f"Plan B sécurisé : {realiste_row['nom']} (taux d'accès {realiste_row['taux_acces']}%). "
        f"Écarts par matière : {gaps_brief}. "
        f"Passions : {passions_brief}. "
        f"Contexte officiel RAG : {rag_brief}. "
        "Rédige la synthèse directe du coach."
    )

    import concurrent.futures

    llm_text = ""
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
    try:
        future = executor.submit(query_local_llm, user_prompt, system_prompt)
        llm_text = future.result(timeout=2.0)
    except Exception:
        llm_text = ""
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    if not llm_text or llm_text.startswith("Erreur"):
        passion_highlight = (
            f"Ta pratique de « {passions_decoded[0].passion_brute} » prouve ta capacité en "
            f"{passions_decoded[0].competence_academique.lower()} : applique cette même discipline à tes matières clés."
            if passions_decoded
            else "La régularité hebdomadaire fera toute la différence devant les jurys."
        )
        llm_text = (
            f"{lucidite} {passion_highlight} "
            f"Priorité dès cette semaine : {actions[0].action_concrete_hebdo}"
        )

    return StrategicSynthesis(
        diagnostic_lucidite_gap=lucidite,
        conditions_non_negociables=conditions,
        analyse_exigences_terrain=mythe_str,
        valorisation_passions=passions_decoded,
        actions_prioritaires=actions,
        discours_coach_llm=llm_text,
    )


# ---------------------------------------------------------------------------
# POINT D'ENTRÉE PRINCIPAL : run_student_diagnostic
# ---------------------------------------------------------------------------
def run_student_diagnostic(
    user_id: str,
    db: Session,
    target_domain: Optional[str] = None,
) -> DiagnosticRunResponse:
    """
    Exécute le diagnostic complet (SQL déterministe + Persistance TargetTrack + RAG + Synthèse LLM).
    """
    profile = db.exec(select(StudentProfile).where(StudentProfile.user_id == user_id)).first()
    if profile is None:
        raise ValueError(
            f"Profil introuvable pour user_id='{user_id}'. Créez d'abord le profil via POST /api/profile."
        )

    raw_domain = (target_domain or profile.target_domain or "").strip()

    # 1. Étape A : Calcul SQL déterministe (moyenne élève, sélection Voie A & Voie B, calcul du gap)
    moyenne_eleve, subject_grades = _compute_student_grades(db, profile.id)
    domain_cfg = _resolve_domain_profile(raw_domain, profile.specialties, profile.interests, subject_grades)
    effective_domain = raw_domain or domain_cfg.get("label", "Orientation Générale")
    if target_domain and target_domain.strip() != profile.target_domain:
        profile.target_domain = effective_domain
        profile.updated_at = datetime.now(timezone.utc)
        db.add(profile)

    referentiel = _load_referentiel()
    filieres_by_id = {f["id"]: f for f in referentiel.get("filieres", [])}
    ambition_ref = filieres_by_id.get(domain_cfg["ambition_ref_id"], {})
    realiste_ref = filieres_by_id.get(domain_cfg["realiste_ref_id"], {})

    ambition_row = _select_formation_from_view(
        db=db,
        view_name="v_voie_a_ambition",
        keywords=domain_cfg["ambition_sql_keywords"],
        moyenne_eleve=moyenne_eleve,
        is_ambition=True,
    )
    realiste_row = _select_formation_from_view(
        db=db,
        view_name="v_voie_b_secours",
        keywords=domain_cfg["realiste_sql_keywords"],
        moyenne_eleve=moyenne_eleve,
        is_ambition=False,
    )

    subject_gaps_ambition = _compute_subject_gaps(
        subject_grades=subject_grades,
        expected_thresholds=ambition_ref.get("seuils_matieres") or {"Mathématiques": 15.5, "Physique-Chimie": 15.0},
    )
    subject_gaps_realiste = _compute_subject_gaps(
        subject_grades=subject_grades,
        expected_thresholds=realiste_ref.get("seuils_matieres") or {"Mathématiques": 12.5, "Physique-Chimie": 12.0},
    )

    # 2. Étape C : Contexte RAG (extrait avant l'étape D pour alimenter la synthèse et le plan d'action)
    rag_chunks = _retrieve_rag_context(domain_cfg["rag_keywords"], limit=4)

    # 3. Étape D : Décodage des passions, actions prioritaires et synthèse du coach
    passions_decoded = _decode_student_passions(
        interests=profile.interests or [],
        decodeur_ref=referentiel.get("decodeur_talents") or {},
    )
    priority_actions = _build_priority_actions(
        subject_gaps=subject_gaps_ambition,
        ambition_name=str(ambition_row["nom"]),
        specialties=profile.specialties or [],
    )
    action_plan_summary = " | ".join(
        f"[{a.ordre}] {a.matiere_ou_axe}: {a.objectif_chiffre} ({a.duree_hebdo_recommandee})"
        for a in priority_actions
    )

    ambition_reqs = list(ambition_ref.get("conditions_acces") or [
        f"Seuil estimé : {ambition_row['seuil_moyenne_estime']}/20",
        f"Spécialités recommandées : {', '.join(ambition_ref.get('specialites_requises', []))}",
    ])
    realiste_reqs = list(realiste_ref.get("conditions_acces") or [
        f"Seuil estimé : {realiste_row['seuil_moyenne_estime']}/20 (Taux d'accès : {realiste_row['taux_acces']}%)",
        "Passerelle active vers les écoles et masters sélectifs après Bac+2/Bac+3",
    ])

    # 4. Étape B : Persistance transactionnelle dans `target_tracks`
    now = datetime.now(timezone.utc)
    track_ambition = _upsert_target_track(
        db=db,
        profile_id=profile.id,
        track_type=TrackType.AMBITION,
        sql_row=ambition_row,
        referentiel_filiere_id=domain_cfg["ambition_ref_id"],
        requirements=ambition_reqs,
        action_plan=action_plan_summary,
        now=now,
    )
    track_realiste = _upsert_target_track(
        db=db,
        profile_id=profile.id,
        track_type=TrackType.REALISTE,
        sql_row=realiste_row,
        referentiel_filiere_id=domain_cfg["realiste_ref_id"],
        requirements=realiste_reqs,
        action_plan="Sécuriser un dossier solide (>12,5/20) et viser le top 15% de promotion pour activer les passerelles.",
        now=now,
    )
    db.commit()
    db.refresh(track_ambition)
    db.refresh(track_realiste)

    synthese = _generate_coach_synthesis(
        moyenne_eleve=moyenne_eleve,
        ambition_row=ambition_row,
        realiste_row=realiste_row,
        ambition_ref=ambition_ref,
        subject_gaps=subject_gaps_ambition,
        passions_decoded=passions_decoded,
        actions=priority_actions,
        rag_chunks=rag_chunks,
    )

    gap_amb = float(ambition_row["estimated_gap"])
    verdict_amb = (
        "Objectif atteignable avec plan de remédiation intensif"
        if gap_amb < 0
        else "Profil en ligne avec les attendus sélectifs"
    )
    gap_rea = float(realiste_row["estimated_gap"])
    verdict_rea = (
        "Voie sécurisée (marge positive)"
        if gap_rea >= 0
        else "Voie réaliste accessible à consolider"
    )

    return DiagnosticRunResponse(
        success=True,
        computed_at=now,
        resume_eleve=StudentDiagnosticSummary(
            user_id=profile.user_id,
            profile_id=profile.id,
            grade_level=str(profile.grade_level.value if hasattr(profile.grade_level, "value") else profile.grade_level),
            target_domain=effective_domain,
            general_average=moyenne_eleve,
            specialties=list(profile.specialties or []),
            interests=list(profile.interests or []),
            subjects_count=len(subject_grades),
        ),
        parcours_ambition=TrackDiagnosticDetail(
            track_id=track_ambition.id,
            type=TrackType.AMBITION,
            formation_id=str(ambition_row["formation_id"]),
            referentiel_filiere_id=domain_cfg["ambition_ref_id"],
            formation_name=str(ambition_row["nom"]),
            etablissement=str(ambition_row.get("etablissement") or ""),
            ville=str(ambition_row.get("ville") or ""),
            filiere=str(ambition_row.get("filiere") or ""),
            taux_acces_pct=float(ambition_row["taux_acces"]),
            seuil_moyenne_estime=float(ambition_row["seuil_moyenne_estime"]),
            estimated_gap=gap_amb,
            selectivity_group=int(ambition_row.get("selectivity_group") or 2),
            ranking_label=str(
                ambition_row.get("ranking_label")
                or "Groupe 2 : Cibles Grandes Écoles Nationales"
            ),
            source_citation=str(
                ambition_row.get("source_citation")
                or "Source : Données MESR Open Data / Classement L'Étudiant"
            ),
            verdict_accessibilite=verdict_amb,
            requirements=ambition_reqs,
            subject_gaps=subject_gaps_ambition,
            casseur_de_mythes=ambition_ref.get("casseur_de_mythes") or {},
        ),
        parcours_realiste=TrackDiagnosticDetail(
            track_id=track_realiste.id,
            type=TrackType.REALISTE,
            formation_id=str(realiste_row["formation_id"]),
            referentiel_filiere_id=domain_cfg["realiste_ref_id"],
            formation_name=str(realiste_row["nom"]),
            etablissement=str(realiste_row.get("etablissement") or ""),
            ville=str(realiste_row.get("ville") or ""),
            filiere=str(realiste_row.get("filiere") or ""),
            taux_acces_pct=float(realiste_row["taux_acces"]),
            seuil_moyenne_estime=float(realiste_row["seuil_moyenne_estime"]),
            estimated_gap=gap_rea,
            selectivity_group=int(realiste_row.get("selectivity_group") or 3),
            ranking_label=str(
                realiste_row.get("ranking_label")
                or "Groupe 3 : Concours Communs & Réseau Régional"
            ),
            source_citation=str(
                realiste_row.get("source_citation")
                or "Source : Données MESR Open Data / Classement L'Étudiant"
            ),
            verdict_accessibilite=verdict_rea,
            requirements=realiste_reqs,
            subject_gaps=subject_gaps_realiste,
            casseur_de_mythes=realiste_ref.get("casseur_de_mythes") or {},
        ),
        contexte_rag=rag_chunks,
        actions_prioritaires=priority_actions,
        synthese_strategique=synthese,
    )
