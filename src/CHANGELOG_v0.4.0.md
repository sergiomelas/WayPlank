# Wayplank V0.4.0 Detailed Technical Changelog

Release Milestone: **V0.4.0** (KWin Fully Supported & Modular Window Management Architecture)  
Archive Source: `0.4_Wayland- Kwin fully supported.zip` (Wayland — KWin Fully Supported)  
Release Date: 2026-09-24  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 🌟 Modular Window Backend Architecture & KWin Scripting Bridge

- **Creation of the Modular Window Management Stack**:
  - Engineered a brand new modular window management subsystem in `lib/Services/`:
    - `WindowBackend.vala` (+39 lines): Abstract interface defining window listing, state tracking, and window actions.
    - `WindowCapabilities.vala` (+73 lines): Compositor capability matrix (supports minimize, raise, close, geometry).
    - `WindowInfo.vala` (+42 lines): Struct representing window handles, titles, `app_id`, active/minimized states, and geometry.
    - `WindowManager.vala` (+166 lines): High-level cache coordinating window focus, window matching, and visibility.
    - `KWinBackend.vala` (+90 lines) & `KWinDbus.vala` (+45 lines): Native backend implementation for KDE KWin.
- **Deep KWin Scripting Engine (`lib/Services/KWinBridge.vala`, +293 lines)**:
  - Dynamically registers and executes ECMAScript code within KWin via D-Bus (`org.kde.KWin.Scripting`):
    - Subscribes to `workspace.windowActivated`, `clientAdded`, `clientRemoved`, `client.frameGeometryChanged`, and `client.minimizedChanged`.
    - Broadcasts structured JSON window updates back to Wayplank via D-Bus signals, providing 100% accurate window state without X11.

---

## 2. 🛡️ Real-Time Window Dodge & Intellihide Engine (`HideManager.vala`)

- **Dynamic Overlap Calculation (+131 lines in `HideManager.vala`)**:
  - Implemented real-time geometric intersection tests between dock boundaries and active window frames:
    - **Intellihide**: Automatically conceals the dock when any window overlaps its boundary; reveals when windows move away.
    - **Dodge Active Window**: Hides only when the currently focused/active window intersects the dock.
    - **Dodge Maximized Window**: Automatically hides the dock whenever a window on the current workspace is maximized.
- **Dynamic Layer-Shell Exclusive Zone Negotiation**:
  - When in `AUTOHIDE` or `DODGE` modes, dynamically sets the Layer Shell exclusive zone to `0`, allowing full-screen windows to occupy the display while preserving edge pressure detection.

---

## 3. 🔍 Application Identity Resolution (`ApplicationDiscovery.vala` & `ApplicationIdentity.vala`)

- **Robust App Discovery Engine (+354 lines)**:
  - Created `ApplicationDiscovery.vala` (+258 lines) and `ApplicationIdentity.vala` (+96 lines):
    - Recursively parses desktop entry hierarchies (`/usr/share/applications`, `~/.local/share/applications`).
    - Maps process `comm` and command line tokens to `StartupWMClass`, `Exec`, and `Name` metadata.
    - **Transient Filtering**: Prevented system tray icons, background notification daemons, and plasma widgets from incorrectly spawning temporary dock icons.

---

## 4. 🗑️ Purge of Legacy Dynamic Docklet Plugins & Introduction of Separators

- **Excision of 530+ Lines of Dead Plugin Infrastructure**:
  - Completely removed the unmaintained external plugin architecture:
    - `lib/Docklets/DockletManager.vala` (-213 lines)
    - `lib/Widgets/DockletViewModel.vala` (-251 lines)
    - `lib/Docklets/Docklet.vala` (-40 lines) and `lib/Docklets/DockletItem.vala` (-30 lines)
- **First Introduction of Dynamic Separator (`SeparatorDockItem.vala`, +109 lines)**:
  - Implemented `SeparatorDockItem.vala` to act as an intuitive visual divider between pinned launchers and running transient application icons.

---

## 5. 📦 Summary of Touched Files & Code Metrics

| Subsystem | File | Lines Changed | Key Modifications |
| :--- | :--- | :--- | :--- |
| **KWin Bridge** | `lib/Services/KWinBridge.vala` | +293 lines | Complete D-Bus ECMAScript bridge for KWin window tracking. |
| **Backend HAL** | `WindowBackend.vala`, `WindowManager.vala` | +317 lines | Modular window backend and window manager architecture. |
| **App Discovery** | `ApplicationDiscovery.vala`, `ApplicationIdentity.vala` | +354 lines | Desktop file indexing, process mapping, and tray filtering. |
| **Hide Engine** | `lib/HideManager.vala` | +131 lines | Window Dodge and Intellihide overlap calculation. |
| **Separator** | `lib/Items/SeparatorDockItem.vala` | +109 lines (New) | Visual divider separating pinned and transient items. |
| **Plugin Purge** | `DockletManager.vala`, `DockletViewModel.vala` | -534 lines | Purged legacy dynamic docklet plugin infrastructure. |
