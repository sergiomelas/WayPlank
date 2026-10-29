//
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
	 * Floating Cairo window cards popup window for multi-window applications.
	 * Positioned above or beside the dock using exact surgical tooltip/menu coordinates,
	 * completely preserving dock HAL stability while adopting the fork's pill card aesthetics.
	 */
	public class WindowCardsWindow : Gtk.Window
	{
		const int GAP = 4;
		const int CARD_WIDTH = 204;
		const int CARD_HEIGHT = 148;
		public const uint DISMISS_DELAY = 450U;

		public DockController controller { get; construct; }
		public ApplicationDockItem? TargetItem { get; protected set; default = null; }

		Gtk.Box main_box;
		Gtk.Box cards_box;
		Gtk.ScrolledWindow scrolled;

		uint dismiss_timer_id = 0U;
		uint pos_timer_1_id = 0U;
		uint pos_timer_2_id = 0U;
		bool pointer_inside = false;

		static Pango.FontDescription? cached_font_title = null;
		static Pango.FontDescription? cached_font_sub = null;

		public WindowCardsWindow (DockController controller)
		{
			GLib.Object (
				type: Gtk.WindowType.TOPLEVEL,
				controller: controller
			);
		}

		construct
		{
			decorated = false;
			app_paintable = true;
			resizable = false;
			accept_focus = false;
			can_focus = false;
			set_decorated (false);
			set_title ("wayplank-hover-cards");
			set_role ("popup-menu");

			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.init_for_window (this);
				GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
				GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
				GtkLayerShell.set_namespace (this, "wayplank-hover-cards");
			} else {
				set_type_hint (Gdk.WindowTypeHint.POPUP_MENU);
				set_skip_taskbar_hint (true);
				set_skip_pager_hint (true);
				set_keep_above (true);
			}

			unowned Gdk.Screen screen = get_screen ();
			var visual = screen.get_rgba_visual ();
			if (visual != null)
				set_visual (visual);

			get_style_context ().add_class ("wayplank-window-cards");

			main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
			main_box.margin = 6;
			add (main_box);

			scrolled = new Gtk.ScrolledWindow (null, null);
			scrolled.set_shadow_type (Gtk.ShadowType.NONE);
			scrolled.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
			scrolled.set_propagate_natural_width (true);
			scrolled.set_propagate_natural_height (true);
			scrolled.set_max_content_width (980);
			main_box.pack_start (scrolled, true, true, 0);

			cards_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			scrolled.add (cards_box);

			apply_theme_style ();

			add_events (
				Gdk.EventMask.ENTER_NOTIFY_MASK |
				Gdk.EventMask.LEAVE_NOTIFY_MASK |
				Gdk.EventMask.POINTER_MOTION_MASK |
				Gdk.EventMask.SCROLL_MASK
			);

			enter_notify_event.connect (on_enter);
			leave_notify_event.connect (on_leave);
			motion_notify_event.connect (() => {
				pointer_inside = true;
				cancel_dismiss_timer ();
				return false;
			});
			scroll_event.connect (on_scroll);

			WindowManager.get_default ().windows_refreshed.connect (on_windows_refreshed);
		}

		~WindowCardsWindow ()
		{
			cancel_dismiss_timer ();
			cancel_position_timers ();
			WindowManager.get_default ().windows_refreshed.disconnect (on_windows_refreshed);
		}

		void cancel_position_timers ()
		{
			if (pos_timer_1_id > 0U) {
				GLib.Source.remove (pos_timer_1_id);
				pos_timer_1_id = 0U;
			}
			if (pos_timer_2_id > 0U) {
				GLib.Source.remove (pos_timer_2_id);
				pos_timer_2_id = 0U;
			}
		}

		bool on_scroll (Gdk.EventScroll event)
		{
			if (TargetItem == null)
				return false;

			bool forward = (event.direction == Gdk.ScrollDirection.UP || event.direction == Gdk.ScrollDirection.RIGHT || event.delta_y < 0);
			string? uuid;
			if (WindowManager.get_default ().cycle_window (TargetItem.Launcher, forward, out uuid)) {
				WindowControl.queue_command (uuid, "activate");
			}
			return Gdk.EVENT_STOP;
		}

		void on_windows_refreshed ()
		{
			if (!get_visible () || TargetItem == null)
				return;

			var windows = WindowManager.get_default ().matching_windows (TargetItem.Launcher);
			if (windows.size == 0) {
				close_cards ();
				return;
			}

			// If window count changed, rebuild cards
			if (windows.size != cards_box.get_children ().length ()) {
				populate_cards ();
				update_position ();
			} else {
				// Re-draw all cards to shift active cyan highlight
				cards_box.queue_draw ();
			}
		}

		void apply_theme_style ()
		{
			var css = new Gtk.CssProvider ();
			try {
				css.load_from_data (
					"window.wayplank-window-cards {\n" +
					"    background-color: transparent;\n" +
					"}\n" +
					".wayplank-card-eb {\n" +
					"    border-radius: 8px;\n" +
					"    background-color: transparent;\n" +
					"}\n"
				);
				Gtk.StyleContext.add_provider_for_screen (
					get_screen (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
				);
			} catch (GLib.Error e) {
				warning ("WindowCardsWindow css error: %s", e.message);
			}
		}

		public override bool draw (Cairo.Context cr)
		{
			var width = get_allocated_width ();
			var height = get_allocated_height ();
			if (width <= 0 || height <= 0)
				return base.draw (cr);

			cr.save ();
			cr.set_operator (Cairo.Operator.CLEAR);
			cr.paint ();
			cr.restore ();

			cr.save ();

			double radius = 10.0;
			double line_width = 1.0;

			// Draw rounded cornered popup rectangle matching menu aesthetics
			Theme.draw_rounded_rect (cr,
				line_width / 2.0, line_width / 2.0,
				width - line_width, height - line_width,
				radius, radius, line_width);

			// Semi-transparent dark charcoal background
			cr.set_source_rgba (20.0 / 255.0, 22.0 / 255.0, 30.0 / 255.0, 0.96);
			cr.fill_preserve ();

			// Subtle crisp border
			cr.set_source_rgba (1.0, 1.0, 1.0, 0.15);
			cr.set_line_width (line_width);
			cr.stroke ();

			cr.restore ();

			return base.draw (cr);
		}

		public void show_for_item (ApplicationDockItem item)
		{
			TargetItem = item;
			pointer_inside = false;
			cancel_dismiss_timer ();
			cancel_position_timers ();

			populate_cards ();
			show_all ();

			var display = get_display ();
			var monitor = (display != null) ? PositionManager.get_monitor_for_plug_name (display, controller.prefs.Monitor) : null;
			if (monitor != null && GtkLayerShell.is_supported ())
				GtkLayerShell.set_monitor (this, monitor);

			update_position ();

			pos_timer_1_id = GLib.Timeout.add (25, () => {
				pos_timer_1_id = 0U;
				if (get_visible () && TargetItem != null)
					update_position ();
				return false;
			});
			pos_timer_2_id = GLib.Timeout.add (75, () => {
				pos_timer_2_id = 0U;
				if (get_visible () && TargetItem != null)
					update_position ();
				return false;
			});
		}

		public void close_cards ()
		{
			cancel_dismiss_timer ();
			cancel_position_timers ();
			hide ();
			TargetItem = null;
			controller.check_collapse_after_interaction (this);
		}

		static string clean_window_caption (string caption, string app_text)
		{
			var trimmed = caption.strip ();
			if (trimmed.length == 0)
				return app_text;

			var suffixes = new string[] {
				" — " + app_text,
				" - " + app_text,
				" — " + app_text.down (),
				" - " + app_text.down ()
			};
			foreach (var suffix in suffixes) {
				if (trimmed.has_suffix (suffix)) {
					var sub = trimmed.substring (0, trimmed.length - suffix.length).strip ();
					if (sub.length > 0)
						return sub;
				}
			}
			return trimmed;
		}

		void populate_cards ()
		{
			foreach (var child in cards_box.get_children ())
				cards_box.remove (child);

			if (TargetItem == null)
				return;

			var windows = WindowManager.get_default ().matching_windows (TargetItem.Launcher);
			if (windows.size == 0) {
				close_cards ();
				return;
			}

			// Sort windows: Active first, then by Caption
			var sorted = new Gee.ArrayList<WindowInfo> ();
			sorted.add_all (windows);
			sorted.sort ((a, b) => {
				if (a.Active && !b.Active) return -1;
				if (!a.Active && b.Active) return 1;
				return GLib.strcmp (a.Caption, b.Caption);
			});

			foreach (var win in sorted) {
				var card = create_card_widget (win);
				cards_box.pack_start (card, false, false, 0);
			}

			cards_box.show_all ();
		}

		Gtk.Widget create_card_widget (WindowInfo win)
		{
			var eb = new Gtk.EventBox ();
			eb.set_visible_window (true);
			eb.set_above_child (true);
			eb.set_size_request (CARD_WIDTH, CARD_HEIGHT);
			eb.get_style_context ().add_class ("wayplank-card-eb");
			eb.add_events (
				Gdk.EventMask.BUTTON_PRESS_MASK |
				Gdk.EventMask.ENTER_NOTIFY_MASK |
				Gdk.EventMask.LEAVE_NOTIFY_MASK |
				Gdk.EventMask.POINTER_MOTION_MASK
			);

			eb.realize.connect (() => {
				if (eb.get_window () != null)
					eb.get_window ().set_cursor (new Gdk.Cursor.for_display (eb.get_display (), Gdk.CursorType.HAND2));
			});

			bool is_card_hovered = false;
			bool is_close_hovered = false;

			int icon_px = 16;
			int icon_large_px = 44;
			Gdk.Pixbuf? app_icon = null;
			Gdk.Pixbuf? app_icon_large = null;
			if (TargetItem != null && TargetItem.Icon != "") {
				app_icon = DrawingService.load_icon (TargetItem.Icon, icon_px, icon_px);
				app_icon_large = DrawingService.load_icon (TargetItem.Icon, icon_large_px, icon_large_px);
			}
			if (app_icon == null && win.DesktopFileName != "") {
				app_icon = DrawingService.load_icon (win.DesktopFileName, icon_px, icon_px);
				app_icon_large = DrawingService.load_icon (win.DesktopFileName, icon_large_px, icon_large_px);
			}
			if (app_icon == null && win.ResourceClass != "") {
				app_icon = DrawingService.load_icon (win.ResourceClass, icon_px, icon_px);
				app_icon_large = DrawingService.load_icon (win.ResourceClass, icon_large_px, icon_large_px);
			}
			if (app_icon == null) {
				app_icon = DrawingService.load_icon ("application-x-executable", icon_px, icon_px);
				app_icon_large = DrawingService.load_icon ("application-x-executable", icon_large_px, icon_large_px);
			}

			var da = new Gtk.DrawingArea ();
			da.set_size_request (CARD_WIDTH, CARD_HEIGHT);

			string app_text = (TargetItem != null) ? TargetItem.Text : _("Application");
			string cleaned_caption = clean_window_caption (win.Caption, app_text);

			int prev_w = CARD_WIDTH - 10;
			int prev_h = 104;

			Gdk.Pixbuf? thumb_pixbuf = KWinThumbnailService.get_default ().get_cached (win.Id);
			if (thumb_pixbuf == null) {
				KWinThumbnailService.get_default ().request_thumbnail (win.Id, prev_w, prev_h, (pix) => {
					if (pix != null) {
						thumb_pixbuf = pix;
						da.queue_draw ();
						cards_box.queue_draw ();
						this.queue_draw ();
					}
				});
			}

			da.draw.connect ((cr) => {
				int w = da.get_allocated_width ();
				int h = da.get_allocated_height ();
				if (w <= 0 || h <= 0)
					return false;

				cr.save ();

				double card_x = 2.0;
				double card_y = 2.0;
				double card_w = w - 4.0;
				double card_h = h - 4.0;
				double card_r = 7.0;

				// 1. Outer rounded card capsule base
				Theme.draw_rounded_rect (cr, card_x, card_y, card_w, card_h, card_r, card_r, 0.0);

				bool is_win_active = false;
				bool demands_attn = false;
				if (TargetItem != null) {
					var cur_windows = WindowManager.get_default ().matching_windows (TargetItem.Launcher);
					foreach (var win_item in cur_windows) {
						if (win_item.Id == win.Id) {
							is_win_active = win_item.Active;
							demands_attn = win_item.DemandsAttention;
							break;
						}
					}
				}

				if (is_card_hovered) {
					cr.set_source_rgba (36.0 / 255.0, 42.0 / 255.0, 56.0 / 255.0, 0.98);
				} else if (is_win_active) {
					cr.set_source_rgba (32.0 / 255.0, 44.0 / 255.0, 64.0 / 255.0, 0.96);
				} else {
					cr.set_source_rgba (28.0 / 255.0, 32.0 / 255.0, 42.0 / 255.0, 0.94);
				}
				cr.fill_preserve ();

				// 2. Delicate hairline border: warm amber/orange on hover or cyan active border
				if (is_card_hovered) {
					cr.set_source_rgba (249.0 / 255.0, 115.0 / 255.0, 22.0 / 255.0, 0.80);
					cr.set_line_width (1.5);
				} else if (is_win_active) {
					cr.set_source_rgba (60.0 / 255.0, 150.0 / 255.0, 255.0 / 255.0, 0.95);
					cr.set_line_width (2.0);
				} else if (demands_attn) {
					cr.set_source_rgba (255.0 / 255.0, 165.0 / 255.0, 0.0, 0.85);
					cr.set_line_width (1.5);
				} else {
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.12);
					cr.set_line_width (1.0);
				}
				cr.stroke ();

				// 3. Preview viewport
				double prev_x = card_x + 5.0;
				double prev_y = card_y + 5.0;
				double prev_w_d = card_w - 10.0;
				double prev_h_d = 104.0;
				double prev_r = 5.0;

				cr.save ();
				Theme.draw_rounded_rect (cr, prev_x, prev_y, prev_w_d, prev_h_d, prev_r, prev_r, 0.0);
				cr.clip ();

				var current_thumb = (thumb_pixbuf != null) ? thumb_pixbuf : KWinThumbnailService.get_default ().get_cached (win.Id);
				if (current_thumb != null) {
					Gdk.cairo_set_source_pixbuf (cr, current_thumb, prev_x, prev_y);
					cr.paint ();
				} else {
					// Graceful Fallback for minimized or non-captured windows
					cr.set_source_rgba (16.0 / 255.0, 20.0 / 255.0, 28.0 / 255.0, 0.92);
					cr.fill ();

					double center_x = prev_x + prev_w_d / 2.0;
					double center_y = prev_y + prev_h_d / 2.0;

					cr.arc (center_x, center_y, 26.0, 0, 2 * Math.PI);
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.06);
					cr.fill ();

					if (app_icon_large != null) {
						cr.save ();
						Gdk.cairo_set_source_pixbuf (cr, app_icon_large,
							center_x - icon_large_px / 2.0,
							center_y - icon_large_px / 2.0);
						cr.paint ();
						cr.restore ();
					}

					if (win.Minimized) {
						if (cached_font_title == null)
							cached_font_title = Pango.FontDescription.from_string ("Sans 7.5");
						var layout_min = Pango.cairo_create_layout (cr);
						layout_min.set_font_description (cached_font_title);
						layout_min.set_text (_("Minimized"), -1);
						cr.set_source_rgba (148.0 / 255.0, 163.0 / 255.0, 184.0 / 255.0, 0.85);
						cr.move_to (center_x - 22.0, center_y + 24.0);
						Pango.cairo_show_layout (cr, layout_min);
					}
				}
				cr.restore ();

				// Inner border around preview viewport
				Theme.draw_rounded_rect (cr, prev_x, prev_y, prev_w_d, prev_h_d, prev_r, prev_r, 0.0);
				cr.set_source_rgba (1.0, 1.0, 1.0, 0.08);
				cr.set_line_width (1.0);
				cr.stroke ();

				// 4. Bottom strip with mini icon and caption
				double header_y = prev_y + prev_h_d + 3.0;
				double header_h = card_h - (prev_h_d + 8.0);

				if (app_icon != null) {
					cr.save ();
					Gdk.cairo_set_source_pixbuf (cr, app_icon,
						card_x + 7.0,
						header_y + (header_h - icon_px) / 2.0);
					cr.paint ();
					cr.restore ();
				}

				double text_x = card_x + 7.0 + icon_px + 6.0;
				double text_w = (card_x + card_w - 24.0) - text_x;
				if (text_w > 15) {
					if (cached_font_sub == null)
						cached_font_sub = Pango.FontDescription.from_string ("Sans Bold 8.5");

					var layout_sub = Pango.cairo_create_layout (cr);
					layout_sub.set_font_description (cached_font_sub);
					layout_sub.set_text (cleaned_caption, -1);
					layout_sub.set_width ((int) (text_w * Pango.SCALE));
					layout_sub.set_ellipsize (Pango.EllipsizeMode.END);

					cr.set_source_rgba (248.0 / 255.0, 250.0 / 255.0, 252.0 / 255.0, 0.95);
					cr.move_to (text_x, header_y + (header_h - 13.0) / 2.0);
					Pango.cairo_show_layout (cr, layout_sub);
				}

				// 5. Close cross on bottom right
				double close_x = card_x + card_w - 13.0;
				double close_y = header_y + header_h / 2.0;
				double cr_size = 4.0;
				if (is_close_hovered) {
					cr.arc (close_x, close_y, 9.0, 0, 2 * Math.PI);
					cr.set_source_rgba (239.0 / 255.0, 68.0 / 255.0, 68.0 / 255.0, 0.35);
					cr.fill ();

					cr.set_source_rgba (255.0 / 255.0, 90.0 / 255.0, 90.0 / 255.0, 1.0);
					cr.set_line_width (2.0);
				} else if (is_card_hovered) {
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.70);
					cr.set_line_width (1.5);
				} else {
					cr.set_source_rgba (1.0, 1.0, 1.0, 0.35);
					cr.set_line_width (1.5);
				}
				cr.move_to (close_x - cr_size, close_y - cr_size);
				cr.line_to (close_x + cr_size, close_y + cr_size);
				cr.move_to (close_x + cr_size, close_y - cr_size);
				cr.line_to (close_x - cr_size, close_y + cr_size);
				cr.stroke ();

				cr.restore ();
				return true;
			});

			eb.add (da);

			eb.motion_notify_event.connect ((event) => {
				pointer_inside = true;
				cancel_dismiss_timer ();
				double close_x = CARD_WIDTH - 15.0;
				double close_y = 111.0 + (CARD_HEIGHT - 111.0) / 2.0;
				bool close_hover = (Math.hypot (event.x - close_x, event.y - close_y) <= 13.0);
				if (close_hover != is_close_hovered) {
					is_close_hovered = close_hover;
					da.queue_draw ();
				}
				return false;
			});

			eb.enter_notify_event.connect (() => {
				is_card_hovered = true;
				pointer_inside = true;
				cancel_dismiss_timer ();
				da.queue_draw ();
				return false;
			});

			eb.leave_notify_event.connect (() => {
				is_card_hovered = false;
				is_close_hovered = false;
				da.queue_draw ();
				return false;
			});

			eb.scroll_event.connect (on_scroll);

			eb.button_press_event.connect ((event) => {
				double close_x = CARD_WIDTH - 15.0;
				double close_y = 111.0 + (CARD_HEIGHT - 111.0) / 2.0;
				bool is_close_click = (Math.hypot (event.x - close_x, event.y - close_y) <= 13.0);

				if (event.button == Gdk.BUTTON_PRIMARY) {
					if (is_close_click) {
						WindowControl.queue_command (win.Id, "close");
						cards_box.remove (eb);
						eb.destroy ();
						if (cards_box.get_children ().length () == 0) {
							close_cards ();
						} else {
							update_position ();
						}
					} else {
						WindowControl.queue_command (win.Id, "activate");
						close_cards ();
					}
					return Gdk.EVENT_STOP;
				}
				return Gdk.EVENT_PROPAGATE;
			});

			return eb;
		}

		/**
		 * Positions the window cards using exact coordinates derived from PositionManager,
		 * identical to FolderMenuWindow and HoverWindow.
		 */
		public void update_position ()
		{
			if (TargetItem == null || !TargetItem.is_valid () || !get_visible ())
				return;

			unowned PositionManager pm = controller.position_manager;
			var val = pm.get_draw_value_for_item (TargetItem);

			int n_cards = (int) cards_box.get_children ().length ();
			if (n_cards <= 0)
				n_cards = 1;
			int expected_w = 12 + n_cards * CARD_WIDTH + (n_cards > 1 ? (n_cards - 1) * 6 : 0);
			if (expected_w > 980)
				expected_w = 980;
			int expected_h = CARD_HEIGHT + 16;

			Gtk.Requisition req;
			get_preferred_size (null, out req);
			int width = req.width >= expected_w ? req.width : expected_w;
			int height = req.height >= expected_h ? req.height : expected_h;

			var display = get_display ();
			var monitor = (display != null) ? PositionManager.get_monitor_for_plug_name (display, controller.prefs.Monitor) : null;
			var geo = (monitor != null) ? monitor.get_geometry () : Gdk.Rectangle ();
			int mon_w = geo.width > 0 ? geo.width : 1920;
			int mon_h = geo.height > 0 ? geo.height : 1080;

			int center_x = (int) Math.round (val.center.x);
			int center_y = (int) Math.round (val.center.y);

			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, 0);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, 0);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, 0);
				GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, 0);

				int visual_thickness = pm.get_visual_thickness_for_item (TargetItem);

				switch (pm.Position) {
				case Gtk.PositionType.BOTTOM:
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, false);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);

					int bottom_margin = visual_thickness + GAP;

					if (monitor != null) {
						var work = monitor.get_workarea ();
						int bottom_panel = int.max (0, (geo.y + geo.height) - (work.y + work.height));
						if (bottom_panel > 0)
							bottom_margin += bottom_panel + 2;
					}

					int clamped_x = int.max (GAP, int.min (mon_w - width - GAP, center_x - width / 2));
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, bottom_margin);
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, clamped_x);
					break;

				case Gtk.PositionType.TOP:
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);

					int top_margin = visual_thickness + GAP;

					if (monitor != null) {
						var work = monitor.get_workarea ();
						int top_panel = int.max (0, work.y - geo.y);
						if (top_panel > 0)
							top_margin += top_panel + 2;
					}
					top_margin += WindowControl.get_top_panel_floating_offset (geo);

					int clamped_top_x = int.max (GAP, int.min (mon_w - width - GAP, center_x - width / 2));
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, top_margin);
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, clamped_top_x);
					break;

				case Gtk.PositionType.LEFT:
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);

					int left_margin = visual_thickness + GAP;

					if (monitor != null) {
						var work = monitor.get_workarea ();
						int left_panel = int.max (0, work.x - geo.x);
						if (left_panel > 0)
							left_margin += left_panel + 2;
					}

					int clamped_left_y = int.max (GAP, int.min (mon_h - height - GAP, center_y - height / 2));
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, left_margin);
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, clamped_left_y);
					break;

				case Gtk.PositionType.RIGHT:
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, false);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);

					int right_margin = visual_thickness + GAP;

					if (monitor != null) {
						var work = monitor.get_workarea ();
						int right_panel = int.max (0, (geo.x + geo.width) - (work.x + work.width));
						if (right_panel > 0)
							right_margin += right_panel + 2;
					}

					int clamped_right_y = int.max (GAP, int.min (mon_h - height - GAP, center_y - height / 2));
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, right_margin);
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, clamped_right_y);
					break;
				}
			} else {
				int mon_x = geo.x;
				int mon_y = geo.y;

				int target_x = mon_x + center_x - width / 2;
				int target_y = mon_y + center_y;
				int visual_thickness = pm.get_visual_thickness_for_item (TargetItem);
				int mutter_offset = 8;

				switch (pm.Position) {
				case Gtk.PositionType.BOTTOM:
					target_y = mon_y + mon_h - visual_thickness - GAP - height + mutter_offset;
					break;
				case Gtk.PositionType.TOP:
					int top_bar_offset = int.max (0, (monitor != null ? monitor.get_workarea ().y - monitor.get_geometry ().y : 0));
					target_y = mon_y + top_bar_offset + visual_thickness + GAP - mutter_offset;
					break;
				case Gtk.PositionType.LEFT:
					target_x = mon_x + visual_thickness + GAP - mutter_offset;
					target_y = mon_y + center_y - height / 2;
					break;
				case Gtk.PositionType.RIGHT:
					target_x = mon_x + mon_w - visual_thickness - GAP - width + mutter_offset;
					target_y = mon_y + center_y - height / 2;
					break;
				}

				var abs_x = int.max (mon_x + GAP, int.min (mon_x + mon_w - width - GAP, target_x));
				var abs_y = int.max (mon_y + GAP, int.min (mon_y + mon_h - height - GAP, target_y));
				move (abs_x, abs_y);
				WindowControl.position_hover (abs_x, abs_y, width, height);
			}
		}

		public void cancel_dismiss_timer ()
		{
			if (dismiss_timer_id > 0U) {
				Source.remove (dismiss_timer_id);
				dismiss_timer_id = 0U;
			}
		}

		public void schedule_dismiss (uint delay_ms = DISMISS_DELAY)
		{
			cancel_dismiss_timer ();
			dismiss_timer_id = Timeout.add (delay_ms, () => {
				dismiss_timer_id = 0U;
				if (!pointer_inside) {
					close_cards ();
				}
				return false;
			});
		}

		bool on_enter (Gdk.EventCrossing event)
		{
			pointer_inside = true;
			cancel_dismiss_timer ();
			return false;
		}

		bool on_leave (Gdk.EventCrossing event)
		{
			if (event.detail != Gdk.NotifyType.INFERIOR) {
				pointer_inside = false;
				schedule_dismiss (DISMISS_DELAY);
			}
			return false;
		}

		public void on_dock_hover (DockItem? hovered_item)
		{
			if (!get_visible () || TargetItem == null)
				return;

			if (hovered_item == TargetItem) {
				cancel_dismiss_timer ();
				update_position ();
				return;
			}

			// If another dock item is actively hovered, dismiss immediately
			if (hovered_item != null) {
				close_cards ();
				return;
			}

			if (!pointer_inside) {
				schedule_dismiss (DISMISS_DELAY);
			}
		}

		public void on_dock_leave ()
		{
			if (!get_visible ())
				return;

			if (!pointer_inside)
				schedule_dismiss (DISMISS_DELAY);
		}
	}
}
