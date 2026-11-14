# 🏛️ WAYPLANK APPLICATION IDENTIFICATION & DISCOVERY ENGINE SPECIFICATION

> **Formal Software Architecture Specification for the Agnostic Launcher/Process Boundary Translator (`IAppSystem`), Cross-OS Path/Argv Purity & 6-Layer Mathematical Window-to-Launcher Solver**  
> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **ISA-88 Document Control & MOC:** `DOC-ARCH-ID-004` • **Revision `2.0`** (`MOC-0.7.2-HAL-001` — `IAppSystem` Boundary Translator, Cross-OS `parse_command_argv` `\` Safety, `Path.is_absolute()`, `aumid://` & `RecentDocInfo`)  
> **Target Core Solver Modules (`Zone 1 — 100% OS-Agnostic Core`):** [`lib/Services/ApplicationIdentity.vala`](../../lib/Services/ApplicationIdentity.vala), [`lib/Services/ApplicationDiscovery.vala`](../../lib/Services/ApplicationDiscovery.vala), [`lib/Services/WindowManager.vala`](../../lib/Services/WindowManager.vala), [`lib/Services/RecentFilesService.vala`](../../lib/Services/RecentFilesService.vala)  
> **Companion Architecture Specifications:** [Master Architecture Overview (`README.md`)](README.md) • [Repository `README.md`](../../README.md) • [HAL_COMPOSITORS.md](HAL_COMPOSITORS.md) • [HAL_BUSES.md](HAL_BUSES.md) • [HAL_WINDOWS_BACKEND.md](HAL_WINDOWS_BACKEND.md) • [USER_GUIDE.md](../USER_GUIDE.md)  
> **Compliance & Verification Baseline:** [CONTRIBUTING.md](../../CONTRIBUTING.md) • [FAT/WAYPLANK_LIFETIME_BUG_REGISTER.md](../../FAT/WAYPLANK_LIFETIME_BUG_REGISTER.md) • [Changelogs/CHANGELOG_v0.1.0.md](../../Changelogs/CHANGELOG_v0.1.0.md) $\longrightarrow$ [Changelogs/CHANGELOG_v0.7.1.md](../../Changelogs/CHANGELOG_v0.7.1.md) • Verified via 10-Iteration Top-Down / Bottom-Up / Tera Logical Simulator ($65,025$ pairwise cross-product evaluations, $0$ failures)

---

## 📌 Table of Contents

- [1. ISA-88 MOC Governance, `IAppSystem` Boundary Translator & Dual-Entity Model](#1-isa-88-moc-governance-iappsystem-boundary-translator--dual-entity-model)
  - [1.0 Document Revision History (`MOC-0.7.2-HAL-001`)](#10-document-revision-history-moc-072-hal-001)
  - [1.1 System Purpose, Scope & Single-Pass Immutable Identity Lock](#11-system-purpose-scope--single-pass-immutable-identity-lock)
  - [1.2 The Agnostic Launcher, Process & Recent-Files Boundary Translator (`IAppSystem`: `.desktop` & `/proc` ⟷ `.lnk`, `AUMID` & `Win32`)](#12-the-agnostic-launcher-process--recent-files-boundary-translator-iappsystem-desktop--proc--lnk-aumid--win32)
  - [1.3 The Dual-Entity Model: Static Identity ($I$) vs. Live Window Descriptor ($W$)](#13-the-dual-entity-model-static-identity-i-vs-live-window-descriptor-w)
  - [1.4 4-Compositor Telemetry Contract & End-to-End Pipeline](#14-4-compositor-telemetry-contract--end-to-end-pipeline)
- [2. The Standard Identification Engine (Normal `.desktop` / `.lnk` ↔ `Exec` & Process Matching)](#2-the-standard-identification-engine-normal-desktop--lnk--exec--process-matching)
  - [2.1 Launcher Discovery, Cross-OS Path/URI Purity (`Path.is_absolute` & `aumid://`) & Visibility Dispositions](#21-launcher-discovery-cross-os-pathuri-purity-pathis_absolute--aumid--visibility-dispositions)
  - [2.2 `Exec=` / `.lnk` Command Grammar, Cross-OS `\`-Safe `parse_command_argv`, Wrapper Unwrapping & Binary Tokenization](#22-exec--lnk-command-grammar-cross-os--safe-parse_command_argv-wrapper-unwrapping--binary-tokenization)
  - [2.3 Live Process & Recent-Document Introspection (`ProcessSnapshot` & `RecentDocInfo`)](#23-live-process--recent-document-introspection-processsnapshot--recentdocinfo)
  - [2.4 The 5-Stage Standard Matching Algorithm (`Exec` ↔ Process & Window)](#24-the-5-stage-standard-matching-algorithm-exec--process--window)
  - [2.5 Multi-Launcher Equivalence & Sibling Co-Illumination (`shares_application_with`)](#25-multi-launcher-equivalence--sibling-co-illumination-shares_application_with)
  - [2.6 Unmatched Process Fallback Synthesis (`.desktop` / `.lnk`) & Garbage Collection](#26-unmatched-process-fallback-synthesis-desktop--lnk--garbage-collection)
- [3. The Specialized & Multiplexed Runtime Engine (Advanced Isolation, Scoring & Selection)](#3-the-specialized--multiplexed-runtime-engine-advanced-isolation-scoring--selection)
  - [3.1 Specialization Model (`is_specialized`) & The `>= 115` Canonical Override Rule](#31-specialization-model-is_specialized--the--115-canonical-override-rule)
  - [3.2 Single-Process Browser, PWA & Event-Driven Multi-Profile Isolation (`Chrome:<Profile>`)](#32-single-process-browser-pwa--event-driven-multi-profile-isolation-chromeprofile)
  - [3.3 Terminal-Hosted Command Execution Specification (`-e`, `--`, `-x`, `Terminal=true`)](#33-terminal-hosted-command-execution-specification--e-----x-terminaltrue)
  - [3.4 Generic Runtime & Container Specification (Interpreters, VMs, Wine/Win32)](#34-generic-runtime--container-specification-interpreters-vms-winewin32)
  - [3.5 Master Scoring Function $S(I, W)$, Effective Score $S_{\text{eff}}(I, W)$ & Selection Criteria](#35-master-scoring-function-si-w-effective-score-s_texteffi-w--selection-criteria)
  - [3.6 Normative Compliance & 10-Iteration Invariant Verification Matrix](#36-normative-compliance--10-iteration-invariant-verification-matrix)

---

## 1. ISA-88 MOC Governance, `IAppSystem` Boundary Translator & Dual-Entity Model

### 1.0 Document Revision History (`MOC-0.7.2-HAL-001`)

| Revision | Date | Author | Summary of Architectural Changes (`MOC-0.7.2-HAL-001`) |
| :---: | :---: | :--- | :--- |
| **`1.0`** | `2026-11-14` | Sergio Melas | Initial multi-OS `IAppSystem` & 6-Layer mathematical identity specification (`v0.7.1.2` baseline). |
| **`2.0`** | `2026-11-14` | Sergio Melas | **`MOC-0.7.2-HAL-001`:** Routed all static launcher files and live `/proc`/PEB/bus signals in `§1.2`–`§1.3` schemes strictly through the **`IAppSystem` + `IAppMenuBus` + `IWindowBackend` Agnostic Boundary Translators**; replaced POSIX `GLib.Shell.parse_argv` (`\`-stripping trap) with `Hal.Runtime.parse_command_argv()`; replaced Unix `has_prefix("/")` checks across 11 Core files with `GLib.Path.is_absolute()` + `IAppSystem.launcher_exists(uri)` (supporting UWP `aumid://`); added `IAppSystem.find_installed_browser_binary()` (replacing hardcoded `/opt/google/chrome`) and `IAppSystem.get_recent_documents()` (`RecentDocInfo`: `RecentManager` vs Windows `Recent\*.lnk`). Preserved 100% of $S(I,W) \in [0..124]$ math and all 11 normative invariants. |

### 1.1 System Purpose, Scope & Single-Pass Immutable Identity Lock

In modern Wayland and Windows desktop environments, there is no legacy X11 property tree linking a surface directly to the dock launcher file that started it. When a window appears on screen, the dock must deterministically answer three questions:
1. **Window-to-Launcher Binding (`best_desktop_file_for_window`):** Which installed launcher (`.desktop` on Linux/BSD or `.lnk` / UWP `AUMID` on Windows) owns this window so the dock can display the right icon, title, and running indicator?
2. **Dock Item Ownership & Co-Illumination (`is_best_launcher_for_window`):** For each pinned icon on the dock or inside a Folder Drawer, does this window belong to that icon?
3. **Unmatched CLI Synthesis (`synthesize_fallback_desktop_file`):** If the window was launched directly from a command-line shell without any installed launcher file, how does the dock construct a temporary launcher that can also be pinned (`Keep in Dock`) and cold-relaunched?

> [!IMPORTANT]
> **Single-Pass Window Identification & Immutable Lock (`v0.7.1+` Invariant):**  
> Every window is identified **exactly once** upon creation (`on_window_opened` / `scan_initial_windows`) inside `ApplicationIdentity`, locked immutably for the entire lifetime of `window.Id` (`window_locked_launcher_uris[window.Id]`, `window_locked_display_names[window.Id]`, `window_browser_profiles[window.Id]`), and purged strictly upon window destruction (`on_window_closed`). All downstream consumers query the locked result in $O(1)$.

---

### 1.2 The Agnostic Launcher, Process & Recent-Files Boundary Translator (`IAppSystem`: `.desktop` & `/proc` ⟷ `.lnk`, `AUMID` & `Win32`)

To keep the mathematical scoring engine (`ApplicationIdentity`, `ApplicationDiscovery`, `WindowManager`, and `RecentFilesService` in `lib/Services/`) **100% OS-agnostic across Linux, BSD, and Windows**, zero `DesktopAppInfo`, `/proc/<pid>`, `Gtk.RecentManager`, `Posix.realpath`, or `IShellLinkW` calls exist in Zone 1 (`lib/`). All launcher, process, and recent-document I/O passes through the **Zone 2 Agnostic Boundary Translator (`hal/Interfaces/IAppSystem.vala`)**:

```mermaid
flowchart TD
    subgraph ZONE3_STATIC ["💾 ZONE 3: Southbound Launcher & Recent-File Drivers (hal/)"]
        direction LR
        FDO_DESK["Linux / BSD Driver (XdgAppSystem.vala — Frozen v0.7.2): Parses XDG .desktop, ~/Desktop & Gtk.RecentManager"];
        WIN_LNK["Windows Driver (Win32AppSystem.vala — Plugged v0.7.3): Parses .lnk via IShellLinkW, UWP AUMID (aumid://), SHIL_JUMBO & Recent .lnk"];
    end

    subgraph ZONE3_LIVE ["⚡ ZONE 3: Southbound Live Window, Kernel & Bus Drivers (hal/)"]
        direction LR
        LIN_LIVE["Linux / BSD Live Drivers (Frozen v0.7.2): KWin / Mutter / Labwc + /proc/PID/{cmdline,comm,environ,fd} + dbusmenu id=61"];
        WIN_LIVE["Windows Live Drivers (Plugged v0.7.3): HWND / Class / AUMID + QueryFullProcessImageNameW & PEB + UIAutomation Profile"];
    end

    subgraph ZONE2_TRANS ["🔀 ZONE 2: Agnostic Boundary Translators & Domain DTOs (hal/Interfaces/ — Frozen v0.7.2)"]
        direction LR
        APP_DESC["IAppSystem Static & Recent DTOs: struct AppDescriptor + struct RecentDocInfo"];
        PROC_SNAP["IAppSystem + IWindowBackend + IAppMenuBus Live DTOs: struct WindowInfo + struct ProcessSnapshot + Hal.Runtime.parse_command_argv"];
    end

    subgraph ZONE1_ENGINE ["🎯 ZONE 1: 100% OS-Agnostic Mathematical Identity Engine (lib/Services/)"]
        ID_CORE["ApplicationIdentity (I) • ApplicationDiscovery • RecentFilesService: 6-Layer Unwrapper + Pairwise Score S(I, W) in [0..124] + Fallback CLI Synthesis"];
    end

    FDO_DESK ==>|"v0.7.2 Linux Freeze"| APP_DESC;
    WIN_LNK -.->|"v0.7.3 Windows Plug-In"| APP_DESC;
    LIN_LIVE ==>|"v0.7.2 Linux Freeze"| PROC_SNAP;
    WIN_LIVE -.->|"v0.7.3 Windows Plug-In"| PROC_SNAP;
    APP_DESC ==>|"100% Normalized Pure Vala Structs"| ID_CORE;
    PROC_SNAP ==>|"100% Normalized Pure Vala Structs"| ID_CORE;
```

#### Table 1.2.A — Static Launcher Normalization (`AppDescriptor`: `.desktop` ⟷ `.lnk` & UWP `AUMID`)

| Normalized `AppDescriptor` Field (`IAppSystem`) | Linux / BSD Source (`hal/Freedesktop/Xdg/XdgAppSystem.vala`) | Windows `7 ⟷ 11+` Source (`hal/Windows/AppSystem/Win32AppSystem.vala`) | Role in `ApplicationIdentity` ($I$) |
| :--- | :--- | :--- | :--- |
| **`uri` & `base_id`** | `file:///.../org.kde.dolphin.desktop` $\rightarrow$ stem `org.kde.dolphin` | `file:///C:/.../Visual Studio Code.lnk` or `aumid://Microsoft.WindowsCalculator...` | Primary identity key & `launcher_exists(uri)` validation |
| **`display_name`** | Localized `Name[lang]=` / `Name=` key | Shortcut filename stem or `IShellFolder::GetDisplayNameOf` (`SHGDN_NORMAL`) | Populates $T_{\text{words}}$ & Stage 5 title matching |
| **`exec_command`** | `Exec=` command string (with `%U`/`%f`/`@@` field codes) | `IShellLinkW::GetPath()` + `" "` + `IShellLinkW::GetArguments()` | Feeds the 6-Layer command/script/wrapper unwrapper ($T_{\text{exec}}, T_{\text{args}}, T_{\text{mod}}$) |
| **`working_dir`** | `Path=` key in `.desktop` | `IShellLinkW::GetWorkingDirectory()` | Leaf folder name added to $T_{\text{args}}$ for Wine/runtime games |
| **`startup_wm_class_or_aumid`** | `StartupWMClass=` key in `.desktop` | COM `IPropertyStore::GetValue(PKEY_AppUserModel_ID)` (`AUMID`) on `.lnk` / UWP package | Populates $T_{\text{wmclass}}$ and $T_{\text{primary}}$ (Stage 1 `100`-pt & Tier 1 `120`-pt match) |
| **`sandbox_ids`** | `X-Flatpak=`, `X-Flatpak-RenamedFrom=`, `X-SnapInstanceName=` | UWP `PackageFamilyName` (`Microsoft.WindowsCalculator_8wekyb3d8bbwe!App`) | Added directly to $T_{\text{primary}}$ for sandboxed/Store apps |
| **`url_target`** | `Type=Link` / `URL=` / `URL[$e]=` | Internet shortcut `.url` (`[InternetShortcut] URL=`) | Classified as Class B1 (`is_browser_url_bookmark`) |
| **`icon_token`** | `Icon=` theme name or image path | `IShellLinkW::GetIconLocation` or `SHGetImageList(SHIL_JUMBO)` `256×256` `GdkPixbuf` | High-DPI dock & folder drawer icon rendering |
| **`is_terminal` & `is_terminal_emulator`** | `Terminal=true` & `Categories=` containing `TerminalEmulator` (`#30`) | Console subsystem flag / known Windows terminal stems (`wt`, `cmd`, `powershell`) | Distinguishes hosted CLI apps (`Terminal=true`) from interactive terminal emulators (`is_terminal_emulator`) |

#### Table 1.2.B — Live Window, Process & Recent-Document Normalization (`WindowInfo` + `ProcessSnapshot` + `RecentDocInfo`)

| Normalized Field | Linux (`KWin`/`Mutter`/`Labwc` + `/proc` + `D-Bus`) | BSD (`Wayland` + `sysctl` + `D-Bus`) | Windows (`Windows Compositor` + `Win32` + `Windows Bus`) |
| :--- | :--- | :--- | :--- |
| **`DesktopFileName` / `ApplicationId`** | Wayland `app_id` / KWin `desktopFileName` / Mutter `WindowTracker` | Same as Linux Wayland | Window `PKEY_AppUserModel_ID` (`SHGetPropertyStoreForWindow`) or executable stem |
| **`ResourceClass` / `ResourceName`** | XWayland `WM_CLASS` or Wayland `app_id` | Same as Linux Wayland | `GetClassNameW(hwnd)` & module base name (`.exe` stripped by `strip_script_ext`) |
| **`Caption` & `Pid`** | Compositor window title & `pid` | Compositor window title & `pid` | `GetWindowTextW(hwnd)` & `GetWindowThreadProcessId(hwnd, &pid)` |
| **`Executable` (`comm`)** | `/proc/<pid>/comm` (15-byte kernel comm) | `sysctl KERN_PROC_PATHNAME` basename | `QueryFullProcessImageNameW(hProcess)` basename |
| **`Cmdline` (`argv[0..k]`)** | `/proc/<pid>/cmdline` (NUL-separated vector) | `sysctl KERN_PROC_ARGS` | Process PEB `RTL_USER_PROCESS_PARAMETERS.CommandLine` / WMI `Win32_Process` |
| **`Environ` (`APPIMAGE`, `WINEPREFIX`)** | `/proc/<pid>/environ` | `sysctl KERN_PROC_ENV` | Process environment block (`NtQueryInformationProcess`) |
| **`Locked Browser Profile`** | `IAppMenuBus` (`com.canonical.dbusmenu` `id=61` + `/proc/<pid>/fd` + `~/.config/google-chrome/Local State`) | `IAppMenuBus` (`com.canonical.dbusmenu` `id=61` + `Local State`) | `IAppMenuBus` (`UIAutomation` / `HWND` property + `%LOCALAPPDATA%\Google\Chrome\User Data\Local State`) |
| **`RecentDocInfo` Jump-List Items** | `Gtk.RecentManager.get_default().get_items()` (`recently-used.xbel`) | `Gtk.RecentManager` (`recently-used.xbel`) | `%APPDATA%\Microsoft\Windows\Recent\*.lnk` parsed via `IShellLinkW` |
| **`Synthesized CLI Launcher`** | `~/.local/share/applications/wayplank-app-<slug>.desktop` | `~/.local/share/applications/wayplank-app-<slug>.desktop` | `%APPDATA%\WayPlank\launchers\wayplank-app-<slug>.lnk` (`IShellLinkW::Save`) |

---

### 1.3 The Dual-Entity Model: Static Identity ($I$) vs. Live Window Descriptor ($W$)

The Identification Engine models application matching as a deterministic mathematical evaluation between two **pre-translated, OS-neutral structures**:

1. **The Static Launcher Identity ($I \in \mathcal{I}$ — `ApplicationIdentity` built from `AppDescriptor`):**
   Extracted once when `Hal.Apps` indexes a launcher on disk (and refreshed only when `Hal.Apps.apps_changed` fires). It represents **what the launcher declares it will start**:
   $$I = \langle \text{uri}, \text{base\_id}, \text{normalized\_id}, T_{\text{primary}}, T_{\text{wmclass}}, T_{\text{exec}}, T_{\text{dedicated}}, T_{\text{words}}, T_{\text{args}}, T_{\text{mod}}, \Phi_{\text{spec}} \rangle$$
   where:
   - $T_{\text{primary}}$: Structural identifiers (launcher filename stem, `startup_wm_class_or_aumid`, `sandbox_ids`, `steam_app_<id>`, and dedicated binary stems).
   - $T_{\text{wmclass}}$: Explicit `startup_wm_class_or_aumid` values (plus synthesized component classes such as `libreoffice-writer` for `libreoffice --writer`).
   - $T_{\text{exec}}$: All executable binary names extracted from `exec_command` (including unwrapped inner binaries, `-bin` variants, and canonical vendor aliases).
   - $T_{\text{dedicated}} \subseteq T_{\text{exec}}$: Non-generic, non-browser application binaries that uniquely identify an application family.
   - $T_{\text{words}}$: Non-generic Unicode word-boundary tokens ($\ge 5$ characters) extracted from `display_name`, `exec_command`, and `startup_wm_class_or_aumid`.
   - $T_{\text{args}}, T_{\text{mod}}, \Phi_{\text{spec}}$: Instance-isolating target arguments (`argument_tokens`), engine mod flags (`required_mod_tokens`, e.g. `+set game rogue`), browser profile/flag requirements (`required_browser_args`, `pwa_id`, `web_app_host`), or container prefixes (`wine_prefix`).

2. **The Live Window & Process Descriptor ($W$ — `WindowInfo` + `ProcessSnapshot`):**
   Assembled at runtime solely from `Hal.Windows` (`WindowInfo`), `Hal.Apps.inspect_process(pid)` (`ProcessSnapshot`), and `Hal.Bus.AppMenu` (`locked_browser_profile`). It represents **what is actually running in memory**:
   $$W = \langle \text{id}, \text{desktop\_file}, \text{app\_id}, \text{res\_class}, \text{res\_name}, \text{caption}, \text{is\_dialog}, \text{pid}, \text{comm}, \text{cmdline}, \text{children}, \text{environ} \rangle$$

```mermaid
flowchart LR
    subgraph ZONE3_IN ["⚙️ ZONE 3: Native OS Sources (hal/)"]
        OS_DISK["Launcher Files on Disk: .desktop • .lnk • .url • AUMID"];
        OS_LIVE["Live Compositor, Kernel & Bus: KWin / Mutter / Labwc / Win32 + /proc/PID / sysctl / PEB + dbusmenu id=61"];
    end

    subgraph ZONE2_TR ["🔀 ZONE 2: Boundary Translators (hal/Interfaces/)"]
        TR_APP["Hal.Apps (IAppSystem) -> struct AppDescriptor + Hal.Runtime.parse_command_argv"];
        TR_WIN["Hal.Windows + Hal.Apps + Hal.Bus.AppMenu -> WindowInfo + ProcessSnapshot + Locked Browser Profile"];
    end

    subgraph ZONE1_SOLVER ["🎯 ZONE 1: 100% OS-Agnostic Identity Engine (lib/Services/)"]
        UNWRAP["6-Layer Command Unwrapper -> Static Signature I"];
        ENGINE{"Pairwise Score S(I, W) & S_eff(I, W) in [0..124]"};
        MATCH["Score >= 50: Lock Window W -> Winner I*"];
        SYNTH["Score < 50 & !suppressed: Hal.Apps.synthesize_fallback_launcher()"];
        UNWRAP --> ENGINE;
        ENGINE --> MATCH;
        ENGINE --> SYNTH;
    end

    OS_DISK ==> TR_APP;
    TR_APP ==> UNWRAP;
    OS_LIVE ==> TR_WIN;
    TR_WIN ==> ENGINE;
```

---

### 1.4 4-Compositor Telemetry Contract & End-to-End Pipeline

#### 4-Compositor & 3-OS Signal Availability, Kernel Limitations & Universal Message Compatibility Matrix:
Per the HAL Prime Directive ([HAL_COMPOSITORS.md](HAL_COMPOSITORS.md) & [HAL_BUSES.md](HAL_BUSES.md)), the engine **never assumes** that a field populated on KWin or Linux `/proc` exists identically on Mutter, Labwc, BSD, or Windows. All messages crossing the translator boundary (`WindowInfo`, `ProcessSnapshot`, `AppDescriptor`) use **opaque string IDs (`Id`)** and **nullable/empty-safe fields (`""` / `0`)** with deterministic multi-level fallback:

| Message Field (`WindowInfo` / `ProcessSnapshot`) | KDE Plasma 6 (`KWinBridge`) | GNOME Shell (`MutterBackend`) | Labwc / wlroots (`LabwcBackend`) | `Windows Compositor` (`Win32 / UWP`) | Universal Compatibility & Degradation Rule |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`Id` (Opaque Surface Key)** | UUID string (`"{...}"`) | Mutter sequence string (`"mutter:123"`) | Pointer handle string (`"wlr:0x..."`) | Hex `HWND` string (`"hwnd:0x00010A20"`) | Always an **opaque `string`**—never cast to `uint32` or `ulong` in Core/UI! |
| **`DesktopFileName`** | Populated (`client.desktopFileName`) | Populated via `Shell.WindowTracker` (may be `""` on scripts/Wine) | Always `""` (not in `wlr-foreign-toplevel`) | Populated with `AUMID` if UWP/Store app, else `""` | Strictly optional (`""` = unknown); falls back to `ApplicationId` / `ResourceClass` / `ProcessSnapshot`. |
| **`ApplicationId`** | Wayland `app_id` / `resourceClass` | `gtk_application_id` / `wm_class` | `zwlr_foreign_toplevel_handle_v1.app_id` | `SHGetPropertyStoreForWindow(PKEY_AppUserModel_ID)` or exe stem | Normalized with `.desktop` & `.exe` stripping and `_` $\leftrightarrow$ `-` canonicalization. |
| **`ResourceClass` / `ResourceName`** | `resourceClass` / `resourceName` | `get_wm_class` / `get_wm_class_instance` | Mirrors `app_id` | `GetClassNameW(hwnd)` (resolving child `CoreWindow` inside `ApplicationFrameHost.exe`) | Checked alongside `ApplicationId` in $W_{\text{ids}}$. |
| **`Pid` & `Executable` (`comm`)** | Direct compositor `pid` $\rightarrow$ `/proc/<pid>/comm` (15-byte limit) | Direct `get_pid()` $\rightarrow$ `/proc/<pid>/comm` | Heuristic `/proc` scan (`resolve_toplevel_process`); **`0` if unmatched** | `GetWindowThreadProcessId` (unwrapping `ApplicationFrameHost.exe`) $\rightarrow$ `QueryFullProcessImageNameW` | `QueryFullProcessImageNameW` uses `PROCESS_QUERY_LIMITED_INFORMATION` (succeeds even on elevated Admin processes!). If `Pid == 0`, falls back to $W_{\text{ids}}$ + `Caption`. |
| **`Cmdline` & `Environ`** | `/proc/<pid>/cmdline` & `environ` (same UID; **`""` if `hidepid=2` or root**) | Same as KWin | **`""` when `Pid == 0`** or different UID | PEB `CommandLine` & Env (**`""` on elevated Admin / protected processes where `PROCESS_VM_READ` is denied**) | **Never required for standard matching!** When `Cmdline == ""`, Stages 1, 2, 4 (`Executable`), and 5 (`Caption`) still identify the window cleanly. |
| **`BrowserProfile` (`IAppMenuBus`)** | `com.canonical.dbusmenu` (`id=61`) + `/proc/<pid>/fd` + `Local State` | `/proc/<pid>/fd` + `Local State` (or `dbusmenu` if active) | `/proc/<pid>/fd` + `Local State` when `Pid > 0` | `UIAutomation` / `HWND` property + `%LOCALAPPDATA%\...\Local State` | If bus/FD introspection is unavailable, degrades gracefully to profile-neutral score (`100` / `120`). |

#### The Four Sequential Pipeline Phases:
1. **Phase 0 (Surface Gatekeeping):** Rejects internal dock surfaces (`is_ignored_app`: `wayplank`, `plank`, `xwaylandvideobridge`) and modal dialogs (`W.IsDialog`).
   - *Note:* `suppressed_nodisplay_tokens` is **never** evaluated in Phase 0, because system packages (such as Debian's `com.google.Chrome.desktop` or `org.kde.gwenview_importer.desktop`) often ship `NoDisplay=true` alias files carrying `StartupWMClass=google-chrome` or `StartupWMClass=gwenview` alongside the visible `google-chrome.desktop` / `org.kde.gwenview.desktop`.
2. **Phase 1 (Pairwise Scoring $S(I, W)$):** Computes the intrinsic match score $S(I, W) \in [0, 124]$ between $W$ and candidate identities $I \in \mathcal{I}$, then applies cross-candidate normalization to obtain the effective score $S_{\text{eff}}(I, W)$.
3. **Phase 2 (Selection & Co-Illumination):** Selects the winning launcher $I^*$ (via Canonical Fast-Path when no candidate achieves $\ge 115$, or via full maximization with priority tie-breaking) and illuminates running dots on all pinned/drawer launchers $I$ satisfying `is_best_launcher_for_window(I, W)`.
4. **Phase 3 (Fallback Synthesis Gate & GC):** If $\max_{I \in \mathcal{I}_{\text{exec}}} S_{\text{eff}}(I, W) < 50$ **and** $\neg\text{is\_suppressed\_nodisplay\_window}(W)$, synthesizes a fallback launcher (`wayplank-app-*.desktop` on Linux/BSD or `wayplank-app-*.lnk` on Windows) via `Hal.Apps.synthesize_fallback_launcher()` and garbage-collects unpinned synthetic files when their windows close.

---

## 2. The Standard Identification Engine (Normal `.desktop` / `.lnk` ↔ `Exec` & Process Matching)

### 2.1 Launcher Discovery, Cross-OS Path/URI Purity (`Path.is_absolute` & `aumid://`) & Visibility Dispositions

`ApplicationDiscovery` (together with `IconChooserDialog`, `ItemFactory`, and `DockItem`) discovers launchers exclusively via `Hal.Apps.get_launcher_search_dirs()` and `Hal.Apps.discover_installed_apps()`, where earlier directories take precedence on duplicate IDs:
1. **Directly Pinned Dock Launchers:** Every `.desktop`, `.lnk`, or `aumid://` URI explicitly referenced by `<config>/wayplank/dock*/launchers/*.dockitem` (indexed first so pinned launchers always win tie-breaks).
2. **User Desktop (`GLib.Environment.get_user_special_dir(UserDirectory.DESKTOP)` — Added in `v0.7.1`):** User desktop shortcuts (`.desktop` on Linux/BSD, `%USERPROFILE%\Desktop\*.lnk` / `*.url` on Windows).
3. **User Applications Directory:** `~/.local/share/applications` on Freedesktop; `%APPDATA%\Microsoft\Windows\Start Menu\Programs\` + `%APPDATA%\WayPlank\launchers\` on Windows.
4. **Sandbox / Package Exports:** `~/.local/share/flatpak/exports/share/applications`, `/var/lib/flatpak/exports/share/applications`, `/var/lib/snapd/desktop/applications` on Freedesktop; UWP `PackageManager` `AUMID` catalog on Windows.
5. **System Applications Directories:** `/usr/local/share/applications` and `/usr/share/applications` on Freedesktop; `%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\` on Windows.
6. **Pinned Folder Drawer Directories:** Every directory pointed to by a `FileDockItem` drawer in `<config>/wayplank/dock*/launchers/*.dockitem` (and its 1st-level non-hidden subdirectories).

> [!WARNING]
> **Cross-OS Path & Launcher URI Invariants (`MOC-0.7.2-HAL-001` — Enforced by `BuildBin.sh` Firewall):**
> 1. **Never Check `path.has_prefix("/")` in Zone 1 Core:** Windows absolute paths (`C:\Program Files\...` or `\\server\share\...`) do not start with `'/'`. All 11 Core path checks (`ApplicationIdentity`, `ApplicationDiscovery`, `AppUsageService`, `DockItemPreferences`, `FileDockItem`, `DockItemProvider`, `ApplicationDockItemProvider`, `DragManager`, `IconChooserDialog`, `DrawingService`, `FolderMenuWindow`) MUST use **`GLib.Path.is_absolute(path)`** (plus `Hal.Runtime.expand_tilde(path)` before `File.new_for_path`).
> 2. **Virtual Launcher URIs (`aumid://` & `docklet://`):** `DockItem.is_valid()` and `DockItem.reset_fmonitor()` MUST delegate to `Hal.Apps.launcher_exists(Launcher)` and `Hal.Apps.monitor_launcher(Launcher)` rather than calling `File.new_for_uri(Launcher).query_exists()` directly, so UWP Store apps (`aumid://Microsoft.WindowsCalculator_8wekyb3d8bbwe!App`) validate cleanly alongside `file://` `.desktop` and `.lnk` items.

#### Indexing & `NoDisplay` Partitioning Dispositions:
Each discovered `AppDescriptor` is classified into one of four dispositions:
- **Disposition A (Standard Visible Application):** `!is_hidden`, `!is_nodisplay`, and non-empty `exec_command` (or `url_target != ""`). Indexed with `has_exec = true`, `is_nodisplay = false`.
- **Disposition B (Indexed `NoDisplay=true` WebApp):** `is_nodisplay == true` with `--app-id=`, `--app=`, or `startup_wm_class_or_aumid` starting with `crx_`/`chrome-`/`brave-`/`msedge-`. Indexed with `has_exec = true`, `is_nodisplay = true`.
- **Disposition C (Indexed Exec-Less Template):** `is_nodisplay == true` and empty `exec_command` (e.g. `/usr/share/applications/qemu.desktop`). Indexed with `has_exec = false` so CLI processes matching its ID inherit its icon while triggering Phase 3 fallback synthesis.
- **Disposition D (Suppressed Helper Utility):** `is_nodisplay == true` **with** a non-empty `exec_command` (e.g. `org.gnome.Zenity.desktop`, `org.kde.kdialog.desktop`). Excluded from `identities`, and inserts into `suppressed_nodisplay_tokens`:
  1. `norm_base = normalize(basename)` and `normalize(startup_wm_class_or_aumid)`;
  2. The `exec_command` binary name `bin_name`, **strictly guarded by**:
     $$\text{norm\_base} == \text{bin\_name} \;\lor\; \text{norm\_base}.\text{has\_suffix}(\text{"."} + \text{bin\_name})$$
     *(This guard prevents `NoDisplay=true` sub-helpers such as `libreoffice-xsltfilter.desktop`, `okularApplication_pdf.desktop`, `vlc-openbd.desktop`, `kcm_*.desktop`, `gnome-*-panel.desktop`, and `com.microsoft.VSCode.UrlHandler.desktop` from adding shared parent binaries `libreoffice`, `okular`, `vlc`, `systemsettings`, `gnome-control-center`, or `code` to `suppressed_nodisplay_tokens`.)*
  3. **Post-Index Pruning:** After all visible Disposition A identities are indexed, every token present in any visible identity's $T_{\text{primary}}$ is removed from `suppressed_nodisplay_tokens` (`suppressed_nodisplay_tokens -= visible_primary_tokens`).

---

### 2.2 `Exec=` / `.lnk` Command Grammar, Cross-OS `\`-Safe `parse_command_argv`, Wrapper Unwrapping & Binary Tokenization

#### Step 1: Cross-OS Backslash-Safe Lexical Tokenization & Field Code Removal
1. Reads normalized fields from `AppDescriptor` (`display_name`, `startup_wm_class_or_aumid`, `exec_command`, `working_dir`, `url_target`, `is_terminal`, `sandbox_ids`).
2. For Snap desktop files named `<snap>_<app>.desktop` where `<snap> == <app>` (e.g. `firefox_firefox.desktop`), inserts `<snap>` into $T_{\text{primary}}$.
3. **Cross-OS Command-Line Tokenizer (`Hal.Runtime.parse_command_argv` — Fixes the POSIX `Shell.parse_argv` Backslash Trap):**
   - **Why Raw `GLib.Shell.parse_argv` Is Forbidden in Zone 1:** `GLib.Shell.parse_argv` implements POSIX `/bin/sh` escape rules where an unquoted or double-quoted single backslash `\` is consumed as an escape character — corrupting Windows command lines such as `"C:\Program Files\App\app.exe" --flag` into `"C:Program FilesAppapp.exe"` before `basename_any_slash()` can even inspect it!
   - **Translator Solution:** All command-line tokenization in `ApplicationIdentity`, `ApplicationDiscovery`, `Matcher`, and `RecentFilesService` routes through **`Hal.Runtime.parse_command_argv(cmd)`**: on `Freedesktop`, it applies standard XDG/POSIX quoting (preserving escaped Wine paths inside `.desktop` files); on `Windows`, it applies Win32 `CommandLineToArgvW` quoting rules where `\` is preserved literally as a path separator unless immediately preceding `"`!
   - Strips Freedesktop field codes (`%f`, `%F`, `%u`, `%U`, `%i`, `%c`, `%k`, `%d`, `%D`, `%n`, `%N`, `%v`, `%m`) and Flatpak forwarding markers (`@@`, `@@u`).

#### Step 2: Recursive Wrapper Unwrapping (`unwrap_command_string`)
The engine recursively unwraps up to 6 layers of command prefixes:

```mermaid
flowchart LR
    RAW["Raw exec_command: sh -c 'TMPDIR=/tmp firejail /usr/bin/blender %f'"] --> P1["Layer 1: Shell Unwrap — Strip sh -c, split ; / && / ||, skip cd/mkdir/killall/cat"];
    P1 --> P2["Layer 2: Env & Wrapper Prefix Unwrap — Strip KEY=VAL, firejail, sudo, pkexec, gamemoderun"];
    P2 --> P3["Layer 3: Sandbox Unwrap — flatpak run --command=bin AppId / snap run"];
    P3 --> TARGET["Resolved Target Binary: /usr/bin/blender -> T_exec = blender, blender-bin"];
```

1. **Leading `KEY=VALUE` Assignment Stripping (With or Without `env`):** Any leading token containing `'='` that does not start with `'-'` (e.g. `TMPDIR=$HOME/.cache/matlab-tmp`, `BAMF_DESKTOP_FILE_HINT=...`, `WINEPREFIX=...`) is stripped at every unwrapping layer (capturing `WINEPREFIX` into `I.wine_prefix`).
2. **Shell Wrappers (`sh`, `bash`, `zsh`, `dash` with `-c`):** Splits the inner command string on `;`, `&&`, and `||`, strips trailing shell control characters (`;`, `&`, `|`, fixing `xinput_calibrator; cat`), skips leading `KEY=VALUE` assignments and preparatory utility commands (`cd`, `mkdir`, `export`, `sleep`, `pidof`, `pgrep`, `killall`, `pkill`, `rm`, `touch`, `true`, `false`, `test`, `[`, `echo`, `exit`, `cat`), and promotes the primary execution statement.
3. **Execution & Sandbox Wrappers (`env`, `exec`, `sudo`, `pkexec`, `gksu`, `kdesu`, `nohup`, `setsid`, `nice`, `ionice`, `chrt`, `systemd-inhibit`, `firejail`, `bwrap`, `prime-run`, `gamemoderun`, `mangohud`, `optirun`, `primusrun`, `snap`, `flatpak-spawn`, `distrobox-enter`, `toolbox`, `gtk-launch`):** Strips the wrapper binary and its leading option flags.
4. **Flatpak (`flatpak run`):** Extracts `--command=<cmd>` via `add_executable_token(<cmd>)` and promotes the Flatpak application ID as the unwrapped command token.
5. **User `.sh` / `.bat` / `.cmd` Wrapper Inspection (`inspect_script_file`):**
   - **Strict `.sh` Extension Gate (`v0.6.2.1` Invariant):** Only when the unwrapped executable path ends with **`.sh`** (`raw_exe.has_suffix(".sh")`) and is $< 16\text{ KB}$ does the engine inspect the script body. Extensionless system startup scripts (`/opt/google/chrome/google-chrome`, `/usr/bin/firefox`, `/usr/local/SCILAB/.../bin/scilab`, `/usr/games/quake2`) are **never** opened as user wrapper scripts.

#### Step 3: Binary Stem Normalization & Alias Expansion (`add_executable_token`)
1. **Universal Slash & Backslash Basename Extraction (`basename_any_slash`):** Normalizes Windows backslashes (`\` $\rightarrow$ `/`) and strips trailing `;`, `&`, `|` before extracting the lowercase filename after the last `/`.
2. **Extension, Architecture & Version Stripping (`strip_script_ext`):**
   - Strips `.sh`, `.py`, `.pl`, `.rb`, `.lua`, `.js`, `.mjs`, `.cjs`, `.jar`, `.asar`, `.appimage`, `.flatpak`, `.snap`, `.desktop`, `.lnk`, `.url`, `.exe`, `.msi`, `.bat`, `.cmd`, `.run`, `.bin`, `.vmx`, `.vbox`, `.ova`, `.ovf`, `.iso`.
   - Strips architecture suffixes (`-x86_64`, `-amd64`, `-arm64`, `-aarch64`, `-i386`, `-linux`, `-appimage`) and version suffixes (`[-_vV]+[0-9]+(\.[0-9]+)*.*$`).
3. **`-bin` Bidirectional Pairing & Underscore/Hyphen Canonicalization (`canon_sep`):**
   - Pairs `<stem>` $\leftrightarrow$ `<stem>-bin`.
   - Treats `_` and `-` as equivalent separators (`canon_sep(s) = s.replace("_", "-")`) when comparing reverse-DNS Wayland `app_id`s against binary/desktop stems (resolving e.g. `com.calibre_ebook.calibre.ebook_viewer` $\leftrightarrow$ `ebook-viewer`).
4. **Canonical Vendor Alias Table & Multi-Component Suite Flags:**
   - `code` $\leftrightarrow$ `com.microsoft.vscode`, `vscode`
   - `codium` $\leftrightarrow$ `vscodium`, `com.vscodium.codium`
   - `soffice.bin` / `soffice` $\leftrightarrow$ `libreoffice` (and when `exec_command` passes `--writer`, `--calc`, `--impress`, `--draw`, `--math`, or `--base`, synthesizes `libreoffice-<component>` into $T_{\text{wmclass}}$ and $T_{\text{primary}}$)
   - `steam://rungameid/<id>` $\rightarrow$ inserts `steam_app_<id>` into $T_{\text{primary}}$ and $T_{\text{args}}$.
   - `+set <var> <mod>` (idTech / Quake engine mod selector, where `<mod> != "base"`) $\rightarrow$ inserts `<mod>` into `required_mod_tokens` ($T_{\text{mod}}$), while skipping `-datadir <path>` and Java `-cp` / `-classpath <path>` values so shared data paths never pollute $T_{\text{args}}$.
   - Generic desktop category dispatchers (`exo-open --launch FileManager|WebBrowser|TerminalEmulator|MailReader`) are ignored as specialization arguments.

---

### 2.3 Live Process & Recent-Document Introspection (`ProcessSnapshot` & `RecentDocInfo`)

1. **Per-PID Cached `ProcessSnapshot` (`Hal.Apps.inspect_process(pid)`):** Queries `/proc/<pid>/{cmdline,comm,environ,children}` via `LinuxProcessInspector` on Linux (`sysctl` on BSD, `QueryFullProcessImageNameW` + PEB `CommandLine` on Windows) once per PID (`pid_snapshot_cache`). Because the Linux kernel truncates `comm` to 15 bytes (`TASK_COMM_LEN - 1`), any `executable_comm` of length $\ge 15$ is compared as a 15-character prefix against $T_{\text{exec}}$.
2. **Cross-OS Recent Documents (`Hal.Apps.get_recent_documents()` $\rightarrow$ `RecentDocInfo`):** `RecentFilesService` queries `Hal.Apps.get_recent_documents()` (backed by `Gtk.RecentManager` on Freedesktop and `%APPDATA%\Microsoft\Windows\Recent\*.lnk` on Windows) and matches `RecentDocInfo.app_exec` using `Hal.Runtime.parse_command_argv()`.

---

### 2.4 The 5-Stage Standard Matching Algorithm (`Exec` ↔ Process & Window)

For a standard unspecialized launcher $I$ (`!I.is_specialized()` and `!I.has_browser_executable`), `match_score(W)` first applies the **Multi-Component Suite Disjointness Guard** and then evaluates five stages:

- **Pre-Stage Multi-Component Suite Disjointness Guard (`LibreOffice`):**
  If $I$ is a component of a multi-component suite (`"libreoffice"` or `"soffice.bin"` $\in I.T_{\text{exec}}$) and declares `StartupWMClass` ($I.T_{\text{wmclass}} \neq \emptyset$), and $W$ reports a non-generic component ID $w \in W_{\text{ids}} \setminus \{\texttt{"soffice"}, \texttt{"soffice.bin"}, \texttt{"libreoffice"}\}$ that does not intersect $I.T_{\text{wmclass}}$, then **`S(I, W) = 0`** immediately (preventing `libreoffice-calc.desktop` from scoring `90` via shared `soffice.bin` on a `libreoffice-writer` window, while never penalizing single-app binaries like `code` or `MATLAB` whose X11/Java `WM_CLASS` differs from `StartupWMClass`).
- **Stage 1 — Structural Surface Identity (`Score 95–100`):**
  If any $w \in W_{\text{ids}}$ (with `.exe` stripped and `_` $\leftrightarrow$ `-` canonicalized) or reverse-DNS base segment matches $I.\text{normalized\_id}$, $I.\text{base\_id}$, or any $p \in I.T_{\text{primary}}$: **`S(I, W) = 100`** (or **`95`** on $\ge 4$-char hyphen/dot prefix match).
- **Stage 2 — `Exec=` Binary vs. Window Class (`Score 90`):**
  If any $w \in W_{\text{ids}}$ (or its `-bin` stripped / `_` $\leftrightarrow$ `-` canonicalized stem) is in $I.T_{\text{exec}}$: **`best = max(best, 90)`**.
- **Stage 3 — `Exec=` Binary vs. Process `full_cmdline` (`Score 85–90`):**
  Unwraps $W.\text{Cmdline}$ via `unwrap_command_string()`. If the unwrapped primary binary basename $b_0 \in I.T_{\text{exec}}$: **`best = max(best, 90)`** (or **`85`** for a non-generic secondary token $b_i \in I.T_{\text{exec}}$).
- **Stage 4 — `Exec=` Binary vs. Process `executable_comm` (`Score 80`):**
  If $\text{normalize}(W.\text{Executable}) \in I.T_{\text{exec}}$ (or matches by 15-character kernel truncation prefix): **`best = max(best, 80)`**.
- **Stage 5 — Unicode Word-Boundary Title Match (`Score 60–90`):**
  - Requires that $I.\text{Name}$ is not in the generic desktop noun stopword set:
    $$G_{\text{stop}} = \{ \texttt{application}, \texttt{app}, \texttt{desktop}, \texttt{window}, \texttt{viewer}, \texttt{player}, \texttt{client}, \texttt{editor}, \texttt{manager}, \texttt{settings}, \texttt{preferences}, \texttt{configuration}, \texttt{system}, \texttt{utility}, \texttt{tool}, \texttt{terminal}, \texttt{console}, \texttt{browser}, \texttt{web}, \texttt{internet}, \texttt{network}, \texttt{file}, \texttt{files}, \texttt{folder}, \texttt{document}, \texttt{documents}, \texttt{media}, \texttt{video}, \texttt{audio}, \texttt{music}, \texttt{image}, \texttt{photo}, \texttt{camera}, \texttt{disks}, \texttt{game}, \texttt{games}, \texttt{launcher}, \texttt{server}, \texttt{service}, \texttt{helper}, \texttt{daemon} \}$$
  - Exact `normalize(W.Caption) == normalize(I.Name)` ($\ge 4$ chars, $\notin G_{\text{stop}}$) $\rightarrow$ **`90`**.
  - Multi-word `I.Name` matched at non-alphanumeric boundaries (`contains_word`) $\rightarrow$ **`75`**.
  - Distinctive word token $w \in I.T_{\text{words}}$ ($\ge 5$ chars, $\notin G_{\text{stop}}$) matched via `contains_word` $\rightarrow$ **`60`**.

---

### 2.5 Multi-Launcher Equivalence & Sibling Co-Illumination (`shares_application_with`)

Two identities $I_1, I_2$ represent the same underlying application ($\text{shares\_application\_with}(I_1, I_2) = \text{true}$) if and only if **all three** conditions hold:

1. **Unspecialized Invariant:**
   $$\neg I_1.\text{is\_specialized}() \;\land\; \neg I_2.\text{is\_specialized}()$$
2. **`StartupWMClass` Cross-Primary Compatibility Guard:**
   If both $I_1$ and $I_2$ explicitly declare `StartupWMClass` ($I_1.T_{\text{wmclass}} \neq \emptyset \land I_2.T_{\text{wmclass}} \neq \emptyset$), at least one's `StartupWMClass` must intersect the other's `StartupWMClass` **or `primary_tokens`**:
   $$(I_1.T_{\text{wmclass}} \cap (I_2.T_{\text{wmclass}} \cup I_2.T_{\text{primary}}) \neq \emptyset) \;\lor\; (I_2.T_{\text{wmclass}} \cap (I_1.T_{\text{wmclass}} \cup I_1.T_{\text{primary}}) \neq \emptyset)$$
3. **Shared Dedicated Binary, Class, or Plain Browser Witness:**
   $$(I_1.T_{\text{dedicated}} \cap I_2.T_{\text{dedicated}} \neq \emptyset) \;\lor\; (I_1.T_{\text{wmclass}} \cap I_2.T_{\text{wmclass}} \neq \emptyset) \;\lor\; (\text{both are plain unspecialized browsers sharing } b \in I_1.T_{\text{exec}} \cap I_2.T_{\text{exec}})$$

---

### 2.6 Unmatched Process Fallback Synthesis (`.desktop` / `.lnk`) & Garbage Collection

When $\max_{I \in \mathcal{I}_{\text{exec}}} S_{\text{eff}}(I, W) < 50$ and $\neg\text{is\_suppressed\_nodisplay\_window}(W)$:
1. Resolves FUSE AppImage mounts (`/tmp/.mount_*`) to the permanent host path via cached `env_appimage` in `ProcessSnapshot`.
2. Synthesizes `~/.local/share/applications/wayplank-app-<slug>.desktop` on Linux/BSD (or `%APPDATA%\WayPlank\launchers\wayplank-app-<slug>.lnk` via `IShellLinkW::Save` on Windows) through `Hal.Apps.synthesize_fallback_launcher()`, with `per_instance = true` when $W$ matched an Exec-less template like `qemu.desktop` or carries `-name <instance>`, and `per_instance = false` with `StartupWMClass=<W.ResourceClass>` otherwise.
3. Automatically garbage-collects unpinned synthetic launchers via `Hal.Apps.delete_synthesized_launcher()` when their window count drops to `0`.

---

## 3. The Specialized & Multiplexed Runtime Engine (Advanced Isolation, Scoring & Selection)

### 3.1 Specialization Model (`is_specialized`) & The `>= 115` Canonical Override Rule

#### Static Specialization (`I.is_specialized()`):
$$\text{is\_specialized}(I) \iff (I.\text{pwa\_id} \neq \text{""}) \lor (I.\text{web\_app\_host} \neq \text{""}) \lor I.\text{is\_browser\_url\_bookmark} \lor I.\text{is\_non\_app\_desktop} \lor (|I.T_{\text{args}}| > 0) \lor (|I.T_{\text{mod}}| > 0) \lor (|I.\text{required\_browser\_args}| > 0) \lor I.\text{requires\_incognito} \lor (I.\text{wine\_prefix} \neq \text{""})$$

#### Dynamic Terminal-Hosted Override (`window_has_terminal_command(W)`):
When a terminal emulator window is invoked with a command payload (e.g. `konsole ... -e /bin/bash /usr/share/updatesys/UpdateSys.sh`), even an **unspecialized** launcher $I$ (`updatesys.desktop` with `Exec=updatesys`, $T_{\text{args}} = \emptyset$) dynamically scores **`118` (`>= 115`)** when its dedicated binary or stem matches the terminal's hosted payload. Therefore, whenever `window_has_terminal_command(W)` is `true`, `ApplicationDiscovery` scans **all** non-terminal identities (not only static `specialized_exec_identities`) for scores $\ge 115$.

---

### 3.2 Single-Process Browser, PWA & Event-Driven Multi-Profile Isolation (`Chrome:<Profile>`)

```mermaid
flowchart LR
    WIN_BR["New Browser Window W — Shared Master PID on Wayland / Windows"] --> TRANS["Hal.Bus.AppMenu (IAppMenuBus Translator): dbusmenu id=61 + /proc/PID/fd + Local State vs UIAutomation / HWND"];
    TRANS -->|"Normalized Profile Name"| LOCK["Zone 1 ApplicationIdentity: window_browser_profiles[W.Id] = Profile & Chrome:ProfileName Tooltip"];
```

1. **Installed Browser Binary Resolution (`Hal.Apps.find_installed_browser_binary`):** Replaces hardcoded `/opt/google/chrome/google-chrome` filesystem checks when resolving wrapper executables across Linux/BSD (`/opt/google/chrome`, `/usr/bin/chromium`, etc.) and Windows (`%ProgramFiles%\Google\Chrome\Application\chrome.exe`, `msedge.exe`, `brave.exe`).
2. **Five Disjoint Browser Launcher Classes:**
   - **Class B1 (URL Bookmark):** `Type=Link` / `URL=` or positional URL without `--app=`/`--app-id=`/profile flags $\rightarrow$ **$S(I, W) = 0$ always**.
   - **Class B2 (Standalone PWA / Extension):** `--app-id=<id>`, `StartupWMClass=crx_<id>` / `chrome-<id>-*`, or **`--app=chrome-extension://<id>/...`** (`extension://`, `moz-extension://`, extracting `<id>` into `pwa_id` and clearing `required_browser_args`) $\rightarrow$ matches chromeless windows ($\neg\text{is\_plain\_browser\_window}(W)$) with **`124`** (exact profile match on $W$'s window ID), **`119`** (shared-PID profile mismatch fallback, resolved in $S_{\text{eff}}$ to `0` if a `124` launcher exists on disk or promoted to `120` otherwise), or **`120`** (profile-neutral).
   - **Class B3 (`--app=URL` Web-App):** `--app=http(s)://<host>/...` $\rightarrow$ matches chromeless windows by host (`120`) or brand/title (`118`), and is promoted in $S_{\text{eff}}$ to `direct_owner_score` (`120` or `124`) when co-matching (`matches_web_app_identity`) a Class B2 owner.
   - **Class B4 (Specialized Browser Wrapper & Multi-Profile Isolation):** `!is_web_app()` with `required_browser_args` (`--profile-directory=`, `--user-data-dir=`, `-P`, `--profile=`, `--user-agent=`, `--class=`), `requires_incognito`, or `.dockitem` `BrowserProfile` $\rightarrow$ requires $\text{is\_plain\_browser\_window}(W) = \text{true}$ **AND** every required browser flag (`Score = 118` / `120`, else `0`). When multiple Chrome/Chromium/Brave windows share a single browser PID across different profiles (`Default`, `Profile 1`, etc.), `Hal.Bus.AppMenu` resolves each window's profile, and `ApplicationIdentity` locks `window_id -> profile` and formats hover tooltips as `Chrome:<ProfileName>`.
   - **Class B5 (Standard Plain Browser):** `!is_web_app()` with zero isolating flags $\rightarrow$ requires $\text{is\_plain\_browser\_window}(W) = \text{true}$ (`Score = 100`, else `0`).

---

### 3.3 Terminal-Hosted Command Execution Specification (`-e`, `--`, `-x`, `Terminal=true`)

1. **Canonical Terminal Emulator Binary Set $B_{\text{term}}$:**
   `konsole`, `gnome-terminal`, `gnome-terminal-server`, `xfce4-terminal`, `ptyxis`, `kgx`, `foot`, `footclient`, `ghostty`, `alacritty`, `kitty`, `tilix`, `terminator`, `xterm`, `uxterm`, `koi8rxterm`, `urxvt`, `rxvt`, `wezterm`, `wezterm-gui`, `mate-terminal`, `lxterminal`, `qterminal`, `sakura`, `guake`, `yakuake`, `terminology`, `deepin-terminal`, `st`, `x-terminal-emulator`, `tilda`, `contour`, `rio`, `warp-terminal`, `wt`, `cmd`, `powershell`, `pwsh`.
2. **Multi-Terminal Payload Extraction (`extract_terminal_command_payload`):**
   - Inspects $W.\text{Cmdline}$ after `-e`, `--command`, `--command=*`, `-e=*`, `-x`, `--`, `/c`, `/k`, or positional command arguments in `foot`/`kitty`.
   - For single-instance terminal servers (`gnome-terminal-server` or `WindowsTerminal.exe`), inspects `ProcessSnapshot.child_cmdlines` when the server hosts a non-interactive script command.
   - Peels intermediate `sh`, `bash`, `zsh`, `dash`, `fish`, `env`, `sudo`, `pkexec`, `nohup`, `-c` tokens to extract `(payload_base, payload_stem)`.
3. **Scoring Rule:**
   - **Interactive Terminal (`payload_stem == ""`):** Non-terminal launchers score **`0`**; Pure Terminal Launcher (`org.kde.konsole.desktop` / `wt`) scores **`100`**.
   - **Hosted Command Terminal (`payload_stem != ""`):** Any non-terminal launcher $I$ (`!I.is_terminal_launcher()`) whose $T_{\text{dedicated}} \cup T_{\text{args}} \cup \{I.\text{base\_id}, I.\text{normalized\_id}\}$ contains `payload_stem` or `payload_base` scores **`118` (`>= 115`)**, overriding the terminal emulator (`100`).

---

### 3.4 Generic Runtime & Container Specification (Interpreters, VMs, Wine/Win32)

For any specialized runtime/container launcher $I$ invoking $b \in B_{\text{runtime}}$ (`wine`, `wine-stable`, `wine-staging`, `wine-devel`, `wine32`, `wine64`, `start.exe`, `explorer.exe`, `playonlinux`, `bottles`, `bottles-cli`, `umu-run`, `proton`, `python*`, `java*`, `vmware`, `vmplayer`, `virtualboxvm`, `qemu-system-*`):
1. **Guard 1 (`base_app_matches`):** $W$ must match $I$'s runtime/binary family (including 15-char `wine64-preloade` prefix).
2. **Guard 2 (`required_mod_tokens` Conjunction):** If $I.T_{\text{mod}} \neq \emptyset$ (e.g. `+set game rogue`), **all** $m \in I.T_{\text{mod}}$ must appear in $W.\text{Cmdline}$ (`Score = 118`, else `0`).
3. **Tier 1 — Explicit `StartupWMClass` Match (`Score = 120`):** Any $w \in W_{\text{ids}}$ (with `.exe` stripped) matches $I.T_{\text{wmclass}}$ (`alliance.exe`, `pinball.exe`, `rayman3.exe`, `burracoepinelle.exe`).
4. **Tier 2 — Disjunctive Target Stem / `Path=` Leaf Match (`Score = 116..118`):** Any $a \in I.T_{\text{args}}$ (either the `\`-normalized `.exe`/`.lnk`/`.vmx` stem **or** the `working_dir` leaf directory name, e.g. `"burracoepinelle"`) matches $W.\text{Cmdline}$ or $W_{\text{ids}}$ (**`118`**) or word-bounded $W.\text{Caption}$ (**`116`**).
5. **Tier 3 — Per-PID Cached `WINEPREFIX` Match (`Score = 116`):** $I.\text{wine\_prefix}$ equals `env_wineprefix` in `ProcessSnapshot`.
6. **Rejection (`Score = 0`):** If none of Tiers 1–3 hold, returns **`0`**.

---

### 3.5 Master Scoring Function $S(I, W)$, Effective Score $S_{\text{eff}}(I, W)$ & Selection Criteria

#### 3.5.1 Complete Hierarchy of Scores $S(I, W) \in [0, 124]$

| Score $S(I, W)$ | Category | Triggering Condition |
| :---: | :--- | :--- |
| **`124`** | **PWA + Exact Window Profile** | $I.\text{pwa\_id}$ matches $W$, and $\text{eff\_profile}(I)$ matches $W$'s compositor window ID profile suffix |
| **`120`** | **Exact Specialized Match** | • PWA match with no profile conflict (or promoted from `119` when sole launcher)<br>• `--app=URL` host match in $W_{\text{ids}}$ / $W.\text{Cmdline}$<br>• Specialized runtime/Wine `StartupWMClass` match (`explicit_wm_class_matched`) |
| **`119`** | **PWA Shared-PID Profile Fallback** | $I.\text{pwa\_id}$ matches $W$ with different window profile suffix (resolved in $S_{\text{eff}}$ to `0` if a `124` launcher exists, else `120`) |
| **`118`** | **Verified Wrapper / Payload / Arg** | • Specialized browser wrapper ($B4$) matching **ALL (`AND`)** `required_browser_args` on a plain browser window<br>• Terminal `-e` / `--` / `-x` / child-PID `<payload>` match on a non-terminal launcher<br>• `--app=URL` chromeless title/brand match<br>• Specialized runtime/Wine/VM target stem or `working_dir` leaf match in $W.\text{Cmdline}$ / $W_{\text{ids}}$ |
| **`116`** | **Specialized Title / `WINEPREFIX`** | • Specialized runtime target stem match in word-bounded $W.\text{Caption}$<br>• Wine launcher `I.wine_prefix` match against `ProcessSnapshot.env_wineprefix` |
| **`100`** | **Stage 1 Canonical Primary Match** | Unspecialized launcher matching $W_{\text{ids}}$ on `normalized_id`, `base_id`, `primary_tokens`, or `startup_wm_classes` |
| **`90`–`95`** | **Stage 1b / Stage 2 / Stage 3** | Prefix/suffix match on $W_{\text{ids}}$ (`95`), $W_{\text{ids}} \cap I.T_{\text{exec}} \neq \emptyset$ (`90`), or unwrapped `argv[0]` basename in $I.T_{\text{exec}}$ (`90`) |
| **`80`–`85`** | **Stage 3b / Stage 4 Process Match** | Secondary `Cmdline` token in $I.T_{\text{exec}}$ (`85`) or `executable_comm` (including 15-char prefix) in $I.T_{\text{exec}}$ (`80`) |
| **`60`–`90`** | **Stage 5 Title Word-Boundary Match** | Non-generic `Caption == Name` (`90`), multi-word `Name` via `contains_word` (`75`), or $\ge 5$-char word token via `contains_word` (`60`) |
| **`0`** | **Rejected (`< 50` or Guard Failure)** | Unmet specialization constraint, multi-component `StartupWMClass` conflict, URL bookmark ($B1$), or score $< 50$ |

#### 3.5.2 Effective Score $S_{\text{eff}}(I, W)$ & Priority Tie-Break Rank $\text{Rank}(I)$
1. **Cross-Candidate Effective Score $S_{\text{eff}}(I, W)$:**
   - Resolves `119` $\rightarrow$ `0` (if $\exists J$ with $S(J, W) \ge 124$) or `120` (if no `124` launcher exists).
   - Propagates `direct_owner_score = max(120, S(J, W))` (`120` or `124`) to any `--app=URL` launcher $I$ that satisfies `I.matches_web_app_identity(J)`.
2. **Priority Tie-Break Rank $\text{Rank}(I) \in \{0, 1, 2, 3\}$:**
   $$\text{Rank}(I) = \begin{cases} 3 & \text{if } I.\text{uri} \in \text{pinned\_launcher\_uris} \text{ (Pinned on Main Dock)} \\ 2 & \text{if } I.\text{uri} \in \text{drawer\_file\_uris} \text{ (Inside a Pinned Folder Drawer)} \\ 1 & \text{if } \neg I.\text{is\_nodisplay} \text{ (Standard Visible Launcher)} \\ 0 & \text{if } I.\text{is\_nodisplay} \text{ (Hidden `NoDisplay=true` Launcher)} \end{cases}$$
3. **Universal Override Probe in `best_desktop_file_for_window(W)`, `active_launcher_ids()`, and `is_best_launcher_for_window(I_my, W)`:**
   - Checks `specialized_exec_identities` (plus all non-terminal identities when `window_has_terminal_command(W)` is `true`) for $S_{\text{eff}}(J, W) \ge 115$. When `true`, preempts the $O(1)$ `100`-point Canonical Fast-Path.

---

### 3.6 Normative Compliance & 10-Iteration Invariant Verification Matrix

| # | Invariant / Community Reference | Formal Mechanism in This Specification | 10-Iteration Simulator Status |
| :-: | :--- | :--- | :---: |
| **1** | **[Issue #6](https://github.com/sergiomelas/WayPlank/issues/6)** — Word-boundary title matching (*Gram* vs *Instagram*) & generic noun stopword filter (*Find in Files* vs *GNOME Files*) | Stage 5 `contains_word()` non-alphanumeric boundary + expanded $G_{\text{stop}}$ (`files`, `settings`, `terminal`, `disks`, `camera`). | ✅ **Verified (`0` errors)** |
| **2** | **[Issue #9](https://github.com/sergiomelas/WayPlank/issues/9) & [#20](https://github.com/sergiomelas/WayPlank/issues/20)** — Browser profiles (`--profile-directory`, `--user-data-dir`, `-P`, `--profile`, `--class`, `--user-agent`) & URL bookmarks | Class B1 (`0` score) + Class B4 strict `AND` conjunction across all `required_browser_args` + `.dockitem` `BrowserProfile`. | ✅ **Verified (`0` errors)** |
| **3** | **[Issue #14](https://github.com/sergiomelas/WayPlank/issues/14)** — CLI QEMU Multi-VM discovery, instance isolation & garbage collection | Disposition C Exec-less template (`qemu.desktop`) + Section 2.6 `per_instance = true` synthesis + `gc_synthetic_launchers()`. | ✅ **Verified (`0` errors)** |
| **4** | **[PR #15](https://github.com/sergiomelas/WayPlank/pull/15)** — Flatpak `@@` delimiters, `--command=` unwrapping, `X-Flatpak` & `-bin` pairing | Section 2.2 Step 1–3 Flatpak unwrapper + `X-Flatpak` primary token + bidirectional `-bin` registration. | ✅ **Verified (`0` errors)** |
| **5** | **[Issue #16](https://github.com/sergiomelas/WayPlank/issues/16)** — CLI GUI (`Obsidian`), AppImage `APPIMAGE=` FUSE resolution & Phase 3 `NoDisplay=true` helper suppression | Phase 3 `is_suppressed_nodisplay_window(W)` gate + Disposition D `norm_base == bin_name` guard & visible pruning + per-PID cached `env_appimage`. | ✅ **Verified (`0` errors)** |
| **6** | **`v0.6.2.1` Invariant** — System startup scripts (`/opt/google/chrome/google-chrome`, `firefox`, `scilab`, `quake2`) never opened as user `.sh` wrappers | Section 2.2 Step 2 strict `.sh` suffix gate (`raw_exe.has_suffix(".sh")`) preserved 100% intact. | ✅ **Verified (`0` errors)** |
| **7** | **`FAT 1.11` Sibling Co-Illumination & Multi-Component Isolation** — `code.desktop` ↔ `com.microsoft.VSCode.desktop`, `MATLAB` ↔ `MATLAB R2024a`, `LibreOffice Writer` $\neq$ `Calc`, `Quake 2` mods | Section 2.2 leading `KEY=VAL` unwrap + Section 2.4 Pre-Stage suite guard + Section 2.5 Cross-Primary `StartupWMClass` compatibility guard + `required_mod_tokens`. | ✅ **Verified (`0` errors)** |
| **8** | **Shared-PID Browser Wrapper vs. PWA (`winchrome-syensqo.sh` vs `YouTube` / `Gmail`)** | Section 3.2 `is_plain_browser_window` gate (`0` for B4/B5 on chromeless windows) + `119` $\rightarrow$ `120` shared-PID fallback + `direct_owner_score = 124` co-match symmetry + `Rank(Drawer) = 2 > Rank(NoDisplay) = 0`. | ✅ **Verified (`0` errors)** |
| **9** | **Browser Extension Popups (`--app=chrome-extension://<id>/...` — `ExpressVpn`, `Norton`, `SurfShark`)** | Section 3.2 Class B2 extraction of `<id>` from `chrome-extension://` into `pwa_id` and clearing of `required_browser_args`. | ✅ **Verified (`0` errors)** |
| **10** | **Terminal-Hosted Scripts (`updatesys.desktop` / `konsole -e`, `gnome-terminal --`, `xfce4-terminal -x`, `foot`, `Terminal=true`) vs. Interactive `Konsole`** | Section 3.3 multi-terminal & child-PID payload extraction scoring `118 >= 115` with universal override probe vs `0` on interactive terminals. | ✅ **Verified (`0` errors)** |
| **11** | **Wine, PlayOnLinux, Bottles & VMware Containers (`Burraco`, `Rayman 3`, `X-Wing`, `3DPinball`, `NFS III`)** | Section 3.4 $B_{\text{runtime}}$ expansion + Tier 1 `StartupWMClass` (`120`) + Tier 2 disjunctive `\`-normalized stem / `working_dir` leaf (`118`) + Tier 3 cached `env_wineprefix` (`116`). | ✅ **Verified (`0` errors)** |
