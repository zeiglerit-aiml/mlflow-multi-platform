from pathlib import Path

from aioffice.catalog import Catalog
from aioffice.planner import ProblemPlanner
from aioffice.schemas import ExecutionMode, InferenceRequest, TaskType


def catalog() -> Catalog:
    root = Path(__file__).parents[1]
    return Catalog(root / "config/algorithm_catalog.yaml", root / "config/model_catalog.yaml")


def test_question_routes_to_classification() -> None:
    plan = ProblemPlanner(catalog()).create_plan(
        InferenceRequest(question="Which customers are likely to cancel next month?")
    )
    assert plan.task == TaskType.BINARY_CLASSIFICATION
    assert plan.mode == ExecutionMode.COMPARE
    assert {candidate.algorithm for candidate in plan.candidates} == {
        "logistic_regression",
        "random_forest",
        "xgboost",
    }


def test_framework_is_metadata_not_task() -> None:
    candidates = catalog().compatible_models(TaskType.REGRESSION, limit=5)
    assert {candidate.framework for candidate in candidates} == {"scikit-learn", "xgboost"}


def test_direct_knn_endpoint_has_registered_model() -> None:
    candidate = catalog().get_model("customer-churn-knn")
    assert candidate is not None
    assert candidate.algorithm == "knn"
    assert candidate.endpoint == "/v1/models/customer-churn-knn:predict"
