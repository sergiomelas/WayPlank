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
	public class EjectorDockItem : DockItem
	{
		const string ICON_NAMES = "media-eject;;drive-removable-media;;media-eject-symbolic";

		private ulong drives_changed_id = 0;

		public EjectorDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public EjectorDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Removable Drives");
			Icon = ICON_NAMES;
			Button = PopupButton.RIGHT;

			drives_changed_id = Hal.Telemetry.Ejector.drives_changed.connect (on_storage_changed);
			update_ejector_status ();
		}

		private void stop_monitoring ()
		{
			if (drives_changed_id != 0) {
				Hal.Telemetry.Ejector.disconnect (drives_changed_id);
				drives_changed_id = 0;
			}
		}

		~EjectorDockItem ()
		{
			stop_monitoring ();
		}

		public override void cleanup ()
		{
			stop_monitoring ();
			base.cleanup ();
		}

		public override void @delete ()
		{
			stop_monitoring ();
			base.@delete ();
		}

		public override bool is_valid ()
		{
			return true;
		}

		private void on_storage_changed ()
		{
			update_ejector_status ();
		}

		public Gee.ArrayList<RemovableDriveInfo> get_removable_drives ()
		{
			return Hal.Telemetry.Ejector.get_removable_drives ();
		}

		public void update_ejector_status ()
		{
			var drives = get_removable_drives ();
			uint count = (uint) drives.size;

			if (count > 0) {
				Count = count;
				CountVisible = true;
				Text = _("Removable Drives (%u mounted)").printf (count);
			} else {
				Count = 0;
				CountVisible = false;
				Text = _("Removable Drives (None connected)");
			}

			reset_icon_buffer ();
		}

		public void eject_drive_by_id (string id)
		{
			Hal.Telemetry.Ejector.eject_drive (id, (success, drive_name, error_message) => {
				if (success) {
					notify_ejected (drive_name);
					update_ejector_status ();
				}
			});
		}

		public void eject_all ()
		{
			Hal.Telemetry.Ejector.eject_all ((success, drive_name, error_message) => {
				if (success) {
					notify_ejected (drive_name);
					update_ejector_status ();
				}
			});
		}

		private void notify_ejected (string drive_name)
		{
			Hal.Bus.Notifications.send_toast (
				_("Safe to Remove"),
				_("Device '%s' has been safely unmounted.").printf (drive_name),
				"media-eject"
			);
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				var drives = get_removable_drives ();
				if (drives.size == 1) {
					eject_drive_by_id (drives[0].id);
					return AnimationType.BOUNCE;
				} else if (drives.size > 1) {
					var menu = new Gtk.Menu ();
					foreach (var d in drives) {
						string target_id = d.id;
						var item = new Gtk.MenuItem.with_label (_("Eject '%s'").printf (d.display_name));
						item.activate.connect (() => eject_drive_by_id (target_id));
						menu.append (item);
					}
					var sep = new Gtk.SeparatorMenuItem ();
					menu.append (sep);
					var item_all = new Gtk.MenuItem.with_label (_("Eject All Devices"));
					item_all.activate.connect (() => eject_all ());
					menu.append (item_all);

					menu.show_all ();
					menu.popup_at_pointer (null);
					return AnimationType.BOUNCE;
				} else {
					notify_no_devices ();
					return AnimationType.NONE;
				}
			}

			return AnimationType.NONE;
		}

		private void notify_no_devices ()
		{
			Hal.Bus.Notifications.send_toast (
				"WayPlank",
				_("No removable devices connected"),
				"drive-removable-media"
			);
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			var drives = get_removable_drives ();

			if (drives.size > 0) {
				foreach (var d in drives) {
					string target_id = d.id;
					var eject_item = create_literal_menu_item (_("Eject '%s'").printf (d.display_name), "media-eject", true);
					eject_item.activate.connect (() => eject_drive_by_id (target_id));
					items.add (eject_item);
				}

				if (drives.size > 1) {
					var eject_all_item = create_literal_menu_item (_("Eject All Devices"), "media-eject", true);
					eject_all_item.activate.connect (() => eject_all ());
					items.add (eject_all_item);
				}
			} else {
				var empty_item = create_literal_menu_item (_("No Removable Devices"), "drive-removable-media", false);
				empty_item.set_sensitive (false);
				items.add (empty_item);
			}

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
