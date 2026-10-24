"""Tests for the training API endpoint."""

from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from ml_backend.server import app


@pytest.fixture
def client():
    return TestClient(app)


def test_train_endpoint_exists(client):
    response = client.post("/train")
    assert response.status_code != 404


def test_train_endpoint_returns_correct_schema(client):
    with patch("ml_backend.api.train.run_full_training_pipeline") as mock_train:
        mock_train.return_value = {
            "model": "RandomForestRegressor",
            "metrics": {"rmse": 0.45, "mae": 0.32, "r2": 0.89},
            "cv_rmse": 0.48,
        }
        response = client.post("/train")
        assert response.status_code == 200
        data = response.json()
        assert "model" in data
        assert "metrics" in data
        assert "cv_rmse" in data


def test_train_endpoint_calls_pipeline(client):
    with patch("ml_backend.api.train.run_full_training_pipeline") as mock_train:
        mock_train.return_value = {
            "model": "RidgeCV",
            "metrics": {"rmse": 0.5, "mae": 0.35, "r2": 0.85},
        }
        client.post("/train")
        mock_train.assert_called_once()


def test_train_endpoint_handles_errors(client):
    with patch("ml_backend.api.train.run_full_training_pipeline") as mock_train:
        mock_train.side_effect = RuntimeError("Training failed")
        response = client.post("/train")
        assert response.status_code == 500
        assert "detail" in response.json()
