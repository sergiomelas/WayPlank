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
	/**
	 * A dock item for the dock itself.  Has things like about, help, quit etc.
	 */
	struct DockletMenuEntry {
		public string label;
		public string uri;
	}

	public class PlankDockItem : DockItem
	{
		static PlankDockItem? instance;
		
		public static unowned PlankDockItem get_instance ()
		{
			if (instance == null)
				instance = new PlankDockItem ();
			
			return instance;
		}
		
		PlankDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences (), Text: "Plank", Icon: "plank");
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
			Application.get_default ().activate_action ("preferences", null);
			
			return AnimationType.DARKEN;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			
			var item = create_menu_item (_("Report a _Bug Online..."), "tools-report-bug");
			item.activate.connect (() => Application.get_default ().activate_action ("help", null));
			items.add (item);

			item = create_menu_item (_("_Shortcuts & Gestures..."), "help-browser");
			item.activate.connect (() => Application.get_default ().activate_action ("shortcuts", null));
			items.add (item);

			items.add (new Gtk.SeparatorMenuItem ());
			
			unowned DockController? controller = get_dock ();
			if (controller != null) {
				unowned DefaultApplicationDockItemProvider? default_provider = controller.default_provider as DefaultApplicationDockItemProvider;
				if (default_provider != null) {
					var docklets_item = create_menu_item (_("_Docklets"), "system-run", true);
					var docklets_menu = new Gtk.Menu ();
					DockletMenuEntry[] docklets = {
						{ _("_Trash"), "docklet://trash" },
						{ _("_Analog Clock"), "docklet://clock" },
						{ _("_Digital Clock"), "docklet://digital-clock" },
						{ _("_Battery"), "docklet://battery" },
						{ _("_CPU / RAM Monitor"), "docklet://cpu" },
						{ _("_Show Desktop"), "docklet://desktop" },
						{ _("_Media Player"), "docklet://mpris" },
						{ _("_Volume Control"), "docklet://volume" },
						{ _("_Screenshot"), "docklet://screenshot" },
						{ _("_Session / Power"), "docklet://session" },
						{ _("_Preferences"), "docklet://preferences" }
					};
					foreach (var d in docklets) {
						var d_uri = d.uri;
						var c_item = new Gtk.CheckMenuItem.with_mnemonic (d.label);
						c_item.active = (default_provider.item_for_uri (d_uri) != null);
						c_item.toggled.connect (() => {
							if (c_item.active) {
								if (default_provider.item_for_uri (d_uri) == null)
									default_provider.add_item_with_uri (d_uri);
							} else {
								unowned DockItem? di = default_provider.item_for_uri (d_uri);
								if (di != null)
									di.delete ();
							}
						});
						docklets_menu.add (c_item);
					}
					
					docklets_menu.show_all ();
					docklets_item.set_submenu (docklets_menu);
					items.add (docklets_item);
					items.add (new Gtk.SeparatorMenuItem ());
				}
			}
			
			item = create_menu_item (_("_Preferences"), "preferences-system", true);
			item.activate.connect (() => Application.get_default ().activate_action ("preferences", null));
			items.add (item);

			item = create_menu_item (_("Wayland Migration Report..."), "text-x-generic", true);
			item.activate.connect (() => Application.get_default ().activate_action ("report", null));
			items.add (item);
			
			item = create_menu_item (_("_About"), "help-about", true);
			item.activate.connect (() => Application.get_default ().activate_action ("about", null));
			items.add (item);
			
			// No explicit quit-item on elementary OS
			if (!environment_is_session_desktop (XdgSessionDesktop.PANTHEON)) {
				items.add (new Gtk.SeparatorMenuItem ());
			
				item = create_menu_item (_("_Quit"), "application-exit", true);
				item.activate.connect (() => Application.get_default ().activate_action ("quit", null));
				items.add (item);
			}
			
			return items;
		}
	}
}
