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
	 * A hover window that shows labels for dock items.
	 * Positioned dynamically using GtkLayerShell.
	 */
	public class HoverWindow : Gtk.Window
	{
		const int GAP = 4;
		
		static construct
		{
			set_accessible_role (Atk.Role.TOOL_TIP);
			PlankCompat.gtk_widget_class_set_css_name ((GLib.ObjectClass) typeof (HoverWindow).class_ref (), "tooltip");
		}
		
		Gtk.Box box;
		Gtk.Label label;
		
		public HoverWindow ()
		{
			GLib.Object (type: Gtk.WindowType.TOPLEVEL);
		}
		
		construct
		{
			decorated = false;
			app_paintable = true;
			resizable = false;
			accept_focus = false;
			can_focus = false;
			
			// Wayland Layer Shell initialization
			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.init_for_window (this);
				GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
				GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
				GtkLayerShell.set_namespace (this, "wayplank-hover");
			} else {
				set_decorated (false);
				set_type_hint (Gdk.WindowTypeHint.TOOLTIP);
				set_skip_taskbar_hint (true);
				set_skip_pager_hint (true);
				set_keep_above (true);
				set_title ("wayplank-hover");
				set_role ("tooltip");
			}

			unowned Gdk.Screen screen = get_screen ();
			var visual = screen.get_rgba_visual ();
			if (visual != null)
				set_visual (visual);
			
			get_style_context ().add_class (Gtk.STYLE_CLASS_TOOLTIP);

			var css_provider = new Gtk.CssProvider ();
			try {
				css_provider.load_from_data (
					"window.tooltip, tooltip, .tooltip {\n" +
					"    background-color: rgba(28, 28, 30, 0.94);\n" +
					"    color: #ffffff;\n" +
					"    border: 1px solid rgba(255, 255, 255, 0.18);\n" +
					"    border-radius: 7px;\n" +
					"}\n" +
					"window.tooltip label, tooltip label, .tooltip label {\n" +
					"    color: #f5f5f7;\n" +
					"    font-size: 11px;\n" +
					"    font-weight: 500;\n" +
					"}\n"
				);
				get_style_context ().add_provider (css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			} catch (GLib.Error e) { }
			
			box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			box.set_margin_start (10);
			box.set_margin_end (10);
			box.set_margin_top (5);
			box.set_margin_bottom (5);
			add (box);
			box.show ();
			
			label = new Gtk.Label (null);
			label.set_line_wrap (false);
			box.pack_start (label, false, false, 0);
		}
		
		public void show_at (int x, int y, Gtk.PositionType position, int dock_thickness, Gdk.Monitor? monitor)
		{
			if (monitor != null && GtkLayerShell.is_supported ())
				GtkLayerShell.set_monitor (this, monitor);

			show ();
			
			Gtk.Requisition requisition;
			get_preferred_size (null, out requisition);
			var width = requisition.width > 0 ? requisition.width : get_allocated_width ();
			var height = requisition.height > 0 ? requisition.height : get_allocated_height ();

			var edge_margin = dock_thickness + GAP;

			var geo = monitor != null ? monitor.get_geometry () : Gdk.Rectangle ();
			var mon_w = geo.width > 0 ? geo.width : 1920;
			var mon_h = geo.height > 0 ? geo.height : 1080;

			if (!GtkLayerShell.is_supported ()) {
				int mon_x = geo.x;
				int mon_y = geo.y;

				int target_x = mon_x + x - width / 2;
				int target_y = mon_y + y;

				switch (position) {
				case Gtk.PositionType.BOTTOM:
					target_y = mon_y + mon_h - edge_margin - height;
					break;
				case Gtk.PositionType.TOP:
					int top_bar_offset = int.max (0, (monitor != null ? monitor.get_workarea ().y - monitor.get_geometry ().y : 0));
					target_y = mon_y + top_bar_offset + edge_margin;
					break;
				case Gtk.PositionType.LEFT:
					target_x = mon_x + edge_margin;
					target_y = mon_y + y - height / 2;
					break;
				case Gtk.PositionType.RIGHT:
					target_x = mon_x + mon_w - edge_margin - width;
					target_y = mon_y + y - height / 2;
					break;
				}

				var abs_x = int.max (mon_x + GAP, int.min (mon_x + mon_w - width - GAP, target_x));
				var abs_y = int.max (mon_y + GAP, int.min (mon_y + mon_h - height - GAP, target_y));

				move (abs_x, abs_y);
				WindowControl.position_hover (abs_x, abs_y, width, height);
				return;
			}

			var clamped_x = int.max (GAP, int.min (mon_w - width - GAP, x - width / 2));
			var clamped_y = int.max (GAP, int.min (mon_h - height - GAP, y - height / 2));

			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, 0);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, 0);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, 0);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, 0);

			switch (position) {
			case Gtk.PositionType.BOTTOM:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
				
				int bottom_panel_offset = 0;
				if (monitor != null) {
					var geom = monitor.get_geometry ();
					var work = monitor.get_workarea ();
					int bottom_panel = int.max (0, (geom.y + geom.height) - (work.y + work.height));
					if (bottom_panel > 0)
						bottom_panel_offset = bottom_panel + 2;
				}
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, edge_margin + bottom_panel_offset);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, clamped_x);
				break;

			case Gtk.PositionType.TOP:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
				
				int top_panel_offset = 0;
				if (monitor != null) {
					var geom = monitor.get_geometry ();
					var work = monitor.get_workarea ();
					int top_panel = int.max (0, work.y - geom.y);
					if (top_panel > 0)
						top_panel_offset = top_panel + 2;
				}
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, edge_margin + top_panel_offset);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, clamped_x);
				break;

			case Gtk.PositionType.LEFT:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				
				int left_panel_offset = 0;
				if (monitor != null) {
					var geom = monitor.get_geometry ();
					var work = monitor.get_workarea ();
					int left_panel = int.max (0, work.x - geom.x);
					if (left_panel > 0)
						left_panel_offset = left_panel + 2;
				}
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, edge_margin + left_panel_offset);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, clamped_y);
				break;

			case Gtk.PositionType.RIGHT:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				
				int right_panel_offset = 0;
				if (monitor != null) {
					var geom = monitor.get_geometry ();
					var work = monitor.get_workarea ();
					int right_panel = int.max (0, (geom.x + geom.width) - (work.x + work.width));
					if (right_panel > 0)
						right_panel_offset = right_panel + 2;
				}
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, edge_margin + right_panel_offset);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, clamped_y);
				break;
			}
		}

		/**
		 * Set the tooltip-text to show
		 *
		 * @param text the text to show
		 */
		public void set_text (string text)
		{
			label.set_text (text);
			if (text != null)
				label.show ();
			else
				label.hide ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override bool draw (Cairo.Context cr)
		{
			var width = get_allocated_width ();
			var height = get_allocated_height ();
			unowned Gtk.StyleContext context = get_style_context ();
			
			cr.save ();
			cr.set_operator (Cairo.Operator.CLEAR);
			cr.paint ();
			cr.restore ();

			context.render_background (cr, 0, 0, width, height);
			context.render_frame (cr, 0, 0, width, height);  
			
			return base.draw (cr);
		}
	}
}