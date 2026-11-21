//
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
	/**
	 * Southbound XDG autostart entry manager (`~/.config/autostart/wayplank.desktop`),
	 * preserving KDE restricted D-Bus screenshot whitelists and compositor autostart sync.
	 */
	public class XdgAutostart : GLib.Object
	{
		static string get_autostart_path (out string autostart_dir)
		{
			autostart_dir = Path.build_filename (Environment.get_user_config_dir (), "autostart");
			return Path.build_filename (autostart_dir, "wayplank.desktop");
		}

		public static bool is_enabled ()
		{
			string autostart_dir;
			var autostart_path = get_autostart_path (out autostart_dir);
			return FileUtils.test (autostart_path, FileTest.IS_REGULAR);
		}

		public static bool set_enabled (bool enabled)
		{
			string autostart_dir;
			var autostart_path = get_autostart_path (out autostart_dir);
			var success = true;

			if (enabled) {
				if (DirUtils.create_with_parents (autostart_dir, 0755) != 0) {
					warning ("Unable to create autostart directory '%s'", autostart_dir);
					success = false;
				} else {
					try {
						FileUtils.set_contents (autostart_path,
							"[Desktop Entry]\n" +
							"Type=Application\n" +
							"Name=WayPlank\n" +
							"Comment=Stupidly simple dock for Wayland\n" +
							"Exec=wayplank\n" +
							"Icon=plank\n" +
							"Terminal=false\n" +
							"X-GNOME-Autostart-enabled=true\n" +
							"X-GNOME-Autostart-Delay=2\n" +
							"X-KDE-DBUS-Restricted-Interfaces=org.kde.kwin.Screenshot,org.kde.KWin.ScreenShot2\n");
					} catch (FileError e) {
						warning ("Unable to create autostart entry '%s': %s", autostart_path, e.message);
						success = false;
					}
				}
			} else if (FileUtils.test (autostart_path, FileTest.EXISTS) && FileUtils.remove (autostart_path) != 0) {
				warning ("Unable to remove autostart entry '%s'", autostart_path);
				success = false;
			}

			if (success)
				WindowControl.sync_autostart (enabled);

			return success;
		}
	}
}
