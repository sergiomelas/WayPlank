# 🖥️ WayPlank Compositors & Desktops Cheatsheet

> **Project:** WayPlank (Lightweight native Wayland dock based on Plank architecture)  
> **Author & Maintainer:** Sergio Melas (<sergiomelas@gmail.com>) © 2026

---

## 1. Mutter 50+ (Minimal Compositor Only — Standalone 800×600 Window)

### Installation
```bash
sudo apt install --no-install-recommends mutter mutter-dev-bin
```

### Test Method A (Recommended: Two Terminals)
- **Terminal 1** — Start persistent nested Mutter 800×600 window:
  ```bash
  MUTTER_DEBUG_DUMMY_MODE_SPECS=800x600 env -u LD_PRELOAD GTK_CSD=1 mutter --wayland --devkit --no-x11 --virtual-monitor=800x600 --wayland-display=wayland-9
  ```
- **Terminal 2** — Launch WayPlank inside that Mutter window (loads standard `dock1`):
  ```bash
  WAYLAND_DISPLAY=wayland-9 env -u LD_PRELOAD GTK_CSD=1 ./build/wayplank -r -d
  ```

### Test Method B (Single-Command One-Liner)
```bash
MUTTER_DEBUG_DUMMY_MODE_SPECS=800x600 env -u LD_PRELOAD GTK_CSD=1 mutter --wayland --devkit --no-x11 --virtual-monitor=800x600 --wayland-display=wayland-9 -- sh -c "env -u LD_PRELOAD GTK_CSD=1 ./build/wayplank -r -d"
```

### Screenshot Capture
```bash
WAYLAND_DISPLAY=wayland-0 spectacle -b -f -o ./screenshot.png
```

### Purge
```bash
sudo apt purge mutter mutter-dev-bin
sudo apt autoremove --purge
```

---

## 2. GNOME Shell & Mutter (Full GNOME Desktop with Extensions Support)

### Option A — Full Session for SDDM / GDM Login Menu (Recommended)
Installs GNOME Shell and the session file (`/usr/share/wayland-sessions/gnome.desktop`):
```bash
sudo apt install --no-install-recommends \
    gnome-session \
    gnome-shell \
    gnome-shell-extension-prefs \
    gnome-terminal
```

### Option B — Minimal for Nested Window Testing Only (No SDDM Menu Entry)
```bash
sudo apt install --no-install-recommends gnome-shell gnome-shell-extension-prefs gnome-terminal
```

### Test Method (Runs GNOME Shell inside a 1280×720 Nested Window on Host Wayland)
- **Terminal 1** — Start nested GNOME Shell:
  ```bash
  MUTTER_DEBUG_DUMMY_MODE_SPECS=1280x720 dbus-run-session gnome-shell --wayland --no-x11 --virtual-monitor=1280x720 --wayland-display=wayland-9
  ```
- **Terminal 2** — Launch WayPlank inside that GNOME nested window:
  ```bash
  WAYLAND_DISPLAY=wayland-9 dbus-run-session ./build/wayplank -d
  ```

### Managing WayPlank GNOME Shell Extension
- **Extensions directory**: `~/.local/share/gnome-shell/extensions/`
- **List installed extensions**:
  ```bash
  gnome-extensions list
  ```
- **Enable extension**:
  ```bash
  gnome-extensions enable wayplank-bridge@wayplank.org
  ```

### Purge
```bash
sudo apt purge \
    gnome-session \
    gnome-shell \
    gnome-shell-extension-prefs \
    gnome-terminal
sudo apt autoremove --purge
```

---

## 3. Labwc (wlroots Standalone Compositor)

### Installation (Includes `grim` & `slurp` for Native WayPlank Screenshot Docklet)
```bash
sudo apt install --no-install-recommends labwc grim slurp
```

### Test Command (Nested Window with WayPlank and Terminal)
```bash
dbus-run-session labwc -s "sh -c './build/wayplank -d & konsole'"
```

### Purge
```bash
sudo apt purge labwc grim slurp
sudo apt autoremove --purge
```

---

## 4. Desktops on Labwc

### 4.1 LXQt (Wayland Session on Labwc)

#### Installation
*(Note: `lxqt-wayland-session` provides `/usr/share/wayland-sessions/lxqt-wayland.desktop` for SDDM)*
```bash
sudo apt install --no-install-recommends \
    lxqt-core \
    lxqt-wayland-session \
    pcmanfm-qt \
    lxqt-panel \
    qterminal \
    grim \
    slurp
```

#### Test Command (Runs LXQt Session Inside a Nested Labwc Window with WayPlank)
```bash
dbus-run-session labwc -s "sh -c './build/wayplank -d & startlxqt'"
```

#### Purge
```bash
sudo apt purge \
    lxqt-core \
    lxqt-wayland-session \
    pcmanfm-qt \
    lxqt-panel \
    qterminal \
    grim \
    slurp
sudo apt autoremove --purge
```

---

### 4.2 XFCE (Desktop Session on Labwc)

#### Installation
```bash
sudo apt install --no-install-recommends \
    xfce4-session \
    xfce4-panel \
    xfdesktop4 \
    thunar \
    xfce4-terminal \
    grim \
    slurp
```

#### Test Command (Runs XFCE Desktop Inside a Nested Labwc Window with WayPlank)
```bash
dbus-run-session labwc -s "sh -c './build/wayplank -d & xfce4-session'"
```

#### Purge
```bash
sudo apt purge \
    xfce4-session \
    xfce4-panel \
    xfdesktop4 \
    thunar \
    xfce4-terminal \
    grim \
    slurp
sudo apt autoremove --purge
```

