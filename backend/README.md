# HomeBudget backend

Historical prototype retained for reference. The current Android application uses Firebase and does not call this backend.

Do not expose this prototype to the internet: it lacks token authentication, stores its household PIN without a password hash, and trusts client-supplied profile IDs. Its endpoints do not provide production authorization.

FastAPI API with a local SQLite database for the first MVP.

## Run on Windows

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` for the generated OpenAPI UI.
