"""Tests for FastAPI prediction endpoints."""

import pytest
from fastapi.testclient import TestClient

from ml_backend.api.predict import MODEL_FEATURES
from ml_backend.server import app


@pytest.fixture
def client():
    return TestClient(app)


def test_predict_endpoint_exists(client):
    """POST /predict should exist and return 422 for invalid input."""
    response = client.post("/predict", json={})
    assert response.status_code in (422, 400)


def test_predict_endpoint_returns_correct_schema(client):
    """POST /predict with valid input returns correct schema."""
    # Valid California housing features
    features = {
        "MedInc": 8.3252,
        "HouseAge": 41.0,
        "AveRooms": 6.984127,
        "AveBedrms": 1.02381,
        "Population": 322.0,
        "AveOccup": 2.555556,
        "Latitude": 37.88,
        "Longitude": -122.23,
        "ocean_proximity": "NEAR BAY",
    }
    with pytest.MonkeyPatch.context() as mp:
        # Mock the model to avoid loading
        from unittest.mock import MagicMock

        mock_model = MagicMock()
        mock_model.predict.side_effect = lambda frame: [4.52] * len(frame)
        mock_model.named_steps = {"preprocessor": MagicMock(), "model": MagicMock()}
        mp.setattr("ml_backend.api.state._model", mock_model)

        response = client.post("/predict", json=features)

        assert response.status_code == 200
        frame = mock_model.predict.call_args.args[0]
        assert list(frame.columns) == MODEL_FEATURES
        assert len(frame) == 1
        assert "ocean_proximity" not in frame.columns

    data = response.json()
    assert "prediction" in data
    assert "model" in data
    assert "model_version" in data
    assert isinstance(data["prediction"], float)
    assert isinstance(data["model"], str)
    assert isinstance(data["model_version"], str)


def test_predict_batch_endpoint_exists(client):
    """POST /predict/batch feeds the model a raw 8-feature DataFrame."""
    features = [
        {
            "MedInc": 8.3252,
            "HouseAge": 41.0,
            "AveRooms": 6.984127,
            "AveBedrms": 1.02381,
            "Population": 322.0,
            "AveOccup": 2.555556,
            "Latitude": 37.88,
            "Longitude": -122.23,
            "ocean_proximity": "NEAR BAY",
        },
        {
            "MedInc": 4.5,
            "HouseAge": 25.0,
            "AveRooms": 5.0,
            "AveBedrms": 1.2,
            "Population": 500.0,
            "AveOccup": 3.0,
            "Latitude": 34.0,
            "Longitude": -118.0,
            "ocean_proximity": "INLAND",
        },
    ]
    with pytest.MonkeyPatch.context() as mp:
        from unittest.mock import MagicMock

        mock_model = MagicMock()
        mock_model.predict.side_effect = lambda frame: [4.1] * len(frame)
        mp.setattr("ml_backend.api.state._model", mock_model)

        response = client.post("/predict/batch", json={"features": features})

        assert response.status_code == 200
        frame = mock_model.predict.call_args.args[0]
        assert list(frame.columns) == MODEL_FEATURES
        assert len(frame) == 2
        assert "ocean_proximity" not in frame.columns

    assert len(response.json()["predictions"]) == 2


def test_predict_rejects_unknown_ocean_proximity(client):
    features = {
        "MedInc": 8.3252,
        "HouseAge": 41.0,
        "AveRooms": 6.984127,
        "AveBedrms": 1.02381,
        "Population": 322.0,
        "AveOccup": 2.555556,
        "Latitude": 37.88,
        "Longitude": -122.23,
        "ocean_proximity": "MOUNTAIN",
    }
    response = client.post("/predict", json=features)
    assert response.status_code == 422


def test_health_endpoint(client):
    """GET /health returns status."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    assert "model_loaded" in data


def test_model_info_endpoint(client):
    """GET /model/info returns model info."""
    response = client.get("/model/info")
    assert response.status_code == 200
    data = response.json()
    assert "model" in data
    assert "loaded" in data


def test_model_comparison_endpoint(client):
    """GET /model/comparison returns comparison data."""
    response = client.get("/model/comparison")
    assert response.status_code == 200
    data = response.json()
    assert "models" in data
    assert isinstance(data["models"], list)
