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

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${BASE_DIR}/build"
mkdir -p "$OUT_DIR"

echo "⚙️ Compiling GLib resources..."
glib-compile-resources \
    --sourcedir="${BASE_DIR}/data" \
    --target="${BASE_DIR}/lib/resources.c" \
    --generate-source \
    "${BASE_DIR}/data/plank.gresource.xml"

echo "🏗️ Compiling Vala & C sources to native binary..."
mapfile -t VALA_FILES < <(find "${BASE_DIR}/lib" "${BASE_DIR}/src" -name "*.vala")

C_SOURCES="${BASE_DIR}/lib/resources.c"
if [ -f "${BASE_DIR}/lib/gtk-compat.c" ]; then
    C_SOURCES="${C_SOURCES} ${BASE_DIR}/lib/gtk-compat.c"
fi

valac -g \
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
    -X -D_GNU_SOURCE \
    -X "-Dsetproctitle(x)=" \
    -X -DGETTEXT_PACKAGE=\"wayplank\" \
    -X -I"${BASE_DIR}/lib" \
    -X -I"${BASE_DIR}/include" \
    -X -w \
    -X -lm \
    "${VALA_FILES[@]}" \
    ${C_SOURCES} \
    -o "${OUT_DIR}/wayplank"

rm -f "${BASE_DIR}/lib/resources.c"

echo "✅ Binary ready: ${OUT_DIR}/wayplank"
