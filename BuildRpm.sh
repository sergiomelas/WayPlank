#!/usr/bin/env bash
#
#  Copyright (C) 2026 Sergio Melas
#  Copyright (C) 2026 史有虎 (IFtiger-hu)
#
#  This file is part of WayPlank.
#
#  WayPlank is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  WayPlank is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ==============================================================================
# Clean RPM Builder for Wayplank (openSUSE / Fedora / RHEL)
# ==============================================================================
set -euo pipefail

# --- Dolphin Auto-Spawn GUI Terminal ---
if [ ! -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
    if command -v konsole >/dev/null 2>&1; then
        exec konsole -e bash "$0" "$@"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        exec x-terminal-emulator -e bash "$0" "$@"
    fi
fi

if ! command -v rpmbuild >/dev/null 2>&1; then
    echo "❌ Error: 'rpmbuild' is not installed."
    echo "   • openSUSE:  sudo zypper install rpm-build"
    echo "   • Fedora:    sudo dnf install rpm-build"
    echo "   • Debian:    sudo apt install rpm"
    if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
    exit 1
fi

PKG_NAME="wayplank"
PKG_REL="1"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_VER="$(sed -n '1p' "${BASE_DIR}/VERSION" | tr -d '[:space:]')"
PKG_DECO="$(sed -n '2p' "${BASE_DIR}/VERSION" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
RPM_TOPDIR="${BASE_DIR}/build_rpm_workspace"
OUT_DIR="${BASE_DIR}/build"
ARCH="$(uname -m)"

echo ""
echo "🚀 Wayplank Standalone Builder — V${PKG_VER} (${PKG_DECO:-RPM} — RPM Integration)"
echo "─────────────────────────────────────────────────────────────"
echo ""

# 1. Call the binary build script (BuildBin.sh)
if [ -f "${BASE_DIR}/BuildBin.sh" ]; then
    if ! WAYPLANK_NO_PROMPT=1 bash "${BASE_DIR}/BuildBin.sh"; then
        echo "❌ Build failed! Compilation error in BuildBin.sh"
        exit 1
    fi
else
    echo "❌ Error: BuildBin.sh not found!"
    exit 1
fi

rm -rf "$RPM_TOPDIR"
mkdir -p "$RPM_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,tmp}

echo "📦 Preparing RPM source payloads..."
cp "${OUT_DIR}/wayplank" "${RPM_TOPDIR}/SOURCES/wayplank"
cp -r "${BASE_DIR}/data/icons" "${RPM_TOPDIR}/SOURCES/"
cp "${BASE_DIR}/data/wayplank.svg" "${RPM_TOPDIR}/SOURCES/wayplank.svg"
cp "${BASE_DIR}/data/wayplank.desktop" "${RPM_TOPDIR}/SOURCES/wayplank.desktop"
cp "${BASE_DIR}/data/glib-2.0/schemas/net.launchpad.plank.gschema.xml" "${RPM_TOPDIR}/SOURCES/net.launchpad.plank.gschema.xml"

cat << 'EOF_COPYRIGHT' > "${RPM_TOPDIR}/SOURCES/copyright"
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: wayplank
Upstream-Contact: Sergio Melas <sergiomelas@gmail.com>
Source: https://github.com/sergiomelas/WayPlank

Files: *
Copyright: 2011-2015 Robert Dyer, Michal Hruby, Rico Tzschichholz
           2026 Sergio Melas <sergiomelas@gmail.com>
           2026 史有虎 (IFtiger-hu)
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

License: LGPL-3.0-or-later
 This library/asset is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 3 of the License, or (at your option) any later version.
EOF_COPYRIGHT

cat << EOF > "${RPM_TOPDIR}/SPECS/${PKG_NAME}.spec"
%define _binary_payload w19.zstdio
%define _source_payload w19.zstdio
%define debug_package %{nil}

Name:           ${PKG_NAME}
Version:        ${PKG_VER}
Release:        ${PKG_REL}
Summary:        Modern standalone dock for Wayland
License:        GPL-3.0-or-later
Group:          System/GUI/Other
URL:            https://github.com/sergiomelas/WayPlank
Provides:       plank = %{version}
Obsoletes:      plank < %{version}
Conflicts:      plank
Requires:       grim, slurp, ddcutil, brightnessctl
Recommends:     (spectacle or flameshot or xfce4-screenshooter)

%description
WayPlank is a monolithic, standalone dock for modern desktop environments.
Drop-in replacement for the original Plank dock with native Wayland enhancements.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_datadir}/applications
mkdir -p %{buildroot}%{_datadir}/icons/hicolor/scalable/apps
mkdir -p %{buildroot}%{_datadir}/glib-2.0/schemas
mkdir -p %{buildroot}%{_datadir}/doc/wayplank

cp %{_sourcedir}/wayplank %{buildroot}%{_bindir}/wayplank
ln -sf wayplank %{buildroot}%{_bindir}/plank

for sz_dir in %{_sourcedir}/icons/*; do
    [ -d "\$sz_dir" ] || continue
    sz="\$(basename "\$sz_dir")"
    mkdir -p %{buildroot}%{_datadir}/icons/hicolor/\${sz}/apps
    cp "\${sz_dir}/plank.svg" %{buildroot}%{_datadir}/icons/hicolor/\${sz}/apps/plank.svg
    cp "\${sz_dir}/plank.svg" %{buildroot}%{_datadir}/icons/hicolor/\${sz}/apps/wayplank.svg
done
cp %{_sourcedir}/wayplank.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/wayplank.svg
cp %{_sourcedir}/wayplank.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/plank.svg

cp %{_sourcedir}/net.launchpad.plank.gschema.xml %{buildroot}%{_datadir}/glib-2.0/schemas/
cp %{_sourcedir}/wayplank.desktop %{buildroot}%{_datadir}/applications/wayplank.desktop
chmod 644 %{buildroot}%{_datadir}/applications/wayplank.desktop
ln -sf wayplank.desktop %{buildroot}%{_datadir}/applications/plank.desktop
cp %{_sourcedir}/copyright %{buildroot}%{_datadir}/doc/wayplank/copyright
chmod 644 %{buildroot}%{_datadir}/doc/wayplank/copyright

%post
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas %{_datadir}/glib-2.0/schemas/ || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f %{_datadir}/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q %{_datadir}/applications/ || true
fi
killall -q plank wayplank >/dev/null 2>&1 || true
pkill -x plank >/dev/null 2>&1 || true
pkill -x wayplank >/dev/null 2>&1 || true

%postun
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas %{_datadir}/glib-2.0/schemas/ || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f %{_datadir}/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q %{_datadir}/applications/ || true
fi

%files
%{_bindir}/wayplank
%{_bindir}/plank
%{_datadir}/applications/wayplank.desktop
%{_datadir}/applications/plank.desktop
%{_datadir}/icons/hicolor/*/apps/wayplank.svg
%{_datadir}/icons/hicolor/*/apps/plank.svg
%{_datadir}/glib-2.0/schemas/net.launchpad.plank.gschema.xml
%{_datadir}/doc/wayplank

%changelog
* Thu Oct 15 2026 Youhu Shi (史有虎) <2212363803@qq.com> & Sergio Melas <sergiomelas@gmail.com> - ${PKG_VER}-${PKG_REL}
- Native RPM automated packaging support for openSUSE, Fedora & RHEL

EOF

echo "📦 Building RPM package..."
rpmbuild --define "_topdir ${RPM_TOPDIR}" --define "_dbpath ${RPM_TOPDIR}/rpmdb" --define "_tmppath ${RPM_TOPDIR}/tmp" -bb "${RPM_TOPDIR}/SPECS/${PKG_NAME}.spec" > /dev/null

GENERATED_RPM="$(find "${RPM_TOPDIR}/RPMS" -name "*.rpm" | head -n 1)"
if [ -n "$GENERATED_RPM" ] && [ -f "$GENERATED_RPM" ]; then
    TARGET_RPM="${OUT_DIR}/$(basename "$GENERATED_RPM")"
    cp "$GENERATED_RPM" "$TARGET_RPM"
    rm -rf "$RPM_TOPDIR"
    echo ""
    echo "🎉 RPM Package built successfully!"
    echo "📦 Package: ${TARGET_RPM}"
    echo "💡 Install with: sudo zypper install \"${TARGET_RPM}\""
    echo "                 or: sudo rpm -Uvh \"${TARGET_RPM}\""
    echo ""
else
    echo "❌ Build failed! No RPM package generated."
    rm -rf "$RPM_TOPDIR"
    if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
    exit 1
fi

if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
    read -rp "👋 Press Enter to close..."
fi
