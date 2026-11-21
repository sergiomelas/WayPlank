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
	 * Southbound Wayland / Freedesktop screen, window, and region capture provider (`IScreenshotProvider`).
	 */
	public class FreedesktopScreenshotProvider : GLib.Object, IScreenshotProvider
	{
		static FreedesktopScreenshotProvider? default_instance = null;

		public static FreedesktopScreenshotProvider get_default ()
		{
			if (default_instance == null)
				default_instance = new FreedesktopScreenshotProvider ();
			return default_instance;
		}

		static bool is_kde_session ()
		{
			var desktop = GLib.Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
			return desktop.down ().contains ("kde") || desktop.down ().contains ("plasma");
		}

		static bool is_gnome_session ()
		{
			var desktop = GLib.Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
			return desktop.down ().contains ("gnome") || desktop.down ().contains ("ubuntu");
		}

		static string build_default_screenshot_path ()
		{
			var base_dir = Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir ();
			var screenshots_dir = Path.build_filename (base_dir, "Screenshots");
			DirUtils.create_with_parents (screenshots_dir, 0755);
			string dir_to_use = FileUtils.test (screenshots_dir, FileTest.IS_DIR) ? screenshots_dir : base_dir;
			var time_str = new DateTime.now_local ().format ("%Y-%m-%d_%H-%M-%S");
			return Path.build_filename (dir_to_use, "Screenshot_%s.png".printf (time_str));
		}

		static bool invoke_gnome_bridge_screenshot (string mode, string filepath = "")
		{
			try {
				var bus = DbusBroker.get_default ().get_session_bus ();
				if (bus == null)
					return false;
				var reply = bus.call_sync (
					"org.wayplank.GnomeBridge",
					"/org/wayplank/GnomeBridge",
					"org.wayplank.GnomeBridge",
					"TakeScreenshot",
					new Variant ("(ss)", mode, filepath),
					new VariantType ("(b)"),
					DBusCallFlags.NO_AUTO_START,
					4000,
					null
				);
				bool ok = false;
				reply.get ("(b)", out ok);
				if (ok && filepath != "" && FileUtils.test (filepath, FileTest.IS_REGULAR)) {
					NotificationDbusService.get_default ().send_toast (_("Screenshot"), filepath, "applets-screenshooter");
				}
				return ok;
			} catch (Error e) {
				debug ("GnomeBridge.TakeScreenshot unavailable (%s): %s", mode, e.message);
				return false;
			}
		}

		static bool invoke_portal_screenshot (bool interactive)
		{
			try {
				var bus = DbusBroker.get_default ().get_session_bus ();
				if (bus == null)
					return false;
				var builder = new VariantBuilder (new VariantType ("a{sv}"));
				builder.add ("{sv}", "interactive", new Variant.boolean (interactive));
				bus.call_sync ("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
					"org.freedesktop.portal.Screenshot", "Screenshot",
					new Variant ("(sa{sv})", "", builder),
					null, DBusCallFlags.NONE, 2000, null);
				return true;
			} catch (Error e) {
				warning ("Failed to invoke XDG screenshot portal: %s", e.message);
				return false;
			}
		}

		public void capture_interactive_region ()
		{
			if (is_gnome_session ()) {
				if (invoke_gnome_bridge_screenshot ("interactive"))
					return;
				if (Environment.find_program_in_path ("gnome-screenshot") != null) {
					try {
						Process.spawn_command_line_async ("gnome-screenshot -a");
						return;
					} catch (Error e) {
						warning ("Failed to launch gnome-screenshot: %s", e.message);
					}
				}
				if (invoke_portal_screenshot (true))
					return;
			}

			if (is_kde_session () && Environment.find_program_in_path ("spectacle") != null) {
				try {
					Process.spawn_command_line_async ("spectacle -r");
					return;
				} catch (Error e) {
					warning ("Failed to launch spectacle: %s", e.message);
				}
			}

			if (Environment.find_program_in_path ("grim") != null && Environment.find_program_in_path ("slurp") != null) {
				var pic_dir = Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir ();
				var time_str = new DateTime.now_local ().format ("%Y-%m-%d_%H-%M-%S");
				var target = Path.build_filename (pic_dir, "Screenshot_%s.png".printf (time_str));
				try {
					Process.spawn_command_line_async ("sh -c 'grim -g \"$(slurp)\" \"$1\"' sh %s".printf (Shell.quote (target)));
					return;
				} catch (Error e) {
					warning ("Failed to launch grim/slurp: %s", e.message);
				}
			}

			if (Environment.find_program_in_path ("flameshot") != null) {
				try {
					Process.spawn_command_line_async ("flameshot gui");
					return;
				} catch (Error e) {
					warning ("Failed to launch flameshot: %s", e.message);
				}
			}

			invoke_portal_screenshot (true);
		}

		public void capture_full_screen ()
		{
			if (is_gnome_session ()) {
				if (invoke_gnome_bridge_screenshot ("fullscreen", build_default_screenshot_path ()))
					return;
				if (Environment.find_program_in_path ("gnome-screenshot") != null) {
					try {
						Process.spawn_command_line_async ("gnome-screenshot");
						return;
					} catch (Error e) { }
				}
				if (invoke_portal_screenshot (false))
					return;
			}

			if (is_kde_session () && Environment.find_program_in_path ("spectacle") != null) {
				try {
					Process.spawn_command_line_async ("spectacle -f");
					return;
				} catch (Error e) {
					warning ("Failed to launch spectacle: %s", e.message);
				}
			}

			if (Environment.find_program_in_path ("grim") != null) {
				var pic_dir = Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir ();
				var time_str = new DateTime.now_local ().format ("%Y-%m-%d_%H-%M-%S");
				var target = Path.build_filename (pic_dir, "Screenshot_%s.png".printf (time_str));
				try {
					Process.spawn_command_line_async ("grim %s".printf (Shell.quote (target)));
					return;
				} catch (Error e) {
					warning ("Failed to launch grim: %s", e.message);
				}
			}

			if (Environment.find_program_in_path ("flameshot") != null) {
				try {
					Process.spawn_command_line_async ("flameshot full");
					return;
				} catch (Error e) {
					warning ("Failed to launch flameshot: %s", e.message);
				}
			}

			invoke_portal_screenshot (false);
		}

		public void capture_active_window ()
		{
			if (is_gnome_session ()) {
				if (invoke_gnome_bridge_screenshot ("window", build_default_screenshot_path ()))
					return;
				if (Environment.find_program_in_path ("gnome-screenshot") != null) {
					try {
						Process.spawn_command_line_async ("gnome-screenshot -w");
						return;
					} catch (Error e) { }
				}
				capture_interactive_region ();
				return;
			}

			if (is_kde_session () && Environment.find_program_in_path ("spectacle") != null) {
				try {
					Process.spawn_command_line_async ("spectacle -a");
					return;
				} catch (Error e) {
					warning ("Failed to launch spectacle: %s", e.message);
				}
			}

			capture_interactive_region ();
		}

		public void open_screenshots_folder ()
		{
			string target_path = Environment.get_home_dir ();
			var pic_dir = Environment.get_user_special_dir (UserDirectory.PICTURES);
			if (pic_dir != null) {
				var screenshots_dir = Path.build_filename (pic_dir, "Screenshots");
				if (FileUtils.test (screenshots_dir, FileTest.IS_DIR))
					target_path = screenshots_dir;
				else
					target_path = pic_dir;
			}

			try {
				if (Gtk.show_uri_on_window (null, Filename.to_uri (target_path), Gdk.CURRENT_TIME))
					return;
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("xdg-open %s".printf (Shell.quote (target_path)));
			} catch (Error e) {
				warning ("Failed to open screenshots folder: %s", e.message);
			}
		}
	}
}
