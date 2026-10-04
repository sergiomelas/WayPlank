//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of Wayplank.
//
//  Wayplank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Wayplank is distributed in the hope that it will be useful,
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
        Intl.bindtextdomain (Build.GETTEXT_PACKAGE, Build.DATADIR + "/locale");
        Intl.bind_textdomain_codeset (Build.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Build.GETTEXT_PACKAGE);

        bool replace_requested = false;
        for (int i = 1; i < argv.length; i++) {
            if (argv[i] == "--help" || argv[i] == "-h" || argv[i] == "-?") {
                print_clean_help ();
                return 0;
            }
            if (argv[i] == "--version" || argv[i] == "-v" || argv[i] == "-V") {
                print ("Wayplank %s\n", Build.VERSION);
                return 0;
            }
            if (argv[i] == "--shortcuts" || argv[i] == "-s" || argv[i] == "--gestures") {
                print_shortcuts_cheatsheet ();
                return 0;
            }
            if (argv[i] == "--replace" || argv[i] == "-r") {
                replace_requested = true;
            }
        }

        if (replace_requested) {
            try {
                Process.spawn_command_line_sync ("killall -q -o 1s -9 wayplank");
            } catch (Error e) { }
            Thread.usleep (250000);
        }

        Gtk.init (ref argv);

        unowned Gdk.Display? display = Gdk.Display.get_default ();
        if (display == null || display.get_type ().name () != "GdkWaylandDisplay") {
            var dialog = new Gtk.MessageDialog (
                null,
                Gtk.DialogFlags.MODAL,
                Gtk.MessageType.WARNING,
                Gtk.ButtonsType.OK,
                "Wayplank is designed exclusively for Wayland sessions."
            );
            dialog.title = "Wayplank - Unsupported Session";
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
                    "Daniel Foré <daniel@elementaryos.org>"
                };

            Object (
                build_data_dir : Build.DATADIR,
                build_pkg_data_dir : Build.PKGDATADIR,
                build_release_name : Build.RELEASE_NAME,
                build_version : Build.VERSION,
                build_version_info : Build.VERSION_INFO,

                program_name : "Wayplank",
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
        print ("  -r, --reload              Reload and refresh running dock instance\n");
        print ("  -d, --debug               Enable debug logging\n");
        print ("  -V, --verbose             Enable verbose logging\n");
        print ("  -n, --name=NAME           The name of this dock. Defaults to \"dock1\"\n\n");
    }

    static void print_shortcuts_cheatsheet ()
    {
        print ("\n=======================================================\n");
        print ("  Wayplank — Shortcuts, Mouse Controls & Gestures Guide\n");
        print ("=======================================================\n\n");
        print ("MOUSE ACTIONS ON ICONS:\n");
        print ("  Left Click                    Launch application, or activate/minimize/cycle open windows\n");
        print ("  Middle Click (or Ctrl+Left)   Force launch a NEW instance of the application\n");
        print ("  Right Click                   Open application context menu (Desktop Actions, Keep in Dock)\n\n");
        print ("DYNAMIC ZOOM & RESIZE:\n");
        print ("  Ctrl + Mouse Scroll Up        Increase dock icon size dynamically in real-time\n");
        print ("  Ctrl + Mouse Scroll Down      Decrease dock icon size dynamically in real-time\n\n");
        print ("DRAG & DROP GESTURES:\n");
        print ("  Drag icon off dock            Unpin / remove launcher from dock (with smoke animation)\n");
        print ("  Drag icon along dock          Reorder pinned application icons\n");
        print ("  Drop file on app icon         Open the dropped file directly with that application\n");
        print ("  Drop .desktop / folder        Pin a new application or folder to the dock\n\n");
        print ("DOCK CONTROLS & DEVELOPER TOOLS:\n");
        print ("  Ctrl + Right Click            Open dock preferences menu directly, even over an icon\n");
        print ("  Right Click on separator      Open dock preferences menu\n");
        print ("  Ctrl+Alt+Shift + Right Click  Open Developer Tools submenu (inspect launcher, config, theme)\n\n");
    }
}
