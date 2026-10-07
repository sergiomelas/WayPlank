# Wayplank V0.5.0 Detailed Technical Changelog

Release Milestone: **V0.5.0** (Phase 6 Hardening — Cross-Compositor FAT Test Protocol, Multi-Monitor Unique Geometry Tagging & Deep Display Matrix Alignment)  
Archive Source: `0.5.0_Final For Debugging.zip`  
Release Date: 2026-10-06  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 📋 Factory Acceptance Test (FAT) Cross-Compositor Protocol

Wayplank underwent an intensive, exhaustive **Factory Acceptance Test (FAT)** matrix executed across the three supported Wayland compositor architectures:
1. **Session 1: GNOME Shell 48 / Mutter** (via native D-Bus Extension Bridge)
2. **Session 2: KDE Plasma 6.7 / KWin** (via native KWin Scripting D-Bus Bridge)
3. **Session 3: Labwc 0.8+ / wlroots** (via native `zwlr_foreign_toplevel_manager_v1` C protocol engine)

The test protocol evaluated 7 core functional areas across 25+ specific validation scenarios, identifying and resolving edge-case architectural regressions:

### Summary of FAT Results
* **Area 0: Crash Resiliency & Memory Safety**: Passed (`[ok]`) on all backends.
* **Area 1: Icon & Launcher Management**: Passed (`[ok]`) on all backends.
* **Area 2: Window Management & Running States**: Passed (`[ok]`) on all backends.
* **Area 3: Hide & Dodge Modes (None, Autohide, Intellihide, Dodge Active, Dodge Maximized, Window Dodge)**: Passed (`[ok]`) on all backends.
* **Area 4: Virtual Desktops & Workspaces**: Passed (`[ok]`) on all backends.
* **Area 5: Tooltips & Hover Visuals (Flicker-free parabolic zoom, border trigger zone)**: Passed (`[ok]`) on all backends.
* **Area 6: Monolithic Built-in Docklets (Show Desktop, Trash, Clocks, Battery, CPU/RAM)**: Passed (`[ok]`) on all backends.
* **Area 7: Preferences & Multi-Monitor Configuration**: Fully resolved and verified (`[ko -> ok]`).

---

## 2. 🖥️ Multi-Monitor Collision Resolution: Unique Geometry Tagging & Spatial Coordinates

### The Multi-Monitor "Screen Crossings & Edge Inversion" Problem
During FAT testing under multi-display topologies (specifically triple-monitor setups with identical hardware displays, e.g. two external `DELL P2219H` monitors alongside an internal eDP panel), a severe multi-monitor breakdown was observed:
1. **Identical Hardware String Collisions**: Both external monitors advertised the identical model identifier string `DELL P2219H` via GDK. Because `PositionManager.get_monitor_for_plug_name()` previously matched displays strictly by string equality, it invariably resolved to monitor index 0 (or fell back to the origin `(0, 0)`). Selecting the second or third display in Preferences was impossible.
2. **Boundary Dislocation & Edge Inversion**: When attempting to position the dock on secondary displays under GNOME/Mutter (which lacks native Layer Shell surface negotiation and relies on absolute XDG coordinates), the dock would straddle the boundary between screens, jump to the wrong edge (e.g. right edge rendering on the left edge with a 1-dock thickness offset), or ignore monitor selection changes completely.
3. **Race Conditions in Mutter Frame Repositioning**: In the GNOME Shell extension, invoking `move_resize_frame()` without first moving the window to the target workspace monitor caused Mutter's layout engine to place the window based on stale viewport coordinates.

### Architectural Fixes Implemented

#### 1. Unique Coordinate & Geometry Tagging (`lib/PositionManager.vala`)
- Redesigned `get_monitor_plug_names()` to guarantee **100% mathematical uniqueness** across every connected display, even when vendor, model, and EDID strings are completely identical:
  ```vala
  // String format: "<Model> (<DuplicateIndex>) [<Width>x<Height> @ <X>,<Y>]"
  // Example: "DELL P2219H (1) [1920x1080 @ 1920,0]"
  ```
- Enhanced `get_monitor_for_plug_name()` to parse the embedded `[@ X,Y]` spatial coordinate token. If present, it resolves the monitor by exact geometric coordinates `(rect.x == target_x && rect.y == target_y)` rather than relying on ambiguous model names.
- Retained clean fallback resolution (matching model name with duplicate index counting) for backwards compatibility with legacy configurations.

#### 2. Dynamic Real-Time Monitor Hotplugging (`lib/Widgets/PreferencesWindow.vala`)
- Implemented `rebuild_monitor_list()` and connected it directly to `Gdk.Screen.get_default().monitors_changed`.
- Connecting, disconnecting, or re-arranging monitors dynamically rebuilds the monitor selector combo box in real time without requiring a dock restart.
- Added re-entrancy protection flag `updating_monitors` to eliminate recursive event loops when synchronizing `sw_primary_display` and `cb_display_plug`.
- Unlocked `cb_display_plug`: the display dropdown is now **always sensitive and interactable**, allowing users to explicitly select their preferred output monitor at any time.

#### 3. Strict Coordinate Isolation & Asynchronous Frame Placement (`extension.js`)
- In the GNOME Shell extension bridge, ensured target monitor assignment via `win.move_to_monitor(targetMon)` strictly prior to invoking `move_resize_frame()`.
- Computed `topBarH` dynamically per target monitor to avoid vertical misalignment on displays where the GNOME top bar is absent or positioned differently.
- Scheduled a secondary deferred repositioning step via `GLib.idle_add` to eliminate layout race conditions with Mutter's compositor pass.

---

## 3. 🛠️ KWin Scripting Bridge Hardening & Virtual Desktop Resiliency

During Session 2 (KDE Plasma 6 / KWin) of the FAT protocol:

### 1. Command Dropping Elimination via FIFO Queue (`lib/Services/KWinBridge.vala`)
- **Problem**: When triggering rapid bulk actions (such as "Close All" on an application with multiple open windows) or selecting windows from the dock context menu, commands were dropped because `KWinBridge` used single static variables (`pending_command`, `pending_win_id`). Subsequent commands in the same event cycle overwrote prior commands before the D-Bus call completed.
- **Solution**: Replaced static command slots with an asynchronous FIFO queue (`Gee.ArrayList<CommandEntry>`) serialized as a JSON array. All batched commands are dispatched and executed sequentially by the KWin script without loss. Added `target.closeWindow()` with fallback to `workspace.closeWindow(target)`.

### 2. Virtual Desktop Traversal & Window List Stacking (`KWin Scripting Bridge`)
- **Problem**: Context menu window activation failed for minimized windows or windows on other virtual desktops. The dock also vanished when switching to an empty virtual desktop.
- **Solution**:
  - Replaced `workspace.stackingOrder` lookup in the KWin script with `workspace.windowList()` / `getAllWindows()`, ensuring minimized and background windows across all desktops are discovered.
  - Implemented `switchToDesktopIfNeeded()`: clicking a window on another virtual desktop now automatically transitions the workspace to that desktop and raises the window.
  - Enforced dock stickiness by calling `stick()` in `DockWindow.vala` and setting `onAllDesktops = true`, `skipTaskbar = true`, and `skipPager = true` in KWin.
  - Connected `workspace.currentDesktopChanged` and `window.desktopsChanged` signals, incorporating KWin 6 `isOnDesktop()` support for instant dodge updates across workspace transitions.

---

## 4. ⚡ GNOME Shell / Mutter Bridge Stabilization & Drag Safety

During Session 1 (GNOME / Mutter) of the FAT protocol:

### 1. Pointer Timer Use-After-Free Elimination (`lib/Widgets/DockWindow.vala`)
- **Problem**: A SIGSEGV (`SEGV_MAPERR`) crash occurred when dragging dock icons to reorder them. The legacy 750ms long-press timer initiated via `Gdk.threads_add_timeout` was not cancelled when pointer motion began, attempting to trigger a context menu while a drag grab was in progress.
- **Solution**: Replaced with `GLib.Timeout.add` with safe closure tracking. The timer is now immediately disarmed and destroyed upon pointer motion or drag start.

### 2. Phantom Separator Gap & Orphan Transient Pruning (`lib/DockRenderer.vala` & `DockController.vala`)
- **Problem**: Dragging external files or `.desktop` files onto the dock created orphan transient entries without GUI windows, causing empty gaps between separators.
- **Solution**: Enforced that unpinned applications are only retained as transient items if they have active GUI windows on the compositor. Orphan transient items with 0 windows are cleanly pruned during separator maintenance, and drag boundaries strictly prevent apps from being dropped beyond the Trash separator.

### 3. Left-Click Minimize Toggle Delegation
- **Problem**: Left-clicking an active window's dock icon did not reliably minimize the window under Mutter.
- **Solution**: Delegated toggle evaluation directly to the GNOME Shell extension proxy, querying Mutter's Most Recently Used (MRU) window tab list (excluding dock surfaces) to reliably toggle active windows between minimized and restored states.

### 4. Pressure Reveal & Hover Boundary Geometry (`lib/DockRenderer.vala`)
- **Problem**: Under autohide/intellihide, the dock collapsed prematurely when the cursor approached from certain angles.
- **Solution**: Retained full static dock geometry for hover detection while revealed, expanded the window input shape immediately on unhide rather than waiting for animation completion, and established a 5-point border trigger zone for pressure reveal.

---

## 5. 📦 Summary of Touched Files

| Subsystem | File | Summary of Changes |
| :--- | :--- | :--- |
| **Positioning** | `lib/PositionManager.vala` | Added `%s (%d) [%dx%d @ %d,%d]` unique geometry tagging and spatial coordinate parsing in `get_monitor_for_plug_name()`. |
| **Preferences UI** | `lib/Widgets/PreferencesWindow.vala` | Dynamic `rebuild_monitor_list()` on `monitors_changed`, `updating_monitors` re-entrancy guard, unlocked display combo box. |
| **KWin Bridge** | `lib/Services/KWinBridge.vala` | FIFO queue for batched commands, virtual desktop switching, `onAllDesktops` dock persistence. |
| **GNOME Bridge** | `data/gnome-shell/.../extension.js` | Target monitor assignment prior to `move_resize_frame()`, per-monitor `topBarH`, deferred idle repositioning. |
| **Dock Window** | `lib/Widgets/DockWindow.vala` | Safe closure timer management for drag reordering, multi-monitor geometry tracking. |
| **Testing** | `FAT/2026-10-06 FAT 0.4.3.txt` | Complete test matrix documenting 25+ test cases across Mutter, KWin, and Labwc. |

