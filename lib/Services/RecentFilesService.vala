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
	 * On-demand OS-blind recent-documents jump-list builder backed by Hal.Apps.
	 * Queries platform recent documents solely when a context menu is opened
	 * (zero background timers or polling).
	 */
	public class RecentFilesService : GLib.Object
	{
		public const int MAX_RECENT_ITEMS = 10;

		public delegate void ItemActivatedFunc ();

		public static Gtk.MenuItem? build_submenu_item (string launcher_uri, owned ItemActivatedFunc? on_activated = null)
		{
			if (launcher_uri == null || launcher_uri == "" || launcher_uri.has_prefix ("docklet://"))
				return null;

			var docs = Hal.Apps.get_recent_documents (launcher_uri, MAX_RECENT_ITEMS);
			if (docs.size == 0)
				return null;

			var root_item = DockElement.create_menu_item (_("Recent Files"), "document-open-recent", true);
			var submenu = new Gtk.Menu ();
			root_item.set_submenu (submenu);

			foreach (var c in docs) {
				string short_name = c.display_name;
				if (short_name.char_count () > 52)
					short_name = short_name.substring (0, short_name.index_of_nth_char (49)) + "…";

				string icon_str = (c.icon_token != "") ? c.icon_token : "text-x-generic";
				var sub_item = DockElement.create_literal_menu_item (short_name, icon_str, true);
				if (c.tooltip_path != "")
					sub_item.set_tooltip_text (c.tooltip_path);

				string target_uri = c.uri;
				string captured_launcher = launcher_uri;
				sub_item.activate.connect (() => {
					bool launched = Hal.Apps.launch_app (captured_launcher, { target_uri });
					if (!launched)
						System.get_default ().open_uri (target_uri);
					if (on_activated != null)
						on_activated ();
				});
				submenu.append (sub_item);
			}

			submenu.show_all ();
			return root_item;
		}
	}
}
