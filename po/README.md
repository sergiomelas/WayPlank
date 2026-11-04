# 🌍 WayPlank Monolithic Localization & Internationalization Guide

> **Project:** WayPlank (Lightweight native Wayland dock based on Plank architecture)  
> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026

WayPlank is designed from the ground up as a high-performance, standalone, and monolithic Wayland desktop dock. Unlike legacy applications that depend on scattered filesystem paths (`/usr/share/locale/<lang>/LC_MESSAGES/...`), WayPlank's localization architecture is designed to be **100% SELF-CONTAINED** and **EMBEDDED** directly into the single binary executable (`wayplank`).

---

## 🔒 Core Principle: 100% Standalone Monolithic Binary Guarantee

WayPlank will **NEVER** be distributed as a multi-file bundle requiring external locale directories. The primary build output of `BuildBin.sh` is **ONE SINGLE STANDALONE FILE** (`build/wayplank`). All translations, icons, themes, and logic reside inside this single ~8.9 MB executable. When this single file is launched on a computer with any supported language, it translates automatically directly from internal memory without accessing the filesystem or requiring installation.

---

## 1. 🗣️ Supported Languages & Status (487 / 487 Strings Qualified — 100%)

| # | Language | Locale | Contributor & Reviewer | Status |
| :---: | :--- | :---: | :--- | :---: |
| 1 | **简体中文** (Simplified Chinese) | `zh_CN` | 史有虎 (IFtiger-hu) `<2212363803@qq.com>` | **100% Translated** (487/487) |
| 2 | **Italiano** (Italian) | `it` | Sergio Melas `<sergiomelas@gmail.com>` | **100% Translated** (487/487) |
| 3 | **Español** (Spanish) | `es` | Sergio Melas `<sergiomelas@gmail.com>` | **100% Translated** (487/487) |
| 4 | **Français** (French) | `fr` | Sergio Melas `<sergiomelas@gmail.com>` | **100% Translated** (487/487) |
| 5 | **Català** (Catalan) | `ca` | Sergio Melas `<sergiomelas@gmail.com>` | **100% Translated** (487/487) |
| 6 | **Deutsch** (German) | `de` | Renate Schwiedernoch `<renate.schwiedernoch@gmail.com>` | **100% Translated** (487/487) |
| 7 | **Українська** (Ukrainian) | `uk` | Michailo Buchko `<mixabuchko@gmail.com>` | **100% Translated** (487/487) |
| 8 | **English** | `en` | Native in-source fallback language | **100% Native** (Zero files needed) |

---

## 2. 🗺️ Monolithic Integration Architecture & Step-by-Step Implementation (Public Beta 1 `v0.7.0`)

In **WayPlank Public Beta 1 (`v0.7.0`)**, all 7 translation catalogs (`487/487` strings — 100%) and generation tools are maintained in the `po/` directory for monolithic in-memory `GResource` integration.

The 100% monolithic embedded localization engine for Public Beta (`v0.7.0`) follows these exact technical steps:

### Step 1: Single Entry Point & Automatic Build-Time Discovery (`po/generate_translations.py` $\rightarrow$ `BuildBin.sh`)
`po/generate_translations.py` is the **sole and exclusive entry point** for defining or adding languages. When `BuildBin.sh` runs:
1. It executes `python3 po/generate_translations.py` to generate `po/wayplank.pot` and all `po/<lang>.po` catalogs.
2. It automatically scans all available `po/*.po` files, compiles each into `data/locale/<lang>/wayplank.mo` via `msgfmt`, dynamically injects `<file compressed="true">locale/<lang>/wayplank.mo</file>` into the build `GResource` XML, and passes the discovered list of embedded languages to the compiler via `-DWAYPLANK_EMBEDDED_LANGS="<lang1>:<lang2>:..."`:

```bash
python3 "${BASE_DIR}/po/generate_translations.py"
EMBEDDED_LANGS=""
for po in "${BASE_DIR}"/po/*.po; do
    lang="$(basename "$po" .po)"
    mkdir -p "${BASE_DIR}/data/locale/${lang}"
    msgfmt "$po" -o "${BASE_DIR}/data/locale/${lang}/wayplank.mo"
    EMBEDDED_LANGS="${EMBEDDED_LANGS:+${EMBEDDED_LANGS}:}${lang}"
done
```

This bakes all discovered language catalogs and the `WAYPLANK_EMBEDDED_LANGS` registry directly into `lib/resources.c` and the monolithic binary ELF (`build/wayplank`), followed immediately by `rm -rf data/locale` to keep the source tree 100% clean. **Adding a new language in the future requires modifying ONLY `po/generate_translations.py`** — zero C code, zero XML, and zero build script changes are ever required.

### Step 2: Zero-Hardcode In-Memory Translation Resolver (`lib/gtk-compat.c`)
In `lib/gtk-compat.c`, implement the lightweight, language-agnostic in-memory lookup function:

```c
const char* wayplank_i18n_get (const char* msgid);
void wayplank_i18n_init (void);
```

How it works:
1. `wayplank_i18n_init()` contains **zero hardcoded language names**. It reads the active desktop locale via `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG`, or `setlocale(LC_MESSAGES, "")` and checks whether the system language exists inside the binary's compile-time `WAYPLANK_EMBEDDED_LANGS` list.
2. If the system language matches one of the languages encoded in `WAYPLANK_EMBEDDED_LANGS`, it loads `/net/launchpad/plank/locale/<lang>/wayplank.mo` directly from in-memory `GResource` (`g_resources_lookup_data`).
3. If the system language does **not** exist in `WAYPLANK_EMBEDDED_LANGS` (or is English), it immediately falls back to **native English** with zero overhead.
4. `wayplank_i18n_get(msgid)` performs a binary search lookup directly into the embedded `.mo` byte table in RAM. If found, returns the translated string; if missing or English, instantly returns `msgid`.

### Step 3: Hook the Vala Gettext Macro (`include/config.h`)
In `include/config.h`, redirect Vala's gettext macro:

```c
const char* wayplank_i18n_get (const char* msgid);
#undef _
#define _(String) wayplank_i18n_get(String)
```

Because Vala compiles every `_("text")` in source code to `_( "text" )`, this transparently intercepts all UI string lookups at compile time, completely eliminating any runtime dependency on external filesystem paths!

### Step 4: Initialize in Main (`src/Main.vala`)
In `src/Main.vala`, call the initialization routine at startup:

```vala
wayplank_i18n_init ();
```

### Step 5: Zero Host Pollution & Pure Monolithic Packaging (`BuildDeb.sh` & `BuildRpm.sh`)
In strict compliance with WayPlank's **Zero Host Pollution** architecture (identical to how embedded docklet SVG assets are handled):
- **Zero `/usr/share/locale/` Files**: Neither `BuildDeb.sh` nor `BuildRpm.sh` installs external `.mo` files into `/usr/share/locale/`. All 7 language catalogs live exclusively inside the single `/usr/bin/wayplank` binary via `GResource` in RAM.
- **Full Debian Policy & Lintian Compliance**: Because the binary resolves translations entirely from internal memory and no `/usr/share/locale/` directory is created in the package payload, `dpkg-deb`, `lintian`, and `rpmbuild` validate the package with **0 warnings and 0 errors**.

---

## 3. 🛠️ Maintenance & Tools

To regenerate or re-verify all 7 language catalogs from the active codebase:

```bash
python3 po/generate_translations.py
```

This script guarantees:
- **100% message coverage** (`487/487` messages across all 7 languages).
- **Validation** with GNU `msgfmt -c -v`.
- **Consistent ordering and validation** across all catalogs.

