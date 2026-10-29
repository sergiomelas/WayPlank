# WayPlank V0.7.0 (Public Beta) Detailed Technical Changelog

Release Series: **V0.7.x Series (The Public Beta Milestone)**  
Current Milestone: **V0.7.0 (Public Beta: Monolithic Embedded Localization & Community Validation)**  
Target Release Date: **Week 45 (Monday, November 2, 2026)**  
Maintainer: **Sergio Melas** (sergiomelas@gmail.com, GitHub: [@sergiomelas](https://github.com/sergiomelas))  
Collaborators & Contributors:
- **史有虎 (IFtiger-hu)** (Collaborator & Simplified Chinese Reviewer, GitHub: [@IFtiger-hu-hub](https://github.com/IFtiger-hu-hub))
- **WayPlank Translation Community**

---

## 1. 📋 Overview & Motivation

Following the successful completion of the pre-beta cycle (**v0.6.2.3**) with comprehensive Factory Acceptance Testing (363/367 test cases passing across KWin, GNOME Shell, and Labwc), WayPlank enters the milestone **Public Beta (v0.7.0)**.

The primary objective of **v0.7.0** is the implementation of a **100% Monolithic, Embedded Localization Engine** combined with broad community multi-compositor field testing. 

Unlike traditional Unix applications that scatter locale catalogs across the filesystem (`/usr/share/locale/<lang>/LC_MESSAGES/wayplank.mo`), WayPlank adheres strictly to its **Monolithic Standalone Executable Guarantee**: all translation catalogs, Cairo themes, vector graphics, and application logic reside directly inside a single portable binary (`build/wayplank`). When launched on any Linux system with any supported locale, WayPlank resolves translations directly from internal RAM without requiring external filesystem lookups, installation, or root privileges.

---

## 2. 🌍 100% Monolithic Embedded Localization Engine

### 2.1. Architectural Design & Philosophy
- **Zero Runtime Filesystem Dependency**: The single binary executable (`build/wayplank`, ~7.8 MB) contains all `.mo` binary catalogs embedded as internal GResource byte tables.
- **In-Memory Hash Resolution**: An ultra-lightweight C resolver (`lib/gtk-compat.c`) hooks GNU gettext calls. It loads the active desktop locale via `setlocale(LC_MESSAGES, "")` / `LANG` and performs an $O(1)$ binary lookup into the in-memory `.mo` byte table in RAM.
- **Instant Fallback**: If a string is untranslated or the user locale is English, the resolver instantly returns the static C string pointer without heap allocations or disk I/O.
- **Vala Interception**: Redirects Vala's compile-time gettext macro in `include/config.h`:
  ```c
  const char* wayplank_i18n_get (const char* msgid);
  #undef _
  #define _(String) wayplank_i18n_get(String)
  ```

### 2.2. Supported Language Catalogs (326 / 326 Strings Qualified - 100%)
All 326 UI msgids covering preferences, dock menus, tooltips, weather settings, and session dialogs are fully qualified:
1. **简体中文 (Simplified Chinese, `zh_CN`)**:
   - Contributor & Reviewer: 史有虎 (IFtiger-hu) <2212363803@qq.com>
   - Status: 100% Translated (326/326 messages). Prioritized in catalogs and dictionaries.
2. **Italiano (Italian, `it`)**:
   - Maintainer: Sergio Melas <sergiomelas@gmail.com>
   - Status: 100% Translated (326/326 messages).
3. **Español (Spanish, `es`)**:
   - Status: 100% Translated (326/326 messages).
4. **Français (French, `fr`)**:
   - Status: 100% Translated (326/326 messages).
5. **Català (Catalan, `ca`)**:
   - Status: 100% Translated (326/326 messages).
6. **Deutsch (German, `de`)**:
   - Contributor: Renate Schwiedernoch
   - Status: 100% Translated (326/326 messages).
7. **Українська (Ukrainian, `uk`)**:
   - Contributor: Michailo Buchko
   - Status: 100% Translated (326/326 messages).
8. **English (`en`)**:
   - Native in-source fallback language (zero overhead).

### 2.3. Community Tooling (`po/generate_translations.py`)
- Single, self-contained Python script maintaining the master dictionary of all UI strings.
- Allows translators to add new languages or refine existing strings in a clean Python dictionary without dealing with raw gettext boilerplate or fuzzy tags.
- Automatically compiles and validates `.po` files with GNU `msgfmt -c -v`.

---

## 3. 📦 Distribution Packaging & System Locale Parity

While the standalone binary `build/wayplank` operates 100% standalone without requiring filesystem files, distribution build scripts have been updated to ensure full packaging compliance:
- **`BuildDeb.sh` (Debian / Ubuntu / Linux Mint)**:
  - Generates `wayplank_0.7.0_amd64.deb`.
  - Installs standard system `.mo` files into `/usr/share/locale/<lang>/LC_MESSAGES/wayplank.mo` to satisfy Debian package linter rules.
- **`BuildRpm.sh` (openSUSE / Fedora / RHEL)**:
  - Generates `wayplank-0.7.0-1.x86_64.rpm`.
  - Installs standard `.mo` files into RPM locale directories.
- **`BuildBin.sh` (Generic / Standalone / Portable)**:
  - Compiles the self-contained monolithic binary `build/wayplank`.

---

## 4. 🧪 Public Beta Factory Acceptance Testing (FAT 0.7.0)

- **378 Total Test Points**:
  - 367 Baseline Test Points carried forward from v0.6.2.3 across KWin, Mutter, and Labwc.
  - 11 New Dedicated Localization & Embedded I18N Verification Test Points (Section 12).
- **Multi-Compositor Validation Scope**:
  - KDE Plasma 6 (KWin Wayland)
  - GNOME Shell 46+ (Mutter Wayland)
  - Labwc / wlroots (Wayland)
  - Community field testing on Sway & Hyprland

---

## 5. 🗺️ Master Release Trajectory

```
v0.6.2.3 (Pre-Beta Finale) ──► v0.7.x (Public Beta) ──► v0.8.x (Release Candidate) ──► v0.9.x (Stabilization) ──► v1.0.0 (Grand Milestone)
```

- **v0.7.x (Public Beta — Week 45: Monday, November 2, 2026)**: Feature-complete monolithic localization release & community field testing.
- **v0.8.x (Release Candidate Series)**: Strict feature freeze, memory leak profiling (Valgrind), and packaging stabilization.
- **v0.9.x (Long-Term Production Stabilization)**: The official battle-tested production milestone for daily driving across all Linux distros.
- **v1.0.0 (Grand Milestone Horizon — ~2 Years)**: Definitive landmark release celebrating multi-year proven stability and mature Wayland protocol standards.

