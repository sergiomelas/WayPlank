#!/usr/bin/env bash
#
#  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
#  Copyright (C) 2026 Sergio Melas
#
#  This file is part of Wayplank.
#
#  Wayplank is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  Wayplank is distributed in the hope that it will be useful,
#  WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ==============================================================================
# Clean Debian Builder for Wayplank (Standalone & Self-Contained)
# Developed by Sergio Melas - 2026
# ==============================================================================
set -euo pipefail

# --- Dolphin Auto-Spawn GUI Terminal ---
if [ ! -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ]; then
    if command -v konsole >/dev/null 2>&1; then
        exec konsole -e bash "$0" "$@"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        exec x-terminal-emulator -e bash "$0" "$@"
    fi
fi

PKG_NAME="wayplank"
PKG_VER="0.5.2"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BASE_DIR}/build_workspace"
OUT_DIR="${BASE_DIR}/build"
ARCH="$(dpkg --print-architecture)"

export DEBFULLNAME="Sergio Melas"
export DEBEMAIL="sergiomelas@gmail.com"
MAINTAINER="${DEBFULLNAME} <${DEBEMAIL}>"

echo ""
echo "🚀 Wayplank Standalone Builder — V${PKG_VER} (Debian Integration)"
echo "─────────────────────────────────────────────────────────────────"
echo ""

# 1. Call the binary build script (BuildBin.sh)
if [ -f "${BASE_DIR}/BuildBin.sh" ]; then
    if ! WAYPLANK_NO_PROMPT=1 bash "${BASE_DIR}/BuildBin.sh"; then
        echo ""
        echo "❌ Build failed! Compilation error in BuildBin.sh"
        echo ""
        if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ]; then
            read -rp "👋 Press Enter to close..."
        fi
        exit 1
    fi
else
    echo "❌ Error: BuildBin.sh not found!"
    if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
    exit 1
fi

if [ ! -f "${OUT_DIR}/wayplank" ]; then
    echo ""
    echo "❌ Build failed! Binary '${OUT_DIR}/wayplank' was not generated."
    echo ""
    if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/usr/bin"
mkdir -p "$BUILD_DIR/usr/share/applications"
mkdir -p "$BUILD_DIR/usr/share/wayplank/themes"
mkdir -p "$BUILD_DIR/usr/share/icons/hicolor"
mkdir -p "$BUILD_DIR/usr/share/glib-2.0/schemas"

echo "📦 Copying compiled binary and resources..."
cp "${OUT_DIR}/wayplank" "${BUILD_DIR}/usr/bin/wayplank"
ln -s wayplank "${BUILD_DIR}/usr/bin/plank"

cp -r "${BASE_DIR}/data/themes/"* "${BUILD_DIR}/usr/share/wayplank/themes/"
ln -s wayplank "${BUILD_DIR}/usr/share/plank"
cp -r "${BASE_DIR}/data/icons/"* "${BUILD_DIR}/usr/share/icons/hicolor/"
mkdir -p "${BUILD_DIR}/usr/share/icons/hicolor/scalable/apps"
cp "${BASE_DIR}/data/wayplank.svg" "${BUILD_DIR}/usr/share/icons/hicolor/scalable/apps/wayplank.svg"
cp "${BASE_DIR}/data/wayplank.svg" "${BUILD_DIR}/usr/share/icons/hicolor/scalable/apps/plank.svg"
cp "${BASE_DIR}/data/glib-2.0/schemas/net.launchpad.plank.gschema.xml" "${BUILD_DIR}/usr/share/glib-2.0/schemas/"

mkdir -p "${BUILD_DIR}/usr/share/doc/wayplank"
ln -s wayplank "${BUILD_DIR}/usr/share/doc/plank"
cat << 'EOF' > "${BUILD_DIR}/usr/share/doc/wayplank/copyright"
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: wayplank
Upstream-Contact: Sergio Melas <sergiomelas@gmail.com>
Source: https://github.com/sergiomelas/WayPlank

Files: *
Copyright: 2011-2015 Robert Dyer, Michal Hruby, Rico Tzschichholz
           2026 Sergio Melas <sergiomelas@gmail.com>
License: GPL-3.0-or-later

Files: data/docklets/*
Copyright: 2014-2026 KDE Community / Breeze Icon Artists
           2026 Sergio Melas <sergiomelas@gmail.com>
License: LGPL-3.0-or-later or GPL-3.0-or-later
Comment: Embedded fallback vector icons for Wayplank docklets (volume scale,
 battery scale and charging states, analog/digital clocks, trash, mpris, system monitors).

License: GPL-3.0-or-later
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 .
 On Debian systems, the full text of the GNU General Public License version 3
 can be found in `/usr/share/common-licenses/GPL-3'.

License: LGPL-3.0-or-later
 This library/asset is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 3 of the License, or (at your option) any later version.
 .
 On Debian systems, the full text of the GNU Lesser General Public License
 version 3 can be found in `/usr/share/common-licenses/LGPL-3'.
EOF
chmod 644 "${BUILD_DIR}/usr/share/doc/wayplank/copyright"

cp "${BASE_DIR}/data/wayplank.desktop" "${BUILD_DIR}/usr/share/applications/wayplank.desktop"
chmod 644 "${BUILD_DIR}/usr/share/applications/wayplank.desktop"
ln -s wayplank.desktop "${BUILD_DIR}/usr/share/applications/plank.desktop"


cat << EOF > "$BUILD_DIR/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${PKG_VER}
Section: misc
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Homepage: https://github.com/sergiomelas/WayPlank
Provides: plank (= ${PKG_VER}), libplank-common, libplank1
Replaces: plank, libplank-common, libplank1
Conflicts: plank, libplank-common, libplank1
Breaks: plank, libplank-common, libplank1
Depends: libgtk-3-0t64 | libgtk-3-0, libgtk-layer-shell0, libwayland-client0, libglib2.0-0t64 | libglib2.0-0, libjson-glib-1.0-0, libgee-0.8-2, libc6, dconf-gsettings-backend | gsettings-backend
Recommends: grim, slurp, spectacle
Description: Wayplank dock - Modern Standalone Fork (GPL-3.0+)
 Wayplank is a monolithic, standalone dock for modern desktop environments.
 Drop-in replacement for the original Plank dock with native enhancements.
 Released under the GNU General Public License v3.0 or later (GPL-3.0+).
 Includes self-contained fallback assets for all docklets.
EOF

cat << 'EOF' > "$BUILD_DIR/DEBIAN/postinst"
#!/bin/bash
set -e
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas /usr/share/glib-2.0/schemas/ || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications/ || true
fi
echo "Wayplank installed and configured successfully."
EOF
chmod 755 "$BUILD_DIR/DEBIAN/postinst"

cat << 'EOF' > "$BUILD_DIR/DEBIAN/postrm"
#!/bin/bash
set -e
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas /usr/share/glib-2.0/schemas/ || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications/ || true
fi
EOF
chmod 755 "$BUILD_DIR/DEBIAN/postrm"
chmod 755 "$BUILD_DIR/DEBIAN"

DEB_FILE="${OUT_DIR}/${PKG_NAME}_${PKG_VER}_${ARCH}.deb"
rm -f "$DEB_FILE"

echo "📦 Building ${PKG_NAME} package..."
if ! dpkg-deb --build --root-owner-group "$BUILD_DIR" "$DEB_FILE"; then
    echo ""
    echo "❌ Build failed! Error creating Debian package with dpkg-deb."
    echo ""
    rm -rf "$BUILD_DIR"
    if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
    exit 1
fi
rm -rf "$BUILD_DIR"

if [ -f "$DEB_FILE" ]; then
    echo ""
    echo "🎉 Build completed successfully!"
    echo "📦 Package: ${DEB_FILE}"
    echo "💡 Install with: sudo dpkg -i \"${DEB_FILE}\""
    echo ""
else
    echo ""
    echo "❌ Build failed! Package file '${DEB_FILE}' was not created."
    echo ""
    if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
    exit 1
fi

if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ]; then
    read -rp "👋 Press Enter to close..."
fi
