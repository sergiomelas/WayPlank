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
	public class VolumeDockItem : DockItem
	{
		uint timer_id = 0;
		int volume = 70;
		bool is_muted = false;
		
		public VolumeDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		public VolumeDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			Text = _("Volume");
			Icon = "audio-volume-medium";
			Button = PopupButton.RIGHT;
			
			refresh_volume_status ();
			start_timer ();
		}
		
		~VolumeDockItem ()
		{
			stop_timer ();
		}
		
		void start_timer ()
		{
			if (timer_id != 0)
				return;
			
			timer_id = Timeout.add_seconds (2, on_timer_tick);
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
		
		void refresh_volume_status ()
		{
			int exit_status;
			string output;
			
			// 1. Check mute state via pactl
			try {
				if (Process.spawn_command_line_sync ("pactl get-sink-mute @DEFAULT_SINK@", out output, null, out exit_status) && exit_status == 0) {
					is_muted = output.contains ("yes");
				}
			} catch (Error e) { }
			
			// 2. Check volume percentage via pactl
			try {
				if (Process.spawn_command_line_sync ("pactl get-sink-volume @DEFAULT_SINK@", out output, null, out exit_status) && exit_status == 0) {
					// Output format: Volume: front-left: 45875 /  70% / ...
					var idx = output.index_of ("%");
					if (idx > 0) {
						var sub = output.slice (0, idx);
						var last_space = sub.last_index_of (" ");
						if (last_space >= 0) {
							string num_str = sub.slice (last_space + 1, sub.length).strip ();
							int v = int.parse (num_str);
							if (v >= 0 && v <= 150)
								volume = v;
						}
					}
				}
			} catch (Error e) { }
			
			update_display ();
		}
		
		void update_display ()
		{
			if (is_muted) {
				Text = _("Volume: %d%% (Muted)").printf (volume);
				Icon = "audio-volume-muted;;stock_volume-mute";
			} else {
				Text = _("Volume: %d%%").printf (volume);
				if (volume == 0)
					Icon = "audio-volume-muted;;stock_volume-mute";
				else if (volume < 35)
					Icon = "audio-volume-low;;stock_volume-min";
				else if (volume < 75)
					Icon = "audio-volume-medium;;stock_volume-med";
				else
					Icon = "audio-volume-high;;stock_volume-max";
			}
		}
		
		bool on_timer_tick ()
		{
			refresh_volume_status ();
			reset_icon_buffer ();
			return true;
		}
		
		public void change_volume (int delta)
		{
			// If muted and raising volume, unmute immediately!
			if (is_muted && delta > 0) {
				is_muted = false;
				try {
					Process.spawn_command_line_async ("pactl set-sink-mute @DEFAULT_SINK@ 0");
				} catch (Error e) {
					try {
						Process.spawn_command_line_async ("amixer set Master unmute");
					} catch (Error e2) { }
				}
			}
			
			volume += delta;
			if (volume < 0) volume = 0;
			if (volume > 150) volume = 150;
			
			string sign = (delta > 0) ? "+" : "-";
			int abs_delta = (delta > 0) ? delta : -delta;
			try {
				Process.spawn_command_line_async ("pactl set-sink-volume @DEFAULT_SINK@ %s%d%%".printf (sign, abs_delta));
			} catch (Error e) {
				try {
					Process.spawn_command_line_async ("amixer set Master %d%%%s".printf (abs_delta, sign));
				} catch (Error e2) { }
			}
			
			update_display ();
			reset_icon_buffer ();
		}
		
		public void toggle_mute ()
		{
			is_muted = !is_muted;
			
			try {
				Process.spawn_command_line_async ("pactl set-sink-mute @DEFAULT_SINK@ %s".printf (is_muted ? "1" : "0"));
			} catch (Error e) {
				try {
					Process.spawn_command_line_async ("amixer set Master toggle");
				} catch (Error e2) { }
			}
			
			update_display ();
			reset_icon_buffer ();
		}
		
		protected override void draw_icon (Surface surface)
		{
			unowned Cairo.Context cr = surface.Context;
			double w = surface.Width;
			double h = surface.Height;
			double cx = w / 2.0;
			double cy = h / 2.0;
			double radius = (double.min (w, h) / 2.0) - (w * 0.08);
			
			if (radius < 8.0)
				return;
			
			cr.save ();
			
			// 1. Vector Speaker Body & Flare Cone
			cr.save ();
			double base_w = radius * 0.28;
			double base_h = radius * 0.44;
			double cone_w = radius * 0.36;
			double cone_h = radius * 0.88;
			double x_base = cx - (radius * 0.35);
			
			cr.new_sub_path ();
			cr.move_to (x_base, cy - base_h / 2.0);
			cr.line_to (x_base + base_w, cy - base_h / 2.0);
			cr.line_to (x_base + base_w + cone_w, cy - cone_h / 2.0);
			cr.line_to (x_base + base_w + cone_w, cy + cone_h / 2.0);
			cr.line_to (x_base + base_w, cy + base_h / 2.0);
			cr.line_to (x_base, cy + base_h / 2.0);
			cr.close_path ();
			
			var pat = new Cairo.Pattern.linear (x_base, cy - cone_h / 2.0, x_base + base_w + cone_w, cy + cone_h / 2.0);
			pat.add_color_stop_rgba (0.0, 0.94, 0.96, 0.98, 0.96);
			pat.add_color_stop_rgba (1.0, 0.74, 0.78, 0.84, 0.96);
			cr.set_source (pat);
			cr.fill_preserve ();
			
			cr.set_source_rgba (0.12, 0.14, 0.18, 0.45);
			cr.set_line_width (radius * 0.04);
			cr.stroke ();
			cr.restore ();
			
			// 2. Sound Wave Arcs (when unmuted and volume > 0)
			if (!is_muted && volume > 0) {
				cr.save ();
				cr.set_line_cap (Cairo.LineCap.ROUND);
				double wave_cx = x_base + base_w + (cone_w * 0.22);
				
				// Arc 1 (> 0%)
				cr.set_line_width (radius * 0.08);
				cr.set_source_rgba (0.86, 0.90, 0.95, 0.92);
				cr.arc (wave_cx, cy, radius * 0.44, -Math.PI / 4.0, Math.PI / 4.0);
				cr.stroke ();
				
				// Arc 2 (> 35%)
				if (volume > 35) {
					cr.set_source_rgba (0.76, 0.84, 0.92, 0.92);
					cr.arc (wave_cx, cy, radius * 0.66, -Math.PI / 4.0, Math.PI / 4.0);
					cr.stroke ();
				}
				
				// Arc 3 (> 75%)
				if (volume > 75) {
					cr.set_source_rgba (0.66, 0.78, 0.90, 0.92);
					cr.arc (wave_cx, cy, radius * 0.88, -Math.PI / 4.0, Math.PI / 4.0);
					cr.stroke ();
				}
				cr.restore ();
			}
			
			// 3. Mute Red Slash (0ms instant, bold and ultra-visible)
			if (is_muted || volume == 0) {
				cr.save ();
				cr.set_line_cap (Cairo.LineCap.ROUND);
				double slash_len = radius * 0.72;
				double x1 = cx - slash_len;
				double y1 = cy - slash_len;
				double x2 = cx + slash_len;
				double y2 = cy + slash_len;
				
				// Drop shadow behind slash
				cr.set_line_width (radius * 0.18);
				cr.set_source_rgba (0.05, 0.06, 0.08, 0.55);
				cr.move_to (x1 + 1.0, y1 + 1.0);
				cr.line_to (x2 + 1.0, y2 + 1.0);
				cr.stroke ();
				
				// Vibrant Red Slash
				cr.set_line_width (radius * 0.14);
				cr.set_source_rgba (0.92, 0.20, 0.18, 0.98);
				cr.move_to (x1, y1);
				cr.line_to (x2, y2);
				cr.stroke ();
				cr.restore ();
			}
			
			cr.restore ();
		}
		
		protected override AnimationType on_scrolled (Gdk.ScrollDirection direction, Gdk.ModifierType mod, uint32 event_time)
		{
			if (direction == Gdk.ScrollDirection.UP) {
				change_volume (5);
				return AnimationType.NONE;
			} else if (direction == Gdk.ScrollDirection.DOWN) {
				change_volume (-5);
				return AnimationType.NONE;
			}
			return base.on_scrolled (direction, mod, event_time);
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				toggle_mute ();
				return AnimationType.BOUNCE;
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
			
			var mute_item = create_menu_item (is_muted ? _("Un_mute") : _("_Mute"), "audio-volume-muted", true);
			mute_item.activate.connect (toggle_mute);
			items.add (mute_item);
			
			var mixer_item = create_menu_item (_("_Audio Settings..."), "multimedia-volume-control", true);
			mixer_item.activate.connect (() => {
				string[] mixers = { "kcmshell6 kcm_pulseaudio", "kcmshell5 kcm_pulseaudio", "pavucontrol" };
				foreach (var m in mixers) {
					try {
						Process.spawn_command_line_async (m);
						break;
					} catch (Error e) { }
				}
			});
			items.add (mixer_item);
			
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
