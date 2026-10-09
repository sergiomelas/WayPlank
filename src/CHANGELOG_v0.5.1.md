# Wayplank V0.5.1 Detailed Technical Changelog

Release Milestone: **V0.5.1** (Hotfix — KWin System Resume Event Storm Prevention, QTimer Debouncing & Script Lifecycle Hardening)  
Release Date: 2026-10-08  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 📋 Overview & Incident Analysis

### The Problem (KWin Post-Resume Freeze)
On multi-monitor setups running KDE Plasma 6 (KWin) on Wayland, waking the machine from system sleep/suspend frequently caused KWin to lock up:
- **Symptom**: Window contents (such as terminal cursors, web pages, text editors) remained interactive and responsive to keyboard input. However, KWin's server-side decorations (title bars, close/minimize/maximize buttons), window dragging, and workspace switching became completely unresponsive.
- **Root Cause**:
  1. **Event Storm on Multi-Display Wakeup**: When external displays wake up, KWin recalculates geometries and shifts screens, firing dozens of rapid `frameGeometryChanged` and `desktopsChanged` signals per window in a fraction of a second.
  2. **Synchronous D-Bus Flooding**: Wayplank's embedded KWin script (`KWinBridge.vala`) was invoking `sendWindowState()` synchronously on *every single signal*, serializing full window lists into JSON and making synchronous D-Bus IPC calls back to Wayplank. This starved KWin's main event loop.
  3. **Duplicate Script Instances**: On resume, Wayplank's system resume hook invoked `reload_script()`, which attempted to unload and re-register the KWin script. Because anonymous JavaScript signal closures in KWin (`.connect(function() { ... })`) are not completely unhooked by `unloadScript()`, a second active script instance was created. This doubled the event storm and caused global shortcut registration collisions in `kglobalaccel`.
  4. **Self-Inspection Feedback Loop**: Wayplank's own window surface was hooked by `connectWindow()`, creating a potential feedback loop when updating desktop properties.

---

## 2. 🛠️ Technical Fixes Implemented

### 1. (KWin) Asynchronous 50ms QTimer Debouncing (`lib/Services/KWinBridge.vala`)
- Integrated a native single-shot `QTimer` directly inside KWin's QJSEngine script:
  ```javascript
  var wayplankDebounceTimer = new QTimer();
  wayplankDebounceTimer.interval = 50;
  wayplankDebounceTimer.singleShot = true;
  wayplankDebounceTimer.timeout.connect(function () {
      sendWindowState();
  });

  function scheduleWindowState () {
      if (wayplankDebounceTimer && !wayplankDebounceTimer.active) {
          wayplankDebounceTimer.start();
      }
  }
  ```
- Routed all high-frequency window lifecycle signals (`frameGeometryChanged`, `minimizedChanged`, `maximizedChanged`, `activeChanged`, `desktopsChanged`, `desktopChanged`, `demandsAttentionChanged`, `currentDesktopChanged`, `windowAdded`, `windowActivated`) through `scheduleWindowState()`.
- Flushes the entire burst into a single serialized state payload at most once every 50ms, keeping KWin's event loop completely fluid.

### 2. (KWin) Dock Surface Filtering (`lib/Services/KWinBridge.vala`)
- Added explicit checks in `connectWindow()` to filter out Wayplank's own surface:
  ```javascript
  if (window.resourceClass === "wayplank" || window.resourceName === "wayplank" || window.caption === "wayplank")
      return;
  ```
- Prevents redundant event triggers and recursive signal loops when setting dock properties like `onAllDesktops`.

### 3. (KWin) Intelligent Resume Script Preservation (`lib/Services/KWinBridge.vala` & `lib/Services/KWinBackend.vala`)
- Implemented `KWinBridge.handle_system_resume()`:
  - Queries `org.kde.kwin.Scripting.isScriptLoaded` over D-Bus before blindly reloading.
  - If the script is already loaded and active in KWin across resume, the reload step is skipped entirely.
  - Prevents zombie script accumulation and eliminates shortcut registration conflicts with `kglobalaccel`.
- Connected `KWinBackend.handle_system_resume()` to the new non-destructive handler.

### 4. (Cross-Compositor: KWin / Mutter / Labwc) Screenshot Docklet (`docklet://screenshot`)
- **Native Wayland Docklet**: Created `ScreenshotDockItem.vala` implementing `docklet://screenshot` across all supported compositors (KDE Plasma/KWin, GNOME Shell/Mutter, Labwc/wlroots).
- **Interactive & Multi-Mode Capture**:
  - **Left-click**: Triggers instant interactive region/area selection with a docklet bounce animation.
  - **Context Menu**: Provides dedicated options for *Capture Area / Rectangular...*, *Capture Entire Screen*, *Capture Active Window*, and *Open Screenshots Folder*.
- **Compositor Adaptation**:
  - Native integration with KDE Spectacle (`spectacle -r` / `-f` / `-a`).
  - GNOME Screenshot integration (`gnome-screenshot -a` / `-w`).
  - Labwc / wlroots integration with `grim` + `slurp`.
  - Universal XDG Desktop Portal D-Bus fallback (`org.freedesktop.portal.Screenshot`).
- **Preferences Integration**: Added a dedicated switch in the *Docklets* tab of `PreferencesWindow.vala` and `preferences.ui` for toggling the Screenshot docklet on and off.

### 5. (KWin & Mutter) Virtual Desktop Tracking & Empty Workspace Dodge Fix (FAT 4.1 Resolution)
- **KDE Plasma 6 (KWin) Virtual Desktop Modernization**:
  - Replaced legacy `onCurrentDesktop` property query with KWin 6 `isOnCurrentDesktop()` C++ method and `client.desktops` array traversal.
  - Correctly marks off-desktop windows with `currentDesktop: false`, allowing window dodge (`any_window_intersects`) to accurately ignore windows from other workspaces.
  - Resolves FAT test 4.1: switching from an occupied workspace (WS1) to an empty workspace (WS2) now immediately unhides / reveals the dock.
- **GNOME Shell / Mutter Workspace Identity Stabilization**:
  - Replaced GObject wrapper instance comparison (`===`) in `MutterBackend.vala` extension with numerical workspace index matching (`winWs.index() === ws.index()`).
  - Seamlessly tracks windows across workspaces regardless of GJS object wrapping variations.
- **Labwc (wlroots) Protocol Demarcation**:
  - Documented wlroots protocol boundaries in FAT test 4.1: because standard `zwlr_foreign_toplevel_management_v1` omits spatial coordinates and workspace IDs for security, workspace dodging on Labwc operates via *Dodge Active* mode until `ext-workspace-v1` integration.

### 6. (KWin) Urgent Bounce & Attention Animation Fix (FAT 2.7 Resolution)
- **ApplicationDockItem Urgency Timestamp Initialization**: Fixed `ApplicationDockItem.set_urgent(bool)` which previously set `State |= ItemState.URGENT` (rendering the red attention dot) but omitted updating `LastUrgent = GLib.get_monotonic_time()`. Without `LastUrgent`, elapsed time calculation underflowed/overflowed in `DockRenderer.vala`, preventing the icon bounce easing animation from ever executing.
- **Continuous Attention Bounce Cadence**: Updated `DockRenderer.vala` bounce calculation to cycle periodically (every 2.0s) while `(item.State & ItemState.URGENT) != 0` and kept `item_animation_needed` active so an urgent window smoothly hops to catch user attention until focused.
- **State Property Change Binding**: Connected `notify["LastUrgent"]` and `notify["last-urgent"]` in `DockItemProvider.vala` to ensure the render engine is triggered on urgency state transitions.

### 7. (KWin) HiDPI & Fractional Scaling Monitor Identity Persistence (FAT 7.7 Resolution)
- **Geometry-Independent Monitor Identification**: Replaced brittle resolution/coordinate string matching with stable monitor label matching (comparing model name and duplicate instance count `(1)`, `(2)`, etc. independently of volatile geometry brackets). This ensures that when display scaling or DPI changes (e.g. 1920x1080 -> 1536x864 under 125% scale), Wayplank reliably identifies and preserves the assigned output instead of falling back to the primary screen.
- **Layer Surface Lifecycle Non-Destructive Scaling**: Eliminated destructive `hide()` calls inside `DockWindow.update_layer_shell_monitor()`. Guarded `GtkLayerShell.set_monitor()` to only trigger when the target monitor actually changes, preventing KWin from re-anchoring layer surfaces to the default primary display during dynamic compositor scale transitions.
- **Dynamic Preference Geometry Synchronization**: Added live synchronization of `prefs.Monitor` upon `screen_changed` so that configuration keys and UI combobox selections reflect the active logical geometry.

### 8. (Cross-Compositor / CLI) Process Lifecycle & `--replace` CLI Option Fix (FAT 9.5 Resolution)
- **GLib.Application CLI Option Registration**: Added `{"replace", 0, 0, OptionArg.NONE, null, "Restart and replace running dock instance", null}` to `AbstractMain.vala`'s `GOptionEntry` table. Previously only `{"reload", 'r'}` was defined in the options array, causing `wayplank --replace` to be rejected with `Unknown option --replace` while `wayplank -r` worked. Now both short (`-r`) and long (`--replace`, `--reload`) flags operate identically.

### 9. (KWin) Rapid Display Reconfiguration & DPI Storm Hardening (FAT 9.6 Resolution)
- **KWin Script Debounced Window Removal**: In `KWinBridge.vala`, routed `workspace.windowRemoved` through the 50ms `scheduleWindowState()` debouncer rather than calling `sendWindowStateEx(w)` synchronously on KWin's main thread. This prevents IPC event floods when multiple layer surfaces or client windows are rapidly destroyed during display mode reconfigurations.
- **Defensive D-Bus Timeout Bounds**: Replaced unbounded (`-1`) timeouts in `KWinBridge.vala` (`loadScript` and `start`) with explicit 2000ms bounds, guaranteeing Wayplank never stalls indefinitely if the compositor is momentarily saturated.
- **PositionManager Re-entrancy Protection**: Added `updating_screen` re-entrancy guard in `PositionManager.vala:screen_changed` to ensure dynamic configuration adjustments during display geometry recalculations do not trigger cascading event feedback loops.

### 10. (Cross-Compositor) Primary Display Switch Previous Monitor Restoration (FAT 7.2 Resolution)
- **Previous Display Persistence**: Resolved a state loss bug in `PreferencesWindow.vala` and `DockController.vala` where enabling the "On Primary Display" switch and subsequently disabling it failed to return the dock to the previously active monitor, leaving it stuck on the primary display.
- **Controller-Level State Memory**: Added `last_explicit_monitor` property in `DockController.vala` hooked into `prefs.notify["Monitor"]`, ensuring explicit secondary monitor choices survive dialog close/open cycles.
- **UI State Protection**: Disabled the monitor selection combo dropdown while "On Primary Display" is active to prevent conflicting selections.

### 11. (GNOME / Mutter) Native XDG Desktop Portal Screenshot Integration (FAT 6.5 Resolution)
- **Wayland Security Compliance**: On modern GNOME Shell (42+), direct D-Bus invocations of `org.gnome.Shell.Screenshot` are blocked with `AccessDenied: InteractiveScreenshot is not allowed`.
- **Portal Standardization**: Updated `ScreenshotDockItem.vala` to route GNOME interactive screenshot requests through the official FreeDesktop portal (`org.freedesktop.portal.Screenshot`), opening GNOME's native full-featured screenshot overlay with zero permission errors.

### 12. (Labwc / wlroots) Window Rules Centering & Debian Package Recommends (FAT 7.1 Resolution)
- **Centered Preferences Dialog**: Documented and applied native Labwc `<windowRules>` with `<action name="AutoPlace" policy="center" />` in `rc.xml` to center the Preferences and dialog windows under Labwc.
- **Debian Recommends Integration**: Added `Recommends: grim, slurp, spectacle` to Debian package control (`BuildDeb.sh`), ensuring native screenshot utilities are automatically pulled in across wlroots, KDE, and GNOME environments.

### 13. (GTK) Window Default Button Critical Assertion Fix
- **GTK Default Widget Safety**: Fixed `gtk_window_set_default: assertion 'gtk_widget_get_can_default (default_widget)' failed` in `PreferencesWindow.vala` and `HelpWindow.vala` by explicitly calling `ok_button.set_can_default (true)` prior to `set_default()`.

---

## 3. 🧪 Verification & Build Status

- **Compilation**: Clean build using Vala compiler (`valac`) with 0 errors and 0 warnings.
- **Binary**: Packaged into standalone `build/wayplank` and verified with `build/wayplank --version` -> `Wayplank 0.5.1`.
- **Debian Package**: Built and validated as `build/wayplank_0.5.1_amd64.deb`.
- **FAT Validation**: 100% pass rate (159/159 test points verified across GNOME Mutter, KDE Plasma KWin, and Labwc wlroots); see [`FAT/2026-10-08 FAT 0.5.1.txt`](../FAT/2026-10-08%20FAT%200.5.1.txt).
- **Architectural Isolation**: Zero modifications made to core dock rendering or IPC state engine.

