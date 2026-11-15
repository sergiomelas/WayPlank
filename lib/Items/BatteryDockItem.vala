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
	public class BatteryDockItem : DockItem
	{
		uint timer_id = 0;
		int percentage = 100;
		bool is_charging = false;
		bool is_full = false;
		bool has_bat = false;
		string status_desc = "Unknown";

		public BatteryDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public BatteryDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Battery");
			Icon = "battery-full";
			Button = PopupButton.RIGHT;

			refresh_battery_status ();
			notify["IsAttached"].connect (on_attached_changed);
			if (has_bat)
				start_timer ();
		}

		~BatteryDockItem ()
		{
			notify["IsAttached"].disconnect (on_attached_changed);
			stop_timer ();
		}

		public override void cleanup ()
		{
			notify["IsAttached"].disconnect (on_attached_changed);
			stop_timer ();
			base.cleanup ();
		}

		void on_attached_changed ()
		{
			if (IsAttached && has_bat)
				refresh_battery_status ();
		}

		void start_timer ()
		{
			if (timer_id != 0)
				return;

			timer_id = Timeout.add_seconds (3, on_timer_tick);
		}

		void stop_timer ()
		{
			if (timer_id != 0) {
				Source.remove (timer_id);
				timer_id = 0;
			}
		}

		public override bool is_valid ()
		{
			return true;
		}

		public override void @delete ()
		{
			stop_timer ();
			base.@delete ();
		}

		void refresh_battery_status ()
		{
			var st = Hal.Telemetry.Battery.query_state ();
			has_bat = st.has_battery;

			if (has_bat) {
				percentage = st.percentage;
				is_charging = st.is_charging;
				is_full = st.is_full;
				string s = st.raw_status;
				if (s == "Discharging")
					status_desc = _("Discharging");
				else if (s == "Not charging")
					status_desc = _("Not charging");
				else if (s == "Unknown" || s == "")
					status_desc = _("Unknown");
				else
					status_desc = s;
			} else {
				percentage = 100;
				is_charging = false;
				is_full = true;
				status_desc = _("AC Power");
			}

			if (is_charging) {
				Text = _("Battery: %d%% (Charging)").printf (percentage);
			} else if (is_full) {
				Text = _("Battery: %d%% (Full)").printf (percentage);
			} else {
				Text = _("Battery: %d%% (%s)").printf (percentage, status_desc);
			}

			if (!has_bat) {
				Icon = "battery-ac-adapter;;battery-missing";
			} else if (is_charging) {
				if (percentage < 20)
					Icon = "battery-caution-charging;;battery-empty-charging";
				else if (percentage < 50)
					Icon = "battery-low-charging;;battery-good-charging";
				else if (percentage < 85)
					Icon = "battery-good-charging";
				else
					Icon = "battery-full-charging;;battery-full-charged";
			} else {
				if (percentage < 15)
					Icon = "battery-empty;;battery-caution";
				else if (percentage < 35)
					Icon = "battery-caution";
				else if (percentage < 65)
					Icon = "battery-low";
				else if (percentage < 90)
					Icon = "battery-good";
				else
					Icon = "battery-full";
			}

			Count = has_bat ? 1 : 0;
			BadgeText = has_bat ? "%d%%".printf (percentage) : null;
			CountVisible = has_bat;
		}

		bool on_timer_tick ()
		{
			if (!IsAttached)
				return true;
			refresh_battery_status ();
			return true;
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				if (Hal.Runtime.open_system_utility (DesktopUtilityKind.POWER_SETTINGS))
					return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var status_item = new Gtk.MenuItem.with_label (Text);
			status_item.sensitive = false;
			items.add (status_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var settings_item = create_menu_item (_("_Power Settings..."), "preferences-system-power", true);
			settings_item.activate.connect (() => {
				on_clicked (PopupButton.LEFT, 0, 0);
			});
			items.add (settings_item);

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
