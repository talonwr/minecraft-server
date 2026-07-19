#!/usr/bin/env bash
# Poll-based mod updater for the Raspberry Pi.
#
# Runs once per invocation (driven by mc-updater.timer). Each run it:
#   1. checks the mods repo for a new commit on the tracked branch,
#   2. if the server's mod set (mods/common + mods/server) changed, syncs it
#      into the live server folder and flags that a restart is needed,
#   3. restarts the server the moment it's empty — so an update never kicks
#      players who are mid-game.
#
# It talks to the server through its tmux console (no RCON needed): `list` to
# read who's online, and `systemctl restart` to bounce it (the unit's ExecStop
# saves the world gracefully first). Pure Bash + git + tmux; cheap to run every
# few minutes because the expensive checks only happen when a commit lands.
#
# Config (environment, see systemd/mc-updater.service):
#   REPO_DIR                repo clone on the Pi      (default: ~/minecraft-repo)
#   MINECRAFT_SERVER_DIR    live Fabric server folder (default: ~/minecraft-server)
#   MINECRAFT_BRANCH        branch to track           (default: main)
#   MINECRAFT_TMUX_SESSION  tmux session name         (default: minecraft)
#   MINECRAFT_SERVICE       systemd unit to restart   (default: minecraft)
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/minecraft-repo}"
SERVER_DIR="${MINECRAFT_SERVER_DIR:-$HOME/minecraft-server}"
BRANCH="${MINECRAFT_BRANCH:-main}"
SESSION="${MINECRAFT_TMUX_SESSION:-minecraft}"
SERVICE="${MINECRAFT_SERVICE:-minecraft}"
DRY_RUN="${DRY_RUN:-0}"   # DRY_RUN=1 → report what it would do, change nothing
FLAG="$SERVER_DIR/.mc-restart-pending"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# sha1 + basename for a set of jars, sorted — an order-independent fingerprint
# of a mod folder, so we can tell whether the server's mods actually changed.
sig() {
    local f
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        printf '%s  %s\n' "$(sha1sum "$f" | cut -d' ' -f1)" "$(basename "$f")"
    done | sort
}

server_running() { tmux has-session -t "$SESSION" 2>/dev/null; }

# Online player count via the console `list` command; empty string if unknown
# (server starting up, console not responding, etc.).
players_online() {
    server_running || { echo ""; return 0; }
    tmux send-keys -t "$SESSION" 'list' Enter 2>/dev/null || { echo ""; return 0; }
    sleep 2
    tmux capture-pane -t "$SESSION" -p 2>/dev/null \
        | grep -oE 'There are [0-9]+ of a max' | tail -1 \
        | grep -oE '^[0-9]+|[0-9]+' | head -1 || true
}

# Refuse to install Git LFS pointer files (happens if `git lfs pull` was skipped).
verify_real_jars() {
    local j
    for j in "$REPO_DIR/mods/common/"*.jar "$REPO_DIR/mods/server/"*.jar; do
        [[ -f "$j" ]] || continue
        if head -c 12 "$j" | grep -q "version http"; then
            log "ERROR: $j is a Git LFS pointer, not a real jar — aborting sync."
            exit 1
        fi
    done
}

sync_mods_to_server() {
    mkdir -p "$SERVER_DIR/mods"
    rm -f "$SERVER_DIR/mods/"*.jar
    local d j
    for d in common server; do
        for j in "$REPO_DIR/mods/$d/"*.jar; do
            [[ -f "$j" ]] || continue
            cp "$j" "$SERVER_DIR/mods/"
        done
    done
}

# --- 1. Fetch; pull if the branch moved ------------------------------------
cd "$REPO_DIR"
if ! git fetch --quiet origin "$BRANCH"; then
    log "git fetch failed (offline?) — will try again next tick."
    exit 0
fi

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$BRANCH")" ]]; then
    log "New commit on $BRANCH — pulling."
    git pull --ff-only origin "$BRANCH"
    git lfs pull
fi

# --- 2. Reconcile the live server's mods with the repo ----------------------
# Done every tick (cheap: a handful of sha1s) so it self-heals if the folders
# ever drift, and so the first run after setup is a clean no-op when they match.
verify_real_jars
desired="$(sig "$REPO_DIR/mods/common/"*.jar "$REPO_DIR/mods/server/"*.jar)"
current="$(sig "$SERVER_DIR/mods/"*.jar)"
if [[ "$desired" != "$current" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        log "[dry-run] server mods differ from repo — would sync and restart when empty:"
        diff <(echo "$current") <(echo "$desired") || true
    else
        log "Server mod set differs from repo — syncing to $SERVER_DIR/mods."
        sync_mods_to_server
        : > "$FLAG"
    fi
else
    log "Server mods already match the repo — nothing to sync."
fi

# --- 3. Act on a pending restart (this tick or an earlier one) --------------
if [[ -f "$FLAG" ]]; then
    if ! server_running; then
        log "Restart pending but server is down — new mods load on next start; clearing flag."
        rm -f "$FLAG"
    else
        count="$(players_online || true)"
        if [[ "$count" == "0" ]]; then
            if [[ "$DRY_RUN" == "1" ]]; then
                log "[dry-run] server empty — would restart now."
            else
                log "Server empty — restarting to load new mods."
                sudo systemctl restart "$SERVICE"
                rm -f "$FLAG"
                log "Restart issued."
            fi
        elif [[ -z "$count" ]]; then
            log "Couldn't read player count — will retry next tick."
        else
            log "$count player(s) online — deferring restart until empty."
        fi
    fi
fi

log "Poll complete."
