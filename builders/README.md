# WayPlank Multi-OS Build & Packaging System (`builders/`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Architecture Reference:** [`Documentation/Architecture/README.md`](../Documentation/Architecture/README.md) • [`HAL_LINUX_BACKEND.md`](../Documentation/Architecture/HAL_LINUX_BACKEND.md) • [`HAL_BSD_BACKEND.md`](../Documentation/Architecture/HAL_BSD_BACKEND.md) • [`HAL_WINDOWS_BACKEND.md`](../Documentation/Architecture/HAL_WINDOWS_BACKEND.md)  
> **Precompiled Outputs:** [`build/README.md`](../build/README.md)

---

## 1. Why `builders/{linux,bsd,windows}/` ➔ `build/{linux,bsd,windows}/`? (Architectural Rationale)

Up to `v0.7.3.2`, all build scripts lived in the repository root (`./BuildBin.sh`, `./BuildDeb.sh`, `./BuildRpm.sh`, `./BuildWin.sh`, `./BuildNsis.sh`) and wrote every deliverable into a single flat `build/` directory.

Introducing native **FreeBSD (`hal/BSD/`)** in **`v0.7.4`** made a flat layout structurally ambiguous and error-prone. Moving to isolated per-OS directories solves four concrete engineering problems:

1. **Binary Name Collision (`wayplank` Linux ELF vs. `wayplank` FreeBSD ELF):**
   Both Linux and FreeBSD compile a monolithic native POSIX executable named `wayplank`. In a flat `build/` directory, building on FreeBSD would overwrite or be indistinguishable from the Linux ELF binary (`build/wayplank`). Isolating outputs under `build/linux/wayplank` and `build/bsd/wayplank` eliminates ambiguity completely.
2. **1:1 Symmetry with the 3-Zone Dichotomic HAL:**
   Every OS backend now has an exact mirror across source drivers, build scripts, and release artifacts:
   ```text
   hal/Linux/   ↔  builders/linux/   ➔  build/linux/
   hal/BSD/     ↔  builders/bsd/     ➔  build/bsd/
   hal/Windows/ ↔  builders/windows/ ➔  build/windows/
   ```
   Zone 1 (`src/`, `lib/`), Zone 2 (`hal/Interfaces/`), and shared Freedesktop userland (`hal/Freedesktop/`) remain 100% single-source and shared across builds.
3. **Clear Build-Host Semantics (Native vs. Cross-Compiled):**
   - **Linux** is compiled **natively on Linux** (`gcc` + `valac`).
   - **FreeBSD** is compiled **natively on FreeBSD** (`clang`/`cc` + `valac` + `libprocstat`/`libdevstat`/`kvm`) — *never* cross-compiled from Linux.
   - **Windows** is **cross-compiled 100% on Linux** (`x86_64-w64-mingw32-gcc` + static 4-Tier 16-library sysroot in `./deps/win32/sysroot` + `makensis`) to produce a Zero-DLL PE32+ executable (`25` evergreen Windows OS DLLs only).
4. **Clean Repository Root & Safe Packaging Pipelines:**
   Seven scripts and seven multi-OS deliverables no longer clutter the top-level repository tree, and each OS packaging pipeline owns its staging/output directory without colliding with other operating systems.

---

## 2. Builder Script Matrix

All scripts are designed to be invoked from the **repository root** and support non-interactive CI / headless execution via **`WAYPLANK_NO_PROMPT=1`**.

| Directory | Script | Build Host | Output Deliverables | Role |
| :--- | :--- | :--- | :--- | :--- |
| **`builders/linux/`** | [`BuildBin.sh`](linux/BuildBin.sh) | Linux (Native) | `build/linux/wayplank` | Compiles GResources (`.mo` catalogs, themes, SVGs, `VERSION`), enforces the **8-Gate HAL Purity Firewall**, links the monolithic ELF binary (statically linking `libplank-internal.a`; zero `libplank.so`), and runs the **Pitfall #14 UAF `objdump` check**. |
| **`builders/linux/`** | [`BuildDeb.sh`](linux/BuildDeb.sh) | Linux (Native) | `build/linux/wayplank`, `build/linux/wayplank_<ver>_amd64.deb` | Calls `BuildBin.sh` and packages a Debian/Ubuntu `.deb` archive (binary, `.desktop`, icons, GSettings schema, postinst/prerm triggers). **Primary Linux engineering build gate.** |
| **`builders/linux/`** | [`BuildRpm.sh`](linux/BuildRpm.sh) | Linux (Native) | `build/linux/wayplank`, `build/linux/wayplank-<ver>-1.x86_64.rpm` | Calls `BuildBin.sh` and packages a Fedora/openSUSE `.rpm` archive. Run **sequentially** after `BuildDeb.sh` (never concurrently, as both share temporary staging inside `build/`). |
| **`builders/bsd/`** | [`BuildBsd.sh`](bsd/BuildBsd.sh) | FreeBSD (Native) | `build/bsd/wayplank` | Compiles GResources, enforces the **8-Gate HAL Purity Firewall** (verifying zero `/proc` and `/sys` leaks in Zone 1 and `hal/BSD/`), links native `libprocstat`, `libdevstat`, and `kvm`, and runs the **Pitfall #14 UAF `llvm-objdump` check**. |
| **`builders/bsd/`** | [`BuildPkg.sh`](bsd/BuildPkg.sh) | FreeBSD (Native) | `build/bsd/wayplank`, `build/bsd/wayplank-<ver>.pkg` | Calls `BuildBsd.sh` and creates a native FreeBSD `pkg(8)` archive installing under `/usr/local/` (with automatic `glib-compile-schemas` and `SIGWINCH` live reload). |
| **`builders/windows/`** | [`BuildWin.sh`](windows/BuildWin.sh) | Linux (Cross) | `build/windows/wayplank.exe` | Transpiles Vala ➔ C (`build/windows/win_c/`), embeds Per-Monitor V2 HiDPI manifest + GSchemas + static `lunasvg`, links the monolithic PE32+ binary against `./deps/win32/sysroot`, and enforces the **Zero-DLL Evergreen OS Allowlist (`objdump -p`)**. |
| **`builders/windows/`** | [`BuildNsis.sh`](windows/BuildNsis.sh) | Linux (Cross) | `build/windows/wayplank.exe`, `build/windows/WayPlank-<ver>-Setup.exe` | Calls `BuildWin.sh` and packages the 64-bit LZMA NSIS installer with automatic running-instance shutdown during upgrades, Start Menu shortcuts, and clean uninstaller. |

---

## 3. Quick Commands (Run from Repository Root)

```bash
# Linux — Debian/Ubuntu (.deb), then Fedora/openSUSE (.rpm) sequentially
WAYPLANK_NO_PROMPT=1 ./builders/linux/BuildDeb.sh
WAYPLANK_NO_PROMPT=1 ./builders/linux/BuildRpm.sh

# FreeBSD — Run natively on a FreeBSD 14.x / 15.x / GhostBSD host
WAYPLANK_NO_PROMPT=1 ./builders/bsd/BuildPkg.sh

# Windows — Cross-compile Zero-DLL monolith + 64-bit NSIS installer on Linux
WAYPLANK_NO_PROMPT=1 ./builders/windows/BuildNsis.sh
```

---

## 4. Automated Quality & Architecture Gates Enforced at Build Time

Every release build enforces the following non-negotiable gates before emitting a package:

- **Monolithic Single-Binary Invariant:** Zero runtime `libplank.so` shared library; all internal libraries, 6 stock themes, 107 embedded SVGs, 8-language `.mo` catalogs (`588/588` strings), and `VERSION` metadata are embedded inside the single executable.
- **8-Gate Dual-Zone HAL Purity Firewall (Linux & FreeBSD):** Fails the build immediately if any OS-specific API (`Posix.*`, `DesktopAppInfo`, `GtkLayerShell`, `/proc`, `/sys`, `.desktop` parsing, or compositor branching) leaks into Zone 1 (`src/`, `lib/`) or Zone 2 (`hal/Interfaces/`), or if `/proc`/`/sys` leaks into `hal/BSD/`.
- **Vala Closure `GDestroyNotify` / Pitfall #14 UAF Scan:** Inspects compiled machine code via `objdump` (Linux) / `llvm-objdump` (FreeBSD) to guarantee `0` dangling `blockN_data_unref` closure allocations.
- **Windows Zero-DLL Gate (`objdump -p`):** Guarantees `build/windows/wayplank.exe` imports **only** evergreen stock Windows OS DLLs (`25` system DLLs; zero GTK, MinGW, MSYS2, or Cygwin DLLs).
