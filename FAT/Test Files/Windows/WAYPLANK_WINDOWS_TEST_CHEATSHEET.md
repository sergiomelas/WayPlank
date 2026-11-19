# 🪟 WayPlank Windows Testing Cheatsheet (`Win 7 ⟷ 11+`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Target Assets:** `build/wayplank.exe` (Zero-DLL Portable) • `build/WayPlank-<ver>-Setup.exe` (64-bit NSIS Installer)

---

## 1. Building on Linux Host
```bash
# Build portable Zero-DLL build/wayplank.exe (uses cached deps/win32/sysroot):
WAYPLANK_NO_PROMPT=1 ./BuildWin.sh

# Build portable build/wayplank.exe + 64-bit NSIS installer build/WayPlank-0.7.3-Setup.exe:
WAYPLANK_NO_PROMPT=1 ./BuildNsis.sh

# Verify Zero-DLL evergreen OS import allowlist manually:
x86_64-w64-mingw32-objdump -p build/wayplank.exe | grep "DLL Name:"
```

## 2. Installing & Running on Windows 10/11 (VMware Workstation / Bare Metal)
- **System-Wide Install (Admin):** Run `WayPlank-0.7.3-Setup.exe` → installs to `C:\Program Files\WayPlank\wayplank.exe`.
- **Per-User Install (No Admin):** Run `WayPlank-0.7.3-Setup.exe` → select Current User → installs to `%LOCALAPPDATA%\Programs\WayPlank\wayplank.exe`.
- **Portable Run:** Copy `wayplank.exe` anywhere and double-click (zero DLLs needed).

## 3. Windows Runtime Paths
- **Dock Config & Unified Registry:** `%LOCALAPPDATA%\wayplank\latch-state.ini`
- **Dock Launchers (`dock1`–`dock4`):** `%LOCALAPPDATA%\wayplank\dock1\launchers\*.dockitem`
- **Custom User Themes:** `%LOCALAPPDATA%\wayplank\themes\`
- **Auto-Extracted GSettings Schema:** `%LOCALAPPDATA%\WayPlank\glib-2.0\schemas\gschemas.compiled`
- **Autostart Registry Value:** `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` → `WayPlank`

## 4. Running Windows FAT Testers (PowerShell)
```powershell
# Fullscreen inhibit test (F11 / Space to toggle, Esc to quit):
powershell -ExecutionPolicy Bypass -File "Testers\test_fullscreen.ps1"

# Windows Notification / Focus Assist test:
powershell -ExecutionPolicy Bypass -File "Testers\test_notification.ps1"

# Win32 FlashWindowEx Urgency / DemandsAttention test:
powershell -ExecutionPolicy Bypass -File "Testers\test_urgency.ps1"

# Test all 8 embedded languages without changing Windows OS language:
powershell -ExecutionPolicy Bypass -File "Localization\switch_lang.ps1" zh_CN

# Test fault-tolerant latch-state.ini recovery & clean first-run onboarding:
powershell -ExecutionPolicy Bypass -File "Environment\Test-Environments.ps1"
```

## 5. Shared OS-Agnostic Assets
- **Sample Drag & Drop Files:** `..\Files\` (`Test.txt`, `WayPlank_FAT_BugSquash.png`, `Sergio Melas CV.pdf`)
- **Sample Custom Theme Archives:** `..\Themes\` (`Glassier Cool Edition.zip`, `.tar.gz`, `Multi_Theme_Pack.zip`)
