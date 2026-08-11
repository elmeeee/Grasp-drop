# Grasp CLI — Windows PowerShell Utility
# Usage:
#   .\grasp-cli.ps1 -Action send -FilePath "C:\path\to\file.zip" -Server "192.168.1.15:7456"
#   .\grasp-cli.ps1 -Action list -Server "192.168.1.15:7456"

param (
    [Parameter(Mandatory=$true)][string]$Action,
    [string]$FilePath,
    [string]$Server = "127.0.0.1:7456"
)

if ($Action -eq "send") {
    if (-not (Test-Path $FilePath)) {
        Write-Host "Error: File '$FilePath' not found!" -ForegroundColor Red
        exit
    }
    Write-Host "Uploading '$FilePath' to Grasp Hub ($Server)..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri "http://$Server/upload" -Method Post -InFile $FilePath
    Write-Host "File Uploaded Successfully!" -ForegroundColor Green
} elseif ($Action -eq "list") {
    Write-Host "Fetching files from Grasp Hub ($Server)..." -ForegroundColor Cyan
    $response = Invoke-RestMethod -Uri "http://$Server/api/files"
    $response | Format-Table -Property name, size, date
} else {
    Write-Host "Unknown Action. Use 'send' or 'list'." -ForegroundColor Yellow
}
