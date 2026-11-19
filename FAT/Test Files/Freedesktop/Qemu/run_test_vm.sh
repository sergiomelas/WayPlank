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
# WayPlank FAT - QEMU Multi-VM Test Launcher
# Author: Sergio Melas <sergiomelas@gmail.com>
# ==============================================================================
# Checks for local CirrOS test-vm.img; downloads it automatically if missing.
# Supports launching distinct VMs by name/number or dual concurrent execution.
#
# Usage:
#   ./run_test_vm.sh          -> Launches VM-Alpha (default)
#   ./run_test_vm.sh 1        -> Launches VM-Alpha
#   ./run_test_vm.sh 2        -> Launches VM-Beta
#   ./run_test_vm.sh both     -> Launches both VM-Alpha and VM-Beta concurrently
#   ./run_test_vm.sh <name>   -> Launches VM with custom name
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG_FILE="${SCRIPT_DIR}/test-vm.img"
DOWNLOAD_URL="https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img"

# Verify if qemu-system-x86_64 is available
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "❌ Error: qemu-system-x86_64 not found in PATH." >&2
    echo "👉 Please install it via: sudo apt install qemu-system-x86" >&2
    exit 1
fi

# Download image if not already present
if [ ! -f "${IMG_FILE}" ]; then
    echo "📥 test-vm.img not found in ${SCRIPT_DIR}."
    echo "🌐 Downloading CirrOS test image (approx. 16 MB)..."
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --progress-bar "${DOWNLOAD_URL}" -o "${IMG_FILE}"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "${IMG_FILE}" "${DOWNLOAD_URL}"
    else
        echo "❌ Error: Neither curl nor wget is installed." >&2
        exit 1
    fi
    echo "✅ Download completed: ${IMG_FILE}"
fi

ARG="${1:-1}"

case "${ARG}" in
    1|alpha|Alpha)
        VM_NAME="VM-Alpha"
        ;;
    2|beta|Beta)
        VM_NAME="VM-Beta"
        ;;
    both|dual|all)
        echo "🚀 Launching Dual VMs: 'VM-Alpha' and 'VM-Beta'..."
        qemu-system-x86_64 \
            -accel kvm -accel tcg \
            -name "VM-Alpha" \
            -m 512M \
            -drive file="${IMG_FILE}",format=qcow2,snapshot=on &
        PID_ALPHA=$!
        sleep 0.8
        qemu-system-x86_64 \
            -accel kvm -accel tcg \
            -name "VM-Beta" \
            -m 512M \
            -drive file="${IMG_FILE}",format=qcow2,snapshot=on &
        PID_BETA=$!
        echo "✅ VM-Alpha (PID $PID_ALPHA) and VM-Beta (PID $PID_BETA) started concurrently."
        echo "ℹ️  Press Ctrl+C or close both windows to exit."
        wait
        exit 0
        ;;
    *)
        VM_NAME="${ARG}"
        ;;
esac

echo "🚀 Launching QEMU VM: '${VM_NAME}' (RAM: 512M, snapshot mode)..."
exec qemu-system-x86_64 \
    -accel kvm -accel tcg \
    -name "${VM_NAME}" \
    -m 512M \
    -drive file="${IMG_FILE}",format=qcow2,snapshot=on \
    "${@:2}"
