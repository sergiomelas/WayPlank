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
	 * Unified Hardware Abstraction Layer (HAL) service for compositor-agnostic
	 * overlay surface initialization, dock-edge coordinate transformation, and
	 * sub-surface Cairo origin compensation across KWin, Mutter, and Labwc.
	 *
	 * UI widgets pass pure dock-monitor canonical logical coordinates and receive
	 * exact local Cairo (canvas_cx, canvas_cy) drawing origins without touching
	 * GtkLayerShell or compositor D-Bus positioning APIs directly.
	 */
	public class SurfaceCoordinateService : GLib.Object
	{
		/**
		 * Initializes a non-interactive, click-through overlay surface for the
		 * active Wayland compositor.
		 */
		public static void init_overlay_surface (Gtk.Window win, string surface_id, string role_name)
		{
			win.decorated = false;
			win.resizable = false;
			win.accept_focus = false;
			win.can_focus = false;

			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.init_for_window (win);
				GtkLayerShell.set_layer (win, GtkLayerShell.Layer.OVERLAY);
				GtkLayerShell.set_keyboard_mode (win, GtkLayerShell.KeyboardMode.NONE);
				GtkLayerShell.set_namespace (win, surface_id);
				GtkLayerShell.set_exclusive_zone (win, 0);
			} else {
				win.set_type_hint (Gdk.WindowTypeHint.UTILITY);
				win.set_skip_taskbar_hint (true);
				win.set_skip_pager_hint (true);
				win.set_keep_above (true);
				win.set_title (surface_id);
				win.set_role (role_name);
			}

			win.realize.connect (() => {
				apply_click_through_region (win);
			});
		}

		/**
		 * Ensures an overlay window never intercepts pointer hover or click events.
		 */
		public static void apply_click_through_region (Gtk.Window win)
		{
			var gdk_win = win.get_window ();
			if (gdk_win != null)
				gdk_win.input_shape_combine_region (new Cairo.Region (), 0, 0);
		}

		/**
		 * Computes native system panel inset on Layer-Shell compositors (KWin, Labwc)
		 * while subtracting WayPlank's own exclusive zone when ReserveSpace is active
		 * (Rule 9: zero workarea feedback loop).
		 */
		static int get_layer_shell_panel_inset (Gdk.Monitor? monitor, Gtk.PositionType dock_edge,
			bool reserve_space_active, int dock_exclusive_thickness)
		{
			if (monitor == null)
				return 0;

			var geom = monitor.get_geometry ();
			var work = monitor.get_workarea ();
			int own_reserve = reserve_space_active ? int.max (0, dock_exclusive_thickness) : 0;
			int inset = 0;

			switch (dock_edge) {
			default:
			case Gtk.PositionType.BOTTOM:
				int raw_bottom = int.max (0, (geom.y + geom.height) - (work.y + work.height));
				int native_bottom = int.max (0, raw_bottom - own_reserve);
				if (native_bottom > 0)
					inset = native_bottom + 2;
				break;
			case Gtk.PositionType.TOP:
				int raw_top = int.max (0, work.y - geom.y);
				int native_top = int.max (0, raw_top - own_reserve);
				if (native_top > 0)
					inset = native_top + 2;
				inset += WindowControl.get_top_panel_floating_offset (geom);
				break;
			case Gtk.PositionType.LEFT:
				int raw_left = int.max (0, work.x - geom.x);
				int native_left = int.max (0, raw_left - own_reserve);
				if (native_left > 0)
					inset = native_left + 2;
				break;
			case Gtk.PositionType.RIGHT:
				int raw_right = int.max (0, (geom.x + geom.width) - (work.x + work.width));
				int native_right = int.max (0, raw_right - own_reserve);
				if (native_right > 0)
					inset = native_right + 2;
				break;
			}

			return inset;
		}

		/**
		 * Places a fixed-size (surf_w x surf_h) overlay window flush with the dock's
		 * base edge at canonical icon coordinate (along_coord, perp_from_dock_base),
		 * clamped safely inside physical monitor bounds, and outputs the exact Cairo
		 * local origin (canvas_cx, canvas_cy) inside the surface matching the icon center.
		 */
		public static void place_dock_overlay (Gtk.Window win, Gdk.Monitor? monitor,
			Gtk.PositionType dock_edge, int along_coord, int perp_from_dock_base,
			int surf_w, int surf_h, bool reserve_space_active, int dock_exclusive_thickness,
			out double canvas_cx, out double canvas_cy)
		{
			var display = win.get_display ();
			if (monitor == null && display != null)
				monitor = display.get_primary_monitor () ?? display.get_monitor (0);

			var geo = (monitor != null) ? monitor.get_geometry () : Gdk.Rectangle ();
			int mon_x = geo.x;
			int mon_y = geo.y;
			int mon_w = geo.width > 0 ? geo.width : 1920;
			int mon_h = geo.height > 0 ? geo.height : 1080;

			int clamped_x = int.max (0, int.min (mon_w - surf_w, along_coord - surf_w / 2));
			int clamped_y = int.max (0, int.min (mon_h - surf_h, along_coord - surf_h / 2));

			int clamped_perp_h = perp_from_dock_base.clamp (8, surf_h - 8);
			int clamped_perp_w = perp_from_dock_base.clamp (8, surf_w - 8);

			switch (dock_edge) {
			default:
			case Gtk.PositionType.BOTTOM:
				canvas_cx = (double) (along_coord - clamped_x);
				canvas_cy = (double) (surf_h - clamped_perp_h);
				break;
			case Gtk.PositionType.TOP:
				canvas_cx = (double) (along_coord - clamped_x);
				canvas_cy = (double) clamped_perp_h;
				break;
			case Gtk.PositionType.LEFT:
				canvas_cx = (double) clamped_perp_w;
				canvas_cy = (double) (along_coord - clamped_y);
				break;
			case Gtk.PositionType.RIGHT:
				canvas_cx = (double) (surf_w - clamped_perp_w);
				canvas_cy = (double) (along_coord - clamped_y);
				break;
			}

			win.set_size_request (surf_w, surf_h);

			if (!GtkLayerShell.is_supported ()) {
				// GNOME Shell / Mutter: anchor strictly to physical monitor geometry (Rule 9).
				// MutterBackend._applyPoofPosition aligns TOP-edge overlays with _lastDockGeo.y.
				int abs_x = mon_x + clamped_x;
				int abs_y = mon_y + clamped_y;

				switch (dock_edge) {
				default:
				case Gtk.PositionType.BOTTOM:
					abs_y = mon_y + mon_h - surf_h;
					break;
				case Gtk.PositionType.TOP:
					abs_y = mon_y;
					break;
				case Gtk.PositionType.LEFT:
					abs_x = mon_x;
					break;
				case Gtk.PositionType.RIGHT:
					abs_x = mon_x + mon_w - surf_w;
					break;
				}

				WindowControl.position_poof (abs_x, abs_y, surf_w, surf_h);
				win.move (abs_x, abs_y);
				win.show ();
				apply_click_through_region (win);
				WindowControl.position_poof (abs_x, abs_y, surf_w, surf_h);
				return;
			}

			// Native Layer-Shell compositors: KDE Plasma 6 (KWin) & Labwc (wlroots)
			if (monitor != null && GtkLayerShell.get_monitor (win) != monitor)
				GtkLayerShell.set_monitor (win, monitor);

			int edge_margin = get_layer_shell_panel_inset (monitor, dock_edge,
				reserve_space_active, dock_exclusive_thickness);

			GtkLayerShell.set_exclusive_zone (win, 0);
			GtkLayerShell.set_margin (win, GtkLayerShell.Edge.TOP, 0);
			GtkLayerShell.set_margin (win, GtkLayerShell.Edge.BOTTOM, 0);
			GtkLayerShell.set_margin (win, GtkLayerShell.Edge.LEFT, 0);
			GtkLayerShell.set_margin (win, GtkLayerShell.Edge.RIGHT, 0);

			switch (dock_edge) {
			default:
			case Gtk.PositionType.BOTTOM:
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.BOTTOM, true);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.TOP, false);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_margin (win, GtkLayerShell.Edge.BOTTOM, edge_margin);
				GtkLayerShell.set_margin (win, GtkLayerShell.Edge.LEFT, clamped_x);
				break;
			case Gtk.PositionType.TOP:
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_margin (win, GtkLayerShell.Edge.TOP, edge_margin);
				GtkLayerShell.set_margin (win, GtkLayerShell.Edge.LEFT, clamped_x);
				break;
			case Gtk.PositionType.LEFT:
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_margin (win, GtkLayerShell.Edge.LEFT, edge_margin);
				GtkLayerShell.set_margin (win, GtkLayerShell.Edge.TOP, clamped_y);
				break;
			case Gtk.PositionType.RIGHT:
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.RIGHT, true);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.LEFT, false);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_margin (win, GtkLayerShell.Edge.RIGHT, edge_margin);
				GtkLayerShell.set_margin (win, GtkLayerShell.Edge.TOP, clamped_y);
				break;
			}

			win.show ();
			apply_click_through_region (win);
		}
	}
}

