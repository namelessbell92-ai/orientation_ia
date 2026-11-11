"""
Couche d'accès base de données (SQLModel / SQLAlchemy) sur la base SQLite locale.

La même base `data/processed/orientation_data.sqlite` contient :
  - les tables Open Data (parcoursup_formations, lycees_ival, onisep_*), gérées par
    `scripts/data/fetch_and_clean.py` ;
  - les tables élèves (student_profiles, academic_records, target_tracks,
    weekly_plans, monthly_checkpoints), gérées ici.

`init_db()` ne crée QUE les tables élèves manquantes (CREATE TABLE IF NOT EXISTS) :
les données Parcoursup / ONISEP / IVAL déjà ingérées ne sont jamais touchées.
"""

import unicodedata
from pathlib import Path
from typing import Iterator

from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlmodel import Session, SQLModel, create_engine

ROOT_DIR = Path(__file__).resolve().parent.parent
SQLITE_DB_PATH = ROOT_DIR / "data" / "processed" / "orientation_data.sqlite"
DATABASE_URL = f"sqlite:///{SQLITE_DB_PATH.as_posix()}"

engine = create_engine(
    DATABASE_URL,
    echo=False,
    connect_args={"check_same_thread": False, "timeout": 15},
)


def unaccent_lower(value) -> str:
    """'Ingénieur Génie' -> 'ingenieur genie' (utilisé en Python ET exposé en SQL)."""
    if value is None:
        return ""
    normalized = unicodedata.normalize("NFKD", str(value))
    return "".join(c for c in normalized if not unicodedata.combining(c)).lower()


@event.listens_for(Engine, "connect")
def _enable_sqlite_foreign_keys(dbapi_connection, _connection_record) -> None:
    """SQLite désactive les clés étrangères par défaut : on les active à chaque connexion
    pour que ON DELETE CASCADE et la FK vers parcoursup_formations soient réellement appliqués.
    On expose aussi unaccent_lower() en SQL (LIKE SQLite ne gère pas les accents)."""
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON;")
    cursor.close()
    dbapi_connection.create_function("unaccent_lower", 1, unaccent_lower, deterministic=True)


def init_db() -> None:
    """Crée les tables élèves si elles n'existent pas (non destructif)."""
    try:
        from models.student import STUDENT_TABLES
    except ImportError:
        from backend.models.student import STUDENT_TABLES

    SQLITE_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    # `tables=` restreint la création aux tables élèves : la table stub
    # `parcoursup_formations` (déclarée uniquement pour résoudre la FK) n'est jamais créée ici.
    SQLModel.metadata.create_all(engine, tables=STUDENT_TABLES, checkfirst=True)


def get_session() -> Iterator[Session]:
    """Dépendance FastAPI : une session par requête."""
    with Session(engine) as session:
        yield session
