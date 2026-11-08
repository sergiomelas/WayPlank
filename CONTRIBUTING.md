# 🤝 Contributing to WayPlank

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026

First off, thank you for considering contributing to WayPlank! 🎉 

WayPlank is a high-performance, standalone, monolithic dock designed natively for the Wayland desktop ecosystem. With hundreds of community users, thousands of lifetime downloads, and active contributors across the world, community feedback and contributions are what make WayPlank thrive.

Whether you are reporting a bug, contributing translations, improving themes, testing on a new compositor, or submitting code, this guide will help you get started quickly.

---

## 📌 Table of Contents

1. [Current Project Status & Roadmap](#-current-project-status--roadmap)
2. [Active Community Tracks, Issues & Discussions Status](#-active-community-tracks-issues--discussions-status)
3. [How to Contribute](#-how-to-contribute)
   - [Track 1: Localization & Translations (i18n)](#track-1-localization--translations-i18n)
   - [Track 2: Reporting Bugs & Feature Requests](#track-2-reporting-bugs--feature-requests)
   - [Track 3: Testing on Other Compositors](#track-3-testing-on-other-compositors)
   - [Track 4: Themes & Visual Customization](#track-4-themes--visual-customization)
   - [Track 5: Distribution Packaging](#track-5-distribution-packaging)
4. [Development & Coding Standards](#-development--coding-standards)
   - [The HAL Rule (Compositor Independence)](#the-hal-rule-compositor-independence)
   - [Building Locally](#building-locally)
   - [Testing & Quality Assurance (FAT)](#testing--quality-assurance-fat)
5. [Submitting Pull Requests (PRs)](#-submitting-pull-requests-prs)

---

## 🗺️ Current Project Status & Roadmap

* **Current Public Beta Release**: `v0.7.1` (**Public Beta 2 — In 10-Day Live Burn-In**, [`FAT/2026-11-07 FAT 0.7.1.txt`](FAT/2026-11-07%20FAT%200.7.1.txt); `v0.7.0` Public Beta 1 concluded & frozen at `95.2% PASS`).
* **Upcoming Public Beta Roadmap (`v0.7.x`)**: **`v0.7.1`** (Public Beta 2: First-Run Onboarding `Classic` vs `Explorer`, 100% read-only `~/.config/plank` migration, Smart Usage-Adaptive Accordion [#26](https://github.com/sergiomelas/WayPlank/issues/26), browser auto-translated User Guide, `MONLMIP Rank 1`, and complete remediation of `#19`–`#25`), followed by **`v0.7.2+`** (dedicated physical `hal/` extraction & `WinPlank` Windows foundation — see [Documentation/HAL_ARCHITECTURE.md](Documentation/HAL_ARCHITECTURE.md)) and iterative `v0.7.x` Public Beta releases remaining open for user feature requests, new translations, and refinements until the community signals readiness for the `v0.8.x` Release Candidate freeze, up to **December 31, 2026**.
* **Completed Foundation Release**: `v0.6.2.3` (Official Closure of the Alpha & Pre-Beta Era).
* **Tier 1 Supported Compositors**:
  - **KDE Plasma (KWin 6.x)**: Full layer-shell integration, D-Bus scripting bridge, live Cairo preview thumbnails.
  - **GNOME Shell (Mutter 46/47/48)**: Dedicated Mutter extension bridge, live window previews, window Dodge/Intellihide.
  - **Labwc (wlroots)**: Pure `zwlr_foreign_toplevel_manager_v1` protocol tracking, honest UI matrix, Dodge.

---

## 🚀 Active Community Tracks, Issues & Discussions Status

### 🌟 Community Roll of Honor & Heartfelt Thanks

A warm, heartfelt thank you to every contributor, translator, tester, and bug reporter who has helped shape WayPlank across KDE Plasma, GNOME Shell, and Labwc:

* **[@IFtiger-hu-hub](https://github.com/IFtiger-hu-hub) — 史有虎 (IFtiger-hu)**: Author of the WayPlank community fork, contributor of native RPM packaging (`BuildRpm.sh`), overflow smooth scrolling, launcher deduplication, Flatpak & matcher hardening ([PR #15](https://github.com/sergiomelas/WayPlank/pull/15)), and Simplified Chinese (`zh_CN`) localization.
* **[@reni001](https://github.com/reni001) — Renate Schwiedernoch**: Author and maintainer of the German (`de`) localization catalog ([#7](https://github.com/sergiomelas/WayPlank/issues/7)).
* **[@Gabenoh](https://github.com/Gabenoh) — Michailo Buchko**: Author of the Ukrainian (`uk`) localization catalog ([#8](https://github.com/sergiomelas/WayPlank/issues/8)), minimalist docklets / `SystemMenuAccess` ergonomics proposal ([Discussion #3](https://github.com/sergiomelas/WayPlank/discussions/3)), and layer-shell click passthrough testing ([#12](https://github.com/sergiomelas/WayPlank/issues/12)).
* **[@tcliuqiang](https://github.com/tcliuqiang)**: Extensive multi-compositor bug hunting and feature proposals — Cold-start HiDPI 4K@1.5x fractional scaling ([#5](https://github.com/sergiomelas/WayPlank/issues/5)), Reserve Screen Space / Panel Mode & SR Flip-Flop ([#9](https://github.com/sergiomelas/WayPlank/issues/9), [#17](https://github.com/sergiomelas/WayPlank/issues/17)), Fullscreen Auto-Hide ([#10](https://github.com/sergiomelas/WayPlank/issues/10)), Show Desktop persistence ([#13](https://github.com/sergiomelas/WayPlank/issues/13)), CLI/QEMU/AppImage discovery ([#14](https://github.com/sergiomelas/WayPlank/issues/14), [#16](https://github.com/sergiomelas/WayPlank/issues/16)), and screen lock / DPMS self-healing ([#18](https://github.com/sergiomelas/WayPlank/issues/18)).
* **[@winteriscariot](https://github.com/winteriscariot)**: Multi-monitor primary display resolution ([#1](https://github.com/sergiomelas/WayPlank/issues/1)) and Application Identity / Chromium PWA isolation testing ([#6](https://github.com/sergiomelas/WayPlank/issues/6)).
* **[@Jolmas](https://github.com/Jolmas)**: Labwc / wlroots multi-workspace dock visibility reporting and verification ([#11](https://github.com/sergiomelas/WayPlank/issues/11)).
* **[@polpodan](https://github.com/polpodan)**: KDE Plasma 6 Desktop & Panel Edit Mode interaction reporting ([#27](https://github.com/sergiomelas/WayPlank/issues/27)).

---

### 📋 Live Issue & Regression Tracker Summary

We actively track all community suggestions, bug reports, post-release audits, and translations on [GitHub Issues](https://github.com/sergiomelas/WayPlank/issues) and [GitHub Discussions](https://github.com/sergiomelas/WayPlank/discussions):

> **Current Status (`2026-11-08` `v0.7.1` Public Beta 2 Burn-In Sync):** **`5` In Active `v0.7.1` Qualification (`4` Remediated Locally `[ko->test]` `#20` – `#23` + `1` Feature Proposal `#26` Implemented `[  ]` in `v0.7.1`)** • **`20` Closed & Qualified Issues, PRs & Discussions (`14` Closed on GitHub `#1`, `#5` – `#15`, `#17`, `Discussion #3` + `6` Qualified `[ok]` / `[ko->ok]` Locally in `v0.7.1` `#16`, `#18`, `#19`, `#24`, `#25`, `#27` pending release push)**

<details>

<summary><b>🔴 Open & In-Qualification GitHub Issues & Proposals (5 in v0.7.1 Live Burn-In: #20–#23, #26 All Remediated/Implemented Locally) — Click to expand</b></summary>

| Issue | Author | Title | Area | Status | Technical Summary & Target Milestone |
|:---:|:---:|---|---|:---:|---|
| **[#20](https://github.com/sergiomelas/WayPlank/issues/20)** | [@sergiomelas](https://github.com/sergiomelas) | **[Bug] Normal Google Chrome Windows Misassigned to Specialized `.sh` Profile Wrapper (FAT 1.11)** | Core / Matching | `[Remediated Locally]` (`FAT 1.11 [ko->test]`) | Remediated in `v0.7.1` (FAT Point `1.11` `[ko->test]`): full 6-Layer Application Identity Engine (`ApplicationIdentity.vala`, `ApplicationDiscovery.vala`) with strict `AND` conjunction across differentiating `.sh` wrapper flags (`--user-agent`, `--incognito`, `--user-data-dir`, `--profile-directory`), multi-profile PWA `119 -> 120/0` resolution, and `.dockitem` `BrowserProfile` metadata scoring. |
| **[#21](https://github.com/sergiomelas/WayPlank/issues/21)** | [@sergiomelas](https://github.com/sergiomelas) | **[Regression] Mouse, Scroll & Modifier Shortcut Regressions on Dock Icons & Preview Cards (FAT 5.6, 7.11, 10.4, 12.4)** | Core UI / Gestures | `[Remediated Locally]` (`FAT 7.11, 10.4, 12.4 [ko->test]`) | Remediated in `v0.7.1`: `FAT 5.6` graduated `[ok]`, and `Shift+Left Click` reverse window cycling (`7.11`), `item_captures_scroll()` overflow scroll exemption (`10.4`), and `Middle-Click` close on `WindowCardsWindow` (`12.4`) in `[ko->test]`. |
| **[#22](https://github.com/sergiomelas/WayPlank/issues/22)** | [@sergiomelas](https://github.com/sergiomelas) | **[Regression] Multi-Compositor HAL Signal & Preview Thumbnail Cache Regressions (FAT 2.7, 2.9, 12.6)** | Compositor HAL / Previews | `[Remediated Locally]` (`FAT 2.7, 2.9, 12.6 [ko->test]`) | Remediated in `v0.7.1`: GNOME Mutter urgent/demands-attention `WindowsChanged` emission & `MinimizedSequence` ordering (`2.7`), KWin `window.captionChanged` dynamic title sync (`2.9`), and `KWinThumbnailService` refresh/eviction, debug cleanup, and Labwc D-Bus guard (`12.6`) in `[ko->test]`. |
| **[#23](https://github.com/sergiomelas/WayPlank/issues/23)** | [@sergiomelas](https://github.com/sergiomelas) | **[Bug] Labwc Do Not Disturb Toggle Failure & Cross-Desktop Docklet Settings Routing (FAT 6.12, 6.18)** | Docklets / Cross-DE | `[Remediated Locally]` (`FAT 6.12, 6.18 [ko->test]`) | Remediated in `v0.7.1`: guarded GNOME `gsettings` branch in `DoNotDisturbDockItem.inhibit()`/`uninhibit()` on Labwc (`6.18`) and centralized `XDG_CURRENT_DESKTOP`-aware priority in `System.launch_desktop_utility()` (`6.12`). |
| **[#26](https://github.com/sergiomelas/WayPlank/issues/26)** | [@sergiomelas](https://github.com/sergiomelas) | **[Feature Proposal] Smart Usage-Adaptive Accordion for Pinned Applications (Community Feedback Welcome!)** | Core UX / Feature | `[Implemented Locally]` (`FAT 6.14 [  ] in v0.7.1`) | Implemented in `v0.7.1` (`AppUsageService.vala`, `PinnedExpanderDockItem.vala`): GNOME `shell-app-usage.c` frecency-based accordion for `[Pinned Apps]` (`Off` / `Auto-Fit Capacity` / `Top 3..12 Most Used`) keeping top-used, running, and urgent launchers visible in manual left-to-right order with per-icon `KeepVisible` override and live expansion while `Preferences` is open. |

</details>

<details>

<summary><b>🟢 Closed & Qualified Community Issues, PRs & Discussions (20 Closed/Qualified: #1, #5 – #19, #24, #25, #27 & Discussion #3) — Click to expand</b></summary>

| Issue / Topic | Author | Title | Area | Status | Technical Details & Next Steps |
|:---:|:---:|---|---|:---:|---|
| **[#1](https://github.com/sergiomelas/WayPlank/issues/1)** | [@winteriscariot](https://github.com/winteriscariot) | **How is primary display determined?** | Multi-Monitor / Geometry | `[Closed]` (Solved) | Resolved in v0.6.0 (`5d59821`): implemented native `Gdk.Display.get_primary_monitor()` fallback with duplicate display disambiguation and monitor index mapping. |
| **[#5](https://github.com/sergiomelas/WayPlank/issues/5)** | [@tcliuqiang](https://github.com/tcliuqiang) | **Wayland can not suite the HIDPI display (3840x2160@1.5x)** | GNOME Mutter / HiDPI | `[Closed]` (Solved) | Resolved in v0.6.2.3 (FAT Point 7.7 `[ko->ok]`, verified 100% across KWin, Mutter & Labwc): added dynamic `notify["scale-factor"]` listener on the dock window in `PositionManager.vala`, tracked `last_scale_factor` in `screen_changed()` to reset Cairo renderer buffers and recompute layout when fractional scaling updates asynchronously on cold start, and forced `current_monitor = null` refresh on monitor preference changes. |
| **[#6](https://github.com/sergiomelas/WayPlank/issues/6)** | [@winteriscariot](https://github.com/winteriscariot) | **WayPlank is mixing up icons, titles, and desktop files, and others are missing** | Core / Matching | `[Closed]` (Solved) | Resolved in v0.6.2.3 (FAT Point 2.14 `[ko->ok]`): exact primary matching on `DesktopFileName`, `ApplicationId`, and `StartupWMClass` (`crx_<id>`), word-boundary Unicode parsing in `ApplicationIdentity.vala` eliminating substring hijacking (e.g. Gram for Instagram, Web for Open WebUI), and `is_best_launcher_for_window` in `ApplicationDockItemProvider.vala` allowing PWA windows to instantiate distinct transient dock items. |
| **[#7](https://github.com/sergiomelas/WayPlank/issues/7)** | [@reni001](https://github.com/reni001) | **German translation** | i18n / Translations | `[Closed]` (Solved) | Resolved in v0.6.2.3: complete German catalog (`po/de.po`, 326 strings; expanded to 487/487 in `v0.7.0`) contributed by reni001 and integrated into `po/generate_translations.py`. |
| **[#8](https://github.com/sergiomelas/WayPlank/issues/8)** | [@Gabenoh](https://github.com/Gabenoh) | **Ukrainian translation** | i18n / Translations | `[Closed]` (Solved) | Resolved in v0.6.2.3: complete Ukrainian catalog (`po/uk.po`, 326 strings; expanded to 487/487 in `v0.7.0`) contributed by Gabenoh and integrated into `po/generate_translations.py`. |
| **[#9](https://github.com/sergiomelas/WayPlank/issues/9)** | [@tcliuqiang](https://github.com/tcliuqiang) | **[Feature Request] Add an option to reserve screen space to prevent overlapping with application windows** | Layer Shell / Geometry | `[Closed]` (Solved) | Resolved in v0.6.2.3 (FAT Point 3.10 `[ok]`, verified 100% across KWin, Mutter & Labwc): added configurable `ReserveSpace` (Panel Mode) in Preferences -> Behaviour (`reserve-space` GSettings key). Negotiates `gtk_layer_shell_set_exclusive_zone` matching visual dock thickness on KDE Plasma 6 (KWin) and Labwc (wlroots); deploys dynamic synthetic strut (`affectsStruts`) on GNOME Shell (Mutter) anchored to physical monitor geometry with top panel offset and `user_op=true` unconstrained placement. |
| **[#10](https://github.com/sergiomelas/WayPlank/issues/10)** | [@tcliuqiang](https://github.com/tcliuqiang) | **[Feature Request] Auto-hide WayPlank dock when applications (e.g., Remmina, QEMU) enter fullscreen mode** | Window Tracking / UX | `[Closed]` (Solved) | Resolved in v0.6.2.3 (FAT Point 3.9 `[ko->ok]`, verified 100% across KWin, Mutter & Labwc): added `Fullscreen` window state tracking and `fullscreen_window_intersects()` across KWin (`client.fullScreen` + `fullScreenChanged`), GNOME Mutter (`win.is_fullscreen()` + `notify::fullscreen`), and Labwc (`t->fullscreen`), with `FullscreenInhibit` in `HideManager.vala` and `{ 0, 0, 0, 0 }` input region for 100% `0px` edge click passthrough. |
| **[#11](https://github.com/sergiomelas/WayPlank/issues/11)** | [@Jolmas](https://github.com/Jolmas) | **Wayplank not appear in other workspace (Labwc)** | Labwc (wlroots) / Workspaces | `[Closed]` (Solved) | Resolved in v0.6.2.3 (FAT Point 4.1 `[ko->ok]`, verified 100% across KWin, Mutter & Labwc): added `t->active` check in `wlr_toplevel_bridge_any_window_intersects` and `wlr_toplevel_bridge_maximized_window_intersects` (`wlr-toplevel-bridge.c`) so inactive-workspace windows on Labwc no longer trigger dodge/hide on empty workspaces; connected `win.connect('workspace-changed')` in `MutterBackend.vala`. |
| **[#12](https://github.com/sergiomelas/WayPlank/issues/12)** | [@Gabenoh](https://github.com/Gabenoh) | **Wayplank blocks mouse clicks on windows behind it when a non-fullscreen window is active** | Layer Shell / Input Mask | `[Closed]` (Solved) | Resolved in v0.6.2.3 (FAT Point 5.4 `[ko->ok]`, verified 100% across KWin, Mutter & Labwc): reported by Gabenoh, clicks swallowed on transparent extended allocations when a window rests behind the dock. Implemented two-stage hysteresis flip-flop and configurable `AnticipateZoom` toggle in Preferences -> Behaviour. |
| **[#13](https://github.com/sergiomelas/WayPlank/issues/13)** | [@tcliuqiang](https://github.com/tcliuqiang) | **[Bug/Feature] WayPlank hides when triggering "Show Desktop" (Super + D) on Ubuntu 26.04 LTS** | Compositor HAL / Layer Shell | `[Closed]` (Solved) | Resolved in v0.6.2.3 (FAT Point 6.1 `[ko->ok]`, verified 100% across KWin, Mutter & Labwc): intercepted `showingDesktopChanged` D-Bus signal in `KWinBridge.vala` on KDE Plasma 6; invoked `win.hide_from_window_list()` on dock/hover/poof surfaces and connected `global.workspace_manager.connect('showing-desktop-changed')` in `MutterBackend.vala` on GNOME Shell; gated intersection checks on `t->active` in `wlr-toplevel-bridge.c` on Labwc. |
| **[#14](https://github.com/sergiomelas/WayPlank/issues/14)** | [@tcliuqiang](https://github.com/tcliuqiang) | **[Bug] QEMU virtual machine window icon is missing from WayPlank dock** | Core / Matching | `[Closed]` (Solved) | Resolved in v0.6.2.3 (FAT Point 2.15 `[ko->ok]`, verified 100% across KWin, Mutter & Labwc): indexed Exec-less `NoDisplay=true` desktop templates (`qemu.desktop`), synthesized dedicated launchers in `~/.local/share/applications/` with `gc_synthetic_launchers()` garbage collection, enforced multi-VM argument isolation in `ApplicationIdentity.vala`, and added $O(1)$-cached `/proc` PID & cmdline resolution (`resolve_toplevel_process`) in `LabwcBackend.vala`. |
| **[#15](https://github.com/sergiomelas/WayPlank/pull/15)** | [@IFtiger-hu-hub](https://github.com/IFtiger-hu-hub) | **fix matcher Flatpak App Icon** *(PR)* | Core / Matching | `[Closed]` (Merged) | Resolved in v0.6.2.3: handled Flatpak delimiters (`@@`, `@@u`), `--command=` target parsing, strict token-level basename matching (with `-bin` suffix handling), and canonical `DesktopFileName` match shortcut. Preserved original commit authorship in git history (`90c1d5e`). |
| **[#16](https://github.com/sergiomelas/WayPlank/issues/16)** | [@tcliuqiang](https://github.com/tcliuqiang) | **[Regression] Command-line launched GUI apps (QEMU, Obsidian) are no longer monitored in v0.7.0 Beta 1** | Core / Matching | `[Closed Locally]` (`FAT 2.15 [ok]`) | Resolved in `v0.7.0` Hotfix & graduated `[ok]` in `v0.7.1` (FAT Point `2.15`): expanded `DataDirFolders` for Snap/Flatpak desktop paths, resolved CLI AppImage FUSE paths via `/proc/<pid>/environ` (`APPIMAGE=`), stabilized synthetic launcher binding across dynamic title updates, and replaced `matched_exec_less_desktop` with zero-hardcoding dialog masking (to be closed on GitHub upon `v0.7.1` push). |
| **[#17](https://github.com/sergiomelas/WayPlank/issues/17)** | [@tcliuqiang](https://github.com/tcliuqiang) | **[Bug/UX] "Reserve Screen Space" toggle is greyed out and cannot be enabled in v0.7.0 Beta 1** | Preferences UX / Geometry | `[Closed]` (Solved) | Confirmed & closed by reporter (`2026-11-04`), and further refined in `v0.7.0` Hotfix (FAT Point 3.10 `[ko->ok]`): replaced the disabled/greyed-out sensitivity lock on `Reserve Screen Space` with a deterministic edge-triggered SR Flip-Flop in `DockPreferences.vala` (`S = ↑ReserveSpace` automatically turns off `Hide Dock` and `Icon Zoom`; `R = ↑HideDock ∨ ↑IconZoom` automatically turns off `ReserveSpace`), keeping all three toggles 100% clickable across GUI and CLI `gsettings`. |
| **[#18](https://github.com/sergiomelas/WayPlank/issues/18)** | [@tcliuqiang](https://github.com/tcliuqiang) | **[Bug] WayPlank dock disappears after running for a while and requires manual CLI refresh to reappear** | Compositor HAL / Lifecycle | `[Closed Locally]` (`FAT 9.9/9.10 [ok]`) | Resolved in `v0.7.0` Hotfix & graduated `[ok]` in `v0.7.1` (FAT Point `9.9/9.10`): broke the GNOME Mutter `PositionDock` / `DockWindow.hide()` Catch-22 deadlock across `unlock-dialog` extension disable/re-enable cycles via `_lastDockGeo` caching, wired `monitors-changed` + `bridge_reconnected` + `org.gnome.ScreenSaver` + `login1.Session.Unlock` to `schedule_dock_refresh()`, and added `dock_unmapped` recovery (to be closed on GitHub upon `v0.7.1` push). |
| **[#19](https://github.com/sergiomelas/WayPlank/issues/19)** | [@sergiomelas](https://github.com/sergiomelas) | **[Regression] "Recent Documents" Jump List submenu missing from application right-click menus** | Core UI / Menus | `[Closed Locally]` (`FAT 12.2 [ok]`) | Resolved in `v0.7.0` & graduated `[ok]` in `v0.7.1` (FAT Point `12.2`): implemented `RecentFilesService.vala` (`Gtk.RecentManager`) and wired the localized *"Recent Files"* jump-list submenu into `ApplicationDockItem` and `FolderMenuWindow` context menus (to be closed on GitHub upon `v0.7.1` push). |
| **[#24](https://github.com/sergiomelas/WayPlank/issues/24)** | [@sergiomelas](https://github.com/sergiomelas) | **[Bug] Preferences Runtime Polish & CLI Short Flag Collision (FAT 1.11, 10.8, 13.8)** | Preferences / CLI | `[Closed Locally]` (`FAT 10.8, 13.8 [ok]`) | Resolved in `v0.7.0` & graduated `[ok]` in `v0.7.1`: wired `ShowRunningIndicators` on Folder Drawers + live redraw notification, centralized `EffectDuration` / `VERSION` constants, added `ReverseRoundness` 40px skirt to redline capacity math, and routed CLI `-V` to `--verbose` (to be closed on GitHub upon `v0.7.1` push). |
| **[#25](https://github.com/sergiomelas/WayPlank/issues/25)** | [@sergiomelas](https://github.com/sergiomelas) | **[Bug] Custom Image File Icons on Folders Fail to Apply Reliably or Persist (FAT 1.10)** | Core UI / Icons | `[Closed Locally]` (`FAT 1.10 [ok]`) | Resolved in `v0.7.0` & graduated `[ok]` in `v0.7.1`: preserved canonical `file://` URIs in `metadata::custom-icon`, handled absolute `/` paths in `DrawingService.get_icon_from_file()`, and added `CustomIcon` persistence in `DockItemPreferences` (`.dockitem`) (to be closed on GitHub upon `v0.7.1` push). |
| **[#27](https://github.com/sergiomelas/WayPlank/issues/27)** | [@polpodan](https://github.com/polpodan) | **Unable to enter Edit Mode in KDE Plasma while Wayplank is running** | Compositor HAL / Show Desktop | `[Closed Locally]` (`FAT 6.1 [ko->ok]`) | Resolved & qualified `[ko->ok]` in `v0.7.1` (`KWinBridge.vala`, `MutterBackend.vala`, FAT Point `6.1`): tracked `org.kde.PlasmaShell.editMode` via `PropertiesChanged` and synchronous D-Bus query in `on_showing_desktop_changed()` so desktop-initiated `showingDesktop=true` (KDE Plasma Edit Mode & `WidgetExplorer`) is allowed through and hides WayPlank via `fullscreen_window_intersects()` (`FullscreenInhibit`), while user-initiated `Super + D` keeps WayPlank visible across KWin, Mutter (`showing-desktop-changed` outside `Main.overview`), and Labwc (to be closed on GitHub upon `v0.7.1` push). |
| **[Discussion #3](https://github.com/sergiomelas/WayPlank/discussions/3)** | [@Gabenoh](https://github.com/Gabenoh) | **Hide Preferences Icon & Minimalist Docklets Mode** | Core UI / Ergonomics | `[Closed]` (Solved) | Resolved in v0.6.2.3: suggested by Gabenoh, implemented 4-position `SystemMenuAccess` engine (Docklets Only, All Icons, Dedicated Icon) and global `Ctrl + Right Click` access shortcut. *(Note: the subsequent pointer input issue discussed at the end of this thread was branched into dedicated Issue #12).* |

</details>

---

## 🛠️ How to Contribute

### Track 1: Localization & Translations (i18n)

WayPlank features a standalone translation architecture managed through a central dictionary script: [`po/generate_translations.py`](po/generate_translations.py).

Currently, **7 languages** are qualified at **100% (519/519 strings)**:

* **Natively Maintained by Author** *(Complete & Closed)*:
  - English (`en`) — In-source native fallback
  - Italiano (`it`) — Sergio Melas
  - Español (`es`) — Sergio Melas
  - Français (`fr`) — Sergio Melas
  - Català (`ca`) — Sergio Melas
* **Community-Contributed Catalogs** *(100% Qualified)*:
  - 简体中文 (`zh_CN`) — 史有虎 (IFtiger-hu)
  - Deutsch (`de`) — Renate Schwiedernoch
  - Українська (`uk`) — Michailo Buchko

> [!NOTE]
> Contributions for **new languages** (e.g., Polish, Portuguese, Dutch, Japanese, Turkish, Swedish, etc.) are warmly welcome! If you speak a language not listed above, follow the steps below to contribute.

#### How to Add a New Language or Refine Existing Translations:
1. Open [`po/generate_translations.py`](po/generate_translations.py).
2. Add your language code (e.g., `pl`, `pt_BR`, `ja`) to the `translations` dictionary entries and the `languages` configuration list at the bottom.
3. **⚠️ Critical Rule for Ampersands (`&`)**:
   - `Session & Power`: Used for plain text window titles -> use literal `&`.
   - `Session &amp; Power`: Used inside GTK Pango XML markup (`title_label.set_markup`) -> **MUST keep `&amp;`**! Unescaped ampersands cause Pango runtime XML parse errors.
4. Regenerate all `.po` files:
   ```bash
   python3 po/generate_translations.py
   ```
5. Verify that `msgfmt` compiles with 0 errors:
   ```bash
   msgfmt -c -v po/<lang>.po -o /dev/null
   ```

---

### Track 2: Reporting Bugs & Feature Requests

When opening a new issue on GitHub, please include:
1. **Operating System & Distribution**: (e.g. Ubuntu 26.04, Fedora 41, Arch Linux, openSUSE Tumbleweed).
2. **Desktop Environment & Compositor**: (e.g. KDE Plasma 6.2 / KWin, GNOME 47 / Mutter, Labwc 0.8).
3. **WayPlank Version**: (run `wayplank -v`).
4. **Steps to Reproduce**: Detailed steps showing the behavior.
5. **Debug Log Output**: Launch WayPlank in debug mode from terminal and capture logs:
   ```bash
   wayplank -d
   ```

---

### Track 3: Testing on Other Compositors

WayPlank's goal is to be the universal dock for the entire Wayland desktop ecosystem. Community testing is especially welcome on:
* **Sway** (wlroots)
* **Hyprland** (wlroots / custom layer-shell)
* **Wayfire** (wlroots 3D)
* **Cosmic Desktop** (cosmic-comp)
* **Mir / Miriway**

If you test WayPlank on any of these compositors, please report your findings in [GitHub Discussions](https://github.com/sergiomelas/WayPlank/discussions)!

---

### Track 4: Themes & Visual Customization

WayPlank supports modular themes compatible with the Plank/WayPlank theme specification (`dock.theme`).
* Themes can be installed dynamically via the **Theme Manager** (`wayplank --preferences` -> Theme tab) by importing `.zip`, `.tar.gz`, or `.theme` archives.
* Community themes can be contributed to `data/themes/` or shared in Discussions.

---

### Track 5: Distribution Packaging

We currently provide native build scripts for:
* **Debian / Ubuntu** (`.deb`): `./BuildDeb.sh`
* **Fedora / openSUSE / RHEL** (`.rpm`): `./BuildRpm.sh`

Community packages for other package managers are warmly welcome:
* **Arch Linux AUR** (`PKGBUILD`)
* **Nix / NixOS Flakes**
* **Gentoo ebuilds**
* **Alpine Linux APK**
* **Flatpak**

---

## 💻 Development & Coding Standards

### The HAL Rule (Compositor Independence)

> [!IMPORTANT]
> **Prime Architectural Directive**:
> `HAL = any part of the repository that depends on the window manager / compositor.`

* WayPlank runs seamlessly across **KWin**, **Mutter**, and **Labwc** (with physical multi-OS HAL isolation documented in [Documentation/HAL_ARCHITECTURE.md](Documentation/HAL_ARCHITECTURE.md)). 
* **Never write compositor-specific or OS-specific logic inside core dock code** (`lib/Widgets/`, `lib/Items/`, `src/`).
* All compositor-specific interactions (window tracking, thumbnails, active desktop detection, panel avoidance) MUST reside strictly behind the HAL interfaces (in [lib/Services/](lib/Services/) on the `v0.7.1` baseline, migrating physically into `hal/{Interfaces,Freedesktop,Linux,BSD,Windows}/` in `v0.7.2+` per [Documentation/HAL_ARCHITECTURE.md](Documentation/HAL_ARCHITECTURE.md)).
* Any fix for one compositor **must be verified not to break other compositors**.
* 🛑 **MANDATORY PR & FORK QUALIFICATION POLICY**:
  - **No pull request from forks will be accepted or merged without an accompanying verified FAT document.**
  - Every PR modifying code, UI, or dock behavior must include its corresponding FAT test document generated directly from the official template ([`FAT/Template/FAT Template.txt`](FAT/Template/FAT%20Template.txt)), strictly named:
    ```
    FAT/<YYYY-MM-DD> FAT from <Contributor Name> <version>.txt
    ```
    *(e.g., `FAT/2026-11-05 FAT from JohnDoe v0.7.0.txt`)*.
  - The project maintainer will **NOT** test unverified third-party PRs across multiple compositors on your behalf. Submissions without a complete FAT run are rejected outright.

### Building Locally

WayPlank uses a native, high-speed compilation script (`BuildBin.sh`) with zero complex build systems:

```bash
# Clone the repository
git clone https://github.com/sergiomelas/WayPlank.git
cd WayPlank

# Build standalone monolithic executable (or full packages via WAYPLANK_NO_PROMPT=1 ./BuildDeb.sh / ./BuildRpm.sh)
./BuildBin.sh

# Run locally in debug mode
./build/wayplank -d

# Replace any existing running instance
./build/wayplank -r
```

### Testing & Quality Assurance (FAT)

WayPlank adheres to a rigorous **Factory Acceptance Test (FAT)** protocol covering 382 validation points across all Tier 1 compositors (`359/377` = `95.2% PASS` in concluded [`FAT/2026-11-05 FAT 0.7.0.txt`](FAT/2026-11-05%20FAT%200.7.0.txt), and `341 [ok]` baseline + `3 [ko->ok]` squashed + `18 [ko->test]` remediations + `18 [  ]` new features + `0 [ko]` in active [`FAT/2026-11-07 FAT 0.7.1.txt`](FAT/2026-11-07%20FAT%200.7.1.txt)):
* Test protocols and matrices are maintained in [`FAT/`](FAT/).
* Any PR introducing new UI, docklets, or window management changes **MUST** be accompanied by verification against the checklist in [`FAT/Template/FAT Template.txt`](FAT/Template/FAT%20Template.txt).
* Fill out the template across tested compositors, save it as `FAT/<date> FAT from <Contributor name> <version>.txt`, and commit it as part of your pull request.

---

## 📬 Submitting Pull Requests (PRs)

1. **Fork the repo** and create your branch from `main`:
   ```bash
   git checkout -b feature/my-cool-feature
   ```
2. **Keep PRs focused**: One feature or bugfix per PR.
3. **Ensure a clean build**: `./BuildBin.sh` must compile with 0 errors.
4. **Mandatory FAT Verification Attached**: Execute the tests against [`FAT/Template/FAT Template.txt`](FAT/Template/FAT%20Template.txt) and commit your completed `FAT/<date> FAT from <Contributor name> <version>.txt` file. PRs without an executed FAT document will be closed without review.
5. **Follow commit conventions**: Use clear, concise commit messages (e.g. `feat(docklet): ...`, `fix(mutter): ...`, `i18n(uk): ...`).
6. **Open your Pull Request**: Reference any relevant issue (e.g., `Fixes #6` or `Addresses #10`).

Thank you for helping make WayPlank the best dock on Wayland! 🚀

