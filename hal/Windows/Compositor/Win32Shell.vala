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
	 * Native Windows (Win32) implementation of `IDockShell`.
	 * Configures borderless always-on-top tool windows (`WS_EX_TOOLWINDOW |
	 * WS_EX_NOACTIVATE | WS_EX_TOPMOST`), subclasses `WM_NCHITTEST` for
	 * pixel-accurate `HTTRANSPARENT` click-through outside `Cairo.Region`,
	 * reserves desktop edges via 3-way idempotent `SHAppBarMessage` struts,
	 * and positions tooltips/folder menus/preview cards/poof overlays cleanly
	 * relative to the active monitor and dock edge.
	 */
	public class Win32Shell : GLib.Object, IDockShell
	{
		static bool ui_theme_installed = false;
		static bool deactivate_hooked = false;

		Gee.HashSet<Gdk.Window> tracked_appbar_windows = new Gee.HashSet<Gdk.Window> ();

		static void on_app_deactivated ()
		{
			foreach (unowned Gtk.Window win in Gtk.Window.list_toplevels ()) {
				if (win == null || !win.get_visible ())
					continue;
				var child = win.get_child ();
				if (child is Gtk.Menu) {
					((Gtk.Menu) child).popdown ();
				}
			}
		}

		public static void ensure_win32_ui_icons_and_css ()
		{
			if (ui_theme_installed)
				return;
			ui_theme_installed = true;

			/* Mount embedded GResource hicolor icon theme BEFORE any GTK window or
			 * Gtk.Window.set_default_icon_name("wayplank") lookup, eliminating the
			 * "Could not find the icon 'wayplank' / 'hicolor' theme not found" warning
			 * and providing scalable vector docklet, UI & widget symbolic icons above
			 * GTK3's legacy 24px PNGs with zero deprecated add_builtin_icon() calls. */
			var default_theme = Gtk.IconTheme.get_default ();
			if (default_theme != null)
				default_theme.add_resource_path (Plank.G_RESOURCE_PATH + "/icons");

			var screen = Gdk.Screen.get_default ();
			if (screen == null)
				return;

			var css = new Gtk.CssProvider ();
			try {
				css.load_from_data ("""
					check,
					menuitem check {
						min-width: 14px;
						min-height: 14px;
						border: 1px solid rgba(128, 128, 128, 0.70);
						border-radius: 3px;
						background-color: transparent;
						background-image: none;
						-gtk-icon-source: none;
					}
					check:checked,
					menuitem check:checked {
						background-color: #3584e4;
						border-color: #3584e4;
						color: #ffffff;
						-gtk-icon-source: -gtk-icontheme("check-active-symbolic");
					}
					check:indeterminate,
					menuitem check:indeterminate {
						background-color: #3584e4;
						border-color: #3584e4;
						color: #ffffff;
						-gtk-icon-source: -gtk-icontheme("check-mixed-symbolic");
					}
					radio,
					menuitem radio {
						min-width: 14px;
						min-height: 14px;
						border: 1px solid rgba(128, 128, 128, 0.70);
						border-radius: 999px;
						background-color: transparent;
						background-image: none;
						-gtk-icon-source: none;
					}
					radio:checked,
					menuitem radio:checked {
						background-color: #3584e4;
						border-color: #3584e4;
						color: #ffffff;
						-gtk-icon-source: -gtk-icontheme("radio-checked-symbolic");
					}
					menuitem arrow {
						min-width: 14px;
						min-height: 14px;
						-gtk-icon-source: -gtk-icontheme("pan-end-symbolic");
					}
				""");
				Gtk.StyleContext.add_provider_for_screen (screen, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
			} catch (Error e) {
				warning ("Win32Shell: failed to load Win32 checkbox CSS: %s", e.message);
			}
		}

		static int position_to_win32_edge (Gtk.PositionType pos)
		{
			switch (pos) {
			case Gtk.PositionType.LEFT:
				return Win32Bridge.EDGE_LEFT;
			case Gtk.PositionType.RIGHT:
				return Win32Bridge.EDGE_RIGHT;
			case Gtk.PositionType.TOP:
				return Win32Bridge.EDGE_TOP;
			default:
			case Gtk.PositionType.BOTTOM:
				return Win32Bridge.EDGE_BOTTOM;
			}
		}

		static void apply_win32_style (Gtk.Window window, bool is_popup, bool no_activate)
		{
			var gdk_win = window.get_window ();
			if (gdk_win != null) {
				Win32Bridge.configure_window (gdk_win, is_popup ? 1 : 0, no_activate ? 1 : 0);
				return;
			}

			/* Defer until first realize if called before GTK creates the HWND */
			if (window.get_data<bool> ("wayplank-win32-realize-hooked"))
				return;
			window.set_data<bool> ("wayplank-win32-realize-hooked", true);
			window.realize.connect (() => {
				var w = window.get_window ();
				if (w != null)
					Win32Bridge.configure_window (w, is_popup ? 1 : 0, no_activate ? 1 : 0);
			});
		}

		public void init_dock_surface (Gtk.Window window)
		{
			ensure_win32_ui_icons_and_css ();
			if (!deactivate_hooked) {
				deactivate_hooked = true;
				Win32Bridge.set_deactivate_callback (on_app_deactivated);
			}
			window.set_decorated (false);
			window.set_type_hint (Gdk.WindowTypeHint.DOCK);
			window.set_skip_taskbar_hint (true);
			window.set_skip_pager_hint (true);
			window.set_keep_above (true);
			window.set_focus_on_map (false);
			window.set_title ("wayplank");
			window.set_role ("dock");
			apply_win32_style (window, false, false);
		}

		public void init_popup_surface (Gtk.Window window, PopupSurfaceKind kind)
		{
			window.set_decorated (false);
			window.set_skip_taskbar_hint (true);
			window.set_skip_pager_hint (true);
			window.set_keep_above (true);
			window.set_focus_on_map (false);

			bool no_activate = (kind == PopupSurfaceKind.TOOLTIP || kind == PopupSurfaceKind.POOF_ANIMATION);
			if (no_activate)
				window.set_accept_focus (false);

			switch (kind) {
			case PopupSurfaceKind.FOLDER_MENU:
				window.set_title ("wayplank-folder-menu");
				window.set_type_hint (Gdk.WindowTypeHint.POPUP_MENU);
				break;
			case PopupSurfaceKind.PREVIEW_CARDS:
				window.set_title ("wayplank-hover-cards");
				window.set_type_hint (Gdk.WindowTypeHint.POPUP_MENU);
				break;
			case PopupSurfaceKind.POOF_ANIMATION:
				window.set_title ("wayplank-poof");
				window.set_type_hint (Gdk.WindowTypeHint.UTILITY);
				break;
			default:
			case PopupSurfaceKind.TOOLTIP:
				window.set_title ("wayplank-hover");
				window.set_type_hint (Gdk.WindowTypeHint.POPUP_MENU);
				break;
			}

			apply_win32_style (window, true, no_activate);
			window.hide.connect (() => {
				window.set_data<int> ("wp-win32-pw", 0);
			});
		}

		public bool set_surface_monitor (Gtk.Window window, Gdk.Monitor? monitor)
		{
			return false;
		}

		public void sync_dock_monitor (Gtk.Window window, Gdk.Monitor? monitor,
			out bool monitor_switched, out bool requires_geometry_refresh)
		{
			if (monitor == null) {
				monitor_switched = false;
				requires_geometry_refresh = false;
				return;
			}

			uint32 topo_gen = Win32Bridge.get_topology_gen ();
			Gdk.Rectangle work = monitor.get_workarea ();
			int sf = int.max (1, monitor.get_scale_factor ());

			Gdk.Monitor? prev_mon = window.get_data<Gdk.Monitor?> ("wp-win32-mon");
			uint32 prev_gen = (uint32) window.get_data<int> ("wp-win32-topogen");
			int prev_wx = window.get_data<int> ("wp-win32-mwx");
			int prev_wy = window.get_data<int> ("wp-win32-mwy");
			int prev_ww = window.get_data<int> ("wp-win32-mww");
			int prev_wh = window.get_data<int> ("wp-win32-mwh");
			int prev_sf = window.get_data<int> ("wp-win32-msf");

			bool changed = (prev_mon != monitor
				|| prev_gen != topo_gen
				|| prev_wx != work.x
				|| prev_wy != work.y
				|| prev_ww != work.width
				|| prev_wh != work.height
				|| prev_sf != sf);

			if (!changed) {
				monitor_switched = false;
				requires_geometry_refresh = false;
				return;
			}

			/* Invalidate per-window cached GDK geometry & AppBar strut only on real
			 * monitor/workarea/DPI/topology changes (including primary-display swaps). */
			window.set_data<int> ("wp-win32-lw", 0);
			window.set_data<int> ("wp-win32-lh", 0);
			window.set_data<bool> ("wp-win32-strut-init", false);
			window.set_data<Gdk.Monitor?> ("wp-win32-mon", monitor);
			window.set_data<int> ("wp-win32-topogen", (int) topo_gen);
			window.set_data<int> ("wp-win32-mwx", work.x);
			window.set_data<int> ("wp-win32-mwy", work.y);
			window.set_data<int> ("wp-win32-mww", work.width);
			window.set_data<int> ("wp-win32-mwh", work.height);
			window.set_data<int> ("wp-win32-msf", sf);
			monitor_switched = true;
			requires_geometry_refresh = true;
		}

		public bool update_dock_anchors (Gtk.Window window, Gdk.Monitor? monitor, Gtk.PositionType position)
		{
			if (monitor != null)
				window.set_data<Gdk.Monitor?> ("wp-win32-mon", monitor);
			return false;
		}

		public void handle_compositor_state_changed (Gtk.Window window, Gdk.Monitor? monitor,
			Gtk.PositionType position, out bool requires_geometry_refresh)
		{
			requires_geometry_refresh = !window.get_visible ();
		}

		public void update_exclusive_zone (Gtk.Window window, bool enabled, int thickness, Gtk.PositionType position)
		{
			/* Per-window 3-way idempotence guard (Pitfall #10 + Multi-Dock dock1..dock4 isolation) */
			bool inited = window.get_data<bool> ("wp-win32-strut-init");
			bool last_en = window.get_data<bool> ("wp-win32-strut-en");
			int last_th = window.get_data<int> ("wp-win32-strut-th");
			int last_pos = window.get_data<int> ("wp-win32-strut-pos");
			if (inited
				&& enabled == last_en
				&& thickness == last_th
				&& (int) position == last_pos) {
				return;
			}

			var gdk_win = window.get_window ();
			if (gdk_win == null)
				return;

			var display = window.get_display ();
			Gdk.Monitor? mon = window.get_data<Gdk.Monitor?> ("wp-win32-mon");
			if (mon == null && display != null)
				mon = display.get_monitor_at_window (gdk_win);
			int sf = (mon != null) ? int.max (1, mon.get_scale_factor ()) : int.max (1, window.get_scale_factor ());
			Gdk.Rectangle geo = (mon != null) ? mon.get_geometry () : Gdk.Rectangle ();

			Win32Bridge.set_appbar_strut (
				gdk_win,
				enabled ? 1 : 0,
				position_to_win32_edge (position),
				thickness * sf,
				geo.x * sf,
				geo.y * sf,
				geo.width * sf,
				geo.height * sf
			);

			window.set_data<bool> ("wp-win32-strut-init", true);
			window.set_data<bool> ("wp-win32-strut-en", enabled);
			window.set_data<int> ("wp-win32-strut-th", thickness);
			window.set_data<int> ("wp-win32-strut-pos", (int) position);
			if (enabled)
				tracked_appbar_windows.add (gdk_win);
			else
				tracked_appbar_windows.remove (gdk_win);
		}

		public void commit_dock_geometry (Gtk.Window window, Gdk.Rectangle win_rect)
		{
			bool was_visible = window.get_visible ();
			int last_x = window.get_data<int> ("wp-win32-lx");
			int last_y = window.get_data<int> ("wp-win32-ly");
			int last_w = window.get_data<int> ("wp-win32-lw");
			int last_h = window.get_data<int> ("wp-win32-lh");
			bool geom_changed = (!was_visible || last_x != win_rect.x || last_y != win_rect.y
				|| last_w != win_rect.width || last_h != win_rect.height);

			if (geom_changed) {
				window.move (win_rect.x, win_rect.y);
				window.set_data<int> ("wp-win32-lx", win_rect.x);
				window.set_data<int> ("wp-win32-ly", win_rect.y);
				window.set_data<int> ("wp-win32-lw", win_rect.width);
				window.set_data<int> ("wp-win32-lh", win_rect.height);
			}

			if (!was_visible) {
				if (!window.get_realized ())
					window.realize ();
				var pre_gdk = window.get_window ();
				if (pre_gdk != null) {
					window.set_data<bool> ("wp-win32-styled", true);
					Win32Bridge.configure_window (pre_gdk, 0, 0);
				}
				window.show_all ();
				window.stick ();
			}

			var gdk_win = window.get_window ();
			if (gdk_win != null) {
				if (!was_visible || !window.get_data<bool> ("wp-win32-styled")) {
					window.set_data<bool> ("wp-win32-styled", true);
					Win32Bridge.configure_window (gdk_win, 0, 0);
				}
				if (geom_changed) {
					Win32Bridge.move_topmost (
						gdk_win,
						win_rect.x,
						win_rect.y,
						win_rect.width,
						win_rect.height,
						int.max (1, window.get_scale_factor ())
					);
				}
			}
			window.queue_draw ();
		}

		public void present_dock_after_show (Gtk.Window window)
		{
			var gdk_win = window.get_window ();
			if (gdk_win != null)
				Win32Bridge.configure_window (gdk_win, 0, 0);
		}

		public void apply_input_region (Gtk.Window window, Cairo.Region? region)
		{
			var gdk_win = window.get_window ();
			if (gdk_win == null)
				return;

			if (region == null) {
				/* Disable custom hit-test mask */
				Win32Bridge.set_input_rects (gdk_win, 0, null, 0);
				return;
			}

			int n = region.num_rectangles ();
			if (n <= 0) {
				/* Active empty region: 100% click-through (e.g. Fullscreen Inhibit) */
				Win32Bridge.set_input_rects (gdk_win, 1, null, 0);
				return;
			}

			int sf = int.max (1, window.get_scale_factor ());
			int[] packed = new int[n * 4];
			for (int i = 0; i < n; i++) {
				var r = region.get_rectangle (i);
				packed[i * 4 + 0] = r.x * sf;
				packed[i * 4 + 1] = r.y * sf;
				packed[i * 4 + 2] = r.width * sf;
				packed[i * 4 + 3] = r.height * sf;
			}
			Win32Bridge.set_input_rects (gdk_win, 1, packed, n);
		}

		public void resolve_tooltip_anchor (bool is_horizontal, int icon_size,
			Gdk.Point dynamic_center, Gdk.Point static_center, out int x, out int y)
		{
			x = dynamic_center.x;
			y = dynamic_center.y;
		}

		public int resolve_tooltip_dock_thickness (int visual_thickness, int dock_window_span)
		{
			return visual_thickness + 40;
		}

		public void position_popup_surface (Gtk.Window window, PopupSurfaceKind kind,
			Gdk.Monitor? monitor, Gtk.PositionType dock_edge, int center_x, int center_y,
			int width, int height, int visual_thickness, int gap)
		{
			Gdk.Rectangle area = get_effective_monitor_geometry (monitor);
			int mon_x = area.x;
			int mon_y = area.y;
			int mon_w = area.width > 0 ? area.width : 1920;
			int mon_h = area.height > 0 ? area.height : 1080;

			int target_x = mon_x + center_x - width / 2;
			int target_y = mon_y + center_y - height / 2;

			switch (dock_edge) {
			default:
			case Gtk.PositionType.BOTTOM:
				target_y = mon_y + mon_h - visual_thickness - gap - height;
				break;
			case Gtk.PositionType.TOP:
				target_y = mon_y + visual_thickness + gap;
				break;
			case Gtk.PositionType.LEFT:
				target_x = mon_x + visual_thickness + gap;
				target_y = mon_y + center_y - height / 2;
				break;
			case Gtk.PositionType.RIGHT:
				target_x = mon_x + mon_w - visual_thickness - gap - width;
				target_y = mon_y + center_y - height / 2;
				break;
			}

			int abs_x = int.max (mon_x + gap, int.min (mon_x + mon_w - width - gap, target_x));
			int abs_y = int.max (mon_y + gap, int.min (mon_y + mon_h - height - gap, target_y));
			int sf = (monitor != null) ? int.max (1, monitor.get_scale_factor ()) : int.max (1, window.get_scale_factor ());
			uint32 topo_gen = Win32Bridge.get_topology_gen ();

			if (window.get_visible ()
				&& window.get_data<int> ("wp-win32-px") == abs_x
				&& window.get_data<int> ("wp-win32-py") == abs_y
				&& window.get_data<int> ("wp-win32-pw") == width
				&& window.get_data<int> ("wp-win32-ph") == height
				&& window.get_data<int> ("wp-win32-psf") == sf
				&& (uint32) window.get_data<int> ("wp-win32-pgen") == topo_gen) {
				return;
			}

			window.set_data<int> ("wp-win32-px", abs_x);
			window.set_data<int> ("wp-win32-py", abs_y);
			window.set_data<int> ("wp-win32-pw", width);
			window.set_data<int> ("wp-win32-ph", height);
			window.set_data<int> ("wp-win32-psf", sf);
			window.set_data<int> ("wp-win32-pgen", (int) topo_gen);
			window.move (abs_x, abs_y);

			var gdk_win = window.get_window ();
			if (gdk_win != null) {
				Win32Bridge.move_topmost (
					gdk_win,
					abs_x,
					abs_y,
					width,
					height,
					sf
				);
			}
		}

		public void sync_popup_after_show (Gtk.Window window, PopupSurfaceKind kind,
			Gdk.Monitor? monitor, Gtk.PositionType dock_edge, int center_x, int center_y,
			int visual_thickness, int gap)
		{
			var gdk_win = window.get_window ();
			if (gdk_win != null && !window.get_data<bool> ("wp-win32-styled")) {
				window.set_data<bool> ("wp-win32-styled", true);
				bool no_activate = (kind == PopupSurfaceKind.TOOLTIP || kind == PopupSurfaceKind.POOF_ANIMATION);
				Win32Bridge.configure_window (gdk_win, 1, no_activate ? 1 : 0);
			}
			int w = 0, h = 0;
			window.get_size (out w, out h);
			if (w > 0 && h > 0)
				position_popup_surface (window, kind, monitor, dock_edge, center_x, center_y, w, h, visual_thickness, gap);
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

			Gdk.Rectangle area = get_effective_monitor_geometry (monitor);
			int wx = area.x;
			int wy = area.y;

			switch (dock_edge) {
			default:
			case Gtk.PositionType.BOTTOM:
				wx = area.x + along_coord - surf_w / 2;
				wy = area.y + area.height - perp_from_dock_base - surf_h / 2;
				break;
			case Gtk.PositionType.TOP:
				wx = area.x + along_coord - surf_w / 2;
				wy = area.y + perp_from_dock_base - surf_h / 2;
				break;
			case Gtk.PositionType.LEFT:
				wx = area.x + perp_from_dock_base - surf_w / 2;
				wy = area.y + along_coord - surf_h / 2;
				break;
			case Gtk.PositionType.RIGHT:
				wx = area.x + area.width - perp_from_dock_base - surf_w / 2;
				wy = area.y + along_coord - surf_h / 2;
				break;
			}

			window.set_size_request (surf_w, surf_h);
			window.move (wx, wy);
			window.show ();

			var gdk_win = window.get_window ();
			if (gdk_win != null) {
				int sf = (monitor != null) ? int.max (1, monitor.get_scale_factor ()) : int.max (1, window.get_scale_factor ());
				Win32Bridge.configure_window (gdk_win, 1, 1);
				Win32Bridge.set_input_rects (gdk_win, 1, null, 0);
				Win32Bridge.move_topmost (gdk_win, wx, wy, surf_w, surf_h, sf);
			}
		}

		public bool get_primary_monitor_geometry (out int x, out int y, out int width, out int height)
		{
			return Win32Bridge.get_primary_monitor_rect (out x, out y, out width, out height) != 0;
		}

		public Gdk.Rectangle get_effective_monitor_geometry (Gdk.Monitor? monitor)
		{
			if (monitor != null)
				return monitor.get_workarea ();
			var display = Gdk.Display.get_default ();
			var primary = (display != null) ? display.get_primary_monitor () : null;
			if (primary != null)
				return primary.get_workarea ();
			return Gdk.Rectangle ();
		}

		public int get_top_panel_floating_offset (Gdk.Rectangle mon_geom = Gdk.Rectangle ())
		{
			return 0;
		}

		public void invalidate_panel_cache ()
		{
		}

		public void cleanup ()
		{
			if (deactivate_hooked) {
				Win32Bridge.set_deactivate_callback (null);
				deactivate_hooked = false;
			}
			foreach (var gw in tracked_appbar_windows) {
				if (gw != null && !gw.is_destroyed ())
					Win32Bridge.remove_appbar_strut (gw);
			}
			tracked_appbar_windows.clear ();
		}
	}
}
