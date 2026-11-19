#
#  Copyright (C) 2026 Sergio Melas
#
#  This file is part of WayPlank (GPLv3).
#  Windows FAT Environment Profile & Fault-Tolerance Tester (mirrors Freedesktop Test environments.sh).
#
$ConfigDir = Join-Path $env:LOCALAPPDATA "wayplank"
$BackupDir = Join-Path $env:LOCALAPPDATA "wayplank_fat_backup"

Write-Host "=== WayPlank Windows Environment & Fault-Tolerance Tester ===" -ForegroundColor Cyan
Write-Host "Target config dir: $ConfigDir"
Write-Host "  1) Backup current profile"
Write-Host "  2) Corrupted latch-state.ini (invalid syntax)"
Write-Host "  3) Partial latch-state.ini (missing keys)"
Write-Host "  4) OutOfRange values (IconSize=999, ZoomPercent=500)"
Write-Host "  5) EmptyProfile (clean first-run onboarding test)"
Write-Host "  6) Restore backup"
$choice = Read-Host "Select option [1-6]"

Get-Process -Name wayplank -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

switch ($choice) {
    "1" {
        if (Test-Path $BackupDir) { Remove-Item -Recurse -Force $BackupDir }
        if (Test-Path $ConfigDir) { Copy-Item -Recurse -Force $ConfigDir $BackupDir }
        Write-Host "Backed up to $BackupDir" -ForegroundColor Green
    }
    "2" {
        New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
        Set-Content -Path (Join-Path $ConfigDir "latch-state.ini") -Value "[[[CORRUPTED_INI_SYNTAX===???"
        Write-Host "Injected Corrupted latch-state.ini" -ForegroundColor Yellow
    }
    "3" {
        New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
        Set-Content -Path (Join-Path $ConfigDir "latch-state.ini") -Value "[DockPreferences]`r`nIconSize=48`r`n"
        Write-Host "Injected Partial latch-state.ini" -ForegroundColor Yellow
    }
    "4" {
        New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
        Set-Content -Path (Join-Path $ConfigDir "latch-state.ini") -Value "[DockPreferences]`r`nIconSize=999`r`nZoomPercent=500`r`nPosition=99`r`n"
        Write-Host "Injected OutOfRange latch-state.ini" -ForegroundColor Yellow
    }
    "5" {
        if (Test-Path $ConfigDir) { Remove-Item -Recurse -Force $ConfigDir }
        Write-Host "Cleared $ConfigDir for clean first-run onboarding" -ForegroundColor Green
    }
    "6" {
        if (Test-Path $ConfigDir) { Remove-Item -Recurse -Force $ConfigDir }
        if (Test-Path $BackupDir) { Copy-Item -Recurse -Force $BackupDir $ConfigDir }
        Write-Host "Restored backup from $BackupDir" -ForegroundColor Green
    }
    default {
        Write-Host "Cancelled."
    }
}
