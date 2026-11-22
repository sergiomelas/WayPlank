# 🪟 WayPlank Windows Testing Cheatsheet (`Win 7 ⟷ 11+`)

> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026  
> **Target Assets:** `build/windows/wayplank.exe` (Zero-DLL Portable) • `build/windows/WayPlank-<ver>-Setup.exe` (64-bit NSIS Installer)

---

## 1. Building on Linux Host
```bash
# Build portable Zero-DLL build/windows/wayplank.exe (uses cached deps/win32/sysroot):
WAYPLANK_NO_PROMPT=1 ./BuildWin.sh

# Build portable build/windows/wayplank.exe + 64-bit NSIS installer build/windows/WayPlank-0.7.3.2-Setup.exe:
WAYPLANK_NO_PROMPT=1 ./BuildNsis.sh

# Verify Zero-DLL evergreen OS import allowlist manually:
x86_64-w64-mingw32-objdump -p build/windows/wayplank.exe | grep "DLL Name:"
```

## 2. Installing & Running on Windows 10/11 (Virtual Machine / Bare Metal)
- **System-Wide Install (Admin):** Run `WayPlank-0.7.3.2-Setup.exe` → installs to `C:\Program Files\WayPlank\wayplank.exe`.
- **Per-User Install (No Admin):** Run `WayPlank-0.7.3.2-Setup.exe` → select Current User → installs to `%LOCALAPPDATA%\Programs\WayPlank\wayplank.exe`.
- **Portable Run:** Copy `wayplank.exe` anywhere and double-click (zero DLLs needed).

## 3. Windows Runtime Paths
- **Dock Config & Unified Registry:** `%LOCALAPPDATA%\wayplank\latch-state.ini`
- **Custom Non-Destructive Shortcut Names:** `%LOCALAPPDATA%\wayplank\launcher-names.ini`
- **Dock Launchers (`dock1`–`dock4`):** `%LOCALAPPDATA%\wayplank\dock1\launchers\*.dockitem`
- **Custom User Themes:** `%LOCALAPPDATA%\wayplank\themes\`
- **Persistent Start Menu `.lnk` Index Cache:** `%LOCALAPPDATA%\WayPlank\lnk-index-cache.ini`
- **Hardware Brightness Capabilities Cache:** `%LOCALAPPDATA%\WayPlank\hw-caps-cache.ini`
- **Auto-Extracted GSettings Schema:** `%LOCALAPPDATA%\WayPlank\glib-2.0\schemas\gschemas.compiled`
- **Autostart Registry Value:** `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` → `WayPlank`

## 4. Running Windows FAT Testers (PowerShell)
Run from `FAT\Test Files\` (or adjust paths if running from `FAT\Test Files\Windows\`):
```powershell
# Fullscreen inhibit test (F11 / Space to toggle, Esc to quit):
powershell -ExecutionPolicy Bypass -File "Windows\Testers\test_fullscreen.ps1"

# Windows Notification / Focus Assist test:
powershell -ExecutionPolicy Bypass -File "Windows\Testers\test_notification.ps1"

# Win32 FlashWindowEx Urgency / DemandsAttention test:
powershell -ExecutionPolicy Bypass -File "Windows\Testers\test_urgency.ps1"

# Test all 8 embedded languages without changing Windows OS language:
powershell -ExecutionPolicy Bypass -File "Windows\Localization\switch_lang.ps1" zh_CN

# Test fault-tolerant latch-state.ini recovery & clean first-run onboarding:
powershell -ExecutionPolicy Bypass -File "Windows\Environment\Test-Environments.ps1"
```

## 5. Shared OS-Agnostic Assets
- **Sample Drag & Drop Files:** `Files\` (`Test.txt`, `WayPlank_FAT_BugSquash.png`, `Sergio Melas CV.pdf`)
- **Sample Custom Theme Archives:** `Themes\` (`Glassier Cool Edition.zip`, `.tar.gz`, `Multi_Theme_Pack.zip`)

---

## 6. Generic Test VM Setup Procedure (Hypervisor-Agnostic)

Works on any desktop or server hypervisor (**QEMU/KVM `virt-manager`**, **VirtualBox**, **Proxmox**, **Hyper-V**, etc.):

### 6.1 Windows 10 / 11 Test VM
1. **VM Sizing:** 64-bit (`x86_64`), `2–4` vCPUs, `4–8 GB` RAM, `50–60 GB` virtual disk, **Bridged** or **NAT** virtual NIC.
2. **Guest Tools & Display:** Install the hypervisor's guest drivers for dynamic display resize and HiDPI scale testing (`100%`, `125%`, `150%`), plus optional second virtual display for multi-monitor FAT (`14.6`).
3. **Host ↔ VM File Transfer:** Use a shared folder, SMB share, or built-in Windows OpenSSH Server (`Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0` + `Start-Service sshd`) to copy `build/wayplank.exe`, `build/WayPlank-<ver>-Setup.exe`, and `FAT/Test Files/` directly into the guest.
4. **Clean FAT Snapshot:** Take a clean VM snapshot **before** installing WayPlank so First-Run Onboarding (`1.9`) and fresh-install tests (`15.1`–`15.6`) can be re-run cleanly anytime.

### 6.2 FreeBSD / GhostBSD Test VM (`v0.7.4` `hal/BSD/`)
1. **VM Sizing:** FreeBSD 64-bit (`x86_64`) using a **GhostBSD** or stock **FreeBSD 15.x-RELEASE** ISO; `2–4` vCPUs, `4 GB` RAM, `30–40 GB` disk, **Bridged** or **NAT** NIC (with host-to-guest routing or port-forwarding `2222 -> 22` under user-mode NAT).
2. **Cap ZFS ARC Memory (Prevents VM RAM Ballooning):**
   ```sh
   sudo sysrc -f /boot/loader.conf vfs.zfs.arc_max="512M"
   # Reboot once, or apply live: sudo sysctl vfs.zfs.arc.max=536870912
   ```
3. **Enable SSH & SFTP for Host File-Manager / `rsync` Access:**
   ```sh
   sudo sysrc sshd_enable="YES"
   sudo service sshd start

   # Disable guest firewall on isolated local test VMs (or allow TCP/22 explicitly):
   sudo sysrc firewall_enable="NO"
   sudo service ipfw onestop
   ```
4. **Passwordless SSH & Fast `rsync` Sync from Linux Host:**
   ```bash
   # Inside VM (find guest IP):
   ifconfig | grep "inet "

   # From Linux host (install SSH key once, then sync sources before each remote build):
   ssh-copy-id -i ~/.ssh/id_ed25519.pub <user>@<VM_IP>
   rsync -avz --delete --exclude='.git/' --exclude='build/' --exclude='deps/' \
       /path/to/WayPlank/ <user>@<VM_IP>:~/WayPlank/
   ```
   *(Tip: To keep `<VM_IP>` fixed across reboots, configure a DHCP reservation on your virtual router or set a static IP with `sysrc ifconfig_<nic>="inet <IP>/24"` and `sysrc defaultrouter="<GW>"`.)*
5. **Install WayPlank Build, Wayland & Clipboard-Bridge Packages Inside the VM:**
   ```sh
   sudo pkg update
   sudo pkg install -y \
       rsync git vala pkgconf gmake gettext-tools python3 \
       gtk3 gtk-layer-shell libgee json-glib wayland wayland-protocols \
       labwc seatd dbus gvfs grim slurp swaylock dunst wl-clipboard xclip
   ```
6. **Enable Wayland Session Services (`dbus` + `seatd` + `video` group):**
   ```sh
   sudo sysrc dbus_enable="YES"
   sudo sysrc seatd_enable="YES"
   sudo service dbus start
   sudo service seatd start
   sudo pw groupmod video -m "$USER"
   ```
   On bare-metal Intel/AMD hardware (`drm-kmod` providing `/dev/dri/card0`), log out and start a Wayland session directly (`dbus-run-session startxfce4 --wayland`, `dbus-run-session labwc`, or KDE Plasma Wayland).
7. **Fullscreen Wayland Session on Hypervisors Without FreeBSD Kernel DRM (`VMware SVGA II` / `VirtualBox`):**
   FreeBSD `drm-kmod` ships only bare-metal GPU drivers (`amdgpu`, `i915kms`, `radeonkms`) — `vmwgfx` and `vboxvideo` were removed, so `/dev/dri/card0` does not exist inside VMware/VirtualBox guests. To boot **100% native fullscreen Wayland (`XFCE 4.20 Wayland + labwc + Xwayland`)** directly from LightDM while preserving host ↔ guest resize and clipboard:
   - Compile a minimal `libX11` borderless fullscreen helper (`/usr/local/bin/wlr-x11-fullscreen`) that tracks `MapNotify`/`ConfigureNotify` on the outer SVGA II framebuffer (`:0`) and calls `XMoveResizeWindow(dpy, win, 0, 0, DisplayWidth, DisplayHeight)`.
   - Install a bidirectional clipboard bridge (`/usr/local/bin/wlr-x11-clipbridge`) using `xclip` (`:0`, synced by `vmtoolsd -n vmusr`) ↔ `wl-copy`/`wl-paste` (`$WAYLAND_DISPLAY`).
   - Wrap the session in `/usr/local/bin/start-vmware-wayland` calling `xset s off s noblank`, exporting `WLR_BACKENDS=x11`, `WLR_RENDERER=pixman`, `WLR_X11_OUTPUTS=1`, `XDG_SESSION_TYPE=wayland`, `GDK_BACKEND=wayland`, `QT_QPA_PLATFORM=wayland`, starting `vmware-user-suid-wrapper`, `wlr-x11-fullscreen`, and `wlr-x11-clipbridge`, and executing `dbus-run-session -- startxfce4 --wayland`.
   - **Prevent VMware Black Screen on Idle (Disable Screensaver & Wayland DPMS):** Under `WLR_BACKENDS=x11`, `xfce4-power-manager` / `xfce4-screensaver` output-blanking can leave the Wayland output black with only the cursor visible. Disable both permanently inside the VM:
     ```sh
     xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -n -t bool -s false
     xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -n -t int -s 0
     mkdir -p ~/.config/autostart
     printf "[Desktop Entry]\nType=Application\nName=Screensaver\nHidden=true\n" > ~/.config/autostart/xfce4-screensaver.desktop
     ```
   - Register `/usr/local/share/xsessions/xfce-vmware-wayland.desktop` pointing to `/usr/local/bin/start-vmware-wayland xfce`, and clean `/usr/local/etc/lightdm/lightdm.conf` to show only the working Wayland & X11 fallback sessions:
     ```ini
     [LightDM]
     sessions-directory=/usr/local/share/xsessions
     [Seat:*]
     user-session=xfce-vmware-wayland
     ```
   - Take a clean VM snapshot once logged into `Xfce Wayland (VMware Fullscreen)` with `labwc` and `Xwayland :1` verified active.
8. **Native FreeBSD Build (`8-Gate Firewall`) & Verbose Launch:**
   ```sh
   cd ~/WayPlank && WAYPLANK_NO_PROMPT=1 ./BuildBsd.sh
   GSETTINGS_SCHEMA_DIR="$PWD/data/glib-2.0/schemas" ./build/bsd/wayplank -v
   ```
