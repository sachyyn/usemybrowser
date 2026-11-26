#!/bin/bash
# Installs umb (and decide), the chrome-devtools CLI they wrap, and the agent skill.
# Safe to run again: a file that already exists and differs from this repo is left alone.
# It never starts the daemon, so the browser shows no "Allow" prompt during install.
# It never touches ~/.config/umb, where learned site notes live.
#
# Usage: ./install.sh [--force]
#   --force  overwrite installed files that differ from this repo, and replace an old v1 `helium` command.
set -eu

CDT_VERSION=1.13.0
REPO="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CDT_DIR="$HOME/.local/share/helium-cdt"
APP_DIR="$HOME/.local/share/usemybrowser"
SKILL_DIR="$HOME/.agents/skills/usemybrowser"

FORCE=0
case "${1:-}" in
  "") ;;
  --force) FORCE=1 ;;
  *) echo "usage: ./install.sh [--force]" >&2; exit 2 ;;
esac

missing=0
need() { echo "missing: $1" >&2; missing=1; }

[ "$(uname -s)" = "Darwin" ] || need "macOS (umb only supports macOS)"
command -v zsh >/dev/null 2>&1 || need "zsh (umb is a zsh script)"
command -v python3 >/dev/null 2>&1 || need "python3"
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

found_browser=0
for app in Helium "Google Chrome"; do
  [ -d "/Applications/$app.app" ] || [ -d "$HOME/Applications/$app.app" ] && found_browser=1
done
[ "$found_browser" -eq 1 ] || echo "warning: no Helium.app or Google Chrome.app found in /Applications or ~/Applications. umb is tested on Helium (https://helium.computer)."

installed_cdt="$(node -p 'try { require(process.argv[1]).version } catch { "" }' "$CDT_DIR/node_modules/chrome-devtools-mcp/package.json")"
if [ "$installed_cdt" = "$CDT_VERSION" ]; then
  echo "unchanged: chrome-devtools-mcp@$CDT_VERSION in $CDT_DIR"
else
  mkdir -p "$CDT_DIR"
  npm install --prefix "$CDT_DIR" --save-exact --no-fund --no-audit "chrome-devtools-mcp@$CDT_VERSION"
  echo "installed: chrome-devtools-mcp@$CDT_VERSION in $CDT_DIR"
fi

# place <source> <target>: copy a file, keeping its mode; an edited copy survives unless --force.
place() {
  if [ ! -e "$2" ]; then
    mkdir -p "$(dirname "$2")"
    cp -p "$1" "$2"
    echo "installed: $2"
  elif cmp -s "$1" "$2"; then
    :
  elif [ "$FORCE" -eq 1 ]; then
    cp -p "$1" "$2"
    echo "overwritten: $2"
  else
    echo "skipped: $2 differs from this repo. Run ./install.sh --force to replace it."
  fi
}

# bin/umb finds lib/, vendor/, recipes/ and notes/ next to its own real path.
for dir in bin lib vendor recipes notes; do
  (cd "$REPO" && find "$dir" -type f ! -name .DS_Store) | while IFS= read -r f; do
    place "$REPO/$f" "$APP_DIR/$f"
  done
done
place "$REPO/skill/SKILL.md" "$SKILL_DIR/SKILL.md"

# link <name> <target>: a symlink in ~/.local/bin; anything else already there is kept unless --force.
link() {
  local path="$BIN_DIR/$1"
  mkdir -p "$BIN_DIR"
  if [ -L "$path" ] && [ "$(readlink "$path")" = "$2" ]; then
    return
  elif [ ! -e "$path" ] && [ ! -L "$path" ]; then
    ln -s "$2" "$path"; echo "linked: $path -> $2"
  elif [ "$FORCE" -eq 1 ]; then
    ln -sfn "$2" "$path"; echo "replaced: $path -> $2"
  else
    echo "skipped: $path already exists and is not this install."
    [ "$1" = helium ] && echo "  It looks like the v1 helium command. umb is installed; use umb, or run ./install.sh --force to point helium at umb too."
    return 0
  fi
}
link umb "$APP_DIR/bin/umb"
link helium "$APP_DIR/bin/umb"
link decide "$APP_DIR/bin/decide"

[ -d "$HOME/.agents/skills/helium-browser" ] && echo "note: the v1 skill in ~/.agents/skills/helium-browser was left alone. Delete it when you no longer use helium, so agents read only the v2 skill."

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "warning: $BIN_DIR is not on your PATH. Add this line to ~/.zshrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo "Done. Next: fill in the Profiles table in $SKILL_DIR/SKILL.md, then follow \"First run\" in the README."
