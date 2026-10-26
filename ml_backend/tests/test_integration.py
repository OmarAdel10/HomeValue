"""
End-to-end integration tests for the HomeValue ML backend.

Tests the full pipeline: data loading -> preprocessing -> model training ->
model saving -> FastAPI server -> prediction endpoint.
"""

import numpy as np
import pytest
from fastapi.testclient import TestClient
from sklearn.linear_model import LinearRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from ml_backend.api import state as api_state
from ml_backend.api.train import save_training_artifact
from ml_backend.config import Config
from ml_backend.data.loader import load_california_housing
from ml_backend.models.baselines import train_baselines
from ml_backend.models.ensembles import train_ensembles
from ml_backend.models.regularized import train_regularized
from ml_backend.models.selection import (
    load_model,
    save_model,
    select_best_model,
)
from ml_backend.preprocessing import (
    build_preprocessing_pipeline,
    split_train_test,
)
from ml_backend.server import app


class TestFullPipeline:
    """Test the complete ML pipeline from data to prediction."""

    @pytest.fixture
    def config(self, tmp_path):
        """Create a test configuration rooted in a temporary directory."""
        return Config(project_root=tmp_path)

    @pytest.fixture
    def trained_pipeline(self, config, monkeypatch):
        """Train a full pipeline and save the best model via the production path."""
        # Load data - returns (X, y) tuple
        X, y = load_california_housing()

        # Split
        X_train, X_test, y_train, y_test = split_train_test(X, y, config)

        # Build preprocessing
        preprocessing_pipeline = build_preprocessing_pipeline(X_train)

        # Fit preprocessor on training data
        X_train_processed = preprocessing_pipeline.fit_transform(X_train)
        X_test_processed = preprocessing_pipeline.transform(X_test)

        # Get all models using actual training functions
        all_models = {}
        all_models.update(train_baselines(X_train_processed, y_train, config))
        all_models.update(train_regularized(X_train_processed, y_train, config))
        all_models.update(train_ensembles(X_train_processed, y_train, config, base_estimators=None))

        # Select best model - select_best_model expects dict of name -> Pipeline
        best_name, best_model = select_best_model(all_models, X_test_processed, y_test)

        # Save through the same helper the training endpoint uses, then reload
        model_path = save_training_artifact(preprocessing_pipeline, best_model, config)
        loaded_pipeline = load_model(model_path)
        monkeypatch.setattr(api_state, "_model", loaded_pipeline)

        return {
            "model_path": model_path,
            "best_name": best_name,
            "pipeline": loaded_pipeline,
            "X_test": X_test,
            "y_test": y_test,
        }

    def test_data_loading(self):
        """Test that California housing data loads correctly."""
        X, y = load_california_housing()
        assert X is not None
        assert y is not None
        assert len(X) > 0
        assert "MedInc" in X.columns
        assert "AveRooms" in X.columns
        assert y.name == "MedHouseVal"

    def test_preprocessing_pipeline(self, config):
        """Test that preprocessing pipeline builds and transforms correctly."""
        X, y = load_california_housing()

        X_train, X_test, y_train, y_test = split_train_test(X, y, config)

        preprocessing_pipeline = build_preprocessing_pipeline(X_train)

        X_train_processed = preprocessing_pipeline.fit_transform(X_train)
        X_test_processed = preprocessing_pipeline.transform(X_test)

        assert X_train_processed.shape[0] == X_train.shape[0]
        assert X_test_processed.shape[0] == X_test.shape[0]
        assert X_train_processed.shape[1] == X_test_processed.shape[1]

    def test_model_training_and_selection(self, trained_pipeline):
        """Test that models train and best model is selected."""
        assert trained_pipeline["model_path"].exists()
        assert trained_pipeline["best_name"] is not None

    def test_model_save_load(self, trained_pipeline):
        """Test that model can be saved and loaded."""
        loaded_pipeline = load_model(trained_pipeline["model_path"])
        assert loaded_pipeline is not None

        # Test prediction
        X_test = trained_pipeline["X_test"]
        predictions = loaded_pipeline.predict(X_test)
        assert len(predictions) == len(X_test)
        assert all(np.isfinite(p) for p in predictions)

    def test_fastapi_predict_endpoint(self, trained_pipeline):
        """Test FastAPI /predict endpoint with loaded model."""
        client = TestClient(app)

        # Use first test sample; ocean_proximity is required by the API contract
        # but is not consumed by the 8-feature model.
        X_test = trained_pipeline["X_test"]
        sample = X_test.iloc[0].to_dict()
        sample["ocean_proximity"] = "INLAND"

        response = client.post("/predict", json=sample)
        assert response.status_code == 200

        data = response.json()
        assert "prediction" in data
        assert "model" in data
        assert "model_version" in data
        assert isinstance(data["prediction"], (int, float))
        assert np.isfinite(data["prediction"])

    def test_fastapi_predict_batch_endpoint(self, trained_pipeline):
        """Test FastAPI /predict/batch endpoint."""
        client = TestClient(app)

        X_test = trained_pipeline["X_test"]
        samples = X_test.iloc[:3].to_dict(orient="records")

        response = client.post("/predict/batch", json={"features": samples})
        assert response.status_code == 200

        data = response.json()
        assert "predictions" in data
        assert len(data["predictions"]) == 3
        assert all(np.isfinite(p) for p in data["predictions"])

    def test_fastapi_health_endpoint(self, trained_pipeline):
        """Test FastAPI /health endpoint."""
        client = TestClient(app)

        response = client.get("/health")
        assert response.status_code == 200

        data = response.json()
        assert data["status"] == "ok"
        assert data["model_loaded"] is True

    def test_fastapi_model_info_endpoint(self, trained_pipeline):
        """Test FastAPI /model/info endpoint."""
        client = TestClient(app)

        response = client.get("/model/info")
        assert response.status_code == 200

        data = response.json()
        assert data["loaded"] is True
        assert "steps" in data

    def test_full_pipeline_end_to_end(self, trained_pipeline):
        """Test complete end-to-end pipeline: data -> model -> API -> prediction."""
        # Verify model file exists and is loadable
        assert trained_pipeline["model_path"].exists()

        loaded = load_model(trained_pipeline["model_path"])
        assert loaded is not None

        # Verify FastAPI app works with the model
        client = TestClient(app)

        # Test prediction
        X_test = trained_pipeline["X_test"]
        sample = X_test.iloc[0].to_dict()
        sample["ocean_proximity"] = "INLAND"

        response = client.post("/predict", json=sample)
        assert response.status_code == 200

        data = response.json()
        prediction = data["prediction"]

        # Verify prediction is a valid float (house price in $100k units)
        assert isinstance(prediction, (int, float))
        assert np.isfinite(prediction)
        assert 0.5 < prediction < 10.0  # Reasonable range for California housing
        # Serialized artifact and API must agree on raw feature input
        expected = float(trained_pipeline["pipeline"].predict(X_test.iloc[[0]])[0])
        assert prediction == pytest.approx(expected, rel=1e-6)


class TestModelPersistence:
    """Test model persistence across restarts."""

    def test_save_load_preserves_predictions(self, tmp_path):
        """Test that saving and loading preserves prediction behavior."""
        # Create simple pipeline
        pipeline = Pipeline(
            [
                ("scaler", StandardScaler()),
                ("model", LinearRegression()),
            ]
        )

        # Generate dummy data
        X = np.random.randn(100, 5)
        y = np.random.randn(100)
        pipeline.fit(X, y)

        # Get predictions before save
        original_preds = pipeline.predict(X[:5])

        # Save and load
        model_path = tmp_path / "test_model.joblib"
        save_model(pipeline, model_path)
        loaded = load_model(model_path)

        # Get predictions after load
        loaded_preds = loaded.predict(X[:5])

        # Predictions should match
        np.testing.assert_array_almost_equal(original_preds, loaded_preds)


class TestAPIValidation:
    """Test API input validation."""

    def test_predict_rejects_invalid_input(self, trained_pipeline):
        """Test that /predict rejects invalid input."""
        client = TestClient(app)

        # Missing required field
        response = client.post("/predict", json={"MedInc": 8.3252})
        assert response.status_code == 422

    def test_predict_batch_rejects_empty_list(self, trained_pipeline):
        """Test that /predict_batch rejects empty list."""
        client = TestClient(app)

        # The endpoint rejects an empty feature list
        response = client.post("/predict/batch", json={"features": []})
        assert response.status_code == 422


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
