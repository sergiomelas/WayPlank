#!/usr/bin/env python3
#
#  Copyright (C) 2026 Sergio Melas <sergiomelas@gmail.com>
#
#  This file is part of Wayplank.
#
#  Wayplank is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  Wayplank is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ==============================================================================
# FAT Notification & Do Not Disturb State Tester
# Author: Sergio Melas <sergiomelas@gmail.com>
# ==============================================================================

import os
import sys
import time
import subprocess

def query_dnd_status():
    try:
        res = subprocess.run(
            ["qdbus", "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications.Inhibited"],
            capture_output=True, text=True, timeout=2
        )
        if res.returncode == 0:
            return res.stdout.strip().lower() == "true"
    except Exception:
        pass

    try:
        res = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.notifications", "show-banners"],
            capture_output=True, text=True, timeout=2
        )
        if res.returncode == 0:
            return res.stdout.strip().lower() == "false"
    except Exception:
        pass

    return None

def send_notification(summary, body, urgency="normal"):
    if subprocess.run(["which", "notify-send"], capture_output=True).returncode == 0:
        subprocess.run(["notify-send", "-a", "WayPlank FAT", "-u", urgency, "-i", "preferences-desktop-notification-bell", summary, body])
        return True

    # Fallback to direct DBus call via qdbus
    try:
        subprocess.run([
            "qdbus", "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications.Notify",
            "WayPlank FAT", "0", "preferences-desktop-notification-bell",
            summary, body, "[]", "{}", "5000"
        ], capture_output=True, timeout=2)
        return True
    except Exception as e:
        print(f"❌ Failed to dispatch notification via DBus: {e}")
        return False

def main():
    print("=======================================================")
    print("    Wayplank FAT Do Not Disturb & Notification Test    ")
    print("=======================================================")
    print("")

    dnd_active = query_dnd_status()
    if dnd_active is True:
        status_str = "🔴 ACTIVE (Notifications Silenced / Inhibit ON)"
    elif dnd_active is False:
        status_str = "🟢 INACTIVE (Notifications Allowed / Inhibit OFF)"
    else:
        status_str = "⚪ UNKNOWN (Notification daemon query failed)"

    print(f"Current Desktop DND State: {status_str}")
    print("───────────────────────────────────────────────────────")
    print("")

    timestamp = time.strftime("%H:%M:%S")
    summary = f"WayPlank FAT Test [{timestamp}]"

    if dnd_active:
        body = "Do Not Disturb is ACTIVE. If working correctly, this notification should be SILENCED/SUPPRESSED."
        print("🔕 Sending test notification under DO NOT DISTURB mode...")
    else:
        body = "Do Not Disturb is OFF. This notification banner should be visible on your screen."
        print("🔔 Sending test notification under NORMAL mode...")

    success = send_notification(summary, body)
    if success:
        print("✅ Notification dispatched successfully.")
    else:
        print("❌ Could not dispatch notification.")

    print("")
    print("📋 FAT TEST PROCEDURE FOR TESTER:")
    print("───────────────────────────────────────────────────────")
    print("1. [DND Inactive]: Click WayPlank DND docklet so it shows the active bell icon.")
    print("   Run this script -> Verify banner appears on screen.")
    print("2. [DND Active]: Click WayPlank DND docklet so it shows the muted/disabled bell icon.")
    print("   Run this script -> Verify banner is suppressed/silenced by the desktop.")
    print("3. [Right-Click Menu]: Right-click the DND docklet -> verify 'Resume / Silence Notifications'")
    print("   and 'Notification Settings...' items work as expected.")
    print("───────────────────────────────────────────────────────")

if __name__ == "__main__":
    main()

