          ╔══════════════════════════════════════════════════════════════════════════════╗
          ║ ┌──────────────────────────────────────────────────────────────────────────┐ ║
          ║ │                     WAYPLANK: THE ROAD TO WAYLAND DOCK                   │ ║
          ║ │       Standalone, Monolithic Fork of Plank (Current X11 Baseline)        │ ║
          ║ │           Laying the Groundwork for Native Wayland Architecture          │ ║
          ║ ├──────────────────────────────────────────────────────────────────────────┤ ║
          ║ │  Developed by Sergio Melas (sergiomelas@gmail.com)         © 2026        │ ║
          ║ └──────────────────────────────────────────────────────────────────────────┘ ║
          ╚══════════════════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 CURRENT RUNTIME: X11 / XWayland Baseline  |  🎯 TARGET GOAL: Native Wayland Compositor Layer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## 📢 Current Status: Sorry for the readme AI generated from the next paragraph but I wanted to share this asap. I developed the core engine to discover the running apps (because Wayland segregates evriting) based on process list matching it with the content of the .desktop files of the user and system. To cope with the nithmerish traps that Wayland esposes programmers (because of the legittimate segregation of Wayland for security) i used AI to help me. Anyway this is a prototype and for version 1.0 the code will be human written or human reviewed.

Important notice: my contribution is just 5% of the code. all the rest is the original Plank code with is look and feel we all love from the original developers of the Docky Core Team.

I always had KDE with plank at bottom but X11 is dying (what a pity bat was necessary). Some functionality will need testing for compositor integration. I hope the comunity Will support on testing on compositors out of KDE/Kwin.

⚠️From here to the end of readme is AI generated I will rewrite it when I have time. Thx to visit this place.



### ⚠️ Reality Check: Where Wayplank Stands Today
 To be completely transparent: **Wayplank right now is still running on the legacy X11 / XWayland
 subsystem.**

 The original Plank project has been abandoned for years, weighed down by archaic autotools build
 locks, dead package dependencies, and monolithic coupling to obsolete libraries. You cannot leap
 straight into native Wayland protocols (wlr-layer-shell / ext-workspace) on top of broken legacy
 scaffolding.

 **Wayplank V1.0.0 represents the indispensable Phase 1 (The Clean Groundwork):**
 We have completely decoupled Plank into a modern, standalone monolithic codebase with its own
 isolated namespace (`wayplank`), clean direct-compiler pipeline, and independent XDG storage
 hierarchies.

### 🔍 Keep an Eye on This Repository!
 If you are waiting for a true, lightweight, native Wayland dock experience to replace Plank
 without bloated desktop dependencies:
 **Bookmark this repo and watch our releases.** This is the active launchpad where the transition
 to modern protocols (and our upcoming Qt backend migration) is taking place step-by-step.
 Community feedback, architecture testing, and PRs are warmly welcome!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

WARNING & DISCLAIMER: ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                                                                                                   ┃
┃          DEVELOPED FOR EXPERIMENTAL AND ADVANCED DESKTOP INTEGRATION PROFILES                     ┃
┃                                                                                                   ┃
┃ We assume no responsibility for errors or omissions in the software or documentation available.   ┃
┃ In no event shall we be liable to you or any third parties for any special, punitive, incidental, ┃
┃ indirect or consequential damages of any kind, or any damages whatsoever, including,              ┃
┃ without limitation, those resulting from loss of use, data or configurations, and on any theory   ┃
┃ of liability, arising out of or in connection with the use of this software.                      ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

================================================================================
Universal Build & Installation Guide (Any Linux Distribution)
================================================================================

1. CORE DEPENDENCIES (Current X11 Stack)
----------------------------------------
To compile Wayplank from source, ensure your distribution provides:
 - Vala compiler (valac >= 0.40)
 - GTK+ 3.0 (gtk3 / libgtk-3-dev)
 - GDK X11 (gdk-x11-3.0)
 - LibWNCK 3.0 (libwnck3 / libwnck-3-dev)
 - BAMF (libbamf3 / bamf-daemon)
 - LibGee 0.8 (libgee-0.8 / libgee-0.8-dev)
 - GLib 2.0 (glib2 / libglib2.0-dev, includes glib-compile-resources)

2. UNIVERSAL MANUAL COMPILATION
-------------------------------
Compile the embedded resource binary directly on any Linux distribution:

 # Step 1: Compile embedded GLib resources
 glib-compile-resources --sourcedir=data --target=lib/resources.c --generate-source data/plank.gresource.xml

 # Step 2: Compile native Wayplank binary
 valac -g \
     --gresources=data/plank.gresource.xml \
     --gresourcesdir=data \
     --vapidir=vapi \
     --pkg posix --pkg gio-unix-2.0 --pkg gtk+-3.0 --pkg gdk-x11-3.0 \
     --pkg libwnck-3.0 --pkg libbamf3 --pkg gee-0.8 --pkg compat --pkg config \
     -X -DWNCK_I_KNOW_THIS_IS_UNSTABLE -X -D_GNU_SOURCE -X "-Dsetproctitle(x)=" \
     -X -DGETTEXT_PACKAGE=\"wayplank\" -X -Ilib -X -Iinclude -X -w -X -lm \
     $(find lib src -name "*.vala") lib/resources.c -o wayplank

 # Step 3: Install binary and data
 sudo install -Dm755 wayplank /usr/local/bin/wayplank
 sudo ln -sf /usr/local/bin/wayplank /usr/local/bin/plank
 sudo cp -r data/themes /usr/local/share/wayplank/
 sudo cp -r data/icons/* /usr/local/share/icons/hicolor/
 sudo cp data/glib-2.0/schemas/* /usr/local/share/glib-2.0/schemas/
 sudo glib-compile-schemas /usr/local/share/glib-2.0/schemas/

3. AUTOMATED DEBIAN/UBUNTU PACKAGE CREATION
-------------------------------------------
If running Debian, Ubuntu, or derivative distributions, run the automated builder:
 $ chmod +x BuildDeb.sh
 $ ./BuildDeb.sh
 $ sudo dpkg -i build/wayplank_1:1.0.0_amd64.deb

================================================================================
RUNTIME DIRECTORIES & CONFIGURATION MIGRATION
================================================================================

Wayplank operates under its own isolated namespace and standard XDG locations:

- Configuration Directory : ~/.config/wayplank/
- Application Launchers   : ~/.config/wayplank/dock1/launchers/
- Local User Themes       : ~/.local/share/wayplank/themes/
- System Themes           : /usr/share/wayplank/themes/ (or /usr/local/share/wayplank/themes/)

Theme Configuration:
Wayplank inspects both system and user theme paths natively. To change dock appearance:
 $ wayplank --preferences

Debug & Verbose Logging:
To inspect running window hooks and debug output:
 $ wayplank -d

================================================================================
PROJECT ROADMAP & THE WAYLAND MILESTONES
================================================================================
 [x] Phase 1 (Completed): Decoupled Standalone Fork
     - Complete breakaway from unmaintained upstream Plank.
     - Full namespace migration to 'wayplank' (configs, directories, launchers).
     - Modern monolithic build system replacing broken autotools/autogen scripts.
     - Multi-distro compatibility and standalone Debian packaging pipeline.

 [x] Phase 2 (In Active Development): Qt Subsystem Transition
     - Refactoring backend abstractions to C++/Qt for modern desktop stability.
     - Built-in transparent config import wizard for legacy Plank configurations.

 [ ] Phase 3 (Final Destination): Native Wayland Integration
     - Implementation of wlr-layer-shell / Wayland native protocols.
     - Complete phasing out of X11/XWayland dependencies.
     - Full fractional scaling and native Wayland compositor window tracking.

##################################################################################################################
Change log:


V0.3.0: 2026-09-23  - Wayland hover and hide stabilization:
                    - Fixed dock hover zoom when the cursor enters the dock surface, restored the
                      proper hidden/show state logic, and removed unsafe X11 overlap assumptions
                      from the live Wayland path.
                    - Kept the architecture compositor-safe by reserving real overlap detection
                      for future compositor-specific integrations instead of forcing legacy X11
                      logic onto Wayland.

V0.2.0: 2026-09-22  - Phase 2 Native Wayland & Labwc Transition:
                    - Complete removal of X11 session-type startup checks: Stripped out the strict
                      initialization block in AbstractMain.vala that previously prevented the dock
                      from launching in non-X11 environments.
                    - Native gtk-layer-shell integration: Integrated native surface layer management
                      tailored specifically for Wayland compositors.
                    - Wayland DND protocol resolution: Fixed drag-and-drop protocol mismatches to ensure
                      seamless file drops from native Wayland clients like Dolphin.
                    - Native Wayland drag-and-drop: Drag-and-drop operations from native Wayland clients
                      are currently non-functional under wlroots/Labwc; file/item drops are disabled,
                      restricting users to pinning and opening apps normally for now.
                    - Build pipeline modularization: Extracted pure binary compilation into a dedicated,
                      shared BuilsBin.sh script to streamline maintenance.
                    - Right-click context menu refactoring: Completely redesigned the right-click handling
                      to remove legacy window control dependencies, eliminating the need for external controls.
                    - Cross-distribution compatibility: Established a clean, distribution-agnostic
                      compilation pipeline supporting both Debian and Arch Linux environments.
                    - Refactored Debian packaging script: Updated BuildDeb.sh to cleanly invoke the
                      shared binary builder prior to packaging.
                    - Updated system dependencies: Replaced legacy X11 packages with native requirements,
                      explicitly adding libgtk-layer-shell0 to the Debian control manifest.
                    - Legacy X11 cleanup: Purged obsolete display server backends, environment override variables
                      (GDK_BACKEND=x11, QT_QPA_PLATFORM=xcb), and version-pinning restrictions from the system.
                    - V0.2.0 Milestone Achievement: Formally advanced the project version to reflect a fully native,
                      X11-free architecture running smoothly on Labwc.
                    - Modularized build pipeline by separating core binary compilation into BuilsBin.sh for
                      cross-distribution compatibility (Debian/Arch).
                    - Updated Debian packaging script (BuildDeb.sh) to depend on libgtk-layer-shell0 and
                      invoke the shared binary builder.
                    - Process Scanner & Generic Desktop Matching: Implemented a robust `/proc`-based process scanner
                      in Matcher.vala with automatic cleanup of dead PIDs and generic, distribution-agnostic desktop
                      file pattern resolution supporting KDE, GNOME, and standard applications.
                    - Persistent Pinning & Lifecycle Management: Fixed application transient item tracking on close
                      and enabled reliable persistence of pinned items through custom `.dockitem` configurations.

V0.1.0: 2026-09-19  - Phase 1 Architecture Decoupling & Baseline Release:
                    - Forked from original Plank codebase to establish clean foundations for future Wayland porting.
                    - Full namespace migration: renamed binary target to 'wayplank' with transparent symlink fallback.
                    - Relocated system assets to '/usr/share/wayplank' via PKGDATADIR redefinition.
                    - Isolated user configurations under '~/.config/wayplank'.
                    - Updated Theme loader to dynamically inspect '~/.local/share/wayplank/themes'.
                    - Created universal manual compile sequence for non-Debian distributions.
                    - Integrated standalone Debian packaging pipeline (BuildDeb.sh) with desktop database triggers.
