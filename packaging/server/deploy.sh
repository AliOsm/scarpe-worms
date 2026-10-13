#!/bin/sh
# Runs on the game server: switch the host to a published image, keeping its saves.
# Usage: deploy.sh IMAGE [REGISTRY_USER]   (a registry token is read from stdin)
set -eu
cd "$(dirname "$0")"
image=$1
user=${2:-}
registry=${image%%/*}

registry_logout() { [ -z "$user" ] || docker logout "$registry" > /dev/null 2>&1 || true; }
trap 'rm -f .env.next; registry_logout' EXIT
printf 'BURROW_IMAGE=%s\n' "$image" > .env.next
[ -z "$user" ] || docker login "$registry" --username "$user" --password-stdin > /dev/null
# Pull while the current host keeps running, so a failed pull changes nothing.
docker compose --env-file .env.next pull --quiet
registry_logout
mv .env.next .env

# Compose stops the old container first; it saves on SIGTERM and the new one
# restores rooms, matches and sessions from the burrow-data volume.
docker compose up --detach --wait --wait-timeout 120
docker compose ps
docker compose logs --no-log-prefix burrow | grep -E '^(Burrow Brigade|Fingerprint)' | tail -n 2
docker image prune --all --force --filter label=org.opencontainers.image.title=burrow-brigade > /dev/null
