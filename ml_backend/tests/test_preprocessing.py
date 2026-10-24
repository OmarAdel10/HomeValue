"""Tests for the preprocessing pipeline, feature engineering, and data split."""

import numpy as np
import pandas as pd
import pytest
from sklearn.exceptions import NotFittedError
from sklearn.linear_model import Ridge
from sklearn.pipeline import Pipeline

from ml_backend.config import Config
from ml_backend.preprocessing import (
    FeatureEngineeringTransformer,
    build_preprocessing_pipeline,
    infer_feature_types,
    split_train_test,
)
from ml_backend.preprocessing.pipeline import (
    _AllMissingCategoricalGuard,
    _to_object_with_nan,
)

ENGINEERED_COLUMNS = ["rooms_per_person", "bedrooms_per_room", "households"]


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


def _categorical_frame(n_rows: int = 30, with_missing: bool = False) -> pd.DataFrame:
    rng = np.random.default_rng(1)
    proximity = rng.choice(["INLAND", "NEAR BAY", "ISLAND"], n_rows).astype(object)
    if with_missing:
        proximity[0] = None
        proximity[1] = None
    return pd.DataFrame(
        {
            "MedInc": rng.uniform(0.5, 15.0, n_rows),
            "HouseAge": rng.uniform(1.0, 52.0, n_rows),
            "ocean_proximity": proximity,
        }
    )


def _dense(matrix):
    return matrix.toarray() if hasattr(matrix, "toarray") else np.asarray(matrix)


def test_feature_engineering_adds_non_redundant_derived_features():
    frame = pd.DataFrame(
        {
            "AveRooms": [4.0, 5.0],
            "AveBedrms": [1.0, 2.0],
            "Population": [100.0, 200.0],
            "AveOccup": [2.0, 4.0],
        }
    )

    transformed = FeatureEngineeringTransformer().fit_transform(frame)

    assert list(transformed.columns) == [*frame.columns, *ENGINEERED_COLUMNS]
    assert list(transformed["rooms_per_person"]) == [2.0, 1.25]
    assert list(transformed["bedrooms_per_room"]) == [0.25, 0.4]
    assert list(transformed["households"]) == [50.0, 50.0]


def test_feature_engineering_does_not_duplicate_existing_features():
    frame = _housing_frame()
    transformed = FeatureEngineeringTransformer().fit_transform(frame)

    for engineered in ENGINEERED_COLUMNS:
        for source in frame.columns:
            assert not np.allclose(
                transformed[engineered].to_numpy(),
                frame[source].to_numpy(),
                equal_nan=True,
            ), f"{engineered} duplicates {source}"


def test_feature_engineering_preserves_non_default_index():
    frame = _housing_frame(3)
    frame.index = pd.Index([10, 30, 20])

    transformed = FeatureEngineeringTransformer().fit_transform(frame)

    assert transformed.index.equals(frame.index)
    assert (
        transformed.loc[30, "households"] == frame.loc[30, "Population"] / frame.loc[30, "AveOccup"]
    )


def test_feature_engineering_replaces_division_by_zero_with_nan():
    frame = _housing_frame(3)
    frame.loc[0, "AveRooms"] = 0.0
    frame.loc[1, "AveOccup"] = 0.0

    transformed = FeatureEngineeringTransformer().fit_transform(frame)

    assert np.isnan(transformed.loc[0, "bedrooms_per_room"])
    assert np.isnan(transformed.loc[1, "rooms_per_person"])
    assert np.isnan(transformed.loc[1, "households"])


def test_feature_engineering_leaves_infinities_outside_ratio_columns():
    frame = _housing_frame(4)
    frame.loc[2, "MedInc"] = np.inf

    transformed = FeatureEngineeringTransformer().fit_transform(frame)

    assert transformed.loc[2, "MedInc"] == np.inf


def test_feature_engineering_rejects_missing_columns():
    frame = _housing_frame().drop(columns=["AveOccup", "AveRooms"])

    with pytest.raises(ValueError) as excinfo:
        FeatureEngineeringTransformer().fit_transform(frame)

    assert "AveOccup" in str(excinfo.value)
    assert "AveRooms" in str(excinfo.value)


def test_feature_engineering_does_not_mutate_input():
    frame = _housing_frame()
    original = frame.copy()

    FeatureEngineeringTransformer().fit_transform(frame)

    pd.testing.assert_frame_equal(frame, original)


def test_feature_engineering_rejects_schema_drift_at_transform():
    frame = _housing_frame()
    transformer = FeatureEngineeringTransformer().fit(frame)

    with pytest.raises(ValueError, match="columns"):
        transformer.transform(frame.assign(Extra=1.0))

    with pytest.raises(ValueError, match="columns"):
        transformer.transform(frame[list(reversed(frame.columns))])


def test_feature_engineering_rejects_wrong_feature_name_count():
    frame = _housing_frame(3)
    transformer = FeatureEngineeringTransformer().fit(frame)

    with pytest.raises(ValueError, match="feature names"):
        transformer.get_feature_names_out(["only_one"])


def test_feature_engineering_transform_requires_fit():
    with pytest.raises(NotFittedError):
        FeatureEngineeringTransformer().transform(_housing_frame(2))


def test_feature_engineering_rejects_division_collision():
    frame = _housing_frame()
    frame["bedrooms_per_room"] = 0.5

    with pytest.raises(ValueError, match="already present"):
        FeatureEngineeringTransformer().fit_transform(frame)


def test_feature_engineering_rejects_non_dataframe_input():
    with pytest.raises(TypeError, match="DataFrame"):
        FeatureEngineeringTransformer().fit_transform(np.zeros((3, 4)))


def test_feature_engineering_exposes_fitted_metadata_and_feature_names():
    frame = _housing_frame()
    transformer = FeatureEngineeringTransformer().fit(frame)

    assert transformer.n_features_in_ == len(frame.columns)
    assert list(transformer.feature_names_in_) == list(frame.columns)
    names = transformer.get_feature_names_out()
    assert list(names) == [*frame.columns, *ENGINEERED_COLUMNS]
    assert len(names) == transformer.transform(frame).shape[1]


def test_feature_engineering_get_feature_names_out_requires_fit():
    with pytest.raises(NotFittedError):
        FeatureEngineeringTransformer().get_feature_names_out()


def test_feature_engineering_accepts_explicit_input_feature_names():
    frame = _housing_frame(3)
    transformer = FeatureEngineeringTransformer().fit(frame)
    explicit = [f"feature_{index}" for index in range(len(frame.columns))]

    names = transformer.get_feature_names_out(explicit)

    assert list(names) == [*explicit, *ENGINEERED_COLUMNS]


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
            "nullable": pd.Series([1, 2], dtype="Int64"),
        }
    )

    numeric, categorical = infer_feature_types(frame)

    assert numeric == ["number", "nullable"]
    assert categorical == ["text", "label"]


def test_infer_feature_types_preserves_non_string_labels():
    frame = pd.DataFrame({0: [1.0, 2.0], 1: [3.0, 4.0]})

    numeric, categorical = infer_feature_types(frame)

    assert numeric == [0, 1]
    assert categorical == []


def test_infer_feature_types_rejects_unclassified_dtypes():
    frame = pd.DataFrame(
        {
            "number": [1.0, 2.0],
            "flag": [True, False],
            "when": pd.to_datetime(["2024-01-01", "2024-01-02"]),
        }
    )

    with pytest.raises(ValueError) as excinfo:
        infer_feature_types(frame)

    message = str(excinfo.value)
    assert "Unsupported column dtypes" in message
    assert "flag" in message
    assert "when" in message


def test_infer_feature_types_handles_empty_frames():
    assert infer_feature_types(pd.DataFrame()) == ([], [])


def test_infer_feature_types_rejects_non_dataframe_input():
    with pytest.raises(TypeError, match="DataFrame"):
        infer_feature_types(np.zeros((2, 2)))


def test_to_object_with_nan_normalizes_nullable_strings():
    frame = pd.DataFrame({"text": pd.Series(["a", pd.NA], dtype="string")})

    normalized = _to_object_with_nan(frame)
    missing = normalized.loc[1, "text"]

    assert normalized["text"].dtype == object
    assert type(missing) is float
    assert np.isnan(missing)


@pytest.mark.parametrize("missing", [None, np.nan])
def test_to_object_with_nan_normalizes_object_missing_values(missing):
    frame = pd.DataFrame({"text": pd.Series(["a", missing], dtype=object)})

    normalized = _to_object_with_nan(frame)
    value = normalized.loc[1, "text"]

    assert normalized["text"].dtype == object
    assert type(value) is float
    assert np.isnan(value)


def test_numeric_pipeline_imputes_with_median_and_standardizes():
    frame = _housing_frame(20)
    frame.loc[0, "MedInc"] = np.nan
    pipeline = build_preprocessing_pipeline(
        numeric_features=list(frame.columns), categorical_features=[]
    )

    pipeline.fit(frame)
    numeric = pipeline.named_transformers_["numeric"]
    imputer = numeric.named_steps["imputer"]
    scaler = numeric.named_steps["scaler"]
    transformed = _dense(pipeline.transform(frame))

    assert imputer.statistics_[0] == pytest.approx(np.nanmedian(frame["MedInc"]))
    expected_mean = frame["MedInc"].fillna(np.nanmedian(frame["MedInc"])).mean()
    assert scaler.mean_[0] == pytest.approx(expected_mean)
    assert transformed[:, 0].mean() == pytest.approx(0.0, abs=1e-9)
    assert transformed[:, 0].std(ddof=0) == pytest.approx(1.0)


def test_numeric_pipeline_keeps_all_nan_declared_columns():
    frame = pd.DataFrame({"MedInc": [np.nan] * 5, "HouseAge": [1.0, 2.0, 3.0, 4.0, 5.0]})
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=[]
    )

    transformed = _dense(pipeline.fit_transform(frame))

    assert transformed.shape == (5, 2)
    assert np.isfinite(transformed).all()


def test_pipeline_encodes_categorical_values_without_dropping_a_level():
    frame = _categorical_frame()
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"],
        categorical_features=["ocean_proximity"],
    )

    transformed = _dense(pipeline.fit_transform(frame))

    # 2 numeric + 3 one-hot levels (no reference level dropped).
    assert transformed.shape == (len(frame), 5)
    levels = sorted(frame["ocean_proximity"].unique())
    output = transformed[:, 2:]
    for row, value in enumerate(frame["ocean_proximity"]):
        expected = np.zeros(len(levels))
        expected[levels.index(value)] = 1.0
        np.testing.assert_array_equal(output[row], expected)


def test_pipeline_imputes_missing_categories_with_most_frequent():
    frame = pd.DataFrame(
        {
            "MedInc": [1.0, 2.0, 3.0, 4.0],
            "HouseAge": [10.0, 20.0, 30.0, 40.0],
            "ocean_proximity": ["INLAND", "INLAND", "NEAR BAY", None],
        }
    )
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=["ocean_proximity"]
    )

    pipeline.fit(frame)
    categorical = pipeline.named_transformers_["categorical"]
    imputer = categorical.named_steps["imputer"]
    transformed = _dense(pipeline.transform(frame))
    levels = sorted(frame["ocean_proximity"].dropna().unique())

    assert imputer.statistics_[0] == "INLAND"
    assert transformed[3, 2 + levels.index("INLAND")] == 1.0


def test_pipeline_handles_nullable_string_categories_with_missing_values():
    frame = _categorical_frame(with_missing=True)
    frame["ocean_proximity"] = frame["ocean_proximity"].astype("string")
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=["ocean_proximity"]
    )

    transformed = _dense(pipeline.fit_transform(frame))

    assert transformed.shape == (len(frame), 5)
    assert np.isfinite(transformed).all()


def test_pipeline_encodes_unseen_categories_as_all_zero_block():
    frame = _categorical_frame()
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=["ocean_proximity"]
    )
    pipeline.fit(frame)
    unseen = frame.iloc[:2].copy()
    unseen["ocean_proximity"] = "NEVER SEEN"

    transformed = _dense(pipeline.transform(unseen))

    assert transformed.shape == (2, 5)
    np.testing.assert_array_equal(transformed[:, 2:], np.zeros((2, 3)))


def test_pipeline_drops_columns_outside_the_declared_feature_lists():
    frame = _categorical_frame()
    frame["Ignored"] = np.arange(len(frame))
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=["ocean_proximity"]
    )

    transformed = pipeline.fit_transform(frame)

    assert transformed.shape == (len(frame), 5)


def test_pipeline_exposes_exact_feature_names() -> None:
    frame = _categorical_frame()
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=["ocean_proximity"]
    )
    pipeline.fit(frame)
    levels = sorted(frame["ocean_proximity"].unique())

    names = list(pipeline.get_feature_names_out())
    expected = [
        "numeric__MedInc",
        "numeric__HouseAge",
        *[f"categorical__ocean_proximity_{level}" for level in levels],
    ]

    assert names == expected
    assert len(names) == len(set(names))


def test_pipeline_names_include_engineered_columns() -> None:
    frame = _housing_frame()
    frame["ocean_proximity"] = "INLAND"
    numeric = list(_housing_frame().columns)
    pipeline = build_preprocessing_pipeline(
        numeric_features=numeric, categorical_features=["ocean_proximity"]
    )
    pipeline.fit(frame)

    names = list(pipeline.get_feature_names_out())

    assert "numeric__rooms_per_person" in names
    assert "numeric__bedrooms_per_room" in names
    assert "numeric__households" in names
    assert len(names) == len(set(names))


def test_pipeline_rejects_all_missing_categorical_columns() -> None:
    frame = _categorical_frame(6)
    frame["ocean_proximity"] = None
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=["ocean_proximity"]
    )

    with pytest.raises(ValueError, match="no observed values.*ocean_proximity"):
        pipeline.fit(frame)


def test_categorical_guard_returns_fitted_feature_names() -> None:
    guard = _AllMissingCategoricalGuard().fit(pd.DataFrame({"a": ["x"], "b": ["y"]}))

    assert list(guard.get_feature_names_out()) == ["a", "b"]


def test_categorical_guard_accepts_non_dataframe_input() -> None:
    guard = _AllMissingCategoricalGuard().fit(np.zeros((2, 3)))

    assert guard.n_features_in_ == 3


def test_pipeline_accepts_categorical_dtype_end_to_end() -> None:
    frame = _categorical_frame()
    frame["ocean_proximity"] = pd.Categorical(
        frame["ocean_proximity"], categories=["INLAND", "NEAR BAY", "ISLAND"]
    )
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=["ocean_proximity"]
    )

    transformed = _dense(pipeline.fit_transform(frame))

    assert transformed.shape == (len(frame), 5)
    assert np.isfinite(transformed).all()


def test_pipeline_enables_engineering_when_explicitly_requested() -> None:
    frame = _housing_frame()
    pipeline = build_preprocessing_pipeline(
        numeric_features=list(frame.columns),
        categorical_features=[],
        feature_engineering=True,
    )

    transformed = pipeline.fit_transform(frame)

    assert transformed.shape == (len(frame), len(frame.columns) + 3)


def test_pipeline_keeps_all_nan_numeric_column_with_engineering() -> None:
    frame = _housing_frame(6)
    frame["MedInc"] = np.nan
    pipeline = build_preprocessing_pipeline(
        numeric_features=list(frame.columns), categorical_features=[]
    )

    transformed = _dense(pipeline.fit_transform(frame))

    assert transformed.shape == (len(frame), len(frame.columns) + 3)
    assert np.isfinite(transformed).all()


def test_pipeline_rejects_bare_string_feature_arguments() -> None:
    with pytest.raises(TypeError, match="sequence"):
        build_preprocessing_pipeline(numeric_features="MedInc", categorical_features=[])

    with pytest.raises(TypeError, match="sequence"):
        build_preprocessing_pipeline(numeric_features=[], categorical_features="ocean_proximity")


def test_pipeline_rejects_duplicate_categorical_features() -> None:
    with pytest.raises(ValueError, match="Duplicate categorical"):
        build_preprocessing_pipeline(
            numeric_features=[],
            categorical_features=["ocean_proximity", "ocean_proximity"],
        )


def test_pipeline_skips_engineering_when_disabled():
    frame = _housing_frame()
    pipeline = build_preprocessing_pipeline(
        numeric_features=list(frame.columns),
        categorical_features=[],
        feature_engineering=False,
    )

    transformed = pipeline.fit_transform(frame)

    numeric = pipeline.named_transformers_["numeric"]
    assert "engineer" not in numeric.named_steps
    assert transformed.shape == (len(frame), len(frame.columns))


def test_pipeline_enables_engineering_for_california_columns_by_default():
    frame = _housing_frame()
    pipeline = build_preprocessing_pipeline(
        numeric_features=list(frame.columns), categorical_features=[]
    )

    transformed = pipeline.fit_transform(frame)

    numeric = pipeline.named_transformers_["numeric"]
    assert "engineer" in numeric.named_steps
    assert transformed.shape == (len(frame), len(frame.columns) + 3)


def test_pipeline_rejects_partial_engineering_columns():
    frame = _housing_frame()

    with pytest.raises(ValueError, match="or feature_engineering=False"):
        build_preprocessing_pipeline(
            numeric_features=[column for column in frame.columns if column != "AveRooms"],
            categorical_features=[],
        )


def test_pipeline_rejects_explicit_engineering_without_source_columns():
    with pytest.raises(ValueError, match="Feature engineering requires"):
        build_preprocessing_pipeline(
            numeric_features=["MedInc", "HouseAge"],
            categorical_features=[],
            feature_engineering=True,
        )


def test_pipeline_supports_categorical_only_frames():
    frame = _categorical_frame()[["ocean_proximity"]]
    pipeline = build_preprocessing_pipeline(
        numeric_features=[], categorical_features=["ocean_proximity"]
    )

    transformed = pipeline.fit_transform(frame)

    assert transformed.shape == (len(frame), 3)


def test_pipeline_rejects_duplicate_features_within_one_list():
    with pytest.raises(ValueError, match="Duplicate"):
        build_preprocessing_pipeline(numeric_features=["MedInc", "MedInc"], categorical_features=[])


def test_pipeline_rejects_duplicate_feature_lists():
    with pytest.raises(ValueError, match="both numeric and categorical"):
        build_preprocessing_pipeline(
            numeric_features=["MedInc"],
            categorical_features=["MedInc"],
        )


def test_pipeline_rejects_empty_feature_lists():
    with pytest.raises(ValueError, match="At least one feature"):
        build_preprocessing_pipeline(numeric_features=[], categorical_features=[])


def test_pipeline_supports_integer_feature_labels():
    frame = pd.DataFrame({0: [1.0, 2.0, 3.0], 1: [4.0, 5.0, 6.0]})
    numeric, categorical = infer_feature_types(frame)
    pipeline = build_preprocessing_pipeline(
        numeric_features=numeric, categorical_features=categorical
    )

    transformed = pipeline.fit_transform(frame)

    assert transformed.shape == (3, 2)


def test_pipeline_fits_an_estimator_end_to_end():
    frame = _housing_frame(60)
    target = pd.Series(np.linspace(1.0, 5.0, len(frame)), name="MedHouseVal")
    model = Pipeline(
        [
            (
                "preprocessing",
                build_preprocessing_pipeline(
                    numeric_features=list(frame.columns), categorical_features=[]
                ),
            ),
            ("model", Ridge()),
        ]
    )

    model.fit(frame, target)
    predictions = model.predict(frame.iloc[:5])

    assert np.isfinite(predictions).all()
    assert len(predictions) == 5


def test_preprocessing_statistics_are_learned_from_fit_data_only():
    train = pd.DataFrame({"MedInc": [1.0, 1.0, 1.0, np.nan], "HouseAge": [1.0, 2.0, 3.0, 4.0]})
    test = pd.DataFrame({"MedInc": [100.0, 100.0], "HouseAge": [5.0, 6.0]})
    pipeline = build_preprocessing_pipeline(
        numeric_features=["MedInc", "HouseAge"], categorical_features=[]
    )

    pipeline.fit(train)
    numeric = pipeline.named_transformers_["numeric"]
    imputer = numeric.named_steps["imputer"]
    scaler = numeric.named_steps["scaler"]
    statistics_before = imputer.statistics_.copy()
    mean_before = scaler.mean_.copy()
    transformed = _dense(pipeline.transform(test))

    assert statistics_before[1] == 2.5  # train median, not combined median 3.5
    assert mean_before[1] == 2.5
    np.testing.assert_array_equal(imputer.statistics_, statistics_before)
    np.testing.assert_array_equal(scaler.mean_, mean_before)
    assert transformed[0, 1] == pytest.approx((5.0 - 2.5) / scaler.scale_[1])


def test_public_exports_are_available():
    from ml_backend import preprocessing

    assert set(preprocessing.__all__) == {
        "FeatureEngineeringTransformer",
        "build_preprocessing_pipeline",
        "infer_feature_types",
        "split_train_test",
    }
    for name in preprocessing.__all__:
        assert callable(getattr(preprocessing, name))


def test_split_train_test_uses_configured_sizes_and_keeps_alignment():
    frame = _housing_frame(100)
    target = pd.Series(np.arange(100, dtype=float), name="MedHouseVal")

    X_train, X_test, y_train, y_test = split_train_test(frame, target, Config())

    assert len(X_train) == 80
    assert len(X_test) == 20
    assert X_train.index.equals(y_train.index)
    assert X_test.index.equals(y_test.index)
    assert set(X_train.index).isdisjoint(X_test.index)


def test_split_train_test_is_reproducible_for_all_partitions():
    frame = _housing_frame(50)
    target = pd.Series(np.arange(50, dtype=float))

    first = split_train_test(frame, target, Config())
    second = split_train_test(frame, target, Config())

    for left, right in zip(first, second, strict=True):
        (
            pd.testing.assert_frame_equal(left, right)
            if isinstance(left, pd.DataFrame)
            else pd.testing.assert_series_equal(left, right)
        )


def test_split_train_test_changes_with_random_state():
    frame = _housing_frame(50)
    target = pd.Series(np.arange(50, dtype=float))

    first = split_train_test(frame, target, Config(random_state=1))
    second = split_train_test(frame, target, Config(random_state=2))

    assert not first[0].index.equals(second[0].index)


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


def test_split_train_test_rejects_mismatched_indices():
    frame = _housing_frame(10)
    target = pd.Series(np.arange(10, dtype=float), index=np.arange(10, 20))

    with pytest.raises(ValueError, match="same index"):
        split_train_test(frame, target, Config())


def test_split_train_test_rejects_empty_input():
    with pytest.raises(ValueError, match="empty"):
        split_train_test(pd.DataFrame(), pd.Series(dtype=float), Config())


@pytest.mark.parametrize("test_size", [0.0, 1.0, 1.5, -0.2])
def test_split_train_test_rejects_invalid_test_size(test_size):
    frame = _housing_frame(10)
    target = pd.Series(np.arange(10, dtype=float))

    with pytest.raises(ValueError, match="test_size"):
        split_train_test(frame, target, Config(test_size=test_size))


@pytest.mark.parametrize("random_state", [None, True, 1.5])
def test_split_train_test_rejects_non_integer_random_state(random_state):
    frame = _housing_frame(10)
    target = pd.Series(np.arange(10, dtype=float))

    with pytest.raises(TypeError, match="random_state"):
        split_train_test(frame, target, Config(random_state=random_state))


@pytest.mark.parametrize("random_state", [-1, 2**32])
def test_split_train_test_rejects_out_of_range_random_state(random_state):
    frame = _housing_frame(10)
    target = pd.Series(np.arange(10, dtype=float))

    with pytest.raises(ValueError, match="random_state"):
        split_train_test(frame, target, Config(random_state=random_state))


def test_split_train_test_rejects_duplicate_index_labels():
    frame = _housing_frame(6)
    frame.index = pd.Index([0, 0, 1, 1, 2, 2])
    target = pd.Series(np.arange(6, dtype=float), index=frame.index)

    with pytest.raises(ValueError, match="unique index"):
        split_train_test(frame, target, Config())


def test_split_train_test_preserves_non_default_index():
    frame = _housing_frame(10)
    frame.index = pd.Index(range(100, 110))
    target = pd.Series(np.arange(10, dtype=float), index=frame.index)

    X_train, X_test, y_train, y_test = split_train_test(frame, target, Config())

    assert X_train.index.equals(y_train.index)
    assert X_test.index.equals(y_test.index)
    assert set(X_train.index).isdisjoint(X_test.index)
