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
	 * A hover window that shows labels for dock items.
	 * Positioned dynamically via Hal.Shell.
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
		Gtk.CssProvider? css_provider = null;
		ulong theme_changed_id = 0UL;
		
		public HoverWindow ()
		{
			GLib.Object (type: Gtk.WindowType.TOPLEVEL);
		}

		void disconnect_theme_signal ()
		{
			if (theme_changed_id != 0UL) {
				SystemTheme.get_default ().disconnect (theme_changed_id);
				theme_changed_id = 0UL;
			}
		}

		public override void destroy ()
		{
			disconnect_theme_signal ();
			Hal.Shell.cancel_popup_sync (this);
			base.destroy ();
		}

		~HoverWindow ()
		{
			disconnect_theme_signal ();
			Hal.Shell.cancel_popup_sync (this);
		}
		
		void apply_theme_style ()
		{
			if (css_provider == null)
				css_provider = new Gtk.CssProvider ();

			bool dark = SystemTheme.get_default ().is_dark;
			try {
				string css = dark ? (
					"window.tooltip, tooltip, .tooltip {\n" +
					"    background-color: rgba(28, 28, 30, 0.94);\n" +
					"    color: #ffffff;\n" +
					"    border: 1px solid rgba(255, 255, 255, 0.18);\n" +
					"    border-radius: 7px;\n" +
					"}\n" +
					"window.tooltip label, tooltip label, .tooltip label, label {\n" +
					"    color: #f5f5f7;\n" +
					"    font-size: 11px;\n" +
					"    font-weight: 500;\n" +
					"}\n"
				) : (
					"window.tooltip, tooltip, .tooltip {\n" +
					"    background-color: rgba(248, 249, 251, 0.96);\n" +
					"    color: #1c1c1e;\n" +
					"    border: 1px solid rgba(0, 0, 0, 0.14);\n" +
					"    border-radius: 7px;\n" +
					"}\n" +
					"window.tooltip label, tooltip label, .tooltip label, label {\n" +
					"    color: #1c1c1e;\n" +
					"    font-size: 11px;\n" +
					"    font-weight: 500;\n" +
					"}\n"
				);
				css_provider.load_from_data (css);
			} catch (GLib.Error e) { }
		}

		void on_system_theme_changed (bool is_dark)
		{
			apply_theme_style ();
			queue_draw ();
		}
		
		construct
		{
			decorated = false;
			app_paintable = true;
			resizable = false;
			accept_focus = false;
			can_focus = false;
			Hal.Shell.init_popup_surface (this, PopupSurfaceKind.TOOLTIP);

			unowned Gdk.Screen screen = get_screen ();
			var visual = screen.get_rgba_visual ();
			if (visual != null)
				set_visual (visual);
			
			get_style_context ().add_class (Gtk.STYLE_CLASS_TOOLTIP);

			apply_theme_style ();
			if (css_provider != null)
				get_style_context ().add_provider (css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			
			box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			box.set_margin_start (10);
			box.set_margin_end (10);
			box.set_margin_top (5);
			box.set_margin_bottom (5);
			add (box);
			box.show ();
			
			label = new Gtk.Label (null);
			label.set_line_wrap (false);
			if (css_provider != null)
				label.get_style_context ().add_provider (css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			box.pack_start (label, false, false, 0);

			theme_changed_id = SystemTheme.get_default ().theme_changed.connect (on_system_theme_changed);
		}
		
		public void show_at (int x, int y, Gtk.PositionType position, int dock_thickness, Gdk.Monitor? monitor)
		{
			Hal.Shell.set_surface_monitor (this, monitor);

			show ();

			Gtk.Requisition requisition;
			get_preferred_size (null, out requisition);
			var width = requisition.width > 0 ? requisition.width : get_allocated_width ();
			var height = requisition.height > 0 ? requisition.height : get_allocated_height ();

			Hal.Shell.cancel_popup_sync (this);
			Hal.Shell.position_popup_surface (
				this, PopupSurfaceKind.TOOLTIP, monitor, position,
				x, y, width, height, dock_thickness, GAP
			);
			Hal.Shell.sync_popup_after_show (
				this, PopupSurfaceKind.TOOLTIP, monitor, position,
				x, y, dock_thickness, GAP
			);
		}

		/**
		 * Set the tooltip-text to show
		 *
		 * @param text the text to show
		 */
		public void set_text (string? text)
		{
			string safe_text = text ?? "";
			label.set_text (safe_text);
			if (safe_text != "")
				label.show ();
			else
				label.hide ();
			queue_resize ();
			queue_draw ();
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