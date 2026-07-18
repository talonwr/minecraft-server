#!/usr/bin/env bash
# Minecraft Mod Sync & Launch — Mac/Linux
# Pulls the latest mods and resourcepacks from the shared repo, then launches Minecraft.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/sync-lib.sh"

# Detect Minecraft directory
if [[ "$OSTYPE" == "darwin"* ]]; then
    MC_DIR="$HOME/Library/Application Support/minecraft"
elif [[ "$OSTYPE" == "linux"* ]]; then
    MC_DIR="$HOME/.minecraft"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

if [[ ! -d "$MC_DIR" ]]; then
    echo "Error: Minecraft directory not found at $MC_DIR"
    echo "Make sure Minecraft is installed and has been run at least once."
    exit 1
fi

echo "=== Minecraft Mod Sync ==="
echo ""

require_git_lfs

echo "Pulling latest mods and resourcepacks..."
pull_latest "$REPO_DIR"
verify_real_jars "$REPO_DIR"
echo ""

echo "Syncing mods..."
sync_mods "$REPO_DIR" "$MC_DIR"

echo "Syncing resourcepacks..."
sync_resourcepacks "$REPO_DIR" "$MC_DIR"

echo ""
echo "Sync complete!"

# Launch Minecraft (Mac only — Linux users may need to adjust)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Launching Minecraft..."
    open -a "Minecraft"
else
    echo "Sync done. Please launch Minecraft manually."
fi
