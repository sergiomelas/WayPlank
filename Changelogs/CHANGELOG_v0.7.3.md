# WayPlank V0.7.3 (Public Beta 4 — Native Windows Zero-DLL Monolith `wayplank.exe`) Detailed Technical Changelog

> [!NOTE]
> **🚧 ISA-88 QUALIFICATION STATUS: IN PROGRESS — MILESTONE W1 COMPLETE & LIVE-BOOTED ON WINDOWS 10 (`2026-11-19`)**  
> `v0.7.3` builds directly on the **`100.0%` 3-compositor Linux-qualified `v0.7.2` (`V0.7.2`, `4da05c5`)** baseline under a strict **Boundary Lock**: `src/`, `lib/`, `vapi/core/`, `hal/Interfaces/`, `hal/Freedesktop/`, and `hal/Linux/` remain **frozen (`0` Linux edits)** while `hal/Windows/`, `vapi/windows/`, `BuildWin.sh`, and `BuildNsis.sh` plug the native Windows `7 ⟷ 11+` backend directly into Zone 2.  
> Active FAT Protocol: [`FAT/2026-11-19 FAT 0.7.3.txt`](../FAT/2026-11-19%20FAT%200.7.3.txt) (`533` tests defined / `528` applicable: `SESSION 1: WINDOWS` `138 [  ]` pending live qualification; `SESSION 2–4` Linux GNOME `132 [ok]`, KDE Plasma 6 `132 [ok]`, Labwc `126 [ok]` + `5 [NA]` frozen from `v0.7.2`, `0 [ko]`).

Release Series: **V0.7.x Series (The Public Beta Milestone)**  
Current Milestone: **V0.7.3 (Public Beta 4 — Native Windows Zero-DLL Monolith `build/wayplank.exe` & 64-Bit NSIS Installer `build/WayPlank-0.7.3-Setup.exe`)**  
Status: **IN PROGRESS — Milestone W1 Complete (Booted Live on Windows 10 x64)**  
Maintainer: **Sergio Melas** (sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))  
Architecture References:
- [`Documentation/Architecture/HAL_WINDOWS_BACKEND.md`](../Documentation/Architecture/HAL_WINDOWS_BACKEND.md) (`DOC-ARCH-WIN-005` Rev 2.1)
- [`Documentation/Architecture/README.md`](../Documentation/Architecture/README.md) (`DOC-ARCH-MASTER-001` Rev 2.5)
- [`Documentation/Architecture/HAL_COMPOSITORS.md`](../Documentation/Architecture/HAL_COMPOSITORS.md) (`DOC-ARCH-COMP-002` Rev 2.0)
- [`Documentation/Architecture/HAL_BUSES.md`](../Documentation/Architecture/HAL_BUSES.md) (`DOC-ARCH-BUS-003` Rev 2.0)
- [`Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md`](../Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md) (`DOC-ARCH-ID-004` Rev 2.2)

---

## 1. 🪜 Incremental Windows Milestone Record (`W1` ➔ `W6`)

### 1.1. Milestone W1 — Linux-Hosted 4-Tier Static MinGW Sysroot, Built-In Static SVG Loader, `BuildWin.sh` & 64-Bit NSIS Installer *(Complete & Live-Booted on Windows 10 — Commit `c97279b`)*
- **Zero-DLL Linux Cross-Compilation Pipeline ([`BuildWin.sh`](../BuildWin.sh) & [`deps/README.md`](../deps/README.md)):**
  - Automated, resumable 4-Tier static MinGW-w64 (`x86_64-w64-mingw32-gcc-posix` / `g++-posix`) sysroot builder in gitignored `./deps/win32/sysroot` covering all **20 static archives**:
    - Tier 1: `zlib 1.3.1`, `libffi 3.4.6`, `libiconv 1.17`, `gettext-runtime 0.22.5`, `pcre2 10.44`
    - Tier 2: `glib-2.0 2.80.5`, `libgee-0.8 0.20.6`, `json-glib-1.0 1.8.0`
    - Tier 3: `libpng 1.6.44`, `pixman 0.43.4`, `freetype 2.13.3`, `fribidi 1.0.16`, `harfbuzz 10.0.1`, `cairo 1.18.2` (`-Ddwrite=disabled`), `pango 1.54.0`, `lunasvg 2.4.1`, `gdk-pixbuf 2.42.12`
    - Tier 4: `libepoxy 1.5.10`, `atk 2.38.0` (`-DATK_STATIC_COMPILATION`), `gtk+-3.0 3.24.43` (`-Dwin32_backend=true -Dx11_backend=false -Dwayland_backend=false -Dbuiltin_immodules=all`)
  - Enforces the pre-compile **Zone 1 / Zone 2 HAL Purity Firewall (`0` leaks)** and the post-link **`x86_64-w64-mingw32-objdump -p` Zero-DLL Allowlist Gate (`GREEN`: 24 evergreen Windows OS DLLs only; 0 third-party/GTK/MinGW DLLs)**.
  - Produces stripped **`build/wayplank.exe` (`23 MB`)** with Per-Monitor V2 HiDPI manifest (`hal/Windows/wayplank.manifest`, `hal/Windows/wayplank.rc`).
- **Built-In Static `lunasvg` SVG Loader (`hal/Windows/win32-svg-loader.cpp`):**
  - Compiled directly into `libgdk_pixbuf-2.0.a` (`-DINCLUDE_svg`, external `loaders.cache` probe disabled) with `size_func` HiDPI scaling so all 63 embedded WayPlank vector icons render crisply on Windows with zero external DLLs.
- **Bootstrap HAL & Embedded Schema Extraction (`hal/Windows/WindowsHalBootstrap.vala`, `hal/Windows/Compositor/win32-bridge.{c,h}`, `vapi/windows/win32-bridge.vapi`):**
  - Exports `wayplank_hal_platform_{bootstrap,early_runtime,early_apps}`, auto-extracts embedded `gschemas.compiled` from `GResource` to `%LOCALAPPDATA%\WayPlank\glib-2.0\schemas\`, and implements backslash-safe `CommandLineToArgvW` tokenization.
- **64-Bit Windows NSIS Installer ([`BuildNsis.sh`](../BuildNsis.sh) $\rightarrow$ `build/WayPlank-0.7.3-Setup.exe`, `8.8 MB` LZMA):**
  - Linux-hosted `makensis` packager supporting both **System-Wide Admin (`C:\Program Files\WayPlank`)** and **Per-User (`%LOCALAPPDATA%\Programs\WayPlank`)** modes (`MULTIUSER_USE_PROGRAMFILES64` + `SetRegView 64`), Start Menu / Desktop shortcuts, optional Autostart, Windows Installed Apps registration, and clean `Uninstall.exe`.
- **Live Verification:** Installed and booted cleanly on Windows 10 x64 (VMware Workstation) displaying the translucent Cairo dock, zoom physics, embedded SVG docklets, and tooltips with zero missing DLLs.
- **Test Suite Reorganization:** Partitioned `FAT/Test Files/` into shared `Files/` & `Themes/`, `Freedesktop/` (existing Linux testers/links/localization/environment/QEMU), and native PowerShell `Windows/` (`test_fullscreen.ps1`, `test_notification.ps1`, `test_urgency.ps1`, `.url` links, `switch_lang.ps1`, `Test-Environments.ps1`, `WAYPLANK_WINDOWS_TEST_CHEATSHEET.md`).

### 1.2. Planned Milestones (`W2` ➔ `W6`)
- [ ] **Milestone W2:** `Win32Backend` + `Win32ThumbnailProvider` (`SetWinEventHook`, `EnumWindows`, `DwmGetWindowAttribute`, `PrintWindow` live preview cards)
- [ ] **Milestone W3:** `Win32Shell` (`SHAppBarMessage` struts, `WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST`, `WM_NCHITTEST -> HTTRANSPARENT` click-through, popup/tooltip/poof anchoring, embedded `wayplank.ico`)
- [ ] **Milestone W4:** `Win32AppSystem` (`.lnk` `IShellLinkW`, UWP `aumid://`, `256×256` `SHIL_JUMBO` icon extraction, `Recent\*.lnk` jump lists, `ShellExecuteW` launching)
- [ ] **Milestone W5:** `Win32BusBroker` & `Win32Telemetry` (Named Pipes IPC, CoreAudio, `GetSystemTimes`, `GetSystemPowerStatus`, `dxva2`, `SHQueryRecycleBinW` Recycle Bin, `CM_Request_Device_EjectW` Ejector, `WinHTTP` Weather, Focus Assist, Registry dark/light theme & `HKCU\...\Run` self-healing Autostart)
- [ ] **Milestone W6:** Full Windows `FAT 0.7.3` qualification (`138/138`), Linux Boundary Lock verification, and unified `v0.7.3` Public Beta 4 release packaging (`.deb`, `.rpm`, `wayplank.exe`, `WayPlank-0.7.3-Setup.exe`).
