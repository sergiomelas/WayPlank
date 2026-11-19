# WayPlank V0.7.3 (Public Beta 4 — Native Windows Zero-DLL Monolith `wayplank.exe`) Detailed Technical Changelog

> [!NOTE]
> **✅ ISA-88 QUALIFICATION STATUS: 100.0% 4-PLATFORM QUALIFIED (`525/525` APPLICABLE PASSED — `2026-11-19`)**  
> `v0.7.3` builds directly on the **`100.0%` 3-compositor Linux-qualified `v0.7.2` (`V0.7.2`, `4da05c5`)** baseline: `hal/Interfaces/`, `hal/Freedesktop/`, and `hal/Linux/` remain **frozen (`0` Linux HAL edits)** while `hal/Windows/`, `vapi/windows/`, `BuildWin.sh`, and `BuildNsis.sh` plug the complete native Windows `7 ⟷ 11+` backend directly into Zone 2 (with 4 minimal, 100% OS-agnostic GTK3 fixes in `lib/DragManager.vala` and `FileChooserDialog` passing all 8/8 Linux HAL Firewall gates).  
> Qualified FAT Protocol: [`FAT/2026-11-19 FAT 0.7.3.txt`](../FAT/2026-11-19%20FAT%200.7.3.txt) (`533` tests defined / `525` applicable: `SESSION 1: WINDOWS` **`135/135 (100.0%)`** [`132 [ok]` + `3 [ko->ok]` (`1.5`, `2.14`, `5.3`) + `3 [NA]` (`9.4`, `9.9`, `10.1`)]; `SESSION 2: GNOME` `132/132`; `SESSION 3: KDE PLASMA 6` `132/132`; `SESSION 4: LABWC` `126/126` + `5 [NA]` → **`525/525 (100.0%)`, `0 [ko]`**).

Release Series: **V0.7.x Series (The Public Beta Milestone)**  
Current Milestone: **V0.7.3 (Public Beta 4 — Native Windows Zero-DLL Monolith `build/wayplank.exe` & 64-Bit NSIS Installer `build/WayPlank-0.7.3-Setup.exe`)**  
Status: **100.0% 4-PLATFORM FAT QUALIFIED (`525/525` — Live-Certified on Real Windows 11 Hardware + Linux 8/8 Firewall GREEN)**  
Maintainer: **Sergio Melas** (sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))  
Architecture References:
- [`Documentation/Architecture/HAL_WINDOWS_BACKEND.md`](../Documentation/Architecture/HAL_WINDOWS_BACKEND.md) (`DOC-ARCH-WIN-005` Rev 2.2)
- [`Documentation/Architecture/README.md`](../Documentation/Architecture/README.md) (`DOC-ARCH-MASTER-001` Rev 2.5)
- [`Documentation/Architecture/HAL_COMPOSITORS.md`](../Documentation/Architecture/HAL_COMPOSITORS.md) (`DOC-ARCH-COMP-002` Rev 2.0)
- [`Documentation/Architecture/HAL_BUSES.md`](../Documentation/Architecture/HAL_BUSES.md) (`DOC-ARCH-BUS-003` Rev 2.0)
- [`Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md`](../Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md) (`DOC-ARCH-ID-004` Rev 2.2)

---

## 1. 🪜 Incremental Windows Milestone Record (`W1` ➔ `W6`)

### 1.1. Milestone W1 — Linux-Hosted 4-Tier Static MinGW Sysroot, Built-In Static SVG Loader, `BuildWin.sh` & 64-Bit NSIS Installer *(Complete & Live-Booted on Windows 10)*
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

### 1.2. Completed Milestones (`W2` ➔ `W6` — Live-Qualified on Real Windows 11 Hardware)
- [x] **Milestone W2 — `Win32Backend` & Off-Thread `Win32ThumbnailProvider` (`hal/Windows/Compositor/`):**
  - `SetWinEventHook` (`WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS`, `g_idle_add` coalesced) + `EnumWindows` with UWP `ApplicationFrameWindow` child `CoreWindow` PID unwrapping, dynamic `DwmGetWindowAttribute(DWMWA_CLOAKED / DWMWA_EXTENDED_FRAME_BOUNDS)`, `SHGetPropertyStoreForWindow` (`PKEY_AppUserModel_ID`), `QueryFullProcessImageNameW`, `AttachThreadInput` + `SetForegroundWindow`, `ShowWindowAsync`, `WM_CLOSE`, and `Shell_TrayWnd` `WM_COMMAND 407` Show Desktop.
  - Generic Win32 framework class filtering (`Chrome_WidgetWin_*`, `ApplicationFrameWindow`, `HwndWrapper[*]`, `Qt*`), `"++"` → `"plusplus"` normalization (`notepad++` vs `notepad`), Chrome/Edge `AUMID` → `--profile-directory=` & `_crx_` PWA parsing, and **off-thread `GLib.Thread` `PrintWindow(PW_RENDERFULLCONTENT)` + `GdiFlush()`** (`0 ms` main-thread stall → smooth 60 FPS hover & live preview cards).
- [x] **Milestone W3 — `Win32Shell` & Embedded Windows Visual Assets (`hal/Windows/Compositor/Win32Shell.vala`, `hal/Windows/wayplank.ico`):**
  - `WS_EX_TOOLWINDOW | WS_EX_TOPMOST` (activatable dock HWND so right-click menus & OLE2 DnD work natively; `no_activate` strictly on `TOOLTIP` & `POOF`), one-shot cached HWND styling (no per-frame `SWP_FRAMECHANGED` stutter), `GWLP_WNDPROC` `WM_NCHITTEST -> HTTRANSPARENT` click-through outside active dock mask, 3-way idempotent `SHAppBarMessage` Panel Mode struts, centered `resolve_tooltip_anchor`, 7-resolution 32-bit RGBA `wayplank.ico`, and in-RAM SVG symbolic checkmarks/radios/submenu arrows (`Gtk.IconTheme.add_builtin_icon` + screen CSS).
- [x] **Milestone W4 — `Win32AppSystem` (`hal/Windows/AppSystem/`):**
  - `OleInitialize(NULL)` COM `IShellLinkW` + `IPropertyStore` (`PKEY_AppUserModel_ID`) `.lnk` parser, `PrivateExtractIconsW` / `SHGetImageList(SHIL_JUMBO)` + `GdiFlush()` icon extractor, `ShellExecuteW`, Toolhelp32 process inspector, `SHGetFolderPathW` known folders, `.url` `[InternetShortcut]`, and `Recent\*.lnk` jump lists.
  - 4-tier icon cascade (`User choice` → validated `.lnk` → target `.exe` → clean fallback SVG), direct Vala ICO/PNG container decoder (`winico:` fixing Windows `io-ico.c` on 256×256 PNG-in-ICO Chrome/Edge `Google Profile.ico`), `GFileMonitor` (`ReadDirectoryChangesW`) on Chrome/Edge `Local State`, and synthetic `.wayplank-app` launchers.
- [x] **Milestone W5 — `Win32BusBroker` & `Win32Telemetry` (`hal/Windows/Bus/`, `hal/Windows/Telemetry/`):**
  - Recycle Bin (`SHQueryRecycleBinW`, `SHFileOperationW`, `SHEmptyRecycleBinW`), Removable Drive Ejector (`GetLogicalDrives`, `DeviceIoControl`), Battery (`GetSystemPowerStatus`), CPU/RAM (`GetSystemTimes`, `GlobalMemoryStatusEx`), CoreAudio (`IMMDeviceEnumerator` → `IAudioEndpointVolume`), dynamic `dxva2.dll` DDC/CI Brightness (dynamically reflected in `caps.supports_hardware_brightness`), Network (`GetAdaptersAddresses`), Session/Power (`LockWorkStation`, dynamic `powrprof.dll` `SetSuspendState`, `ExitWindowsEx`), `AppsUseLightTheme`, `VK_MEDIA_*`, dynamic `winhttp.dll` HTTPS GET (Weather), Registry Autostart (`HKCU\...\Run\WayPlank`), full-screen `BitBlt` Screenshot, `DesktopUtilityKind` (`ms-settings:*`, `taskmgr.exe`), and `Win32AppMenuBus` (`AUMID` + `Local State` Chrome multi-profile running-dot stability).
  - Embedded all 4 GTK3 GSchemas (`org.gtk.Settings.FileChooser`, `ColorChooser`, `EmojiChooser`, `Debug`) into `gschemas.compiled` in `BuildWin.sh`, and added NSIS auto-close (`taskkill /F /IM wayplank.exe`) in `BuildNsis.sh` for seamless overwrite upgrades.
- [x] **Milestone W6 — Full 4-Platform `FAT 0.7.3` Qualification (`525/525` — `100.0%`) & Unified Packaging:**
  - Live-certified on real Windows 11 hardware: **`135/135 (100.0%)`** (`132 [ok]` + `3 [ko->ok]` squashed: **`1.5`** drag-out removal via `Gdk.DragAction.MOVE | Gdk.DragAction.PRIVATE` & outside-dock `drag_failed` guard in `DragManager.vala`; **`2.14`** `notepad++` vs `notepad` `++`→`plusplus` normalization; **`5.3`** 60 FPS off-thread `PrintWindow` + one-shot HWND styling; `3 [NA]` protocol/platform items `9.4`, `9.9`, `10.1`).
  - Minimal Zone 1 cross-OS GTK3 fixes (`lib/DragManager.vala`, `IconChooserDialog.vala`, `DockFolderDialogs.vala`, `PreferencesWindow.vala` `Gtk.FileChooserDialog`) verified against all **8/8 Linux HAL Purity Firewall Gates (`GREEN`)** and `0` Pitfall #14 closure UAFs.
  - All 5 unified `v0.7.3` deliverables synchronized in `build/`: `wayplank`, `wayplank_0.7.3_amd64.deb`, `wayplank-0.7.3-1.x86_64.rpm`, `wayplank.exe` (`24 MB`, **24 evergreen Windows OS DLLs only**), and `WayPlank-0.7.3-Setup.exe` (`8.8 MB`).
