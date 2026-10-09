#!/bin/bash
# Run on macOS after native validation, with a Developer ID identity in Keychain.
set -euo pipefail
BURROW_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BURROW_APP="${1:-$BURROW_ROOT/dist/Burrow Brigade.app}"
: "${BURROW_SIGN_IDENTITY:?Set BURROW_SIGN_IDENTITY to your Developer ID Application identity}"
: "${BURROW_NOTARY_PROFILE:?Set BURROW_NOTARY_PROFILE to an existing notarytool Keychain profile}"
test "$(uname -s)" = Darwin
export BURROW_APP BURROW_ROOT
python3 - <<'PY'
from pathlib import Path
import os, subprocess
app = Path(os.environ['BURROW_APP']).resolve()
identity = os.environ['BURROW_SIGN_IDENTITY']
entitlements = Path(os.environ['BURROW_ROOT']) / 'packaging/macos/entitlements.plist'
for path in sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open('rb') as stream:
        magic = stream.read(4)
    if magic != b'\xcf\xfa\xed\xfe':
        continue
    command = ['codesign', '--force', '--timestamp', '--options', 'runtime', '--sign', identity]
    if path.name == 'ruby':
        command.extend(['--entitlements', str(entitlements)])
    subprocess.run(command + [str(path)], check=True)
subprocess.run(['codesign', '--force', '--timestamp', '--options', 'runtime', '--sign', identity, str(app)], check=True)
PY
codesign --verify --deep --strict --verbose=2 "$BURROW_APP"
BURROW_SUBMISSION="$(mktemp -d)/Burrow-Brigade-submission.zip"
trap 'rm -f "$BURROW_SUBMISSION"; rmdir "$(dirname "$BURROW_SUBMISSION")"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$BURROW_APP" "$BURROW_SUBMISSION"
xcrun notarytool submit "$BURROW_SUBMISSION" --keychain-profile "$BURROW_NOTARY_PROFILE" --wait
xcrun stapler staple "$BURROW_APP"
xcrun stapler validate "$BURROW_APP"
spctl --assess --type execute --verbose=2 "$BURROW_APP"
BURROW_RELEASE="$BURROW_ROOT/dist/Burrow-Brigade-macos-arm64-notarized.zip"
ditto -c -k --sequesterRsrc --keepParent "$BURROW_APP" "$BURROW_RELEASE"
shasum -a 256 "$BURROW_RELEASE" > "$BURROW_RELEASE.sha256"
echo "Created $BURROW_RELEASE"
