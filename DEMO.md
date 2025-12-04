# Grimoire Demonstration

## 🎬 What to Expect When You Run Grimoire

When you run `./grimoire`, here's exactly what will happen:

## Phase 1: System Check & Setup (2-3 minutes)

### Step 1: System Requirements Check
```
✨ Grimoire Launcher v1.0.0 ✨

╔══════════════════════════════════════════════════════════════╗
║ Checking System Requirements
╚══════════════════════════════════════════════════════════════╝

✓ macOS Version: 13.5.1
✓ Python Version: 3.11.5
✓ Xcode command line tools: Installed
✓ All system requirements satisfied
```

### Step 2: Python Environment Setup
```
╔══════════════════════════════════════════════════════════════╗
║ Setting Up Python Environment
╚══════════════════════════════════════════════════════════════╝

✓ Creating virtual environment...
✓ Virtual environment created at: backend/venv
```

### Step 3: Installing Dependencies
```
╔══════════════════════════════════════════════════════════════╗
║ Installing Python Dependencies
╚══════════════════════════════════════════════════════════════╝

✓ Upgrading pip...
✓ Installing dependencies from requirements.txt...
✓ Python dependencies installed successfully
✓ Testing critical imports...
✓ All critical packages are importable
```

### Step 4: Semantic Model Preparation
```
╔══════════════════════════════════════════════════════════════╗
║ Preparing Semantic Model
╚══════════════════════════════════════════════════════════════╝

✓ Checking for sentence-transformers model...
⚠ Model will be downloaded on first use (this may take a few minutes)
ℹ The first search might be slow while the model downloads
```

### Step 5: Storage Setup
```
╔══════════════════════════════════════════════════════════════╗
║ Setting Up Storage Directories
╚══════════════════════════════════════════════════════════════╝

✓ Created directory: backend/storage
✓ Created directory: backend/storage/notes
✓ Created directory: backend/storage/embeddings
✓ Creating sample welcome note...
✓ Sample welcome note created
✓ Creating sample 'Getting Started' note...
✓ Sample 'Getting Started' note created
✓ Storage directories setup complete
```

## Phase 2: Backend Launch (30 seconds)

### Step 6: Starting Backend Server
```
╔══════════════════════════════════════════════════════════════╗
║ Starting Backend Server
╚══════════════════════════════════════════════════════════════╝

✓ Starting FastAPI server on http://127.0.0.1:8000
ℹ API Docs: http://127.0.0.1:8000/docs
ℹ OpenAPI: http://127.0.0.1:8000/openapi.json
✓ Waiting for server to start...
.....✓ Backend server started successfully (PID: 12345)
```

### Step 7: Backend Health Check
```
╔══════════════════════════════════════════════════════════════╗
║ Checking Backend Health
╚══════════════════════════════════════════════════════════════╝

✓ Testing backend connection...
✓ Backend is responding
✓ Testing API endpoints...
✓ /all-notes endpoint working
✓ Note retrieval working
```

## Phase 3: macOS App Launch (1-2 minutes)

### Step 8: Setting Up macOS Application
```
╔══════════════════════════════════════════════════════════════╗
║ Setting Up macOS Application
╚══════════════════════════════════════════════════════════════╝

✓ Creating Xcode project...
✓ Xcode project created successfully
```

### Step 9: Building and Launching App
```
╔══════════════════════════════════════════════════════════════╗
║ Launching Grimoire Application
╚══════════════════════════════════════════════════════════════╝

✓ Building Grimoire from Xcode project...
✓ App built successfully
✓ Launching Grimoire...
✓ Grimoire launched successfully!
ℹ The app will connect to the backend at http://127.0.0.1:8000
ℹ Check the backlinks panel to see semantic connections
```

## Phase 4: Application Ready!

### Final Screen
```
══════════════════════════════════════════════════════════════
✓ Grimoire is now running!
══════════════════════════════════════════════════════════════

Quick Start:
  1. Open the welcome note in Grimoire
  2. Start typing in the editor
  3. Watch backlinks appear in the right panel
  4. Click any backlink to jump to related content

Backend: http://127.0.0.1:8000/docs
Notes: backend/storage/notes
Logs: grimoire.log

Press Ctrl+C in this terminal to stop the backend
Run './grimoire stop' to stop the backend server
```

## 🖥️ What You'll See in the App

### Initial App Window
```
┌─────────────────────────────────────────────────────────────┐
│ Grimoire                                    [−] [□] [×]     │
├─────────────────────────────────────────────────────────────┤
│  Sidebar                    Editor           Backlinks      │
│  ┌────────────────┐ ┌────────────────────┐ ┌─────────────┐ │
│  │ 📁 Projects    │ │ # Welcome Note     │ │ Semantic    │ │
│  │   📝 Welcome   │ │                    │ │ Backlinks   │ │
│  │   📝 Getting   │ │ This is your first │ │             │ │
│  │     Started    │ │ note in Grimoire...│ │ No backlinks│ │
│  │   📁 Personal  │ │                    │ │ found yet.  │ │
│  │   📁 Work      │ │ Start typing to    │ │             │ │
│  │                │ │ see semantic       │ │ As you type,│ │
│  │ [+] New Note   │ │ connections appear │ │ semantically│ │
│  │                │ │ automatically!     │ │ related     │ │
│  └────────────────┘ └────────────────────┘ │ excerpts    │ │
│                                            │ will appear │ │
│                                            └─────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### After Typing (Example)
When you type about "machine learning" in the welcome note:

```
Backlinks Panel Updates:
┌─────────────────────────────────────────┐
│ Semantic Backlinks            ↻ [92%]   │
├─────────────────────────────────────────┤
│ 📝 Getting Started                      │
│   "Machine learning is a subset of AI..." │
│   From: getting-started.md • 92% match  │
│                                          │
│ 📝 Project Ideas                         │
│   "Neural networks can be used for..."  │
│   From: projects/ideas.md • 87% match   │
│                                          │
│ 📝 Research Notes                        │
│   "Deep learning requires large datasets"│
│   From: research/deep-learning.md • 76% │
└─────────────────────────────────────────┘
```

## 🎯 First-Time User Experience

### 1. **Immediate Value** (0-5 minutes)
- Open the app, see the welcome note
- Start typing about any topic
- Watch backlinks appear instantly
- Click a backlink to jump to related content

### 2. **Discovery Phase** (5-15 minutes)
- Create 2-3 new notes on different topics
- Notice how Grimoire finds connections automatically
- Experiment with markdown formatting
- Organize notes into folders

### 3. **Productive Use** (15+ minutes)
- Use as your daily note-taking app
- Let semantic connections guide research
- Build a personal knowledge base
- Discover unexpected relationships between ideas

## 🔧 Troubleshooting First Run

### If Something Goes Wrong:

1. **Check the log file**:
   ```bash
   tail -f grimoire.log
   ```

2. **Reset and try again**:
   ```bash
   ./grimoire reset
   ./grimoire
   ```

3. **Manual step-by-step**:
   ```bash
   ./grimoire setup
   ./grimoire backend
   # In another terminal:
   ./grimoire app
   ```

### Common First-Run Scenarios:

**Scenario 1: Model download is slow**
- First search takes 2-5 minutes
- Subsequent searches are instant
- Model is cached locally (~80MB)

**Scenario 2: Xcode build fails**
- Open `macos-app/Grimoire.xcodeproj` manually
- Build in Xcode (Cmd+R)
- The launcher will detect the built app next time

**Scenario 3: Port 8000 is in use**
- Launcher automatically checks
- Uses next available port if needed
- Updates app configuration automatically

## 🎉 Success Indicators

You'll know Grimoire is working when:

1. ✅ Backend shows "status: ok" at http://127.0.0.1:8000
2. ✅ macOS app opens with three-pane interface
3. ✅ Welcome note loads in editor
4. ✅ Typing triggers backlinks (after 10+ characters)
5. ✅ Clicking backlinks opens target notes

## 📊 Expected Performance

- **First launch**: 3-5 minutes (includes setup)
- **Subsequent launches**: 30 seconds
- **First search**: 2-5 minutes (model download)
- **Subsequent searches**: < 100ms
- **Note save**: < 500ms
- **Backlink updates**: Real-time as you type

## 🚀 Ready to Go!

The entire setup is automated. Just run:

```bash
chmod +x grimoire
./grimoire
```

Then start typing and watch your notes come to life with automatic semantic connections!

---

*Note: Times are estimates based on typical macOS systems with decent internet connection. The semantic model download (~80MB) is the main variable factor.*