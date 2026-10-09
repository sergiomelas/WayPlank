# Wayplank V0.5.2 Detailed Technical Changelog

Release Milestone: **V0.5.2 (First Official Alpha Release)** (Session & Power Management Docklet, Preferences Docklet, Multi-Compositor Session Control)  
Release Date: 2026-10-09  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)  
FAT Protocol: [`FAT/2026-10-09 FAT 0.5.2.txt`](../FAT/2026-10-09%20FAT%200.5.2.txt) (100% PASS Multi-Compositor Test Protocol)

---

## 1. 📋 Overview & Motivation

> 📢 **FIRST OFFICIAL ALPHA RELEASE & END OF MASS DEVELOPMENT PHASE**:  
> Wayplank **V0.5.2 officially marks the first ALPHA release** and concludes the "Mass Development" phase of the project! With our Multi-Compositor HAL (KWin, Labwc, Mutter), comprehensive Wayland bridges, 11 monolithic docklets, self-contained binary GResource fallbacks, and deep signal/memory hardening now complete, the core architecture is rock-solid.  
> **Starting from this release, Wayplank enters a user-driven maintenance phase**: all future modifications, optimizations, and new features will be implemented strictly based on community requests, user issues, and direct feedback.

Wayplank v0.5.2 introduces two major user-facing docklets designed to streamline desktop navigation and system control directly from the dock across all supported Wayland compositors (KDE Plasma/KWin, GNOME Shell/Mutter, Labwc/wlroots, and standard FreeDesktop/systemd environments):

1. **Session & Power Management Docklet (`docklet://session`)**: Provides instant desktop session controls directly from the dock (Lock Screen, Switch User, Log Out, Suspend, Restart, Shut Down) with both one-click contextual menus and a modern, centered GTK Session Dialog.
2. **Dedicated Preferences Docklet (`docklet://preferences`)**: Provides an intuitive one-click launcher for Wayplank Preferences as a convenient alternative to right-clicking empty dock areas or using `Ctrl+Right Click`.
3. **100% Self-Contained Binary Fallback Architecture**: All 11 docklets are backed by 30 high-definition vector icons compiled directly into the binary executable via GResources, eliminating host filesystem pollution and providing universal distribution support.
4. **Digital Clock Visual Fix**: Modernized the digital clock docklet icon with a sleek dark LED tile, eliminating visual confusion with the analog clock docklet.
5. **Factory Acceptance Test (FAT) Protocol**: Complete multi-compositor validation test matrix with 100% PASS across GNOME, KDE Plasma, and Labwc; see [`FAT/2026-10-09 FAT 0.5.2.txt`](../FAT/2026-10-09%20FAT%200.5.2.txt).

---

## 2. 🛠️ Technical Implementation & Architecture

### 1. Embedded Session Docklet (`lib/Items/SessionDockItem.vala`)
- **Docklet URI**: Implemented `docklet://session` with instant dock discovery and persistence.
- **Smart Theme Icon Resolution**: Configured multi-fallback icon resolving (`system-shutdown`, `system-shutdown-symbolic`, `xfsm-shutdown`, `application-exit`, `system-log-out`) ensuring crisp vector icons on any icon theme.
- **Left-Click Interactive Trigger**: Left-clicking the docklet bounces the icon and toggles the centered `SessionWindow` dialog.
- **Comprehensive Right-Click Context Menu**:
  - 🔒 **Lock Screen** (`system-lock-screen`)
  - 👥 **Switch User...** (`system-users`)
  - 🚪 **Log Out...** (`system-log-out`)
  - 💤 **Suspend** (`system-suspend`)
  - 🔄 **Restart...** (`system-reboot`)
  - ⏻ **Shut Down...** (`system-shutdown`)
  - ⚙ **Session Dialog...** (`system-shutdown-symbolic`)
  - 🗑 **Remove from Dock** (`edit-delete`)

### 2. Centered GTK Session Dialog (`lib/Widgets/SessionWindow.vala`)
- **Centered Dialog Layout**: Fully decorated dialog centered on screen, compatible with Labwc's `AutoPlace` centering policy and Mutter/KWin window rules.
- **Session Identity Banner**: Displays current user real name/username and hostname (`Logged in as User @ Host`).
- **Ergonomic 6-Button Action Grid**:
  - `Lock Screen`: Locks display immediately.
  - `Switch User`: Direct transfer to display manager greeter.
  - `Log Out`: Triggers in-place confirmation screen.
  - `Suspend`: System sleep mode.
  - `Restart`: Triggers in-place confirmation screen.
  - `Shut Down`: Triggers in-place confirmation screen.
- **In-Place Confirmation Transition (`GtkStack`)**: Clicking *Log Out*, *Restart*, or *Shut Down* smoothly crossfades within the same dialog into a dedicated confirmation screen (large 54px icon, descriptive title, warning notice, `[Cancel]` / `[Back]` button, and highlighted confirmation action button).
- **Keyboard & Navigation Safety**: `Escape` key smoothly returns from confirmation back to the 6 actions (or closes if on main screen); `Cancel` button is default-focused to prevent accidental activation.

### 3. Cross-Compositor & Session Backend Dispatching
- **KDE Plasma 6 (KWin) Integration & Fixes**:
  - **Switch User**: Resolved `UnknownMethod: No such method 'openSwitchUser' in interface 'org.kde.KSMServerInterface'` (removed in Plasma 6) by integrating the standard FreeDesktop DisplayManager interface: `org.freedesktop.DisplayManager /org/freedesktop/DisplayManager/Seat0 SwitchToGreeter` (or `dm-tool switch-to-greeter`).
  - **Power & Session Control**: Modernized native systemd/logind dispatching (`systemctl poweroff`, `systemctl reboot`, `loginctl`, and `org.freedesktop.login1`), bypassing Plasma 6's known `KWin failed to complete logout` bug; native logout via `org.kde.Shutdown` and `loginctl terminate-session`.
  - **Screen Lock**: Uses `loginctl lock-session` followed by `org.freedesktop.ScreenSaver /ScreenSaver Lock`, reliably engaging KScreenLocker.
- **GNOME Shell (Mutter)**:
  - Native Prompts: Dispatches `gnome-session-quit` with `--power-off`, `--reboot`, and `--logout`.
  - Screen Lock: `org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.Lock`.
- **Labwc / wlroots & Generic Wayland**:
  - Native Exit: Invokes `labwc --exit` or `loginctl terminate-session` on logout.
  - Defensive Confirmation Dialog: Prompts modal GTK confirmation before executing `systemctl poweroff`, `systemctl reboot`, or logout, preventing accidental loss of unsaved work.
  - Universal Lock: Dispatches `loginctl lock-session` with fallbacks to `swaylock`, `waylock`, and `hyprlock`.

### 4. Dedicated Preferences Docklet (`lib/Items/PreferencesDockItem.vala`)
- **Docklet URI**: Implemented `docklet://preferences`.
- **One-Click Preferences Access**: Left-clicking opens the Wayplank Preferences window immediately with icon bounce animation.
- **Context Menu with Direct Subsection Deep-Linking**: Right-clicking the Preferences docklet directly displays the 4 preferences subsections (*Appearance...*, *Behaviour...*, *Applications...*, *Docklets...*), followed by a visual separator, jumping directly to the requested tab inside `PreferencesWindow`.
- **Additional Context Actions**: Provides direct links to *Shortcuts & Gestures...*, *Report a Bug Online...*, *About Wayplank...*, and *Remove from Dock*.
- **Docklets Tab in Preferences**: Added dedicated "Preferences" toggle switch (`sw_docklet_preferences`) in `PreferencesWindow.vala` and `preferences.ui` (Row 6, Column 0).
- **Visual Icons in Docklets Settings Tab**: Each of the 11 docklet switches in the Preferences *Docklets* tab now features its crisp native vector icon (35px) aligned next to the docklet name, providing immediate visual recognition and polish.
- **Iconic Anchor Visual Identity**: Uses the classic Plank/Wayplank anchor icon (`plank` / `wayplank`) for the Preferences docklet, completely avoiding visual collision with host OS System Settings (`preferences-system` / `systemsettings`).

### 5. 🛡️ Deep Bug Hunting & Core Hardening
- **PreferencesWindow Signal & Lifecycle Safety**: Added `destroy` signal hook and `signals_connected` guard in `PreferencesWindow.vala`, properly disconnecting `prefs.notify`, `controller.default_provider.elements_changed`, and `monitors_changed`. Eliminates circular references, memory leaks, and phantom callbacks on destroyed widgets.
- **Shutdown Crash Prevention (Null Pointer Safety)**: Hardened destructors across `PositionManager`, `DragManager`, `HideManager`, and `DockRenderer` to safely guard against null `controller`, `controller.window`, or `controller.hide_manager` during asynchronous disposal, eliminating potential `SIGSEGV` exit crashes.
- **KWinTrashBridge & Theme Signal Disconnection**: Named handler connections in `TrashDockItem` and added `~Theme()` destructor to cleanly disconnect `gtk-theme-name` from the global `Gtk.Settings` singleton, preventing object retention.
- **Session Dialog Keyboard Focus Restoration**: Promoted `actions_cancel_btn` to instance field in `SessionWindow.vala`, automatically restoring keyboard focus to the Cancel button when returning from the confirmation page via `Escape` or the *Cancel* button.
- **MPRIS Docklet Performance Hardening**: Replaced separate blocking D-Bus calls with a single `GetAll("org.mpris.MediaPlayer2.Player")` invocation and reduced timeout from 500ms to 50ms (and polling interval to 3s), eliminating dock UI thread stutters when media players are lagging.
- **Volume Docklet Process Optimization**: Added support for WirePlumber (`wpctl`) and combined PulseAudio mute/volume retrieval into a single command invocation, cutting process spawns by over 50%.
- **Dynamic Power Supply Discovery**: Updated `BatteryDockItem` to enumerate `/sys/class/power_supply/` and detect any node declaring `type == Battery`, adding support for `CMB1`, `BATC`, `axp20x-battery`, and laptop UPS units.
- **CSS Style Provider Leaks**: Added scoped screen cleanup in `HelpWindow.vala` destructor to remove custom CSS providers from `Gdk.Screen`.
- **Wlr-Toplevel String Leak & Focus Thrashing**:
  - `lib/Services/wlr-toplevel-bridge.c`: Fixed memory leak of `h->data` string in `handle_toplevel_closed()` before `g_list_delete_link`.
  - Removed redundant `zwlr_foreign_toplevel_handle_v1_activate` loop in `toggle_desktop()` to prevent compositor event/focus thrashing.
  - Added `is_wayplank_toplevel()` filtering to exclude Wayplank's own windows (dialogs, preferences, help) from toplevel window lists and intersection calculations.
- **Multi-Desktop Environment Detection (Colon-Separated Strings & Plasma)**:
  - `lib/Services/Environment.vala`: Added support for standard FreeDesktop colon-separated `XDG_CURRENT_DESKTOP` strings (e.g. `KDE:Plasma`, `ubuntu:GNOME`, `budgie:GNOME`).
  - Added support for `plasma` and `plasmawayland` session names in `XdgSessionDesktop.from_single_string()`.
- **EnvironmentSettings Bitflag Desktop Resolution**: Replaced naive `switch` statement with `environment_is_session_desktop()` bitmask checks in `EnvironmentSettings.vala`, correctly resolving notification settings on composite sessions (such as Ubuntu GNOME).
- **Matcher Singleton Signal Leak**: Replaced anonymous closure on `WindowControl.get_default().state_changed` with a named handler and disconnected it in `~Matcher()`, eliminating permanent object retention.
- **ApplicationIdentity Null Path Safeguard**: Added null-guard for `desktop_file.get_path()` before calling `key_file.load_from_file()`, preventing GLib assertion errors on virtual URIs.
- **System.open() Null Pointer Guard**: Made the `file` parameter in `System.open()` nullable and added an immediate null check to prevent dereferencing null pointers.
- **Labwc & Mutter Backend Destruction Cleanup**: Added explicit destructors to `LabwcBackend` and `MutterBackend` to unwatch D-Bus names, cancel pending debounce timers, and release static singleton references upon disposal.
- **PoofWindow Drawing & Timer Hardening**: Guarded against null `poof_image` in `PoofWindow.draw()` to prevent Cairo/GDK errors, and properly reset `animation_timer_id` to `0U` upon cancellation.
- **DockWindow Disposal Null-Safety**: Guarded against null `controller.prefs` in `~DockWindow()` and explicitly destroyed `menu` to avoid GTK menu retention.
- **DockController Lifecycle & Destruction Hardening**: Added `is_initialized` state tracking to prevent disconnecting non-connected signals, and explicitly invoked `hover.destroy()` and `window.destroy()`.
- **Unity LauncherEntry Timer Cleanup**: Cancelled active per-entry timers in `~Unity()` and during periodic cleanup in `clean_up_launcher_entries()`.
- **Screenshot Docklet Native D-Bus & Wayland Integration**:
  - Replaced external shell-spawned `gdbus call` subprocesses with native GLib D-Bus calls via `Bus.get_sync (BusType.SESSION)` for interactive and fullscreen captures.
  - Used `Gtk.show_uri_on_window()` for opening screenshots folders across all Wayland file managers.
- **Atomic Launcher Creation**: Hardened `ItemFactory.make_dock_item()` with `make_directory_with_parents()` and atomic file replacement (`replace()`).

### 6. 🎨 Docklet Visual Enhancements & Digital Clock Icon Fix
- **Digital Clock Visual Fix (`preferences.ui` & `DigitalClockDockItem.vala`)**: Fixed an issue where the Digital Clock docklet displayed an analog dial icon with hands (`alarm-clock` / `preferences-system-time`), visually duplicating the Analog Clock docklet. Digital Clock now renders a dedicated modern tile icon with digital numerals (`org.kde.plasma.digitalclock` / `digital-clock.svg`).
- **Preferences Dialog Visual Icons**: Bound all 11 docklet image items in `PreferencesWindow.vala` (`img_docklet_*`) with automatic runtime fallback: if the host icon theme contains the icon, it is displayed natively; otherwise, the internal vector resource is scaled to 35px, guaranteeing crisp icons regardless of desktop environment or minimal install profile.

### 7. 📦 100% Self-Contained Binary Fallback Icons Architecture
- **Pure Binary GResource Encapsulation**: All 11 docklets are backed by 30 high-definition vector SVG assets compiled directly into the `wayplank` executable ELF binary under `/net/launchpad/plank/docklets/`.
- **Dynamic Volume Scale**: Full multi-state scale embedded into binary resources:
  - `volume-high.svg` (High volume $\ge 75\%$)
  - `volume-medium.svg` (Medium volume $35\% - 74\%$)
  - `volume-low.svg` (Low volume $1\% - 34\%$)
  - `volume-muted.svg` (Muted / $0\%$)
- **Dynamic Battery Scale**: Complete 12-state vector battery scale embedded into binary resources:
  - Discharge levels: `battery-full.svg` ($\ge 90\%$), `battery-good.svg` ($65\% - 89\%$), `battery-low.svg` ($35\% - 64\%$), `battery-caution.svg` ($15\% - 34\%$), `battery-empty.svg` ($< 15\%$)
  - Charging states: `battery-full-charging.svg`, `battery-good-charging.svg`, `battery-low-charging.svg`, `battery-caution-charging.svg`, `battery-empty-charging.svg`
  - Fixed / VM power: `battery-ac-adapter.svg` (AC power connection), `battery-missing.svg` (no battery present)
- **Dynamic Trash & MPRIS States**:
  - Trash empty (`trash.svg`) and full (`trash-full.svg`)
  - Media player default (`mpris.svg`), playing (`mpris-play.svg`), and paused (`mpris-pause.svg`)
- **Zero Host Filesystem Pollution**: Fallback assets are strictly kept inside the binary. The Debian package installs only the application icon (`wayplank.svg` / `plank.svg`), ensuring complete distribution independence, zero host file collision, and standalone portability.

### 8. ⚖️ GPL-3.0 License & Integrated Asset Attribution
- **Core Codebase**: Licensed under **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.
  - © 2011–2015 Robert Dyer, Michal Hruby, Rico Tzschichholz, and Plank contributors.
  - © 2026 Sergio Melas (<sergiomelas@gmail.com>).
- **Integrated Fallback Vector Assets (`data/docklets/`)**:
  - High-definition scalable vector icons derived from the KDE Breeze / FreeDesktop icon sets.
  - © 2014–2026 KDE Community / Breeze Icon Artists, © 2026 Sergio Melas.
  - Licensed under **LGPL-3.0-or-later** / **GPL-3.0-or-later** (fully compatible with GPL-3.0).
- **Debian Package Compliance**:
  - Machine-readable DEP-5 copyright specification installed to `/usr/share/doc/wayplank/copyright` (with symlink `/usr/share/doc/plank/copyright`).
  - Package description in Debian `control` explicitly references GPL-3.0+ licensing.

---

## 3. 🧪 Verification & Build Status

- **Compilation**: Clean build using `valac` with 0 errors and 0 warnings.
- **Binary**: Standalone binary compiled in `build/wayplank` (`Wayplank 0.5.2`).
- **Embedded Resources**: Verified with `gresource list build/wayplank` (all 30 docklet fallback SVGs present).
- **Debian Package**: Built and validated as `build/wayplank_0.5.2_amd64.deb` (includes `/usr/share/doc/wayplank/copyright` and clean hicolor icons).
- **FAT Validation**: 100% PASS across all tested compositors (KWin, Mutter, Labwc); see [`FAT/2026-10-09 FAT 0.5.2.txt`](../FAT/2026-10-09%20FAT%200.5.2.txt).
