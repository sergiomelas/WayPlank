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
#  WayPlank v0.7.3 — 100% Linux-Hosted Zero-DLL PE32+ Cross-Build Pipeline
#  Target: build/wayplank.exe (Windows 7 <-> 11+, 0 external DLLs)
#  Governed by: Documentation/Architecture/HAL_WINDOWS_BACKEND.md
#
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
read_version_key() {
    awk -F'=' -v sec="$1" -v key="$2" '
        /^\[.*\]/ { in_sec = ($0 == "[" sec "]"); next }
        in_sec && $1 == key { sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }
    ' "${BASE_DIR}/VERSION"
}
PKG_VER="$(read_version_key Release Version)"
PKG_DECO="$(read_version_key Release Decoration)"
PKG_YEAR="$(read_version_key Release Year)"
PKG_PROG="$(read_version_key Release ProgramName)"
PKG_HOLDER="$(read_version_key Release CopyrightHolder)"
PKG_COMPANY="$(read_version_key Release CompanyName)"
PKG_HOMEPAGE="$(read_version_key Release Homepage)"
PKG_ISSUES="$(read_version_key Release IssuesUrl)"
[ -z "$PKG_DECO" ] && PKG_DECO="Public Beta"
IFS='.' read -r _v1 _v2 _v3 _v4 _vrest <<< "${PKG_VER}.0.0.0"
PKG_VER_4="${_v1}.${_v2}.${_v3}.${_v4}"
PKG_VER_CSV="${_v1},${_v2},${_v3},${_v4}"

OUT_DIR="${BASE_DIR}/build"
WIN_C_DIR="${OUT_DIR}/win_c"
DEPS_DIR="${BASE_DIR}/deps/win32"
SRC_CACHE="${DEPS_DIR}/src"
BUILD_WORK="${DEPS_DIR}/build"
SYSROOT="${DEPS_DIR}/sysroot"
STAMPS="${DEPS_DIR}/stamps"
CROSS_FILE="${DEPS_DIR}/x86_64-w64-mingw32.ini"
CMAKE_TOOLCHAIN="${DEPS_DIR}/x86_64-w64-mingw32.cmake"
BUILD_GRESOURCE_XML="${BASE_DIR}/data/.plank.win.gresource.xml"

JOBS="$(nproc 2>/dev/null || echo 4)"
HOST_TRIPLET="x86_64-w64-mingw32"

# Prefer posix-threaded MinGW compilers so C++17 static libs (harfbuzz, lunasvg)
# link libwinpthread.a cleanly under -static with 0 external DLLs.
if command -v "${HOST_TRIPLET}-gcc-posix" >/dev/null 2>&1; then
    WIN_CC="${HOST_TRIPLET}-gcc-posix"
    WIN_CXX="${HOST_TRIPLET}-g++-posix"
else
    WIN_CC="${HOST_TRIPLET}-gcc"
    WIN_CXX="${HOST_TRIPLET}-g++"
fi
WIN_AR="${HOST_TRIPLET}-ar"
WIN_RANLIB="${HOST_TRIPLET}-ranlib"
WIN_STRIP="${HOST_TRIPLET}-strip"
WIN_WINDRES="${HOST_TRIPLET}-windres"
WIN_OBJDUMP="${HOST_TRIPLET}-objdump"
WIN_DLLTOOL="${HOST_TRIPLET}-dlltool"

ONLY_SYSROOT=0
REBUILD_LIB=""
while [ $# -gt 0 ]; do
    case "$1" in
        --build-sysroot)
            ONLY_SYSROOT=1
            shift
            ;;
        --rebuild-lib)
            REBUILD_LIB="${2:-}"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--build-sysroot] [--rebuild-lib <name>]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

cleanup_win_temps() {
    rm -rf "${BASE_DIR}/data/locale" "$BUILD_GRESOURCE_XML" "$WIN_C_DIR"
}
trap cleanup_win_temps EXIT

# --- Pre-flight Toolchain Check ---
check_toolchain() {
    local missing=()
    for cmd in "$WIN_CC" "$WIN_CXX" "$WIN_AR" "$WIN_RANLIB" "$WIN_STRIP" "$WIN_WINDRES" "$WIN_OBJDUMP" \
               valac meson ninja cmake pkg-config make curl tar xz python3 glib-compile-resources glib-compile-schemas msgfmt; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "❌ Missing required cross-build tools: ${missing[*]}"
        echo "   Install MinGW-w64 on Debian/Ubuntu with:"
        echo "   sudo apt-get update && sudo apt-get install -y gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64"
        exit 1
    fi
}

# --- Cross-Env & Meson/CMake Toolchain Generation ---
setup_cross_files() {
    mkdir -p "$SRC_CACHE" "$BUILD_WORK" "$SYSROOT/bin" "$SYSROOT/include" "$SYSROOT/lib/pkgconfig" "$STAMPS"

    # Dedicated pkg-config wrapper pointing strictly at the static MinGW sysroot
    cat > "${SYSROOT}/bin/${HOST_TRIPLET}-pkg-config" <<EOF
#!/usr/bin/env bash
export PKG_CONFIG_LIBDIR="${SYSROOT}/lib/pkgconfig:${SYSROOT}/share/pkgconfig"
export PKG_CONFIG_PATH=""
export PKG_CONFIG_SYSROOT_DIR=""
exec pkg-config --static "\$@"
EOF
    chmod +x "${SYSROOT}/bin/${HOST_TRIPLET}-pkg-config"

    cat > "$CROSS_FILE" <<EOF
[binaries]
c = '${WIN_CC}'
cpp = '${WIN_CXX}'
ar = '${WIN_AR}'
strip = '${WIN_STRIP}'
windres = '${WIN_WINDRES}'
pkg-config = '${SYSROOT}/bin/${HOST_TRIPLET}-pkg-config'
exe_wrapper = 'wine64'

[built-in options]
c_args = ['-std=gnu17', '-I${SYSROOT}/include', '-O2', '-D_WIN32_WINNT=0x0601', '-DWINVER=0x0601', '-DGLIB_STATIC_COMPILATION', '-DGOBJECT_STATIC_COMPILATION', '-DGIO_STATIC_COMPILATION', '-DGMODULE_STATIC_COMPILATION', '-DATK_STATIC_COMPILATION', '-DCAIRO_WIN32_STATIC_BUILD', '-DPIXMAN_API=', '-DLUNASVG_BUILD_STATIC', '-Dg_variant_builder_init_static=g_variant_builder_init', '-Wno-error=incompatible-pointer-types', '-Wno-error=int-conversion', '-Wno-error=implicit-function-declaration']
cpp_args = ['-I${SYSROOT}/include', '-O2', '-D_WIN32_WINNT=0x0601', '-DWINVER=0x0601', '-DLUNASVG_BUILD_STATIC']
c_link_args = ['-L${SYSROOT}/lib', '-static-libgcc', '-static-libstdc++', '-lstdc++', '-Wl,--allow-multiple-definition']
cpp_link_args = ['-L${SYSROOT}/lib', '-static-libgcc', '-static-libstdc++', '-Wl,--allow-multiple-definition']

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
needs_exe_wrapper = true
EOF

    cat > "$CMAKE_TOOLCHAIN" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER ${WIN_CC})
set(CMAKE_CXX_COMPILER ${WIN_CXX})
set(CMAKE_RC_COMPILER ${WIN_WINDRES})
set(CMAKE_FIND_ROOT_PATH ${SYSROOT})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_PREFIX_PATH ${SYSROOT})
EOF
}

fetch_tarball() {
    local name="$1"
    local url="$2"
    local file="${SRC_CACHE}/${name}"
    if [ ! -f "$file" ]; then
        echo "   ⬇️  Downloading ${name}..."
        curl -fL --retry 3 --retry-delay 2 -o "${file}.tmp" "$url"
        mv "${file}.tmp" "$file"
    fi
}

extract_tarball() {
    local archive="$1"
    local dest="$2"
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xf "${SRC_CACHE}/${archive}" -C "$dest" --strip-components=1
}

export_autotools_env() {
    export CC="$WIN_CC"
    export CXX="$WIN_CXX"
    export AR="$WIN_AR"
    export RANLIB="$WIN_RANLIB"
    export STRIP="$WIN_STRIP"
    export WINDRES="$WIN_WINDRES"
    export RC="$WIN_WINDRES"
    export DLLTOOL="$WIN_DLLTOOL"
    export PKG_CONFIG="${SYSROOT}/bin/${HOST_TRIPLET}-pkg-config"
    export PKG_CONFIG_LIBDIR="${SYSROOT}/lib/pkgconfig:${SYSROOT}/share/pkgconfig"
    export PKG_CONFIG_PATH=""
    export CPPFLAGS="-I${SYSROOT}/include -D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -DGLIB_STATIC_COMPILATION -DGOBJECT_STATIC_COMPILATION -DGIO_STATIC_COMPILATION -DCAIRO_WIN32_STATIC_BUILD"
    export CFLAGS="-std=gnu17 -O2 -I${SYSROOT}/include -D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=implicit-function-declaration"
    export CXXFLAGS="-O2 -I${SYSROOT}/include -D_WIN32_WINNT=0x0601 -DWINVER=0x0601"
    export LDFLAGS="-L${SYSROOT}/lib -static-libgcc"
}

run_step() {
    local name="$1"
    local fn="$2"
    if [ -n "$REBUILD_LIB" ] && [ "$REBUILD_LIB" = "$name" ]; then
        rm -f "${STAMPS}/${name}.built"
    fi
    if [ -f "${STAMPS}/${name}.built" ]; then
        echo "   ✅ [cached] ${name}"
        return 0
    fi
    echo "🔨 [sysroot] Building ${name}..."
    "$fn"
    touch "${STAMPS}/${name}.built"
    echo "   ✅ [built]  ${name}"
}

# ============================================================================
# TIER 1: Foundational Primitives (zlib, libffi, libiconv, gettext-runtime, pcre2)
# ============================================================================

build_zlib() {
    local v="1.3.1"
    fetch_tarball "zlib-${v}.tar.xz" "https://github.com/madler/zlib/releases/download/v${v}/zlib-${v}.tar.xz"
    local d="${BUILD_WORK}/zlib"
    extract_tarball "zlib-${v}.tar.xz" "$d"
    (
        cd "$d"
        make -f win32/Makefile.gcc \
            PREFIX="${HOST_TRIPLET}-" \
            CC="$WIN_CC" AR="$WIN_AR" RC="$WIN_WINDRES" STRIP="$WIN_STRIP" \
            CFLAGS="-O2" \
            libz.a -j"$JOBS"
        install -m 644 libz.a "${SYSROOT}/lib/libz.a"
        install -m 644 zlib.h zconf.h "${SYSROOT}/include/"
        cat > "${SYSROOT}/lib/pkgconfig/zlib.pc" <<EOF
prefix=${SYSROOT}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: zlib
Description: zlib compression library
Version: ${v}
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF
    )
}

build_libffi() {
    local v="3.4.6"
    fetch_tarball "libffi-${v}.tar.gz" "https://github.com/libffi/libffi/releases/download/v${v}/libffi-${v}.tar.gz"
    local d="${BUILD_WORK}/libffi"
    extract_tarball "libffi-${v}.tar.gz" "$d"
    (
        export_autotools_env
        cd "$d"
        ./configure --host="$HOST_TRIPLET" --prefix="$SYSROOT" \
            --enable-static --disable-shared --disable-docs
        make -j"$JOBS"
        make install
    )
}

build_libiconv() {
    local v="1.17"
    fetch_tarball "libiconv-${v}.tar.gz" "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${v}.tar.gz"
    local d="${BUILD_WORK}/libiconv"
    extract_tarball "libiconv-${v}.tar.gz" "$d"
    (
        export_autotools_env
        cd "$d"
        ./configure --host="$HOST_TRIPLET" --prefix="$SYSROOT" \
            --enable-static --disable-shared --disable-nls
        make -j"$JOBS"
        make install
    )
}

build_gettext_runtime() {
    local v="0.22.5"
    fetch_tarball "gettext-${v}.tar.xz" "https://ftp.gnu.org/pub/gnu/gettext/gettext-${v}.tar.xz"
    local d="${BUILD_WORK}/gettext"
    extract_tarball "gettext-${v}.tar.xz" "$d"
    (
        export_autotools_env
        cd "$d/gettext-runtime"
        ./configure --host="$HOST_TRIPLET" --prefix="$SYSROOT" \
            --enable-static --disable-shared \
            --disable-java --disable-csharp --disable-c++ --disable-libasprintf \
            --with-libiconv-prefix="$SYSROOT" \
            --enable-threads=windows
        make -j"$JOBS"
        make install
    )
}

build_pcre2() {
    local v="10.44"
    fetch_tarball "pcre2-${v}.tar.bz2" "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${v}/pcre2-${v}.tar.bz2"
    local d="${BUILD_WORK}/pcre2"
    extract_tarball "pcre2-${v}.tar.bz2" "$d"
    (
        export_autotools_env
        cd "$d"
        ./configure --host="$HOST_TRIPLET" --prefix="$SYSROOT" \
            --enable-static --disable-shared \
            --enable-unicode --enable-pcre2-8 --disable-pcre2grep-libz --disable-pcre2grep-libbz2
        make -j"$JOBS"
        make install
    )
}

# ============================================================================
# TIER 2: GLib Ecosystem & Vala Models (glib-2.0, libgee-0.8, json-glib-1.0)
# ============================================================================

build_glib() {
    local v="2.80.5"
    fetch_tarball "glib-${v}.tar.xz" "https://download.gnome.org/sources/glib/2.80/glib-${v}.tar.xz"
    local d="${BUILD_WORK}/glib"
    extract_tarball "glib-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dtests=false -Dintrospection=disabled -Ddocumentation=false \
            -Dman-pages=disabled -Dnls=disabled -Dlibmount=disabled \
            -Dselinux=disabled -Dxattr=false -Dsysprof=disabled
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_libgee() {
    local v="0.20.6"
    fetch_tarball "libgee-${v}.tar.xz" "https://download.gnome.org/sources/libgee/0.20/libgee-${v}.tar.xz"
    local d="${BUILD_WORK}/libgee"
    extract_tarball "libgee-${v}.tar.xz" "$d"
    (
        export_autotools_env
        cd "$d"
        ./configure --host="$HOST_TRIPLET" --prefix="$SYSROOT" \
            --enable-static --disable-shared --enable-introspection=no
        make -j"$JOBS"
        make install
    )
}

build_json_glib() {
    local v="1.8.0"
    fetch_tarball "json-glib-${v}.tar.xz" "https://download.gnome.org/sources/json-glib/1.8/json-glib-${v}.tar.xz"
    local d="${BUILD_WORK}/json-glib"
    extract_tarball "json-glib-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dtests=false -Dintrospection=disabled -Dgtk_doc=disabled -Dman=false -Dnls=disabled
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

# ============================================================================
# TIER 3: 2D Vector Graphics, Shaping & Static Loaders
# (libpng, pixman, freetype2, fribidi, harfbuzz, cairo, pango, lunasvg, gdk-pixbuf)
# ============================================================================

build_libpng() {
    local v="1.6.44"
    fetch_tarball "libpng-${v}.tar.xz" "https://downloads.sourceforge.net/project/libpng/libpng16/${v}/libpng-${v}.tar.xz"
    local d="${BUILD_WORK}/libpng"
    extract_tarball "libpng-${v}.tar.xz" "$d"
    (
        export_autotools_env
        cd "$d"
        ./configure --host="$HOST_TRIPLET" --prefix="$SYSROOT" \
            --enable-static --disable-shared --with-zlib-prefix="$SYSROOT"
        make -j"$JOBS"
        make install
    )
}

build_pixman() {
    local v="0.43.4"
    fetch_tarball "pixman-${v}.tar.gz" "https://cairographics.org/releases/pixman-${v}.tar.gz"
    local d="${BUILD_WORK}/pixman"
    extract_tarball "pixman-${v}.tar.gz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_freetype() {
    local v="2.13.3"
    fetch_tarball "freetype-${v}.tar.xz" "https://download.savannah.gnu.org/releases/freetype/freetype-${v}.tar.xz"
    local d="${BUILD_WORK}/freetype"
    extract_tarball "freetype-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dzlib=enabled -Dpng=enabled -Dbzip2=disabled -Dbrotli=disabled -Dharfbuzz=disabled -Dtests=disabled
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_fribidi() {
    local v="1.0.16"
    fetch_tarball "fribidi-${v}.tar.xz" "https://github.com/fribidi/fribidi/releases/download/v${v}/fribidi-${v}.tar.xz"
    local d="${BUILD_WORK}/fribidi"
    extract_tarball "fribidi-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Ddocs=false -Dbin=false -Dtests=false
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_harfbuzz() {
    local v="10.0.1"
    fetch_tarball "harfbuzz-${v}.tar.xz" "https://github.com/harfbuzz/harfbuzz/releases/download/${v}/harfbuzz-${v}.tar.xz"
    local d="${BUILD_WORK}/harfbuzz"
    extract_tarball "harfbuzz-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dfreetype=enabled -Dglib=enabled -Dgobject=enabled -Dgdi=enabled -Ddirectwrite=enabled \
            -Dcairo=disabled -Dicu=disabled -Dgraphite=disabled \
            -Dtests=disabled -Ddocs=disabled -Dutilities=disabled -Dintrospection=disabled
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_cairo() {
    local v="1.18.2"
    fetch_tarball "cairo-${v}.tar.xz" "https://cairographics.org/releases/cairo-${v}.tar.xz"
    local d="${BUILD_WORK}/cairo"
    extract_tarball "cairo-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Ddwrite=disabled -Dfreetype=enabled -Dfontconfig=disabled -Dpng=enabled -Dzlib=enabled \
            -Dglib=enabled -Dxlib=disabled -Dxcb=disabled -Dquartz=disabled \
            -Dtests=disabled -Dspectre=disabled -Dsymbol-lookup=disabled
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_pango() {
    local v="1.54.0"
    fetch_tarball "pango-${v}.tar.xz" "https://download.gnome.org/sources/pango/1.54/pango-${v}.tar.xz"
    local d="${BUILD_WORK}/pango"
    extract_tarball "pango-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dintrospection=disabled -Ddocumentation=false -Dbuild-testsuite=false -Dbuild-examples=false \
            -Dfontconfig=disabled -Dfreetype=disabled -Dxft=disabled -Dcairo=enabled
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_lunasvg() {
    local v="2.4.1"
    fetch_tarball "lunasvg-${v}.tar.gz" "https://github.com/sammycage/lunasvg/archive/refs/tags/v${v}.tar.gz"
    local d="${BUILD_WORK}/lunasvg"
    extract_tarball "lunasvg-${v}.tar.gz" "$d"
    (
        cd "$d"
        cmake -S . -B _build -G Ninja \
            -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
            -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_SHARED_LIBS=OFF \
            -DLUNASVG_BUILD_EXAMPLES=OFF
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_gdk_pixbuf() {
    local v="2.42.12"
    fetch_tarball "gdk-pixbuf-${v}.tar.xz" "https://download.gnome.org/sources/gdk-pixbuf/2.42/gdk-pixbuf-${v}.tar.xz"
    local d="${BUILD_WORK}/gdk-pixbuf"
    extract_tarball "gdk-pixbuf-${v}.tar.xz" "$d"
    # Inject static zero-DLL lunasvg SVG loader directly as a built-in gdk-pixbuf module
    cp "${BASE_DIR}/hal/Windows/win32-svg-loader.cpp" "${d}/gdk-pixbuf/io-svg.cpp"
    python3 - "${d}" "${SYSROOT}/lib" <<'PY'
import pathlib, sys

root = pathlib.Path(sys.argv[1])
sysroot_lib = sys.argv[2]

# 1. Enable C++ in top-level meson.build so io-svg.cpp compiles with lunasvg
top_meson = root / "meson.build"
txt = top_meson.read_text()
txt = txt.replace("project('gdk-pixbuf', 'c',", "project('gdk-pixbuf', 'c', 'cpp',", 1)
if "lunasvg_dep" not in txt:
    txt = txt.replace(
        "gdk_pixbuf_deps = [",
        f"cpp_compiler = meson.get_compiler('cpp')\nlunasvg_dep = cpp_compiler.find_library('lunasvg', dirs: ['{sysroot_lib}'])\npng_static_dep = cpp_compiler.find_library('png16', dirs: ['{sysroot_lib}'])\nz_static_dep = cpp_compiler.find_library('z', dirs: ['{sysroot_lib}'])\ngdk_pixbuf_deps = [\n  lunasvg_dep,\n  png_static_dep,\n  z_static_dep,",
        1,
    )
top_meson.write_text(txt)

# 2. Register static builtin 'svg' module in gdk-pixbuf/gdk-pixbuf-io.c and disable external loaders.cache probe
io_c = root / "gdk-pixbuf" / "gdk-pixbuf-io.c"
txt = io_c.read_text()
if "load_one_builtin_module (svg);" not in txt:
    txt = txt.replace(
        "load_one_builtin_module (png);",
        "load_one_builtin_module (png);\n        load_one_builtin_module (svg);",
        1,
    )
if "\nmodule (svg);" not in txt:
    txt = txt.replace(
        "\nmodule (png);",
        "\nmodule (png);\n#ifdef INCLUDE_svg\nmodule (svg);\n#endif",
        1,
    )
if "try_module (svg,svg);" not in txt:
    txt = txt.replace(
        "try_module (png,png);",
        "try_module (png,png);\n#ifdef INCLUDE_svg\n        try_module (svg,svg);\n#endif",
        1,
    )
if "/* WAYPLANK_STATIC_BUILTIN_ONLY */" not in txt:
    txt = txt.replace(
        "gdk_pixbuf_io_init_builtin ();",
        "gdk_pixbuf_io_init_builtin ();\n        /* WAYPLANK_STATIC_BUILTIN_ONLY */\n        return TRUE;",
        1,
    )
io_c.write_text(txt)

# 3. Compile io-svg.cpp into libgdk_pixbuf-2.0.a with -DINCLUDE_svg
sub_meson = root / "gdk-pixbuf" / "meson.build"
txt = sub_meson.read_text()
if "'io-svg.cpp'" not in txt:
    txt = txt.replace(
        "gdkpixbuf_sources = [",
        "gdkpixbuf_sources = [\n  'io-svg.cpp',",
        1,
    )
    txt = txt.replace(
        "gdk_pixbuf_cflags = [",
        "gdk_pixbuf_cflags = [\n  '-DINCLUDE_svg',",
        1,
    )
sub_meson.write_text(txt)
PY
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dpng=enabled -Djpeg=disabled -Dtiff=disabled -Dgif=enabled -Dothers=enabled \
            -Dbuiltin_loaders=png,bmp,ico,gif \
            -Dgio_sniffing=false -Dnative_windows_loaders=false \
            -Drelocatable=false -Dintrospection=disabled -Dgtk_doc=false \
            -Dman=false -Dtests=false -Dinstalled_tests=false
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

# ============================================================================
# TIER 4: Widget Toolkit (libepoxy, atk, gtk+-3.0 Win32 Static)
# ============================================================================

build_libepoxy() {
    local v="1.5.10"
    fetch_tarball "libepoxy-${v}.tar.gz" "https://github.com/anholt/libepoxy/archive/refs/tags/${v}.tar.gz"
    local d="${BUILD_WORK}/libepoxy"
    extract_tarball "libepoxy-${v}.tar.gz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dglx=no -Degl=no -Dx11=false -Dtests=false -Ddocs=false
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_atk() {
    local v="2.38.0"
    fetch_tarball "atk-${v}.tar.xz" "https://download.gnome.org/sources/atk/2.38/atk-${v}.tar.xz"
    local d="${BUILD_WORK}/atk"
    extract_tarball "atk-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dintrospection=false -Ddocs=false
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_gtk3() {
    local v="3.24.43"
    fetch_tarball "gtk+-${v}.tar.xz" "https://download.gnome.org/sources/gtk+/3.24/gtk+-${v}.tar.xz"
    local d="${BUILD_WORK}/gtk3"
    extract_tarball "gtk+-${v}.tar.xz" "$d"
    (
        cd "$d"
        meson setup _build --cross-file "$CROSS_FILE" \
            --prefix="$SYSROOT" --libdir=lib --default-library=static \
            -Dwin32_backend=true -Dx11_backend=false -Dwayland_backend=false -Dbroadway_backend=false \
            -Dintrospection=false -Ddemos=false -Dexamples=false -Dtests=false -Dinstalled_tests=false \
            -Dgtk_doc=false -Dman=false -Dprint_backends=auto -Dcolord=no -Dcloudproviders=false \
            -Dtracker3=false -Dbuiltin_immodules=all
        ninja -C _build -j"$JOBS"
        ninja -C _build install
        # Guard: ensure gettext-runtime's full libintl.a is never overwritten by gtk3's proxy-libintl
        if [ -f "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" ]; then
            install -m 644 "${BUILD_WORK}/gettext/gettext-runtime/intl/.libs/libintl.a" "${SYSROOT}/lib/libintl.a"
        fi
    )
}

build_sysroot() {
    echo "📦 Building 4-Tier Static MinGW-w64 Sysroot (${SYSROOT})..."
    setup_cross_files
    # Tier 1
    run_step "zlib"            build_zlib
    run_step "libffi"          build_libffi
    run_step "libiconv"        build_libiconv
    run_step "gettext-runtime" build_gettext_runtime
    run_step "pcre2"           build_pcre2
    # Tier 2
    run_step "glib"            build_glib
    run_step "libgee"          build_libgee
    run_step "json-glib"       build_json_glib
    # Tier 3
    run_step "libpng"          build_libpng
    run_step "pixman"          build_pixman
    run_step "freetype"        build_freetype
    run_step "fribidi"         build_fribidi
    run_step "harfbuzz"        build_harfbuzz
    run_step "cairo"           build_cairo
    run_step "pango"           build_pango
    run_step "lunasvg"         build_lunasvg
    run_step "gdk-pixbuf"      build_gdk_pixbuf
    # Tier 4
    run_step "libepoxy"        build_libepoxy
    run_step "atk"             build_atk
    run_step "gtk3"            build_gtk3
    echo "✅ 4-Tier Static MinGW-w64 Sysroot ready!"
}

# ============================================================================
# WAYPLANK WINDOWS CROSS-COMPILATION & ZERO-DLL VERIFICATION
# ============================================================================

check_toolchain
build_sysroot
if [ "$ONLY_SYSROOT" -eq 1 ]; then
    exit 0
fi

echo "🛡️ Verifying Zone 1 / Zone 2 HAL Purity Firewall..."
HAL_FIREWALL_REGEX='GtkLayerShell|GdkWayland|GdkX11|GdkWin32|Posix\.|GLib\.Unix|UnixFDList|UnixInputStream|sys/prctl\.h|unistd\.h|DesktopAppInfo|GDesktopAppInfo|VolumeMonitor|RecentManager|show_uri|\[DBus|DBusConnection|DBusProxy|DBusManager|DBusClient|BusType\.|Bus\.(get|own_name|watch_name)|UnityClient|IPortalThemeBus|/proc/|/sys/|/dev/i2c|trash://|WindowControl|WindowCapabilities|\bWindowBackend\b|KWin|MutterBackend|LabwcBackend|WlrBridge|SurfaceCoordinateService|BrightnessControl|XdgSession|environment_is_session_|Shell\.parse_argv|has_prefix\s*\(\s*"/"|Win32|HWND|\bAppInfo\.|AppLaunchContext|KeyFileDesktop|"Desktop Entry"|"Desktop Action "|\.desktop"|\.directory"|desktop\.ini|applications?://|Shell\.quote|xdg-open|has_prefix\s*\(\s*"~/|XDG_CURRENT_DESKTOP|/var/lib/(snapd|flatpak)|/opt/google|/usr/(local/)?share|/tmp/\.mount_|Dbusmenu|HAVE_DBUSMENU|x-(desktop|gnome-app-info|kde-appmenu)|layer_shell|unity_|\bapp_dbus\b'
if FIREWALL_HITS="$(grep -rnE --exclude="resources.c" "$HAL_FIREWALL_REGEX" "${BASE_DIR}/src" "${BASE_DIR}/lib" "${BASE_DIR}/hal/Interfaces" "${BASE_DIR}/vapi/core" || true)" && [ -n "$FIREWALL_HITS" ]; then
    echo "❌ HAL PURITY FIREWALL VIOLATION DETECTED (Zone 1 / Zone 2):"
    echo "$FIREWALL_HITS"
    exit 1
fi
echo "   ✅ Gates 1 & 2 GREEN: 0 leaks across src/, lib/, hal/Interfaces/, vapi/core/."

echo "🌍 Compiling embedded locales, GSettings schema & GResource..."
python3 "${BASE_DIR}/po/generate_translations.py"
rm -rf "${BASE_DIR}/data/locale"
EMBEDDED_LANGS=""
EXTRA_XML_ENTRIES=""
for po in "${BASE_DIR}"/po/*.po; do
    lang="$(basename "$po" .po)"
    mkdir -p "${BASE_DIR}/data/locale/${lang}"
    msgfmt "$po" -o "${BASE_DIR}/data/locale/${lang}/wayplank.mo"
    if [ -z "$EMBEDDED_LANGS" ]; then
        EMBEDDED_LANGS="${lang}"
    else
        EMBEDDED_LANGS="${EMBEDDED_LANGS}:${lang}"
    fi
    EXTRA_XML_ENTRIES="${EXTRA_XML_ENTRIES}		<file compressed=\"true\">locale/${lang}/wayplank.mo</file>\n"
done

SCHEMA_STAGE="${WIN_C_DIR}_schemas"
rm -rf "$SCHEMA_STAGE"
mkdir -p "$SCHEMA_STAGE"
cp "${BASE_DIR}/data/glib-2.0/schemas/"*.gschema.xml "$SCHEMA_STAGE/"
if [ -d "${SYSROOT}/share/glib-2.0/schemas" ]; then
    cp "${SYSROOT}/share/glib-2.0/schemas/"*.gschema.xml "$SCHEMA_STAGE/" 2>/dev/null || true
fi
glib-compile-schemas "$SCHEMA_STAGE" --targetdir="${BASE_DIR}/data/glib-2.0/schemas"
rm -rf "$SCHEMA_STAGE"
EXTRA_XML_ENTRIES="${EXTRA_XML_ENTRIES}		<file compressed=\"true\">glib-2.0/schemas/gschemas.compiled</file>\n"

awk -v entries="$EXTRA_XML_ENTRIES" '
    /<\/gresource>/ { printf "%s", entries }
    { print }
' "${BASE_DIR}/data/plank.gresource.xml" > "$BUILD_GRESOURCE_XML"

rm -rf "$WIN_C_DIR"
mkdir -p "$OUT_DIR" "$WIN_C_DIR"

glib-compile-resources \
    --sourcedir="${BASE_DIR}/data" \
    --target="${WIN_C_DIR}/resources.c" \
    --generate-source \
    "$BUILD_GRESOURCE_XML"
rm -rf "${BASE_DIR}/data/locale"

echo "🏗️ Transpiling Zone 1 + Zone 2 + hal/Windows/ Vala sources to portable C..."
mapfile -t VALA_FILES < <(find "${BASE_DIR}/hal/Interfaces" "${BASE_DIR}/hal/Windows" "${BASE_DIR}/lib" "${BASE_DIR}/src" -name "*.vala" | sort)

valac -C -d "$WIN_C_DIR" \
    --gresources="$BUILD_GRESOURCE_XML" \
    --gresourcesdir="${BASE_DIR}/data" \
    --vapidir="${BASE_DIR}/vapi/core" \
    --vapidir="${BASE_DIR}/vapi/windows" \
    --pkg gtk+-3.0 \
    --pkg gee-0.8 \
    --pkg json-glib-1.0 \
    --pkg compat \
    --pkg config \
    --pkg win32-bridge \
    --pkg win32-app-bridge \
    --pkg win32-sys-bridge \
    --pkg win32-media-bridge \
    "${VALA_FILES[@]}"

echo "🪟 Compiling Windows resource manifest (wayplank.rc)..."
cat > "${WIN_C_DIR}/wayplank-ver.h" <<EOF
#define WAYPLANK_VER_STR "${PKG_VER}\0"
#define WAYPLANK_VER_CSV ${PKG_VER_CSV}
#define WAYPLANK_COMPANY_STR "${PKG_COMPANY}\0"
#define WAYPLANK_COPYRIGHT_STR "Copyright (C) ${PKG_YEAR} ${PKG_HOLDER} (GPLv3)\0"
#define WAYPLANK_PRODUCT_STR "${PKG_PROG}\0"
EOF
sed "s/@WAYPLANK_VER_4@/${PKG_VER_4}/g" "${BASE_DIR}/hal/Windows/wayplank.manifest" > "${WIN_C_DIR}/wayplank.manifest"
"$WIN_WINDRES" \
    -I "${WIN_C_DIR}" \
    -I "${BASE_DIR}/hal/Windows" \
    "${BASE_DIR}/hal/Windows/wayplank.rc" \
    -O coff -o "${WIN_C_DIR}/wayplank.res.o"

echo "⚙️ Cross-compiling C sources (${JOBS} parallel jobs)..."
WIN_PKG_CONFIG="${SYSROOT}/bin/${HOST_TRIPLET}-pkg-config"
WIN_CFLAGS=(
    -O2
    -D_WIN32_WINNT=0x0601
    -DWINVER=0x0601
    -DGLIB_STATIC_COMPILATION
    -DGOBJECT_STATIC_COMPILATION
    -DGIO_STATIC_COMPILATION
    -DGMODULE_STATIC_COMPILATION
    -DATK_STATIC_COMPILATION
    -DCAIRO_WIN32_STATIC_BUILD
    -DGETTEXT_PACKAGE=\"wayplank\"
    -DPACKAGE_VERSION=\"${PKG_VER}\"
    "-DPACKAGE_VERSION_DECO=\"${PKG_DECO}\""
    -DPACKAGE_YEAR=\"${PKG_YEAR}\"
    -DPACKAGE_URL=\"${PKG_HOMEPAGE}\"
    -DPACKAGE_BUGREPORT=\"${PKG_ISSUES}\"
    -DWAYPLANK_EMBEDDED_LANGS=\"${EMBEDDED_LANGS}\"
    -I"${BASE_DIR}/lib"
    -I"${BASE_DIR}/include"
    -I"${BASE_DIR}/hal/Windows/Compositor"
    -I"${BASE_DIR}/hal/Windows/AppSystem"
    -I"${BASE_DIR}/hal/Windows/Bus"
    -I"${BASE_DIR}/hal/Windows/Telemetry"
    -include "${BASE_DIR}/include/config.h"
    -w
)
# Read pkg-config cflags into array
read -r -a PKG_CFLAGS <<< "$("$WIN_PKG_CONFIG" --cflags gtk+-3.0 gee-0.8 json-glib-1.0)"

mapfile -t GEN_C_FILES < <(find "$WIN_C_DIR" -name "*.c" | sort)
EXTRA_C_FILES=("${BASE_DIR}/lib/gtk-compat.c")
while IFS= read -r win_c; do
    EXTRA_C_FILES+=("$win_c")
done < <(find "${BASE_DIR}/hal/Windows" -name "*.c" | sort)

ALL_C_FILES=("${GEN_C_FILES[@]}" "${EXTRA_C_FILES[@]}")
OBJ_FILES=("${WIN_C_DIR}/wayplank.res.o")

compile_one() {
    local src="$1"
    local obj="$2"
    "$WIN_CC" "${WIN_CFLAGS[@]}" "${PKG_CFLAGS[@]}" -c "$src" -o "$obj"
}

active_jobs=0
idx=0
for cfile in "${ALL_C_FILES[@]}"; do
    idx=$((idx + 1))
    obj="${WIN_C_DIR}/obj_${idx}.o"
    OBJ_FILES+=("$obj")
    compile_one "$cfile" "$obj" &
    active_jobs=$((active_jobs + 1))
    if [ "$active_jobs" -ge "$JOBS" ]; then
        wait -n
        active_jobs=$((active_jobs - 1))
    fi
done
wait

echo "🔗 Linking Zero-DLL static PE32+ monolith (${OUT_DIR}/wayplank.exe)..."
read -r -a PKG_LIBS <<< "$("$WIN_PKG_CONFIG" --libs gtk+-3.0 gee-0.8 json-glib-1.0)"

"$WIN_CXX" \
    -static -static-libgcc -static-libstdc++ -mwindows -O2 \
    -Wl,--allow-multiple-definition \
    -L"${SYSROOT}/lib" \
    "${OBJ_FILES[@]}" \
    -Wl,--start-group \
    "${PKG_LIBS[@]}" \
    -llunasvg \
    -lgtk-3 -lgdk-3 -latk-1.0 \
    -lpangowin32-1.0 -lpangocairo-1.0 -lpango-1.0 \
    -lharfbuzz -lfribidi -lcairo-gobject -lcairo -lpixman-1 -lfreetype \
    -lgdk_pixbuf-2.0 -lpng16 -lepoxy \
    -lgee-0.8 -ljson-glib-1.0 \
    -lgio-2.0 -lgobject-2.0 -lgmodule-2.0 -lgthread-2.0 -lglib-2.0 \
    -lintl -liconv -lpcre2-8 -lffi -lz \
    -Wl,--end-group \
    -limm32 -lwinmm -lgdi32 -lmsimg32 -lshell32 -lshlwapi -lcomctl32 -lcomdlg32 \
    -lole32 -loleaut32 -luuid -ldwmapi -luxtheme -lws2_32 -lwinhttp -liphlpapi \
    -ldnsapi -lsetupapi -lhid -lwtsapi32 -ldxva2 -lpowrprof -luser32 -ladvapi32 -lkernel32 \
    -lm \
    -o "${OUT_DIR}/wayplank.exe"

"$WIN_STRIP" --strip-all "${OUT_DIR}/wayplank.exe"

echo "🔍 Verifying Zero-DLL PE32+ Evergreen Windows OS Allowlist (GEMINI.md §8)..."
python3 - "${OUT_DIR}/wayplank.exe" "$WIN_OBJDUMP" <<'PY'
import subprocess, sys, re

exe_path, objdump_cmd = sys.argv[1], sys.argv[2]
out = subprocess.check_output([objdump_cmd, "-p", exe_path], text=True, errors="replace")
dlls = sorted(set(re.findall(r"DLL Name:\s+(\S+)", out)))

# Evergreen Windows 7 <-> 11+ OS DLL allowlist (GEMINI.md §8 + MSVC/UCRT stock OS runtime)
ALLOWLIST = {
    "KERNEL32.DLL", "ADVAPI32.DLL", "USER32.DLL", "IMM32.DLL", "WINMM.DLL",
    "GDI32.DLL", "MSIMG32.DLL", "SHELL32.DLL", "SHLWAPI.DLL", "COMCTL32.DLL",
    "COMDLG32.DLL", "OLE32.DLL", "OLEAUT32.DLL", "UUID.DLL", "DWMAPI.DLL",
    "UXTHEME.DLL", "WS2_32.DLL", "WINHTTP.DLL", "IPHLPAPI.DLL", "DNSAPI.DLL",
    "SETUPAPI.DLL", "HID.DLL", "WTSAPI32.DLL", "DXVA2.DLL", "POWRPROF.DLL",
    "MSVCRT.DLL", "USP10.DLL", "WININSPOOL.DRV", "WINSPOOL.DRV", "CFGMGR32.DLL",
    "BCRYPT.DLL", "CRYPT32.DLL", "NETAPI32.DLL", "USERENV.DLL", "VERSION.DLL",
    "OPENGL32.DLL", "GDIPLUS.DLL", "PSAPI.DLL", "WLANAPI.DLL", "DWRITE.DLL", "RPCRT4.DLL",
}

forbidden = [d for d in dlls if d.upper() not in ALLOWLIST]
print("   📋 Imported DLLs:", ", ".join(dlls))
if forbidden:
    print("❌ ZERO-DLL GATE FAILED! Forbidden non-OS DLLs detected:", ", ".join(forbidden), file=sys.stderr)
    sys.exit(1)
print(f"   ✅ ZERO-DLL GATE GREEN: {len(dlls)} evergreen Windows OS DLLs only (0 third-party/MinGW/GTK DLLs).")
PY

ls -lh "${OUT_DIR}/wayplank.exe"
echo "✅ Windows Zero-DLL Monolith ready: ${OUT_DIR}/wayplank.exe"
