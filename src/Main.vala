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
}
