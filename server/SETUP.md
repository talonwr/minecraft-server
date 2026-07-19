# Raspberry Pi Setup — Auto-Updating Server

One-time setup so the server keeps itself in sync with this repo. The flow:

```
mc-updater.timer (every ~3 min)
  └─ poll-updater.sh: git fetch → new commit on the tracked branch?
       └─ server's mods (common + server) changed?
            └─ sync into the server folder, flag a restart
                 └─ once the server is empty: `systemctl restart minecraft`
```

No inbound networking, no webhook, no tunnel — the Pi *pulls*, so this works fine
behind your home router and alongside the playit.gg game tunnel. Updates land
within a few minutes of a merge; if players are online, the restart waits until
the server is empty so no one gets kicked.

> **Mod layout:** the server installs `mods/common/` (both sides) + `mods/server/`
> (server-only, e.g. the Discord bridge). It never installs `mods/client/`
> (shaders, client rendering). Players get `common + client` via the launcher.

## 1. Prerequisites on the Pi

- Java 21+ (already installed)
- Git + Git LFS: `sudo apt update && sudo apt install -y git git-lfs && git lfs install`
- A working Fabric server folder, e.g. `/home/maxmason/minecraft-server`, started
  from a tmux session (session name `minecraft`) via a `tmux-start.sh` in that folder

## 2. Clone this repo (separate from the server folder)

The clone must **not** be the server folder — keep them apart:

```bash
git clone https://github.com/talonwr/minecraft-server.git /home/maxmason/minecraft-repo
cd /home/maxmason/minecraft-repo
git lfs pull
chmod +x server/poll-updater.sh server/tmux-graceful-stop.sh
```

## 3. Graceful restarts (recommended)

The updater restarts the server with `systemctl restart minecraft`. Point the unit
at the graceful stop script so a restart *saves the world* instead of hard-killing
the JVM. Back up your current unit, then install the one from this repo (it keeps
your `tmux-start.sh` as ExecStart and only changes ExecStop):

```bash
sudo cp /etc/systemd/system/minecraft.service ~/minecraft.service.bak
sudo cp server/systemd/minecraft.service /etc/systemd/system/
sudo systemctl daemon-reload
```

For reference, `tmux-start.sh` (in the server folder) looks roughly like:

```bash
#!/usr/bin/env bash
cd /home/maxmason/minecraft-server
exec tmux new-session -d -s minecraft \
  'java -Xms512M -Xmx6G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
   -jar fabric-server-mc.1.21.11-loader.0.18.4-launcher.1.1.1.jar nogui'
```

## 4. Let the updater restart the server without a password

```bash
sudo install -m 0440 server/sudoers.d/mc-updater /etc/sudoers.d/mc-updater
sudo visudo -cf /etc/sudoers.d/mc-updater   # should print "parsed OK"
```

This grants `maxmason` exactly one thing: `systemctl restart minecraft`.

## 5. Install and start the updater timer

```bash
sudo cp server/systemd/mc-updater.service server/systemd/mc-updater.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mc-updater.timer
```

Run it once by hand to confirm the first sync is clean:

```bash
sudo systemctl start mc-updater.service
journalctl -u mc-updater --no-pager -n 30
```

On a correctly-set-up server the first run logs *"Update didn't touch the server's
mods"* (or syncs an identical set) and does **not** restart — because the repo's
`common + server` set matches what's already installed.

## Everyday use

Merge a PR that adds/removes a jar in `mods/common/` or `mods/server/` → within a
few minutes the Pi syncs it and restarts once empty. Changes to `mods/client/`,
resourcepacks, or docs don't restart the server (they don't affect it).

## Testing against a branch before merging

To trial a change before it hits `main`, point the updater at the branch:

```bash
cd /home/maxmason/minecraft-repo && git checkout <branch>
sudo systemctl edit mc-updater.service   # set Environment=MINECRAFT_BRANCH=<branch>
sudo systemctl daemon-reload
```

Switch `MINECRAFT_BRANCH` back to `main` (and `git checkout main`) once merged.

## Troubleshooting

```bash
systemctl status mc-updater.timer          # next scheduled run
journalctl -u mc-updater -f                # watch each poll
tmux attach -t minecraft                   # the live server console (Ctrl-b d to detach)
```

To force a check right now: `sudo systemctl start mc-updater.service`.
