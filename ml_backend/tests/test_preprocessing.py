"""Tests for the preprocessing pipeline, feature engineering, and data split."""

import numpy as np
import pandas as pd
import pytest

from ml_backend.config import Config
from ml_backend.preprocessing.pipeline import (
    build_preprocessing_pipeline,
    infer_feature_types,
)
from ml_backend.preprocessing.split import split_train_test
from ml_backend.preprocessing.transformers import FeatureEngineeringTransformer


def _housing_frame(n_rows: int = 40) -> pd.DataFrame:
    rng = np.random.default_rng(0)
    return pd.DataFrame(
        {
            "MedInc": rng.uniform(0.5, 15.0, n_rows),
            "HouseAge": rng.uniform(1.0, 52.0, n_rows),
            "AveRooms": rng.uniform(2.0, 10.0, n_rows),
            "AveBedrms": rng.uniform(0.5, 4.0, n_rows),
            "Population": rng.uniform(100.0, 5000.0, n_rows),
            "AveOccup": rng.uniform(1.0, 8.0, n_rows),
            "Latitude": rng.uniform(32.5, 42.0, n_rows),
            "Longitude": rng.uniform(-124.5, -114.0, n_rows),
        }
    )


def _categorical_frame(n_rows: int = 30) -> pd.DataFrame:
    rng = np.random.default_rng(1)
    return pd.DataFrame(
        {
            "MedInc": rng.uniform(0.5, 15.0, n_rows),
            "HouseAge": rng.uniform(1.0, 52.0, n_rows),
            "ocean_proximity": rng.choice(["INLAND", "NEAR BAY", "ISLAND"], n_rows),
        }
    )


def test_feature_engineering_adds_week_two_ratio_features():
    frame = _housing_frame()

    transformed = FeatureEngineeringTransformer().fit_transform(frame)

    assert list(transformed.columns) == [
        *frame.columns,
        "rooms_per_household",
        "bedrooms_per_room",
        "population_per_household",
    ]
    pd.testing.assert_series_equal(
        transformed["rooms_per_household"], frame["AveRooms"], check_names=False
    )
    pd.testing.assert_series_equal(
        transformed["bedrooms_per_room"],
        frame["AveBedrms"] / frame["AveRooms"],
        check_names=False,
    )
    pd.testing.assert_series_equal(
        transformed["population_per_household"],
        frame["Population"] / frame["AveOccup"],
        check_names=False,
    )


def test_feature_engineering_preserves_index_and_does_not_mutate_input():
    frame = _housing_frame()
    original = frame.copy()

    transformed = FeatureEngineeringTransformer().fit_transform(frame)

    pd.testing.assert_frame_equal(frame, original)
    assert transformed.index.equals(frame.index)


def test_feature_engineering_replaces_division_by_zero_with_nan():
    frame = _housing_frame(3)
    frame.loc[0, "AveRooms"] = 0.0
    frame.loc[1, "AveOccup"] = 0.0

    transformed = FeatureEngineeringTransformer().fit_transform(frame)

    assert np.isnan(transformed.loc[0, "bedrooms_per_room"])
    assert np.isnan(transformed.loc[1, "population_per_household"])


def test_feature_engineering_rejects_missing_columns():
    frame = _housing_frame().drop(columns=["AveOccup"])

    with pytest.raises(ValueError, match="AveOccup"):
        FeatureEngineeringTransformer().fit_transform(frame)


def test_feature_engineering_rejects_non_dataframe_input():
    with pytest.raises(TypeError, match="DataFrame"):
        FeatureEngineeringTransformer().fit_transform(np.zeros((3, 4)))


def test_infer_feature_types_splits_numeric_and_categorical():
    frame = _categorical_frame()

    numeric, categorical = infer_feature_types(frame)

    assert numeric == ["MedInc", "HouseAge"]
    assert categorical == ["ocean_proximity"]


def test_infer_feature_types_treats_string_and_category_as_categorical():
    frame = pd.DataFrame(
        {
            "number": [1.0, 2.0],
            "text": pd.Series(["a", "b"], dtype="string"),
            "label": pd.Categorical(["x", "y"]),
        }
    )

    numeric, categorical = infer_feature_types(frame)

    assert numeric == ["number"]
    assert categorical == ["text", "label"]


def test_numeric_pipeline_imputes_scales_and_engineers_features():
    frame = _housing_frame()
    frame.loc[0, "MedInc"] = np.nan
    pipeline = build_preprocessing_pipeline(
        numeric_features=list(frame.columns), categorical_features=[]
    )

    transformed = pipeline.fit_transform(frame)

    assert transformed.shape == (len(frame), len(frame.columns) + 3)
    assert not np.isnan(np.asarray(transformed)).any()


def test_pipeline_encodes_categorical_values_and_drops_first_level():
    frame = _categorical_frame()
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"],
        categorical_features=["ocean_proximity"],
    )

    transformed = pipeline.fit_transform(frame)

    # 2 numeric + (3 levels - 1 dropped) dummy columns.
    assert transformed.shape == (len(frame), 4)


def test_pipeline_ignores_unseen_categories_at_transform_time():
    frame = _categorical_frame()
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"],
        categorical_features=["ocean_proximity"],
    )
    pipeline.fit(frame)
    unseen = frame.iloc[:2].copy()
    unseen["ocean_proximity"] = "NEVER SEEN"

    with pytest.warns(UserWarning, match="unknown categories"):
        transformed = pipeline.transform(unseen)

    assert transformed.shape == (2, 4)


def test_pipeline_drops_columns_outside_the_declared_feature_lists():
    frame = _categorical_frame()
    frame["Ignored"] = np.arange(len(frame))
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"],
        categorical_features=["ocean_proximity"],
    )

    transformed = pipeline.fit_transform(frame)

    assert transformed.shape == (len(frame), 4)


def test_pipeline_supports_categorical_only_frames():
    frame = _categorical_frame()[["ocean_proximity"]]
    pipeline = build_preprocessing_pipeline(
        numeric_features=[], categorical_features=["ocean_proximity"]
    )

    transformed = pipeline.fit_transform(frame)

    assert transformed.shape == (len(frame), 2)


def test_pipeline_rejects_duplicate_feature_lists():
    with pytest.raises(ValueError, match="both numeric and categorical"):
        build_preprocessing_pipeline(
            numeric_features=["MedInc"],
            categorical_features=["MedInc"],
        )


def test_pipeline_rejects_empty_feature_lists():
    with pytest.raises(ValueError, match="At least one feature"):
        build_preprocessing_pipeline(numeric_features=[], categorical_features=[])


def test_split_train_test_uses_configured_sizes_and_keeps_alignment():
    frame = _housing_frame(100)
    target = pd.Series(np.arange(100, dtype=float), name="MedHouseVal")

    X_train, X_test, y_train, y_test = split_train_test(frame, target, Config())

    assert len(X_train) == 80
    assert len(X_test) == 20
    assert X_train.index.equals(y_train.index)
    assert X_test.index.equals(y_test.index)
    assert set(X_train.index).isdisjoint(X_test.index)


def test_split_train_test_is_reproducible():
    frame = _housing_frame(50)
    target = pd.Series(np.arange(50, dtype=float))

    first = split_train_test(frame, target, Config())
    second = split_train_test(frame, target, Config())

    pd.testing.assert_frame_equal(first[0], second[0])
    pd.testing.assert_series_equal(first[2], second[2])


def test_split_train_test_honours_custom_test_size():
    frame = _housing_frame(100)
    target = pd.Series(np.arange(100, dtype=float))

    X_train, X_test, _, _ = split_train_test(frame, target, Config(test_size=0.25))

    assert len(X_train) == 75
    assert len(X_test) == 25


def test_split_train_test_rejects_mismatched_lengths():
    frame = _housing_frame(10)
    target = pd.Series(np.arange(9, dtype=float))

    with pytest.raises(ValueError, match="same number of rows"):
        split_train_test(frame, target, Config())


def test_split_train_test_rejects_empty_input():
    with pytest.raises(ValueError, match="empty"):
        split_train_test(pd.DataFrame(), pd.Series(dtype=float), Config())
