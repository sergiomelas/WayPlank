# 🛡️ WayPlank Lifetime Master Bug & Defect Register

> **Project:** WayPlank (Lightweight native Wayland dock based on Plank architecture)  
> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Scope:** Complete Lifetime Audit — From Inception (`v0.1.0`) to Present (`v0.7.0` Public Beta 1)  
> **Period:** 2026-09-19 to 2026-11-05  
> **Standard:** ISA-88 Qualification Standard

---

## 📊 Lifetime Executive Scoreboard

* **ERA 1 (Pre-FAT Foundation & X11 Purge: `v0.1.0` – `v0.4.2`)**:
  - **Milestones**: 6 (`v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.4.0`, `v0.4.1`, `v0.4.2`)
  - **Architectural Bugs & Blockers Resolved**: **34** `[ko->ok]`
* **ERA 2 (Multi-Compositor Qualification & Public Beta 1: `v0.4.3` – `v0.7.0`)**:
  - **Milestones**: 10 (`v0.4.3`, `v0.5.0`, `v0.5.1`, `v0.5.2`, `v0.6.0`, `v0.6.1`, `v0.6.2.1`, `v0.6.2.2`, `v0.6.2.3`, `v0.7.0`)
  - **Formal Tests Executed**: **2,416** Total Test Executions across Compositors
  - **Tests Passed on First Run / Baseline**: **2,213** `[ok]`
  - **Unique Functional Bugs Squashed**: **80** `[ko->ok]`
  - **Total Compositor Test Verifications**: **131** `[ko->ok]`
  - **Open FAT Regressions Remaining (`2026-11-05` Audit)**: **7 Active Audit Issues (`#19`–`#25`) / 33 `[ko]` Compositor Instances** (**344/377 = 91.2% PASS** across all 3 compositors — queued for `v0.7.1`; plus Community Issues [#16](https://github.com/sergiomelas/WayPlank/issues/16) & [#18](https://github.com/sergiomelas/WayPlank/issues/18) awaiting reporter confirmation and Feature Proposal [#26](https://github.com/sergiomelas/WayPlank/issues/26), totaling `10` open GitHub issues)
* **GRAND TOTAL ACROSS LIFETIME**:
  - **Total Milestones**: **16 Releases**
  - **Total Unique Functional & Architectural Bugs Squashed**: **114** `[ko->ok]`
  - **Total Multi-Compositor Verification Instances**: **165** `[ko->ok]`

---

## 🗓️ Historical Milestone Qualification Matrix

| Milestone | Date | Scope & Focus | FAT Points | Squashed | Open |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **`v0.1.0`** | 2026-09-19 | Autotools & Namespace | Pre-FAT | 4 | 0 |
| **`v0.2.0`** | 2026-09-22 | Layer Shell & `/proc` | Pre-FAT | 5 | 0 |
| **`v0.3.0`** | 2026-09-23 | Early KWin D-Bus & Zoom | Pre-FAT | 5 | 0 |
| **`v0.4.0`** | 2026-09-24 | Modular & Intellihide | Pre-FAT | 6 | 0 |
| **`v0.4.1`** | 2026-09-25 | Multi-Mon & Tooltips | Pre-FAT | 4 | 0 |
| **`v0.4.2`** | 2026-10-02 | Monolithic Docklets | Pre-FAT | 10 | 0 |
| **ERA 1 SUB** | **Foundation** | **6 Early Engine Milestones** | **Pre-FAT** | **34** | **0** |
| **`v0.4.3`** | 2026-10-06 | 3-Compositor Baseline | 117 | 9 | 0 |
| **`v0.5.0`** | 2026-10-07 | Cross-Compositor Check | 120 | 0 | 7 `ko`* |
| **`v0.5.1`** | 2026-10-08 | 100% Pass (all rem.) | 162 | 15 | 0 |
| **`v0.5.2`** | 2026-10-09 | Session & Brightness | 203 | 4 | 0 |
| **`v0.6.0`** | 2026-10-11 | Shortcuts & Debounce | 231 | 1 | 0 |
| **`v0.6.1`** | 2026-10-13 | 0-byte MIME & Badges | 246 | 7 | 0 |
| **`v0.6.2.1`** | 2026-10-17 | Fork & Gold Standard | 282 | 16 | 0 |
| **`v0.6.2.2`** | 2026-10-20 | Round 2 & DND Docklet | 306 | 5 | 0 |
| **`v0.6.2.3`** | 2026-11-01 | Previews, Stacks, Comm. | 370 | 27 | 0 |
| **`v0.7.0`** | 2026-11-05 | Public Beta 1 & Audit | 379 | 7 | 7 `ko`** |
| **ERA 2 SUB** | **Formal FAT** | **10 Multi-Comp. Releases** | **2,416** | **80** | **7 `ko`** |
| **TOTAL** | **All Eras** | **16 Milestone Releases** | **2,416** | **114** | **7 `ko`** |

*\*Note on `v0.5.0`: The 7 `[ko]` defects discovered were formally remediated and verified in `v0.5.1` under standard ISA-88 qualification protocol.*  
*\*\*Note on `v0.7.0` (`2026-11-05` Post-Release Deep Audit): 7 non-critical regression groups (GitHub Issues [#19](https://github.com/sergiomelas/WayPlank/issues/19)–[#25](https://github.com/sergiomelas/WayPlank/issues/25), covering 33 `[ko]` compositor test instances across 14 unique FAT points; `344/377` = `91.2% PASS`) are logged openly and queued for remediation in `v0.7.1`.*

---

## 🖥️ Compositor Resolution Breakdown (Era 2 Qualification)

| Compositor Backend | Verifications Squashed `[ko->ok]` | Share | Active Open `[ko]` (`v0.7.1` Queue) |
| :--- | :---: | :---: | :---: |
| **GNOME Shell (Mutter Backend)** | 57 | 43.5% | 11 (`91.4% PASS`) |
| **KDE Plasma 6 (KWin Backend)** | 42 | 32.1% | 11 (`91.3% PASS`) |
| **Labwc (wlroots Backend)** | 32 | 24.4% | 11 (`91.1% PASS`) |
| **TOTAL COMPOSITOR VERIFICATIONS** | **131 Squashed** | **100%** | **33 Open (`344/377` — `91.2% PASS`)** |

---

## 🔴 Active Open Regressions (`v0.7.0` Audit — Queued for `v0.7.1`)

1. **[Issue #19](https://github.com/sergiomelas/WayPlank/issues/19)** (`FAT 12.2` `[ko]` — All 3 Compositors): Missing *"Recent Documents"* `Gtk.RecentManager` jump-list submenu in app right-click menus (`RecentFilesService` omitted during `v0.6.2.3` consolidation).
2. **[Issue #20](https://github.com/sergiomelas/WayPlank/issues/20)** (`FAT 1.11` `[ko]` — All 3 Compositors): Normal Google Chrome windows misassigned to specialized `.sh` browser profile wrappers (`score = 116 >= 115` via shared single-process tokens).
3. **[Issue #21](https://github.com/sergiomelas/WayPlank/issues/21)** (`FAT 5.6, 7.11, 10.4, 12.4` `[ko]` — All 3 Compositors): Mouse, scroll & modifier gesture regressions (`Shift+Left Click` window cycle, preview card `Middle-Click` close, `MPRIS` wheel/middle-click parity, overflow scroll hijacking, `Ctrl+Alt+Shift+Right Click` inspector, and right-side Accordion tooltip arrow).
4. **[Issue #22](https://github.com/sergiomelas/WayPlank/issues/22)** (`FAT 2.7` GNOME, `2.9 & 12.6` KDE `[ko]`): Multi-compositor HAL signal & preview cache regressions (Mutter background urgency `WindowsChanged` & `MinimizedSequence`, KWin `captionChanged` dynamic title sync, `KWinThumbnailService` refresh/eviction/`stderr`/Labwc guard).
5. **[Issue #23](https://github.com/sergiomelas/WayPlank/issues/23)** (`FAT 6.12` GNOME/Labwc, `6.18` Labwc `[ko]`): Labwc Do Not Disturb unguarded `gsettings` early return breaking `dunstctl`/`swaync-client`, and multi-DE KDE settings tool priority ahead of `XDG_CURRENT_DESKTOP`.
6. **[Issue #24](https://github.com/sergiomelas/WayPlank/issues/24)** (`FAT 1.11, 10.8, 13.8` `[ko]` — All 3 Compositors): Folder `ShowRunningIndicators` & live notify, `PoofWindow` `1500 ms` `EffectDuration` clamp, `ReverseRoundness` 40px skirt in redline capacity math, and CLI `-V` verbose short flag.
7. **[Issue #25](https://github.com/sergiomelas/WayPlank/issues/25)** (`FAT 1.10` `[ko]` — All 3 Compositors): Custom image file icons on folders strip `file://` in `metadata::custom-icon`, racing `FileMonitor` reload and reverting to the default folder icon.

---

## 🧩 Defect Classification by Subsystem

### 1. Window Management, Focus & Virtual Desktops (19 Bugs)
- KWin FIFO command queue for rapid multi-window close (`v0.4.3` / `2.8`)
- `getAllWindows()` & `switchToDesktopIfNeeded()` window list focus (`v0.4.3` / `2.9`)
- Sticky dock surface across virtual desktops on KWin (`v0.4.3` & `v0.5.1` / `4.1`)
- GNOME Shell workspace changed signal tracking (`v0.5.1` & `v0.6.2.3` / `4.1`, Issue #11)
- Labwc `t->active` workspace intersection filtering (`v0.6.2.3` / `4.1`, Issue #11)
- Attention bounce easing underflow & `LastUrgent` timestamp (`v0.5.1` / `v0.6.2.1`)
- Smooth mouse-wheel window focus cycling (`v0.4.2` / `6.10`)
- Anti-bounce on application window closure (`v0.4.2` / `6.8`)
- Show Desktop bi-directional stateful restore toggle (`v0.4.2` / `6.2`)
- Ghost window shielding for screen-sharing helpers (`v0.6.2.1` / `10.11`)
- Urgent window auto-scrolling on dock overflow (`v0.6.2.1` / `10.6`)
- Running indicator dots for folder items & drawer rows (`v0.6.2.3` / `1.11`)
- Folder drawer application contract parity & wheel cycling (`v0.6.2.3` / `1.12`)
- Cross-compositor dock persistence on "Show Desktop" (`Super + D`) via KWin D-Bus signal bridge, GNOME Mutter `hide_from_window_list()` + `showing-desktop-changed`, and Labwc `t->active` (`v0.6.2.3` / `6.1`, Issue #13)
- GNOME Mutter exact surface title classification (`===`) & `show_in_window_list()` self-healing (`v0.6.2.3` / `0.4`)

### 2. Multi-Monitor, Display Geometry & Tooltips (21 Bugs)
- Layer-shell secondary monitor display persistence (`v0.4.1` & `v0.5.1` / `7.2`)
- Tooltip coordinate translation on secondary screens (`v0.4.1` / `5.2`)
- Primary display toggle off restoration failure (`v0.5.1` / `7.2`)
- Fractional scaling & HiDPI label identity matching + cold-start `notify["scale-factor"]` listener (`v0.5.1` & `v0.6.2.3` / `7.7`, Issue #5)
- Folder menu centering bug on GNOME Mutter (`v0.5.2` & `v0.6.2.1` / `1.8`)
- Shortcuts & Gestures dialog centering on Mutter (`v0.6.0` / `7.12`)
- Multi-monitor DDC/CI & back-end brightness decoupling (`v0.6.2.1` / `6.10`)
- Rapid display reconfiguration & DPI storm hardening (`v0.5.1` / `9.6`)
- About dialog screen centering via independent toplevel & role binding (`v0.6.2.3` / `7.1`)
- Cross-compositor peer dialog stacking & sub-popup decoupling (`v0.6.2.3` / `7.15`)
- AboutDialog native CSD HeaderBar & close action on Mutter (`v0.6.2.3` / `7.16`)
- KDE Plasma 6 dynamic top floating panel offset & maximized de-float synchronization (`v0.6.2.3` / `7.2`)
- Dynamic scale capacity redline SVG teardrop pointer, topology auto-shrink & dual-color highlight split (`v0.6.2.3` / `10.8`)
- HAL Prime Directive extraction & Multi-monitor external auto-sync (`v0.6.2.3` / `6.10b`)
- GNOME Mutter vertical dock resize-commit race & `size-changed` re-anchoring (`v0.6.2.3` / `7.2`)
- KDE Plasma 6 multi-monitor per-screen floating panel check & layer-shell `GtkWindow` resize synchronization (`v0.6.2.3` / `7.6`)
- `HoverWindow` `popup-menu` role standardization & 25ms post-show coordinate re-assertion (`v0.6.2.3` / `5.1`)
- KDE Plasma 6 primary panel monitor tracking (`__wayplank_primary_panel__` in-RAM KWin bridge & `plasmashell` panel observer) and Labwc Honest UI disable for `On Primary Display` (`WindowCapabilities.primary_display_supported()`) (`v0.7.0` / `7.6`)

### 3. Docklets & Special Items (19 Bugs)
- Trash docklet bi-directional D-Bus sync with Dolphin/KIO (`v0.4.2` / `6.1`)
- Screenshot docklet multi-compositor fallback (`v0.5.1` & `v0.5.2` / `6.5`)
- Session & Power docklet lock-screen SDDM fallback (`v0.5.2` / `6.5`)
- Screen brightness 3s debounce & GPU override loop fix (`v0.5.2` / `6.10`)
- Weather forecast docklet vector SVG icon fallback (`v0.6.2.1` / `6.11`)
- Docklet badge unit strings (`°C`, `°F`, `%`) & proportional scaling (`v0.6.1` / `6.17`)
- Volume over-amplification guard and step scrolling (`v0.4.2` & `v0.6.2.1`)
- Battery sysfs introspection on modern Wayland systems (`v0.4.2` / `6.4`)
- CPU/RAM differential calculation in circular gauges (`v0.4.2` / `6.5`)
- Session & Power dialog centering on GNOME Mutter (`v0.6.2.3` / `6.5`)
- Weather location settings dialog crash on GNOME Mutter (`v0.6.2.3` / `0.1`)
- Asynchronous timer elimination & Mutter assertion crash prevention (`v0.6.2.3` / `0.2`)
- Strict Minimalist Dock Mode (Mode 1: `Docklets Only` — zero app intrusion fallback) (`v0.6.2.3` / `13.6`)

### 4. Hide, Dodge, Hover & Pressure Reveal (14 Bugs)
- Mouse hover zoom stuck on layer-shell surfaces (`v0.3.0` / `3.2`)
- Intellihide geometric intersection calculation (`v0.4.0` / `4.2`)
- Fullscreen exclusive zone toggle to 0 (`v0.4.0` / `4.3`)
- Pressure reveal timer leak & mouse unhide race (`v0.6.1` / `3.7`)
- Inverted pressure reveal semantics: 10px default vs 1px pressure (`v0.6.1`)
- Layer-shell tooltip margin clamping against negative coordinates (`v0.4.2`)
- Layer-shell input passthrough clipping for permanent non-hiding dock (`v0.6.2.3` / `3.1`)
- Two-stage hysteresis flip-flop & `AnticipateZoom` runway pointer click stealing on overlapping windows (`v0.6.2.3` / `5.4`, Issue #12)
- Direct unmaximized-to-fullscreen auto-hide & `0px` edge click passthrough (`v0.6.2.3` / `3.9`, Issue #10)
- `ReserveSpace` Panel Mode exclusive zone / synthetic strut & mutual exclusivity guard (`v0.6.2.3` / `3.10`, Issue #9)
- Edge-triggered SR Flip-Flop for clickable `Reserve Screen Space`, `Hide Dock` & `Icon Zoom` across GUI and CLI `gsettings` (`v0.7.0` / `3.10`, Issue #17)

### 5. Application Matching, Sandboxes & Pinning (20 Bugs)
- Asynchronous `/proc` process scanner for Wayland (`v0.2.0` / `2.3`)
- Multi-tier `.desktop` application discovery & `app_id` matching (`v0.4.0` / `4.4`)
- 0-byte file drop with `application/x-zerosize` MIME guessing (`v0.6.1` / `1.6`)
- Strict `.desktop` pinning precedence over app drop handlers (`v0.6.2.1` / `1.6`)
- Sandbox / wrapper unwrapping (Flatpak, Snap, Firejail) (`v0.6.2.1` / `2.12`)
- Universal Change Icon & theme change fallback (`v0.6.1` & `v0.6.2.1` / `1.10`)
- Show Unpinned dynamic layout refresh without window focus (`v0.6.1` / `7.14`)
- Canonical launcher deduplication via `Posix.realpath` & `equal` (`v0.6.2.2` / `11.7`)
- Strict FreeDesktop MIME rejection on application drops (`v0.6.2.2` / `11.6`)
- KISS Drag-Off immediate removal & poof animation (`v0.6.2.2` / `11.8`)
- Desktop link shortcut (`Type=Link` & `URL[$e]`) parsing and launch (`v0.6.2.2` / `11.1`)
- Application identity, Chromium PWA (`pwa_id` & `ResourceName` multi-PWA profile isolation) & word-boundary matching (`v0.6.2.3` & `v0.7.0` / `2.14`)
- CLI virtual machines, Exec-less `NoDisplay=true` template matching & `gc_synthetic_launchers()` garbage collection (`v0.6.2.3` / `2.15`, Issue #14)
- Multi-VM instance isolation & generic argument stopwords (`v0.6.2.3` / `2.15`, Issue #14)
- `LabwcBackend.resolve_toplevel_process()` $O(1)$ `/proc` PID/cmdline resolver & synthetic `.desktop` self-healing for Labwc VM cold relaunch (`v0.6.2.3` / `2.15`, Issue #14)
- URI-keyed folder/web-app isolation, `NoDisplay=true` PWA ↔ `--app=URL` & sibling `WMClass` parity, and open-popup folder DnD (`v0.7.0` / `1.11` — `.sh` profile wrapper isolation reopened as `#20` for `v0.7.1`)
- CLI-launched GUI & AppImage (`/proc/<pid>/environ` `APPIMAGE=`) discovery, dynamic-title binding stability & zero-hardcoding dialog masking (`v0.7.0` / `2.15`, Issue #16)
- HAL `SurfaceCoordinateService` overlay positioning, timer-free VSync 3-Beat unpin pipeline & `PendingRemovalLauncher` deduplication (`v0.7.0` / `11.8`)

### 6. Process Lifecycle, IPC Bridges & Architectural Purge (21 Bugs)
- Purge of 112,000+ lines of obsolete X11 Autotools & VAPIs (`v0.1.0` – `v0.3.0`)
- Purge of dynamic shared-library docklet plugins (`v0.4.0` / `4.5`)
- CLI `--replace` / `-r` flag registration & clean `killall` (`v0.4.2` & `v0.5.1`)
- KWin resume event storm prevention via 50ms `QTimer` debouncer (`v0.5.1` / `9.6`)
- KWin duplicate script prevention on system sleep/resume (`v0.5.1` / `9.4`)
- Labwc `wlr-toplevel` RFC 8259 JSON escaper for UTF-8 bytes (`v0.5.1` / `2.13`)
- Labwc toplevel callback 50ms single-shot debouncer (`v0.5.1` / `9.7`)
- Native RPM packaging for openSUSE and Fedora (`v0.6.2.1` / Round 1)
- FreeDesktop color-scheme Settings portal D-Bus sync (`v0.6.2.2` / `11.3`)
- ThemeManager archive scanner & native portal file chooser (`v0.6.2.2` / `11.5`)
- KWin `ScreenShot2` D-Bus pipe capture & binary authorization (`v0.6.2.3` / `12.1`)
- Dynamic counterpart theme swapping & buffer reset (`v0.6.2.3` / `11.4`)
- `WindowCardsWindow` dynamic positioning without stale caching (`v0.6.2.3` / `12.2`)
- GNOME Shell crash safety mode unblock & extension self-healing bootstrap (`v0.6.2.3` / `9.9`)
- KWin D-Bus service watcher & bridge script self-healing (`v0.6.2.3` / `0.1`)
- KWin preview cards first-hover zero-alpha & autostart `ScreenShot2` authorization (`v0.6.2.3` / `12.6`)
- GNOME Shell extension error-latch recovery, floating dock concealment & unaccelerated `/proc` throttle (`v0.6.2.3` / `0.3`)
- GNOME Mutter D-Bus window position recursive loop elimination (`v0.6.2.3` / `2.15` & `0.3`)
- Cross-compositor instantaneous startup (`GTK_USE_PORTAL=0` / `NameHasOwner` portal decoupling, background `kscreen-doctor` probing, KWin single-load owner guard, Labwc native `autostart` sync), `SIGTERM` clean shutdown handshake & `LC_ALL=C` audio volume locale fix (`v0.7.0` / `0.1` & `0.3`)
- Screen lock/unlock, idle & DPMS sleep/wake dock self-healing (`_lastDockGeo` Mutter deadlock break, `bridge_reconnected`, `login1.Session.Unlock`, `dock_unmapped` recovery) & `SIGWINCH` live `.deb` upgrade reload (`v0.7.0` / `9.9` & `9.10`, Issue #18)
- Cross-compositor internal popup window-event filtering, multi-size `SurfaceCache` & 50ms VSync motion hold for 60 FPS hover at `0.1%` idle CPU (`v0.7.0` / `0.1` & `0.3`)

---

## 📁 Directory of Corresponding FAT Documents

1. [`FAT/2026-10-02 PRE-FAT  (v0.1.0 - v0.4.2).txt`](2026-10-02%20PRE-FAT%20%20%28v0.1.0%20-%20v0.4.2%29.txt) — Covers `v0.1.0` to `v0.4.2` (34 bugs squashed)
2. [`FAT/2026-10-06 FAT 0.4.3.txt`](2026-10-06%20FAT%200.4.3.txt) — Covers `v0.4.3` (117 tests, 9 bugs squashed)
3. [`FAT/2026-10-07 FAT 0.5.0.txt`](2026-10-07%20FAT%200.5.0.txt) — Covers `v0.5.0` (120 tests, 7 open defects logged)
4. [`FAT/2026-10-08 FAT 0.5.1.txt`](2026-10-08%20FAT%200.5.1.txt) — Covers `v0.5.1` (162 tests, 15 bugs squashed, 100% compliant)
5. [`FAT/2026-10-09 FAT 0.5.2.txt`](2026-10-09%20FAT%200.5.2.txt) — Covers `v0.5.2` (203 tests, 4 bugs squashed, 100% compliant)
6. [`FAT/2026-10-11 FAT 0.6.0.txt`](2026-10-11%20FAT%200.6.0.txt) — Covers `v0.6.0` (231 tests, 1 bug squashed, 100% compliant)
7. [`FAT/2026-10-13 FAT 0.6.1.txt`](2026-10-13%20FAT%200.6.1.txt) — Covers `v0.6.1` (246 tests, 7 bugs squashed, 100% compliant on KWin)
8. [`FAT/2026-10-17 FAT 0.6.2.1.txt`](2026-10-17%20FAT%200.6.2.1.txt) — Covers `v0.6.2.1` (282 tests, 16 bugs squashed, 100% compliant Gold Standard)
9. [`FAT/2026-10-20 FAT 0.6.2.2.txt`](2026-10-20%20FAT%200.6.2.2.txt) — Covers `v0.6.2.2` (306 tests, Round 2 completed, 100% compliant, 0 pending, Gold Standard)
10. [`FAT/2026-11-01 FAT 0.6.2.3.txt`](2026-11-01%20FAT%200.6.2.3.txt) — Covers `v0.6.2.3` (370 tests, Round 3: Window Cards, Dynamic System Theming, Recent Files, Stock Themes, Folder Running Dots, Drawer UX Parity, Native Peer Stacking, 4-Position System Menu Access, Do Not Disturb Docklet, 7×2 Balanced Preferences Grid, KDE Plasma 6 Multi-Monitor Floating Panel Tracking, Layer-Shell Input Passthrough, Fullscreen Auto-Hide & `0px` Edge Passthrough [Issue #10], Reserve Screen Space / Panel Mode [Issue #9], Show Desktop Persistence [Issue #13], Workspace Switch Visibility [Issue #11], Cold-Start Fractional Scaling [Issue #5], & Multi-VM Instance Tracking with Garbage Collection [Issue #14] on GNOME, KDE Plasma, Labwc)
11. [`FAT/2026-11-05 FAT 0.7.0.txt`](2026-11-05%20FAT%200.7.0.txt) — Covers `v0.7.0` (Public Beta 1 & `2026-11-05` Audit: 379 tests defined, 344/377 applicable passed — `91.2% PASS`: 324 `[ok]` baseline + 20 `[ko->ok]` squashed across GNOME Shell, KDE Plasma 6, and Labwc, 2 `[NA]`, 33 `[ko]` open defect instances across Issues [#19](https://github.com/sergiomelas/WayPlank/issues/19)–[#25](https://github.com/sergiomelas/WayPlank/issues/25) queued for `v0.7.1`)
