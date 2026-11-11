import sys
import urllib.request
import zipfile
import io
import json
import re
import shutil
from pathlib import Path

# Assure le support UTF-8 sur la console Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROME_ZIP_URL = "https://api.francetravail.fr/api-nomenclatureemploi/v1/open-data/json"
DATA_DIR = Path(__file__).resolve().parent.parent / "data"
METIERS_FILE = DATA_DIR / "metiers.json"
BACKUP_FILE = DATA_DIR / "metiers.backup.json"

FAMILY_SOFT_SKILLS = {
    "A": {"creativite": 5, "empathie": 5, "communication": 5, "organisation": 7, "logique": 6},
    "B": {"creativite": 10, "empathie": 6, "communication": 7, "organisation": 6, "logique": 5},
    "C": {"creativite": 4, "empathie": 6, "communication": 8, "organisation": 8, "logique": 8},
    "D": {"creativite": 6, "empathie": 8, "communication": 9, "organisation": 7, "logique": 6},
    "E": {"creativite": 9, "empathie": 7, "communication": 9, "organisation": 7, "logique": 6},
    "F": {"creativite": 5, "empathie": 5, "communication": 6, "organisation": 8, "logique": 7},
    "G": {"creativite": 6, "empathie": 8, "communication": 9, "organisation": 8, "logique": 5},
    "H": {"creativite": 5, "empathie": 5, "communication": 6, "organisation": 8, "logique": 8},
    "I": {"creativite": 5, "empathie": 5, "communication": 6, "organisation": 8, "logique": 9},
    "J": {"creativite": 5, "empathie": 10, "communication": 8, "organisation": 9, "logique": 7},
    "K": {"creativite": 6, "empathie": 9, "communication": 8, "organisation": 8, "logique": 6},
    "L": {"creativite": 10, "empathie": 7, "communication": 8, "organisation": 6, "logique": 5},
    "M": {"creativite": 6, "empathie": 6, "communication": 7, "organisation": 8, "logique": 8},
    "N": {"creativite": 4, "empathie": 5, "communication": 6, "organisation": 9, "logique": 7},
}

SPECIFIC_M_SOFT_SKILLS = {
    "M18": {"creativite": 7, "empathie": 5, "communication": 6, "organisation": 7, "logique": 9},
    "M15": {"creativite": 6, "empathie": 9, "communication": 9, "organisation": 8, "logique": 6},
    "M12": {"creativite": 4, "empathie": 5, "communication": 6, "organisation": 9, "logique": 9},
    "M16": {"creativite": 5, "empathie": 7, "communication": 8, "organisation": 9, "logique": 6},
    "M17": {"creativite": 8, "empathie": 7, "communication": 8, "organisation": 8, "logique": 7},
}

def determine_soft_skills(code_rome: str) -> dict:
    prefix2 = code_rome[:3].upper()
    prefix1 = code_rome[:1].upper()
    if prefix2 in SPECIFIC_M_SOFT_SKILLS:
        return SPECIFIC_M_SOFT_SKILLS[prefix2].copy()
    if prefix1 in FAMILY_SOFT_SKILLS:
        return FAMILY_SOFT_SKILLS[prefix1].copy()
    return {"creativite": 5, "empathie": 5, "communication": 5, "organisation": 5, "logique": 5}

def slugify(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[àáâãäå]", "a", text)
    text = re.sub(r"[éèêë]", "e", text)
    text = re.sub(r"[îï]", "i", text)
    text = re.sub(r"[ôö]", "o", text)
    text = re.sub(r"[ùûü]", "u", text)
    text = re.sub(r"[ç]", "c", text)
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return text.strip("_")

def clean_text(text: str) -> str:
    if not text:
        return ""
    return re.sub(r"\s+", " ", str(text)).strip()

def download_and_extract_rome():
    print("[TELECHARGEMENT] Telechargement de l'archive ROME 4.0 depuis France Travail...")
    req = urllib.request.Request(ROME_ZIP_URL, headers={"User-Agent": "Mozilla/5.0 (OrientationIA/1.0)"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        zip_bytes = resp.read()
    print(f"[EXTRACTION] Archive telechargee avec succes ({len(zip_bytes) / 1024 / 1024:.2f} Mo).")

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
        print("[EXTRACTION] Extraction de unix_fiche_emploi_metier_v461.json...")
        raw_data = z.read("unix_fiche_emploi_metier_v461.json")
        try:
            return json.loads(raw_data.decode("iso-8859-1"))
        except Exception:
            return json.loads(raw_data.decode("utf-8", errors="ignore"))

def main():
    print("=== Demarrage de l'importation ROME 4.0 ===")
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    existing_metiers = []
    if METIERS_FILE.exists():
        shutil.copyfile(METIERS_FILE, BACKUP_FILE)
        print(f"[SAUVEGARDE] Sauvegarde creee : {BACKUP_FILE}")
        with open(METIERS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            existing_metiers = data.get("metiers", [])
        print(f"[INFO] {len(existing_metiers)} metiers enrichis existants charges.")

    existing_slugs = {m.get("id"): m for m in existing_metiers}
    existing_rome_codes = {m.get("code_rome"): m for m in existing_metiers if m.get("code_rome")}

    rome_fiches = download_and_extract_rome()
    print(f"[INFO] {len(rome_fiches)} fiches metiers ROME 4.0 trouvees.")

    imported_metiers = []

    for fiche in rome_fiches:
        rome_info = fiche.get("rome", {})
        code_rome = rome_info.get("code_rome", "").strip()
        intitule = clean_text(rome_info.get("intitule", ""))

        if not code_rome or not intitule:
            continue

        fiche_slug = f"{code_rome.lower()}_{slugify(intitule)}"

        if fiche_slug in existing_slugs or code_rome in existing_rome_codes:
            matched_job = existing_slugs.get(fiche_slug) or existing_rome_codes.get(code_rome)
            matched_job["code_rome"] = code_rome
            matched_job["rome_definition"] = clean_text(fiche.get("definition", ""))
            continue

        definition = clean_text(fiche.get("definition", ""))
        missions = []
        if definition:
            sentences = [clean_text(s) for s in re.split(r"[.;]", definition) if len(clean_text(s)) > 15]
            missions = sentences[:4]

        hard_skills = []
        competences_obj = fiche.get("competences", {})
        savoir_faire = competences_obj.get("savoir_faire", {}).get("enjeux", [])
        for enjeu in savoir_faire:
            for item in enjeu.get("items", []):
                libelle = clean_text(item.get("libelle", ""))
                if libelle and libelle not in hard_skills:
                    hard_skills.append(libelle)
                if item.get("coeur_metier") == "Principale" and len(missions) < 5:
                    if libelle not in missions:
                        missions.append(libelle)

        acces_metier = clean_text(fiche.get("acces_metier", ""))
        etudes = [acces_metier] if acces_metier else ["Cursus selon profil et specialite"]

        secteurs = [clean_text(s.get("libelle", "")) for s in fiche.get("secteurs_activite", []) if s.get("libelle")]
        if not secteurs:
            secteurs = ["Tous secteurs"]

        appellations = [clean_text(a.get("libelle", "")) for a in fiche.get("appellations", []) if a.get("libelle")][:10]

        soft_skills = determine_soft_skills(code_rome)

        job_entry = {
            "id": fiche_slug,
            "nom": intitule,
            "code_rome": code_rome,
            "domaines": secteurs[:3],
            "missions": missions if missions else ["Realiser les activites operationnelles du metier"],
            "soft_skills": soft_skills,
            "hard_skills": hard_skills[:8],
            "etudes": etudes,
            "environnement": {
                "lieu": "entreprise / terrain",
                "rythme": "standard",
                "teletravail": bool(code_rome.startswith("M") or code_rome.startswith("E")),
                "ambiance": "professionnelle"
            },
            "appellations": appellations,
            "source": "rome_4.0"
        }

        imported_metiers.append(job_entry)

    all_metiers = existing_metiers + imported_metiers

    print(f"[FUSION] Fusion terminee : {len(existing_metiers)} metiers enrichis + {len(imported_metiers)} metiers ROME 4.0 = {len(all_metiers)} metiers au total.")

    with open(METIERS_FILE, "w", encoding="utf-8") as f:
        json.dump({"metiers": all_metiers}, f, indent=2, ensure_ascii=False)

    print(f"[TERMINE] Fichier sauvegarde : {METIERS_FILE} ({METIERS_FILE.stat().st_size / 1024 / 1024:.2f} Mo).")

if __name__ == "__main__":
    main()
