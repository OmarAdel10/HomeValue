"""Scaffold tests to verify project structure."""

from ml_backend.config import config


def test_config_exists():
    """Test that config is properly initialized."""
    assert config is not None
    assert config.random_state == 42
    assert config.cv_folds == 5
    assert config.test_size == 0.2


def test_config_directories_exist():
    """Test that config directories exist after init."""
    assert config.data_dir.exists()
    assert config.models_dir.exists()
    assert config.logs_dir.exists()


def test_imports_work():
    """Test that all main modules can be imported."""
    from ml_backend import __version__

    assert __version__ == "0.1.0"


def test_sample_pipeline_trains_and_predicts(trained_pipeline, sample_housing_data):
    """Test that the shared pipeline fixture is usable by later phases."""
    predictions = trained_pipeline.predict(sample_housing_data)

    assert len(predictions) == len(sample_housing_data)
