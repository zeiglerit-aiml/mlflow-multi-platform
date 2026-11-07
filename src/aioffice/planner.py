import re

from .catalog import Catalog
from .schemas import ExecutionMode, ExecutionPlan, InferenceRequest, TaskType


TASK_HINTS: dict[TaskType, tuple[str, ...]] = {
    # Outcome language is stronger than a time horizon: "likely to cancel next
    # month" is classification, while "forecast next month's sales" is forecasting.
    TaskType.BINARY_CLASSIFICATION: ("likely", "whether", "yes or no", "cancel", "fail"),
    TaskType.FORECASTING: ("forecast", "sales next month", "future values", "time series"),
    TaskType.ANOMALY_DETECTION: ("anomaly", "unusual", "outlier", "abnormal"),
    TaskType.CLUSTERING: ("cluster", "segment", "group similar"),
    TaskType.REGRESSION: ("how much", "price", "amount", "continuous value"),
}


class ProblemPlanner:
    def __init__(self, catalog: Catalog) -> None:
        self.catalog = catalog

    def infer_task(self, request: InferenceRequest) -> TaskType:
        if request.task:
            return request.task
        text = re.sub(r"\s+", " ", (request.question or "").lower())
        for task, hints in TASK_HINTS.items():
            if any(hint in text for hint in hints):
                return task
        raise ValueError(
            "The task could not be determined safely. Specify task or provide a clearer question."
        )

    def create_plan(self, request: InferenceRequest) -> ExecutionPlan:
        task = self.infer_task(request)
        candidates = self.catalog.compatible_models(
            task=task,
            preferred_algorithms=request.preferred_algorithms,
            limit=request.maximum_models,
        )
        warnings: list[str] = []
        if not candidates:
            warnings.append("No compatible ready model was found; a training plan is required.")

        metrics = {
            TaskType.BINARY_CLASSIFICATION: ["pr_auc", "recall", "brier_score"],
            TaskType.MULTICLASS_CLASSIFICATION: ["macro_f1", "log_loss"],
            TaskType.REGRESSION: ["rmse", "mae", "r2"],
            TaskType.FORECASTING: ["mase", "wape", "rmse"],
            TaskType.CLUSTERING: ["silhouette_score", "stability"],
            TaskType.ANOMALY_DETECTION: ["precision_at_k", "recall", "detection_delay"],
        }[task]

        mode = request.mode
        if mode == ExecutionMode.AUTO:
            mode = ExecutionMode.COMPARE if len(candidates) > 1 else ExecutionMode.DIRECT

        return ExecutionPlan(
            interpreted_question=request.question,
            task=task,
            target=request.target,
            candidates=candidates,
            mode=mode,
            evaluation_metrics=metrics,
            warnings=warnings,
        )
