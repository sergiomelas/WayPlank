#!/usr/bin/env python3
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
# FAT Urgency State Test (Wayplank Attention Protocol Tester)
# Author: Sergio Melas <sergiomelas@gmail.com>
# ==============================================================================

import os
import sys
import time
import subprocess

def detect_compositor():
    desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or "").lower()
    if "kde" in desktop or "plasma" in desktop:
        return "kwin"
    elif "gnome" in desktop or "ubuntu" in desktop:
        return "gnome"
    elif "labwc" in desktop or "wlroots" in desktop:
        return "labwc"
    
    try:
        out = subprocess.check_output(["ps", "-e"], text=True)
        if "kwin_wayland" in out:
            return "kwin"
        if "gnome-shell" in out:
            return "gnome"
        if "labwc" in out:
            return "labwc"
    except Exception:
        pass
    return "generic"

def run_kwin_konsole():
    # Verify Konsole is running so KWin can target it
    has_konsole = subprocess.run(["pgrep", "-x", "konsole"], capture_output=True).returncode == 0
    if not has_konsole:
        print("⚠️  REMINDER FOR TESTER:")
        print("   Konsole must be open/running before launching this test on KDE Plasma!")
        print("   Please start Konsole first, then re-run test_urgency.py.")
        print("")
        sys.exit(1)

    print("ℹ️  TESTER NOTE: Konsole is running and will be targeted for urgency.")
    print("👉 Switch focus to another window (e.g. Browser or Editor) RIGHT NOW!")
    print("   In 3 seconds, KWin will trigger 'demandsAttention' on Konsole.")
    print("")

    for i in range(3, 0, -1):
        print(f"Triggering in {i} seconds...")
        time.sleep(1)

    script_content = """
    var windows = workspace.windowList();
    for (var i = 0; i < windows.length; i++) {
        var w = windows[i];
        if (w.resourceClass === 'org.kde.konsole' || (w.desktopFileName && w.desktopFileName.indexOf('konsole') !== -1)) {
            w.demandsAttention = true;
            break;
        }
    }
    """

    script_file = "/tmp/wayplank_attention_trigger.js"
    with open(script_file, "w") as f:
        f.write(script_content)

    res = subprocess.run(["qdbus", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", script_file], capture_output=True, text=True)
    sid = res.stdout.strip()
    if sid.isdigit():
        subprocess.run(["qdbus", "org.kde.KWin", f"/Scripting/Script{sid}", "org.kde.kwin.Script.run"], capture_output=True)
        subprocess.run(["qdbus", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", script_file], capture_output=True)

    if os.path.exists(script_file):
        os.remove(script_file)

    print("")
    print("🔔 URGENCY HINT TRIGGERED ON KONSOLE!")
    print("👉 Look at the Konsole icon on your Wayplank dock: it is now bouncing!")
    print("👉 Click on the Konsole window/icon to give it focus: the bouncing stops immediately.")

def run_terminal_bell():
    print("👉 Switch focus to another window (e.g. Browser or Editor) RIGHT NOW!")
    print("   In 3 seconds, urgency will be triggered on this terminal.")
    print("")

    for i in range(3, 0, -1):
        print(f"Triggering in {i} seconds...")
        time.sleep(1)

    # Standard terminal bell trigger (\a) sets urgency / demands-attention on unfocused terminals
    sys.stdout.write('\a')
    sys.stdout.flush()

    print("")
    print("🔔 URGENCY HINT TRIGGERED ON TERMINAL!")
    print("👉 Look at the terminal icon on your Wayplank dock: it should now be bouncing!")
    print("👉 Click on this terminal window to give it focus: the bouncing stops immediately.")

def main():
    print("=======================================================")
    print("   Wayplank FAT Attention / Urgent State Test    ")
    print("=======================================================")
    
    comp = detect_compositor()
    print(f"Detected Desktop Environment / Compositor: {comp.upper()}")
    print("───────────────────────────────────────────────────────")

    if comp == "labwc":
        print("LabWC detected: urgent-attention is not applicable in LabWC")
        sys.exit(0)
    elif comp == "kwin":
        run_kwin_konsole()
    else:
        run_terminal_bell()

if __name__ == "__main__":
    main()
