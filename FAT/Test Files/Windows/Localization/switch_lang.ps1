#
#  Copyright (C) 2026 Sergio Melas
#
#  This file is part of WayPlank (GPLv3).
#  Windows FAT Localization Switcher: launches wayplank.exe in any of the 8 embedded languages
#  without changing the Windows OS language.
#
#  Usage: .\switch_lang.ps1 zh_CN   (or: en, it, es, fr, ca, de, uk, zh_CN)
#
param(
    [Parameter(Position=0)]
    [string]$Lang = ""
)

$ValidLangs = @("en", "zh_CN", "it", "es", "fr", "ca", "de", "uk")
if (-not $Lang -or ($ValidLangs -notcontains $Lang)) {
    Write-Host "WayPlank Windows Localization Switcher" -ForegroundColor Cyan
    Write-Host "Usage: .\switch_lang.ps1 <lang>"
    Write-Host "Supported embedded languages: $($ValidLangs -join ', ')"
    exit 1
}

$Candidates = @(
    "C:\Program Files\WayPlank\wayplank.exe",
    "$env:LOCALAPPDATA\Programs\WayPlank\wayplank.exe",
    (Join-Path $PSScriptRoot "..\..\..\..\build\wayplank.exe")
)
$Exe = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Exe) {
    Write-Error "wayplank.exe not found in Program Files, LOCALAPPDATA, or build\"
    exit 1
}

Get-Process -Name wayplank -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

$env:LANGUAGE = $Lang
$env:LC_ALL = $Lang
$env:LANG = $Lang
Write-Host "Launching $Exe with LANGUAGE=$Lang ..." -ForegroundColor Green
Start-Process -FilePath $Exe -ArgumentList "-r"
