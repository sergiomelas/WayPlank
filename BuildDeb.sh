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
PKG_VER="0.3"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BASE_DIR}/build_workspace"
OUT_DIR="${BASE_DIR}/build"
ARCH="$(dpkg --print-architecture)"

export DEBFULLNAME="Sergio Melas"
export DEBEMAIL="sergiomelas@gmail.com"
MAINTAINER="${DEBFULLNAME} <${DEBEMAIL}>"

echo " "
echo " ##################################################################"
echo " #                                                                #"
echo " #               Plank Dock Local Builder - Standalone            #"
echo " #             Master Builder V1.0 - Debian Integration           #"
echo " #                                                                #"
echo " ##################################################################"
echo " "

# 1. Call the binary build script (BuilsBin.sh)
if [ -f "${BASE_DIR}/BuilsBin.sh" ]; then
    bash "${BASE_DIR}/BuilsBin.sh"
else
    echo "❌ Error: BuilsBin.sh not found!"
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
cp -r "${BASE_DIR}/data/icons/"* "${BUILD_DIR}/usr/share/icons/hicolor/"
cp "${BASE_DIR}/data/glib-2.0/schemas/net.launchpad.plank.gschema.xml" "${BUILD_DIR}/usr/share/glib-2.0/schemas/"

cat << 'EOF' > "${BUILD_DIR}/usr/share/applications/wayplank.desktop"
[Desktop Entry]
Name=Wayplank
GenericName=Dock
Comment=Stupidly simple dock for Wayland
Categories=Utility;
Exec=wayplank
Icon=plank
Terminal=false
Type=Application
StartupNotify=true
X-GNOME-Autostart-Delay=2
EOF
chmod 644 "${BUILD_DIR}/usr/share/applications/wayplank.desktop"

cat << EOF > "$BUILD_DIR/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${PKG_VER}
Section: x11
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Provides: plank (= ${PKG_VER}), libplank-common, libplank1
Replaces: plank, libplank-common, libplank1
Conflicts: plank, libplank-common, libplank1
Breaks: plank, libplank-common, libplank1
Depends: libgtk-3-0, libgtk-layer-shell0, libwnck-3-0, libbamf3-2, libgee-0.8-2, libc6, dconf-gsettings-backend | gsettings-backend
Description: Wayplank dock - Modern Standalone Fork
 Wayplank is a monolithic, standalone dock for modern desktop environments.
 Drop-in replacement for the original Plank dock with native enhancements.
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

DEB_FILE="${OUT_DIR}/${PKG_NAME}_${PKG_VER}_${ARCH}.deb"
echo "📦 Building ${PKG_NAME} package..."
dpkg-deb --build --root-owner-group "$BUILD_DIR" "$DEB_FILE"
rm -rf "$BUILD_DIR"

echo " "
echo "################################################"
echo "# Build successful!                            #"
echo "# Package created: ${DEB_FILE}                 #"
echo "################################################"
echo " "

if [ -t 0 ]; then
    read -rp "Press Enter to close..."
fi
