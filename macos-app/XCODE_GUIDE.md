# Xcode Setup Guide

## Quick Start

### Option 1: Build from command line
```bash
# Build the app
./build_simple.sh

# Run the app (make sure backend is running first)
open Grimoire.app
```

### Option 2: Open in Xcode
```bash
# Open the project
open Grimoire.xcodeproj
```
Then:
1. Select "Grimoire" scheme
2. Choose "My Mac" as destination
3. Press `Cmd + R` to build and run

## Project Structure

The Xcode project includes:
- `GrimoireApp.swift` - App entry point
- `ContentView.swift` - Main layout
- `SidebarView.swift` - Note hierarchy
- `EditorView.swift` - Markdown editor
- `BacklinksView.swift` - Semantic connections
- `SettingsView.swift` - App settings
- `NoteManager.swift` - Note management
- `SearchManager.swift` - Semantic search
- `Resources/Info.plist` - App configuration

## Backend Requirements

The app needs the Python backend running:
```bash
# From the Grimoire root directory
./grimoire backend
```

Or manually:
```bash
cd ../backend
source venv/bin/activate
python3 main.py
```

The app connects to: http://127.0.0.1:8000

## Troubleshooting

### "Cannot code sign" error
The project is configured with:
- No code signing required for development
- `PRODUCT_BUNDLE_IDENTIFIER = com.grimoire.app`
- `CODE_SIGNING_ALLOWED = NO`

### Missing files
If files are missing:
1. Open `Grimoire.xcodeproj`
2. Drag missing files into project navigator
3. Check "Copy items if needed"
4. Add to Grimoire target

### Build fails
Try:
1. Clean build folder: `rm -rf Build`
2. Open in Xcode and build manually
3. Check for Swift syntax errors
