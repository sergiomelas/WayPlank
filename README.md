# WAYPLANK: THE ROAD TO WAYLAND DOCK

> Standalone, Monolithic Fork of Plank (Current X11 Baseline)
>
> Laying the Groundwork for Native Wayland Architecture
>
> Developed by Sergio Melas (sergiomelas@gmail.com) © 2026

---

🚀 CURRENT RUNTIME: Full Wayland with Kwin support | 🎯 TARGET GOAL: Support all major Compositors

---

## 📢 ## 📢 Current Status
I developed the core engine to discover the running apps (because Wayland segregates evriting)
based on process list matching it with the content of the .desktop files of the user and system. To cope
with the nightmarish traps that Wayland exposes programmers (because of the legitimate segregation of
Wayland for security) i used AI to help me. Anyway this is a prototype and for version 1.0
the code will be human written or human reviewed.

Important notice: my contribution is just 10% of the code. all the rest is the original Plank code
with is look and feel we all love from the original developers of the Docky Core Team.
But i added some functionality i always wanted in Plank

I always had KDE with plank at bottom but X11 is dying (what a pity bat was necessary). Some
functionality will need testing for compositor integration.
I hope the comunity Will support on testing on compositors out of KDE/Kwin.

### ⚠️ Reality Check: Where Wayplank Stands Today

To be completely transparent: **Wayplank right now is full wayland based, but it fully works only in kwin**.

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

To compile Wayplank from source, ensure your distribution provides:

- Vala compiler (valac >= 0.40)
- GTK+ 3.0 (gtk3 / libgtk-3-dev)
- GTK Layer Shell (gtk-layer-shell-0 / libgtk-layer-shell-dev)
- JSON-GLib 1.0 (json-glib-1.0 / libjson-glib-dev)
- LibGee 0.8 (libgee-0.8 / libgee-0.8-dev)
- GLib 2.0 (glib2 / libglib2.0-dev, includes glib-compile-resources)
- pkg-config

## 2. UNIVERSAL MANUAL COMPILATION

Compile the embedded resource binary directly on any Linux distribution:

```bash
# Step 1: Compile embedded GLib resources
glib-compile-resources --sourcedir=data --target=lib/resources.c --generate-source data/plank.gresource.xml

# Step 2: Compile native Wayplank binary
valac -g \
    --gresources=data/plank.gresource.xml \
    --gresourcesdir=data \
    --vapidir=vapi \
    --pkg posix --pkg gio-unix-2.0 --pkg gtk+-3.0 --pkg gtk-layer-shell-0 \
    --pkg json-glib-1.0 --pkg gee-0.8 --pkg compat --pkg config \
    -X -DWNCK_I_KNOW_THIS_IS_UNSTABLE -X -D_GNU_SOURCE -X "-Dsetproctitle(x)=" \
    -X -DGETTEXT_PACKAGE=\"wayplank\" -X -Ilib -X -Iinclude -X -w -X -lm \
    $(find lib src -name "*.vala") lib/resources.c -o wayplank
```

```bash
# Step 3: Install binary and data
sudo install -Dm755 wayplank /usr/local/bin/wayplank
sudo ln -sf /usr/local/bin/wayplank /usr/local/bin/plank
sudo cp -r data/themes /usr/local/share/wayplank/
sudo cp -r data/icons/* /usr/local/share/icons/hicolor/
sudo cp data/glib-2.0/schemas/* /usr/local/share/glib-2.0/schemas/
sudo glib-compile-schemas /usr/local/share/glib-2.0/schemas/
```

## 3. AUTOMATED DEBIAN/UBUNTU PACKAGE CREATION

If running Debian, Ubuntu, or derivative distributions, run the automated builder:

```bash
chmod +x BuildDeb.sh
./BuildDeb.sh
sudo dpkg -i build/wayplank_1:1.0.0_amd64.deb
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

- [x] Phase 1 (Completed): Decoupled Standalone Fork
  - Complete breakaway from unmaintained upstream Plank.
  - Full namespace migration to 'wayplank' (configs, directories, launchers).
  - Modern monolithic build system replacing broken autotools/autogen scripts.
  - Multi-distro compatibility and standalone Debian packaging pipeline.

- [x] Phase 2 (Completed): Application Discovery and Dock Lifecycle
  - Implemented generic application discovery from running processes and desktop files.
  - Added persistent pinned application handling and temporary running application icons.
  - Implemented running-instance marking and multi-instance application management.

- [x] Phase 3 (Completed) WayPlank Fully works with no X11 dependency: Native Wayland Integration
  - Implementation of Wayland native protocols.
  - Complete phasing out of X11/XWayland dependencies. Support one compositor.
    This will be Kwin because it is the one I know the best.
  - Full fractional scaling and native Wayland compositor window tracking.

- [ ] Phase 4 (In Progress): KWin Stabilization and Bug Fixes
  - Define and implement the HAL architecture to support multiple compositors.
  - Implement Multi Monitor Support: Verify monitor selection, persistence, and fallback when a display disconnects.
  - Fix and test reported KWin bugs across hide modes and dock interactions.
  - Stop mass development; receive user feedback and debugging.

- [ ] Phase 5 (Next): Add Support for Other Compositors
  - Import existing Plank settings, launchers, themes, and pinned items.
  - Add and test support for selected wlroots compositors, such as Sway, Hyprland, Wayfire, and Labwc.
  - Develop Mutter support separately, including the required GNOME Shell bridge and dock integration.
  - Test the new compositor support and fix compatibility issues.

- [ ] Phase 6 (Final): Publish Version 1.0 and Move to Maintenance
  - Finish documentation, packaging, and configuration migration.
  - Publish Version 1.0 with a clear list of supported compositors.
  - After release, focus on bug fixes and compatibility updates.

---

# Change log

## V0.4.1: 2026-09-25

###KWin multi-monitor fixes:
- Fixed dock placement not updating after selecting a different monitor.
- Persisted the selected monitor across restarts.
- Fixed the bug where tooltips on secondary monitors appeared on the primary monitor.
- Added a fallback to the primary monitor if the selected monitor is disconnected.
###Core fixes:
- Deactivated system configuration polling during icon zoom to avoid UI freezes.
- Adjusted the zoom level to prevent icons from being clipped.
- Removed leftover X11 code that generated XWayland calls.
- Removed a ton of deprecated code, fully modernizing the stack.
- Cleaned most compiler warnings caused by stale and obsolete code.

## V0.4.0: 2026-09-24

Finalized KWin Wayland :
- Added KDE/KWin Wayland window-state integration through a KWin scripting bridge.
- Implemented Intellihide using active-window overlap detection.
- Implemented Window Dodge using live KWin window geometry and overlap detection.
- Implemented Dodge Active Window and Dodge Maximized Window modes for KWin.
- Added dynamic layer-shell exclusive-zone and input-region handling so dodge modes
  allow windows to receive input while Autohide and dock interactions remain stable.
- Tray icons do not appear as temporary icons

## V0.3.0: 2026-09-23

Wayland hover and hide stabilization:

- Implemented drag icon pinning
- Implemented running app marking and multi instance management
- Fixed dock hover zoom when the cursor enters the dock surface, restored the proper hidden/show state logic, and removed unsafe X11 overlap assumptions from the live Wayland path.
- Kept the architecture compositor-safe by reserving real overlap detection for future compositor-specific integrations instead of forcing legacy X11 logic onto Wayland.

## V0.2.0: 2026-09-22

Phase 2 Native Wayland & Labwc Transition:

- Partial removal of X11 session-type startup checks: Stripped out the strict initialization block in AbstractMain.vala that previously prevented the dock from launching in non-X11 environments.
- Native gtk-layer-shell integration: Integrated native surface layer management tailored specifically for Wayland compositors.
- Wayland DND protocol resolution: Fixed drag-and-drop protocol mismatches to ensure seamless file drops from native Wayland clients like Dolphin.
- Native Wayland drag-and-drop: Drag-and-drop operations from native Wayland clients are currently non-functional under wlroots/Labwc; file/item drops are disabled, restricting users to pinning and opening apps normally for now.
- Build pipeline modularization: Extracted pure binary compilation into a dedicated, shared BuilsBin.sh script to streamline maintenance.
- Right-click context menu refactoring: Completely redesigned the right-click handling to remove legacy window control dependencies, eliminating the need for external controls.
- Cross-distribution compatibility: Established a clean, distribution-agnostic compilation pipeline supporting both Debian and Arch Linux environments.
- Refactored Debian packaging script: Updated BuildDeb.sh to cleanly invoke the shared binary builder prior to packaging.
- Updated system dependencies: Replaced legacy X11 packages with native requirements, explicitly adding libgtk-layer-shell0 to the Debian control manifest.
- Legacy X11 cleanup: Purged obsolete display server backends, environment override variables (GDK_BACKEND=x11, QT_QPA_PLATFORM=xcb), and version-pinning restrictions from the system.
- V0.2.0 Milestone Achievement: Formally advanced the project version to reflect a fully native, X11-free architecture running smoothly on Labwc.
- Modularized build pipeline by separating core binary compilation into BuilsBin.sh for cross-distribution compatibility (Debian/Arch).
- Updated Debian packaging script (BuildDeb.sh) to depend on libgtk-layer-shell0 and invoke the shared binary builder.
- Process Scanner & Generic Desktop Matching: Implemented a robust `/proc`-based process scanner in Matcher.vala with automatic cleanup of dead PIDs and generic, distribution-agnostic desktop file pattern resolution supporting KDE, GNOME, and standard applications.
- Persistent Pinning & Lifecycle Management: Fixed application transient item tracking on close and enabled reliable persistence of pinned items through custom `.dockitem` configurations.

## V0.1.0: 2026-09-19

Phase 1 Architecture Decoupling & Baseline Release:

- Forked from original Plank codebase to establish clean foundations for future Wayland porting.
- Full namespace migration: renamed binary target to 'wayplank' with transparent symlink fallback.
- Relocated system assets to '/usr/share/wayplank' via PKGDATADIR redefinition.
- Isolated user configurations under '~/.config/wayplank'.
- Updated Theme loader to dynamically inspect '~/.local/share/wayplank/themes'.
- Created universal manual compile sequence for non-Debian distributions.
- Integrated standalone Debian packaging pipeline (BuildDeb.sh)
