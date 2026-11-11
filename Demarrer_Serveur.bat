@echo off
title Serveur Backend Orientation & ADB Bridge
echo ===================================================
echo   Lancement du Serveur Orientation Parcoursup
echo ===================================================
echo.

cd /d "%~dp0"

echo [1/2] Configuration du pont ADB avec le smartphone...
adb reverse tcp:8000 tcp:8000
echo.

echo [2/2] Demarrage du serveur FastAPI sur http://0.0.0.0:8000 ...
.\backend\venv\Scripts\python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000

pause
