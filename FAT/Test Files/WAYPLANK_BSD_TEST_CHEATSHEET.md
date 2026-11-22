# 😈 WayPlank FreeBSD / GhostBSD Build & Testing Cheatsheet (`FreeBSD 14.x / 15.x`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Target Assets:** `build/bsd/wayplank` (Native FreeBSD ELF Monolith) • `build/bsd/wayplank-<ver>.pkg` (Native FreeBSD Package)  
> **Key Architectural Fact:** Unlike Windows (`builders/windows/BuildWin.sh` cross-compiled on Linux via MinGW-w64), **FreeBSD builds are 100% NATIVE on FreeBSD** — they link native FreeBSD base libraries (`libprocstat`, `libkvm`, `libdevstat`) and package via official FreeBSD `pkg create`.

---

## 1. For Native FreeBSD / GhostBSD Users (Bare Metal)

If you are already running **FreeBSD 14.x / 15.x** or **GhostBSD** on physical hardware (Intel/AMD GPU with `drm-kmod` providing `/dev/dri/card0` and a Wayland session such as `Labwc`, `KDE Plasma Wayland`, or `XFCE 4.20 Wayland`), **you do NOT need a VM**:

```sh
# 1. Install build prerequisites:
sudo pkg install -y \
    git vala pkgconf gmake gettext-tools python3 \
    gtk3 gtk-layer-shell libgee json-glib wayland wayland-protocols

# 2. Build standalone binary (enforces all 8 HAL Purity Firewall gates):
./builders/bsd/BuildBsd.sh

# 3. Or build + create & install the native FreeBSD .pkg under /usr/local:
./builders/bsd/BuildPkg.sh
sudo pkg add -f ./build/bsd/wayplank-<ver>.pkg
```

*(See repository root [`README.md §5`](../../README.md) for full bare-metal installation and manual step-by-step compilation instructions.)*

### FreeBSD Runtime Paths
- **Installed Binary & Symlink:** `/usr/local/bin/wayplank` (`plank -> wayplank`)
- **Desktop Entry, Icons & GSettings Schemas:** `/usr/local/share/{applications,icons/hicolor,glib-2.0/schemas}`
- **User Dock Config & Unified Registry:** `~/.config/wayplank/latch-state.ini`
- **Custom Non-Destructive Shortcut Names:** `~/.config/wayplank/launcher-names.ini`
- **Dock Launchers (`dock1`–`dock4`):** `~/.config/wayplank/dock1/launchers/*.dockitem`
- **Custom User Themes:** `~/.local/share/wayplank/themes/`
- **Run from Build Tree (Without Installing `.pkg`):**
  ```sh
  GSETTINGS_SCHEMA_DIR="$PWD/data/glib-2.0/schemas" ./build/bsd/wayplank -v
  ```

---

## 2. For Linux Maintainers — Why a FreeBSD Test VM Is Required

Because FreeBSD binaries link native FreeBSD kernel/userland shared libraries (`libprocstat.so.1`, `libkvm.so.7`, `libdevstat.so.7`, `libgtk-layer-shell.so.0`, `libwayland-client.so.0`) and `.pkg` archives require FreeBSD's official `pkg create` (ABI `FreeBSD:15:amd64`, SHA-256 manifests), **a Linux workstation cannot cross-compile `build/bsd/wayplank-<ver>.pkg`**.

To compile, package, and execute ISA-88 FAT testing from a Linux workstation, set up a lightweight FreeBSD/GhostBSD VM (works on **VMware**, **QEMU/KVM**, **VirtualBox**, **Proxmox**, etc.):

### 2.1 VM Sizing & Base Services
1. **VM Sizing:** FreeBSD 64-bit (`x86_64`), **GhostBSD** or stock **FreeBSD 15.x-RELEASE** ISO; `2–4` vCPUs, `4 GB` RAM, `30–40 GB` disk, **Bridged** or **NAT** NIC.
2. **Cap ZFS ARC Memory (Prevents VM RAM Ballooning):**
   ```sh
   sudo sysrc -f /boot/loader.conf vfs.zfs.arc_max="512M"
   # Reboot once, or apply live: sudo sysctl vfs.zfs.arc.max=536870912
   ```
3. **Enable SSH & Disable Guest Firewall (Isolated Local Test VM Only):**
   ```sh
   sudo sysrc sshd_enable="YES"
   sudo service sshd start
   sudo sysrc firewall_enable="NO"
   sudo service ipfw onestop
   ```
4. **Passwordless SSH & Fast `rsync` Workflow (Linux Host ↔ FreeBSD VM):**
   ```bash
   # Inside VM (find guest IP):
   ifconfig | grep "inet "

   # From Linux host (one-time key install):
   ssh-copy-id -i ~/.ssh/id_ed25519.pub <user>@<VM_IP>

   # Sync Linux repo -> FreeBSD VM (always edit sources on Linux host!):
   rsync -avz --delete --exclude='.git/' --exclude='build/' --exclude='deps/' \
       /path/to/WayPlank/ <user>@<VM_IP>:~/WayPlank/

   # Trigger remote native FreeBSD build & .pkg packaging:
   ssh <user>@<VM_IP> "cd ~/WayPlank && WAYPLANK_NO_PROMPT=1 ./builders/bsd/BuildPkg.sh"

   # Retrieve compiled deliverables back into Linux repo build/bsd/:
   scp <user>@<VM_IP>:'~/WayPlank/build/bsd/wayplank*' /path/to/WayPlank/build/bsd/
   ```
5. **Install Build, Wayland & Clipboard-Bridge Packages Inside the VM:**
   ```sh
   sudo pkg update
   sudo pkg install -y \
       rsync git vala pkgconf gmake gettext-tools python3 \
       gtk3 gtk-layer-shell libgee json-glib wayland wayland-protocols \
       labwc seatd dbus gvfs grim slurp swaylock dunst wl-clipboard xclip
   ```
6. **Enable `dbus` + `seatd` + `video` Group:**
   ```sh
   sudo sysrc dbus_enable="YES"
   sudo sysrc seatd_enable="YES"
   sudo service dbus start
   sudo service seatd start
   sudo pw groupmod video -m "$USER"
   ```

### 2.2 Fullscreen Wayland on Hypervisors Without FreeBSD Kernel DRM (`VMware SVGA II` / `VirtualBox`)
FreeBSD's `drm-kmod` ships bare-metal GPU drivers only (`amdgpu`, `i915kms`, `radeonkms`); virtual GPU DRM modules (`vmwgfx`, `vboxvideo`) were removed, so `/dev/dri/card0` does not exist inside VMware or VirtualBox guests.

To boot **100% native fullscreen Wayland (`XFCE 4.20 Wayland + labwc + Xwayland`)** directly from LightDM while keeping VMware auto-resize and host ↔ guest copy/paste:
1. Compile a minimal `libX11` borderless fullscreen helper (`/usr/local/bin/wlr-x11-fullscreen`) that tracks `MapNotify`/`ConfigureNotify` on outer `:0` and calls `XMoveResizeWindow(dpy, win, 0, 0, DisplayWidth, DisplayHeight)`.
2. Install a bidirectional clipboard bridge (`/usr/local/bin/wlr-x11-clipbridge`) syncing outer `:0` (`xclip`, updated by `vmtoolsd -n vmusr`) ↔ inner `$WAYLAND_DISPLAY` (`wl-copy`/`wl-paste`).
3. Wrap the session in `/usr/local/bin/start-vmware-wayland` calling `xset s off s noblank`, exporting `WLR_BACKENDS=x11`, `WLR_RENDERER=pixman`, `WLR_X11_OUTPUTS=1`, `XDG_SESSION_TYPE=wayland`, `GDK_BACKEND=wayland`, `QT_QPA_PLATFORM=wayland`, launching `vmware-user-suid-wrapper`, `wlr-x11-fullscreen`, and `wlr-x11-clipbridge`, and executing `dbus-run-session -- startxfce4 --wayland`.
4. **Prevent VMware Black Screen on Idle (Disable Screensaver & Wayland DPMS):**
   ```sh
   xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -n -t bool -s false
   xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -n -t int -s 0
   mkdir -p ~/.config/autostart
   printf "[Desktop Entry]\nType=Application\nName=Screensaver\nHidden=true\n" > ~/.config/autostart/xfce4-screensaver.desktop
   ```
5. Register `/usr/local/share/xsessions/xfce-vmware-wayland.desktop` pointing to `/usr/local/bin/start-vmware-wayland xfce`, and clean `/usr/local/etc/lightdm/lightdm.conf` so only the working Wayland & X11 fallback sessions appear:
   ```ini
   [LightDM]
   sessions-directory=/usr/local/share/xsessions
   [Seat:*]
   user-session=xfce-vmware-wayland
   ```
6. Take a clean VM snapshot once logged into `Xfce Wayland (VMware Fullscreen)` with `labwc` and `Xwayland :1` verified active.

---

## 3. Shared OS-Agnostic FAT Assets
- **Sample Drag & Drop Files:** `Files\` (`Test.txt`, `WayPlank_FAT_BugSquash.png`, `Sergio Melas CV.pdf`)
- **Sample Custom Theme Archives:** `Themes\` (`Glassier Cool Edition.zip`, `.tar.gz`, `Multi_Theme_Pack.zip`)
- **Linux/Freedesktop FAT Testers:** `Freedesktop\` (reused identically on FreeBSD Wayland sessions)
