"""Tests for the backend configuration."""

from pathlib import Path

import pytest

from ml_backend import config as config_module
from ml_backend.config import Config, _find_repo_root, config


def _require_checkout() -> None:
    if not (config.project_root / "pubspec.yaml").is_file():
        pytest.skip("test requires a full repository checkout")


def test_project_root_is_repository_root():
    _require_checkout()
    assert (config.project_root / "pubspec.yaml").is_file()
    assert (config.project_root / "ml_backend" / "pyproject.toml").is_file()


def test_find_repo_root_raises_when_markers_are_missing(tmp_path):
    with pytest.raises(RuntimeError, match="Could not locate the HomeValue repository root"):
        _find_repo_root(tmp_path)


def test_find_repo_root_walks_up_to_markers(tmp_path):
    repo = tmp_path / "repo"
    (repo / "ml_backend").mkdir(parents=True)
    (repo / "pubspec.yaml").write_text("name: demo", encoding="utf-8")
    nested = repo / "ml_backend" / "src" / "pkg"

    assert _find_repo_root(nested) == repo


def test_find_repo_root_requires_directory_marker(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / "pubspec.yaml").write_text("name: demo", encoding="utf-8")
    (repo / "ml_backend").write_text("not a directory", encoding="utf-8")

    with pytest.raises(RuntimeError):
        _find_repo_root(repo)


def test_default_root_honours_environment_override(tmp_path, monkeypatch):
    monkeypatch.setenv("HOMEVALUE_ROOT", str(tmp_path))

    assert config_module._default_project_root() == tmp_path.resolve()


def test_default_root_falls_back_to_cwd(monkeypatch):
    monkeypatch.delenv("HOMEVALUE_ROOT", raising=False)

    def missing_root(_start):
        raise RuntimeError("missing")

    monkeypatch.setattr(config_module, "_find_repo_root", missing_root)

    assert config_module._default_project_root() == Path.cwd()


def test_ensure_dirs_creates_directories_with_restricted_mode(tmp_path):
    cfg = Config(
        data_dir=tmp_path / "nested" / "data",
        models_dir=tmp_path / "nested" / "models",
        logs_dir=tmp_path / "nested" / "logs",
    )

    cfg.ensure_dirs()

    for directory in (cfg.data_dir, cfg.models_dir, cfg.logs_dir):
        assert directory.is_dir()
        assert directory.stat().st_mode & 0o777 == 0o750


def test_custom_project_root_reparents_default_directories(tmp_path):
    cfg = Config(project_root=tmp_path)

    assert cfg.data_dir == tmp_path / "data"
    assert cfg.models_dir == tmp_path / "models"
    assert cfg.logs_dir == tmp_path / "logs"


def test_custom_project_root_keeps_explicit_directory(tmp_path):
    cfg = Config(project_root=tmp_path, data_dir=tmp_path / "custom")

    assert cfg.data_dir == tmp_path / "custom"
    assert cfg.models_dir == tmp_path / "models"
    assert cfg.logs_dir == tmp_path / "logs"


def test_paths_are_under_project_root():
    _require_checkout()
    for directory in (config.data_dir, config.models_dir, config.logs_dir):
        assert Path(directory).parent == config.project_root
