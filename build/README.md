# WayPlank Prebuilt Multi-OS Deliverables (`build/`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Current Qualified Release:** `v0.7.4` (Final Public Beta 5 — **`942/942` `100.0%` 7-Platform FAT Qualified & FROZEN**, [`FAT/2026-11-25 FAT 0.7.4.txt`](../FAT/2026-11-25%20FAT%200.7.4.txt))  
> **How These Are Built:** [`builders/README.md`](../builders/README.md)

---

## 1. Directory Layout & Rationale

Every operating system stores its standalone monolithic binary and native installer/package inside its own isolated folder:

```text
build/
├── linux/
│   ├── wayplank                       # Standalone monolithic Linux ELF binary (x86_64)
│   ├── wayplank_<ver>_amd64.deb       # Debian / Ubuntu / Mint / Pop!_OS package
│   └── wayplank-<ver>-1.x86_64.rpm    # Fedora / openSUSE / RHEL-family package
├── bsd/
│   ├── wayplank                       # Standalone monolithic FreeBSD ELF binary (amd64)
│   └── wayplank-<ver>.pkg             # Native FreeBSD 15.x / GhostBSD 15.x pkg(8) archive
└── windows/
    ├── wayplank.exe                   # Portable Zero-DLL Windows monolith (x64, Win 7 <-> 11+)
    └── WayPlank-<ver>-Setup.exe       # 64-bit LZMA Windows Installer (NSIS)
```

**Why separate `build/linux/`, `build/bsd/`, and `build/windows/`?**
- Both **Linux** and **FreeBSD** produce a POSIX executable named `wayplank`. Keeping them in separate subdirectories prevents binary collisions and makes it unmistakable which ELF binary targets the Linux kernel (`hal/Linux/`) vs. the FreeBSD kernel (`hal/BSD/`).
- Mirrors the 3-Zone HAL repository structure 1:1 (`hal/{Linux,BSD,Windows}/` ↔ `builders/{linux,bsd,windows}/` ↔ `build/{linux,bsd,windows}/`).

---

## 2. Which File Should I Use?

### 🐧 Linux (`build/linux/`)
- **Debian / Ubuntu (`amd64`):**
  ```bash
  sudo apt install ./build/linux/wayplank_0.7.4_amd64.deb
  ```
- **openSUSE / Fedora (`x86_64`):**
  ```bash
  sudo zypper install ./build/linux/wayplank-0.7.4-1.x86_64.rpm   # openSUSE
  sudo dnf install ./build/linux/wayplank-0.7.4-1.x86_64.rpm      # Fedora
  ```
- **Standalone / Other Distros:** Copy `build/linux/wayplank` or rebuild natively in seconds with `./builders/linux/BuildBin.sh`.

### 😈 FreeBSD & GhostBSD (`build/bsd/`)
- **FreeBSD 15.x / GhostBSD 15.x (`amd64`):**
  ```sh
  sudo pkg add -f ./build/bsd/wayplank-0.7.4.pkg
  ```
- **FreeBSD 14.x, `aarch64` (ARM64), or custom `ports` trees:** Rebuild natively on FreeBSD (~2 min) with `./builders/bsd/BuildPkg.sh` so `pkg create` binds your exact local ABI and library versions.

### 🪟 Windows (`7 ⟷ 11+`, `build/windows/`)
- **Recommended Installer:** Run **`WayPlank-0.7.4-Setup.exe`** (automatically closes any running WayPlank instance during upgrades, installs to `Program Files\WayPlank`, and registers Start Menu / clean uninstaller).
- **Portable Zero-DLL Executable:** Copy **`wayplank.exe`** anywhere and double-click — requires **zero external DLLs** (only 25 stock Windows OS DLLs; extracts embedded GTK3 GSchemas automatically to `%LOCALAPPDATA%\WayPlank\glib-2.0\schemas`).
