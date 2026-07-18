#!/usr/bin/env bash
# One-time setup — gives you the `minecraft` command in your terminal.
# Run once after cloning: ./launcher/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH="$SCRIPT_DIR/launch.sh"
ALIAS_LINE="alias minecraft=\"$LAUNCH\""

case "$(basename "${SHELL:-/bin/bash}")" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) RC="$HOME/.bashrc" ;;
    *)    RC="$HOME/.profile" ;;
esac

if [[ -f "$RC" ]] && grep -qF 'alias minecraft=' "$RC"; then
    echo "A 'minecraft' alias already exists in $RC — updating it."
    tmp="$(mktemp)"
    grep -vF 'alias minecraft=' "$RC" > "$tmp"
    mv "$tmp" "$RC"
fi

{
    echo ""
    echo "# Minecraft mod sync + launch (added by minecraft-server/launcher/install.sh)"
    echo "$ALIAS_LINE"
} >> "$RC"

chmod +x "$LAUNCH" "$SCRIPT_DIR/server-start.sh" 2>/dev/null || true

echo "Done! Added the 'minecraft' command to $RC."
echo "Open a new terminal (or run: source $RC) and type 'minecraft' to play."
