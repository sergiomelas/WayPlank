# Wayplank V0.5.2 Detailed Technical Changelog

Release Milestone: **V0.5.2 (First Official Alpha Release)** (Session & Power Management Docklet, Preferences Docklet, Multi-Compositor Session Control)  
Release Date: 2026-10-09  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)  
FAT Protocol: [`FAT/2026-10-09 FAT 0.5.2.txt`](../FAT/2026-10-09%20FAT%200.5.2.txt) (Multi-Compositor Test Protocol)

---

## 1. 📋 Overview & Motivation

> 📢 **FIRST OFFICIAL ALPHA RELEASE & END OF MASS DEVELOPMENT PHASE**:  
> Wayplank **V0.5.2 officially marks the first ALPHA release** and concludes the "Mass Development" phase of the project! With our Multi-Compositor HAL (KWin, Labwc, Mutter), comprehensive Wayland bridges, 14 monolithic docklets, categorized layout architecture, self-contained binary GResource fallbacks, and deep signal/memory hardening now complete, the core architecture is rock-solid.  
> **Starting from this release, Wayplank enters a user-driven maintenance phase**: all future modifications, optimizations, and new features will be implemented strictly based on community requests, user issues, and direct feedback.

Wayplank v0.5.2 introduces major user-facing docklets, an advanced categorized layout engine, and core stability hardening designed to deliver a rock-solid, native dock experience across all supported Wayland compositors (KDE Plasma/KWin, GNOME Shell/Mutter, Labwc/wlroots, and standard FreeDesktop/systemd environments):

1. **Expanded 14 Monolithic Docklets Suite**: Added 5 new native docklets in v0.5.2:
   - **Session & Power Management (`docklet://session`)**: Instant desktop session controls (Lock Screen, Switch User, Log Out, Suspend, Restart, Shut Down) with both one-click contextual menus and a modern, centered GTK Session Dialog.
   - **Dedicated Preferences (`docklet://preferences`)**: One-click launcher for Wayplank Preferences with direct deep-linking to all settings sections.
   - **Removable Drive Ejector (`docklet://ejector`)**: Automount/unmount management via GIO `VolumeMonitor` and UDisks2, safe detachment desktop notifications, and dynamic eject menu.
   - **Screen Brightness (`docklet://brightness`)**: Hardware backlight control via `org.freedesktop.login1` Session SetBrightness / `brightnessctl`, mouse-wheel brightness stepping (±5%), preset click cycling (25% → 50% → 75% → 100%), and percentage badge.
   - **Weather Forecast (`docklet://weather`)**: Real-time atmospheric updates via Open-Meteo API, dynamic weather status icons, temperature badge (°C / °F), 3-day forecast popup (`WeatherWindow`), and configuration dialog (`WeatherCityDialog`) with automatic IP geolocation fallback.
2. **7×2 Symmetrical Preferences Docklets Grid**: Redesigned the Preferences *Docklets* tab into a balanced 7×2 grid accommodating all 14 docklets with native 35px vector icons and instant live toggle switches.
3. **Categorize Items Layout Architecture (`categorize-items`)**:
   - Organizes dock items into dedicated semantic groups: `[Folders] | [Docklets] | [Pinned Apps] | [Unpinned Transients] | [Trash]`.
   - Dynamic separator suppression: dividers automatically hide when an adjacent category contains 0 items, preventing phantom gaps.
   - Clamped category drag bounding: items are strictly constrained within their category boundary during drag-and-drop.
   - Cross-separator drag pin/unpin: dragging an application icon across the transient/pinned divider automatically pins or unpins it.
   - Clean state preservation: independent serialization (`FreeDockItems` vs `CategorizedDockItems`) restoring exact user placement when toggled.
4. **Cairo-Dock Style Folder Launcher Menu (`FolderMenuWindow`)**:
   - **Left-Click Interactive Menu**: Left-clicking a folder dock item toggles a fast, non-modal overlay displaying subdirectories, application launchers, and documents without locking the desktop.
   - **Fluid 60 FPS Zoom Following**: Window anchors dynamically follow the horizontal center (`val.center.x`) and vertical elevation during dock magnification, keeping dock hover zoom animations completely smooth.
   - **Decoupled Click Bounce**: Left-clicking triggers the standard icon bounce animation while the popup menu remains rock-steady and decoupled from the bounce height (`pm.get_visual_thickness_for_item (TargetItem)`) for effortless item selection.
   - **Dark Tooltip Styling**: Rendered with exact tooltip aesthetics (`rgba(28, 28, 30, 0.95)`, 7px rounded corners, 1px border `rgba(255, 255, 255, 0.18)`), crisp white typography, and illuminated mouseover highlight (`rgba(255, 255, 255, 0.20)`).
   - **Subdirectory Drill-Down & History**: Browse nested folders with smooth back-button navigation, execute `.desktop` applications, and open documents directly in default apps.
   - **Intelligent Auto-Dismiss**: Automatically closes when hovering another dock item or upon a 150ms pointer exit timer.
   - **Dedicated Right-Click Menu**: Right-click on folder items is reserved exclusively for dock management (*Keep in Dock*, *Open in File Browser*, *Preferences*, *About Wayplank*).
5. **Icon Size Slider Resiliency & Auto-Shrink Guard**: Fixed `PositionManager` auto-shrink calculation to prevent crushing icons to the 24px minimum during rapid slider resizing or uninitialized monitor geometry.
6. **Universal Docklet Context Menu Consistency**: Appended standard dock actions (*Preferences...*, *Shortcuts & Gestures...*, *Report a Bug...*, *About Wayplank...*) to all 14 docklets via `Utils.append_docklet_menu_items()`, and placed *Preferences...* at the top of the Preferences docklet context menu.
7. **Layer-Shell Surface Isolation**: Replaced unconditional `window.present()` calls with a Layer Shell guard (`!GtkLayerShell.is_supported ()`), preventing the dock from stealing keyboard focus from active application windows upon display changes or redraws.
8. **100% Self-Contained Binary Fallback Architecture**: All 14 docklets are backed by 33 high-definition vector icons compiled directly into the binary executable via GResources, eliminating host filesystem pollution and providing universal distribution support.
9. **Digital Clock Visual Fix**: Modernized the digital clock docklet icon with a sleek dark LED tile, eliminating visual confusion with the analog clock docklet.
10. **Factory Acceptance Test (FAT) Protocol**: Complete multi-compositor validation test matrix with 100% PASS across GNOME, KDE Plasma, and Labwc; see [`FAT/2026-10-09 FAT 0.5.2.txt`](../FAT/2026-10-09%20FAT%200.5.2.txt).

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
- **Context Menu with Direct Subsection Deep-Linking**: Right-clicking the Preferences docklet directly displays the 4 preferences subsections (*Preferences...*, *Appearance...*, *Behaviour...*, *Applications...*, *Docklets...*), followed by a visual separator, jumping directly to the requested tab inside `PreferencesWindow`.
- **Additional Context Actions**: Provides direct links to *Shortcuts & Gestures...*, *Report a Bug Online...*, *About Wayplank...*, and *Remove from Dock*.
- **Iconic Anchor Visual Identity**: Uses the classic Plank/Wayplank anchor icon (`plank` / `wayplank`) for the Preferences docklet, completely avoiding visual collision with host OS System Settings (`preferences-system` / `systemsettings`).

### 5. Removable Drive Ejector Docklet (`lib/Items/EjectorDockItem.vala`)
- **Docklet URI**: Implemented `docklet://ejector`.
- **Removable Media Management**: Monitors mounted volumes using GIO `VolumeMonitor` and UDisks2.
- **Contextual Operations**:
  - Left-click safely unmounts and ejects the active removable drive (or shows a drive selection menu if multiple removable drives are present).
  - Emits desktop notifications confirming safe removal ("*Drive safely removed*").
  - Right-click context menu dynamically lists all mounted removable media with individual "Eject / Safe Remove" actions.
- **Fallback Vector Resource**: Embedded `data/docklets/ejector.svg` in GResources with fallback resolution in `DrawingService.vala`.

### 6. Screen Brightness Docklet (`lib/Items/BrightnessDockItem.vala`)
- **Docklet URI**: Implemented `docklet://brightness`.
- **Hardware Backlight Control**: Interfaces with `org.freedesktop.login1.Session.SetBrightness` (unprivileged D-Bus interface) with fallbacks to `brightnessctl` and `light`.
- **Visual Percentage Badge**: Real-time badge counter on the dock item displaying current screen brightness percentage (e.g., `75%`).
- **Interactive Controls**:
  - Mouse-wheel scroll over the docklet increases / decreases brightness by 5% increments.
  - Left-click cycles through quick brightness presets (25% → 50% → 75% → 100%).
  - Right-click context menu provides instant preset jumps (10%, 25%, 50%, 75%, 100%) and launches system display settings.
- **Fallback Vector Resource**: Embedded `data/docklets/brightness.svg` in GResources.

### 7. Weather Forecast Docklet (`lib/Items/WeatherDockItem.vala`)
- **Docklet URI**: Implemented `docklet://weather`.
- **Real-Time Atmospheric Data**: Fetches live weather conditions via the high-performance Open-Meteo REST API.
- **Dynamic Status Icons & Badge**:
  - Dynamically updates icon to match current weather (Clear/Sun, Few Clouds, Overcast, Rain/Showers, Snow, Thunderstorm).
  - Badge counter displays current temperature in °C or °F (e.g., `18°` or `64°`).
- **Modern Forecast Window (`lib/Widgets/WeatherWindow.vala`)**:
  - Left-clicking opens a dedicated, centered GTK window displaying current temperature, "feels like", humidity, wind speed, and 3-day forecast summary cards.
- **Location Configuration Dialog (`lib/Widgets/WeatherCityDialog.vala`)**:
  - Right-clicking allows opening the location settings dialog to specify custom city/country coordinates and toggle Celsius / Fahrenheit units.
  - Automatic IP geolocation fallback via `ip-api.com` when city coordinates are unconfigured.
- **Fallback Vector Resource**: Embedded `data/docklets/weather.svg` in GResources.

### 8. Categorize Items Layout Architecture (`lib/DockPreferences.vala`, `lib/DragManager.vala`, `lib/Items/DefaultApplicationDockItemProvider.vala`)
- **Semantic Multi-Zone Grouping**: Categorized layout dynamically groups dock items into:
  `[Folders] | [Docklets] | [Pinned Apps] | [Unpinned Transients] | [Trash]`
- **Dynamic Separator Suppression**: Dividers automatically hide when an adjacent category contains 0 items, preventing phantom gaps or orphaned separators.
- **Category Drag Bounding**: Drag-and-drop operations in `DragManager.vala` strictly clamp items within their respective category boundaries (Folders within Folders, Docklets within Docklets, Apps within Apps).
- **Cross-Separator Drag Pin/Unpin**: Dragging an application icon across the transient/pinned divider automatically pins or unpins it.
- **Independent State Preservation**: Persists `FreeDockItems` and `CategorizedDockItems` separately in GSettings (`net.launchpad.plank.gschema.xml`), cleanly restoring exact original user ordering when toggling between free and categorized modes.

### 9. Icon Size Slider Resiliency & Auto-Shrink Guard (`lib/PositionManager.vala`)
- **Geometry Auto-Shrink Guard**: Fixed `PositionManager.update_max_icon_size()` to prevent crushing icons to the minimum 24px during slider resizing.
- **Monitor Geometry Initialization**: Added safeguards against zero or negative monitor geometry and uninitialized dock dimensions.
- **Smooth Scaling Cadence**: Preserves user-selected icon size across all valid ranges (24px to 64px+) without spurious shrinkage triggered by separator count.

### 10. Universal Docklet Context Menu Consistency (`lib/Services/Utils.vala`)
- **Consistent Dock Actions**: Implemented `Utils.append_docklet_menu_items()` ensuring ALL 14 docklets (Trash, CPU, Clock, Desktop, Digital Clock, MPRIS, Battery, Volume, Screenshot, Session, Preferences, Ejector, Brightness, Weather) have standard dock actions appended to their right-click menus:
  - *Preferences...*
  - *Shortcuts & Gestures...*
  - *Report a Bug...*
  - *About Wayplank...*
- **Preferences Docklet Placement**: Preferences docklet displays *Preferences...* at the very top of its right-click menu for instant access.

### 11. Layer-Shell Surface Isolation & Focus Theft Prevention (`lib/DockController.vala`, `lib/Widgets/DockWindow.vala`)
- **Unwanted Focus Theft Elimination**: Replaced unconditional `window.present()` calls in `DockController.vala` and `DockWindow.vala` with `if (!GtkLayerShell.is_supported ()) window.present();`.
- **Compositor Surface Integrity**: Layer Shell surfaces maintain absolute isolation without stealing keyboard focus or active window state during dock redraws, theme changes, or monitor reconfiguration.

### 12. 🛡️ Deep Bug Hunting & Core Hardening
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
  - Stationary capture animation: eliminated mid-air animation jump across screen edges during capture.
- **Atomic Launcher Creation**: Hardened `ItemFactory.make_dock_item()` with `make_directory_with_parents()` and atomic file replacement (`replace()`).

### 13. 🎨 Docklet Visual Enhancements & Digital Clock Icon Fix
- **Digital Clock Visual Fix (`preferences.ui` & `DigitalClockDockItem.vala`)**: Fixed an issue where the Digital Clock docklet displayed an analog dial icon with hands (`alarm-clock` / `preferences-system-time`), visually duplicating the Analog Clock docklet. Digital Clock now renders a dedicated modern tile icon with digital numerals (`org.kde.plasma.digitalclock` / `digital-clock.svg`).
- **Preferences Dialog 7×2 Symmetric Grid**: Reorganized the Preferences *Docklets* tab into a balanced 7×2 grid accommodating all 14 docklets with native 35px vector icons:
  - Left Column: Trash, Clock (Analog), Digital Clock, Battery, Screenshot, Preferences, Removable Drives (Ejector).
  - Right Column: CPU & RAM, Show Desktop, Media Player (MPRIS), Volume Control, Session & Power, Screen Brightness, Weather Forecast.
- **Tooltip Category Badges**: Added contextual type indicators (`• Folder`, `• Running`, `• Docklet`) in free-placement mode, and sanitized the Trash docklet tooltip.

### 14. 📦 100% Self-Contained Binary Fallback Icons Architecture
- **Pure Binary GResource Encapsulation**: All 14 docklets are backed by 33 high-definition vector SVG assets compiled directly into the `wayplank` executable ELF binary under `/net/launchpad/plank/docklets/`.
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
- **New Docklet Vectors**:
  - Removable Drive Ejector (`ejector.svg`)
  - Screen Brightness (`brightness.svg`)
  - Weather Forecast (`weather.svg`)
- **Zero Host Filesystem Pollution**: Fallback assets are strictly kept inside the binary. The Debian package installs only the application icon (`wayplank.svg` / `plank.svg`), ensuring complete distribution independence, zero host file collision, and standalone portability.

### 16. 📂 Cairo-Dock Style Folder Launcher Menu (`lib/Widgets/FolderMenuWindow.vala`, `lib/Items/FileDockItem.vala`, `lib/Widgets/DockWindow.vala`)
- **Cairo-Dock Interactive Paradigm**: Left-clicking a folder dock item toggles a fast, non-modal launcher popup (`FolderMenuWindow`) displaying the folder's contents (subdirectories, `.desktop` launchers, and documents) directly from the dock.
- **Non-Grabbing Layer Shell Overlay (`GtkLayerShell.Layer.OVERLAY`, `KeyboardMode.NONE`)**: Unlike traditional modal GTK popups or grabbing menus, `FolderMenuWindow` does NOT take global pointer grabs or freeze compositor input. The desktop remains 100% interactive, and the dock icon zoom animation maintains a fluid 60 FPS while the menu is open.
- **Dynamic 60 FPS Zoom Following**:
  - `FolderMenuWindow.update_position()` is called directly inside `DockWindow.draw()` on every rendering frame.
  - Dynamically calculates the target item's horizontal center (`val.center.x`) and visual dock elevation (`pm.get_visual_thickness_for_item (TargetItem)`), smoothly sliding and elevating with icon magnification across all four dock screen positions (`BOTTOM`, `TOP`, `LEFT`, `RIGHT`).
- **Decoupled Click Bounce**:
  - Clicking a folder launches the classic dock icon bounce animation (`AnimationType.BOUNCE`).
  - Position calculation uses `pm.get_visual_thickness_for_item (TargetItem)` strictly based on icon size rather than `val.center.y`. This decouples the popup menu from the jumping vertical bounce offset, ensuring the menu remains rock-steady and effortless to click while the icon animates.
- **Exact Tooltip Dark Aesthetics**:
  - Background drawn via Cairo using `Theme.draw_rounded_rect` with radius 7px, matching `HoverWindow` tooltips identically (`rgba(28, 28, 30, 0.95)` with 1px border `rgba(255, 255, 255, 0.18)`).
  - Clean CSS styling applied via `Gtk.StyleContext.add_provider_for_screen()` with priority `APPLICATION + 20`: crisp white labels (`#ffffff`, 13px, weight 500), symbolic white icons, and illuminated hover highlights (`rgba(255, 255, 255, 0.20)` with 1px border `rgba(255, 255, 255, 0.35)`).
- **Subdirectory Drill-Down & History Stack**:
  - Clicking a subdirectory drills down in-place with back-button navigation (`go-previous-symbolic`) and a history stack (`Gee.ArrayList<File>`).
  - Clicking `.desktop` application launchers launches the program via `System.get_default ().launch ()` and triggers a confirmation bounce on the dock icon.
  - Clicking files/documents opens them in the user's default desktop handler via `System.get_default ().open ()`.
- **Intelligent Auto-Dismissal**:
  - Moving the mouse from the folder icon to another dock item immediately closes the folder menu.
  - Moving the mouse away onto the desktop engages a 150ms dismiss timer, cancelled immediately if the cursor re-enters the dock or menu surface.
- **Dedicated Right-Click Menu**:
  - Right-clicking folder dock items is reserved exclusively for dock management actions (*Keep in Dock*, *Open in File Browser*, *Preferences...*, *Shortcuts & Gestures...*, *Report a Bug...*, *About Wayplank...*).

### 17. ⚖️ GPL-3.0 License & Integrated Asset Attribution
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

- **Compilation**: Clean build using `valac` with 0 errors and 0 warnings via `./BuildBin.sh`.
- **Binary**: Standalone binary compiled in `build/wayplank` (`Wayplank 0.5.2`).
- **Embedded Resources**: Verified with `gresource list build/wayplank` (all 33 docklet fallback SVGs present).
- **Debian Package**: Built and validated as `build/wayplank_0.5.2_amd64.deb` via `./BuildDeb.sh` (includes `/usr/share/doc/wayplank/copyright` and clean hicolor icons).
- **FAT Validation**: Multi-compositor validation test protocol across GNOME, KDE Plasma, and Labwc; see [`FAT/2026-10-09 FAT 0.5.2.txt`](../FAT/2026-10-09%20FAT%200.5.2.txt).
