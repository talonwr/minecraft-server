#!/usr/bin/env bash
# Minecraft Server Sync & Start — Raspberry Pi (Linux)
# Pulls the latest mods from the shared repo, syncs them to the server, then starts it.
# Run directly, or as the ExecStart of the minecraft-server systemd service.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/sync-lib.sh"

# --- CONFIGURATION ---
# Set this to your Fabric server directory on the Pi
SERVER_DIR="${MINECRAFT_SERVER_DIR:-$HOME/minecraft-server}"
# RAM allocation
MIN_RAM="${MINECRAFT_MIN_RAM:-1G}"
MAX_RAM="${MINECRAFT_MAX_RAM:-2G}"
# Server jar name
SERVER_JAR="${MINECRAFT_SERVER_JAR:-fabric-server-launch.jar}"
# --- END CONFIGURATION ---

if [[ ! -d "$SERVER_DIR" ]]; then
    echo "Error: Server directory not found at $SERVER_DIR"
    echo "Set MINECRAFT_SERVER_DIR to your Fabric server location."
    exit 1
fi

if [[ ! -f "$SERVER_DIR/$SERVER_JAR" ]]; then
    echo "Error: Server jar not found at $SERVER_DIR/$SERVER_JAR"
    echo "Set MINECRAFT_SERVER_JAR if your jar has a different name."
    exit 1
fi

echo "=== Minecraft Server Sync ==="
echo ""

require_git_lfs

# A transient network outage shouldn't stop the server from booting with the
# mods it already has, so sync failures are non-fatal here.
echo "Pulling latest mods and resourcepacks..."
if pull_latest "$REPO_DIR"; then
    verify_real_jars "$REPO_DIR"
    echo ""
    echo "Syncing mods to server..."
    sync_mods "$REPO_DIR" "$SERVER_DIR"
else
    echo "Warning: could not pull latest mods — starting with the current set."
fi

echo ""
echo "Sync complete! Starting server..."
echo ""

# Start the server
cd "$SERVER_DIR"
exec java -Xms"$MIN_RAM" -Xmx"$MAX_RAM" -jar "$SERVER_JAR" nogui
