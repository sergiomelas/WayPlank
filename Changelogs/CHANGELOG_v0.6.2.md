# WayPlank V0.6.2 Series Detailed Technical Changelog

Release Series: **V0.6.2 Series (The Community Unification & Distribution Release)**  
Current Milestone: **V0.6.2.3 (Round 3 & Community Features: Multi-Window Preview Cards, Dynamic Theming, DND Docklet, System Menu Access, 7×2 Grid, German & Ukrainian Translations, HAL Brightness Sync) — Completed / 100% FAT Passed (2026-10-27)**  
Release Date: 2026-10-27 (Community Contributions Fully Integrated & 100% FAT Qualified)  
Authors & Contributors:
- **Sergio Melas** (Maintainer — sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))
- **史有虎 (IFtiger-hu)** (Collaborator, GitHub: [@IFtiger-hu-hub](https://github.com/IFtiger-hu-hub))

---

## 1. 📋 Overview & Motivation

Wayplank **V0.6.2 series** marks a landmark milestone in the project's evolution: the **unification of upstream WayPlank with the community fork created by IFtiger-hu (史有虎)**. Following formal collaborative agreement, upstream WayPlank integrates the high-value distribution tooling, core item deduplication, and overflow navigation innovations from the fork in progressive, linear validation rounds, expanding WayPlank's reach across the entire Linux ecosystem with full author attribution.

### Core Highlights of v0.6.2.1 (Round 1):
1. **Native openSUSE, Fedora & RHEL Automated RPM Packaging (`BuildRpm.sh`)**: Direct standalone RPM generation supporting openSUSE (Tumbleweed, Leap), Fedora (40, 41), and RHEL/CentOS, featuring automated desktop database integration, GSettings schema compilation, and clean distribution independence alongside our Debian/Ubuntu `.deb` packages.
2. **Launcher Deduplication & Item Reuse Engine (`ItemFactory.vala`)**: Eliminates duplicated `.dockitem` generation (`app-1.dockitem`, `app-2.dockitem`) when re-adding or refreshing launchers, reusing existing valid item definitions and cleanly pruning redundant duplicate URI entries.
3. **Ghost Window & Screen-Sharing Bridge Shielding (`ApplicationDiscovery.vala`)**: Transparently filters background auxiliary windows such as `xwaylandvideobridge` (used by Discord, WebRTC, and OBS for Wayland screen sharing), preventing invisible 1×1 ghost icons from polluting the dock.
4. **Dock Overflow Smooth Scrolling Architecture (`PositionManager.vala`, `DockRenderer.vala`, `DockWindow.vala`)**: Clamps dock background geometry to screen boundaries and enables smooth, interpolated mouse wheel scrolling when pinned and running items exceed available screen span. Includes Preferences toggle ("Scroll on Overflow") and Appearance dynamic capacity redline indicator.
5. **Multi-Monitor DDC/CI Brightness Sync & SP/PV Decoupling (`BrightnessDockItem.vala`)**: Resolves external display backlight synchronization under Mutter and Labwc using a dedicated serialized background worker thread with target coalescing, while architecturally decoupling user Set Point (SP) from background Process Variable (PV) sensor polling to prevent docklet badge bounce.
6. **Weather Forecast Vector Fallback & Direct Yr.no Navigation (`DrawingService.vala`, `WeatherWindow.vala`, `WeatherDockItem.vala`)**: Eliminates broken icon placeholders by guaranteeing 100% vector fallback to bundled SVG assets. Adds high/low temperature ranges (▲/▼), localized weekday formatting, condition details (humidity and wind speed), and direct headless Yr.no location resolution for one-click browser navigation.
7. **Volume Docklet Overamplification Guard (`VolumeDockItem.vala`)**: Prevents speaker damage from unlimited relative volume runaway. Replaces unbounded relative increments (`+5%`) with absolute capped volume commands (`wpctl set-volume -l 1.5` and `pactl set-sink-volume`), strictly enforcing the 150% maximum limit and blocking scroll wheel overflow.
8. **Application Identity & Wrapper Matching Engine Hardening (`ApplicationIdentity.vala`, `ApplicationDiscovery.vala`)**:
   - **Recursive Command Unwrapping**: Recursively peels wrapper commands (`sh -c`, `bash -c`, `env VAR=val`, `firejail`, `flatpak-spawn`, `flatpak run`, `pkexec`, `sudo`, `systemd-inhibit`) to reliably identify target application binaries (e.g. MATLAB under Firejail, Scilab under Mesa GL overrides).
   - **Dynamic Drawer Folder Discovery**: Automatically indexes custom drawer folder directories referenced by dockitems (`~/.config/wayplank/dock*/launchers/`), ensuring applications pinned inside category drawers (Engineering, Games, Internet) are discovered and tracked.
   - **Hardened Script Wrapper Inspection**: Accurately inspects user shell launcher scripts (e.g. `winchrome-syensqo.sh`) with strict shell-shebang and <4KB size bounds, extracting instance-specific options (`--profile-directory=...`, `--class=...`).
   - **Tiered Scoring & Specialized Launcher Isolation**: Prioritizes specialized instances with score 110 when arguments match, while strictly zeroing scores (`return 0`) on generic windows. Eliminates cross-app false positives (e.g. Scilab vs Quake 2) and protects standard browser windows from profile hijacking.
9. **Consolidated Core Hardening & 100% FAT Qualification**: 279 test points executed across GNOME/Mutter, KDE/KWin, and Labwc with 0 open defects and 18 squashed bugs.

### 🗺️ The V0.6.2 Multi-Round Integration Plan:
* **Round 1 (`v0.6.2.1`) — ✅ Completed (100% FAT Passed, Released 2026-10-17)**:
  - **Distribution & Packaging**: Automated standalone RPM packaging for openSUSE, Fedora and RHEL (`BuildRpm.sh`) with headless CI support.
  - **Core Stability**: ItemFactory launcher deduplication, ghost window & screen-sharing bridge shielding (`xwaylandvideobridge`).
  - **Navigation & Display**: Dock overflow smooth scrolling with tachometer redline capacity indicator, and multi-monitor screen brightness DDC/CI synchronization with architectural SP/PV decoupling.
* **Round 2 (`v0.6.2.2`) — ✅ Completed (100% FAT Passed, Released 2026-10-21)**:
  - **Remote Web Drag-and-Drop**: Remote web URL delivery (`http://`, `https://`) with automatic browser launching via `DesktopAppInfo.launch_uris()`.
  - **Window Interaction**: Automatic hover window raising during drag operations to simplify dragging files directly into target application workspaces.
  - **System Theme Integration**: Real-time dark/light mode detection via FreeDesktop Settings Portal (`org.freedesktop.portal.Settings`).
  - **Interactive Theme Manager**: Native portal file chooser and theme archive installer/uninstaller (.zip, .tar.gz, .theme).
  - **Strict FreeDesktop MIME Validation**: Strict MIME compatibility checks guarding application file drops.
  - **Canonical Deduplication & Drag-Off Poof**: Canonical symlink/URI deduplication and instant drag-off removal with particle poof animation.
* **Round 3 (`v0.6.2.3`) — ✅ Completed (100% FAT Passed, Released 2026-10-22)**:
  - **Universal Multi-Window Preview Cards**: Cairo-rendered visual window preview cards with live IPC thumbnails on KWin and GNOME Mutter, with graceful blank card fallback on Labwc.
  - **True Dynamic System Theme Switching**: Real-time synchronization across KDE (`kdeglobals`), GNOME Shell (`color-scheme`), and FreeDesktop portal with automated Dark/Light counterpart theme swapping.
  - **Recent Files Jump List**: FreeDesktop `Gtk.RecentManager` jump list in application right-click context menus (`RecentFilesService`).
  - **Packaged Stock Themes**: Bundled Dark, Light, Arian Dark/Light, and IFtiger Dark/Light themes.
  - **Running Dots & Drawer UX Parity**: Pinned folder dock items render illuminated running dots (and dual dots for 2+ active apps); drawer rows render running indicators with stabilized geometry; complete application contract parity (Ctrl/Middle click launch instance, wheel window cycling, row context menu guard).
  - **Native Window Stacking & Crash Elimination**: Completely excised asynchronous presentation timers eliminating Mutter `meta_window_unmanage` assertion crashes; decoupled peer dialogs for natural bidirectional stacking; reconnected native CSD HeaderBar on Mutter; KWin D-Bus service watcher for automatic bridge script recovery.
  - **Full Multi-Compositor Qualification**: 335 tests executed, 333 passed (324 baseline + 9 squashed), 2 NA, 0 open defects (100% PASS rate across GNOME Shell, KDE Plasma 6, and Labwc).
  - **Release Schedule**: v0.6.2.3 (Round 3) is officially released and live on GitHub! The official WayPlank Public Beta (v0.7.0) will launch in Week 45 (Monday, November 2, 2026), providing full community and downstream testing runway during Week 44.

---

## 2. 📦 Native openSUSE / Fedora / RHEL RPM Packaging (`BuildRpm.sh`)

### Context & Need
While WayPlank provided comprehensive Debian/Ubuntu packaging (`BuildDeb.sh`), openSUSE and Fedora users previously had to build manually from source or convert Debian packages.

### Architectural Solution
WayPlank v0.6.2.1 (Round 1) integrates `BuildRpm.sh`, authored by **史有虎 (IFtiger-hu)** and refined for upstream:
- **Standalone Isolated Workspace**: Prepares source payloads under `build_rpm_workspace/` with automated spec file synthesis.
- **Cross-Distribution Portability**: Automatically handles:
  - openSUSE: `zypper install rpm-build`
  - Fedora: `dnf install rpm-build`
  - Debian/Ubuntu: `apt install rpm` (with `--define "_dbpath %{_topdir}/rpmdb"` to prevent non-root sqlite database collisions)
- **Standardized RPM File System Hierarchy**:
  - Binary in `/usr/bin/wayplank` with symlink `/usr/bin/plank`
  - Desktop integration in `/usr/share/applications/`
  - Themes in `/usr/share/wayplank/themes/`
  - Icons across all standard hicolor dimensions (16×16 to scalable)
  - Post-install scriptlets executing `glib-compile-schemas`, `gtk-update-icon-cache`, and `update-desktop-database`.
- **Target Output**: Generates clean, signed-ready packages: `build/wayplank-0.6.2.1-1.x86_64.rpm`.

---

## 3. 🧹 Launcher Deduplication & Item Reuse (`lib/Factories/ItemFactory.vala`)

### The Problem
When users repeatedly launched, pinned, or rearranged items with identical URIs or application IDs, previous versions incremented numeric suffixes (`firefox-1.dockitem`, `firefox-2.dockitem`) or left duplicate definitions in `~/.config/wayplank/dock1/launchers/`.

### The Solution
1. **URI Deduplication on Load**: In `get_dock_elements_from_dir()`, WayPlank now checks `find_item_for_uri(result, item.Launcher)`. If a dock item with an identical launcher URI already exists in the active dock set, the redundant duplicate is safely deleted from disk and ignored.
2. **Deterministic Item Reuse**: In `create_dock_item()`, before incrementing numeric filenames, WayPlank queries existing items for `get_launcher_from_dockitem(dockitem_file)`. If an existing dock item file already targets the desired URI, WayPlank reuses it directly, eliminating file churn and maintaining clean launcher directories.

---

## 4. 🛡️ Ghost Window & Screen-Sharing Bridge Filtering (`lib/Services/ApplicationDiscovery.vala`)

### The Problem
Under Wayland, tools like `xwaylandvideobridge` (standard KDE/GNOME tool enabling legacy X11 applications like Discord, Zoom, or Slack to capture Wayland screens) create hidden 1×1 pixel toplevel surfaces. WayPlank previously attempted to match these auxiliary surfaces to `.desktop` entries, spawning empty or unwanted bridge icons on the running section of the dock.

### The Solution
Added `ApplicationDiscovery.is_ignored_app()`:
```vala
public static bool is_ignored_app (string? app_id)
{
    if (app_id == null || app_id == "")
        return false;
    var lower = app_id.down ();
    return lower.contains ("xwaylandvideobridge")
        || lower == "wayplank";
}
```
In `best_desktop_file_for_window()`, any window matching ignored application IDs, resource classes, resource names, or desktop file names is discarded immediately, preserving a clean running application bar.

---

## 5. 🌊 Dock Overflow Smooth Scrolling (`lib/PositionManager.vala`, `lib/DockRenderer.vala`, `lib/Widgets/DockWindow.vala`)

### The Problem
On smaller displays (e.g. 1366×768 laptops) or when users pinned a very large number of applications, the dock previously exceeded the physical monitor width or shrank icon sizes aggressively.

### The Solution
Integrated the smooth overflow scrolling architecture authored by **史有虎 (IFtiger-hu)**:
1. **Boundary Clamping**:
   - `width = int.min(monitor_geo.width, width);`
   - `background_width = int.min(monitor_geo.width, background_width);`
2. **Scroll Offset Calculation**:
   - `available_content_span = width - 2.0 * items_offset;`
   - When `current_items_span > available_content_span`, `max_scroll_offset` is dynamically computed.
3. **Smooth Interpolated Movement**:
   - Scroll events are interpolated smoothly: `scroll_offset += (target_scroll_offset - scroll_offset) * 0.35`.
4. **Mouse Wheel Interception**:
   - Mouse wheel events over the dock surface shift the view by 80px (or smooth delta fractions), while preserving volume docklet adjustment when hovering over the volume icon.

---

## 6. 🛡️ Application Identity & Wrapper Engine Hardening

### Motivation & Root Cause Analysis
Complex application launchers in Linux frequently wrap native binaries in shell scripts or sandbox layers:
1. **Sandboxes & Environment Overrides**:
   - MATLAB: `Exec=sh -c "TMPDIR=$HOME/.cache/matlab-tmp firejail /usr/local/MATLAB/R2024a/bin/matlab -desktop"`
   - Scilab: `Exec=env MESA_GL_VERSION_OVERRIDE=3.0 /usr/local/SCILAB/scilab-2025.1.0/bin/scilab %f`
2. **User Launcher Scripts with Specific Profiles**:
   - Syensqo Chrome: `winchrome-syensqo.sh` running `/opt/google/chrome/google-chrome ... --profile-directory="Profile 14"`
3. **Category Drawer Folders**:
   - Custom `.desktop` files stored exclusively inside dock drawer folders (e.g. `~/.config/wayplank/dock1/launchers/Enginnering` or `Games`) were previously not indexed by standard XDG search directories.

### Architecture & Implementation
- **Recursive Command Unwrapping (`unwrap_command_string`)**:
  Recursively strips command wrappers (`sh -c`, `bash -c`, `env VAR=val`, `firejail`, `flatpak-spawn`, `flatpak run`, `pkexec`, `sudo`, `systemd-inhibit`) to locate the genuine target executable. Automatically registers binary aliases (e.g. `scilab` ↔ `scilab-bin`, `google-chrome` ↔ `chrome`).
- **Dynamic Category Drawer Indexing (`application_folders`)**:
  Inspects all `*.dockitem` entries in `~/.config/wayplank/dock*/launchers/` for directory URIs, adding drawer folder paths directly to the desktop search paths.
- **Bounded Script Inspection (`inspect_script_file`)**:
  Restricts script file parsing strictly to `.sh` user launcher scripts (<4KB bounds, shell shebang enforcement). Prevents reading system scripts or Python wrappers (e.g. `gdp-launcher`).
- **Specialized Launcher Isolation & Prioritization (`match_score`)**:
  When a launcher targets a specific profile (`--profile-directory=...`), it receives score **110** when the window matches. If the window does not match the specialized arguments, the launcher score is strictly zeroed (`return 0`), ensuring specialized launchers never steal generic application windows.

---

## 7. 🤝 Community Attribution & Collaboration Log

This milestone exemplifies collaborative open-source synergy:
- **Collaboration Initiated**: 2026-10-15 via direct maintainer exchange.
- **Authorization**: Full mutual consent to cherry-pick, adapt, and integrate fork features under Option 2.
- **Git Authorship**: Preserved on all imported code chunks (`史有虎 (IFtiger-hu)`).
- **Roadmap & Strategy**: Documented in `Documentation/WAYPLANK_V062_FORK_INTEGRATION_ROADMAP.md`.

---

## 8. 🧪 Testing & Validation Matrix (FAT v0.6.2.1 Final)

- **Debian SID (amd64)**: `./BuildDeb.sh` builds cleanly -> `build/wayplank_0.6.2.1_amd64.deb`.
- **openSUSE / Fedora / RHEL (x86_64)**: `./BuildRpm.sh` builds cleanly with custom local `_dbpath` -> `build/wayplank-0.6.2.1-1.x86_64.rpm`.
- **KDE Plasma 6 (KWin Backend)**: FINISHED (100% Passed) | 89 [ok] | 5 [ko->ok] | 0 [NA] | 0 Open.
- **GNOME Shell (Mutter Backend)**: FINISHED (100% Passed) | 86 [ok] | 8 [ko->ok] | 0 [NA] | 0 Open.
- **Labwc (wlroots Backend)**: FINISHED (100% Passed) | 89 [ok] | 3 [ko->ok] | 2 [NA] | 0 Open.
- **Total Qualification Scoreboard**: 282 Tests Executed | 264 [ok] | 16 Bugs Squashed [ko->ok] | 0 Open Defects (100% Compliant).

---

## 9. 🌟 WayPlank V0.6.2.2 (Round 2: Ergonomics, DND Remote URLs, Theme Manager & Portal Sync) — Completed / 100% FAT Passed (2026-10-21)

### Core Highlights of v0.6.2.2 (Round 2):
1. **DND Remote Web URL Delivery & Cross-Browser Target Compatibility (`DragManager.vala`, `System.vala`)**:
   - Comprehensive drop targets: `text/uri-list`, `text/x-moz-url`, `UTF8_STRING`, `text/plain`, `text/html`, and Windows/Qt UTF-16LE clipboard decoding.
   - Dropping web URLs on dock background launches the system default web browser.
   - Dropping web URLs on browser dock items opens them in a new tab.
   - Internet desktop link shortcuts (`.desktop` with `Type=Link` and `URL[$e]=` / `URL=`, plus `.url`) are fully parsed and launched.
   - Pinning precedence strictly protects `.desktop` files (including Chrome Web Apps like WhatsApp/YouTube) from browser drop hijacking.
2. **Hover Window Activation During External Drag (`DragManager.vala`)**:
   - Pausing cursor hover over a running application dock item for >500ms during an active drag operation triggers an automated `WindowManager.activate()` call.
   - Automatically raises the target application window to the foreground, allowing the user to drop files directly into the application's workspace without manual task switching.
3. **FreeDesktop Settings Portal Color-Scheme Synchronization (`DrawingService.vala`, `Theme.vala`)**:
   - Direct D-Bus listener connected to `org.freedesktop.portal.Settings` for the `color-scheme` key.
   - Dynamically re-renders adaptive GTK+ dock themes in real-time when the desktop switches between Dark and Light mode without requiring a dock restart.
4. **Interactive Theme Manager with Native Portal File Chooser (`ThemeManager.vala`, `PreferencesWindow.vala`, `preferences.ui`)**:
   - Adds interactive `+` (Install) and trash (Delete) buttons to the Preferences -> Appearance -> Theme selector.
   - Integrates `Gtk.FileChooserNative` portal dialog for seamless KDE Plasma Wayland integration.
   - Built-in archive scanner for `.zip`, `.tar.gz`, `.tar.xz`, `.tar.bz2`, and standalone `.theme` files with automatic multi-theme selection dialogs.
   - Safe installation to `~/.local/share/wayplank/themes/` and safe deletion with immediate fallback to Default.
   - Hardened with POSIX `GLib.Shell.quote()` escaping and guaranteed temporary directory cleanup.
   - Ellipsized ComboBox (`Pango.EllipsizeMode.END`) and tooltips preventing theme names from stretching the preferences window.
5. **Strict FreeDesktop MIME Type Drop Validation (`ApplicationDockItem.vala`, `DragManager.vala`)**:
   - Strictly enforces FreeDesktop `Gio.ContentType` matching against target applications' `.desktop` `MimeType=` declarations.
   - Incompatible drops (e.g. dropping PDF files onto Kate, Gedit, or Dolphin) bounce and reject cleanly, preventing unwanted launches and accidental pinning to the dock.
6. **Canonical Launcher Deduplication & Item Reuse (`DockItemProvider.vala`, `ItemFactory.vala`)**:
   - Replaces naive string comparison with canonical URI matching (`DockItemProvider.uri_matches()`): resolves symlinks (`Posix.realpath`), percent-encoding (`GLib.File.equal`), and desktop IDs.
   - Reuses and updates existing `.dockitem` files instead of spamming `-1.dockitem`, `-2.dockitem` files on disk.
7. **Clean KISS Drag-Off Removal & Poof Animation (`DefaultApplicationDockItemProvider.vala`, `DragManager.vala`)**:
   - Evaluates active running windows directly (`window_count_for_app > 0`).
   - Applications with 0 open windows delete immediately from disk and trigger the Cairo `PoofWindow` cloud particle animation at cursor release, completely eliminating transient icon ghosting or hopping into the unpinned section.
8. **100% Multi-Compositor Qualification (FAT 0.6.2.2)**:
   - 306 total tests executed across KDE Plasma 6 (KWin), GNOME Shell (Mutter), and Labwc (wlroots) with 304 passed, 2 NA (known Labwc protocol limitations), 0 pending, and 0 open defects.

---

## 10. 🎯 WayPlank V0.6.2.3 (Round 3: Multi-Window Preview Cards, Dynamic Theming, Recent Files, Stock Themes, Folder Running Dots, Drawer UX Parity & Native Peer Stacking) — Completed / 100% FAT Passed (2026-10-22)

### Core Highlights & Technical Accomplishments of v0.6.2.3 (Round 3):

1. **Universal Multi-Window Preview Cards (`WindowCard.vala`, `WindowCardsWindow.vala`)**:
   - **Cairo-Rendered Elevated Card Popup**: Hovering or clicking multi-window applications opens an elevated Cairo floating card popup (`WindowCardsWindow`) dynamically anchored over the dock item.
   - **Live Compositor Thumbnails (KWin & Mutter)**:
     - On **KDE Plasma 6 (KWin)**: Captures live window thumbnails via `org.kde.KWin.ScreenShot2` D-Bus IPC over a private Unix pipe file descriptor (`capture_window()`). Integrated with `X-KDE-DBUS-Restricted-Interfaces` security declarations in `wayplank.desktop`.
     - On **GNOME Shell (Mutter)**: Captures live window thumbnails via the internal Mutter extension D-Bus bridge (`/mutter/screen/preview`) with sub-pixel Clutter stage scaling.
   - **Graceful Blank Card Fallback (Labwc / wlroots)**: On compositors without standard window capture protocols, WayPlank presents elegant, legible blank preview cards displaying high-contrast application vector icons, exact window title bars, and action buttons.
   - **Interactive Card Controls**:
     - Hovering a card highlights it with theme-aware rounded card borders and active elevation.
     - Left-clicking activates and raises the target window (`WindowManager.activate()`).
     - Clicking the top-right close icon (X) terminates the window via `WindowManager.close_window()`.
   - **User-Configurable Window Navigation**: Toggle switch in **Preferences $\rightarrow$ Behaviour** ("Show window preview cards on hover/click") allowing users to choose between modern visual cards or traditional rapid cyclic window switching.
   - **60 FPS Zoom Follower Synchronization**: Zoom animations on the underlying dock remain synchronized at 60 FPS while the preview window is displayed.

2. **True Dynamic System Theme Switching (`lib/Services/SystemTheme.vala`, `lib/DockRenderer.vala`)**:
   - **Multi-Bus & Desktop Protocol Convergence**:
     - FreeDesktop Settings Portal: Intercepts `SettingChanged` events for `key == "color-scheme"` across both `org.freedesktop.appearance` (uint32: 1=Dark, 2=Light) and `org.gnome.desktop.interface` (string: `"prefer-dark"`, `"prefer-light"`).
     - Direct GNOME GSettings Fallback: Connects to `org.gnome.desktop.interface.color-scheme` via direct GSettings signal monitoring.
     - KDE Plasma Inotify File Monitor: Monitors `~/.config/kdeglobals` for instantaneous color scheme modifications under Plasma 6.
   - **Dynamic Counterpart Theme Swapping**:
     - When the system switches between Dark and Light mode, WayPlank automatically swaps active counterpart themes:
       - *Arian Theme Light* $\longleftrightarrow$ *Arian Theme Dark*
       - *IFtiger Theme Light* $\longleftrightarrow$ *IFtiger Theme Dark*
       - *Light* $\longleftrightarrow$ *Dark*
     - If the `Default` dynamic theme is active, it immediately calls `reset_buffers()` and re-renders adaptive GTK+ translucent glass styles in real time without restarting the dock.

3. **Recent Files Jump List (`lib/Services/RecentFilesService.vala`, `lib/Items/ApplicationDockItem.vala`)**:
   - Integrated FreeDesktop `Gtk.RecentManager` jump list querying recently opened documents.
   - Accessible as a dedicated "Recent Documents" submenu in application right-click context menus.
   - Filtered by application desktop ID and registered MIME types, providing one-click document reopening.

4. **Packaged Stock Themes Suite (`data/themes/`)**:
   - Fully installed stock themes to `/usr/share/wayplank/themes/`:
     - `Default`: Adaptive dynamic translucent glass matching system GTK+ colors.
     - `Arian Theme Dark` & `Arian Theme Light`: Modern frosted glass themes with subtle illumination.
     - `IFtiger Theme Dark` & `IFtiger Theme Light`: Sleek high-contrast themes authored by IFtiger-hu (史有虎).
     - `Dark` & `Light`: Classic clean monochrome stock themes.

5. **Folder Running Indicator Dots (`FileDockItem.vala`, `FolderMenuWindow.vala`, `DockRenderer.vala`, `DrawingService.vala`)**:
   - **Dock Folder Items**: Pinned folder items now inspect whether any application contained within them is currently active. If 1 application is running, an illuminated indicator dot is rendered on the folder dock item; if 2 or more applications are active, dual indicator dots are rendered.
   - **Drawer Application Rows**: Inside open folder drawers, each application row now renders an indicator dot beside the application icon if that application is running.
   - **Anti-Clipping Geometry & Reverse Roundness**: Stabilized indicator positioning with proportional margin offsets and reverse roundness clearance, eliminating indicator dot clipping across all icon sizes and themes.

6. **Folder Drawer Application Contract Parity & UX Trust (`FolderMenuWindow.vala`)**:
   - **Full Click Behavior Compliance**: Left-clicking an application row routes through `WindowManager.resolve_click_command()`, respecting the user's configured WindowClickBehavior (Smart, Focus, or Cycle).
   - **Force New Instance Shortcut**: `Ctrl+Left Click` and `Middle Click` strictly invoke `System.get_default().launch()` to spawn brand new application instances directly from the drawer.
   - **Mouse Wheel Window Cycling**: Moving the mouse wheel over any drawer application row smoothly cycles through that application's open windows.
   - **Attached Context Menu with Guard**: Right-clicking an application row attaches a native GTK context menu directly to the row widget with a `context_menu_active` guard, preventing premature dismissal or auto-hide conflicts. Omitted the irrelevant "Keep in Dock" checkbox from drawer menus.

7. **Elimination of Asynchronous Timers & Mutter Crash Prevention (`AbstractMain.vala`, `SessionWindow.vala`, `WeatherWindow.vala`)**:
   - **Root-Cause Analysis**: Rapidly double-clicking or toggling docklet icons caused Mutter to abort with SIGABRT in `meta_window_unmanage: assertion failed: (g_list_find (workspace->windows, window) == NULL)`. This was caused by asynchronous timers (`GLib.Timeout.add (50)`) calling `show_all()`, `deiconify()`, and `present()` on windows undergoing unmanagement.
   - **Deterministic Signal Architecture**: Completely excised all asynchronous presentation timers across the codebase. Replaced with one-shot native GTK `window.map` signal listeners that activate the window strictly when the surface is configured by the compositor, disconnecting immediately and disposing cleanly on destroy without race conditions.

8. **Cross-Compositor Peer Dialog Stacking & Sub-Popup Decoupling (`AbstractMain.vala`, `SessionWindow.vala`, `WeatherWindow.vala`)**:
   - **Decoupled Peer Dialogs**: Removed artificial `set_transient_for` calls that locked independent dialogs (`PreferencesWindow`, `SessionWindow`, `WeatherWindow`, `AboutDialog`, `HelpWindow`) into strict Wayland xdg-shell hierarchy traps.
   - **Bidirectional Stacking**: Windows can now naturally stack above or below each other on 1st click based on user focus, with instant toggle-off when active.
   - **Legitimate Sub-Popup Transiency**: Preserved modal child transiency strictly for true subordinate popups (`WeatherCityDialog` for `WeatherWindow`, and `IconChooserDialog` for `PreferencesWindow`).
   - **Native Mutter CSD HeaderBar**: Decoupling `AboutDialog` restores its complete native CSD HeaderBar and functional Close button on GNOME Shell (circumventing Mutter's `attach-modal-dialogs` mode). Connected `about_dlg.response` to `destroy()`.

9. **KWin D-Bus Service Watcher & Bridge Script Self-Healing (`KWinBridge.vala`)**:
   - Added `Bus.watch_name (BusType.SESSION, "org.kde.KWin")` to dynamically watch KWin's D-Bus name.
   - Automatically registers and re-executes the WayPlank bridge ECMAScript whenever KWin starts, restarts, or recovers from a crash (`kwin_wayland --replace`), restoring window dodging and thumbnail tracking without requiring WayPlank restart.

10. **100% FAT Multi-Compositor Qualification (FAT 0.6.2.3)**:
    - **357 Total Tests Defined** across 3 validation sessions:
      - **Session 1 (GNOME Shell / Mutter)**: 120 tests | 110 [ok] | 10 [ko->ok] | 100% PASS
      - **Session 2 (KDE Plasma 6 / KWin)**: 119 tests | 111 [ok] | 8 [ko->ok] | 100% PASS
      - **Session 3 (Labwc / wlroots)**: 118 tests | 113 [ok] | 3 [ko->ok] | 2 [NA] | 100% PASS
    - **Scoreboard**: 334 Passed Baseline `[ok]`, 21 Squashed `[ko->ok]`, 2 Not Applicable `[NA]`, 0 Pending `[ ]`, 0 Open Defects (100% PASS rate across all Tier-1 compositors).

---

## 11. 🌟 WayPlank V0.6.2.3 Community User Contributions & Ergonomics Update (2026-10-27)

Following community feedback and user contributions, this release incorporates major workflow enhancements, full localization catalogs, and HAL architecture hardening:

* 🔕 **Do Not Disturb Docklet (`docklet://dnd`)**:
  - Integrated desktop notification mute docklet adhering to the FreeDesktop `org.freedesktop.Notifications` standard.
  - Bidirectional D-Bus synchronization with KDE Plasma system tray and GNOME Shell top panel.
  - Graded vector states: active bell, muted/silenced bell, and localized toggle notifications.

* 🎛️ **3-Position System Menu Access Modes**:
  - Configurable in Preferences -> Behaviour: Mode 0 (Dedicated Preferences Icon), Mode 1 (Docklets Only with application menu fallback), and Mode 2 (All Icons Integrated).
  - Clean separation: prevents unwanted dock configuration items from polluting pure application context menus while preserving unconditional access via `Ctrl + Right Click`.

* ⚖️ **Symmetric 7×2 Docklets Grid & Shell Architecture**:
  - Perfectly balanced 14-item grid (7 columns × 2 rows) in Preferences -> Docklets with real-time toggle switches.
  - Relocated Trash docklet to the Appearance tab, establishing it as a permanent desktop shell anchor alongside classic stock themes.

* 🌍 **Community Localizations & Contributor Track**:
  - 100% complete German (`po/de.po`) and Ukrainian (`po/uk.po`) translation catalogs added to existing catalogs (`zh_CN`, `it`, `es`, `fr`, `ca`).
  - Formal [`CONTRIBUTING.md`](../CONTRIBUTING.md) guide establishing community localization, packaging, and bug reporting workflows.

* ☀️ **HAL Screen Brightness Separation & Multi-Monitor Synchronization (`lib/Services/BrightnessControl.vala`)**:
  - Pure Hardware Abstraction Layer service decoupling hardware sysfs, multi-monitor topology discovery, and D-Bus interfaces from UI docklets.
  - Real-time kernel sysfs polling (500ms heartbeat) on `/sys/class/backlight` catching physical laptop Fn keys and `brightnessctl set xx%` instantly.
  - 350ms Inbound Settle Debounce with anti-echo guard: automatically synchronizes external displays via `kscreen-doctor` (KWin) or `ddcutil` (Mutter/Labwc) when brightness is modified externally, maintaining seamless mouse wheel continuity from the physical Set Point.

---

## 12. 📦 Release Finalization & Master Milestone Roadmap

- **Current Live GitHub Release**: **v0.6.2.3 (Round 3 & Community Update)** is officially released on GitHub with 100% FAT qualification (355/355 tests passing, 2 NA).
- **Distribution packages available**:
  - `build/wayplank_0.6.2.3_amd64.deb`
  - `build/wayplank-0.6.2.3-1.x86_64.rpm`
- **Master Release Trajectory**:
  - **v0.7.x (Public Beta — Week 45: Monday, November 2, 2026)**: Official GitHub Launch of Public Beta, embedding monolithic in-memory gettext catalogs (`GResource`) and community testing buffer throughout Week 44.
  - **v0.8.x (Release Candidate Series)**: Strict feature freeze, memory leak profiling (Valgrind), and packaging standardization.
  - **v0.9.x (Long-Term Production Stabilization)**: The battle-tested production milestone and daily driver release for the Linux desktop community.
  - **v1.0.0 (Grand Milestone Horizon — ~2 Years)**: Definitive landmark release celebrating multi-year proven stability and mature Wayland protocol standards.

