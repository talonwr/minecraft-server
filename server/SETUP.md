# Raspberry Pi Setup — Auto-Updating Server

One-time setup so that merging a PR to `main` automatically updates the server. The flow: GitHub fires a webhook on merge → Cloudflare Tunnel delivers it to the Pi → the updater syncs the new mods → the server restarts as soon as nobody is online.

## 1. Prerequisites on the Pi

- Java 21+, Git, and Git LFS installed (`sudo apt install git git-lfs`, then `git lfs install`)
- This repo cloned (e.g. `/home/pi/minecraft-server`)
- A working Fabric server folder (e.g. `/home/pi/minecraft-fabric`)

## 2. Enable RCON

The updater uses RCON to see who's online and to restart the server gracefully. In your server folder's `server.properties`:

```properties
enable-rcon=true
rcon.port=25575
rcon.password=pick-something-long-and-random
```

RCON stays local to the Pi — don't port-forward 25575.

## 3. Run the server under systemd

Edit the paths and user in `server/systemd/minecraft-server.service` to match your Pi, then:

```bash
sudo cp server/systemd/minecraft-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now minecraft-server
```

The service runs `launcher/server-start.sh`, which pulls the latest mods on every boot. `Restart=always` is what lets the updater bounce the server by simply telling it to stop.

## 4. Run the webhook updater

Create a webhook secret and install the service (edit paths/user in the unit file first):

```bash
openssl rand -hex 32 > /home/pi/.mc-webhook-secret
chmod 600 /home/pi/.mc-webhook-secret
sudo cp server/systemd/mc-updater.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mc-updater
```

It listens on `127.0.0.1:9000` — only the tunnel can reach it.

## 5. Cloudflare Tunnel

On the Pi:

```bash
cloudflared tunnel login
cloudflared tunnel create mc-webhook
cloudflared tunnel route dns mc-webhook mc-webhook.yourdomain.com
```

Then create `~/.cloudflared/config.yml`:

```yaml
tunnel: mc-webhook
credentials-file: /home/pi/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: mc-webhook.yourdomain.com
    service: http://localhost:9000
  - service: http_status:404
```

And run it as a service:

```bash
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

## 6. Point GitHub at it

In the repo: **Settings → Webhooks → Add webhook**

- **Payload URL:** `https://mc-webhook.yourdomain.com/webhook`
- **Content type:** `application/json`
- **Secret:** the contents of `/home/pi/.mc-webhook-secret`
- **Events:** just the push event

GitHub sends a ping immediately — a green check next to the webhook means the whole chain works.

## How updates behave

When a PR merges, the Pi syncs the new mods within seconds. If the server is empty it restarts right away; if people are playing, it waits and checks every 30 seconds, restarting the moment the last player logs off (with a `say` announcement first). If the server happens to be offline, the new mods simply load on its next start.

## Troubleshooting

```bash
journalctl -u mc-updater -f        # watch the updater react to a merge
journalctl -u minecraft-server -f  # watch the server itself
```

Redeliver a webhook from GitHub's webhook page (Recent Deliveries → Redeliver) to test without merging anything.
