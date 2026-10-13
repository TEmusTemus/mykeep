# MyKeep

MyKeep is a private family cloud-storage application accessed through a LINE MINI App / LIFF experience. Approved family members can manage only their own files through a server-authorized FastAPI backend; direct browser access to private Supabase data and self-service enrollment are outside the v1 design.

## Project references

- [Architecture](docs/architecture.md)
- [Delivery roadmap](docs/roadmap.md)
- [Implementation issue map](docs/issue-map.md)
- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Local development

The repository pins its supported runtimes in [`.node-version`](.node-version) and
[`.python-version`](.python-version). Install the frontend dependencies, then use the
root workspace commands:

```powershell
npm install
npm run dev
npm run lint
npm run typecheck
npm run test
npm run build
```

Set up the API in a virtual environment and run it from the repository root:

```powershell
python -m venv .venv
$env:PYTHONUTF8 = "1"
.\.venv\Scripts\python.exe -m pip install -e "apps/api[dev]"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir apps/api --reload
.\.venv\Scripts\python.exe -m ruff check apps/api
.\.venv\Scripts\python.exe -m pytest apps/api -q
```

`PYTHONUTF8` keeps the commands reliable when the checkout path contains non-ASCII
characters.
