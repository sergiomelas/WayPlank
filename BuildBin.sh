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
TMP_ISO_DIR=""

cleanup_build_artifacts() {
    rm -rf "${BASE_DIR}/data/locale" "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"
    if [ -n "$TMP_ISO_DIR" ] && [ -d "$TMP_ISO_DIR" ]; then
        rm -rf "$TMP_ISO_DIR"
    fi
}
trap cleanup_build_artifacts EXIT

mkdir -p "$OUT_DIR"
rm -f "${OUT_DIR}/wayplank"

echo "🛡️ Verifying 8-Gate Multi-Layer HAL & Isolation Firewall..."
HAL_FIREWALL_REGEX='GtkLayerShell|GdkWayland|GdkX11|GdkWin32|Posix\.|GLib\.Unix|UnixFDList|UnixInputStream|sys/prctl\.h|unistd\.h|DesktopAppInfo|GDesktopAppInfo|VolumeMonitor|RecentManager|show_uri|\[DBus|DBusConnection|DBusProxy|DBusManager|DBusClient|BusType\.|Bus\.(get|own_name|watch_name)|UnityClient|IPortalThemeBus|/proc/|/sys/|/dev/i2c|trash://|WindowControl|WindowCapabilities|\bWindowBackend\b|KWin|MutterBackend|LabwcBackend|WlrBridge|SurfaceCoordinateService|BrightnessControl|XdgSession|environment_is_session_|Shell\.parse_argv|has_prefix\s*\(\s*"/"|Win32|HWND|\bAppInfo\.|AppLaunchContext|KeyFileDesktop|"Desktop Entry"|"Desktop Action "|\.desktop"|\.directory"|desktop\.ini|applications?://|Shell\.quote|xdg-open|has_prefix\s*\(\s*"~/|XDG_CURRENT_DESKTOP|/var/lib/(snapd|flatpak)|/opt/google|/usr/(local/)?share|/tmp/\.mount_|Dbusmenu|HAVE_DBUSMENU|x-(desktop|gnome-app-info|kde-appmenu)|layer_shell|unity_|\bapp_dbus\b'
if FIREWALL_HITS="$(grep -rnE --exclude="resources.c" "$HAL_FIREWALL_REGEX" "${BASE_DIR}/src" "${BASE_DIR}/lib" "${BASE_DIR}/hal/Interfaces" "${BASE_DIR}/vapi/core" || true)" && [ -n "$FIREWALL_HITS" ]; then
    echo "❌ GATE 1/2 HAL PURITY FIREWALL VIOLATION DETECTED (Zone 1 / Zone 2):"
    echo "$FIREWALL_HITS"
    exit 1
fi
echo "   ✅ Gates 1 & 2 GREEN: 0 OS/Bus/Compositor/naming leaks across src/, lib/, hal/Interfaces/, vapi/core/."

FDO_LINUX_LEAK_REGEX='LinuxProcessInspector|LinuxSessionPower|LinuxBatteryProvider|LinuxCpuMemDiskTelemetry|LinuxAudioTelemetry|LinuxPlatformRuntime|LinuxSysfsBacklight|LinuxKernelBootstrap|/proc/|/sys/|/dev/i2c'
if FDO_HITS="$(grep -rnE "$FDO_LINUX_LEAK_REGEX" "${BASE_DIR}/hal/Freedesktop" || true)" && [ -n "$FDO_HITS" ]; then
    echo "❌ GATE 6A VIOLATION: Linux kernel symbol/path leak inside hal/Freedesktop/:"
    echo "$FDO_HITS"
    exit 1
fi

LINUX_FDO_LEAK_REGEX='XdgSession|environment_is_session_|XdgAutostart|XdgAppSystem|DbusBroker|DBusConnection|DBusProxy|DBusSignalFlags|DBusCallFlags|BusType|\bBus\.|WindowControl|WindowCapabilities|GtkLayerShell|KWin|MutterBackend|LabwcBackend'
if LIN_HITS="$(grep -rnE "$LINUX_FDO_LEAK_REGEX" "${BASE_DIR}/hal/Linux" || true)" && [ -n "$LIN_HITS" ]; then
    echo "❌ GATE 6B VIOLATION: Freedesktop/D-Bus/Compositor leak inside hal/Linux/:"
    echo "$LIN_HITS"
    exit 1
fi
echo "   ✅ Gate 6 GREEN: 0 horizontal symbol/path leaks between hal/Freedesktop/ and hal/Linux/."

BUS_BYPASS_REGEX='\bBus\.(get|get_sync|get_proxy|get_proxy_sync|own_name|own_name_on_connection|unown_name|watch_name|watch_name_on_connection|unwatch_name)\b'
if BUS_HITS="$(grep -rnE --exclude="DbusBroker.vala" "$BUS_BYPASS_REGEX" "${BASE_DIR}/hal" || true)" && [ -n "$BUS_HITS" ]; then
    echo "❌ GATE 7 VIOLATION: Direct GLib.Bus.* call outside DbusBroker.vala:"
    echo "$BUS_HITS"
    exit 1
fi
echo "   ✅ Gate 7 GREEN: DbusBroker is the sole GLib.Bus.* entry point."

VALA_EXTRA_DEFINES=()
if [ -f /usr/include/sys/prctl.h ] || compgen -G "/usr/include/*/sys/prctl.h" >/dev/null; then
    VALA_EXTRA_DEFINES+=(-D HAVE_SYS_PRCTL_H)
fi

TMP_ISO_DIR="$(mktemp -d)"
mkdir -p "${TMP_ISO_DIR}/z2" "${TMP_ISO_DIR}/fdo" "${TMP_ISO_DIR}/lin"
mapfile -t Z2_VALA_FILES < <(find "${BASE_DIR}/hal/Interfaces" -name "*.vala" | sort)
mapfile -t FDO_VALA_FILES < <(find "${BASE_DIR}/hal/Freedesktop" -name "*.vala" | sort)
mapfile -t LIN_VALA_FILES < <(find "${BASE_DIR}/hal/Linux" -name "*.vala" | sort)

valac -C -d "${TMP_ISO_DIR}/z2" \
    --vapidir="${BASE_DIR}/vapi/core" \
    --pkg gtk+-3.0 --pkg gee-0.8 --pkg json-glib-1.0 --pkg config \
    "${Z2_VALA_FILES[@]}"
echo "   ✅ Gate 3 GREEN: hal/Interfaces/ compiles standalone with 0 OS packages."

valac -C -d "${TMP_ISO_DIR}/fdo" \
    --vapidir="${BASE_DIR}/vapi/core" --vapidir="${BASE_DIR}/vapi/freedesktop" \
    --pkg posix --pkg gio-unix-2.0 --pkg gtk+-3.0 --pkg gtk-layer-shell-0 \
    --pkg json-glib-1.0 --pkg gee-0.8 --pkg compat --pkg config --pkg wlr-bridge \
    "${Z2_VALA_FILES[@]}" "${FDO_VALA_FILES[@]}"
echo "   ✅ Gate 4 GREEN: hal/Freedesktop/ compiles standalone without hal/Linux/."

valac -C -d "${TMP_ISO_DIR}/lin" \
    --vapidir="${BASE_DIR}/vapi/core" --vapidir="${BASE_DIR}/vapi/freedesktop" \
    --pkg posix --pkg gio-unix-2.0 --pkg gtk+-3.0 \
    --pkg json-glib-1.0 --pkg gee-0.8 --pkg unix-compat --pkg config \
    "${VALA_EXTRA_DEFINES[@]}" \
    "${Z2_VALA_FILES[@]}" "${LIN_VALA_FILES[@]}"
echo "   ✅ Gate 5 GREEN: hal/Linux/ compiles standalone without hal/Freedesktop/."
rm -rf "$TMP_ISO_DIR"
TMP_ISO_DIR=""

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
mapfile -t VALA_FILES < <(find "${BASE_DIR}/hal/Interfaces" "${BASE_DIR}/hal/Freedesktop" "${BASE_DIR}/hal/Linux" "${BASE_DIR}/lib" "${BASE_DIR}/src" -name "*.vala" | sort)

C_SOURCES=("${BASE_DIR}/lib/resources.c")
if [ -f "${BASE_DIR}/lib/gtk-compat.c" ]; then
    C_SOURCES+=("${BASE_DIR}/lib/gtk-compat.c")
fi
if [ -f "${BASE_DIR}/hal/Freedesktop/Wlroots/wlr-foreign-toplevel-management-protocol.c" ]; then
    C_SOURCES+=("${BASE_DIR}/hal/Freedesktop/Wlroots/wlr-foreign-toplevel-management-protocol.c")
fi
if [ -f "${BASE_DIR}/hal/Freedesktop/Wlroots/wlr-toplevel-bridge.c" ]; then
    C_SOURCES+=("${BASE_DIR}/hal/Freedesktop/Wlroots/wlr-toplevel-bridge.c")
fi

if valac -g \
    --gresources="$BUILD_GRESOURCE_XML" \
    --gresourcesdir="${BASE_DIR}/data" \
    --vapidir="${BASE_DIR}/vapi/core" \
    --vapidir="${BASE_DIR}/vapi/freedesktop" \
    --pkg posix \
    --pkg gio-unix-2.0 \
    --pkg gtk+-3.0 \
    --pkg gtk-layer-shell-0 \
    --pkg json-glib-1.0 \
    --pkg gee-0.8 \
    --pkg compat \
    --pkg unix-compat \
    --pkg config \
    --pkg wlr-bridge \
    "${VALA_EXTRA_DEFINES[@]}" \
    -X -D_GNU_SOURCE \
    -X "-Dsetproctitle(x)=" \
    -X -DGETTEXT_PACKAGE=\"wayplank\" \
    -X -DPACKAGE_VERSION=\"${PKG_VER}\" \
    -X "-DPACKAGE_VERSION_DECO=\"${PKG_DECO}\"" \
    -X -DWAYPLANK_EMBEDDED_LANGS=\"${EMBEDDED_LANGS}\" \
    -X -I"${BASE_DIR}/lib" \
    -X -I"${BASE_DIR}/hal/Freedesktop/Wlroots" \
    -X -I"${BASE_DIR}/include" \
    -X -include -X "${BASE_DIR}/include/config.h" \
    -X -w \
    -X -lm \
    -X -lwayland-client \
    "${VALA_FILES[@]}" \
    "${C_SOURCES[@]}" \
    -o "${OUT_DIR}/wayplank"; then
    rm -f "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"
    python3 - "${OUT_DIR}/wayplank" <<'PY'
import subprocess, sys, re
bin_path = sys.argv[1]
out = subprocess.check_output(["objdump", "-d", bin_path], text=True, errors="replace")
bad = []
for func in out.split("\n\n"):
    if not func.strip():
        continue
    hdr = func.splitlines()[0]
    if "@plt>:" in hdr:
        continue
    has_nonfull_gdk = bool(re.search(r"<gdk_threads_add_(timeout|timeout_seconds|idle)@plt>", func))
    if has_nonfull_gdk and ("g_slice_alloc0" in func and "_data_unref" in func):
        bad.append(hdr)
if bad:
    print("❌ GATE 8 VIOLATION: Pitfall #14 closure UAF pattern detected in:", file=sys.stderr)
    for b in bad:
        print("  ", b, file=sys.stderr)
    sys.exit(1)
PY
    echo "   ✅ Gate 8 GREEN: 0 Pitfall #14 closure UAF patterns in ${OUT_DIR}/wayplank."
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
