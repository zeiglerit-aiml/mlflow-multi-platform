"""Serving-pool MLflow loader with runtime validation and artifact caching."""

from dataclasses import dataclass
from threading import RLock
from typing import Any

import mlflow


@dataclass(frozen=True)
class ModelKey:
    name: str
    reference: str

    @property
    def uri(self) -> str:
        marker = self.reference if self.reference.isdigit() else f"@{self.reference}"
        separator = "/" if self.reference.isdigit() else ""
        return f"models:/{self.name}{separator}{marker}"


class MLflowModelCache:
    def __init__(self, runtime_class: str, allowed_frameworks: set[str]) -> None:
        self.runtime_class = runtime_class
        self.allowed_frameworks = allowed_frameworks
        self._models: dict[ModelKey, Any] = {}
        self._lock = RLock()

    def load(self, key: ModelKey, framework: str, declared_runtime: str):
        if declared_runtime != self.runtime_class:
            raise ValueError(
                f"Artifact requires {declared_runtime}; endpoint is {self.runtime_class}"
            )
        if framework not in self.allowed_frameworks:
            raise ValueError(f"Framework {framework} is not permitted in this serving pool")
        with self._lock:
            if key not in self._models:
                # PyFunc provides a uniform predict contract across supported flavors.
                self._models[key] = mlflow.pyfunc.load_model(key.uri)
            return self._models[key]

    def evict(self, key: ModelKey) -> None:
        with self._lock:
            self._models.pop(key, None)

