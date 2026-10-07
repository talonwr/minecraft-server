#!/usr/bin/env bash
# `minecraft start` — launch straight into the home server, already logged in.
# Uses Prism Launcher (brew install --cask prismlauncher), which can start a
# game and join a server from the command line; the official launcher can't.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Override any of these in your shell profile if the server moves or updates.
MC_SERVER_NAME="${MC_SERVER_NAME:-Home Server}"
MC_SERVER_ADDRESS="${MC_SERVER_ADDRESS:-100.127.91.62}"   # Mac mini on Tailscale
MC_SERVER_VERSION="${MC_SERVER_VERSION:-26.3}"
MC_INSTANCE="${MC_INSTANCE:-home-server}"

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "'minecraft start' is Mac-only for now."
    exit 1
fi

PRISM_APP="/Applications/Prism Launcher.app"
PRISM_BIN="$PRISM_APP/Contents/MacOS/prismlauncher"
PRISM_DIR="$HOME/Library/Application Support/PrismLauncher"
INSTANCE_DIR="$PRISM_DIR/instances/$MC_INSTANCE"

if [[ ! -x "$PRISM_BIN" ]]; then
    echo "Installing Prism Launcher..."
    brew install --cask prismlauncher
fi

# Create the Prism instance the first time (plain Minecraft, matching the server).
if [[ ! -f "$INSTANCE_DIR/instance.cfg" ]]; then
    echo "Creating '$MC_SERVER_NAME' instance (Minecraft $MC_SERVER_VERSION)..."
    mkdir -p "$INSTANCE_DIR/minecraft"
    cat > "$INSTANCE_DIR/instance.cfg" <<EOF
InstanceType=OneSix
name=$MC_SERVER_NAME
iconKey=grass
EOF
    cat > "$INSTANCE_DIR/mmc-pack.json" <<EOF
{
    "components": [
        { "important": true, "uid": "net.minecraft", "version": "$MC_SERVER_VERSION" }
    ],
    "formatVersion": 1
}
EOF
fi

# Keep the server in the Multiplayer list of both Prism and the official launcher.
python3 "$SCRIPT_DIR/add-server.py" "$INSTANCE_DIR/minecraft/servers.dat" "$MC_SERVER_NAME" "$MC_SERVER_ADDRESS"
OFFICIAL_DIR="$HOME/Library/Application Support/minecraft"
if [[ -d "$OFFICIAL_DIR" ]]; then
    python3 "$SCRIPT_DIR/add-server.py" "$OFFICIAL_DIR/servers.dat" "$MC_SERVER_NAME" "$MC_SERVER_ADDRESS"
fi

# Prism needs a Microsoft account added once; until then, open it so you can sign in.
if ! grep -q '"type": *"MSA"' "$PRISM_DIR/accounts.json" 2>/dev/null; then
    echo ""
    echo "One-time step: sign in to Prism Launcher."
    echo "  In the window that opens, click Accounts (top right) > Manage Accounts >"
    echo "  Add Microsoft, and sign in. Then close Prism and run 'minecraft start' again."
    open "$PRISM_APP"
    exit 0
fi

echo "Launching Minecraft $MC_SERVER_VERSION and joining $MC_SERVER_NAME ($MC_SERVER_ADDRESS)..."
open -a "$PRISM_APP" --args --launch "$MC_INSTANCE" --server "$MC_SERVER_ADDRESS"
