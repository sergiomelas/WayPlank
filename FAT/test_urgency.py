#!/usr/bin/env python3
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

def run_gtk_window(compositor):
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, GLib

    class UrgencyTestWindow(Gtk.Window):
        def __init__(self):
            super().__init__(title="Wayplank Urgency Tester")
            self.set_default_size(360, 160)
            self.set_position(Gtk.WindowPosition.CENTER)
            
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            box.set_margin_top(20)
            box.set_margin_bottom(20)
            box.set_margin_start(20)
            box.set_margin_end(20)
            
            self.label = Gtk.Label()
            self.label.set_line_wrap(True)
            self.label.set_markup("<b>Switch focus to another window now!</b>\nUrgency hint will trigger in 3 seconds...")
            box.pack_start(self.label, True, True, 0)
            
            self.btn_close = Gtk.Button(label="Close Test")
            self.btn_close.connect("clicked", lambda b: Gtk.main_quit())
            box.pack_start(self.btn_close, False, False, 0)
            
            self.add(box)
            self.connect("destroy", Gtk.main_quit)
            self.connect("focus-in-event", self.on_focus_in)
            
            self.countdown = 3
            GLib.timeout_add_seconds(1, self.on_tick)

        def on_tick(self):
            self.countdown -= 1
            if self.countdown > 0:
                self.label.set_markup(f"<b>Switch focus away now!</b>\nUrgency hint will trigger in {self.countdown}s...")
                return True
            else:
                self.set_urgency_hint(True)
                if compositor == "labwc":
                    self.label.set_markup("🔔 <b>Urgency Hint Sent via GTK!</b>\n\n<i>Note: wlroots (zwlr_foreign_toplevel_management_v1) lacks urgency protocol events, so foreign docks cannot receive attention notifications by protocol design.</i>")
                else:
                    self.label.set_markup("🔔 <b>URGENT STATE TRIGGERED!</b>\n\nLook at the dock icon: it should be bouncing.\nFocus this window to clear urgency.")
                return False

        def on_focus_in(self, widget, event):
            self.set_urgency_hint(False)
            return False

    win = UrgencyTestWindow()
    win.show_all()
    Gtk.main()

def main():
    print("=======================================================")
    print("   Wayplank FAT 2.7 - Attention / Urgent State Test    ")
    print("=======================================================")
    
    comp = detect_compositor()
    print(f"Detected Desktop Environment / Compositor: {comp.upper()}")
    print("───────────────────────────────────────────────────────")

    if comp == "kwin" and len(sys.argv) == 1:
        run_kwin_konsole()
    elif comp == "labwc":
        print("ℹ️ Note for Labwc / wlroots:")
        print("  The 'zwlr_foreign_toplevel_management_unstable_v1' Wayland protocol")
        print("  used by wlroots compositors only exports: maximized, minimized,")
        print("  activated, and fullscreen states. It lacks an 'urgent' state.")
        print("  Launching universal GTK test window...")
        print("")
        run_gtk_window("labwc")
    else:
        print("Launching universal GTK test window...")
        run_gtk_window(comp)

if __name__ == "__main__":
    main()
