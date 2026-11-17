# WayPlank Hardware & OS Abstraction Layer (`hal/`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Canonical Architecture Specs:** [`Documentation/Architecture/README.md`](../Documentation/Architecture/README.md) · [`HAL_COMPOSITORS.md`](../Documentation/Architecture/HAL_COMPOSITORS.md) · [`HAL_BUSES.md`](../Documentation/Architecture/HAL_BUSES.md) · [`APPLICATION_IDENTITY_ENGINE.md`](../Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md) · [`HAL_WINDOWS_BACKEND.md`](../Documentation/Architecture/HAL_WINDOWS_BACKEND.md)

---

## 1. Why `hal/` Is Cataloged This Way

WayPlank enforces a strict **3-Zone Dichotomic Architecture** verified at every build by the pre-compile **Dual-Zone HAL Purity Firewall** (`BuildBin.sh`):

- **Zone 1 — Agnostic Core (`src/`, `lib/`, `vapi/core/`):** Pure dock rendering, animations, layout geometry, preferences, and 6-layer identity math. Zero OS, compositor, D-Bus, POSIX, `/proc`, `/sys`, or `.desktop` symbols allowed.
- **Zone 2 — Pure Vala Boundary Translators (`hal/Interfaces/`):** The 7 OS-agnostic contracts and POD structs through which Zone 1 speaks to the outside world. Also guarded by the Purity Firewall (`0` OS or wire-bus leaks).
- **Zone 3 — Concrete Southbound Drivers (`hal/Freedesktop/`, `hal/Linux/`, and future `hal/Windows/`, `hal/BSD/`):** The only place in the repository permitted to touch Wayland protocols, compositor bridges, D-Bus, POSIX APIs, or kernel filesystems.

### Why Separate `Freedesktop/` from `Linux/`?
Instead of dumping everything into a single monolithic `linux/` folder, POSIX desktop drivers are split along the **Userland Desktop Standard vs. OS Kernel** boundary:

1. **`hal/Freedesktop/` (Userland Desktop, Wayland & IPC Standards):** Wayland compositors (`KWin`, `Mutter`, `Wlroots`), `gtk-layer-shell` (`Shell/`), `D-Bus` (`Dbus/`), and `XDG` `.desktop`/trash/portal specs (`Xdg/`) are **FreeDesktop standards**, not Linux-kernel APIs. Separating `Freedesktop/` allows non-Linux POSIX desktops (such as **FreeBSD** running KDE Plasma or Labwc) to reuse 100% of `hal/Freedesktop/` while only swapping `hal/Linux/` for `hal/BSD/`.
2. **`hal/Linux/` (Strictly Linux-Kernel & Linux-OS Plumbing):** Isolates `/proc` (`ProcFs/`), `/sys` + `/dev/i2c-*` DDC/CI (`SysFs/`), `systemd-logind` session power, PipeWire/PulseAudio CLI telemetry, and `prctl`/POSIX process lifecycle.
3. **Future `hal/Windows/` (`v0.7.3` Zero-DLL `wayplank.exe`):** Plugs Win32, DWM Thumbnails, UIAutomation, COM Shell Links, and WMI directly into `hal/Interfaces/` (`BuildWin.sh`), bypassing both `Freedesktop/` and `Linux/` with zero edits to Zone 1 or Zone 2.

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
├── Freedesktop/             # ZONE 3a: Wayland Compositors, Layer-Shell, D-Bus & XDG Userland
│   ├── FreedesktopHalBootstrap.vala # Session probe & Hal.* dependency injection at startup
│   ├── Shell/               # GtkLayerShell surface/strut/mask driver & coordinate helper
│   ├── KWin/                # KDE Plasma 6 D-Bus script bridge, ScreenShot2 pipe & KIO trash bridge
│   ├── Mutter/              # GNOME Shell auto-deployed JS bridge (v072_bridge_2) & SHM thumbnails
│   ├── Wlroots/             # zwlr_foreign_toplevel_management_v1 C bridge & LabwcBackend
│   ├── Dbus/                # Shared DbusBroker + MPRIS, Unity LauncherEntry, Portals, NetworkManager
│   └── Xdg/                 # XdgAppSystem (.desktop/PWA/Chrome sessions), GVFS Trash, Ejector, Autostart
│
└── Linux/                   # ZONE 3b: Linux Kernel & OS-Specific Drivers
    ├── ProcFs/              # /proc/<pid> cmdline/environ/FD inspector & /proc CPU/RAM/Disk telemetry
    ├── SysFs/               # /sys/class/backlight + DDC/CI BrightnessControl & /sys power_supply Battery
    ├── LinuxAudioTelemetry.vala
    ├── LinuxSessionPower.vala
    └── LinuxPlatformRuntime.vala
```
