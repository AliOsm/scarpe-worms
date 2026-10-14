$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-Location $PSScriptRoot

# Use an x64 Visual Studio developer shell (ilammy/msvc-dev-cmd on CI).
if (!$env:VCToolsInstallDir) { throw 'Run this in an x64 Visual Studio developer PowerShell with the C++ build tools installed.' }
$env:RUSTFLAGS = '-C target-feature=+crt-static'
$env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER = Join-Path $env:VCToolsInstallDir 'bin/Hostx64/x64/link.exe'
if (!(Test-Path 'vendor/scarpe/.git')) {
    New-Item -ItemType Directory -Force 'vendor/scarpe' | Out-Null
    git -C vendor/scarpe init -q
    git -C vendor/scarpe config core.autocrlf false
    git -C vendor/scarpe remote add origin https://github.com/scarpe-team/scarpe.git
    git -C vendor/scarpe fetch --depth 1 origin (Get-Content SCARPE_REVISION).Trim()
    git -C vendor/scarpe checkout -q --detach FETCH_HEAD
}
python -I tools/verify_scarpe.py --apply
bundle config set --local path vendor/bundle
bundle install
cargo build --release --locked --manifest-path vendor/scarpe/native/Cargo.toml
python -I tools/package_windows.py --prepare-audio
Write-Host 'Ready. Run ./run-windows.ps1 to play, or bundle exec rake test.'
