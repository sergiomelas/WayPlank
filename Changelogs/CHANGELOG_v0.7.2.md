# WayPlank V0.7.2 (Public Beta 3 — Agnostic Boundary Translator & Linux HAL/Bus Freeze) Detailed Technical Changelog

> [!WARNING]
> **🚧 ISA-88 QUALIFICATION STATUS: WORK IN PROGRESS — UNQUALIFIED DEVELOPMENT BRANCH (`hal-v0.7.2`)**  
> `v0.7.1.2` (`FAT/2026-11-13 FAT 0.7.1.txt`, `375/375` = `100.0% PASS`) remains the active qualified public release on `main`.  
> Moves 1–3 (including the **33-item ISA-88 Post-Audit Remediation across Sub-Gates A, B & C**, `backup/0.7.2-move-3b`) are **implemented and live smoke-checked across KDE Plasma 6 (`KWin`), GNOME Shell (`Mutter`), and `Labwc`**, while **Move 4 (`IAppSystem` + Dual-Zone Firewall, `[M4-01..40]`)** and **formal human ISA-88 qualification (`FAT/2026-11-15 FAT 0.7.2.txt`, `394` test definitions)** are still pending execution and maintainer sign-off.

Release Series: **V0.7.x Series (The Public Beta Milestone)**  
Current Milestone: **V0.7.2 (Public Beta 3 — `MOC-0.7.2-HAL-001`: 3-Zone Dichotomic Architecture, Agnostic Boundary Translator Layer `hal/Interfaces/`, Concentrated Freedesktop/Linux Southbound Drivers & Automated Dual-Zone HAL Purity Firewall)**  
Status / Target Window: **Active Engineering on `hal-v0.7.2` (~2026-11-14 to 2026-11-30 — Pending Move 4 & Formal `FAT 0.7.2` Qualification)**  
Maintainer: **Sergio Melas** (sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))  
Architecture References:
- [`Documentation/Architecture/README.md`](../Documentation/Architecture/README.md) (`DOC-ARCH-MASTER-001` Rev 2.2)
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
  - Initialized [`FAT/2026-11-15 FAT 0.7.2.txt`](../FAT/2026-11-15%20FAT%200.7.2.txt) (`394` test definitions across Sections `0`–`14`, adding Section `14` HAL Architecture & Purity Verification `14.1`–`14.5` and Tests `0.1`–`0.2`).
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

### 2.3.1. Moves 1–3 ISA-88 Post-Audit Remediation Closure (`Sub-Gates A, B & C` — `33/33` Items Closed & Live-Verified, Tag `backup/0.7.2-move-3b`)
- **Sub-Gate A — Build, Lifecycle, Multi-Dock IPC & Early Bootstrap (`[M1-10..11]`, `[M2-17..25]`, `[M3-31..33, 35, 42, 46, 47, 52]`):**
  - Synchronized `po/POTFILES.in` via `po/generate_translations.py`, wired early `wayplank_hal_platform_early_runtime()` bootstrap for `--validate-latch` before GTK init, ordered deterministic `Hal` / controller / singleton teardown on `SIGINT`/`SIGTERM`, isolated multi-dock IPC object paths (`/net/launchpad/plank/<dock_name>`), and fixed `FAT 0.1` (`wayplank -n <dock>` `GVariantDict.lookup("name", "s", ...)` owned-string lifetime).
- **Sub-Gate B — Typed Bus/Telemetry Contracts, Process Inspector & Notification Hardening (`[M3-36..39, 41, 49]`):**
  - Completed typed `IBusBackend`, `ISystemTelemetry`, and `IPlatformRuntime` contracts (`DbusBroker` connection/watcher cleanup, `LauncherEntryDbusService` normalized launcher matching + multi-type `int32`/`uint32`/`int64` `Variant` badge unpacker, `MprisDbusService` snapshot guards, `LinuxProcessInspector`), fixed `FAT 6.9` (`NotificationDbusService` `"as"` `VariantBuilder` action array + `EjectorDockItem` `cleaned_up` guard), and fixed `FAT 0.2` by switching `SurfaceCache` maintenance timer (plus `Preferences`, `ApplicationDockItemProvider`, and `NotificationDbusService` `WeakRef` closures) to static `GLib.Timeout.add_seconds` / owned-closure helpers with zero `Use-After-Free` or implicit strong `self` capture.
- **Sub-Gate C — Portable Cairo Surface, Locale-Independent Floats, Cross-OS Path/Theme Safety & 13 GResource Vector Fallbacks (`[M3-34, 40, 43..45, 48, 50, 51]`):**
  - Switched `Drawing.Surface` backing buffer to `Cairo.ImageSurface` while preserving `device_scale` HiDPI cache isolation, fixed `Theme.notify_property("TopRoundness")` and `ApplicationDockItem` cold-start `position_manager` null guard, switched CSS/HTTP float formatting in `WeatherDockItem` & `PreferencesWindow` to `g_ascii_formatd` (`double.format`), added Win32/DOS reserved-name and path-traversal guards in `ThemeManager` & `DockPreferences`, and authored **13 WayPlank vector fallback SVGs** in `data/docklets/` (`63` total embedded SVGs in `plank.gresource.xml`) with `Gtk.IconTheme`-first resolution in `DrawingService`.

### 2.4. Move 4 — `IAppSystem` Data Translator, Cross-OS Path/Argv Purity, Build Firewall & Formal `FAT 0.7.2` *(Pending — `[M4-01..40]`)*
- **Remaining Engineering & Qualification Gate (`40` Items in `HAL_DIFFUSED_CHUNKS_CHECKLIST.txt` Section 4):**
  - Freeze `IAppSystem.vala` (`AppDescriptor`, `ProcessSnapshot`, `RecentDocInfo`, `QuicklistAction`, `DefaultAppRole`, `BrowserFamily`) and `IAppMenuBus`; implement `XdgAppSystem.vala`, expand `LinuxProcessInspector.vala`, and implement `AppMenuDbusService.vala` (`dbusmenu` `id=61` + `Local State`).
  - Purify the remaining Core files in `src/` and `lib/` (`ApplicationIdentity`, `ApplicationDiscovery`, `Matcher`, `System`, `RecentFilesService`, `Paths`, `Utils`, `ItemFactory`, `ApplicationDockItem*`, `DockItem*`, `FileDockItem`, `DragManager`, `FolderMenuWindow`, `DockWindow`, `IconChooserDialog`, `DrawingService`, `AppUsageService`, `Main`, `AbstractMain`), keeping 100% of the 6-Layer mathematical identity solver $S(I, W) \in [0, 124]$ in Zone 1 Core.
  - Enable the automated pre-compile **Dual-Zone HAL Purity Firewall** in `BuildBin.sh`.
  - Hand off to the human maintainer for full 3-compositor **ISA-88 `FAT 0.7.2` qualification (`FAT/2026-11-15 FAT 0.7.2.txt`)**.
