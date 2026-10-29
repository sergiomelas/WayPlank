# WayPlank V0.7.0 (Public Beta 1) Detailed Technical Changelog

Release Series: **V0.7.x Series (The Public Beta Milestone)**  
Current Milestone: **V0.7.0 (Public Beta 1: Monolithic Embedded Localization Engine, Complete V0.6.2.3 Feature & HAL Consolidation, GNOME Bridge v4 & 381-Point FAT Qualification)**  
Target Release Date: **Week 45 (Monday, November 2, 2026)**  
Maintainer: **Sergio Melas** (sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))  
Collaborators & Contributors:
- **史有虎 (IFtiger-hu)** (Collaborator & Simplified Chinese Reviewer, GitHub: [@IFtiger-hu-hub](https://github.com/IFtiger-hu-hub))
- **Renate Schwiedernoch** (German `de` Localization Contributor)
- **Michailo Buchko** (Ukrainian `uk` Localization Contributor)

---

## 1. 📋 Overview & Motivation

Following the formal closure of the **Alpha & Pre-Beta development cycle (`v0.1.0` $\longrightarrow$ `v0.6.2.3`)** with **100% Factory Acceptance Testing qualification (`368/368` applicable test points passed, `107` lifetime bugs squashed, `145` multi-compositor verifications, `0` open defects)** across **KDE Plasma 6 (KWin)**, **GNOME Shell (Mutter)**, and **Labwc (wlroots)**, WayPlank officially enters its **Public Beta 1 (`v0.7.0`)**.

**WayPlank `v0.7.0`** consolidates the entire architectural and functional foundation built through **`v0.6.2.3`** and activates four Public Beta milestones:
1. **100% Monolithic Embedded Localization Engine (`GResource` in RAM)**: Compiles all **7 complete language catalogs (`326 / 326` strings — 100%)** directly into the single ELF executable (`/usr/bin/wayplank`) via `data/plank.gresource.xml` with an $O(1)$ in-memory GNU `.mo` hash resolver (`wayplank_i18n_init()` / `wayplank_i18n_get()` in `lib/gtk-compat.c`), achieving **Zero Host Pollution** (`0` files in `/usr/share/locale/`).
2. **GNOME Shell Companion Extension Version `4` (`wayplank-bridge@wayplank.org`)**: Increments `metadata.json` `version` from `3` (pre-beta `v0.6.2.x` series) to **`4`** for the Public Beta milestone.
3. **381-Point Public Beta FAT Protocol (ISA-88 Phase B Consolidation + Section 12 I18N)**: Consolidates all **370 test points** from `v0.6.2.3` (`368 [ok]` baseline, `2 [NA]`) and adds **11 dedicated Embedded I18N & Localization Verification test points (Section 12, `12.1`–`12.11`)**.
4. **Full Binary & Distribution Packaging Parity (`0.7.0`)**: Synchronized standalone binary (`build/wayplank`), Debian/Ubuntu package (`build/wayplank_0.7.0_amd64.deb`), and openSUSE/Fedora/RHEL package (`build/wayplank-0.7.0-1.x86_64.rpm`).

---

## 2. 🌍 100% Monolithic Embedded Localization Engine (New in V0.7.0)

### 2.1. Architectural Design & Zero Host Pollution Philosophy
Unlike traditional Unix applications that scatter locale catalogs across `/usr/share/locale/<lang>/LC_MESSAGES/wayplank.mo`, WayPlank adheres strictly to its **Monolithic Standalone Executable Guarantee**:
- **Zero Runtime Filesystem Dependency**: All `.mo` binary catalogs are compiled at build time (`msgfmt -c`) and embedded directly inside `build/wayplank` as `GResource` byte streams (`/net/launchpad/plank/locale/<lang>/wayplank.mo`).
- **In-Memory $O(1)$ Hash Resolution (`lib/gtk-compat.c`)**:
  - `wayplank_i18n_init()` detects the active system locale via `setlocale(LC_MESSAGES, "")` and `g_get_language_names()`, looks up the matching embedded `.mo` resource in RAM, parses its binary header (`0x950412de`), and populates a `GHashTable` in memory.
  - `wayplank_i18n_get(const char *msgid)` performs an $O(1)$ lookup in RAM and falls back instantaneously to the original English `msgid` pointer when running under `en`, `C`, or `POSIX` locales without disk I/O or heap allocation.
- **Vala & C Translation Interception (`include/config.h`)**:
  ```c
  const char* wayplank_i18n_get (const char* msgid);
  #undef _
  #define _(String) wayplank_i18n_get(String)
  ```
- **Zero Host Pollution in `.deb` & `.rpm`**: Neither `BuildDeb.sh` nor `BuildRpm.sh` installs any files under `/usr/share/locale/`. Moving `/usr/bin/wayplank` alone to any compatible Linux machine preserves all 7 languages, 16 docklets, and UI layouts out of the box.

### 2.2. Supported Language Catalogs (`326 / 326` Strings Qualified — 100%)
All **326 UI `msgid`s** covering the Preferences dialog (Appearance, Behaviour, Docklets), dock context menus, tooltips, Weather forecast dialogs, Session confirmation dialogs, and CLI help are 100% translated and verified with `msgfmt -c -v`:
1. **简体中文 (Simplified Chinese, `zh_CN`)** — Contributor & Reviewer: **史有虎 (IFtiger-hu)** (`326/326`, 100%)
2. **Italiano (Italian, `it`)** — Author & Maintainer: **Sergio Melas** (`326/326`, 100%)
3. **Español (Spanish, `es`)** — Maintainer: **Sergio Melas** (`326/326`, 100%)
4. **Français (French, `fr`)** — Maintainer: **Sergio Melas** (`326/326`, 100%)
5. **Català (Catalan, `ca`)** — Maintainer: **Sergio Melas** (`326/326`, 100%)
6. **Deutsch (German, `de`)** — Contributor: **Renate Schwiedernoch** (`326/326`, 100%)
7. **Українська (Ukrainian, `uk`)** — Contributor: **Michailo Buchko** (`326/326`, 100%)
8. **English (`en` / `C` / `POSIX`)** — Native in-source fallback language (zero overhead).

### 2.3. Community Translation Generator (`po/generate_translations.py`)
- Self-contained Python utility maintaining the master dictionary of all 326 UI strings across all 7 languages and automatically compiling/validating `.po` and `.mo` catalogs via GNU `msgfmt`.

---

## 3. 🏛️ Consolidated Architecture & Features (Inherited from V0.6.2.1 – V0.6.2.3)

WayPlank `v0.7.0` includes the complete set of features, docklets, and HAL engineering developed and qualified across the `v0.6.2` series:

### 3.1. Native RPM & DEB Multi-Distribution Packaging (`BuildDeb.sh`, `BuildRpm.sh`)
- **Debian / Ubuntu / Linux Mint (`BuildDeb.sh`)**: Automated native compilation, `GResource` embedding, GSettings schema compilation, and `.deb` packaging (`build/wayplank_0.7.0_amd64.deb`).
- **openSUSE / Fedora / RHEL (`BuildRpm.sh`)**: Standalone RPM packaging authored by **史有虎 (IFtiger-hu)** and refined for upstream, supporting openSUSE (Tumbleweed, Leap), Fedora (40+), and RHEL/CentOS with isolated `_dbpath` builds (`build/wayplank-0.7.0-1.x86_64.rpm`).

### 3.2. Launcher Deduplication, Ghost Window Shielding & Application Identity Engine
- **Canonical Launcher Deduplication (`ItemFactory.vala`, `DockItemProvider.vala`)**: Resolves symlinks (`Posix.realpath`), percent-encoding (`GLib.File.equal`), and desktop IDs via `DockItemProvider.uri_matches()`, reusing existing `.dockitem` files and pruning duplicate definitions on load.
- **Ghost Window & Screen-Sharing Bridge Filtering (`ApplicationDiscovery.vala`)**: Filters auxiliary 1×1 surfaces such as `xwaylandvideobridge` and internal `wayplank` surfaces.
- **Recursive Command Unwrapping & Wrapper Engine (`ApplicationIdentity.vala`)**:
  - Unwraps `sh -c`, `bash -c`, `env VAR=val`, `firejail`, `flatpak-spawn`, `flatpak run`, `pkexec`, `sudo`, and `systemd-inhibit` to identify target binaries.
  - Dynamically indexes custom category drawer folders (`~/.config/wayplank/dock*/launchers/`).
  - Inspects user `.sh` launcher scripts (<4 KB, shell shebang enforced) for profile flags (`--profile-directory=...`, `--class=...`) with score **110** prioritization and strict `0` score isolation on non-matching generic windows.
- **Chromium PWA Isolation & Word-Boundary Token Matching (Issue #6 / FAT Point 2.14)**:
  - Exact primary matching on `DesktopFileName`, `ApplicationId`, and `StartupWMClass` (`crx_<id>`) plus Unicode word-boundary matching (`contains_word`), preventing false-positive hijacking and ensuring standalone PWAs instantiate distinct dock items.
- **Pure FreeDesktop Exec-Less Template Guard, Labwc `/proc` Resolver & Synthetic Launcher GC (Issue #14 / FAT Point 2.15)**:
  - Restricts `synthesize_fallback_desktop_file()` strictly to windows matching an installed Exec-less desktop template (`matched_exec_less_desktop`), preventing transient CLI utilities (`zenity`) from spawning dock icons.
  - Implements `resolve_toplevel_process()` in `LabwcBackend.vala` ($O(1)$-cached `/proc` PID and command-line resolution) and self-healing `wayplank-app-*.desktop` launchers so multiple distinct CLI QEMU VMs pin, isolate, and cold-relaunch 100% across KWin, Mutter, and Labwc.
  - Automatically purges unpinned `wayplank-app-*.desktop` files via `gc_synthetic_launchers()` when their windows close.

### 3.3. Dock Overflow Smooth Scrolling & Tachometer Capacity Indicator
- **Boundary Clamping & Interpolated Wheel Scrolling (`PositionManager.vala`, `DockRenderer.vala`, `DockWindow.vala`)**: Clamps dock geometry to monitor width/height and interpolates mouse wheel scrolling (`scroll_offset += (target_scroll_offset - scroll_offset) * 0.35`) when pinned/running items exceed available screen span.
- **Tachometer Redline Slider (`PreferencesWindow.vala`)**: Real-time capacity feedback on the Icon Size slider using a custom red SVG teardrop marker (`slider-marks-below-red.svg`) when `scroll-on-overflow` is disabled and icons exceed monitor bounds.

### 3.4. Drag-and-Drop (DND) Remote Web URLs, MIME Validation & Hover Window Raising
- **Remote Web URL Delivery (`DragManager.vala`, `System.vala`)**: Supports `text/uri-list`, `text/x-moz-url`, `UTF8_STRING`, `text/plain`, `text/html`, and UTF-16LE clipboard decoding; dropping URLs on the dock background opens the default browser, while dropping onto a browser icon opens a new tab. Parses `.desktop` (`Type=Link`) and `.url` internet shortcuts.
- **Hover Window Activation During Drag (`DragManager.vala`)**: Pausing cursor hover over a running dock icon for >500 ms during an active drag raises the target window via `WindowManager.activate()`.
- **Strict FreeDesktop MIME Drop Validation (`ApplicationDockItem.vala`)**: Enforces `Gio.ContentType` compatibility against `.desktop` `MimeType=` declarations so incompatible drops bounce cleanly.
- **Instant Drag-Off Removal & Poof Animation**: Dragging an unrunning pinned icon off the dock deletes its `.dockitem` immediately and triggers the Cairo `PoofWindow` animation.

### 3.5. Universal Multi-Window Preview Cards (`WindowCard.vala`, `WindowCardsWindow.vala`)
- **Cairo Elevated Card Popup**: Clicking a multi-window application icon opens `WindowCardsWindow` anchored over the dock item (while hovering shows the text tooltip). Configurable via **Preferences $\rightarrow$ Behaviour $\rightarrow$ Window Preview Cards**.
- **Live Compositor Thumbnails & Graceful Fallback**:
  - **KDE Plasma 6 (KWin)**: Live window pipe capture via `org.kde.KWin.ScreenShot2` (`KWinThumbnailService.vala`) with forced full opacity (`buffer[i + 3] = 255`) and `X-KDE-DBUS-Restricted-Interfaces` autostart whitelist.
  - **GNOME Shell (Mutter)**: Live window capture via the companion extension D-Bus bridge (`CaptureWindowPreview`).
  - **Labwc (wlroots)**: High-contrast vector application icon card fallback with full window titles and close/focus actions.

### 3.6. True Dynamic System Theme Switching, Interactive Theme Manager & 6 Stock Themes
- **Multi-Protocol Dark/Light Detection (`SystemTheme.vala`, `DrawingService.vala`)**: Listens simultaneously to FreeDesktop Portal (`org.freedesktop.portal.Settings` `color-scheme`), GNOME `org.gnome.desktop.interface`, and KDE `~/.config/kdeglobals` inotify events, automatically swapping counterpart themes (*Arian Theme Light* $\leftrightarrow$ *Dark*, *IFtiger Theme Light* $\leftrightarrow$ *Dark*) or refreshing the adaptive `Default` theme in real time.
- **Interactive Theme Manager (`ThemeManager.vala`, `PreferencesWindow.vala`)**: Native `Gtk.FileChooserNative` portal installer (`+`) and uninstaller (`Trash`) supporting `.zip`, `.tar.gz`, `.tar.xz`, `.tar.bz2`, and `.theme` archives into `~/.local/share/wayplank/themes/`.
- **6 Built-In Themes (`data/themes/`)**: `Default` (adaptive GTK+), `Arian Theme Dark`, `Arian Theme Light`, `IFtiger Theme Dark`, `IFtiger Theme Light`, and `Transparent` (`TopPadding = -11`).

### 3.7. Folder Drawers, Running Indicator Dots & Recent Files Jump List
- **Folder Running Indicator Dots (`FileDockItem.vala`, `FolderMenuWindow.vala`, `DockRenderer.vala`)**: Renders 1 or 2 illuminated running dots on pinned folder icons when apps inside the folder are running, plus per-row running indicator dots inside open folder popups with anti-clipping reverse-roundness geometry.
- **Folder Drawer UX Parity (`FolderMenuWindow.vala`)**: Full click behavior compliance (`Smart`, `Focus`, `Cycle`), `Ctrl+Left Click` / `Middle Click` new instance launch, mouse wheel window cycling, and attached row context menus with `context_menu_active` guard.
- **Recent Files Jump List (`RecentFilesService.vala`)**: Native `Gtk.RecentManager` submenu in application right-click context menus filtered by desktop ID and MIME type.

### 3.8. 16 Built-In Zero-Dependency Docklets, 7×2 Grid & 4-Mode System Menu Access
- **16 Embedded Docklets**:
  - **14 in the symmetric 7×2 Docklets Grid**: `Clippy`, `Clock`, `Battery`, `Trash` (also accessible in Appearance), `Desktop` (Show Desktop), `Applications`, `Workspaces`, `Weather`, `Session`, `CPUMonitor`, `Volume`, `MPRIS` (Media Player with Album Art, `Align by Type`, middle-click Play/Pause, scroll track skip), `Brightness`, and `Network` (`nmcli` Wi-Fi/Ethernet monitor).
  - **Do Not Disturb (`docklet://dnd`)**: Desktop notification mute toggle synchronized with KDE Plasma and GNOME Shell.
  - **Dedicated Preferences Docklet (`docklet://preferences`)**: Automatically placed on the dock when System Menu Access Mode 4 is selected.
- **4-Position System Menu Access (`Preferences -> Behaviour`)**: `Docklets Only`, `Docklets Only (Auto Fallback)`, `All Icons`, or `Dedicated Preferences Icon` (with `Ctrl + Right Click` always available on any icon).
- **HAL Multi-Monitor Brightness Sync (`BrightnessControl.vala`, `BrightnessDockItem.vala`)**: Decouples hardware `/sys/class/backlight` polling (500 ms heartbeat) and multi-monitor DDC/CI (`kscreen-doctor` on KWin, `ddcutil` on Mutter/Labwc) into `lib/Services/BrightnessControl.vala` with a 350 ms inbound settle debounce and SP/PV anti-echo decoupling.
- **Volume Overamplification Guard (`VolumeDockItem.vala`)**: Enforces a strict 150% hardware cap (`wpctl set-volume -l 1.5` / `pactl`).

### 3.9. HAL Window Management, Panel Mode, Fullscreen Inhibit & Input Mask Hysteresis
- **Zero Async Timers & Peer Dialog Stacking (`AbstractMain.vala`, `SessionWindow.vala`, `WeatherWindow.vala`)**: Eliminated asynchronous presentation timers (`GLib.Timeout.add`) to prevent Mutter `meta_window_unmanage` `SIGABRT` crashes; removed artificial `transient_for` on independent dialogs for natural bidirectional stacking and native Mutter CSD HeaderBars.
- **Cross-Compositor Show Desktop & Workspace Visibility (Issues #11 & #13 / FAT Points 4.1 & 6.1)**:
  - Synchronizes `showingDesktopChanged` on KWin, `showing-desktop-changed` + `workspace-changed` + `hide_from_window_list()` on GNOME Mutter, and `t->active` filtering in `wlr-toplevel-bridge.c` on Labwc.
- **Cold-Start HiDPI Fractional Scaling Sync (Issue #5 / FAT Point 7.7)**: Listens to `notify["scale-factor"]` in `PositionManager.vala` to reset Cairo buffers and recompute layout when fractional scaling settles on cold start.
- **HoverWindow Popup Standardization & Exact Mutter Classification (FAT Points 5.1 & 0.4)**: Uses `set_role("popup-menu")` and `Gdk.WindowTypeHint.POPUP_MENU` across all floating dock popups (`HoverWindow`, `FolderMenuWindow`, `WindowCardsWindow`) and enforces strict `===` title matching in `MutterBackend.vala` (`_classifyWindow`).
- **Two-Stage Hysteresis Input Mask & Transparent Passthrough (Issue #12 / FAT Point 5.4)**:
  - Configurable **Anticipate Icon Zoom** (`anticipate-zoom`, default `true`) in **Preferences $\rightarrow$ Behaviour**. When disabled, the layer-shell input region strictly hugs the 60 px visual dock pill at rest so 100% of clicks above the dock pass through to underlying windows, dynamically expanding upward by `hover_region` only while an icon is actively hovered.
- **Reserve Screen Space / Panel Mode (Issue #9 / FAT Point 3.8)**:
  - Configurable **Reserve Screen Space** (`reserve-space`) in **Preferences $\rightarrow$ Behaviour** (mutually exclusive with Auto-Hide and Icon Zoom). Uses `GtkLayerShell.set_exclusive_zone` on KWin/Labwc and physical-monitor-anchored (`monGeo`) chrome struts (`affectsStruts: true`) with dynamic content-hashed ES module reloading (`impl-<hash>.js`, `version: 4`) and unconstrained `user_op = true` positioning on GNOME Shell.
- **Fullscreen Window Inhibit & 0px Edge Click Passthrough (Issue #10 / FAT Point 3.9)**:
  - Detects direct unmaximized-to-fullscreen transitions (`Fullscreen` state and `fullscreen_window_intersects()`) across KWin, Mutter, and Labwc, hides the dock across all `HideMode`s (including `HideType.NONE`) via `FullscreenInhibit`, and sets `get_cursor_region()` to `{ 0, 0, 0, 0 }` so 100% of `0px` screen-edge clicks pass through to fullscreen apps (Remmina, MPV, browsers, games).

---

## 4. 🧪 Public Beta Factory Acceptance Testing (FAT 0.7.0)

- **381 Total Qualification Test Points Defined**:
  - **370 Baseline Test Points (`368 [ok]` + `2 [NA]`, `0` Open Defects)**: Consolidated via ISA-88 Phase B from the 100% qualified `v0.6.2.3` release across **GNOME Shell (Mutter)**, **KDE Plasma 6 (KWin)**, and **Labwc (wlroots)**.
  - **11 New Embedded I18N & Localization Test Points (Section 12, `12.1`–`12.11`)**:
    - `12.1`: Build-Time `.po` Validation & `.mo` Compilation (`326/326` strings across 7 languages, 0 errors/warnings).
    - `12.2`: Monolithic `GResource` Embedding & Zero Host Pollution (`0` files in `/usr/share/locale/`).
    - `12.3`–`12.9`: Live Runtime Verification for `zh_CN`, `it`, `es`, `fr`, `ca`, `de`, and `uk`.
    - `12.10`: Fallback Verification (`LANG=C` / `LANG=en_US.UTF-8`).
    - `12.11`: Dynamic Widget Layout Resilience (no text clipping or overlapping controls in `PreferencesWindow`, `WeatherWindow`, `SessionWindow`, or context menus across verbose locales such as German and Ukrainian).

---

## 5. 🗺️ Master Release Trajectory

```
v0.6.2.3 (Pre-Beta Finale) ──► v0.7.0 (Public Beta 1) ──► v0.8.x (Release Candidate) ──► v0.9.x (Stabilization) ──► v1.0.0 (Grand Milestone)
```

- **v0.7.x (Public Beta — Week 45: Monday, November 2, 2026)**: Feature-complete monolithic localization release & community field testing across KWin, Mutter, Labwc, Sway, and Hyprland.
- **v0.8.x (Release Candidate Series)**: Strict feature freeze, memory leak profiling (Valgrind), and packaging stabilization.
- **v0.9.x (Long-Term Production Stabilization)**: The official battle-tested production milestone for daily driving across all Linux distributions.
- **v1.0.0 (Grand Milestone Horizon — ~2 Years)**: Definitive landmark release celebrating multi-year proven stability and mature Wayland protocol standards.
