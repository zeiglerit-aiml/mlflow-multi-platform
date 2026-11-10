"""MLflow-backed tabular model-serving API.

Predictions are produced by registered MLflow PyFunc artifacts. No synthetic
fallback is provided: missing/unavailable artifacts fail closed with HTTP 503.
"""
from functools import lru_cache
from time import perf_counter
from typing import Any

import mlflow.pyfunc
import pandas as pd
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="MLflow Tabular Model Pool")


class PredictRequest(BaseModel):
    model_name: str
    alias: str = Field(default="champion", min_length=1)
    data: list[dict[str, Any]] | dict[str, Any]


@lru_cache(maxsize=32)
def load_model(model_uri: str):
    """Load and cache the registered model version/alias."""
    return mlflow.pyfunc.load_model(model_uri)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "serving_mode": "mlflow-pyfunc"}


@app.post("/v1/models/{model_name}:predict")
async def predict(model_name: str, request: PredictRequest) -> dict[str, Any]:
    started = perf_counter()
    if request.model_name != model_name:
        raise HTTPException(status_code=400, detail="Path and request model names do not match")
    rows = [request.data] if isinstance(request.data, dict) else request.data
    if not rows:
        raise HTTPException(status_code=422, detail="data must contain at least one row")

    model_uri = f"models:/{model_name}@{request.alias}"
    try:
        model = load_model(model_uri)
        predictions = model.predict(pd.DataFrame(rows))
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Unable to load or run registered model '{model_uri}': {type(exc).__name__}",
        ) from exc

    if hasattr(predictions, "tolist"):
        predictions = predictions.tolist()
    return {
        "model_name": model_name,
        "model_uri": model_uri,
        "framework": "mlflow-pyfunc",
        "prediction": predictions,
        "latency_ms": round((perf_counter() - started) * 1000, 3),
    }
