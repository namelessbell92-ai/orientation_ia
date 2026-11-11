"""
Modèles élèves (SQLModel) — Profil, Relevés de notes, Double Trajectoire, Planning, Checkpoints.

Conventions :
  - `user_id` = UID Firebase Auth (unique).
  - Les champs liste / dictionnaire sont stockés en colonne JSON (TEXT JSON sous SQLite).
    ⚠️ Toujours RÉASSIGNER la valeur (profile.interests = [...]) plutôt que muter en place,
    sinon SQLAlchemy ne détecte pas le changement.
  - Tous les calculs d'écart (gap) restent déterministes et faits côté SQL/Python, jamais par un LLM.
"""

import uuid
from datetime import date, datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

from sqlalchemy import JSON, CheckConstraint, Column, String, Table, UniqueConstraint
from sqlmodel import Field, Relationship, SQLModel


# ---------------------------------------------------------------------------
# Table Open Data référencée (stub) : déclarée uniquement pour que SQLAlchemy
# résolve la clé étrangère TargetTrack.formation_id. Elle n'est JAMAIS créée ni
# modifiée par l'application : c'est `scripts/data/fetch_and_clean.py` qui la gère.
# ---------------------------------------------------------------------------
parcoursup_formations_ref = Table(
    "parcoursup_formations",
    SQLModel.metadata,
    Column("formation_id", String, primary_key=True),
    extend_existing=True,
)


def _new_id() -> str:
    return uuid.uuid4().hex


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def current_school_year(today: Optional[date] = None) -> str:
    """Année scolaire française : à partir de septembre on bascule sur la nouvelle année."""
    d = today or date.today()
    start = d.year if d.month >= 9 else d.year - 1
    return f"{start}-{start + 1}"


class GradeLevel(str, Enum):
    TROISIEME = "TROISIEME"
    SECONDE = "SECONDE"
    PREMIERE = "PREMIERE"
    TERMINALE = "TERMINALE"


class TrackType(str, Enum):
    REALISTE = "REALISTE"   # Plan B sécurisé
    AMBITION = "AMBITION"   # Voie d'excellence


# ---------------------------------------------------------------------------
# Profil élève
# ---------------------------------------------------------------------------
class StudentProfile(SQLModel, table=True):
    __tablename__ = "student_profiles"

    id: str = Field(default_factory=_new_id, primary_key=True)
    user_id: str = Field(index=True, unique=True, description="UID Firebase Auth")
    grade_level: GradeLevel
    target_domain: Optional[str] = None  # Ex: "Ingénierie & Sciences dures"

    interests: List[str] = Field(default_factory=list, sa_column=Column(JSON, nullable=False))
    specialties: List[str] = Field(default_factory=list, sa_column=Column(JSON, nullable=False))
    riasec_scores: Dict[str, float] = Field(default_factory=dict, sa_column=Column(JSON, nullable=False))

    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)

    academic_records: List["AcademicRecord"] = Relationship(
        back_populates="student_profile",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"},
    )
    target_tracks: List["TargetTrack"] = Relationship(
        back_populates="student_profile",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"},
    )
    weekly_plans: List["WeeklyPlan"] = Relationship(
        back_populates="student_profile",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"},
    )
    monthly_checkpoints: List["MonthlyCheckpoint"] = Relationship(
        back_populates="student_profile",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"},
    )


# ---------------------------------------------------------------------------
# Relevés de notes / bulletins
# ---------------------------------------------------------------------------
class AcademicRecord(SQLModel, table=True):
    __tablename__ = "academic_records"
    __table_args__ = (
        UniqueConstraint(
            "student_profile_id", "school_year", "trimester", "subject",
            name="uq_record_profile_year_trimester_subject",
        ),
        CheckConstraint("trimester BETWEEN 1 AND 3", name="ck_record_trimester"),
        CheckConstraint("grade >= 0 AND grade <= 20", name="ck_record_grade"),
        CheckConstraint(
            "class_average IS NULL OR (class_average >= 0 AND class_average <= 20)",
            name="ck_record_class_average",
        ),
    )

    id: str = Field(default_factory=_new_id, primary_key=True)
    student_profile_id: str = Field(
        foreign_key="student_profiles.id", ondelete="CASCADE", index=True
    )
    school_year: str = Field(index=True)          # Ex: "2026-2027"
    grade_level: GradeLevel                       # Niveau au moment du relevé
    trimester: int                                # 1, 2 ou 3
    subject: str                                  # Ex: "Mathématiques"
    grade: float                                  # /20
    class_average: Optional[float] = None         # /20

    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)

    student_profile: Optional[StudentProfile] = Relationship(back_populates="academic_records")


# ---------------------------------------------------------------------------
# Double Trajectoire (une seule voie AMBITION et une seule voie REALISTE par élève)
# ---------------------------------------------------------------------------
class TargetTrack(SQLModel, table=True):
    __tablename__ = "target_tracks"
    __table_args__ = (
        UniqueConstraint("student_profile_id", "type", name="uq_track_profile_type"),
    )

    id: str = Field(default_factory=_new_id, primary_key=True)
    student_profile_id: str = Field(
        foreign_key="student_profiles.id", ondelete="CASCADE", index=True
    )
    type: TrackType

    # Formation Parcoursup précise (établissement) — FK vers les données Open Data.
    formation_id: Optional[str] = Field(
        default=None,
        foreign_key="parcoursup_formations.formation_id",
        ondelete="SET NULL",
        index=True,
    )
    # Filière générique du référentiel stratégique (backend/data/filieres_selectives.json),
    # ex: "cpge_mpsi_pcsi". Utile quand l'élève vise une filière sans établissement précis.
    referentiel_filiere_id: Optional[str] = None

    formation_name: str
    estimated_gap: Optional[float] = None          # Snapshot du delta (points /20)
    gap_computed_at: Optional[datetime] = None     # Date du snapshot
    requirements: List[str] = Field(default_factory=list, sa_column=Column(JSON, nullable=False))
    action_plan: Optional[str] = None

    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)

    student_profile: Optional[StudentProfile] = Relationship(back_populates="target_tracks")


# ---------------------------------------------------------------------------
# Planning hebdomadaire de remédiation (Skill 7)
# ---------------------------------------------------------------------------
class WeeklyPlan(SQLModel, table=True):
    __tablename__ = "weekly_plans"
    __table_args__ = (
        UniqueConstraint("student_profile_id", "week_start", name="uq_plan_profile_week"),
    )

    id: str = Field(default_factory=_new_id, primary_key=True)
    student_profile_id: str = Field(
        foreign_key="student_profiles.id", ondelete="CASCADE", index=True
    )
    week_start: date                                # Lundi de la semaine
    # Ex: [{"subject": "Mathématiques", "duration_min": 45, "objective": "...", "done": false}]
    blocks: List[Dict[str, Any]] = Field(default_factory=list, sa_column=Column(JSON, nullable=False))
    completion_rate: float = 0.0                    # 0.0 → 1.0

    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)

    student_profile: Optional[StudentProfile] = Relationship(back_populates="weekly_plans")


# ---------------------------------------------------------------------------
# Checkpoint mensuel (Skill 10)
# ---------------------------------------------------------------------------
class MonthlyCheckpoint(SQLModel, table=True):
    __tablename__ = "monthly_checkpoints"
    __table_args__ = (
        UniqueConstraint("student_profile_id", "month", name="uq_checkpoint_profile_month"),
    )

    id: str = Field(default_factory=_new_id, primary_key=True)
    student_profile_id: str = Field(
        foreign_key="student_profiles.id", ondelete="CASCADE", index=True
    )
    month: str = Field(index=True)                  # "YYYY-MM"
    general_average: Optional[float] = None
    realism_index: Optional[float] = None           # 0 → 100
    notes: Optional[str] = None

    created_at: datetime = Field(default_factory=_utcnow)

    student_profile: Optional[StudentProfile] = Relationship(back_populates="monthly_checkpoints")


# Tables gérées par l'application (la table stub parcoursup_formations en est exclue).
STUDENT_TABLES = [
    StudentProfile.__table__,
    AcademicRecord.__table__,
    TargetTrack.__table__,
    WeeklyPlan.__table__,
    MonthlyCheckpoint.__table__,
]
