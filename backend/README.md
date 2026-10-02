# HomeBudget backend

FastAPI API with a local SQLite database for the first MVP.

## Run on Windows

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` for the generated OpenAPI UI.
