# 📦 WayPlank Static Cross-Build Dependencies (`deps/`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Governed By:** [`Documentation/Architecture/HAL_WINDOWS_BACKEND.md`](../Documentation/Architecture/HAL_WINDOWS_BACKEND.md) • [`BuildWin.sh`](../BuildWin.sh)

This directory holds the **locally generated, gitignored** static cross-compilation sysroot used to build WayPlank's Zero-DLL Windows executable (`build/wayplank.exe`) 100% on Linux.

> [!NOTE]
> Everything inside `deps/` except this `README.md` is ignored by `.gitignore` (`deps/*` + `!deps/README.md`). Nothing downloaded or compiled here is ever committed to Git.

---

## 📁 Directory Structure (`deps/win32/`)

Created and managed automatically by [`./BuildWin.sh`](../BuildWin.sh):

```text
deps/
├── README.md                          # This file (tracked in Git)
└── win32/                             # Gitignored local Windows cross-build workspace
    ├── x86_64-w64-mingw32.ini         # Auto-generated Meson cross-compilation file
    ├── x86_64-w64-mingw32.cmake       # Auto-generated CMake toolchain file
    ├── src/                           # Cached upstream release tarballs (.tar.xz/.tar.gz/.tar.bz2)
    ├── build/                         # Temporary extracted source & compile trees (safe to delete after sysroot completes)
    ├── stamps/                        # Per-library .built markers so ./BuildWin.sh skips already-built libraries
    └── sysroot/                       # Installed static MinGW-w64 libraries & headers
        ├── bin/                       # Dedicated static pkg-config wrapper (x86_64-w64-mingw32-pkg-config)
        ├── include/                   # Cross-compiled C/C++ headers
        └── lib/                       # Static archives (*.a) & pkgconfig/*.pc files
```

---

## 🧱 4-Tier Static Library Inventory (`deps/win32/sysroot/`)

All libraries are cross-compiled with `x86_64-w64-mingw32-gcc-posix` / `g++-posix` as **static-only archives (`.a`)** targeting Windows `7 ⟷ 11+` (`_WIN32_WINNT=0x0601`):

| Tier | Library | Version | Purpose |
| :---: | :--- | :---: | :--- |
| **Tier 1** | `zlib` | `1.3.1` | Deflate compression (`GResource`, PNG, archives) |
| **Tier 1** | `libffi` | `3.4.6` | Foreign function interface for `GObject` |
| **Tier 1** | `libiconv` | `1.17` | Character-set conversion for `GLib` |
| **Tier 1** | `gettext-runtime` | `0.22.5` | `libintl` runtime for `GLib` / `GTK3` |
| **Tier 1** | `pcre2` | `10.44` | Unicode regular expressions (`GRegex`) |
| **Tier 2** | `glib-2.0` | `2.80.5` | `GLib`, `GObject`, `GIO` (`giowin32` + `GRegistrySettingsBackend`), `GModule` |
| **Tier 2** | `libgee-0.8` | `0.20.6` | Vala collections (`ArrayList`, `HashMap`, `HashSet`) |
| **Tier 2** | `json-glib-1.0` | `1.8.0` | JSON parsing (`AppUsageService`, `Weather`, browser `Local State`) |
| **Tier 3** | `libpng` | `1.6.44` | Static PNG codec |
| **Tier 3** | `pixman` | `0.43.4` | Low-level 2D pixel manipulation for `Cairo` |
| **Tier 3** | `freetype2` | `2.13.3` | Font rasterizer |
| **Tier 3** | `fribidi` | `1.0.16` | Unicode bidirectional text algorithm |
| **Tier 3** | `harfbuzz` | `10.0.1` | OpenType text shaping (GDI + DirectWrite) |
| **Tier 3** | `cairo` | `1.18.2` | 2D vector rendering engine (`win32` + `ARGB32` image surfaces) |
| **Tier 3** | `pango` | `1.54.0` | Text layout (`pangowin32` + `pangocairo`) |
| **Tier 3** | `lunasvg` | `2.4.1` | Zero-dependency C++17 SVG rasterizer (bundled with `plutovg`) |
| **Tier 3** | `gdk-pixbuf-2.0` | `2.42.12` | Image loaders (`png`, `bmp`, `ico`, `gif` + static built-in `svg` via `hal/Windows/win32-svg-loader.cpp`) |
| **Tier 4** | `libepoxy` | `1.5.10` | OpenGL function pointer dispatch for `GTK3` |
| **Tier 4** | `atk` | `2.38.0` | Accessibility toolkit required by `GTK3` |
| **Tier 4** | `gtk+-3.0` | `3.24.43` | Static Win32-only `GTK3` / `GDK3` (`-Dwin32_backend=true -Dx11_backend=false -Dwayland_backend=false`) |

---

## 🛠️ Maintenance Commands

```bash
# Build or resume the static sysroot only:
./BuildWin.sh --build-sysroot

# Force-rebuild a single library (e.g. after changing win32-svg-loader.cpp):
./BuildWin.sh --rebuild-lib gdk-pixbuf

# Reclaim disk space after sysroot is built (keeps cached tarballs & installed sysroot):
rm -rf deps/win32/build

# Full clean reset of the Windows sysroot:
rm -rf deps/win32
```
