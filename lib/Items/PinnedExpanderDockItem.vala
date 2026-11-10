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
	/**
	 * The expander shown at the edge of the pinned apps group while the Smart Pinned
	 * Accordion is hiding some of them: a single chevron (›) while collapsed, a double
	 * chevron («) while expanded.
	 *
	 * It is owned and positioned by the DefaultApplicationDockItemProvider, has no
	 * backing .dockitem file (so it is never serialized), cannot be dragged or removed.
	 * Expanding/collapsing is handled by the DockWindow, like for the docklet accordion.
	 */
	public class PinnedExpanderDockItem : DockItem
	{
		const int BAR_THICKNESS = 2;

		public Color ChevronColor { get; set; default = Color () { red = 0.0, green = 0.0, blue = 0.0, alpha = 0.7 }; }
		public Color BarColor { get; set; default = Color () { red = 0.0, green = 0.0, blue = 0.0, alpha = 0.42 }; }

		/**
		 * Whether the accordion is currently expanded.
		 */
		public bool Expanded { get; set; default = false; }

		/**
		 * True when this expander controls the Docklets Accordion, false when it controls
		 * the Smart Pinned Apps Accordion.
		 */
		public bool IsDockletExpander { get; set; default = false; }

		bool horizontal = true;

		construct
		{
			Text = "";
			Icon = "";
			notify["ChevronColor"].connect (() => reset_icon_buffer ());
			notify["BarColor"].connect (() => reset_icon_buffer ());
			notify["Expanded"].connect (() => reset_icon_buffer ());
		}

		public void set_horizontal_orientation (bool value)
		{
			if (horizontal == value)
				return;
			horizontal = value;
			reset_icon_buffer ();
		}

		static void draw_chevron (Cairo.Context cr, double center_x, double center_y, double size, bool pointing_right)
		{
			var dir = pointing_right ? 1.0 : -1.0;
			cr.move_to (center_x - dir * size * 0.5, center_y - size);
			cr.line_to (center_x + dir * size * 0.5, center_y);
			cr.line_to (center_x - dir * size * 0.5, center_y + size);
			cr.stroke ();
		}

		/**
		 * {@inheritDoc}
		 */
		protected override void draw_icon (Surface surface)
		{
			unowned Cairo.Context cr = surface.Context;
			var w = surface.Width;
			var h = surface.Height;
			if (w <= 0 || h <= 0)
				return;

			var cx = w / 2.0;
			var cy = h / 2.0;
			var size = double.max (4.0, w * 0.17);

			cr.save ();
			if (!horizontal) {
				// Vertical docks: rotate so that › points down and « points up
				cr.translate (cx, cy);
				cr.rotate (Math.PI_2);
				cr.translate (-cx, -cy);
			}
			cr.set_source_rgba (ChevronColor.red, ChevronColor.green, ChevronColor.blue, ChevronColor.alpha);
			cr.set_line_width (double.max (2.0, w * 0.07));
			cr.set_line_cap (Cairo.LineCap.ROUND);
			cr.set_line_join (Cairo.LineJoin.ROUND);

			if (Expanded) {
				draw_chevron (cr, cx - size * 0.72, cy, size, false);
				draw_chevron (cr, cx + size * 0.12, cy, size, false);
			} else {
				draw_chevron (cr, cx - size * 0.18, cy, size, true);
			}

			// Thin separator bar on the right edge (›| / «|) matching SeparatorDockItem
			var bar_height = double.max (10.0, Math.floor (h * 0.52));
			var bar_x = cx + size * 1.05 - BAR_THICKNESS / 2.0;
			var bar_y = (h - bar_height) / 2.0;
			var radius = BAR_THICKNESS / 2.0;

			cr.set_source_rgba (BarColor.red, BarColor.green, BarColor.blue, BarColor.alpha);
			cr.new_sub_path ();
			cr.arc (bar_x + BAR_THICKNESS - radius, bar_y + radius, radius, -Math.PI_2, 0);
			cr.arc (bar_x + BAR_THICKNESS - radius, bar_y + bar_height - radius, radius, 0, Math.PI_2);
			cr.arc (bar_x + radius, bar_y + bar_height - radius, radius, Math.PI_2, Math.PI);
			cr.arc (bar_x + radius, bar_y + radius, radius, Math.PI, -Math.PI_2);
			cr.close_path ();
			cr.fill ();

			cr.restore ();
		}

		/**
		 * {@inheritDoc}
		 */
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			return AnimationType.NONE;
		}

		/**
		 * {@inheritDoc}
		 */
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			return new Gee.ArrayList<Gtk.MenuItem> ();
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool can_be_removed ()
		{
			return false;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool is_valid ()
		{
			return true;
		}
	}
}
