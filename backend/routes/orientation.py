from fastapi import APIRouter, HTTPException, Header, UploadFile, File
from pydantic import BaseModel
from typing import Optional, Dict, List, Any
import json
import re
import io
from pathlib import Path
import pypdf

try:
    from services.ai_engine import query_local_llm
except ImportError:
    from backend.services.ai_engine import query_local_llm

router = APIRouter()

DATA_FILE = Path(__file__).resolve().parent.parent / "data" / "metiers.json"
FILIERES_FILE = Path(__file__).resolve().parent.parent / "data" / "filieres_selectives.json"

_CACHED_METIERS = None
_CACHED_FILIERES_DATA = None

class StudentBulletin(BaseModel):
    moyenne_generale: Optional[float] = None
    matieres: Dict[str, float] = {}
    filiere: Optional[str] = None
    classe_actuelle: Optional[str] = None
    specialites: List[str] = []
    trimestre: Optional[str] = None
    points_forts: List[str] = []
    dominante: Optional[str] = None
    lycee_nom: Optional[str] = None
    lycee_ville: Optional[str] = None
    lycee_academie: Optional[str] = None
    lycee_region: Optional[str] = None
    lycee_taux_mentions: Optional[float] = None
    lycee_bonus_selectivite: Optional[float] = 0.0

class StudentProfile(BaseModel):
    # Niveau scolaire & Spécialités (Modules 1 & 2)
    classe_actuelle: Optional[str] = None
    specialites_choisies: List[str] = []
    filiere_ambition_id: Optional[str] = None

    # Lycée d'origine & Région
    lycee_nom: Optional[str] = None
    lycee_ville: Optional[str] = None
    lycee_academie: Optional[str] = None
    lycee_region: Optional[str] = None
    lycee_taux_mentions: Optional[float] = None
    lycee_bonus_selectivite: Optional[float] = 0.0

    # Profilage RIASEC (Skill 3 - Holland) & Passions brutes (Skill 2 - Décodeur de Talents)
    riasec_scores: Dict[str, float] = {}  # R, I, A, S, E, C (échelle 0-10)
    passions_brutes: List[str] = []

    # Rétrocompatibilité soft skills (dérivables du RIASEC)
    creativite: int = 0
    empathie: int = 0
    communication: int = 0
    organisation: int = 0
    logique: int = 0
    mbti_archetype: Optional[str] = None

    # Vœux & Vision du Futur
    secteurs_souhaits: List[str] = []
    role_vise: Optional[str] = None
    style_vie: Optional[str] = None
    preferences_sociales: Optional[str] = None
    environnement_prefere: Optional[str] = None

    # Bulletin Scolaire (Priorité Académique #1)
    bulletin: Optional[StudentBulletin] = None

class SubjectGapItem(BaseModel):
    matiere: str
    note_actuelle: float
    seuil_attendu: float
    delta: float
    statut: str  # "favorable", "vigilance", "critique"
    priorite: int = 1

class GapAnalysisResponse(BaseModel):
    filiere_cible: str
    probabilite_admission: int
    statut_global: str
    ecarts_matieres: List[SubjectGapItem] = []
    talents_decodes: List[Dict[str, str]] = []
    profil_riasec: Dict[str, float] = {}

class TrajectoryOption(BaseModel):
    type_trajectoire: str  # "ambition" | "realiste"
    titre: str
    etablissement_type: str
    taux_acces_estime: int
    conditions_acces: List[str] = []
    metiers_cibles: List[Dict[str, Any]] = []

class DoubleTrajectoryResponse(BaseModel):
    parcours_ambition: TrajectoryOption
    parcours_realiste: TrajectoryOption
    impact_specialites: Dict[str, Any] = {}


import sqlite3
import unicodedata

def _unaccent_lower_helper(text: str) -> str:
    if not text:
        return ""
    return "".join(
        c for c in unicodedata.normalize("NFD", text.lower())
        if unicodedata.category(c) != "Mn"
    )

def _resolve_db_path() -> Path:
    candidates = [
        Path(__file__).resolve().parent.parent / "data" / "processed" / "orientation_data.sqlite",
        Path(__file__).resolve().parent.parent / "data" / "orientation_data.sqlite",
        Path("data/processed/orientation_data.sqlite"),
        Path("backend/data/processed/orientation_data.sqlite"),
        Path("backend/data/orientation_data.sqlite"),
        Path("orientation_data.sqlite"),
    ]
    for p in candidates:
        if p.exists() and p.stat().st_size > 1000:
            return p
    return candidates[0]

DB_PROCESSED_PATH = _resolve_db_path()

def _get_sqlite_conn():
    conn = sqlite3.connect(DB_PROCESSED_PATH)
    conn.create_function("unaccent_lower", 1, _unaccent_lower_helper)
    return conn


BASSIN_BORDERS = {
    "Auvergne-Rhône-Alpes": ["Auvergne-Rhône-Alpes", "Bourgogne-Franche-Comté", "Centre-Val de Loire", "Nouvelle-Aquitaine", "Occitanie", "Provence-Alpes-Côte d'Azur"],
    "Bourgogne-Franche-Comté": ["Bourgogne-Franche-Comté", "Auvergne-Rhône-Alpes", "Centre-Val de Loire", "Grand Est", "Île-de-France"],
    "Bretagne": ["Bretagne", "Normandie", "Pays de la Loire"],
    "Centre-Val de Loire": ["Centre-Val de Loire", "Auvergne-Rhône-Alpes", "Bourgogne-Franche-Comté", "Île-de-France", "Normandie", "Nouvelle-Aquitaine", "Pays de la Loire"],
    "Corse": ["Corse", "Provence-Alpes-Côte d'Azur"],
    "Grand Est": ["Grand Est", "Bourgogne-Franche-Comté", "Hauts-de-France", "Île-de-France"],
    "Hauts-de-France": ["Hauts-de-France", "Grand Est", "Île-de-France", "Normandie"],
    "Île-de-France": ["Île-de-France", "Bourgogne-Franche-Comté", "Centre-Val de Loire", "Grand Est", "Hauts-de-France", "Normandie"],
    "Normandie": ["Normandie", "Bretagne", "Centre-Val de Loire", "Hauts-de-France", "Île-de-France", "Pays de la Loire"],
    "Nouvelle-Aquitaine": ["Nouvelle-Aquitaine", "Auvergne-Rhône-Alpes", "Centre-Val de Loire", "Occitanie", "Pays de la Loire"],
    "Occitanie": ["Occitanie", "Auvergne-Rhône-Alpes", "Nouvelle-Aquitaine", "Provence-Alpes-Côte d'Azur"],
    "Pays de la Loire": ["Pays de la Loire", "Bretagne", "Centre-Val de Loire", "Normandie", "Nouvelle-Aquitaine"],
    "Provence-Alpes-Côte d'Azur": ["Provence-Alpes-Côte d'Azur", "Auvergne-Rhône-Alpes", "Corse", "Occitanie"],
    "Guadeloupe": ["Guadeloupe", "Martinique"],
    "Martinique": ["Martinique", "Guadeloupe"],
    "Guyane": ["Guyane"],
    "La Réunion": ["La Réunion", "Mayotte"],
    "Mayotte": ["Mayotte", "La Réunion"],
}

DOMAIN_MAPPING = {
    "pass_las_sante": "sante",
    "sante": "sante",
    "cpge_mpsi_pcsi": "cpge_sci",
    "ecole_inge_postbac": "inge",
    "sciences_po_iep": "sciences_po",
    "droit": "droit",
    "droit_sciences_juridiques": "droit",
    "cpge_ecg_droit": "droit",
    "cpge_ecg_commerce": "commerce",
    "but_info_geii": "informatique",
    "informatique": "informatique",
    "architecture": "architecture",
}


ID_ALIASES = {
    "pass_las_sante": "pass_las_medecine",
    "pass_las_medecine": "pass_las_medecine",
    "sante": "pass_las_medecine",
    "medecine": "pass_las_medecine",
    "cpge_ecg_droit": "cpge_ecg_commerce",
    "cpge_ecg_commerce": "cpge_ecg_commerce",
    "commerce": "cpge_ecg_commerce",
    "ecg": "cpge_ecg_commerce",
    "sciences_po_iep": "sciences_po_bl_droit",
    "sciences_po_bl_droit": "sciences_po_bl_droit",
    "sciences_po": "sciences_po_bl_droit",
    "droit": "sciences_po_bl_droit",
    "but_info_geii": "but_info_geii",
    "informatique": "but_info_geii",
    "cpge_mpsi_pcsi": "cpge_mpsi_pcsi",
    "ecole_inge_postbac": "ecole_inge_postbac",
    "ensa_archi_gobelins": "ensa_archi_gobelins",
}

def _get_adaptive_elite_note(domain: str) -> str:
    if domain == "sante":
        return "Tu es déjà au sommet des exigences régionales en santé (17+/20). Bascule sur l'échelle « Toute la France (National) » pour viser les facultés de médecine les plus prestigieuses et sélectives du pays (Faculté de Santé Sorbonne Université, Faculté de Médecine Paris Cité, Université Claude Bernard Lyon 1...)."
    elif domain == "droit":
        return "Tu es déjà au sommet des exigences régionales en droit (17+/20). Bascule sur l'échelle « Toute la France (National) » pour viser l'élite juridique nationale (Université Paris-Panthéon-Assas, Sorbonne Droit, Collèges de Droit d'Excellence...)."
    elif domain == "commerce":
        return "Tu es déjà au sommet des exigences régionales en économie et gestion (17+/20). Bascule sur l'échelle « Toute la France (National) » pour viser les grandes prépas ECG d'élite (Stanislas, Henri IV, Franklin) et Paris-Dauphine (PSL)."
    elif domain == "sciences_po":
        return "Tu es déjà au sommet des exigences académiques régionales (17+/20). Bascule sur l'échelle « Toute la France (National) » pour viser Sciences Po Paris et les cursus d'excellence en sciences politiques."
    elif domain == "informatique":
        return "Tu es déjà au sommet des exigences régionales (17+/20). Bascule sur l'échelle « Toute la France (National) » pour viser les filières d'excellence en informatique et IA (Université Paris-Saclay, Sorbonne Université, UTC, INSA Lyon)."
    else:
        return "Tu es déjà au sommet des exigences régionales (17+/20). Bascule sur l'échelle « Toute la France (National) » pour viser l'élite ultra-sélective des CPGE et Grandes Écoles (Henri IV, Louis-le-Grand, Sainte-Geneviève, INSA Lyon...)."

def resolve_domain_tag(
    filiere_id: Optional[str] = None,
    secteurs: Optional[list] = None,
    pole_default: str = "",
    passions: Optional[list] = None
) -> str:
    # 1. Détection prioritaire par passions réelles (Décodeur de Talents)
    passions_str = " ".join(passions or []).lower()
    if any(t in passions_str for t in ["gaming", "esport", "programmation", "mods", "cyber", "serveurs"]):
        return "informatique"
    if any(t in passions_str for t in ["manga", "dessin", "musique", "beatmaking", "video", "vidéo", "montage", "design"]):
        return "architecture"
    if any(t in passions_str for t in ["achat-revente", "sneakers", "commerce", "finance", "e-commerce"]):
        return "commerce"
    if any(t in passions_str for t in ["debat", "débat", "eloquence", "éloquence", "géopolitique"]):
        return "droit"
    if any(t in passions_str for t in ["bricolage", "mecanique", "mécanique", "electronique", "électronique"]):
        return "inge"
    if any(t in passions_str for t in ["sport", "aide aux autres"]):
        return "sante"

    combined = f"{filiere_id or ''} {' '.join(secteurs or [])} {' '.join(passions or [])} {pole_default or ''}".lower()
    for k, v in DOMAIN_MAPPING.items():
        if k in combined:
            return v
    if any(t in combined for t in ["art", "design", "manga", "dessin", "musique", "beatmaking", "video", "vidéo", "montage", "architecture", "3d"]):
        return "architecture"
    if any(t in combined for t in ["gaming", "esport", "programmation", "mods", "cyber", "serveurs", "code", "info", "donnees", "données", "numerique", "numérique"]):
        return "informatique"
    if any(t in combined for t in ["achat-revente", "sneakers", "commerce", "finance", "e-commerce", "gestion", "management", "ecg", "marketing"]):
        return "commerce"
    if any(t in combined for t in ["debat", "débat", "eloquence", "éloquence", "droit", "juridique", "justice", "avocat"]):
        return "droit"
    if any(t in combined for t in ["sciences po", "iep", "geopolitique", "géopolitique", "actualites", "actualités", "politique", "international"]):
        return "sciences_po"
    if any(t in combined for t in ["bricolage", "mecanique", "mécanique", "electronique", "électronique", "robotique", "inge", "ingé", "polytech", "insa"]):
        return "inge"
    if any(t in combined for t in ["sante", "santé", "medecine", "médecine", "pass", "las", "soins", "kine", "kiné", "sport", "aide aux autres"]):
        return "sante"
    if any(t in combined for t in ["prepa", "mpsi", "pcsi", "mp2i", "ptsi", "bcpst"]):
        return "cpge_sci"
    return "general"


def search_lycees_db(
    q: str = "",
    region: Optional[str] = None,
    departement: Optional[str] = None,
    academie: Optional[str] = None,
    limit: int = 25
):
    """Recherche parmi les 4 783 lycées français avec filtres hiérarchiques (Région, Académie, Département, Commune/Nom)."""
    try:
        conn = _get_sqlite_conn()
        cursor = conn.cursor()
        where_parts = []
        params = []

        if q and q.strip():
            q_norm = _unaccent_lower_helper(q.strip())
            where_parts.append("(unaccent_lower(nom) LIKE ? OR unaccent_lower(ville) LIKE ? OR code_postal LIKE ? OR unaccent_lower(uai) LIKE ?)")
            val = f"%{q_norm}%"
            params.extend([val, val, val, val])

        if region and region.strip():
            where_parts.append("unaccent_lower(region) = ?")
            params.append(_unaccent_lower_helper(region.strip()))

        if departement and departement.strip():
            where_parts.append("(unaccent_lower(departement) = ? OR unaccent_lower(code_departement) = ?)")
            d_val = _unaccent_lower_helper(departement.strip())
            params.extend([d_val, d_val])

        if academie and academie.strip():
            where_parts.append("unaccent_lower(academie) = ?")
            params.append(_unaccent_lower_helper(academie.strip()))

        where_clause = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
        sql = f"""
        SELECT lycee_id, nom, ville, code_postal, departement, academie, region, taux_mentions_bac, valeur_ajoutee_mentions, bonus_selectivite
        FROM lycees_ival
        {where_clause}
        ORDER BY bonus_selectivite DESC, taux_mentions_bac DESC, nom ASC
        LIMIT ?
        """
        params.append(limit)
        cursor.execute(sql, params)
        rows = cursor.fetchall()
        conn.close()

        out = []
        for r in rows:
            out.append({
                "lycee_id": r[0],
                "nom": r[1],
                "ville": r[2],
                "code_postal": r[3] or "",
                "departement": r[4] or "",
                "academie": r[5] or "",
                "region": r[6] or "",
                "taux_mentions": float(r[7] or 0.0),
                "valeur_ajoutee_mentions": float(r[8] or 0.0),
                "bonus_selectivite": float(r[9] or 0.0),
            })
        return out
    except Exception as e:
        print(f"[search_lycees_db error] {e}")
        return []

def detect_lycee_from_text(bulletin_text: str):
    """Détecte automatiquement si un lycée français reconnu apparaît dans l'en-tête du bulletin."""
    if not bulletin_text:
        return None
    text_clean = _unaccent_lower_helper(bulletin_text[:2000])
    try:
        conn = _get_sqlite_conn()
        cursor = conn.cursor()
        cursor.execute("SELECT nom, ville, academie, region, taux_mentions_bac, valeur_ajoutee_mentions FROM lycees_ival")
        all_lycees = cursor.fetchall()
        conn.close()

        best_match = None
        best_score = 0
        for l_nom, l_ville, l_acad, l_reg, l_taux, l_va in all_lycees:
            nom_clean = _unaccent_lower_helper(l_nom)
            core_nom = re.sub(r'^(lycee|institution|college|ensemble scolaire)\s+', '', nom_clean).strip()
            if len(core_nom) >= 4 and core_nom in text_clean:
                score = len(core_nom)
                if score > best_score:
                    best_score = score
                    taux = float(l_taux or 0.0)
                    bonus = 0.0
                    if taux >= 92.0:
                        bonus = 1.2
                    elif taux >= 85.0:
                        bonus = 0.8
                    elif taux >= 78.0:
                        bonus = 0.4
                    best_match = {
                        "nom": l_nom,
                        "ville": l_ville,
                        "academie": l_acad,
                        "region": l_reg,
                        "taux_mentions": taux,
                        "bonus_selectivite": bonus,
                        "est_reconnu": True,
                    }
        return best_match
    except Exception as e:
        print(f"[detect_lycee_from_text error] {e}")
        return None

def _extract_smart_domain_keywords(ambition_id: Optional[str] = None, secteurs_souhaits: Optional[list] = None, pole_default: str = "") -> list:
    kws = set()
    text = f"{ambition_id or ''} {' '.join(secteurs_souhaits or [])} {pole_default or ''}".lower()
    mapping = {
        ('mpsi', 'pcsi', 'mp2i', 'ptsi', 'cpge', 'prepa', 'math'): ['mpsi', 'pcsi', 'mp2i', 'ptsi', 'cpge', 'ingenieur', 'sciences', 'math'],
        ('info', 'data', 'ia', 'cyber', 'numerique', 'nsi'): ['informatique', 'numerique', 'data', 'sciences', 'but', 'licence'],
        ('sante', 'medecine', 'pass', 'las', 'biologie', 'svt'): ['pass', 'las', 'sante', 'biologie', 'sciences'],
        ('commerce', 'ecg', 'gestion', 'management', 'eco'): ['ecg', 'commerce', 'economie', 'gestion'],
        ('droit', 'sciences po', 'iep', 'avocat'): ['droit', 'sciences po', 'sciences sociales'],
        ('art', 'design', 'manga', 'architecture'): ['architecture', 'art', 'design', 'communication'],
    }
    for triggers, additions in mapping.items():
        if any(t in text for t in triggers):
            kws.update(additions)
    if not kws:
        kws.update(['sciences', 'licence', 'but', 'ingenieur', 'cpge'])
    return list(kws)


def get_triple_trajectory_formations(
    moyenne_eleve: float,
    filiere_id: Optional[str] = None,
    domain_keywords: Optional[list] = None,
    region: Optional[str] = None,
    secteurs_souhaits: Optional[list] = None,
    pole_default: str = "",
    is_top_lycee: bool = False,
    passions: Optional[list] = None
) -> Dict[str, Any]:
    """
    Génère les 3 Pôles de trajectoire (Sécurité, Cible, Ambition)
    avec filtrage strict par domaine et seuils mathématiques officiels :
      - Sécurité : [-3.0, -1.5] (vide si moyenne < 10)
      - Cible : [-1.0, +1.5]
      - Ambition : [+3.0, +5.0] (vide en Bassin si moyenne >= 17 avec invite National, 13-14 si < 10)
      - Bassin Géographique : Région de l'élève + Régions frontalières uniquement
      - Vérité des résultats : ZÉRO remplissage artificiel (si 1 école, affiche 1).
    """
    domain = resolve_domain_tag(filiere_id, secteurs_souhaits, pole_default, passions)
    try:
        conn = _get_sqlite_conn()
        cursor = conn.cursor()

        bassin_regions = BASSIN_BORDERS.get(region, [region] if region else [])

        def _query(min_s: float, max_s: float, reg_list: Optional[List[str]] = None, max_taux: Optional[float] = None, min_group: Optional[int] = None, order_by: str = "seuil_moyenne_estime ASC, taux_acces DESC"):
            params = [f"%{domain}%", min_s, max_s]
            where_conds = ["domain_tag LIKE ?", "seuil_moyenne_estime >= ?", "seuil_moyenne_estime <= ?"]

            if reg_list:
                placeholders = ",".join(["?"] * len(reg_list))
                where_conds.append(f"region IN ({placeholders})")
                params.extend(reg_list)

            if max_taux is not None:
                where_conds.append("taux_acces <= ?")
                params.append(max_taux)
            if min_group is not None:
                where_conds.append("selectivity_group <= ?")
                params.append(min_group)

            sql = f"""
            SELECT formation_id, nom, etablissement, filiere, filiere_detail, ville, region,
                   taux_acces, seuil_moyenne_estime, selectivity_group, ranking_label
            FROM parcoursup_formations
            WHERE {' AND '.join(where_conds)}
            ORDER BY {order_by}
            LIMIT 10
            """
            cursor.execute(sql, params)
            rows = cursor.fetchall()
            items = []
            for r in rows:
                seuil = float(r[8] or 14.0)
                taux = float(r[7] or 30.0)
                gap = round(moyenne_eleve - seuil, 2)
                prob = max(10, min(95, int(round(65 + gap * 12 + (taux - 40) * 0.3))))
                items.append({
                    "formation_id": r[0],
                    "nom": r[1],
                    "etablissement": r[2] or r[1],
                    "filiere": r[3],
                    "filiere_detail": r[4],
                    "ville": r[5] or "",
                    "region": r[6] or "",
                    "taux_acces": round(taux, 1),
                    "seuil_moyenne_estime": round(seuil, 2),
                    "estimated_gap": gap,
                    "probabilite_admission": prob,
                    "selectivity_group": int(r[9] or 3),
                    "ranking_label": r[10] or "",
                })
            return items

        # --- 1. PÔLE SÉCURITÉ ---
        sec_note = None
        if moyenne_eleve < 10.0:
            sec_nat = []
            sec_bassin = []
            sec_note = "Aucune voie de sécurité disponible : avec une moyenne inférieure à 10/20, la priorité absolue est la consolidation académique pour sécuriser l'obtention du baccalauréat."
        else:
            min_sec = max(10.0, round(moyenne_eleve - 3.0, 2))
            max_sec = round(moyenne_eleve - 1.5, 2)
            sec_nat = _query(min_sec, max_sec)
            sec_bassin = _query(min_sec, max_sec, bassin_regions) if bassin_regions else sec_nat
            if len(sec_bassin) == 0:
                sec_note = "Aucune formation dans cette tranche de sécurité dans ton bassin géographique."

        # --- 2. PÔLE CIBLE ---
        min_cib = max(10.0, round(moyenne_eleve - 1.0, 2))
        max_cib = min(20.0, round(moyenne_eleve + 1.5, 2))
        cib_nat = _query(min_cib, max_cib, order_by=f"ABS(seuil_moyenne_estime - {moyenne_eleve}) ASC, taux_acces DESC")
        cib_bassin = _query(min_cib, max_cib, bassin_regions, order_by=f"ABS(seuil_moyenne_estime - {moyenne_eleve}) ASC, taux_acces DESC") if bassin_regions else cib_nat
        cib_note = None
        if len(cib_bassin) == 0:
            cib_note = "Aucune formation cible correspondant exactement à cette tranche dans ton bassin."

        # --- 3. PÔLE AMBITION ---
        amb_note = None
        voie_royale = []

        if moyenne_eleve >= 17.0:
            amb_bassin = []
            amb_note = _get_adaptive_elite_note(domain)
            amb_nat = _query(17.0, 20.0, None, max_taux=15.0, min_group=1)
        elif moyenne_eleve < 10.0:
            amb_nat = _query(12.5, 14.5)
            amb_bassin = _query(12.5, 14.5, bassin_regions) if bassin_regions else amb_nat
            amb_note = "Objectif tremplin : franchir le palier des 13-14/20 pour débloquer ces filières sélectives."
        else:
            min_amb = round(moyenne_eleve + 3.0, 2)
            max_amb = min(20.0, round(moyenne_eleve + 5.0, 2))
            amb_nat = _query(min_amb, max_amb)
            amb_bassin = _query(min_amb, max_amb, bassin_regions) if bassin_regions else amb_nat

            if len(amb_bassin) == 0 and len(amb_nat) == 0:
                amb_nat = _query(moyenne_eleve + 1.5, 20.0, None)
                amb_bassin = _query(moyenne_eleve + 1.5, 20.0, bassin_regions) if bassin_regions else amb_nat

            if len(amb_bassin) == 0:
                amb_note = "Aucune formation dans cette tranche d'ambition dans ton bassin. Bascule sur l'échelle « Toute la France (National) » pour afficher les formations d'ambition."

        # VOIE ROYALE & ÉLITE : Toujours alimentée avec le TOP 10 National absolu, peu importe la moyenne
        cursor.execute("""
        SELECT formation_id, nom, etablissement, filiere, filiere_detail, ville, region,
               taux_acces, seuil_moyenne_estime, selectivity_group, ranking_label
        FROM parcoursup_formations
        WHERE domain_tag LIKE ?
        ORDER BY seuil_moyenne_estime DESC, taux_acces ASC
        LIMIT 10
        """, (f"%{domain}%",))
        for r in cursor.fetchall():
            voie_royale.append({
                "formation_id": r[0], "nom": r[1], "etablissement": r[2] or r[1],
                "filiere": r[3], "filiere_detail": r[4],
                "ville": r[5] or "", "region": r[6] or "", "taux_acces": round(float(r[7] or 0.0), 1),
                "seuil_moyenne_estime": round(float(r[8] or 0.0), 2), "selectivity_group": int(r[9] or 1),
                "ranking_label": r[10] or "Voie Royale & Élite Nationale",
            })

        conn.close()

        return {
            "securite": {
                "titre": "1. Sécurité",
                "sous_titre": "Socle Garanti (Filet de Secours)",
                "description": "Formations accessibles (2 à 3 points sous ton niveau) garantissant ton admission.",
                "national": sec_nat,
                "regional": sec_bassin,
                "note": sec_note,
            },
            "cible": {
                "titre": "2. Cible",
                "sous_titre": "Ton Niveau Réel",
                "description": "Formations parfaitement calibrées sur tes résultats actuels (-1.0 à +1.5 pt).",
                "national": cib_nat,
                "regional": cib_bassin,
                "note": cib_note,
            },
            "ambition": {
                "titre": "3. Ambition",
                "sous_titre": "Défi d'Excellence",
                "description": "Formations sélectives prestigieuses (+3.5 à +5.0 pts) qui tirent ton potentiel vers le haut.",
                "national": amb_nat,
                "regional": amb_bassin,
                "note": amb_note,
            },
            "voie_royale_elite": voie_royale,
        }
    except Exception as e:
        print(f"[get_triple_trajectory_formations error] {e}")
        return {}


class WeeklyTaskItem(BaseModel):
    jour: str
    creneau: str
    matiere: str
    objectif: str
    duree_minutes: int
    type_exercice: str

class DebateMessage(BaseModel):
    role: str = "user"
    text: str = ""

class DebateRequest(BaseModel):
    metier_nom: str
    metier_code_rome: Optional[str] = None
    objection: str
    history: List[DebateMessage] = []
    profile: Optional[StudentProfile] = None

class MetierChatRequest(BaseModel):
    metier_nom: str
    metier_code_rome: Optional[str] = None
    metier_description: Optional[str] = None
    metier_missions: List[str] = []
    metier_etudes: List[str] = []
    metier_salaire: Optional[Dict[str, Any]] = None
    question: str
    history: List[DebateMessage] = []
    profile: Optional[StudentProfile] = None

def load_metiers_data() -> list:
    global _CACHED_METIERS
    if _CACHED_METIERS is not None:
        return _CACHED_METIERS
    try:
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            _CACHED_METIERS = data.get("metiers", [])
            return _CACHED_METIERS
    except Exception as e:
        print(f"Erreur lors du chargement de metiers.json: {e}")
        return []

def generate_smart_fallback(profile: StudentProfile, top_3: list) -> str:
    m1 = top_3[0]["meta"].get("nom", "Métier recommandé")
    m2 = top_3[1]["meta"].get("nom", "Métier alternatif") if len(top_3) > 1 else ""
    m3 = top_3[2]["meta"].get("nom", "Piste d'avenir") if len(top_3) > 2 else ""
    return (
        f"### Synthèse Stratégique\n\n"
        f"Ton profil académique et tes centres d'intérêt mettent en évidence des aptitudes solides : "
        f"Logique ({profile.logique}/10), Organisation ({profile.organisation}/10), "
        f"Communication ({profile.communication}/10), Empathie ({profile.empathie}/10) "
        f"et Créativité ({profile.creativite}/10).\n\n"
        f"### Trajectoires Identifiées\n\n"
        f"1. **{m1}** : Cible principale cohérente avec tes compétences et ton cadre de travail privilégié.\n"
        f"2. **{m2}** : Trajectoire complémentaire valorisant tes capacités d'analyse et d'exécution.\n"
        f"3. **{m3}** : Option de sécurisation offrant des débouchés concrets et rapides.\n\n"
        f"### Prochaine action recommandée\n\n"
        f"Vérifie les attendus académiques et les spécialités requises pour **{m1}** afin de planifier tes priorités de travail hebdomadaires."
    )

def _build_metier_description(m: dict) -> str:
    # 1. Si description déjà explicite
    if m.get("description") and len(str(m["description"]).strip()) > 20:
        return str(m["description"]).strip()

    nom = m.get("nom", "Ce professionnel")
    missions = m.get("missions", [])
    domaines = m.get("domaines", [])

    if missions:
        m0 = missions[0].strip()
        # Si la première mission décrit le poste (ex: ROME "Le responsable de...")
        if m0.lower().startswith("le ") or m0.lower().startswith("la ") or m0.lower().startswith("l'"):
            desc = m0
            if not desc.endswith("."):
                desc += "."
            return desc

        # Sinon combiner les premières missions pour une description claire
        parts = [m0]
        if len(missions) > 1 and len(m0) < 140:
            parts.append(missions[1].strip())
        joined = ". ".join(parts)
        if not joined.endswith("."):
            joined += "."
        return f"En tant que {nom}, le quotidien consiste à : {joined}"

    if domaines:
        return f"{nom} est une profession d'expertise intervenant principalement dans les secteurs : {', '.join(domaines)}."

    return f"{nom} : activité professionnelle clé dans son secteur d'activité."

# Liste ordonnée (du plus spécifique au plus général) pour éviter les collisions
# ex: "Éducation physique et sportive (EPS)" ne doit JAMAIS matcher "Physique-Chimie",
# et "Mathématiques expertes" ne doit pas être absorbé par "Mathématiques".
ORDERED_SUBJECT_RULES = [
    ("Mathématiques expertes", [
        r"math[ée]matiques?\s+expertes?",
        r"maths?\s+expertes?",
    ]),
    ("Mathématiques complémentaires", [
        r"math[ée]matiques?\s+compl[ée]mentaires?",
        r"maths?\s+compl[ée]mentaires?",
    ]),
    ("Informatique / NSI", [
        r"\bnsi\b",
        r"num[ée]rique\s+et\s+sciences?\s+informatiques?",
        r"sp[ée]cialit[ée]\s+num[ée]rique",
        r"sciences?\s+informatiques?",
        r"\binformatiques?\b",
        r"\balgorithmique\b",
    ]),
    ("Éducation Physique (EPS)", [
        r"\beps\b",
        r"[ée]ducation\s+physique\s+et\s+sportive",
        r"physique\s+et\s+sportive",
        r"[ée]duc(?:ation)?\s+phys",
    ]),
    ("Enseignement moral et civique (EMC)", [
        r"\bemc\b",
        r"enseignement\s+moral\s+et\s+civique",
        r"moral\s+et\s+civique",
    ]),
    ("Enseignement scientifique", [
        r"enseignement\s+scientifique",
    ]),
    ("HGGSP", [
        r"\bhggsp\b",
        r"g[ée]opolitique\s+et\s+sciences?\s+politiques?",
    ]),
    ("HLP", [
        r"\bhlp\b",
        r"humanit[ée]s?\s*,?\s*litt[ée]rature\s+et\s+philosophie",
    ]),
    ("LLCE", [
        r"\bllcer?\b",
        r"litt[ée]ratures?\s+et\s+cultures?\s+[ée]trang[èe]res?",
    ]),
    ("Français-Philosophie", [
        r"fran[çc]ais[\s\-]*(?:philo|philosophie)",
        r"culture\s+g[ée]n[ée]rale",
    ]),
    ("SVT / Biologie", [
        r"\bsvt\b",
        r"sciences?\s+de\s+la\s+vie\s+et\s+de\s+la\s+terre",
        r"sciences?\s+de\s+la\s+vie",
        r"\bbiologie\b",
    ]),
    ("Sciences Industrielles / SI", [
        r"sciences?\s+industrielles?",
        r"sciences?\s+de\s+l[\'\’\s]?ing[ée]nieur",
        r"\bsi\s+sem\b",
        r"g[ée]nie\s+m[ée]canique",
    ]),
    ("SES / Économie", [
        r"\bses\b",
        r"sciences?\s+[ée]conomiques?\s+et\s+sociales?",
        r"[ée]conomie[\s\-]+gestion",
        r"\b[ée]conomie\b",
    ]),
    ("Physique-Chimie", [
        r"physique[\s\-]*chimie",
        r"sp[ée]cialit[ée]\s+physique",
        r"sciences?\s+physiques?",
        r"\bphysique\b",
        r"\bchimie\b",
    ]),
    ("Mathématiques", [
        r"sp[ée]cialit[ée]\s+math[ée]matiques?",
        r"\bmath[ée]matiques?\b",
        r"\bmaths?\b",
    ]),
    ("Histoire-Géographie", [
        r"histoire[\s\-–—]*g[ée]ographie",
        r"\bhist[\s\-]*g[ée]o\b",
        r"\bhistoire\b",
        r"\bg[ée]ographie\b",
    ]),
    ("Philosophie", [
        r"\bphilosophie\b",
        r"\bphilo\b",
    ]),
    ("Français", [
        r"\bfran[çc]ais\b",
        r"\blettres\b",
    ]),
    ("Anglais", [
        r"langue\s+vivante\s*[a1]?[\s\-–—:]*anglais",
        r"\banglais\b",
        r"\benglish\b",
        r"\blva\b",
        r"\blv1\b",
    ]),
    ("Espagnol / LV2", [
        r"langue\s+vivante\s*[b2]?[\s\-–—:]*espagnol",
        r"\bespagnol\b",
        r"\ballemand\b",
        r"\bitalien\b",
        r"\blvb\b",
        r"\blv2\b",
    ]),
    ("Littérature arabe", [
        r"litt[ée]rature\s+arabe",
        r"\barabe\b",
        r"\badab\b",
    ]),
    ("Sciences islamiques", [
        r"sciences?\s+islamiques?",
        r"\bcharia\b",
        r"\btarbiya\b",
    ]),
    ("Art", [
        r"\barts?\s+plastiques?\b",
        r"enseignement\s+artistique",
        r"\bmusique\b",
    ]),
]


def _match_canonical_subject(text_fragment: str, already_found: set) -> Optional[str]:
    """Identifie une matière canonique dans un court fragment d'intitulé de matière."""
    frag = (text_fragment or "").strip().lower()
    if not frag:
        return None
    # Ignorer les lignes d'en-tête ou de synthèse globale
    if any(k in frag for k in [
        "appréciation générale",
        "appreciation generale",
        "conseil de classe",
        "moyenne générale",
        "moyenne generale",
        "chef d'établissement",
        "professeur principal",
        "enseignements de spécialité",
        "enseignements communs",
        "enseignements optionnels",
    ]):
        return None

    for canonical, patterns in ORDERED_SUBJECT_RULES:
        if canonical in already_found:
            continue
        for pat in patterns:
            if re.search(pat, frag):
                return canonical
    return None


def _detect_classe_from_text(full_text: str) -> Optional[str]:
    t = (full_text or "").lower()
    if re.search(r"classe\s+de\s+premi[èe]re|\bpremi[èe]re\s+g[ée]n[ée]rale|\b1[èe]re\s+g[ée]n[ée]rale", t):
        return "Première"
    if re.search(r"classe\s+de\s+terminale|\bterminale\s+g[ée]n[ée]rale|\bterminale\b", t):
        return "Terminale"
    if re.search(r"classe\s+de\s+seconde|\bseconde\s+g[ée]n[ée]rale|\b2nde\b", t):
        return "2nde"
    if re.search(r"classe\s+de\s+troisi[èe]me|\bclasse\s+de\s+3[eè]\b|\b3[eè]me\b", t):
        return "3e"
    return None


def _compute_bulletin_summary(
    found_matieres: Dict[str, float],
    moyenne_gen: Optional[float],
    classe_detectee: Optional[str] = None,
    specialites_detectees: Optional[List[str]] = None,
    lycee_detecte: Optional[dict] = None,
) -> dict:
    detected = bool(found_matieres)
    notes = list(found_matieres.values())
    if moyenne_gen is None:
        moyenne_gen = round(sum(notes) / len(notes), 2) if notes else None
    else:
        moyenne_gen = round(moyenne_gen, 2)

    points_forts = [m for m, n in found_matieres.items() if n >= 13.5]
    if not points_forts and found_matieres:
        sorted_m = sorted(found_matieres.items(), key=lambda x: x[1], reverse=True)
        points_forts = [m[0] for m in sorted_m[:3]]

    sci_subjects = [
        "Mathématiques",
        "Mathématiques expertes",
        "Mathématiques complémentaires",
        "Physique-Chimie",
        "Sciences Industrielles / SI",
        "SVT / Biologie",
        "Informatique / NSI",
        "Enseignement scientifique",
    ]
    lit_subjects = [
        "Français-Philosophie",
        "Français",
        "HLP",
        "HGGSP",
        "LLCE",
        "Littérature arabe",
        "Sciences islamiques",
        "Histoire-Géographie",
        "Philosophie",
        "Anglais",
        "Espagnol / LV2",
    ]

    sci_notes = [found_matieres[s] for s in sci_subjects if s in found_matieres]
    lit_notes = [found_matieres[s] for s in lit_subjects if s in found_matieres]

    sci_avg = sum(sci_notes) / len(sci_notes) if sci_notes else 0.0
    lit_avg = sum(lit_notes) / len(lit_notes) if lit_notes else 0.0

    if not found_matieres:
        dominante = None
    elif sci_avg >= 13.0 and sci_avg > lit_avg + 0.6:
        dominante = "Profil Scientifique & Technique"
    elif lit_avg >= 13.0 and lit_avg > sci_avg + 0.6:
        dominante = "Profil Littéraire, Humain & Communication"
    elif (moyenne_gen or 0.0) >= 13.0:
        dominante = "Profil Équilibré & Polyvalent"
    else:
        dominante = "Profil Polyvalent en Construction"

    return {
        "success": True,
        "is_detected": detected,
        "moyenne_generale": moyenne_gen,
        "matieres": found_matieres,
        "points_forts": points_forts,
        "dominante": dominante,
        "classe_detectee": classe_detectee,
        "specialites_detectees": specialites_detectees or [],
        "lycee_detecte": lycee_detecte,
    }


_OCR_READER = None

def get_ocr_reader():
    global _OCR_READER
    if _OCR_READER is None:
        import sys
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
        import easyocr
        _OCR_READER = easyocr.Reader(['fr', 'en'], gpu=False, verbose=False)
    return _OCR_READER


def parse_bulletin_image(image_bytes: bytes) -> dict:
    reader = get_ocr_reader()
    results = reader.readtext(image_bytes)

    items = []
    for bbox, text, conf in results:
        text_clean = text.strip()
        if not text_clean:
            continue
        cy = (bbox[0][1] + bbox[2][1]) / 2.0
        cx = (bbox[0][0] + bbox[2][0]) / 2.0
        items.append({'y': cy, 'x': cx, 'text': text_clean})

    lines = []
    for item in sorted(items, key=lambda x: x['y']):
        placed = False
        for line in lines:
            if abs(line['y'] - item['y']) <= 14:
                line['items'].append(item)
                line['y'] = (line['y'] + item['y']) / 2.0
                placed = True
                break
        if not placed:
            lines.append({'y': item['y'], 'items': [item]})

    eleve_col_x = None
    for line in lines:
        for it in line['items']:
            t = it['text'].strip().lower()
            if (
                t in ('élève', 'eleve', 'moy.', 'moy', 'moyenne', 'moy. élève', 'moy eleve')
                or any(k in t for k in ['moy:', 'moy.', 'moy /20', 'moy/20', 'moyenne élève', 'moyenne eleve'])
            ) and not any(k in t for k in ['general', 'général', 'trimestri', 'classe', 'm.cl', 'm.ci']):
                eleve_col_x = it['x']
                break
        if eleve_col_x is not None:
            break

    found_matieres: Dict[str, float] = {}
    specialites_detectees: List[str] = []
    moyenne_gen = None

    sorted_lines = []
    for line in lines:
        l_items = sorted(line['items'], key=lambda x: x['x'])
        l_text = ' '.join([it['text'] for it in l_items])
        sorted_lines.append({'items': l_items, 'text': l_text, 'lower': l_text.lower()})

    full_ocr_text = "\n".join(l['text'] for l in sorted_lines)
    classe_detectee = _detect_classe_from_text(full_ocr_text)

    # Recherche prioritaire de la Moyenne générale de l'élève
    m_gen_match = re.search(
        r"moyenne\s+g[ée]n[ée]rale\s*[:=\-]?\s*(\d{1,2}[,\.]\d{1,2})",
        full_ocr_text.lower(),
    )
    if m_gen_match:
        try:
            val = float(m_gen_match.group(1).replace(",", "."))
            if 0.0 <= val <= 20.0:
                moyenne_gen = val
        except ValueError:
            pass

    for idx, line_obj in enumerate(sorted_lines):
        line_sorted = line_obj['items']
        line_text = line_obj['text']
        line_lower = line_obj['lower']

        if moyenne_gen is None and any(k in line_lower for k in ['moyenne générale', 'moyenne generale', 'moyenne du trimestre']):
            m_avg = re.findall(r'\b\d{1,2}[,\.]\d{1,2}\b', line_text)
            for cand in m_avg:
                try:
                    c_val = float(cand.replace(',', '.'))
                    if 0.0 <= c_val <= 20.0:
                        moyenne_gen = c_val
                        break
                except ValueError:
                    pass

        if any(k in line_lower for k in ['moyenne générale', 'moyenne generale']) or re.match(r'^\s*classe\s*:', line_lower):
            continue

        # Extraire les notes décimales de la ligne triées de gauche à droite (x croissant)
        candidates = []
        first_grade_x = None
        for it in line_sorted:
            clean_it = re.sub(r'\b(\d{1,2})\s+(\d{2})\b', r'\1.\2', it['text'].strip())
            if '/' in clean_it:
                continue
            nums = re.findall(r'\b\d{1,2}[,\.]\d{1,2}\b', clean_it)
            for n in nums:
                try:
                    val = float(n.replace(',', '.'))
                    if 0.0 <= val <= 20.0:
                        candidates.append((it['x'], val))
                        if first_grade_x is None or it['x'] < first_grade_x:
                            first_grade_x = it['x']
                except ValueError:
                    pass

        if not candidates:
            continue

        candidates.sort(key=lambda c: c[0])

        # Texte situé à gauche de la première note (intitulé de la matière)
        left_items = [it['text'] for it in line_sorted if first_grade_x is None or it['x'] < first_grade_x - 5]
        left_text = ' '.join(left_items).strip()

        # Contexte multi-lignes (si l'intitulé de matière est coupé sur la ligne précédente ou suivante sans notes)
        context_candidates = []
        if left_text:
            context_candidates.append(left_text)
            if idx + 1 < len(sorted_lines):
                next_l = sorted_lines[idx + 1]['text']
                if not re.search(r'\b\d{1,2}[,\.]\d{1,2}\b', next_l):
                    context_candidates.insert(0, f"{left_text} {next_l}")
            if idx - 1 >= 0:
                prev_l = sorted_lines[idx - 1]['text']
                if not re.search(r'\b\d{1,2}[,\.]\d{1,2}\b', prev_l):
                    context_candidates.append(f"{prev_l} {left_text}")
        else:
            prev_parts = []
            if idx - 2 >= 0 and not re.search(r'\b\d{1,2}[,\.]\d{1,2}\b', sorted_lines[idx - 2]['text']):
                prev_parts.append(sorted_lines[idx - 2]['text'])
            if idx - 1 >= 0 and not re.search(r'\b\d{1,2}[,\.]\d{1,2}\b', sorted_lines[idx - 1]['text']):
                prev_parts.append(sorted_lines[idx - 1]['text'])
            if prev_parts:
                context_candidates.append(" ".join(prev_parts))

        matched_subject = None
        matched_raw_label = ""
        for ctx_str in context_candidates:
            matched_subject = _match_canonical_subject(ctx_str, set(found_matieres.keys()))
            if matched_subject:
                matched_raw_label = ctx_str
                break

        if matched_subject:
            chosen_note = None
            if eleve_col_x is not None:
                close_candidates = [c for c in candidates if abs(c[0] - eleve_col_x) <= 55]
                if close_candidates:
                    close_candidates.sort(key=lambda c: abs(c[0] - eleve_col_x))
                    chosen_note = close_candidates[0][1]

            if chosen_note is None:
                # La 1re note à gauche est TOUJOURS la moyenne de l'Élève (jamais la dernière qui est Max)
                chosen_note = candidates[0][1]

            found_matieres[matched_subject] = chosen_note
            if "spécialité" in matched_raw_label.lower() or "specialite" in matched_raw_label.lower():
                if matched_subject not in specialites_detectees:
                    specialites_detectees.append(matched_subject)

    lycee_det = detect_lycee_from_text(text)
    return _compute_bulletin_summary(
        found_matieres=found_matieres,
        moyenne_gen=moyenne_gen,
        classe_detectee=classe_detectee,
        specialites_detectees=specialites_detectees,
        lycee_detecte=lycee_det,
    )


def parse_bulletin_text(text: str) -> dict:
    SKIP_PREFIXES = ['devoirs', 'travaux', 'khôlles', 'kholles', 'interrogations', 'interro', 'tp', 'ds']
    raw_lines = [l.strip() for l in (text or "").split("\n") if l.strip()]
    found_matieres: Dict[str, float] = {}
    specialites_detectees: List[str] = []
    moyenne_gen = None

    classe_detectee = _detect_classe_from_text(text)

    # 1. Extraction directe de la Moyenne générale de l'élève
    m_gen_match = re.search(
        r"moyenne\s+g[ée]n[ée]rale\s*[:=\-]?\s*(\d{1,2}[,\.]\d{1,2})",
        (text or "").lower(),
    )
    if m_gen_match:
        try:
            val = float(m_gen_match.group(1).replace(",", "."))
            if 0.0 <= val <= 20.0:
                moyenne_gen = val
        except ValueError:
            pass

    def _extract_decimal_grades(line_str: str) -> List[float]:
        # Séparer les notes collées (ex: "13,2012,00" -> "13,20 12,00") et ignorer "/20"
        cleaned = re.sub(r'(\d{1,2}[,\.]\d{2})(?=\d{1,2}[,\.])', r'\1 ', line_str)
        cleaned = re.sub(r'\d{1,2}\s*/\s*\d{1,2}', ' ', cleaned)
        matches = re.findall(r'\b\d{1,2}[,\.]\d{1,2}\b', cleaned)
        out = []
        for m in matches:
            try:
                v = float(m.replace(',', '.'))
                if 0.0 <= v <= 20.0:
                    out.append(v)
            except ValueError:
                pass
        return out

    consumed_header_lines = set()

    for idx, line in enumerate(raw_lines):
        line_lower = line.lower()

        # Si la moyenne générale n'a pas encore été trouvée
        if moyenne_gen is None and any(k in line_lower for k in ['moyenne générale', 'moyenne generale', 'moyenne du trimestre']):
            g_list = _extract_decimal_grades(line)
            if g_list:
                moyenne_gen = g_list[0]

        # Ignorer la ligne de moyenne générale ou "Classe : 12,1 / 20"
        if any(k in line_lower for k in ['moyenne générale', 'moyenne generale']) or re.match(r'^classe\s*:', line_lower):
            continue

        if any(line_lower.startswith(sp) for sp in SKIP_PREFIXES):
            continue

        grades = _extract_decimal_grades(line)
        if not grades:
            continue

        # Isoler le texte situé AVANT la toute première note de la ligne
        first_num_match = re.search(r'\b\d{1,2}[,\.]\d{1,2}\b', line)
        prefix = line[:first_num_match.start()].strip() if first_num_match else ""

        candidate_labels = []
        if prefix:
            # Si la ligne commence par l'intitulé de matière suivi des notes (ex: "Spécialité Mathématiques 13,2 12,0 5,5 18,5 ...")
            candidate_labels.append(prefix)
            if idx - 1 >= 0 and (idx - 1) not in consumed_header_lines and not _extract_decimal_grades(raw_lines[idx - 1]):
                candidate_labels.append(f"{raw_lines[idx - 1]} {prefix}")
        else:
            # La ligne commence directement par les notes (ex: "13,8 12,3 6,0 19,0 Bon trimestre...")
            # L'intitulé de matière se trouve sur les 1 ou 2 lignes précédentes (ex: "Spécialité Numérique et Sciences" + "Informatiques (NSI)")
            prev_1 = raw_lines[idx - 1] if (idx - 1 >= 0 and (idx - 1) not in consumed_header_lines and not _extract_decimal_grades(raw_lines[idx - 1])) else ""
            prev_2 = raw_lines[idx - 2] if (idx - 2 >= 0 and (idx - 2) not in consumed_header_lines and not _extract_decimal_grades(raw_lines[idx - 2])) else ""
            if prev_2 and prev_1:
                candidate_labels.append(f"{prev_2} {prev_1}")
            if prev_1:
                candidate_labels.append(prev_1)

        detected_subject = None
        matched_label_str = ""
        for cand_str in candidate_labels:
            detected_subject = _match_canonical_subject(cand_str, set(found_matieres.keys()))
            if detected_subject:
                matched_label_str = cand_str
                break

        if detected_subject and detected_subject not in found_matieres:
            # La PREMIÈRE note de la ligne (grades[0]) correspond à la colonne "Élève"
            # (les suivantes sont Classe, Min, Max).
            found_matieres[detected_subject] = grades[0]
            if not prefix:
                if idx - 1 >= 0:
                    consumed_header_lines.add(idx - 1)
                if idx - 2 >= 0:
                    consumed_header_lines.add(idx - 2)
            if "spécialité" in matched_label_str.lower() or "specialite" in matched_label_str.lower():
                if detected_subject not in specialites_detectees:
                    specialites_detectees.append(detected_subject)

    return _compute_bulletin_summary(
        found_matieres=found_matieres,
        moyenne_gen=moyenne_gen,
        classe_detectee=classe_detectee,
        specialites_detectees=specialites_detectees,
    )

SECTOR_KEYWORDS = {
    "Intelligence Artificielle & Data": ["ia", "intelligence artificielle", "data", "données", "machine learning", "algorithme", "python", "informatique", "statistiques", "big data", "logiciel", "développeur"],
    "Ingénierie, Robotique & Aéronautique": ["ingénieur", "robotique", "aéronautique", "mécanique", "électronique", "systèmes", "industrie", "spatial", "automatismes", "production", "maintenance", "bureau d'études", "si"],
    "Santé, Biomédical & Recherche": ["santé", "médical", "biologie", "bio", "médecine", "recherche", "soin", "hôpital", "pharmacie", "laboratoire", "thérapie", "biomédical"],
    "Design, Médias & Création Numérique": ["design", "ux", "ui", "graphisme", "création", "artistique", "multimédia", "jeux", "audiovisuel", "webdesign", "communication visuelle"],
    "Climat, Écologie & Énergie": ["environnement", "énergie", "écologie", "renouvelable", "climat", "durable", "agronomie", "transition", "eau", "déchets", "vert"],
    "Business, Finance & Entrepreneuriat": ["business", "finance", "gestion", "stratégie", "conseil", "management", "audit", "marketing", "direction", "banque", "commercial", "vente"],
    "Droit, Justice & Relations Internationales": ["droit", "juridique", "justice", "international", "avocat", "magistrat", "politique", "diplomatie", "notaire", "affaires publiques"],
}

def _infer_academic_context(profile: StudentProfile) -> dict:
    """Déduit le profil académique réel (littéraire, scientifique, éco, santé, art) depuis les spécialités et le bulletin."""
    specs = list(profile.specialites_choisies or (profile.bulletin.specialites if profile.bulletin else []) or [])
    specs_low = " ".join(s.lower() for s in specs)
    matieres = (profile.bulletin.matieres if profile.bulletin and profile.bulletin.matieres else {})
    dominante_low = (profile.bulletin.dominante.lower() if profile.bulletin and profile.bulletin.dominante else "")
    filiere_id = (profile.filiere_ambition_id or "").lower()

    lit_keys = [
        "Français", "Français-Philosophie", "Philosophie", "Histoire-Géographie",
        "HGGSP", "HLP", "LLCE", "Anglais", "Espagnol / LV2", "Littérature arabe",
        "Sciences islamiques", "Enseignement moral et civique (EMC)",
    ]
    sci_keys = [
        "Mathématiques", "Mathématiques expertes", "Mathématiques complémentaires",
        "Physique-Chimie", "Informatique / NSI", "Sciences Industrielles / SI",
        "Enseignement scientifique",
    ]
    lit_vals = [float(matieres[k]) for k in lit_keys if k in matieres]
    sci_vals = [float(matieres[k]) for k in sci_keys if k in matieres]
    lit_avg = (sum(lit_vals) / len(lit_vals)) if lit_vals else 0.0
    sci_avg = (sum(sci_vals) / len(sci_vals)) if sci_vals else 0.0
    bio_avg = float(matieres.get("SVT / Biologie", 0.0))
    eco_avg = float(matieres.get("SES / Économie", 0.0))
    art_avg = float(matieres.get("Art", matieres.get("Arts", 0.0)))

    has_math_phys_spec = any(
        k in specs_low for k in ["math", "physique", "chimie", "nsi", "informatique", "sciences industrielles", "ingénieur"]
    )
    has_lit_spec = any(
        k in specs_low for k in [
            "français", "francais", "histoire", "géographie", "geographie",
            "hggsp", "hlp", "llce", "philosophie", "littérature", "anglais", "espagnol", "langue",
        ]
    )
    has_art_spec = "art" in specs_low
    has_eco_spec = any(k in specs_low for k in ["ses", "économie", "economie"])
    has_bio_spec = any(k in specs_low for k in ["svt", "biologie"])

    is_literary = (
        filiere_id == "sciences_po_bl_droit"
        or "littéraire" in dominante_low
        or "litteraire" in dominante_low
        or (has_lit_spec and not has_math_phys_spec)
        or (not specs and lit_avg > 0 and lit_avg >= sci_avg + 0.4)
    )
    is_art = (
        filiere_id == "ensa_archi_gobelins"
        or (has_art_spec and not has_math_phys_spec and not has_lit_spec)
    )
    is_eco = (
        filiere_id == "cpge_ecg_commerce"
        or "économique" in dominante_low
        or (has_eco_spec and not has_math_phys_spec)
        or (not specs and eco_avg >= 13.5 and eco_avg > sci_avg)
    )
    is_health = (
        filiere_id == "pass_las_medecine"
        or (has_bio_spec and not ("math" in specs_low and ("nsi" in specs_low or "informatique" in specs_low)))
        or (not specs and bio_avg >= 14.0 and bio_avg >= sci_avg)
    )

    return {
        "specs": specs,
        "specs_low": specs_low,
        "matieres": matieres,
        "dominante": profile.bulletin.dominante if profile.bulletin else None,
        "lit_avg": lit_avg,
        "sci_avg": sci_avg,
        "bio_avg": bio_avg,
        "eco_avg": eco_avg,
        "art_avg": art_avg,
        "has_math_phys_spec": has_math_phys_spec,
        "has_lit_spec": has_lit_spec,
        "has_art_spec": has_art_spec,
        "has_eco_spec": has_eco_spec,
        "has_bio_spec": has_bio_spec,
        "is_literary": is_literary,
        "is_art": is_art,
        "is_eco": is_eco,
        "is_health": is_health,
    }


def get_top_metiers(profile: StudentProfile, limit: int = 3) -> list:
    try:
        metiers = load_metiers_data()
        if not metiers:
            return []

        acad_ctx = _infer_academic_context(profile)
        secteurs_choisis = [s.strip() for s in (profile.secteurs_souhaits or []) if s.strip()]
        inferred_sector_label = None

        # Si l'élève n'a pas coché manuellement de secteur dans l'onglet 2,
        # on déduit automatiquement ses secteurs cibles à partir de son profil scolaire (bulletin & spécialités) !
        if not secteurs_choisis:
            if acad_ctx["is_literary"]:
                secteurs_choisis = [
                    "Lettres, Journalisme, Droit & Sciences Humaines",
                    "Droit, Justice & Relations Internationales",
                ]
                inferred_sector_label = "Profil Littéraire, Droit, Journalisme & Sciences Humaines"
            elif acad_ctx["is_art"]:
                secteurs_choisis = ["Design, Médias & Création Numérique"]
                inferred_sector_label = "Profil Création, Design & Architecture"
            elif acad_ctx["is_eco"]:
                secteurs_choisis = ["Business, Finance & Entrepreneuriat"]
                inferred_sector_label = "Profil Économique, Management & Finance"
            elif acad_ctx["is_health"]:
                secteurs_choisis = ["Santé, Médecine & Soins"]
                inferred_sector_label = "Profil Santé, Biologie & Soins"
            else:
                if "nsi" in acad_ctx["specs_low"] or "informatique" in acad_ctx["specs_low"]:
                    secteurs_choisis = ["Intelligence Artificielle & Data", "Ingénierie, Robotique & Aéronautique"]
                else:
                    secteurs_choisis = ["Ingénierie, Robotique & Aéronautique", "Intelligence Artificielle & Data"]
                inferred_sector_label = "Profil Scientifique, Ingénierie & Tech"

        role_vise = (profile.role_vise or "").strip()
        environnement_prefere = (profile.environnement_prefere or "").strip()

        # =====================================================================
        # ÉTAPE 1 : FILTRE ÉLIMINATOIRE PAR SECTEUR CIBLE / PROFIL SCOLAIRE
        # =====================================================================
        pool = []
        if secteurs_choisis:
            for m in metiers:
                code = (m.get("code_rome") or "").upper()
                doms = [str(d).lower() for d in m.get("domaines", [])]
                nom = m.get("nom", "").lower()
                missions = " ".join([str(x).lower() for x in m.get("missions", [])])
                full = f"{nom} {' '.join(doms)} {missions}"

                match_any_sector = False
                for sec in secteurs_choisis:
                    s_low = sec.lower()
                    if any(k in s_low for k in ["lettres", "littéraire", "journalisme", "sciences humaines"]):
                        # Exclure strictement les métiers d'ingénierie, robotique, IT, artisanat, BTP, médecine, finance comptable
                        stem_or_manual_banned = [
                            "ingénieur", "ingenieur", "robot", "mécatronique", "mecatronique", "drone",
                            "automatisme", "informatique", "data", "développeur", "developpeur", "cyber",
                            "machine learning", "logiciel", "programmeur", "électricien", "mécanicien",
                            "plombier", "menuisier", "boulanger", "pâtissier", "cuisinier", "agriculteur",
                            "sylviculteur", "bûcheron", "jardinier", "logistique", "sécurité", "pompier",
                            "policier", "pilote", "contrôleur aérien", "technicien", "infirmier", "kiné",
                            "médecin", "chirurgien", "pharmacien", "vétérinaire", "sage-femme", "comptable",
                            "commercial", "marketing digital", "growth marketer", "coach sportif", "game designer",
                            "ux designer", "animateur 3d", "monteur vidéo", "sound designer",
                        ]
                        if any(b in nom for b in stem_or_manual_banned):
                            continue
                        if any(k in d for d in doms for k in ["robotique", "mécatronique", "informatique", "bâtiment", "agriculture", "industrie", "logistique", "maintenance"]):
                            continue
                        if (
                            any(k in nom for k in [
                                "avocat", "journaliste", "scénariste", "auteur", "écrivain", "traducteur",
                                "interprète", "professeur", "enseignant", "juriste", "magistrat", "notaire",
                                "rédacteur", "éditeur", "conservateur", "médiateur culturel", "psychologue",
                                "assistant juridique", "diplomate", "sociologue", "historien",
                            ])
                            or (acad_ctx["has_art_spec"] and any(k in nom for k in ["architecte", "graphiste"]))
                            or code.startswith("K19")
                            or code in ["E1104", "E1105", "E1106", "E1108", "K1602", "K2107"]
                        ):
                            match_any_sector = True
                            break
                    elif "santé" in s_low or "médecine" in s_low or "médic" in s_low or "soin" in s_low or "biomédical" in s_low:
                        is_excluded = any(k in nom for k in ["toiletteur", "maréchal-ferrant", "coach", "sportif", "fitness", "musculation", "animal", "animaux", "vétérinaire", "équin", "insémination", "sécurité sociale", "agricole"])
                        if not is_excluded:
                            if (code.startswith("J") or 
                                any(k in nom for k in ["médecin", "chirurgien", "infirmier", "kiné", "dentiste", "pharmacien", "urgentiste", "pédiatre", "cardiologue", "sage-femme", "psychologue", "biologiste", "radiologue", "anesthésiste", "neurologue", "orthophoniste", "soignant", "ergothérapeute", "manipulateur", "ambulancier", "thérapeute", "puéricult"]) or
                                (any(k in d for d in doms for k in ["médecine", "médic", "soin", "pharmacie", "biomédical", "santé"]) and not any(k in doms for k in ["sport", "animaux", "elevage"]))):
                                match_any_sector = True
                                break
                    elif "ia" in s_low or "data" in s_low or "intelligence artificielle" in s_low:
                        if any(k in nom for k in ["commercial", "vente", "coutur", "brasseur", "boulang", "boucher", "coiff", "secrétaire"]):
                            continue
                        if any(k in doms for k in ["commerce et distribution", "industrie - alimentaire", "industrie - textile et mode", "artisanat"]):
                            continue
                        if (code.startswith("M18") or code.startswith("M1403") or
                            any(k in doms for k in ["intelligence artificielle", "data", "big data", "informatique", "logiciel", "cybersécurité"]) or
                            any(k in nom for k in ["intelligence artificielle", "data scientist", "data engineer", "data analyst", "développeur", "developpeur", "architecte cloud", "cybersécurité", "logiciel", "programmeur"]) or
                            any(re.search(r'\b' + re.escape(w) + r'\b', nom, re.IGNORECASE) for w in ["ia", "ai", "data", "algorithme", "machine learning", "deep learning"])):
                            match_any_sector = True
                            break
                    elif "ingénierie" in s_low or "robotique" in s_low or "aéronautique" in s_low:
                        if any(k in nom for k in ["coutur", "brasseur", "boulang", "boucher", "coiff", "tailleur", "textile", "habillement", "chaussure", "menuisier"]):
                            continue
                        if any(k in doms for k in ["commerce et distribution", "industrie - alimentaire", "industrie - textile et mode", "artisanat"]):
                            continue
                        if code in ["H1206", "I1302", "I1304", "I1305", "H1401", "H1402", "H1201", "H1202", "H1203", "H1204", "H1205", "H1207", "H1208", "H1209", "H1210"]:
                            match_any_sector = True
                            break
                        if (any(k in d for d in doms for k in ["robotique", "mécatronique", "aéronautique", "aérospatial", "électronique", "ingénierie", "automatismes"]) or
                            any(k in nom for k in ["ingénieur", "ingenieur", "robotique", "robot", "mécatronique", "mecatronique", "aéronautique", "aeronautique", "aérospatial", "aerospatial", "drones", "drone", "automatisme", "avionique", "systèmes embarqués", "systemes embarques", "spatial"])):
                            match_any_sector = True
                            break
                    elif "design" in s_low or "média" in s_low or "création" in s_low:
                        if (code.startswith("E") or code.startswith("L") or
                            any(k in d for d in doms for k in ["design", "art", "graphisme", "création", "multimédia", "audiovisuel"]) or
                            any(k in nom for k in ["designer", "graphiste", "ux", "ui", "illustrateur", "animateur", "créateur", "artiste", "architecte", "scénariste"])):
                            match_any_sector = True
                            break
                    elif "climat" in s_low or "écologie" in s_low or "énergie" in s_low:
                        if (code.startswith("A12") or
                            any(k in d for d in doms for k in ["environnement", "écologie", "énergie", "climat", "nature", "forêt", "durable", "biodiversité", "transition"]) or
                            any(k in nom for k in ["écologue", "climatologue", "énergie", "environnement", "renouvelable", "biodiversité", "forestier"])):
                            match_any_sector = True
                            break
                    elif "business" in s_low or "finance" in s_low or "entrepreneuriat" in s_low:
                        if (code.startswith("C") or code.startswith("D14") or code.startswith("M12") or code.startswith("M14") or code.startswith("M17") or
                            any(k in d for d in doms for k in ["finance", "gestion", "management", "banque", "commerce", "marketing"]) or
                            any(k in nom for k in ["directeur", "manager", "auditeur", "financier", "banquier", "commercial", "trader", "gestion", "comptable", "marketing"])):
                            match_any_sector = True
                            break
                    elif "droit" in s_low or "justice" in s_low:
                        if (code.startswith("K19") or
                            any(k in d for d in doms for k in ["droit", "justice", "juridique"]) or
                            any(k in nom for k in ["avocat", "juge", "magistrat", "juriste", "notaire", "greffier", "assistant juridique"])):
                            match_any_sector = True
                            break
                    else:
                        kw_list = SECTOR_KEYWORDS.get(sec, [sec.lower()])
                        if any(kw in full for kw in kw_list):
                            match_any_sector = True
                            break

                if match_any_sector:
                    pool.append(m)
        else:
            pool = list(metiers)

        if not pool:
            pool = list(metiers)

        # =====================================================================
        # ÉTAPE 2 : FILTRE / AFFINEMENT PAR "COMMENT TE VOIS-TU AGIR" (RÔLE)
        # =====================================================================
        if role_vise and pool:
            rv = role_vise.lower()
            role_filtered = []
            for m in pool:
                nom = m.get("nom", "").lower()
                missions = " ".join([str(x).lower() for x in m.get("missions", [])])
                full = f"{nom} {missions}"

                if "aide" in rv or "santé" in rv or "soin" in rv:
                    if any(k in full for k in ["soigner", "soin", "patient", "diagnostique", "thérapie", "traitement", "maladie", "médical", "consultation", "aide", "santé", "relationnel", "clinique", "médicaments", "ordonnance", "accompagner", "enseigner", "défendre"]):
                        role_filtered.append(m)
                elif "expertise" in rv or "technique" in rv or "r&d" in rv:
                    if any(k in full for k in ["concevoir", "conception", "développer", "developper", "programmer", "analyser", "recherche", "r&d", "algorithme", "prototype", "modéliser", "architecture", "technique", "spécialiste", "ingénierie", "rédiger", "expertise", "juridique"]):
                        if not any(k in nom for k in ["commercial", "vente", "magasin", "rayon"]):
                            role_filtered.append(m)
                elif "management" in rv or "leadership" in rv:
                    if any(k in full for k in ["responsable", "chef", "manager", "directeur", "diriger", "coordonnateur", "encadrement", "gestion", "piloter", "conduite de projet", "plaider", "défendre"]):
                        role_filtered.append(m)
                elif "création" in rv or "design" in rv:
                    if any(k in full for k in ["créer", "imaginer", "conception", "design", "artistique", "visuel", "inventer", "graphisme", "esthétique", "écrire", "scénario", "rédiger"]):
                        role_filtered.append(m)

            if len(role_filtered) >= limit:
                pool = role_filtered

        # =====================================================================
        # ÉTAPE 3 : FILTRE / AFFINEMENT PAR "LE CADRE DE TRAVAIL"
        # =====================================================================
        if environnement_prefere and pool:
            c_low = environnement_prefere.lower()
            cadre_filtered = []
            for m in pool:
                nom = m.get("nom", "").lower()
                missions = " ".join([str(x).lower() for x in m.get("missions", [])])
                env = m.get("environnement", {})
                lieu = str(env.get("lieu", "")).lower()
                teletravail = env.get("teletravail", False)
                code = (m.get("code_rome") or "").upper()
                full = f"{nom} {missions} {lieu}"

                if "hôpital" in c_low or "médical" in c_low:
                    if any(k in full for k in ["hôpital", "hopital", "clinique", "médical", "cabinet", "urgences", "soin", "patient", "consultation", "maternité"]):
                        cadre_filtered.append(m)
                elif "bureau" in c_low or "start-up" in c_low:
                    is_bureau = (
                        teletravail in [True, "partiel", "total", "possible"] or
                        code.startswith("M18") or code.startswith("M14") or code.startswith("C") or code.startswith("E") or code.startswith("K19") or
                        any(k in lieu for k in ["bureau", "startup", "start-up", "tech", "agence", "siège", "labo", "r&d", "centre d innovation", "entreprise tech", "open-space", "cabinet", "rédaction"]) or
                        any(k in nom for k in ["data", "ia", "logiciel", "développeur", "ingénieur", "analyste", "avocat", "journaliste", "traducteur", "scénariste", "architecte"]) or
                        any(k in missions for k in ["bureau", "ordinateur", "logiciel", "données", "conception", "rédiger", "plaider"])
                    )
                    if is_bureau:
                        cadre_filtered.append(m)
                elif "labo" in c_low or "atelier" in c_low:
                    if any(k in full for k in ["laboratoire", "atelier", "recherche", "salle blanche", "analyse", "paillasse", "centre de recherche", "studio"]):
                        cadre_filtered.append(m)
                elif "terrain" in c_low or "extérieur" in c_low:
                    if any(k in full for k in ["terrain", "extérieur", "déplacement", "nature", "chantier", "visite", "intervention", "reportage"]):
                        cadre_filtered.append(m)

            if len(cadre_filtered) >= limit:
                pool = cadre_filtered

        # =====================================================================
        # ÉTAPE 4 : CLASSEMENT FINAL PAR PROFIL ACADÉMIQUE, SPÉCIALITÉS & RIASEC
        # =====================================================================
        scored_candidates = []
        user_skills = {
            "creativite": getattr(profile, "creativite", 0) or 0,
            "empathie": getattr(profile, "empathie", 0) or 0,
            "communication": getattr(profile, "communication", 0) or 0,
            "organisation": getattr(profile, "organisation", 0) or 0,
            "logique": getattr(profile, "logique", 0) or 0,
        }
        has_personality = any(v > 0 for v in user_skills.values())

        bulletin = profile.bulletin
        b_moyenne = bulletin.moyenne_generale if (bulletin and bulletin.moyenne_generale) else None
        matieres = acad_ctx["matieres"]
        specs = acad_ctx["specs"]

        for m in pool:
            sk = m.get("soft_skills", {})
            if has_personality:
                dist = (
                    abs(user_skills["creativite"] - sk.get("creativite", 5)) +
                    abs(user_skills["empathie"] - sk.get("empathie", 5)) +
                    abs(user_skills["communication"] - sk.get("communication", 5)) +
                    abs(user_skills["organisation"] - sk.get("organisation", 5)) +
                    abs(user_skills["logique"] - sk.get("logique", 5))
                )
                soft_score = max(75.0, 98.0 - (dist / 25.0) * 15.0)
            else:
                dist = 0.0
                soft_score = 92.0

            thematic_priority = 0.0
            nom_low = m.get("nom", "").lower()
            doms_low = " ".join(str(d).lower() for d in m.get("domaines", []))
            c_rome = (m.get("code_rome") or "").upper()

            # Bonus pour les fiches complètes enrichies (avec salaire, études et journée type)
            if m.get("journee_type") and m.get("salaire"):
                thematic_priority += 3.0

            # 1. Alignement Littéraire / Sciences Humaines / Droit / Langues / Arts
            if acad_ctx["is_literary"] or any(k in s.lower() for s in secteurs_choisis for k in ["lettres", "littéraire", "journalisme", "droit", "justice"]):
                note_fr = float(matieres.get("Français", matieres.get("Français-Philosophie", 14.0)))
                note_hg = float(matieres.get("Histoire-Géographie", matieres.get("HGGSP", 14.0)))
                note_philo = float(matieres.get("Philosophie", matieres.get("HLP", note_fr)))
                note_lang = max(
                    float(matieres.get("Anglais", 13.5)),
                    float(matieres.get("Espagnol / LV2", 13.5)),
                )
                if "avocat" in nom_low or "magistrat" in nom_low or "juriste" in nom_low:
                    thematic_priority += 16.0 + (note_fr + note_hg + note_philo) / 6.0
                elif "journaliste" in nom_low:
                    thematic_priority += 15.5 + (note_fr + note_hg + note_lang) / 6.0
                elif "scénariste" in nom_low or "auteur" in nom_low or "écrivain" in nom_low:
                    thematic_priority += 14.5 + (note_fr + note_philo) / 4.0 + (2.5 if acad_ctx["has_art_spec"] else 0.0)
                elif "traducteur" in nom_low or "interprète" in nom_low:
                    thematic_priority += 14.0 + (note_lang + note_fr) / 4.0
                elif "professeur" in nom_low or "enseignant" in nom_low:
                    thematic_priority += 13.5 + (note_fr + note_hg) / 4.5
                elif acad_ctx["has_art_spec"] and ("architecte" in nom_low or "graphiste" in nom_low):
                    thematic_priority += 14.2 + float(matieres.get("Art", 14.0)) / 3.0
                elif "assistant juridique" in nom_low or "psychologue" in nom_low:
                    thematic_priority += 10.0

            # 2. Alignement Design / Architecture / Création
            if acad_ctx["is_art"] or any(k in s.lower() for s in secteurs_choisis for k in ["design", "média", "création"]):
                if any(k in nom_low for k in ["architecte", "graphiste", "ux designer", "game designer", "animateur 3d", "scénariste"]):
                    thematic_priority += 14.0

            # 3. Alignement Économie / Commerce / Finance
            if acad_ctx["is_eco"] or any(k in s.lower() for s in secteurs_choisis for k in ["business", "finance", "entrepreneuriat"]):
                if any(k in nom_low for k in ["comptable", "financier", "commercial", "business developer", "marketing", "manager", "auditeur"]):
                    thematic_priority += 14.0

            # 4. Alignement Santé / Médecine
            if acad_ctx["is_health"] or any("médecine" in s.lower() or "santé" in s.lower() for s in secteurs_choisis):
                if c_rome.startswith("J11") or any(k in nom_low for k in ["médecin", "chirurgien", "dentiste", "pharmacien", "sage-femme", "kinésithérapeute"]):
                    thematic_priority += 15.0
                elif c_rome.startswith("J") or "infirmier" in nom_low or "chercheur en biologie" in nom_low:
                    thematic_priority += 11.0

            # 5. Alignement IA, Data, Robotique & Ingénierie (uniquement si profil/secteur scientifique)
            if not acad_ctx["is_literary"] and any(k in s.lower() for s in secteurs_choisis for k in ["ia", "data", "robotique", "ingénierie", "aéronautique"]):
                if any(k in nom_low for k in ["ingénieur ia", "data scientist", "machine learning", "ingénieur / ingénieure en robotique", "mécatronique", "ingénieur de recherche"]):
                    thematic_priority += 8.0
                elif any(k in nom_low for k in ["data", "robotique", "aéronautique", "drones", "automatisme", "développeur", "ingénieur"]):
                    thematic_priority += 4.0
                if c_rome in ["H1206", "I1302", "M1805", "M1802"]:
                    thematic_priority += 2.0

            academic_bonus = min(6.0, thematic_priority * 0.25)
            if b_moyenne and b_moyenne >= 14.0:
                academic_bonus += 1.5

            final_compatibilite = max(75, min(99, int(round(soft_score + academic_bonus))))

            m_copy = dict(m)
            m_copy["compatibilite"] = final_compatibilite
            m_copy["description"] = _build_metier_description(m)

            feedbacks = []
            if profile.secteurs_souhaits:
                feedbacks.append(f"Vœu : {profile.secteurs_souhaits[0]}")
            elif inferred_sector_label:
                feedbacks.append(inferred_sector_label)
            if specs:
                feedbacks.append(f"Spécialités : {', '.join(specs[:3])}")
            elif acad_ctx["dominante"]:
                feedbacks.append(str(acad_ctx["dominante"]))
            if role_vise:
                feedbacks.append(f"Action : {role_vise}")
            if environnement_prefere:
                feedbacks.append(f"Cadre : {environnement_prefere}")
            if (
                profile.mbti_archetype
                and not profile.mbti_archetype.startswith("Test non")
                and "non complété" not in profile.mbti_archetype.lower()
            ):
                feedbacks.append(profile.mbti_archetype)

            if feedbacks:
                m_copy["bulletin_feedback"] = " • ".join(feedbacks)

            scored_candidates.append({
                "meta": m_copy,
                "score": final_compatibilite + thematic_priority + (1.0 / (dist + 0.1))
            })

        scored_candidates.sort(key=lambda x: x["score"], reverse=True)
        return scored_candidates[:limit]
    except Exception as e:
        print(f"Erreur lors du calcul du Top Métiers: {e}")
        return []

DOMAIN_INTENTS = {
    "robotique": {
        "keywords": ["robot", "robotique", "mécatronique", "mecatronique", "automate", "automatisme", "cobotique", "drone", "drones"],
        "display": "la robotique et la mécatronique",
    },
    "aéronautique": {
        "keywords": ["aéro", "aéronautique", "aeronautique", "aviation", "avion", "avions", "pilote", "aérospatial", "aerospatial", "espace", "astronaute"],
        "display": "l'aéronautique et l'espace",
    },
    "jeux vidéo": {
        "keywords": ["jeux vidéo", "jeux video", "jeu vidéo", "jeu video", "gaming", "game design", "jeux videos"],
        "display": "l'industrie des jeux vidéo",
    },
    "santé": {
        "keywords": ["santé", "sante", "médical", "medical", "soin", "soins", "soigner", "infirmier", "infirmière", "infirmiere", "médecin", "medecin", "docteur", "kiné", "kine", "hôpital", "hopital"],
        "display": "la santé et les soins",
    },
    "animaux": {
        "keywords": ["animal", "animaux", "vétérinaire", "veterinaire", "faune", "soigneur", "élevage", "elevage", "refuge"],
        "display": "le contact avec les animaux",
    },
    "sport": {
        "keywords": ["sport", "sportif", "fitness", "coaching", "entraîneur", "entraineur", "musculation", "athlète", "athlete"],
        "display": "le sport et l'entraînement",
    },
    "art & création": {
        "keywords": ["art", "artistique", "créatif", "creatif", "dessin", "graphisme", "graphiste", "illustration", "photo", "photographe", "cinéma", "cinema", "audiovisuel", "musique"],
        "display": "la création artistique et le design",
    },
    "droit & justice": {
        "keywords": ["droit", "justice", "juridique", "avocat", "juge", "loi", "notaire", "juriste"],
        "display": "le droit et la justice",
    },
    "nature & écologie": {
        "keywords": ["nature", "environnement", "écologie", "ecologie", "forêt", "foret", "climat", "plante", "biodiversité", "biodiversite"],
        "display": "l'environnement et la nature",
    },
    "bâtiment & architecture": {
        "keywords": ["bâtiment", "batiment", "architecture", "architecte", "btp", "construction", "chantier"],
        "display": "l'architecture et la construction",
    },
    "commerce & finance": {
        "keywords": ["commerce", "commercial", "vente", "marketing", "business", "finance", "banque", "banquier", "comptable"],
        "display": "le commerce et la gestion",
    },
    "sécurité & défense": {
        "keywords": ["sécurité", "securite", "police", "gendarmerie", "armée", "armee", "pompier", "pompiers", "défense", "defense"],
        "display": "la sécurité et la protection",
    },
    "cuisine & restauration": {
        "keywords": ["cuisine", "restauration", "pâtisserie", "patisserie", "gastronomie", "cuisinier", "chef", "boulangerie", "boulanger"],
        "display": "la cuisine et la gastronomie",
    },
    "social & éducation": {
        "keywords": ["social", "éducateur", "educateur", "professeur", "enseignant", "enseignement", "enfant", "enfants", "aide sociale"],
        "display": "le social et l'enseignement",
    },
    "sciences & recherche": {
        "keywords": ["science", "sciences", "recherche", "chercheur", "laboratoire", "chimie", "physique", "biologie", "scientifique"],
        "display": "les sciences et la recherche",
    },
    "informatique & cyber": {
        "keywords": ["informatique", "code", "coder", "programmeur", "développeur", "developpeur", "cyber", "cybersécurité", "cybersecurite", "ia", "intelligence artificielle", "logiciel", "données", "data"],
        "display": "l'informatique et les technologies",
    }
}

def detect_domain_intent(text: str):
    import re
    t = text.lower()
    neg_pattern = r"(?:pas\s+de\s+|pas\s+d['’]\s*|déteste\s+|deteste\s+|eviter\s+|éviter\s+|aucun\s+|refuse\s+|surtout\s+pas\s+)([a-zà-ÿ0-9\s]{1,30})"
    neg_matches = re.findall(neg_pattern, t)
    neg_substrings = [m.strip() for m in neg_matches]

    best_match = None
    best_score = 0
    for dom_key, dom_data in DOMAIN_INTENTS.items():
        score = 0
        for kw in dom_data['keywords']:
            if kw in t:
                is_negated = any(kw in neg_s for neg_s in neg_substrings)
                if is_negated:
                    score -= 100
                else:
                    score += 10 if len(kw) > 5 else 6
        if score > 0 and score > best_score:
            best_score = score
            best_match = (dom_key, dom_data['display'])
    return best_match

@router.post("/debate")
def debate_recommendation(req: DebateRequest):
    import re
    nom = req.metier_nom
    obj = req.objection.lower().strip()
    profile = req.profile
    history = req.history or []

    b_matieres = profile.bulletin.matieres if (profile and profile.bulletin) else {}
    b_moy = profile.bulletin.moyenne_generale if (profile and profile.bulletin) else None

    metiers = load_metiers_data()

    def clean_title(title: str) -> str:
        t = re.sub(r'\(\s*[hHfF]\s*/\s*[hHfF]\s*\)', '', title or '')
        t = re.sub(r'([A-Za-zÀ-ÿ]+)\s*/\s*([A-Za-zÀ-ÿ]+)', r'\1', t)
        return t.strip()

    # Détection d'une intention thématique ou sectorielle explicite
    domain_match = detect_domain_intent(obj)

    # Identifier les métiers déjà évoqués ou rejetés dans l'historique
    rejected_metier_names = {nom.lower(), clean_title(nom).lower()}
    previous_history = history[:-1] if (history and history[-1].role == "user" and history[-1].text.strip().lower() == obj) else history
    for h in previous_history:
        h_text = h.text.lower()
        for m in metiers:
            m_name = m.get("nom", "").lower()
            m_clean = clean_title(m_name).lower()
            if h.role == "assistant":
                # Éviter de reproposer immédiatement un métier déjà suggéré par Nova
                if (m_name in h_text or m_clean in h_text) and not (m_name in obj or m_clean in obj):
                    rejected_metier_names.add(m_name)
                    rejected_metier_names.add(m_clean)
            elif h.role == "user":
                if any(neg in h_text for neg in ["pas", "déteste", "deteste", "refuse", "non", "aucun", "jamais"]):
                    if m_name in h_text or m_clean in h_text:
                        rejected_metier_names.add(m_name)
                        rejected_metier_names.add(m_clean)

    # Détecter toutes les contraintes exprimées au fil de la discussion
    combined_user_text = " ".join([h.text.lower() for h in history if h.role == "user"] + [obj])

    dislikes_screen = any(w in combined_user_text for w in [
        "écran", "ecran", "ordinateur", "assis", "bureau", "statique",
        "code", "coder", "programmeur", "informatique", "web", "développeur",
        "developpeur", "tech", "digital", "ux", "ui", "réseau", "reseau"
    ])
    dislikes_sales = any(w in combined_user_text for w in ["vente", "commercial", "vendre", "démarchage", "client", "négociation", "negociation"])
    dislikes_physical = any(w in combined_user_text for w in ["physique", "chantier", "porter", "sale", "fatigant", "bâtiment", "batiment", "dur", "manuel"])
    dislikes_long_studies = any(w in combined_user_text for w in ["études", "etudes", "long", "prépa", "prepa", "bac+5", "sélection", "selection", "doctorat"])
    dislikes_stress = any(w in combined_user_text for w in ["stress", "pression", "charge", "horaires", "fatigue", "nuit", "garde"])
    dislikes_math = any(w in combined_user_text for w in ["math", "maths", "chiffre", "chiffres", "calcul", "8/20", "note"])
    wants_human = any(w in combined_user_text for w in ["humain", "social", "contact", "aider", "gens", "équipe", "equipe", "échanger", "echanger", "santé", "medical"])
    wants_creative = any(w in combined_user_text for w in ["créatif", "creatif", "dessin", "art", "imaginer", "créer", "creer", "concevoir", "photo"])
    wants_terrain = any(w in combined_user_text for w in ["terrain", "voyager", "bouger", "extérieur", "exterieur", "visite", "nature", "animal", "animaux", "forêt", "sport"])

    # Filtrer et scorer les alternatives pertinentes dans le catalogue ROME
    alternatives = []
    candidates = []

    screen_banned = [
        "écran", "ecran", "ordinateur", "développeur", "developpeur", "programmeur",
        "informatique", "web", "réseau", "reseau", "système", "systeme", "ux", "ui",
        "logiciel", "données", "data", "cyber", "numérique", "numerique", "télécom", "telecom"
    ]

    for m in metiers:
        m_nom = m.get("nom", "")
        if m_nom.lower() in rejected_metier_names or clean_title(m_nom).lower() in rejected_metier_names:
            continue
        
        m_env = " ".join([str(x).lower() for x in m.get("environnements", [])])
        m_miss = " ".join([str(x).lower() for x in m.get("missions", [])])
        m_dom = " ".join([str(x).lower() for x in m.get("domaines", [])])
        m_full = f"{m_nom.lower()} {m_dom} {m_env} {m_miss}"

        # Éliminer si enfreint les contraintes de l'élève (sauf si l'élève demande explicitement ce secteur)
        if not domain_match:
            if dislikes_screen and any(k in m_full for k in screen_banned):
                continue
            if dislikes_sales and any(k in m_full for k in ["prospection", "démarchage commercial", "vendre des contrats", "téléconseiller"]):
                continue
            if dislikes_physical and any(k in m_full for k in ["gros œuvre", "chantier btp", "manutention lourde"]):
                continue
            if dislikes_math and any(k in m_full for k in ["analyse financière", "statistiques", "actuariat", "comptable", "audit", "ingénieur", "ingenieur"]):
                continue

        score = 80
        if domain_match:
            dom_key, dom_display = domain_match
            dom_kws = DOMAIN_INTENTS[dom_key]["keywords"]
            if any(k in m_nom.lower() for k in dom_kws):
                score += 300
            elif any(k in m_dom for k in dom_kws):
                score += 200
            elif any(k in m_miss for k in dom_kws):
                score += 100
        else:
            if wants_human and any(k in m_full for k in ["équipe", "patient", "client", "public", "accompagnement", "conseil", "soin"]):
                score += 20
            if wants_creative and any(k in m_full for k in ["création", "conception", "design", "projet", "communication", "photo"]):
                score += 20
            if wants_terrain and any(k in m_full for k in ["extérieur", "terrain", "déplacement", "visite", "sport", "nature", "forêt", "animal"]):
                score += 20
            if dislikes_long_studies and any(k in m_nom.lower() for k in ["technicien", "chargé", "assistant", "coordinateur"]):
                score += 10

        candidates.append((score, m))

    candidates.sort(key=lambda x: x[0], reverse=True)
    for _, m in candidates[:2]:
        m_copy = dict(m)
        m_copy["compatibilite"] = 94 if domain_match else 92
        m_copy["description"] = _build_metier_description(m)
        m_copy["bulletin_feedback"] = f"Piste ciblée dans {domain_match[1]}" if domain_match else "Pivot personnalisé suite à votre échange"
        alternatives.append(m_copy)

    # Si la recherche est trop restrictive, ajouter des alternatives variées
    if len(alternatives) < 2:
        for m in metiers:
            m_nom = m.get("nom", "")
            m_full = f"{m_nom.lower()} {' '.join(m.get('missions', []))}".lower()
            if m_nom.lower() in rejected_metier_names or clean_title(m_nom).lower() in rejected_metier_names:
                continue
            if not domain_match and dislikes_screen and any(k in m_full for k in screen_banned):
                continue
            m_copy = dict(m)
            m_copy["compatibilite"] = 89
            m_copy["description"] = _build_metier_description(m)
            m_copy["bulletin_feedback"] = "Alternative adaptée à tes retours"
            alternatives.append(m_copy)
            if len(alternatives) >= 2:
                break

    spoken_nom = clean_title(nom)
    spoken_alts = [clean_title(a.get("nom", "")) for a in alternatives]
    alt_1 = spoken_alts[0] if spoken_alts else "une autre voie"
    alt_2 = spoken_alts[1] if len(spoken_alts) > 1 else ""
    alt_phrase = f"{alt_1} ou {alt_2}" if alt_2 else alt_1

    # Construction de l'historique récent pour le contexte LLM
    history_lines = []
    for h in history[-4:]:
        r_name = "Élève" if h.role == "user" else "Nova"
        history_lines.append(f"{r_name}: {h.text}")
    dialogue_str = "\n".join(history_lines) if history_lines else f"Élève: {obj}"

    # Appel au LLM local (Qwen 2.5 3B via Ollama) pour une réponse 100% conversationnelle et vivante
    system_prompt = (
        "Tu es Nova, mentor d'orientation humaine et bienveillante. "
        "Réponds oralement en 2 phrases naturelles, directes et chaleureuses en français, sans aucun émoji."
    )

    if domain_match:
        dom_key, dom_display = domain_match
        user_prompt = (
            f"L'élève te demande précisément des métiers dans le domaine de {dom_display} (sa demande : « {req.objection} »). "
            f"Tu lui proposes de découvrir : {alt_phrase}. "
            f"Réponds-lui chaleureusement en validant son intérêt pour ce domaine et en lui présentant directement ces métiers pour continuer la discussion."
        )
    else:
        user_prompt = (
            f"L'élève te dit : « {req.objection} » au sujet de son orientation. "
            f"Tu lui proposes plutôt d'explorer : {alt_phrase}. "
            f"Réponds-lui directement avec empathie en t'adressant à lui (tutoiement)."
        )

    reponse_ia = None
    try:
        raw_llm = query_local_llm(user_prompt, system_prompt)
        if raw_llm and not raw_llm.startswith("Erreur") and len(raw_llm.strip()) > 15:
            clean_res = re.sub(r'[\U0001F300-\U0001F9FF\u2600-\u26FF\u2700-\u27BF\U0001F1E6-\U0001F1FF\U0001F600-\U0001F64F\U0001F680-\U0001F6FF]', '', raw_llm)
            clean_res = clean_res.strip().strip('"').strip("'")
            if len(clean_res) > 15:
                reponse_ia = clean_res
    except Exception as e:
        print(f"[Debate LLM Error] {e}")

    # Fallback contextuel riche et dynamique si le LLM est indisponible ou tarde
    if not reponse_ia:
        turn_count = len([h for h in history if h.role == "user"])
        if domain_match:
            dom_key, dom_display = domain_match
            reponse_ia = (
                f"Absolument ! {dom_display.capitalize()} est un secteur passionnant. "
                f"Dans ce domaine, je te conseille de regarder {alt_phrase} : laquelle de ces pistes t'attire le plus ?"
            )
        elif any(w in obj for w in ["pas compris", "mal compris", "faux", "non", "mauvais"]):
            reponse_ia = (
                f"Toutes mes excuses, je t'ai visiblement mal cerné ! "
                f"Oublions complètement ce domaine. "
                f"Si on repart sur de toutes nouvelles bases, que dirais-tu d'explorer plutôt {alt_phrase} ? "
                f"Dis-moi ce qui te motive le plus."
            )
        elif any(w in obj for w in ["écran", "ecran", "ordinateur", "assis"]):
            reponse_ia = (
                f"Je te comprends à cent pour cent : passer ses journées assis devant un écran peut vite devenir étouffant. "
                f"Pour avoir du mouvement et des missions concrètes, regarde plutôt {alt_phrase}. "
                f"Qu'est-ce que tu en penses ?"
            )
        elif any(w in obj for w in ["humain", "contact", "gens", "aider", "social"]):
            reponse_ia = (
                f"Tu as parfaitement raison : le relationnel et le contact humain changent tout au quotidien. "
                f"Pour être au cœur des échanges et te sentir vraiment utile, que penserais-tu de {alt_phrase} ?"
            )
        elif any(w in obj for w in ["math", "maths", "note", "chiffre", "calcul", "8/20"]):
            reponse_ia = (
                f"Ne te bloque surtout pas sur les notes de maths, l'épanouissement professionnel repose sur bien d'autres talents ! "
                f"Tu peux t'épanouir pleinement dans {alt_phrase} sans avoir cette pression."
            )
        elif any(w in obj for w in ["terrain", "bouger", "dehors", "extérieur", "exterieur", "animal", "animaux", "nature"]):
            reponse_ia = (
                f"Le grand air et le terrain, c'est incomparable ! "
                f"Pour bouger et être au contact direct du réel, {alt_phrase} sont deux superbes pistes. "
                f"Laquelle te tente le plus ?"
            )
        elif turn_count > 0:
            reponse_ia = (
                f"C'est très clair, je note bien ton refus et on écarte cette piste. "
                f"Pour contourner ce blocage tout en valorisant tes points forts, regarde plutôt du côté de {alt_phrase}. "
                f"Est-ce que l'une de ces deux voies te parle davantage ?"
            )
        else:
            reponse_ia = (
                f"Je comprends tout à fait ton point de vue sur {spoken_nom}. "
                f"Si tu souhaites éviter ce genre de contrainte, que dirais-tu d'explorer plutôt {alt_phrase} ? "
                f"Dis-moi ce que tu en penses !"
            )

    # Nettoyage phonétique et suppression des fractions de notes "8/20" -> "8 sur 20"
    if reponse_ia:
        reponse_ia = re.sub(r'(\d+(?:[.,]\d+)?)\s*/\s*(\d+)', r'\1 sur \2', reponse_ia)
        reponse_ia = re.sub(r'[\U0001F300-\U0001F9FF\u2600-\u26FF\u2700-\u27BF\U0001F1E6-\U0001F1FF\U0001F600-\U0001F64F\U0001F680-\U0001F6FF]', '', reponse_ia)
        reponse_ia = reponse_ia.strip().strip('"').strip("'")

    return {
        "success": True,
        "reponse_ia": reponse_ia,
        "metiers_alternatifs": alternatives
    }



class NovaChatMessage(BaseModel):
    role: str  # "user" | "assistant"
    content: str

class NovaChatRequest(BaseModel):
    message: str
    conversation_history: List[Dict[str, str]] = []
    student_profile: Optional[Dict[str, Any]] = None

def _build_nova_fallback_response(user_msg: str, prof: dict) -> str:
    msg_low = (user_msg or "").lower()
    classe = prof.get("classe_actuelle") or "au lycée"
    moy = prof.get("moyenne_generale") or prof.get("bulletin", {}).get("moyenne_generale")

    if any(k in msg_low for k in ["math", "calcul", "notes", "progresser", "remédiation"]):
        return (
            "Pour faire grimper ta moyenne en maths, la clé n'est pas de refaire 50 fois les mêmes exercices faciles, "
            "mais de cibler les automatismes de calcul et les démonstrations de cours. "
            "Consacre 3 sessions de 35 minutes par semaine exclusivement aux exercices types du bac ou de concours. "
            "Rédige chaque étape au propre comme si tu étais le jour de l'épreuve."
        )
    elif any(k in msg_low for k in ["parcoursup", "dossier", "commission", "selection", "sélectif"]):
        return (
            "Pour les commissions Parcoursup, deux éléments pèsent lourdement en dehors des notes : "
            "la progression entre le 1er et le 2e trimestre, et l'adéquation de tes spécialités avec la filière visée. "
            "Si ton lycée applique une notation exigeante, n'hésite pas à le faire valoir via la fiche Avenir et ta lettre de motivation."
        )
    elif any(k in msg_low for k in ["prépa", "mpsi", "pcsi", "ecg", "concours"]):
        return (
            "Viser une classe préparatoire est une excellente ambition qui structure ta méthode pour toute ta carrière. "
            "Les prépas recherchent avant tout de la régularité et une capacité à surmonter les moments de doute. "
            "Assure-toi de consolider tes bases dès maintenant et prévois toujours un plan B sécurisé (BUT ou licence sélective)."
        )
    elif any(k in msg_low for k in ["lycee", "henri", "louis", "ival"]):
        return (
            "Le lycée d'origine est en effet scruté par les meilleures formations : un 14 dans un établissement réputé pour sa sévérité "
            "vaut souvent un 16 ou 17 dans un lycée moyen. C'est précisément pour cela que l'application étalonne ton dossier via les indicateurs officiels IVAL."
        )
    else:
        return (
            f"Je prends bien en compte ta question par rapport à ta situation {classe}. "
            "Pour construire une trajectoire solide, concentre-toi d'abord sur la régularité de tes notes et l'alignement de tes spécialités. "
            "Quelle est la filière ou le métier qui te motive le plus en ce moment ?"
        )

@router.post("/nova/chat")
async def nova_chat_endpoint(req: NovaChatRequest):
    user_msg = req.message.strip()
    history = req.conversation_history
    prof = req.student_profile or {}

    classe = prof.get("classe_actuelle") or "Lycée"
    moy = prof.get("moyenne_generale") or (prof.get("bulletin") or {}).get("moyenne_generale") or "non renseignée"
    lycee = prof.get("lycee_nom") or "non renseigné"
    specs = prof.get("specialites_choisies") or []
    specs_str = ", ".join(specs) if specs else "non renseignées"

    system_prompt = (
        "Tu es Nova, le mentor d'orientation et de réussite scolaire d'un élève de lycée en France. "
        f"Contexte de l'élève : Classe : {classe}, Moyenne : {moy}/20, Lycée : {lycee}, Spécialités : {specs_str}. "
        "Règles impératives de style et de ton :\n"
        "1. Tu tutoies l'élève avec bienveillance, franchise et réalisme. Tu es son coach académique de confiance.\n"
        "2. Tu es ultra-concret : cite des formations réelles (CPGE, BUT, Licences, Grandes Écoles), des attendus Parcoursup et des conseils de travail.\n"
        "3. Interdiction formelle du vocabulaire marketing IA ('révolutionnaire', 'incontournable', 'optimiser ton potentiel', 'au cœur de').\n"
        "4. Réponds de façon concise et percutante en 2 courts paragraphes (environ 100 à 130 mots au total). Sois direct et va droit au but.\n"
        "5. Pas d'émoticône excessive, langage soigné en français standard."
    )

    hist_text = ""
    for msg in history[-6:]:
        r = "Élève" if msg.get("role") == "user" else "Nova"
        hist_text += f"\n{r}: {msg.get('content', '')}"

    full_prompt = f"{hist_text}\nÉlève: {user_msg}\nNova:"

    reponse = None
    try:
        raw_llm = query_local_llm(full_prompt, system_prompt)
        if raw_llm and len(raw_llm.strip()) > 15 and not raw_llm.startswith("Erreur"):
            reponse = raw_llm.strip().strip('"').strip("'")
    except Exception as e:
        print(f"[Nova LLM Error] {e}")

    if not reponse:
        reponse = _build_nova_fallback_response(user_msg, prof)

    return {
        "success": True,
        "reply": reponse,
    }


@router.get("/lycees/search")
async def search_lycees_endpoint(
    q: str = "",
    region: Optional[str] = None,
    departement: Optional[str] = None,
    academie: Optional[str] = None,
    limit: int = 25
):
    results = search_lycees_db(q=q, region=region, departement=departement, academie=academie, limit=limit)
    return {"results": results}

@router.get("/lycees/hierarchy")
async def get_lycees_hierarchy_endpoint():
    """Retourne la hiérarchie officielle : Régions -> Départements pour la navigation par filtres."""
    try:
        conn = _get_sqlite_conn()
        cursor = conn.cursor()
        cursor.execute("SELECT DISTINCT region FROM lycees_ival WHERE region != '' ORDER BY region ASC")
        regions = [r[0] for r in cursor.fetchall()]

        cursor.execute("SELECT DISTINCT region, departement FROM lycees_ival WHERE region != '' AND departement != '' ORDER BY departement ASC")
        depts_by_reg = {}
        for r, d in cursor.fetchall():
            depts_by_reg.setdefault(r, []).append(d)

        conn.close()
        return {"regions": regions, "departements_par_region": depts_by_reg}
    except Exception as e:
        print(f"[get_lycees_hierarchy error] {e}")
        return {"regions": [], "departements_par_region": {}}

@router.post("/bulletin/parse")
async def parse_bulletin_file(file: UploadFile = File(...)):
    try:
        content = await file.read()
        filename = (file.filename or "").lower()
        content_type = (file.content_type or "").lower()
        
        is_image = any(filename.endswith(ext) for ext in [".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tiff"]) or "image" in content_type

        if is_image:
            result = parse_bulletin_image(content)
            return result

        if filename.endswith(".pdf") or "pdf" in content_type:
            extracted_text = ""
            reader = None
            try:
                reader = pypdf.PdfReader(io.BytesIO(content))
                for page in reader.pages:
                    txt = page.extract_text() or ""
                    extracted_text += "\n" + txt
            except Exception as e:
                print(f"Erreur lecture PDF: {e}")
            
            result = parse_bulletin_text(extracted_text)
            if not result.get("matieres") and reader is not None:
                merged_matieres: Dict[str, float] = {}
                merged_specs: List[str] = []
                moy_gen = result.get("moyenne_generale")
                classe_det = result.get("classe_detectee")
                for page in reader.pages:
                    for img_file in getattr(page, "images", []):
                        try:
                            ocr_res = parse_bulletin_image(img_file.data)
                            for k, v in (ocr_res.get("matieres") or {}).items():
                                if k not in merged_matieres:
                                    merged_matieres[k] = v
                            for sp in (ocr_res.get("specialites_detectees") or []):
                                if sp not in merged_specs:
                                    merged_specs.append(sp)
                            if moy_gen is None and ocr_res.get("moyenne_generale") is not None:
                                moy_gen = ocr_res["moyenne_generale"]
                            if classe_det is None and ocr_res.get("classe_detectee") is not None:
                                classe_det = ocr_res["classe_detectee"]
                        except Exception:
                            pass
                if merged_matieres:
                    result = _compute_bulletin_summary(
                        found_matieres=merged_matieres,
                        moyenne_gen=moy_gen,
                        classe_detectee=classe_det,
                        specialites_detectees=merged_specs,
                    )
            return result
        else:
            try:
                extracted_text = content.decode("utf-8", errors="replace")
            except Exception:
                extracted_text = ""
            result = parse_bulletin_text(extracted_text)
            return result
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Erreur traitement bulletin: {str(e)}")

def _load_filieres_referentiel() -> dict:
    global _CACHED_FILIERES_DATA
    if _CACHED_FILIERES_DATA is not None:
        return _CACHED_FILIERES_DATA
    try:
        with open(FILIERES_FILE, "r", encoding="utf-8") as f:
            _CACHED_FILIERES_DATA = json.load(f)
            return _CACHED_FILIERES_DATA
    except Exception as e:
        print(f"Erreur chargement filieres_selectives.json: {e}")
        return {"filieres": [], "decodeur_talents": {}, "matrice_specialites": {}}


def _compute_riasec_scores(profile: StudentProfile, ref_data: dict) -> Dict[str, float]:
    base = {
        "R": float(profile.riasec_scores.get("R", 0.0)),
        "I": float(profile.riasec_scores.get("I", 0.0)),
        "A": float(profile.riasec_scores.get("A", 0.0)),
        "S": float(profile.riasec_scores.get("S", 0.0)),
        "E": float(profile.riasec_scores.get("E", 0.0)),
        "C": float(profile.riasec_scores.get("C", 0.0)),
    }
    # Si le profil utilise encore les 5 soft-skills, on les projette sur RIASEC
    if sum(base.values()) == 0:
        base["I"] = float(profile.logique or 5)
        base["A"] = float(profile.creativite or 5)
        base["S"] = float(profile.empathie or 5)
        base["E"] = float(profile.communication or 5)
        base["C"] = float(profile.organisation or 5)
        base["R"] = round((base["I"] + base["C"]) / 2.0, 1)

    # Boost via le Décodeur de Talents (Skill 2)
    decodeur = ref_data.get("decodeur_talents", {})
    for passion in (profile.passions_brutes or []):
        info = decodeur.get(passion)
        if info and "riasec_boost" in info:
            for dim, boost in info["riasec_boost"].items():
                if dim in base:
                    base[dim] = min(10.0, round(base[dim] + float(boost), 1))

    return base


def _resolve_target_filieres(profile: StudentProfile, ref_data: dict) -> tuple:
    filieres = ref_data.get("filieres", [])
    ambitions = [f for f in filieres if f.get("categorie") == "ambition"]
    realistes = {f["id"]: f for f in filieres if f.get("categorie") == "realiste"}

    if not ambitions:
        return None, None

    has_real_notes = bool(profile.bulletin and (
        (profile.bulletin.matieres and len(profile.bulletin.matieres) > 0) or
        (profile.bulletin.moyenne_generale is not None and profile.bulletin.moyenne_generale > 0)
    ))

    # Si l'élève renseigne des passions réelles sans avoir de bulletin ou sans choix explicite de filière,
    # l'orientation découle directement de ses passions (vivre de ses passions).
    if profile.passions_brutes and (not has_real_notes or not profile.filiere_ambition_id):
        p_txt = " ".join(profile.passions_brutes).lower()
        if any(k in p_txt for k in ["gaming", "esport", "programmation", "mods", "cyber", "serveurs", "code"]):
            chosen = next((f for f in filieres if f["id"] == "but_info_geii"), None)
            if chosen: return chosen, chosen
        elif any(k in p_txt for k in ["manga", "dessin", "design", "musique", "beatmaking", "vidéo", "montage", "3d"]):
            chosen = next((f for f in ambitions if f["id"] == "ensa_archi_gobelins"), None)
            if chosen: return chosen, realistes.get(chosen.get("plan_b_id"), chosen)
        elif any(k in p_txt for k in ["achat-revente", "sneakers", "commerce", "finance", "e-commerce"]):
            chosen = next((f for f in ambitions if f["id"] == "cpge_ecg_commerce"), None)
            if chosen: return chosen, realistes.get(chosen.get("plan_b_id"), chosen)
        elif any(k in p_txt for k in ["débat", "debat", "éloquence", "eloquence", "géopolitique"]):
            chosen = next((f for f in ambitions if f["id"] == "sciences_po_bl_droit"), None)
            if chosen: return chosen, realistes.get(chosen.get("plan_b_id"), chosen)
        elif any(k in p_txt for k in ["bricolage", "mécanique", "mecanique", "électronique", "electronique"]):
            chosen = next((f for f in ambitions if f["id"] == "ecole_inge_postbac"), None)
            if chosen: return chosen, realistes.get(chosen.get("plan_b_id"), chosen)
        elif any(k in p_txt for k in ["sport", "aide aux autres"]):
            chosen = next((f for f in ambitions if f["id"] == "pass_las_medecine"), None)
            if chosen: return chosen, realistes.get(chosen.get("plan_b_id"), chosen)

    # 1. Choix explicite par ID avec résolution d'alias stricte
    if profile.filiere_ambition_id:
        raw_id = profile.filiere_ambition_id.strip()
        mapped_id = ID_ALIASES.get(raw_id, raw_id)

        # Recherche exacte par mapped_id ou raw_id dans ambitions
        for f in ambitions:
            if f["id"] == mapped_id or f["id"] == raw_id:
                plan_b = realistes.get(f.get("plan_b_id")) or next(iter(realistes.values()), f)
                return f, plan_b

        # Recherche dans toutes les filières (ex: BUT info)
        for f in filieres:
            if f["id"] == mapped_id or f["id"] == raw_id:
                plan_b = realistes.get(f.get("plan_b_id")) or f
                return f, plan_b

        # Recherche par mot-clé dans les IDs
        low = raw_id.lower()
        if "sante" in low or "medecine" in low or "pass" in low:
            m = next((f for f in ambitions if f["id"] == "pass_las_medecine"), None)
            if m: return m, realistes.get(m.get("plan_b_id"), m)
        elif "ecg" in low or "commerce" in low or "eco" in low:
            m = next((f for f in ambitions if f["id"] == "cpge_ecg_commerce"), None)
            if m: return m, realistes.get(m.get("plan_b_id"), m)
        elif "po" in low or "droit" in low:
            m = next((f for f in ambitions if f["id"] == "sciences_po_bl_droit"), None)
            if m: return m, realistes.get(m.get("plan_b_id"), m)
        elif "mpsi" in low or "pcsi" in low or "prepa" in low:
            m = next((f for f in ambitions if f["id"] == "cpge_mpsi_pcsi"), None)
            if m: return m, realistes.get(m.get("plan_b_id"), m)
        elif "inge" in low:
            m = next((f for f in ambitions if f["id"] == "ecole_inge_postbac"), None)
            if m: return m, realistes.get(m.get("plan_b_id"), m)
        elif "info" in low or "cyber" in low:
            m = next((f for f in filieres if f["id"] == "but_info_geii"), None)
            if m: return m, m

    # 2. Déduction par secteurs souhaités, spécialités et dominante du bulletin
    # 2. Déduction par secteurs souhaités ET passions (Décodeur de Talents)
    combined_interests = f"{' '.join(profile.secteurs_souhaits or [])} {' '.join(profile.passions_brutes or [])}".lower()
    dominante_txt = (profile.bulletin.dominante.lower() if (profile.bulletin and profile.bulletin.dominante) else "")
    ctx = _infer_academic_context(profile)

    chosen_ambition = ambitions[0]
    if any(k in combined_interests for k in ["design", "création", "architecture", "médias", "art", "manga", "dessin", "musique", "beatmaking", "vidéo", "montage", "2d", "3d"]):
        chosen_ambition = next((f for f in ambitions if f["id"] == "ensa_archi_gobelins"), ambitions[0])
    elif any(k in combined_interests for k in ["gaming", "esport", "programmation", "mods", "cyber", "informatique", "code"]):
        chosen_ambition = next((f for f in filieres if f["id"] == "but_info_geii"), ambitions[0])
    elif any(k in combined_interests for k in ["business", "finance", "management", "commerce", "entrepreneuriat", "achat-revente", "sneakers", "e-commerce"]):
        chosen_ambition = next((f for f in ambitions if f["id"] == "cpge_ecg_commerce"), ambitions[0])
    elif any(k in combined_interests for k in ["droit", "politique", "humain", "enseignement", "journalisme", "débat", "éloquence", "géopolitique"]):
        chosen_ambition = next((f for f in ambitions if f["id"] == "sciences_po_bl_droit"), ambitions[0])
    elif any(k in combined_interests for k in ["médecine", "santé", "biologie", "paramédical", "soin", "sport", "aide aux autres"]):
        chosen_ambition = next((f for f in ambitions if f["id"] == "pass_las_medecine"), ambitions[0])
    elif any(k in combined_interests for k in ["ia", "data", "robotique", "ingénierie", "tech", "aéronautique", "bricolage", "mécanique", "électronique"]):
        chosen_ambition = next((f for f in ambitions if f["id"] == "ecole_inge_postbac"), ambitions[0])
    elif ctx["is_literary"] or "littéraire" in dominante_txt or "humanités" in dominante_txt:
        chosen_ambition = next((f for f in ambitions if f["id"] == "sciences_po_bl_droit"), ambitions[0])
    elif ctx["is_art"] or "artistique" in dominante_txt:
        chosen_ambition = next((f for f in ambitions if f["id"] == "ensa_archi_gobelins"), ambitions[0])
    elif ctx["is_eco"] or "économique" in dominante_txt:
        chosen_ambition = next((f for f in ambitions if f["id"] == "cpge_ecg_commerce"), ambitions[0])
    elif ctx["is_health"]:
        chosen_ambition = next((f for f in ambitions if f["id"] == "pass_las_medecine"), ambitions[0])

    plan_b = realistes.get(chosen_ambition.get("plan_b_id")) or next(iter(realistes.values()), chosen_ambition)
    return chosen_ambition, plan_b


def _matches_spec_req(req_str: str, student_specs: list | set) -> bool:
    """Vérifie si une exigence de spécialité correspond aux spécialités suivies par l'élève."""
    r_clean = (req_str or "").lower().strip()
    for s in student_specs:
        s_clean = (str(s) or "").lower().strip()
        if not s_clean:
            continue
        # Biologie / SVT
        if ("svt" in s_clean or "bio" in s_clean) and ("svt" in r_clean or "bio" in r_clean):
            return True
        # Mathématiques
        if "math" in s_clean and "math" in r_clean:
            return True
        # Physique-Chimie
        if ("phys" in s_clean or "chim" in s_clean) and ("phys" in r_clean or "chim" in r_clean):
            return True
        # Informatique / NSI
        if ("info" in s_clean or "nsi" in s_clean) and ("info" in r_clean or "nsi" in r_clean):
            return True
        # SES / Économie
        if ("ses" in s_clean or "éco" in s_clean or "eco" in s_clean) and ("ses" in r_clean or "éco" in r_clean or "eco" in r_clean):
            return True
        # Histoire-Géographie / HGGSP
        if ("hist" in s_clean or "géo" in s_clean or "geo" in s_clean or "hggsp" in s_clean) and ("hist" in r_clean or "géo" in r_clean or "geo" in r_clean or "hggsp" in r_clean):
            return True
        # HLP / Philosophie / Lettres / Humanités
        if ("hlp" in s_clean or "philo" in s_clean or "litt" in s_clean or "human" in s_clean) and ("hlp" in r_clean or "philo" in r_clean or "litt" in r_clean or "human" in r_clean):
            return True
        # LLCER / Langues
        if ("llcer" in s_clean or "angl" in s_clean or "lang" in s_clean) and ("llcer" in r_clean or "angl" in r_clean or "lang" in r_clean):
            return True
        # Arts
        if "art" in s_clean and "art" in r_clean:
            return True
        # Sciences de l'Ingénieur (SI)
        if ("ingé" in s_clean or "inge" in s_clean or s_clean == "si") and ("ingé" in r_clean or "inge" in r_clean or "si" in r_clean.split()):
            return True
        # Correspondance textuelle directe
        if s_clean in r_clean or r_clean in s_clean:
            return True
    return False


def compute_gap_analysis(profile: StudentProfile) -> dict:
    ref_data = _load_filieres_referentiel()
    ambition, plan_b = _resolve_target_filieres(profile, ref_data)
    riasec = _compute_riasec_scores(profile, ref_data)

    # Décodage des passions (Skill 2)
    decodeur = ref_data.get("decodeur_talents", {})
    talents_decodes = []
    for p in (profile.passions_brutes or []):
        if p in decodeur:
            d = decodeur[p]
            talents_decodes.append({
                "passion": p,
                "competence_academique": d["competence_academique"],
                "competence_pro": d["competence_pro"],
                "argument_parcoursup": d["argument_parcoursup"],
            })

    if not ambition:
        return {
            "filiere_cible": "Filière générale",
            "probabilite_admission": 50,
            "statut_global": "À préciser",
            "ecarts_matieres": [],
            "talents_decodes": talents_decodes,
            "profil_riasec": riasec,
        }

    notes_eleve = (profile.bulletin.matieres if profile.bulletin and profile.bulletin.matieres else {})
    seuils = ambition.get("seuils_matieres", {})

    ecarts = []
    total_delta = 0.0
    nb_matieres = 0

    for matiere, seuil in seuils.items():
        # Recherche de la note correspondante dans le bulletin
        note = notes_eleve.get(matiere)
        if note is None:
            for k, v in notes_eleve.items():
                if matiere.lower()[:5] in k.lower() or k.lower()[:5] in matiere.lower():
                    note = v
                    break
        if note is None:
            note = profile.bulletin.moyenne_generale if (profile.bulletin and profile.bulletin.moyenne_generale) else 12.0

        delta = round(float(note) - float(seuil), 1)
        total_delta += delta
        nb_matieres += 1

        if delta >= 0:
            statut = "favorable"
            priorite = 3
        elif delta >= -2.0:
            statut = "vigilance"
            priorite = 2
        else:
            statut = "critique"
            priorite = 1

        ecarts.append({
            "matiere": matiere,
            "note_actuelle": round(float(note), 1),
            "seuil_attendu": round(float(seuil), 1),
            "delta": delta,
            "statut": statut,
            "priorite": priorite,
        })

    ecarts.sort(key=lambda x: (x["priorite"], x["delta"]))

    avg_delta = (total_delta / nb_matieres) if nb_matieres > 0 else 0.0
    # Probabilité d'admission réaliste centrée sur 65% quand l'élève est pile aux seuils
    raw_prob = int(round(68 + avg_delta * 11))

    # Pénalité si une spécialité requise est absente (lorsque l'élève a renseigné ses spécialités)
    specs_eleve = set(profile.specialites_choisies or (profile.bulletin.specialites if profile.bulletin else []) or [])
    missing_specs = []
    if specs_eleve:
        for req_spec in ambition.get("specialites_requises", []):
            if not _matches_spec_req(req_spec, specs_eleve):
                missing_specs.append(req_spec)
                raw_prob -= 22

    probabilite = max(8, min(95, raw_prob))

    if probabilite >= 70:
        statut_global = "Dossier Compétitif (Voie Ambition accessible)"
    elif probabilite >= 45:
        statut_global = "Écart Modéré (Remédiation ciblée requise)"
    else:
        statut_global = "Écart Critique (Plan B indispensable + Remédiation intensive)"

    # Calcul de la probabilité pour le Plan B Réaliste
    prob_plan_b = min(96, max(35, probabilite + 28))

    return {
        "filiere_cible_id": ambition["id"],
        "filiere_cible": ambition["nom"],
        "etablissement_type": ambition["etablissement_type"],
        "taux_acces_parcoursup": ambition["taux_acces_parcoursup"],
        "moyenne_attendue": ambition["moyenne_generale_attendue"],
        "probabilite_admission": probabilite,
        "probabilite_plan_b": prob_plan_b,
        "statut_global": statut_global,
        "specialites_manquantes": missing_specs,
        "ecarts_matieres": ecarts,
        "talents_decodes": talents_decodes,
        "profil_riasec": riasec,
    }


def compute_double_trajectory(profile: StudentProfile, top_metiers: Optional[list] = None) -> dict:
    ref_data = _load_filieres_referentiel()
    ambition, plan_b = _resolve_target_filieres(profile, ref_data)
    gap = compute_gap_analysis(profile)

    if top_metiers is None:
        top_3 = get_top_metiers(profile, limit=3)
        top_metiers = [item["meta"] for item in top_3]

    # Simulateur d'impact de spécialités (Skill 5)
    specs_eleve = list(profile.specialites_choisies or (profile.bulletin.specialites if profile.bulletin else []) or [])
    if not specs_eleve and profile.bulletin and profile.bulletin.matieres:
        # Déduction automatique des spécialités probables si non renseignées
        for cand in ["Mathématiques", "Physique-Chimie", "SVT / Biologie", "SES / Économie", "Informatique / NSI", "Histoire-Géographie", "Art"]:
            if cand in profile.bulletin.matieres:
                specs_eleve.append(cand)
        specs_eleve = specs_eleve[:3]

    filieres_ouvertes = []
    filieres_vigilance = []
    filieres_fermees = []

    for f in ref_data.get("filieres", []):
        reqs = f.get("specialites_requises", [])
        if not reqs:
            filieres_ouvertes.append({"id": f["id"], "nom": f["nom"], "pole": f["pole"]})
            continue
        matched_reqs = [r for r in reqs if _matches_spec_req(r, specs_eleve)]
        if len(matched_reqs) == len(reqs):
            filieres_ouvertes.append({"id": f["id"], "nom": f["nom"], "pole": f["pole"]})
        elif len(matched_reqs) > 0:
            manquantes = [r for r in reqs if r not in matched_reqs]
            filieres_vigilance.append({
                "id": f["id"],
                "nom": f["nom"],
                "pole": f["pole"],
                "alerte": f"Spécialité manquante : {', '.join(manquantes)}"
            })
        else:
            filieres_fermees.append({
                "id": f["id"],
                "nom": f["nom"],
                "pole": f["pole"],
                "raison": f"Requiert : {', '.join(reqs)}"
            })

    matrice_specs = ref_data.get("matrice_specialites", {})
    details_specs = {s: matrice_specs[s] for s in specs_eleve if s in matrice_specs}

    # Sélection SQL déterministe d'établissements réels MESR (Groupes 1, 2, 3)
    # Détection de notes réelles vs orientation purement par les passions
    moy_eleve = 13.0
    notes_dict = {}
    has_real_notes = False
    if profile.bulletin:
        if profile.bulletin.matieres:
            notes_dict = {k: float(v) for k, v in profile.bulletin.matieres.items() if v is not None}
            if notes_dict:
                has_real_notes = True
        if profile.bulletin.moyenne_generale is not None and profile.bulletin.moyenne_generale > 0:
            moy_eleve = float(profile.bulletin.moyenne_generale)
            has_real_notes = True
        elif notes_dict:
            moy_eleve = round(sum(notes_dict.values()) / len(notes_dict), 2)
    amb_sql = None
    sec_sql = None
    try:
        try:
            from database import engine as sql_engine
            from services.diagnostic_service import _resolve_domain_profile, _select_formation_from_view
        except ImportError:
            from backend.database import engine as sql_engine
            from backend.services.diagnostic_service import _resolve_domain_profile, _select_formation_from_view
        from sqlmodel import Session as SqlSession

        target_dom = " ".join(profile.secteurs_souhaits or []) or (ambition["pole"] if ambition else "")
        dom_prof = _resolve_domain_profile(
            target_domain=target_dom,
            specialties=specs_eleve,
            interests=list(profile.passions_brutes or []),
            subject_grades=notes_dict,
        )
        with SqlSession(sql_engine) as sql_db:
            amb_sql = _select_formation_from_view(
                db=sql_db,
                view_name="v_voie_a_ambition",
                keywords=dom_prof["ambition_sql_keywords"],
                moyenne_eleve=moy_eleve,
                is_ambition=True,
            )
            sec_sql = _select_formation_from_view(
                db=sql_db,
                view_name="v_voie_b_secours",
                keywords=dom_prof["realiste_sql_keywords"],
                moyenne_eleve=moy_eleve,
                is_ambition=False,
            )
    except Exception as e:
        print(f"[DoubleTrajectory SQL Fallback] {e}")

    amb_group = int(amb_sql.get("selectivity_group") or 2) if amb_sql else 2
    amb_label = (
        str(amb_sql.get("ranking_label"))
        if (amb_sql and amb_sql.get("ranking_label"))
        else "Groupe 2 : Cibles Grandes Écoles Nationales"
    )
    amb_source = (
        str(amb_sql.get("source_citation"))
        if (amb_sql and amb_sql.get("source_citation"))
        else "Source : Données MESR Open Data / Classement L'Étudiant"
    )

    sec_group = int(sec_sql.get("selectivity_group") or 3) if sec_sql else 3
    sec_label = (
        str(sec_sql.get("ranking_label"))
        if (sec_sql and sec_sql.get("ranking_label"))
        else "Groupe 3 : Accès Régional & Tremplin Sécurisé"
    )
    sec_source = (
        str(sec_sql.get("source_citation"))
        if (sec_sql and sec_sql.get("source_citation"))
        else "Source : Données officielles MESR Parcoursup Open Data"
    )

    # Calcul du bonus de sélectivité du lycée d'origine (IVAL)
    lycee_nom = profile.lycee_nom or (profile.bulletin.lycee_nom if profile.bulletin else None) or ""
    lycee_ville = profile.lycee_ville or (profile.bulletin.lycee_ville if profile.bulletin else None) or ""
    lycee_region = profile.lycee_region or (profile.bulletin.lycee_region if profile.bulletin else None) or ""
    lycee_taux = profile.lycee_taux_mentions or (profile.bulletin.lycee_taux_mentions if profile.bulletin else None) or 0.0
    lycee_bonus = profile.lycee_bonus_selectivite or (profile.bulletin.lycee_bonus_selectivite if profile.bulletin else None) or 0.0

    # Si un lycée est renseigné mais sans bonus calculé, on le résout via la base
    if lycee_nom and lycee_bonus == 0.0:
        found_l = search_lycees_db(lycee_nom, limit=1)
        if found_l:
            lycee_bonus = found_l[0]["bonus_selectivite"]
            lycee_taux = found_l[0]["taux_mentions"]
            if not lycee_region:
                lycee_region = found_l[0]["region"]
            if not lycee_ville:
                lycee_ville = found_l[0]["ville"]

    moy_calibree = round(moy_eleve + lycee_bonus, 2)

    # Récupération des mots clés du domaine visé avec tokenisation intelligente
    dom_kws = _extract_smart_domain_keywords(
        profile.filiere_ambition_id or (ambition["id"] if ambition else ""),
        profile.secteurs_souhaits,
        ambition.get("pole", "") if ambition else "",
    )

    poles_3 = get_triple_trajectory_formations(
        moyenne_eleve=moy_calibree,
        filiere_id=profile.filiere_ambition_id or (ambition["id"] if ambition else ""),
        domain_keywords=dom_kws,
        region=lycee_region if lycee_region else None,
        secteurs_souhaits=profile.secteurs_souhaits,
        pole_default=ambition.get("pole", "") if ambition else "",
        is_top_lycee=(lycee_bonus >= 0.8 or lycee_taux >= 85.0),
        passions=profile.passions_brutes,
    )

    lycee_analyse = {
        "nom": lycee_nom,
        "ville": lycee_ville,
        "region": lycee_region,
        "taux_mentions": lycee_taux,
        "bonus_selectivite": lycee_bonus,
        "moyenne_brute": moy_eleve,
        "moyenne_ponderee": moy_calibree,
        "impact_mention": f"+{lycee_bonus} pt sur dossier sélectif" if lycee_bonus > 0 else "Neutre",
    }

    return {
        "poles_trajectoire": poles_3,
        "voie_royale_elite": poles_3.get("voie_royale_elite", []),
        "lycee_analyse": lycee_analyse,
        "parcours_ambition": {
            "type_trajectoire": "ambition",
            "id": amb_sql["formation_id"] if amb_sql else (ambition["id"] if ambition else "ambition_default"),
            "titre": amb_sql["nom"] if amb_sql else (ambition["nom"] if ambition else "Filière Sélective"),
            "etablissement": amb_sql["etablissement"] if amb_sql else (ambition["etablissement_type"] if ambition else ""),
            "ville": amb_sql["ville"] if amb_sql else "",
            "pole": ambition["pole"] if ambition else "",
            "etablissement_type": ambition["etablissement_type"] if ambition else "",
            "taux_acces_parcoursup": round(float(amb_sql["taux_acces"]), 1) if amb_sql else (ambition["taux_acces_parcoursup"] if ambition else 20),
            "probabilite_eleve": gap["probabilite_admission"],
            "moyenne_attendue": round(float(amb_sql["seuil_moyenne_estime"]), 2) if amb_sql else (ambition["moyenne_generale_attendue"] if ambition else 15.0),
            "estimated_gap": round(float(amb_sql["estimated_gap"]), 2) if amb_sql else round(moy_eleve - (ambition["moyenne_generale_attendue"] if ambition else 15.0), 2),
            "selectivity_group": amb_group,
            "ranking_label": amb_label,
            "source_citation": amb_source,
            "specialites_requises": ambition.get("specialites_requises", []) if ambition else [],
            "conditions_acces": ambition.get("conditions_acces", []) if ambition else [],
            "casseur_de_mythes": ambition.get("casseur_de_mythes", {}) if ambition else {},
            "metiers_cibles": top_metiers[:2] if top_metiers else [],
        },
        "parcours_realiste": {
            "type_trajectoire": "realiste",
            "id": sec_sql["formation_id"] if sec_sql else (plan_b["id"] if plan_b else "realiste_default"),
            "titre": sec_sql["nom"] if sec_sql else (plan_b["nom"] if plan_b else "Plan B Sécurisé"),
            "etablissement": sec_sql["etablissement"] if sec_sql else (plan_b["etablissement_type"] if plan_b else ""),
            "ville": sec_sql["ville"] if sec_sql else "",
            "pole": plan_b["pole"] if plan_b else "",
            "etablissement_type": plan_b["etablissement_type"] if plan_b else "",
            "taux_acces_parcoursup": round(float(sec_sql["taux_acces"]), 1) if sec_sql else (plan_b["taux_acces_parcoursup"] if plan_b else 45),
            "probabilite_eleve": gap["probabilite_plan_b"],
            "moyenne_attendue": round(float(sec_sql["seuil_moyenne_estime"]), 2) if sec_sql else (plan_b["moyenne_generale_attendue"] if plan_b else 12.5),
            "estimated_gap": round(float(sec_sql["estimated_gap"]), 2) if sec_sql else round(moy_eleve - (plan_b["moyenne_generale_attendue"] if plan_b else 12.5), 2),
            "selectivity_group": sec_group,
            "ranking_label": sec_label,
            "source_citation": sec_source,
            "specialites_requises": plan_b.get("specialites_requises", []) if plan_b else [],
            "conditions_acces": plan_b.get("conditions_acces", []) if plan_b else [],
            "casseur_de_mythes": plan_b.get("casseur_de_mythes", {}) if plan_b else {},
            "metiers_cibles": top_metiers[1:3] if (top_metiers and len(top_metiers) > 1) else (top_metiers or []),
        },
        "impact_specialites": {
            "specialites_actuelles": specs_eleve,
            "filieres_ouvertes": filieres_ouvertes,
            "filieres_vigilance": filieres_vigilance,
            "filieres_fermees": filieres_fermees,
            "details_par_specialite": details_specs,
        }
    }


EXERCISE_BANK = {
    "Mathématiques": {
        "question": "Soit f(x) = x² - 4x + 3. Déterminer la forme canonique, les racines et le tableau de variation complet en moins de 4 minutes.",
        "methode": "1) Identifier a=1, b=-4, c=3. 2) Sommet α = -b/(2a) = 2, β = f(2) = -1 → f(x) = (x-2)² - 1. 3) Factoriser via identité remarquable a²-b².",
        "objectif_chiffre": "Maîtriser le calcul algébrique sans calculatrice (0 erreur de signe sur 10 exercices)."
    },
    "Physique-Chimie": {
        "question": "Analyse dimensionnelle et conversion : exprimer une énergie cinétique Ec = ½·m·v² en unités SI fondamentales (kg, m, s) et isoler la vitesse v.",
        "methode": "Toujours isoler littéralement l'inconnue (v = √(2·Ec/m)) AVANT de remplacer par les valeurs numériques et convertir toutes les grandeurs en unités SI.",
        "objectif_chiffre": "Gagner +2 points par devoir en éliminant 100% des erreurs d'unités et de formules littérales."
    },
    "SVT / Biologie": {
        "question": "Structurer l'introduction et le schéma-bilan d'une synthèse sur l'expression du patrimoine génétique (Transcription → Traduction).",
        "methode": "Définir les mots-clés (ADN, ARNm, ribosome, polypeptide), formuler la problématique fonctionnelle et dessiner un schéma légendé avec flèches causales.",
        "objectif_chiffre": "Intégrer systématiquement un schéma-bilan fonctionnel dans chaque exercice de synthèse."
    },
    "SES / Économie": {
        "question": "Lire et interpréter rigoureusement un indice base 100 et un taux de variation cumulé dans un dossier documentaire.",
        "methode": "Utiliser une phrase-type précise avec unité, date et source, puis distinguer ralentissement de la hausse (désinflation) et baisse réelle.",
        "objectif_chiffre": "Obtenir 4/4 aux questions d'exploitation statistique de l'épreuve composée."
    },
    "Histoire-Géographie": {
        "question": "Rédiger l'accroche, l'analyse des bornes chronologiques et la problématique d'une question problématisée en 15 minutes.",
        "methode": "Contextualiser les dates clés du sujet, définir chaque terme conceptuel et formuler un paradoxe historique (« Dans quelle mesure... »).",
        "objectif_chiffre": "Passer au-dessus de 15/20 grâce à une problématisation explicite dès l'introduction."
    },
    "Français": {
        "question": "Transformer un relevé de procédés littéraires en une sous-partie de commentaire composé (Idée directrice → Citation → Procédé → Effet).",
        "methode": "Ne jamais juxtaposer stylistique et paraphrase : chaque figure de style relevée doit prouver l'idée directrice de la sous-partie.",
        "objectif_chiffre": "Rédiger 2 paragraphes d'analyse littéraire structurés en 30 minutes."
    },
    "Anglais": {
        "question": "Synthétiser un article de presse anglophone (The Economist / BBC) en 5 phrases en utilisant 4 connecteurs logiques avancés.",
        "methode": "Mobiliser des structures idiomatiques (However, Furthermore, Consequently, Not only... but also) et proscrire les répétitions de verbes faibles.",
        "objectif_chiffre": "Atteindre le niveau B2/C1 exigé par les filières sélectives et prépas."
    }
}


def compute_weekly_execution_plan(profile: StudentProfile, gap_data: Optional[dict] = None) -> dict:
    if gap_data is None:
        gap_data = compute_gap_analysis(profile)

    ecarts = gap_data.get("ecarts_matieres", [])
    prioritaires = [e for e in ecarts if e["delta"] < 0]
    if not prioritaires:
        prioritaires = ecarts[:3]

    jours = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    creneaux = [
        "18h00 - 18h45",
        "18h00 - 18h45",
        "14h30 - 16h00",
        "18h00 - 18h45",
        "17h30 - 18h15",
        "10h00 - 11h30",
        "17h00 - 17h45",
    ]

    weekly_plan = []
    micro_exercices = []

    for idx, jour in enumerate(jours):
        target = prioritaires[idx % len(prioritaires)] if prioritaires else {
            "matiere": "Mathématiques",
            "note_actuelle": 13.0,
            "seuil_attendu": 15.0,
            "delta": -2.0,
        }
        mat = target["matiere"]
        delta = target["delta"]
        duree = 90 if jour in ["Mercredi", "Samedi"] else 45

        if jour == "Dimanche":
            objectif = "Bilan de la semaine : refaire sans aide les exercices ratés du lundi au samedi + planification."
            type_ex = "Consolidation & Méthode"
        elif delta < -2.0:
            objectif = f"Remédiation prioritaire ({delta} pts à combler) : reprendre les théorèmes/notions du chapitre en cours + 3 exercices progressifs."
            type_ex = "Remédiation Intensive"
        elif delta < 0:
            objectif = f"Objectif seuil {target['seuil_attendu']}/20 : entraînement chronométré sur annales et exercices types de contrôle."
            type_ex = "Entraînement Ciblé"
        else:
            objectif = f"Maintien d'excellence ({target['note_actuelle']}/20) : approfondissement hors-programme / sujet type prépa ou concours."
            type_ex = "Approfondissement Ambition"

        weekly_plan.append({
            "jour": jour,
            "creneau": creneaux[idx],
            "matiere": mat,
            "objectif": objectif,
            "duree_minutes": duree,
            "type_exercice": type_ex,
            "delta_cible": delta,
        })

    # Génération des micro-exercices adaptatifs (Skill 8)
    seen_subjects = set()
    for item in prioritaires[:4]:
        mat = item["matiere"]
        if mat in seen_subjects:
            continue
        seen_subjects.add(mat)
        ex_info = EXERCISE_BANK.get(mat) or {
            "question": f"Résoudre un exercice-type de contrôle en {mat} en temps limité (20 min) sans consulter le cours.",
            "methode": "Identifier la consigne exacte, mobiliser les définitions du cours et vérifier la cohérence du résultat.",
            "objectif_chiffre": f"Combler l'écart de {item['delta']} pt(s) pour atteindre le seuil de {item['seuil_attendu']}/20."
        }
        micro_exercices.append({
            "matiere": mat,
            "note_actuelle": item["note_actuelle"],
            "seuil_attendu": item["seuil_attendu"],
            "delta": item["delta"],
            "question": ex_info["question"],
            "methode": ex_info["methode"],
            "objectif_chiffre": ex_info["objectif_chiffre"],
        })

    return {
        "filiere_cible": gap_data.get("filiere_cible", ""),
        "weekly_plan": weekly_plan,
        "micro_exercices": micro_exercices,
    }


@router.get("/strategy/referentiel")
def get_strategy_referentiel():
    ref_data = _load_filieres_referentiel()
    return {
        "success": True,
        "filieres": ref_data.get("filieres", []),
        "passions_disponibles": list(ref_data.get("decodeur_talents", {}).keys()),
        "decodeur_talents": ref_data.get("decodeur_talents", {}),
        "matrice_specialites": ref_data.get("matrice_specialites", {}),
    }


@router.post("/diagnostic/gap-analyzer")
def endpoint_gap_analyzer(profile: StudentProfile):
    return {
        "success": True,
        **compute_gap_analysis(profile),
    }


@router.post("/strategy/double-trajectory")
def endpoint_double_trajectory(profile: StudentProfile):
    return {
        "success": True,
        **compute_double_trajectory(profile),
    }


@router.post("/execution/weekly-plan")
def endpoint_weekly_plan(profile: StudentProfile):
    return {
        "success": True,
        **compute_weekly_execution_plan(profile),
    }


@router.post("/analyze")
def analyze_orientation(profile: StudentProfile):
    top_3 = get_top_metiers(profile, limit=3)

    if not top_3:
        raise HTTPException(status_code=500, detail="Impossible de charger ou calculer les métiers.")

    top_metiers_meta = [item["meta"] for item in top_3]
    gap_analysis = compute_gap_analysis(profile)
    double_trajectoire = compute_double_trajectory(profile, top_metiers=top_metiers_meta)
    execution_plan = compute_weekly_execution_plan(profile, gap_data=gap_analysis)

    return {
        "success": True,
        "recommendation": f"Analyse stratégique complète : {gap_analysis['statut_global']}.",
        "top_metiers": top_metiers_meta,
        "gap_analysis": gap_analysis,
        "double_trajectoire": double_trajectoire,
        "execution_plan": execution_plan,
    }

@router.get("/health")
def api_health():
    return {"status": "ok", "service": "orientation-ia-strategic-coach"}

@router.get("/metiers/search")
def search_metiers(q: str = "", limit: int = 20):
    metiers = load_metiers_data()
    if not q or len(q.strip()) < 2:
        return {"total": len(metiers), "count": min(len(metiers), limit), "results": metiers[:limit]}

    query = q.lower().strip()
    results = []
    for m in metiers:
        nom = m.get("nom", "").lower()
        code = m.get("code_rome", "").lower()
        domaines = [d.lower() for d in m.get("domaines", [])]
        appellations = [a.lower() for a in m.get("appellations", [])]

        if (query in nom or
            query in code or
            any(query in d for d in domaines) or
            any(query in a for a in appellations)):
            results.append(m)
            if len(results) >= limit:
                break

    return {"total": len(results), "query": q, "results": results}

def _clean_and_complete_llm_response(text: str) -> str:
    text = text.strip()
    if not text:
        return text

    lines = [l.rstrip() for l in text.split("\n")]
    while lines:
        last = lines[-1].strip()
        if not last:
            lines.pop()
            continue
        if last.endswith("(") or last.endswith("[") or last.endswith(":") or last in ["-", "•", "*"]:
            lines.pop()
            continue
        if re.match(r'^\d+[\.\)]\s*(\*\*)?$', last):
            lines.pop()
            continue
        if last[-1] not in [".", "!", "?", "…", "»", '"', "”"]:
            matches = list(re.finditer(r'(?<!\b\d)[\.\!\?](?=\s|$)', last))
            if matches:
                last_idx = matches[-1].end()
                lines[-1] = last[:last_idx]
            else:
                if len([l for l in lines if l.strip()]) > 1:
                    lines.pop()
                else:
                    lines[-1] = last + "."
            continue
        break

    cleaned = "\n".join(lines).strip()
    open_p = cleaned.count("(")
    close_p = cleaned.count(")")
    if open_p > close_p:
        cleaned += ")" * (open_p - close_p)
    if cleaned.count('"') % 2 != 0:
        cleaned += '"'
    return cleaned

@router.post("/chat-metier")
def chat_metier_interaction(req: MetierChatRequest):
    nom = req.metier_nom.strip()
    q = req.question.strip()
    if not q:
        raise HTTPException(status_code=400, detail="La question ne peut pas être vide.")

    # Contexte métier
    desc = req.metier_description or ""
    missions = req.metier_missions or []
    etudes = req.metier_etudes or []
    salaire = req.metier_salaire or {}
    missions_str = ", ".join(missions[:4]) if missions else "Missions spécialisées du secteur"
    etudes_str = ", ".join(etudes[:3]) if etudes else "Formations académiques et professionnelles"
    
    # Historique de dialogue
    history_lines = []
    for h in req.history[-6:]:
        role_label = "Élève" if h.role == "user" else "Nova"
        history_lines.append(f"{role_label}: {h.text}")
    dialogue_str = "\n".join(history_lines) if history_lines else f"Élève: {q}"

    system_prompt = (
        "Tu es Nova, une IA experte d'orientation scolaire et professionnelle, bienveillante, dynamique, directe et claire (comme ChatGPT ou Claude). "
        f"L'élève explore le métier : '{nom}' et te pose des questions pour en savoir plus ou débattre. "
        "Réponds-lui directement et chaleureusement en t'adressant à lui (tutoiement). "
        "Donne des explications concrètes, des exemples de terrain et des conseils d'écoles/formations réalistes. "
        "Structure bien ta réponse en 2 à 3 points clés lisibles. "
        "IMPORTANT : Termine TOUJOURS complètement tes phrases et tes listes, ne t'interromps jamais au milieu d'une idée."
    )

    user_prompt = (
        f"Fiche du métier '{nom}' :\n"
        f"- Description : {desc}\n"
        f"- Missions clés : {missions_str}\n"
        f"- Accès & Formations : {etudes_str}\n"
        f"- Rémunération indicative : Junior ~{salaire.get('junior', 28000)}€, Confirmé ~{salaire.get('medior', 38000)}€, Senior ~{salaire.get('senior', 50000)}€\n\n"
        f"Historique de l'échange :\n{dialogue_str}\n\n"
        f"Nouvelle question de l'élève : « {q} »\n\n"
        f"Réponds directement à l'élève avec 2 ou 3 conseils ou exemples concrets et conclus chaleureusement."
    )

    reponse_ia = None
    try:
        raw_llm = query_local_llm(user_prompt, system_prompt)
        if raw_llm and not raw_llm.startswith("Erreur") and len(raw_llm.strip()) > 20:
            reponse_ia = _clean_and_complete_llm_response(raw_llm.strip().strip('"').strip("'"))
    except Exception as e:
        print(f"[Chat Metier LLM Error] {e}")

    # Fallback contextuel riche basé sur l'intention sémantique de la question
    if not reponse_ia:
        q_low = q.lower()
        
        # 1. Écoles de commerce / Grandes écoles / Types d'études
        if any(w in q_low for w in ["école de commerce", "ecole de commerce", "écoles de commerce", "ecoles de commerce", "école d'ingénieur", "ecole d'ingenieur", "grande école", "grandes écoles", "grandes ecoles", "commerce", "école", "ecole"]):
            nom_low = nom.lower()
            if any(k in nom_low for k in ["commercial", "business", "vente", "marketing", "manager", "gestion"]):
                reponse_ia = (
                    f"Concernant les **écoles de commerce** pour devenir **{nom}** :\n\n"
                    f"• **Est-ce adapté ?** Oui, absolument ! Les écoles de commerce (post-bac ou post-prépa) apportent une solide formation en négociation, stratégie de vente, gestion financière et relation client, très prisée des recruteurs.\n"
                    f"• **Alternatives très reconnues** : Tu peux aussi passer par les IAE (écoles universitaires de management, publiques et gratuites) ou un BTS/BUT commercial (ex: Tech de Co), complété par une licence pro ou un master.\n"
                    f"• **Profil hybride très recherché** : Si le métier est technique, associer une base scientifique/technique (DUT/BTS/Licence) avec une spécialisation en école de commerce te rendra particulièrement attractif !"
                )
            elif any(k in nom_low for k in ["ingénieur", "robotique", "ia", "data", "développeur", "aéronautique", "mécatronique"]):
                reponse_ia = (
                    f"Concernant les écoles pour devenir **{nom}** :\n\n"
                    f"• **Faut-il faire une école de commerce ?** Non, pour la conception technique et la R&D, la voie royale reste les **écoles d'ingénieurs** (Polytechnique, Mines, INSA, Télécom, UTC...) ou un Master universitaire scientifique spécialisé (Informatique, Data, Mécatronique).\n"
                    f"• **Quand l'école de commerce devient-elle utile ?** Seulement si tu souhaites évoluer vers du Product Management, de la direction de start-up ou du conseil en stratégie technologique, souvent après ton diplôme d'ingénieur (double diplôme ou Mastère Spécialisé).\n"
                    f"• **Parcours conseillé** : Prépa scientifique (MPSI/PCSI/MPI), école d'ingénieurs généraliste ou spécialisée, complétée par des projets et stages pratiques."
                )
            elif any(k in nom_low for k in ["médecin", "chirurgien", "infirmier", "dentiste", "kiné", "santé", "médical"]):
                reponse_ia = (
                    f"Pour exercer le métier de **{nom}** :\n\n"
                    f"• **Les écoles de commerce ne sont pas adaptées** : L'accès aux professions de santé est strictement encadré par l'État et passe obligatoirement par les facultés de médecine et formations universitaires en santé (filières PASS ou LAS en 1ère année post-bac).\n"
                    f"• **Cursus requis** : Après le bac (avec spécialités scientifiques fortement conseillées), tu candidates sur Parcoursup en PASS (Parcours Accès Santé Spécifique) ou LAS (Licence Accès Santé) avant de poursuivre les années d'études médicales hospitalières."
                )
            else:
                reponse_ia = (
                    f"Pour accéder à **{nom}**, le choix de l'école dépend de ton objectif :\n\n"
                    f"• **Formations de référence** : {etudes_str}.\n"
                    f"• **Écoles vs Université** : Les écoles spécialisées t'offrent un réseau et une forte immersion professionnelle, tandis que l'université propose des masters pointus et reconnus pour un coût très accessible.\n"
                    f"• Veux-tu qu'on regarde ensemble les conditions d'admission ou les concours associés ?"
                )

        # 2. Marketing vs Commercial / Vente
        elif any(w in q_low for w in ["marketing", "différence", "difference", "rapport avec le marketing"]):
            reponse_ia = (
                f"C'est une excellente question pour bien cerner la nuance entre **marketing** et **commercial** :\n\n"
                f"• **Le Marketing (en amont)** : Il analyse le marché, définit l'image de marque, identifie les besoins des consommateurs, conçoit les offres et génère des opportunités (campagnes digitales, publicités, positionnement produit).\n"
                f"• **Le Commercial (sur le terrain)** : Il intervient en contact direct avec les prospects et clients pour négocier, adapter la solution sur mesure, convaincre et conclure les ventes.\n\n"
                f"Pour le poste de **{nom}**, le rôle est avant tout orienté vers l'échange direct et la négociation concrète, même si une bonne compréhension des outils marketing est un sérieux atout !"
            )

        # 3. Niveau en mathématiques & exigences scolaires
        elif any(w in q_low for w in ["math", "maths", "mathématiques", "mathematiques", "niveau", "sélection", "selection", "concours"]):
            reponse_ia = (
                f"Concernant le niveau requis et les matières clés pour **{nom}** :\n\n"
                f"• **Importance des fondamentaux** : La rigueur, le sens de l'analyse et la capacité à structurer son raisonnement sont essentiels.\n"
                f"• **Ce que recherchent les recruteurs** : Au-delà des notes pures, ce sont la curiosité, la motivation, la capacité d'apprentissage et la méthode de travail qui font la différence.\n"
                f"• **Conseil** : Consolide tes bases actuelles au lycée et mets l'accent sur les projets concrets et stages pour valoriser ton dossier."
            )

        # 4. Salaire & Rémunération
        elif any(w in q_low for w in ["salaire", "gagne", "combien", "argent", "rémunération", "remuneration", "paye", "brut", "net", "prime"]):
            j = salaire.get('junior', '26 000 à 32 000')
            m = salaire.get('medior', '35 000 à 45 000')
            s = salaire.get('senior', '50 000+')
            reponse_ia = (
                f"Pour le métier de **{nom}**, voici les repères de rémunération :\n\n"
                f"• **Débutant (Junior)** : environ **{j} € bruts/an** (soit environ 1 800 à 2 200 € net/mois selon la structure).\n"
                f"• **Confirmé (3 à 5 ans)** : autour de **{m} € bruts/an**.\n"
                f"• **Senior / Expert** : peut atteindre ou dépasser **{s} € bruts/an**.\n\n"
                f"Des primes sur objectifs, intéressement ou avantages spécifiques peuvent s'y ajouter. "
                f"Souhaites-tu en savoir plus sur les perspectives d'évolution de carrière ?"
            )

        # 5. Études & Voies d'accès générales
        elif any(w in q_low for w in ["étude", "etude", "formation", "diplôme", "diplome", "bac", "prépa", "fac", "université", "licence", "master", "bts", "but", "spécialité"]):
            reponse_ia = (
                f"Pour accéder au métier de **{nom}**, le parcours type est le suivant :\n\n"
                f"• **Formations recommandées** : {etudes_str}.\n"
                f"• **Voie d'accès** : selon la filière, cela passe par des grandes écoles, l'université (Licence/Master/Doctorat) ou des instituts spécialisés reconnus par l'État.\n"
                f"• **Conseil au lycée** : privilégie les spécialités en lien avec les fondamentaux du métier pour construire un dossier Parcoursup cohérent.\n\n"
                f"Veux-tu que je t'explique les étapes de sélection ou les matières au programme ?"
            )

        # 6. Journée type & Missions concrètes
        elif any(w in q_low for w in ["journée", "journee", "quotidien", "semaine", "routine", "faire quoi", "mission", "tâche", "tache"]):
            reponse_ia = (
                f"Au quotidien, un **{nom}** partage son temps entre plusieurs activités concrètes :\n\n"
                f"1. **Missions clés** : {missions_str}.\n"
                f"2. **Gestion opérationnelle** : traitement des dossiers, coordination technique et prise de décision sur le terrain.\n"
                f"3. **Travail d'équipe & relationnel** : collaboration avec les équipes internes et partenaires externes.\n\n"
                f"Les journées sont rythmées et stimulantes. Quel aspect du quotidien t'intrigue le plus ?"
            )

        # 7. Inconvénients & Pression
        elif any(w in q_low for w in ["difficile", "dur", "inconvénient", "inconvenient", "défaut", "pression", "stress", "contrainte", "négatif", "fatigue"]):
            reponse_ia = (
                f"Comme tout métier d'envergure, **{nom}** comporte des exigences réelles :\n\n"
                f"• **Niveau d'engagement** : les responsabilités demandent de la méthode, de la concentration et de la rigueur.\n"
                f"• **Gestion des délais et imprévus** : savoir prioriser sous pression et garder son calme face aux aléas.\n"
                f"• **Veille constante** : les outils et les méthodes évoluent rapidement, il faut continuer à apprendre tout au long de sa carrière.\n\n"
                f"Ces défis sont valorisants dès lors que le métier correspond à tes centres d'intérêt réels."
            )

        # 8. Débouchés & Marché (vérification regex mot entier pour éviter les faux positifs)
        elif (any(w in q_low for w in ["débouché", "debouche", "avenir", "marché", "chômage"]) or
              bool(re.search(r'\b(ia|intelligence artificielle|robots?)\b', q_low))):
            reponse_ia = (
                f"Côté débouchés pour **{nom}** :\n\n"
                f"• C'est un secteur avec des **besoins dynamiques et pérennes**, car l'expertise humaine et technique y est centrale.\n"
                f"• Les opportunités existent dans les grands groupes, les PME/start-ups innovantes et les structures publiques.\n"
                f"• L'évolution technologique transforme les pratiques professionnelles, augmentant la valeur des experts bien formés.\n\n"
                f"As-tu une région ou un type d'organisation précis en tête pour ton futur poste ?"
            )

        # 9. Entreprises qui recrutent / Employeurs majeurs
        elif any(w in q_low for w in ["entreprise", "entreprises", "société", "societe", "sociétés", "societes", "boîte", "boite", "boîtes", "boites", "employeur", "employeurs", "recrute", "recruteur", "recruteurs", "qui embauche", "qui recrute", "où travailler", "ou travailler", "quel groupe"]):
            nom_low = nom.lower()
            if any(k in nom_low for k in ["robotique", "mécatronique", "automate"]):
                reponse_ia = (
                    f"En France, les principales entreprises et fleurons qui recrutent dans la **robotique** sont :\n\n"
                    f"• **Champions industriels & Logistique** : **Exotec** (la première licorne industrielle française avec ses robots logistiques autonomes), **Stäubli Robotics** (robots industriels de précision), **Siléane** (robotique et vision 3D en agro et pharmacie).\n"
                    f"• **Défense, Aéronautique & Sécurité** : **ECA Group** (drones et robotique navale autonome), **Safran** et **Thales** (systèmes mécatroniques et robotique embarquée).\n"
                    f"• **Start-ups & Cobotique** : **Isybot** (robots collaboratifs interactifs), **Naïo Technologies** (robots agricoles autonomes) et **Wandercraft** (exosquelettes robotisés médicaux).\n\n"
                    f"Souhaites-tu des conseils pour postuler ou savoir quelles compétences techniques précises ils recherchent ?"
                )
            elif any(k in nom_low for k in ["ia", "data", "intelligence artificielle", "machine learning"]):
                reponse_ia = (
                    f"En France, les principaux employeurs en **Intelligence Artificielle & Data** incluent :\n\n"
                    f"• **Pépites et licornes IA** : **Mistral AI**, **Hugging Face**, **Dataiku**, **Doctolib**, **Shift Technology**.\n"
                    f"• **Centres de R&D des géants mondiaux** : Google Research Paris, Meta FAIR Paris, Criteo AI Lab.\n"
                    f"• **Grands groupes industriels & bancaires** : Thales, Dassault Systèmes, BNP Paribas, TotalEnergies, Renault.\n"
                    f"• **Cabinets de conseil spécialisés** : Quantmetry, Artefact, Capgemini Invent.\n\n"
                    f"Aimerais-tu savoir quel niveau de diplôme est attendu par ces recruteurs ?"
                )
            elif any(k in nom_low for k in ["aéronautique", "aérospatial", "spatial"]):
                reponse_ia = (
                    f"En France, les leaders de l'**aéronautique et du spatial** qui recrutent des ingénieurs sont :\n\n"
                    f"• **Constructeurs & Systémiers** : **Airbus**, **Dassault Aviation**, **Safran**, **Thales Alenia Space**, **ArianeGroup**.\n"
                    f"• **Équipementiers & R&D** : Liebherr Aerospace, Latécoère, Collins Aerospace, Daher.\n"
                    f"• **Organismes de recherche** : ONERA, CNES."
                )
            elif any(k in nom_low for k in ["sylviculteur", "forêt", "agronome", "environnement"]):
                reponse_ia = (
                    f"Pour les métiers de la **gestion forestière et sylviculture**, les principaux employeurs en France sont :\n\n"
                    f"• **Secteur public & Institutionnel** : L'**ONF** (Office National des Forêts), le CNPF (Centre National de la Propriété Forestière), les Parcs Naturels Régionaux.\n"
                    f"• **Coopératives forestières & Entreprises privées** : Alliance Forêts Bois, Unisylva, COSYLVAL, ainsi que les cabinets d'experts forestiers indépendants et les exploitants forestiers certifiés PEFC/FSC."
                )
            else:
                reponse_ia = (
                    f"Pour le métier de **{nom}**, les principaux débouchés et recruteurs se trouvent parmi :\n\n"
                    f"• **Grandes entreprises et PME spécialisées** du secteur.\n"
                    f"• **Cabinets d'études, agences expertes et sociétés de conseil**.\n"
                    f"• **Organismes publics, collectivités territoriales et institutions nationales**.\n\n"
                    f"Veux-tu que nous regardions un secteur d'activité ou une zone géographique en particulier ?"
                )

        # 10. Réponse générale contextualisée
        else:
            reponse_ia = (
                f"C'est une excellente question sur le métier de **{nom}** !\n\n"
                f"{desc}\n\n"
                f"Ce qui caractérise particulièrement cette profession, c'est l'équilibre entre expertise technique et impact concret au quotidien. "
                f"Tu peux t'y épanouir si tu aimes : {missions_str.lower()}.\n\n"
                f"Dis-moi : quel aspect souhaites-tu explorer plus en profondeur (études, salaires, journée type ou débouchés) ?"
            )

    # Suggestions de rebond pour poursuivre la discussion
    suggestions = [
        "Quelles sont les meilleures études pour ce métier ?",
        "Quelle est la progression de salaire possible ?",
        "⚖️ Quels sont les plus gros avantages et inconvénients ?",
        "À quoi ressemble une journée de travail type ?",
    ]

    return {
        "success": True,
        "metier_nom": nom,
        "reponse_ia": reponse_ia,
        "suggestions": suggestions
    }


# ==============================================================================
# ROUTES OPEN DATA FRANCE (SQLITE DÉTERMINISTE + CORPUS RAG SÉMANTIQUE)
# ==============================================================================
@router.get("/opendata/parcoursup-sql")
async def get_parcoursup_sql_gaps(
    moyenne: float = 14.0,
    filiere: Optional[str] = None,
    ville: Optional[str] = None,
    limit: int = 10,
):
    """
    Requête SQL déterministe (zéro LLM) sur `data/processed/orientation_data.sqlite`
    comparant la moyenne de l'élève aux formations Parcoursup (Voie A Ambition vs Voie B Secours).
    """
    try:
        from scripts.data.query_engine import query_parcoursup_gap_sql
        return query_parcoursup_gap_sql(
            moyenne_eleve=moyenne,
            filiere_keyword=filiere,
            ville=ville,
            limit=limit,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/opendata/lycees-ival")
async def get_lycees_ival_sql(ville: Optional[str] = None, limit: int = 10):
    """
    Requête SQL déterministe sur les Indicateurs de Valeur Ajoutée des Lycées (DEPP IVAL).
    """
    try:
        from scripts.data.query_engine import query_lycees_ival_sql
        return {
            "ville": ville,
            "lycees": query_lycees_ival_sql(ville=ville, limit=limit),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/opendata/rag-search")
async def get_rag_semantic_chunks(q: str, limit: int = 5):
    """
    Recherche dans les chunks sémantiques `data/processed/rag_corpus/metiers_formations_chunks.jsonl`.
    """
    try:
        from scripts.data.query_engine import search_rag_chunks
        return {
            "query": q,
            "chunks": search_rag_chunks(keyword=q, limit=limit),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# PHASE 3 : ROUTE PRINCIPALE DU DIAGNOSTIC & DOUBLE TRAJECTOIRE PERSISTÉE
# ==============================================================================
try:
    from fastapi import Body, Depends
    from fastapi.responses import Response
    from sqlmodel import Session
    from database import get_session
    from routes.profile import get_current_uid
    from services.diagnostic_service import DiagnosticRunResponse, run_student_diagnostic
    from services.pdf_service import generate_strategic_pdf
except ImportError:
    from fastapi import Body, Depends
    from fastapi.responses import Response
    from sqlmodel import Session
    from backend.database import get_session
    from backend.routes.profile import get_current_uid
    from backend.services.diagnostic_service import DiagnosticRunResponse, run_student_diagnostic
    from backend.services.pdf_service import generate_strategic_pdf


class DiagnosticRunRequest(BaseModel):
    target_domain: Optional[str] = None


@router.post("/diagnostic/run", response_model=DiagnosticRunResponse)
def run_diagnostic_endpoint(
    payload: Optional[DiagnosticRunRequest] = Body(default=None),
    target_domain: Optional[str] = None,
    uid: str = Depends(get_current_uid),
    db: Session = Depends(get_session),
):
    """
    Analyse le profil et les notes de l'élève connecté (X-User-Id), sélectionne
    automatiquement la meilleure voie AMBITION et la meilleure voie REALISTE (Plan B)
    en SQL déterministe, persiste ces 2 pistes dans `target_tracks` et retourne
    la synthèse stratégique complète enrichie par le contexte RAG et le LLM.
    """
    effective_domain = (payload.target_domain if payload and payload.target_domain else target_domain)
    try:
        return run_student_diagnostic(user_id=uid, db=db, target_domain=effective_domain)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur lors de l'exécution du diagnostic : {str(e)}")


@router.get("/diagnostic/export-pdf")
def export_diagnostic_pdf_endpoint(
    target_domain: Optional[str] = None,
    user_id: Optional[str] = None,
    x_user_id: Optional[str] = Header(default=None, alias="X-User-Id"),
    db: Session = Depends(get_session),
):
    """
    Skill 12 : Génère à la volée la Fiche Stratégique de Préparation à l'Entretien
    d'Orientation (1 page A4 recto stricte) pour le Professeur Principal ou le Psy-EN.
    Accepte `X-User-Id` en en-tête ou `?user_id=` en paramètre d'URL (pour ouverture directe navigateur).
    """
    uid = (x_user_id or user_id or "").strip()
    if not uid:
        raise HTTPException(status_code=401, detail="En-tête X-User-Id ou paramètre user_id requis.")
    try:
        pdf_bytes = generate_strategic_pdf(user_id=uid, db=db, target_domain=target_domain)
        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={
                "Content-Disposition": 'inline; filename="fiche_orientation.pdf"',
                "Cache-Control": "no-store",
            },
        )
    except (ValueError, KeyError) as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur lors de la génération du PDF : {str(e)}")