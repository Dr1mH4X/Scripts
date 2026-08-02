# ==========================================
#   Custom RclickContentMenu (PWSh)
#   Switch between Win10 legacy / Win11 new
#   context menu, then restart explorer.
# ==========================================

# Require admin (self-elevate)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
    Start-Process pwsh -Verb RunAs -ArgumentList "-NoExit -File `"$PSCommandPath`""
    exit
}

Write-Host "============================================="
Write-Host "Custom RclickContentMenu"
Write-Host "1 (Win10 legacy)"
Write-Host "2 (Win11 new design)"
Write-Host "============================================="

$opt = Read-Host "choose"
switch ($opt) {
    "1" {
        Write-Host "change to Win10 legacy 》》》》》》》》》" -ForegroundColor Cyan
        reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve
    }
    "2" {
        Write-Host "change to Win11 new design 》》》》》》》》》" -ForegroundColor Cyan
        reg delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f
    }
    default {
        Write-Host "Invalid choice, exiting." -ForegroundColor Red
        exit
    }
}

Write-Host "*************************************"
Write-Host "*                                   *"
Write-Host "*         restart  explorer..        *"
Write-Host "*                                   *"
Write-Host "*************************************"
Stop-Process -Name explorer -Force
Start-Process explorer.exe

Read-Host "Press Enter to exit..."
