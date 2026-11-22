<#
.SYNOPSIS
Compresses Tempo's offline exercise MP4 assets using ffmpeg to dramatically reduce
Tempo.apk size while preserving crisp 720p playback and any audio tracks.
#>
param(
    [int]$Crf = 28,
    [int]$MaxWidth = 720,
    [int]$ThrottleLimit = 4
)

$ErrorActionPreference = 'Stop'

$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
$ffmpegPath = if ($ffmpegCmd) {
    $ffmpegCmd.Source
} elseif (Test-Path "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe") {
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe"
} else {
    throw "ffmpeg not found in PATH or WinGet Links."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$dirs = @(
    (Join-Path $repoRoot 'assets\Fitness_Journey'),
    (Join-Path $repoRoot 'assets\videos')
)

$files = foreach ($d in $dirs) {
    if (Test-Path $d) {
        Get-ChildItem -Path $d -Filter '*.tmp.mp4' -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $d -Filter '*.mp4' -Recurse -File
    }
}

if (-not $files -or $files.Count -eq 0) {
    Write-Host "No MP4 files found."
    exit 0
}

$beforeBytes = ($files | Measure-Object -Property Length -Sum).Sum
Write-Host ("Found {0} MP4 files totaling {1:N2} MB. Compressing (CRF={2}, MaxWidth={3}, Threads={4})..." -f $files.Count, ($beforeBytes / 1MB), $Crf, $MaxWidth, $ThrottleLimit)

$results = $files | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $ErrorActionPreference = 'Continue'
    $src = $_.FullName
    $origSize = $_.Length
    $tmp = "$src.tmp.mp4"
    $ffmpeg = $using:ffmpegPath
    $crfVal = $using:Crf
    $maxW = $using:MaxWidth

    try {
        if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force }
        & $ffmpeg -y -v error -i $src `
            -c:v libx264 -preset medium -crf $crfVal -threads 2 `
            -vf "scale='min($maxW,iw)':-2" -pix_fmt yuv420p `
            -c:a aac -b:a 64k -ac 1 `
            -movflags +faststart $tmp 2>$null

        if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
            $newSize = (Get-Item -LiteralPath $tmp).Length
            if ($newSize -gt 1024 -and $newSize -lt $origSize) {
                Move-Item -LiteralPath $tmp -Destination $src -Force
                [PSCustomObject]@{ File = $_.Name; Before = $origSize; After = $newSize; Status = 'Compressed' }
            } else {
                Remove-Item -LiteralPath $tmp -Force
                [PSCustomObject]@{ File = $_.Name; Before = $origSize; After = $origSize; Status = 'KeptOriginal' }
            }
        } else {
            if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force }
            [PSCustomObject]@{ File = $_.Name; Before = $origSize; After = $origSize; Status = 'Failed' }
        }
    } catch {
        if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force }
        [PSCustomObject]@{ File = $_.Name; Before = $origSize; After = $origSize; Status = "Error: $_" }
    }
}

$afterBytes = ($results | Measure-Object -Property After -Sum).Sum
$compressedCount = ($results | Where-Object { $_.Status -eq 'Compressed' }).Count
$keptCount = ($results | Where-Object { $_.Status -eq 'KeptOriginal' }).Count
$failedCount = ($results | Where-Object { $_.Status -like 'Failed*' -or $_.Status -like 'Error*' }).Count

Write-Host ("Done! Compressed {0}/{1} videos (kept original: {2}, failed: {3})." -f $compressedCount, $files.Count, $keptCount, $failedCount)
Write-Host ("Total size: {0:N2} MB -> {1:N2} MB (saved {2:N2} MB / {3:N1}%)" -f ($beforeBytes / 1MB), ($afterBytes / 1MB), (($beforeBytes - $afterBytes) / 1MB), ((1 - ($afterBytes / $beforeBytes)) * 100))
exit 0
