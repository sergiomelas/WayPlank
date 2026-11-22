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
set -eu

HOST_OS="$(uname -s)"
if [ "$HOST_OS" != "FreeBSD" ]; then
    echo "❌ BuildBsd.sh must be executed natively on FreeBSD (detected: ${HOST_OS})."
    exit 1
fi

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
PKG_YEAR="$(read_version_key Release Year)"
PKG_HOMEPAGE="$(read_version_key Release Homepage)"
PKG_ISSUES="$(read_version_key Release IssuesUrl)"
[ -z "$PKG_DECO" ] && PKG_DECO="Public Beta"

OUT_DIR="${BASE_DIR}/build/bsd"
BUILD_GRESOURCE_XML="${BASE_DIR}/data/.plank.build.gresource.xml"
TMP_ISO_DIR=""

cleanup_build_artifacts() {
    rm -rf "${BASE_DIR}/data/locale" "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"
    if [ -n "$TMP_ISO_DIR" ] && [ -d "$TMP_ISO_DIR" ]; then
        rm -rf "$TMP_ISO_DIR"
    fi
}
trap cleanup_build_artifacts EXIT INT TERM

for tool in valac pkg-config msgfmt glib-compile-resources python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Missing required FreeBSD build tool: ${tool}"
        echo "   Install prerequisites with:"
        echo "   sudo pkg install -y git vala pkgconf gmake gettext-tools python3 gtk3 gtk-layer-shell libgee json-glib wayland wayland-protocols"
        exit 1
    fi
done

mkdir -p "$OUT_DIR"
rm -f "${OUT_DIR}/wayplank" "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"

echo "🛡️ Verifying 8-Gate Multi-Layer HAL & Isolation Firewall (FreeBSD)..."
python3 - <<'PY'
import os, re, sys

def scan_dirs(roots, pattern, exclude_files=None):
    exclude_files = set(exclude_files or [])
    rx = re.compile(pattern)
    hits = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, _, filenames in os.walk(root):
            for fn in sorted(filenames):
                if fn in exclude_files:
                    continue
                path = os.path.join(dirpath, fn)
                try:
                    with open(path, "r", encoding="utf-8", errors="ignore") as f:
                        for lineno, line in enumerate(f, 1):
                            if rx.search(line):
                                hits.append(f"{path}:{lineno}:{line.rstrip()}")
                except OSError:
                    pass
    return hits

HAL_FIREWALL_REGEX = r'GtkLayerShell|GdkWayland|GdkX11|GdkWin32|Posix\.|GLib\.Unix|UnixFDList|UnixInputStream|sys/prctl\.h|unistd\.h|DesktopAppInfo|GDesktopAppInfo|VolumeMonitor|RecentManager|show_uri|\[DBus|DBusConnection|DBusProxy|DBusManager|DBusClient|BusType\.|Bus\.(get|own_name|watch_name)|UnityClient|IPortalThemeBus|/proc/|/sys/|/dev/i2c|trash://|WindowControl|WindowCapabilities|\bWindowBackend\b|KWin|MutterBackend|LabwcBackend|WlrBridge|SurfaceCoordinateService|BrightnessControl|XdgSession|environment_is_session_|Shell\.parse_argv|has_prefix\s*\(\s*"/"|Win32|HWND|\bAppInfo\.|AppLaunchContext|KeyFileDesktop|"Desktop Entry"|"Desktop Action "|\.desktop"|\.directory"|desktop\.ini|applications?://|Shell\.quote|xdg-open|has_prefix\s*\(\s*"~/|XDG_CURRENT_DESKTOP|/var/lib/(snapd|flatpak)|/opt/google|/usr/(local/)?share|/tmp/\.mount_|Dbusmenu|HAVE_DBUSMENU|x-(desktop|gnome-app-info|kde-appmenu)|layer_shell|unity_|\bapp_dbus\b'
hits = scan_dirs(["src", "lib", "hal/Interfaces", "vapi/core"], HAL_FIREWALL_REGEX, exclude_files={"resources.c"})
if hits:
    print("❌ GATE 1/2 HAL PURITY FIREWALL VIOLATION DETECTED (Zone 1 / Zone 2):", file=sys.stderr)
    print("\n".join(hits), file=sys.stderr)
    sys.exit(1)
print("   ✅ Gates 1 & 2 GREEN: 0 OS/Bus/Compositor/naming leaks across src/, lib/, hal/Interfaces/, vapi/core/.")

FDO_KERNEL_LEAK_REGEX = r'LinuxProcessInspector|LinuxSessionPower|LinuxBatteryProvider|LinuxCpuMemDiskTelemetry|LinuxAudioTelemetry|LinuxPlatformRuntime|LinuxSysfsBacklight|LinuxKernelBootstrap|BsdProcessInspector|BsdBatteryProvider|BsdCpuMemDiskTelemetry|BsdAudioTelemetry|BsdPlatformRuntime|BsdBacklight|BsdKernelBootstrap|BsdKernelBridge|/proc/|/sys/|/dev/i2c'
hits = scan_dirs(["hal/Freedesktop"], FDO_KERNEL_LEAK_REGEX)
if hits:
    print("❌ GATE 6A VIOLATION: Kernel symbol/path leak inside hal/Freedesktop/:", file=sys.stderr)
    print("\n".join(hits), file=sys.stderr)
    sys.exit(1)

BSD_LEAK_REGEX = r'XdgSession|environment_is_session_|XdgAutostart|XdgAppSystem|DbusBroker|DBusConnection|DBusProxy|DBusSignalFlags|DBusCallFlags|BusType|\bBus\.|WindowControl|WindowCapabilities|GtkLayerShell|KWin|MutterBackend|LabwcBackend|LinuxProcessInspector|LinuxBatteryProvider|LinuxCpuMemDiskTelemetry|LinuxAudioTelemetry|LinuxPlatformRuntime|LinuxSysfsBacklight|LinuxKernelBootstrap|/proc/|/sys/'
hits = scan_dirs(["hal/BSD"], BSD_LEAK_REGEX)
if hits:
    print("❌ GATE 6B VIOLATION: Freedesktop/D-Bus/Compositor/Linux leak inside hal/BSD/:", file=sys.stderr)
    print("\n".join(hits), file=sys.stderr)
    sys.exit(1)
print("   ✅ Gate 6 GREEN: 0 horizontal symbol/path leaks between hal/Freedesktop/ and hal/BSD/.")

BUS_BYPASS_REGEX = r'\bBus\.(get|get_sync|get_proxy|get_proxy_sync|own_name|own_name_on_connection|unown_name|watch_name|watch_name_on_connection|unwatch_name)\b'
hits = scan_dirs(["hal"], BUS_BYPASS_REGEX, exclude_files={"DbusBroker.vala"})
if hits:
    print("❌ GATE 7 VIOLATION: Direct GLib.Bus.* call outside DbusBroker.vala:", file=sys.stderr)
    print("\n".join(hits), file=sys.stderr)
    sys.exit(1)
print("   ✅ Gate 7 GREEN: DbusBroker is the sole GLib.Bus.* entry point.")
PY

TMP_ISO_DIR="$(mktemp -d)"
mkdir -p "${TMP_ISO_DIR}/z2" "${TMP_ISO_DIR}/fdo" "${TMP_ISO_DIR}/bsd"

Z2_VALA_FILES="$(find hal/Interfaces -name "*.vala" | sort)"
FDO_VALA_FILES="$(find hal/Freedesktop -name "*.vala" | sort)"
BSD_VALA_FILES="$(find hal/BSD -name "*.vala" | sort)"

# shellcheck disable=SC2086
valac -C -d "${TMP_ISO_DIR}/z2" \
    --vapidir="vapi/core" \
    --pkg gtk+-3.0 --pkg gee-0.8 --pkg json-glib-1.0 --pkg config \
    $Z2_VALA_FILES
echo "   ✅ Gate 3 GREEN: hal/Interfaces/ compiles standalone with 0 OS packages."

# shellcheck disable=SC2086
valac -C -d "${TMP_ISO_DIR}/fdo" \
    --vapidir="vapi/core" --vapidir="vapi/freedesktop" \
    --pkg posix --pkg gio-unix-2.0 --pkg gtk+-3.0 --pkg gtk-layer-shell-0 \
    --pkg json-glib-1.0 --pkg gee-0.8 --pkg compat --pkg config --pkg wlr-bridge \
    $Z2_VALA_FILES $FDO_VALA_FILES
echo "   ✅ Gate 4 GREEN: hal/Freedesktop/ compiles standalone without hal/BSD/ or hal/Linux/."

# shellcheck disable=SC2086
valac -C -d "${TMP_ISO_DIR}/bsd" \
    --vapidir="vapi/core" --vapidir="vapi/freedesktop" --vapidir="vapi/bsd" \
    --pkg posix --pkg gio-unix-2.0 --pkg gtk+-3.0 \
    --pkg json-glib-1.0 --pkg gee-0.8 --pkg unix-compat --pkg config --pkg bsd-kernel-bridge \
    $Z2_VALA_FILES $BSD_VALA_FILES
echo "   ✅ Gate 5 GREEN: hal/BSD/ compiles standalone without hal/Freedesktop/ or hal/Linux/."

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

echo "🏗️ Compiling Vala & C sources to native FreeBSD binary..."
ALL_VALA_FILES="$(find hal/Interfaces hal/Freedesktop hal/BSD lib src -name "*.vala" | sort)"

C_SOURCES="lib/resources.c"
[ -f lib/gtk-compat.c ] && C_SOURCES="${C_SOURCES} lib/gtk-compat.c"
[ -f hal/Freedesktop/Wlroots/wlr-foreign-toplevel-management-protocol.c ] && C_SOURCES="${C_SOURCES} hal/Freedesktop/Wlroots/wlr-foreign-toplevel-management-protocol.c"
[ -f hal/Freedesktop/Wlroots/wlr-toplevel-bridge.c ] && C_SOURCES="${C_SOURCES} hal/Freedesktop/Wlroots/wlr-toplevel-bridge.c"
[ -f hal/BSD/bsd-kernel-bridge.c ] && C_SOURCES="${C_SOURCES} hal/BSD/bsd-kernel-bridge.c"

# shellcheck disable=SC2086
if valac -g \
    --gresources="$BUILD_GRESOURCE_XML" \
    --gresourcesdir="${BASE_DIR}/data" \
    --vapidir="vapi/core" \
    --vapidir="vapi/freedesktop" \
    --vapidir="vapi/bsd" \
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
    --pkg bsd-kernel-bridge \
    -X -DGETTEXT_PACKAGE=\"wayplank\" \
    -X -DPACKAGE_VERSION=\"${PKG_VER}\" \
    -X "-DPACKAGE_VERSION_DECO=\"${PKG_DECO}\"" \
    -X -DPACKAGE_YEAR=\"${PKG_YEAR}\" \
    -X -DPACKAGE_URL=\"${PKG_HOMEPAGE}\" \
    -X -DPACKAGE_BUGREPORT=\"${PKG_ISSUES}\" \
    -X -DWAYPLANK_EMBEDDED_LANGS=\"${EMBEDDED_LANGS}\" \
    -X -I"${BASE_DIR}/lib" \
    -X -I"${BASE_DIR}/hal/Freedesktop/Wlroots" \
    -X -I"${BASE_DIR}/hal/BSD" \
    -X -I"${BASE_DIR}/include" \
    -X -include -X "${BASE_DIR}/include/config.h" \
    -X -w \
    -X -lprocstat \
    -X -lkvm \
    -X -ldevstat \
    -X -lm \
    -X -lwayland-client \
    $ALL_VALA_FILES \
    $C_SOURCES \
    -o "${OUT_DIR}/wayplank"; then
    rm -f "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"

    OBJDUMP_BIN=""
    if command -v llvm-objdump >/dev/null 2>&1; then
        OBJDUMP_BIN="llvm-objdump"
    elif command -v objdump >/dev/null 2>&1; then
        OBJDUMP_BIN="objdump"
    fi
    if [ -z "$OBJDUMP_BIN" ]; then
        echo "❌ GATE 8 VIOLATION: Neither llvm-objdump nor objdump found to verify Pitfall #14."
        exit 1
    fi

    python3 - "$OBJDUMP_BIN" "${OUT_DIR}/wayplank" <<'PY'
import subprocess, sys, re
objdump_bin, bin_path = sys.argv[1], sys.argv[2]
out = subprocess.check_output([objdump_bin, "-d", bin_path], text=True, errors="replace")
bad = []
for func in out.split("\n\n"):
    if not func.strip():
        continue
    hdr = func.splitlines()[0]
    if "@plt>:" in hdr:
        continue
    has_nonfull_gdk = bool(re.search(r"<gdk_threads_add_(timeout|timeout_seconds|idle)(@plt)?>", func))
    if has_nonfull_gdk and ("g_slice_alloc0" in func and "_data_unref" in func):
        bad.append(hdr)
if bad:
    print("❌ GATE 8 VIOLATION: Pitfall #14 closure UAF pattern detected in:", file=sys.stderr)
    for b in bad:
        print("  ", b, file=sys.stderr)
    sys.exit(1)
PY
    echo "   ✅ Gate 8 GREEN: 0 Pitfall #14 closure UAF patterns in ${OUT_DIR}/wayplank (${OBJDUMP_BIN})."
    echo "✅ FreeBSD binary ready: ${OUT_DIR}/wayplank"
else
    rm -f "${BASE_DIR}/lib/resources.c" "$BUILD_GRESOURCE_XML"
    echo ""
    echo "❌ Error: FreeBSD compilation failed!"
    exit 1
fi
