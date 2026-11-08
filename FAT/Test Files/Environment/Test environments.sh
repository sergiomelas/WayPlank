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
# WayPlank FAT 7.17 - Environment & Profile Persistence Qualification Harness
# Developed by Sergio Melas - 2026
# ==============================================================================
set -euo pipefail

# --- Auto-change into the script's own directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Dolphin / File Manager Auto-Spawn GUI Terminal ---
if [ ! -t 0 ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
    if command -v konsole >/dev/null 2>&1; then
        exec konsole --workdir "$SCRIPT_DIR" -e bash "$0" "$@"
    elif command -v gnome-terminal >/dev/null 2>&1; then
        exec gnome-terminal --working-directory="$SCRIPT_DIR" -- bash "$0" "$@"
    elif command -v xfce4-terminal >/dev/null 2>&1; then
        exec xfce4-terminal --working-directory="$SCRIPT_DIR" -e "bash \"$0\" $*"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        exec x-terminal-emulator -e bash "$0" "$@"
    fi
fi

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
USER_CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wayplank"
TARGET_INI="${USER_CFG_DIR}/latch-state.ini"
BACKUP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wayplank_fat_backup"
BACKUP_CFG_COPY="${BACKUP_DIR}/wayplank"
BACKUP_DCONF="${BACKUP_DIR}/dconf_plank.bak"
MANUAL_RESTORE_SCRIPT="${BACKUP_DIR}/MANUAL_RESTORE.sh"

if command -v wayplank >/dev/null 2>&1; then
    WAYPLANK_BIN="$(command -v wayplank)"
elif [ -x "${REPO_ROOT}/build/wayplank" ]; then
    WAYPLANK_BIN="${REPO_ROOT}/build/wayplank"
else
    echo "❌ Error: wayplank binary not found!"
    exit 1
fi

ensure_backup() {
    mkdir -p "$BACKUP_DIR"
    if [ ! -d "$BACKUP_CFG_COPY" ] && [ ! -f "${BACKUP_DIR}/no_cfg_originally" ]; then
        if [ -d "$USER_CFG_DIR" ]; then
            cp -a "$USER_CFG_DIR" "$BACKUP_CFG_COPY"
            echo "💾 [STEP 1] Full backup of ${USER_CFG_DIR} created at: ${BACKUP_CFG_COPY}"
        else
            touch "${BACKUP_DIR}/no_cfg_originally"
        fi
    fi
    if [ ! -f "$BACKUP_DCONF" ] && command -v dconf >/dev/null 2>&1; then
        dconf dump /net/launchpad/plank/ > "$BACKUP_DCONF" || true
    fi
    cat > "$MANUAL_RESTORE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
pkill -TERM -x wayplank >/dev/null 2>&1 || true
sleep 0.3
rm -rf "${USER_CFG_DIR}"
if [ -d "${BACKUP_CFG_COPY}" ]; then
    cp -a "${BACKUP_CFG_COPY}" "${USER_CFG_DIR}"
fi
if [ -f "${BACKUP_DCONF}" ] && command -v dconf >/dev/null 2>&1; then
    dconf reset -f /net/launchpad/plank/ || true
    dconf load /net/launchpad/plank/ < "${BACKUP_DCONF}" || true
fi
nohup "${WAYPLANK_BIN}" >/dev/null 2>&1 &
echo "✅ Original WayPlank environment manually restored from ${BACKUP_DIR}"
EOF
    chmod +x "$MANUAL_RESTORE_SCRIPT"
}

print_backup_instructions() {
    echo "================================================================================"
    echo " 🛡️  SAFETY BACKUP CREATED BEFORE TESTING"
    echo " 📂 Backup Directory : ${BACKUP_DIR}"
    echo "--------------------------------------------------------------------------------"
    echo " 🔧 HOW TO RESTORE MANUALLY IF THIS SCRIPT FAILS OR IS INTERRUPTED:"
    echo "   • Option A (One-click / Terminal Emergency Script):"
    echo "       ${MANUAL_RESTORE_SCRIPT}"
    echo "   • Option B (Manual Terminal Commands):"
    echo "       rm -rf \"${USER_CFG_DIR}\" && cp -a \"${BACKUP_CFG_COPY}\" \"${USER_CFG_DIR}\""
    echo "       dconf load /net/launchpad/plank/ < \"${BACKUP_DCONF}\""
    echo "   • Option C (From File Manager - Dolphin / Nautilus):"
    echo "       Delete '${USER_CFG_DIR}' and copy '${BACKUP_CFG_COPY}' back to '${USER_CFG_DIR}'."
    echo "================================================================================"
}

find_first_desktop_uri() {
    for candidate in "$@"; do
        for dir in "/usr/share/applications" "/var/lib/flatpak/exports/share/applications" "$HOME/.local/share/applications"; do
            if [ -f "${dir}/${candidate}" ]; then
                echo "file://${dir}/${candidate}"
                return 0
            fi
        done
    done
    return 1
}

populate_host_app_dockitems() {
    local launchers_dir="$1"
    mkdir -p "$launchers_dir"

    local fm_uri=""
    fm_uri="$(find_first_desktop_uri org.kde.dolphin.desktop org.gnome.Nautilus.desktop thunar.desktop pcmanfm-qt.desktop pcmanfm.desktop nemo.desktop caja.desktop || true)"
    if [ -n "$fm_uri" ]; then
        printf "[PlankDockItemPreferences]\nLauncher=%s\n" "$fm_uri" > "${launchers_dir}/files.dockitem"
    fi

    local term_uri=""
    term_uri="$(find_first_desktop_uri org.kde.konsole.desktop org.gnome.Ptyxis.desktop org.gnome.Console.desktop org.gnome.Terminal.desktop xfce4-terminal.desktop foot.desktop qterminal.desktop alacritty.desktop kitty.desktop xterm.desktop || true)"
    if [ -n "$term_uri" ]; then
        printf "[PlankDockItemPreferences]\nLauncher=%s\n" "$term_uri" > "${launchers_dir}/terminal.dockitem"
    fi

    local browser_uri=""
    browser_uri="$(find_first_desktop_uri firefox.desktop firefox-esr.desktop org.mozilla.firefox.desktop google-chrome.desktop chromium.desktop chromium-browser.desktop brave-browser.desktop org.gnome.Epiphany.desktop falkon.desktop || true)"
    if [ -n "$browser_uri" ]; then
        printf "[PlankDockItemPreferences]\nLauncher=%s\n" "$browser_uri" > "${launchers_dir}/browser.dockitem"
    fi
}

restart_wayplank() {
    pkill -TERM -x wayplank >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x wayplank >/dev/null 2>&1 || break
        sleep 0.1
    done
    nohup "$WAYPLANK_BIN" >/dev/null 2>&1 &
    disown || true
}

apply_environment() {
    local env_name="$1"
    local src_dir="${SCRIPT_DIR}/${env_name}"
    local src_ini="${src_dir}/latch-state.ini"
    if [ ! -d "$src_dir" ]; then
        echo "❌ Missing test directory: ${src_dir}"
        return 1
    fi
    ensure_backup
    pkill -TERM -x wayplank >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x wayplank >/dev/null 2>&1 || break
        sleep 0.1
    done
    rm -rf "$USER_CFG_DIR"
    mkdir -p "${USER_CFG_DIR}/dock1/launchers"
    if [ "$env_name" = "EmptyProfile" ]; then
        if command -v dconf >/dev/null 2>&1; then
            dconf reset -f /net/launchpad/plank/ || true
        fi
        echo "================================================================"
        echo " 🧪 Applied Full Test Environment : EmptyProfile (Virgin First-Run State)"
        echo " 📂 Target Config Dir             : ${USER_CFG_DIR} (empty)"
        echo " 🚀 Launching                     : ${WAYPLANK_BIN}"
        echo "================================================================"
        restart_wayplank
        return 0
    fi
    if [ ! -f "$src_ini" ]; then
        echo "❌ Missing test file: ${src_ini}"
        return 1
    fi
    if [ -d "${src_dir}/dock1/launchers" ]; then
        cp -a "${src_dir}/dock1/launchers/." "${USER_CFG_DIR}/dock1/launchers/"
    fi
    populate_host_app_dockitems "${USER_CFG_DIR}/dock1/launchers"
    cp -f "$src_ini" "$TARGET_INI"
    echo "================================================================"
    echo " 🧪 Applied Full Test Environment : ${env_name}"
    echo " 📄 Target Root INI               : ${TARGET_INI}"
    echo " 📂 Target Launchers Dir          : ${USER_CFG_DIR}/dock1/launchers"
    echo " 🚀 Launching                     : ${WAYPLANK_BIN}"
    echo "================================================================"
    restart_wayplank
}

restore_environment() {
    pkill -TERM -x wayplank >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x wayplank >/dev/null 2>&1 || break
        sleep 0.1
    done
    if [ -f "$BACKUP_DCONF" ] && command -v dconf >/dev/null 2>&1; then
        dconf reset -f /net/launchpad/plank/ || true
        dconf load /net/launchpad/plank/ < "$BACKUP_DCONF" || true
    fi
    rm -rf "$USER_CFG_DIR"
    if [ -d "$BACKUP_CFG_COPY" ]; then
        cp -a "$BACKUP_CFG_COPY" "$USER_CFG_DIR"
        echo "✅ Restored full original ${USER_CFG_DIR} from ${BACKUP_CFG_COPY}"
    elif [ -f "${BACKUP_DIR}/no_cfg_originally" ]; then
        echo "✅ Removed test ${USER_CFG_DIR} (none existed originally)"
    fi
    rm -rf "$BACKUP_DIR"
    restart_wayplank
    echo "🚀 WayPlank restarted with your original user environment."
}

# --- STEP 1: ALWAYS CREATE BACKUP IMMEDIATELY ON STARTUP ---
ensure_backup
print_backup_instructions

if [ $# -ge 1 ]; then
    case "$1" in
        1|Corrupted|corrupted) apply_environment "Corrupted" ;;
        2|Partial|partial) apply_environment "Partial" ;;
        3|OutOfRange|outofrange) apply_environment "OutOfRange" ;;
        4|InvalidTypesAndPaths|invalid) apply_environment "InvalidTypesAndPaths" ;;
        5|CorruptedDockItems|dockitems) apply_environment "CorruptedDockItems" ;;
        6|ValidCustomProfile|valid) apply_environment "ValidCustomProfile" ;;
        7|EmptyProfile|empty) apply_environment "EmptyProfile" ;;
        8|restore|Restore) restore_environment ;;
        *)
            echo "Usage: $0 [Corrupted|Partial|OutOfRange|InvalidTypesAndPaths|CorruptedDockItems|ValidCustomProfile|EmptyProfile|restore]"
            exit 1
            ;;
    esac
    exit 0
fi

while true; do
    echo ""
    echo "================================================================================"
    echo " 🛡️  WayPlank FAT 7.17 — Environment Persistence Tester"
    echo " 📂 Working Dir : ${SCRIPT_DIR}"
    echo " 💾 Backup Dir  : ${BACKUP_DIR}"
    echo "================================================================================"
    echo "  1) Corrupted             (Broken latch-state.ini syntax -> Subprocess fallback + Popup)"
    echo "  2) Partial               (Missing keys in latch-state.ini -> Partial defaults + Popup)"
    echo "  3) OutOfRange            (Out-of-range numbers/enums -> Clamped defaults + Popup)"
    echo "  4) InvalidTypesAndPaths  (Wrong types & ../ path traversal -> Sanitized + Popup)"
    echo "  5) CorruptedDockItems    (Corrupted .dockitem files in dock1/launchers -> Cleaned + Popup)"
    echo "  6) ValidCustomProfile    (100% Valid custom profile -> Clean load, NO Popup)"
    echo "  7) EmptyProfile          (Virgin empty profile + dconf reset -> First-Run Onboarding)"
    echo "  8) Restore Original User Environment & Exit"
    echo "  q) Quit (keep current state; backup remains in ${BACKUP_DIR})"
    echo "--------------------------------------------------------------------------------"
    read -rp "Select option [1-8, q]: " choice
    case "$choice" in
        1) apply_environment "Corrupted" ;;
        2) apply_environment "Partial" ;;
        3) apply_environment "OutOfRange" ;;
        4) apply_environment "InvalidTypesAndPaths" ;;
        5) apply_environment "CorruptedDockItems" ;;
        6) apply_environment "ValidCustomProfile" ;;
        7) apply_environment "EmptyProfile" ;;
        8) restore_environment; break ;;
        q|Q)
            echo "ℹ️ Backup preserved at: ${BACKUP_DIR}"
            echo "   Run '${MANUAL_RESTORE_SCRIPT}' or option 8 to restore later."
            break
            ;;
        *) echo "⚠️ Invalid choice: ${choice}" ;;
    esac
done
