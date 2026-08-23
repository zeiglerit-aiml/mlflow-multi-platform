from pathlib import Path
from typing import Any

import yaml

from .schemas import CandidateModel, TaskType


class Catalog:
    def __init__(self, algorithm_path: Path, model_path: Path) -> None:
        self.algorithms = self._load(algorithm_path).get("algorithms", [])
        self.models = self._load(model_path).get("models", [])

    @staticmethod
    def _load(path: Path) -> dict[str, Any]:
        if not path.exists():
            return {}
        return yaml.safe_load(path.read_text(encoding="utf-8")) or {}

    def list_algorithms(self, task: TaskType | None = None) -> list[dict[str, Any]]:
        if task is None:
            return self.algorithms
        return [item for item in self.algorithms if task.value in item["supported_tasks"]]

    def compatible_models(
        self,
        task: TaskType,
        preferred_algorithms: list[str] | None = None,
        limit: int = 3,
    ) -> list[CandidateModel]:
        preferred = set(preferred_algorithms or [])
        eligible = [
            item
            for item in self.models
            if item["task"] == task.value
            and item.get("status") == "ready"
            and item.get("alias") in {"champion", "challenger", "canary"}
        ]
        if preferred:
            eligible = [item for item in eligible if item["algorithm"] in preferred]

        # Prefer production champions, then higher declared quality.
        eligible.sort(
            key=lambda item: (
                item.get("alias") == "champion",
                item.get("validation_metrics", {}).get("primary_score", 0.0),
            ),
            reverse=True,
        )
        return [CandidateModel.model_validate(item) for item in eligible[:limit]]

    def get_model(self, model_name: str) -> CandidateModel | None:
        matches = [item for item in self.models if item["model_name"] == model_name]
        if not matches:
            return None
        matches.sort(
            key=lambda item: (item.get("alias") == "champion", item.get("version", 0)),
            reverse=True,
        )
        return CandidateModel.model_validate(matches[0])
