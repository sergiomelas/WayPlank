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
	/**
	 * A dock item for the dock itself.  Has things like about, help, quit etc.
	 */
	struct DockletMenuEntry {
		public string label;
		public string uri;
	}

	public class PlankDockItem : DockItem
	{
		public PlankDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences (), Text: "WayPlank", Icon: "wayplank;;plank");
		}
		
		construct
		{
			// if plank is pinned indicate that it is running while it isnt user-visible
			Indicator = IndicatorState.SINGLE;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override bool can_be_removed ()
		{
			return false;
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (AbstractMain.app_instance != null)
				AbstractMain.app_instance.open_preferences_for_dock (get_dock ());
			else
				Application.get_default ().activate_action ("preferences", null);
			
			return AnimationType.DARKEN;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			unowned DockController? controller = get_dock ();
			var ctrl_ref = GLib.WeakRef (controller);
			
			var item = create_menu_item (_("Report a _Bug Online..."), "tools-report-bug");
			item.activate.connect (() => Application.get_default ().activate_action ("help", null));
			items.add (item);

			item = create_menu_item (_("_Shortcuts & Gestures..."), "help-browser");
			item.activate.connect (() => Application.get_default ().activate_action ("shortcuts", null));
			items.add (item);

			items.add (new Gtk.SeparatorMenuItem ());
			
			var docklets_item = PreferencesDockItem.create_docklets_submenu_item (controller);
			if (docklets_item != null) {
				items.add (docklets_item);
			}

			var add_folder_item = create_menu_item (_("Add _Folder..."), "folder-new", true);
			add_folder_item.sensitive = (controller != null && !controller.prefs.LockItems);
			add_folder_item.activate.connect (() => {
				DockFolderDialogs.show_add_folder_dialog (ctrl_ref.get () as DockController);
			});
			items.add (add_folder_item);

			var new_dock_item = create_menu_item (_("Open _Dock..."), "list-add", true);
			new_dock_item.sensitive = (AbstractMain.app_instance != null && AbstractMain.app_instance.get_dock_count () < DockPreferences.MAX_DOCK_SLOTS);
			new_dock_item.activate.connect (() => {
				DockFolderDialogs.show_new_dock_dialog (ctrl_ref.get () as DockController);
			});
			items.add (new_dock_item);

			items.add (new Gtk.SeparatorMenuItem ());
			
			item = create_menu_item (_("_Preferences"), "preferences-system", true);
			item.activate.connect (() => {
				if (AbstractMain.app_instance != null)
					AbstractMain.app_instance.open_preferences_for_dock (ctrl_ref.get () as DockController);
				else
					Application.get_default ().activate_action ("preferences", null);
			});
			items.add (item);

			item = create_menu_item (_("User Guide..."), "help-browser", true);
			item.activate.connect (() => Application.get_default ().activate_action ("guide", null));
			items.add (item);
			
			item = create_menu_item (_("_About"), "help-about", true);
			item.activate.connect (() => Application.get_default ().activate_action ("about", null));
			items.add (item);
			
			if (controller != null && controller.name != "dock1") {
				items.add (new Gtk.SeparatorMenuItem ());
				item = create_menu_item (_("_Close This Dock"), "window-close", true);
				item.activate.connect (() => {
					var target = ctrl_ref.get () as DockController;
					if (AbstractMain.app_instance != null && target != null)
						AbstractMain.app_instance.close_dock (target);
				});
				items.add (item);
			}

			// No explicit quit-item when session disallowing quit (e.g. Pantheon)
			if (Hal.Capabilities.supports_quit_action) {
				items.add (new Gtk.SeparatorMenuItem ());
			
				item = create_menu_item (_("_Quit"), "application-exit", true);
				item.activate.connect (() => Application.get_default ().activate_action ("quit", null));
				items.add (item);
			}
			
			return items;
		}
	}
}
