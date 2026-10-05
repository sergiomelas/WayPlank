# Wayplank V0.4.3 Detailed Technical Changelog

Release Milestone: **V0.4.3** (Multi-Compositor HAL Release — Native Labwc / wlroots Engine, GNOME Shell / Mutter Monolithic Bridge & Strict Coordinate Isolation)  
Release Date: 2026-10-05  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 🌐 Multi-Compositor Hardware Abstraction Layer (HAL) Architecture

- **Unified Abstract Backend Contract (`WindowBackend.vala`)**:
  - Formalized the complete window management interface into a compositor-agnostic abstract class:
    - Window list retrieval (`get_window_list()`, `get_window_ids()`, `get_windows_by_app()`).
    - Focus and state introspection (`get_active_window()`, `is_window_active()`, `is_window_minimized()`).
    - Window actions (`activate_window()`, `minimize_window()`, `close_window()`, `toggle_window_state()`).
    - Multi-window cycling (`activate_next_window()`, `activate_previous_window()`).
    - Intellihide and dodge geometry predicates (`active_window_intersects()`, `maximized_window_intersects()`).
    - Subsystem signals (`window_list_changed`, `active_window_changed`, `window_state_changed`, `intellihide_state_changed`).
    - System resume lifecycle handling (`handle_system_resume()`).
- **Dynamic Runtime Compositor Probing (`WindowControl.vala`)**:
  - Implemented automatic zero-configuration compositor discovery at startup via `WindowControl.detect_backend()`.
  - Probes the active Wayland display registry for the presence of the `zwlr_foreign_toplevel_manager_v1` global interface using a low-overhead Wayland roundtrip (`wlr_toplevel_bridge_probe()`).
  - **Dynamic Delegation**:
    - If `zwlr_foreign_toplevel_manager_v1` is detected on the Wayland bus: automatically instantiates and binds `LabwcBackend`.
    - If not present (or under KDE Plasma): automatically falls back to `KWinBackend` using the KWin scripting D-Bus bridge.
  - Eliminated manual environment flags or command-line parameters; Wayplank seamlessly adapts to the running compositor environment out of the box.

---

## 2. ⚡ Native Labwc & wlroots Protocol Engine (`LabwcBackend` & C Protocol Bridge)

- **Wayland Protocol Code Generation**:
  - Extracted and compiled the official `wlr-foreign-toplevel-management-unstable-v1.xml` specification into high-performance C source and client headers:
    - `lib/Protocols/wlr-foreign-toplevel-management-client-protocol.h`
    - `lib/Protocols/wlr-foreign-toplevel-management-protocol.c`
- **Native C Protocol Bridge (`lib/Services/wlr-toplevel-bridge.c`)**:
  - Engineered an asynchronous, thread-safe C bridge interfacing directly with `libwayland-client` without external intermediary daemons:
    - Maintains a live linked list of `wlr_toplevel_entry_t` handles tracking title, `app_id`, active/focused state, minimized state, and maximized state.
    - Listens to core toplevel events: `handle_toplevel_title`, `handle_toplevel_app_id`, `handle_toplevel_state` (handling `MAXIMIZED`, `MINIMIZED`, `ACTIVATED`, `FULLSCREEN`), and `handle_toplevel_closed`.
    - Dispatches native client requests:
      - `zwlr_foreign_toplevel_handle_v1_set_activated` (window raise/focus)
      - `zwlr_foreign_toplevel_handle_v1_set_minimized` / `unset_minimized` (window minimize/unminimize)
      - `zwlr_foreign_toplevel_handle_v1_set_maximized` / `unset_maximized` (window maximize toggle)
      - `zwlr_foreign_toplevel_handle_v1_close` (clean window termination)
    - Dispatches real-time GSource callbacks into the GLib main event loop (`g_idle_add` / `wlr_toplevel_bridge_step`) ensuring zero thread contention with GTK.
- **Vala VAPI Interoperability (`vapi/wlr-bridge.vapi`)**:
  - Created complete Vala bindings for the C bridge, exposing toplevel iteration, callback registration, and command queueing directly to `LabwcBackend.vala`.

---

## 3. 🎯 Application Indicator Reactive Buffer Invalidation & Lifecycle Fix

- **Root Cause Analysis**:
  - Diagnostic testing under both Labwc and KWin identified three interrelated failure modes that caused indicator dots (the running application markers beneath dock icons) to fail to render, require mouse hover to appear, or remain visible after window closure:
    1. **Lack of Cairo Invalidation**: `Indicator` in `lib/Items/DockItem.vala` was implemented as a simple Vala auto-property (`public int Indicator { get; set; default = 0; }`). Setting the indicator count updated the integer value but never cleared the cached Cairo foreground buffer (`reset_foreground_buffer()`) or informed the dock surface that a redraw was necessary (`needs_redraw()`). As a result, the dock only redrew the icon if a subsequent hover event forced buffer re-rendering.
    2. **GObject Property Notification Mismatch**: In `lib/Items/DockItemProvider.vala`, signal listeners were connected only to PascalCase notifications (`notify["Indicator"]`). Vala's GObject generation translates properties to lowercase canonical names (`notify::indicator`), causing changes in indicator count to be silently ignored by the provider.
    3. **Missing Initialization for Transient Items**: Newly launched unpinned applications (`TransientDockItem.vala`) did not invoke `update_indicator(false)` during instantiation, leaving newly created transient icons without an indicator count until a later mouse movement or window focus shift occurred.
- **Full Resolution Implemented**:
  - **Explicit Reactive Setter (`DockItem.vala`)**:
    ```vala
    public int Indicator {
        get { return _indicator; }
        set {
            if (_indicator != value) {
                _indicator = value;
                reset_foreground_buffer ();
                needs_redraw ();
            }
        }
    }
    ```
  - **Dual Notification Binding (`DockItemProvider.vala`)**: Connected both canonical lowercase (`notify["indicator"]`, `notify["state"]`, `notify["last-clicked"]`) and Vala property notifications to guarantee immediate dock relayout.
  - **Immediate Constructor Synchronization (`TransientDockItem.vala` & `ApplicationDockItem.vala`)**: Added immediate `update_indicator(false)` execution upon item construction. Indicator dots now render immediately with zero latency upon window creation across both pinned and unpinned applications.

---

## 4. 🪟 Cross-Compositor Bi-Directional Show Desktop Engine

- **State Desynchronization Elimination**:
  - Previously, Show Desktop relied on internal boolean toggles (`showing_desktop`) that fell out of sync whenever a window minimized/restored outside of Wayplank's control or when state changes were received during bulk minimization.
- **True Visibility-State Engine**:
  - In `lib/Services/wlr-toplevel-bridge.c`:
    - `wlr_toplevel_bridge_toggle_show_desktop()` now inspects the real visibility of all tracked windows by calculating `any_unminimized`:
      - **If any window is unminimized**: Iterates over all toplevel handles and sets `zwlr_foreign_toplevel_handle_v1_set_minimized` on every unminimized window.
      - **If all windows are already minimized**: Iterates over all toplevel handles and calls `zwlr_foreign_toplevel_handle_v1_unset_minimized` to atomically restore every window, followed by `zwlr_foreign_toplevel_handle_v1_set_activated` on the topmost restored window.
    - Removed premature boolean resets during intermediate window state notifications.
  - In `lib/Services/KWinBridge.vala`:
    - Synchronized with `workspace.windowList()` checking `anyVisible` across normal client windows.
  - Decoupled `ShowDesktopDockItem.vala` to route through `WindowControl.queue_command ("desktop", "toggle_desktop")`, providing an identical, rock-solid user experience across all supported compositors.

---

## 5. 🛡️ Wayland Security Isolation & wlroots Intellihide Strategy

- **Security Model Context**:
  - Under the Wayland security architecture, unprivileged client applications (including docks, panels, and taskbars) are strictly prohibited from inspecting the global coordinates ($x, y, \text{width}, \text{height}$) of other client windows to prevent keylogging and screen layout snooping.
  - The `wlr-foreign-toplevel-management-unstable-v1` protocol intentionally omits coordinate attributes. Upstream Labwc maintainers explicitly decline implementing private IPC protocols (such as Sway's tree IPC).
- **Intelligent State-Based Dodge Implementation & Honest UI Matrix**:
  - For wlroots/Labwc sessions, Wayplank implements a robust, privacy-compliant hide architecture:
    - **`DODGE_MAXIMIZED`**: `maximized_window_intersects` evaluates native Wayland `MAXIMIZED` and `FULLSCREEN` state events, reliably retracting the dock for maximized/fullscreen windows while keeping it visible for floating applications.
    - **`AUTOHIDE` & `NONE`**: Operate with 100% fidelity via layer-shell edge detection and exclusive zone reservation.
    - **Preferences UI Filtering**: Under Labwc, unsupported spatial hide modes (`Intelligent`, `Window Dodge`, `Dodge Active`) are made insensitive and explicitly labeled `(Requires KWin)`.
    - **Transparent Runtime Fallback**: Stored preferences from desktop switching (e.g. migrating from Plasma to Labwc) safely degrade to `DODGE_MAXIMIZED` at runtime without corrupting or overwriting the user's configuration on disk.
    - **Field-Tested & Validated**: Passed complete end-to-end user experience and protocol verification under native LXQt 2.x and XFCE 4.20 on Labwc.

---

## 6. 🧹 Subsystem Decoupling & Clean Architecture Polish

- **Abstract System Resume (`handle_system_resume`)**:
  - Elevated sleep/wake recovery from KWin-specific code to the abstract `WindowBackend` and `WindowControl` classes.
  - Cleaned `lib/DockController.vala` of direct `KWinBridge` references, routing system resume notifications cleanly through `WindowControl.handle_system_resume()`.
- **Conditional KDE Plasma Trash Bridge (`KWinTrashBridge.vala`)**:
  - Guarded Plasma `org.kde.KDirNotify` D-Bus signals with `WindowControl.is_kwin()`, preventing unneeded D-Bus activation attempts when running under Labwc or other desktop environments while maintaining full Trash drag-and-drop and occupancy monitoring.
- **Build System Conformance**:
  - Updated `BuildBin.sh` and `BuildDeb.sh` to package and compile `wlr-foreign-toplevel-management-protocol.c`, `wlr-toplevel-bridge.c`, `vapi/wlr-bridge.vapi`, and `-lwayland-client`.
  - Maintained zero compiler warnings and zero errors across the entire codebase.

---

## 7. 🦊 Native GNOME Shell / Mutter Architecture & Monolithic Bridge (`MutterBackend.vala`)

- **100% Monolithic Architecture (Zero Loose Files)**:
  - The complete GNOME Shell extension JavaScript (`extension.js`), metadata (`metadata.json`), and D-Bus interface definition (`org.wayplank.GnomeBridge`) are embedded directly as raw string constants within `lib/Services/MutterBackend.vala`.
  - At startup, `MutterBackend` self-deploys and enables the extension in `~/.local/share/gnome-shell/extensions/wayplank-bridge@wayplank.org/` if absent or updated, eliminating external installer scripts and packaging fragmentation.
- **Permanent Elimination of GNOME Attention Notification Banners**:
  - GNOME Shell's `WindowAttentionHandler` normally generates unwanted notification banners ("wayplank-hover is ready", "Wayplank Preferences is ready") when Wayplank maps utility or tooltip windows without decoration.
  - Implemented proactive monkey-patching of `Meta.Window.prototype.is_skip_taskbar` inside the GNOME Shell extension for all Wayplank window roles (`dock`, `hover`, `preferences`, `help`), ensuring `WindowAttentionHandler` ignores them completely.
  - Connected `window-demands-attention` and `window-marked-urgent` signals to instantly reset `demands_attention = false`.
- **Strict HAL Coordinate Isolation (Zero Regressions on Layer Shell)**:
  - **KWin & Labwc / wlroots (`GtkLayerShell.is_supported()` == `true`)**:
    - Retains 100% pure relative margin calculations (`x - width / 2`, `y - height / 2`) anchored to the monitor edge via `GtkLayerShell.set_margin()`. Zero screen-offset contamination.
  - **GNOME Shell / Mutter (`!GtkLayerShell.is_supported()` && `WindowControl.is_mutter()`)**:
    - Confined absolute screen coordinate transformations (`mon_x + ...`, `mon_y + ...`) and D-Bus calls strictly inside the non-Layer Shell fallback branch.
    - Enhanced GNOME Shell extension `_applyHoverPosition()` to dynamically measure the real frame rect of the dock window (`dockWin.get_frame_rect()`), adjusting tooltip margins to eliminate overlap with the dock bar and GNOME panel across all four screen edges (`Top`, `Bottom`, `Left`, `Right`).
- **Clean Dialog Classification & Window Centering**:
  - Hardened `_classifyWindow()` to prevent Preferences and Shortcuts windows from being misclassified as dock surfaces during early GTK allocation.
  - Implemented dynamic first-frame centering (`_centerWindow()`) for Preferences and Help dialogs on GNOME Shell Wayland.

---

## 8. 🔮 GNOME / Mutter Next Steps & Roadmap (Window Geometry for Full Dodge & Intellihide)

- **Phase 1 Mutter Integration Completed**:
  - Successfully delivered the foundational GNOME Shell / Mutter integration milestone: monolithic embedded extension auto-deployment, D-Bus session communication, live window list tracking, activation, minimization, closing, Show Desktop toggle, total suppression of unwanted notification banners, dialog centering, and dock edge placement.
- **Roadmap for Full Spatial Dodge & Intellihide**:
  - Full spatial Dodge (`Dodge Active`, `Window Dodge`) and Intellihide under GNOME Shell require real-time knowledge of client window geometries across the active workspace.
  - The next development milestone will expand the extension D-Bus bridge interface (`org.wayplank.GnomeBridge`) to stream window bounding boxes (`MetaWindow.get_frame_rect()`) directly to `MutterBackend`:
    - Track active and maximized window bounding boxes across monitors in real time.
    - Feed live geometry data into `active_window_intersects()` and `maximized_window_intersects()` predicates.
    - Finalize poof animation and dodge state transitions in the next iteration.



