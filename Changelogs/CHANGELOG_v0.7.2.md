# WayPlank V0.7.2 (Public Beta 3 — Agnostic Boundary Translator & Linux HAL/Bus Freeze) Detailed Technical Changelog

> [!WARNING]
> **🚧 ISA-88 QUALIFICATION STATUS: WORK IN PROGRESS — UNQUALIFIED DEVELOPMENT BRANCH (`hal-v0.7.2`)**  
> `v0.7.1.2` (`FAT/2026-11-13 FAT 0.7.1.txt`, `375/375` = `100.0% PASS`) remains the active qualified public release on `main`.  
> Moves 1–3 below are **implemented and developer smoke-checked across KDE Plasma 6 (`KWin`), GNOME Shell (`Mutter`), and `Labwc`**, while **Move 4 (`IAppSystem` + Dual-Zone Firewall)** and **formal human ISA-88 qualification (`FAT/2026-11-14 FAT 0.7.2.txt`, `392` test definitions)** are still pending maintainer execution and sign-off.

Release Series: **V0.7.x Series (The Public Beta Milestone)**  
Current Milestone: **V0.7.2 (Public Beta 3 — `MOC-0.7.2-HAL-001`: 3-Zone Dichotomic Architecture, Agnostic Boundary Translator Layer `hal/Interfaces/`, Concentrated Freedesktop/Linux Southbound Drivers & Automated Dual-Zone HAL Purity Firewall)**  
Status / Target Window: **Active Engineering on `hal-v0.7.2` (~2026-11-14 to 2026-11-30 — Pending Move 4 & Formal `FAT 0.7.2` Qualification)**  
Maintainer: **Sergio Melas** (sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))  
Architecture References:
- [`Documentation/Architecture/README.md`](../Documentation/Architecture/README.md) (`DOC-ARCH-MASTER-001` Rev 2.1)
- [`Documentation/Architecture/HAL_COMPOSITORS.md`](../Documentation/Architecture/HAL_COMPOSITORS.md) (`DOC-ARCH-COMP-002` Rev 2.0)
- [`Documentation/Architecture/HAL_BUSES.md`](../Documentation/Architecture/HAL_BUSES.md) (`DOC-ARCH-BUS-003` Rev 2.0)
- [`Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md`](../Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md) (`DOC-ARCH-ID-004` Rev 2.0)
- [`Documentation/Architecture/HAL_WINDOWS_BACKEND.md`](../Documentation/Architecture/HAL_WINDOWS_BACKEND.md) (`DOC-ARCH-WIN-005` Rev 2.0 — Scheduled for `v0.7.3`)

---

## 1. 📋 Overview & Architectural Objective (`MOC-0.7.2-HAL-001`)

With WayPlank's Linux user-facing core feature-frozen at **`100.0%` multi-compositor qualification** in **`v0.7.1.2`**, **WayPlank `v0.7.2` (Public Beta 3)** executes a strictly behavior-preserving structural refactor under **ISA-88 Management of Change (`MOC-0.7.2-HAL-001`)**:

1. **Zone 1 — 100% OS-Agnostic Portable Core (`src/`, `lib/`, `vapi/core/`):**
   - Pure Cairo rendering, parabolic zoom physics, 26 visual effects, folder drawers, preview cards, 16 docklets UI, accordions, preferences, and the 6-Layer mathematical identity solver $S(I, W) \in [0, 124]$ contain **zero** Wayland, D-Bus, GVFS, POSIX, `/proc`, `/sys`, or Windows symbols.
2. **Zone 2 — 100% OS-Blind Agnostic Boundary Translator Layer (`hal/Interfaces/`):**
   - Pure Vala domain interfaces, normalized DTOs, and capability structs (`Hal`, `PlatformCapabilities`, `IDockShell`, `IWindowBackend`, `IThumbnailProvider`, `WindowInfo`, `IBusBackend`, `ISystemTelemetry`, `IPlatformRuntime`, `IAppSystem`) containing **zero** `DBusConnection`, `GLib.Variant` wire tuples, `GtkLayerShell`, `DesktopAppInfo`, or kernel paths.
3. **Zone 3 — Concentrated Southbound Platform Drivers (`hal/Freedesktop/`, `hal/Linux/`, `vapi/freedesktop/`):**
   - Houses 100% of Wayland (`KWin`, `Mutter` JS bridge `v5`, `Labwc`/`wlroots`, `LayerShellDockShell`), D-Bus (`DbusBroker` + typed bus unpackers), XDG (`.desktop`, Trash, Ejector, Autostart, Screenshot), and Linux (`/proc`, `/sys`, `systemd-logind`, `wpctl`, `fork`/`waitpid` KeyFile isolation, Unix signals) drivers—establishing a frozen northbound contract ready for the `v0.7.3` `hal/Windows/` plug-in without touching Core or Linux drivers.

---

## 2. 🪜 Incremental Vertical Execution Record (`Move 1` ➔ `Move 4`)

### 2.1. Move 1 — Physical Directory Skeleton & Zero-Logic Driver Relocation *(Implemented & Smoke-Checked — Commit `938d3be`, Tag `backup/0.7.2-move-1`)*
- **Scope & Verification:**
  - Created `hal/{Interfaces,Freedesktop/{KWin,Mutter,Wlroots,Shell},Linux/SysFs}/` and `vapi/{core,freedesktop}/`.
  - Relocated 21 existing compositor, protocol, C-bridge, and VAPI files out of `lib/Services/`, `lib/Protocols/`, and `vapi/` with **zero logic changes**.
  - Updated `BuildBin.sh`, `BuildDeb.sh`, `BuildRpm.sh`, and `po/generate_translations.py` (`VERSION` set to `0.7.2` on `hal-v0.7.2`); verified clean `WAYPLANK_NO_PROMPT=1 ./BuildDeb.sh` build (`0` errors, `0` warnings).

### 2.2. Move 2 — Compositor Shell, Input Region, Thumbnails & Capabilities Translator *(Implemented & 3-Compositor Smoke-Checked — Commit `73da67d`, Tag `backup/0.7.2-move-2`)*
- **Zone 2 Contracts Frozen (`hal/Interfaces/`):**
  - `Hal.vala`, `PlatformCapabilities.vala`, `IDockShell.vala` (`PopupSurfaceKind`, `apply_input_region`, `place_transient_overlay`), `IWindowBackend.vala` (100% purged of `DBusConnection`), `IThumbnailProvider.vala`, and `WindowInfo.vala`.
  - Retired `WindowControl.vala` and `WindowCapabilities.vala`.
- **Zone 3 Drivers Implemented (`hal/Freedesktop/`):**
  - `FreedesktopHalBootstrap.vala` (runtime Wayland session probe & `Hal.*` slot binder) and `Shell/LayerShellDockShell.vala` (consolidating `GtkLayerShell` anchoring, struts, input-shape regions `#34`, and Mutter/KWin popup/poof positioning).
  - Updated `KWinBackend`, `MutterBackend`, `LabwcBackend`, and `KWinThumbnailService` (`IThumbnailProvider`) to implement the bus-free Zone 2 interfaces.
- **Zone 1 Core Purification (`13` UI/Controller Files):**
  - Purified `DockWindow`, `HoverWindow`, `FolderMenuWindow`, `WindowCardsWindow`, `PoofWindow`, `PositionManager`, `HideManager`, `DragManager`, `DockController`, `PreferencesWindow`, `PlankDockItem`, `PreferencesDockItem`, `ShowDesktopDockItem`, and `WindowManager` of all `GtkLayerShell`, `WindowControl`, `SurfaceCoordinateService`, `KWinThumbnailService`, and `XdgSessionDesktop` references.
- **FAT Protocol Initialization & Smoke Check:**
  - Initialized [`FAT/2026-11-14 FAT 0.7.2.txt`](../FAT/2026-11-14%20FAT%200.7.2.txt) (`392` test definitions across Sections `1`–`14`, adding Section `14` HAL Architecture & Purity Verification `14.1`–`14.5`).
  - Developer smoke-checked live across **KDE Plasma 6 (`KWin`)**, **GNOME Shell (`Mutter`)**, and **`Labwc`**.

### 2.3. Move 3 — Bus, Telemetry, 16-Docklet, C/VAPI & Runtime Translators *(Implemented & 3-Compositor Smoke-Checked — Commit `21e2fb0`, Tag `backup/0.7.2-move-3`)*
- **Zone 2 Contracts Frozen (`hal/Interfaces/`):**
  - `IBusBackend.vala` (`IDockIpcServer`, `IDockIpcTarget`, `IMediaController` + `MediaPlayerSnapshot`, `INotificationBus`, `IDesktopThemeBus`, `ILauncherBadgeBus` + `ILauncherBadgeClient` + `LauncherBadgeState`).
  - `ISystemTelemetry.vala` (`ISessionPowerProvider`, `IBatteryProvider`, `IAudioProvider`, `IBrightnessProvider`, `INetworkProvider`, `ICpuMemoryProvider`, `IScreenshotProvider`, `ITrashProvider` + `TrashItemInfo`, `IEjectorProvider` + `RemovableDriveInfo`).
  - `IPlatformRuntime.vala` (`DesktopUtilityKind`, `open_system_utility`, `open_uri`, `http_get_sync`, `extract_archive`, `validate_keyfile_isolated`, `get/set_autostart_enabled`, `replace_running_instances`, `get_current_pid`, `set_process_title`, `parse_command_argv`, `termination_requested`, `system_resumed`).
- **Zone 3 Southbound Drivers (`hal/Freedesktop/` & `hal/Linux/`):**
  - `Freedesktop/Dbus/`: `DbusBroker.vala` (single shared Session & System `DBusConnection` + `NameOwnerChanged` / PID cache), `DockIpcServer.vala`, `DockIpcClient.vala`, `MprisDbusService.vala`, `NotificationDbusService.vala`, `DesktopThemeDbusService.vala`, `LauncherEntryDbusService.vala`, `NetworkManagerDbusService.vala`.
  - `Freedesktop/Xdg/`: `XdgEnvironment.vala`, `XdgAutostart.vala`, `FreedesktopTrashProvider.vala` (GVFS `trash:///`, `.trashinfo`, restore, permanent delete, `KWinTrashBridge`), `FreedesktopEjectorProvider.vala` (`VolumeMonitor` + `/media` filter), `FreedesktopScreenshotProvider.vala` (`grim`/`slurp`/`spectacle`/portal).
  - `Linux/`: `LinuxPlatformRuntime.vala`, `LinuxSessionPower.vala`, `LinuxAudioTelemetry.vala`, `ProcFs/LinuxCpuMemDiskTelemetry.vala`, `SysFs/LinuxBatteryProvider.vala`, and `SysFs/BrightnessControl.vala` (`IBrightnessProvider`).
- **C/VAPI Cross-Build Hygiene & Zone 1 Purification:**
  - Relocated Unix `<unistd.h>` and `<sys/prctl.h>` bindings out of `vapi/core/compat.vapi` into `vapi/freedesktop/unix-compat.vapi`; guarded ELF weak symbols in `lib/gtk-compat.c` and Unix install prefixes in `include/config.h` under `#ifndef _WIN32`; replaced `Posix.memset` in `lib/Drawing/Surface.vala` with `GLib.Memory.set()`.
  - Retired `lib/DBusManager.vala`, `lib/DBus/{Client,Interfaces}.vala`, `lib/Services/Unity.vala`, `lib/Services/Environment.vala`, and `lib/Services/EnvironmentSettings.vala`.
  - Purified all docklets (`Mpris`, `DoNotDisturb`, `Session`, `Battery`, `Volume`, `Brightness`, `Network`, `Cpu`, `Screenshot`, `Trash`, `Ejector`, `Weather`, `Clock`, `DigitalClock`), `SessionWindow`, `CalendarWindow`, `WeatherWindow`, `WeatherCityDialog`, `ThemeManager`, `SystemTheme`, `DockRenderer`, `Theme`, `ApplicationDockItemProvider`, `DockPreferences`, `PreferencesWindow`, `src/Main.vala`, and `AbstractMain.vala`.
  - Verified `0` forbidden leaks in `hal/Interfaces/` and `vapi/core/`, `0` compiler errors, `0` warnings (`WAYPLANK_NO_PROMPT=1 ./BuildDeb.sh`), and developer smoke-checked live across **KDE Plasma 6 (`KWin`)**, **GNOME Shell (`Mutter`)**, and **`Labwc`**.

### 2.4. Move 4 — `IAppSystem` Data Translator, Cross-OS Path/Argv Purity, Build Firewall & Formal `FAT 0.7.2` *(Pending)*
- **Remaining Engineering & Qualification Gate (`[M4-01]`–`[M4-19]`):**
  - Freeze `IAppSystem.vala` (`AppDescriptor`, `ProcessSnapshot`, `RecentDocInfo`) and `IAppMenuBus`; implement `XdgAppSystem.vala`, `LinuxProcessInspector.vala`, and `AppMenuDbusService.vala` (`dbusmenu` `id=61` + `Local State`).
  - Purify the final 19 files in `lib/` (`ApplicationIdentity`, `ApplicationDiscovery`, `Matcher`, `System`, `RecentFilesService`, `Paths`, `Utils`, `ItemFactory`, `ApplicationDockItem*`, `DockItem*`, `FileDockItem`, `DragManager`, `FolderMenuWindow`, `IconChooserDialog`, `DrawingService`, `AppUsageService`), replacing `Shell.parse_argv` with `Hal.Runtime.parse_command_argv()` and `has_prefix("/")` with `GLib.Path.is_absolute()`.
  - Enable the automated pre-compile **Dual-Zone HAL Purity Firewall** in `BuildBin.sh`.
  - Hand off to the human maintainer for full 3-compositor **ISA-88 `FAT 0.7.2` qualification (`FAT/2026-11-14 FAT 0.7.2.txt`)**.
