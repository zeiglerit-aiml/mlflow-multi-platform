import sys
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services"))
import model_service


class FakeModel:
    def predict(self, frame):
        assert list(frame.columns) == ["tenure", "spend"]
        return ["retained"]


def test_prediction_uses_requested_alias(monkeypatch):
    seen = []
    monkeypatch.setattr(model_service, "load_model", lambda uri: seen.append(uri) or FakeModel())
    client = TestClient(model_service.app)
    response = client.post(
        "/v1/models/customer-churn:predict",
        json={"model_name": "customer-churn", "alias": "challenger",
              "data": {"tenure": 12, "spend": 45.5}},
    )
    assert response.status_code == 200
    assert response.json()["prediction"] == ["retained"]
    assert seen == ["models:/customer-churn@challenger"]


def test_missing_registry_model_returns_503(monkeypatch):
    def fail_to_load(uri):
        raise RuntimeError("registry unavailable")

    monkeypatch.setattr(model_service, "load_model", fail_to_load)
    client = TestClient(model_service.app)
    response = client.post(
        "/v1/models/customer-churn:predict",
        json={"model_name": "customer-churn", "data": {"tenure": 12}},
    )
    assert response.status_code == 503


def test_path_and_payload_name_must_match():
    client = TestClient(model_service.app)
    response = client.post(
        "/v1/models/customer-churn:predict",
        json={"model_name": "other-model", "data": {"tenure": 12}},
    )
    assert response.status_code == 400
