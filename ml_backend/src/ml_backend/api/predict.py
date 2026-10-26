"""FastAPI router for prediction endpoints."""

from typing import Any

import pandas as pd
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, field_validator

from ml_backend.api.state import get_model

router = APIRouter(prefix="/predict", tags=["prediction"])


# Numeric features the trained model consumes, in the order used at training time.
# ``ocean_proximity`` is accepted in requests for API compatibility but is not part
# of the California Housing dataset shipped by scikit-learn.
MODEL_FEATURES = [
    "MedInc",
    "HouseAge",
    "AveRooms",
    "AveBedrms",
    "Population",
    "AveOccup",
    "Latitude",
    "Longitude",
]

OCEAN_PROXIMITY_VALUES = [
    "<1H OCEAN",
    "INLAND",
    "NEAR OCEAN",
    "NEAR BAY",
    "ISLAND",
]


class PredictionRequest(BaseModel):
    """Single prediction request with California housing features."""

    MedInc: float = Field(..., description="Median income in block group")
    HouseAge: float = Field(..., description="Median house age in block group")
    AveRooms: float = Field(..., description="Average number of rooms per household")
    AveBedrms: float = Field(..., description="Average number of bedrooms per household")
    Population: float = Field(..., description="Block group population")
    AveOccup: float = Field(..., description="Average household occupancy")
    Latitude: float = Field(..., description="Block group latitude")
    Longitude: float = Field(..., description="Block group longitude")
    ocean_proximity: str = Field(..., description="Ocean proximity category")

    @field_validator("ocean_proximity")
    @classmethod
    def validate_ocean_proximity(cls, v: str) -> str:
        if v not in OCEAN_PROXIMITY_VALUES:
            raise ValueError(f"ocean_proximity must be one of {OCEAN_PROXIMITY_VALUES}")
        return v


class BatchPredictionRequest(BaseModel):
    """Batch prediction request with multiple feature sets."""

    features: list[dict[str, Any]] = Field(
        ..., description="List of feature dictionaries", min_length=1
    )


class PredictionResponse(BaseModel):
    """Single prediction response."""

    prediction: float = Field(..., description="Predicted house value (in $100k)")
    model: str = Field(..., description="Model name used for prediction")
    model_version: str = Field(..., description="Model version identifier")


class BatchPredictionResponse(BaseModel):
    """Batch prediction response."""

    predictions: list[float] = Field(..., description="List of predicted house values")
    model: str = Field(..., description="Model name used for predictions")
    model_version: str = Field(..., description="Model version identifier")


@router.post("", response_model=PredictionResponse)
async def predict(request: PredictionRequest) -> PredictionResponse:
    """Make a single house price prediction.

    Args:
        request: California housing features for a single property.

    Returns:
        PredictionResponse with predicted value, model name, and version.

    Raises:
        HTTPException: If model is not loaded or prediction fails.
    """
    model = get_model()
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Model not loaded. Train a model first via POST /train",
        )

    try:
        # Build a DataFrame with the named columns the pipeline was fitted on.
        features_frame = pd.DataFrame(
            [[getattr(request, feature) for feature in MODEL_FEATURES]],
            columns=MODEL_FEATURES,
        )

        prediction = model.predict(features_frame)[0]

        return PredictionResponse(
            prediction=float(prediction),
            model="best_model.joblib",
            model_version="1.0.0",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {e}") from e


@router.post("/batch", response_model=BatchPredictionResponse)
async def predict_batch(request: BatchPredictionRequest) -> BatchPredictionResponse:
    """Make batch house price predictions.

    Args:
        request: List of California housing features for multiple properties.

    Returns:
        BatchPredictionResponse with list of predicted values, model name, and version.

    Raises:
        HTTPException: If model is not loaded or prediction fails.
    """
    model = get_model()
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Model not loaded. Train a model first via POST /train",
        )

    try:
        # Build a DataFrame with the named columns the pipeline was fitted on.
        features_frame = pd.DataFrame(
            [
                {feature: sample[feature] for feature in MODEL_FEATURES}
                for sample in request.features
            ]
        )

        predictions = model.predict(features_frame)

        return BatchPredictionResponse(
            predictions=[float(p) for p in predictions],
            model="best_model.joblib",
            model_version="1.0.0",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Batch prediction failed: {e}") from e
