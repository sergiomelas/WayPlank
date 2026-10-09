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
				Icon = "battery-ac-adapter;;battery-missing;;battery-full";
			} else if (is_charging) {
				if (percentage < 20)
					Icon = "battery-caution-charging;;battery-empty-charging;;battery-full-charging";
				else if (percentage < 50)
					Icon = "battery-low-charging;;battery-good-charging;;battery-full-charging";
				else if (percentage < 85)
					Icon = "battery-good-charging;;battery-full-charging";
				else
					Icon = "battery-full-charging;;battery-full-charged;;battery-full";
			} else {
				if (percentage < 15)
					Icon = "battery-empty;;battery-caution;;battery-low";
				else if (percentage < 35)
					Icon = "battery-caution;;battery-low";
				else if (percentage < 65)
					Icon = "battery-low;;battery-good";
				else if (percentage < 90)
					Icon = "battery-good;;battery-full";
				else
					Icon = "battery-full";
			}
		}
		
		bool on_timer_tick ()
		{
			refresh_battery_status ();
			reset_icon_buffer ();
			return true;
		}
		
		protected override void draw_icon (Surface surface)
		{
			unowned Cairo.Context cr = surface.Context;
			double w = surface.Width;
			double h = surface.Height;
			double cx = w / 2.0;
			double cy = h / 2.0;
			double radius = (double.min (w, h) / 2.0) - (w * 0.05);
			
			if (radius < 8.0)
				return;
			
			cr.save ();
			
			// Battery Outer Dimensions (Vertical Capsule)
			double bat_w = radius * 1.08;
			double bat_h = radius * 1.62;
			double corner = radius * 0.22;
			double x0 = cx - bat_w / 2.0;
			double y0 = cy - bat_h / 2.0 + (radius * 0.08);
			
			// 1. Top Terminal Nub
			double nub_w = bat_w * 0.38;
			double nub_h = radius * 0.12;
			double nub_x = cx - nub_w / 2.0;
			double nub_y = y0 - nub_h + 1.0;
			
			cr.new_sub_path ();
			cr.arc (nub_x + nub_w - 2.0, nub_y + 2.0, 2.0, -Math.PI_2, 0);
			cr.arc (nub_x + 2.0, nub_y + 2.0, 2.0, Math.PI, 3 * Math.PI_2);
			cr.close_path ();
			cr.set_source_rgba (0.85, 0.88, 0.92, 0.85);
			cr.fill ();
			
			// 2. Battery Glass Body (Outer Shell)
			cr.new_sub_path ();
			cr.arc (x0 + bat_w - corner, y0 + corner, corner, -Math.PI_2, 0);
			cr.arc (x0 + bat_w - corner, y0 + bat_h - corner, corner, 0, Math.PI_2);
			cr.arc (x0 + corner, y0 + bat_h - corner, corner, Math.PI_2, Math.PI);
			cr.arc (x0 + corner, y0 + corner, corner, Math.PI, 3 * Math.PI_2);
			cr.close_path ();
			
			cr.set_source_rgba (0.10, 0.12, 0.16, 0.88);
			cr.fill_preserve ();
			
			cr.set_line_width (radius * 0.06);
			cr.set_source_rgba (0.90, 0.92, 0.96, 0.35);
			cr.stroke ();
			
			// 3. Inner Fill Gauge
			double pad = radius * 0.08;
			double fill_max_w = bat_w - 2 * pad;
			double fill_max_h = bat_h - 2 * pad;
			double fill_h = fill_max_h * (percentage / 100.0);
			if (fill_h < 4.0 && percentage > 0)
				fill_h = 4.0;
			
			double fill_x = x0 + pad;
			double fill_y = (y0 + bat_h - pad) - fill_h;
			double fill_r = corner * 0.70;
			
			if (percentage > 0) {
				cr.save ();
				cr.new_sub_path ();
				cr.arc (fill_x + fill_max_w - fill_r, fill_y + fill_r, fill_r, -Math.PI_2, 0);
				cr.arc (fill_x + fill_max_w - fill_r, fill_y + fill_h - fill_r, fill_r, 0, Math.PI_2);
				cr.arc (fill_x + fill_r, fill_y + fill_h - fill_r, fill_r, Math.PI_2, Math.PI);
				cr.arc (fill_x + fill_r, fill_y + fill_r, fill_r, Math.PI, 3 * Math.PI_2);
				cr.close_path ();
				
				// Determine color theme
				if (is_charging) {
					// Electric Cyan
					cr.set_source_rgba (0.16, 0.75, 0.98, 0.95);
				} else if (percentage > 35) {
					// Emerald Green
					cr.set_source_rgba (0.18, 0.82, 0.44, 0.95);
				} else if (percentage > 15) {
					// Amber / Orange
					cr.set_source_rgba (0.95, 0.65, 0.12, 0.95);
				} else {
					// Critical Red
					cr.set_source_rgba (0.92, 0.22, 0.20, 0.95);
				}
				cr.fill ();
				cr.restore ();
			}
			
			// 4. Center Symbol: Lightning Bolt if charging, Percentage otherwise
			if (is_charging) {
				cr.save ();
				cr.set_source_rgba (1.0, 1.0, 1.0, 0.95);
				cr.move_to (cx + (radius * 0.08), cy - (radius * 0.26));
				cr.line_to (cx - (radius * 0.18), cy + (radius * 0.04));
				cr.line_to (cx, cy + (radius * 0.04));
				cr.line_to (cx - (radius * 0.08), cy + (radius * 0.28));
				cr.line_to (cx + (radius * 0.18), cy - (radius * 0.02));
				cr.line_to (cx, cy - (radius * 0.02));
				cr.close_path ();
				cr.fill ();
				cr.restore ();
			} else {
				string pct_str = "%d%%".printf (percentage);
				cr.save ();
				cr.select_font_face ("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
				cr.set_font_size (radius * 0.34);
				Cairo.TextExtents te;
				cr.text_extents (pct_str, out te);
				
				cr.set_source_rgba (0.0, 0.0, 0.0, 0.60);
				cr.move_to (cx - te.width / 2.0 - te.x_bearing + 1.0, cy - te.height / 2.0 - te.y_bearing + 1.0);
				cr.show_text (pct_str);
				
				cr.set_source_rgba (1.0, 1.0, 1.0, 0.98);
				cr.move_to (cx - te.width / 2.0 - te.x_bearing, cy - te.height / 2.0 - te.y_bearing);
				cr.show_text (pct_str);
				cr.restore ();
			}
			
			cr.restore ();
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
			
			append_dock_menu_items (items);
			return items;
		}
		
		void append_dock_menu_items (Gee.ArrayList<Gtk.MenuItem> items)
		{
			if (items.size > 0)
				items.add (new Gtk.SeparatorMenuItem ());
			var dock_item = Factory.item_factory.get_item_for_dock ();
			if (dock_item != null)
				foreach (var menu_item in dock_item.get_menu_items ())
					items.add (menu_item);
		}
	}
}
