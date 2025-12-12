#!/usr/bin/env bash
#
# Fast rebuild helper for Grimoire.
#
# Default behavior:
# - Preserve backend Python virtualenv (so pip installs are skipped)
# - Run cleanup.sh (auto-yes, keep Xcode project)
# - Restore virtualenv
# - Run ./grimoire
#
# Options:
#   --interactive   Run cleanup.sh interactively (no auto-input)
#   --no-cache      Do not preserve/restore venv
#   -h, --help      Show help
#
# Any other args are passed through to ./grimoire.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.rebuild-cache"
VENV_DIR="${SCRIPT_DIR}/backend/venv"
CACHED_VENV="${CACHE_DIR}/venv"

INTERACTIVE=0
NO_CACHE=0
GRIMOIRE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive)
      INTERACTIVE=1
      shift
      ;;
    --no-cache)
      NO_CACHE=1
      shift
      ;;
    -h|--help)
      sed -n '1,60p' "$0"
      exit 0
      ;;
    *)
      GRIMOIRE_ARGS+=("$1")
      shift
      ;;
  esac
done

preserve_venv() {
  if [[ $NO_CACHE -eq 1 ]]; then
    return 0
  fi
  if [[ -d "$VENV_DIR" ]]; then
    mkdir -p "$CACHE_DIR"
    rm -rf "$CACHED_VENV" 2>/dev/null || true
    echo "Preserving Python virtualenv to speed rebuild..."
    mv "$VENV_DIR" "$CACHED_VENV"
  fi
}

restore_venv() {
  if [[ $NO_CACHE -eq 1 ]]; then
    return 0
  fi
  if [[ -d "$CACHED_VENV" ]]; then
    mkdir -p "$(dirname "$VENV_DIR")"
    if [[ ! -d "$VENV_DIR" ]]; then
      echo "Restoring cached Python virtualenv..."
      mv "$CACHED_VENV" "$VENV_DIR"
    fi
  fi
}

RESTORED=0
on_exit() {
  if [[ $RESTORED -eq 0 ]]; then
    restore_venv || true
    RESTORED=1
  fi
}
trap on_exit EXIT INT TERM

preserve_venv

if [[ $INTERACTIVE -eq 1 ]]; then
  bash "${SCRIPT_DIR}/cleanup.sh"
else
  # cleanup.sh prompts twice:
  # 1) continue? [y/N]  -> answer y
  # 2) remove Xcode project? [y/N] -> answer n (keep it)
  printf "y\nn\n" | bash "${SCRIPT_DIR}/cleanup.sh"
fi

restore_venv
RESTORED=1

echo "Running Grimoire..."
bash "${SCRIPT_DIR}/grimoire" "${GRIMOIRE_ARGS[@]}"

