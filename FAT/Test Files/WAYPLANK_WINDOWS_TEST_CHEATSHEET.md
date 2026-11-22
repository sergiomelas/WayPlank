# 🪟 WayPlank Windows Testing Cheatsheet (`Win 7 ⟷ 11+`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Target Assets:** `build/windows/wayplank.exe` (Zero-DLL Portable) • `build/windows/WayPlank-<ver>-Setup.exe` (64-bit NSIS Installer)

---

## 1. Building on Linux Host
```bash
# Build portable Zero-DLL build/windows/wayplank.exe (uses cached deps/win32/sysroot):
WAYPLANK_NO_PROMPT=1 ./builders/windows/BuildWin.sh

# Build portable build/windows/wayplank.exe + 64-bit NSIS installer build/windows/WayPlank-0.7.3.2-Setup.exe:
WAYPLANK_NO_PROMPT=1 ./builders/windows/BuildNsis.sh

# Verify Zero-DLL evergreen OS import allowlist manually:
x86_64-w64-mingw32-objdump -p build/windows/wayplank.exe | grep "DLL Name:"
```

## 2. Installing & Running on Windows 10/11 (Virtual Machine / Bare Metal)
- **System-Wide Install (Admin):** Run `WayPlank-0.7.3.2-Setup.exe` → installs to `C:\Program Files\WayPlank\wayplank.exe`.
- **Per-User Install (No Admin):** Run `WayPlank-0.7.3.2-Setup.exe` → select Current User → installs to `%LOCALAPPDATA%\Programs\WayPlank\wayplank.exe`.
- **Portable Run:** Copy `wayplank.exe` anywhere and double-click (zero DLLs needed).

## 3. Windows Runtime Paths
- **Dock Config & Unified Registry:** `%LOCALAPPDATA%\wayplank\latch-state.ini`
- **Custom Non-Destructive Shortcut Names:** `%LOCALAPPDATA%\wayplank\launcher-names.ini`
- **Dock Launchers (`dock1`–`dock4`):** `%LOCALAPPDATA%\wayplank\dock1\launchers\*.dockitem`
- **Custom User Themes:** `%LOCALAPPDATA%\wayplank\themes\`
- **Persistent Start Menu `.lnk` Index Cache:** `%LOCALAPPDATA%\WayPlank\lnk-index-cache.ini`
- **Hardware Brightness Capabilities Cache:** `%LOCALAPPDATA%\WayPlank\hw-caps-cache.ini`
- **Auto-Extracted GSettings Schema:** `%LOCALAPPDATA%\WayPlank\glib-2.0\schemas\gschemas.compiled`
- **Autostart Registry Value:** `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` → `WayPlank`

## 4. Running Windows FAT Testers (PowerShell)
Run from `FAT\Test Files\` (or adjust paths if running from `FAT\Test Files\Windows\`):
```powershell
# Fullscreen inhibit test (F11 / Space to toggle, Esc to quit):
powershell -ExecutionPolicy Bypass -File "Windows\Testers\test_fullscreen.ps1"

# Windows Notification / Focus Assist test:
powershell -ExecutionPolicy Bypass -File "Windows\Testers\test_notification.ps1"

# Win32 FlashWindowEx Urgency / DemandsAttention test:
powershell -ExecutionPolicy Bypass -File "Windows\Testers\test_urgency.ps1"

# Test all 8 embedded languages without changing Windows OS language:
powershell -ExecutionPolicy Bypass -File "Windows\Localization\switch_lang.ps1" zh_CN

# Test fault-tolerant latch-state.ini recovery & clean first-run onboarding:
powershell -ExecutionPolicy Bypass -File "Windows\Environment\Test-Environments.ps1"
```

## 5. Shared OS-Agnostic Assets
- **Sample Drag & Drop Files:** `Files\` (`Test.txt`, `WayPlank_FAT_BugSquash.png`, `Sergio Melas CV.pdf`)
- **Sample Custom Theme Archives:** `Themes\` (`Glassier Cool Edition.zip`, `.tar.gz`, `Multi_Theme_Pack.zip`)

---

## 6. Generic Windows Test VM Setup Procedure (Hypervisor-Agnostic)

Works on any desktop or server hypervisor (**QEMU/KVM `virt-manager`**, **VMware**, **VirtualBox**, **Proxmox**, **Hyper-V**, etc.):

1. **VM Sizing:** Windows 10 / 11 64-bit (`x86_64`), `2–4` vCPUs, `4–8 GB` RAM, `50–60 GB` virtual disk, **Bridged** or **NAT** virtual NIC.
2. **Guest Tools & Display:** Install the hypervisor's guest drivers for dynamic display resize and HiDPI scale testing (`100%`, `125%`, `150%`), plus optional second virtual display for multi-monitor FAT (`14.6`).
3. **Host ↔ VM File Transfer:** Use a shared folder, SMB share, or built-in Windows OpenSSH Server (`Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0` + `Start-Service sshd`) to copy `build/windows/wayplank.exe`, `build/windows/WayPlank-<ver>-Setup.exe`, and `FAT/Test Files/` directly into the guest.
4. **Clean FAT Snapshot:** Take a clean VM snapshot **before** installing WayPlank so First-Run Onboarding (`1.9`) and fresh-install tests (`15.1`–`15.6`) can be re-run cleanly anytime.

*(For native FreeBSD / GhostBSD build & test VM procedures, see [`WAYPLANK_BSD_TEST_CHEATSHEET.md`](WAYPLANK_BSD_TEST_CHEATSHEET.md).)*
