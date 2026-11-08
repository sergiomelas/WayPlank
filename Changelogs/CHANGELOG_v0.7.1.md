# WayPlank V0.7.1 (Public Beta 2) Detailed Technical Changelog

Release Series: **V0.7.x Series (The Public Beta Milestone)**  
Current Milestone: **V0.7.1 (Public Beta 2: First-Run Onboarding Classic vs Explorer, 100% Read-Only Legacy Plank Migration, Pinned Apps Usage-Adaptive Accordion, MONLMIP Rank 1, SR Flip-Flop Reboot Persistence, Browser Auto-Translated User Guide, 6-Layer Application Identity Engine, KDE Plasma Edit Mode Coexistence & Zero-[ko] Remediation)**  
Target Release Date: **Week 46 (November 2026)**  
Maintainer: **Sergio Melas** (sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))  
Collaborators & Contributors:
- **史有虎 (IFtiger-hu)** (Collaborator & Simplified Chinese Reviewer, GitHub: [@IFtiger-hu-hub](https://github.com/IFtiger-hu-hub))
- **Renate Schwiedernoch** (German `de` Localization Contributor)
- **Michailo Buchko** (Ukrainian `uk` Localization Contributor)
- **@polpodan** (Community Issue Reporter — Issue [#27](https://github.com/sergiomelas/WayPlank/issues/27))

---

## 1. 📋 Overview & Motivation

Following the formal conclusion and freeze of **Public Beta 1 (`v0.7.0`, [`FAT/2026-11-05 FAT 0.7.0.txt`](../FAT/2026-11-05%20FAT%200.7.0.txt) at `359/377` = `95.2% PASS`, with 18 open `[ko]` points transferred to `v0.7.1`)**, **WayPlank `v0.7.1` (Public Beta 2)** delivers a major user-experience and architectural consolidation:
1. **First-Run Onboarding Popup (`FirstRunWindow` — `WayPlank Classic` vs `WayPlank Explorer`) + 100% Read-Only Legacy Plank Migration (`~/.config/plank` $\rightarrow$ `~/.config/wayplank`, `FAT 1.9` `[  ]`)**:
   - Copies compatible `.dockitem` launchers, user folders (`FileDockItem`), and supported docklets from `~/.config/plank/<dock>/launchers` into `~/.config/wayplank/<dock>/launchers` in **100% read-only mode** so dual-session X11 Plank configurations are never modified or deleted.
   - Presents `FirstRunWindow` on first launch so users can choose between **🏛️ WayPlank Classic** (Free Mode near classic Plank) and **🚀 WayPlank Explorer** (Categorized mode + 4 Smart Folder Drawers + Docklets Accordion + Pinned Apps Accordion `Auto-Fit Capacity` + Window Preview Cards) without ever deleting existing user items or folders.
2. **Smart Usage-Adaptive Accordion for Pinned Apps (`PinnedExpanderDockItem`, `AppUsageService`, Issue [#26](https://github.com/sergiomelas/WayPlank/issues/26), `FAT 6.14` `[  ]`)**:
   - Ports GNOME Shell's `shell-app-usage.c` frecency algorithm (`AppUsageService.vala`, reading GNOME Shell's `~/.local/share/gnome-shell/application_state` XML + runtime focus tracking with a 5s minimum focus threshold ignoring `Alt+Tab`, lazy exponential half-life decay, zero background timers) with **`Off`**, **`Auto-Fit Capacity`**, and **`Top 3 / 5 / 8 / 10 / 12 Most Used`** modes (`PinnedAccordionMode`), a dedicated **`»` / `«`** `PinnedExpanderDockItem`, per-icon `KeepVisible` override, and a **`Show Icon Tooltips`** switch (`TooltipsEnabled`), while keeping running/urgent apps visible at all times.
3. **Live Accordions While `Preferences`, `Help`, or `About` Windows Are Open (`FAT 6.14` `[  ]`)**:
   - Removes `PreferencesWindow`, `HelpWindow`, `FirstRunWindow`, and `AboutDialog` from `DockController.is_interaction_active ()` so both the Docklets Accordion and Pinned Apps Accordion expand and collapse live on the dock while the user adjusts settings in `Preferences`.
4. **MONLMIP Rank 1 (`WayPlank Always Left`), Full Profile & SR Flip-Flop Disk Persistence (`~/.config/wayplank/latch-state.ini`), SIL-4 Startup Validation & Centered `Show Trash` (`FAT 3.10, 7.8, 7.9` `[  ]`, `FAT 7.17` `[ko->ok]`)**:
   - Keeps `WayPlank Always Left` clickable (`sensitive = true`) in both Categorized and Free Mode: toggling it ON while `Categorize Items` is OFF promotes `Categorize Items` ON via a Monotonic Linear Mixed-Integer Program (`MONLMIP` of Rank 1), while toggling `Categorize Items` ON/OFF preserves `WayPlank Always Left`.
   - Persists all **43 `DockPreferences` properties** (`[DockPreferences]`) and **5 SR Flip-Flop states** (`[LatchState]`: `ReserveSpace` vs `HideDock`/`IconZoom`, `CategorizeItems`, `AnchorAlwaysLeft`) across WayPlank restarts and OS reboots in a single unified `~/.config/wayplank/latch-state.ini`, protected by a fork-isolated syntax probe (`probe_latch_file_in_subprocess`), per-key schema range validation, `.dockitem` corruption quarantine (`ItemFactory.load_elements` + `..` path-traversal rejection), a localized `"Load environment failed"` startup diagnostic dialog (`AbstractMain`), and an 8-scenario interactive test suite (`FAT/Test Files/Environment/Test environments.sh`).
   - Relocates `Show Trash` to the bottom-center of `Preferences -> Docklets` directly beneath the 7×2 docklets grid (`FAT 7.8`).
5. **Browser Auto-Translation of `wayplank_user_guide.html` (`switch_lang.sh` Compatible + China-Safe Fallback, `FAT 2.6` `[  ]`)**:
   - Detects the active WayPlank locale (`LANGUAGE` $\rightarrow$ `LC_ALL` $\rightarrow$ `LC_MESSAGES` $\rightarrow$ `LANG` $\rightarrow$ `setlocale`, 100% compatible with `"FAT/Test Files/Localization/switch_lang.sh"` without altering the OS desktop language) and translates `wayplank_user_guide.html` automatically in the browser via `Promise.any` across `translate.googleapis.com` + `api.mymemory.translated.net` + mainland China fallback `res.zvo.cn/translate/translate.js`, with a top-right `#wp-lang-select` switcher and `notranslate` protection on `<pre>`, `<code>`, and `.mermaid`.
6. **6-Layer Application Identity Engine (`#22` — [`Documentation/APPLICATION_IDENTITY_ENGINE.md`](../Documentation/APPLICATION_IDENTITY_ENGINE.md), `FAT 1.11, 2.12–2.15`)**:
   - Replaces legacy X11 string heuristics with a formal 6-Layer Deterministic Multi-Tier Application Identity Engine (`L1` Wayland Compositor Surface Identity $\rightarrow$ `L2` `/proc/<pid>` Kernel Process Inspection & Ancestor Climb $\rightarrow$ `L3` Container/Sandbox Unwrapping for Flatpak/Snap/AppImage/Firejail $\rightarrow$ `L4` Multi-Runtime Script/Interpreter Unwrapping for Python/Node/Java/.NET/Electron/Wine $\rightarrow$ `L5` Browser Multi-Profile, PWA & Custom Flag Isolation $\rightarrow$ `L6` Deterministic 13-Tier Scoring Matrix + Global Hungarian-Style Optimal Assignment Solver & Dynamic Runtime Re-Evaluation).
7. **KDE Plasma 6 Edit Mode & Multi-Compositor Show Desktop Coexistence (`#23` — Issue [#27](https://github.com/sergiomelas/WayPlank/issues/27) by `@polpodan`, `FAT 6.1` `[ko->ok]`)**:
   - Subscribes to `org.kde.PlasmaShell.editMode` on D-Bus in `KWinBridge.vala` so entering KDE Plasma 6 Edit Mode lets `showingDesktop=true` pass through undisturbed while temporarily hiding WayPlank via `fullscreen_window_intersects ()`, whereas `Super + D` outside Edit Mode continues to keep WayPlank visible (`showDesktop(false)` + `toggle_desktop ()`); extends the same `Super + D` vs `Main.overview` separation to GNOME Shell (`MutterBackend.vala`).
8. **Complete Remediation of All `v0.7.0` Audit Issues (`#19`–`#27` $\rightarrow$ `0 [ko]` Open Defects)**:
   - Remediates all 18 `[ko]` compositor test instances transferred from `v0.7.0` (`#20`–`#23`, marked `[ko->test]` in `FAT 0.7.1`) alongside `FAT 6.1` (`1 [ko->ok]` KDE #27) and `FAT 7.17` (`3 [ko->ok]`), `519/519` in-RAM localized strings across all 8 languages (`zh_CN`, `it`, `es`, `fr`, `ca`, `de`, `uk`, `en`), and a 9-point post-`91c94e9` stability hardening pass (`S1`–`S9`, including the `SurfaceCache` `GDestroyNotify` closure fix codified as `AI_RULES.md` Rule #14).
   - Updates [`FAT/2026-11-07 FAT 0.7.1.txt`](../FAT/2026-11-07%20FAT%200.7.1.txt) to **`335 [ok]` Consolidated Baseline + `4 [ko->ok]` Squashed (`FAT 6.1` KDE #27 & `FAT 7.17`) + `18 [ko->test]` Remediations + `18 [  ]` New `v0.7.1` Feature Points + `2 [NA]` + `0 [ko]` Open Defects**.

---

## 2. 🚀 New Features & Architectural Enhancements in V0.7.1 (`#16`, `#19`–`#21`)

### 2.1. First-Run Onboarding Popup (`FirstRunWindow` — `WayPlank Classic` vs `WayPlank Explorer`) & 100% Read-Only `~/.config/plank` Migration (`#20` | `FAT 1.9` `[  ]`)
- **Files Modified / Created**:
  - `lib/Widgets/FirstRunWindow.vala` (new)
  - `lib/DockController.vala` (`apply_onboarding_profile ()`, `~/.config/wayplank/<dock>/onboarding-done`)
  - `lib/Factories/ItemFactory.vala` (`migrate_legacy_plank_items ()`, `load_missing_items ()`)
  - `lib/Items/DefaultApplicationDockItemProvider.vala` (`reload_items ()`)
  - `lib/Factories/AbstractMain.vala`
- **Permanent Architectural Invariants**:
  1. **100% Read-Only Legacy Plank Migration**: `ItemFactory.migrate_legacy_plank_items ()` only reads and copies compatible `.dockitem` files from `~/.config/plank/<dock>/launchers` into `~/.config/wayplank/<dock>/launchers` (filtering out incompatible legacy X11 `docklet://cpumonitor`, `docklet://clippy`, `docklet://workspaces` and translating `docklet://applications` to `wayplank-folder-applications.dockitem`). It **NEVER** modifies, moves, or deletes anything inside `~/.config/plank`, preserving dual-session X11 Plank installations 100% intact.
  2. **Zero Deletion of User Items or Folders**: Neither **🏛️ WayPlank Classic** (`CategorizeItems = false`, `PinnedAccordionMode = PINNED_ACCORDION_OFF`, `AccordionDocklets = false`) nor **🚀 WayPlank Explorer** (`CategorizeItems = true`, `PinnedAccordionMode = PINNED_ACCORDION_AUTO_FIT`, `AccordionDocklets = true`, `ShowWindowCards = true`, plus non-destructive seeding of the 4 Smart Folder Drawers via `ensure_default_folders ()`) ever deletes any existing user `.dockitem` launcher or user folder (`FileDockItem`). Switching back to `Classic` only removes unmodified Explorer-seeded `wayplank-folder-{system,office,navigation}.dockitem` wrappers if they still point to `~/.config/wayplank/folders/`.
  3. **Headless / CI & Shutdown Safety**: Setting `WAYPLANK_NO_PROMPT=1`, `CI=1`, or `NONINTERACTIVE=1` bypasses `FirstRunWindow` automatically, and `FirstRunWindow.cancel_without_applying ()` ensures clean shutdowns (`SIGTERM` / `SIGWINCH`) do not prematurely mark `onboarding-done`.

### 2.2. Smart Usage-Adaptive Accordion for Pinned Apps & `Show Icon Tooltips` Switch (`#16` | Issue [#26](https://github.com/sergiomelas/WayPlank/issues/26) | `FAT 6.14` `[  ]`)
- **Files Modified / Created**:
  - `lib/Services/AppUsageService.vala` (new)
  - `lib/Items/PinnedExpanderDockItem.vala` (new)
  - `lib/Items/DefaultApplicationDockItemProvider.vala`
  - `lib/Items/DockItemPreferences.vala` (`KeepVisible`)
  - `lib/Items/ApplicationDockItem.vala` (`Always Keep Visible in Accordion`)
  - `lib/Widgets/DockWindow.vala` & `lib/DockController.vala`
  - `lib/DockPreferences.vala`, `data/ui/preferences.ui`, `lib/Widgets/PreferencesWindow.vala`
- **Permanent Architectural Invariants**:
  1. **GNOME `shell-app-usage.c` Frecency Engine (`AppUsageService.vala`)**: Tracks active window focus durations with a **5-second minimum focus threshold** (ignoring transient `Alt+Tab` sweeps), applies lazy exponential half-life decay (14 days, `HALF_LIFE_SECONDS = 14 * 86400`) and `SCORE_MAX = 100.0` rescaling along with read-only import of `~/.local/share/gnome-shell/application_state`, uses `0.0` clean cold-start scores with left-to-right positional tie-breaking, and uses **zero periodic background timers**.
  2. **Accordion Modes, Half-Slot (`0.5`) Expander Geometry & Trailing Separator Suppression**: Supports `Off` (`PINNED_ACCORDION_OFF = 0`), `Auto-Fit Capacity` (`PINNED_ACCORDION_AUTO_FIT = 1`, dynamically computing the maximum non-overflowing pinned budget from `PositionManager.get_preferred_slot_capacity ()`), and `Top Most Used` (`PINNED_ACCORDION_TOP_N = 2` + `PinnedAccordionCount` numeric SpinButton `1..20`, default `6`). Running or urgent pinned apps and items with `KeepVisible=true` are **never** collapsed; left-to-right user pin order is strictly preserved; hovering or clicking the `›` / `«` `PinnedExpanderDockItem` expands/collapses the shelf using the shared `AccordionDelay` timer. `PinnedExpanderDockItem` occupies **half an icon slot (`0.5` slot width, matching `SeparatorDockItem`)** in `PositionManager.vala` and `DefaultApplicationDockItemProvider.compute_hidden_pinned_apps ()`, and automatically suppresses any immediately following `SeparatorDockItem` (`|`) in `update_visible_elements ()`.
  3. **Live Accordions While `PreferencesWindow` Is Open**: `PreferencesWindow`, `HelpWindow`, `FirstRunWindow`, and `AboutDialog` are excluded from `DockController.is_interaction_active ()` so users can test both `Pinned Apps Accordion` and `Running Apps Accordion` live on the dock while `Preferences` is open.
  4. **`Show Icon Tooltips` Switch (`TooltipsEnabled`)**: Exposed in `Preferences -> Behaviour -> Item Management` (`2×4` grid) and immediately hides any active `HoverWindow` when toggled OFF.

### 2.3. `MONLMIP Rank 1` (`WayPlank Always Left`), Full Profile & SR Flip-Flop Disk Persistence (`~/.config/wayplank/latch-state.ini`), SIL-4 Startup Validation & Centered `Show Trash` (`#19` | `FAT 3.10, 7.8, 7.9` `[  ]`, `FAT 7.17` `[ko->ok]`)
- **Files Modified**:
  - `lib/DockPreferences.vala`
  - `lib/Services/Settings.vala`
  - `lib/Factories/ItemFactory.vala`, `lib/DockController.vala`, `lib/Factories/AbstractMain.vala`
  - `lib/Widgets/PreferencesWindow.vala` & `data/ui/preferences.ui`
- **Permanent Architectural Invariants**:
  1. **`MONLMIP Rank 1` (`WayPlank Always Left`)**: `WayPlank Always Left` (`anchor-always-left`) is never greyed out (`sensitive = true` in both Categorized and Free Mode). Enabling `AnchorAlwaysLeft` when `CategorizeItems == false` executes the Rank-1 Monotonic Linear Mixed-Integer Program transition $C' = \min(1, C + \max(0, A' - A))$, automatically promoting `CategorizeItems = true`. Toggling `CategorizeItems` ON/OFF preserves `AnchorAlwaysLeft`.
  2. **Unified Full-Profile & SR Flip-Flop Reboot Persistence (`~/.config/wayplank/latch-state.ini`) & SIL-4 Startup Validation (`FAT 7.17` `[ko->ok]`)**: `DockPreferences` persists all **43 dock preferences** under `[DockPreferences]` alongside all **5 SR Flip-Flop keys** (`HasSavedPreReserveState`, `SavedHideModeBeforeReserve`, `SavedZoomBeforeReserve`, `HasSavedAnchorAlwaysLeft`, `SavedAnchorAlwaysLeft`) under `[LatchState]` in `~/.config/wayplank/latch-state.ini` via `FileUtils.set_contents` (automatically migrating and removing legacy `<dock>/latch-state.ini`). On startup, `probe_latch_file_in_subprocess ()` validates `KeyFile` syntax inside an isolated child process before parsing, validates every key against schema ranges and path/theme/monitor invariants, quarantines corrupted or path-traversal `.dockitem` files in `ItemFactory.load_elements ()`, displays a centered `"Load environment failed"` dialog listing defaulted settings and discarded `.dockitem` files, and includes an 8-scenario test suite in `FAT/Test Files/Environment/Test environments.sh` (`Corrupted`, `Partial`, `OutOfRange`, `InvalidTypesAndPaths`, `CorruptedDockItems`, `ValidCustomProfile`, `EmptyProfile`, `Restore`).
  3. **Centered `Show Trash` (`FAT 7.8`)**: `Show Trash` is centered directly beneath the 7×2 docklets grid in `Preferences -> Docklets`.

### 2.4. Browser Auto-Translation of `wayplank_user_guide.html` (`switch_lang.sh` Compatible + China-Safe Fallback, `#21` | `FAT 2.6` `[  ]`)
- **Files Modified**:
  - `lib/Factories/AbstractMain.vala` (`show_guide ()`)
- **Permanent Architectural Invariants**:
  1. **`switch_lang.sh` & `wayplank_i18n_init ()` Locale Detection Parity**: `show_guide ()` resolves the active locale using `LANGUAGE` $\rightarrow$ `LC_ALL` $\rightarrow$ `LC_MESSAGES` $\rightarrow$ `LANG` $\rightarrow$ `Intl.setlocale (LocaleCategory.MESSAGES, null)` (stripping `:`, `@`, and `.encoding`), supporting both embedded catalogs (`zh-CN`, `it`, `es`, `fr`, `ca`, `de`, `uk`, `en`) and arbitrary ISO locales passed to `"FAT/Test Files/Localization/switch_lang.sh"` (e.g. `ja`, `zh-TW`, `pt`, `ko`) by dynamically injecting a `<select>` `<option>` when needed.
  2. **Zero-Key Multi-Provider Translation & Code/Mermaid Protection**: Uses `Promise.any` racing `translate.googleapis.com/translate_a/single` and `api.mymemory.translated.net/get` with automatic fallback to `https://res.zvo.cn/translate/translate.js` (`client.edge`) for mainland China, pre-computes original English heading slugs (`data-orig-slug`) so Markdown TOC `#anchor` links work after headings are translated, marks `<pre>`, `<code>`, and `.mermaid` as `translate="no" class="notranslate"`, and injects a floating top-right `#wp-lang-select` selector.

---

## 3. 🟢 Category 1: Pure Core / UI Consolidations (`#1`–`#10` & `#17` — `HAL-Neutral`)

1. **`#1` — CLI `-V` Verbose Short Flag Collision (`src/Main.vala` | Issue `#24` part 1 | `FAT 13.8`)**:
   - Removed `|| arg == "-V"` from `src/Main.vala:35` so `-V` routes cleanly to `AbstractMain` `--verbose` while `-v` / `--version` prints the version.
2. **`#2` — Single-Source-of-Truth Global Constants, `VERSION`, `.dockitem` Metadata & Monolithic `GResource` Stock Themes (Issue `#24` part 2 | `FAT 12.1, 13.8`)**:
   - Centralized `MIN/MAX/DEFAULT_EFFECT_DURATION = 300/1500/600` (fixing `PoofWindow` `1500 ms` clamp), `ACCORDION_DELAY` bounds, canonical root `VERSION` (`0.7.1`), `DockItemPreferences` (`CustomIcon`, `BrowserProfile`, `KeepVisible`), and embedded all 5 stock `.theme` files in RAM (`GResource`, `350 ms` `DEFAULT_HIDE_TIME`, zero `/usr/share/wayplank/themes/` in `.deb`/`.rpm`).
3. **`#3` — Accordion Tooltip Arrow Direction under `DockletsOnRight` (`lib/Widgets/DockWindow.vala` | Issue `#21` part 1 | `FAT 5.6`)**:
   - Flipped `arrow_expand` / `arrow_collapse` when `DockletsOnRight` is active.
4. **`#4` — Diagnostic Inspector Shortcut (`Ctrl + Alt + Shift + Right Click`) + Enhanced Debug Output (`lib/Widgets/DockWindow.vala` | Issue `#21` part 2)**:
   - Routed single `Ctrl + Right Click` to global dock menu and 3-modifier `Ctrl + Alt + Shift + Right Click` on items to `Developer _Tools` submenu (`Inspect Window Matching (CLI -d)` + live Frecency telemetry).
5. **`#5` — `MPRIS` Docklet Scroll Wheel, Middle-Click Parity, Rising-Edge Latch & Multi-Player Radio Selector (`lib/Items/MprisDockItem.vala` | Issue `#21` part 3 | `FAT 6.16, 7.11`)**:
   - Fixed `Play`/`Pause` state-icon polarity, single-register rising-edge `Playing` latch, context-menu radio player selector, Middle-Click `PlayPause`, and mouse-wheel track skipping.
6. **`#6` — Folder Drawers `ShowRunningIndicators` Toggle + Live Redraw (`FileDockItem.vala`, `FolderMenuWindow.vala`, `DefaultApplicationDockItemProvider.vala` | Issue `#24` part 3 | `FAT 1.11`)**:
   - Wired `ShowRunningIndicators` into `FileDockItem.update_indicator ()`, `FolderMenuWindow`, and live preference notifications.
7. **`#7` — `ReverseRoundness` 40px Skirt Margin in Redline Capacity Slider (`lib/PositionManager.vala` | Issue `#24` part 4 | `FAT 10.8`)**:
   - Added `2.0 * get_reverse_roundness_padding (ReverseRoundness, BottomRoundness)` to `get_max_screen_fit_icon_size ()` and `get_preferred_slot_capacity ()`.
8. **`#8` — Restore "Recent Files" Jump List Submenu (`lib/Services/RecentFilesService.vala`, `ApplicationDockItem.vala`, `FolderMenuWindow.vala` | Issue `#19` | `FAT 12.2`)**:
   - Restored localized *"Recent Files"* submenu via `Gtk.RecentManager` with Flatpak/Snap/`env` binary unwrapping and `"Clear Recent Files"` action.
9. **`#9` — Custom Image File Icons on Folders (`IconChooserDialog.vala`, `DrawingService.vala`, `FileDockItem.vala` | Issue `#25` | `FAT 1.10`)**:
   - Preserved `file://` URIs in `IconChooserDialog`, supported `/` paths in `DrawingService`, and persisted `CustomIcon` in `DockItemPreferences` with localized `Icon[...]` key clearing on reset.
10. **`#10` — Purge Obsolete Embedded `doc/report.md` from Binary (`data/plank.gresource.xml`, `AbstractMain.vala`)**:
    - Removed `doc/report.md` (`-110 KB`) from `GResource` while keeping `Documentation/wayplank_x11_to_wayland_report_en.md` in Git.
11. **`#17` — Community Reporter Verification (`#16`, `#18`) & Chinese Fork Scouting (`@IFtiger-hu-hub` `c981e42`)**:
    - Cherry-picked compositor-safe wrapper script `16 KB` limit + `.sh`/`.py`/`.run`/`.bin` stem extraction + `"studio"`/`"ide"`/`"browser"`/`"player"` stopwords in `ApplicationIdentity.vala` and strong-ref `ClickedItem` guard in `DockWindow.vala`.

---

## 4. 🟡 Category 2: Core HAL-Consumer Remediations (`#11`–`#14` — `Zero HAL Driver Modification`, Marked `[ko->test]` in `FAT 0.7.1`)

1. **`#11` — Chrome `.sh` Profile Wrappers, Multi-Profile PWAs & `.dockitem` `BrowserProfile` Scoring (Issue `#20` | `FAT 1.11` `[ko->test]`)**:
   - **Files Modified (`0` HAL Files Touched)**: `lib/Services/ApplicationIdentity.vala`, `lib/Services/ApplicationDiscovery.vala`, `lib/Services/WindowManager.vala`, `lib/Items/ApplicationDockItem.vala`, `lib/Items/DockItemPreferences.vala`.
   - **Invariants**:
     - Extracts `detected_browser_profile` (`--profile-directory=`, `--user-data-dir=`, `-P`, `--profile=`, expanding `$HOME`/`~/` in `.sh` scripts) without losing it when `pwa_id != ""`.
     - Enforces **strict `AND` conjunction** of all differentiating wrapper switches (`--user-agent`, `--incognito`, `--tor`, `--guest`, `--user-data-dir`, `--profile-directory`, `--class`) on specialized browser launchers (`winchrome-syensqo.sh`, `chrome-private.sh`), never matching generic webpage titles (allowing `(Incognito)` suffix for shared-process Chrome incognito windows).
     - Passes `.dockitem` `BrowserProfile` metadata into `match_score ()` (`score = 124` / `118`, `0` on mismatched profile) and auto-populates `Prefs.BrowserProfile` from `identity.detected_browser_profile` when empty.
2. **`#12` — Labwc Do Not Disturb Toggle & Cross-Desktop Docklet Settings Priority (Issue `#23` | `FAT 6.12, 6.18` `[ko->test]`)**:
   - **Files Modified (`0` HAL Files Touched)**: `lib/Services/System.vala`, `lib/Items/DoNotDisturbDockItem.vala`, `lib/Items/BatteryDockItem.vala`, `lib/Items/BrightnessDockItem.vala`, `lib/Items/CpuDockItem.vala`, `lib/Items/NetworkDockItem.vala`, `lib/Items/VolumeDockItem.vala`, `lib/Widgets/CalendarWindow.vala`.
   - **Invariants**:
     - Guards `org.gnome.desktop.notifications` `show-banners` write in `DoNotDisturbDockItem.inhibit ()` / `uninhibit ()` with `environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)` so Labwc reaches `dunstctl set-paused` and `swaync-client` (`FAT 6.18`).
     - Centralizes `System.launch_desktop_utility (kde_cmds, gnome_cmds, generic_cmds)` checking `XDG_CURRENT_DESKTOP` once across all 7 docklets (`FAT 6.12`).
3. **`#13` — `Shift + Left Click` Window Cycle & Overflow Scroll Exemption (Issue `#21` parts 4 & 5 | `FAT 7.11, 10.4` `[ko->test]`)**:
   - **Files Modified (`0` HAL Files Touched)**: `lib/Widgets/DockWindow.vala`, `lib/Items/ApplicationDockItem.vala`.
   - **Invariants**:
     - Gates `window_cards.show_for_item ()` on `!has_ctrl && !has_shift` and handles `Gdk.ModifierType.SHIFT_MASK` in `ApplicationDockItem.on_clicked ()` via `WindowManager.cycle_window (Launcher, true, out uuid)` (`FAT 7.11`).
     - Centralizes `item_captures_scroll (DockItem? item)` returning `true` for `VolumeDockItem`, `BrightnessDockItem`, `MprisDockItem`, and `ApplicationDockItem` with `window_count_for_app (Launcher) > 1` so scrolling over those icons adjusts their parameter instead of scrolling the overflow dock (`FAT 10.4`).
4. **`#14` — `WindowCardsWindow` Middle-Click to Close Single Window (Issue `#21` part 6 | `FAT 12.4` `[ko->test]`)**:
   - **File Modified (`0` HAL Files Touched)**: `lib/Widgets/WindowCardsWindow.vala`.
   - **Invariant**: Shares the single-card close block (`WindowControl.queue_command (win.Id, "close")`, remove `eb`, `close_cards ()` if empty else `update_position ()`) across both `(event.button == Gdk.BUTTON_PRIMARY && is_close_click)` and `event.button == Gdk.BUTTON_MIDDLE`.
5. **`#22` — 6-Layer Deterministic Application Identity Engine ([`Documentation/APPLICATION_IDENTITY_ENGINE.md`](../Documentation/APPLICATION_IDENTITY_ENGINE.md) | `FAT 1.11, 2.12–2.15`)**:
   - **Files Modified (`0` HAL Files Touched)**: `lib/Services/ApplicationIdentity.vala`, `lib/Services/ApplicationDiscovery.vala`, `lib/Services/WindowManager.vala`.
   - **Invariants**:
     - Implements the 10-iteration verified 6-Layer Architecture (`L1` Compositor Surface Identity $\rightarrow$ `L2` `/proc/<pid>` Kernel Process & 5-Level Ancestor Climb $\rightarrow$ `L3` Flatpak `.flatpak-info` / Snap / AppImage `ARGV0` / Bubblewrap / Firejail Unwrapping $\rightarrow$ `L4` Python/Node/Java/.NET/Electron/Wine/Shell Unwrapping $\rightarrow$ `L5` Browser Multi-Profile, PWA & Differentiating Flag Conjunction $\rightarrow$ `L6` 13-Tier Scoring Matrix `0..135`).
     - Replaces greedy per-item claiming with a Global Optimal Assignment Solver (`score * 100 + specificity_bonus`, with `specificity_bonus = 25` for `has_custom_flags` and `15` for `detected_browser_profile`), dynamic runtime re-evaluation when late `app_id`/titles or `/proc` cmdlines settle, a 500ms transient helper-process suppression gate (`process_has_own_toplevel_surface ()`), and event-driven multi-profile Chrome/Chromium isolation via `com.canonical.dbusmenu` (`list_all_chrome_menu_paths ()` sorting `Gee.ArrayList<string>` directly without boxed-key `HashMap<uint64?, string>` `NULL` returns, paired with `Chrome:<ProfileName>` tooltips and defensive `!= null` guards across `ApplicationDockItem`, `DockWindow`, and `HoverWindow`).

---

## 5. 🔴 Category 3: True HAL Modifications (`#15`, `#23` — Marked `[ko->test]` / `[ko->ok]` in `FAT 0.7.1`)

1. **`#15` — Multi-Compositor HAL Signals & Preview Thumbnail Cache (Issue `#22` | `FAT 2.7, 2.9, 12.6` `[ko->test]`)**:
   - **GNOME Mutter (`lib/Services/MutterBackend.vala` — `FAT 2.7`)**:
     - Emits `this._notifyWindowsChanged ()` when normal app windows (`=== 'other'`) fire `window-demands-attention` / `window-marked-urgent` or per-window `notify::demands-attention` / `notify::urgent` in `_connectWindow`.
     - Tracks monotonic `this._minSeq` on `notify::minimized` for `MinimizedSequence` and parses `minimizedSequence` in `MutterBackend.parse_window_infos ()`.
   - **KDE KWin (`lib/Services/KWinBridge.vala` — `FAT 2.9`)**:
     - Connects `window.captionChanged` (`+3` lines vs `91c94e9`) to the ≥50ms debounced D-Bus notifier inside the KWin ECMAScript bridge so dynamic browser/terminal tab titles update live without D-Bus floods (Pitfall #8).
   - **Thumbnail Service (`lib/Services/KWinThumbnailService.vala` — `FAT 12.6`)**:
     - Guards the KWin `ScreenShot2` branch with `else if (WindowControl.is_kwin ())` (returning `null` cleanly on Labwc), replaces `stderr.printf` spam with `debug`, refreshes stale cached thumbnails (`2.5s` TTL) asynchronously on re-hover, evicts closed `win_id`s via `prune_closed_windows ()`, and enforces `buffer[i + 3] = 255` BGRA opacity (Pitfall #3).
2. **`#23` — KDE Plasma 6 Edit Mode & Multi-Compositor Show Desktop Coexistence (Issue [#27](https://github.com/sergiomelas/WayPlank/issues/27) by `@polpodan` | `FAT 6.1` `[ko->ok]` on KDE)**:
   - **KDE KWin (`lib/Services/KWinBridge.vala` — `FAT 6.1` `[ko->ok]`)**:
     - Subscribes to `org.freedesktop.DBus.Properties.PropertiesChanged` on `org.kde.plasmashell` (`/PlasmaShell`, `org.kde.PlasmaShell`) to track `editMode` (`plasma_edit_mode_active`) with synchronous fallback `query_plasma_edit_mode ()`.
     - When `showingDesktop == true` and `editMode == true`, lets `showingDesktop` pass through without calling `showDesktop(false)` or `toggle_desktop ()`, sets `desktop_show_desktop_active = true`, and returns `true` from `fullscreen_window_intersects ()` so `HideManager` sets `FullscreenInhibit = true` and hides WayPlank during KDE Plasma Edit Mode; keeps `Super + D` interception active when `editMode == false`.
   - **GNOME Mutter (`lib/Services/MutterBackend.vala` — `FAT 6.1`)**:
     - Connects `global.workspace_manager.connect('showing-desktop-changed')`: when `ws.showing_desktop === true` outside `Main.overview.visible`, calls `global.workspace_manager.unshow_desktop()` and `this.ToggleDesktop()` so `Super + D` keeps WayPlank visible while `Main.overview` passes through.

---

## 6. 🛡️ Post-`91c94e9` Stability Hardening Pass (`S1`–`S9`) & Iterative "Black-Hole" Deep Debugging (`#18`)

- **`S1` — Packaging & Upgrade Migration (`BuildDeb.sh`, `BuildRpm.sh`, `BuildBin.sh`)**:
  - Restored full `hicolor` SVG icon tree (`16/22/24/32/48/64/128/scalable`) for both `wayplank.svg` and `plank.svg` in `.deb` & `.rpm`; added `Obsoletes: plank < 0.7.1` and weak `Recommends: (spectacle or flameshot or xfce4-screenshooter)` in `.rpm`; guarded `glib-compile-schemas` on read-only `/usr/share/glib-2.0/schemas`.
- **`S2` — Signal-Safe Shutdown, `dconf` Flush & `LC_NUMERIC` Guard (`src/Main.vala`, `AbstractMain.vala`, `DockController.vala`)**:
  - Replaced async-signal-unsafe `Posix.signal` with `GLib.Unix.signal_add` (`INT`/`TERM`/`HUP`), added `GLib.Settings.sync ()` on shutdown, re-enforced `Intl.setlocale (LocaleCategory.NUMERIC, "C")` **after** `Gtk.init ()` (preventing comma decimals in `WeatherDockItem` URLs), and guarded `serialize_item_positions ()`.
- **`S3` — Deterministic Docklet Teardown & Zero Timer/D-Bus Leaks (`DockElement`, `DockItem`, `DockContainer`, `DefaultApplicationDockItemProvider`, All 16 Docklets)**:
  - Wired idempotent `cleanup ()` on item deletion/replacement/deduplication across all 16 docklets so removed docklets cancel all `GLib.Timeout` sources and D-Bus subscriptions immediately.
- **`S4` — Preferences, Stock Themes & `RecentFilesService` Hardening (`Preferences.vala`, `ThemeManager.vala`, `RecentFilesService.vala`, `FileDockItem.vala`)**:
  - Fixed `ThemeManager` stock theme fallback (`Plank.Theme.is_valid_name`), preserved `Preferences` write serialization & atomic replace, fixed `FileDockItem` custom icon reset/override (`Icon[...]` localized keys + live index refresh), and preserved Flatpak/Snap/`env` launcher matching in `RecentFilesService`.
- **`S5` — Surface Cache, Closure `GDestroyNotify` Fix (`AI_RULES.md` Rule #14), Renderer & Null-Safety (`SurfaceCache.vala`, `PositionManager.vala`, `DockWindow.vala`, `DragManager.vala`, `HideManager.vala`)**:
  - Fixed the 5-minute periodic `SIGSEGV` in `SurfaceCache` (restored zero-closure instance timer without `Block3Data` UAF, codified as `AI_RULES.md` Rule #14), replaced raw `weak` pointers (`spring_hover_target`, `tracked_monitor`) with strong lifecycle-cleared references, guarded `SurfaceCache` against `null` surface returns inside `cache_mutex`, guarded `controller.renderer != null && controller.renderer.theme != null`, and cancelled `long_press_timer_id` on dock leave/destroy.
- **`S6` — Modal Dialogs & Async Worker Lifecycles (`PreferencesWindow.vala`, `IconChooserDialog.vala`, `WeatherCityDialog.vala`, `SessionWindow.vala`, `WeatherWindow.vala`)**:
  - Removed artificial `transient_for` (`parent = null` per Rule `§5.2`), prevented `keep_above` file-chooser occlusion in `IconChooserDialog`, guarded `is_destroyed` across nested `.run ()` loops, deduplicated per-item `IconChooserDialog` / `WeatherCityDialog`, and made `WeatherCityDialog` geocoding non-blocking via `GLib.WeakRef`.
- **`S7` — Minimal Surgical KDE KWin Caption Signal (`lib/Services/KWinBridge.vala` — `+3` lines only vs `91c94e9`)**:
  - Kept `KWinBridge.vala` 100% identical to qualified `91c94e9` except for connecting `window.captionChanged` (`+3` lines, `FAT 2.9`) to the 50ms debounced notifier (`toggleDesktop` and virtual-desktop logic untouched).
- **`S8` — Minimal Pipe & Thumbnail Capture Safety (`lib/Services/KWinThumbnailService.vala`)**:
  - Added Labwc guard (`else if (WindowControl.is_kwin ())`), converted `stderr.printf` to `debug`, kept `/dev/shm/wayplank_thumb_%s.png` with `finally` unlink and KWin pipe read loop with `finally` FD close, added 2.5s cache TTL + closed-window pruning, and preserved `buffer[i + 3] = 255` (Rule `§5.3`).
- **`S9` — Event-Driven Brightness Subsystem & Popup CSS/Timer Hygiene (`BrightnessControl.vala`, `FolderMenuWindow.vala`, `WindowCardsWindow.vala`)**:
  - Replaced 500ms brightness polling with `FileMonitor` + D-Bus signals; fixed `Gtk.CssProvider` leak and position timer cleanup in `FolderMenuWindow` / `WindowCardsWindow` while keeping `HoverWindow.vala` at `0` lines diff vs `91c94e9`.

---

## 7. 🧪 Public Beta 2 Factory Acceptance Testing Status (`FAT/2026-11-07 FAT 0.7.1.txt`)

- **377 Total Qualification Test Points Defined (`335 [ok]` Consolidated Baseline, `4 [ko->ok]` Squashed in `FAT 6.1` KDE #27 & `FAT 7.17`, `18 [ko->test]` Remediations Ready for Re-Test, `18 [  ]` New `v0.7.1` Feature Points, `2 [NA]`, `0 [ko]` Open Defects)**:
  - **Session 1 (GNOME Shell / Mutter)**: `126` tests | `113 [ok]` | `1 [ko->ok]` (`7.17`) | `6 [ko->test]` (`1.11, 2.7, 6.12, 7.11, 10.4, 12.4`) | `6 [  ]` (`1.9, 2.6, 3.10, 6.14, 7.8, 7.9`) | `0 [NA]` | `0 [ko]`
  - **Session 2 (KDE Plasma 6 / KWin)**: `126` tests | `112 [ok]` | `2 [ko->ok]` (`6.1, 7.17`) | `6 [ko->test]` (`1.11, 2.9, 7.11, 10.4, 12.4, 12.6`) | `6 [  ]` (`1.9, 2.6, 3.10, 6.14, 7.8, 7.9`) | `0 [NA]` | `0 [ko]`
  - **Session 3 (Labwc / wlroots)**: `125` tests | `110 [ok]` | `1 [ko->ok]` (`7.17`) | `6 [ko->test]` (`1.11, 6.12, 6.18, 7.11, 10.4, 12.4`) | `6 [  ]` (`1.9, 2.6, 3.10, 6.14, 7.8, 7.9`) | `2 [NA]` (`2.7, 10.6`) | `0 [ko]`
- **Monolithic Embedded Localization (`519 / 519` Strings — 100%)**:
  - All 7 embedded `.mo` catalogs (`zh_CN`, `it`, `es`, `fr`, `ca`, `de`, `uk`) + `en` native fallback updated to `519 / 519` translated messages (`0 fuzzy, 0 untranslated`).
