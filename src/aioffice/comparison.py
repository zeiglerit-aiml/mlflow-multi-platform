from collections import Counter

from .schemas import ComparisonResult, ModelResult, Prediction, TaskType


def compare_results(task: TaskType, results: list[ModelResult]) -> ComparisonResult:
    valid = [result for result in results if not result.error]
    if not valid:
        return ComparisonResult(
            task=task,
            results=results,
            recommendation_basis="No model completed successfully.",
            warnings=["No valid result is available."],
        )

    if task in {TaskType.BINARY_CLASSIFICATION, TaskType.MULTICLASS_CLASSIFICATION}:
        labels = [result.prediction.label for result in valid]
        winner, count = Counter(labels).most_common(1)[0]
        matching = [result for result in valid if result.prediction.label == winner]
        probabilities = [
            result.prediction.probability
            for result in matching
            if result.prediction.probability is not None
        ]
        probability = sum(probabilities) / len(probabilities) if probabilities else None
        return ComparisonResult(
            task=task,
            results=results,
            agreement=count / len(valid),
            recommended_prediction=Prediction(label=winner, probability=probability),
            recommendation_basis="Majority label with mean agreeing-model probability.",
        )

    numeric = [
        float(result.prediction.value)
        for result in valid
        if isinstance(result.prediction.value, (int, float))
    ]
    value = sum(numeric) / len(numeric) if numeric else None
    return ComparisonResult(
        task=task,
        results=results,
        recommended_prediction=Prediction(value=value),
        recommendation_basis="Mean of compatible numeric predictions.",
    )

