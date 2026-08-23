import asyncio
from time import perf_counter
from typing import Any

import httpx

from .schemas import CandidateModel, ModelResult, Prediction


class ModelRouter:
    def __init__(self, base_url: str = "", timeout_seconds: float = 30.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds

    async def predict(self, candidate: CandidateModel, data: Any) -> ModelResult:
        started = perf_counter()
        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                endpoint = candidate.endpoint
                if endpoint.startswith("/"):
                    endpoint = f"{self.base_url}{endpoint}"
                response = await client.post(
                    endpoint,
                    json={"model_name": candidate.model_name, "alias": candidate.alias, "data": data},
                )
                response.raise_for_status()
                payload = response.json()
            return ModelResult.model_validate(payload)
        except Exception as exc:  # Boundary intentionally converts transport failures.
            return ModelResult(
                model_name=candidate.model_name,
                version=candidate.version,
                algorithm=candidate.algorithm,
                framework=candidate.framework,
                task=candidate.task,
                prediction=Prediction(),
                validation_metrics=candidate.validation_metrics,
                latency_ms=(perf_counter() - started) * 1000,
                error=str(exc),
            )

    async def execute(self, candidates: list[CandidateModel], data: Any) -> list[ModelResult]:
        return await asyncio.gather(*(self.predict(candidate, data) for candidate in candidates))
