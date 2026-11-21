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

		public void capture_interactive ()
		{
			Hal.Telemetry.Screenshot.capture_interactive_region ();
		}

		public void capture_fullscreen ()
		{
			Hal.Telemetry.Screenshot.capture_full_screen ();
		}

		public void capture_window ()
		{
			Hal.Telemetry.Screenshot.capture_active_window ();
		}

		public void open_folder ()
		{
			Hal.Telemetry.Screenshot.open_screenshots_folder ();
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				capture_interactive ();
				return AnimationType.NONE;
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

			if (!is_dock_locked ()) {
				items.add (new Gtk.SeparatorMenuItem ());

				var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
				remove_item.activate.connect (() => {
					this.@delete ();
				});
				items.add (remove_item);
			}

			return items;
		}
	}
}
