"""Development serving pool. Production resolves and caches real MLflow artifacts."""

from hashlib import sha256
from time import perf_counter
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Development Tabular Model Pool")


class PredictRequest(BaseModel):
    model_name: str
    alias: str = "champion"
    data: list[dict[str, Any]] | dict[str, Any] | None = None


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/models/{model_name}:predict")
async def predict(model_name: str, request: PredictRequest) -> dict[str, Any]:
    started = perf_counter()
    if request.model_name != model_name:
        # The duplicated identity protects against accidental proxy/path mismatch.
        raise HTTPException(status_code=400, detail="Path and request model names do not match")
    # Deterministic development stub; replace with mlflow.pyfunc.load_model cache.
    digest = sha256(f"{request.model_name}:{request.data}".encode()).digest()
    probability = round(0.55 + (digest[0] / 255) * 0.4, 4)
    is_regression = request.model_name.startswith("property-value")
    prediction = (
        {"value": round(150000 + probability * 500000, 2)}
        if is_regression
        else {"label": "positive" if probability >= 0.5 else "negative", "probability": probability}
    )
    return {
        "model_name": request.model_name,
        "algorithm": request.model_name,
        "framework": "development-stub",
        "task": "regression" if is_regression else "binary_classification",
        "prediction": prediction,
        "validation_metrics": {},
        "latency_ms": (perf_counter() - started) * 1000,
        "explanation": {"notice": "Development stub; connect MLflow artifact loader."},
    }
