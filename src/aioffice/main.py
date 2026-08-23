import asyncio
import json
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import StreamingResponse

from .catalog import Catalog
from .dependencies import get_catalog, get_orchestrator
from .orchestrator import MLOrchestrator
from .schemas import AnalysisResponse, InferenceRequest, ModelResult, TaskType

app = FastAPI(
    title="AI Office Agentic Multi-Model Gateway",
    version="0.1.0",
    description="Question-to-ML planning, heterogeneous inference, and comparison.",
)

_analyses: dict[UUID, AnalysisResponse] = {}


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/v1/algorithms")
async def algorithms(
    task: TaskType | None = None,
    catalog: Catalog = Depends(get_catalog),
) -> list[dict]:
    return catalog.list_algorithms(task)


@app.get("/api/v1/models")
async def models(catalog: Catalog = Depends(get_catalog)) -> list[dict]:
    return catalog.models


@app.post("/api/v1/infer", response_model=AnalysisResponse)
async def infer(
    request: InferenceRequest,
    orchestrator: MLOrchestrator = Depends(get_orchestrator),
) -> AnalysisResponse:
    try:
        response = await orchestrator.analyze(request)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    _analyses[response.analysis_id] = response
    return response


@app.post("/api/v1/tasks/{task}/compare", response_model=AnalysisResponse)
async def compare_task(
    task: TaskType,
    request: InferenceRequest,
    orchestrator: MLOrchestrator = Depends(get_orchestrator),
) -> AnalysisResponse:
    request.task = task
    request.mode = "compare"
    return await infer(request, orchestrator)


@app.post("/api/v1/algorithms/{algorithm}/predict", response_model=AnalysisResponse)
async def predict_algorithm(
    algorithm: str,
    request: InferenceRequest,
    orchestrator: MLOrchestrator = Depends(get_orchestrator),
) -> AnalysisResponse:
    """Public expert route selecting one algorithm's eligible registered model."""
    request.preferred_algorithms = [algorithm]
    request.maximum_models = 1
    request.mode = "direct"
    return await infer(request, orchestrator)


@app.post("/api/v1/models/{model_name}/predict", response_model=ModelResult)
async def predict_model(
    model_name: str,
    request: InferenceRequest,
    catalog: Catalog = Depends(get_catalog),
    orchestrator: MLOrchestrator = Depends(get_orchestrator),
) -> ModelResult:
    """Public direct route for a logical registered model's active catalog entry."""
    candidate = catalog.get_model(model_name)
    if candidate is None:
        raise HTTPException(status_code=404, detail="Model not found")
    return await orchestrator.router.predict(candidate, request.data)


@app.post("/api/v1/models/{model_name}/versions/{version}/predict", response_model=ModelResult)
async def predict_model_version(
    model_name: str,
    version: int,
    request: InferenceRequest,
    catalog: Catalog = Depends(get_catalog),
    orchestrator: MLOrchestrator = Depends(get_orchestrator),
) -> ModelResult:
    """Public immutable-version route; the serving pool resolves the exact MLflow version."""
    candidate = catalog.get_model(model_name)
    if candidate is None:
        raise HTTPException(status_code=404, detail="Model not found")
    candidate = candidate.model_copy(update={"version": version, "alias": str(version)})
    return await orchestrator.router.predict(candidate, request.data)


@app.get("/api/v1/analyses/{analysis_id}", response_model=AnalysisResponse)
async def analysis(analysis_id: UUID) -> AnalysisResponse:
    if analysis_id not in _analyses:
        raise HTTPException(status_code=404, detail="Analysis not found")
    return _analyses[analysis_id]


@app.get("/api/v1/analyses/{analysis_id}/events")
async def analysis_events(analysis_id: UUID) -> StreamingResponse:
    if analysis_id not in _analyses:
        raise HTTPException(status_code=404, detail="Analysis not found")

    async def stream():
        response = _analyses[analysis_id]
        events = [
            {"stage": "planned", "task": response.plan.task},
            {"stage": response.status, "analysis_id": str(analysis_id)},
        ]
        for event in events:
            yield f"data: {json.dumps(event, default=str)}\n\n"
            await asyncio.sleep(0)

    return StreamingResponse(stream(), media_type="text/event-stream")
