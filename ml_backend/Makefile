# HomeValue ML Backend Makefile
.PHONY: install format lint test train serve clean release help

# Default target
help:
	@echo "HomeValue ML Backend - Available targets:"
	@echo "  install   - Install dependencies (with dev extras)"
	@echo "  format    - Format code with black and ruff"
	@echo "  lint      - Run linting (ruff, mypy)"
	@echo "  test      - Run tests with pytest"
	@echo "  train     - Train model and save to models/"
	@echo "  serve     - Start FastAPI server"
	@echo "  release   - Build release artifacts (train model, build Flutter Linux bundle)"
	@echo "  clean     - Remove cache and build artifacts"

# Install dependencies
install:
	pip install -e ".[dev]"

# Format code
format:
	black src/ tests/
	ruff format src/ tests/

# Lint code
lint:
	ruff check src/ tests/
	mypy src/

# Run tests
test:
	pytest tests/ -v --cov=ml_backend --cov-branch --cov-report=term-missing

# Train model
train:
	python -m ml_backend.api.train

# Serve API
serve:
	uvicorn ml_backend.server:app --host 127.0.0.1 --port 8000 --reload

# Release: train model and build Flutter Linux bundle
# Run from repository root: make -C ml_backend release
release: train
	@echo "Building Flutter Linux release bundle..."
	cd .. && flutter build linux --release
	@echo "Release artifacts:"
	@echo "  Model: models/homevalue_best_model.joblib"
	@echo "  Flutter bundle: build/linux/x64/release/bundle/"

# Clean cache
clean:
	rm -rf __pycache__ .pytest_cache .mypy_cache .ruff_cache
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

# Full clean including build artifacts
clean-all: clean
	rm -rf build/ dist/ *.egg-info