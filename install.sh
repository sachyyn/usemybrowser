#!/bin/bash
# Installs the helium and decide commands, the chrome-devtools CLI they wrap, and the agent skill.
# Safe to run again: a file that already exists and differs from this repo is left alone.
# It never starts the daemon, so Helium shows no "Allow" prompt during install.
#
# Usage: ./install.sh [--force]
#   --force  overwrite existing scripts and SKILL.md. LESSONS.md is your own log and is never overwritten.
set -eu

CDT_VERSION=1.13.0
REPO="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CDT_DIR="$HOME/.local/share/helium-cdt"
SKILL_DIR="$HOME/.agents/skills/helium-browser"

FORCE=0
case "${1:-}" in
  "") ;;
  --force) FORCE=1 ;;
  *) echo "usage: ./install.sh [--force]" >&2; exit 2 ;;
esac

missing=0
need() { echo "missing: $1" >&2; missing=1; }

[ "$(uname -s)" = "Darwin" ] || need "macOS (this tool only supports Helium on macOS)"
command -v zsh >/dev/null 2>&1 || need "zsh (the helium command is a zsh script)"
command -v python3 >/dev/null 2>&1 || need "python3 (used by helium text and decide)"
command -v npm >/dev/null 2>&1 || need "npm"
if ! command -v node >/dev/null 2>&1; then
  need "node 22.12 or newer"
elif ! node -e 'const [a, b] = process.versions.node.split(".").map(Number); process.exit(a > 22 || (a === 22 && b >= 12) ? 0 : 1)'; then
  need "node 22.12 or newer (found $(node -v))"
fi
if [ "$missing" -ne 0 ]; then
  echo "Nothing was installed. Install what is missing and run ./install.sh again." >&2
  exit 1
fi

# Helium can live outside /Applications, so a miss here is a warning and not a stop.
if [ ! -d "/Applications/Helium.app" ] && [ ! -d "$HOME/Applications/Helium.app" ]; then
  echo "warning: Helium.app was not found in /Applications or ~/Applications. Install it from https://helium.computer before the first run."
fi

installed_cdt="$(node -p 'try { require(process.argv[1]).version } catch { "" }' "$CDT_DIR/node_modules/chrome-devtools-mcp/package.json")"
if [ "$installed_cdt" = "$CDT_VERSION" ]; then
  echo "unchanged: chrome-devtools-mcp@$CDT_VERSION in $CDT_DIR"
else
  mkdir -p "$CDT_DIR"
  npm install --prefix "$CDT_DIR" --save-exact --no-fund --no-audit "chrome-devtools-mcp@$CDT_VERSION"
  echo "installed: chrome-devtools-mcp@$CDT_VERSION in $CDT_DIR"
fi

# place <source> <target> <mode> <overwrite with --force: 1 or 0>
place() {
  if [ ! -e "$2" ]; then
    mkdir -p "$(dirname "$2")"
    install -m "$3" "$1" "$2"
    echo "installed: $2"
  elif cmp -s "$1" "$2"; then
    echo "unchanged: $2"
  elif [ "$FORCE" -eq 1 ] && [ "$4" -eq 1 ]; then
    install -m "$3" "$1" "$2"
    echo "overwritten: $2"
  elif [ "$4" -eq 1 ]; then
    echo "skipped: $2 exists and differs from this repo. Run ./install.sh --force to replace it."
  else
    echo "skipped: $2 is your own log and is never overwritten."
  fi
}

place "$REPO/bin/helium" "$BIN_DIR/helium" 755 1
place "$REPO/bin/decide" "$BIN_DIR/decide" 755 1
place "$REPO/skill/SKILL.md" "$SKILL_DIR/SKILL.md" 644 1
place "$REPO/skill/LESSONS.md" "$SKILL_DIR/LESSONS.md" 644 0

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "warning: $BIN_DIR is not on your PATH. Add this line to ~/.zshrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo "Done. Next: fill in the Profiles table in $SKILL_DIR/SKILL.md, then follow \"First run\" in the README."
