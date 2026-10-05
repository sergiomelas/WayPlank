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
	public class ClockDockItem : DockItem
	{
		uint timer_id = 0;
		
		public ClockDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		public ClockDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			Text = _("Clock");
			Icon = "preferences-system-time";
			Button = PopupButton.RIGHT;
			
			update_clock_text ();
			start_timer ();
		}
		
		~ClockDockItem ()
		{
			stop_timer ();
		}
		
		void start_timer ()
		{
			if (timer_id != 0)
				return;
			
			timer_id = Timeout.add_seconds (1, on_timer_tick);
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
		
		void update_clock_text ()
		{
			var now = new DateTime.now_local ();
			Text = now.format ("%A %e %B %Y\n%H:%M:%S");
		}
		
		bool on_timer_tick ()
		{
			update_clock_text ();
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
			
			// 1. Dial Background
			cr.save ();
			cr.arc (cx, cy, radius, 0, 2 * Math.PI);
			cr.set_source_rgba (0.10, 0.11, 0.14, 0.88);
			cr.fill_preserve ();
			
			// Outer Bezel Rim
			cr.set_source_rgba (1.0, 1.0, 1.0, 0.35);
			cr.set_line_width (radius * 0.055);
			cr.stroke ();
			cr.restore ();
			
			// 2. Hour Ticks
			cr.save ();
			for (int i = 0; i < 12; i++) {
				double angle = i * (Math.PI / 6.0) - Math.PI_2;
				bool is_quarter = (i % 3 == 0);
				double tick_len = is_quarter ? (radius * 0.20) : (radius * 0.11);
				double tick_width = is_quarter ? (radius * 0.075) : (radius * 0.04);
				double r_outer = radius * 0.88;
				double r_inner = r_outer - tick_len;
				
				cr.set_line_width (tick_width);
				cr.set_line_cap (Cairo.LineCap.ROUND);
				if (is_quarter)
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.95);
				else
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.55);
				
				cr.move_to (cx + r_inner * Math.cos (angle), cy + r_inner * Math.sin (angle));
				cr.line_to (cx + r_outer * Math.cos (angle), cy + r_outer * Math.sin (angle));
				cr.stroke ();
			}
			cr.restore ();
			
			// 3. Current Time Angles
			var now = new DateTime.now_local ();
			int hour = now.get_hour ();
			int minute = now.get_minute ();
			int second = now.get_second ();
			
			double angle_h = (hour % 12 + minute / 60.0 + second / 3600.0) * (Math.PI / 6.0) - Math.PI_2;
			double angle_m = (minute + second / 60.0) * (Math.PI / 30.0) - Math.PI_2;
			double angle_s = second * (Math.PI / 30.0) - Math.PI_2;
			
			// 4. Hour Hand
			cr.save ();
			cr.set_line_cap (Cairo.LineCap.ROUND);
			cr.set_line_width (radius * 0.11);
			cr.set_source_rgba (0.95, 0.95, 0.95, 1.0);
			cr.move_to (cx - (radius * 0.12) * Math.cos (angle_h), cy - (radius * 0.12) * Math.sin (angle_h));
			cr.line_to (cx + (radius * 0.52) * Math.cos (angle_h), cy + (radius * 0.52) * Math.sin (angle_h));
			cr.stroke ();
			cr.restore ();
			
			// 5. Minute Hand
			cr.save ();
			cr.set_line_cap (Cairo.LineCap.ROUND);
			cr.set_line_width (radius * 0.08);
			cr.set_source_rgba (1.0, 1.0, 1.0, 1.0);
			cr.move_to (cx - (radius * 0.12) * Math.cos (angle_m), cy - (radius * 0.12) * Math.sin (angle_m));
			cr.line_to (cx + (radius * 0.76) * Math.cos (angle_m), cy + (radius * 0.76) * Math.sin (angle_m));
			cr.stroke ();
			cr.restore ();
			
			// 6. Second Hand (Vibrant Red Accent)
			cr.save ();
			cr.set_line_cap (Cairo.LineCap.ROUND);
			cr.set_line_width (radius * 0.04);
			cr.set_source_rgba (0.90, 0.22, 0.21, 1.0);
			cr.move_to (cx - (radius * 0.20) * Math.cos (angle_s), cy - (radius * 0.20) * Math.sin (angle_s));
			cr.line_to (cx + (radius * 0.84) * Math.cos (angle_s), cy + (radius * 0.84) * Math.sin (angle_s));
			cr.stroke ();
			
			// Center Pivot Dot
			cr.arc (cx, cy, radius * 0.075, 0, 2 * Math.PI);
			cr.fill ();
			
			// Center Highlight Pin
			cr.arc (cx, cy, radius * 0.03, 0, 2 * Math.PI);
			cr.set_source_rgba (1.0, 1.0, 1.0, 0.90);
			cr.fill ();
			cr.restore ();
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				CalendarWindow.toggle_calendar ();
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}
		
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			var now = new DateTime.now_local ();
			
			var time_item = new Gtk.MenuItem.with_label (now.format ("%A %e %B %Y — %H:%M:%S"));
			time_item.sensitive = false;
			items.add (time_item);
			
			items.add (new Gtk.SeparatorMenuItem ());
			
			var copy_item = create_menu_item (_("_Copy Time"), "edit-copy", true);
			copy_item.activate.connect (() => {
				var clip = Gtk.Clipboard.get (Gdk.SELECTION_CLIPBOARD);
				clip.set_text (new DateTime.now_local ().format ("%H:%M:%S"), -1);
			});
			items.add (copy_item);
			
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
