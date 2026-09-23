# Wayplank V0.3.0 Detailed Technical Changelog

Release Milestone: **V0.3.0** (Wayland Hover Stabilization & Early KWin Integration)  
Archive Source: `0.3_Wayland- Kwin partially supported.zip` (Wayland — KWin Partially Supported)  
Release Date: 2026-09-23  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 🌉 Inception of KWin Scripting Bridge (`lib/Services/KWinBridge.vala`)

- **First Integration with KDE KWin (+136 lines in `KWinBridge.vala`)**:
  - Recognizing that pure `/proc` process tracking lacks window focus and geometry awareness, Wayplank introduced its very first native compositor bridge: `KWinBridge.vala`.
  - Established a D-Bus connection to `org.kde.KWin`, laying the groundwork for live client window tracking directly from KDE Plasma's compositor rather than guessing from filesystem processes.

---

## 2. ✂️ Total Purge of XInput, XFixes & BAMF VAPIs (800+ Lines Excised)

- **Eradication of Obsolete X11 VAPI Bindings**:
  - Completely deleted legacy VAPI bindings from the `vapi/` tree:
    - `vapi/xi.vapi` (-580 lines): Purged XInput 2 device grab and pointer tracking definitions.
    - `vapi/libbamf3.vapi` (-171 lines) and `vapi/libbamf3.deps`: Completely eliminated the BAMF application matching daemon dependency.
    - `vapi/xfixes.vapi` (-40 lines): Excised XFixes barrier and selection tracking.
- **Excising Legacy `WindowControl.vala` (-484 lines)**:
  - Completely dismantled the original 484-line X11 `WindowControl.vala` class that depended on `Wnck.Screen`, `Wnck.Window`, and Xlib event atoms, replacing it with an abstracted stub interface awaiting native Wayland backends.

---

## 3. 🎯 Pointer Crossing Lifecycle & Hover Zoom Stabilization

- **Wayland Hover Zoom Stabilization (`DockWindow.vala` & `DockRenderer.vala`)**:
  - Fixed a persistent defect under Wayland where moving the cursor across the dock surface failed to trigger icon magnification or caused icons to remain stuck in an expanded state.
  - Rewrote pointer enter/leave/motion event handlers:
    - Added clean coordinate translation accounting for Layer Shell subsurface boundaries.
    - Eliminated legacy X11 pointer grab calls that caused compositor deadlocks.
    - Restored reliable dock hide/show state machine transitions on border crossings.

---

## 4. 📌 Application Pinning & Multi-Instance Indicators

- **Refactoring `ApplicationDockItem.vala` (-294 lines of legacy code)**:
  - Stripped legacy Unity launcher API bindings and BAMF signal connections.
  - Implemented drag-and-drop launcher pinning and right-click "Keep in Dock" configuration persistence.
  - Integrated Cairo-rendered indicator dots reflecting running application instances directly from `Matcher` process counts.

---

## 5. 📦 Summary of Touched Files & Code Metrics

| Subsystem | File | Lines Changed | Key Modifications |
| :--- | :--- | :--- | :--- |
| **KWin Bridge** | `lib/Services/KWinBridge.vala` | +136 lines (New) | First inception of KWin D-Bus integration. |
| **VAPI Purge** | `vapi/xi.vapi`, `vapi/libbamf3.vapi`, `vapi/xfixes.vapi` | -791 lines | Total removal of XInput, BAMF, and XFixes VAPI files. |
| **Window Control** | `lib/Services/WindowControl.vala` | -484 lines | Stripped legacy X11 Wnck/Xlib window controller. |
| **App Item** | `lib/Items/ApplicationDockItem.vala` | -294 lines | Modernized pinning and indicator dot drawing. |
| **Hover Engine** | `lib/Widgets/DockWindow.vala` | Refactored | Fixed Wayland pointer crossing and zoom animations. |
| **Proc Scanner** | `lib/Services/Matcher.vala` | +87 lines | Enhanced active app and PID registration. |
