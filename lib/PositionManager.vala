//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//  Copyright (C) 2026 史有虎 (IFtiger-hu)
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
	public class PositionManager : GLib.Object
	{
		public DockController controller { private get; construct; }
		
		public bool screen_is_composited { get; private set; }
		
		Gdk.Rectangle static_dock_region;
		Gee.HashMap<DockElement, DockItemDrawValue> draw_values;
		
		Gdk.Rectangle monitor_geo;
		
		int window_scale_factor = 1;
		
		public PositionManager (DockController controller)
		{
			GLib.Object (controller : controller);
		}
		
		construct
		{
			static_dock_region = {};
			draw_values = new Gee.HashMap<DockElement, DockItemDrawValue> ();
		}
		
		public void initialize ()
			requires (controller.window != null)
		{
			unowned Gdk.Screen screen = controller.window.get_screen ();
			
			controller.prefs.notify.connect (prefs_changed);
			screen.monitors_changed.connect (on_screen_topology_changed);
			screen.size_changed.connect (on_screen_topology_changed);
			screen.composited_changed.connect (screen_composited_changed);
			WindowControl.get_default ().primary_monitor_changed.connect (prefs_monitor_changed);
			
			var monitor = get_monitor_for_plug_name (screen.get_display (), controller.prefs.Monitor);
			monitor_geo = get_effective_monitor_geometry (monitor);
			
			screen_is_composited = screen.is_composited ();
		}
		
		~PositionManager ()
		{
			if (screen_topology_timer_id != 0U) {
				Source.remove (screen_topology_timer_id);
				screen_topology_timer_id = 0U;
			}

			WindowControl.get_default ().primary_monitor_changed.disconnect (prefs_monitor_changed);
			
			if (controller != null) {
				controller.prefs.notify.disconnect (prefs_changed);
				if (controller.window != null) {
					unowned Gdk.Screen screen = controller.window.get_screen ();
					if (screen != null) {
						screen.monitors_changed.disconnect (on_screen_topology_changed);
						screen.size_changed.disconnect (on_screen_topology_changed);
						screen.composited_changed.disconnect (screen_composited_changed);
					}
				}
			}
			
			draw_values.clear ();
		}
		
		void prefs_changed (Object prefs, ParamSpec prop)
		{
			switch (prop.name) {
			case "Monitor":
				prefs_monitor_changed ();
				break;
			case "IconSize":
			case "ScrollOverflow":
				update (controller.renderer.theme);
				break;
			case "ZoomPercent":
			case "ZoomEnabled":
			case "AnticipateZoom":
				prefs_zoom_changed ();
				break;
			default:
				break;
			}
		}
		
		public static string[] get_monitor_plug_names (Gdk.Display display)
		{
			int n_monitors = display.get_n_monitors ();
			var result = new string[n_monitors];
			
			// 1. Count occurrences to detect identical monitor models
			var model_counts = new Gee.HashMap<string, int> ();
			for (int i = 0; i < n_monitors; i++) {
				var monitor = display.get_monitor (i);
				var model = (monitor != null && monitor.get_model () != null && monitor.get_model () != "")
					? monitor.get_model () : "Monitor";
				model_counts.set (model, model_counts.has_key (model) ? model_counts.get (model) + 1 : 1);
			}

			// 2. Assign unique, human-readable labels with geometry
			var seen_counts = new Gee.HashMap<string, int> ();
			for (int i = 0; i < n_monitors; i++) {
				var monitor = display.get_monitor (i);
				var model = (monitor != null && monitor.get_model () != null && monitor.get_model () != "")
					? monitor.get_model () : "Monitor";
				var geom = monitor != null ? monitor.get_geometry () : Gdk.Rectangle ();
				
				if (model_counts.get (model) > 1) {
					int count = seen_counts.has_key (model) ? seen_counts.get (model) + 1 : 1;
					seen_counts.set (model, count);
					result[i] = "%s (%d) [%dx%d @ %d,%d]".printf (model, count, geom.width, geom.height, geom.x, geom.y);
				} else {
					result[i] = "%s [%dx%d @ %d,%d]".printf (model, geom.width, geom.height, geom.x, geom.y);
				}
			}
			
			return result;
		}
		
		public static Gdk.Monitor? get_monitor_for_plug_name (Gdk.Display display, string plug_name)
		{
			if (plug_name == "" || plug_name == "primary") {
				var primary = display.get_primary_monitor ();
				if (primary != null)
					return primary;

				int px, py, pw, ph;
				if (WindowControl.get_primary_monitor_geometry (out px, out py, out pw, out ph)) {
					for (int i = 0; i < display.get_n_monitors (); i++) {
						var mon = display.get_monitor (i);
						var geom = mon.get_geometry ();
						if (geom.x == px && geom.y == py && (pw == 0 || (geom.width == pw && geom.height == ph)))
							return mon;
					}
				}

				// Fallback: look for monitor whose origin is at (0, 0)
				for (int i = 0; i < display.get_n_monitors (); i++) {
					var mon = display.get_monitor (i);
					var geom = mon.get_geometry ();
					if (geom.x == 0 && geom.y == 0)
						return mon;
				}

				if (display.get_n_monitors () > 0)
					return display.get_monitor (0);

				return null;
			}

			var names = get_monitor_plug_names (display);
			int n_monitors = display.get_n_monitors ();
			
			// 1. Exact match with generated unique name (e.g. "DELL P2219H (1) [1920x1080 @ 0,0]")
			for (int i = 0; i < n_monitors; i++) {
				if (plug_name == names[i])
					return display.get_monitor (i);
			}

			// 2. Geometry coordinate match from string "[... @ X,Y]"
			// In multi-monitor setups (especially with identical monitor models),
			// coordinates in compositor space are the most reliable anchor, since
			// synthetic indices like (1), (2) can fluctuate upon sleep/wake.
			if (plug_name.contains ("@")) {
				int at_idx = plug_name.index_of ("@");
				int end_idx = plug_name.index_of ("]", at_idx);
				if (at_idx >= 0 && end_idx > at_idx) {
					var coord_str = plug_name.substring (at_idx + 1, end_idx - at_idx - 1).strip ();
					var parts = coord_str.split (",");
					if (parts.length == 2) {
						int target_x = int.parse (parts[0].strip ());
						int target_y = int.parse (parts[1].strip ());
						for (int i = 0; i < n_monitors; i++) {
							var geom = display.get_monitor (i).get_geometry ();
							if (geom.x == target_x && geom.y == target_y)
								return display.get_monitor (i);
						}
					}
				}
			}

			// 3. Stable Label match ignoring volatile resolution/coordinates (e.g. "DELL P2219H (1)" or "eDP-1-0x0B58")
			// This preserves monitor assignment across fractional scaling, DPI changes, and resolution switches.
			string plug_label = plug_name;
			if (plug_label.contains ("[")) {
				plug_label = plug_label.split ("[")[0].strip ();
			}
			if (plug_label != "") {
				for (int i = 0; i < n_monitors; i++) {
					string cur_label = names[i];
					if (cur_label.contains ("["))
						cur_label = cur_label.split ("[")[0].strip ();
					if (plug_label == cur_label)
						return display.get_monitor (i);
				}
			}

			// 4. Match numeric index "X" or legacy "PLUG_MONITOR_X"
			for (int i = 0; i < n_monitors; i++) {
				var fallback = "PLUG_MONITOR_%i".printf (i);
				if (plug_name == fallback || plug_name == i.to_string ())
					return display.get_monitor (i);
			}

			// 5. Fallback to matching raw model prefix or name (only if no coordinates were specified)
			if (!plug_name.contains ("@")) {
				for (int i = 0; i < n_monitors; i++) {
					var monitor = display.get_monitor (i);
					if (monitor != null) {
						var m = monitor.get_model ();
						if (m != null && m != "" && (plug_name == m || plug_name.has_prefix (m)))
							return monitor;
					}
				}
			}
			
			return get_monitor_for_plug_name (display, "");
		}
		
		void prefs_monitor_changed ()
		{
			if (controller != null && controller.window != null)
				screen_changed (controller.window.get_screen ());
		}

		weak Gdk.Monitor? current_monitor = null;

		Gdk.Rectangle get_effective_monitor_geometry (Gdk.Monitor? monitor)
		{
			if (monitor == null)
				return Gdk.Rectangle ();

			if (GtkLayerShell.is_supported ())
				return monitor.get_geometry ();

			var geom = monitor.get_geometry ();
			Gdk.Rectangle wa;
			if (WindowControl.get_workarea_for_geometry (geom, out wa)) {
				message ("Wayplank: using Mutter workarea %d,%d %dx%d (monitor geom was %d,%d %dx%d)",
					wa.x, wa.y, wa.width, wa.height, geom.x, geom.y, geom.width, geom.height);
				return wa;
			}

			message ("Wayplank: fallback to monitor.get_workarea() %d,%d %dx%d",
				monitor.get_workarea ().x, monitor.get_workarea ().y, monitor.get_workarea ().width, monitor.get_workarea ().height);
			return monitor.get_workarea ();
		}

		uint screen_topology_timer_id = 0U;

		void on_screen_topology_changed (Gdk.Screen screen)
		{
			if (screen_topology_timer_id != 0U) {
				Source.remove (screen_topology_timer_id);
				screen_topology_timer_id = 0U;
			}

			// Debounce monitor/size reconfiguration storms (e.g. sleep/wake or hotplug)
			screen_topology_timer_id = Timeout.add (250, () => {
				screen_topology_timer_id = 0U;
				screen_changed (screen);
				return Source.REMOVE;
			});
		}

		bool updating_screen = false;

		void screen_changed (Gdk.Screen screen)
		{
			if (updating_screen)
				return;
			updating_screen = true;

			var old_monitor_geo = monitor_geo;
			var monitor = get_monitor_for_plug_name (screen.get_display (), controller.prefs.Monitor);
			monitor_geo = get_effective_monitor_geometry (monitor);
			bool monitor_changed = (monitor != current_monitor);
			current_monitor = monitor;

			if (!monitor_changed
				&& old_monitor_geo.x == monitor_geo.x
				&& old_monitor_geo.y == monitor_geo.y
				&& old_monitor_geo.width == monitor_geo.width
				&& old_monitor_geo.height == monitor_geo.height) {
				updating_screen = false;
				return;
			}
			
			Logger.verbose ("PositionManager.monitor_geo_changed (%i,%i-%ix%i)",
				monitor_geo.x, monitor_geo.y, monitor_geo.width, monitor_geo.height);
			
			freeze_notify ();
			
			controller.window.update_layer_shell_monitor ();

			if (controller.renderer != null && controller.renderer.theme != null) {
				update (controller.renderer.theme);
			} else {
				update_dimensions ();
				update_regions ();
			}

			controller.window.update_size_and_position ();
			
			thaw_notify ();
			updating_screen = false;
		}
		
		void screen_composited_changed (Gdk.Screen screen)
		{
			freeze_notify ();
			
			screen_is_composited = screen.is_composited ();
			
			update (controller.renderer.theme);
			
			thaw_notify ();
		}
		
		public int LineWidth { get; private set; }
		public int IconSize { get; private set; }
		public int ZoomIconSize { get; private set; }
		public Gtk.PositionType Position { get; private set; }
		public Gtk.Align Alignment { get; private set; }
		public Gtk.Align ItemsAlignment { get; private set; }
		public int Offset { get; private set; }
		public int IndicatorSize { get; private set; }
		public int IconShadowSize { get; private set; }
		public int GlowSize { get; private set; }
		public int HorizPadding  { get; private set; }
		public int TopPadding    { get; private set; }
		public int BottomPadding { get; private set; }
		public int ItemPadding   { get; private set; }
		public int UrgentBounceHeight { get; private set; }
		public int LaunchBounceHeight { get; private set; }
		public int ReverseRoundness { get; private set; }
		public int TopRoundness { get; private set; }
		public int BottomRoundness { get; private set; }
		
		int items_width;
		int items_offset;
		int top_offset;
		int bottom_offset;
		int extra_hide_offset;
		
		int win_x;
		int win_y;

		public int VisibleDockHeight;
		public int DockHeight;
		public int DockBackgroundHeight;
		
		public int VisibleDockWidth;
		public int DockWidth;
		public int DockBackgroundWidth;
		
		double ZoomPercent;
		
		Gdk.Rectangle background_rect;
		
		public int MaxItemCount { get; private set; }
		public int MaxIconSize { get; private set; default = DockPreferences.MAX_ICON_SIZE; }

		// =========================================================================
		// Dock Overflow Smooth Scrolling (Fork Integration by 史有虎 / IFtiger-hu)
		// =========================================================================
		public double scroll_offset { get; set; default = 0.0; }
		public double target_scroll_offset { get; set; default = 0.0; }
		public double max_scroll_offset { get; private set; default = 0.0; }

		public bool is_scrolling ()
		{
			return (max_scroll_offset > 0.0 && Math.fabs (target_scroll_offset - scroll_offset) > 0.5);
		}

		public void scroll_by (double delta)
		{
			if (max_scroll_offset <= 0.0)
				return;

			target_scroll_offset = (target_scroll_offset + delta).clamp (0.0, max_scroll_offset);
			controller.renderer.animated_draw ();
		}

		public void ensure_item_visible (DockItem? item)
		{
			if (item == null || max_scroll_offset <= 0.0)
				return;

			if (!draw_values.has_key (item))
				return;

			var val = draw_values[item];
			if (val == null)
				return;

			double cx = is_horizontal_dock () ? val.static_center.x : val.static_center.y;
			double slot = get_item_slot (item);
			double left = cx - slot / 2.0;
			double right = cx + slot / 2.0;
			double vis_min = (double) items_offset;
			double vis_max = (double) ((is_horizontal_dock () ? DockWidth : DockHeight) - items_offset);

			if (left < vis_min)
				scroll_by (left - vis_min - 20.0);
			else if (right > vis_max)
				scroll_by (right - vis_max + 20.0);
		}
		
		public void update (DockTheme theme)
		{
			Logger.verbose ("PositionManager.update ()");
			
			screen_is_composited = controller.window.get_screen ().is_composited ();
			
			freeze_notify ();
			
			MaxIconSize = controller.prefs.IconSize;
			update_caches (theme);
			if (!controller.prefs.ScrollOverflow)
				update_max_icon_size (theme);
			update_dimensions ();
			update_regions ();
			
			thaw_notify ();
		}
		
		inline int get_reverse_roundness_padding (int rev_round, int bot_round)
		{
			if (rev_round > 0 && bot_round == 0)
				return int.max (8, (int) Math.round (rev_round * 0.75));
			return 0;
		}
		
		void update_caches (DockTheme theme)
		{
			unowned DockPreferences prefs = controller.prefs;
			
			Position = prefs.Position;
			Alignment = prefs.Alignment;
			ItemsAlignment = prefs.ItemsAlignment;
			Offset = prefs.Offset;
			
			if (Gtk.Widget.get_default_direction () == Gtk.TextDirection.RTL) {
				if (is_horizontal_dock ()) {
					if (Alignment == Gtk.Align.START)
						Alignment = Gtk.Align.END;
					else if (Alignment == Gtk.Align.END)
						Alignment = Gtk.Align.START;
					
					if (ItemsAlignment == Gtk.Align.START)
						ItemsAlignment = Gtk.Align.END;
					else if (ItemsAlignment == Gtk.Align.END)
						ItemsAlignment = Gtk.Align.START;
					
					Offset = -Offset;
				} else {
					if (Position == Gtk.PositionType.RIGHT)
						Position = Gtk.PositionType.LEFT;
					else
						Position = Gtk.PositionType.RIGHT;
				}
			}
			
			IconSize = int.min (MaxIconSize, prefs.IconSize);
			ZoomPercent = (screen_is_composited ? prefs.ZoomPercent / 100.0 : 1.0);
			ZoomIconSize = (screen_is_composited && prefs.ZoomEnabled ? (int) Math.round (IconSize * ZoomPercent) : IconSize);
			
			var scaled_icon_size = IconSize / 10.0;
			
			IconShadowSize = (int) Math.ceil (theme.IconShadowSize * scaled_icon_size);
			IndicatorSize = (int) (theme.IndicatorSize * scaled_icon_size);
			GlowSize      = (int) (theme.GlowSize      * scaled_icon_size);
			HorizPadding  = (int) (theme.HorizPadding  * scaled_icon_size);
			TopPadding    = (int) (theme.TopPadding    * scaled_icon_size);
			BottomPadding = (int) (theme.BottomPadding * scaled_icon_size);
			ItemPadding   = (int) (theme.ItemPadding   * scaled_icon_size);
			UrgentBounceHeight = (int) (theme.UrgentBounceHeight * IconSize);
			LaunchBounceHeight = (int) (theme.LaunchBounceHeight * IconSize);
			LineWidth     = theme.LineWidth;
			ReverseRoundness = theme.ReverseRoundness;
			TopRoundness  = theme.TopRoundness;
			BottomRoundness = theme.BottomRoundness;
			
			if (!screen_is_composited) {
				if (HorizPadding < 0)
					HorizPadding = (int) scaled_icon_size;
				if (TopPadding < 0)
					TopPadding = (int) scaled_icon_size;
			}
			
			var rev_padding = get_reverse_roundness_padding (ReverseRoundness, BottomRoundness);
			items_offset  = (int) (2 * LineWidth + (HorizPadding > 0 ? HorizPadding : 0) + rev_padding);
			
			top_offset = theme.get_top_offset () + TopPadding;
			bottom_offset = theme.get_bottom_offset () + BottomPadding;
			
			if (top_offset < 0)
				extra_hide_offset = IconShadowSize;
			else if (top_offset < IconShadowSize)
				extra_hide_offset = (IconShadowSize - top_offset);
			else
				extra_hide_offset = 0;
		}
		
		void prefs_zoom_changed ()
		{
			unowned DockPreferences prefs = controller.prefs;
			
			ZoomPercent = (screen_is_composited ? prefs.ZoomPercent / 100.0 : 1.0);
			ZoomIconSize = (screen_is_composited && prefs.ZoomEnabled ? (int) Math.round (IconSize * ZoomPercent) : IconSize);
			if (controller.window != null) {
				controller.window.set_input_mask ();
			}
		}
		
		void update_max_icon_size (DockTheme theme)
		{
			unowned DockPreferences prefs = controller.prefs;
			
			var max_width = (is_horizontal_dock () ? monitor_geo.width : monitor_geo.height);
			if (max_width <= 0) {
				MaxIconSize = prefs.IconSize;
				update_caches (theme);
				return;
			}
			
			var item_count = controller.VisibleItems.size;
			if (item_count == 0) {
				MaxIconSize = prefs.IconSize;
				update_caches (theme);
				return;
			}
			
			// CRITICAL LAYOUT WIDTH CONSISTENCY:
			// Must use get_items_total_span () instead of (item_count * slot_size) so that
			// variable-sized items (such as SeparatorDockItem) reflect true rendered span
			// matching update_dimensions (), avoiding premature icon shrinking.
			var rev_extra = 2 * get_reverse_roundness_padding (theme.ReverseRoundness, theme.BottomRoundness);
			var width = get_items_total_span () + 2 * HorizPadding + 4 * LineWidth + rev_extra;
			var step_size = int.max (1, (int) (Math.fabs (width - max_width) / item_count));
			
			if (width > max_width && MaxIconSize > DockPreferences.MIN_ICON_SIZE) {
				MaxIconSize -= step_size;
			// CRITICAL HYSTERESIS GUARD (DO NOT REMOVE OR MODIFY):
			// The condition 'step_size > 1' is strictly required to prevent infinite recursive
			// oscillation (stack overflow / SIGSEGV). When the dock length overflows by only a few pixels,
			// step_size collapses to 1. Since modifying an icon's size by 1px scales the total dock width
			// by (item_count * 1px) (e.g. 22px), removing this check causes an endless ping-pong loop
			// (+1px / -1px) between width > max_width and width < max_width.
			// When step_size reaches 1, the algorithm MUST break out to the 'else' termination branch.
			} else if (width < max_width && MaxIconSize < prefs.IconSize && step_size > 1) {
				MaxIconSize += step_size;
			} else {
				MaxIconSize = int.max (DockPreferences.MIN_ICON_SIZE,
					int.min (DockPreferences.MAX_ICON_SIZE, (int) (MaxIconSize / 2.0) * 2));
				Logger.verbose ("PositionManager.MaxIconSize = %i", MaxIconSize);
				update_caches (theme);
				return;
			}
			
			update_caches (theme);
			update_max_icon_size (theme);
		}
		
		int get_items_total_span ()
		{
			var sep_slot = (int) Math.round ((ItemPadding + IconSize) / 2.0);
			var total = 0;
			foreach (var item in controller.VisibleItems) {
				if (item is SeparatorDockItem)
					total += sep_slot;
				else
					total += (ItemPadding + IconSize);
			}
			return total;
		}

		double get_item_slot (DockItem item)
		{
			if (item is SeparatorDockItem)
				return Math.round ((ItemPadding + IconSize) / 2.0);
			return (double) (ItemPadding + IconSize);
		}

		public int get_max_screen_fit_icon_size ()
		{
			var max_width = (is_horizontal_dock () ? monitor_geo.width : monitor_geo.height);
			if (max_width <= 0)
				return DockPreferences.MAX_ICON_SIZE;
			
			var items = controller.VisibleItems;
			if (items.size == 0)
				return DockPreferences.MAX_ICON_SIZE;
			
			double eff_count = 0.0;
			foreach (var item in items) {
				if (item is SeparatorDockItem)
					eff_count += 0.5;
				else
					eff_count += 1.0;
			}
			
			if (eff_count <= 0.0)
				return DockPreferences.MAX_ICON_SIZE;
			
			double overhead = 2.0 * HorizPadding + 4.0 * LineWidth + eff_count * ItemPadding;
			double available_for_icons = (double) max_width - overhead;
			if (available_for_icons <= 0.0)
				return DockPreferences.MIN_ICON_SIZE;
			
			int fit_size = (int) Math.floor (available_for_icons / eff_count);
			fit_size = (fit_size / 2) * 2;
			return fit_size.clamp (DockPreferences.MIN_ICON_SIZE, DockPreferences.MAX_ICON_SIZE);
		}

		void update_dimensions ()
		{
			Logger.verbose ("PositionManager.update_dimensions ()");
			
			var height = IconSize + top_offset + bottom_offset;
			var background_height = int.max (0, height);
			
			if (top_offset < 0)
				height -= top_offset;
			
			var dock_height = height + (screen_is_composited ? UrgentBounceHeight : 0);
			
			var width = 0;
			switch (Alignment) {
			default:
			case Gtk.Align.START:
			case Gtk.Align.END:
			case Gtk.Align.CENTER:
				var rev_extra = 2 * get_reverse_roundness_padding (ReverseRoundness, BottomRoundness);
				width = get_items_total_span () + 2 * HorizPadding + 4 * LineWidth + rev_extra;
				break;
			case Gtk.Align.FILL:
				if (is_horizontal_dock ())
					width = monitor_geo.width;
				else
					width = monitor_geo.height;
				break;
			}
			
			var background_width = int.max (0, width);
			
			if (HorizPadding < 0)
				width -= 2 * HorizPadding;
			
			if (is_horizontal_dock ()) {
				width = int.min (monitor_geo.width, width);
				background_width = int.min (monitor_geo.width, background_width);
				VisibleDockHeight = height;
				VisibleDockWidth = width;
				DockHeight = dock_height;
				DockWidth = (screen_is_composited ? monitor_geo.width : width);
				DockBackgroundHeight = background_height;
				DockBackgroundWidth = background_width;
				MaxItemCount = (int) Math.floor ((double) (monitor_geo.width - 2 * HorizPadding + 4 * LineWidth) / (ItemPadding + IconSize));
			} else {
				width = int.min (monitor_geo.height, width);
				background_width = int.min (monitor_geo.height, background_width);
				VisibleDockHeight = width;
				VisibleDockWidth = height;
				DockHeight = (screen_is_composited ? monitor_geo.height : width);
				DockWidth = dock_height;
				DockBackgroundHeight = background_width;
				DockBackgroundWidth = background_height;
				MaxItemCount = (int) Math.floor ((double) (monitor_geo.height - 2 * HorizPadding + 4 * LineWidth) / (ItemPadding + IconSize));
			}
		}
		
		public bool is_horizontal_dock ()
		{
			return (Position == Gtk.PositionType.TOP || Position == Gtk.PositionType.BOTTOM);
		}
		
		public Gdk.Rectangle get_cursor_region ()
		{
			var cursor_region = static_dock_region;
			if (background_rect.width > 0 && background_rect.height > 0) {
				cursor_region.union (background_rect, out cursor_region);
			}
			var gdk_win = controller.window.get_window ();
			window_scale_factor = (gdk_win != null) ? gdk_win.get_scale_factor () : 1;
			
			if (controller.prefs.ZoomEnabled) {
				unowned DockItem? hovered_item = controller.window.HoveredItem;
				if (hovered_item != null) {
					var hover_region = get_hover_region_for_element (hovered_item);
					cursor_region.union (hover_region, out cursor_region);
				}
			}
			
			if (!controller.hide_manager.Hidden || controller.hide_manager.unhide_pending ()) {
				bool allow_anticipate = controller.prefs.ZoomEnabled && controller.prefs.AnticipateZoom;
				if (allow_anticipate) {
					if (is_horizontal_dock ()) {
						cursor_region.y = 0;
						cursor_region.height = DockHeight;
					} else {
						cursor_region.x = 0;
						cursor_region.width = DockWidth;
					}
				}
				return cursor_region;
			}
			
			int edge_size = controller.prefs.PressureReveal ? (1 * window_scale_factor) : (10 * window_scale_factor);
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				cursor_region.height = edge_size;
				cursor_region.y = DockHeight - edge_size;
				break;
			case Gtk.PositionType.TOP:
				cursor_region.height = edge_size;
				cursor_region.y = 0;
				break;
			case Gtk.PositionType.LEFT:
				cursor_region.width = edge_size;
				cursor_region.x = 0;
				break;
			case Gtk.PositionType.RIGHT:
				cursor_region.width = edge_size;
				cursor_region.x = DockWidth - edge_size;
				break;
			}
			
			return cursor_region;
		}
		
		public Gdk.Rectangle get_static_dock_region ()
		{
			var dock_region = static_dock_region;
			if (background_rect.width > 0 && background_rect.height > 0) {
				dock_region.union (background_rect, out dock_region);
			}
			dock_region.x += win_x;
			dock_region.y += win_y;
			
			if (!screen_is_composited && controller.hide_manager.Hidden) {
				switch (Position) {
				default:
				case Gtk.PositionType.BOTTOM:
					dock_region.y -= DockHeight - 1;
					break;
				case Gtk.PositionType.TOP:
					dock_region.y += DockHeight - 1;
					break;
				case Gtk.PositionType.LEFT:
					dock_region.x += DockWidth - 1;
					break;
				case Gtk.PositionType.RIGHT:
					dock_region.x -= DockWidth - 1;
					break;
				}
			}
			
			return dock_region;
		}
		
		public void update_regions ()
		{
			Logger.verbose ("PositionManager.update_regions ()");
			
			var old_region = static_dock_region;
			
			items_width = get_items_total_span ();
			
			static_dock_region.width = VisibleDockWidth;
			static_dock_region.height = VisibleDockHeight;
			
			var xoffset = (DockWidth - static_dock_region.width) / 2;
			var yoffset = (DockHeight - static_dock_region.height) / 2;
			
			if (screen_is_composited) {
				var offset = Offset;
				xoffset = (int) ((1 + offset / 100.0) * xoffset);
				yoffset = (int) ((1 + offset / 100.0) * yoffset);
				
				switch (Alignment) {
				default:
				case Gtk.Align.CENTER:
				case Gtk.Align.FILL:
					break;
				case Gtk.Align.START:
					if (is_horizontal_dock ()) {
						xoffset = 0;
						yoffset = (monitor_geo.height - static_dock_region.height);
					} else {
						xoffset = (monitor_geo.width - static_dock_region.width);
						yoffset = 0;
					}
					break;
				case Gtk.Align.END:
					if (is_horizontal_dock ()) {
						xoffset = (monitor_geo.width - static_dock_region.width);
						yoffset = 0;
					} else {
						xoffset = 0;
						yoffset = (monitor_geo.height - static_dock_region.height);
					}
					break;
				}
			}

			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				static_dock_region.x = xoffset;
				static_dock_region.y = DockHeight - static_dock_region.height;
				break;
			case Gtk.PositionType.TOP:
				static_dock_region.x = xoffset;
				static_dock_region.y = 0;
				break;
			case Gtk.PositionType.LEFT:
				static_dock_region.x = 0;
				static_dock_region.y = yoffset;
				break;
			case Gtk.PositionType.RIGHT:
				static_dock_region.x = DockWidth - static_dock_region.width;
				static_dock_region.y = yoffset;
				break;
			}
			
			var old_win_x = win_x;
			var old_win_y = win_y;
			update_dock_position ();
			
			if (!screen_is_composited
				|| old_region.x != static_dock_region.x
				|| old_region.y != static_dock_region.y
				|| old_region.width != static_dock_region.width
				|| old_region.height != static_dock_region.height
				|| win_x != old_win_x
				|| win_y != old_win_y) {
				controller.window.update_size_and_position ();
				if (screen_is_composited)
					controller.renderer.animated_draw ();
			} else {
				controller.renderer.animated_draw ();
			}
		}
		
		public DockItemDrawValue get_draw_value_for_item (DockItem item)
		{
			if (draw_values.size == 0) {
				debug ("Without draw_values there is trouble ahead");
				update_draw_values (controller.VisibleItems);
			}
			
			var draw_value = draw_values[item];
			if (draw_value == null) {
				update_draw_values (controller.VisibleItems);
				draw_value = draw_values[item];
				if (draw_value == null) {
					warning ("Without a draw_value there is trouble ahead for '%s'", item.Text);
					draw_value = new DockItemDrawValue ();
				}
			}
			
			return draw_value;
		}
		
		public void update_draw_values (Gee.ArrayList<unowned DockItem> items, DrawValueFunc? func = null,
			DrawValuesFunc? post_func = null)
		{
			unowned DockPreferences prefs = controller.prefs;
			unowned DockRenderer renderer = controller.renderer;
			
			draw_values.clear ();
			
			int width = DockWidth;
			int height = DockHeight;
			int icon_size = IconSize;
			
			Gdk.Point cursor = renderer.local_cursor;
			
			switch (Position) {
			case Gtk.PositionType.RIGHT:
				cursor.x = width - cursor.x;
				break;
			case Gtk.PositionType.BOTTOM:
				cursor.y = height - cursor.y;
				break;
			default:
				break;
			}
			
			if (!is_horizontal_dock ()) {
				int tmp = cursor.y;
				cursor.y = cursor.x;
				cursor.x = tmp;
				
				tmp = width;
				width = height;
				height = tmp;
			}
			
			double center_y = (is_horizontal_dock () ? static_dock_region.height / 2.0 : static_dock_region.width / 2.0);
			
			double current_items_span = 0.0;
			for (int j = 0; j < items.size; j++) {
				current_items_span += get_item_slot (items[j]);
			}

			double current_dock_width = current_items_span + 2 * items_offset;
			double available_content_span = (double) width - 2.0 * items_offset;
			if (controller.prefs.ScrollOverflow && available_content_span > 0 && current_items_span > available_content_span) {
				max_scroll_offset = current_items_span - available_content_span;
			} else {
				max_scroll_offset = 0.0;
				target_scroll_offset = 0.0;
				scroll_offset = 0.0;
			}

			if (max_scroll_offset > 0.0) {
				target_scroll_offset = target_scroll_offset.clamp (0.0, max_scroll_offset);
				if (Math.fabs (target_scroll_offset - scroll_offset) > 0.1) {
					scroll_offset += (target_scroll_offset - scroll_offset) * 0.35;
					if (Math.fabs (target_scroll_offset - scroll_offset) <= 0.1)
						scroll_offset = target_scroll_offset;
				} else {
					scroll_offset = target_scroll_offset;
				}
			}

			double dock_start_coord = 0.0;
			if (max_scroll_offset > 0.0) {
				dock_start_coord = 0.0;
			} else if (screen_is_composited) {
				double base_span = (double) width - current_dock_width;
				switch (Alignment) {
				default:
				case Gtk.Align.CENTER:
					dock_start_coord = (base_span / 2.0) * (1.0 + Offset / 100.0);
					break;
				case Gtk.Align.START:
					dock_start_coord = 0.0;
					break;
				case Gtk.Align.END:
					dock_start_coord = base_span;
					break;
				case Gtk.Align.FILL:
					dock_start_coord = is_horizontal_dock () ? static_dock_region.x : static_dock_region.y;
					break;
				}
			} else {
				dock_start_coord = is_horizontal_dock () ? static_dock_region.x : static_dock_region.y;
			}

			double first_slot = (items.size > 0) ? get_item_slot (items.first ()) : (icon_size + ItemPadding);
			double center_x;
			if (Alignment == Gtk.Align.FILL && max_scroll_offset <= 0.0) {
				center_x = first_slot / 2.0 + items_offset;
				switch (ItemsAlignment) {
				default:
				case Gtk.Align.FILL:
				case Gtk.Align.CENTER:
					if (is_horizontal_dock ())
						center_x += static_dock_region.x + (static_dock_region.width - 2 * items_offset - items_width) / 2;
					else
						center_x += static_dock_region.y + (static_dock_region.height - 2 * items_offset - items_width) / 2;
					break;
				case Gtk.Align.START:
					break;
				case Gtk.Align.END:
					if (is_horizontal_dock ())
						center_x += static_dock_region.x + (static_dock_region.width - 2 * items_offset - items_width);
					else
						center_x += static_dock_region.y + (static_dock_region.height - 2 * items_offset - items_width);
					break;
				}
			} else if (max_scroll_offset <= 0.0) {
				center_x = first_slot / 2.0 + items_offset + (is_horizontal_dock () ? static_dock_region.x : static_dock_region.y);
			} else {
				center_x = dock_start_coord + items_offset + first_slot / 2.0 - scroll_offset;
			}
			
			PointD center = { Math.floor (center_x), Math.floor (center_y) };
			
			bool expand_for_drop = (controller.drag_manager.ExternalDragActive && !prefs.LockItems);
			bool zoom_enabled = prefs.ZoomEnabled;
			double zoom_in_progress = (zoom_enabled || expand_for_drop ? renderer.zoom_in_progress : 0.0);
			double zoom_in_percent = (zoom_enabled ? 1.0 + (ZoomPercent - 1.0) * zoom_in_progress : 1.0);
			double zoom_icon_size = ZoomIconSize;
			
			for (int i = 0; i < items.size; i++) {
				unowned DockItem item = items[i];
				DockItemDrawValue val = new DockItemDrawValue ();
				val.opacity = 1.0;
				val.darken = 0.0;
				val.lighten = 0.0;
				val.show_indicator = true;
				val.zoom = 1.0;
				
				val.static_center = center;
				
				double cursor_position = cursor.x;
				double center_position = center.x;
				
				double offset = double.min (Math.fabs (cursor_position - center_position), zoom_icon_size);
				
				double offset_percent;
				if (expand_for_drop) {
					offset += offset * zoom_icon_size / icon_size;
					offset_percent = double.min (1.0, offset / (2.0 * zoom_icon_size));
				} else {
					offset_percent = offset / zoom_icon_size;
				}
				
				if (offset_percent > 0.99)
					offset_percent = 1.0;
				
				if (expand_for_drop)
					offset *= zoom_in_progress / 2.0;
				else
					offset *= zoom_in_percent - 1.0;
				offset *= 1.0 - offset_percent / 3.0;
				
				if (cursor_position > center_position)
					center_position -= offset;
				else
					center_position += offset;
				
				var zoom = 1.0 - Math.pow (offset_percent, 2);
				zoom = 1.0 + zoom * (zoom_in_percent - 1.0);
				
				double zoomed_center_height = (icon_size * zoom / 2.0);
				
				if (zoom == 1.0)
					center_position = Math.round (center_position);
				
				val.center = { center_position, zoomed_center_height };
				val.zoom = zoom;
				val.icon_size = Math.round (zoom * icon_size);
				
				// The separator is a real item for layout/animation purposes, but its
				// own rendered size must stay fixed regardless of hover-zoom.
				if (item is SeparatorDockItem) {
					val.center.y = icon_size / 2.0;
					val.zoom = 1.0;
					val.icon_size = icon_size;
				}
				
				if (!is_horizontal_dock ()) {
					double tmp = val.center.y;
					val.center.y = val.center.x;
					val.center.x = tmp;
					
					tmp = val.static_center.y;
					val.static_center.y = val.static_center.x;
					val.static_center.x = tmp;
				}
				
				switch (Position) {
				case Gtk.PositionType.RIGHT:
					val.center.x = height - val.center.x;
					val.static_center.x = height - val.static_center.x;
					break;
				case Gtk.PositionType.BOTTOM:
					val.center.y = height - val.center.y;
					val.static_center.y = height - val.static_center.y;
					break;
				default:
					break;
				}
				
				val.move_in (Position, bottom_offset);
				
				if (func != null)
					func (item, val);
				
				draw_values[item] = val;
				
				if (item.RemoveTime == 0 && i + 1 < items.size) {
					unowned DockItem next_item = items[i + 1];
					center.x += (get_item_slot (item) + get_item_slot (next_item)) / 2.0;
				}
			}
			
			if (post_func != null)
				post_func (draw_values);
			
			update_background_region (draw_values[items.first ()], draw_values[items.last ()]);
			
			draw_values.map_iterator ().foreach ((i, val) => {
				val.draw_region = get_item_draw_region (val);
				val.hover_region = get_item_hover_region (val);
				val.background_region = get_item_background_region (val);
				return true;
			});
		}

		Gdk.Rectangle get_item_draw_region (DockItemDrawValue val)
		{
			var width = val.icon_size, height = val.icon_size;
			
			return { (int) Math.round (val.center.x - width / 2.0),
				(int) Math.round (val.center.y - height / 2.0),
				(int) width,
				(int) height };
		}
		
		Gdk.Rectangle get_item_background_region (DockItemDrawValue val)
		{
			Gdk.Rectangle rect;
			var hover_region = val.hover_region;
			
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				hover_region.height = (background_rect.y + background_rect.height - hover_region.y).abs ();
				break;
			case Gtk.PositionType.TOP:
				hover_region.y = background_rect.y;
				hover_region.height = (hover_region.y - background_rect.y + background_rect.height).abs ();
				break;
			case Gtk.PositionType.LEFT:
				hover_region.x = background_rect.x;
				hover_region.width = (hover_region.x - background_rect.x + background_rect.width).abs ();
				break;
			case Gtk.PositionType.RIGHT:
				hover_region.width = (background_rect.x + background_rect.width - hover_region.x).abs ();
				break;
			}
			
			if (!hover_region.intersect (background_rect, out rect))
				return {};
			
			return rect;
		}
		
		Gdk.Rectangle get_item_hover_region (DockItemDrawValue val)
		{
			Gdk.Rectangle rect;
			
			var item_padding = ItemPadding;
			var top_padding = (top_offset < 0 ? 0 : top_offset);
			var bottom_padding = bottom_offset;
			var width = val.icon_size, height = val.icon_size;
			
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				width += item_padding;
				break;
			case Gtk.PositionType.TOP:
				width += item_padding;
				break;
			case Gtk.PositionType.LEFT:
				height += item_padding;
				break;
			case Gtk.PositionType.RIGHT:
				height += item_padding;
				break;
			}
			
			rect = { (int) Math.round (val.center.x - width / 2.0),
				(int) Math.round (val.center.y - height / 2.0),
				(int) width,
				(int) height };
			
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				rect.y -= top_padding;
				rect.height += bottom_padding + top_padding;
				break;
			case Gtk.PositionType.TOP:
				rect.y -= bottom_padding;
				rect.height += bottom_padding + top_padding;
				break;
			case Gtk.PositionType.LEFT:
				rect.x -= bottom_padding;
				rect.width += bottom_padding + top_padding;
				break;
			case Gtk.PositionType.RIGHT:
				rect.x -= top_padding;
				rect.width += bottom_padding + top_padding;
				break;
			}
			
			Gdk.Rectangle background_region;
			
			if (rect.intersect (get_background_region (), out background_region))
				background_region.union (get_item_draw_region (val), out rect);
			
			return rect;
		}
		
		public Gdk.Rectangle get_hover_region_for_element (DockElement element)
		{
			unowned DockItem? item = (element as DockItem);
			if (item != null)
				return get_draw_value_for_item (item).hover_region;
			
			unowned DockContainer? container = (element as DockContainer);
			if (container == null)
				return {};
			
			unowned Gee.ArrayList<DockElement> items = container.VisibleElements;
			
			if (items.size == 0)
				return {};
			
			var first_rect = get_hover_region_for_element (items.first ());
			if (items.size == 1)
				return first_rect;
			
			var last_rect = get_hover_region_for_element (items.last ());
			
			Gdk.Rectangle result;
			first_rect.union (last_rect, out result);
			return result;
		}
		
		public unowned DockItem? get_nearest_item_at (int x, int y, DockContainer? container = null)
		{
			unowned DockItem? result = null;
			var square_distance = double.MAX;
			
			var draw_values_it = draw_values.map_iterator ();
			while (draw_values_it.next ()) {
				var val = draw_values_it.get_value ();
				var center = val.static_center;
				var new_square_distance = (x - center.x) * (x - center.x) + (y - center.y) * (y - center.y);
				if (square_distance > new_square_distance) {
					DockItem? item = (draw_values_it.get_key () as DockItem);
					if (item == null)
						continue;
					if (container == null || item.Container == container) {
						square_distance = new_square_distance;
						result = item;
					}				
				}				
			}
			
			return result;
		}
		
		public unowned DockItem? get_current_target_item (DockContainer? container = null)
		{
			unowned DockRenderer renderer = controller.renderer;
			var cursor = renderer.local_cursor;
			var offset = (int) ((renderer.zoom_in_progress * ZoomIconSize + ItemPadding) / 2.0);
			
			return get_nearest_item_at (cursor.x + offset, cursor.y + offset, container);
		}

		public void get_menu_position (DockElement? item, Gtk.Requisition requisition, out int x, out int y)
		{
			var rect = item != null ? get_hover_region_for_element (item) : static_dock_region;
			var dock_window_region = get_dock_window_region ();

			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				x = dock_window_region.x + rect.x + (rect.width - requisition.width) / 2;
				y = dock_window_region.y - requisition.height;
				break;
			case Gtk.PositionType.TOP:
				x = dock_window_region.x + rect.x + (rect.width - requisition.width) / 2;
				y = dock_window_region.y + dock_window_region.height;
				break;
			case Gtk.PositionType.LEFT:
				x = dock_window_region.x + dock_window_region.width;
				y = dock_window_region.y + rect.y + (rect.height - requisition.height) / 2;
				break;
			case Gtk.PositionType.RIGHT:
				x = dock_window_region.x - requisition.width;
				y = dock_window_region.y + rect.y + (rect.height - requisition.height) / 2;
				break;
			}
		}

		public int get_visual_thickness ()
		{
			return is_horizontal_dock () ? VisibleDockHeight : VisibleDockWidth;
		}

		public int get_visual_thickness_for_item (DockElement? item)
		{
			unowned DockItem? dock_item = item as DockItem;
			double icon_sz = IconSize;
			if (dock_item != null) {
				var val = get_draw_value_for_item (dock_item);
				if (val != null && val.icon_size > 0)
					icon_sz = val.icon_size;
			}
			int offset = (top_offset > 0 ? top_offset : 0) + (bottom_offset > 0 ? bottom_offset : 0);
			return (int) Math.round (icon_sz) + offset;
		}

		public void get_hover_position (DockElement item, out int x, out int y)
		{
			// =========================================================================
			// 1. NATIVE LAYER SHELL COMPOSITORS: KWIN (PLASMA) & LABWC (WLROOTS)
			// =========================================================================
			if (GtkLayerShell.is_supported ()) {
				unowned DockItem? dock_item = (item as DockItem);
				if (dock_item != null) {
					var val = get_draw_value_for_item (dock_item);
					x = (int) Math.round (val.center.x);
					y = (int) Math.round (val.center.y);
				} else {
					var rect = get_hover_region_for_element (item);
					x = rect.x + rect.width / 2;
					y = rect.y + rect.height / 2;
				}
				return;
			}

			// =========================================================================
			// 2. NON-LAYER SHELL COMPOSITOR: GNOME SHELL / MUTTER ONLY
			// =========================================================================
			unowned DockItem? dock_item = (item as DockItem);
			if (dock_item != null) {
				var val = get_draw_value_for_item (dock_item);
				x = (int) Math.round (val.static_center.x > 0 ? val.static_center.x : val.center.x);
				if (is_horizontal_dock ()) {
					y = (int) Math.round (val.center.y);
				} else {
					int half_icon = (int) Math.round (IconSize / 2.0);
					y = (int) Math.round (val.static_center.y > 0 ? val.static_center.y : val.center.y) + half_icon;
				}
			} else {
				var rect = get_hover_region_for_element (item);
				x = rect.x + rect.width / 2;
				y = rect.y + rect.height / 2;
			}
		}
		
		public void get_hover_position_at (ref int x, ref int y)
		{
			var center = get_draw_value_for_item (controller.VisibleItems.first ()).static_center;
			var offset = (ZoomIconSize - IconSize / 2.0);
			
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				y = (int) Math.round (center.y + win_y - offset);
				break;
			case Gtk.PositionType.TOP:
				y = (int) Math.round (center.y + win_y + offset);
				break;
			case Gtk.PositionType.LEFT:
				x = (int) Math.round (center.x + win_x + offset);
				break;
			case Gtk.PositionType.RIGHT:
				x = (int) Math.round (center.x + win_x - offset);
				break;
			}
		}

		public void get_urgent_glow_position (DockItem item, out int x, out int y)
		{
			var rect = get_hover_region_for_element (item);
			var glow_size = GlowSize;
			
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				x = rect.x + (rect.width - glow_size) / 2;
				y = DockHeight - glow_size / 2;
				break;
			case Gtk.PositionType.TOP:
				x = rect.x + (rect.width - glow_size) / 2;
				y = - glow_size / 2;
				break;
			case Gtk.PositionType.LEFT:
				y = rect.y + (rect.height - glow_size) / 2;
				x = - glow_size / 2;
				break;
			case Gtk.PositionType.RIGHT:
				y = rect.y + (rect.height - glow_size) / 2;
				x = DockWidth - glow_size / 2;
				break;
			}
		}

		public void update_dock_position ()
		{
			var xoffset = 0;
			var yoffset = 0;
			
			if (!screen_is_composited) {
				var offset = Offset;
				xoffset = (int) ((1 + offset / 100.0) * (monitor_geo.width - DockWidth) / 2);
				yoffset = (int) ((1 + offset / 100.0) * (monitor_geo.height - DockHeight) / 2);
				
				switch (Alignment) {
				default:
				case Gtk.Align.CENTER:
				case Gtk.Align.FILL:
					break;
				case Gtk.Align.START:
					if (is_horizontal_dock ()) {
						xoffset = 0;
						yoffset = (monitor_geo.height - static_dock_region.height);
					} else {
						xoffset = (monitor_geo.width - static_dock_region.width);
						yoffset = 0;
					}
					break;
				case Gtk.Align.END:
					if (is_horizontal_dock ()) {
						xoffset = (monitor_geo.width - static_dock_region.width);
						yoffset = 0;
					} else {
						xoffset = 0;
						yoffset = (monitor_geo.height - static_dock_region.height);
					}
					break;
				}
			}
			
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				win_x = monitor_geo.x + xoffset;
				win_y = monitor_geo.y + monitor_geo.height - DockHeight;
				break;
			case Gtk.PositionType.TOP:
				win_x = monitor_geo.x + xoffset;
				win_y = monitor_geo.y;
				break;
			case Gtk.PositionType.LEFT:
				win_y = monitor_geo.y + yoffset;
				win_x = monitor_geo.x;
				break;
			case Gtk.PositionType.RIGHT:
				win_y = monitor_geo.y + yoffset;
				win_x = monitor_geo.x + monitor_geo.width - DockWidth;
				break;
			}
			
			if (!screen_is_composited && controller.hide_manager.Hidden) {
				switch (Position) {
				default:
				case Gtk.PositionType.BOTTOM:
					win_y += DockHeight - 1;
					break;
				case Gtk.PositionType.TOP:
					win_y -= DockHeight - 1;
					break;
				case Gtk.PositionType.LEFT:
					win_x -= DockWidth - 1;
					break;
				case Gtk.PositionType.RIGHT:
					win_x += DockWidth - 1;
					break;
				}
			}
		}
		
		public void get_dock_draw_position (out int x, out int y)
		{
			if (!screen_is_composited) {
				x = 0;
				y = 0;
				return;
			}
			
			var progress = controller.renderer.hide_progress;
			
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				x = 0;
				y = (int) ((VisibleDockHeight + extra_hide_offset) * progress);
				break;
			case Gtk.PositionType.TOP:
				x = 0;
				y = (int) (- (VisibleDockHeight + extra_hide_offset) * progress);
				break;
			case Gtk.PositionType.LEFT:
				x = (int) (- (VisibleDockWidth + extra_hide_offset) * progress);
				y = 0;
				break;
			case Gtk.PositionType.RIGHT:
				x = (int) ((VisibleDockWidth + extra_hide_offset) * progress);
				y = 0;
				break;
			}
		}
		
		public Gdk.Rectangle get_dock_window_region ()
		{
			return { win_x, win_y, DockWidth, DockHeight };
		}
		
		public void get_background_padding (out int x, out int y)
		{
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				x = 0;
				y = VisibleDockHeight - DockBackgroundHeight + extra_hide_offset;
				break;
			case Gtk.PositionType.TOP:
				x = 0;
				y = -(VisibleDockHeight - DockBackgroundHeight + extra_hide_offset);
				break;
			case Gtk.PositionType.LEFT:
				x = -(VisibleDockWidth - DockBackgroundWidth + extra_hide_offset);
				y = 0;
				break;
			case Gtk.PositionType.RIGHT:
				x = VisibleDockWidth - DockBackgroundWidth + extra_hide_offset;
				y = 0;
				break;
			}
		}
		
		public Gdk.Rectangle get_background_region ()
		{
			return background_rect;
		}
		
		void update_background_region (DockItemDrawValue val_first, DockItemDrawValue val_last)
		{
			var x = 0, y = 0, width = 0, height = 0;
			
			if (screen_is_composited) {
				x = static_dock_region.x;
				y = static_dock_region.y;
				width = VisibleDockWidth;
				height = VisibleDockHeight;
			} else {
				width = DockWidth;
				height = DockHeight;
			}
			
			if (Alignment == Gtk.Align.FILL) {
				switch (Position) {
				default:
				case Gtk.PositionType.BOTTOM:
					x += (width - DockBackgroundWidth) / 2;
					y += height - DockBackgroundHeight;
					break;
				case Gtk.PositionType.TOP:
					x += (width - DockBackgroundWidth) / 2;
					y = 0;
					break;
				case Gtk.PositionType.LEFT:
					x = 0;
					y += (height - DockBackgroundHeight) / 2;
					break;
				case Gtk.PositionType.RIGHT:
					x += width - DockBackgroundWidth;
					y += (height - DockBackgroundHeight) / 2;
					break;
				}
				
				background_rect = { x, y, DockBackgroundWidth, DockBackgroundHeight };
				return;
			}
			
			var center_first = val_first.center;
			var center_last = val_last.center;
			var padding = ItemPadding + 2 * HorizPadding + 4 * LineWidth;
			var padding_first = (val_first.icon_size + padding) / 2.0;
			var padding_last = (val_last.icon_size + padding) / 2.0;
			
			if (max_scroll_offset > 0.0) {
				if (is_horizontal_dock ()) {
					x = static_dock_region.x;
					width = monitor_geo.width;
					y += (Position == Gtk.PositionType.BOTTOM) ? (height - DockBackgroundHeight) : 0;
					background_rect = { x, y, width, DockBackgroundHeight };
					return;
				} else {
					x += (Position == Gtk.PositionType.RIGHT) ? (width - DockBackgroundWidth) : 0;
					y = static_dock_region.y;
					height = monitor_geo.height;
					background_rect = { x, y, DockBackgroundWidth, height };
					return;
				}
			}

			var rev_round = get_reverse_roundness_padding (ReverseRoundness, BottomRoundness);

			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				x = (int) Math.round (center_first.x - padding_first - rev_round);
				y += height - DockBackgroundHeight;
				width = (int) Math.round (center_last.x - center_first.x + padding_first + padding_last + 2 * rev_round);
				height = DockBackgroundHeight;
				break;
			case Gtk.PositionType.TOP:
				x = (int) Math.round (center_first.x - padding_first - rev_round);
				y = 0;
				width = (int) Math.round (center_last.x - center_first.x + padding_first + padding_last + 2 * rev_round);
				height = DockBackgroundHeight;
				break;
			case Gtk.PositionType.LEFT:
				x = 0;
				y = (int) Math.round (center_first.y - padding_first - rev_round);
				width = DockBackgroundWidth;
				height = (int) Math.round (center_last.y - center_first.y + padding_first + padding_last + 2 * rev_round);
				break;
			case Gtk.PositionType.RIGHT:
				x += width - DockBackgroundWidth;
				y = (int) Math.round (center_first.y - padding_first - rev_round);
				width = DockBackgroundWidth;
				height = (int) Math.round (center_last.y - center_first.y + padding_first + padding_last + 2 * rev_round);
				break;
			}
			
			if (is_horizontal_dock ()) {
				if (x < 0) {
					width += x;
					x = 0;
				}
				if (x + width > monitor_geo.width) {
					width = monitor_geo.width - x;
				}
			} else {
				if (y < 0) {
					height += y;
					y = 0;
				}
				if (y + height > monitor_geo.height) {
					height = monitor_geo.height - y;
				}
			}

			background_rect = { x, y, width, height };
		}
		
		public Gdk.Rectangle get_icon_geometry (ApplicationDockItem item, bool for_hidden)
		{
			var region = get_hover_region_for_element (item);
			
			if (!for_hidden) {
				region.x += win_x;
				region.y += win_y;
				
				return region;
			}
			
			var x = win_x, y = win_y;
			
			switch (Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				x += region.x + region.width / 2;
				y += DockHeight;
				break;
			case Gtk.PositionType.TOP:
				x += region.x + region.width / 2;
				y += 0;
				break;
			case Gtk.PositionType.LEFT:
				x += 0;
				y += region.y + region.height / 2;
				break;
			case Gtk.PositionType.RIGHT:
				x += DockWidth;
				y += region.y + region.height / 2;
				break;
			}
			
			return { x, y, 0, 0 };
		}
		
	}
}