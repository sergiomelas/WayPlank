//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of WayPlank.
//
//  WayPlank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  WayPlank is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

namespace Plank
{
    public static int main (string[] argv)
    {
        Intl.setlocale (LocaleCategory.ALL, "");
        PlankCompat.i18n_init ();

        bool replace_requested = false;

        foreach (unowned string arg in argv) {
            if (arg == "--help" || arg == "-h" || arg == "-?") {
                print_clean_help ();
                return 0;
            }
            if (arg == "--version" || arg == "-v" || arg == "-V") {
                print ("WayPlank %s\n", Build.VERSION);
                return 0;
            }
            if (arg == "--shortcuts" || arg == "-s" || arg == "--gestures") {
                print_shortcuts_cheatsheet ();
                return 0;
            }
            if (arg == "--replace" || arg == "--reload" || arg == "-r") {
                replace_requested = true;
            }
        }

        if (replace_requested) {
            int self_pid = (int) Posix.getpid ();
            try {
                string out_pids = "";
                Process.spawn_command_line_sync ("pidof wayplank", out out_pids);
                foreach (unowned string tok in out_pids.strip ().split (" ")) {
                    int p = int.parse (tok);
                    if (p > 0 && p != self_pid)
                        Posix.kill ((Posix.pid_t) p, Posix.Signal.TERM);
                }
            } catch (Error e) { }
            Thread.usleep (200000);
            try {
                string out_pids = "";
                Process.spawn_command_line_sync ("pidof wayplank", out out_pids);
                foreach (unowned string tok in out_pids.strip ().split (" ")) {
                    int p = int.parse (tok);
                    if (p > 0 && p != self_pid)
                        Posix.kill ((Posix.pid_t) p, Posix.Signal.KILL);
                }
            } catch (Error e) { }
            Thread.usleep (50000);
        }

        AbstractMain.saved_gtk_use_portal = Environment.get_variable ("GTK_USE_PORTAL");
        Environment.set_variable ("GTK_USE_PORTAL", "0", true);

        Gtk.init (ref argv);

        unowned Gdk.Display? display = Gdk.Display.get_default ();
        if (display == null || display.get_type ().name () != "GdkWaylandDisplay") {
            var dialog = new Gtk.MessageDialog (
                null,
                Gtk.DialogFlags.MODAL,
                Gtk.MessageType.WARNING,
                Gtk.ButtonsType.OK,
                _("WayPlank is designed exclusively for Wayland sessions.")
            );
            dialog.title = _("WayPlank - Unsupported Session");
            dialog.run ();
            dialog.destroy ();
            return 1;
        }

        var application = new Plank.Main ();
        Factory.init (application, new ItemFactory ());
        return application.run (argv);
    }

    public class Main : AbstractMain
    {
        public Main ()
        {
            var authors = new string[] {
                    "Sergio Melas <sergiomelas@gmail.com>",
                    "史有虎 (IFtiger-hu) <2212363803@qq.com>",
                    "Robert Dyer <psybers@gmail.com>",
                    "Rico Tzschichholz <ricotz@ubuntu.com>",
                    "Michal Hruby <michal.mhr@gmail.com>"
                };

            var documenters = new string[] {
                    "Sergio Melas <sergiomelas@gmail.com>",
                    "Robert Dyer <psybers@gmail.com>",
                    "Rico Tzschichholz <ricotz@ubuntu.com>"
                };

            var artists = new string[] {
                    "Sergio Melas <sergiomelas@gmail.com>",
                    "Daniel Foré <daniel@elementaryos.org>"
                };

            Object (
                build_data_dir : Build.DATADIR,
                build_pkg_data_dir : Build.PKGDATADIR,
                build_release_name : Build.RELEASE_NAME,
                build_version : Build.VERSION,
                build_version_info : Build.VERSION_INFO,

                program_name : "WayPlank",
                exec_name : "wayplank",

                app_copyright : "2026 Sergio Melas\nCopyright © 2011-2017 Plank Developers",
                app_dbus : "net.launchpad.plank",
                app_icon : "plank",
                app_launcher : "wayplank.desktop",

                main_url : "https://github.com/sergiomelas/wayplank",
                help_url : "https://github.com/sergiomelas/wayplank/issues",
                translate_url : "https://github.com/sergiomelas/wayplank",

                about_authors : authors,
                about_documenters : documenters,
                about_artists : artists,
                about_translators : _("translator-credits"),
                about_license_type : Gtk.License.GPL_3_0
            );
        }
    }

    static void print_clean_help ()
    {
        print ("Usage:\n  wayplank [OPTION…]\n\n");
        print ("Help Options:\n");
        print ("  -h, --help                Show help options\n");
        print ("  -s, --shortcuts           Show shortcuts and mouse gestures in terminal\n");
        print ("  -v, --version             Show application version\n\n");
        print ("Application Options:\n");
        print ("  -p, --preferences         Show preferences dialog of the running or started instance\n");
        print ("  -r, --replace, --reload   Restart and replace running dock instance\n");
        print ("  -d, --debug               Enable debug logging\n");
        print ("  -V, --verbose             Enable verbose logging\n");
        print ("  -n, --name=NAME           The name of this dock. Defaults to \"dock1\"\n\n");
    }

    static void print_shortcuts_cheatsheet ()
    {
        print ("\n=======================================================\n");
        print ("  WayPlank — Shortcuts, Mouse Controls & Gestures Guide\n");
        print ("=======================================================\n\n");
        print ("MOUSE ACTIONS ON ICONS:\n");
        print ("  Left Click                    Launch app; if running, raises or opens Multi-Window Cards\n");
        print ("  Middle Click (or Ctrl+Left)   Force launch a NEW instance of the application\n");
        print ("  Right Click                   Open context menu (Recent Documents, Quicklists, Keep in\n");
        print ("                                Dock, Change Icon, Shortcuts & Gestures, Preferences)\n");
        print ("  Mouse Scroll on App           Cycle between all open windows of this application\n");
        print ("  Hover / Click on Preferences  Expand docklet accordion drawer; Directional indicators (▸ / ◂ / ▾ / ▴)\n");
        print ("  Accordion Auto-Retention      Drawer stays open during menus/dialogs; resets delay (0.5s–20s) on close\n\n");
        print ("MULTI-WINDOW PREVIEW CARDS:\n");
        print ("  Left Click (2+ windows)       Displays floating Cairo preview cards with live window thumbnails\n");
        print ("  Card Left Click               Brings chosen window forward and focuses it\n");
        print ("  Card Close / Middle Click     Closes the target window instance directly from the card\n");
        print ("  Preferences -> Behaviour      Toggle between Multi-Window Preview Cards and cyclic switching\n\n");
        print ("OVERFLOW & DYNAMIC ZOOM:\n");
        print ("  Mouse Scroll on Dock Body     Smoothly scroll overflowing dock items when capacity is reached\n");
        print ("  Ctrl + Mouse Scroll Up        Increase dock icon size dynamically in real-time\n");
        print ("  Ctrl + Mouse Scroll Down      Decrease dock icon size dynamically in real-time\n\n");
        print ("DRAG & DROP GESTURES:\n");
        print ("  Drag icon off dock            Unpin / remove launcher from dock (with poof animation)\n");
        print ("  Drag icon along dock          Reorder pinned items (within category in Categorized mode)\n");
        print ("  Drop file on app icon         Open the dropped file directly with that application\n");
        print ("  Drop web URL on browser       Drop http:// or https:// URL onto browser to open in new tab\n");
        print ("  Hover over icon during DND    Spring-loaded hover (500ms) raises window to foreground\n");
        print ("  Drop .desktop / folder        Pin a new application or folder drawer to the dock\n\n");
        print ("DOCK CONTROLS & THEMES:\n");
        print ("  Right Click -> Change Icon    Choose system icon or custom image for launcher or folder\n");
        print ("  Right Click -> Shortcuts      Open interactive Shortcuts & Gestures window directly\n");
        print ("  Ctrl + Right Click            Open dock preferences menu directly, even over an icon\n");
        print ("  Preferences -> Theme Manager  Install theme archives (.zip, .tar.gz) with native file chooser\n");
        print ("  Dynamic Counterpart Swapping  Real-time automatic Light/Dark mode switching on KDE and GNOME\n");
        print ("  Ctrl+Alt+Shift + Right Click  Open Developer Tools submenu (inspect launcher, config, theme)\n\n");
    }
}
