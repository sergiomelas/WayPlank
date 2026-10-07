# WAYPLANK: THE ROAD TO WAYLAND DOCK

> Standalone, Monolithic Fork of Plank for Wayland
>
> Laying the Groundwork for Native Wayland Architecture
>
> Developed by Sergio Melas (sergiomelas@gmail.com) © 2026

![Wayplank v0.5.0 Release Banner](Release%20Pic.png)

---

🚀 CURRENT RUNTIME: Full Wayland with KWin, Labwc (wlroots) & GNOME (Mutter) support | 🎯 TARGET GOAL: Support all major Compositors

---

## 📢 Current Status

I developed the core engine to discover running applications (since Wayland isolates and segregates window introspection by design) based on process list matching against the content of user and system `.desktop` files. To overcome the challenges of Wayland security boundaries, I utilized AI assistance during early prototyping. The codebase has undergone comprehensive human review, bug hunting, and code purging for high performance and stability.

Important notice: core dock rendering and layout inherit the beloved look and feel from the original Plank developers (Docky Core Team), representing roughly 90% of the baseline code, while the remaining 10% introduces native Wayland architecture, compositor bridges, and modern features.

Having used KDE with Plank for years, Wayplank provides a true native Wayland successor as X11 phases out. Starting with version 0.4.3, Wayplank features a modular Hardware Abstraction Layer (HAL) with native support for **KWin (KDE Plasma)**, **Labwc (wlroots)**, and **GNOME Shell (Mutter)** compositors! Testing and feedback across different Wayland environments are warmly welcome.

👉 *For the complete technical migration report, please refer to [`Documentation/wayplank_x11_to_wayland_report_en.md`](Documentation/wayplank_x11_to_wayland_report_en.md).*

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
sudo dpkg -i build/wayplank_0.5.0_amd64.deb
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
  - [ ] Broaden community testing across additional wlroots compositors (Sway, Hyprland, Wayfire).
  - [ ] Finish documentation, packaging, and configuration migration.
  - [ ] After release, focus on bug fixes and compatibility updates.

- [ ] Phase 7 (Final) v1.0.0: Publish Version 1.0 as first stable
  - [ ] Publish Version 1.0 with a clear list of supported compositors.
  - [ ] After release, focus on bug fixes and compatibility updates.
---

# Change log

## V0.5.0: 2026-10-07

**Phase 6 Hardening, Multi-Monitor Unique Tagging & Cross-Compositor FAT**:
- **Cross-Compositor FAT Validation Matrix**: Full Factory Acceptance Testing executed across GNOME/Mutter, KDE/KWin, and Labwc covering 25+ validation scenarios.
- **Unique Multi-Monitor Geometry Tagging**: Solved multi-display collisions between identical hardware monitors via `%s (%d) [%dx%d @ %d,%d]` spatial tags in `PositionManager.vala`.
- **Dynamic Monitor Hotplugging & Unlocked UI**: Connected `monitors_changed` signal to rebuild display lists in real time; unlocked display dropdown with re-entrancy guards.
- **KWin FIFO Queue & Desktop Traversal**: Solved dropped bulk actions ("Close All") via serialized JSON queue in `KWinBridge.vala`; added automatic virtual desktop switching.
- **GNOME Shell Bridge & Drag Safety**: Resolved frame positioning race conditions via explicit monitor assignment and eliminated pointer timer use-after-free crashes.
- **Release status**: Still some bugs persists but good enough for publishing see fat status: [`FAT/2026-10-07 FAT 0.5.0.txt`](FAT/2026-10-07%20FAT%200.5.0.txt)

👉 **Full Technical Details:** See [`src/CHANGELOG_v0.5.0.md`](src/CHANGELOG_v0.5.0.md).

## V0.4.3: 2026-10-05

**Multi-Compositor HAL Release (KWin, Labwc/wlroots & GNOME/Mutter)**:
- **Modular Multi-Compositor HAL**: Dynamic runtime auto-probing across KWin, Labwc, and GNOME/Mutter at startup with zero configuration.
- **Native Labwc & wlroots Support**: Integrated asynchronous C protocol bridge implementing `zwlr_foreign_toplevel_manager_v1` with zero-latency Cairo dot indicators.
- **Native GNOME/Mutter D-Bus Bridge**: Monolithic self-deploying GNOME Shell extension via D-Bus (`MutterBackend`) with window state tracking and edge positioning.
- **Strict HAL Coordinate Isolation**: Pure relative Layer Shell margins for KWin/Labwc; dedicated absolute screen positioning with real frame anchoring for Mutter.
- **Bi-Directional Show Desktop & Dynamic Separators**: Atomic bulk minimize/restore across all backends; dual visual separators (`[Pinned] | [Transient] | [Trash]`).
- **Release status**: Still some bugs persists but good enough for publishing see fat status: [`FAT/2026-10-06 FAT 0.4.3.txt`](FAT/2026-10-06%20FAT%200.4.3.txt)

👉 **Full Technical Details:** See [`src/CHANGELOG_v0.4.3.md`](src/CHANGELOG_v0.4.3.md).

## V0.4.2: 2026-10-02

**Wayland Stabilization, Monolithic Docklets & Architecture Polish**:
- **Total Independence from X11**: Completely purged X11/XWayland libraries, building with zero warnings and zero errors.
- **Monolithic Built-in Docklets**: Replaced external plugins with 8 static docklets (Trash, Clocks, Battery, CPU/RAM, Show Desktop, MPRIS, Volume).
- **KWin & Plasma D-Bus Trash Bridge**: Real-time trash synchronization with Dolphin and KDE Plasma widgets.
- **Transient Items & Multi-Window Cycling**: Zero-latency tracking of unpinned windows and scroll-wheel window cycling.
- **Anti-Bounce & Process Takeover**: Eliminated spurious bounce animations and added `--replace` / `-r` support.

👉 **Full Technical Details:** See [`src/CHANGELOG_v0.4.2.md`](src/CHANGELOG_v0.4.2.md).

## V0.4.1: 2026-09-25

**KWin Multi-Monitor Stabilization & Core Modernization**:
- **Multi-Monitor Display Tracking**: Fixed dock placement when switching monitors, persisted monitor selection across reboots, and added primary monitor fallback on disconnect.
- **Tooltip Positioning**: Fixed tooltips on secondary screens incorrectly rendering on the primary monitor.
- **Zoom & UI Smoothness**: Disabled system config polling during icon zoom to eliminate micro-stutters and adjusted zoom bounds to avoid icon clipping.
- **Legacy Code Purge**: Removed leftover X11/XWayland calls, stripped deprecated APIs, and eliminated compiler warnings.

👉 **Full Technical Details:** See [`src/CHANGELOG_v0.4.1.md`](src/CHANGELOG_v0.4.1.md).

## V0.4.0: 2026-09-24

**KWin Wayland Scripting Bridge & Window Dodge Engine**:
- **KWin Scripting Bridge**: Integrated Wayland window state tracking via native KWin D-Bus scripting interface.
- **Window Dodge & Intellihide**: Implemented real-time window overlap detection supporting Dodge Active Window and Dodge Maximized Window modes.
- **Dynamic Layer-Shell Negotiation**: Handled dynamic layer-shell exclusive zones and input regions to ensure seamless window interaction alongside dock auto-hide.
- **Transient Icon Filtering**: Prevented system tray icons from incorrectly spawning as temporary dock items.

👉 **Full Technical Details:** See [`src/CHANGELOG_v0.4.0.md`](src/CHANGELOG_v0.4.0.md).

## V0.3.0: 2026-09-23

**Wayland Hover Stabilization & Application Management**:
- **Icon Pinning & Instance Marking**: Implemented drag-and-drop icon pinning, running application markers, and multi-instance management.
- **Hover & Surface Lifecycle**: Fixed dock hover zoom when cursor enters the dock surface, restored show/hide logic, and eliminated unsafe X11 overlap assumptions.
- **Compositor-Safe Architecture**: Replaced legacy X11 window queries with Wayland compositor-safe abstractions.

👉 **Full Technical Details:** See [`src/CHANGELOG_v0.3.0.md`](src/CHANGELOG_v0.3.0.md).

## V0.2.0: 2026-09-22

**Native Wayland & GTK Layer Shell Transition**:
- **GTK Layer Shell Integration**: Implemented native Wayland surface layer management (`gtk-layer-shell`) and removed X11 startup blocks.
- **Process Scanner & Desktop Matching**: Implemented `/proc`-based process scanner with automatic dead PID cleanup and generic `.desktop` file resolution.
- **Context Menus & Pinning**: Redesigned right-click context menu handling and enabled persistent pinned items via custom `.dockitem` configurations.
- **Build Pipeline & Packaging**: Modularized build scripts (`BuildBin.sh`, `BuildDeb.sh`), updated dependencies to `libgtk-layer-shell0`, and established cross-distro compatibility.
- **Legacy Cleanup**: Purged obsolete X11 backends, environment overrides (`GDK_BACKEND=x11`), and legacy display server restrictions.

👉 **Full Technical Details:** See [`src/CHANGELOG_v0.2.0.md`](src/CHANGELOG_v0.2.0.md).

## V0.1.0: 2026-09-19

**Phase 1 Architecture Decoupling & Baseline Release**:
- **Standalone Fork**: Forked from original Plank codebase to establish clean foundations for Wayland migration.
- **Namespace Migration**: Renamed binary and data namespaces to `wayplank` with transparent symlink compatibility.
- **XDG Directory Isolation**: Relocated configs to `~/.config/wayplank` and themes to `~/.local/share/wayplank/themes`.
- **Packaging Pipeline**: Created universal manual compilation sequence and standalone Debian packaging script.

👉 **Full Technical Details:** See [`src/CHANGELOG_v0.1.0.md`](src/CHANGELOG_v0.1.0.md).

