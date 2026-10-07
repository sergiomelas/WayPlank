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

### 1. Asynchronous 50ms QTimer Debouncing (`lib/Services/KWinBridge.vala`)
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

### 2. Dock Surface Filtering (`lib/Services/KWinBridge.vala`)
- Added explicit checks in `connectWindow()` to filter out Wayplank's own surface:
  ```javascript
  if (window.resourceClass === "wayplank" || window.resourceName === "wayplank" || window.caption === "wayplank")
      return;
  ```
- Prevents redundant event triggers and recursive signal loops when setting dock properties like `onAllDesktops`.

### 3. Intelligent Resume Script Preservation (`lib/Services/KWinBridge.vala` & `lib/Services/KWinBackend.vala`)
- Implemented `KWinBridge.handle_system_resume()`:
  - Queries `org.kde.kwin.Scripting.isScriptLoaded` over D-Bus before blindly reloading.
  - If the script is already loaded and active in KWin across resume, the reload step is skipped entirely.
  - Prevents zombie script accumulation and eliminates shortcut registration conflicts with `kglobalaccel`.
- Connected `KWinBackend.handle_system_resume()` to the new non-destructive handler.

---

## 3. 🧪 Verification & Build Status

- **Compilation**: Clean build using Vala compiler (`valac`) with 0 errors and 0 warnings.
- **Binary**: Packaged into standalone `build/wayplank` and verified with `build/wayplank --version` -> `Wayplank 0.5.1`.
- **Debian Package**: Built and validated as `build/wayplank_0.5.1_amd64.deb`.
- **Architectural Isolation**: Zero modifications made to Labwc/wlroots backend (`LabwcBackend.vala`), Mutter/GNOME Shell extension (`MutterBackend.vala`, `extension.js`), or dock rendering engine.

