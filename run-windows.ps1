$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-Location $PSScriptRoot
$env:SCARPE_NATIVE_BIN = Join-Path $PSScriptRoot 'vendor/scarpe/native/target/release/scarpe-native.exe'
$env:PATH = (Join-Path $PSScriptRoot '.cache/windows/audio') + [IO.Path]::PathSeparator + $env:PATH
ruby bin/scarpe --native game.rb @args
