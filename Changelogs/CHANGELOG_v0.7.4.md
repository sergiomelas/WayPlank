# WayPlank V0.7.4 (Public Beta 5 — Native FreeBSD Kernel Backend `hal/BSD/`, Multi-OS Parity & Unified 3-OS Delivery) Detailed Technical Changelog

> [!NOTE]
> **✅ ISA-88 QUALIFICATION STATUS: `v0.7.4` PUBLIC BETA 5 — 100.0% 5-PLATFORM QUALIFIED & FROZEN (`661/661`, `0 [ko]` — `2026-11-23`)**  
> `v0.7.4` extends the `100.0%` 4-platform qualified **`v0.7.3.2`** baseline ([`FAT/2026-11-22 FAT 0.7.3.txt`](../FAT/2026-11-22%20FAT%200.7.3.txt), `529/529`) with the native **FreeBSD 14.x / 15.x & GhostBSD** kernel driver layer (**`hal/BSD/`**, `MOC-0.7.4-BSD-001`), capability-driven multi-OS **`Workspace Only`** filtering, multi-OS priority **Network Docklet** with live 1s RX/TX throughput, universal **Folder `Change Icon...`** parity, HiDPI Preferences Docklets icons, atomic GNOME Mutter monitor switching + native `xdg_popup` crash protection (`v074_bridge_7`), one-click `OK` cleanup of stale internal `.dockitem` files, and unified **`builders/{linux,bsd,windows}/` ➔ `build/{linux,bsd,windows}/`** delivery across all 3 operating systems.  
> Frozen FAT Protocol: [`FAT/2026-11-22 FAT 0.7.4.txt`](../FAT/2026-11-22%20FAT%200.7.4.txt) (**`675` tests defined / `661` applicable — `661/661` (`100.0%`) PASSED**: `653 [ok]` + `8 [ko->ok]` across `3` unique defect IDs `1.10`, `2.6`, `15.6`; `14 [NA]`, `0 [ko]` — **FreeBSD 15.1 `132/132` [Labwc + KWin + GNOME]**, **Windows 11 `136/136`**, **GNOME Linux `133/133`**, **KDE Plasma 6 Linux `133/133`**, **Labwc Linux `127/127`**).

Release Series: **V0.7.x Series (Final Public Beta before `v0.8.x` RC Feature Freeze)**  
Current Milestone: **V0.7.4 (Public Beta 5 — Native FreeBSD Kernel Backend `hal/BSD/`, Multi-OS Parity & Unified 3-OS Packaging)**  
Status: **CONCLUDED & FROZEN — `100.0%` 5-Platform Qualified (`661/661` Passed, `0 [ko]`, 8/8 HAL Purity Firewall GREEN on Linux & FreeBSD, Zero-DLL Gate GREEN at 25 Stock OS DLLs on Windows)**  
Maintainer: **Sergio Melas** (sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))  
Architecture References:
- [`Documentation/Architecture/HAL_BSD_BACKEND.md`](../Documentation/Architecture/HAL_BSD_BACKEND.md) (`DOC-ARCH-BSD-006`)
- [`Documentation/Architecture/HAL_LINUX_BACKEND.md`](../Documentation/Architecture/HAL_LINUX_BACKEND.md) (`DOC-ARCH-LIN-007`)
- [`Documentation/Architecture/HAL_WINDOWS_BACKEND.md`](../Documentation/Architecture/HAL_WINDOWS_BACKEND.md) (`DOC-ARCH-WIN-005`)
- [`Documentation/Architecture/README.md`](../Documentation/Architecture/README.md) (`DOC-ARCH-MASTER-001`)
- [`Documentation/Architecture/HAL_COMPOSITORS.md`](../Documentation/Architecture/HAL_COMPOSITORS.md) (`DOC-ARCH-COMP-002`)
- [`Documentation/Architecture/HAL_BUSES.md`](../Documentation/Architecture/HAL_BUSES.md) (`DOC-ARCH-BUS-003`)
- [`Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md`](../Documentation/Architecture/APPLICATION_IDENTITY_ENGINE.md) (`DOC-ARCH-ID-004`)

---

## 1. 😈 Native FreeBSD Kernel Backend (`hal/BSD/`, `MOC-0.7.4-BSD-001` — Milestones `B1`–`B5`)

- **Zero `/proc`, Zero `/sys`, 100% Reuse of Zone 1 Core & `hal/Freedesktop/`:**
  - Plugs native FreeBSD 14.x / 15.x & GhostBSD kernel drivers (`hal/BSD/bsd-kernel-bridge.{c,h}`, `vapi/bsd/bsd-kernel-bridge.vapi`, `hal/BSD/BsdKernelBootstrap.vala`) directly behind the `14` C link-seam exports (`wayplank_hal_kernel_*`) consumed by `hal/Freedesktop/`, reusing 100% of Zone 1 Core, Zone 2 Translators, `KWin`, `Mutter`, `Labwc / wlroots`, `gtk-layer-shell`, D-Bus, and `XdgAppSystem`.
  - **Process & Identity (`16.2`):** Native `libprocstat(3)` + `sysctl(3)` (`KERN_PROC_ARGS`, `KERN_PROC_PATHNAME`, `KERN_PROC_ENV`, `KERN_PROC_FILEDESC`, child traversal) with zero `/proc`.
  - **System Telemetry (`16.3`, `16.4`, `16.5`):** `kern.cp_time` CPU, **OpenZFS ARC-aware RAM** (`kstat.zfs.misc.arcstats` reclaimable accounting), `libdevstat(3)` Disk I/O, ACPI `hw.acpi.battery.*`, PipeWire/PulseAudio + native OSS `/dev/mixer*` `ioctl`, `<sys/backlight.h>` + `hw.acpi.video.*` backlight, `getifaddrs` (`AF_LINK` 64-bit `ifi_ibytes`/`ifi_obytes`) + `SIOCGIFMEDIA` / `SIOCG80211` + `PF_ROUTE` default-gateway network telemetry, `ConsoleKit2` / `acpiconf` / `shutdown` session power, `/usr/bin/fetch` weather HTTP, and `setproctitle` / `KERN_PROC_PATHNAME` / `SIGWINCH` hot-reload.
  - **Native FreeBSD Build & `.pkg` Packaging (`16.1`, `16.6`):** [`builders/bsd/BuildBsd.sh`](../builders/bsd/BuildBsd.sh) (8/8 HAL Purity Firewall `GREEN` + `llvm-objdump` `0` Pitfall #14 UAFs) and [`builders/bsd/BuildPkg.sh`](../builders/bsd/BuildPkg.sh) (`pkg create` ➔ [`build/bsd/wayplank-0.7.4.pkg`](../build/bsd/wayplank-0.7.4.pkg) installing cleanly under `/usr/local`).
  - **3-Compositor Live Verification on FreeBSD 15.1-RELEASE-p6:** Certified live across **Labwc `0.20.2`**, **KDE Plasma `6.7.5` / KWin Wayland**, and **GNOME Shell `47.10` / Mutter Wayland** (including dual concurrent docks and Breeze Light ↔ Breeze Dark live theme switching).

---

## 2. 🌐 Multi-OS Priority Network Docklet, Live 1s RX/TX & Embedded 4-Arc Wi-Fi SVGs (`FAT 6.13`, `14.4`)

- **Zone 2 Contract (`hal/Interfaces/ISystemTelemetry.vala`):** Added `NetworkInterfaceInfo` (`iface_id`, `display_name`, `kind` = `"wifi"|"ethernet"|"virtual"`, `wifi_strength`, `ip_address`, `gateway`, `rx_bytes`, `tx_bytes`) and `INetworkProvider.list_interfaces_sync ()` (+ `NullNetworkProvider`).
- **3-OS Southbound Drivers:**
  - **Linux (`hal/Linux/SysFs/LinuxNetworkTelemetry.vala`):** `/sys/class/net` (`/device` physical vs virtual discrimination + 64-bit `statistics/{rx,tx}_bytes`) + libc `getifaddrs` + `/proc/net/{route,wireless}` + NetworkManager D-Bus `ActiveConnections` enrichment.
  - **FreeBSD (`hal/BSD/bsd-kernel-bridge.c`):** `getifaddrs` (`AF_LINK` `ifi_ibytes`/`ifi_obytes` + `AF_INET`), `SIOCGIFMEDIA`/`SIOCG80211`, and `PF_ROUTE` gateway interface matching.
  - **Windows (`hal/Windows/Telemetry/win32-sys-bridge.c`):** `GetAdaptersAddresses` + dynamic `GetIfEntry2` (64-bit `InOctets`/`OutOctets`) + `wlanapi.dll` per-adapter GUID signal lookup + virtual adapter filtering (`VMware`/`VMnet`/`VirtualBox`/`Hyper-V`/`WSL`/`WireGuard`/`TAP`/`VPN`).
- **Zone 1 UI & Haptic-Kore Embedded SVGs (`lib/Items/NetworkDockItem.vala`, `data/docklets/network*.svg`):**
  - Strict interface priority: **1. Wi-Fi** (`>=85%` 4/4, `60–84%` 3/4, `35–59%` 2/4, `10–34%` 1/4, `<10%` 0/4) ➔ **2. Physical Ethernet** (default gateway first) ➔ **3. Virtual**.
  - Replaced legacy teal-circle SVGs with crisp standalone 4-arc Wi-Fi signal SVGs (`#333333` + `fill-opacity="0.3"`, zero `currentColor` for 100% `lunasvg` Windows parity) plus dedicated `network-wired.svg` and `network-virtual.svg` (bringing embedded SVGs to **`107`** and 8-language translations to **`581/581`**).
  - Right-click menu displays all active interfaces with live 1-second `↓ RX / ↑ TX` throughput updates (`map`/`unmap`/`destroy` lifecycle + `GLib.WeakRef`), single-row click copies that interface's IP, and `Copy IP Address` / middle-click copies all active IPs labeled by network name (`Name: IP`).

---

## 3. ✨ Cross-OS Feature Parity, Hardening & Squashed Live Defects (`8 [ko->ok]`)

- **Capability-Driven `Workspace Only` Filtering (`FAT 7.13`):** Active on **KWin**, **Mutter**, and **Windows 10/11+** (COM `IVirtualDesktopManager`), with honest disabled switch + dynamic protocol-explanation tooltips on **Labwc / wlroots** and **Windows 7/8**.
- **Universal Folder `Change Icon...` Parity (`FAT 1.10` — `[ko->ok]` across all 5 platforms):** Unified `CustomIconService.vala` persisting custom folder and app icons cleanly across Linux, FreeBSD, and Windows.
- **HiDPI Preferences Docklets Selector Icons (`FAT 7.8`):** Replaced fixed `35×35` icon loading in `PreferencesWindow.ensure_docklet_icon()` with HiDPI `DrawingService.load_icon (spec, 36 * scale, 36 * scale)` + `Gdk.cairo_surface_create_from_pixbuf` matching live docklet visuals identically across all 3 OSes.
- **Windows Context Menu `Preferences...` Stock Icon Fix (`FAT 15.6` — `[ko->ok]` on Windows):** Removed broken `SIID_SETTINGS` (`106`) mapping in `Win32AppSystem.map_stock_icon_id()` so Windows context menus render the crisp embedded `settings-gear.svg`.
- **GNOME Mutter Atomic Monitor-Switch & Native `xdg_popup` Crash Fix (`v074_bridge_6` ➔ `v074_bridge_7`, `FAT 2.6` — `[ko->ok]` on FreeBSD & GNOME Linux):**
  - Replaced sequential `move_frame` + `move_resize_frame` in `_applyDockPosition` / `_applyPoofPosition` with a single atomic `win.move_resize_frame(true, targetX, targetY, width, height)`.
  - Guarded `_classifyWindow(win)` in `hal/Freedesktop/Mutter/MutterBackend.vala` so native GTK3 `xdg_popup`s (`Gtk.Menu` / `Gtk.ComboBox`: untitled/role-less or `POPUP_MENU`/`DROPDOWN_MENU`/`MENU`/`TOOLTIP`/`COMBO`/`override_redirect`) return `'unknown'` instead of falling through to `'dialog'`, eliminating `activate()`/`_centerWindow()` calls on `xdg_popup`s that caused `MetaStack` Use-After-Free `SIGSEGV` on Mutter 47.
- **One-Click `OK` Cleanup of Stale Internal `.dockitem` Files (`FAT 7.17`):** Preserves 100% non-destructive disk immunity at startup (`#33`, all 9 `Test environments.sh` profiles untouched on disk), while clicking **`OK`** on the `Load environment failed` dialog now safely removes discarded corrupted/orphan `.dockitem` files inside `launchers_folder`, strips them from `DockItems` lists, and flushes clean `latch-state.ini` so users never get stuck in an infinite startup warning loop (closing via `X` leaves disk untouched).
- **Zoom-Consistent Master `SurfaceCache` & Exact XDG Category Tokens (`FAT 7.4`, `1.9`):** Unified master-resolution icon scaling across zoom transitions and tightened Explorer smart-folder XDG category token matching.

---

## 4. 📦 Unified 3-OS Delivery Pipeline (`builders/{linux,bsd,windows}/` ➔ `build/{linux,bsd,windows}/`)

All 7 release deliverables built cleanly from a single unified repository tree (`581/581` 8-language translations, `107` embedded SVGs, `8/8` HAL Purity Firewall `GREEN`, `0` Pitfall #14 UAFs, `25` evergreen Windows OS DLLs only):
- **Linux (`build/linux/`):** `wayplank` (`14M`), `wayplank_0.7.4_amd64.deb` (`4.9M`), `wayplank-0.7.4-1.x86_64.rpm` (`3.4M`)
- **FreeBSD (`build/bsd/`):** `wayplank` (`13M`), `wayplank-0.7.4.pkg` (`4.9M`)
- **Windows (`build/windows/`):** `wayplank.exe` (`24M`), `WayPlank-0.7.4-Setup.exe` (`8.9M`)
