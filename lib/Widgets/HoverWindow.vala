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
			GtkLayerShell.init_for_window (this);
			GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
			GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
			GtkLayerShell.set_namespace (this, "wayplank-hover");
			
			var display = Gdk.Display.get_default ();
			if (display != null) {
				var monitor = display.get_primary_monitor () ?? display.get_monitor (0);
				if (monitor != null)
					GtkLayerShell.set_monitor (this, monitor);
			}

			unowned Gdk.Screen screen = get_screen ();
			var visual = screen.get_rgba_visual ();
			if (visual != null)
				set_visual (visual);
			
			get_style_context ().add_class (Gtk.STYLE_CLASS_TOOLTIP);
			
			box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			box.set_margin_left (6);
			box.set_margin_right (6);
			box.set_margin_top (6);
			box.set_margin_bottom (6);
			add (box);
			box.show ();
			
			label = new Gtk.Label (null);
			label.set_line_wrap (true);
			box.pack_start (label, false, false, 0);
		}
		
		public void show_at (int x, int y, Gtk.PositionType position, int dock_thickness)
		{
			show ();
			
			Gtk.Requisition requisition;
			get_preferred_size (null, out requisition);
			var width = requisition.width > 0 ? requisition.width : get_allocated_width ();
			var height = requisition.height > 0 ? requisition.height : get_allocated_height ();

			var edge_margin = dock_thickness + GAP;
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
				
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, edge_margin);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, x - width / 2);
				break;

			case Gtk.PositionType.TOP:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
				
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, edge_margin);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, x - width / 2);
				break;

			case Gtk.PositionType.LEFT:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, edge_margin);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, y - height / 2);
				break;

			case Gtk.PositionType.RIGHT:
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, false);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
				
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, edge_margin);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, y - height / 2);
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
			
			context.render_background (cr, 0, 0, width, height);
			context.render_frame (cr, 0, 0, width, height);  
			
			return base.draw (cr);
		}
	}
}