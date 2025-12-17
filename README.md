# Grimoire — Local-First Semantic macOS Notes App

A local-first macOS notes app with:

- `.grim` projects (each project has its own notes + indexes)
- nested folders + notes (drag/drop restructuring)
- chunk-based Markdown editor (renders everything except the chunk you’re editing)
- cursor-conditioned “semantic backlinks” sidebar (verbatim snippets, no generation)
- automated glossary (People / Places / Things) built only from your notes (verbatim definitions)

If you run into build/dependency issues: `./cleanup.sh` then `./grimoire` (or `./.rebuild.sh` for a faster cached rebuild).

## ✨ One-Command Setup & Launch (Recommended)

The launcher handles backend setup + app build/launch.

```bash
# Make the launcher executable
chmod +x grimoire

# Run the launcher (does everything automatically)
./grimoire
```

On launch you’ll land in **Project Selection** (create/open a `.grim` project, or open a recent project).

## 🚀 Quick Start

### Option 1: Full Automatic Setup (Recommended)
```bash
./grimoire
```

### Option 1b: Faster “clean rebuild” (cached)
```bash
./.rebuild.sh
```

### Option 2: Step-by-Step Setup
```bash
# Setup only (no launch)
./grimoire setup

# Start backend only
./grimoire backend

# Launch app only (backend must be running)
./grimoire app
```

### Option 3: Manual Control
```bash
# Check status
./grimoire status

# Stop backend
./grimoire stop

# Reset everything
./grimoire reset

# Show help
./grimoire help
```

## 🎯 How It Works (At a Glance)

- **macOS app (SwiftUI)**: UI, chunk editor, sidebar tree, backlinks + glossary panels
- **backend (Python/FastAPI)**: project storage, indexing, retrieval, glossary building
- **local-only models**:
  - embeddings: `BAAI/bge-small-en-v1.5`
  - reranker: `BAAI/bge-reranker-base` (optional)
  - spaCy `en_core_web_sm` (optional; glossary has a fallback mode)

## 📁 Project Structure

```
Grimoire/
├── grimoire                    # Main launcher script (run this!)
├── .rebuild.sh                 # Fast cached rebuild helper (cleanup + launch)
├── cleanup.sh                  # Reset build env (keeps projects/notes)
├── README.md                   # This file
├── SETUP.md                    # Detailed setup guide
├── PROJECT_SUMMARY.md          # Technical architecture
├── technical specficiations/   # Detailed subsystem specs (see below)
│
├── backend/                    # Python backend (semantic search)
│   ├── main.py                 # FastAPI app + routes
│   ├── app_state.py            # Project-scoped service wiring
│   ├── project_manager.py      # .grim projects
│   ├── storage.py              # Notes/folders persistence
│   ├── context_service.py      # Semantic backlinks retrieval/indexing
│   ├── glossary_service.py     # Automated glossary (spaCy + fallback)
│   └── storage/                # Local projects + state
│
└── macos-app/                  # SwiftUI macOS application
    ├── Domain/                 # Core models
    ├── Data/                   # API repositories
    ├── Stores/                 # App state containers
    ├── Resources/              # App metadata
    ├── *.swift                 # Views + app entry points
    └── create_xcode_project.sh # Xcode project setup
```

## 📚 Technical Specifications

Start here:

- `technical specficiations/00-system-overview.md`

Subsystem deep-dives:

- `technical specficiations/01-backend-fastapi.md`
- `technical specficiations/02-macos-app.md`
- `technical specficiations/03-projects-and-storage.md`
- `technical specficiations/04-semantic-backlinks.md`
- `technical specficiations/05-glossary.md`
- `technical specficiations/06-chunked-editor.md`
- `technical specficiations/07-build-and-dev.md`
- `technical specficiations/08-api.md`

## 🔧 Manual Setup (If Needed)

If you prefer manual setup:

### 1. Backend Setup
```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 main.py
```

### 2. Frontend Setup
```bash
cd macos-app
./create_xcode_project.sh
open Grimoire.xcodeproj
# In Xcode: Build and run (Cmd+R)
```

## 📊 API Endpoints

The backend provides these REST endpoints:
- `GET /` and `GET /health` - Health checks
- `GET /projects*` - Project management (`.grim`)
- `GET /notes` (alias `/all-notes`) - Note tree (flat list with children refs)
- `GET /note/{note_id:path}` - Get note content
- `POST /update-note` - Save note and update embeddings
- `POST /create-note` / `/create-folder` - Create items
- `POST /rename-note` / `/delete-note` - Modify items
- `POST /context` - Cursor-conditioned semantic context (semantic backlinks)
- `POST /search` - Legacy semantic search (non-cursor-conditioned)
- `POST /admin/rebuild-index` - Rebuild vector index
- `GET /glossary` and `POST /admin/rebuild-glossary` - Glossary

## 🎨 Features

### Core Features
- **Semantic backlinks (cursor-conditioned)**: Verbatim snippets from other notes relevant to the current cursor context
- **Automated glossary**: Terms + verbatim definitions derived from your own corpus
- **Project system**: Create/open `.grim` projects, including a “recent projects” list

### Organization
- **Nested folders**: Create deep hierarchies
- **Drag & drop**: Restructure notes/folders without breaking links
- **Quick Search**: Find notes instantly
- **Auto-Save**: Never lose your work

### Privacy & Control
- **Local-Only**: No cloud, no accounts, no tracking
- **Deterministic output**: No generative text; everything is traceable to source notes

## 🚦 Getting Started After Launch

1. Create or open a `.grim` project from the Project Selection screen.
2. Create notes/folders in the sidebar.
3. Write in the editor; semantic backlinks appear on the right.
4. Open the glossary panel from the sidebar icon.
5. Use the macOS menu bar `File` menu for project actions and `Rebuild Glossary`.

## 🐛 Troubleshooting

### **If Dependencies Failed to Install**
If you see errors about `faiss-cpu` or other dependencies:

```bash
# 1. Clean up old environment
./cleanup.sh

# 2. Start fresh
./grimoire
```

This will:
1. Remove the old virtual environment with incompatible dependencies
2. Create a fresh environment with updated requirements
3. Install compatible versions for your Python version (3.13+)

### **Common Dependency Issues**
- **Python 3.13 users**: The original `faiss-cpu==1.7.4` doesn't work. Use `./cleanup.sh` then `./grimoire`
- **Apple Silicon (M1/M2/M3)**: Some packages need specific builds. The launcher handles this automatically after cleanup.
- **Network issues**: The launcher includes retry logic for downloads.

### **Manual Fix (if needed)**
```bash
# Remove old venv manually
rm -rf backend/venv

# Update requirements (already done in current version)
# Then run launcher
./grimoire
```

### Common Issues

**Backend won't start (dependency issues):**
```bash
# First, clean up old environment
./cleanup.sh

# Then start fresh
./grimoire
```

**Backend won't start (other issues):**
```bash
# Check logs
tail -f grimoire.log

# Reset and try again
./grimoire reset
./grimoire
```

**No backlinks appearing:**
- Make sure you have at least 2 notes with content
- Type more text (search triggers after 10+ characters)
- Wait for the semantic model to download (first time only)

**App won't launch:**
```bash
# Check if backend is running
./grimoire status

# Try building manually
cd macos-app
xcodebuild -project Grimoire.xcodeproj -scheme Grimoire
```

### Logs & Debugging
- **Application Logs**: Check Console.app (filter by "Grimoire")
- **Backend Logs**: `tail -f grimoire.log`
- **Dependency Issues**: Check for `faiss-cpu` / Python version compatibility errors
- **Fast rebuild**: Use `./.rebuild.sh` to clean-rebuild while caching dependencies
- **API Documentation**: http://127.0.0.1:8000/docs (when backend is running)

## 🤝 Contributing

Grimoire is built with:
- **Frontend**: SwiftUI, macOS native APIs
- **Backend**: Python, FastAPI, local embedding + reranking models, FAISS
- **Communication**: REST API over localhost

The architecture is modular and documented in `PROJECT_SUMMARY.md` and `technical specficiations/`.

## 🆘 Support

### **Quick Fix for Dependency Issues**
If you see dependency errors (especially `faiss-cpu`):
```bash
./cleanup.sh
./grimoire
```

- **Quick Help**: Run `./grimoire help`
- **Dependency Fix**: Run `./cleanup.sh` then `./grimoire`
- **Fast Cached Rebuild**: Run `./.rebuild.sh`
- **Detailed Guide**: See `SETUP.md`
- **Technical Docs**: See `technical specficiations/00-system-overview.md`
- **Backend API**: http://127.0.0.1:8000/docs (when running)

---
**Happy note-taking!** Start with `./grimoire`.
