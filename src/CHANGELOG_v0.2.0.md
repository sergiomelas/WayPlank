# Wayplank V0.2.0 Detailed Technical Changelog

Release Milestone: **V0.2.0** (Phase 2 Native Wayland & GTK Layer Shell Transition)  
Archive Source: `0.2_Wayland-after eng.zip` (Wayland After Re-Engineering)  
Release Date: 2026-09-22  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 🌐 Native Wayland Surface Architecture via GTK Layer Shell

- **Excising Legacy X11 Dock Windows (`DockWindow.vala`)**:
  - In original Plank and v0.1, the dock was implemented as an X11 top-level window requesting `_NET_WM_WINDOW_TYPE_DOCK` with custom X11 struts (`_NET_WM_STRUT_PARTIAL`). In Wayland, window types and global screen struts are forbidden by the display protocol.
  - Completely re-engineered `DockWindow.vala` (over 490 lines of legacy X11 surface management replaced):
    - Integrated native `gtk-layer-shell` API:
      ```vala
      GtkLayerShell.init_for_window (this);
      GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
      GtkLayerShell.set_namespace (this, "wayplank");
      ```
    - Edge Anchoring: Configured dynamic layer anchors (`set_anchor (Edge.LEFT / RIGHT / TOP / BOTTOM)`) based on dock orientation.
    - Exclusive Zone Management: Integrated `GtkLayerShell.set_exclusive_zone ()` to negotiate screen margins directly with Wayland compositors (Labwc, KWin).
- **Purge of X11 Session Startup Blocks (`AbstractMain.vala`)**:
  - Removed the hardcoded X11 check in `AbstractMain.vala` that forcefully terminated the application if running under a non-X11 display server.
  - Removed `GDK_BACKEND=x11` and `QT_QPA_PLATFORM=xcb` environment overrides.

---

## 2. 🔍 Introduction of `/proc` Process Scanner (`lib/Services/Matcher.vala`)

- **The Problem of Wayland Application Introspection**:
  - Without the X11 root window tree or external window tracking daemons (BAMF / libwnck), a dock in Wayland has no global visibility into running desktop applications.
- **The `/proc` Procfs Scanner Architecture**:
  - Implemented an asynchronous procfs scanner in `lib/Services/Matcher.vala` (+279 lines of new scanning logic):
    - Periodically scans `/proc` directories, reading process command lines (`/proc/[pid]/cmdline`), executable names (`/proc/[pid]/comm`), and stat files.
    - Heuristically maps running process names to installed `.desktop` file identifiers across `/usr/share/applications/` and `~/.local/share/applications/`.
    - Handles process termination: periodically prunes dead PIDs and removes corresponding transient dock icons via `unregister_process_for_app ()`.

---

## 3. 🧹 Elimination of 400+ Lines of X11 Strut & Workarea Logic (`PositionManager.vala`)

- **Decoupling PositionManager from X11 Screen Workareas**:
  - Excised over 400 lines of complex X11 screen workarea code from `lib/PositionManager.vala`:
    - Purged manual strut recalculation routines, X11 monitor coordinate offsets, and root window geometry event listeners.
    - Delegated monitor bounding rect queries directly to `Gdk.Display` and `Gdk.Monitor` abstractions.
- **Provider Streamlining (`ApplicationDockItemProvider.vala`)**:
  - Removed 317 lines from `ApplicationDockItemProvider.vala` and 269 lines from `DefaultApplicationDockItemProvider.vala`, stripping out legacy BAMF matcher connections and redirecting event handling to the new Wayland-safe `Matcher` signals.

---

## 4. 📦 Packaging Updates & Debian Dependency Management

- **Build Pipeline Modularization**:
  - Maintained clear separation between binary compilation (`BuilsBin.sh`) and distribution packaging (`BuildDeb.sh`).
  - Added explicit runtime and build dependencies on `libgtk-layer-shell0` and `libgtk-layer-shell-dev` in Debian package control manifests.
  - Verified clean builds across both Debian and Arch Linux environments.

---

## 5. 📦 Summary of Touched Files & Code Metrics

| Subsystem | File | Lines Changed | Key Modifications |
| :--- | :--- | :--- | :--- |
| **Layer Shell** | `lib/Widgets/DockWindow.vala` | +130 / -499 | Replaced X11 dock types with `gtk-layer-shell` layer, anchors, and exclusive zones. |
| **Positioning** | `lib/PositionManager.vala` | -400 lines | Excised X11 struts (`_NET_WM_STRUT_PARTIAL`) and legacy workarea calculations. |
| **Proc Scanner** | `lib/Services/Matcher.vala` | +279 / -145 | First implementation of `/proc` process scanner with PID cleanup. |
| **App Providers** | `ApplicationDockItemProvider.vala` | -317 lines | Removed BAMF and legacy X11 application tracking hooks. |
| **Startup** | `lib/Factories/AbstractMain.vala` | -16 lines | Removed hardcoded X11 session-type startup blocks. |
| **Packaging** | `BuildDeb.sh` | Updated | Added `libgtk-layer-shell0` to runtime dependency list. |
