#!/usr/bin/env bash
# Shared helpers for the launcher scripts. Source this file, don't run it.

# Fail early if Git LFS isn't installed — without it, git pull downloads tiny
# placeholder text files instead of the real mod jars.
require_git_lfs() {
    if ! git lfs version >/dev/null 2>&1; then
        echo "Error: Git LFS is not installed."
        echo "Install it from https://git-lfs.com/ then run: git lfs install"
        exit 1
    fi
}

# Pull the latest commit and the real mod files behind it.
pull_latest() {
    local repo_dir="$1"
    cd "$repo_dir"
    git pull --ff-only origin main
    git lfs pull
}

# Detect LFS pointer files masquerading as jars (happens when someone cloned
# before installing Git LFS). Bail out rather than install broken mods.
# Scans every env subfolder (mods/common, mods/client, mods/server).
verify_real_jars() {
    local repo_dir="$1"
    local jar
    for jar in "$repo_dir/mods/"*/*.jar; do
        [[ -f "$jar" ]] || continue
        if head -c 12 "$jar" | grep -q "version http"; then
            echo "Error: '$jar' is a Git LFS placeholder, not a real mod."
            echo "Run 'git lfs install' then 'git lfs pull' in the repo and try again."
            exit 1
        fi
    done
}

# Mirror the given repo mod env-folders into <target_dir>/mods.
# Usage: sync_mods <repo_dir> <target_dir> <env>...   e.g. sync_mods "$REPO" "$MC" common client
# Mods live under mods/<env>/ (common = both sides, client = client-only, server = server-only).
sync_mods() {
    local repo_dir="$1" target_dir="$2"; shift 2
    local envs=("$@") sub jar count=0
    mkdir -p "$target_dir/mods"
    rm -f "$target_dir/mods/"*.jar 2>/dev/null || true
    for sub in "${envs[@]}"; do
        for jar in "$repo_dir/mods/$sub/"*.jar; do
            [[ -f "$jar" ]] || continue
            cp "$jar" "$target_dir/mods/"
            count=$((count + 1))
        done
    done
    echo "  Installed $count mod(s) from: ${envs[*]}"
}

sync_resourcepacks() {
    local repo_dir="$1" target_dir="$2"
    mkdir -p "$target_dir/resourcepacks"
    rm -f "$target_dir/resourcepacks/"*.zip 2>/dev/null || true
    if ls "$repo_dir/resourcepacks/"*.zip 1>/dev/null 2>&1; then
        cp "$repo_dir/resourcepacks/"*.zip "$target_dir/resourcepacks/"
        echo "  Installed $(ls "$repo_dir/resourcepacks/"*.zip 2>/dev/null | wc -l | tr -d ' ') resourcepack(s)"
    else
        echo "  No resourcepacks to sync"
    fi
}
