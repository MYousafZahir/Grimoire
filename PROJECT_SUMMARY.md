# Grimoire Project Summary

## Overview
Grimoire is a semantic macOS notes application with automatic real-time backlinks, built using SwiftUI for the frontend and Python/FastAPI for the backend. The application enables intelligent note-taking by automatically discovering and displaying semantic connections between notes as you type.

## Architecture

### Frontend (macOS App)
- **Technology**: SwiftUI, native macOS application
- **Layout**: Three-pane interface (sidebar, editor, backlinks panel)
- **Key Components**:
  - `GrimoireApp.swift`: App entry point
  - `ContentView.swift`: Main three-pane container
  - `SidebarView.swift`: Hierarchical note navigation
  - `EditorView.swift`: Markdown editor with live preview
  - `BacklinksView.swift`: Semantic connections display
  - `NoteManager.swift`: Note persistence and API communication
  - `SearchManager.swift`: Semantic search with debouncing
  - `SettingsView.swift`: App configuration

### Backend (Python Server)
- **Technology**: FastAPI, sentence-transformers, FAISS
- **Key Components**:
  - `main.py`: FastAPI server with REST endpoints
  - `chunker.py`: Text segmentation into 150-300 character excerpts
  - `embedder.py`: Text embedding using sentence-transformers
  - `indexer.py`: FAISS vector index management
  - `requirements.txt`: Python dependencies

### Storage
- **Notes**: Plain markdown files in nested directories
- **Embeddings**: FAISS index for vector similarity search
- **Metadata**: JSON file for chunk information
- **Location**: All data stored locally in `backend/storage/`

## Key Features

### 1. Semantic Backlinks
- Real-time discovery of related content across notes
- Excerpt-level linking (not just note-to-note)
- Similarity scoring (0-100%) for each connection
- Dynamic updating as you type

### 2. Note Management
- Nested hierarchy with folders and subfolders
- Markdown editing with live preview
- Auto-save with configurable intervals
- Native macOS interface with keyboard shortcuts

### 3. Search & Discovery
- Debounced real-time search (500ms default)
- Configurable search parameters
- Exclusion of current note from results
- Context-aware excerpt display

### 4. Configuration
- Backend URL configuration
- Search debounce timing
- Auto-save settings
- Theme selection (light/dark/system)

## API Design

### REST Endpoints
- `GET /` - Health check
- `POST /search` - Semantic search for related excerpts
- `POST /update-note` - Save note and update embeddings
- `GET /all-notes` - Get hierarchical note structure
- `GET /note/{note_id}` - Get note content

### Data Flow
1. User types in editor → text sent to `/search` after debounce
2. Backend embeds text → searches FAISS index → returns top matches
3. Frontend displays backlinks in right panel
4. User clicks backlink → opens target note at relevant excerpt
5. Note changes auto-saved → backend re-chunks and re-embeds

## Setup Requirements

### Backend
- Python 3.11+
- Dependencies: FastAPI, sentence-transformers, FAISS, numpy
- Initial model download: ~80MB (all-MiniLM-L6-v2)
- Launch script: `./launch_backend.sh`

### Frontend
- macOS 13.0+ (Ventura)
- Xcode 15.0+
- Swift 5.9+
- Optional: MarkdownUI for preview feature

## Project Structure

```
Grimoire/
├── README.md                    # Main project documentation
├── SETUP.md                     # Detailed setup guide
├── PROJECT_SUMMARY.md          # This file
├── launch_backend.sh           # Backend launch script
│
├── backend/                    # Python backend
│   ├── main.py                # FastAPI server
│   ├── chunker.py             # Text chunking logic
│   ├── embedder.py            # Embedding generation
│   ├── indexer.py             # FAISS index management
│   ├── requirements.txt       # Python dependencies
│   └── storage/               # Local data storage
│       ├── notes/            # Markdown files
│       ├── index.json        # Chunk metadata
│       └── faiss.index       # Vector index
│
└── macos-app/                 # SwiftUI macOS app
    ├── GrimoireApp.swift      # App entry point
    ├── create_xcode_project.sh # Project setup script
    ├── Package.swift          # Swift dependencies
    ├── README.md              # App documentation
    │
    ├── Views/                 # SwiftUI views
    │   ├── ContentView.swift  # Main layout
    │   ├── SidebarView.swift  # Note hierarchy
    │   ├── EditorView.swift   # Markdown editor
    │   ├── BacklinksView.swift # Semantic backlinks
    │   └── SettingsView.swift # App settings
    │
    ├── FileManager/           # Note management
    │   └── NoteManager.swift  # Note persistence
    │
    └── Networking/            # API communication
        └── SearchManager.swift # Semantic search
```

## Development Status

### ✅ Completed
- Complete backend implementation (FastAPI + FAISS)
- Complete frontend SwiftUI architecture
- API design and communication layer
- Project structure and scaffolding
- Documentation and setup guides
- Sample data and configurations

### 🔄 Next Steps
1. Create Xcode project using provided script
2. Install Python dependencies and test backend
3. Build and run macOS application
4. Test semantic search functionality
5. Add additional features (tags, global search, etc.)

## Technical Highlights

### Semantic Engine
- Uses sentence-transformers (MiniLM-L6-v2) for embeddings
- FAISS for efficient similarity search
- Configurable chunking (150-300 characters)
- Overlap between chunks for context preservation

### Real-Time Performance
- Debounced search to prevent excessive API calls
- Local FAISS index for sub-second search times
- Efficient embedding caching
- Background processing for note updates

### Privacy & Security
- All data stored locally
- No cloud dependencies
- No external API calls (except initial model download)
- Configurable CORS for development

## Scalability Considerations

### Current Limitations
- Single-user, local-only design
- In-memory FAISS index (limited by RAM)
- No concurrent editing support
- No version history

### Future Scalability
- Could add SQLite for metadata scaling
- Distributed FAISS indexes for larger collections
- Multi-user support with authentication
- Cloud sync option with end-to-end encryption

## Getting Started

1. **Backend**: Run `./launch_backend.sh` to start Python server
2. **Frontend**: Use `create_xcode_project.sh` to set up Xcode project
3. **Integration**: Configure backend URL in app settings
4. **Testing**: Create notes and observe semantic backlinks

## Conclusion

Grimoire provides a sophisticated yet approachable semantic note-taking experience for macOS users. By combining modern SwiftUI development with Python's ML ecosystem, it offers intelligent note organization without compromising privacy or requiring cloud services. The modular architecture allows for easy extension and customization based on user needs.