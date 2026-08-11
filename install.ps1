# Grasp — Windows 1-Line Terminal Installer
# Usage in PowerShell:
#   iwr -useb https://raw.githubusercontent.com/username/Grasp/main/install.ps1 | iex

$ErrorActionPreference = "Stop"
$Version = "1.0.0"
$Url = "https://github.com/elmeeee/Grasp-drop/releases/download/v$Version/grasp-windows-x64.exe"
$InstallDir = "$env:LOCALAPPDATA\Grasp"
$TargetExe = "$InstallDir\grasp.exe"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Installing Grasp for Windows..." -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Host "Downloading executable from GitHub..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $Url -OutFile $TargetExe

# Add to User PATH if not present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", "User")
    Write-Host "Added $InstallDir to User PATH." -ForegroundColor Green
}

Write-Host "--------------------------------------------------" -ForegroundColor Cyan
Write-Host "✓ Grasp installed successfully!" -ForegroundColor Green
Write-Host "  Type 'grasp' in any terminal to start the server." -ForegroundColor White
Write-Host "==================================================" -ForegroundColor Cyan
