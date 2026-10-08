# Wayplank V0.1.0 Detailed Technical Changelog

Release Milestone: **V0.1.0** (Phase 1 Architecture Decoupling & Baseline Release)  
Archive Source: `0.1_X11 Bare lauch in walyns with stubs.zip` (based on `0.0 X11 Original Codebase.zip` / `plank-0.11.89`)  
Release Date: 2026-09-19  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 🍴 (Cross-Compositor / Build) Upstream Decoupling & Purge of Legacy Autotools (112,000+ Lines Removed)

- **The Upstream Baseline (`plank-0.11.89`)**:
  - The starting codebase was Debian's upstream `plank-0.11.89` package (authored by Robert Dyer, Rico Tzschichholz, and elementary OS), heavily constrained by obsolete X11 build infrastructure and broken m4 macros.
- **Complete Eradication of Legacy Autotools**:
  - Completely excised the fragile GNU Autotools build pipeline:
    - Purged `configure.ac`, `Makefile.am`, `Makefile.in`, `autogen.sh`, `aclocal.m4`, and `build-aux/`.
    - Removed 300+ legacy translation catalogs (`po/*.po`, `po/*.gmo`) and static documentation build steps.
    - Stripped out unmaintained test harnesses (`tests/gmock`, `tests/Controller.vala`, `tests/Drawing.vala`, `tests/Widgets.vala`).
  - Total code excised in initial purge: **over 112,600 lines of dead code and obsolete build scripts**.

---

## 2. 🏗️ (Cross-Compositor / Architecture) Architectural Restructuring & Staging Workflow

- **Clean Directory Hierarchy (`_Private/Howto.txt`)**:
  - Established a modern, streamlined project directory topology:
    - `data/`: Extracted themes (Default, Matte, Transparent), icons, and schemas.
    - `include/`: Common C header definitions (`config.h`).
    - `lib/`: Extracted core Vala modules (`Drawing/`, `Items/`, `Services/`, `Widgets/`).
    - `src/`: Application entry point (`Main.vala`).
    - `build/`: Isolated compilation artifact target.
- **Introduction of Fast Monolithic Build Scripts**:
  - Replaced the multi-minute autotools configure/make cycle with high-speed direct compilation:
    - `BuilsBin.sh`: Compiles binary directly using `valac` with GResource compilation via `glib-compile-resources` (`lib/resources.c` from `data/plank.gresource.xml`).
    - `BuildDeb.sh`: Generates standalone native Debian `.deb` packages with automated packaging metadata, permission fixing, and post-installation desktop database triggers (`desktop-file-utils`, `glib-compile-schemas`).

---

## 3. 🏷️ (Cross-Compositor / Core) Complete Namespace Migration to `wayplank`

- **Binary & Symbolic Links**:
  - Renamed target executable from `plank` to `wayplank`.
  - Added compatibility symlink `/usr/local/bin/plank -> /usr/local/bin/wayplank` to prevent breaking user autostart scripts.
- **GSettings Schema Isolation**:
  - Migrated schema ID from `net.launchpad.plank` to `net.launchpad.wayplank` in `data/glib-2.0/schemas/`.
  - Relocated system assets to `/usr/share/wayplank` and `/usr/local/share/wayplank` via `PKGDATADIR` redefinition.
  - Isolated user runtime configurations strictly under `~/.config/wayplank` and custom themes under `~/.local/share/wayplank/themes`.

---

## 4. 🧩 (Early Wayland Stubs) Wayland Bare-Launch Stubs & Display Abstraction

- **Bare Launch in Wayland with Stubs**:
  - In `0.0`, Plank unconditionally failed or aborted with X11 connection errors when launched in pure Wayland sessions.
  - In `0.1`, preliminary stubs were wrapped around X11 window calls in `DockWindow.vala` and `PositionManager.vala`, allowing the binary to launch and create basic drawing surfaces under Wayland before full protocol re-engineering.

---

## 5. 📦 Summary of Touched Files & Code Metrics

| Subsystem | File / Directory | Key Modifications |
| :--- | :--- | :--- |
| **Purged** | `autogen.sh`, `configure.ac`, `Makefile.am`, `po/*`, `tests/*` | Removed 112,649 lines of obsolete build scaffolding and dead files. |
| **Build System** | `BuilsBin.sh`, `BuildDeb.sh` | Created monolithic direct-compilation scripts using `valac` and `glib-compile-resources`. |
| **Namespace** | `src/Main.vala`, `lib/Factories/AbstractMain.vala` | Renamed executable and package definitions to `wayplank`. |
| **Configuration** | `data/glib-2.0/schemas/*` | Relocated GSettings schemas to `net.launchpad.wayplank`. |
| **Resources** | `data/plank.gresource.xml` | Embedded icons and UI assets into binary via GLib resource bundles. |
| **Staging** | `_Private/Howto.txt` | Documented initial tree restructuring and module extraction workflow. |
