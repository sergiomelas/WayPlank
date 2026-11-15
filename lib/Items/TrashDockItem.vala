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
	public class TrashDockItem : DockItem
	{
		const string ICON_EMPTY = "trashcan_empty;;user-trash;;emptytrash;;gnome-fs-trash-empty";
		const string ICON_FULL = "trashcan_full;;user-trash-full;;trashcan_full-new;;gnome-fs-trash-full";

		uint trash_count = 0;
		ulong trash_changed_id = 0;

		public TrashDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public TrashDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Trash");
			Icon = ICON_EMPTY;
			Button = PopupButton.RIGHT;

			trash_changed_id = Hal.Telemetry.Trash.trash_changed.connect (update_trash_state);
			update_trash_state ();
		}

		~TrashDockItem ()
		{
			stop_monitor ();
		}

		public override void cleanup ()
		{
			stop_monitor ();
			base.cleanup ();
		}

		void stop_monitor ()
		{
			if (trash_changed_id != 0) {
				Hal.Telemetry.Trash.disconnect (trash_changed_id);
				trash_changed_id = 0;
			}
		}

		public override bool is_valid ()
		{
			return true;
		}

		public override void @delete ()
		{
			stop_monitor ();
			base.@delete ();
		}

		void update_trash_state ()
		{
			trash_count = Hal.Telemetry.Trash.get_item_count ();

			if (trash_count == 0) {
				Icon = ICON_EMPTY;
				Text = _("Trash (Empty)");
			} else if (trash_count == 1) {
				Icon = ICON_FULL;
				Text = _("Trash (1 item)");
			} else {
				Icon = ICON_FULL;
				Text = _("Trash (%u items)").printf (trash_count);
			}

			reset_icon_buffer ();
		}

		void open_trash ()
		{
			Hal.Telemetry.Trash.open_trash_ui ();
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				open_trash ();
				return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public override bool can_accept_drop (Gee.ArrayList<string> uris)
		{
			return uris != null && uris.size > 0;
		}

		public override bool accept_drop (Gee.ArrayList<string> uris)
		{
			if (uris == null || uris.size == 0)
				return false;

			bool any_trashed = false;
			foreach (var uri in uris) {
				if (Hal.Telemetry.Trash.move_uri_to_trash (uri))
					any_trashed = true;
			}

			if (any_trashed) {
				update_trash_state ();
				ClickedAnimation = AnimationType.BOUNCE;
				LastClicked = GLib.get_monotonic_time ();
			}

			return any_trashed;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var open_item = create_menu_item (_("_Open Trash"), "document-open", true);
			open_item.activate.connect (open_trash);
			items.add (open_item);

			var empty_item = create_menu_item (_("_Empty Trash"), "edit-clear", true);
			empty_item.sensitive = (trash_count > 0);
			empty_item.activate.connect (empty_trash);
			items.add (empty_item);

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

		void empty_trash ()
		{
			Hal.Telemetry.Trash.empty_trash ();
			update_trash_state ();
			ClickedAnimation = AnimationType.BOUNCE;
			LastClicked = GLib.get_monotonic_time ();
		}
	}
}
