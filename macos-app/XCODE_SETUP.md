# Xcode Project Setup

## Quick Start

1. **Open the project**:
   ```bash
   open Grimoire.xcodeproj
   ```

2. **Build and run**:
   - Select the "Grimoire" scheme
   - Choose "My Mac" as the destination
   - Press `Cmd + R` to build and run

## Alternative: Command Line Build

```bash
# Build from command line
./build_app.sh

# Run the built app
open Grimoire.app
```

## Project Structure

```
macos-app/
├── Grimoire.xcodeproj/          # Xcode project
├── Resources/                   # Resources (Info.plist)
├── Views/                       # SwiftUI views
├── FileManager/                 # Note management
├── Networking/                  # API communication
├── GrimoireApp.swift           # App entry point
├── build_app.sh                # Build script
└── XCODE_SETUP.md              # This file
```

## Troubleshooting

### "Cannot code sign" error
The project is configured with:
- `PRODUCT_BUNDLE_IDENTIFIER = com.grimoire.app`
- `INFOPLIST_FILE = Resources/Info.plist`
- No code signing required for development

### Missing files
If files are missing from the project:
1. Open Grimoire.xcodeproj
2. Drag missing files into the project navigator
3. Make sure "Copy items if needed" is checked
4. Add to the Grimoire target

### Swift Package Dependencies
The project includes MarkdownUI for markdown rendering.
If package resolution fails, in Xcode: File → Add Packages..., enter
`https://github.com/gonzalezreal/swift-markdown-ui`, and add it to the Grimoire target.

## Backend Requirements

Make sure the Python backend is running:
```bash
cd ../backend
source venv/bin/activate
python3 main.py
```

Or use the launcher:
```bash
cd ..
./grimoire backend
```

The app will connect to: http://127.0.0.1:8000
