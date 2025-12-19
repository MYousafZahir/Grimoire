# Grimoire — Build, Launch, and Development Technical Specification

This document describes how to build and run Grimoire, and what the helper scripts do.

---

## One-Command Launcher (Recommended)

- Script: `./grimoire`
- Responsibilities:
  - check system requirements
  - create/manage `backend/venv`
  - install Python dependencies
  - start the FastAPI backend
  - build and launch the macOS app
  - log to `grimoire.log`

`./grimoire help` shows supported subcommands (setup/backend/app/status/stop/reset).

---

## Cleanup Script

- Script: `./cleanup.sh`
- Responsibilities:
  - remove `backend/venv`
  - remove build artifacts (`macos-app/Build`)
  - optionally remove the Xcode project/build output
  - stop backend process and clear pid/log state

Notes:

- It intentionally does **not** delete project notes by default.
- Projects live under `backend/storage/projects/`.

---

## Fast Rebuild Script (Cached)

- Script: `./.rebuild.sh`
- Goal: “cleanup + rebuild” without paying the full dependency download cost each time.

It caches:

- `backend/venv` (Python dependencies)
- `macos-app/Build/SourcePackages` (Swift Package Manager checkouts)

Usage:

- `./.rebuild.sh` — non-interactive cleanup (keeps Xcode project), then runs `./grimoire`
- `./.rebuild.sh --interactive` — run `cleanup.sh` interactively
- `./.rebuild.sh --no-cache` — do not preserve cached artifacts

---

## Logs

- Launcher/backend log: `grimoire.log`
- Backend PID file: `backend.pid`

Backend API docs (when running):

- http://127.0.0.1:8000/docs

---

## Local Models and Caching

ML model weights are cached locally by the underlying libraries (Hugging Face cache).

If network access is restricted, the backend can still run using cached weights.
If weights are missing, the model-dependent subsystems may fall back or be unavailable until the models are present locally.

---

## Manual Build (If Needed)

Backend:

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 main.py
```

macOS app:

```bash
cd macos-app
open Grimoire.xcodeproj
```

