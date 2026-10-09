# Hosting Burrow Brigade

## Host from the game

Choose **Play with friends → Host for friends**. The game starts a TLS listener
on port 4388 and opens your lobby. Add computer teams or invite up to five
friends. **Copy invite** includes the room code and server certificate
fingerprint. On a LAN, that address is usually sufficient. For internet play,
replace its LAN address with your public hostname/IP and forward TCP 4388 to
this computer. Closing the desktop host disconnects its guests.

Quick battle and Create a match start a loopback-only local host. Use Host for
friends to make a room reachable from another computer. An unfinished local
match is recovered on the next launch; leave it through the match menu to start
fresh. Local and externally hosted state have separate data directories.
Switching from hosting to Quick battle keeps the public listener running for
friends and opens a separate private match. Return through Host for friends to
use the same hosted identity. Both listeners stop when the desktop app closes.

## Persistent Docker host

```sh
docker compose up -d --build
docker compose logs burrow
```

The image is headless Ruby; it has no desktop or renderer dependency. It runs as
UID 10001 with a read-only application filesystem. The named `burrow-data`
volume holds saves, session hashes, certificates, and completed match logs.
Compose publishes 4388/TCP and restarts the host after failure or reboot.

Clients enter `tls://your-host:4388` and the SHA-256 fingerprint printed in the
log. Compare/share the fingerprint with the host outside the connection being
established. The client verifies it before sending its session token. A valid
public CA certificate works without a pin.

```sh
docker compose ps
docker compose exec burrow ruby bin/healthcheck
docker compose restart burrow
docker compose stop burrow
```

For a custom certificate, mount the certificate and private key read-only and
set the service command to `--cert /certs/fullchain.pem --key /certs/key.pem`.
The game protocol is TLS over TCP, not HTTP/WebSocket; a web-only reverse proxy
needs a TCP stream listener. Keep server and client protocol versions matched.

`python3 tools/check_container.py` builds and checks the same image using an
isolated temporary volume and an ephemeral loopback port. It removes both after
verifying play, health checks, and restart recovery.

## Direct Ruby or systemd

The server needs Ruby 3.4+, `base64` 0.3, and `logger` 1.7. It does not need the
Scarpe checkout, graphics assets, ffi, or ChunkyPNG.

```sh
gem install base64 -v 0.3.0
gem install logger -v 1.7.0
./bin/server --host 0.0.0.0 --port 4388 --data /path/to/private/state
```

For a service, copy the source to `/opt/burrow-brigade` and install
`packaging/burrow-brigade.service`. Adjust its Ruby executable to the installed
Ruby 3.4+ path, then enable it with systemd. StateDirectory creates a private
writable directory; application files remain read-only. SIGTERM and Ctrl-C
save state before shutdown. Two processes cannot share the same save directory.

`--local` deliberately starts unencrypted loopback TCP for development. Public
listeners require TLS. The client permits remote `tcp://` only when the player
explicitly enables Trusted LAN connections in settings.

## Recovery and backups

`server.json` is replaced atomically every two seconds and during clean shutdown.
A crash can lose up to the last checkpoint interval. Keep a backup of the
entire state directory, including `tls/`: changing the certificate invalidates
existing invites, and losing session hashes prevents players reclaiming teams.
Stop the host before making a consistent backup, then start it again. Preserve
file permissions; certificates' private keys and session data are private.

After restart the room, terrain, projectiles, ammo, bot search, turn clocks, and
session identities are restored. A match pauses while every human is offline.
When others remain online, a disconnected player's normal turn timer continues.
The connected human host role migrates automatically. Disconnected sessions
expire after 24 hours; abandoned rooms then disappear.

Corrupted or unsupported saves stop startup with an error, preserving the file.
Restore a backup or move the damaged file aside intentionally. The host does not
silently discard it. Completed match command logs live in `replays/` with unique
match IDs; they are diagnostic logs, not a replay playback feature.

Limits are six teams per room, sixteen rooms, 128 sockets, 24 sockets per IP,
and 2,048 saved sessions. These are defensive limits, not a certified hosting
capacity. The included checks validate one full six-team room. Size a shared
host by measuring it with your expected number of rooms and computer players.
No public matchmaking, NAT relay, or provider-operated lobby is bundled.
