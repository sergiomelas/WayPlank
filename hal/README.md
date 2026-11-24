# WayPlank Hardware & OS Abstraction Layer (`hal/`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Canonical Architecture Specs:** [`Documentation/Architecture/README.md`](../Documentation/Architecture/README.md) · [`HAL_COMPOSITORS.md`](../Documentation/Architecture/HAL_COMPOSITORS.md) · [`HAL_BUSES.md`](../Documentation/Architecture/HAL_BUSES.md) · [`APPLICATION_IDENTITY_ENGINE.md`](../Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md) · [`HAL_LINUX_BACKEND.md`](../Documentation/Architecture/HAL_LINUX_BACKEND.md) · [`HAL_BSD_BACKEND.md`](../Documentation/Architecture/HAL_BSD_BACKEND.md) · [`HAL_WINDOWS_BACKEND.md`](../Documentation/Architecture/HAL_WINDOWS_BACKEND.md)  
> **Multi-OS Build System:** [`builders/README.md`](../builders/README.md) · [`build/README.md`](../build/README.md)

---

## 1. Why `hal/` Is Cataloged This Way

WayPlank enforces a strict **3-Zone Dichotomic Architecture** verified at every build by the pre-compile **8-Gate Dual-Zone HAL Purity Firewall** ([`builders/linux/BuildBin.sh`](../builders/linux/BuildBin.sh), [`builders/bsd/BuildBsd.sh`](../builders/bsd/BuildBsd.sh), and [`builders/windows/BuildWin.sh`](../builders/windows/BuildWin.sh)):

- **Zone 1 — Agnostic Core (`src/`, `lib/`, `vapi/core/`):** Pure dock rendering, animations, layout geometry, preferences, 16 docklets, and 6-layer identity math. Zero OS, compositor, D-Bus, POSIX, `/proc`, `/sys`, or `.desktop` symbols allowed.
- **Zone 2 — Pure Vala Boundary Translators (`hal/Interfaces/`):** The 7 OS-agnostic contracts and POD structs through which Zone 1 speaks to the outside world. Also guarded by the Purity Firewall (`0` OS or wire-bus leaks).
- **Zone 3 — Concrete Southbound Drivers (`hal/Freedesktop/`, `hal/Linux/`, `hal/BSD/`, and `hal/Windows/`):** The only place in the repository permitted to touch Wayland protocols, compositor bridges, D-Bus, POSIX/BSD/Linux kernel APIs, or Win32/DWM/COM APIs.

### Why Separate `Freedesktop/` from `Linux/` and `BSD/`?
Instead of dumping everything into a single monolithic Unix folder, POSIX desktop drivers are split along the **Userland Desktop Standard vs. OS Kernel** boundary:

1. **`hal/Freedesktop/` (🐧😈 Shared Linux & FreeBSD Userland — Wayland, D-Bus & XDG Standards):** Wayland compositors (`KWin`, `Mutter`, `Wlroots`), `gtk-layer-shell` (`Shell/`), `D-Bus` (`Dbus/`, including dual `systemd-logind` / `ConsoleKit2` session power), and `XDG` `.desktop`/trash/portal specs (`Xdg/`) are **FreeDesktop standards**, not Linux-kernel APIs. Keeping `Freedesktop/` separate lets **Linux** and **FreeBSD** share 100% of `hal/Freedesktop/` while swapping only the kernel layer (`hal/Linux/` $\leftrightarrow$ `hal/BSD/`).
2. **`hal/Linux/` (🐧 Strictly Linux-Kernel & Linux-OS Plumbing — Live on `main`):** Isolates `/proc` (`ProcFs/`), `/sys` + `/dev/i2c-*` DDC/CI + Linux netlink/sysfs network telemetry (`SysFs/`), PipeWire/PulseAudio CLI audio telemetry, and `prctl`/POSIX process lifecycle (`builders/linux/{BuildBin,BuildDeb,BuildRpm}.sh` $\rightarrow$ `build/linux/`).
3. **`hal/BSD/` (😈 Strictly FreeBSD 14.x / 15.x & GhostBSD Kernel Plumbing — Live on `main`, `v0.7.4`):** Native FreeBSD kernel driver layer with **zero `/proc` and zero `/sys`**: `libprocstat(3)` + `sysctl(3)` process/argv/CWD/env/FD/child inspection, `kern.cp_time` CPU + OpenZFS ARC-aware RAM (`kstat.zfs.misc.arcstats`) + `libdevstat(3)` Disk I/O, ACPI `hw.acpi.battery.*`, PipeWire/PulseAudio + native OSS `/dev/mixer*` `ioctl`, `<sys/backlight.h>` + `hw.acpi.video.*` backlight, `getifaddrs`/`SIOCGIFMEDIA`/`IEEE80211_IOC_SSID`/`PF_ROUTE` network telemetry, `setproctitle`/`KERN_PROC_PATHNAME`/`SIGWINCH` hot-reload, and native `/usr/bin/fetch` HTTP (`builders/bsd/{BuildBsd,BuildPkg}.sh` $\rightarrow$ `build/bsd/`).
4. **`hal/Windows/` (🪟 Native Windows `7 ⟷ 11+` Zero-DLL `wayplank.exe` — Live on `main`, `v0.7.3+`):** Plugs Win32, DWM Thumbnails, `IVirtualDesktopManager` (`Workspace Only`), `GA_ROOTOWNER` popup focus retention, `ITaskbarList::DeleteTab`, WinRT GSMTC Media Player, COM Shell Links + UWP/Metro `aumid://` + persistent `.lnk` index cache + `IApplicationDocumentLists` Recent Files, static `lunasvg` SVG loading, and Win32 telemetry directly into `hal/Interfaces/` (`builders/windows/{BuildWin,BuildNsis}.sh` $\rightarrow$ `build/windows/`), bypassing `Freedesktop/`, `Linux/`, and `BSD/` cleanly.

### Why `Wlroots/` Instead of `Labwc/`?
All three compositor subdirectories under `hal/Freedesktop/` are named after the **compositor engine / protocol family** rather than a single desktop or window manager:
- **`KWin/`** (engine behind KDE Plasma, rather than `Plasma/`)
- **`Mutter/`** (engine behind GNOME Shell, rather than `GNOME/`)
- **`Wlroots/`** (protocol family behind **Labwc**, **Sway**, **Wayfire**, **Hyprland**, and **River**, rather than `Labwc/`): houses the shared `zwlr_foreign_toplevel_management_v1` XML/C wire bridge (`wlr-toplevel-bridge.c`) alongside `LabwcBackend.vala`, ready for additional `wlroots` compositors without misnaming their parent directory.

---

## 2. Directory Tree Overview

```text
hal/
├── Interfaces/              # ZONE 2: Pure Vala Contracts & Hal.* Slot Registry (Firewall-Protected)
│   ├── Hal.vala             # Runtime singleton slots (Shell, Windows, Thumbnails, Apps, Runtime, ...)
│   ├── IDockShell.vala      # Surface anchoring, struts, input masks (#34), popup/poof positioning
│   ├── IWindowBackend.vala  # Toplevel enumeration, focus/minimize/close, dodge/fullscreen queries
│   ├── IThumbnailProvider.vala # Live RGBA window preview capture contract
│   ├── IBusBackend.vala     # Single-instance IPC, MPRIS, DND notifications, Unity badges, portals
│   ├── ISystemTelemetry.vala# CPU/RAM/Disk, Battery, Brightness, Audio, Network, Trash, Ejector
│   ├── IPlatformRuntime.vala# Process lifecycle, signals, resume hooks, HTTP, archive & keyfile probes
│   ├── IAppSystem.vala      # Launcher catalog, PID/FD inspection, inotify browser session watch
│   ├── PlatformCapabilities.vala
│   └── WindowInfo.vala
│
├── Freedesktop/             # ZONE 3a (Shared Linux & FreeBSD): Wayland, Layer-Shell, D-Bus & XDG Userland
│   ├── FreedesktopHalBootstrap.vala # Session probe & Hal.* dependency injection at startup
│   ├── Shell/               # GtkLayerShell surface/strut/mask driver & coordinate helper
│   ├── KWin/                # KDE Plasma 6 D-Bus script bridge (transientFor), ScreenShot2 pipe & KIO trash
│   ├── Mutter/              # GNOME Shell auto-deployed JS bridge (v074_bridge_8) & SHM thumbnails
│   ├── Wlroots/             # zwlr_foreign_toplevel_management_v1 C bridge & LabwcBackend
│   ├── Dbus/                # Shared DbusBroker + MPRIS, Unity LauncherEntry, Portals, NetworkManager,
│   │                        # FreedesktopSessionPower (systemd-logind + ConsoleKit2/acpiconf/shutdown)
│   └── Xdg/                 # XdgAppSystem (.desktop/PWA/Chrome sessions), GVFS Trash, Ejector, Autostart
│
├── Linux/                   # ZONE 3b (Linux Kernel Only): /proc, /sys, DDC/CI & PipeWire/ALSA
│   ├── LinuxKernelBootstrap.vala    # Registers Linux kernel providers into FreedesktopHalBootstrap
│   ├── ProcFs/              # LinuxProcessInspector (/proc/<pid>) & LinuxCpuMemDiskTelemetry
│   ├── SysFs/               # LinuxSysfsBacklight (/sys + DDC/CI), LinuxBatteryProvider, LinuxNetworkTelemetry
│   ├── LinuxAudioTelemetry.vala
│   └── LinuxPlatformRuntime.vala
│
├── BSD/                     # ZONE 3c (FreeBSD 14.x/15.x & GhostBSD Kernel — Zero /proc, Zero /sys)
│   ├── BsdKernelBootstrap.vala      # Registers FreeBSD kernel providers into FreedesktopHalBootstrap
│   ├── bsd-kernel-bridge.{c,h}      # Native C bridge: libprocstat, sysctl, OpenZFS ARC, libdevstat,
│   │                                # OSS /dev/mixer*, <sys/backlight.h>, getifaddrs/IEEE80211/PF_ROUTE
│   ├── BsdProcessInspector.vala     # libprocstat(3)/sysctl(3) argv, exe, CWD, env, FDs & child PIDs
│   ├── BsdCpuMemDiskTelemetry.vala  # kern.cp_time CPU, OpenZFS ARC-aware RAM & libdevstat Disk I/O
│   ├── BsdBatteryProvider.vala      # hw.acpi.battery.* & hw.acpi.acline telemetry
│   ├── BsdBacklight.vala            # <sys/backlight.h> & hw.acpi.video.* brightness control
│   ├── BsdAudioTelemetry.vala       # PipeWire/PulseAudio CLI with native OSS /dev/mixer* ioctl fallback
│   └── BsdPlatformRuntime.vala      # setproctitle(3), KERN_PROC_PATHNAME, SIGWINCH & /usr/bin/fetch
│
└── Windows/                 # ZONE 3d: Native Windows 7..11+ Drivers (builders/windows/ -> build/windows/)
    ├── WindowsHalBootstrap.vala  # Win32 Hal.* binder, embedded gschemas.compiled extractor & CommandLineToArgvW
    ├── win32-svg-loader.cpp      # Built-in static lunasvg SVG loader compiled into libgdk_pixbuf-2.0.a
    ├── wayplank.ico / wayplank.rc / wayplank.manifest # 7-res icon, Per-Monitor V2 HiDPI manifest & PE metadata
    ├── Compositor/               # win32-bridge.{c,h} (GA_ROOTOWNER, IVirtualDesktopManager), Win32Backend, Win32Shell, Win32ThumbnailProvider
    ├── AppSystem/                # win32-app-bridge.{c,h}, Win32AppSystem (.lnk cache, AUMID/UWP, winico:, Explorer icons)
    ├── Bus/                      # win32-media-bridge.{c,h} (WinRT GSMTC), Win32BusBroker, Win32AppMenuBus
    └── Telemetry/                # win32-sys-bridge.{c,h}, Win32Telemetry (CoreAudio, WMI/DXVA2, Network, Recycle Bin, Ejector, WinHTTP)
```
