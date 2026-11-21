//
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
	 * Logical role for non-dock popup and transient overlay surfaces.
	 */
	public enum PopupSurfaceKind
	{
		TOOLTIP,
		FOLDER_MENU,
		PREVIEW_CARDS,
		POOF_ANIMATION
	}

	/**
	 * Metacompositor surface, strut, input-region, drag-grab, and monitor
	 * geometry contract. Encapsulates all display-protocol and compositor
	 * mechanics so Core never branches on surface model or driver type.
	 */
	public interface IDockShell : GLib.Object
	{
		public signal void primary_monitor_changed ();

		public abstract void init_dock_surface (Gtk.Window window);
		public abstract void init_popup_surface (Gtk.Window window, PopupSurfaceKind kind);
		public abstract bool set_surface_monitor (Gtk.Window window, Gdk.Monitor? monitor);
		public abstract void sync_dock_monitor (Gtk.Window window, Gdk.Monitor? monitor,
			out bool monitor_switched, out bool requires_geometry_refresh);
		public abstract bool update_dock_anchors (Gtk.Window window, Gdk.Monitor? monitor, Gtk.PositionType position);
		public abstract void handle_compositor_state_changed (Gtk.Window window, Gdk.Monitor? monitor,
			Gtk.PositionType position, out bool requires_geometry_refresh);
		public abstract void update_exclusive_zone (Gtk.Window window, bool enabled, int thickness, Gtk.PositionType position);
		public abstract void commit_dock_geometry (Gtk.Window window, Gdk.Rectangle win_rect);
		public abstract void present_dock_after_show (Gtk.Window window);
		public abstract void apply_input_region (Gtk.Window window, Cairo.Region? region);
		public abstract void resolve_tooltip_anchor (bool is_horizontal, int icon_size,
			Gdk.Point dynamic_center, Gdk.Point static_center, out int x, out int y);
		public abstract int resolve_tooltip_dock_thickness (int visual_thickness, int dock_window_span);
		public abstract void position_popup_surface (Gtk.Window window, PopupSurfaceKind kind,
			Gdk.Monitor? monitor, Gtk.PositionType dock_edge, int center_x, int center_y,
			int width, int height, int visual_thickness, int gap);
		public abstract void sync_popup_after_show (Gtk.Window window, PopupSurfaceKind kind,
			Gdk.Monitor? monitor, Gtk.PositionType dock_edge, int center_x, int center_y,
			int visual_thickness, int gap);
		public abstract void cancel_popup_sync (Gtk.Window window);
		public abstract void begin_drag_pointer_grab (Gtk.Window window, Gdk.DragContext context);
		public abstract void end_drag_pointer_grab (Gdk.DragContext context);
		public abstract void place_transient_overlay (Gtk.Window window, Gdk.Monitor? monitor,
			Gtk.PositionType dock_edge, int along_coord, int perp_from_dock_base,
			int surf_w, int surf_h, bool reserve_space_active, int dock_exclusive_thickness,
			out double canvas_cx, out double canvas_cy);
		public abstract bool get_primary_monitor_geometry (out int x, out int y, out int width, out int height);
		public abstract Gdk.Rectangle get_effective_monitor_geometry (Gdk.Monitor? monitor);
		public abstract int get_top_panel_floating_offset (Gdk.Rectangle mon_geom = Gdk.Rectangle ());
		public abstract void invalidate_panel_cache ();
		public virtual void cleanup () {}
	}

	/**
	 * Safe fallback shell implementation when no platform shell driver is bound.
	 */
	public class NullDockShell : GLib.Object, IDockShell
	{
		public void init_dock_surface (Gtk.Window window)
		{
			window.set_decorated (false);
			window.set_type_hint (Gdk.WindowTypeHint.DOCK);
			window.set_skip_taskbar_hint (true);
			window.set_skip_pager_hint (true);
			window.set_keep_above (true);
			window.set_title ("wayplank");
			window.set_role ("dock");
		}

		public void init_popup_surface (Gtk.Window window, PopupSurfaceKind kind)
		{
			window.set_decorated (false);
			window.set_skip_taskbar_hint (true);
			window.set_skip_pager_hint (true);
			window.set_keep_above (true);
		}

		public bool set_surface_monitor (Gtk.Window window, Gdk.Monitor? monitor)
		{
			return false;
		}

		public void sync_dock_monitor (Gtk.Window window, Gdk.Monitor? monitor,
			out bool monitor_switched, out bool requires_geometry_refresh)
		{
			monitor_switched = false;
			requires_geometry_refresh = false;
		}

		public bool update_dock_anchors (Gtk.Window window, Gdk.Monitor? monitor, Gtk.PositionType position)
		{
			return false;
		}

		public void handle_compositor_state_changed (Gtk.Window window, Gdk.Monitor? monitor,
			Gtk.PositionType position, out bool requires_geometry_refresh)
		{
			requires_geometry_refresh = !window.get_visible ();
		}

		public void update_exclusive_zone (Gtk.Window window, bool enabled, int thickness, Gtk.PositionType position)
		{
		}

		public void commit_dock_geometry (Gtk.Window window, Gdk.Rectangle win_rect)
		{
			window.move (win_rect.x, win_rect.y);
			if (!window.get_visible ()) {
				window.show_all ();
				window.stick ();
				window.present ();
			}
			window.queue_draw ();
		}

		public void present_dock_after_show (Gtk.Window window)
		{
		}

		public void apply_input_region (Gtk.Window window, Cairo.Region? region)
		{
		}

		public void resolve_tooltip_anchor (bool is_horizontal, int icon_size,
			Gdk.Point dynamic_center, Gdk.Point static_center, out int x, out int y)
		{
			x = dynamic_center.x;
			y = dynamic_center.y;
		}

		public int resolve_tooltip_dock_thickness (int visual_thickness, int dock_window_span)
		{
			return dock_window_span;
		}

		public void position_popup_surface (Gtk.Window window, PopupSurfaceKind kind,
			Gdk.Monitor? monitor, Gtk.PositionType dock_edge, int center_x, int center_y,
			int width, int height, int visual_thickness, int gap)
		{
			window.move (center_x - width / 2, center_y - height / 2);
		}

		public void sync_popup_after_show (Gtk.Window window, PopupSurfaceKind kind,
			Gdk.Monitor? monitor, Gtk.PositionType dock_edge, int center_x, int center_y,
			int visual_thickness, int gap)
		{
		}

		public void cancel_popup_sync (Gtk.Window window)
		{
		}

		public void begin_drag_pointer_grab (Gtk.Window window, Gdk.DragContext context)
		{
		}

		public void end_drag_pointer_grab (Gdk.DragContext context)
		{
		}

		public void place_transient_overlay (Gtk.Window window, Gdk.Monitor? monitor,
			Gtk.PositionType dock_edge, int along_coord, int perp_from_dock_base,
			int surf_w, int surf_h, bool reserve_space_active, int dock_exclusive_thickness,
			out double canvas_cx, out double canvas_cy)
		{
			canvas_cx = surf_w / 2.0;
			canvas_cy = surf_h / 2.0;
			window.set_size_request (surf_w, surf_h);
			window.show ();
		}

		public bool get_primary_monitor_geometry (out int x, out int y, out int width, out int height)
		{
			x = 0; y = 0; width = 0; height = 0;
			return false;
		}

		public Gdk.Rectangle get_effective_monitor_geometry (Gdk.Monitor? monitor)
		{
			return monitor != null ? monitor.get_workarea () : Gdk.Rectangle ();
		}

		public int get_top_panel_floating_offset (Gdk.Rectangle mon_geom = Gdk.Rectangle ())
		{
			return 0;
		}

		public void invalidate_panel_cache ()
		{
		}
	}
}
