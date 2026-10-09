//
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
	public class ScreenshotDockItem : DockItem
	{
		const string ICON_NAMES = "applets-screenshooter;;accessories-screenshot-tool;;spectacle;;org.kde.spectacle;;camera-photo;;screengrab";
		
		public ScreenshotDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		public ScreenshotDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			Text = _("Screenshot");
			Icon = ICON_NAMES;
			Button = PopupButton.RIGHT;
		}
		
		public override bool is_valid ()
		{
			return true;
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

		static bool invoke_portal_screenshot (bool interactive)
		{
			try {
				var bus = Bus.get_sync (BusType.SESSION, null);
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

		public void capture_interactive ()
		{
			// 1. GNOME Session -> Native XDG Desktop Portal (Interactive UI)
			if (is_gnome_session ()) {
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

			// 2. KDE Plasma / Spectacle
			if (is_kde_session () && Environment.find_program_in_path ("spectacle") != null) {
				try {
					Process.spawn_command_line_async ("spectacle -r");
					return;
				} catch (Error e) {
					warning ("Failed to launch spectacle: %s", e.message);
				}
			}
			
			// 3. Labwc / wlroots (grim + slurp)
			if (Environment.find_program_in_path ("grim") != null && Environment.find_program_in_path ("slurp") != null) {
				var pic_dir = Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir ();
				var time_str = new DateTime.now_local ().format ("%Y-%m-%d_%H-%M-%S");
				var target = Path.build_filename (pic_dir, "Screenshot_%s.png".printf (time_str));
				try {
					Process.spawn_command_line_async ("sh -c 'grim -g \"$(slurp)\" \"%s\"'".printf (target));
					return;
				} catch (Error e) {
					warning ("Failed to launch grim/slurp: %s", e.message);
				}
			}
			
			// 4. Flameshot
			if (Environment.find_program_in_path ("flameshot") != null) {
				try {
					Process.spawn_command_line_async ("flameshot gui");
					return;
				} catch (Error e) {
					warning ("Failed to launch flameshot: %s", e.message);
				}
			}
			
			// 5. Universal Wayland Desktop Portal via D-Bus
			invoke_portal_screenshot (true);
		}
		
		public void capture_fullscreen ()
		{
			// 1. GNOME Session -> Native XDG Desktop Portal / gnome-screenshot
			if (is_gnome_session ()) {
				if (Environment.find_program_in_path ("gnome-screenshot") != null) {
					try {
						Process.spawn_command_line_async ("gnome-screenshot");
						return;
					} catch (Error e) { }
				}
				if (invoke_portal_screenshot (false))
					return;
			}

			// 2. KDE Plasma / Spectacle
			if (is_kde_session () && Environment.find_program_in_path ("spectacle") != null) {
				try {
					Process.spawn_command_line_async ("spectacle -f");
					return;
				} catch (Error e) {
					warning ("Failed to launch spectacle: %s", e.message);
				}
			}
			
			// 3. Labwc / wlroots (grim)
			if (Environment.find_program_in_path ("grim") != null) {
				var pic_dir = Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir ();
				var time_str = new DateTime.now_local ().format ("%Y-%m-%d_%H-%M-%S");
				var target = Path.build_filename (pic_dir, "Screenshot_%s.png".printf (time_str));
				try {
					Process.spawn_command_line_async ("grim \"%s\"".printf (target));
					return;
				} catch (Error e) {
					warning ("Failed to launch grim: %s", e.message);
				}
			}
			
			// 4. Flameshot
			if (Environment.find_program_in_path ("flameshot") != null) {
				try {
					Process.spawn_command_line_async ("flameshot full");
					return;
				} catch (Error e) {
					warning ("Failed to launch flameshot: %s", e.message);
				}
			}
			
			// 5. Universal Wayland Desktop Portal via D-Bus
			invoke_portal_screenshot (false);
		}
		
		public void capture_window ()
		{
			// 1. GNOME Session -> gnome-screenshot or Interactive Portal
			if (is_gnome_session ()) {
				if (Environment.find_program_in_path ("gnome-screenshot") != null) {
					try {
						Process.spawn_command_line_async ("gnome-screenshot -w");
						return;
					} catch (Error e) { }
				}
				capture_interactive ();
				return;
			}

			// 2. KDE Plasma / Spectacle
			if (is_kde_session () && Environment.find_program_in_path ("spectacle") != null) {
				try {
					Process.spawn_command_line_async ("spectacle -a");
					return;
				} catch (Error e) {
					warning ("Failed to launch spectacle: %s", e.message);
				}
			}
			
			capture_interactive ();
		}
		
		public void open_folder ()
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
				Process.spawn_command_line_async ("xdg-open \"%s\"".printf (target_path));
			} catch (Error e) {
				warning ("Failed to open screenshots folder: %s", e.message);
			}
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				capture_interactive ();
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}
		
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			
			var area_item = create_menu_item (_("Capture Area / Rectangular..."), "applets-screenshooter", true);
			area_item.activate.connect (capture_interactive);
			items.add (area_item);
			
			var full_item = create_menu_item (_("Capture Entire Screen"), "video-display", true);
			full_item.activate.connect (capture_fullscreen);
			items.add (full_item);
			
			var win_item = create_menu_item (_("Capture Active Window"), "window-new", true);
			win_item.activate.connect (capture_window);
			items.add (win_item);
			
			items.add (new Gtk.SeparatorMenuItem ());
			
			var folder_item = create_menu_item (_("Open Screenshots Folder"), "folder-pictures", true);
			folder_item.activate.connect (open_folder);
			items.add (folder_item);
			
			items.add (new Gtk.SeparatorMenuItem ());
			
			var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
			remove_item.activate.connect (() => {
				this.@delete ();
			});
			items.add (remove_item);
			
			append_dock_menu_items (items);
			return items;
		}
		
		void append_dock_menu_items (Gee.ArrayList<Gtk.MenuItem> items)
		{
			if (items.size > 0)
				items.add (new Gtk.SeparatorMenuItem ());
			var dock_item = Factory.item_factory.get_item_for_dock ();
			if (dock_item != null)
				foreach (var menu_item in dock_item.get_menu_items ())
					items.add (menu_item);
		}
	}
}

