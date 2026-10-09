#!/bin/sh
set -eu
BURROW_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$BURROW_ROOT"
command -v ruby >/dev/null || { echo 'Install Ruby 3.4 or newer.' >&2; exit 1; }
command -v cargo >/dev/null || { echo 'Install Rust with rustup and put cargo on PATH.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Install Python 3.' >&2; exit 1; }
if [ ! -d vendor/scarpe/.git ]; then
  mkdir -p vendor
  git clone https://github.com/scarpe-team/scarpe.git vendor/scarpe
  git -C vendor/scarpe checkout --detach "$(cat SCARPE_REVISION)"
fi
python3 tools/verify_scarpe.py --apply
bundle config set --local path vendor/bundle
bundle install
cargo build --release --locked --manifest-path vendor/scarpe/native/Cargo.toml
echo 'Ready. Launch with ./run.sh; test with bundle exec rake test and ./bin/check-native.'
