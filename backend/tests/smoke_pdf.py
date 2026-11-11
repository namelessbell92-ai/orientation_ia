#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
Test d'intégration autonome — Skill 12 : Export Fiche Stratégique PDF (1 Page A4)
=================================================================================

Usage :
  .\backend\venv\Scripts\python.exe -W ignore backend/tests/smoke_pdf.py
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import pypdf  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlmodel import Session, select  # noqa: E402

from backend.database import engine  # noqa: E402
from backend.main import app  # noqa: E402
from backend.models.student import StudentProfile  # noqa: E402

UID = "smoke-test-diagnostic-premiere-uid"
HEADERS = {"X-User-Id": UID}
OUTPUT_PDF_PATH = ROOT / "data" / "processed" / "test_fiche_orientation.pdf"


def check(cond: bool, label: str) -> None:
    print(f"  {'OK ' if cond else 'ÉCHEC'} {label}")
    if not cond:
        raise SystemExit(1)


def ensure_test_profile(client: TestClient) -> None:
    """
    Récupère le profil créé par `smoke_diagnostic.py` ou le (re)crée s'il a été nettoyé,
    avec les mêmes paramètres : Première Générale, 13.2/20 en sciences, cible Ingénierie.
    """
    with Session(engine) as s:
        prof = s.exec(select(StudentProfile).where(StudentProfile.user_id == UID)).first()

    if prof is None:
        client.post(
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
        client.post(
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


def main() -> None:
    print("=" * 78)
    print("SMOKE TEST SKILL 12 : GET /api/diagnostic/export-pdf (FICHE A4 1 PAGE)")
    print("=" * 78)

    with TestClient(app) as client:
        # 1. Récupération / préparation du profil de test
        print("\n[1/4] Récupération du profil de test (Première, 13.2/20 en sciences, Ingénierie)...")
        ensure_test_profile(client)
        r_me = client.get("/api/profile/me", headers=HEADERS)
        check(r_me.status_code == 200, f"Profil actif récupéré (UID={UID})")

        # 2. Appel de la route GET /api/diagnostic/export-pdf
        print("\n[2/4] Appel de GET /api/diagnostic/export-pdf...")
        r_pdf = client.get(
            "/api/diagnostic/export-pdf",
            headers=HEADERS,
            params={"target_domain": "Ingénierie"},
        )
        check(r_pdf.status_code == 200, f"GET /api/diagnostic/export-pdf -> HTTP {r_pdf.status_code}")
        check(
            r_pdf.headers.get("content-type") == "application/pdf",
            f"Content-Type = {r_pdf.headers.get('content-type')}",
        )
        check(
            'filename="fiche_orientation.pdf"' in (r_pdf.headers.get("content-disposition") or ""),
            f"Content-Disposition = {r_pdf.headers.get('content-disposition')}",
        )

        # 3. Vérification de la taille (> 5 Ko) et du nombre strict de pages (1 page A4)
        print("\n[3/4] Vérification du binaire PDF (taille > 5 Ko, 1 page A4 stricte, texte valide)...")
        pdf_bytes = r_pdf.content
        size_kb = round(len(pdf_bytes) / 1024, 2)
        check(len(pdf_bytes) > 5120, f"Taille du PDF = {size_kb} Ko ({len(pdf_bytes)} octets > 5 Ko)")
        check(pdf_bytes.startswith(b"%PDF-"), "Signature binaire %PDF- valide")

        reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
        num_pages = len(reader.pages)
        check(num_pages == 1, f"Nombre de pages strict = {num_pages} page A4 recto")

        extracted_text = reader.pages[0].extract_text() or ""
        check(
            "FICHE STRATÉGIQUE" in extracted_text and "VOIE A" in extracted_text and "VOIE B" in extracted_text,
            "Les 4 blocs visuels (En-tête, Voie A / Voie B, Plan d'actions, Questions PP/Psy-EN) sont présents dans le PDF",
        )

        # 4. Sauvegarde sous data/processed/test_fiche_orientation.pdf
        print("\n[4/4] Sauvegarde de l'exemplaire de test...")
        OUTPUT_PDF_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_PDF_PATH.write_bytes(pdf_bytes)
        check(
            OUTPUT_PDF_PATH.exists() and OUTPUT_PDF_PATH.stat().st_size > 5120,
            f"Exemplaire sauvegardé sous : {OUTPUT_PDF_PATH.relative_to(ROOT)} ({size_kb} Ko)",
        )

    print("\n" + "=" * 78)
    print("SUCCÈS TOTAL : LE GÉNÉRATEUR PDF SKILL 12 EST VALIDÉ.")
    print("=" * 78)


if __name__ == "__main__":
    main()
