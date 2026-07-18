#!/usr/bin/env python3
"""GitHub webhook listener for the Raspberry Pi.

Listens for push events on main (delivered via Cloudflare Tunnel), syncs the
latest mods from the repo to the server folder, then restarts the Minecraft
server — but only once nobody is online, so a merge never kicks players.

The restart works by sending `stop` over RCON; the minecraft-server systemd
unit (Restart=always) brings the server back up with the new mods.

Configuration (environment variables, see systemd/mc-updater.service):
  WEBHOOK_SECRET_FILE   file containing the GitHub webhook secret (required)
  REPO_DIR              path to this repo on the Pi (default: this file's repo)
  MINECRAFT_SERVER_DIR  Fabric server folder (default: ~/minecraft-server)
  UPDATER_PORT          port to listen on (default: 9000)
  EMPTY_POLL_SECONDS    how often to check for an empty server (default: 30)

Requires enable-rcon=true and rcon.password in server.properties; RCON
settings are read from there automatically. Python 3 stdlib only.
"""

import hashlib
import hmac
import json
import os
import socket
import struct
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

REPO_DIR = Path(os.environ.get("REPO_DIR", Path(__file__).resolve().parents[1]))
SERVER_DIR = Path(os.environ.get("MINECRAFT_SERVER_DIR", Path.home() / "minecraft-server"))
PORT = int(os.environ.get("UPDATER_PORT", "9000"))
POLL_SECONDS = int(os.environ.get("EMPTY_POLL_SECONDS", "30"))

restart_wanted = threading.Event()


def log(msg):
    print(msg, flush=True)


def load_secret():
    secret_file = os.environ.get("WEBHOOK_SECRET_FILE")
    if not secret_file:
        sys.exit("WEBHOOK_SECRET_FILE is not set — refusing to run without signature checks.")
    return Path(secret_file).read_text().strip().encode()


SECRET = load_secret()


def read_rcon_config():
    """Pull RCON port/password from server.properties."""
    props = {}
    for line in (SERVER_DIR / "server.properties").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            key, _, value = line.partition("=")
            props[key.strip()] = value.strip()
    if props.get("enable-rcon") != "true" or not props.get("rcon.password"):
        raise RuntimeError("RCON is not enabled in server.properties")
    return int(props.get("rcon.port", "25575")), props["rcon.password"]


class Rcon:
    """Minimal RCON client (login, one command, close)."""

    LOGIN, COMMAND = 3, 2

    def __init__(self, port, password):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=10)
        if self._send(self.LOGIN, password)[0] == -1:
            raise RuntimeError("RCON authentication failed")

    def _send(self, kind, payload):
        body = struct.pack("<ii", 1, kind) + payload.encode() + b"\x00\x00"
        self.sock.sendall(struct.pack("<i", len(body)) + body)
        (length,) = struct.unpack("<i", self._recv(4))
        data = self._recv(length)
        req_id, _ = struct.unpack("<ii", data[:8])
        return req_id, data[8:-2].decode(errors="replace")

    def _recv(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("RCON connection closed")
            buf += chunk
        return buf

    def command(self, text):
        return self._send(self.COMMAND, text)[1]

    def close(self):
        self.sock.close()


def players_online():
    """Return the online player count, or None if the server isn't reachable."""
    try:
        rcon_port, rcon_password = read_rcon_config()
        rcon = Rcon(rcon_port, rcon_password)
    except (OSError, RuntimeError) as err:
        log(f"RCON unavailable ({err}) — assuming server is not running.")
        return None
    reply = ""
    try:
        # Reply looks like: "There are 2 of a max of 20 players online: a, b"
        reply = rcon.command("list")
        return int(reply.split("There are ", 1)[1].split(" ", 1)[0])
    except (OSError, IndexError, ValueError):
        log(f"Could not read player count (reply was {reply!r}).")
        return None
    finally:
        rcon.close()


def sync_repo():
    log("Pulling latest mods from GitHub...")
    subprocess.run(["git", "pull", "--ff-only", "origin", "main"], cwd=REPO_DIR, check=True)
    subprocess.run(["git", "lfs", "pull"], cwd=REPO_DIR, check=True)

    mods_dir = SERVER_DIR / "mods"
    mods_dir.mkdir(parents=True, exist_ok=True)
    for old in mods_dir.glob("*.jar"):
        old.unlink()
    count = 0
    for jar in (REPO_DIR / "mods").glob("*.jar"):
        (mods_dir / jar.name).write_bytes(jar.read_bytes())
        count += 1
    log(f"Synced {count} mod(s) to {mods_dir}")


def restart_when_empty():
    """Background thread: once a restart is wanted, wait for an empty server."""
    while True:
        restart_wanted.wait()
        count = players_online()
        if count is None:
            # Server isn't running; the new mods load whenever it next starts.
            log("Server not running — new mods will load on next start.")
            restart_wanted.clear()
        elif count == 0:
            log("Server is empty — restarting to load new mods.")
            try:
                rcon_port, rcon_password = read_rcon_config()
                rcon = Rcon(rcon_port, rcon_password)
                rcon.command("say Updating mods — back in a minute!")
                rcon.command("stop")
                rcon.close()
                restart_wanted.clear()
            except (OSError, RuntimeError) as err:
                log(f"Restart attempt failed ({err}); will retry.")
        else:
            log(f"{count} player(s) online — waiting to restart.")
        if restart_wanted.is_set():
            time.sleep(POLL_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        signature = self.headers.get("X-Hub-Signature-256", "")
        expected = "sha256=" + hmac.new(SECRET, body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature, expected):
            self.send_error(403, "Bad signature")
            return

        event = self.headers.get("X-GitHub-Event", "")
        if event == "ping":
            self._ok("pong")
            return
        if event != "push":
            self._ok(f"ignoring event: {event}")
            return

        payload = json.loads(body)
        if payload.get("ref") != "refs/heads/main":
            self._ok(f"ignoring ref: {payload.get('ref')}")
            return

        self._ok("syncing")
        try:
            sync_repo()
            restart_wanted.set()
            log("Update queued — server restarts when empty.")
        except subprocess.CalledProcessError as err:
            log(f"Sync failed: {err}")

    def _ok(self, message):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(message.encode())

    def log_message(self, fmt, *args):
        log(f"http: {fmt % args}")


def main():
    threading.Thread(target=restart_when_empty, daemon=True).start()
    log(f"Webhook listener on port {PORT}; repo={REPO_DIR} server={SERVER_DIR}")
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
