#!/usr/bin/env bash
# Graceful stop for the tmux-hosted Fabric server, used as the systemd unit's
# ExecStop. It sends `stop` to the server console so the world is saved cleanly,
# waits for the JVM to exit, then removes the (now-idle) tmux session.
#
# This replaces a bare `tmux kill-session`, which would hard-kill the JVM without
# saving — risking chunk/world corruption even when no one is online.
#
# Config (environment):
#   MINECRAFT_TMUX_SESSION  tmux session name  (default: minecraft)
#   MINECRAFT_USER          user running the JVM, for pgrep (default: current user)
set -u

SESSION="${MINECRAFT_TMUX_SESSION:-minecraft}"
RUN_USER="${MINECRAFT_USER:-$(id -un)}"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    exit 0
fi

# Ask the server to shut down cleanly (saves the world).
tmux send-keys -t "$SESSION" 'stop' Enter 2>/dev/null || true

# Wait up to ~110s for the JVM to finish saving and exit. Keep this below the
# unit's TimeoutStopSec so systemd doesn't SIGKILL us mid-save.
for _ in $(seq 1 110); do
    if ! pgrep -u "$RUN_USER" -f 'fabric-server' >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Clean up the session if it lingers (or if the JVM had to be given up on).
tmux kill-session -t "$SESSION" 2>/dev/null || true
exit 0
