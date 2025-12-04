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

# Check if sentence-transformers model needs to be downloaded
echo -e "${BLUE}Checking for sentence-transformers model...${NC}"
python3 -c "
import sys
sys.path.insert(0, '.')
try:
    from embedder import Embedder
    e = Embedder()
    e.load_model()
    print('✓ Model is available')
except Exception as e:
    print(f'⚠ Model loading issue: {e}')
    print('The model will be downloaded when first used')
" 2>/dev/null || echo -e "${YELLOW}⚠ Could not check model status${NC}"

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
