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

		public override bool can_be_removed ()
		{
			return true;
		}

		public override void delete ()
		{
			unowned DockController? dock = get_dock ();
			if (dock != null && dock.prefs.SystemMenuAccess == 4) {
				dock.prefs.SystemMenuAccess = 2;
			}
			base.delete ();
		}

		public void open_preferences ()
		{
			Application.get_default ().activate_action ("preferences", null);
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				unowned DockController? dock = get_dock ();
				if (dock != null && dock.prefs.CategorizeItems && dock.prefs.AccordionDocklets && dock.prefs.AccordionClickToExpand) {
					unowned DefaultApplicationDockItemProvider? app_prov = dock.default_provider as DefaultApplicationDockItemProvider;
					if (app_prov != null && !app_prov.docklets_expanded && app_prov.get_docklet_count () > 1) {
						app_prov.expand_docklets ();
						return AnimationType.BOUNCE;
					}
				}
				open_preferences ();
				return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public static void append_full_system_menu (DockController? controller, Gee.ArrayList<Gtk.MenuItem> items)
		{
			items.add (new Gtk.SeparatorMenuItem ());

			if (controller != null) {
				unowned DefaultApplicationDockItemProvider? default_provider = controller.default_provider as DefaultApplicationDockItemProvider;
				if (default_provider != null) {
					var docklets_item = DockElement.create_menu_item (_("_Docklets"), "system-run", true);
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
						{ _("_Screen Brightness"), "docklet://brightness" },
						{ _("_Removable Drives"), "docklet://ejector" },
						{ _("_Weather Forecast"), "docklet://weather" },
						{ _("_Network / Wi-Fi"), "docklet://network" },
						{ _("_Do Not Disturb"), "docklet://dnd" }
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

			var pref_item = DockElement.create_menu_item (_("_Preferences..."), "preferences-system", true);
			pref_item.activate.connect (() => Application.get_default ().activate_action ("preferences", null));
			items.add (pref_item);

			var appearance_item = DockElement.create_menu_item (_("_Appearance..."), "preferences-desktop-theme", true);
			appearance_item.activate.connect (() => Application.get_default ().activate_action ("preferences-appearance", null));
			items.add (appearance_item);

			var behaviour_item = DockElement.create_menu_item (_("_Behaviour..."), "preferences-desktop", true);
			behaviour_item.activate.connect (() => Application.get_default ().activate_action ("preferences-behaviour", null));
			items.add (behaviour_item);

			var apps_item = DockElement.create_menu_item (_("A_pplications..."), "applications-other", true);
			apps_item.activate.connect (() => Application.get_default ().activate_action ("preferences-applications", null));
			items.add (apps_item);

			var docklets_tab_item = DockElement.create_menu_item (_("_Docklets..."), "preferences-plugin", true);
			docklets_tab_item.activate.connect (() => Application.get_default ().activate_action ("preferences-docklets", null));
			items.add (docklets_tab_item);

			var shortcuts_item = DockElement.create_menu_item (_("_Shortcuts & Gestures..."), "help-browser");
			shortcuts_item.activate.connect (() => Application.get_default ().activate_action ("shortcuts", null));
			items.add (shortcuts_item);

			var guide_item = DockElement.create_menu_item (_("User Guide..."), "help-browser", true);
			guide_item.activate.connect (() => Application.get_default ().activate_action ("guide", null));
			items.add (guide_item);

			var report_item = DockElement.create_menu_item (_("Report a _Bug Online..."), "tools-report-bug");
			report_item.activate.connect (() => Application.get_default ().activate_action ("help", null));
			items.add (report_item);

			var about_item = DockElement.create_menu_item (_("_About"), "help-about", true);
			about_item.activate.connect (() => Application.get_default ().activate_action ("about", null));
			items.add (about_item);

			if (!environment_is_session_desktop (XdgSessionDesktop.PANTHEON)) {
				items.add (new Gtk.SeparatorMenuItem ());

				var quit_item = DockElement.create_menu_item (_("_Quit"), "application-exit", true);
				quit_item.activate.connect (() => Application.get_default ().activate_action ("quit", null));
				items.add (quit_item);
			}
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			append_full_system_menu (get_dock (), items);
			return items;
		}
	}
}
