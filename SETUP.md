# Grimoire Setup Guide

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd Grimoire
```

### 2. Backend Setup
```bash
# Make the launch script executable
chmod +x launch_backend.sh

# Start the backend
./launch_backend.sh
```

The backend will:
- Create a Python virtual environment
- Install all dependencies (FastAPI, sentence-transformers, FAISS, etc.)
- Download the embedding model (all-MiniLM-L6-v2, ~80MB)
- Start the server on http://127.0.0.1:8000

### 3. Frontend Setup (macOS App)
```bash
# Open the project in Xcode
open macos-app/Grimoire.xcodeproj
```

If the Xcode project doesn't exist yet:
1. Open Xcode
2. Create new macOS App project
3. Name it "Grimoire"
4. Select SwiftUI as the interface
5. Copy all files from `macos-app/` into your project

### 4. Build and Run
1. In Xcode, select the Grimoire scheme
2. Choose "My Mac" as the target
3. Press `Cmd + R` to build and run

## Detailed Setup

### Python Backend Requirements
- Python 3.11 or later
- pip package manager
- 2GB RAM minimum (for embedding model)
- ~500MB disk space for dependencies

### macOS App Requirements
- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Swift 5.9 or later

## First Run

### Backend First Run
On first run, the backend will:
1. Download the sentence-transformers model (takes 1-5 minutes depending on internet speed)
2. Create necessary directories:
   - `storage/notes/` - for markdown files
   - `storage/embeddings/` - for cached embeddings
3. Create a sample welcome note
4. Start the FastAPI server

You can verify the backend is running by visiting:
- http://127.0.0.1:8000 - Health check
- http://127.0.0.1:8000/docs - Interactive API documentation
- http://127.0.0.1:8000/openapi.json - OpenAPI schema

### App First Run
On first run, the app will:
1. Connect to the backend (default: http://127.0.0.1:8000)
2. Load the note hierarchy
3. Display the welcome note
4. Start listening for typing to trigger semantic search

## Configuration

### Backend Configuration
Edit `backend/main.py` to modify:
- Server host/port (default: 127.0.0.1:8000)
- Embedding model (default: all-MiniLM-L6-v2)
- Chunking parameters

### App Configuration
Access settings via `Cmd + ,` or the Grimoire menu:
- **Backend URL**: Change if backend is running on different host/port
- **Debounce Delay**: Adjust search responsiveness (0.1-2.0 seconds)
- **Auto-save**: Enable/disable with configurable interval
- **Theme**: Light, Dark, or System

## Testing the Setup

### Test Backend
```bash
cd backend
python3 -c "
import requests
response = requests.get('http://127.0.0.1:8000')
print(f'Status: {response.status_code}')
print(f'Response: {response.json()}')
"
```

### Test API Endpoints
```bash
# Get all notes
curl http://127.0.0.1:8000/all-notes

# Get a specific note
curl http://127.0.0.1:8000/note/welcome

# Test cursor-conditioned semantic context (semantic backlinks)
curl -X POST http://127.0.0.1:8000/context \
  -H "Content-Type: application/json" \
  -d '{"text": "machine learning artificial intelligence", "note_id": "test", "cursor_offset": 10}'

# Legacy semantic search (non-cursor-conditioned)
curl -X POST http://127.0.0.1:8000/search \
  -H "Content-Type: application/json" \
  -d '{"text": "machine learning artificial intelligence", "note_id": "test"}'
```

## Troubleshooting

### Backend Won't Start
**Issue**: Python dependencies fail to install
```bash
# Try installing manually
cd backend
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn sentence-transformers faiss-cpu numpy pydantic
```

**Issue**: FAISS installation fails
```bash
# Try alternative installation
pip install faiss-cpu --no-cache-dir
# Or on Apple Silicon:
pip install faiss-cpu --no-deps
pip install numpy
```

### Model Download Issues
**Issue**: Slow or failed model download
```bash
# The model will be cached locally after first download
# Check cache location: ~/.cache/torch/sentence_transformers
# You can also use a smaller model in backend/embedder.py:
# Change model_name to "all-MiniLM-L6-v2" (already default)
```

### App Can't Connect to Backend
**Issue**: Connection refused
1. Verify backend is running: `curl http://127.0.0.1:8000`
2. Check backend URL in app settings (`Cmd + ,`)
3. Test connection in settings panel

**Issue**: CORS errors
- The backend already has CORS enabled for development
- If issues persist, check browser console for errors

### No Backlinks Appearing
**Issue**: Semantic search returns no results
1. Ensure you have at least 2 notes with substantial content
2. Wait for embeddings to be generated (first time takes longer)
3. Type more content - search triggers after 10+ characters
4. Check backend logs for errors

## Development

### Running in Development Mode

**Backend with auto-reload:**
```bash
cd backend
source venv/bin/activate
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

**App with debug logging:**
1. In Xcode, enable debug logging
2. Check Console.app for logs (filter by "Grimoire")

### Adding Sample Data
```bash
# Create sample notes
cd backend/storage/notes
echo "# Machine Learning" > machine-learning.md
echo "# Python Programming" > python.md
echo "# Project Ideas" > projects/ideas.md
```

The backend will automatically process new notes when they're accessed.

## Production Considerations

### Backend Production
For production use:
1. Use a production ASGI server (e.g., gunicorn with uvicorn workers)
2. Set up proper CORS origins
3. Add authentication if needed
4. Implement proper logging
5. Set up monitoring/health checks

### App Distribution
To distribute the macOS app:
1. Archive in Xcode
2. Notarize for Gatekeeper
3. Distribute via App Store or direct download

## Getting Help

- Check the logs in Console.app (filter by "Grimoire")
- Visit API documentation: http://127.0.0.1:8000/docs
- Check backend logs in terminal where it's running
- Review error messages in app settings test panel

## Next Steps

After setup:
1. Create your first note
2. Type some content - watch backlinks appear
3. Create nested folders for organization
4. Explore the semantic connections between notes
5. Customize settings to your preference

Enjoy your semantic note-taking journey with Grimoire!
