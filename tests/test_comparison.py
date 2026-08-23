from aioffice.comparison import compare_results
from aioffice.schemas import ModelResult, Prediction, TaskType


def result(name: str, probability: float, label: str = "churn") -> ModelResult:
    return ModelResult(
        model_name=name,
        algorithm=name,
        framework="test",
        task=TaskType.BINARY_CLASSIFICATION,
        prediction=Prediction(label=label, probability=probability),
        latency_ms=10,
    )


def test_classification_comparison_uses_majority_and_mean_probability() -> None:
    comparison = compare_results(
        TaskType.BINARY_CLASSIFICATION,
        [result("logistic", 0.7), result("forest", 0.8), result("xgboost", 0.9)],
    )
    assert comparison.agreement == 1
    assert comparison.recommended_prediction is not None
    assert comparison.recommended_prediction.label == "churn"
    assert comparison.recommended_prediction.probability == 0.8

