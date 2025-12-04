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

# Check if sentence-transformers model needs to be downloaded
echo "🤖 Checking for sentence-transformers model..."
python3 -c "
try:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('all-MiniLM-L6-v2')
    print('✅ Model is ready')
except Exception as e:
    print(f'⚠️  Model check: {e}')
    print('The model will be downloaded on first use.')
"

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
