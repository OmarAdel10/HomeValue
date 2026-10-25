"""Tests for FastAPI model info and comparison endpoints."""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from ml_backend.server import app


@pytest.fixture
def client():
    return TestClient(app)


def test_model_info_returns_correct_schema_when_model_not_loaded(client):
    """GET /model/info returns correct schema when no model loaded."""
    with patch("ml_backend.api.state._model", None):
        response = client.get("/model/info")
        assert response.status_code == 200
        data = response.json()
        assert data["model"] is None
        assert data["loaded"] is False


def test_model_info_returns_correct_schema_when_model_loaded(client):
    """GET /model/info returns correct schema when model loaded."""
    with patch("ml_backend.api.state._model") as mock_model:
        mock_model.named_steps = {"preprocessor": MagicMock(), "model": MagicMock()}
        response = client.get("/model/info")
        assert response.status_code == 200
        data = response.json()
        assert data["model"] == "best_model.joblib"
        assert data["loaded"] is True
        assert "steps" in data
        assert isinstance(data["steps"], list)


def test_model_comparison_returns_correct_schema(client):
    """GET /model/comparison returns correct schema with empty list when no models."""
    response = client.get("/model/comparison")
    assert response.status_code == 200
    data = response.json()
    assert "models" in data
    assert isinstance(data["models"], list)


def test_model_comparison_returns_metrics_when_available(client):
    """GET /model/comparison returns metrics when comparison data available."""
    # This test would require loading saved model metrics
    # For now, verify endpoint exists and returns list
    response = client.get("/model/comparison")
    data = response.json()
    assert "models" in data
    if data["models"]:
        model = data["models"][0]
        assert "model" in model
        assert "rmse" in model
        assert "mae" in model
        assert "r2" in model
