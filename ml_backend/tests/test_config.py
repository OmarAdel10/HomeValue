"""Tests for the backend configuration."""

from pathlib import Path

from ml_backend.config import Config, config


def test_project_root_is_repository_root():
    assert (config.project_root / "pubspec.yaml").is_file()
    assert (config.project_root / "ml_backend" / "pyproject.toml").is_file()


def test_post_init_creates_directories(tmp_path):
    cfg = Config(
        data_dir=tmp_path / "data",
        models_dir=tmp_path / "models",
        logs_dir=tmp_path / "logs",
    )

    for directory in (cfg.data_dir, cfg.models_dir, cfg.logs_dir):
        assert directory.is_dir()


def test_paths_are_under_project_root():
    for directory in (config.data_dir, config.models_dir, config.logs_dir):
        assert Path(directory).parent == config.project_root
