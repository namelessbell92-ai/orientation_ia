#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
Test d'intégration autonome — Phase 3 : Diagnostic, Double Trajectoire & Persistance TargetTrack
================================================================================================

Usage :
  .\backend\venv\Scripts\python.exe -W ignore backend/tests/smoke_diagnostic.py
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from fastapi.testclient import TestClient  # noqa: E402
from sqlmodel import Session, select  # noqa: E402

from backend.database import SQLITE_DB_PATH, engine  # noqa: E402
from backend.main import app  # noqa: E402
from backend.models.student import StudentProfile  # noqa: E402

UID = "smoke-test-diagnostic-premiere-uid"
HEADERS = {"X-User-Id": UID}


def check(cond: bool, label: str) -> None:
    print(f"  {'OK ' if cond else 'ÉCHEC'} {label}")
    if not cond:
        raise SystemExit(1)


def cleanup_test_user() -> None:
    with Session(engine) as s:
        existing = s.exec(select(StudentProfile).where(StudentProfile.user_id == UID)).first()
        if existing:
            s.delete(existing)
            s.commit()


def main() -> None:
    print("=" * 78)
    print("SMOKE TEST PHASE 3 : POST /api/diagnostic/run & PERSISTANCE TARGET_TRACK")
    print("=" * 78)

    with TestClient(app) as client:
        cleanup_test_user()

        # 1. Création du profil élève de Première visant l'ingénierie avec 13.2/20 de moyenne en sciences
        print("\n[1/4] Création du profil de test (Première, 13.2/20 en sciences, cible Ingénierie)...")
        r_prof = client.post(
            "/api/profile",
            headers=HEADERS,
            json={
                "grade_level": "PREMIERE",
                "target_domain": "Ingénierie & Sciences dures",
                "interests": ["Gaming compétitif", "Programmation", "Sport en club"],
                "specialties": ["Mathématiques", "Physique-Chimie", "NSI"],
                "riasec_scores": {"I": 8.5, "R": 7.5, "C": 6.5},
            },
        )
        check(r_prof.status_code == 200, f"POST /api/profile -> HTTP {r_prof.status_code}")

        # Notes en sciences donnant exactement 13.20/20 de moyenne générale : (12.8 + 13.2 + 13.6) / 3 = 13.2
        r_grades = client.post(
            "/api/profile/grades",
            headers=HEADERS,
            json={
                "school_year": "2026-2027",
                "trimester": 1,
                "grades": [
                    {"subject": "Mathématiques", "grade": 12.8, "class_average": 11.5},
                    {"subject": "Physique-Chimie", "grade": 13.2, "class_average": 11.8},
                    {"subject": "NSI", "grade": 13.6, "class_average": 12.4},
                ],
            },
        )
        check(
            r_grades.status_code == 200 and r_grades.json()["general_average"] == 13.2,
            f"POST /api/profile/grades -> moyenne générale = {r_grades.json().get('general_average')}/20",
        )

        # 2. Exécution de POST /api/diagnostic/run
        print("\n[2/4] Exécution de POST /api/diagnostic/run...")
        r_diag = client.post(
            "/api/diagnostic/run",
            headers=HEADERS,
            json={"target_domain": "Ingénierie"},
        )
        check(r_diag.status_code == 200, f"POST /api/diagnostic/run -> HTTP {r_diag.status_code}")
        data = r_diag.json()

        # 3. Vérification de la réponse JSON (les 2 parcours, leurs ID de formation, leurs deltas et les 3 actions)
        print("\n[3/4] Vérification du contrat JSON de sortie...")
        resume = data["resume_eleve"]
        amb = data["parcours_ambition"]
        rea = data["parcours_realiste"]
        rag = data["contexte_rag"]
        actions = data["actions_prioritaires"]
        synth = data["synthese_strategique"]

        check(resume["general_average"] == 13.2, f"Moyenne élève restituée = {resume['general_average']}/20")
        check(
            amb["type"] == "AMBITION" and bool(amb["formation_id"]) and amb["estimated_gap"] is not None,
            f"Parcours AMBITION : [{amb['formation_id']}] {amb['formation_name'][:52]} "
            f"(Seuil: {amb['seuil_moyenne_estime']}/20 | Gap: {amb['estimated_gap']:+.2f} pts)",
        )
        check(
            rea["type"] == "REALISTE" and bool(rea["formation_id"]) and rea["estimated_gap"] is not None,
            f"Parcours REALISTE : [{rea['formation_id']}] {rea['formation_name'][:52]} "
            f"(Taux accès: {rea['taux_acces_pct']}% | Seuil: {rea['seuil_moyenne_estime']}/20 | Gap: {rea['estimated_gap']:+.2f} pts)",
        )
        check(len(rag) >= 1, f"Contexte RAG extrait ({len(rag)} chunks : {[c['chunk_id'] for c in rag]})")
        check(len(actions) == 3, f"3 actions prioritaires générées ({[a['matiere_ou_axe'] for a in actions]})")
        check(
            len(synth["valorisation_passions"]) == 3 and bool(synth["discours_coach_llm"]),
            f"Synthèse stratégique et passions décodées ({len(synth['valorisation_passions'])} passions)",
        )

        # 4. Vérification directe en base SQLite dans la table `target_tracks` + test d'idempotence (mise à jour)
        print("\n[4/4] Vérification en base SQLite (table `target_tracks`) et test de mise à jour...")
        profile_id = resume["profile_id"]
        with sqlite3.connect(SQLITE_DB_PATH) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT type, formation_id, formation_name, estimated_gap, gap_computed_at "
                "FROM target_tracks WHERE student_profile_id = ? ORDER BY type",
                (profile_id,),
            ).fetchall()

        check(len(rows) == 2, f"2 enregistrements présents dans `target_tracks` pour le profil {profile_id}")
        by_type = {r["type"]: dict(r) for r in rows}
        check(
            "AMBITION" in by_type and by_type["AMBITION"]["formation_id"] == amb["formation_id"],
            f"SQLite AMBITION : formation_id={by_type['AMBITION']['formation_id']}, gap={by_type['AMBITION']['estimated_gap']}",
        )
        check(
            "REALISTE" in by_type and by_type["REALISTE"]["formation_id"] == rea["formation_id"],
            f"SQLite REALISTE : formation_id={by_type['REALISTE']['formation_id']}, gap={by_type['REALISTE']['estimated_gap']}",
        )

        # Relancer avec un changement de domaine ("Commerce") pour vérifier l'upsert sans doublon
        r_diag2 = client.post(
            "/api/diagnostic/run",
            headers=HEADERS,
            json={"target_domain": "Commerce"},
        )
        check(r_diag2.status_code == 200, "2e appel POST /api/diagnostic/run (changement vers Commerce) -> HTTP 200")
        with sqlite3.connect(SQLITE_DB_PATH) as conn:
            count_after = conn.execute(
                "SELECT COUNT(*) FROM target_tracks WHERE student_profile_id = ?",
                (profile_id,),
            ).fetchone()[0]
        check(count_after == 2, f"Upsert vérifié : toujours exactement {count_after} pistes dans `target_tracks`")

        # Nettoyage final du profil de test
        cleanup_test_user()

    print("\n" + "=" * 78)
    print("SUCCÈS TOTAL : TOUS LES TESTS DU DIAGNOSTIC PHASE 3 SONT VALIDÉS.")
    print("=" * 78)


if __name__ == "__main__":
    main()
