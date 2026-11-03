# PowerShell Build Script for Antigravity Orbit (WinUI 3)
param (
    [string]$Configuration = "Release",
    [string]$Platform = "win-x64"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Join-Path $ScriptDir "AntigravityOrbit"
$DistDir = Join-Path $ScriptDir "dist"

Write-Host "=== Building Antigravity Orbit for Windows 11 (WinUI 3) ===" -ForegroundColor Cyan

# Ensure dist directory exists
if (Test-Path $DistDir) { Remove-Item $DistDir -Recurse -Force }
New-Item -ItemType Directory -Path $DistDir | Out-Null

Write-Host "1. Restoring NuGet dependencies..."
dotnet restore "$ProjectDir\AntigravityOrbit.csproj"

Write-Host "2. Publishing self-contained executable ($Platform)..."
dotnet publish "$ProjectDir\AntigravityOrbit.csproj" `
    -c $Configuration `
    -r $Platform `
    --self-contained true `
    /p:PublishSingleFile=true `
    /p:IncludeNativeLibrariesForSelfExtract=true `
    /p:WindowsPackageType=None `
    -o "$DistDir"

# Create portable zip archive
$Version = "1.0.0"
$ZipName = "Antigravity-Orbit-$Version-$Platform.zip"
$ZipPath = Join-Path $DistDir $ZipName

Write-Host "3. Creating portable distribution archive: $ZipPath..."
Compress-Archive -Path "$DistDir\*" -DestinationPath "$ZipPath" -Force

Write-Host "✔ Build complete! Artifacts located in: $DistDir" -ForegroundColor Green

