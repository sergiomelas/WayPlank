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
			start_timer ();
		}
		
		~BatteryDockItem ()
		{
			stop_timer ();
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
			// 1. Inspect /sys/class/power_supply for any battery device
			string? bat_dir_path = null;
			var ps_dir = File.new_for_path ("/sys/class/power_supply");
			try {
				var enumerator = ps_dir.enumerate_children ("standard::name", FileQueryInfoFlags.NONE, null);
				FileInfo? info = null;
				while ((info = enumerator.next_file (null)) != null) {
					var candidate = Path.build_filename ("/sys/class/power_supply", info.get_name ());
					var type_file = Path.build_filename (candidate, "type");
					string type_str;
					if (FileUtils.get_contents (type_file, out type_str) && type_str.strip () == "Battery") {
						bat_dir_path = candidate;
						break;
					}
				}
			} catch (Error e) { }

			if (bat_dir_path == null) {
				for (int i = 0; i <= 3; i++) {
					string test_path = "/sys/class/power_supply/BAT%d".printf (i);
					if (FileUtils.test (test_path, FileTest.IS_DIR)) {
						bat_dir_path = test_path;
						break;
					}
				}
			}

			if (bat_dir_path != null) {
				string cap_str, stat_str;
				try {
					if (FileUtils.get_contents (Path.build_filename (bat_dir_path, "capacity"), out cap_str)) {
						percentage = int.parse (cap_str.strip ());
						if (percentage < 0) percentage = 0;
						if (percentage > 100) percentage = 100;
					}
				} catch (Error e) { }

				try {
					if (FileUtils.get_contents (Path.build_filename (bat_dir_path, "status"), out stat_str)) {
						string s = stat_str.strip ();
						status_desc = s;
						is_charging = (s == "Charging");
						is_full = (s == "Full");
					}
				} catch (Error e) { }
			} else {
				// No battery (Desktop / VM on AC power)
				percentage = 100;
				is_charging = false;
				is_full = true;
				status_desc = "AC Power";
			}

			if (is_charging) {
				Text = _("Battery: %d%% (Charging)").printf (percentage);
			} else if (is_full) {
				Text = _("Battery: %d%% (Full)").printf (percentage);
			} else {
				Text = _("Battery: %d%% (%s)").printf (percentage, status_desc);
			}

			if (bat_dir_path == null) {
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

			Count = percentage;
			BadgeText = (bat_dir_path != null) ? "%d%%".printf (percentage) : null;
			CountVisible = (bat_dir_path != null);
		}
		
		bool on_timer_tick ()
		{
			refresh_battery_status ();
			reset_icon_buffer ();
			return true;
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				string[] commands = {
					"kcmshell6 powerdevilprofilesconfig",
					"kcmshell5 powerdevilprofilesconfig",
					"gnome-control-center power",
					"xfce4-power-manager-settings"
				};
				foreach (var cmd in commands) {
					try {
						Process.spawn_command_line_async (cmd);
						return AnimationType.BOUNCE;
					} catch (Error e) { }
				}
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
