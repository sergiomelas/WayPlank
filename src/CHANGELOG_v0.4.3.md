# Wayplank V0.4.3 Detailed Technical Changelog

Release Milestone: **V0.4.3** (Multi-Compositor HAL Release — Native Labwc / wlroots Engine, Zero-Latency Indicators & Subsystem Decoupling)  
Release Date: 2026-10-03  
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
  - Updated `BuilsBin.sh` and `BuildDeb.sh` to package and compile `wlr-foreign-toplevel-management-protocol.c`, `wlr-toplevel-bridge.c`, `vapi/wlr-bridge.vapi`, and `-lwayland-client`.
  - Maintained zero compiler warnings and zero errors across the entire codebase.

