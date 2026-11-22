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
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ==============================================================================
# Intelligent Pre-Backup Repository Cleaner for WayPlank
# Developed by Sergio Melas - 2026
#
# Removes bulky temporary build trees (~36k+ files / ~2.8 GB) while preserving
# downloaded tarballs (deps/win32/src) and the compiled Windows static sysroot
# (deps/win32/sysroot + stamps) so builders never need to re-download/recompile.
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

# Always switch to the script's own repository directory (safe for right-click launch)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

DRY_RUN=0
FULL_CLEAN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        --full)       FULL_CLEAN=1 ;;
        -h|--help)
            echo "Usage: ./CleanRepo.sh [--dry-run] [--full]"
            echo "  (default)  Smart clean: deletes temp build trees (~2.8 GB / 36k+ files),"
            echo "             keeps deps/win32/{src,sysroot,stamps} and current VERSION packages."
            echo "  --dry-run  Show what would be removed without deleting anything."
            echo "  --full     Also wipe deps/win32/{src,sysroot,stamps} (requires full rebuild)."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (use --help)" >&2
            exit 1
            ;;
    esac
done

CURRENT_VER=""
if [ -f "${BASE_DIR}/VERSION" ]; then
    CURRENT_VER="$(sed -n '1p' "${BASE_DIR}/VERSION" | tr -d '[:space:]')"
fi

count_repo() {
    local files size
    files="$(find . -not -path './.git/*' -not -path './.git' | wc -l)"
    size="$(du -sh --exclude=.git . 2>/dev/null | cut -f1)"
    echo "${files} entries, ${size} (excluding .git)"
}

remove_path() {
    local target="$1"
    if [ -e "$target" ] || [ -L "$target" ]; then
        local sz
        sz="$(du -sh "$target" 2>/dev/null | cut -f1)"
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [DRY-RUN] would remove: $target ($sz)"
        else
            echo "  [CLEAN]   removing: $target ($sz)"
            rm -rf -- "$target"
        fi
    fi
}

echo "============================================================"
echo "  WayPlank Intelligent Pre-Backup Cleaner"
echo "  Workspace : $BASE_DIR"
echo "  Version   : ${CURRENT_VER:-unknown}"
echo "  Mode      : $([ "$FULL_CLEAN" -eq 1 ] && echo "FULL (wipes sysroot + downloads)" || echo "SMART (keeps sysroot + downloads)")$([ "$DRY_RUN" -eq 1 ] && echo " [DRY-RUN]")"
echo "============================================================"
echo "Before: $(count_repo)"
echo ""

# 1. Bulky MinGW unpacked source & object trees (~36,190 files / ~2.8 GB)
remove_path "deps/win32/build"

# 2. Optional full wipe of Windows sysroot & downloads (only if --full)
if [ "$FULL_CLEAN" -eq 1 ]; then
    remove_path "deps/win32/sysroot"
    remove_path "deps/win32/src"
    remove_path "deps/win32/stamps"
    remove_path "deps/win32/x86_64-w64-mingw32.cmake"
    remove_path "deps/win32/x86_64-w64-mingw32.ini"
fi

# 3. Temporary C & packaging staging directories
remove_path "build_workspace"
remove_path "build/win_c"
remove_path "build/windows/win_c"
for tmp_dir in build/deb_* build/rpm_* build/nsis* build/staging* build/*/deb_* build/*/rpm_* build/*/nsis* build/*/staging*; do
    [ -e "$tmp_dir" ] && remove_path "$tmp_dir"
done

# 4. Generated build scratch files (from .gitignore)
remove_path "data/glib-2.0/schemas/gschemas.compiled"
remove_path "data/locale"
remove_path "data/.plank.build.gresource.xml"
remove_path "data/.plank.win.gresource.xml"
remove_path "lib/resources.c"

# 5. Stale older-version packages in build/{linux,bsd,windows}/ (keep current VERSION)
if [ -n "$CURRENT_VER" ] && [ -d "build" ]; then
    for pkg in build/wayplank_*.deb build/wayplank-*.rpm build/WayPlank-*-Setup.exe \
               build/linux/wayplank_*.deb build/linux/wayplank-*.rpm \
               build/bsd/wayplank-*.pkg build/windows/WayPlank-*-Setup.exe; do
        [ -e "$pkg" ] || continue
        case "$pkg" in
            *"${CURRENT_VER}"*) ;; # keep current version
            *) remove_path "$pkg" ;;
        esac
    done
fi

# 6. Stray Vala C dumps, Python caches & editor swap files (outside .git, deps, compositor_sources)
while IFS= read -r -d '' f; do
    remove_path "$f"
done < <(find . \( -path './.git' -o -path './deps' -o -path './compositor_sources' \) -prune -o \
    \( -name '*.vala.c' -o -name '*~' -o -name '*.swp' -o -name '*.kate-swp' -o -name '.*.kate-swp' -o -name '__pycache__' \) -print0)

echo ""
echo "After : $(count_repo)"
echo ""
echo "Preserved:"
[ -d "deps/win32/sysroot" ] && echo "  - deps/win32/sysroot  (compiled static libs — instant BuildWin.sh)"
[ -d "deps/win32/src" ]     && echo "  - deps/win32/src      (downloaded tarballs — zero re-download)"
[ -d "build" ]              && echo "  - build/              ($(ls -1 build/ 2>/dev/null | tr '\n' ' '))"
echo "============================================================"
echo "Clean complete!"

if [ -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
    read -rp "👋 Press Enter to close..."
fi
