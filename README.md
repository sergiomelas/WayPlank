# WAYPLANK: THE ROAD TO WAYLAND DOCK

> Standalone, Monolithic Fork of Plank for Wayland
>
> Laying the Groundwork for Native Wayland Architecture
>
> Developed by Sergio Melas (sergiomelas@gmail.com) © 2026
>
> [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
> [![Release: v0.5.2 Alpha](https://img.shields.io/badge/Release-v0.5.2%20Alpha-orange.svg)](Changelogs/CHANGELOG_v0.5.2.md)

![Wayplank v0.5.2 Release Banner](Release%20Pic.png)

---

🚀 CURRENT RUNTIME: Full Wayland with KWin, Labwc (wlroots) & GNOME (Mutter) support | 🎯 MILESTONE: First Official Alpha Release (v0.5.2)

---

## 📢 Current Status

I developed the core engine to discover running applications (since Wayland isolates and segregates window introspection by design) based on process list matching against the content of user and system `.desktop` files. To overcome the challenges of Wayland security boundaries, I utilized AI assistance during early prototyping. The codebase has undergone comprehensive human review, bug hunting, and code purging for high performance and stability.

Important notice: while the core dock rendering and layout inherit the beloved look and feel from the original Plank developers (Docky Core Team), Wayplank has evolved significantly: between v0.1.0 and v0.5.1, over **12,400 lines of new code were introduced** (+49% of the active codebase) and **3,875 lines of legacy X11 infrastructure were purged**. Today, **roughly 50% of the active codebase represents modern native Wayland architecture** (our modular Multi-Compositor HAL for KWin, Labwc, and GNOME/Mutter, asynchronous D-Bus IPC bridges, embedded docklets, Layer Shell anchoring, and multi-monitor geometry tracking), while the remaining ~50% preserves Plank's rock-solid Cairo rendering pipeline.

Having used KDE with Plank for years, Wayplank provides a true native Wayland successor as X11 phases out. Starting with version 0.4.3, Wayplank features a modular Hardware Abstraction Layer (HAL) with native support for **KWin (KDE Plasma)**, **Labwc (wlroots)**, and **GNOME Shell (Mutter)** compositors! Testing and feedback across different Wayland environments are warmly welcome.

👉 *For the complete technical migration report, please refer to [`Documentation/wayplank_x11_to_wayland_report_en.md`](Documentation/wayplank_x11_to_wayland_report_en.md).*  
👉 *For the complete Factory Acceptance Test (FAT) protocols and test matrix across compositors, see [`FAT/`](FAT/).*  
👉 *For detailed technical changelogs for each release milestone, see [`Changelogs/`](Changelogs/).*

### ⚠️ Reality Check: Where Wayplank Stands Today

To be completely transparent: **Wayplank is fully Wayland-native, with window-management and dock integration tested and verified on KWin (KDE Plasma), Labwc (wlroots), and GNOME Shell (Mutter)**. Support for additional compositors (Sway, Hyprland) is progressing along the roadmap.

### 🔍 Keep an Eye on This Repository!

If you are waiting for a true, lightweight, native Wayland dock experience to replace Plank without bloated desktop dependencies:
**Bookmark this repo and watch our releases.** This is the active launchpad where the transition to modern protocols (and our upcoming Qt backend migration) is taking place step-by-step. Community feedback, architecture testing, and PRs are warmly welcome!

---

> WARNING & DISCLAIMER:
>
> DEVELOPED FOR EXPERIMENTAL AND ADVANCED DESKTOP INTEGRATION PROFILES
>
> We assume no responsibility for errors or omissions in the software or documentation available. In no event shall we be liable to you or any third parties for any special, punitive, incidental, indirect or consequential damages of any kind, or any damages whatsoever, including, without limitation, those resulting from loss of use, data or configurations, and on any theory of liability, arising out of or in connection with the use of this software.

---

# Universal Build & Installation Guide (Any Linux Distribution)

## 1. CORE DEPENDENCIES

To compile Wayplank from source, ensure your distribution provides the required development libraries:

- Vala compiler (`valac >= 0.40`)
- GTK+ 3.0 development headers (`gtk3` / `libgtk-3-dev`)
- GTK Layer Shell (`gtk-layer-shell` / `libgtk-layer-shell-dev`)
- Wayland Client library (`wayland` / `libwayland-client0` / `libwayland-dev`)
- JSON-GLib 1.0 (`json-glib` / `libjson-glib-dev`)
- LibGee 0.8 (`libgee` / `libgee-0.8-dev`)
- GLib 2.0 (`glib2` / `libglib2.0-dev`, includes `glib-compile-resources`)
- `pkg-config` / `base-devel` / `build-essential`

**Quick Install Commands:**
- **Arch Linux:**
  ```bash
  sudo pacman -S --needed base-devel vala gtk3 gtk-layer-shell wayland json-glib libgee glib2
  ```
- **Debian / Ubuntu:**
  ```bash
  sudo apt install build-essential valac libgtk-3-dev libgtk-layer-shell-dev libwayland-dev libjson-glib-dev libgee-0.8-dev libglib2.0-dev
  ```
- **Fedora:**
  ```bash
  sudo dnf install gcc vala gtk3-devel gtk-layer-shell-devel wayland-devel json-glib-devel libgee-devel glib2-devel
  ```

---

## 2. COMPILATION

### Option A: Universal Automated Build Script (Recommended for Any Distro)

Wayplank includes an automated standalone build script that compiles all Vala sources, C bridges, and GLib resources directly without distribution-specific dependencies:

```bash
chmod +x BuildBin.sh
./BuildBin.sh
```

The resulting standalone binary is generated in `build/wayplank`.

---

### Option B: Manual Step-by-Step Compilation

If you prefer building manually in your terminal:

```bash
# Step 1: Compile embedded GLib resources
glib-compile-resources --sourcedir=data --target=lib/resources.c --generate-source data/plank.gresource.xml

# Step 2: Compile native Wayplank binary (Vala + C bridges)
valac -g \
    --gresources=data/plank.gresource.xml \
    --gresourcesdir=data \
    --vapidir=vapi \
    --pkg posix --pkg gio-unix-2.0 --pkg gtk+-3.0 --pkg gtk-layer-shell-0 \
    --pkg json-glib-1.0 --pkg gee-0.8 --pkg compat --pkg config --pkg wlr-bridge \
    -X -D_GNU_SOURCE -X "-Dsetproctitle(x)=" \
    -X -DGETTEXT_PACKAGE=\"wayplank\" \
    -X -Ilib -X -Ilib/Protocols -X -Ilib/Services -X -Iinclude -X -w -X -lm -X -lwayland-client \
    $(find lib src -name "*.vala") \
    lib/resources.c \
    lib/gtk-compat.c \
    lib/Protocols/wlr-foreign-toplevel-management-protocol.c \
    lib/Services/wlr-toplevel-bridge.c \
    -o wayplank
```

---

### Step 3: Install Binary and Desktop Assets

Once built (via Option A or Option B), install the binary, themes, icons, and GSettings schemas:

```bash
# Install binary into /usr/local/bin
[ -f build/wayplank ] && sudo install -Dm755 build/wayplank /usr/local/bin/wayplank || sudo install -Dm755 wayplank /usr/local/bin/wayplank
sudo ln -sf /usr/local/bin/wayplank /usr/local/bin/plank

# Install themes and icons
sudo mkdir -p /usr/local/share/wayplank/themes
sudo cp -r data/themes/* /usr/local/share/wayplank/themes/
sudo cp -r data/icons/* /usr/local/share/icons/hicolor/

# Install and compile GSettings schemas
sudo cp data/glib-2.0/schemas/* /usr/local/share/glib-2.0/schemas/
sudo glib-compile-schemas /usr/local/share/glib-2.0/schemas/
```

---

## 3. AUTOMATED DEBIAN/UBUNTU PACKAGE CREATION

If running Debian, Ubuntu, or derivative distributions, run the automated packager to create a native `.deb`:

```bash
chmod +x BuildDeb.sh
./BuildDeb.sh
sudo dpkg -i build/wayplank_0.5.2_amd64.deb
```

---

# RUNTIME DIRECTORIES & CONFIGURATION MIGRATION

Wayplank operates under its own isolated namespace and standard XDG locations:

- Configuration Directory: `~/.config/wayplank/`
- Application Launchers: `~/.config/wayplank/dock1/launchers/`
- Local User Themes: `~/.local/share/wayplank/themes/`
- System Themes: `/usr/share/wayplank/themes/` (or `/usr/local/share/wayplank/themes/`)

**Theme Configuration:**
Wayplank inspects both system and user theme paths natively. To change dock appearance:

```bash
wayplank --preferences
```

**Debug & Verbose Logging:**
To inspect running window hooks and debug output:

```bash
wayplank -d
```

---

# PROJECT ROADMAP & THE WAYLAND MILESTONES

- [x] Phase 1 (Completed) v0.1.0: Decoupled Standalone Fork
  - [x] Complete breakaway from unmaintained upstream Plank.
  - [x] Full namespace migration to 'wayplank' (configs, directories, launchers).
  - [x] Modern monolithic build system replacing broken autotools/autogen scripts.
  - [x] Multi-distro compatibility and standalone Debian packaging pipeline.

- [x] Phase 2 (Completed) v0.2.0: Application Discovery and Dock Lifecycle
  - [x] Implemented generic application discovery from running processes and desktop files.
  - [x] Added persistent pinned application handling and temporary running application icons.
  - [x] Implemented running-instance marking and multi-instance application management.

- [x] Phase 3 (Completed) v0.3.0: Declaration of Independence from X11 & Native Wayland Integration
  - [x] Implementation of Wayland native protocols.
  - [x] Complete phasing out of X11/XWayland dependencies. Support one compositor.
    This will be Kwin because it is the one I know the best.
  - [x] Full fractional scaling and native Wayland compositor window tracking.

- [x] Phase 4 (Completed) v0.4.0, v0.4.1, v0.4.2: KWin Stabilization, Monolithic Docklets & Bug Fixes
  - [x] Hardened KWin scripting bridge, overlap detection, and multi-monitor tracking.
  - [x] Implemented 8 embedded monolithic docklets (Trash, Clocks, Battery, CPU/RAM, Show Desktop, MPRIS, Volume).
  - [x] Bi-directional KWin & Plasma D-Bus trash bridge synchronization.
  - [x] Resolved icon bounce regressions, portal file launching, and process replacement (`--replace` / `-r`).

- [x] Phase 5 (Completed) v0.4.3: Multi-Compositor HAL & Support for Other Compositors (Labwc, wlroots, Mutter)
  - [x] Defined and implemented the modular Hardware Abstraction Layer (`WindowBackend` / `WindowControl`).
  - [x] Added native Labwc & wlroots support via `zwlr_foreign_toplevel_manager_v1` protocol and C bridge (v0.4.3).
  - [x] Zero-configuration runtime dynamic compositor auto-probing (Labwc vs KWin vs Mutter).
  - [x] Reactive Cairo indicator dots and cross-compositor Show Desktop toggle engine.
  - [x] State-based Dodge & Honest UI Matrix for Labwc (`DODGE_MAXIMIZED`, UI filtering, transparent fallback; validated on LXQt 2.x and XFCE 4.20).
  - [x] Native GNOME Shell / Mutter bridge integration (Phase 1): monolithic self-deploying GNOME Shell extension via D-Bus (`MutterBackend`), window state tracking, zero-notification banners, centered dialogs, and edge positioning (v0.4.3).
  - [x] Strict HAL coordinate isolation: native Layer Shell margins for KWin/Labwc and dedicated absolute screen positioning for Mutter (v0.4.3).
  - [x] Finalize GNOME Shell extension bridge for window geometry retrieval to support Intellihide & Dodge on Mutter.

- [ ] Phase 6 (Ongoing) v0.5,..,v0.9: Move to Maintenance and Bugfixing
  - [x] Multi-monitor selection persistence and edge placement fine-tuning across all compositors. 
  - [x] Native Session & Power Management Docklet (v0.5.2): Multi-compositor power controls (Logout, Switch User, Restart, Shutdown, Lock, Suspend) and centered GTK session dialog.
  - [x] Dedicated Preferences Docklet (v0.5.2): One-click docklet launcher for Wayplank Preferences.
  - [x] Finish documentation, packaging, and configuration migration.
  - [ ] After release, focus on bug fixes and compatibility updates.
  - [ ] Broaden community testing across additional wlroots compositors (Sway, Hyprland, Wayfire).

- [ ] Phase 7 (Final) v1.0.0: Publish Version 1.0 as first stable
  - [ ] Publish Version 1.0 with a clear list of supported compositors.
  - [ ] After release, focus on bug fixes and compatibility updates.
---

# Change log

## V0.5.2 (First Alpha Release): 2026-10-09

> 📢 **FIRST OFFICIAL ALPHA RELEASE & FINAL MASS DEVELOPMENT MILESTONE**:  
> Version **V0.5.2 marks the first official ALPHA release** and the conclusion of the "Mass Development" phase of Wayplank! The core foundation (Multi-Compositor HAL for KWin, Labwc, and Mutter; native Layer Shell integration; 11 monolithic docklets; self-contained binary fallback architecture; and deep crash/leak hardening) is now fully established and rock-solid.  
> **From this point forward, Wayplank transitions to a user-driven maintenance phase: all future changes, enhancements, and new features will be developed exclusively upon user requests, bug reports, and community feedback.**

**Native Session & Power Management Docklet, Preferences Docklet & 100% Internal Fallbacks**:
- **(Cross-Compositor) Embedded Session Docklet (`docklet://session`)**: Added native docklet providing instant desktop session and power management (Lock Screen, Switch User, Log Out, Suspend, Restart, Shut Down) with multi-fallback vector icon resolution.
- **(Cross-Compositor) Centered GTK Session Dialog (`SessionWindow`)**: Interactive centered dialog with current user/host banner, 6 ergonomic action buttons, and smooth in-place `GtkStack` confirmation transitions for Logout, Restart, and Shutdown (Escape to step back/dismiss, Cancel default-focused).
- **(KDE Plasma 6 / KWin) Modernized Session & DisplayManager IPC**: Solved `UnknownMethod: openSwitchUser in KSMServer` by integrating `org.freedesktop.DisplayManager.Seat.SwitchToGreeter`; stabilized native shutdown/reboot via direct `systemctl` / `loginctl` / `login1` dispatching (bypassing Plasma 6's `KWin failed to complete logout` bug) and `loginctl lock-session`.
- **(Cross-Compositor) Dedicated Preferences Docklet (`docklet://preferences`)**: Added native one-click docklet styled with the classic Plank anchor icon (`plank` / `wayplank`); right-click context menu provides instant deep-linking into all 4 preferences sections (*Appearance...*, *Behaviour...*, *Applications...*, *Docklets...*), followed by a visual separator.
- **(Preferences) Docklets Tab & Context Menu Integration**: Added "Session / Power" and "Preferences" toggle switches in Preferences Docklets grid, equipped all 11 docklet switches with native 35px vector icons, and added entries to Plank dock item catalog.
- **(Docklets / UI) Digital Clock Visual Fix**: Resolved visual duplication where Digital Clock showed an analog dial; Digital Clock now renders a crisp, dedicated digital tile icon with numerals (`org.kde.plasma.digitalclock` / `digital-clock.svg`).
- **(Architecture / Portability) 100% Self-Contained Binary GResources**: Embedded complete vector fallback icons for all 11 docklets directly inside the `wayplank` executable (`/net/launchpad/plank/docklets/`), including full dynamic volume scale (muted, low, medium, high), full battery scale (12 levels & charging states), trash states, and MPRIS controls. Zero host filesystem pollution, ensuring universal standalone operation on any Linux distro.
- **(Licensing) GPL-3.0 Compliance & Integrated Asset Attribution**: All integrated fallback assets and codebase are fully documented and licensed under GPL-3.0-or-later / LGPL-3.0-or-later.
- **Release status**: 100% PASS on multi-compositor FAT validation protocol across GNOME, KDE Plasma, and Labwc; see FAT status: [`FAT/2026-10-09 FAT 0.5.2.txt`](FAT/2026-10-09%20FAT%200.5.2.txt).

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.5.2.md`](Changelogs/CHANGELOG_v0.5.2.md).

## V0.5.1: 2026-10-08

**KWin Resume Event Storm Hotfix & QTimer Debouncing**:
- **(KWin) Event Loop Starvation Hotfix**: Fixed a severe compositor freeze in KDE Plasma 6.x upon system resume from sleep where KWin server-side decorations (title bars, window movement, minimize/maximize buttons) stopped responding while client windows remained interactive.
- **(KWin) 50ms QTimer Single-Shot Debounce**: Replaced direct, synchronous `sendWindowState()` invocations across rapid window geometry and desktop signals with an asynchronous 50ms debounced queue in `KWinBridge.vala`.
- **(KWin) Zombie Script & Shortcut Collision Prevention**: Added `isScriptLoaded` check in `KWinBridge.handle_system_resume()`; preserves existing script instances across system sleep instead of re-registering duplicate scripts and colliding with `kglobalaccel`.
- **(KWin) Dock Self-Filtering**: Excluded Wayplank's own surface from KWin script signal connections to prevent circular window state emissions.
- **(Cross-Compositor: KWin / Mutter / Labwc) Screenshot Docklet (`docklet://screenshot`)**: Added native built-in Screenshot docklet supporting instant interactive rectangular capture on click and multi-mode capture (Area, Fullscreen, Window, Open Screenshots folder) across KDE Spectacle, GNOME Screenshot, Labwc/Grim, and XDG Desktop Portal.
- **(KWin & Mutter) Virtual Desktop Tracking & Empty Workspace Dodge (FAT 4.1)**: Modernized KWin 6 virtual desktop tracking via `isOnCurrentDesktop()` and `client.desktops` array inspection; stabilized GNOME Shell workspace index matching (`ws.index()`). Switching to an empty workspace now immediately unhides / reveals the dock across compositors.
- **(KWin) Urgent Bounce & Attention Animation (FAT 2.7)**: Initialized `LastUrgent` timestamp in `ApplicationDockItem.vala` and established 2s periodic bounce cadence in `DockRenderer.vala` so urgent windows bounce continuously until focused.
- **(KWin) HiDPI & Fractional Scaling Output Anchoring (FAT 7.7)**: Replaced volatile coordinate matching with stable model labels and eliminated destructive `hide()` calls in `DockWindow.vala`, preserving monitor anchoring during scale/DPI changes.
- **(Cross-Compositor / CLI) Process Lifecycle `--replace` Option (FAT 9.5)**: Added `--replace` long option to `AbstractMain.vala` `GOptionEntry` table, aligning `--replace` with `-r`.
- **(Cross-Compositor) Primary Display Previous Monitor Restoration (FAT 7.2)**: Toggling "On Primary Display" off now restores the dock to the previously active secondary monitor via `last_explicit_monitor` persistence in `DockController.vala`.
- **(GNOME) Native XDG Desktop Portal Screenshot (FAT 6.5)**: Replaced restricted GNOME Shell D-Bus screenshot calls with the official `org.freedesktop.portal.Screenshot` interface, providing native interactive screenshot UI on modern GNOME Shell.
- **(Labwc / wlroots) Centered Preferences Window & Packaging Recommends (FAT 7.1)**: Documented Labwc window rule `<action name="AutoPlace" policy="center" />` for dialogs and added `Recommends: grim, slurp, spectacle` in Debian package control.
- **(GTK) Window Default Button Critical Assertion Fix**: Eliminated `gtk_window_set_default` assertion failure by ensuring `ok_button.set_can_default (true)`.
- **Release status**: 100% FAT pass rate (159/159 test points verified across GNOME Mutter, KDE Plasma KWin, and Labwc wlroots), see FAT status: [`FAT/2026-10-08 FAT 0.5.1.txt`](FAT/2026-10-08%20FAT%200.5.1.txt)

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.5.1.md`](Changelogs/CHANGELOG_v0.5.1.md).

## V0.5.0: 2026-10-07

**Phase 6 Hardening, Multi-Monitor Unique Tagging & Cross-Compositor FAT**:
- **(Cross-Compositor) Cross-Compositor FAT Validation Matrix**: Full Factory Acceptance Testing executed across GNOME/Mutter, KDE/KWin, and Labwc covering 25+ validation scenarios.
- **(Cross-Compositor) Unique Multi-Monitor Geometry Tagging**: Solved multi-display collisions between identical hardware monitors via `%s (%d) [%dx%d @ %d,%d]` spatial tags in `PositionManager.vala`.
- **(Cross-Compositor) Dynamic Monitor Hotplugging & Unlocked UI**: Connected `monitors_changed` signal to rebuild display lists in real time; unlocked display dropdown with re-entrancy guards.
- **(KWin) FIFO Queue & Desktop Traversal**: Solved dropped bulk actions ("Close All") via serialized JSON queue in `KWinBridge.vala`; added automatic virtual desktop switching.
- **(GNOME / Mutter) Shell Bridge & Drag Safety**: Resolved frame positioning race conditions via explicit monitor assignment and eliminated pointer timer use-after-free crashes.
- **Release status**: Still some bugs persists but good enough for publishing see fat status: [`FAT/2026-10-07 FAT 0.5.0.txt`](FAT/2026-10-07%20FAT%200.5.0.txt)

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.5.0.md`](Changelogs/CHANGELOG_v0.5.0.md).

## V0.4.3: 2026-10-05

**Multi-Compositor HAL Release (KWin, Labwc/wlroots & GNOME/Mutter)**:
- **(Cross-Compositor) Modular Multi-Compositor HAL**: Dynamic runtime auto-probing across KWin, Labwc, and GNOME/Mutter at startup with zero configuration.
- **(Labwc / wlroots) Native Support**: Integrated asynchronous C protocol bridge implementing `zwlr_foreign_toplevel_manager_v1` with zero-latency Cairo dot indicators.
- **(GNOME / Mutter) Native D-Bus Bridge**: Monolithic self-deploying GNOME Shell extension via D-Bus (`MutterBackend`) with window state tracking and edge positioning.
- **(Cross-Compositor) Strict HAL Coordinate Isolation**: Pure relative Layer Shell margins for KWin/Labwc; dedicated absolute screen positioning with real frame anchoring for Mutter.
- **(Cross-Compositor) Bi-Directional Show Desktop & Dynamic Separators**: Atomic bulk minimize/restore across all backends; dual visual separators (`[Pinned] | [Transient] | [Trash]`).
- **Release status**: Still some bugs persists but good enough for publishing see fat status: [`FAT/2026-10-06 FAT 0.4.3.txt`](FAT/2026-10-06%20FAT%200.4.3.txt)

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.4.3.md`](Changelogs/CHANGELOG_v0.4.3.md).

## V0.4.2: 2026-10-02

**Wayland Stabilization, Monolithic Docklets & Architecture Polish**:
- **(Cross-Compositor) Total Independence from X11**: Completely purged X11/XWayland libraries, building with zero warnings and zero errors.
- **(Cross-Compositor: All Compositors / KWin) Monolithic Built-in Docklets**: Replaced external plugins with 8 static docklets (Trash, Clocks, Battery, CPU/RAM, Show Desktop, MPRIS, Volume).
- **(KWin) Plasma D-Bus Trash Bridge**: Real-time trash synchronization with Dolphin and KDE Plasma widgets.
- **(Cross-Compositor) Transient Items & Multi-Window Cycling**: Zero-latency tracking of unpinned windows and scroll-wheel window cycling.
- **(Cross-Compositor / CLI) Anti-Bounce & Process Takeover (`--replace`)**: Eliminated spurious bounce animations and added `--replace` / `-r` support.

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.4.2.md`](Changelogs/CHANGELOG_v0.4.2.md).

## V0.4.1: 2026-09-25

**KWin Multi-Monitor Stabilization & Core Modernization**:
- **(KWin) Multi-Monitor Display Tracking**: Fixed dock placement when switching monitors, persisted monitor selection across reboots, and added primary monitor fallback on disconnect.
- **(KWin) Tooltip Positioning**: Fixed tooltips on secondary screens incorrectly rendering on the primary monitor.
- **(Cross-Compositor) Zoom & UI Smoothness**: Disabled system config polling during icon zoom to eliminate micro-stutters and adjusted zoom bounds to avoid icon clipping.
- **(Cross-Compositor) Legacy Code Purge**: Removed leftover X11/XWayland calls, stripped deprecated APIs, and eliminated compiler warnings.

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.4.1.md`](Changelogs/CHANGELOG_v0.4.1.md).

## V0.4.0: 2026-09-24

**KWin Wayland Scripting Bridge & Window Dodge Engine**:
- **(KWin) Wayland Scripting Bridge**: Integrated Wayland window state tracking via native KWin D-Bus scripting interface.
- **(KWin) Window Dodge & Intellihide**: Implemented real-time window overlap detection supporting Dodge Active Window and Dodge Maximized Window modes.
- **(Cross-Compositor) Dynamic Layer-Shell Negotiation**: Handled dynamic layer-shell exclusive zones and input regions to ensure seamless window interaction alongside dock auto-hide.
- **(Cross-Compositor) Transient Icon Filtering**: Prevented system tray icons from incorrectly spawning as temporary dock items.

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.4.0.md`](Changelogs/CHANGELOG_v0.4.0.md).

## V0.3.0: 2026-09-23

**Wayland Hover Stabilization & Application Management**:
- **(Cross-Compositor) Icon Pinning & Instance Marking**: Implemented drag-and-drop icon pinning, running application markers, and multi-instance management.
- **(Cross-Compositor) Hover & Surface Lifecycle**: Fixed dock hover zoom when cursor enters the dock surface, restored show/hide logic, and eliminated unsafe X11 overlap assumptions.
- **(Cross-Compositor) Compositor-Safe Architecture**: Replaced legacy X11 window queries with Wayland compositor-safe abstractions.

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.3.0.md`](Changelogs/CHANGELOG_v0.3.0.md).

## V0.2.0: 2026-09-22

**Native Wayland & GTK Layer Shell Transition**:
- **(Cross-Compositor: Wayland / Layer Shell) GTK Layer Shell Integration**: Implemented native Wayland surface layer management (`gtk-layer-shell`) and removed X11 startup blocks.
- **(Cross-Compositor) Process Scanner & Desktop Matching**: Implemented `/proc`-based process scanner with automatic dead PID cleanup and generic `.desktop` file resolution.
- **(Cross-Compositor) Context Menus & Pinning**: Redesigned right-click context menu handling and enabled persistent pinned items via custom `.dockitem` configurations.
- **(Cross-Compositor) Build Pipeline & Packaging**: Modularized build scripts (`BuildBin.sh`, `BuildDeb.sh`), updated dependencies to `libgtk-layer-shell0`, and established cross-distro compatibility.
- **(Cross-Compositor) Legacy Cleanup**: Purged obsolete X11 backends, environment overrides (`GDK_BACKEND=x11`), and legacy display server restrictions.

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.2.0.md`](Changelogs/CHANGELOG_v0.2.0.md).

## V0.1.0: 2026-09-19

**Phase 1 Architecture Decoupling & Baseline Release**:
- **(Cross-Compositor) Standalone Fork**: Forked from original Plank codebase to establish clean foundations for Wayland migration.
- **(Cross-Compositor) Namespace Migration**: Renamed binary and data namespaces to `wayplank` with transparent symlink compatibility.
- **(Cross-Compositor) XDG Directory Isolation**: Relocated configs to `~/.config/wayplank` and themes to `~/.local/share/wayplank/themes`.
- **(Cross-Compositor) Packaging Pipeline**: Created universal manual compilation sequence and standalone Debian packaging script.

👉 **Full Technical Details:** See [`Changelogs/CHANGELOG_v0.1.0.md`](Changelogs/CHANGELOG_v0.1.0.md).

---

## ⚖️ License & Integrated Assets Attribution

Wayplank is free software licensed under the **GNU General Public License v3.0 or later** ([GPL-3.0-or-later](LICENSE)).

### 1. Core Project & Codebase
* **License**: GNU General Public License v3.0 or later ([GPL-3.0-or-later](LICENSE)).
* **Original Plank Codebase**: © 2011–2015 Robert Dyer, Michal Hruby, Rico Tzschichholz, and Plank contributors.
* **Wayplank Fork & Architecture**: © 2026 Sergio Melas (<sergiomelas@gmail.com>).

### 2. Integrated Fallback Assets & Vector Artwork
Wayplank incorporates high-definition vector assets compiled directly into the binary executable via GLib GResources (`/net/launchpad/plank/docklets/`) to provide self-contained, standalone operation on any desktop or minimal distribution:
* **Docklet Fallback Icons** (`data/docklets/`):
  * **Volume Scale**: High, Medium, Low, Muted (`volume-*.svg`).
  * **Battery Scale**: Full, Good, Low, Caution, Empty, Full-Charging, Good-Charging, Low-Charging, Caution-Charging, Empty-Charging, AC-Adapter, Missing (`battery-*.svg`).
  * **Clock & Time**: Analog Clock (`clock.svg`), Digital LED Clock (`digital-clock.svg`).
  * **System & Desktop**: Trash empty/full (`trash.svg`, `trash-full.svg`), CPU/RAM Monitor (`cpu.svg`), Show Desktop (`desktop.svg`), MPRIS play/pause (`mpris-*.svg`), Screenshot (`screenshot.svg`), Session/Power (`session.svg`), Wayplank Preferences (`preferences.svg`).
* **Attribution & Upstream**: Derived from FreeDesktop & KDE Breeze icon specifications © KDE Community / Breeze Icon Artists, licensed under **LGPL-3.0-or-later** / **GPL-3.0-or-later**.
* **Zero Host Pollution**: All fallback icons are strictly compiled into the internal executable binary; no extra icon files are installed into `/usr/share/icons/hicolor/`, ensuring pure standalone behavior and complete distribution independence.


