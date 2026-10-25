"""Tests for FastAPI server application."""

import pytest
from fastapi.testclient import TestClient

from ml_backend.server import app


@pytest.fixture
def client():
    return TestClient(app)


def test_app_creation():
    """Test that FastAPI app is created correctly."""
    assert app.title == "HomeValue ML API"
    assert app.version == "0.1.0"


def test_root_endpoint(client):
    """Test root endpoint redirects or returns 404."""
    response = client.get("/")
    # Root might redirect or 404
    assert response.status_code in (200, 404, 307)


def test_docs_endpoint(client):
    """Test that OpenAPI docs are accessible."""
    response = client.get("/docs")
    assert response.status_code == 200


def test_openapi_schema(client):
    """Test that OpenAPI schema is accessible."""
    response = client.get("/openapi.json")
    assert response.status_code == 200
    schema = response.json()
    assert "openapi" in schema
    assert schema["info"]["title"] == "HomeValue ML API"
