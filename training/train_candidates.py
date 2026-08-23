"""Train heterogeneous classification candidates and register qualifying artifacts."""

from dataclasses import dataclass

import mlflow
import mlflow.sklearn
import numpy as np
from mlflow.models import infer_signature
from sklearn.datasets import make_classification
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, recall_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler


@dataclass(frozen=True)
class Candidate:
    name: str
    estimator: object


def candidates() -> list[Candidate]:
    return [
        Candidate("logistic-regression", make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000))),
        Candidate("random-forest", RandomForestClassifier(n_estimators=300, random_state=42)),
    ]


def main() -> None:
    mlflow.set_experiment("customer-churn-candidates")
    X, y = make_classification(
        n_samples=4000,
        n_features=20,
        n_informative=10,
        weights=[0.82, 0.18],
        random_state=42,
    )
    X_train, X_valid, y_train, y_valid = train_test_split(
        X, y, test_size=0.25, stratify=y, random_state=42
    )

    for candidate in candidates():
        with mlflow.start_run(run_name=candidate.name):
            candidate.estimator.fit(X_train, y_train)
            probability = candidate.estimator.predict_proba(X_valid)[:, 1]
            prediction = (probability >= 0.5).astype(int)
            metrics = {
                "pr_auc": average_precision_score(y_valid, probability),
                "recall": recall_score(y_valid, prediction),
                "brier_score": brier_score_loss(y_valid, probability),
            }
            mlflow.log_metrics(metrics)
            signature = infer_signature(X_train, candidate.estimator.predict_proba(X_train[:5]))
            mlflow.sklearn.log_model(
                sk_model=candidate.estimator,
                name="model",
                signature=signature,
                input_example=np.asarray(X_train[:2]),
                registered_model_name=f"customer-churn-{candidate.name}",
                extra_pip_requirements=["scikit-learn>=1.5,<2"],
            )
            print(candidate.name, metrics)


if __name__ == "__main__":
    main()
