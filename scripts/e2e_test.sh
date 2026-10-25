#!/usr/bin/env bash
# End-to-end test script for HomeValue
# Starts FastAPI server, runs Flutter integration tests, stops server

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ML_BACKEND_DIR="$PROJECT_ROOT/ml_backend"
FLUTTER_DIR="$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SERVER_PID=""

cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Stopping FastAPI server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

echo -e "${GREEN}=== HomeValue E2E Test ===${NC}"
echo "Project root: $PROJECT_ROOT"

# Check if we're in the right directory
if [ ! -f "$ML_BACKEND_DIR/pyproject.toml" ] && [ ! -f "$ML_BACKEND_DIR/requirements.txt" ]; then
    echo -e "${RED}Error: ml_backend directory not found or not a Python project${NC}"
    exit 1
fi

if [ ! -f "$FLUTTER_DIR/pubspec.yaml" ]; then
    echo -e "${RED}Error: Flutter project not found${NC}"
    exit 1
fi

# Start FastAPI server
echo -e "${YELLOW}Starting FastAPI server...${NC}"
cd "$ML_BACKEND_DIR"

# Check if virtual environment exists
if [ -d ".venv" ]; then
    source .venv/bin/activate
elif [ -d "venv" ]; then
    source venv/bin/activate
else
    echo -e "${YELLOW}No virtual environment found, using system Python${NC}"
fi

# Train model if not exists
MODEL_PATH="$ML_BACKEND_DIR/models/homevalue_best_model.joblib"
if [ ! -f "$MODEL_PATH" ]; then
    echo -e "${YELLOW}Model not found, training...${NC}"
    python -m home_value.train || {
        echo -e "${RED}Model training failed${NC}"
        exit 1
    }
fi

# Start server in background
python -m uvicorn home_value.server:app --host 0.0.0.0 --port 8000 &
SERVER_PID=$!

# Wait for server to be ready
echo -e "${YELLOW}Waiting for server to be ready...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo -e "${GREEN}Server is ready!${NC}"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        echo -e "${RED}Server failed to start within 30 seconds${NC}"
        exit 1
    fi
done

# Verify model is loaded
echo -e "${YELLOW}Verifying model is loaded...${NC}"
MODEL_INFO=$(curl -s http://localhost:8000/model_info)
if echo "$MODEL_INFO" | grep -q '"loaded": true'; then
    echo -e "${GREEN}Model loaded successfully${NC}"
else
    echo -e "${RED}Model not loaded: $MODEL_INFO${NC}"
    exit 1
fi

# Run Flutter integration tests
echo -e "${YELLOW}Running Flutter integration tests...${NC}"
cd "$FLUTTER_DIR"

# Check if integration_test directory exists
if [ ! -d "integration_test" ]; then
    echo -e "${RED}integration_test directory not found${NC}"
    exit 1
fi

# Run integration tests
flutter test integration_test/app_test.dart -d linux --timeout=120s || {
    echo -e "${RED}Flutter integration tests failed${NC}"
    exit 1
}

echo -e "${GREEN}=== All E2E tests passed! ===${NC}"