//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
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
	/**
	 * An animated window that draws a 'poof' animation.
	 * Used when dragging items off the dock.
	 */
	public class PoofWindow : CompositedWindow
	{
		const int RUN_LENGTH = 300 * 1000;
		
		static PoofWindow? instance = null;
		
		public static unowned PoofWindow get_default ()
		{
			if (instance == null)
				instance = new PoofWindow ();
			
			return instance;
		}
		
		Gdk.Pixbuf poof_image;
		int poof_size;
		int poof_frames;
		
		int64 start_time = 0LL;
		int64 frame_time = 0LL;
		
		uint animation_timer_id = 0U;
		
		/**
		 * Creates a new poof window at the screen-relative coordinates specified.
		 */
		public PoofWindow ()
		{
			GLib.Object (type: Gtk.WindowType.TOPLEVEL);
		}
		
		construct
		{
			decorated = false;
			resizable = false;
			accept_focus = false;
			can_focus = false;

			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.init_for_window (this);
				GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
				GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
				GtkLayerShell.set_namespace (this, "wayplank-poof");
			} else {
				set_decorated (false);
				set_type_hint (Gdk.WindowTypeHint.UTILITY);
				set_skip_taskbar_hint (true);
				set_skip_pager_hint (true);
				set_keep_above (true);
				set_title ("wayplank-poof");
				set_role ("poof");
			}
			
			try {
				poof_image = new Gdk.Pixbuf.from_resource ("%s/img/poof.svg".printf (Plank.G_RESOURCE_PATH));
				poof_size = poof_image.width;
				poof_frames = (int) Math.floor (poof_image.height / poof_size);
				debug ("Loaded animation: size = %ipx, frame-count = %i, duration = %ims", poof_size, poof_frames, RUN_LENGTH / 1000);
			} catch (Error e) {
				poof_image = null;
				critical ("Unable to load poof animation image: %s", e.message);
			}
			
			set_size_request (poof_size, poof_size);
		}
		
		~PoofWindow ()
		{
			if (animation_timer_id > 0U) {
				GLib.Source.remove (animation_timer_id);
				animation_timer_id = 0U;
			}
		}
		
		/**
		 * Show the animated poof-window at the given dock-relative coordinates.
		 *
		 * @param x the x position of the poof window
		 * @param y the y position of the poof window
		 * @param position the dock position
		 * @param dock_thickness thickness of the dock window
		 * @param monitor the monitor where the dock resides
		 */
		public void show_at (int x, int y, Gtk.PositionType position = Gtk.PositionType.BOTTOM, int dock_thickness = 0, Gdk.Monitor? monitor = null)
		{
			if (animation_timer_id > 0U)
				GLib.Source.remove (animation_timer_id);
			
			if (poof_image == null || poof_frames <= 0)
				return;
			
			Logger.verbose ("Show animation: size = %ipx, frame-count = %i, duration = %ims", poof_size, poof_frames, RUN_LENGTH / 1000);
			
			start_time = GLib.get_monotonic_time ();
			frame_time = start_time;
			
			var display = get_display ();
			if (monitor == null && display != null) {
				monitor = display.get_monitor_at_point (x, y);
				if (monitor == null)
					monitor = display.get_primary_monitor () ?? display.get_monitor (0);
			}
			
			if (monitor != null && GtkLayerShell.is_supported ())
				GtkLayerShell.set_monitor (this, monitor);
			
			var geo = monitor != null ? monitor.get_geometry () : Gdk.Rectangle ();
			var mon_w = geo.width > 0 ? geo.width : 1920;
			var mon_h = geo.height > 0 ? geo.height : 1080;
			
			var clamped_x = int.max (0, int.min (mon_w - poof_size, x - poof_size / 2));
			var clamped_y = int.max (0, int.min (mon_h - poof_size, y - poof_size / 2));
			var edge_margin = 0;

			if (!GtkLayerShell.is_supported ()) {
				int mon_x = geo.x;
				int mon_y = geo.y;

				int target_x = mon_x + x - poof_size / 2;
				int target_y = mon_y + y - poof_size / 2;

				switch (position) {
				case Gtk.PositionType.BOTTOM:
					target_y = mon_y + mon_h - poof_size;
					break;
				case Gtk.PositionType.TOP:
					target_y = mon_y;
					break;
				case Gtk.PositionType.LEFT:
					target_x = mon_x;
					break;
				case Gtk.PositionType.RIGHT:
					target_x = mon_x + mon_w - poof_size;
					break;
				}

				var abs_x = int.max (mon_x, int.min (mon_x + mon_w - poof_size, target_x));
				var abs_y = int.max (mon_y, int.min (mon_y + mon_h - poof_size, target_y));

				WindowControl.position_poof (abs_x, abs_y, poof_size, poof_size);
				move (abs_x, abs_y);
				show ();
				WindowControl.position_poof (abs_x, abs_y, poof_size, poof_size);
				GLib.Timeout.add (25, () => {
					WindowControl.position_poof (abs_x, abs_y, poof_size, poof_size);
					return false;
				});
				animation_timer_id = Gdk.threads_add_timeout (30, () => {
					frame_time = GLib.get_monotonic_time ();
					if (frame_time - start_time <= RUN_LENGTH) {
						queue_draw ();
						return true;
					}
					animation_timer_id = 0U;
					hide ();
					return false;
				});
				return;
			}
			
			GtkLayerShell.set_exclusive_zone (this, 0);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, 0);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, 0);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, 0);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, 0);
			set_size_request (poof_size, poof_size);
			
			switch (position) {
			case Gtk.PositionType.BOTTOM:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, edge_margin);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, clamped_x);
				break;
			case Gtk.PositionType.TOP:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, edge_margin);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, clamped_x);
				break;
			case Gtk.PositionType.LEFT:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, edge_margin);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, clamped_y);
				break;
			case Gtk.PositionType.RIGHT:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, edge_margin);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, clamped_y);
				break;
			}
			show ();

			animation_timer_id = Gdk.threads_add_timeout (30, () => {
				frame_time = GLib.get_monotonic_time ();
				
				if (frame_time - start_time <= RUN_LENGTH) {
					queue_draw ();
					return true;
				}
				
				animation_timer_id = 0U;
				hide ();
				return false;
			});
		}
		
		public override bool draw (Cairo.Context cr)
		{
			cr.set_operator (Cairo.Operator.SOURCE);
			Gdk.cairo_set_source_pixbuf (cr, poof_image, 0, -poof_size * (int) (poof_frames * (frame_time - start_time) / (double) RUN_LENGTH));
			cr.paint ();
			
			return Gdk.EVENT_STOP;
		}
	}
}
