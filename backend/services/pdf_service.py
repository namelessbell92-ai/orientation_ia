# -*- coding: utf-8 -*-
"""
Service Métier Skill 12 : Générateur de Fiche Stratégique PDF (1 Page A4 Recto Stricte)
=======================================================================================

Génère à la volée une fiche PDF institutionnelle, sobre et dense (1 page A4 recto stricte,
marges de 1,2 cm, palette bleu marine / ardoise / blanc) destinée au Professeur Principal
ou au Psychologue de l'Éducation Nationale (Psy-EN).

Structure en 4 blocs visuels :
  1. En-tête Institutionnel & Profil de l'Élève (Moyenne générale vs Moyenne matières dominantes)
  2. La Double Trajectoire côte à côte (Voie A Ambition vs Voie B Sécurité / Tremplin)
  3. Plan de Redressement & 3 Actions Prioritaires Hebdomadaires
  4. Questions Stratégiques Préparées pour le Professeur Principal / Psy-EN
"""

from __future__ import annotations

import io
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    KeepInFrame,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)
from sqlalchemy import text
from sqlmodel import Session, select

try:
    from models.student import AcademicRecord, StudentProfile, TargetTrack, TrackType, current_school_year
    from services.diagnostic_service import (
        DiagnosticRunResponse,
        StudentDiagnosticSummary,
        StrategicSynthesis,
        TrackDiagnosticDetail,
        _build_priority_actions,
        _compute_student_grades,
        _compute_subject_gaps,
        _decode_student_passions,
        _load_referentiel,
        _resolve_domain_profile,
        run_student_diagnostic,
    )
except ImportError:
    from backend.models.student import AcademicRecord, StudentProfile, TargetTrack, TrackType, current_school_year
    from backend.services.diagnostic_service import (
        DiagnosticRunResponse,
        StudentDiagnosticSummary,
        StrategicSynthesis,
        TrackDiagnosticDetail,
        _build_priority_actions,
        _compute_student_grades,
        _compute_subject_gaps,
        _decode_student_passions,
        _load_referentiel,
        _resolve_domain_profile,
        run_student_diagnostic,
    )


# ---------------------------------------------------------------------------
# PALETTE INSTITUTIONNELLE (BLEU MARINE / ARDOISE / BLANC)
# ---------------------------------------------------------------------------
NAVY_DARK = colors.HexColor("#0F172A")
NAVY_PRIMARY = colors.HexColor("#1E3A8A")
SLATE_DARK = colors.HexColor("#1E293B")
SLATE_TEXT = colors.HexColor("#334155")
SLATE_MUTED = colors.HexColor("#64748B")
SLATE_BORDER = colors.HexColor("#CBD5E1")
BG_LIGHT = colors.HexColor("#F8FAFC")
BG_ICE = colors.HexColor("#EFF6FF")
BG_EMERALD = colors.HexColor("#ECFDF5")
TEXT_EMERALD = colors.HexColor("#047857")
BG_AMBER = colors.HexColor("#FFFBEB")
WHITE = colors.HexColor("#FFFFFF")


def _register_fonts() -> Tuple[str, str, str]:
    """
    Enregistre une famille de polices TrueType système (Segoe UI / Arial / DejaVuSans)
    avec `registerFontFamily` pour supporter les balises `<b>` et `<i>` dans ReportLab.
    """
    candidates = [
        (
            "AppSans",
            Path("C:/Windows/Fonts/segoeui.ttf"),
            Path("C:/Windows/Fonts/segoeuib.ttf"),
            Path("C:/Windows/Fonts/segoeuii.ttf"),
        ),
        (
            "AppSans",
            Path("C:/Windows/Fonts/arial.ttf"),
            Path("C:/Windows/Fonts/arialbd.ttf"),
            Path("C:/Windows/Fonts/ariali.ttf"),
        ),
        (
            "AppSans",
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf"),
        ),
    ]
    for family, reg, bold, ital in candidates:
        if reg.exists() and bold.exists():
            try:
                reg_name = f"{family}-Regular"
                bold_name = f"{family}-Bold"
                ital_name = f"{family}-Italic"
                pdfmetrics.registerFont(TTFont(reg_name, str(reg)))
                pdfmetrics.registerFont(TTFont(bold_name, str(bold)))
                pdfmetrics.registerFont(TTFont(ital_name, str(ital if ital.exists() else reg)))
                pdfmetrics.registerFontFamily(
                    reg_name,
                    normal=reg_name,
                    bold=bold_name,
                    italic=ital_name,
                    boldItalic=bold_name,
                )
                return reg_name, bold_name, ital_name
            except Exception:
                pass
    return "Helvetica", "Helvetica-Bold", "Helvetica-Oblique"


def _format_grade_level(grade_level: str) -> str:
    mapping = {
        "TROISIEME": "Troisième (3e)",
        "SECONDE": "Seconde Générale & Technologique",
        "PREMIERE": "Première Générale",
        "TERMINALE": "Terminale Générale",
    }
    return mapping.get(grade_level.upper(), grade_level)


def _compute_dominant_average(
    db: Session, profile: StudentProfile, general_avg: float
) -> Tuple[float, List[str]]:
    records = db.exec(
        select(AcademicRecord).where(AcademicRecord.student_profile_id == profile.id)
    ).all()
    if not records:
        return general_avg, []

    latest_year = max(r.school_year for r in records)
    year_records = [r for r in records if r.school_year == latest_year]
    latest_tri = max(r.trimester for r in year_records)
    tri_records = sorted(
        [r for r in year_records if r.trimester == latest_tri],
        key=lambda x: x.subject.lower(),
    )

    spec_lower = {s.lower() for s in (profile.specialties or [])}
    dominant_grades = [
        float(r.grade)
        for r in tri_records
        if any(sp in r.subject.lower() or r.subject.lower() in sp for sp in spec_lower)
    ]
    if not dominant_grades:
        dominant_grades = [float(r.grade) for r in tri_records]

    dominant_avg = round(sum(dominant_grades) / len(dominant_grades), 2) if dominant_grades else general_avg
    details = [
        f"<b>{r.subject}</b> : {r.grade:.1f}/20"
        + (f" <i>(cl. {r.class_average:.1f})</i>" if r.class_average is not None else "")
        for r in tri_records
    ]
    return dominant_avg, details


def _load_or_run_diagnostic(
    user_id: str,
    db: Session,
    target_domain: Optional[str] = None,
) -> DiagnosticRunResponse:
    """
    Récupère instantanément le dernier diagnostic persisté dans `target_tracks`
    (ou lance `run_student_diagnostic` si aucune piste n'est encore enregistrée
    ou si un nouveau `target_domain` différent est forcé).
    """
    profile = db.exec(select(StudentProfile).where(StudentProfile.user_id == user_id)).first()
    if profile is None:
        raise ValueError(f"Profil introuvable pour user_id='{user_id}'.")

    tracks = db.exec(
        select(TargetTrack).where(TargetTrack.student_profile_id == profile.id)
    ).all()
    by_type = {t.type: t for t in tracks}

    if (
        TrackType.AMBITION not in by_type
        or TrackType.REALISTE not in by_type
        or (target_domain and target_domain.strip().lower() != (profile.target_domain or "").strip().lower())
    ):
        return run_student_diagnostic(user_id=user_id, db=db, target_domain=target_domain)

    # Reconstruction déterministe rapide (< 10 ms) depuis les pistes persistées en base
    moyenne_eleve, subject_grades = _compute_student_grades(db, profile.id)
    effective_domain = (target_domain or profile.target_domain or "Ingénierie & Sciences").strip()
    domain_cfg = _resolve_domain_profile(effective_domain, profile.specialties, profile.interests)
    referentiel = _load_referentiel()
    filieres_by_id = {f["id"]: f for f in referentiel.get("filieres", [])}

    t_amb = by_type[TrackType.AMBITION]
    t_rea = by_type[TrackType.REALISTE]

    amb_ref = filieres_by_id.get(t_amb.referentiel_filiere_id or domain_cfg["ambition_ref_id"], {})
    rea_ref = filieres_by_id.get(t_rea.referentiel_filiere_id or domain_cfg["realiste_ref_id"], {})

    def _fetch_f_meta(fid: Optional[str], default_seuil: float, default_taux: float, default_grp: int) -> Dict[str, Any]:
        default_lbl = (
            "Groupe 1 : Cibles Top Concours (X, ENS, HEC)"
            if default_grp == 1
            else (
                "Groupe 2 : Cibles Grandes Écoles Nationales"
                if default_grp == 2
                else "Groupe 3 : Concours Communs & Réseau Régional"
            )
        )
        fallback = {
            "etablissement": "",
            "ville": "France",
            "filiere": "Formation",
            "taux_acces": default_taux,
            "seuil_moyenne_estime": default_seuil,
            "selectivity_group": default_grp,
            "ranking_label": default_lbl,
            "source_citation": "Source : Données MESR Open Data / Classement L'Étudiant",
        }
        if not fid:
            return fallback
        row = db.execute(
            text(
                "SELECT etablissement, ville, filiere, taux_acces, seuil_moyenne_estime, "
                "selectivity_group, ranking_label, source_citation "
                "FROM parcoursup_formations WHERE formation_id = :fid"
            ),
            {"fid": fid},
        ).mappings().first()
        return dict(row) if row else fallback

    f_amb = _fetch_f_meta(t_amb.formation_id, 16.0, 20.0, 2)
    f_rea = _fetch_f_meta(t_rea.formation_id, 12.0, 80.0, 3)

    gaps_amb = _compute_subject_gaps(
        subject_grades, amb_ref.get("seuils_matieres") or {"Mathématiques": 15.5, "Physique-Chimie": 15.0}
    )
    gaps_rea = _compute_subject_gaps(
        subject_grades, rea_ref.get("seuils_matieres") or {"Mathématiques": 12.5, "Physique-Chimie": 12.0}
    )
    passions = _decode_student_passions(profile.interests or [], referentiel.get("decodeur_talents") or {})
    actions = _build_priority_actions(gaps_amb, t_amb.formation_name, profile.specialties or [])

    gap_amb_val = round(moyenne_eleve - float(f_amb["seuil_moyenne_estime"]), 2)
    gap_rea_val = round(moyenne_eleve - float(f_rea["seuil_moyenne_estime"]), 2)

    return DiagnosticRunResponse(
        success=True,
        computed_at=t_amb.gap_computed_at or datetime.now(),
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
            track_id=t_amb.id,
            type=TrackType.AMBITION,
            formation_id=str(t_amb.formation_id or ""),
            referentiel_filiere_id=str(t_amb.referentiel_filiere_id or domain_cfg["ambition_ref_id"]),
            formation_name=t_amb.formation_name,
            etablissement=str(f_amb.get("etablissement") or ""),
            ville=str(f_amb.get("ville") or ""),
            filiere=str(f_amb.get("filiere") or ""),
            taux_acces_pct=float(f_amb.get("taux_acces") or 20.0),
            seuil_moyenne_estime=float(f_amb.get("seuil_moyenne_estime") or 16.0),
            estimated_gap=gap_amb_val,
            selectivity_group=int(f_amb.get("selectivity_group") or 2),
            ranking_label=str(f_amb.get("ranking_label") or "Groupe 2 : Cibles Grandes Écoles Nationales"),
            source_citation=str(f_amb.get("source_citation") or "Source : Données MESR Open Data / Classement L'Étudiant"),
            verdict_accessibilite="Objectif exigeant avec plan de remédiation" if gap_amb_val < 0 else "En ligne avec les attendus",
            requirements=list(t_amb.requirements or []),
            subject_gaps=gaps_amb,
            casseur_de_mythes=amb_ref.get("casseur_de_mythes") or {},
        ),
        parcours_realiste=TrackDiagnosticDetail(
            track_id=t_rea.id,
            type=TrackType.REALISTE,
            formation_id=str(t_rea.formation_id or ""),
            referentiel_filiere_id=str(t_rea.referentiel_filiere_id or domain_cfg["realiste_ref_id"]),
            formation_name=t_rea.formation_name,
            etablissement=str(f_rea.get("etablissement") or ""),
            ville=str(f_rea.get("ville") or ""),
            filiere=str(f_rea.get("filiere") or ""),
            taux_acces_pct=float(f_rea.get("taux_acces") or 80.0),
            seuil_moyenne_estime=float(f_rea.get("seuil_moyenne_estime") or 12.0),
            estimated_gap=gap_rea_val,
            selectivity_group=int(f_rea.get("selectivity_group") or 3),
            ranking_label=str(f_rea.get("ranking_label") or "Groupe 3 : Concours Communs & Réseau Régional"),
            source_citation=str(f_rea.get("source_citation") or "Source : Données MESR Open Data / Classement L'Étudiant"),
            verdict_accessibilite="Voie sécurisée (marge positive)" if gap_rea_val >= 0 else "Voie réaliste à consolider",
            requirements=list(t_rea.requirements or []),
            subject_gaps=gaps_rea,
            casseur_de_mythes=rea_ref.get("casseur_de_mythes") or {},
        ),
        contexte_rag=[],
        actions_prioritaires=actions,
        synthese_strategique=StrategicSynthesis(
            diagnostic_lucidite_gap="",
            conditions_non_negociables=list(t_amb.requirements or []),
            analyse_exigences_terrain="",
            valorisation_passions=passions,
            actions_prioritaires=actions,
            discours_coach_llm="",
        ),
    )


def _build_interview_questions(diag: DiagnosticRunResponse) -> List[str]:
    amb = diag.parcours_ambition
    rea = diag.parcours_realiste
    top_gap_subj = (
        diag.actions_prioritaires[0].matiere_ou_axe
        if diag.actions_prioritaires
        else "mes spécialités majeures"
    )

    return [
        (
            f"<b>1. Calibrage Voie A ({amb.filiere}) :</b> « Au vu des admissions historiques des élèves de notre lycée "
            f"vers <i>{amb.formation_name[:68]}</i> (seuil estimé {amb.seuil_moyenne_estime}/20), quel rang dans la classe "
            f"et quelle cible de moyenne au prochain trimestre dois-je atteindre pour sécuriser un avis Très Favorable ? »"
        ),
        (
            f"<b>2. Stratégie de progression en {top_gap_subj} :</b> « J'ai identifié un écart de {amb.estimated_gap:+.2f} pts "
            f"sur mon objectif d'ambition et mis en place un créneau hebdomadaire dédié. Quels points méthodologiques "
            f"précis me conseillez-vous de travailler en priorité sur mes prochains devoirs surveillés ? »"
        ),
        (
            f"<b>3. Validation du Plan B Tremplin ({rea.filiere}) :</b> « En parallèle de mon vœu d'ambition, je sécurise "
            f"<i>{rea.formation_name[:68]}</i> (taux d'accès {rea.taux_acces_pct:.0f}%). Quelles autres formations "
            f"à passerelles (BUT, licences sélectives, prépas de proximité) recommandez-vous d'ajouter à ma liste Parcoursup ? »"
        ),
    ]


def generate_strategic_pdf(
    user_id: str,
    db: Session,
    target_domain: Optional[str] = None,
) -> bytes:
    """
    Génère en mémoire le PDF A4 1 page stricte du dernier diagnostic de l'élève.
    """
    diag = _load_or_run_diagnostic(user_id=user_id, db=db, target_domain=target_domain)
    profile = db.exec(select(StudentProfile).where(StudentProfile.user_id == user_id)).first()
    if profile is None:
        raise KeyError(f"Profil introuvable pour user_id='{user_id}'.")

    dominant_avg, subject_pills = _compute_dominant_average(
        db=db,
        profile=profile,
        general_avg=diag.resume_eleve.general_average,
    )

    font_reg, font_bold, font_ital = _register_fonts()
    buffer = io.BytesIO()

    margin = 1.2 * cm
    page_w, page_h = A4
    usable_w = page_w - (2 * margin)
    usable_h = page_h - (2 * margin)

    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=margin,
        rightMargin=margin,
        topMargin=margin,
        bottomMargin=margin,
        title="Fiche Stratégique de Préparation à l'Entretien d'Orientation",
        author="Orientation IA — Coach Stratégique Parcoursup & ONISEP",
    )

    base_styles = getSampleStyleSheet()

    st_header_title = ParagraphStyle(
        "HeaderTitle",
        parent=base_styles["Normal"],
        fontName=font_bold,
        fontSize=13.0,
        leading=15.5,
        textColor=WHITE,
    )
    st_header_sub = ParagraphStyle(
        "HeaderSub",
        parent=base_styles["Normal"],
        fontName=font_ital,
        fontSize=7.8,
        leading=10,
        textColor=colors.HexColor("#BFDBFE"),
    )
    st_header_right = ParagraphStyle(
        "HeaderRight",
        parent=base_styles["Normal"],
        fontName=font_reg,
        fontSize=8.0,
        leading=10.5,
        alignment=TA_RIGHT,
        textColor=WHITE,
    )
    st_section_banner = ParagraphStyle(
        "SectionBanner",
        parent=base_styles["Normal"],
        fontName=font_bold,
        fontSize=9.2,
        leading=11.5,
        textColor=NAVY_PRIMARY,
    )
    st_body = ParagraphStyle(
        "BodyCompact",
        parent=base_styles["Normal"],
        fontName=font_reg,
        fontSize=8.0,
        leading=10.6,
        textColor=SLATE_TEXT,
    )
    st_body_small = ParagraphStyle(
        "BodySmall",
        parent=base_styles["Normal"],
        fontName=font_reg,
        fontSize=7.5,
        leading=9.8,
        textColor=SLATE_TEXT,
    )
    st_kpi_label = ParagraphStyle(
        "KpiLabel",
        parent=base_styles["Normal"],
        fontName=font_bold,
        fontSize=7.1,
        leading=9,
        textColor=SLATE_MUTED,
        alignment=TA_CENTER,
    )
    st_kpi_val = ParagraphStyle(
        "KpiVal",
        parent=base_styles["Normal"],
        fontName=font_bold,
        fontSize=11.5,
        leading=13.5,
        textColor=NAVY_DARK,
        alignment=TA_CENTER,
    )
    st_track_header = ParagraphStyle(
        "TrackHeader",
        parent=base_styles["Normal"],
        fontName=font_bold,
        fontSize=8.5,
        leading=10.5,
        textColor=WHITE,
    )
    st_footer = ParagraphStyle(
        "FooterNote",
        parent=base_styles["Normal"],
        fontName=font_ital,
        fontSize=7.0,
        leading=9.0,
        textColor=SLATE_MUTED,
        alignment=TA_CENTER,
    )

    elements: List[Any] = []

    # =========================================================================
    # BLOC 1 : EN-TÊTE INSTITUTIONNEL & PROFIL DE L'ÉLÈVE
    # =========================================================================
    today_str = datetime.now().strftime("%d/%m/%Y")
    school_year = current_school_year()
    classe_label = _format_grade_level(diag.resume_eleve.grade_level)

    header_left = [
        Paragraph("FICHE STRATÉGIQUE DE PRÉPARATION À L'ENTRETIEN D'ORIENTATION", st_header_title),
        Spacer(1, 2),
        Paragraph(
            "Généré via Orientation IA — Données certifiées Open Data Parcoursup (MESR) &amp; ONISEP Idéo2",
            st_header_sub,
        ),
    ]
    header_right = [
        Paragraph(
            f"<b>Classe :</b> {classe_label}<br/>"
            f"<b>Année scolaire :</b> {school_year}<br/>"
            f"<b>Édité le :</b> {today_str}",
            st_header_right,
        )
    ]

    header_table = Table(
        [[header_left, header_right]],
        colWidths=[usable_w * 0.68, usable_w * 0.32],
    )
    header_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), NAVY_DARK),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(header_table)
    elements.append(Spacer(1, 5))

    spes_str = ", ".join(diag.resume_eleve.specialties) or "Tronc commun général"
    passions_items = diag.synthese_strategique.valorisation_passions
    passions_str = (
        " ; ".join(f"<b>{p.passion_brute}</b> ({p.competence_academique.split(',')[0]})" for p in passions_items[:3])
        if passions_items
        else "Non renseignées"
    )
    notes_inline = "  |  ".join(subject_pills) if subject_pills else "Aucun bulletin détaillé saisi"

    kpi_row = [
        [
            Paragraph("MOYENNE GÉNÉRALE", st_kpi_label),
            Paragraph("MOYENNE DOMINANTES / SPÉ.", st_kpi_label),
            Paragraph("CAP D'ORIENTATION VISÉ", st_kpi_label),
            Paragraph("ÉCART VOIE A (AMBITION)", st_kpi_label),
        ],
        [
            Paragraph(f"{diag.resume_eleve.general_average:.2f} / 20", st_kpi_val),
            Paragraph(f"{dominant_avg:.2f} / 20", st_kpi_val),
            Paragraph(f"<b>{diag.resume_eleve.target_domain}</b>", st_body),
            Paragraph(
                f"{diag.parcours_ambition.estimated_gap:+.2f} pt (seuil {diag.parcours_ambition.seuil_moyenne_estime}/20)",
                st_kpi_val,
            ),
        ],
    ]
    kpi_table = Table(
        kpi_row,
        colWidths=[usable_w * 0.20, usable_w * 0.23, usable_w * 0.30, usable_w * 0.27],
    )
    kpi_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), BG_LIGHT),
                ("BOX", (0, 0), (-1, -1), 0.7, SLATE_BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.4, SLATE_BORDER),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    elements.append(kpi_table)
    elements.append(Spacer(1, 3))

    profile_meta = Table(
        [
            [
                Paragraph(
                    f"<b>Spécialités :</b> {spes_str}   •   "
                    f"<b>Relevé trimestriel :</b> {notes_inline}<br/>"
                    f"<b>Talents &amp; centres d'intérêt transférables :</b> {passions_str}",
                    st_body_small,
                )
            ]
        ],
        colWidths=[usable_w],
    )
    profile_meta.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), BG_ICE),
                ("BOX", (0, 0), (-1, -1), 0.5, SLATE_BORDER),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    elements.append(profile_meta)
    elements.append(Spacer(1, 6))

    # =========================================================================
    # BLOC 2 : LA DOUBLE TRAJECTOIRE (VOIE A AMBITION VS VOIE B SÉCURITÉ)
    # =========================================================================
    elements.append(
        Paragraph("1. STRATÉGIE À DEUX VITESSES : DOUBLE TRAJECTOIRE PARCOURSUP (VOIE A &amp; PLAN B)", st_section_banner)
    )
    elements.append(Spacer(1, 3))

    amb = diag.parcours_ambition
    rea = diag.parcours_realiste

    amb_gaps_str = ", ".join(
        f"{g.subject}: {g.student_grade}/20 (attendu {g.expected_grade}/20, <b>{g.delta:+.1f}</b>)"
        for g in amb.subject_gaps[:3]
    )
    amb_reqs_bullets = "<br/>".join(f"• {req}" for req in amb.requirements[:3])
    rea_reqs_bullets = "<br/>".join(f"• {req}" for req in rea.requirements[:3])

    col_w = usable_w * 0.5

    amb_group_color = "#4C1D95" if amb.selectivity_group == 1 else "#1E3A8A"
    rea_group_color = "#047857" if rea.selectivity_group == 3 else "#1E3A8A"

    track_a_content = [
        Paragraph(
            f"<font color='{amb_group_color}'><b>[{amb.ranking_label}]</b></font><br/>"
            f"<b>{amb.formation_name}</b><br/>"
            f"<i>Code Parcoursup #{amb.formation_id} — {amb.ville or 'France'} ({amb.filiere})</i>",
            st_body,
        ),
        Spacer(1, 2),
        Paragraph(
            f"• <b>Seuil estimé d'admission :</b> {amb.seuil_moyenne_estime:.2f}/20 "
            f"(Taux d'accès : {amb.taux_acces_pct:.0f}%)<br/>"
            f"• <b>Gap actuel à combler :</b> <b>{amb.estimated_gap:+.2f} points</b> "
            f"({amb.verdict_accessibilite})<br/>"
            f"• <b>Écarts par matière cible :</b> {amb_gaps_str}",
            st_body_small,
        ),
        Spacer(1, 2),
        Paragraph(f"<b>Attendus &amp; conditions clés de sélection :</b><br/>{amb_reqs_bullets}", st_body_small),
        Spacer(1, 2),
        Paragraph(
            f"<i><font color='#64748B'>{amb.source_citation} — Données certifiées MESR / Classements de référence</font></i>",
            st_body_small,
        ),
    ]

    track_b_content = [
        Paragraph(
            f"<font color='{rea_group_color}'><b>[{rea.ranking_label}]</b></font><br/>"
            f"<b>{rea.formation_name}</b><br/>"
            f"<i>Code Parcoursup #{rea.formation_id} — {rea.ville or 'France'} ({rea.filiere})</i>",
            st_body,
        ),
        Spacer(1, 2),
        Paragraph(
            f"• <b>Taux d'accès officiel :</b> <b>{rea.taux_acces_pct:.0f}%</b> "
            f"(Seuil estimé : {rea.seuil_moyenne_estime:.2f}/20)<br/>"
            f"• <b>Marge de sécurité :</b> <b>{rea.estimated_gap:+.2f} points</b> "
            f"({rea.verdict_accessibilite})<br/>"
            f"• <b>Rôle stratégique :</b> Sécuriser l'admission post-bac tout en visant le haut de promotion.",
            st_body_small,
        ),
        Spacer(1, 2),
        Paragraph(f"<b>Passerelles &amp; poursuite d'études :</b><br/>{rea_reqs_bullets}", st_body_small),
        Spacer(1, 2),
        Paragraph(
            f"<i><font color='#64748B'>{rea.source_citation} — Données certifiées MESR / Classements de référence</font></i>",
            st_body_small,
        ),
    ]

    tracks_table = Table(
        [
            [
                Paragraph(
                    f"VOIE A — OBJECTIF D'EXCELLENCE (GROUPE {amb.selectivity_group})",
                    st_track_header,
                ),
                Paragraph(
                    f"VOIE B — SÉCURITÉ &amp; TREMPLIN (GROUPE {rea.selectivity_group})",
                    st_track_header,
                ),
            ],
            [track_a_content, track_b_content],
        ],
        colWidths=[col_w, col_w],
    )
    tracks_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, 0), colors.HexColor("#4C1D95") if amb.selectivity_group == 1 else NAVY_PRIMARY),
                ("BACKGROUND", (1, 0), (1, 0), TEXT_EMERALD),
                ("BACKGROUND", (0, 1), (0, 1), BG_AMBER),
                ("BACKGROUND", (1, 1), (1, 1), BG_EMERALD),
                ("BOX", (0, 0), (-1, -1), 0.8, SLATE_BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.6, SLATE_BORDER),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, 0), 4),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 4),
                ("TOPPADDING", (0, 1), (-1, 1), 6),
                ("BOTTOMPADDING", (0, 1), (-1, 1), 6),
            ]
        )
    )
    elements.append(tracks_table)
    elements.append(Spacer(1, 6))

    # =========================================================================
    # BLOC 3 : PLAN DE REDRESSEMENT & 3 ACTIONS PRIORITAIRES HEBDOMADAIRES
    # =========================================================================
    elements.append(
        Paragraph("2. PLAN DE REDRESSEMENT &amp; ACTIONS PRIORITAIRES HEBDOMADAIRES", st_section_banner)
    )
    elements.append(Spacer(1, 3))

    action_rows: List[List[Any]] = [
        [
            Paragraph("<b>#</b>", st_track_header),
            Paragraph("<b>Matière / Axe</b>", st_track_header),
            Paragraph("<b>Objectif Chiffré</b>", st_track_header),
            Paragraph("<b>Protocole d'Exécution Hebdomadaire</b>", st_track_header),
            Paragraph("<b>Volume</b>", st_track_header),
        ]
    ]
    for act in diag.actions_prioritaires[:3]:
        action_rows.append(
            [
                Paragraph(f"<b>{act.ordre}</b>", st_body_small),
                Paragraph(f"<b>{act.matiere_ou_axe}</b>", st_body_small),
                Paragraph(act.objectif_chiffre, st_body_small),
                Paragraph(act.action_concrete_hebdo, st_body_small),
                Paragraph(f"<b>{act.duree_hebdo_recommandee}</b>", st_body_small),
            ]
        )

    actions_table = Table(
        action_rows,
        colWidths=[
            usable_w * 0.04,
            usable_w * 0.18,
            usable_w * 0.27,
            usable_w * 0.39,
            usable_w * 0.12,
        ],
    )
    actions_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), SLATE_DARK),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [WHITE, BG_LIGHT]),
                ("BOX", (0, 0), (-1, -1), 0.7, SLATE_BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.4, SLATE_BORDER),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    elements.append(actions_table)
    elements.append(Spacer(1, 6))

    # =========================================================================
    # BLOC 4 : QUESTIONS PRÉPARÉES POUR LE PROFESSEUR PRINCIPAL / PSY-EN
    # =========================================================================
    elements.append(
        Paragraph("3. QUESTIONS PRÉPARÉES POUR L'ENTRETIEN (PROFESSEUR PRINCIPAL / PSY-EN)", st_section_banner)
    )
    elements.append(Spacer(1, 3))

    questions = _build_interview_questions(diag)
    q_content: List[Any] = []
    for idx, q in enumerate(questions):
        q_content.append(Paragraph(q, st_body_small))
        if idx < len(questions) - 1:
            q_content.append(Spacer(1, 3))

    questions_table = Table([[q_content]], colWidths=[usable_w])
    questions_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), BG_LIGHT),
                ("BOX", (0, 0), (-1, -1), 0.7, SLATE_BORDER),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    elements.append(questions_table)
    elements.append(Spacer(1, 5))

    visa_table = Table(
        [
            [
                Paragraph(
                    "<b>Observations &amp; Recommandations du Professeur Principal / Psy-EN :</b><br/><br/>",
                    st_body_small,
                ),
                Paragraph(
                    "<b>Visa Établissement / Date de l'entretien :</b><br/><br/>",
                    st_body_small,
                ),
            ]
        ],
        colWidths=[usable_w * 0.68, usable_w * 0.32],
    )
    visa_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), WHITE),
                ("BOX", (0, 0), (-1, -1), 0.6, SLATE_BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.5, SLATE_BORDER),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(visa_table)
    elements.append(Spacer(1, 3))

    elements.append(
        Paragraph(
            "Document d'aide à la décision pédagogique — Les seuils et taux d'accès proviennent des données consolidées "
            "Open Data du Ministère de l'Enseignement Supérieur et de la Recherche (Parcoursup) et de l'ONISEP.",
            st_footer,
        )
    )

    single_page_frame = KeepInFrame(
        maxWidth=usable_w,
        maxHeight=usable_h,
        content=elements,
        mode="shrink",
    )

    doc.build([single_page_frame])
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes
