from fastapi import FastAPI

app = FastAPI(title="MyKeep API")


@app.get("/healthz")
def health() -> dict[str, str]:
    return {"service": "mykeep-api", "status": "ok"}
