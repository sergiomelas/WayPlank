#!/usr/bin/env bash
#
#  Copyright (C) 2026 Sergio Melas <sergiomelas@gmail.com>
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
# WayPlank FAT - Multi-Compositor Hot-Reload Localization Switcher
# Author: Sergio Melas <sergiomelas@gmail.com>
# ==============================================================================
# Detects the active Wayland compositor (KDE Plasma KWin, GNOME Mutter, Labwc),
# verifies the requested locale identifier against po/*.po (or English fallback),
# and restarts ONLY the WayPlank process with standard OS locale environment
# variables without altering or polluting the desktop session environment.
#
# Usage:
#   ./switch_lang.sh <locale>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

detect_compositor() {
    local desk="${XDG_CURRENT_DESKTOP:-}${XDG_SESSION_DESKTOP:-}${DESKTOP_SESSION:-}"
    if echo "$desk" | grep -qi "kde\|plasma" || pgrep -x "kwin_wayland" >/dev/null 2>&1; then
        echo "KDE Plasma 6 (KWin Wayland)"
    elif echo "$desk" | grep -qi "gnome\|ubuntu" || pgrep -x "gnome-shell" >/dev/null 2>&1; then
        echo "GNOME Shell (Mutter Wayland)"
    elif echo "$desk" | grep -qi "labwc\|wlroots" || pgrep -x "labwc" >/dev/null 2>&1; then
        echo "Labwc (wlroots Wayland)"
    else
        echo "Wayland Generic (${XDG_CURRENT_DESKTOP:-unknown})"
    fi
}

AVAILABLE_LANGS=()
for po in "${REPO_ROOT}"/po/*.po; do
    [ -f "$po" ] && AVAILABLE_LANGS+=("$(basename "$po" .po)")
done
AVAILABLE_LANGS+=("en")

LANG_INPUT="${1:-}"
if [ -z "$LANG_INPUT" ]; then
    echo "Usage: $0 <locale>"
    echo "Available locales: ${AVAILABLE_LANGS[*]}"
    exit 1
fi

# Strip any .UTF-8 or @modifier if passed
CLEAN_INPUT="${LANG_INPUT%%.*}"
CLEAN_INPUT="${CLEAN_INPUT%%@*}"
BASE_INPUT="${CLEAN_INPUT%%_*}"

LANG_CODE=""
if [ "$BASE_INPUT" = "en" ] || [ "$CLEAN_INPUT" = "C" ] || [ "$CLEAN_INPUT" = "POSIX" ]; then
    LANG_CODE="en"
else
    for avail in "${AVAILABLE_LANGS[@]}"; do
        if [ "$avail" = "$CLEAN_INPUT" ] || [ "$avail" = "$BASE_INPUT" ] || [[ "$avail" == "${BASE_INPUT}_"* ]]; then
            LANG_CODE="$avail"
            break
        fi
    done
fi

if [ -z "$LANG_CODE" ]; then
    echo "⚠️ Locale '${LANG_INPUT}' not in embedded catalogs (${AVAILABLE_LANGS[*]}) -> WayPlank will fallback to English."
    LANG_CODE="$CLEAN_INPUT"
fi

case "$LANG_CODE" in
    en) FULL_LOCALE="en_US.UTF-8" ;;
    uk) FULL_LOCALE="uk_UA.UTF-8" ;;
    ca) FULL_LOCALE="ca_ES.UTF-8" ;;
    ja) FULL_LOCALE="ja_JP.UTF-8" ;;
    *_*) FULL_LOCALE="${LANG_CODE}.UTF-8" ;;
    *)
        UP="$(echo "$LANG_CODE" | tr '[:lower:]' '[:upper:]')"
        FULL_LOCALE="${LANG_CODE}_${UP}.UTF-8"
        ;;
esac

COMPOSITOR="$(detect_compositor)"

if command -v wayplank >/dev/null 2>&1; then
    WAYPLANK_BIN="$(command -v wayplank)"
elif [ -x "${REPO_ROOT}/build/wayplank" ]; then
    WAYPLANK_BIN="${REPO_ROOT}/build/wayplank"
else
    echo "❌ Error: wayplank binary not found!"
    exit 1
fi

echo "================================================================"
echo " 🖥️  Compositor : ${COMPOSITOR}"
echo " 🌍 Locale     : ${LANG_CODE} (${FULL_LOCALE})"
echo " 🚀 Binary     : ${WAYPLANK_BIN}"
echo "================================================================"

# Launch ONLY WayPlank with the target locale environment (desktop session untouched)
nohup env \
    LANGUAGE="${LANG_CODE}" \
    LC_ALL="${FULL_LOCALE}" \
    LC_MESSAGES="${FULL_LOCALE}" \
    LANG="${FULL_LOCALE}" \
    "${WAYPLANK_BIN}" --replace >/dev/null 2>&1 &
disown || true

echo "✅ WayPlank restarted with locale '${LANG_CODE}' on ${COMPOSITOR}."
