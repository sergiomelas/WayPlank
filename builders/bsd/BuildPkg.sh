#!/bin/sh
#
#  Copyright (C) 2026 Sergio Melas
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
# Clean Native FreeBSD .pkg Builder for WayPlank (Standalone & Self-Contained)
# Developed by Sergio Melas - 2026
# ==============================================================================
set -eu

HOST_OS="$(uname -s)"
if [ "$HOST_OS" != "FreeBSD" ]; then
    echo "❌ BuildPkg.sh must be executed natively on FreeBSD (detected: ${HOST_OS})."
    exit 1
fi

if ! command -v pkg >/dev/null 2>&1; then
    echo "❌ Error: FreeBSD 'pkg' tool not found."
    exit 1
fi

PKG_NAME="wayplank"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)"
cd "$BASE_DIR"

read_version_key() {
    awk -F'=' -v sec="$1" -v key="$2" '
        /^\[.*\]/ { in_sec = ($0 == "[" sec "]"); next }
        in_sec && $1 == key { sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }
    ' "${BASE_DIR}/VERSION"
}

PKG_VER="$(read_version_key Release Version)"
PKG_DECO="$(read_version_key Release Decoration)"
PKG_HOLDER="$(read_version_key Release CopyrightHolder)"
PKG_EMAIL="$(read_version_key Release CopyrightEmail)"
PKG_HOMEPAGE="$(read_version_key Release Homepage)"
MAINTAINER="${PKG_HOLDER} <${PKG_EMAIL}>"

OUT_DIR="${BASE_DIR}/build/bsd"
PREFIX="/usr/local"
WORK_DIR=""

cleanup_pkg_workspace() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup_pkg_workspace EXIT INT TERM

echo ""
echo "🚀 WayPlank Standalone Builder — V${PKG_VER} (${PKG_DECO:-FreeBSD} — FreeBSD .pkg Integration)"
echo "─────────────────────────────────────────────────────────────────"
echo ""

# 1. Build native FreeBSD ELF binary via BuildBsd.sh (enforces all 8 HAL Firewall Gates)
if [ -f "${SCRIPT_DIR}/BuildBsd.sh" ]; then
    WAYPLANK_NO_PROMPT=1 /bin/sh "${SCRIPT_DIR}/BuildBsd.sh"
else
    echo "❌ Error: BuildBsd.sh not found!"
    exit 1
fi

if [ ! -f "${OUT_DIR}/wayplank" ]; then
    echo "❌ Build failed! Binary '${OUT_DIR}/wayplank' was not generated."
    exit 1
fi

WORK_DIR="$(mktemp -d)"
STAGE_DIR="${WORK_DIR}/stage"
META_DIR="${WORK_DIR}/meta"
PLIST_FILE="${WORK_DIR}/pkg-plist"
mkdir -p "${STAGE_DIR}${PREFIX}/bin" \
         "${STAGE_DIR}${PREFIX}/share/applications" \
         "${STAGE_DIR}${PREFIX}/share/icons/hicolor/scalable/apps" \
         "${STAGE_DIR}${PREFIX}/share/glib-2.0/schemas" \
         "${STAGE_DIR}${PREFIX}/share/licenses/${PKG_NAME}-${PKG_VER}" \
         "$META_DIR"

echo "📦 Staging FreeBSD package payload under ${PREFIX}..."
install -m 755 "${OUT_DIR}/wayplank" "${STAGE_DIR}${PREFIX}/bin/wayplank"
ln -sf wayplank "${STAGE_DIR}${PREFIX}/bin/plank"

: > "$PLIST_FILE"
printf '%s\n' "bin/wayplank" >> "$PLIST_FILE"
printf '%s\n' "bin/plank" >> "$PLIST_FILE"

for sz_dir in "${BASE_DIR}/data/icons"/*; do
    [ -d "$sz_dir" ] || continue
    sz="$(basename "$sz_dir")"
    mkdir -p "${STAGE_DIR}${PREFIX}/share/icons/hicolor/${sz}/apps"
    install -m 644 "${sz_dir}/plank.svg" "${STAGE_DIR}${PREFIX}/share/icons/hicolor/${sz}/apps/plank.svg"
    install -m 644 "${sz_dir}/plank.svg" "${STAGE_DIR}${PREFIX}/share/icons/hicolor/${sz}/apps/wayplank.svg"
    printf '%s\n' "share/icons/hicolor/${sz}/apps/plank.svg" >> "$PLIST_FILE"
    printf '%s\n' "share/icons/hicolor/${sz}/apps/wayplank.svg" >> "$PLIST_FILE"
done

install -m 644 "${BASE_DIR}/data/wayplank.svg" "${STAGE_DIR}${PREFIX}/share/icons/hicolor/scalable/apps/wayplank.svg"
install -m 644 "${BASE_DIR}/data/wayplank.svg" "${STAGE_DIR}${PREFIX}/share/icons/hicolor/scalable/apps/plank.svg"
printf '%s\n' "share/icons/hicolor/scalable/apps/wayplank.svg" >> "$PLIST_FILE"
printf '%s\n' "share/icons/hicolor/scalable/apps/plank.svg" >> "$PLIST_FILE"

install -m 644 "${BASE_DIR}/data/glib-2.0/schemas/net.launchpad.plank.gschema.xml" \
    "${STAGE_DIR}${PREFIX}/share/glib-2.0/schemas/net.launchpad.plank.gschema.xml"
printf '%s\n' "share/glib-2.0/schemas/net.launchpad.plank.gschema.xml" >> "$PLIST_FILE"

sed "s|Exec=/usr/bin/wayplank|Exec=${PREFIX}/bin/wayplank|g" "${BASE_DIR}/data/wayplank.desktop" \
    > "${STAGE_DIR}${PREFIX}/share/applications/wayplank.desktop"
chmod 644 "${STAGE_DIR}${PREFIX}/share/applications/wayplank.desktop"
ln -sf wayplank.desktop "${STAGE_DIR}${PREFIX}/share/applications/plank.desktop"
printf '%s\n' "share/applications/wayplank.desktop" >> "$PLIST_FILE"
printf '%s\n' "share/applications/plank.desktop" >> "$PLIST_FILE"

install -m 644 "${BASE_DIR}/LICENSE" "${STAGE_DIR}${PREFIX}/share/licenses/${PKG_NAME}-${PKG_VER}/GPLv3"
printf '%s\n' "share/licenses/${PKG_NAME}-${PKG_VER}/GPLv3" >> "$PLIST_FILE"

FLATSIZE="$(du -sk "$STAGE_DIR" | awk '{print $1 * 1024}')"

# Query exact installed runtime dependency versions from local FreeBSD pkg DB
DEPS_BLOCK=""
for dep in gtk3 gtk-layer-shell libgee json-glib wayland; do
    dep_info="$(pkg query '%n %o %v' "$dep" 2>/dev/null || true)"
    if [ -n "$dep_info" ]; then
        d_name="$(printf '%s' "$dep_info" | awk '{print $1}')"
        d_orig="$(printf '%s' "$dep_info" | awk '{print $2}')"
        d_ver="$(printf '%s' "$dep_info" | awk '{print $3}')"
        DEPS_BLOCK="${DEPS_BLOCK}  \"${d_name}\": { origin: \"${d_orig}\", version: \"${d_ver}\" }
"
    fi
done

cat << EOF > "${META_DIR}/+MANIFEST"
name: "${PKG_NAME}"
version: "${PKG_VER}"
origin: "x11/${PKG_NAME}"
comment: "Modern monolithic standalone Wayland dock for FreeBSD and Linux"
desc: <<EOD
WayPlank is a monolithic, standalone dock for modern Wayland desktop environments
(Labwc/wlroots, KDE Plasma 6/KWin, GNOME Shell/Mutter) with a native FreeBSD
kernel backend (libprocstat, sysctl, libdevstat, OSS mixer, hardware backlight,
and 16 built-in docklets).
EOD
maintainer: "${MAINTAINER}"
www: "${PKG_HOMEPAGE}"
prefix: "${PREFIX}"
licenselogic: "single"
licenses: [ "GPLv3+" ]
flatsize: ${FLATSIZE}
deps: {
${DEPS_BLOCK}}
scripts: {
  post-install: <<EOD
#!/bin/sh
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas /usr/local/share/glib-2.0/schemas >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/local/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/local/share/applications >/dev/null 2>&1 || true
fi
pkill -WINCH -x wayplank >/dev/null 2>&1 || true
echo "WayPlank installed cleanly under /usr/local (GSettings schemas compiled)."
EOD
  post-deinstall: <<EOD
#!/bin/sh
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas /usr/local/share/glib-2.0/schemas >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/local/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/local/share/applications >/dev/null 2>&1 || true
fi
EOD
}
EOF

PKG_FILE="${OUT_DIR}/${PKG_NAME}-${PKG_VER}.pkg"
rm -f "$PKG_FILE"

echo "📦 Building FreeBSD .pkg archive via pkg create..."
pkg create -r "$STAGE_DIR" -m "$META_DIR" -p "$PLIST_FILE" -o "$OUT_DIR"

if [ ! -f "$PKG_FILE" ]; then
    echo "❌ Build failed! Package '${PKG_FILE}' was not created."
    exit 1
fi

echo ""
echo "🔍 Verifying generated FreeBSD package metadata..."
pkg info -F "$PKG_FILE"
echo ""
echo "🎉 FreeBSD .pkg completed successfully!"
echo "📦 Package: ${PKG_FILE}"
echo "💡 Install with: sudo pkg add -f \"${PKG_FILE}\""
echo ""
