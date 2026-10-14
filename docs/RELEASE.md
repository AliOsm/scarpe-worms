# GitHub Releases

A `v<version>` tag creates a GitHub Release containing the macOS, Windows and
Linux clients, two loadable server Docker images, checksums and release notes.
The tag must match `Burrow::VERSION` at the tagged commit. The release stays
unpublished until every platform has passed its required functional checks and
GitHub has received and verified every asset.

## Cut a release

1. Integrate the platform packaging workflows and run the checks in
   [CONTRIBUTING.md](../CONTRIBUTING.md). Update `Burrow::VERSION`, user docs and,
   optionally, `docs/releases/<version>.md` with the changes players should know.
   Preserve protocol/save compatibility or document its migration. Commit and
   merge the version change.
2. Tag that commit and push the tag over SSH. For example, after changing the
   source version to `0.5.6`:

   ```sh
   git tag -a v0.5.6 -m 'Burrow Brigade 0.5.6'
   git push origin v0.5.6
   ```

3. Watch **GitHub Release** in Actions. Its successful publication is the download
   link to share: <https://github.com/AliOsm/scarpe-worms/releases>.
   **Deploy server** runs separately on the same tag: it tests and pushes the
   multi-architecture GHCR image, then deploys through the existing `production`
   environment. See [Hosting](HOSTING.md) for that independent deployment.

Do not move a release tag to different source. Cut another version instead.
Use an SSH Git remote for workflow commits; an HTTPS token may lack `workflow`
scope. The Actions `GITHUB_TOKEN` needs `contents: write` only in the final
release job. Package jobs need read access; this release workflow does not use
production SSH secrets or push images to GHCR.

## What runs

`.github/workflows/release.yml` resolves an existing tag to an immutable commit,
validates the version, and passes that commit through the common `ref` input to:

- `package-macos.yml`: build Ruby 4.0.7 and the native renderer on Apple silicon,
  verify archive contents, then run the relocated package on a separate
  `macos-15` runner. Required checks cover ad-hoc signatures, the menu, a bot match,
  movement, focus/charge handling, resize, clean shutdown, diagnostics and
  recovery of the same saved match and player. The install/data paths include
  Unicode and spaces, including a windowed launch with the C locale.
- `package-windows.yml` and `package-linux.yml`: build and verify the packaged
  clients on their platform runners. Their platform guides describe installer,
  portable runtime and native smoke coverage.
- Two server jobs: build the same Dockerfile on `ubuntu-24.04` (amd64) and
  `ubuntu-24.04-arm` (arm64), export with `docker save | gzip -n`, remove and
  reload the image from that archive, then play a six-team TLS match and verify
  health checks plus restart recovery of the room, projectile, session and
  certificate. ARM server checks run natively, without QEMU.

Mac deadline and sustained-rendering benchmarks remain visible in the run
summary and `macos-execution-evidence` artifact. They are informational because
shared VM timing is noisy. Required functional checks remain hard failures.
The old `macos-preview.yml` is retired, so a tag builds the Mac package once.

Each client workflow accepts `workflow_call` with `ref`, supports manual runs,
and checks packaging changes in pull requests without publishing. Its final
artifact is `burrow-brigade-macos`, `burrow-brigade-windows` or
`burrow-brigade-linux`, containing only distributables and `.sha256` sidecars.
Diagnostic artifacts have separate names and do not become release downloads.

## Download contents

For version `<v>`:

| Download | Purpose |
| --- | --- |
| `Burrow-Brigade-<v>-macos-arm64.zip` | Apple silicon app, macOS 13+ |
| `Burrow-Brigade-<v>-windows-x64-setup.exe` | Windows x64 installer |
| `Burrow-Brigade-<v>-windows-x64.zip` | Windows portable app |
| `Burrow-Brigade-<v>-linux-x86_64.tar.gz` and/or `.AppImage` | Linux portable client; see its platform guide |
| `Burrow-Brigade-server-<v>-docker-linux-amd64.tar.gz` | Docker-loadable x86-64 server image |
| `Burrow-Brigade-server-<v>-docker-linux-arm64.tar.gz` | Docker-loadable ARM64 server image |
| `compose.yaml` | Persistent host with the versioned image as its default |
| `release.json` | Source commit, version, protocol, workflow run, package sizes and hashes |
| `SHA256SUMS` | SHA-256 manifest for all packages, Compose and provenance |

Every row's file also has a `.sha256` sidecar, including `SHA256SUMS` itself.
The assembler rejects absent platforms, unexpected files, wrong versions,
symlinks, missing sidecars and mismatched hashes. Linux must supply at least one
of its two supported formats. Notes include a download table, first-launch
instructions, Docker/Compose commands, the certificate fingerprint requirement
and changes from `docs/releases/<v>.md`, or a Git log since the previous
reachable release tag if that file is absent.

The server archives are independent builds from the tagged source and a
digest-pinned multi-architecture Ruby base, labeled with
its revision and loaded under `ghcr.io/aliosm/burrow-brigade:<v>`. They do not wait
for `deploy-server.yml` to push that name and do not assume a registry digest is
identical to the separately built archives. The pipeline deliberately uses
explicit version tags rather than updating `latest`: rerunning an old release
must not silently roll a host back. Application and Ruby notices are in the
image; Debian and gem notices remain with their respective packages.

## Verify downloads

Download an asset and its sidecar into the same directory:

```sh
sha256sum -c Burrow-Brigade-0.5.6-linux-x86_64.tar.gz.sha256
# macOS equivalent:
shasum -a 256 -c Burrow-Brigade-0.5.6-macos-arm64.zip.sha256
# With every payload downloaded:
sha256sum -c SHA256SUMS
```

On Windows, use PowerShell and compare the result with the sidecar:

```powershell
Get-FileHash .\Burrow-Brigade-0.5.6-windows-x64-setup.exe -Algorithm SHA256
```

Checksums detect damaged/substituted downloads; they are not developer signatures.

## Rerun or prepare a draft

Use **Actions → GitHub Release → Run workflow**, select a revision containing
all release workflows, enter the existing tag, and choose **draft** (the safe
manual default). From the CLI:

```sh
gh workflow run release.yml --ref main -f tag=v0.5.6 -F draft=true
```

Once the workflows are on `main`, this also works for older tags that contain
the required packaging helpers. Selecting an older source tag does not create
or move that tag and does not deploy the production server.

All package jobs must succeed before the release job runs. Local assets are
fully validated before a draft is created or changed. A rerun replaces assets
with the same names and removes obsolete assets while the release is a draft;
an existing public release is temporarily returned to draft before replacement.
GitHub's uploaded sizes, state and SHA-256 digests are verified (with a download
fallback when digests are absent), and the remote tag is rechecked immediately
before publication. Only then does `draft=false` publish the complete release.
If upload/verification fails, a recoverable partial draft may remain. Rerun the
workflow to repair it. A failed build never publishes a release. Repositories
using immutable GitHub Releases should cut a new version rather than replace
published assets.

For pipeline development, manually dispatch an existing
`test-rel-<version>-<name>` tag with `draft=true`. The helper rejects publishing
test tags and validates their embedded version. Test tags do not trigger the
production deploy workflow. Delete test drafts and tags when finished. There
are no permanent branch/test-tag push triggers or artifact stubs in the final
pipeline. The release helper's safety tests run with
`python3 -I tools/test_release.py`.

## Acceptance beyond CI

These are unsigned/unnotarized preview downloads, not certification for sale.
macOS has an ad-hoc signature; Windows may show SmartScreen warnings. Read the
platform guides before first launch. A physical Mac/Windows/Linux playtest is
still needed for display density, audio devices, focus, sleep/wake, input feel,
balance, and real internet sessions with two through six humans. Automated
loopback checks do not establish every network or device condition.

Developer ID signing, hardened-runtime validation, notarization, stapling and
clean-machine Gatekeeper acceptance require the credentials and workflow in
[macOS packaging](MACOS.md). A commercial launch also needs support, licensing
review, pricing/refunds and update delivery. No store or automatic updater is
part of this release pipeline. CI evidence and its limits are recorded in
[release validation](validation/release-pipeline.json).
