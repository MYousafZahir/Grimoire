# Grimoire macOS App

A native macOS application for semantic note-taking with automatic backlinks.

## Features

- **Native macOS Interface**: Built with SwiftUI for a seamless macOS experience
- **Three-Pane Layout**: Sidebar (note hierarchy), Editor (markdown), Backlinks (semantic connections)
- **Real-Time Semantic Search**: Automatic backlinks update as you type
- **Markdown Support**: Write with full markdown syntax, with live preview option
- **Nested Note Hierarchy**: Organize notes in folders and subfolders
- **Local-First Architecture**: All data stays on your machine

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Python backend running (see Backend Setup)

## Project Structure

```
macos-app/
├── GrimoireApp.swift              # App entry point
├── ContentView.swift              # Main three-pane layout
├── SidebarView.swift              # Note hierarchy sidebar
├── EditorView.swift               # Markdown editor
├── BacklinksView.swift            # Semantic backlinks panel
├── SettingsView.swift             # App settings
├── Domain/                        # Domain models
├── Data/                          # HTTP repositories
├── Stores/                        # ObservableObject state stores
├── Resources/                     # App resources
└── README.md
```

## Getting Started

### 1. Backend Setup

First, ensure the Python backend is running:

```bash
cd ../backend
./launch_backend.sh
```

Or manually:
```bash
cd ../backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 main.py
```

The backend will start on `http://127.0.0.1:8000`.

### 2. Open in Xcode

```bash
open macos-app/Grimoire.xcodeproj
```

Or create a new Xcode project if needed:
1. Open Xcode
2. Create new macOS App project
3. Select SwiftUI as the interface
4. Copy the files from this directory into your project

### 3. Build and Run

1. Select the Grimoire scheme
2. Choose your target device (My Mac)
3. Click the Run button (▶️) or press `Cmd + R`

## Architecture

### NoteManager
Replaced by `NoteStore` + `HTTPNoteRepository`:
- `NoteStore` owns tree state, selection, drafts, and save lifecycle (async/await)
- `HTTPNoteRepository` wraps backend endpoints for notes/folders

### SearchManager
Replaced by `BacklinksStore` + `HTTPSearchRepository`:
- `BacklinksStore` handles debounced semantic search and result cache per note
- `HTTPSearchRepository` wraps `/context` backend endpoint

### Views
- **ContentView**: Main container with three-pane layout
- **SidebarView**: Displays nested note hierarchy with folder support
- **EditorView**: Markdown editor with auto-save and preview toggle
- **BacklinksView**: Shows semantically related excerpts from other notes
- **SettingsView**: App configuration and backend settings

## API Integration

The app communicates with the Python backend via REST API:

- `GET /notes` - Get note hierarchy for sidebar
- `GET /note/{note_id}` - Get note content
- `POST /update-note` - Save note content and update embeddings
- `POST /context` - Get cursor-conditioned semantic backlinks for current note
- `POST /attachments` - Upload an image attachment (multipart form)
- `GET /attachments/{filename}` - Serve a previously uploaded attachment

## Configuration

Settings are stored in UserDefaults and can be accessed via the Settings menu (`Cmd + ,`):

- **Backend URL**: URL of the Python backend (default: `http://127.0.0.1:8000`)
- **Debounce Delay**: Delay before searching after typing stops (0.1-2.0 seconds)
- **Auto-save**: Enable/disable auto-save with configurable interval
- **Markdown Preview**: Toggle between editor and preview mode
- **Theme**: Light, Dark, or System theme

## Development Notes

### Dependencies
- SwiftUI for UI components
- MarkdownUI for markdown rendering (if using preview feature)
- URLSession + async/await for networking

### Key Features Implementation

1. **Real-Time Search**: Uses debounced search with 500ms delay by default
2. **Auto-Save**: Saves note content 2 seconds after last edit
3. **Note Hierarchy**: Recursive tree structure with folder/note distinction
4. **Semantic Backlinks**: Displays excerpts with similarity scores (0-100%)
5. **Image Attachments**: Drag/drop or paste images into the plain-text editor to upload and insert markdown (`![](/attachments/...)`)

### Testing

The app includes preview data for testing UI components without a running backend:

```swift
#Preview {
    ContentView()
        .environmentObject(NoteStore())
        .environmentObject(BacklinksStore())
}
```

## Troubleshooting

### Backend Connection Issues
1. Ensure Python backend is running: `http://127.0.0.1:8000`
2. Check backend URL in Settings (`Cmd + ,`)
3. Use "Test Connection" button in Settings

### No Backlinks Appearing
1. Ensure you have multiple notes with content
2. Wait for the backend to process embeddings (first run may take time)
3. Check that note content is being saved (auto-save indicator)

### Build Errors
1. Clean build folder: `Shift + Cmd + K`
2. Delete derived data: `Xcode → Preferences → Locations → Derived Data`
3. Ensure all Swift files are added to the target

## Future Enhancements

Planned features for future releases:

1. **Global Search**: Search across all notes
2. **Tags**: Tag-based organization
3. **Note Templates**: Pre-defined note structures
4. **Export Options**: Export notes as PDF, HTML, or plain text
5. **Keyboard Shortcuts**: Customizable keyboard shortcuts
6. **Plugin System**: Extend functionality with plugins
7. **Sync**: Optional cloud sync with end-to-end encryption

## License

MIT License - see LICENSE file for details.

## Support

For issues and feature requests, please use the GitHub issue tracker.
