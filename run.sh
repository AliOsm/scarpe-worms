#!/bin/sh
set -eu
BURROW_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$BURROW_ROOT/bin/scarpe" --native "$BURROW_ROOT/game.rb" "$@"
