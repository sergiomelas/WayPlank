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
	 * A non-interactive divider auto-inserted between pinned and temporary items.
	 */
	public class SeparatorDockItem : DockItem
	{
		const int THICKNESS = 2;
		
		public Color BarColor { get; set; default = Color () { red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0 }; }
		bool horizontal = true;
		
		construct
		{
			Text = "";
			Icon = "";
			notify["BarColor"].connect (() => reset_icon_buffer ());
		}

		public void set_horizontal_orientation (bool value)
		{
			if (horizontal == value)
				return;
			horizontal = value;
			reset_icon_buffer ();
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

			var bar_width = horizontal ? THICKNESS : int.max (10, (int) Math.floor (w * 0.52));
			var bar_height = horizontal ? int.max (10, (int) Math.floor (h * 0.52)) : THICKNESS;
			var bar_x = (w - bar_width) / 2.0;
			var bar_y = (h - bar_height) / 2.0;
			var radius = THICKNESS / 2.0;
			
			cr.save ();
			cr.set_source_rgba (BarColor.red, BarColor.green, BarColor.blue, BarColor.alpha);
			cr.new_sub_path ();
			cr.arc (bar_x + bar_width - radius, bar_y + radius, radius, -Math.PI_2, 0);
			cr.arc (bar_x + bar_width - radius, bar_y + bar_height - radius, radius, 0, Math.PI_2);
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
