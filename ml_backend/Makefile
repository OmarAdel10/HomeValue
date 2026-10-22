# HomeValue ML Backend Makefile
.PHONY: install format lint test train serve clean help

# Default target
help:
	@echo "HomeValue ML Backend - Available targets:"
	@echo "  install  - Install dependencies (with dev extras)"
	@echo "  format   - Format code with black and ruff"
	@echo "  lint     - Run linting (ruff, mypy)"
	@echo "  test     - Run tests with pytest"
	@echo "  train    - Train model and save to models/"
	@echo "  serve    - Start FastAPI server"
	@echo "  clean    - Remove cache and build artifacts"

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
	pytest tests/ -v

# Train model
train:
	python -m ml_backend.scripts.train

# Serve API
serve:
	uvicorn ml_backend.server:app --host 0.0.0.0 --port 8000 --reload

# Clean cache
clean:
	rm -rf __pycache__ .pytest_cache .mypy_cache .ruff_cache
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
