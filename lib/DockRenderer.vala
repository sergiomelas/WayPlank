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
	/**
	 * Handles all of the drawing for a dock.
	 */
	public class DockRenderer : Renderer
	{
		public DockController controller { private get; construct; }
		
		public DockTheme theme { get; private set; }
		
		/**
		 * The current progress [0.0..1.0] of the hide-animation of the dock.
		 */
		[CCode (notify = false)]
		public double hide_progress { get; private set; }
		
		/**
		 * The current opacity of the dock.
		 */
		[CCode (notify = false)]
		double opacity { get; private set; }
		
		/**
		 * The current progress [0.0..1.0] of the zoom-in-animation of the dock.
		 */
		[CCode (notify = false)]
		public double zoom_in_progress { get; private set; }
		
		/**
		 * The current local cursor-position on the dock if hovered.
		 */
		public Gdk.Point local_cursor;

		Surface? main_buffer = null;
		Surface? fade_buffer = null;
		
		Surface? background_buffer = null;
		Gdk.Rectangle background_rect;
		Surface? indicator_buffer = null;
		Surface? urgent_indicator_buffer = null;
		Surface? urgent_glow_buffer = null;
		Color? cached_styled_color = null;
		Gee.HashMap<int, Surface> item_scratch_pool;
		
		int64 last_hide = 0LL;
		int64 last_hovered_changed = 0LL;
		int64 last_cursor_motion = 0LL;
		
		bool screen_is_composited = false;
		bool show_notifications = true;
		uint reset_position_manager_timer_id = 0U;
		int window_scale_factor = 1;
		bool is_first_frame = true;
		bool zoom_changed = false;
		
		ulong gtk_theme_name_changed_handler_id = 0UL;
		ulong gtk_dark_theme_changed_handler_id = 0UL;
		
		double dynamic_animation_offset = 0.0;

		public signal void removal_shrink_completed (uint64 tx_id);

		DockItem? hidden_removal_item = null;
		uint64 active_shrink_tx_id = 0ULL;
		uint64 pending_after_paint_tx_id = 0ULL;
		ulong shrink_after_paint_handler_id = 0UL;
		Gdk.FrameClock? shrink_after_paint_clock = null;
		bool watching_shrink = false;
		
		Gee.ArrayList<unowned DockItem> current_items;
		Gee.HashSet<DockItem> transient_items;
#if BENCHMARK
		Gee.ArrayList<string> benchmark;
#endif
		
		/**
		 * Create a new dock renderer for a dock.
		 *
		 * @param controller the dock controller to manage drawing for
		 * @param window the dock window to be animated
		 */
		public DockRenderer (DockController controller, Gtk.Window window)
		{
			GLib.Object (controller : controller, widget : window);
		}
		
		construct
		{
			transient_items = new Gee.HashSet<DockItem> ();
			current_items = new Gee.ArrayList<unowned DockItem> ();
			item_scratch_pool = new Gee.HashMap<int, Surface> ();
#if BENCHMARK
			benchmark = new Gee.ArrayList<string> ();
#endif
			controller.prefs.notify.connect (prefs_changed);
			SystemTheme.get_default ().theme_changed.connect (on_system_theme_changed);
			
			load_theme ();
		}
		
		/**
		 * Initializes the renderer.  Call after the DockWindow is constructed.
		 */
		public void initialize ()
			requires (controller.window != null)
		{
			controller.position_manager.update (theme);
			if (controller.app_provider != null)
				controller.app_provider.refresh_pinned_accordion ();
			
			controller.window.notify["HoveredItem"].connect (animated_draw);
			controller.hide_manager.notify["Hidden"].connect (hidden_changed);
			controller.hide_manager.notify["Hovered"].connect (hovered_changed);
		}
		
		~DockRenderer ()
		{
			cancel_shrink_after_paint ();
			if (reset_position_manager_timer_id > 0U) {
				Source.remove (reset_position_manager_timer_id);
				reset_position_manager_timer_id = 0U;
			}
			item_scratch_pool.clear ();
			SystemTheme.get_default ().theme_changed.disconnect (on_system_theme_changed);

			if (controller != null) {
				controller.prefs.notify.disconnect (prefs_changed);
				if (controller.hide_manager != null) {
					controller.hide_manager.notify["Hidden"].disconnect (hidden_changed);
					controller.hide_manager.notify["Hovered"].disconnect (hovered_changed);
				}
				if (controller.window != null) {
					controller.window.notify["HoveredItem"].disconnect (animated_draw);
				}
			}
			if (theme != null) {
				theme.notify.disconnect (theme_changed);
			}
			if (gtk_theme_name_changed_handler_id > 0UL) {
				SignalHandler.disconnect (Gtk.Settings.get_default (), gtk_theme_name_changed_handler_id);
				gtk_theme_name_changed_handler_id = 0UL;
			}
			if (gtk_dark_theme_changed_handler_id > 0UL) {
				SignalHandler.disconnect (Gtk.Settings.get_default (), gtk_dark_theme_changed_handler_id);
				gtk_dark_theme_changed_handler_id = 0UL;
			}
		}
		
		void prefs_changed (Object prefs, ParamSpec prop)
		{
			switch (prop.name) {
			case "Alignment":
			case "IconSize":
			case "ItemsAlignment":
			case "Offset":
			case "Position":
				reset_position_manager ();
				break;
			case "Theme":
				load_theme ();
				break;
			case "ActiveHighlight":
			case "EffectDuration":
			case "ZoomEnabled":
			case "ZoomPercent":
				animated_draw ();
				break;
			default:
				// Nothing important for us changed
				break;
			}
		}

		inline int get_effective_active_highlight ()
		{
			return controller.prefs.ActiveHighlight;
		}

		inline int get_effective_launch_animation ()
		{
			return controller.prefs.LaunchAnimation;
		}

		inline int get_effective_launch_duration_ms ()
		{
			return controller.prefs.EffectDuration.clamp (DockPreferences.MIN_EFFECT_DURATION, DockPreferences.MAX_EFFECT_DURATION);
		}

		inline int get_effective_active_duration_ms ()
		{
			return int.max (80, controller.prefs.EffectDuration.clamp (DockPreferences.MIN_EFFECT_DURATION, DockPreferences.MAX_EFFECT_DURATION) / 2);
		}

		Color get_item_accent_color (DockItem item)
		{
			var glow_color = item.AverageIconColor;
			if (glow_color.get_sat () < 0.15) {
				glow_color = get_styled_color ();
				glow_color.set_min_sat (0.45);
			} else {
				glow_color.set_min_sat (0.45);
				if (glow_color.get_val () < 0.72)
					glow_color.set_val (0.72);
			}
			return glow_color;
		}
		
		void theme_changed ()
		{
			reset_position_manager ();
		}
		
		void reset_position_manager ()
		{
			// Don't perform an update immediately and summon further
			// update-requests, wait at least 50ms after the last request
			
			if (reset_position_manager_timer_id > 0U)
				Source.remove (reset_position_manager_timer_id);
			
			reset_position_manager_timer_id = Gdk.threads_add_timeout (50, () => {
				reset_position_manager_timer_id = 0U;
				
				reset_buffers ();
				reset_item_buffers ();
				controller.position_manager.update (theme);
				if (controller.app_provider != null)
					controller.app_provider.refresh_pinned_accordion ();
				
				return false;
			});
		}
		
		void on_system_theme_changed (bool is_dark)
		{
			unowned string cur_theme = controller.prefs.Theme;
			if (cur_theme == Theme.DEFAULT_NAME || cur_theme == Theme.GTK_THEME_NAME) {
				load_theme ();
			} else if (is_dark && cur_theme.has_suffix (" Light")) {
				string dark_counterpart = cur_theme.substring (0, cur_theme.length - 6) + " Dark";
				if (Theme.is_valid_name (dark_counterpart)) {
					controller.prefs.Theme = dark_counterpart;
				} else {
					load_theme ();
				}
			} else if (!is_dark && cur_theme.has_suffix (" Dark")) {
				string light_counterpart = cur_theme.substring (0, cur_theme.length - 5) + " Light";
				if (Theme.is_valid_name (light_counterpart)) {
					controller.prefs.Theme = light_counterpart;
				} else {
					load_theme ();
				}
			} else {
				load_theme ();
			}
		}

		void load_theme ()
		{
			var is_reload = (theme != null);
			
			if (is_reload)
				theme.notify.disconnect (theme_changed);
			
			unowned string name = controller.prefs.Theme;
			if (name == Theme.DEFAULT_NAME || name == Theme.GTK_THEME_NAME) {
				if (gtk_theme_name_changed_handler_id == 0UL)
					gtk_theme_name_changed_handler_id = Gtk.Settings.get_default ().notify["gtk-theme-name"].connect (load_theme);
				if (gtk_dark_theme_changed_handler_id == 0UL)
					gtk_dark_theme_changed_handler_id = Gtk.Settings.get_default ().notify["gtk-application-prefer-dark-theme"].connect (load_theme);
			} else {
				if (gtk_theme_name_changed_handler_id > 0UL) {
					SignalHandler.disconnect (Gtk.Settings.get_default (), gtk_theme_name_changed_handler_id);
					gtk_theme_name_changed_handler_id = 0UL;
				}
				if (gtk_dark_theme_changed_handler_id > 0UL) {
					SignalHandler.disconnect (Gtk.Settings.get_default (), gtk_dark_theme_changed_handler_id);
					gtk_dark_theme_changed_handler_id = 0UL;
				}
			}
			
			theme = new DockTheme (name);
			theme.load ("dock");
			theme.notify.connect (theme_changed);
			cached_styled_color = null;
			cached_background_average_color = null;
			
			if (is_reload) {
				reset_buffers ();
				reset_item_buffers ();
				theme_changed ();
				if (controller.window != null)
					controller.window.queue_draw ();
			}
		}
		
		/**
		 * Resets all internal buffers and forces a redraw.
		 */
		public void reset_buffers ()
		{
			Logger.verbose ("DockRenderer.reset_buffers ()");
			
			main_buffer = null;
			fade_buffer = null;
			item_scratch_pool.clear ();
			
			background_buffer = null;
			cached_background_average_color = null;
			cached_styled_color = null;
			indicator_buffer = null;
			urgent_indicator_buffer = null;
			urgent_glow_buffer = null;
			
			animated_draw ();
		}
		
		/**
		 * Resets all internal item buffers and forces a redraw.
		 */
		void reset_item_buffers ()
		{
			Logger.verbose ("DockRenderer.reset_item_buffers ()");
			
			controller.reset_buffers ();
			
			animated_draw ();
		}

		void cancel_shrink_after_paint ()
		{
			if (shrink_after_paint_handler_id > 0UL && shrink_after_paint_clock != null) {
				SignalHandler.disconnect (shrink_after_paint_clock, shrink_after_paint_handler_id);
			}
			shrink_after_paint_handler_id = 0UL;
			shrink_after_paint_clock = null;
			pending_after_paint_tx_id = 0ULL;
		}

		void schedule_shrink_ack_after_paint (uint64 tx_id)
		{
			cancel_shrink_after_paint ();
			unowned Gdk.FrameClock? clock = widget.get_frame_clock ();
			if (clock == null || !widget.get_mapped ()) {
				removal_shrink_completed (tx_id);
				return;
			}

			pending_after_paint_tx_id = tx_id;
			shrink_after_paint_clock = clock;
			shrink_after_paint_handler_id = clock.after_paint.connect (() => {
				uint64 ack_tx = pending_after_paint_tx_id;
				cancel_shrink_after_paint ();
				if (ack_tx != 0ULL)
					removal_shrink_completed (ack_tx);
			});
		}

		/**
		 * Beat 1 (DESTROYING): Keeps the item's slot open and unshrunk on the dock
		 * while hiding its icon surface while PoofWindow plays its VSync destruction frames.
		 */
		public void hold_removal_slot (DockItem item)
		{
			cancel_shrink_after_paint ();
			hidden_removal_item = item;
			watching_shrink = false;
			active_shrink_tx_id = 0ULL;
			if (widget.get_realized ()) {
				force_frame_time_update ();
				initialize_frame (frame_time);
				widget.queue_draw ();
			}
			animated_draw ();
		}

		/**
		 * Beat 2 (SHRINKING_GAP): Arms VSync completion tracking for the removed item's
		 * smooth EASE_IN_QUINT gap-shrink, returning false if no transient shrink is active.
		 */
		public bool watch_removal_shrink (DockItem item, uint64 tx_id)
		{
			cancel_shrink_after_paint ();
			if (!screen_is_composited || !transient_items.contains (item)) {
				hidden_removal_item = null;
				watching_shrink = false;
				active_shrink_tx_id = 0ULL;
				return false;
			}

			hidden_removal_item = item;
			active_shrink_tx_id = tx_id;
			watching_shrink = true;
			animated_draw ();
			return true;
		}

		/**
		 * Aborts any active slot hold or shrink watch synchronously.
		 */
		public void clear_removal_hold ()
		{
			cancel_shrink_after_paint ();
			if (hidden_removal_item != null)
				transient_items.remove (hidden_removal_item);
			hidden_removal_item = null;
			watching_shrink = false;
			active_shrink_tx_id = 0ULL;
			if (widget.get_realized ()) {
				force_frame_time_update ();
				initialize_frame (frame_time);
				widget.queue_draw ();
			}
			animated_draw ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override void initialize_frame (int64 frame_time)
		{
			return_if_fail (theme != null);
			
			unowned Gee.ArrayList<unowned DockItem> new_items = controller.VisibleItems;
			
			// FIXME This should never happen
			if (new_items.size <= 0) {
				critical ("No items available to initialize frame");
				return;
			}
			
			unowned PositionManager position_manager = controller.position_manager;
			
			screen_is_composited = position_manager.screen_is_composited;
			show_notifications = EnvironmentSettings.get_instance ().ShowNotifications;
			dynamic_animation_offset = 0.0;
			
			var fade_opacity = theme.FadeOpacity;
			
			if (screen_is_composited) {
				var hide_duration = (fade_opacity == 1.0 ? theme.HideTime : theme.FadeTime) * 1000;
				var hide_time = int64.max (0LL, frame_time - last_hide);
				if (hide_time < hide_duration) {
					if (controller.hide_manager.Hidden)
						hide_progress = easing_for_mode (AnimationMode.EASE_IN_CUBIC, hide_time, hide_duration);
					else
						hide_progress = 1.0 - easing_for_mode (AnimationMode.EASE_OUT_CUBIC, hide_time, hide_duration);
				} else {
					hide_progress = (controller.hide_manager.Hidden ? 1.0 : 0.0);
				}
				
				var zoom_duration = DOCK_ZOOM_DURATION * 1000;
				var zoom_time = int64.max (0LL, frame_time - last_hovered_changed);
				double zoom_progress;
				if (zoom_time < zoom_duration) {
					if (controller.hide_manager.Hovered)
						zoom_progress = easing_for_mode (AnimationMode.EASE_OUT_CUBIC, zoom_time, zoom_duration);
					else
						zoom_progress = 1.0 - easing_for_mode (AnimationMode.EASE_IN_CUBIC, zoom_time, zoom_duration);
				} else {
					zoom_progress = (controller.hide_manager.Hovered ? 1.0 : 0.0);
				}
				zoom_in_progress = zoom_progress * (1.0 - hide_progress);
			} else {
				hide_progress = 0.0;
				zoom_in_progress = 0.0;
			}
			
			if (fade_opacity < 1.0)
				opacity = 1.0 - (1.0 - fade_opacity) * hide_progress;
			else
				opacity = 1.0;
			
			// Update *ordered* list of items
			current_items.clear ();
			current_items.add_all (new_items);
			
			if (screen_is_composited) {
				var add_time = 0LL;
				var remove_time = 0LL;
				var move_time = 0LL;
				var move_duration = theme.ItemMoveTime * 1000;
				
				var transient_items_it = transient_items.iterator ();
				while (transient_items_it.next ()) {
					var item = transient_items_it.get ();
					add_time = item.AddTime;
					remove_time = item.RemoveTime;
					
					if (add_time > remove_time) {
						move_time = frame_time - add_time;
						if (move_time < move_duration) {
							if (!current_items.contains (item))
								current_items.add (item);
						} else {
							transient_items_it.remove ();
						}
					} else if (remove_time > 0) {
						move_time = frame_time - remove_time;
						if (move_time < move_duration) {
							if (!current_items.contains (item))
								current_items.add (item);
						} else {
							transient_items_it.remove ();
						}
					} else {
						transient_items_it.remove ();
					}
				}
			} else {
				transient_items.clear ();
			}

			if (watching_shrink && (hidden_removal_item == null || !transient_items.contains (hidden_removal_item))) {
				uint64 finished_tx = active_shrink_tx_id;
				watching_shrink = false;
				active_shrink_tx_id = 0ULL;
				hidden_removal_item = null;
				if (finished_tx != 0ULL)
					schedule_shrink_ack_after_paint (finished_tx);
			}
			
			current_items.sort ((CompareDataFunc) compare_dock_item_position);
			
			// Calculate positions for given ordered list of items
			position_manager.update_draw_values (current_items,
				(DrawValueFunc) animate_draw_value_for_item,
				(DrawValuesFunc) post_process_draw_values);
			
			background_rect = position_manager.get_background_region ();

			if (controller.hide_manager.Hovered && !controller.hide_manager.Hidden
				&& local_cursor.x >= 0 && local_cursor.y >= 0
				&& controller.window != null && !controller.window.menu_is_visible ()) {
				controller.window.update_hovered (local_cursor.x, local_cursor.y);
			}
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override void draw (Cairo.Context cr, int64 frame_time)
		{
			// FIXME This should never happen
			if (current_items.size <= 0) {
				critical ("No items available to draw frame");
				return;
			}
			
			window_scale_factor = controller.window.get_window ().get_scale_factor ();
			// take the previous frame values into account to decide if we
			// can bail a full draw to not miss a finishing animation-frame
			var no_full_draw_needed = (!is_first_frame && hide_progress == 1.0 && opacity == 1.0);
			
			unowned PositionManager position_manager = controller.position_manager;
			unowned DockItem dragged_item = controller.drag_manager.DragItem;
			var win_rect = position_manager.get_dock_window_region ();
			
			if (main_buffer == null || main_buffer.Width != win_rect.width || main_buffer.Height != win_rect.height) {
				main_buffer = new Surface.with_cairo_surface (win_rect.width, win_rect.height, cr.get_target ());
				main_buffer.Internal.set_device_scale (window_scale_factor, window_scale_factor);
			}
			
			// if the dock is completely hidden and not transparently drawn
			// only draw ugent-glow indicators and bail since there is no need
			// for further things
			if (no_full_draw_needed && hide_progress == 1.0 && opacity == 1.0) {
				// we still need to clear out the previous output
				cr.save ();
				cr.set_operator (Cairo.Operator.CLEAR);
				cr.paint ();
				cr.restore ();
				
				if (show_notifications)
					foreach (unowned DockItem item in current_items)
						draw_urgent_glow (item, cr, frame_time);
				
				return;
			}

			if (opacity < 1.0 && (fade_buffer == null || fade_buffer.Width != win_rect.width || fade_buffer.Height != win_rect.height)) {
				fade_buffer = new Surface.with_cairo_surface (win_rect.width, win_rect.height, cr.get_target ());
				fade_buffer.Internal.set_device_scale (window_scale_factor, window_scale_factor);
			}
			
#if BENCHMARK
			DateTime start, start2, end, end2;
			benchmark.clear ();
			start = new DateTime.now_local ();
#endif
			
			// calculate drawing offset
			var x_offset = 0, y_offset = 0;
			if (opacity == 1.0)
				position_manager.get_dock_draw_position (out x_offset, out y_offset);
			
			// composite dock layers directly onto main_buffer in two light passes
			main_buffer.clear ();
			unowned Cairo.Context main_cr = main_buffer.Context;
			main_cr.set_operator (Cairo.Operator.OVER);
			
#if BENCHMARK
			start2 = new DateTime.now_local ();
#endif
			// draw background-layer
			draw_dock_background (main_cr, background_rect, x_offset, y_offset);
#if BENCHMARK
			end2 = new DateTime.now_local ();
			benchmark.add ("background render time - %f ms".printf (end2.difference (start2) / 1000.0));
#endif
			
			update_separator_colors ();

			// Translate item/shadow pass by (x_offset, y_offset) and clip scrolled-out items if overflowed
			bool need_clip = (position_manager.max_scroll_offset > 0.0);
			bool transform_active = (x_offset != 0 || y_offset != 0 || need_clip);
			if (transform_active) {
				main_cr.save ();
				if (x_offset != 0 || y_offset != 0)
					main_cr.translate (x_offset, y_offset);
				if (need_clip) {
					if (position_manager.is_horizontal_dock ())
						main_cr.rectangle (background_rect.x, 0, background_rect.width, win_rect.height);
					else
						main_cr.rectangle (0, background_rect.y, win_rect.width, background_rect.height);
					main_cr.clip ();
				}
			}

			// Pass 1: draw item shadows onto main_buffer
			if (position_manager.IconShadowSize > 0) {
				foreach (unowned DockItem item in current_items) {
					if (item.IsVisible && dragged_item != item && hidden_removal_item != item) {
						var draw_value = position_manager.get_draw_value_for_item (item);
						draw_item_shadow (main_cr, item, draw_value);
					}
				}
			}

			// Pass 2: draw items onto main_buffer
			foreach (unowned DockItem item in current_items) {
#if BENCHMARK
				start2 = new DateTime.now_local ();
#endif
				// Do not draw the currently dragged item or an item whose removal slot is being destroyed/shrunk
				if (item.IsVisible && dragged_item != item && hidden_removal_item != item) {
					var draw_value = position_manager.get_draw_value_for_item (item);
					draw_item (main_cr, item, draw_value, frame_time);
				}
#if BENCHMARK
				end2 = new DateTime.now_local ();
				benchmark.add ("item render time - %f ms".printf (end2.difference (start2) / 1000.0));
#endif
			}

			if (transform_active)
				main_cr.restore ();

			// draw scroll indicators if overflowed
			if (position_manager.max_scroll_offset > 0.0) {
				draw_scroll_edge_indicators (main_cr, background_rect, x_offset, y_offset);
			}
			
			// draw the dock on the window and fade it if need be
			cr.set_operator (Cairo.Operator.SOURCE);
			if (opacity < 1.0) {
				fade_buffer.clear ();
				unowned Cairo.Context fade_cr = fade_buffer.Context;
				fade_cr.set_operator (Cairo.Operator.OVER);
				fade_cr.set_source_surface (main_buffer.Internal, 0, 0);
				fade_cr.paint_with_alpha (opacity);
				
				cr.set_source_surface (fade_buffer.Internal, 0, 0);
			} else {
				cr.set_source_surface (main_buffer.Internal, 0, 0);
			}
			cr.paint ();
			
			// draw urgent-glow if dock is completely hidden
			if (show_notifications && hide_progress == 1.0) {
				foreach (unowned DockItem item in current_items)
					draw_urgent_glow (item, cr, frame_time);
			}
			
#if BENCHMARK
			end = new DateTime.now_local ();
			var diff = end.difference (start) / 1000.0;
			if (diff > 5.0)
				foreach (var s in benchmark)
					message ("	" + s);
			message ("render time - %f ms", diff);
#endif
			
			if (is_first_frame) {
				message ("Cairo.SurfaceType: %s", cairo_surface_type_to_string (cr.get_target ().get_type ()));
				
				Gdk.threads_add_idle_full (GLib.Priority.LOW, () => {
					unowned HideManager hide_manager = controller.hide_manager;
					
					// FIXME HideManager.initialize () -> setup_active_window ();
					// is already taking care of updating the Hidden-state,
					// but only if there is already an active/open window
					if (hide_manager.Hidden)
						return false;
					
					// slide the dock in, if it shouldnt start hidden
					hide_manager.update_hovered ();
					
					// FIXME there must be a sane way
					// https://github.com/sergiomelas/wayplank/issues/+bug/1256626
					force_frame_time_update ();
					last_hide = frame_time;
					
					hidden_changed ();
					return false;
				});
				
				is_first_frame = false;
			}
		}
		
		/**
		 * Updates the color of any real SeparatorDockItem present, based on how
		 * the dock background actually renders (only touches the item's cache
		 * when the color actually changed, to avoid needless redraw churn).
		 */
		Color? cached_background_average_color = null;
		
		void update_separator_colors ()
		{
			if (cached_background_average_color == null && background_buffer != null) {
				cached_background_average_color = background_buffer.average_color ();
			}
			var reference = (cached_background_average_color != null ? cached_background_average_color : theme.FillEndColor);
			var luminance = 0.299 * reference.red + 0.587 * reference.green + 0.114 * reference.blue;
			var is_light = (reference.alpha < 0.35 || luminance > 0.5);
			var alpha = (is_light ? 0.42 : 0.58);
			
			var color = (is_light
				? Color () { red = 0.0, green = 0.0, blue = 0.0, alpha = alpha }
				: Color () { red = 1.0, green = 1.0, blue = 1.0, alpha = alpha });
			var chevron_color = Color () { red = color.red, green = color.green, blue = color.blue, alpha = 0.85 };
			
			foreach (unowned DockItem item in current_items) {
				unowned SeparatorDockItem? sep = (item as SeparatorDockItem);
				if (sep != null && (sep.BarColor.red != color.red
					|| sep.BarColor.green != color.green
					|| sep.BarColor.blue != color.blue
					|| sep.BarColor.alpha != color.alpha)) {
					sep.BarColor = color;
				}
				unowned PinnedExpanderDockItem? expander = (item as PinnedExpanderDockItem);
				if (expander != null && (expander.ChevronColor.red != chevron_color.red
					|| expander.ChevronColor.green != chevron_color.green
					|| expander.ChevronColor.blue != chevron_color.blue
					|| expander.ChevronColor.alpha != chevron_color.alpha)) {
					expander.ChevronColor = chevron_color;
				}
			}
		}
		
		void draw_dock_background (Cairo.Context cr, Gdk.Rectangle background_rect, int x_offset, int y_offset)
		{
			unowned PositionManager position_manager = controller.position_manager;
			
			if (background_rect.width <= 0 || background_rect.height <= 0) {
				background_buffer = null;
				cached_background_average_color = null;
				return;
			}
			
			if (background_buffer == null || background_buffer.Width != background_rect.width
				|| background_buffer.Height != background_rect.height) {
				background_buffer = theme.create_background (background_rect.width, background_rect.height,
					position_manager.Position, main_buffer);
			}
			
			if (hide_progress > 0.0 && theme.CascadeHide) {
				int x, y;
				position_manager.get_background_padding (out x, out y);
				x_offset -= (int) (x * hide_progress);
				y_offset -= (int) (y * hide_progress);
			}
			
			cr.set_source_surface (background_buffer.Internal, background_rect.x + x_offset, background_rect.y + y_offset);
			cr.paint ();
		}
		
		[CCode (instance_pos = -1)]
		void animate_draw_value_for_item (DockItem item, DockItemDrawValue draw_value)
		{
			unowned PositionManager position_manager = controller.position_manager;
			unowned DockItem hovered_item = controller.window.HoveredItem;
			unowned DragManager drag_manager = controller.drag_manager;
			
			var icon_size = (int) draw_value.icon_size;
			var position = position_manager.Position;
			var x_offset = 0.0, y_offset = 0.0;
			
			// check for and calculate click-animation
			var max_click_time = item.ClickedAnimation == AnimationType.BOUNCE ? get_effective_launch_duration_ms () : theme.ClickTime;
			max_click_time *= 1000;
			var click_time = int64.max (0LL, frame_time - item.LastClicked);
			if (click_time < max_click_time) {
				var click_animation_progress = click_time / (double) max_click_time;
				
				switch (item.ClickedAnimation) {
				default:
				case AnimationType.NONE:
					break;
				case AnimationType.BOUNCE:
					int launch_anim = get_effective_launch_animation ();
					if (screen_is_composited && (launch_anim == 0 || launch_anim == 1))
						y_offset += position_manager.LaunchBounceHeight * easing_bounce (click_time, max_click_time, 2);
					break;
				case AnimationType.DARKEN:
					draw_value.darken = double.max (0, Math.sin (Math.PI * click_animation_progress)) * 0.5;
					break;
				case AnimationType.LIGHTEN:
					draw_value.lighten = double.max (0, Math.sin (Math.PI * click_animation_progress)) * 0.5;
					break;
				}
			}
			
			// check for and calculate scroll-animation
			var max_scroll_time = ITEM_SCROLL_DURATION * 1000;
			var scroll_time = int64.max (0LL, frame_time - item.LastScrolled);
			if (scroll_time < max_scroll_time) {
				var scroll_animation_progress = scroll_time / (double) max_scroll_time;
				
				switch (item.ScrolledAnimation) {
				default:
				case AnimationType.NONE:
					break;
				case AnimationType.DARKEN:
					draw_value.darken = double.max (0, Math.sin (Math.PI * scroll_animation_progress)) * 0.5;
					break;
				case AnimationType.LIGHTEN:
					draw_value.lighten = double.max (0, Math.sin (Math.PI * scroll_animation_progress)) * 0.5;
					break;
				}
			}
			
			// check for and calculate hover-animation
			var max_hover_time = ITEM_HOVER_DURATION * 1000;
			var hover_time = int64.max (0LL, frame_time - item.LastHovered);
			if (hover_time < max_hover_time) {
				var hover_animation_progress = 0.0;
				if (hovered_item == item) {
					hover_animation_progress = easing_for_mode (AnimationMode.LINEAR, hover_time, max_hover_time);
				} else {
					hover_animation_progress = 1.0 - easing_for_mode (AnimationMode.LINEAR, hover_time, max_hover_time);
				}
				
				switch (item.HoveredAnimation) {
				default:
				case AnimationType.NONE:
					break;
				case AnimationType.LIGHTEN:
					draw_value.lighten = double.max (draw_value.lighten, hover_animation_progress * 0.2);
					break;
				}
			} else if (hovered_item == item) {
				draw_value.lighten = double.max (draw_value.lighten, 0.2);
			}
			
			if (hovered_item == item && controller.window.menu_is_visible ())
				draw_value.darken += 0.4;
			else if (drag_manager.ExternalDragActive
				&& (drag_manager.DragNeedsCheck || item is FileDockItem)
				&& !drag_manager.drop_is_accepted_by (item))
				draw_value.darken += 0.6;
			
			// bounce icon on urgent state
			if (screen_is_composited && show_notifications && (item.State & ItemState.URGENT) != 0) {
				var urgent_duration = theme.UrgentBounceTime * 1000;
				var urgent_time = int64.max (0LL, frame_time - item.LastUrgent);
				var urgent_cycle = urgent_time % (2000 * 1000);
				if (urgent_cycle < urgent_duration)
					y_offset += position_manager.UrgentBounceHeight * easing_bounce (urgent_cycle, urgent_duration, 1.0);
			}
			
			// animate addition/removal
			unowned DockContainer? container = item.Container;
			var allow_animation = (screen_is_composited && !(item is SeparatorDockItem) && (container == null || container.AddTime < item.AddTime));
			if (allow_animation && item.AddTime > item.RemoveTime) {
				var move_duration = theme.ItemMoveTime * 1000;
				var move_time = int64.max (0LL, frame_time - item.AddTime);
				if (move_time < move_duration) {
					var move_animation_progress = 1.0 - easing_for_mode (AnimationMode.LINEAR, move_time, move_duration);
					draw_value.opacity = easing_for_mode (AnimationMode.EASE_IN_EXPO, move_time, move_duration);
					y_offset -= move_animation_progress * (icon_size + position_manager.BottomPadding);
					draw_value.show_indicator = false;
					
					// calculate the resulting incremental dynamic-animation-offset used to animate the background-resize and icon-offset
					move_animation_progress = 1.0 - easing_for_mode (AnimationMode.EASE_OUT_QUINT, move_time, move_duration);
					dynamic_animation_offset -= move_animation_progress * (icon_size + position_manager.ItemPadding);
					x_offset += dynamic_animation_offset;
				}
			} else if (allow_animation && item.RemoveTime > 0) {
				var move_duration = theme.ItemMoveTime * 1000;
				var move_time = int64.max (0LL, frame_time - item.RemoveTime);
				if (move_time < move_duration) {
					var move_animation_progress = easing_for_mode (AnimationMode.LINEAR, move_time, move_duration);
					draw_value.opacity = 1.0 - easing_for_mode (AnimationMode.EASE_OUT_EXPO, move_time, move_duration);
					y_offset -= move_animation_progress * (icon_size + position_manager.BottomPadding);
					draw_value.show_indicator = false;
					
					// calculate the resulting incremental dynamic-animation-offset used to animate the background-resize and icon-offset
					move_animation_progress = 1.0 - easing_for_mode (AnimationMode.EASE_IN_QUINT, move_time, move_duration);
					dynamic_animation_offset += move_animation_progress * (icon_size + position_manager.ItemPadding);
					x_offset += dynamic_animation_offset - (icon_size + position_manager.ItemPadding);
				}
			}
			
			// animate icon movement on move state
			if ((item.State & ItemState.MOVE) != 0) {
				var move_duration = theme.ItemMoveTime * 1000;
				var move_time = int64.max (0LL, frame_time - item.LastMove);
				if (move_time < move_duration) {
					var move_animation_progress = 0.0;
					if (transient_items.size > 0) {
						if (dynamic_animation_offset > 0)
							move_animation_progress = 1.0 - easing_for_mode (AnimationMode.EASE_IN_QUINT, move_time, move_duration);
						else
							move_animation_progress = 1.0 - easing_for_mode (AnimationMode.EASE_OUT_QUINT, move_time, move_duration);
					} else {
						move_animation_progress = 1.0 - easing_for_mode (AnimationMode.EASE_OUT_CIRC, move_time, move_duration);
					}
					var change = move_animation_progress * (icon_size + position_manager.ItemPadding);
					x_offset += (item.Position < item.LastPosition ? change : -change);
				} else {
					item.unset_move_state ();
				}
			}
			
			// animate icon on invalid state
			if ((item.State & ItemState.INVALID) != 0) {
				var invalid_duration = ITEM_INVALID_DURATION * 1000;
				var invalid_time = int64.max (0LL, frame_time - item.LastValid);
				if (invalid_time < invalid_duration) {
					draw_value.opacity = 0.10 + (0.90 * (Math.cos (invalid_time / (double) invalid_duration * 4.5 * Math.PI) + 1) / 2);
				} else {
					draw_value.opacity = 0.10;
				}
			}
			
			if (x_offset != 0.0)
				draw_value.move_right (position, x_offset);
			
			if (y_offset != 0.0)
				draw_value.move_in (position, y_offset);
		}
		
		[CCode (instance_pos = -1)]
		void post_process_draw_values (Gee.HashMap<DockElement, DockItemDrawValue?> draw_values)
		{
			if (dynamic_animation_offset == 0.0)
				return;
			
			unowned PositionManager position_manager = controller.position_manager;
			var position = position_manager.Position;
			
			var x_offset = 0.0;
			
			switch (position_manager.Alignment) {
			default:
			case Gtk.Align.CENTER:
				x_offset -= Math.round (dynamic_animation_offset / 2.0);
				break;
			case Gtk.Align.START:
				break;
			case Gtk.Align.END:
				x_offset -= Math.round (dynamic_animation_offset);
				break;
			case Gtk.Align.FILL:
				switch (position_manager.ItemsAlignment) {
				default:
				case Gtk.Align.FILL:
				case Gtk.Align.CENTER:
					x_offset -= Math.round (dynamic_animation_offset / 2.0);
					break;
				case Gtk.Align.START:
					break;
				case Gtk.Align.END:
					x_offset -= Math.round (dynamic_animation_offset);
					break;
				}
				break;
			}
			
			if (x_offset == 0.0)
				return;
			
			draw_values.map_iterator ().foreach ((i, val) => {
				val.move_right (position, x_offset);
				return true;
			});
		}
		
		inline Surface get_item_surface (DockItem item, int icon_size)
		{
			var private_icon_surface = item.get_surface (icon_size, icon_size, main_buffer);
			if (!screen_is_composited)
				return private_icon_surface;
			
			string? drawing_status;
			unowned PositionManager position_manager = controller.position_manager;
			var max_icon_size = position_manager.ZoomIconSize * window_scale_factor;
			if (icon_size < max_icon_size
				&& ((drawing_status = private_icon_surface.steal_qdata<string> (quark_surface_stats)) != null
				&& drawing_status == SURFACE_STATS_DRAWING_TIME_EXCEEDED))
				item.get_surface (max_icon_size, max_icon_size, main_buffer);
			
			return private_icon_surface;
		}
		
		inline Surface get_scratch_icon_surface (int size)
		{
			var scratch = item_scratch_pool.get (size);
			if (scratch == null) {
				scratch = new Surface.with_surface (size, size, main_buffer);
				item_scratch_pool.set (size, scratch);
			}
			return scratch;
		}

		void draw_item (Cairo.Context cr, DockItem item, DockItemDrawValue draw_value, int64 frame_time)
		{
			unowned PositionManager position_manager = controller.position_manager;
			unowned SeparatorDockItem? separator = (item as SeparatorDockItem);
			if (separator != null)
				separator.set_horizontal_orientation (position_manager.is_horizontal_dock ());
			unowned PinnedExpanderDockItem? pinned_expander = (item as PinnedExpanderDockItem);
			if (pinned_expander != null)
				pinned_expander.set_horizontal_orientation (position_manager.is_horizontal_dock ());
			var icon_size = (int) draw_value.icon_size * window_scale_factor;
			var position = position_manager.Position;
			
			// load the icon
#if BENCHMARK
			var start = new DateTime.now_local ();
#endif
			bool has_overlay = (item.CountVisible || item.ProgressVisible);
			bool has_tint = (draw_value.lighten > 0 || draw_value.darken > 0);

			Surface icon_surface;
			if (has_overlay || has_tint) {
				var base_surface = get_item_surface (item, icon_size);
				icon_surface = get_scratch_icon_surface (icon_size);
				unowned Cairo.Context icon_cr = icon_surface.Context;
				icon_cr.set_operator (Cairo.Operator.SOURCE);
				icon_cr.set_source_surface (base_surface.Internal, 0, 0);
				icon_cr.paint ();
				icon_cr.set_operator (Cairo.Operator.OVER);

				if (has_overlay) {
					var icon_overlay_surface = item.get_foreground_surface (icon_size, icon_size, main_buffer, (DrawDataFunc<DockItem>) draw_item_foreground);
					if (icon_overlay_surface != null) {
						icon_cr.set_source_surface (icon_overlay_surface.Internal, 0, 0);
						icon_cr.paint ();
					}
				}

				// lighten the icon (1:1 unscaled SIMD fast path)
				if (draw_value.lighten > 0) {
					icon_cr.set_source_surface (base_surface.Internal, 0, 0);
					icon_cr.set_operator (Cairo.Operator.ADD);
					icon_cr.paint_with_alpha (draw_value.lighten);
					icon_cr.set_operator (Cairo.Operator.OVER);
				}

				// darken the icon
				if (draw_value.darken > 0) {
					icon_cr.rectangle (0, 0, icon_surface.Width, icon_surface.Height);
					icon_cr.set_source_rgba (0, 0, 0, draw_value.darken);
					icon_cr.set_operator (Cairo.Operator.ATOP);
					icon_cr.fill ();
					icon_cr.set_operator (Cairo.Operator.OVER);
				}
			} else {
				icon_surface = get_item_surface (item, icon_size);
			}

			double base_scale_x = ((double) icon_size / icon_surface.Width) / window_scale_factor;
			double base_scale_y = ((double) icon_size / icon_surface.Height) / window_scale_factor;
			
			// draw active highlight
			int highlight_mode = get_effective_active_highlight ();
			double active_opacity = 0.0;
			if (highlight_mode != 7) {
				var active_time = int64.max (0LL, frame_time - item.LastActive);
				active_opacity = double.min (1.0, active_time / (double) (get_effective_active_duration_ms () * 1000));
				if ((item.State & ItemState.ACTIVE) == 0)
					active_opacity = 1.0 - active_opacity;
				if (active_opacity > 0.0) {
					var glow_color = get_item_accent_color (item);
					switch (highlight_mode) {
					default:
					case 0: // Classic Box
						theme.draw_active_glow (main_buffer, background_rect, draw_value.background_region, item.AverageIconColor, active_opacity, position);
						break;
					case 1: // Icon Glow
						theme.draw_active_icon_glow (main_buffer, draw_value.draw_region, glow_color, active_opacity);
						break;
					case 2: // Spotlight
						theme.draw_active_spotlight (main_buffer, background_rect, draw_value.draw_region, glow_color, active_opacity, position);
						break;
					case 3: // Rounded Card
						theme.draw_active_rounded_card (main_buffer, draw_value.draw_region, glow_color, active_opacity);
						break;
					case 4: // Accent Bar (drawn in indicator slot below)
						break;
					case 5: // Rim Halo
						theme.draw_active_rim_halo (main_buffer, draw_value.draw_region, glow_color, active_opacity);
						break;
					case 6: // Floor Reflection
						theme.draw_active_reflection (main_buffer, icon_surface, background_rect, draw_value.draw_region, window_scale_factor, active_opacity, position);
						break;
					}
				}
			}
			
			// draw the icon (with optional launch / click animation)
			var draw_region = draw_value.draw_region;
			int launch_anim = get_effective_launch_animation ();
			var max_anim_time = get_effective_launch_duration_ms () * 1000;
			var anim_elapsed = int64.max (0LL, frame_time - item.LastClicked);
			bool in_custom_launch = (screen_is_composited
				&& item.ClickedAnimation == AnimationType.BOUNCE
				&& launch_anim >= 1 && launch_anim <= 7
				&& anim_elapsed < max_anim_time);

			if (in_custom_launch) {
				double p = anim_elapsed / (double) max_anim_time;
				double cx = draw_region.x + draw_region.width / 2.0;
				double cy = draw_region.y + draw_region.height / 2.0;

				switch (launch_anim) {
				case 1: // Elastic (squash & stretch anchored at dock-side base)
					double stretch = 0.16 * Math.cos (4.0 * Math.PI * p) * (1.0 - p);
					double sx = 1.0, sy = 1.0;
					double px = cx, py = cy;
					switch (position) {
					default:
					case Gtk.PositionType.BOTTOM:
						sx = 1.0 + stretch; sy = 1.0 - stretch;
						py = draw_region.y + draw_region.height;
						cr.save ();
						cr.translate (px, py);
						cr.scale (sx * base_scale_x, sy * base_scale_y);
						cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, -icon_surface.Height);
						break;
					case Gtk.PositionType.TOP:
						sx = 1.0 + stretch; sy = 1.0 - stretch;
						py = draw_region.y;
						cr.save ();
						cr.translate (px, py);
						cr.scale (sx * base_scale_x, sy * base_scale_y);
						cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, 0);
						break;
					case Gtk.PositionType.LEFT:
						sx = 1.0 - stretch; sy = 1.0 + stretch;
						px = draw_region.x;
						cr.save ();
						cr.translate (px, py);
						cr.scale (sx * base_scale_x, sy * base_scale_y);
						cr.set_source_surface (icon_surface.Internal, 0, -icon_surface.Height / 2.0);
						break;
					case Gtk.PositionType.RIGHT:
						sx = 1.0 - stretch; sy = 1.0 + stretch;
						px = draw_region.x + draw_region.width;
						cr.save ();
						cr.translate (px, py);
						cr.scale (sx * base_scale_x, sy * base_scale_y);
						cr.set_source_surface (icon_surface.Internal, -icon_surface.Width, -icon_surface.Height / 2.0);
						break;
					}
					if (draw_value.opacity < 1.0)
						cr.paint_with_alpha (draw_value.opacity);
					else
						cr.paint ();
					cr.restore ();
					break;

				case 2: // Pulse (expanding ghost halo + gentle breath)
					double halo_scale = 1.0 + 0.42 * Math.sin (0.5 * Math.PI * p);
					double halo_alpha = 0.52 * (1.0 - p) * (1.0 - p) * draw_value.opacity;
					double icon_scale = 1.0 + 0.12 * Math.sin (Math.PI * p);

					if (halo_alpha > 0.005) {
						cr.save ();
						cr.translate (cx, cy);
						cr.scale (halo_scale * base_scale_x, halo_scale * base_scale_y);
						cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, -icon_surface.Height / 2.0);
						cr.paint_with_alpha (halo_alpha);
						cr.restore ();
					}

					cr.save ();
					cr.translate (cx, cy);
					cr.scale (icon_scale * base_scale_x, icon_scale * base_scale_y);
					cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, -icon_surface.Height / 2.0);
					if (draw_value.opacity < 1.0)
						cr.paint_with_alpha (draw_value.opacity);
					else
						cr.paint ();
					cr.restore ();
					break;

				case 3: // Spring (tactile press dip + elastic pop)
					double sp_scale = 1.0 - 0.22 * Math.sin (2.5 * Math.PI * p) * (1.0 - p);
					cr.save ();
					cr.translate (cx, cy);
					cr.scale (sp_scale * base_scale_x, sp_scale * base_scale_y);
					cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, -icon_surface.Height / 2.0);
					if (draw_value.opacity < 1.0)
						cr.paint_with_alpha (draw_value.opacity);
					else
						cr.paint ();
					cr.restore ();
					break;

				case 4: // Ripple (expanding colored shockwave ring + subtle tap)
					var ripple_color = get_item_accent_color (item);
					double ease_p = 1.0 - (1.0 - p) * (1.0 - p);
					double ring_r = draw_region.width * (0.28 + 0.44 * ease_p);
					double ring_alpha = 0.82 * (1.0 - p) * (1.0 - p) * draw_value.opacity;
					double tap_scale = 1.0 + 0.06 * Math.sin (Math.PI * p);

					if (ring_alpha > 0.005) {
						cr.save ();
						cr.arc (cx, cy, ring_r, 0, 2.0 * Math.PI);
						cr.set_line_width (3.2 * (1.0 - p) + 1.0);
						cr.set_source_rgba (ripple_color.red, ripple_color.green, ripple_color.blue, ring_alpha);
						cr.stroke ();
						cr.restore ();
					}

					cr.save ();
					cr.translate (cx, cy);
					cr.scale (tap_scale * base_scale_x, tap_scale * base_scale_y);
					cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, -icon_surface.Height / 2.0);
					if (draw_value.opacity < 1.0)
						cr.paint_with_alpha (draw_value.opacity);
					else
						cr.paint ();
					cr.restore ();
					break;

				case 5: // Flip (ease-out 360-degree coin spin with matrix singularity guard)
					double flip_ease = 1.0 - (1.0 - p) * (1.0 - p);
					double flip_sx = Math.cos (2.0 * Math.PI * flip_ease);
					if (Math.fabs (flip_sx) < 0.03)
						flip_sx = (flip_sx >= 0.0 ? 0.03 : -0.03);
					cr.save ();
					cr.translate (cx, cy);
					cr.scale (flip_sx * base_scale_x, base_scale_y);
					cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, -icon_surface.Height / 2.0);
					if (draw_value.opacity < 1.0)
						cr.paint_with_alpha (draw_value.opacity);
					else
						cr.paint ();
					cr.restore ();
					break;

				case 6: // Swing (damped pendulum wiggle pivoted at dock-side base)
					double angle = 0.28 * Math.sin (3.0 * Math.PI * p) * (1.0 - p);
					cr.save ();
					switch (position) {
					default:
					case Gtk.PositionType.BOTTOM:
						cr.translate (cx, draw_region.y + draw_region.height);
						cr.rotate (angle);
						cr.scale (base_scale_x, base_scale_y);
						cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, -icon_surface.Height);
						break;
					case Gtk.PositionType.TOP:
						cr.translate (cx, draw_region.y);
						cr.rotate (-angle);
						cr.scale (base_scale_x, base_scale_y);
						cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, 0);
						break;
					case Gtk.PositionType.LEFT:
						cr.translate (draw_region.x, cy);
						cr.rotate (angle);
						cr.scale (base_scale_x, base_scale_y);
						cr.set_source_surface (icon_surface.Internal, 0, -icon_surface.Height / 2.0);
						break;
					case Gtk.PositionType.RIGHT:
						cr.translate (draw_region.x + draw_region.width, cy);
						cr.rotate (-angle);
						cr.scale (base_scale_x, base_scale_y);
						cr.set_source_surface (icon_surface.Internal, -icon_surface.Width, -icon_surface.Height / 2.0);
						break;
					}
					if (draw_value.opacity < 1.0)
						cr.paint_with_alpha (draw_value.opacity);
					else
						cr.paint ();
					cr.restore ();
					break;

				default:
				case 7: // Flash (camera-strobe white silhouette flash + radiant accent bloom)
					double primary = (p < 0.08)
						? (p / 0.08)
						: Math.pow (1.0 - (p - 0.08) / 0.92, 2.2);
					double after_pulse = 0.40 * Math.exp (-Math.pow ((p - 0.34) / 0.09, 2.0));
					double flash_env = (primary + after_pulse).clamp (0.0, 1.0);
					double flash_scale = 1.0 + 0.07 * flash_env;
					var flash_color = get_item_accent_color (item);

					if (flash_env > 0.01) {
						double bloom_r = draw_region.width * (0.56 + 0.24 * flash_env);
						var bloom = new Cairo.Pattern.radial (cx, cy, draw_region.width * 0.08, cx, cy, bloom_r);
						bloom.add_color_stop_rgba (0.00, 1.0, 1.0, 1.0, 0.72 * flash_env * draw_value.opacity);
						bloom.add_color_stop_rgba (0.48, flash_color.red, flash_color.green, flash_color.blue, 0.44 * flash_env * draw_value.opacity);
						bloom.add_color_stop_rgba (1.00, flash_color.red, flash_color.green, flash_color.blue, 0.0);
						cr.save ();
						cr.arc (cx, cy, bloom_r, 0, 2.0 * Math.PI);
						cr.set_source (bloom);
						cr.fill ();
						cr.restore ();
					}

					cr.save ();
					cr.push_group ();
					cr.translate (cx, cy);
					cr.scale (flash_scale * base_scale_x, flash_scale * base_scale_y);
					cr.set_source_surface (icon_surface.Internal, -icon_surface.Width / 2.0, -icon_surface.Height / 2.0);
					cr.paint ();
					if (flash_env > 0.005) {
						cr.set_operator (Cairo.Operator.ATOP);
						cr.set_source_rgba (1.0, 1.0, 1.0, 0.84 * flash_env);
						cr.paint ();
					}
					cr.pop_group_to_source ();
					if (draw_value.opacity < 1.0)
						cr.paint_with_alpha (draw_value.opacity);
					else
						cr.paint ();
					cr.restore ();
					break;
				}
			} else {
				if (window_scale_factor > 1) {
					cr.save ();
					cr.scale (1.0 / window_scale_factor, 1.0 / window_scale_factor);
				}
				cr.set_source_surface (icon_surface.Internal, draw_region.x * window_scale_factor, draw_region.y * window_scale_factor);
				if (draw_value.opacity < 1.0)
					cr.paint_with_alpha (draw_value.opacity);
				else
					cr.paint ();
				if (window_scale_factor > 1)
					cr.restore ();
			}
			
			// draw inner-side focused Accent Bar (follows zoomed draw_region) and normal running dots
			if (highlight_mode == 4 && active_opacity > 0.0)
				theme.draw_active_accent_bar (main_buffer, draw_value.draw_region, position_manager.DockWidth, position_manager.DockHeight, get_item_accent_color (item), active_opacity, position);

			if (draw_value.show_indicator && item.Indicator != IndicatorState.NONE)
				draw_indicator_state (cr, draw_value.draw_region, item.Indicator, item.State);
		}
		
		void draw_item_shadow (Cairo.Context cr, DockItem item, DockItemDrawValue draw_value)
		{
			unowned PositionManager position_manager = controller.position_manager;
			var shadow_size = position_manager.IconShadowSize;
			if (shadow_size <= 0)
				return;

			// Inflate size to fit shadow (1:1 integer cached surface, matching V0.7.0)
			var icon_size = (int) (draw_value.icon_size + 2 * shadow_size) * window_scale_factor;
			var icon_shadow_surface = item.get_background_surface (icon_size, icon_size, main_buffer, (DrawDataFunc<DockItem>) draw_item_background);
			if (icon_shadow_surface == null)
				return;

			if (window_scale_factor > 1) {
				cr.save ();
				cr.scale (1.0 / window_scale_factor, 1.0 / window_scale_factor);
			}
			var draw_region = draw_value.draw_region;
			cr.set_operator (Cairo.Operator.OVER);
			cr.set_source_surface (icon_shadow_surface.Internal, (draw_region.x - shadow_size) * window_scale_factor, (draw_region.y - shadow_size) * window_scale_factor);
			if (draw_value.opacity < 1.0)
				cr.paint_with_alpha (draw_value.opacity);
			else
				cr.paint ();
			if (window_scale_factor > 1)
				cr.restore ();
		}
		
		[CCode (instance_pos = -1)]
		Surface draw_item_foreground (int width, int height, Surface model, DockItem item)
		{
			Logger.verbose ("DockItem.draw_item_overlay (width = %i, height = %i)", width, height);
			var surface = new Surface.with_surface (width, height, model);
			
			var icon_size = int.min (width, height);
			var urgent_color = theme.BadgeColor;
			if (urgent_color.equal ({0.0, 0.0, 0.0, 0.0})) {
				urgent_color = get_styled_color ();
				urgent_color.add_hue (theme.UrgentHueShift);
			}
			
			// draw item's count / badge
			if (item.CountVisible)
				theme.draw_item_badge (surface, icon_size, urgent_color, item.get_badge_text ());
			
			// draw item's progress
			if (item.ProgressVisible)
				theme.draw_item_progress (surface, icon_size, urgent_color, item.Progress);
			
			return surface;
		}
		
		[CCode (instance_pos = -1)]
		Surface draw_item_background (int width, int height, Surface model, DockItem item)
		{
			unowned PositionManager position_manager = controller.position_manager;
			var shadow_size = position_manager.IconShadowSize * window_scale_factor;
			var icon_size = int.max (1, width - 2 * shadow_size);
			var icon_surface = item.get_surface (icon_size, icon_size, model);
			
			Logger.verbose ("DockItem.draw_icon_with_shadow (width = %i, height = %i, shadow_size = %i)", width, height, shadow_size);
			var surface = new Surface.with_surface (width, height, model);
			unowned Cairo.Context cr = surface.Context;
			var shadow_surface = icon_surface.create_mask (0.4, null);
			
			var xoffset = 0, yoffset = 0;
			switch (position_manager.Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				yoffset = -shadow_size / 4;
				break;
			case Gtk.PositionType.TOP:
				yoffset = shadow_size / 4;
				break;
			case Gtk.PositionType.LEFT:
				xoffset = shadow_size / 4;
				break;
			case Gtk.PositionType.RIGHT:
				xoffset = -shadow_size / 4;
				break;
			}
			
			cr.set_source_surface (shadow_surface.Internal, shadow_size + xoffset, shadow_size + yoffset);
			cr.paint_with_alpha (0.44);
			surface.gaussian_blur (shadow_size);
			
			return surface;
		}
		
		void draw_indicator_state (Cairo.Context cr, Gdk.Rectangle item_rect, IndicatorState indicator, ItemState item_state)
		{
			unowned PositionManager position_manager = controller.position_manager;
			
			if (indicator_buffer == null) {
				var indicator_color = get_styled_color ();
				indicator_color.set_min_sat (0.4);
				indicator_buffer = theme.create_indicator (position_manager.IndicatorSize, indicator_color, main_buffer);
			}
			if (urgent_indicator_buffer == null) {
				var urgent_indicator_color = get_styled_color ();
				urgent_indicator_color.add_hue (theme.UrgentHueShift);
				urgent_indicator_color.set_sat (1.0);
				urgent_indicator_buffer = theme.create_indicator (position_manager.IndicatorSize, urgent_indicator_color, main_buffer);
			}
			
			unowned Surface indicator_surface = (item_state & ItemState.URGENT) != 0 ? urgent_indicator_buffer : indicator_buffer;
			
			var offset = Math.round (position_manager.IconSize / 6.5).clamp (6.0, 10.0);
			var x = 0.0, y = 0.0;
			switch (position_manager.Position) {
			default:
			case Gtk.PositionType.BOTTOM:
				x = item_rect.x + item_rect.width / 2.0 - indicator_surface.Width / 2.0;
				y = main_buffer.Height - indicator_surface.Height / 2.0 - offset;
				break;
			case Gtk.PositionType.TOP:
				x = item_rect.x + item_rect.width / 2.0 - indicator_surface.Width / 2.0;
				y = - indicator_surface.Height / 2.0 + offset;
				break;
			case Gtk.PositionType.LEFT:
				x = - indicator_surface.Width / 2.0 + offset;
				y = item_rect.y + item_rect.height / 2.0 - indicator_surface.Height / 2.0;
				break;
			case Gtk.PositionType.RIGHT:
				x = main_buffer.Width - indicator_surface.Width / 2.0 - offset;
				y = item_rect.y + item_rect.height / 2.0 - indicator_surface.Height / 2.0;
				break;
			}
			
			if (indicator == IndicatorState.SINGLE) {
				cr.set_source_surface (indicator_surface.Internal, x, y);
				cr.paint ();
			} else {
				var x_offset = 0.0, y_offset = 0.0;
				if (position_manager.is_horizontal_dock ())
					x_offset = position_manager.IconSize / 8.0;
				else
					y_offset = position_manager.IconSize / 8.0;
				
				cr.set_source_surface (indicator_surface.Internal, x - x_offset, y - y_offset);
				cr.paint ();
				cr.set_source_surface (indicator_surface.Internal, x + x_offset, y + y_offset);
				cr.paint ();
			}
		}
		
		void draw_urgent_glow (DockItem item, Cairo.Context cr, int64 frame_time)
		{
			if ((item.State & ItemState.URGENT) == 0)
				return;
			
			var diff = int64.max (0LL, frame_time - item.LastUrgent);
			if (diff >= theme.GlowTime * 1000)
				return;
			
			unowned PositionManager position_manager = controller.position_manager;
			var x_offset = 0, y_offset = 0;
			
			if (urgent_glow_buffer == null) {
				var urgent_color = get_styled_color ();
				urgent_color.add_hue (theme.UrgentHueShift);
				urgent_color.set_sat (1.0);
				urgent_glow_buffer = theme.create_urgent_glow (position_manager.GlowSize, urgent_color, main_buffer);
			}
			
			position_manager.get_urgent_glow_position (item, out x_offset, out y_offset);
			
			cr.set_source_surface (urgent_glow_buffer.Internal, x_offset, y_offset);
			var opacity = 0.2 + (0.75 * (Math.sin (diff / (double) (theme.GlowPulseTime * 1000) * 2 * Math.PI) + 1) / 2);
			cr.paint_with_alpha (opacity);
		}
		
		Color get_styled_color ()
		{
			if (cached_styled_color != null)
				return cached_styled_color;

			unowned Gtk.StyleContext context = theme.get_style_context ();
			Gdk.RGBA styled_rgba;
			if (!context.lookup_color ("theme_selected_bg_color", out styled_rgba))
				context.get (context.get_state (), "background-color", out styled_rgba, null);
			var color = (Color) styled_rgba;
			color.set_min_val (90 / (double) uint16.MAX);
			cached_styled_color = color;
			return color;
		}
		
		void hidden_changed ()
		{
			force_frame_time_update ();
			var now = frame_time;
			var diff = now - last_hide;
			var time = (theme.FadeOpacity == 1.0 ? theme.HideTime : theme.FadeTime) * 1000;
			
			if (diff < time)
				last_hide = now + (diff - time);
			else
				last_hide = now;
			
			controller.position_manager.update_dock_position ();
			controller.window.update_size_and_position ();
			controller.window.update_icon_regions ();
			
			animated_draw ();
		}
		
		void hovered_changed ()
		{
			force_frame_time_update ();
			var now = frame_time;
			var diff = now - last_hovered_changed;
			var time = DOCK_ZOOM_DURATION * 1000;
			
			if (diff < time)
				last_hovered_changed = now + (diff - time);
			else
				last_hovered_changed = now;
			
			animated_draw ();
		}
		
		public void update_local_cursor (int x, int y)
		{
			Gdk.Point new_cursor = { x, y };
			if (local_cursor == new_cursor)
				return;
			
			local_cursor = new_cursor;
			
			if (screen_is_composited) {
				last_cursor_motion = GLib.get_monotonic_time ();
				zoom_changed = true;
				animated_draw ();
			}
		}
		
		public void animate_items (Gee.List<DockElement> elements)
		{
			if (!screen_is_composited)
				return;
			
			foreach (var element in elements) {
				DockItem? item = (element as DockItem);
				if (item != null && !(item is SeparatorDockItem))
					transient_items.add (item);
			}
			
			if (transient_items.size > 0)
				animated_draw ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override bool animation_needed (int64 frame_time)
		{
			if (controller.position_manager.is_scrolling ())
				return true;

			if (zoom_changed) {
				zoom_changed = false;
				return true;
			}
			
			if (frame_time - last_cursor_motion <= 50 * 1000)
				return true;
			
			if (frame_time - last_hovered_changed <= DOCK_ZOOM_DURATION * 1000)
				return true;
			
			if (theme.FadeOpacity == 1.0) {
				if (frame_time - last_hide <= theme.HideTime * 1000)
					return true;
			} else {
				if (frame_time - last_hide <= theme.FadeTime * 1000)
					return true;
			}
			
			if (watching_shrink || transient_items.size > 0)
				return true;
			
			foreach (var item in current_items)
				if (item_animation_needed (item, frame_time))
					return true;
			
			return false;
		}

		protected override void animation_finished ()
		{
			controller.window.set_input_mask ();
		}

		inline bool item_animation_needed (DockItem item, int64 render_time)
		{
			if (item.ClickedAnimation != AnimationType.NONE
				&& !(item.ClickedAnimation == AnimationType.BOUNCE && get_effective_launch_animation () == 8)
				&& render_time - item.LastClicked <= (item.ClickedAnimation == AnimationType.BOUNCE ? get_effective_launch_duration_ms () : theme.ClickTime) * 1000)
				return true;
			if (item.HoveredAnimation != AnimationType.NONE
				&& render_time - item.LastHovered <= ITEM_HOVER_DURATION * 1000)
				return true;
			if (item.ScrolledAnimation != AnimationType.NONE
				&& render_time - item.LastScrolled <= ITEM_SCROLL_DURATION * 1000)
				return true;
			if (item.LastActive > 0 && render_time - item.LastActive <= get_effective_active_duration_ms () * 1000)
				return true;
			if (show_notifications && (item.State & ItemState.URGENT) != 0)
				return true;
			if (item.LastMove > 0 && (item.State & ItemState.MOVE) != 0 && render_time - item.LastMove <= theme.ItemMoveTime * 1000)
				return true;
			if (item.AddTime > 0 && render_time - item.AddTime <= theme.ItemMoveTime * 1000)
				return true;
			if (item.RemoveTime > 0 && render_time - item.RemoveTime <= theme.ItemMoveTime * 1000)
				return true;
			if (item.LastValid > 0 && (item.State & ItemState.INVALID) != 0 && render_time - item.LastValid <= ITEM_INVALID_DURATION * 1000)
				return true;
			
			return false;
		}
		
		static int compare_dock_item_position (DockItem i1, DockItem i2)
		{
			var p_i1 = i1.Position;
			var p_i2 = i2.Position;
			
			if (p_i1 > p_i2)
				return 1;
			
			if (p_i1 < p_i2)
				return -1;
			
			if (i1.RemoveTime > i2.RemoveTime)
				return -1;
			
			return 1;
		}

		// =========================================================================
		// Dock Overflow Edge Indicators (Fork Integration by 史有虎 / IFtiger-hu)
		// =========================================================================
		void draw_scroll_edge_indicators (Cairo.Context cr, Gdk.Rectangle base_rect, int x_offset = 0, int y_offset = 0)
		{
			unowned PositionManager pm = controller.position_manager;
			Gdk.Rectangle rect = { base_rect.x + x_offset, base_rect.y + y_offset, base_rect.width, base_rect.height };
			double fade_w = 42.0;

			if (pm.is_horizontal_dock ()) {
				// Left edge gradient when scroll_offset > 2
				if (pm.scroll_offset > 2.0) {
					cr.save ();
					var pat = new Cairo.Pattern.linear (rect.x, 0, rect.x + fade_w, 0);
					pat.add_color_stop_rgba (0.0, theme.FillEndColor.red, theme.FillEndColor.green, theme.FillEndColor.blue, 0.85);
					pat.add_color_stop_rgba (1.0, theme.FillEndColor.red, theme.FillEndColor.green, theme.FillEndColor.blue, 0.0);
					cr.set_source (pat);
					cr.rectangle (rect.x, rect.y, fade_w, rect.height);
					cr.fill ();

					// Subtle glow indicator chevron "<"
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.65);
					cr.set_line_width (2.0);
					cr.set_line_cap (Cairo.LineCap.ROUND);
					cr.set_line_join (Cairo.LineJoin.ROUND);
					cr.move_to (rect.x + 16, rect.y + rect.height / 2.0 - 6);
					cr.line_to (rect.x + 10, rect.y + rect.height / 2.0);
					cr.line_to (rect.x + 16, rect.y + rect.height / 2.0 + 6);
					cr.stroke ();
					cr.restore ();
				}

				// Right edge gradient when scroll_offset < max_scroll_offset - 2
				if (pm.scroll_offset < pm.max_scroll_offset - 2.0) {
					cr.save ();
					var pat = new Cairo.Pattern.linear (rect.x + rect.width - fade_w, 0, rect.x + rect.width, 0);
					pat.add_color_stop_rgba (0.0, theme.FillEndColor.red, theme.FillEndColor.green, theme.FillEndColor.blue, 0.0);
					pat.add_color_stop_rgba (1.0, theme.FillEndColor.red, theme.FillEndColor.green, theme.FillEndColor.blue, 0.85);
					cr.set_source (pat);
					cr.rectangle (rect.x + rect.width - fade_w, rect.y, fade_w, rect.height);
					cr.fill ();

					// Subtle glow indicator chevron ">"
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.65);
					cr.set_line_width (2.0);
					cr.set_line_cap (Cairo.LineCap.ROUND);
					cr.set_line_join (Cairo.LineJoin.ROUND);
					cr.move_to (rect.x + rect.width - 16, rect.y + rect.height / 2.0 - 6);
					cr.line_to (rect.x + rect.width - 10, rect.y + rect.height / 2.0);
					cr.line_to (rect.x + rect.width - 16, rect.y + rect.height / 2.0 + 6);
					cr.stroke ();
					cr.restore ();
				}
			} else {
				// Top edge gradient when scroll_offset > 2
				if (pm.scroll_offset > 2.0) {
					cr.save ();
					var pat = new Cairo.Pattern.linear (0, rect.y, 0, rect.y + fade_w);
					pat.add_color_stop_rgba (0.0, theme.FillEndColor.red, theme.FillEndColor.green, theme.FillEndColor.blue, 0.85);
					pat.add_color_stop_rgba (1.0, theme.FillEndColor.red, theme.FillEndColor.green, theme.FillEndColor.blue, 0.0);
					cr.set_source (pat);
					cr.rectangle (rect.x, rect.y, rect.width, fade_w);
					cr.fill ();

					// Subtle glow indicator chevron "^"
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.65);
					cr.set_line_width (2.0);
					cr.set_line_cap (Cairo.LineCap.ROUND);
					cr.set_line_join (Cairo.LineJoin.ROUND);
					cr.move_to (rect.x + rect.width / 2.0 - 6, rect.y + 16);
					cr.line_to (rect.x + rect.width / 2.0, rect.y + 10);
					cr.line_to (rect.x + rect.width / 2.0 + 6, rect.y + 16);
					cr.stroke ();
					cr.restore ();
				}

				// Bottom edge gradient when scroll_offset < max_scroll_offset - 2
				if (pm.scroll_offset < pm.max_scroll_offset - 2.0) {
					cr.save ();
					var pat = new Cairo.Pattern.linear (0, rect.y + rect.height - fade_w, 0, rect.y + rect.height);
					pat.add_color_stop_rgba (0.0, theme.FillEndColor.red, theme.FillEndColor.green, theme.FillEndColor.blue, 0.0);
					pat.add_color_stop_rgba (1.0, theme.FillEndColor.red, theme.FillEndColor.green, theme.FillEndColor.blue, 0.85);
					cr.set_source (pat);
					cr.rectangle (rect.x, rect.y + rect.height - fade_w, rect.width, fade_w);
					cr.fill ();

					// Subtle glow indicator chevron "v"
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.65);
					cr.set_line_width (2.0);
					cr.set_line_cap (Cairo.LineCap.ROUND);
					cr.set_line_join (Cairo.LineJoin.ROUND);
					cr.move_to (rect.x + rect.width / 2.0 - 6, rect.y + rect.height - 16);
					cr.line_to (rect.x + rect.width / 2.0, rect.y + rect.height - 10);
					cr.line_to (rect.x + rect.width / 2.0 + 6, rect.y + rect.height - 16);
					cr.stroke ();
					cr.restore ();
				}
			}
		}

		static double easing_bounce (double t, double d, double n)
			requires (t >= 0.0 && d > 0.0 && n >= 1.0)
			requires (t <= d)
		{
			var p = t / d;
			return Math.fabs (Math.sin (n * Math.PI * p) * double.min (1.0, (1.0 - p) * (2.0 * n) / (2.0 * n - 1.0)));
		}
		
		static unowned string cairo_surface_type_to_string (Cairo.SurfaceType type)
		{
			unowned string result;
			
			switch (type) {
			case Cairo.SurfaceType.IMAGE: result = "IMAGE"; break;
			case Cairo.SurfaceType.PDF: result = "PDF"; break;
			case Cairo.SurfaceType.PS: result = "PS"; break;
			case Cairo.SurfaceType.XLIB: result = "XLIB"; break;
			case Cairo.SurfaceType.XCB: result = "XCB"; break;
			case Cairo.SurfaceType.GLITZ: result = "GLITZ"; break;
			case Cairo.SurfaceType.QUARTZ: result = "QUARTZ"; break;
			case Cairo.SurfaceType.WIN32: result = "WIN32"; break;
			case Cairo.SurfaceType.BEOS: result = "BEOS"; break;
			case Cairo.SurfaceType.DIRECTFB: result = "DIRECTFB"; break;
			case Cairo.SurfaceType.SVG: result = "SVG"; break;
			case Cairo.SurfaceType.OS2: result = "OS2"; break;
			case Cairo.SurfaceType.WIN32_PRINTING: result = "WIN32_PRINTING"; break;
			case Cairo.SurfaceType.QUARTZ_IMAGE: result = "QUARTZ_IMAGE"; break;
			case Cairo.SurfaceType.SCRIPT: result = "SCRIPT"; break;
			case Cairo.SurfaceType.QT: result = "QT"; break;
			case Cairo.SurfaceType.RECORDING: result = "RECORDING"; break;
			case Cairo.SurfaceType.VG: result = "VG"; break;
			case Cairo.SurfaceType.GL: result = "GL"; break;
			case Cairo.SurfaceType.DRM: result = "DRM"; break;
			case Cairo.SurfaceType.TEE: result = "TEE"; break;
			case Cairo.SurfaceType.XML: result = "XML"; break;
			case Cairo.SurfaceType.SKIA: result = "SKIA"; break;
			case Cairo.SurfaceType.SUBSURFACE: result = "SUBSURFACE"; break;
			//FIXME Available in cairo since 1.12
			//case Cairo.SurfaceType.COGL: result = "COGL"; break;
			default: result = "???"; break;
			}
			
			return result;
		}
	}
}
