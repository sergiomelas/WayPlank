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
	public class PreferencesDockItem : DockItem
	{
		const string ICON_NAMES = "plank;;wayplank;;preferences-other;;configure;;preferences-system";

		public PreferencesDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public PreferencesDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Preferences");
			Icon = ICON_NAMES;
			Button = PopupButton.RIGHT;
		}

		public override bool is_valid ()
		{
			return true;
		}

		public void open_preferences ()
		{
			Application.get_default ().activate_action ("preferences", null);
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				open_preferences ();
				return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var appearance_item = create_menu_item (_("_Appearance..."), "preferences-desktop-theme", true);
			appearance_item.activate.connect (() => Application.get_default ().activate_action ("preferences-appearance", null));
			items.add (appearance_item);

			var behaviour_item = create_menu_item (_("_Behaviour..."), "preferences-desktop", true);
			behaviour_item.activate.connect (() => Application.get_default ().activate_action ("preferences-behaviour", null));
			items.add (behaviour_item);

			var apps_item = create_menu_item (_("A_pplications..."), "applications-other", true);
			apps_item.activate.connect (() => Application.get_default ().activate_action ("preferences-applications", null));
			items.add (apps_item);

			var docklets_item = create_menu_item (_("_Docklets..."), "preferences-plugin", true);
			docklets_item.activate.connect (() => Application.get_default ().activate_action ("preferences-docklets", null));
			items.add (docklets_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var shortcuts_item = create_menu_item (_("_Shortcuts & Gestures..."), "help-browser", true);
			shortcuts_item.activate.connect (() => Application.get_default ().activate_action ("shortcuts", null));
			items.add (shortcuts_item);

			var bug_item = create_menu_item (_("Report a _Bug Online..."), "tools-report-bug", true);
			bug_item.activate.connect (() => Application.get_default ().activate_action ("help", null));
			items.add (bug_item);

			var about_item = create_menu_item (_("_About Wayplank..."), "help-about", true);
			about_item.activate.connect (() => Application.get_default ().activate_action ("about", null));
			items.add (about_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
			remove_item.activate.connect (() => {
				this.@delete ();
			});
			items.add (remove_item);

			return items;
		}
	}
}
