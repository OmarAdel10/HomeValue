"""Tests for the backend configuration."""

from pathlib import Path

import pytest

from ml_backend.config import Config, _find_repo_root, config


def test_project_root_is_repository_root():
    assert (config.project_root / "pubspec.yaml").is_file()
    assert (config.project_root / "ml_backend" / "pyproject.toml").is_file()


def test_find_repo_root_raises_when_markers_are_missing(tmp_path):
    with pytest.raises(RuntimeError, match="Could not locate the HomeValue repository root"):
        _find_repo_root(tmp_path)


def test_ensure_dirs_creates_directories(tmp_path):
    cfg = Config(
        data_dir=tmp_path / "nested" / "data",
        models_dir=tmp_path / "nested" / "models",
        logs_dir=tmp_path / "nested" / "logs",
    )

    cfg.ensure_dirs()

    for directory in (cfg.data_dir, cfg.models_dir, cfg.logs_dir):
        assert directory.is_dir()


def test_custom_project_root_reparents_default_directories(tmp_path):
    cfg = Config(project_root=tmp_path)

    assert cfg.data_dir == tmp_path / "data"
    assert cfg.models_dir == tmp_path / "models"
    assert cfg.logs_dir == tmp_path / "logs"


def test_paths_are_under_project_root():
    for directory in (config.data_dir, config.models_dir, config.logs_dir):
        assert Path(directory).parent == config.project_root
