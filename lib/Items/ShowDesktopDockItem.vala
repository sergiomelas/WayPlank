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
	public class ShowDesktopDockItem : DockItem
	{
		const string ICON_NAMES = "user-desktop;;desktop;;user-home;;computer";
		
		public ShowDesktopDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		public ShowDesktopDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			Text = _("Show Desktop");
			Icon = ICON_NAMES;
			Button = PopupButton.RIGHT;
		}
		
		public override bool is_valid ()
		{
			return true;
		}
		
		public void toggle_desktop ()
		{
			// Neutral compositor command via WindowControl (bidirectional minimize / restore toggle)
			WindowControl.queue_command ("desktop", "toggle_desktop");
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				toggle_desktop ();
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}
		
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			
			var toggle_item = create_menu_item (_("_Show / Hide Desktop"), "user-desktop", true);
			toggle_item.activate.connect (toggle_desktop);
			items.add (toggle_item);
			
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
