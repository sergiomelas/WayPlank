# WAYPLANK: THE ROAD TO WAYLAND DOCK

> A lightweight native Wayland dock, forked and modernized from Plank.
>
> Maintained by Sergio Melas (sergiomelas@gmail.com) © 2026
>
> [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
> [![Current Live Release: v0.7.0 (Public Beta 1)](https://img.shields.io/badge/Live_on_GitHub-v0.7.0_%28Public_Beta_1%29-brightgreen.svg)](Changelogs/CHANGELOG_v0.7.0.md)
> [![Next Release: v0.7.1 (Public Beta 2)](https://img.shields.io/badge/Next_Release-v0.7.1_%28Public_Beta_2%29-orange.svg)](README.md)
> [![FAT: 100% Passed (377/377)](https://img.shields.io/badge/FAT_Status-100%25_PASS_%28377%2F377%29_%7C_379_Points-brightgreen.svg)](FAT/2026-11-04%20FAT%200.7.0.txt)
> [![Localization: 8 Languages (100% In-RAM)](https://img.shields.io/badge/Localization-8_Languages_%28487%2F487_In--RAM%29-blueviolet.svg)](po/README.md)
> [![Architecture: 100% Monolithic Single Binary](https://img.shields.io/badge/Architecture-Single_Binary_%7C_Zero_Host_Pollution-informational.svg)](README.md)

![Wayplank Release Banner](Beta%20Release%20Pic%20-%20github.png)

> *📌 **Hotfix Update Note (`2026-11-04`):** While the release banner and package identifiers remain `v0.7.0`, an urgent  hotfix update was issued to squash critical post-launch regressions ([#16](https://github.com/sergiomelas/WayPlank/issues/16), [#17](https://github.com/sergiomelas/WayPlank/issues/17), [#18](https://github.com/sergiomelas/WayPlank/issues/18), and hover smoothness) and graduate the **Icons Visual Effects** animation suite — **100% FAT qualified (`377/377` applicable passed)**.*

> [!TIP]
> ## 🎉 WAYPLANK `v0.7.0` — PUBLIC BETA 1 IS OFFICIALLY LIVE!
> **The Alpha & Pre-Beta Engineering Era (`v0.1.0` $\longrightarrow$ `v0.6.2.3`) is permanently CLOSED, and the Public Beta Era begins today!**
>
> Across **16 consecutive milestone releases**, over **112,000 lines of legacy X11/Autotools code** have been purged, **115 unique functional & architectural bugs** have been squashed across **2,416 formal ISA-88 test definitions**, and all **`377 / 377` applicable FAT validation points (`379` defined: `354 [ok]` baseline + `23 [ko->ok]` squashed, `2 [NA]`, `0` open `[ko]` defects)** have achieved a **100% PASS** rate across **KDE Plasma 6 (KWin)**, **GNOME Shell (Mutter)**, and **Labwc (wlroots)**:
> - 🌍 **100% Automatic Monolithic In-Memory Localization Engine (`GResource`)**: **8 languages** compiled directly into the executable's RAM (**Simplified Chinese `zh_CN`**, **Italian `it`**, **Spanish `es`**, **French `fr`**, **Catalan `ca`**, **German `de`**, **Ukrainian `uk`**, and native **English `en`** — **`487 / 487` strings each**) with automatic OS locale detection and **zero files installed in `/usr/share/locale/`**.
> - 🎛️ **Configurable Category & Docklet Layout Engine (`Apps & Layout`)**: Place the **Docklets** group on the right immediately before the Trash in **System Tray style (`Docklets on Right`, default)** or on the left after Folders, with symmetric outer-edge Accordion collapsing (collapsing right when on the right, left when on the left), pair **WayPlank Always Left** (fixed far-left anchor with its own separator) alongside **Show Trash** (far-right anchor), and one-click **Align by Type** in Free Mode while preserving 100% seamless drag-to-pin/unpin across `[Pinned Apps] | [Unpinned Apps]`.
> - 🏛️ **Pure Single-Binary Monolithic Architecture**: **16 built-in docklets**, **6 dock themes**, **52 vector icons**, the **self-deploying GNOME Shell companion bridge (`version: 4`)**, the **KWin D-Bus ECMAScript bridge**, and **all 8 language catalogs** reside inside a single standalone `wayplank` binary.
> - 🖥️ **Tier-1 Multi-Compositor Parity & Native Packages**: Out-of-the-box runtime auto-detection across **KWin**, **Mutter**, and **Labwc**, shipped with automated **Debian/Ubuntu (`.deb`)** and **openSUSE/Fedora/RHEL (`.rpm`)** native builders!
> - 🗣️ **Community-Driven Public Beta (`v0.7.x` Open Through Up to Dec 31, 2026)**: The `v0.7.x` Public Beta series (`v0.7.1` Beta 2, `v0.7.2` Beta 3, ...) remains actively open until the community says we are ready for the `v0.8.x` feature freeze (with an upper deadline of **December 31, 2026**). **Tell us what features, workflows, and languages you want to see in WayPlank** via [GitHub Issues](https://github.com/sergiomelas/WayPlank/issues) and [Discussions](https://github.com/sergiomelas/WayPlank/discussions)!

---

> [!IMPORTANT]
> ### 📅 Master Release Roadmap & Milestone Schedule
> - 🚀 **v0.7.0 (Public Beta 1 — Current Live GitHub Release & Hotfix Consolidation)**: Officially live on GitHub with **100% multi-compositor FAT qualification** across KDE Plasma 6 (KWin), GNOME Shell (Mutter), and Labwc (wlroots) (`379` test points defined, `377/377` applicable passed: `354 [ok]` baseline + `23 [ko->ok]` squashed, `0` open `[ko]` defects, `2` `[NA]`), featuring the **100% Monolithic Embedded Localization Engine (`GResource`, 7 languages + English, `487/487` strings, Zero Host Pollution)**, the **Configurable Category & Docklet Layout Engine (`Apps & Layout` — `Docklets on Right` System Tray layout & `WayPlank Always Left` anchor)**, **Icons Visual Effects** (`300–1500 ms` `Effect Duration`), and GNOME Shell Bridge `version: 4`!
> - 🔄 **v0.7.x (Active Public Beta Series — `v0.7.1` Beta 2, `v0.7.2` Beta 3, ... | Community-Driven Window up to Dec 31, 2026)**: Active multi-week Public Beta cycle dedicated to community feature requests, iterative bug fixing, new language localizations, UX refinements, community PR integrations, and preliminary native Windows preview ([WinPlank](Documentation/WINPLANK_PORT_BATTLE_PLAN.md))—remaining open until the community says we are ready for the `v0.8.x` freeze (hard cap: **December 31, 2026**).
> - **v0.8.x (Release Candidate — RC Series)**: Following the completion of the `v0.7.x` Public Beta cycle, strict feature freeze, memory leak profiling, and distribution packaging hardening (.deb, .rpm, AUR).
> - **v0.9.x (Long-Term Production Stabilization)**: The official battle-tested production milestone for daily driving across all Linux distros and Windows 10, 11+.
> - **v1.0.0 (The Grand Milestone — ~2-Year Horizon)**: The long-term landmark celebrating proven stability and next-gen Wayland protocol standards.

---

> [!NOTE]
> ### 📢 Maintainer Announcement: Feature & Issue Freeze (Oct 30 Midnight – Nov 16)
> Please note that **Friday, October 30, 2026 at midnight (24:00 CET)** marked the final cut-off deadline for maintainer-implemented bug fixes and feature requests ahead of the **Public Beta (`v0.7.0`)** launch on **Monday, November 2, 2026**. All pre-cutoff issues ([#5](https://github.com/sergiomelas/WayPlank/issues/5), [#9](https://github.com/sergiomelas/WayPlank/issues/9), [#10](https://github.com/sergiomelas/WayPlank/issues/10), [#11](https://github.com/sergiomelas/WayPlank/issues/11), [#12](https://github.com/sergiomelas/WayPlank/issues/12), [#13](https://github.com/sergiomelas/WayPlank/issues/13), and [#14](https://github.com/sergiomelas/WayPlank/issues/14)) have been **100% resolved, verified `[ko->ok]` / `[ok]` across KWin, Mutter, and Labwc, and closed**.
> 
> Through **Monday, November 16, 2026 (Weeks 45–46)**, WayPlank enters a **2-week maintainer freeze & community testing runway** while the author focuses on upstream Linux kernel maintainer review cycles for the `yogafan` driver series in [**`sergiomelas/lenovo-linux-drivers`**](https://github.com/sergiomelas/lenovo-linux-drivers):
> 
> - 🛑 **Maintainer Issue Processing Paused Until Nov 16:** Issues and feature requests opened after the October 30 midnight deadline remain welcome in the tracker, but **will not be actively worked on by the maintainer until November 16, 2026**, with the **sole exception of critical disaster-recovery hotfixes** (e.g., startup crashes or severe blocker regressions).
> - 🚑 **First Emergency Hotfix Batch (`v0.7.0` Hotfix — Verified 100% PASS `[ko->ok]` on `2026-11-04`):** Resolved critical post-launch regressions across all 3 compositors: automatic dock surface & anchor self-healing after screen lock/unlock, idle, and DPMS monitor sleep/wake plus seamless `SIGWINCH` live reload upon `.deb` upgrades ([#18](https://github.com/sergiomelas/WayPlank/issues/18)), clickable edge-triggered SR Flip-Flop between `Reserve Screen Space`, `Hide Dock`, and `Icon Zoom` across GUI and `gsettings` ([#17](https://github.com/sergiomelas/WayPlank/issues/17)), CLI-launched GUI & AppImage window monitoring with zero-hardcoding dialog masking and Labwc main-PID scoring ([#16](https://github.com/sergiomelas/WayPlank/issues/16)), `.sh` profile wrapper (`116 >= 115`), `NoDisplay=true` Chrome PWA ↔ `--app=URL`, and sibling binary (`VS Code`, `MATLAB`, `Scilab`) co-matching & isolation, direct folder/launcher drag-and-drop onto both the dock `[Folders]` zone and open folder popups, VSync 3-Beat unpin pipeline (`SurfaceCoordinateService`), 60 FPS hover popup-event filtering & multi-size `SurfaceCache` (`0.1%` idle CPU), and graduation of **Icons Visual Effects** (`300–1500 ms` `Effect Duration`) to **Preferences → Behaviour**.
> - 🤝 **Door Wide Open for Community Contributors:** Community developers and translators are **warmly encouraged to step in**, investigate open issues, and submit Pull Requests or translation updates at any time (following our HAL & FAT qualification guidelines in [`CONTRIBUTING.md`](CONTRIBUTING.md))!
> - 🚀 **v0.7.x Public Beta Cycle Resumption (Nov 16 — `v0.7.1` Public Beta 2 & Beyond, up to Dec 31, 2026):** Full maintainer triage, PR merges, community translation integrations, and active Beta feature development will resume on **November 16, 2026** for the ongoing **`v0.7.x` Public Beta Series (`v0.7.1` Beta 2, `v0.7.2` Beta 3, etc.)**. **The Beta will remain actively open until the community says we are ready for the `v0.8.x` feature freeze (with a final deadline of December 31, 2026)—I genuinely want you to tell me what features, workflows, and improvements you want in WayPlank!**

---

> [!TIP]
> ### 🌍 Call for Translators — Help Localize WayPlank (`v0.7.x` Public Beta Series)!
> All WayPlank translations are maintained in a clean, self-contained Python generator script: [`po/generate_translations.py`](po/generate_translations.py).
> Complete 100% string coverage (`487/487` strings) is shipped in **Public Beta 1 (`v0.7.0`)** for **Simplified Chinese (`zh_CN`)**, **Italian (`it`)**, **Spanish (`es`)**, **French (`fr`)**, **Catalan (`ca`)**, **German (`de`)**, and **Ukrainian (`uk`)** (plus native **English (`en`)**).
>
> **Want to add your language (e.g. Portuguese, Polish, Japanese, etc.) or contribute?**
> 1. Open [`po/generate_translations.py`](po/generate_translations.py), where all 487 strings are stored in a simple, structured Python dictionary.
> 2. Add or update your language entries directly in the dictionary (much cleaner and easier to manage than raw `.po` files!).
> 3. Submit your updated `generate_translations.py` by opening a [GitHub Issue](https://github.com/sergiomelas/WayPlank/issues) or Pull Request for inclusion in upcoming `v0.7.x` / `v0.8.x` releases!

---

## 📢 Current Status

Plank was completely unmaintained and broken on Wayland. Wayplank brings it back to life with a native Wayland architecture using `gtk-layer-shell`, modular bridges for different compositors, while preserving the fast and clean Cairo rendering engine we all loved.

I get why it might look like slop at first glance, but this is done with professional rigor. Before dumping code, every single change and architecture shift goes through strict Factory Acceptance Testing—you can literally check the logs in the FAT/ folder to see how every version is systematically tested and verified.

AI is fantastic for rapid prototyping and bringing boilerplate up fast, but this isn't just 'vibe coding'; it's heavily human-reviewed, debugged, and architected for real stability across KWin, Labwc, and Mutter. It’s a robust, hobbyist-driven, native Wayland solution. All compositor features, window previews, and theming integrations are verified with total engineering transparency. Take it or leave it, enjoy the code!

With **Public Beta 1 (`v0.7.0`)**, WayPlank ships a mature, battle-tested Hardware Abstraction Layer (HAL) working out of the box on **KDE Plasma 6 (KWin)**, **GNOME Shell (Mutter)**, and **Labwc (wlroots)**—auto-detecting your compositor at startup with zero messy configuration, complete with live Cairo window preview cards, smart multi-zone app drawers, configurable docklet positioning (left or right System Tray style via `Docklets on Right` and `WayPlank Always Left` in `Apps & Layout`), 16 monolithic docklets, 8-language in-RAM localization, real-time dark/light theme switching, fullscreen inhibit, and panel mode. 

## 🤝 Acknowledgments & Contributors

WayPlank is proudly developed with and for the Linux Wayland community. A huge thank you to our 400+ users, issue reporters, and translators whose real-world feedback has helped squash 115 bugs across 379 validation points (100% FAT pass rate)!

* **史有虎 (IFtiger-hu)** ([@IFtiger-hu-hub](https://github.com/IFtiger-hu-hub)): Author of the WayPlank community fork, contributor of native openSUSE/Fedora/RHEL RPM packaging (`BuildRpm.sh`), dock overflow smooth scrolling architecture, and launcher deduplication engine.

### 🤝 How to Contribute & Community Roll of Honor

All community feature ideas, issue reporters, and translation authors are actively tracked and credited in our community roll of honor:
👉 Please see [**CONTRIBUTING.md**](CONTRIBUTING.md) for full contribution guidelines, active tracks, and the comprehensive issues & discussions matrix.


## 📖 Documentation

* 📚 [User Guide & Reference Manual](Documentation/USER_GUIDE.md)
* 🤝 [Contributing Guidelines & Community Tracks](CONTRIBUTING.md)
* 🌍 [Monolithic Localization & i18n Guide](po/README.md)
* 🖥️ [Compositors & Nested Desktops Cheatsheet](FAT/Test%20Files/WAYPLANK_COMPOSITORS_CHEATSHEET.md)
* 🗺️ [v0.6.2 Fork Integration Roadmap](Documentation/WAYPLANK_V062_FORK_INTEGRATION_ROADMAP.md)
* 📖 [Technical migration report](Documentation/wayplank_x11_to_wayland_report_en.md)
* 🛡️ [Lifetime Master Bug & Defect Register](FAT/WAYPLANK_LIFETIME_BUG_REGISTER.md)
* 🧪 [Compositor test matrix & protocols](FAT/)
* 📦 [Full technical changelogs](Changelogs/)

### 🎯 Compositor Support & Native HAL Architecture

WayPlank features a modular Hardware Abstraction Layer (HAL) with zero-configuration runtime auto-detection:

| Compositor / Desktop | Integration Engine | Key Capabilities | Status |
| :--- | :--- | :--- | :---: |
| **KDE Plasma 6 (KWin)** | D-Bus ECMAScript Bridge | Live Cairo window preview cards (`ScreenShot2` D-Bus IPC), `Bus.watch_name` bridge self-healing, bidirectional event tracking, atomic DRM `kscreen-doctor` brightness sync, real-time dark/light theme switching, Super+D Show Desktop persistence, 100% FAT pass | **Tier 1 (100% PASS)** |
| **GNOME Shell (Mutter)** | Monolithic Mutter Extension | Live Cairo window preview cards (`/mutter/screen/preview` IPC), 0.74s instant cold start, deterministic map activation (zero async timer crashes), native CSD HeaderBar dialogs, window Dodge/Intellihide, real-time dark/light theme switching, 100% FAT pass | **Tier 1 (100% PASS)** |
| **Labwc / wlroots** | `gtk-layer-shell` + `zwlr_foreign_toplevel` | Native C protocol bridge, Cairo blank preview cards with app icons & titles, Honest UI matrix, real-time dark/light theme switching, tested on LXQt 2.x & XFCE 4.20 Wayland | **Tier 1 (100% PASS)** |
| **Sway & Hyprland** | wlroots protocol extensions | Native layer-shell docking & workspace tracking | *In Roadmap* |

*For in-depth architectural details, protocol diagrams, and security model analysis, see [User Guide Chapter 9: Hardware Abstraction Layer (HAL)](Documentation/USER_GUIDE.md#9-hardware-abstraction-layer-hal--compositor-architecture).*

Feel free to star the repo or follow releases if you want to track progress!

---

> 🌟 **Compositor Qualification Status:** On KDE Plasma 6 (KWin), GNOME Shell (Mutter), and Labwc (wlroots), all 377/377 applicable FAT validation points (`379` defined: `354 [ok]` baseline + `23 [ko->ok]` squashed, `2 [NA]`, `0` pending `[  ]`, `0` open `[ko]` defects — **100% PASS**) are verified under the formal ISA-88 qualification protocol, including Fullscreen Inhibit & 0px Edge Click Passthrough (Issue #10), Reserve Screen Space / Panel Mode & SR Flip-Flop (Issues #9, #17), Show Desktop persistence (Issue #13), Workspace Switch visibility on Labwc/Mutter (Issue #11), Cold-Start HiDPI Fractional Scaling (Issue #5), CLI GUI / Multi-VM monitoring & zero-hardcoding dialog masking (Issues #14, #16), Screen Lock / DPMS self-healing (Issue #18), and Monolithic In-Memory Multi-Language Live Switching. Every validation point is documented with total engineering transparency in [`FAT/`](FAT/).

---

## 📸 Screenshots

![Wayplank Dock & Drawers Showcase](Screenshots/1.png)

<details>
<summary><b>🔍 Click to view full desktop integration (1920x1080), detail 1</b></summary>

<br>

![Wayplank Full Desktop](Screenshots/2.png)

</details>

<details>
<summary><b>🔍 Click to view full desktop integration (1920x1080), detail 2</b></summary>

<br>

![Wayplank Full Desktop](Screenshots/3.png)

</details>

<details>
<summary><b>🌍 Click to view native multi-language localization showcase (Simplified Chinese — zh_CN)</b></summary>

<br>

![WayPlank Multi-Language Localization Showcase](Screenshots/4.png)

</details>

---

# Universal Build & Installation Guide (Any Linux Distribution)

## 1. CORE DEPENDENCIES

To compile Wayplank from source and enable all docklets, ensure your distribution provides the required development libraries and runtime tools:

### Build Dependencies (Compiler & Headers):
- Vala compiler (`valac >= 0.40`)
- GTK+ 3.0 development headers (`gtk3` / `libgtk-3-dev`)
- GTK Layer Shell (`gtk-layer-shell` / `libgtk-layer-shell-dev`)
- Wayland Client library (`wayland` / `libwayland-client0` / `libwayland-dev`)
- JSON-GLib 1.0 (`json-glib` / `libjson-glib-dev`)
- LibGee 0.8 (`libgee` / `libgee-0.8-dev`)
- GLib 2.0 (`glib2` / `libglib2.0-dev`, includes `glib-compile-resources`)
- `pkg-config` / `base-devel` / `build-essential`

### Runtime Dependencies & Docklet Tools:
- **Screenshot Docklet (Labwc / wlroots / XFCE on Labwc):** `grim`, `slurp`
- **Screenshot Docklet (KDE Plasma):** `kde-spectacle`
- **Screenshot Docklet (XFCE / Generic X11):** `xfce4-screenshooter` or `flameshot`
- **Screen Brightness Docklet (Hardware control fallback):** `brightnessctl` (optional)

**Quick Install Commands:**
- **Debian / Ubuntu:**
  ```bash
  sudo apt install build-essential valac libgtk-3-dev libgtk-layer-shell-dev libwayland-dev libjson-glib-dev libgee-0.8-dev libglib2.0-dev grim slurp
  ```
- **Arch Linux:**
  ```bash
  sudo pacman -S --needed base-devel vala gtk3 gtk-layer-shell wayland json-glib libgee glib2 grim slurp
  ```
- **Fedora / RHEL:**
  ```bash
  sudo dnf install gcc vala gtk3-devel gtk-layer-shell-devel wayland-devel json-glib-devel libgee-devel glib2-devel grim slurp rpm-build
  ```
- **openSUSE (Tumbleweed / Leap):**
  ```bash
  sudo zypper install gcc vala gtk3-devel gtk-layer-shell-devel wayland-devel json-glib-devel libgee-devel glib2-devel grim slurp rpm-build
  ```

---

## 2. COMPILATION

### Option A: Universal Automated Build Script (Recommended for Any Distro)

Wayplank includes an automated standalone build script that compiles all Vala sources, C bridges, and GLib resources directly without distribution-specific dependencies:

```bash
chmod +x BuildBin.sh
./BuildBin.sh
```

The resulting standalone binary is generated in `build/wayplank`.

---

### Option B: Manual Step-by-Step Compilation

If you prefer building manually in your terminal *(note: `./BuildBin.sh` in Option A is recommended as it also automatically compiles and embeds all `po/*.po` localization catalogs into RAM via `GResource`)*:

```bash
# Step 1: Compile embedded GLib resources
glib-compile-resources --sourcedir=data --target=lib/resources.c --generate-source data/plank.gresource.xml

# Step 2: Compile native Wayplank binary (Vala + C bridges)
valac -g \
    --gresources=data/plank.gresource.xml \
    --gresourcesdir=data \
    --vapidir=vapi \
    --pkg posix --pkg gio-unix-2.0 --pkg gtk+-3.0 --pkg gtk-layer-shell-0 \
    --pkg json-glib-1.0 --pkg gee-0.8 --pkg compat --pkg config --pkg wlr-bridge \
    -X -D_GNU_SOURCE -X "-Dsetproctitle(x)=" \
    -X -DGETTEXT_PACKAGE=\"wayplank\" \
    -X -include -X include/config.h \
    -X -Ilib -X -Ilib/Protocols -X -Ilib/Services -X -Iinclude -X -w -X -lm -X -lwayland-client \
    $(find lib src -name "*.vala") \
    lib/resources.c \
    lib/gtk-compat.c \
    lib/Protocols/wlr-foreign-toplevel-management-protocol.c \
    lib/Services/wlr-toplevel-bridge.c \
    -o wayplank
```

---

### Step 3: Install Binary and Desktop Assets

Once built (via Option A or Option B), install the binary, themes, icons, and GSettings schemas:

```bash
# Install binary into /usr/local/bin
[ -f build/wayplank ] && sudo install -Dm755 build/wayplank /usr/local/bin/wayplank || sudo install -Dm755 wayplank /usr/local/bin/wayplank
sudo ln -sf /usr/local/bin/wayplank /usr/local/bin/plank

# Install themes and icons
sudo mkdir -p /usr/local/share/wayplank/themes
sudo cp -r data/themes/* /usr/local/share/wayplank/themes/
sudo cp -r data/icons/* /usr/local/share/icons/hicolor/

# Install and compile GSettings schemas
sudo cp data/glib-2.0/schemas/* /usr/local/share/glib-2.0/schemas/
sudo glib-compile-schemas /usr/local/share/glib-2.0/schemas/
```

---

## 3. AUTOMATED DEBIAN/UBUNTU PACKAGE CREATION

If running Debian, Ubuntu, or derivative distributions, run the automated packager to create a native `.deb`:

```bash
chmod +x BuildDeb.sh
./BuildDeb.sh
# Install with automatic dependency resolution:
sudo apt install ./build/wayplank_0.7.0_amd64.deb
# Or via dpkg:
# sudo dpkg -i build/wayplank_0.7.0_amd64.deb && sudo apt install -f
```

---

## 4. AUTOMATED OPENSUSE / FEDORA / RHEL RPM PACKAGE CREATION

If running openSUSE (Tumbleweed / Leap), Fedora, or RHEL-based distributions, run the automated RPM packager:

```bash
chmod +x BuildRpm.sh
./BuildRpm.sh

# Install on openSUSE with zypper:
sudo zypper install ./build/wayplank-0.7.0-1.x86_64.rpm

# Or install on Fedora/RHEL with dnf:
sudo dnf install ./build/wayplank-0.7.0-1.x86_64.rpm

# Or install via rpm directly:
sudo rpm -Uvh ./build/wayplank-0.7.0-1.x86_64.rpm
```

> 💡 **Headless / CI Environments:** You can bypass interactive prompts across all build scripts using `WAYPLANK_NO_PROMPT=1` (e.g. `WAYPLANK_NO_PROMPT=1 ./BuildRpm.sh`).

---

# RUNTIME DIRECTORIES & CONFIGURATION MIGRATION

Wayplank operates under its own isolated namespace and standard XDG locations:

- Configuration Directory: `~/.config/wayplank/`
- Application Launchers: `~/.config/wayplank/dock1/launchers/`
- Local User Themes: `~/.local/share/wayplank/themes/`
- System Themes: `/usr/share/wayplank/themes/` (or `/usr/local/share/wayplank/themes/`)

**Theme Configuration:**
Wayplank inspects both system and user theme paths natively. To change dock appearance:

```bash
wayplank --preferences
```

**Debug & Verbose Logging:**
To inspect running window hooks and debug output:

```bash
wayplank -d
```

---

# PROJECT ROADMAP & THE WAYLAND MILESTONES

- [x] Phase 1 (Completed) v0.1.0: Decoupled Standalone Fork
  - [x] Complete breakaway from unmaintained upstream Plank.
  - [x] Full namespace migration to 'wayplank' (configs, directories, launchers).
  - [x] Modern monolithic build system replacing broken autotools/autogen scripts.
  - [x] Multi-distro compatibility and standalone Debian packaging pipeline.

- [x] Phase 2 (Completed) v0.2.0: Application Discovery and Dock Lifecycle
  - [x] Implemented generic application discovery from running processes and desktop files.
  - [x] Added persistent pinned application handling and temporary running application icons.
  - [x] Implemented running-instance marking and multi-instance application management.

- [x] Phase 3 (Completed) v0.3.0: Declaration of Independence from X11 & Native Wayland Integration
  - [x] Implementation of Wayland native protocols.
  - [x] Complete phasing out of X11/XWayland dependencies. Support one compositor.
    This will be Kwin because it is the one I know the best.
  - [x] Full fractional scaling and native Wayland compositor window tracking.

- [x] Phase 4 (Completed) v0.4.0, v0.4.1, v0.4.2: KWin Stabilization, Monolithic Docklets & Bug Fixes
  - [x] Hardened KWin scripting bridge, overlap detection, and multi-monitor tracking.
  - [x] Implemented 8 embedded monolithic docklets (Trash, Clocks, Battery, CPU/RAM, Show Desktop, MPRIS, Volume).
  - [x] Bi-directional KWin & Plasma D-Bus trash bridge synchronization.
  - [x] Resolved icon bounce regressions, portal file launching, and process replacement (`--replace` / `-r`).

- [x] Phase 5 (Completed) v0.4.3: Multi-Compositor HAL & Support for Other Compositors (Labwc, wlroots, Mutter)
  - [x] Defined and implemented the modular Hardware Abstraction Layer (`WindowBackend` / `WindowControl`).
  - [x] Added native Labwc & wlroots support via `zwlr_foreign_toplevel_manager_v1` protocol and C bridge (v0.4.3).
  - [x] Zero-configuration runtime dynamic compositor auto-probing (Labwc vs KWin vs Mutter).
  - [x] Reactive Cairo indicator dots and cross-compositor Show Desktop toggle engine.
  - [x] State-based Dodge & Honest UI Matrix for Labwc (`DODGE_MAXIMIZED`, UI filtering, transparent fallback; validated on LXQt 2.x and XFCE 4.20).
  - [x] Native GNOME Shell / Mutter bridge integration (Phase 1): monolithic self-deploying GNOME Shell extension via D-Bus (`MutterBackend`), window state tracking, zero-notification banners, centered dialogs, and edge positioning (v0.4.3).
  - [x] Strict HAL coordinate isolation: native Layer Shell margins for KWin/Labwc and dedicated absolute screen positioning for Mutter (v0.4.3).
  - [x] Finalize GNOME Shell extension bridge for window geometry retrieval to support Intellihide & Dodge on Mutter.

- [x] Phase 6 (Completed) v0.5.0 - v0.6.2.3: Visual Ergonomics, Advanced Theming & Community Features
  - [x] Comprehensive 16-docklet suite (14 in the 7×2 Docklets grid + Trash + Preferences, including Do Not Disturb, Network, Screenshot, Brightness, Weather, Removable Drive Ejector).
  - [x] Semantic categorized multi-zone dock layout (`[Folders] | [Docklets] | [Pinned Apps] | [Transients] | [Trash]`).
  - [x] Cairo folder launcher menus and full application drawers with active window indicators.
  - [x] Universal Cairo multi-window preview cards with live thumbnails on KWin and GNOME Mutter.
  - [x] Real-time dark/light theme switching with native Theme Manager and portal synchronization.
  - [x] Advanced ergonomics: remote URL drag-and-drop, hover-to-raise window activation, recent files jump lists.
  - [x] Configurable System Menu Access modes, Panel Mode (`ReserveSpace`), and Fullscreen Auto-Hide with 0px edge passthrough.
  - [x] Multi-distribution packaging parity (Debian `.deb` & openSUSE/Fedora `.rpm`).
  - [x] Incorporate community user contributions, bug reports, and UX requests ahead of Public Beta.

- [x] Phase 7 (Active — Public Beta 1 Launched) WayPlank Public Beta (v0.7.x)
  - [x] **Official Launch of Public Beta 1 (v0.7.0) on GitHub!**
  - [x] Monolithic embedded gettext localization engine (`GResource`) with 100% in-memory string resolution (`487/487` strings across 7 languages + English, Zero Host Pollution).
  - [x] Configurable Category & Docklet Layout Engine (`Apps & Layout` tab): two-position Docklets (`Docklets on Right` System Tray layout vs. Default Left), symmetric `WayPlank Always Left` & `Show Trash` edge anchors, and one-click `Align by Type` in Free Mode.
  - [x] Consolidated ISA-88 Phase B FAT baseline across KDE Plasma 6 (KWin), GNOME Shell (Mutter), and Labwc (wlroots) (`379` points defined, `377/377` applicable passed: `354 [ok]` + `23 [ko->ok]`, `2 [NA]`, `0` open `[ko]` defects — **100% PASS**).
  - [ ] Iterative `v0.7.x` Public Beta releases (`v0.7.1` Public Beta 2, `v0.7.2`, etc.) integrating community feature requests, new language catalogs, and UX refinements until the community signals readiness for the `v0.8.x` freeze (hard cap: December 31, 2026).
  - [ ] Broaden community field testing across additional wlroots compositors (Sway, Hyprland, Wayfire).
  - [ ] Preliminary native standalone Windows preview ([WinPlank](Documentation/WINPLANK_PORT_BATTLE_PLAN.md)).
- [ ] Phase 8 (Planned) WayPlank Release Candidate (v0.8.x)
  - [ ] Strict Feature Freeze — no new architectural features, focusing purely on stability and hardening.
  - [ ] Systematic memory leak profiling (Valgrind / AddressSanitizer) and CPU efficiency audits.
  - [ ] Distribution packaging parity: official Debian (.deb), Fedora/openSUSE (.rpm), and Arch Linux AUR PKGBUILD.
- [ ] Phase 9 (Planned) WayPlank Long-Term Production Stabilization (v0.9.x)
  - [ ] The official daily driver production milestone, rock-solid across all major Linux compositors (KWin, Mutter, Labwc) and native Windows 10/11+.
  - [ ] Production maintenance releases (`v0.9.1`, `v0.9.2`, etc.) as Wayland protocols and driver stacks evolve.
- [ ] Phase 10 (Long-Term Horizon ~2 Years) WayPlank 1.0.0 Grand Milestone
  - [ ] The definitive landmark celebration after 2 years of proven daily production stability and mature protocol integration.
---

# 📝 Release Highlights & Changelog

> 🏛️ **HISTORIC MILESTONE CLOSURE — END OF THE ALPHA & PRE-BETA ERA (`v0.1.0` $\longrightarrow$ `v0.6.2.3`) & LAUNCH OF PUBLIC BETA 1 (`v0.7.0`):**  
> Following the final qualification and sign-off of **`v0.6.2.3`** on **November 1, 2026**, the foundational **Alpha & Pre-Beta Engineering Cycle** of WayPlank is permanently **CLOSED**. Across **15 consecutive releases** in 43 days, over **112,000 lines of legacy X11/Autotools code** were purged, a **3-compositor native Wayland HAL** (**KDE Plasma 6 / KWin**, **GNOME Shell / Mutter**, and **Labwc / wlroots**) was built from the ground up, **107 unique functional & architectural bugs** were squashed across **2,037+ formal ISA-88 test executions**, and all **368/368 applicable FAT validation points** achieved a **100% PASS** rate with **0 open defects**. WayPlank now officially stands in the **Public Beta Era (`v0.7.0` — Public Beta 1)**! 🚀

Here is a recap of the journey so far! For complete technical breakdown and FAT test matrix, see [`Changelogs/`](Changelogs/) and [`FAT/`](FAT/). 🚀

* 🚀 **v0.7.0 (Public Beta 1: Monolithic Embedded Localization, Category & Docklet Layout Engine & Hotfix Consolidation) — 2026-11-04 [COMPLETED / 100% FAT PASSED]**:  
  Activates the 100% Monolithic Embedded Localization Engine (`GResource` in RAM, 7 complete language catalogs `zh_CN`, `it`, `es`, `fr`, `ca`, `de`, `uk` at `487/487` strings + native `en`, `0` files in `/usr/share/locale/`), introduces the **Category & Docklet Layout Engine** in **Preferences $\rightarrow$ Apps & Layout** (`Docklets on Right` System Tray layout, symmetric `WayPlank Always Left` & `Show Trash` edge anchors, and `Align by Type` in Free Mode), graduates the **26-style Icons Visual Effects suite** (`Launch Effect`, `Focused App`, `Unpin Effect` + `300–1500 ms` `Effect Duration`) to **Preferences $\rightarrow$ Behaviour**, expands the **Session & Power** docklet to a **3×3 control center** (`Hibernate`, `Hybrid Sleep`, and `UEFI / BIOS` with automatic `systemd-logind` capability detection), upgrades the GNOME Shell companion extension to `version: 4`, resolves Issues **#16, #17, and #18** plus `.sh` profile wrapper (`116 >= 115`), `NoDisplay=true` PWA ↔ `--app=URL`, sibling binary (`VS Code`, `MATLAB`, `Scilab`) parity, folder/open-drawer drag-and-drop, Labwc `"Unknown" -> "Monitor"` display label normalization, 60 FPS hover popup-event filtering (`0.1%` idle CPU), and `SIGWINCH` live `.deb` upgrade reload, and passes **100% of applicable FAT test points (`377/377` passed: `354 [ok]` + `23 [ko->ok]`, `2 [NA]`, `0` open `[ko]`)** across KDE Plasma 6 (KWin), GNOME Shell (Mutter), and Labwc (wlroots).
* 🌟 **v0.6.2.3 (Final Pre-Beta: Community & Visual Enhancements) — 2026-11-01 [COMPLETED / 100% FAT PASSED]**:  
  Universal Cairo multi-window preview cards with live thumbnails on KWin and GNOME Mutter, real-time light/dark theme switching, built-in Do Not Disturb docklet, configurable System Menu Access, Panel Mode (`ReserveSpace`), Fullscreen Inhibit with 0px edge click passthrough (Issue #10), two-stage hysteresis input mask (`AnticipateZoom`, Issue #12), QEMU multi-VM isolation with Labwc `/proc` cold-relaunch synthesis (Issue #14), dynamic top panel avoidance, folder launcher indicators, and recent files jump lists. Permanently closed the Alpha & Pre-Beta cycle!
* 🌟 **v0.6.2.2 (Round 2, Pre-Beta) — 2026-10-21 [COMPLETED / 100% FAT PASSED]**:  
  Remote web URL & browser shortcut DND delivery (`DesktopAppInfo.launch_uris`), hover-to-raise target window activation,  
  real-time dark/light portal color-scheme synchronization (`org.freedesktop.portal.Settings`), interactive Theme Manager  
  with native portal file chooser and archive installer (.zip/.tar.gz), strict FreeDesktop MIME type drop validation,  
  canonical launcher deduplication (`Posix.realpath` & `File.equal`), and clean KISS drag-off removal with instant poof animation.
* 🌟 **v0.6.2.1 (Round 1, Pre-Beta) — 2026-10-19 [COMPLETED / 100% FAT PASSED]**:  
  Native openSUSE/Fedora/RHEL RPM packaging (`BuildRpm.sh`), launcher deduplication & item reuse, ghost bridge window shield,  
  dock overflow smooth scrolling with tachometer redline capacity indicator, and multi-monitor DDC/CI sync with SP/PV decoupling.
* 💡 **v0.6.1 (Alpha) — 2026-10-15:** The Bug Hunting Release — Multi-monitor KWin brightness sync, unified Global System Pressure engine, drag-and-drop payload delivery & 0-byte MIME fix, docklet icon standardization & adaptive dynamic Gtk+ theme engine.
* ✨ **v0.6.0 (Alpha) — 2026-10-11:** Smart first-run auto-configuration (categorized English app drawers, auto-detected pinned apps, docklets & trash), universal "Change Icon..." dialog with FreeDesktop & GIO metadata, integrated User Guide, and clean release polish.
* 🚀 **v0.5.2 (Alpha) — 2026-10-09:** Cairo folder launcher menu, 14 built-in docklets, category layout grouping and deep audit fixing stack overflows & GObject assertions.
* 🛠️ **v0.5.1 (Alpha) — 2026-10-08:** Fixed KWin resume freeze on Plasma 6 with 50ms debouncer, native screenshot docklet and 100% FAT pass rate.
* 🖥️ **v0.5.0 (Alpha) — 2026-10-07:** Solved multi-monitor duplicate ID collisions, live monitor hotplugging and Mutter drag race fixes.
* 🧩 **v0.4.3 (Pre-Alpha) — 2026-10-05:** Modular Multi-Compositor HAL: dynamic auto-probing for KWin, Labwc (via `zwlr_foreign_toplevel`) and GNOME Shell bridge.
* 📦 **v0.4.2 (Pre-Alpha) — 2026-10-02:** First 8 monolithic docklets (Trash, Clock, Battery, etc.), total purge of X11 libs and `--replace` flag.
* ⚙️ **v0.4.1 (Pre-Alpha) — 2026-09-25:** Multi-monitor config persistence, secondary display tooltip fix and smooth zoom without micro-stutters.
* 🪟 **v0.4.0 (Pre-Alpha) — 2026-09-24:** KWin D-Bus scripting bridge, real-time window Dodge/Intellihide and layer-shell input region negotiation.
* 📌 **v0.3.0 (Pre-Alpha) — 2026-09-23:** Drag-and-drop icon pinning, running app dots and native compositor-safe window tracking.
* 🏗️ **v0.2.0 (Pre-Alpha) — 2026-09-22:** Native `gtk-layer-shell` integration, `/proc` process scanner and standalone packaging scripts.
* 🌱 **v0.1.0 (Pre-Alpha) — 2026-09-19:** Initial standalone fork from Plank, clean namespace migration to `wayplank` and XDG isolated paths.

👉 *Read the full detailed commits and milestone notes in [`Changelogs/`](Changelogs/).*
 

---

## ⚖️ License & Integrated Assets Attribution

Wayplank is free software licensed under the **GNU General Public License v3.0 or later** ([GPL-3.0-or-later](LICENSE)).

### 1. Core Project & Codebase
* **License**: GNU General Public License v3.0 or later ([GPL-3.0-or-later](LICENSE)).
* **Original Plank Codebase**: © 2011–2015 Robert Dyer, Michal Hruby, Rico Tzschichholz, and Plank contributors.
* **Wayplank Fork & Architecture**: © 2026 Sergio Melas (<sergiomelas@gmail.com>).

### 2. Integrated Fallback Assets & Vector Artwork
Wayplank incorporates high-definition vector assets compiled directly into the binary executable via GLib GResources (`/net/launchpad/plank/docklets/`) to provide self-contained, standalone operation on any desktop or minimal distribution:
* **Docklet Fallback Icons** (`data/docklets/`):
  * **Volume Scale**: Overamplified (>100%), High, Medium, Low, Muted (`volume-*.svg`).
  * **Battery Scale**: Full, Good, Low, Caution, Empty, Full-Charging, Good-Charging, Low-Charging, Caution-Charging, Empty-Charging, AC-Adapter, Missing (`battery-*.svg`).
  * **Brightness Scale**: High, Medium, Low, Base (`brightness-*.svg`).
  * **Weather Forecast Scale**: Clear, Few Clouds, Overcast, Showers, Snow, Storm, Fog (`weather-*.svg`).
  * **Clock & Time**: Analog Clock (`clock.svg`), Digital LED Clock (`digital-clock.svg`).
  * **System & Hardware**: Trash empty/full (`trash.svg`, `trash-full.svg`), Global System Pressure Monitor (`cpu.svg`), Network Monitor (`network.svg`), Do Not Disturb (`dnd.svg`), Show Desktop (`desktop.svg`), MPRIS Media Player (`mpris.svg`, `mpris-play.svg`, `mpris-pause.svg`), Screenshot (`screenshot.svg`), Session/Power (`session.svg`), Wayplank Preferences (`preferences.svg`), Removable Drive Ejector (`ejector.svg`).
* **Attribution & Upstream**: Derived from FreeDesktop & KDE Breeze icon specifications © KDE Community / Breeze Icon Artists, licensed under **LGPL-3.0-or-later** / **GPL-3.0-or-later**.
* **Zero Host Pollution**: All fallback icons are strictly compiled into the internal executable binary; no extra icon files are installed into `/usr/share/icons/hicolor/`, ensuring pure standalone behavior and complete distribution independence.


