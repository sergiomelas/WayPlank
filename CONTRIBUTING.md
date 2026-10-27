# 🤝 Contributing to WayPlank

First off, thank you for considering contributing to WayPlank! 🎉 

WayPlank is a high-performance, standalone, monolithic dock designed natively for the Wayland desktop ecosystem. With hundreds of community users, thousands of lifetime downloads, and active contributors across the world, community feedback and contributions are what make WayPlank thrive.

Whether you are reporting a bug, contributing translations, improving themes, testing on a new compositor, or submitting code, this guide will help you get started quickly.

---

## 📌 Table of Contents

1. [Current Project Status & Roadmap](#-current-project-status--roadmap)
2. [Active Community Tracks & Open Issues](#-active-community-tracks--open-issues)
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

* **Current Stable / Pre-Beta Release**: `v0.6.2.3` (Community User Contributions).
* **Upcoming Major Milestone**: **Public Beta (`v0.7.0`)** launching in **Week 45 (Monday, November 2, 2026)**.
* **Tier 1 Supported Compositors**:
  - **KDE Plasma (KWin 6.x)**: Full layer-shell integration, D-Bus scripting bridge, live Cairo preview thumbnails.
  - **GNOME Shell (Mutter 46/47/48)**: Dedicated Mutter extension bridge, live window previews, window Dodge/Intellihide.
  - **Labwc (wlroots)**: Pure `zwlr_foreign_toplevel_manager_v1` protocol tracking, honest UI matrix, Dodge.

---

## 🚀 Active Community Tracks & Open Issues

We actively track open community suggestions and bug reports on [GitHub Issues](https://github.com/sergiomelas/WayPlank/issues) and [GitHub Discussions](https://github.com/sergiomelas/WayPlank/discussions). Here is the status of active topics:

| Issue / Topic | Title | Area | Status & Next Steps |
|---|---|---|---|
| [#5](https://github.com/sergiomelas/WayPlank/issues/5) | **HiDPI 4K@1.5x Fractional Scaling on Cold Start** | GNOME Mutter / Display | Workaround available (logout/login). Adding dynamic `notify::scale-factor` and cold-start geometry debounce in v0.7.0. |
| [#6](https://github.com/sergiomelas/WayPlank/issues/6) | **Application Identity & PWA Matching Hardening** | Core / Matching | Refining `ApplicationIdentity.vala` fuzzy matching to strictly prioritize exact `app_id` / `StartupWMClass` over partial titles for Chromium PWAs & Flatpaks. |
| [#9](https://github.com/sergiomelas/WayPlank/issues/9) | **Option to Reserve Screen Space (Panel Mode)** | Layer Shell / Geometry | Planned: add configurable toggle (`reserve-space`) for users running permanent dock (`HideMode == NONE`) who want maximized windows tiled above the dock. |
| [#10](https://github.com/sergiomelas/WayPlank/issues/10) | **Auto-hide Dock on Fullscreen Windows** | Window Tracking / UX | Planned: auto-hide the dock when active applications (e.g. Remmina remote desktop, QEMU/KVM virtual machines, full-screen games) enter fullscreen. |
| [#11](https://github.com/sergiomelas/WayPlank/issues/11) | **Dock Hidden on Workspace Switch in Labwc** | Labwc (wlroots) / Workspaces | Under investigation: track `zwlr_foreign_toplevel_manager_v1` active workspace change events in `LabwcBackend.vala` to properly restore dock visibility when moving from a maximized workspace to an empty/non-maximized workspace. |
| [#12](https://github.com/sergiomelas/WayPlank/issues/12) | **Pointer Input Blocking on Windows Behind Dock** | Layer Shell / Input Mask | Reported by Gabenoh: when a non-fullscreen window (terminal, messenger) overlaps behind the dock, WayPlank captures pointer clicks on the transparent extended allocation. Refining `set_input_mask()` in `DockWindow.vala` to ensure transparent areas strictly pass through clicks to underlying windows. |

---

## 🛠️ How to Contribute

### Track 1: Localization & Translations (i18n)

WayPlank features a standalone translation architecture managed through a central dictionary script: [`po/generate_translations.py`](po/generate_translations.py).

Currently, **7 languages** are qualified at **100% (322/322 strings)**:

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

* WayPlank runs seamlessly across **KWin**, **Mutter**, and **Labwc**. 
* **Never write compositor-specific logic inside core dock code** (`lib/Widgets/`, `lib/Items/`, `src/`).
* All compositor-specific interactions (window tracking, thumbnails, active desktop detection, panel avoidance) MUST reside strictly inside [`lib/Services/`](lib/Services/) behind the abstract `WindowBackend` and `WindowControl` interfaces.
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

# Build standalone monolithic executable
./BuildBin.sh

# Run locally in debug mode
./build/wayplank -d

# Replace any existing running instance
./build/wayplank -r
```

### Testing & Quality Assurance (FAT)

WayPlank adheres to a rigorous **Factory Acceptance Test (FAT)** protocol covering over 350 validation points across all Tier 1 compositors:
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

