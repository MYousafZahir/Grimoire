#!/bin/bash

# Grimoire Backend Launch Script
# This script sets up and launches the Python backend server

set -e

echo "🚀 Starting Grimoire Backend..."

# Change to backend directory
cd "$(dirname "$0")/backend"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python 3.11 or later."
    exit 1
fi

# Check Python version
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "📦 Python version: $PYTHON_VERSION"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "🔧 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source venv/bin/activate

# Install/upgrade pip
echo "📦 Upgrading pip..."
pip install --upgrade pip

# Install requirements
echo "📦 Installing dependencies..."
pip install -r requirements.txt

# Check if required models need to be downloaded
echo "🤖 Downloading required models..."
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
    echo "✅ Models are ready"
else
    echo "⚠️  Some models could not be downloaded"
    echo "   The app will attempt to download them when first used."
fi

# Create necessary directories
echo "📁 Creating storage directories..."
mkdir -p storage/notes
mkdir -p storage/embeddings

# Check if sample note exists
if [ ! -f "storage/notes/welcome.md" ]; then
    echo "📝 Creating sample note..."
    cp ../backend/storage/notes/welcome.md storage/notes/welcome.md 2>/dev/null || echo "# Welcome to Grimoire" > storage/notes/welcome.md
fi

# Start the FastAPI server
echo "🌐 Starting FastAPI server on http://127.0.0.1:8000"
echo "📚 API Documentation: http://127.0.0.1:8000/docs"
echo "📊 OpenAPI Schema: http://127.0.0.1:8000/openapi.json"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Run the server
python3 main.py
