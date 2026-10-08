# Wayplank V0.4.1 Detailed Technical Changelog

Release Milestone: **V0.4.1** (KWin Multi-Monitor Stabilization & Core Modernization)  
Archive Source: `0.4.1_Wayland- Kwin fully supported bugfixes.zip` (Wayland — KWin Fully Supported Bugfixes)  
Release Date: 2026-09-25  
Author & Maintainer: Sergio Melas (sergiomelas@gmail.com)

---

## 1. 🖥️ (KWin / Wayland) Multi-Monitor Tracking & Display Persistence (`PositionManager.vala`)

- **Resolution of Multi-Monitor Selection Bugs**:
  - In v0.4.0, selecting a different output monitor in Preferences did not immediately reposition the dock surface or persisted monitor choice across restarts.
  - **Fixes in `lib/PositionManager.vala`**:
    - Ensured that changing the active display triggers immediate layer-shell margin and monitor binding updates.
    - Persisted chosen monitor IDs to GSettings, ensuring the dock reappears on the correct output after system reboots.
    - Added automatic primary monitor fallback: if a previously selected external monitor is disconnected, the dock gracefully repositions to the primary display instead of remaining off-screen or crashing.

---

## 2. 🎯 (KWin / Wayland) Tooltip Coordinate Translation Across Displays (`DockWindow.vala`)

- **Secondary Monitor Tooltip Placement Fix**:
  - Addressed a major UX defect where hovering over icons on a secondary monitor caused tooltips to render on the primary monitor.
  - **Resolution**: Translated icon bounding coordinates relative to the specific `Gdk.Monitor` hosting the dock surface rather than using root screen coordinates, ensuring tooltips render centered above/below their respective icons with correct pointer arrows.

---

## 3. 🚀 (Cross-Compositor / Core) Animation Smoothness & De-Polling (`lib/Drawing/Easing.vala`)

- **Elimination of Micro-Stutters During Zoom Animation**:
  - Refactored `lib/Drawing/Easing.vala` (87 lines) and `DockRenderer.vala`:
    - Deactivated system configuration file and GSettings polling during active icon zoom sequences.
    - Caching configuration values in memory prevented I/O latency from interrupting the 60 FPS animation loop.
    - Adjusted zoom bounding calculations to prevent icon textures from being clipped during parabolic scaling.

---

## 4. 🎨 (Cross-Compositor / Theming) Bundled Arian Themes & Legacy Unity Purge

- **Introduction of Arian Themes**:
  - Bundled two high-contrast, modern themes:
    - `data/themes/Arian Theme/dock.theme` (+66 lines)
    - `data/themes/Arian Theme Light/dock.theme` (+66 lines)
- **Dead Code Purge**:
  - Excised `lib/Services/Unity.vala` (-22 lines) and obsolete X11 window hooks.
  - Cleaned dozens of compiler warnings across Vala sources, modernizing nullability and reference ownership annotations.

---

## 5. 📦 Summary of Touched Files & Code Metrics

| Subsystem | File | Lines Changed | Key Modifications |
| :--- | :--- | :--- | :--- |
| **Positioning** | `lib/PositionManager.vala` | 62 lines changed | Fixed display switching, persistence, and disconnect fallback. |
| **Tooltips** | `lib/Widgets/DockWindow.vala` | 43 lines changed | Monitor-relative coordinate translation for secondary screens. |
| **Animation** | `lib/Drawing/Easing.vala` | 87 lines changed | Zoom curve smoothing and de-polling during active gestures. |
| **Themes** | `data/themes/Arian Theme*` | +132 lines | Added modern Arian Theme and Arian Theme Light configurations. |
| **Legacy Cleanup** | `lib/Services/Unity.vala` | -22 lines (Purged) | Removed obsolete Ubuntu Unity integration. |
