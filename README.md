# HomeBudget

HomeBudget is a family expense tracker. The repository currently contains the first local MVP: a FastAPI backend and a Kivy client with local SQLite persistence.

## Backend

```powershell
cd backend
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload
```

API docs: `http://127.0.0.1:8000/docs`

## Mobile client

```powershell
cd mobile
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python main.py
```

The first screen creates a local household. Data is stored in `mobile/homebudget_local.sqlite3` during development. Cloud synchronization and Android packaging follow after the local MVP is validated.

## Android build audit

The mobile client currently requires only Python and Kivy for Android packaging. HTTP uses Python's standard-library `urllib`, and local storage uses SQLite. The complete WSL dependency matrix and clean source-sync/build procedure are documented in [docs/android-build-audit.md](docs/android-build-audit.md).
