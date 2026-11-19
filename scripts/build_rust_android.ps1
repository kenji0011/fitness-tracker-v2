$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$rustDir = Join-Path $repoRoot "rust\tempo_core"
$jniLibsDir = Join-Path $repoRoot "android\app\src\main\jniLibs"

# Locate Android NDK automatically
$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME }
           elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
           else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }

$ndkParent = Join-Path $sdkRoot "ndk"
if (-not (Test-Path $ndkParent)) {
    throw "Android NDK not found under $ndkParent"
}
$ndkDir = (Get-ChildItem $ndkParent -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$ndkBin = Join-Path $ndkDir "toolchains\llvm\prebuilt\windows-x86_64\bin"

Write-Host "Using Android NDK: $ndkDir"

$targets = @(
    @{ Triple = "aarch64-linux-android"; Abi = "arm64-v8a"; Clang = "aarch64-linux-android26-clang.cmd"; LinkerEnv = "CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER"; CcEnv = "CC_aarch64_linux_android"; ArEnv = "AR_aarch64_linux_android" },
    @{ Triple = "armv7-linux-androideabi"; Abi = "armeabi-v7a"; Clang = "armv7a-linux-androideabi26-clang.cmd"; LinkerEnv = "CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER"; CcEnv = "CC_armv7_linux_androideabi"; ArEnv = "AR_armv7_linux_androideabi" },
    @{ Triple = "x86_64-linux-android"; Abi = "x86_64"; Clang = "x86_64-linux-android26-clang.cmd"; LinkerEnv = "CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER"; CcEnv = "CC_x86_64_linux_android"; ArEnv = "AR_x86_64_linux_android" }
)

Push-Location $rustDir
try {
    foreach ($t in $targets) {
        $clangPath = Join-Path $ndkBin $t.Clang
        $arPath = Join-Path $ndkBin "llvm-ar.exe"
        Set-Item -Path "Env:$($t.CcEnv)" -Value $clangPath
        Set-Item -Path "Env:$($t.ArEnv)" -Value $arPath
        Set-Item -Path "Env:$($t.LinkerEnv)" -Value $clangPath

        Write-Host "Building tempo_core for $($t.Triple) ($($t.Abi))..."
        cargo +stable-x86_64-pc-windows-gnu build --target $t.Triple --release
        if ($LASTEXITCODE -ne 0) { throw "Cargo build failed for $($t.Triple)" }

        $outDir = Join-Path $jniLibsDir $t.Abi
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        $srcSo = Join-Path $rustDir "target\$($t.Triple)\release\libtempo_core.so"
        Copy-Item $srcSo (Join-Path $outDir "libtempo_core.so") -Force
        $sizeKb = [Math]::Round((Get-Item (Join-Path $outDir "libtempo_core.so")).Length / 1KB, 1)
        Write-Host "  -> Bundled $($t.Abi)/libtempo_core.so ($sizeKb KB)"
    }
} finally {
    Pop-Location
}
Write-Host "Done building all Android Rust native libraries!"
