# Wayplank V0.4.2 Detailed Technical Changelog

Release Milestone: **V0.4.2** (Wayland Stabilization, Monolithic Docklets & Architecture Polish)  
Archive Source: `0.4.2_Wayland- Kwin fully supported bugfixes - 5.zip`  
Release Date: 2026-10-02  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 🌟 (Cross-Compositor: All Compositors / KWin) Monolithic Built-in Docklets Architecture (Complete Suite)

- **Standalone Monolithic Docklet Engine**: Completely purged the legacy, unmaintained external dynamic shared-library plugin architecture (`lib/Docklets/`), replacing it with high-performance, statically compiled monolithic dock items embedded directly into Wayplank's core binary with zero external `.so` dependencies.
- **Full Community-Requested Docklet Suite Implemented**:
  1. **Real-Time Trash Docklet (`TrashDockItem` — `docklet://trash`)**:
     - Dynamically inspects trash occupancy (0 items, 1 item, N items) and updates label and icon in real time.
     - Full Drag & Drop file trashing: dragging files, directories, or `.desktop` files onto the trash icon moves them to the trash with animated bounce feedback (`AnimationType.BOUNCE`).
     - Right-click contextual actions: *Open Trash*, *Empty Trash*, and *Remove from Dock*.
     - Left-click bounce animation and instant trash folder opening via KIO/GIO/portal.
     - Drag-to-remove: dragging the trash docklet off the dock triggers the smoke puff animation (`poof`) and unpins it cleanly.
     - **Bi-Directional KWin & Plasma D-Bus Trash Bridge (`KWinTrashBridge`)**: Real-time D-Bus synchronization with KDE Plasma desktop trash widgets and Dolphin via `org.kde.KDirNotify` (both listener and emitter), native KIO trashing, and multi-theme desktop icon resolution.
  2. **Vector Analog Clock (`ClockDockItem` — `docklet://clock`)**:
     - Real-time vector analog clock rendered smoothly on a dedicated Cairo canvas at any dock size and zoom level.
     - Anti-aliased bezel rim, dark translucent dial face, 12-hour tick marks with accented quarters, smooth hour and minute hands, vibrant red sweeping second hand, and dual-tone center pivot pin.
     - 1-second timeout updates, localized full-date tooltip, right-click time copying to clipboard, and left-click calendar launcher.
  3. **Modern Glassy Digital Clock (`DigitalClockDockItem` — `docklet://digital-clock`)**:
     - High-contrast rounded glassy dial card rendered via Cairo with subtle translucent gradient and white border rim.
     - Bold digital time (`HH:MM`) with soft drop-shadow and vibrant cyan localized date badge (`VEN 02`).
     - Live 1-second tick updates, left-click calendar launch, and right-click time copying.
  4. **Hardware Battery Monitor (`BatteryDockItem` — `docklet://battery`)**:
     - Direct hardware introspection via `/sys/class/power_supply/BAT*` (`capacity`, `status`).
     - Sleek vertical capsule vector rendering with level-dependent fill coloring (Green > 40%, Amber 16-40%, Red < 15%), glowing cyan charging state with centered vector lightning bolt, and top terminal nub.
     - Desktop power & battery settings launch on click and contextual menu.
  5. **CPU & RAM Resource Monitor (`CpuDockItem` — `docklet://cpu`)**:
     - Live differential parser for `/proc/stat` (CPU usage %) and `/proc/meminfo` (RAM usage % and used/total GB).
     - Smooth dual circular Cairo gauges with accented percentage arcs and color thresholds (Green/Amber/Red).
     - Launches system monitor (`plasma-systemmonitor`, `ksysguard`, `gnome-system-monitor`) on click.
  6. **Show Desktop Two-Way Toggle (`ShowDesktopDockItem` — `docklet://desktop`)**:
     - **True Bi-Directional Toggle**: First click minimizes all normal user windows into the background, maintaining WayPlank and desktop widgets visible while remembering the exact set of hidden window UUIDs (`wayplankDesktopHiddenClients`). Second click restores all previously hidden windows back to their original state and restores focus to the last active window.
     - **State Resets on User Activation**: If a user manually activates an application window while in Show Desktop mode, the state resets gracefully so the next click cleanly returns to minimizing.
     - Direct D-Bus queue command dispatch (`toggle_desktop`) via KWin bridge script.
  7. **MPRIS Media Player Controller (`MprisDockItem` — `docklet://mpris`)**:
     - Native D-Bus session bus scanner tracking active `org.mpris.MediaPlayer2.*` players (Spotify, VLC, Elisa, Chrome, Firefox).
     - Real-time `PlaybackStatus` and `Metadata` inspection (Artist, Title, status).
     - Dynamic icon state (`media-playback-start`, `media-playback-pause`), left-click Play/Pause toggle, middle-click Next Track, and full playback control menu (*Play/Pause*, *Next*, *Previous*).
  8. **Audio Volume Controller (`VolumeDockItem` — `docklet://volume`)**:
     - Native PulseAudio & PipeWire integration via `pactl` / `amixer`.
     - **Mouse Wheel Volume Scrolling**: Scrolling up/down directly over the docklet increments or decrements volume in smooth 5% steps.
     - Click toggles mute/unmute with dynamic audio volume icon states (`audio-volume-muted`, `audio-volume-low`, `audio-volume-medium`, `audio-volume-high`).
     - Contextual menu with mute toggle and direct audio mixer launch (`kcmshell6 kcm_pulseaudio`, `pavucontrol`).
- **Preferences Dialog & Context Menu Integration**:
  - Dedicated "Docklets" tab in the Preferences window (`preferences.ui` and `PreferencesWindow.vala`) with an ergonomic 2-column layout (4 rows x 2 columns) of toggle switches for all 8 monolithic docklets.
  - Quick `_Docklets` submenu in the dock context menu (`PlankDockItem.vala`) for instant, one-click enabling and disabling of any docklet.
  - All docklets fully support standard drag-to-remove poof animations (`poof`) and right-click "Remove from Dock".

---

## 2. 📁 (Cross-Compositor) Folder Stacks & File Management (`FileDockItem`)

- **Standard Drag & Grab Mechanics Restored**: Removed legacy `Button = PopupButton.RIGHT | PopupButton.LEFT` override that previously opened the context menu on left press, restoring standard drag gestures: left-click and drag grabs the folder icon to reorder or drag it off the dock to delete/unpin with the smoke poof animation, a single click triggers a playful bounce animation, and right-click displays the contextual stack menu.
- **Native Drag & Drop into Pinned Folders**: Dropping `.desktop` shortcuts, files, or directories onto a pinned folder automatically copies them into the target directory (with recursive subfolder support), applies executable permissions (`0755`) to `.desktop` files for instant launchability, invalidates Cairo thumbnail buffers, and animates a bounce.
- **Portal & MIME-Type Launching (`System.open`)**: Replaced deprecated 2011 handler queries with `GLib.AppInfo.launch_default_for_uri` and `xdg-desktop-portal` fallback, allowing documents, images, and subfolders inside stacks to open seamlessly under Wayland.

---

## 3. ⚡ (KWin / Wayland) Compositor Integration & Window Management

- **Dynamic Transient Dock Items Synchronization**: Connected `WindowManager.windows_refreshed` directly to `sync_compositor_windows()` in `ApplicationDockItemProvider.vala`. Unpinned running applications dynamically appear with temporary icons the instant their first window opens, and cleanly disappear when their last window closes.
- **Real-Time Indicator Dots (0ms Latency)**: Connected `GdkFrameClock.begin_updating()` in `Renderer.vala` and filtered out `client.deleted` windows in KWin bridge, ensuring instantaneous indicator redraws synchronized with compositor frame callbacks (`wl_surface.frame`).
- **Visual Pinning Boundary**: The separator (`SeparatorDockItem`) acts as a dynamic boundary: dragging an item across the separator dynamically promotes or demotes its pinning state, while internal icon reordering preserves separator integrity.
- **Native Smooth Scrolling & Multi-Window Cycling**: Implemented smooth mouse wheel event translation (`Gdk.ScrollDirection.SMOOTH` deltas) with rate limiting. Rolling the wheel over an application with multiple open windows smoothly cycles focus forward and backward across all its windows.
- **Smart Sleep & Resume Recovery**: Subscribed to systemd-logind `PrepareForSleep` and ScreenSaver `ActiveChanged` signals to survive suspend/hibernate cycles by re-binding layer-shell surfaces to awakened outputs and unhiding the dock upon resume.
- **Precise Smoke Poof Coordinates**: Querying real pointer release coordinates via GDK root coordinates, seat devices, and layer-shell monitor offsets ensures the smoke poof animation renders exactly where the icon is released outside the dock.
- **Window Focus & Anti-Bounce Stabilization**:
  - Eliminated spurious icon bounce when closing the last window of an application (fixed regression where closing an app like Konsole caused adjacent dock icons like Dolphin to bounce).
  - Eliminated spurious icon bounce on active windows when closing WayPlank dialogs (Preferences, Shortcuts).

---

## 4. 🛠️ (Cross-Compositor) Desktop Matching & Process Scanner

- **Robust Command Line Parsing (`GLib.Shell.parse_argv`)**: Replaced whitespace splitting on `Exec=` lines in `Matcher.vala` with `GLib.Shell.parse_argv`, eliminating false-negative running states for applications with spaces or quotes (e.g. `/opt/My App/binary`).
- **UID-Isolated Process Scanning**: Scans are isolated to the user's UID to prevent system daemons from triggering false running indicators, with title and argument matching for custom launchers and web apps.
- **Event-Driven Inotify Discovery**: Replaced continuous 2-second background disk polling with event-driven `inotify` monitors with 300ms debounce, achieving zero idle CPU and disk I/O.

---

## 5. 🎨 (Cross-Compositor / CLI) UI, Theming & CLI Modernization

- **Standardized CLI Flags**: Restored short flag `-p` for `--preferences`. Aligned flags to standard conventions: `-v` for `--version` and `-V` for `--verbose`.
- **Seamless Process Replacement (`--replace` / `-r`)**: Added native command-line option `--replace` (short `-r`) that cleanly terminates previous background WayPlank instances (`killall -q -o 1s -9 wayplank`) before taking over the session, preventing duplicated docks and bridge script conflicts.
- **Multi-Tab Help & Shortcuts Dialog**: Redesigned help window into a modern multi-tab `Gtk.Stack` dialog (*Mouse Actions*, *Drag & Drop*, *Shortcuts & Tools*).
- **Embedded Monolithic Wayplank Vector Logo**: Vector Wayplank logo embedded directly into GResource (`/net/launchpad/plank/img/wayplank.svg`) for crisp About dialog rendering.
- **In-App Wayland Migration Report**: Embedded `Documentation/wayplank_x11_to_wayland_report_en.md` into GResource (`/net/launchpad/plank/doc/report.md`), exportable and viewable with Mermaid.js diagrams directly from the dock context menu.
- **Layer-Shell Margin Clamping**: Clamped tooltip margins against negative coordinates, preventing GTK Layer Shell protocol errors near screen edges.

---

## 6. 🧹 (Cross-Compositor / Core) Codebase Health, Deprecation Removal & Clean Build

- **Declaration of Independence from X11 & Native Modernization**: WayPlank has officially severed all ties with legacy X11: purged all remaining X11, XRandR, XInput, and libwnck dependencies, obsolete VAPIs, and build flags. The codebase compiles with **0 warnings and 0 errors**.
- **AI Slop & Placebo Code Purged**: Removed dead placeholder checks (such as empty `win != null && !win.has_native ()` checks and redundant try/catch blocks on non-throwing methods), eliminating stale prototyping leftovers.
- **Native Hardware Multi-Monitor Discovery**: Reimplemented display querying via `Gdk.Monitor` with automatic name disambiguation for identical models (e.g., `DELL U2720Q (1)`, `DELL U2720Q (2)`).
- **Clean Build Pipeline**: Modernized `BuildBin.sh` and `BuildDeb.sh` with strict exit-code validation and zero-warning compilation.
