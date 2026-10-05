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
set -euo pipefail

# --- Dolphin Auto-Spawn GUI Terminal ---
if [ ! -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ]; then
    if command -v konsole >/dev/null 2>&1; then
        exec konsole -e bash "$0" "$@"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        exec x-terminal-emulator -e bash "$0" "$@"
    fi
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${BASE_DIR}/build"
mkdir -p "$OUT_DIR"
rm -f "${OUT_DIR}/wayplank"

echo "⚙️ Compiling GLib resources..."
glib-compile-resources \
    --sourcedir="${BASE_DIR}/data" \
    --target="${BASE_DIR}/lib/resources.c" \
    --generate-source \
    "${BASE_DIR}/data/plank.gresource.xml"

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
    --gresources="${BASE_DIR}/data/plank.gresource.xml" \
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
    -X -I"${BASE_DIR}/lib" \
    -X -I"${BASE_DIR}/lib/Protocols" \
    -X -I"${BASE_DIR}/lib/Services" \
    -X -I"${BASE_DIR}/include" \
    -X -w \
    -X -lm \
    -X -lwayland-client \
    "${VALA_FILES[@]}" \
    "${C_SOURCES[@]}" \
    -o "${OUT_DIR}/wayplank"; then
    rm -f "${BASE_DIR}/lib/resources.c"
    echo "✅ Binary ready: ${OUT_DIR}/wayplank"
    if [ -t 0 ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${VSCODE_INJECTION:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
else
    rm -f "${BASE_DIR}/lib/resources.c"
    echo ""
    echo "❌ Error: Compilation failed!"
    if [ -t 0 ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${VSCODE_INJECTION:-}" ]; then
        read -rp "👋 Press Enter to close..."
    fi
    exit 1
fi
