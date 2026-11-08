#!/usr/bin/env bash
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
#  WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
set -euo pipefail

# --- Dolphin Auto-Spawn GUI Terminal ---
if [ ! -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
    if command -v konsole >/dev/null 2>&1; then
        exec konsole -e bash "$0" "$@"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        exec x-terminal-emulator -e bash "$0" "$@"
    fi
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_VER="$(sed -n '1p' "${BASE_DIR}/VERSION" | tr -d '[:space:]')"
PKG_DECO="$(sed -n '2p' "${BASE_DIR}/VERSION" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[ -z "$PKG_DECO" ] && PKG_DECO="Public Beta"
OUT_DIR="${BASE_DIR}/build"
BUILD_GRESOURCE_XML="${BASE_DIR}/data/.plank.build.gresource.xml"

cleanup_build_artifacts() {
    rm -rf "${BASE_DIR}/data/locale" "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"
}
trap cleanup_build_artifacts EXIT

mkdir -p "$OUT_DIR"
rm -f "${OUT_DIR}/wayplank"

echo "🌍 Generating and compiling embedded localization dictionaries..."
python3 "${BASE_DIR}/po/generate_translations.py"
rm -rf "${BASE_DIR}/data/locale"
EMBEDDED_LANGS=""
LOCALE_XML_ENTRIES=""
for po in "${BASE_DIR}"/po/*.po; do
    lang="$(basename "$po" .po)"
    mkdir -p "${BASE_DIR}/data/locale/${lang}"
    msgfmt "$po" -o "${BASE_DIR}/data/locale/${lang}/wayplank.mo"
    if [ -z "$EMBEDDED_LANGS" ]; then
        EMBEDDED_LANGS="${lang}"
    else
        EMBEDDED_LANGS="${EMBEDDED_LANGS}:${lang}"
    fi
    LOCALE_XML_ENTRIES="${LOCALE_XML_ENTRIES}		<file compressed=\"true\">locale/${lang}/wayplank.mo</file>\n"
done
echo "   📦 Encoded binary languages: ${EMBEDDED_LANGS}"

awk -v entries="$LOCALE_XML_ENTRIES" '
    /<\/gresource>/ { printf "%s", entries }
    { print }
' "${BASE_DIR}/data/plank.gresource.xml" > "$BUILD_GRESOURCE_XML"

echo "⚙️ Compiling GLib schemas & resources..."
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas "${BASE_DIR}/data/glib-2.0/schemas"
fi
glib-compile-resources \
    --sourcedir="${BASE_DIR}/data" \
    --target="${BASE_DIR}/lib/resources.c" \
    --generate-source \
    "$BUILD_GRESOURCE_XML"
rm -rf "${BASE_DIR}/data/locale"

echo "🏗️ Compiling Vala & C sources to native binary..."
mapfile -t VALA_FILES < <(find "${BASE_DIR}/lib" "${BASE_DIR}/src" -name "*.vala")

C_SOURCES=("${BASE_DIR}/lib/resources.c")
if [ -f "${BASE_DIR}/lib/gtk-compat.c" ]; then
    C_SOURCES+=("${BASE_DIR}/lib/gtk-compat.c")
fi
if [ -f "${BASE_DIR}/lib/Protocols/wlr-foreign-toplevel-management-protocol.c" ]; then
    C_SOURCES+=("${BASE_DIR}/lib/Protocols/wlr-foreign-toplevel-management-protocol.c")
fi
if [ -f "${BASE_DIR}/lib/Services/wlr-toplevel-bridge.c" ]; then
    C_SOURCES+=("${BASE_DIR}/lib/Services/wlr-toplevel-bridge.c")
fi

if valac -g \
    --gresources="$BUILD_GRESOURCE_XML" \
    --gresourcesdir="${BASE_DIR}/data" \
    --vapidir="${BASE_DIR}/vapi" \
    --pkg posix \
    --pkg gio-unix-2.0 \
    --pkg gtk+-3.0 \
    --pkg gtk-layer-shell-0 \
    --pkg json-glib-1.0 \
    --pkg gee-0.8 \
    --pkg compat \
    --pkg config \
    --pkg wlr-bridge \
    -X -D_GNU_SOURCE \
    -X "-Dsetproctitle(x)=" \
    -X -DGETTEXT_PACKAGE=\"wayplank\" \
    -X -DPACKAGE_VERSION=\"${PKG_VER}\" \
    -X "-DPACKAGE_VERSION_DECO=\"${PKG_DECO}\"" \
    -X -DWAYPLANK_EMBEDDED_LANGS=\"${EMBEDDED_LANGS}\" \
    -X -I"${BASE_DIR}/lib" \
    -X -I"${BASE_DIR}/lib/Protocols" \
    -X -I"${BASE_DIR}/lib/Services" \
    -X -I"${BASE_DIR}/include" \
    -X -include -X "${BASE_DIR}/include/config.h" \
    -X -w \
    -X -lm \
    -X -lwayland-client \
    "${VALA_FILES[@]}" \
    "${C_SOURCES[@]}" \
    -o "${OUT_DIR}/wayplank"; then
    rm -f "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"
    echo "✅ Binary ready: ${OUT_DIR}/wayplank"
    if [ -t 0 ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
else
    rm -f "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"
    echo ""
    echo "❌ Error: Compilation failed!"
    if [ -t 0 ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
    exit 1
fi
