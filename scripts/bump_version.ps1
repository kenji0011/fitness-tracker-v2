# Increments Tempo's patch version by +0.0.1 and build number by +1
# in both pubspec.yaml and lib/config/app_version.dart.
$ErrorActionPreference = 'Stop'

$pubspecPath = Join-Path $PSScriptRoot "..\pubspec.yaml"
$dartVerPath = Join-Path $PSScriptRoot "..\lib\config\app_version.dart"

$pubspec = Get-Content -Raw $pubspecPath
if ($pubspec -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$') {
  throw "Could not parse version line in pubspec.yaml"
}

$major = [int]$Matches[1]
$minor = [int]$Matches[2]
$patch = [int]$Matches[3] + 1
$build = [int]$Matches[4] + 1

$newVer = "$major.$minor.$patch"
$newFull = "$newVer+$build"

$updatedPubspec = [regex]::Replace(
  $pubspec,
  '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$',
  "version: $newFull"
)
Set-Content -NoNewline -Path $pubspecPath -Value $updatedPubspec

$dartContent = @"
/// Single source of truth for Tempo's displayed release version.
/// Incremented by +0.0.1 on every release build alongside ``pubspec.yaml``.
const String kTempoVersionNumber = '$newVer';
const String kTempoDisplayVersion = 'V`$kTempoVersionNumber - R';
"@
Set-Content -NoNewline -Path $dartVerPath -Value ($dartContent + "`n")

Write-Host "Bumped Tempo version to V$newVer - R ($newFull)"
