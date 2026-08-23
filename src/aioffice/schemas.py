from enum import StrEnum
from typing import Any
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, model_validator


class TaskType(StrEnum):
    BINARY_CLASSIFICATION = "binary_classification"
    MULTICLASS_CLASSIFICATION = "multiclass_classification"
    REGRESSION = "regression"
    FORECASTING = "forecasting"
    CLUSTERING = "clustering"
    ANOMALY_DETECTION = "anomaly_detection"


class ExecutionMode(StrEnum):
    AUTO = "auto"
    DIRECT = "direct"
    COMPARE = "compare"
    ENSEMBLE = "ensemble"
    SHADOW = "shadow"
    RECOMMEND = "recommend"


class InferenceRequest(BaseModel):
    question: str | None = None
    task: TaskType | None = None
    target: str | None = None
    data: list[dict[str, Any]] | dict[str, Any] | None = None
    dataset_uri: str | None = None
    preferred_algorithms: list[str] = Field(default_factory=list)
    mode: ExecutionMode = ExecutionMode.AUTO
    maximum_models: int = Field(default=3, ge=1, le=10)
    require_explanation: bool = True

    @model_validator(mode="after")
    def require_problem_input(self) -> "InferenceRequest":
        if not any((self.question, self.data, self.dataset_uri)):
            raise ValueError("question, data, or dataset_uri is required")
        return self


class CandidateModel(BaseModel):
    model_name: str
    algorithm: str
    framework: str
    runtime_class: str = "tabular-cpu"
    task: TaskType
    alias: str = "champion"
    version: int | None = None
    endpoint: str
    input_schema: str
    purpose: str
    validation_metrics: dict[str, float] = Field(default_factory=dict)


class ExecutionPlan(BaseModel):
    plan_id: UUID = Field(default_factory=uuid4)
    interpreted_question: str | None
    task: TaskType
    target: str | None
    candidates: list[CandidateModel]
    mode: ExecutionMode
    evaluation_metrics: list[str]
    warnings: list[str] = Field(default_factory=list)


class Prediction(BaseModel):
    label: str | int | None = None
    value: float | list[float] | None = None
    probability: float | None = Field(default=None, ge=0, le=1)


class ModelResult(BaseModel):
    model_name: str
    version: int | None = None
    algorithm: str
    framework: str
    task: TaskType
    prediction: Prediction
    validation_metrics: dict[str, float] = Field(default_factory=dict)
    latency_ms: float = Field(ge=0)
    explanation: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None


class ComparisonResult(BaseModel):
    task: TaskType
    results: list[ModelResult]
    agreement: float | None = Field(default=None, ge=0, le=1)
    recommended_prediction: Prediction | None = None
    recommendation_basis: str
    warnings: list[str] = Field(default_factory=list)


class AnalysisResponse(BaseModel):
    analysis_id: UUID = Field(default_factory=uuid4)
    status: str
    plan: ExecutionPlan
    comparison: ComparisonResult | None = None
