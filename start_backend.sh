#!/bin/bash

# Grimoire Backend Startup Script
# This script helps start the Python backend for the Grimoire app

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Grimoire Backend Startup${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

if [ ! -d "$PROJECT_ROOT/backend" ]; then
    echo -e "${RED}Error: Backend directory not found${NC}"
    echo -e "${YELLOW}Please run this script from the Grimoire project root${NC}"
    exit 1
fi

cd "$PROJECT_ROOT/backend"

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 not found${NC}"
    echo -e "${YELLOW}Please install Python 3.8 or higher${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Python 3 found: $(python3 --version)${NC}"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}Virtual environment not found. Creating one...${NC}"

    # Create virtual environment
    python3 -m venv venv

    # Activate virtual environment
    source venv/bin/activate

    # Upgrade pip
    pip install --upgrade pip

    # Install requirements
    echo -e "${BLUE}Installing Python dependencies...${NC}"
    pip install -r requirements.txt

    echo -e "${GREEN}✓ Virtual environment created and dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Virtual environment found${NC}"
    source venv/bin/activate
fi

# Check if required models need to be downloaded
echo -e "${BLUE}Downloading required models...${NC}"
if python3 - <<'PY'
import os
import sys

errors = []

def normalize(value: str, fallback: str) -> str:
    name = (value or fallback or "").strip()
    return name

def is_disabled(flag: str) -> bool:
    return flag.strip().lower() in ("0", "false", "no", "off")

search_model = normalize(os.environ.get("GRIMOIRE_SEARCH_EMBED_MODEL"), "BAAI/bge-small-en-v1.5")
context_model = normalize(os.environ.get("GRIMOIRE_BGE_EMBED_MODEL"), "BAAI/bge-small-en-v1.5")
reranker_model = normalize(os.environ.get("GRIMOIRE_BGE_RERANKER_MODEL"), "BAAI/bge-reranker-base")
spacy_model = normalize(os.environ.get("GRIMOIRE_SPACY_MODEL"), "en_core_web_sm")

models = []

def add_model(label: str, name: str) -> None:
    if name:
        models.append((label, name))

add_model("search embedder", search_model)
if context_model and context_model != search_model:
    add_model("context embedder", context_model)

reranker_enabled = not is_disabled(os.environ.get("GRIMOIRE_ENABLE_RERANKER", "1"))
if reranker_enabled and reranker_model:
    add_model("reranker", reranker_model)

unique_models = []
seen = set()
for label, name in models:
    if name in seen:
        continue
    seen.add(name)
    unique_models.append((label, name))

try:
    from huggingface_hub import snapshot_download  # type: ignore
except Exception as exc:
    snapshot_download = None
    errors.append(f"huggingface_hub unavailable: {exc}")

if snapshot_download:
    for label, name in unique_models:
        if os.path.exists(name):
            print(f"{label}: using local path {name}")
            continue
        try:
            print(f"{label}: downloading {name}")
            snapshot_download(repo_id=name, local_files_only=False)
            print(f"{label}: ready")
        except Exception as exc:
            errors.append(f"{label} model '{name}' download failed: {exc}")
else:
    for label, name in unique_models:
        errors.append(f"{label} model '{name}' could not be checked (huggingface_hub missing)")

try:
    import spacy  # type: ignore
    if os.path.exists(spacy_model):
        spacy.load(spacy_model)
        print(f"spaCy: loaded {spacy_model}")
    else:
        try:
            spacy.load(spacy_model)
            print(f"spaCy: model '{spacy_model}' ready")
        except Exception:
            print(f"spaCy: downloading '{spacy_model}'")
            from spacy.cli import download as spacy_download  # type: ignore
            spacy_download(spacy_model)
            spacy.load(spacy_model)
            print(f"spaCy: model '{spacy_model}' ready")
except Exception as exc:
    errors.append(f"spaCy model '{spacy_model}' unavailable: {exc}")

if errors:
    for err in errors:
        print(err)
    sys.exit(1)
PY
then
    echo -e "${GREEN}✓ Models are ready${NC}"
else
    echo -e "${YELLOW}⚠ Some models could not be downloaded${NC}"
    echo -e "${YELLOW}  The app will attempt to download them when first used${NC}"
fi

# Check if storage directory exists
STORAGE_DIR="storage/notes"
if [ ! -d "$STORAGE_DIR" ]; then
    echo -e "${BLUE}Creating storage directory...${NC}"
    mkdir -p "$STORAGE_DIR"
    echo -e "${GREEN}✓ Storage directory created${NC}"
else
    echo -e "${GREEN}✓ Storage directory exists${NC}"
fi

# Count existing .grim files
GRIM_COUNT=$(find "$STORAGE_DIR" -name "*.grim" 2>/dev/null | wc -l)
echo -e "${BLUE}Found $GRIM_COUNT .grim files${NC}"

# Start the backend server
echo -e "\n${BLUE}Starting Grimoire backend server...${NC}"
echo -e "${YELLOW}Server will run at: http://127.0.0.1:8000${NC}"
echo -e "${YELLOW}API documentation: http://127.0.0.1:8000/docs${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo -e "${BLUE}----------------------------------------${NC}"

# Run the server
python3 main.py

# Handle server exit
echo -e "\n${BLUE}----------------------------------------${NC}"
echo -e "${YELLOW}Backend server stopped${NC}"
echo -e "\n${BLUE}To restart:${NC}"
echo -e "  ${YELLOW}./start_backend.sh${NC} (from Grimoire directory)"
echo -e "  ${YELLOW}Or: cd backend && source venv/bin/activate && python3 main.py${NC}"
