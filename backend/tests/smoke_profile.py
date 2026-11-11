r"""
Test d'intégration rapide du profil élève (SQLModel + SQLite réelle).

Usage (depuis la racine du projet) :
  .\backend\venv\Scripts\python.exe backend/tests/smoke_profile.py

Le test utilise un UID dédié et supprime son profil à la fin (vérifie au passage le ON DELETE CASCADE).
"""

import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.exc import IntegrityError  # noqa: E402
from sqlmodel import Session, select  # noqa: E402

from backend.database import SQLITE_DB_PATH, engine  # noqa: E402
from backend.main import app  # noqa: E402
from backend.models.student import StudentProfile, TargetTrack, TrackType  # noqa: E402

UID = "smoke-test-firebase-uid"
H = {"X-User-Id": UID}


def count(table: str) -> int:
    with sqlite3.connect(SQLITE_DB_PATH) as c:
        return c.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


def check(cond: bool, label: str) -> None:
    print(f"  {'OK ' if cond else 'ÉCHEC'} {label}")
    if not cond:
        raise SystemExit(1)


def main() -> None:
    open_data_before = {t: count(t) for t in ("parcoursup_formations", "onisep_metiers", "lycees_ival")}

    with TestClient(app) as client:  # déclenche le startup -> init_db()
        # Nettoyage d'un éventuel run précédent
        with Session(engine) as s:
            old = s.exec(select(StudentProfile).where(StudentProfile.user_id == UID)).first()
            if old:
                s.delete(old)
                s.commit()

        print("1. Tables")
        with sqlite3.connect(SQLITE_DB_PATH) as c:
            tables = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        for t in ("student_profiles", "academic_records", "target_tracks", "weekly_plans", "monthly_checkpoints"):
            check(t in tables, f"table {t} présente")

        print("2. POST /api/profile")
        r = client.post("/api/profile", headers=H, json={
            "grade_level": "PREMIERE",
            "target_domain": "Ingénierie & Sciences dures",
            "interests": ["gaming", "manga", "Gaming", " musculation "],
            "specialties": ["Mathématiques", "Physique-Chimie", "NSI"],
            "riasec_scores": {"i": 8.5, "R": 7, "C": 6},
        })
        check(r.status_code == 200 and r.json()["created"], f"création ({r.status_code})")
        check(r.json()["profile"]["interests"] == ["gaming", "manga", "musculation"], "intérêts dédoublonnés")
        r = client.post("/api/profile", headers=H, json={"grade_level": "PREMIERE", "interests": ["gaming", "musique"]})
        p = r.json()["profile"]
        check(not r.json()["created"] and p["specialties"] == ["Mathématiques", "Physique-Chimie", "NSI"],
              "mise à jour partielle sans écraser les spécialités")
        r = client.post("/api/profile", headers=H, json={"grade_level": "PREMIERE", "specialties": ["A", "B", "C", "D"]})
        check(r.status_code == 422, "4 spécialités refusées (422)")

        print("3. POST /api/profile/grades")
        r = client.post("/api/profile/grades", headers=H, json={
            "school_year": "2026-2027", "trimester": 1,
            "grades": [
                {"subject": "Mathématiques", "grade": 14.5, "class_average": 11.2},
                {"subject": "Physique-Chimie", "grade": 13.0, "class_average": 10.8},
                {"subject": "NSI", "grade": 16.0},
            ],
        })
        check(r.status_code == 200 and r.json()["inserted"] == 3, f"3 notes insérées, moyenne {r.json().get('general_average')}")
        r = client.post("/api/profile/grades", headers=H, json={
            "school_year": "2026-2027", "trimester": 1,
            "grades": [{"subject": "mathématiques", "grade": 15.5}],
        })
        check(r.json()["updated"] == 1 and r.json()["inserted"] == 0, "upsert : même matière mise à jour (insensible à la casse)")
        r = client.post("/api/profile/grades", headers=H, json={"trimester": 4, "grades": [{"subject": "X", "grade": 10}]})
        check(r.status_code == 422, "trimestre 4 refusé (422)")
        r = client.post("/api/profile/grades", headers=H, json={"trimester": 1, "grades": [{"subject": "X", "grade": 21}]})
        check(r.status_code == 422, "note 21/20 refusée (422)")

        print("4. TargetTrack : FK Parcoursup + unicité (profil, type)")
        with sqlite3.connect(SQLITE_DB_PATH) as c:
            fid = c.execute(
                "SELECT formation_id FROM parcoursup_formations ORDER BY seuil_moyenne_estime DESC LIMIT 1"
            ).fetchone()[0]
        with Session(engine) as s:
            prof = s.exec(select(StudentProfile).where(StudentProfile.user_id == UID)).one()
            s.add(TargetTrack(student_profile_id=prof.id, type=TrackType.AMBITION, formation_id=fid,
                              formation_name="Voie A (test)", requirements=["Maintien 16+ en Maths"]))
            s.commit()
            check(True, f"piste AMBITION liée à formation_id={fid}")

            s.add(TargetTrack(student_profile_id=prof.id, type=TrackType.AMBITION, formation_name="Doublon"))
            try:
                s.commit()
                check(False, "2e piste AMBITION refusée")
            except IntegrityError:
                s.rollback()
                check(True, "2e piste AMBITION refusée (UNIQUE)")

            s.add(TargetTrack(student_profile_id=prof.id, type=TrackType.REALISTE,
                              formation_id="FORMATION_INEXISTANTE", formation_name="FK cassée"))
            try:
                s.commit()
                check(False, "formation_id inexistant refusé")
            except IntegrityError:
                s.rollback()
                check(True, "formation_id inexistant refusé (FOREIGN KEY)")

        print("5. GET /api/profile/me")
        r = client.get("/api/profile/me", headers=H)
        body = r.json()
        latest = body["grades"]["latest"]
        track = body["target_tracks"][0]
        check(r.status_code == 200, "200")
        check(latest == {"school_year": "2026-2027", "trimester": 1, "general_average": 14.83}, f"moyenne agrégée {latest}")
        check(track["parcoursup"] is not None and track["live_gap"] is not None,
              f"écart recalculé : {latest['general_average']} - {track['parcoursup']['seuil_moyenne_estime']} = {track['live_gap']}")
        check(client.get("/api/profile/me").status_code == 422, "sans X-User-Id refusé")

        print("6. Suppression + CASCADE")
        with Session(engine) as s:
            prof = s.exec(select(StudentProfile).where(StudentProfile.user_id == UID)).one()
            pid = prof.id
            s.delete(prof)
            s.commit()
        with sqlite3.connect(SQLITE_DB_PATH) as c:
            left = sum(c.execute(f"SELECT COUNT(*) FROM {t} WHERE student_profile_id=?", (pid,)).fetchone()[0]
                       for t in ("academic_records", "target_tracks"))
        check(left == 0, "notes et pistes supprimées en cascade")

    open_data_after = {t: count(t) for t in open_data_before}
    print("7. Données Open Data intactes")
    check(open_data_before == open_data_after, f"{open_data_after}")
    print("\nTous les tests sont passés.")


if __name__ == "__main__":
    main()
