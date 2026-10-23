# HomeValue ML Backend

scikit-learn training pipeline and FastAPI service for the HomeValue house price
prediction project.

> Phase 1 status: data loading, dataset integrity caching, exploratory analysis,
> and CI are implemented. Preprocessing, model training/tuning, ensembles, and the
> HTTP API arrive in later phases.

## Setup

```bash
pip install -e ".[dev]"
```

## Commands

```bash
make format   # black + ruff format
make lint     # ruff + mypy
make test     # pytest with branch coverage
```

`make train` and `make serve` intentionally exit with a roadmap message until the
training pipeline and API land.
