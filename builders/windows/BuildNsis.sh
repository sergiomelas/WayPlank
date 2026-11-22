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
#  WayPlank Windows NSIS Installer Packager (Linux-hosted -> build/windows/WayPlank-<ver>-Setup.exe)
#  Mirrors BuildDeb.sh / BuildRpm.sh: invokes ./BuildWin.sh first, then packages via makensis.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
read_version_key() {
    awk -F'=' -v sec="$1" -v key="$2" '
        /^\[.*\]/ { in_sec = ($0 == "[" sec "]"); next }
        in_sec && $1 == key { sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }
    ' "${BASE_DIR}/VERSION"
}
PKG_VER="$(read_version_key Release Version)"
PKG_DECO="$(read_version_key Release Decoration)"
PKG_PROG="$(read_version_key Release ProgramName)"
PKG_COMPANY="$(read_version_key Release CompanyName)"
PKG_HOMEPAGE="$(read_version_key Release Homepage)"
[ -z "$PKG_DECO" ] && PKG_DECO="Public Beta"

OUT_DIR="${BASE_DIR}/build/windows"
EXE_PATH="${OUT_DIR}/wayplank.exe"
SETUP_OUT="${OUT_DIR}/WayPlank-${PKG_VER}-Setup.exe"
NSI_FILE="${OUT_DIR}/.wayplank-installer.nsi"

cleanup_nsis_temps() {
    rm -f "$NSI_FILE"
}
trap cleanup_nsis_temps EXIT

if ! command -v makensis >/dev/null 2>&1; then
    echo "❌ Error: 'makensis' (NSIS) is not installed."
    echo "   Install it on Debian/Ubuntu with:"
    echo "   sudo apt-get install -y nsis"
    exit 1
fi

echo "🏗️ Step 1/2: Building Zero-DLL Windows monolith via BuildWin.sh..."
WAYPLANK_NO_PROMPT=1 "${SCRIPT_DIR}/BuildWin.sh"

if [ ! -f "$EXE_PATH" ]; then
    echo "❌ Error: Expected binary not found at ${EXE_PATH}"
    exit 1
fi

echo "📦 Step 2/2: Packaging Windows Setup Installer (${SETUP_OUT})..."
rm -f "$SETUP_OUT"

cat > "$NSI_FILE" <<EOF
Unicode True
SetCompressor /SOLID lzma

!define APP_NAME "${PKG_PROG}"
!define APP_VER "${PKG_VER}"
!define APP_DECO "${PKG_DECO}"
!define APP_PUBLISHER "${PKG_COMPANY}"
!define APP_URL "${PKG_HOMEPAGE}"
!define APP_EXE "wayplank.exe"
!define UNINST_KEY "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\WayPlank"
!define APP_PATHS_KEY "Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\wayplank.exe"

!define MULTIUSER_EXECUTIONLEVEL Highest
!define MULTIUSER_MUI
!define MULTIUSER_USE_PROGRAMFILES64
!define MULTIUSER_INSTALLMODE_COMMANDLINE
!define MULTIUSER_INSTALLMODE_INSTDIR "WayPlank"
!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_KEY "\${UNINST_KEY}"
!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_VALUENAME "InstallMode"

!include "MultiUser.nsh"
!include "MUI2.nsh"

Name "\${APP_NAME} \${APP_VER} (\${APP_DECO})"
OutFile "${SETUP_OUT}"
BrandingText "\${APP_NAME} \${APP_VER} — GPLv3"

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "\$INSTDIR\\\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch WayPlank now"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${BASE_DIR}/LICENSE"
!insertmacro MULTIUSER_PAGE_INSTALLMODE
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
    SetRegView 64
    nsExec::ExecToStack 'taskkill /F /IM wayplank.exe'
    Pop \$0
    Pop \$1
    !insertmacro MULTIUSER_INIT
FunctionEnd

Function un.onInit
    SetRegView 64
    nsExec::ExecToStack 'taskkill /F /IM wayplank.exe'
    Pop \$0
    Pop \$1
    !insertmacro MULTIUSER_UNINIT
FunctionEnd

Section "WayPlank Dock (Required)" SecCore
    SectionIn RO
    SetOutPath "\$INSTDIR"
    File "${EXE_PATH}"
    File "${BASE_DIR}/LICENSE"

    WriteUninstaller "\$INSTDIR\\Uninstall.exe"

    ; Start Menu shortcuts
    CreateDirectory "\$SMPROGRAMS\\\${APP_NAME}"
    CreateShortcut "\$SMPROGRAMS\\\${APP_NAME}\\\${APP_NAME}.lnk" "\$INSTDIR\\\${APP_EXE}"
    CreateShortcut "\$SMPROGRAMS\\\${APP_NAME}\\\${APP_NAME} Preferences.lnk" "\$INSTDIR\\\${APP_EXE}" "--preferences"
    CreateShortcut "\$SMPROGRAMS\\\${APP_NAME}\\Uninstall \${APP_NAME}.lnk" "\$INSTDIR\\Uninstall.exe"

    ; Register in Windows Installed Apps / Add-Remove Programs
    WriteRegStr SHCTX "\${UNINST_KEY}" "DisplayName" "\${APP_NAME} \${APP_VER}"
    WriteRegStr SHCTX "\${UNINST_KEY}" "DisplayVersion" "\${APP_VER}"
    WriteRegStr SHCTX "\${UNINST_KEY}" "Publisher" "\${APP_PUBLISHER}"
    WriteRegStr SHCTX "\${UNINST_KEY}" "URLInfoAbout" "\${APP_URL}"
    WriteRegStr SHCTX "\${UNINST_KEY}" "InstallLocation" "\$INSTDIR"
    WriteRegStr SHCTX "\${UNINST_KEY}" "DisplayIcon" "\$INSTDIR\\\${APP_EXE},0"
    WriteRegStr SHCTX "\${UNINST_KEY}" "UninstallString" '"\$INSTDIR\\Uninstall.exe"'
    WriteRegStr SHCTX "\${UNINST_KEY}" "InstallMode" "\$MultiUser.InstallMode"
    WriteRegDWORD SHCTX "\${UNINST_KEY}" "NoModify" 1
    WriteRegDWORD SHCTX "\${UNINST_KEY}" "NoRepair" 1

    ; Register in Windows App Paths (zero global PATH touch; enables Win+R & start wayplank)
    WriteRegStr SHCTX "\${APP_PATHS_KEY}" "" "\$INSTDIR\\\${APP_EXE}"
    WriteRegStr SHCTX "\${APP_PATHS_KEY}" "Path" "\$INSTDIR"
SectionEnd

Section "Desktop Shortcut" SecDesktop
    CreateShortcut "\$DESKTOP\\\${APP_NAME}.lnk" "\$INSTDIR\\\${APP_EXE}"
SectionEnd

Section "Start WayPlank on Windows Login" SecAutostart
    WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Run" "WayPlank" '"\$INSTDIR\\\${APP_EXE}"'
SectionEnd

Section "Uninstall"
    Delete "\$INSTDIR\\\${APP_EXE}"
    Delete "\$INSTDIR\\LICENSE"
    Delete "\$INSTDIR\\Uninstall.exe"
    RMDir "\$INSTDIR"

    Delete "\$SMPROGRAMS\\\${APP_NAME}\\\${APP_NAME}.lnk"
    Delete "\$SMPROGRAMS\\\${APP_NAME}\\\${APP_NAME} Preferences.lnk"
    Delete "\$SMPROGRAMS\\\${APP_NAME}\\Uninstall \${APP_NAME}.lnk"
    RMDir "\$SMPROGRAMS\\\${APP_NAME}"

    Delete "\$DESKTOP\\\${APP_NAME}.lnk"
    DeleteRegValue HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Run" "WayPlank"
    DeleteRegKey SHCTX "\${UNINST_KEY}"
    DeleteRegKey SHCTX "\${APP_PATHS_KEY}"
SectionEnd
EOF

makensis -V2 "$NSI_FILE"
ls -lh "$EXE_PATH" "$SETUP_OUT"
echo "✅ Windows Setup Installer ready: ${SETUP_OUT}"

if [ -t 0 ] && [ -z "${WAYPLANK_NO_PROMPT:-}" ] && [ -z "${VSCODE_INJECTION:-}" ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
    read -rp "👋 Press Enter to close..."
fi
