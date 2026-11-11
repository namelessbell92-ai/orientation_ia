import sys
from pathlib import Path

# Force UTF-8 on Windows stdout/stderr to prevent cp1252 UnicodeEncodeError
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

try:
    from routes.orientation import router as orientation_router, load_metiers_data
    from routes.profile import router as profile_router
    from database import init_db
except ImportError:
    from backend.routes.orientation import router as orientation_router, load_metiers_data
    from backend.routes.profile import router as profile_router
    from backend.database import init_db

app = FastAPI(title="Orientation IA API", version="1.0.0")


@app.on_event("startup")
def _create_student_tables() -> None:
    # CREATE TABLE IF NOT EXISTS uniquement sur les tables élèves : les données
    # Parcoursup / ONISEP / IVAL déjà ingérées ne sont pas touchées.
    init_db()


# Configuration CORS pour Flutter (mobile, web, émulateur)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Enregistrement des routes d'orientation sous /api
app.include_router(orientation_router, prefix="/api")
app.include_router(profile_router, prefix="/api")

@app.get("/health")
@app.get("/api/health")
def health_check():
    return {"status": "ok", "service": "orientation-ia"}

@app.get("/")
def read_root():
    return {"message": "Orientation IA backend is running"}

@app.get("/orientation")
def get_orientation():
    return {"message": "Connexion réussie avec FastAPI"}

@app.get("/metiers")
def get_metiers(limit: int = Query(default=50, ge=1, le=2000), skip: int = Query(default=0, ge=0)):
    metiers = load_metiers_data()
    return {
        "total": len(metiers),
        "count": len(metiers[skip:skip + limit]),
        "limit": limit,
        "skip": skip,
        "metiers": metiers[skip:skip + limit]
    }

@app.get("/metier/{id}")
def get_metier(id: str):
    metiers = load_metiers_data()
    for m in metiers:
        if m["id"] == id or m.get("code_rome", "").lower() == id.lower():
            return m
    return {"error": "Métier introuvable"}