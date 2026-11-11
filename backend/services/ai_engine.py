import os
import sys
import json
import subprocess
import requests

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

def _load_dotenv():
    """Charge automatiquement les variables depuis .env sans dépendance externe."""
    candidates = [
        os.path.join(os.path.dirname(__file__), "..", "..", ".env"),
        os.path.join(os.path.dirname(__file__), "..", ".env"),
        ".env",
        "backend/.env",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            k, v = line.split("=", 1)
                            k = k.strip()
                            v = v.strip().strip('"').strip("'")
                            if k and k not in os.environ:
                                os.environ[k] = v
            except Exception:
                pass

_load_dotenv()

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434/api/generate")

def get_gemini_api_key() -> str:
    _load_dotenv()
    return os.environ.get("GEMINI_API_KEY", "").strip()

def _safe_print(text: str, end: str = "\n", flush: bool = True):
    try:
        sys.stdout.write(text + end)
        if flush:
            sys.stdout.flush()
    except Exception:
        pass

def _get_preferred_model() -> str:
    """Détecte dynamiquement le meilleur modèle disponible dans Ollama par ordre de puissance."""
    forced_model = os.environ.get("OLLAMA_MODEL", "").strip()
    if forced_model:
        return forced_model

    try:
        r = requests.get("http://127.0.0.1:11434/api/tags", timeout=2)
        if r.status_code == 200:
            models = [m.get("name", "") for m in r.json().get("models", [])]
            priority_patterns = [
                "deepseek-r1:14b", "deepseek-r1:8b", "deepseek-r1:7b", "deepseek-r1",
                "qwen2.5:14b", "qwen2.5:7b",
                "mistral-nemo", "mistral:7b", "mistral",
                "llama3.1:8b", "llama3:8b",
                "qwen2.5:3b", "qwen2.5", "qwen"
            ]
            for pattern in priority_patterns:
                for m in models:
                    if pattern in m:
                        return m
            if models:
                return models[0]
    except Exception:
        pass
    return "qwen2.5:3b"

def _query_gemini(prompt: str, system_prompt: str = "") -> str:
    """Appel direct à l'API Google Gemini Cloud (3.5 Flash-Lite / 3.5 Flash).
    Utilise le binaire natif curl.exe sous Windows pour contourner les limitations de proxy réseau.
    """
    api_key = get_gemini_api_key()
    if not api_key:
        raise ValueError("Clé GEMINI_API_KEY non définie.")

    models_to_try = ["gemini-3.5-flash"]

    payload_dict = {
        "contents": [
            {
                "role": "user",
                "parts": [{"text": prompt}]
            }
        ],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 800,
        }
    }

    if system_prompt:
        payload_dict["systemInstruction"] = {
            "parts": [{"text": system_prompt}]
        }

    payload_json = json.dumps(payload_dict)

    for model_name in models_to_try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={api_key}"
        cmd = [
            "curl.exe", "--noproxy", "*", "-s", "-m", "20", "-X", "POST",
            url,
            "-H", "Content-Type: application/json",
            "-d", payload_json
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
            if res.returncode == 0 and res.stdout:
                data = json.loads(res.stdout)
                candidates = data.get("candidates", [])
                if candidates:
                    parts = candidates[0].get("content", {}).get("parts", [])
                    if parts:
                        text_parts = [p.get("text", "") for p in parts if "text" in p]
                        if text_parts:
                            return "\n".join(text_parts).strip()
                error_info = data.get("error", {})
                if error_info:
                    _safe_print(f"[Gemini API] Erreur {error_info.get('code')}: {error_info.get('message', '')[:120]}")
                    continue
        except Exception as e:
            _safe_print(f"[Gemini API] Exception sur {model_name}: {e}")
            continue

    raise RuntimeError("Tous les modèles Gemini Cloud ont échoué.")

def query_local_llm(prompt: str, system_prompt: str = "") -> str:
    api_key = get_gemini_api_key()
    
    # 1. Priorité absolue : Google Gemini Cloud si la clé est présente
    if api_key:
        try:
            _safe_print("\n[IA Engine] Requête via Google Gemini Cloud...", flush=True)
            res = _query_gemini(prompt, system_prompt)
            _safe_print(f"[IA Engine] Réponse reçue de Gemini ({len(res)} car)\n")
            return res
        except Exception as e:
            _safe_print(f"[IA Engine] Échec Gemini ({e}), bascule de secours sur Ollama local...", flush=True)

    # 2. Modèle Ollama local en secours
    model_name = _get_preferred_model()
    payload = {
        "model": model_name,
        "prompt": prompt,
        "system": system_prompt,
        "stream": False,
        "options": {
            "temperature": 0.7,
            "num_predict": 220,
            "top_p": 0.9,
        }
    }
    
    try:
        _safe_print(f"\n[IA Engine] Lancement génération locale avec {model_name}...", flush=True)
        response = requests.post(OLLAMA_URL, json=payload, timeout=(5, 90))
        if response.status_code == 200:
            res_data = response.json()
            full_response = res_data.get("response", "").strip()
            _safe_print(f"[IA Engine] Réponse reçue ({len(full_response)} car)\n")
            return full_response
        else:
            _safe_print(f"\n[IA Engine] Statut erreur Ollama: {response.status_code}")
            return f"Erreur de l'IA locale (Status: {response.status_code})"
    except requests.exceptions.RequestException as e:
        _safe_print(f"\n[IA Engine] Timeout ou indisponibilité Ollama: {e}\n")
        return f"Erreur communication Ollama: {str(e)}"
    except Exception as e:
        _safe_print(f"\n[IA Engine] Erreur inattendue: {e}\n")
        return f"Erreur inattendue: {str(e)}"
