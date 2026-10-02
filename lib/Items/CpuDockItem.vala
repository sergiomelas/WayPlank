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
	public class CpuDockItem : DockItem
	{
		uint timer_id = 0;
		uint64 prev_total = 0;
		uint64 prev_idle = 0;
		int cpu_pct = 0;
		int ram_pct = 0;
		double ram_used_gb = 0.0;
		double ram_total_gb = 0.0;
		
		public CpuDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		public CpuDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			Text = _("System Monitor");
			Icon = "utilities-system-monitor";
			Button = PopupButton.RIGHT;
			
			update_stats ();
			start_timer ();
		}
		
		~CpuDockItem ()
		{
			stop_timer ();
		}
		
		void start_timer ()
		{
			if (timer_id != 0)
				return;
			
			timer_id = Timeout.add (1500, on_timer_tick);
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
		
		void update_stats ()
		{
			// 1. CPU Usage via /proc/stat
			string stat_content;
			try {
				if (FileUtils.get_contents ("/proc/stat", out stat_content)) {
					var lines = stat_content.split ("\n");
					if (lines.length > 0 && lines[0].has_prefix ("cpu ")) {
						var parts = lines[0].split (" ");
						uint64 user = 0, nice = 0, system = 0, idle = 0, iowait = 0, irq = 0, softirq = 0, steal = 0;
						int part_idx = 0;
						for (int i = 1; i < parts.length; i++) {
							if (parts[i].strip () == "") continue;
							uint64 val = (uint64) uint64.parse (parts[i]);
							if (part_idx == 0) user = val;
							else if (part_idx == 1) nice = val;
							else if (part_idx == 2) system = val;
							else if (part_idx == 3) idle = val;
							else if (part_idx == 4) iowait = val;
							else if (part_idx == 5) irq = val;
							else if (part_idx == 6) softirq = val;
							else if (part_idx == 7) steal = val;
							part_idx++;
						}
						
						uint64 total = user + nice + system + idle + iowait + irq + softirq + steal;
						uint64 idle_all = idle + iowait;
						
						if (prev_total > 0 && total > prev_total) {
							uint64 diff_total = total - prev_total;
							uint64 diff_idle = (idle_all >= prev_idle) ? (idle_all - prev_idle) : 0;
							cpu_pct = (int) Math.round (100.0 * (double) (diff_total - diff_idle) / (double) diff_total);
							if (cpu_pct < 0) cpu_pct = 0;
							if (cpu_pct > 100) cpu_pct = 100;
						}
						prev_total = total;
						prev_idle = idle_all;
					}
				}
			} catch (Error e) { }

			// 2. RAM Usage via /proc/meminfo
			string mem_content;
			try {
				if (FileUtils.get_contents ("/proc/meminfo", out mem_content)) {
					uint64 total_kb = 0, avail_kb = 0;
					foreach (unowned string line in mem_content.split ("\n")) {
						if (line.has_prefix ("MemTotal:")) {
							var parts = line.split (":");
							if (parts.length > 1) total_kb = (uint64) uint64.parse (parts[1].strip ().replace ("kB", "").strip ());
						} else if (line.has_prefix ("MemAvailable:")) {
							var parts = line.split (":");
							if (parts.length > 1) avail_kb = (uint64) uint64.parse (parts[1].strip ().replace ("kB", "").strip ());
						}
					}
					
					if (total_kb > 0) {
						ram_total_gb = total_kb / (1024.0 * 1024.0);
						ram_used_gb = (total_kb - avail_kb) / (1024.0 * 1024.0);
						ram_pct = (int) Math.round (100.0 * (double) (total_kb - avail_kb) / (double) total_kb);
						if (ram_pct < 0) ram_pct = 0;
						if (ram_pct > 100) ram_pct = 100;
					}
				}
			} catch (Error e) { }

			Text = _("CPU: %d%% | RAM: %d%% (%.1f / %.1f GB)").printf (cpu_pct, ram_pct, ram_used_gb, ram_total_gb);
		}
		
		bool on_timer_tick ()
		{
			update_stats ();
			reset_icon_buffer ();
			return true;
		}
		
		void draw_gauge (Cairo.Context cr, double cx, double cy, double r, int percent, string label, bool is_cpu)
		{
			double start_angle = 135.0 * (Math.PI / 180.0);
			double end_angle = 405.0 * (Math.PI / 180.0);
			double total_angle = end_angle - start_angle;
			double sweep = start_angle + total_angle * (percent / 100.0);
			
			// Background Track
			cr.save ();
			cr.set_line_width (r * 0.22);
			cr.set_line_cap (Cairo.LineCap.ROUND);
			cr.set_source_rgba (1.0, 1.0, 1.0, 0.16);
			cr.arc (cx, cy, r, start_angle, end_angle);
			cr.stroke ();
			cr.restore ();
			
			// Active Filled Arc
			if (percent > 0) {
				cr.save ();
				cr.set_line_width (r * 0.22);
				cr.set_line_cap (Cairo.LineCap.ROUND);
				
				if (is_cpu) {
					// CPU: Emerald Green -> Amber -> Ruby Red
					if (percent < 50) cr.set_source_rgba (0.18, 0.80, 0.44, 0.95);
					else if (percent < 80) cr.set_source_rgba (0.95, 0.70, 0.12, 0.95);
					else cr.set_source_rgba (0.92, 0.22, 0.20, 0.95);
				} else {
					// RAM: Electric Cyan -> Purple -> Coral
					if (percent < 60) cr.set_source_rgba (0.16, 0.75, 0.98, 0.95);
					else if (percent < 85) cr.set_source_rgba (0.68, 0.38, 0.92, 0.95);
					else cr.set_source_rgba (0.92, 0.25, 0.40, 0.95);
				}
				
				cr.arc (cx, cy, r, start_angle, sweep);
				cr.stroke ();
				cr.restore ();
			}
			
			// Gauge Text Labels
			cr.save ();
			cr.select_font_face ("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
			
			// Value text (e.g. 42%)
			string val_str = "%d%%".printf (percent);
			cr.set_font_size (r * 0.58);
			Cairo.TextExtents te_val;
			cr.text_extents (val_str, out te_val);
			cr.set_source_rgba (1.0, 1.0, 1.0, 0.95);
			cr.move_to (cx - te_val.width / 2.0 - te_val.x_bearing, cy + (r * 0.12));
			cr.show_text (val_str);
			
			// Subtitle label (CPU / RAM)
			cr.set_font_size (r * 0.38);
			Cairo.TextExtents te_lbl;
			cr.text_extents (label, out te_lbl);
			cr.set_source_rgba (0.75, 0.82, 0.90, 0.85);
			cr.move_to (cx - te_lbl.width / 2.0 - te_lbl.x_bearing, cy + (r * 0.75));
			cr.show_text (label);
			
			cr.restore ();
		}
		
		protected override void draw_icon (Surface surface)
		{
			unowned Cairo.Context cr = surface.Context;
			double w = surface.Width;
			double h = surface.Height;
			double cx = w / 2.0;
			double cy = h / 2.0;
			double radius = (double.min (w, h) / 2.0) - (w * 0.04);
			
			if (radius < 8.0)
				return;
			
			// 1. Sleek Dashboard Card
			cr.save ();
			double box_w = radius * 1.92;
			double box_h = radius * 1.84;
			double r_corner = radius * 0.35;
			double x0 = cx - box_w / 2.0;
			double y0 = cy - box_h / 2.0;
			
			cr.new_sub_path ();
			cr.arc (x0 + box_w - r_corner, y0 + r_corner, r_corner, -Math.PI_2, 0);
			cr.arc (x0 + box_w - r_corner, y0 + box_h - r_corner, r_corner, 0, Math.PI_2);
			cr.arc (x0 + r_corner, y0 + box_h - r_corner, r_corner, Math.PI_2, Math.PI);
			cr.arc (x0 + r_corner, y0 + r_corner, r_corner, Math.PI, 3 * Math.PI_2);
			cr.close_path ();
			
			var pat = new Cairo.Pattern.linear (cx, y0, cx, y0 + box_h);
			pat.add_color_stop_rgba (0.0, 0.12, 0.14, 0.19, 0.94);
			pat.add_color_stop_rgba (1.0, 0.07, 0.08, 0.11, 0.94);
			cr.set_source (pat);
			cr.fill_preserve ();
			
			cr.set_source_rgba (1.0, 1.0, 1.0, 0.25);
			cr.set_line_width (radius * 0.04);
			cr.stroke ();
			cr.restore ();
			
			// 2. Dual Side-by-Side Meters
			double meter_r = radius * 0.38;
			double left_cx = cx - (radius * 0.48);
			double right_cx = cx + (radius * 0.48);
			double meter_cy = cy - (radius * 0.05);
			
			draw_gauge (cr, left_cx, meter_cy, meter_r, cpu_pct, "CPU", true);
			draw_gauge (cr, right_cx, meter_cy, meter_r, ram_pct, "RAM", false);
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				string[] monitors = { "plasma-systemmonitor", "gnome-system-monitor", "ksysguard" };
				foreach (var mon in monitors) {
					try {
						Process.spawn_command_line_async (mon);
						return AnimationType.BOUNCE;
					} catch (Error e) { }
				}
			}
			
			return AnimationType.NONE;
		}
		
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			
			var header_item = new Gtk.MenuItem.with_label (Text);
			header_item.sensitive = false;
			items.add (header_item);
			
			items.add (new Gtk.SeparatorMenuItem ());
			
			var mon_item = create_menu_item (_("_System Monitor..."), "utilities-system-monitor", true);
			mon_item.activate.connect (() => {
				on_clicked (PopupButton.LEFT, 0, 0);
			});
			items.add (mon_item);
			
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
