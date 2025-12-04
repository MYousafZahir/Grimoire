# Grimoire - Semantic macOS Notes App

> **⚠️ IMPORTANT FIX**: If you had issues with dependencies, run `./cleanup.sh` first, then `./grimoire`

A macOS desktop note editor with nested hierarchy, markdown editing, and automatic real-time semantic backlinks.

## ✨ One-Command Setup & Launch

Grimoire now includes a comprehensive launcher script that handles everything for you. **If you previously had dependency issues, run `./cleanup.sh` first to start fresh.**

```bash
# Make the launcher executable
chmod +x grimoire

# Run the launcher (does everything automatically)
./grimoire
```

That's it! The launcher will (after cleanup if needed):
1. ✅ Check system requirements (Python 3.11+, macOS 13+)
2. ✅ Set up Python virtual environment
3. ✅ Install all dependencies (FastAPI, sentence-transformers, FAISS, etc.)
4. ✅ Download the semantic model (if needed)
5. ✅ Create sample notes
6. ✅ Start the backend server
7. ✅ Build and launch the macOS app
8. ✅ Show you how to get started

## 🚀 Quick Start

### Option 1: Full Automatic Setup (Recommended)
```bash
./grimoire
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

## 🎯 What Grimoire Does

Grimoire is an intelligent note-taking app that **automatically discovers connections** between your notes as you type:

- **Semantic Backlinks**: Real-time discovery of related content across notes
- **Excerpt-Level Linking**: Links to specific passages, not just whole notes
- **Nested Hierarchy**: Organize notes in folders and subfolders
- **Markdown Editing**: Full markdown support with live preview
- **Local-Only**: All data stays on your machine
- **Real-Time**: Backlinks update as you type

## 📁 Project Structure

```
Grimoire/
├── grimoire                    # Main launcher script (run this!)
├── README.md                   # This file
├── SETUP.md                    # Detailed setup guide
├── PROJECT_SUMMARY.md          # Technical architecture
│
├── backend/                    # Python backend (semantic search)
│   ├── main.py                # FastAPI server
│   ├── chunker.py             # Text chunking
│   ├── embedder.py            # Embedding generation
│   ├── indexer.py             # FAISS vector search
│   └── storage/               # Local data storage
│
└── macos-app/                 # SwiftUI macOS application
    ├── Views/                 # SwiftUI views
    ├── FileManager/           # Note management
    ├── Networking/            # API communication
    └── create_xcode_project.sh # Xcode project setup
```

## 🖥️ How It Works

### Backend (Python)
- **FastAPI Server**: REST API for note management and search
- **Sentence-Transformers**: Converts text to semantic vectors
- **FAISS**: Fast similarity search for finding related content
- **Local Storage**: All data stored in `backend/storage/`

### Frontend (SwiftUI macOS App)
- **Three-Pane Layout**: Sidebar (notes), Editor (markdown), Backlinks (connections)
- **Real-Time Search**: Debounced search as you type
- **Native macOS**: Full macOS integration and keyboard shortcuts
- **Auto-Save**: Configurable auto-save with preview

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
- `GET /` - Health check
- `POST /search` - Semantic search for related excerpts
- `POST /update-note` - Save note and update embeddings
- `GET /all-notes` - Get hierarchical note structure
- `GET /note/{note_id}` - Get note content

## 🎨 Features

### Core Features
- **Automatic Semantic Linking**: No manual linking required
- **Real-Time Updates**: Backlinks update as you type
- **Similarity Scoring**: See how strongly notes are related (0-100%)
- **Click-to-Jump**: Click any backlink to open the related note
- **Markdown Preview**: Toggle between editor and preview modes

### Organization
- **Nested Folders**: Create unlimited hierarchy
- **Quick Search**: Find notes instantly
- **Auto-Save**: Never lose your work
- **Sample Notes**: Get started with helpful examples

### Privacy & Control
- **Local-Only**: No cloud, no accounts, no tracking
- **Configurable**: Adjust search timing, auto-save, themes
- **Exportable**: Notes are plain markdown files
- **Open Architecture**: Easy to extend and modify

## 🚦 Getting Started After Launch

1. **Open the welcome note** (already loaded)
2. **Start typing** in the editor
3. **Watch backlinks appear** in the right panel
4. **Click any backlink** to jump to related content
5. **Create new notes** using the + button in the sidebar
6. **Organize with folders** by creating nested notes

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
- **Dependency Issues**: Check for `faiss-cpu` or `No matching distribution` errors
- **Cleanup Script**: Use `./cleanup.sh` to fix dependency issues
- **API Documentation**: http://127.0.0.1:8000/docs (when backend is running)

## 📈 Development Roadmap

### MVP (Complete ✅)
- [x] Three-pane SwiftUI interface
- [x] Python backend with semantic search
- [x] Real-time backlinks
- [x] Markdown editing
- [x] Nested note hierarchy
- [x] One-command launcher

### Planned Features
- [ ] Global search across all notes
- [ ] Tags and tag-based organization
- [ ] Note templates
- [ ] Export options (PDF, HTML)
- [ ] Keyboard shortcuts customization
- [ ] Theme editor
- [ ] Plugin system

## 🤝 Contributing

Grimoire is built with:
- **Frontend**: SwiftUI, macOS native APIs
- **Backend**: Python, FastAPI, sentence-transformers, FAISS
- **Communication**: REST API over localhost

The architecture is modular and well-documented in `PROJECT_SUMMARY.md`.

## 📄 License

MIT License - see LICENSE file for details.

## 🆘 Support

### **Quick Fix for Dependency Issues**
If you see dependency errors (especially `faiss-cpu`):
```bash
./cleanup.sh
./grimoire
```

### **What Changed**
- Updated `faiss-cpu` from 1.7.4 to 1.13.0+ for Python 3.13 compatibility
- Added version ranges instead of fixed versions for better compatibility
- Added automatic cleanup and retry logic in the launcher

- **Quick Help**: Run `./grimoire help`
- **Dependency Fix**: Run `./cleanup.sh` then `./grimoire`
- **Detailed Guide**: See `SETUP.md`
- **Technical Docs**: See `PROJECT_SUMMARY.md`
- **Backend API**: http://127.0.0.1:8000/docs (when running)

---

**Happy note-taking!** Start with `./grimoire` and let the semantic connections guide your thinking.

> **Note for previous users**: If you had issues, run `./cleanup.sh` first to get the updated dependencies.
```

Now let me create a simple test to verify the launcher works. First, let me check if there are any syntax issues in the launcher script: