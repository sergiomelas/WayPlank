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
	 * Southbound Freedesktop/Wayland Metacompositor shell implementation.
	 * Encapsulates all `GtkLayerShell` (KWin / Labwc) vs. `WindowControl` IPC
	 * (GNOME Mutter) surface, anchor, monitor, drag-grab, and popup mechanics
	 * so Core remains 100% blind to the underlying compositor model.
	 */
	public class LayerShellDockShell : GLib.Object, IDockShell
	{
		class DockAnchorCache : GLib.Object
		{
			public GLib.WeakRef win_ref;
			public GLib.WeakRef clock_ref;
			public bool initialized = false;
			public Gtk.PositionType pos = Gtk.PositionType.BOTTOM;
			public int top_margin = -1;
			public int bottom_margin = -1;
			public int left_margin = -1;
			public int right_margin = -1;
			public bool excl_enabled = false;
			public int excl_thickness = 0;
			public bool pending_post_map_excl = false;
			public bool map_hooked = false;
			public ulong after_paint_id = 0UL;

			public DockAnchorCache (Gtk.Window window)
			{
				win_ref = GLib.WeakRef (window);
				clock_ref = GLib.WeakRef (null);
			}

			public void disconnect_frame_clock ()
			{
				if (after_paint_id != 0UL) {
					var clk = clock_ref.get () as Gdk.FrameClock;
					if (clk != null)
						clk.disconnect (after_paint_id);
					after_paint_id = 0UL;
					clock_ref.set (null);
				}
			}

			public bool on_mapped (Gtk.Widget w, Gdk.EventAny ev)
			{
				var win = win_ref.get () as Gtk.Window;
				if (win == null || !pending_post_map_excl || !excl_enabled || excl_thickness <= 0)
					return false;

				disconnect_frame_clock ();
				var clk = win.get_frame_clock ();
				if (clk != null) {
					clock_ref.set (clk);
					after_paint_id = clk.after_paint.connect (on_after_first_paint);
					win.queue_draw ();
				} else {
					pending_post_map_excl = false;
					GtkLayerShell.set_exclusive_zone (win, excl_thickness);
					win.queue_draw ();
				}
				return false;
			}

			void on_after_first_paint (Gdk.FrameClock clk)
			{
				disconnect_frame_clock ();
				var win = win_ref.get () as Gtk.Window;
				if (win == null || !pending_post_map_excl)
					return;
				pending_post_map_excl = false;
				if (excl_enabled && excl_thickness > 0) {
					GtkLayerShell.set_layer (win, GtkLayerShell.Layer.TOP);
					GtkLayerShell.set_exclusive_zone (win, excl_thickness);
					win.queue_draw ();
				}
			}
		}

		class PopupSyncState : GLib.Object
		{
			public GLib.WeakRef win_ref;
			public GLib.WeakRef mon_ref;
			public unowned LayerShellDockShell shell;
			public PopupSurfaceKind kind = PopupSurfaceKind.TOOLTIP;
			public Gtk.PositionType dock_edge = Gtk.PositionType.BOTTOM;
			public int center_x = 0;
			public int center_y = 0;
			public int visual_thickness = 0;
			public int gap = 4;
			public uint timer_id = 0U;
			public bool signals_hooked = false;

			public PopupSyncState (LayerShellDockShell owner, Gtk.Window window)
			{
				shell = owner;
				win_ref = GLib.WeakRef (window);
				mon_ref = GLib.WeakRef (null);
			}

			public void cancel ()
			{
				if (timer_id > 0U) {
					GLib.Source.remove (timer_id);
					timer_id = 0U;
				}
			}

			public bool on_sync_tick ()
			{
				timer_id = 0U;
				var win = win_ref.get () as Gtk.Window;
				if (win == null || !win.get_visible ())
					return false;

				Gtk.Requisition req;
				win.get_preferred_size (null, out req);
				int w = req.width > 0 ? req.width : win.get_allocated_width ();
				int h = req.height > 0 ? req.height : win.get_allocated_height ();
				var mon = mon_ref.get () as Gdk.Monitor;
				shell.position_popup_surface (win, kind, mon, dock_edge, center_x, center_y, w, h, visual_thickness, gap);
				return false;
			}
		}

		bool monitor_signal_connected = false;

		public LayerShellDockShell ()
		{
			WindowControl.get_default ().primary_monitor_changed.connect (on_backend_primary_monitor_changed);
			monitor_signal_connected = true;
		}

		~LayerShellDockShell ()
		{
			cleanup ();
		}

		public void cleanup ()
		{
			if (!monitor_signal_connected)
				return;
			monitor_signal_connected = false;
			WindowControl.get_default ().primary_monitor_changed.disconnect (on_backend_primary_monitor_changed);
		}

		void on_backend_primary_monitor_changed ()
		{
			primary_monitor_changed ();
		}

		public void init_dock_surface (Gtk.Window window)
		{
			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.init_for_window (window);
				GtkLayerShell.set_layer (window, GtkLayerShell.Layer.TOP);
				GtkLayerShell.set_keyboard_mode (window, GtkLayerShell.KeyboardMode.NONE);
				GtkLayerShell.set_namespace (window, "dock");
			} else {
				window.set_decorated (false);
				window.set_type_hint (Gdk.WindowTypeHint.DOCK);
				window.set_skip_taskbar_hint (true);
				window.set_skip_pager_hint (true);
				window.set_keep_above (true);
				window.set_title ("wayplank");
				window.set_role ("dock");
			}
		}

		public void init_popup_surface (Gtk.Window window, PopupSurfaceKind kind)
		{
			if (kind == PopupSurfaceKind.POOF_ANIMATION) {
				SurfaceCoordinateService.init_overlay_surface (window, "wayplank-poof", "poof");
				return;
			}

			string ns = "wayplank-hover";
			switch (kind) {
			case PopupSurfaceKind.FOLDER_MENU:
				ns = "wayplank-folder-menu";
				break;
			case PopupSurfaceKind.PREVIEW_CARDS:
				ns = "wayplank-hover-cards";
				break;
			default:
			case PopupSurfaceKind.TOOLTIP:
				ns = "wayplank-hover";
				break;
			}

			window.set_decorated (false);
			window.set_title (ns);
			window.set_role ("popup-menu");

			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.init_for_window (window);
				GtkLayerShell.set_layer (window, GtkLayerShell.Layer.OVERLAY);
				GtkLayerShell.set_keyboard_mode (window, GtkLayerShell.KeyboardMode.NONE);
				GtkLayerShell.set_namespace (window, ns);
			} else {
				window.set_type_hint (Gdk.WindowTypeHint.POPUP_MENU);
				window.set_skip_taskbar_hint (true);
				window.set_skip_pager_hint (true);
				window.set_keep_above (true);
			}
		}

		public bool set_surface_monitor (Gtk.Window window, Gdk.Monitor? monitor)
		{
			if (monitor == null || !GtkLayerShell.is_supported ())
				return false;
			if (GtkLayerShell.get_monitor (window) == monitor)
				return false;
			GtkLayerShell.set_monitor (window, monitor);
			return true;
		}

		public void sync_dock_monitor (Gtk.Window window, Gdk.Monitor? monitor,
			out bool monitor_switched, out bool requires_geometry_refresh)
		{
			monitor_switched = false;
			requires_geometry_refresh = false;

			if (!GtkLayerShell.is_supported () || monitor == null)
				return;

			monitor_switched = set_surface_monitor (window, monitor);
			requires_geometry_refresh = true;
		}

		public bool update_dock_anchors (Gtk.Window window, Gdk.Monitor? monitor, Gtk.PositionType pos)
		{
			if (!GtkLayerShell.is_supported ())
				return false;

			int top_margin = 0;
			int bottom_margin = 0;
			int left_margin = 0;
			int right_margin = 0;
			if (monitor != null) {
				var geom = monitor.get_geometry ();
				var work = monitor.get_workarea ();
				int top_panel = int.max (0, work.y - geom.y);
				int bottom_panel = int.max (0, (geom.y + geom.height) - (work.y + work.height));
				int left_panel = int.max (0, work.x - geom.x);
				int right_panel = int.max (0, (geom.x + geom.width) - (work.x + work.width));
				if (pos == Gtk.PositionType.TOP && top_panel > 0)
					top_margin = top_panel + 2;
				else if (pos == Gtk.PositionType.BOTTOM && bottom_panel > 0)
					bottom_margin = bottom_panel + 2;
				else if (pos == Gtk.PositionType.LEFT && left_panel > 0)
					left_margin = left_panel + 2;
				else if (pos == Gtk.PositionType.RIGHT && right_panel > 0)
					right_margin = right_panel + 2;
			}
			if (pos == Gtk.PositionType.TOP) {
				Gdk.Rectangle mon_geom = (monitor != null) ? monitor.get_geometry () : Gdk.Rectangle ();
				top_margin += WindowControl.get_top_panel_floating_offset (mon_geom);
			}

			var cache = window.get_data<DockAnchorCache> ("wayplank-anchor-cache");
			if (cache == null) {
				cache = new DockAnchorCache (window);
				window.set_data<DockAnchorCache> ("wayplank-anchor-cache", cache);
			}

			if (cache.initialized
				&& pos == cache.pos
				&& top_margin == cache.top_margin
				&& bottom_margin == cache.bottom_margin
				&& left_margin == cache.left_margin
				&& right_margin == cache.right_margin) {
				return false;
			}

			cache.initialized = true;
			cache.pos = pos;
			cache.top_margin = top_margin;
			cache.bottom_margin = bottom_margin;
			cache.left_margin = left_margin;
			cache.right_margin = right_margin;

			GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, pos == Gtk.PositionType.BOTTOM || pos == Gtk.PositionType.LEFT || pos == Gtk.PositionType.RIGHT);
			GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, pos == Gtk.PositionType.TOP || pos == Gtk.PositionType.LEFT || pos == Gtk.PositionType.RIGHT);
			GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, pos == Gtk.PositionType.LEFT || pos == Gtk.PositionType.BOTTOM || pos == Gtk.PositionType.TOP);
			GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, pos == Gtk.PositionType.RIGHT || pos == Gtk.PositionType.BOTTOM || pos == Gtk.PositionType.TOP);

			GtkLayerShell.set_margin (window, GtkLayerShell.Edge.TOP, top_margin);
			GtkLayerShell.set_margin (window, GtkLayerShell.Edge.BOTTOM, bottom_margin);
			GtkLayerShell.set_margin (window, GtkLayerShell.Edge.LEFT, left_margin);
			GtkLayerShell.set_margin (window, GtkLayerShell.Edge.RIGHT, right_margin);
			return true;
		}

		public void handle_compositor_state_changed (Gtk.Window window, Gdk.Monitor? monitor,
			Gtk.PositionType position, out bool requires_geometry_refresh)
		{
			if (GtkLayerShell.is_supported ()) {
				requires_geometry_refresh = false;
				if (position == Gtk.PositionType.TOP && update_dock_anchors (window, monitor, position))
					window.queue_draw ();
			} else {
				requires_geometry_refresh = !window.get_visible ();
			}
		}

		public void update_exclusive_zone (Gtk.Window window, bool enabled, int thickness, Gtk.PositionType position)
		{
			if (GtkLayerShell.is_supported ()) {
				var cache = window.get_data<DockAnchorCache> ("wayplank-anchor-cache");
				if (cache == null) {
					cache = new DockAnchorCache (window);
					window.set_data<DockAnchorCache> ("wayplank-anchor-cache", cache);
				}
				if (!cache.map_hooked) {
					cache.map_hooked = true;
					window.map_event.connect (cache.on_mapped);
					window.destroy.connect (cache.disconnect_frame_clock);
				}

				cache.excl_enabled = enabled;
				cache.excl_thickness = thickness;

				// Keep WayPlank on Layer.TOP (standard Wayland panel layer: above normal/maximized
				// windows and below fullscreen windows) so floating windows never paint over the dock.
				GtkLayerShell.set_layer (window, GtkLayerShell.Layer.TOP);
				if (enabled && thickness > 0) {
					if (!window.get_mapped ()) {
						cache.pending_post_map_excl = true;
						GtkLayerShell.set_exclusive_zone (window, 0);
					} else {
						cache.pending_post_map_excl = false;
						cache.disconnect_frame_clock ();
						GtkLayerShell.set_exclusive_zone (window, thickness);
					}
				} else {
					cache.pending_post_map_excl = false;
					cache.disconnect_frame_clock ();
					GtkLayerShell.set_exclusive_zone (window, 0);
				}
			}

			WindowControl.set_reserve_space (enabled, thickness, position);
		}

		public void commit_dock_geometry (Gtk.Window window, Gdk.Rectangle win_rect)
		{
			bool ready = true;
			if (!GtkLayerShell.is_supported ()) {
				int cur_w, cur_h;
				window.get_size (out cur_w, out cur_h);
				if (cur_w != win_rect.width || cur_h != win_rect.height)
					window.resize (win_rect.width, win_rect.height);
				window.move (win_rect.x, win_rect.y);
				ready = WindowControl.position_dock (win_rect.x, win_rect.y, win_rect.width, win_rect.height);
			}

			if (ready) {
				window.show_all ();
				window.stick ();
				if (!GtkLayerShell.is_supported ())
					window.present ();
				window.queue_draw ();
			} else if (!GtkLayerShell.is_supported () && window.get_visible ()) {
				window.hide ();
			}
		}

		public void present_dock_after_show (Gtk.Window window)
		{
			if (GtkLayerShell.is_supported ())
				window.present ();
		}

		public void apply_input_region (Gtk.Window window, Cairo.Region? region)
		{
			var gdk_win = window.get_window ();
			if (gdk_win != null)
				gdk_win.input_shape_combine_region (region ?? new Cairo.Region (), 0, 0);
		}

		public void resolve_tooltip_anchor (bool is_horizontal, int icon_size,
			Gdk.Point dynamic_center, Gdk.Point static_center, out int x, out int y)
		{
			if (GtkLayerShell.is_supported ()) {
				x = dynamic_center.x;
				y = dynamic_center.y;
				return;
			}

			x = static_center.x > 0 ? static_center.x : dynamic_center.x;
			if (is_horizontal) {
				y = dynamic_center.y;
			} else {
				int half_icon = (int) Math.round (icon_size / 2.0);
				y = (static_center.y > 0 ? static_center.y : dynamic_center.y) + half_icon;
			}
		}

		public int resolve_tooltip_dock_thickness (int visual_thickness, int dock_window_span)
		{
			return GtkLayerShell.is_supported () ? visual_thickness + 40 : dock_window_span;
		}

		public void position_popup_surface (Gtk.Window window, PopupSurfaceKind kind,
			Gdk.Monitor? monitor, Gtk.PositionType dock_edge, int center_x, int center_y,
			int width, int height, int visual_thickness, int gap)
		{
			var geo = (monitor != null) ? monitor.get_geometry () : Gdk.Rectangle ();
			int mon_w = geo.width > 0 ? geo.width : 1920;
			int mon_h = geo.height > 0 ? geo.height : 1080;

			if (!GtkLayerShell.is_supported ()) {
				int mon_x = geo.x;
				int mon_y = geo.y;
				int target_x = mon_x + center_x - width / 2;
				int target_y = mon_y + center_y;
				int mutter_offset = (kind == PopupSurfaceKind.TOOLTIP) ? 0 : 8;

				switch (dock_edge) {
				default:
				case Gtk.PositionType.BOTTOM:
					target_y = mon_y + mon_h - visual_thickness - gap - height + mutter_offset;
					break;
				case Gtk.PositionType.TOP:
					int top_bar_offset = int.max (0, (monitor != null ? monitor.get_workarea ().y - monitor.get_geometry ().y : 0));
					target_y = mon_y + top_bar_offset + visual_thickness + gap - mutter_offset;
					break;
				case Gtk.PositionType.LEFT:
					target_x = mon_x + visual_thickness + gap - mutter_offset;
					target_y = mon_y + center_y - height / 2;
					break;
				case Gtk.PositionType.RIGHT:
					target_x = mon_x + mon_w - visual_thickness - gap - width + mutter_offset;
					target_y = mon_y + center_y - height / 2;
					break;
				}

				int abs_x = int.max (mon_x + gap, int.min (mon_x + mon_w - width - gap, target_x));
				int abs_y = int.max (mon_y + gap, int.min (mon_y + mon_h - height - gap, target_y));
				window.move (abs_x, abs_y);
				WindowControl.position_hover (abs_x, abs_y, width, height);
				return;
			}

			int edge_margin = visual_thickness + gap;
			int clamped_x = int.max (gap, int.min (mon_w - width - gap, center_x - width / 2));
			int clamped_y = int.max (gap, int.min (mon_h - height - gap, center_y - height / 2));

			GtkLayerShell.set_margin (window, GtkLayerShell.Edge.TOP, 0);
			GtkLayerShell.set_margin (window, GtkLayerShell.Edge.BOTTOM, 0);
			GtkLayerShell.set_margin (window, GtkLayerShell.Edge.LEFT, 0);
			GtkLayerShell.set_margin (window, GtkLayerShell.Edge.RIGHT, 0);

			switch (dock_edge) {
			default:
			case Gtk.PositionType.BOTTOM:
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, true);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, false);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, false);

				int bottom_panel_offset = 0;
				if (monitor != null) {
					var work = monitor.get_workarea ();
					int bottom_panel = int.max (0, (geo.y + geo.height) - (work.y + work.height));
					if (bottom_panel > 0)
						bottom_panel_offset = bottom_panel + 2;
				}
				GtkLayerShell.set_margin (window, GtkLayerShell.Edge.BOTTOM, edge_margin + bottom_panel_offset);
				GtkLayerShell.set_margin (window, GtkLayerShell.Edge.LEFT, clamped_x);
				break;

			case Gtk.PositionType.TOP:
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, false);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, false);

				int top_panel_offset = 0;
				if (monitor != null) {
					var work = monitor.get_workarea ();
					int top_panel = int.max (0, work.y - geo.y);
					if (top_panel > 0)
						top_panel_offset = top_panel + 2;
				}
				top_panel_offset += WindowControl.get_top_panel_floating_offset (geo);
				GtkLayerShell.set_margin (window, GtkLayerShell.Edge.TOP, edge_margin + top_panel_offset);
				GtkLayerShell.set_margin (window, GtkLayerShell.Edge.LEFT, clamped_x);
				break;

			case Gtk.PositionType.LEFT:
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, false);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, false);

				int left_panel_offset = 0;
				if (monitor != null) {
					var work = monitor.get_workarea ();
					int left_panel = int.max (0, work.x - geo.x);
					if (left_panel > 0)
						left_panel_offset = left_panel + 2;
				}
				GtkLayerShell.set_margin (window, GtkLayerShell.Edge.LEFT, edge_margin + left_panel_offset);
				GtkLayerShell.set_margin (window, GtkLayerShell.Edge.TOP, clamped_y);
				break;

			case Gtk.PositionType.RIGHT:
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, true);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, false);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, false);

				int right_panel_offset = 0;
				if (monitor != null) {
					var work = monitor.get_workarea ();
					int right_panel = int.max (0, (geo.x + geo.width) - (work.x + work.width));
					if (right_panel > 0)
						right_panel_offset = right_panel + 2;
				}
				GtkLayerShell.set_margin (window, GtkLayerShell.Edge.RIGHT, right_margin_total (edge_margin, right_panel_offset));
				GtkLayerShell.set_margin (window, GtkLayerShell.Edge.TOP, clamped_y);
				break;
			}
		}

		static int right_margin_total (int edge_margin, int right_panel_offset)
		{
			return edge_margin + right_panel_offset;
		}

		public void sync_popup_after_show (Gtk.Window window, PopupSurfaceKind kind,
			Gdk.Monitor? monitor, Gtk.PositionType dock_edge, int center_x, int center_y,
			int visual_thickness, int gap)
		{
			if (GtkLayerShell.is_supported ())
				return;

			var state = window.get_data<PopupSyncState> ("wayplank-popup-sync");
			if (state == null) {
				state = new PopupSyncState (this, window);
				window.set_data<PopupSyncState> ("wayplank-popup-sync", state);
			}
			if (!state.signals_hooked) {
				state.signals_hooked = true;
				window.hide.connect (state.cancel);
				window.unmap.connect (state.cancel);
				window.destroy.connect (state.cancel);
			}
			state.cancel ();
			state.mon_ref.set (monitor);
			state.kind = kind;
			state.dock_edge = dock_edge;
			state.center_x = center_x;
			state.center_y = center_y;
			state.visual_thickness = visual_thickness;
			state.gap = gap;
			state.timer_id = GLib.Timeout.add (25, state.on_sync_tick);
		}

		public void cancel_popup_sync (Gtk.Window window)
		{
			var state = window.get_data<PopupSyncState> ("wayplank-popup-sync");
			if (state != null)
				state.cancel ();
		}

		public void begin_drag_pointer_grab (Gtk.Window window, Gdk.DragContext context)
		{
			if (!GtkLayerShell.is_supported ()) {
				context.get_device ().get_seat ().grab (window.get_window (), Gdk.SeatCapabilities.POINTER, true,
					null, null, null);
			}
		}

		public void end_drag_pointer_grab (Gdk.DragContext context)
		{
			if (!GtkLayerShell.is_supported ())
				context.get_device ().get_seat ().ungrab ();
		}

		public void place_transient_overlay (Gtk.Window window, Gdk.Monitor? monitor,
			Gtk.PositionType dock_edge, int along_coord, int perp_from_dock_base,
			int surf_w, int surf_h, bool reserve_space_active, int dock_exclusive_thickness,
			out double canvas_cx, out double canvas_cy)
		{
			SurfaceCoordinateService.place_dock_overlay (
				window, monitor, dock_edge, along_coord, perp_from_dock_base,
				surf_w, surf_h, reserve_space_active, dock_exclusive_thickness,
				out canvas_cx, out canvas_cy
			);
		}

		public bool get_primary_monitor_geometry (out int x, out int y, out int width, out int height)
		{
			return WindowControl.get_primary_monitor_geometry (out x, out y, out width, out height);
		}

		public Gdk.Rectangle get_effective_monitor_geometry (Gdk.Monitor? monitor)
		{
			if (monitor == null)
				return Gdk.Rectangle ();

			if (GtkLayerShell.is_supported ())
				return monitor.get_geometry ();

			var geom = monitor.get_geometry ();
			Gdk.Rectangle wa;
			if (WindowControl.get_workarea_for_geometry (geom, out wa)) {
				debug ("Wayplank: using Mutter workarea %d,%d %dx%d (monitor geom was %d,%d %dx%d)",
					wa.x, wa.y, wa.width, wa.height, geom.x, geom.y, geom.width, geom.height);
				return wa;
			}

			return monitor.get_workarea ();
		}

		public int get_top_panel_floating_offset (Gdk.Rectangle mon_geom = Gdk.Rectangle ())
		{
			return WindowControl.get_top_panel_floating_offset (mon_geom);
		}

		public void invalidate_panel_cache ()
		{
			WindowControl.invalidate_panel_cache ();
		}
	}
}
