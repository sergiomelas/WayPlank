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
	public class DigitalClockDockItem : DockItem
	{
		uint timer_id = 0;
		
		public DigitalClockDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		public DigitalClockDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			Text = _("Digital Clock");
			Icon = "org.kde.plasma.digitalclock;;preferences-system-time";
			Button = PopupButton.RIGHT;
			
			update_clock_text ();
			start_timer ();
		}
		
		~DigitalClockDockItem ()
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
			double radius = (double.min (w, h) / 2.0) - (w * 0.04);
			
			if (radius < 8.0)
				return;
			
			// 1. Sleek Modern Rounded Card / Dial Background
			cr.save ();
			double box_w = radius * 1.88;
			double box_h = radius * 1.76;
			double r_corner = radius * 0.38;
			double x0 = cx - box_w / 2.0;
			double y0 = cy - box_h / 2.0;
			
			// Draw smooth rounded rectangle
			cr.new_sub_path ();
			cr.arc (x0 + box_w - r_corner, y0 + r_corner, r_corner, -Math.PI_2, 0);
			cr.arc (x0 + box_w - r_corner, y0 + box_h - r_corner, r_corner, 0, Math.PI_2);
			cr.arc (x0 + r_corner, y0 + box_h - r_corner, r_corner, Math.PI_2, Math.PI);
			cr.arc (x0 + r_corner, y0 + r_corner, r_corner, Math.PI, 3 * Math.PI_2);
			cr.close_path ();
			
			// Dark glassy gradient background
			var pat = new Cairo.Pattern.linear (cx, y0, cx, y0 + box_h);
			pat.add_color_stop_rgba (0.0, 0.13, 0.15, 0.20, 0.94);
			pat.add_color_stop_rgba (1.0, 0.08, 0.09, 0.12, 0.94);
			cr.set_source (pat);
			cr.fill_preserve ();
			
			// Subtle border rim
			cr.set_source_rgba (1.0, 1.0, 1.0, 0.28);
			cr.set_line_width (radius * 0.04);
			cr.stroke ();
			cr.restore ();
			
			// 2. Render Time & Date
			var now = new DateTime.now_local ();
			string time_str = now.format ("%H:%M");
			string date_str = now.format ("%a %d").up ();
			
			cr.save ();
			cr.select_font_face ("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
			
			// Primary Time String (HH:MM)
			double time_font_size = radius * 0.62;
			cr.set_font_size (time_font_size);
			Cairo.TextExtents te_time;
			cr.text_extents (time_str, out te_time);
			
			// Soft shadow behind time
			cr.set_source_rgba (0.0, 0.0, 0.0, 0.50);
			cr.move_to (cx - te_time.width / 2.0 - te_time.x_bearing + 1.0,
			            cy - (radius * 0.04) + 1.0);
			cr.show_text (time_str);
			
			// Crisp pure white time
			cr.set_source_rgba (0.98, 0.98, 1.0, 1.0);
			cr.move_to (cx - te_time.width / 2.0 - te_time.x_bearing,
			            cy - (radius * 0.04));
			cr.show_text (time_str);
			
			// Subtitle Date String (e.g. "VEN 02")
			double date_font_size = radius * 0.32;
			cr.set_font_size (date_font_size);
			Cairo.TextExtents te_date;
			cr.text_extents (date_str, out te_date);
			
			// Cyan / Pastel accent color for date
			cr.set_source_rgba (0.38, 0.72, 0.98, 0.92);
			cr.move_to (cx - te_date.width / 2.0 - te_date.x_bearing,
			            cy + (radius * 0.44));
			cr.show_text (date_str);
			
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
