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
	 * The main window for all docks.
	 */
	public class DockWindow : CompositedWindow
	{
		const uint LONG_PRESS_TIME = 750U;
		const uint HOVER_DELAY_TIME = 200U;

		/**
		 * The controller for this dock.
		 */
		public DockController controller { private get; construct; }

		/**
		 * The currently hovered item (if any).
		 */
		public DockItem? HoveredItem { get; private set; }

		/**
		 * The currently hovered item-provider (if any).
		 */
		public DockItemProvider? HoveredItemProvider { get; private set; }

		/**
		 * The item which "received" the button-pressed signal (if any).
		 */
		unowned DockItem? ClickedItem { get; private set; }

		/**
		 * The popup menu for this dock.
		 */
		Gtk.Menu? menu;
		Gee.ArrayList<Gtk.MenuItem>? menu_items;

		uint hover_reposition_timer_id = 0U;

		uint long_press_timer_id = 0U;
		bool long_press_active = false;
		uint long_press_button = 0U;

		double smooth_scroll_dy = 0.0;
		double smooth_scroll_dx = 0.0;
		uint32 last_scroll_time = 0U;
		int window_position_retry = 0;
		Gdk.Event? last_button_event = null;

		weak Gdk.Monitor? tracked_monitor = null;
		ulong monitor_workarea_handler_id = 0UL;

		/**
		 * Creates a new dock window.
		 */
		public DockWindow (DockController controller)
		{
			GLib.Object (controller: controller, type: Gtk.WindowType.TOPLEVEL);
		}

		construct
		{
			// Wayland Layer Shell initialization
			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.init_for_window (this);
				GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
				GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
				GtkLayerShell.set_namespace (this, "wayplank");
				update_exclusive_zone ();

				update_layer_shell_monitor ();

				// Apply dynamic anchors based on current preferences
				update_layer_shell_anchors ();

				WindowControl.get_default ().state_changed.connect (() => {
					if (controller.prefs.Position == Gtk.PositionType.TOP) {
						update_layer_shell_anchors ();
					}
				});
			} else {
				set_decorated (false);
				set_type_hint (Gdk.WindowTypeHint.DOCK);
				set_skip_taskbar_hint (true);
				set_skip_pager_hint (true);
				set_keep_above (true);
				set_title ("wayplank");
				set_role ("dock");
				WindowControl.get_default ().state_changed.connect (on_backend_state_changed);
			}

			realize.connect (() => {
				input_rect = { -1, -1, -1, -1 };
				set_input_mask ();
			});

			// Track position setting changes
			controller.prefs.notify["Position"].connect (on_position_changed);
			controller.prefs.notify["HideMode"].connect (on_reserve_space_changed);
			controller.prefs.notify["ReserveSpace"].connect (on_reserve_space_changed);
			controller.prefs.notify["ZoomEnabled"].connect (on_reserve_space_changed);
			controller.prefs.notify["IconSize"].connect (update_exclusive_zone);

			// Native RGBA visual setup for Wayland transparency
			var visual = get_screen ().get_rgba_visual ();
			if (visual != null)
				set_visual (visual);

			set_app_paintable (true);
			stick ();

			accept_focus = false;
			can_focus = false;

			add_events (Gdk.EventMask.BUTTON_PRESS_MASK |
						Gdk.EventMask.BUTTON_RELEASE_MASK |
						Gdk.EventMask.ENTER_NOTIFY_MASK |
						Gdk.EventMask.LEAVE_NOTIFY_MASK |
						Gdk.EventMask.POINTER_MOTION_MASK |
						Gdk.EventMask.SCROLL_MASK |
						Gdk.EventMask.STRUCTURE_MASK);

			update_exclusive_zone ();
		}

		void on_backend_state_changed ()
		{
			if (!GtkLayerShell.is_supported () && !get_visible ()) {
				update_size_and_position ();
			}
		}

		void on_reserve_space_changed ()
		{
			update_exclusive_zone ();
			update_size_and_position ();
		}

		void on_position_changed ()
		{
			if (GtkLayerShell.is_supported ())
				update_layer_shell_anchors ();
			controller.position_manager.update (controller.renderer.theme);
			update_exclusive_zone ();
			update_size_and_position ();
		}

		void update_exclusive_zone ()
		{
			bool reserve = controller.prefs.ReserveSpace && controller.prefs.HideMode == HideType.NONE && !controller.prefs.ZoomEnabled;
			int thickness = controller.position_manager.get_visual_thickness ();

			if (reserve && thickness <= 0)
				return;

			if (GtkLayerShell.is_supported ()) {
				if (reserve) {
					GtkLayerShell.set_layer (this, GtkLayerShell.Layer.BOTTOM);
					GtkLayerShell.set_exclusive_zone (this, thickness);
				} else {
					GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
					GtkLayerShell.set_exclusive_zone (this, 0);
				}
			}

			WindowControl.set_reserve_space (reserve, thickness, controller.prefs.Position);
		}

		public void cancel_long_press ()
		{
			if (long_press_timer_id > 0U) {
				GLib.Source.remove (long_press_timer_id);
				long_press_timer_id = 0U;
			}
			long_press_active = false;
			long_press_button = 0;
		}

		~DockWindow ()
		{
			cancel_long_press ();
			if (!GtkLayerShell.is_supported ()) {
				WindowControl.get_default ().state_changed.disconnect (on_backend_state_changed);
			}
			if (tracked_monitor != null && monitor_workarea_handler_id != 0UL) {
				tracked_monitor.disconnect (monitor_workarea_handler_id);
				monitor_workarea_handler_id = 0UL;
				tracked_monitor = null;
			}
			if (controller != null && controller.prefs != null) {
				controller.prefs.notify["Position"].disconnect (on_position_changed);
				controller.prefs.notify["HideMode"].disconnect (on_reserve_space_changed);
				controller.prefs.notify["ReserveSpace"].disconnect (on_reserve_space_changed);
				controller.prefs.notify["ZoomEnabled"].disconnect (on_reserve_space_changed);
				controller.prefs.notify["IconSize"].disconnect (update_exclusive_zone);
				WindowControl.set_reserve_space (false, 0, controller.prefs.Position);
			}

			if (menu != null) {
				menu.show.disconnect (on_menu_show);
				menu.hide.disconnect (on_menu_hide);
				menu.destroy ();
				menu = null;
			}

			if (hover_reposition_timer_id > 0U) {
				GLib.Source.remove (hover_reposition_timer_id);
				hover_reposition_timer_id = 0U;
			}
		}

		void update_layer_shell_anchors ()
		{
			if (!GtkLayerShell.is_supported ())
				return;

			var pos = controller.prefs.Position;

			GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, pos == Gtk.PositionType.BOTTOM || pos == Gtk.PositionType.LEFT || pos == Gtk.PositionType.RIGHT);
			GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, pos == Gtk.PositionType.TOP || pos == Gtk.PositionType.LEFT || pos == Gtk.PositionType.RIGHT);
			GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, pos == Gtk.PositionType.LEFT || pos == Gtk.PositionType.BOTTOM || pos == Gtk.PositionType.TOP);
			GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, pos == Gtk.PositionType.RIGHT || pos == Gtk.PositionType.BOTTOM || pos == Gtk.PositionType.TOP);

			var display = get_display ();
			var monitor = (display != null) ? PositionManager.get_monitor_for_plug_name (display, controller.prefs.Monitor) : null;
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
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, top_margin);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, bottom_margin);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, left_margin);
			GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, right_margin);
			queue_draw ();
		}

		public void update_layer_shell_monitor ()
		{
			if (!GtkLayerShell.is_supported ())
				return;

			var display = get_display ();
			if (display == null)
				return;

			var monitor = PositionManager.get_monitor_for_plug_name (display, controller.prefs.Monitor);
			if (monitor == null)
				return;

			if (monitor != tracked_monitor) {
				if (tracked_monitor != null && monitor_workarea_handler_id != 0UL) {
					tracked_monitor.disconnect (monitor_workarea_handler_id);
					monitor_workarea_handler_id = 0UL;
				}
				tracked_monitor = monitor;
				if (tracked_monitor != null) {
					monitor_workarea_handler_id = tracked_monitor.notify["workarea"].connect (() => {
						WindowControl.invalidate_panel_cache ();
						update_layer_shell_anchors ();
					});
				}
			}

			if (GtkLayerShell.get_monitor (this) != monitor) {
				GtkLayerShell.set_monitor (this, monitor);
				update_layer_shell_anchors ();
			}

			update_size_and_position ();
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool button_press_event (Gdk.EventButton event)
		{
			if (menu_is_visible ())
				return Gdk.EVENT_PROPAGATE;

			if (controller.folder_menu.get_visible ()) {
				if (HoveredItem != controller.folder_menu.TargetItem)
					controller.folder_menu.close_menu ();
			}

			if (controller.window_cards.get_visible ()) {
				if (HoveredItem != controller.window_cards.TargetItem)
					controller.window_cards.close_cards ();
			}

			if (controller.hide_manager.Hidden)
				return Gdk.EVENT_STOP;

			if (controller.drag_manager.InternalDragActive)
				return Gdk.EVENT_STOP;

			if (HoveredItem == null)
				update_hovered ((int) event.x, (int) event.y);

			ClickedItem = HoveredItem;
			last_button_event = ((Gdk.Event) event).copy ();

			var button = PopupButton.from_event_button (event);
			if (button != PopupButton.LEFT && show_menu (HoveredItem, button, event.state, (int) event.x, (int) event.y, (Gdk.Event) event))
				return Gdk.EVENT_STOP;

			cancel_long_press ();

			if (event.button == Gdk.BUTTON_PRIMARY) {
				long_press_active = false;
				long_press_button = event.button;
				Gdk.ModifierType ev_state = event.state;
				int ex = (int) event.x;
				int ey = (int) event.y;

				long_press_timer_id = Timeout.add (LONG_PRESS_TIME, () => {
					long_press_timer_id = 0U;
					if (controller.drag_manager.InternalDragActive || controller.drag_manager.ExternalDragActive)
						return false;
					long_press_active = true;
					if (HoveredItem != null)
						show_menu (HoveredItem, PopupButton.RIGHT, ev_state, ex, ey, null);
					return false;
				});
			}

			return Gdk.EVENT_PROPAGATE;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool button_release_event (Gdk.EventButton event)
		{
			if (controller.hide_manager.Hidden)
				return Gdk.EVENT_STOP;

			if (long_press_timer_id > 0U) {
				Source.remove (long_press_timer_id);
				long_press_timer_id = 0U;
			}

			if (long_press_active && long_press_button == event.button) {
				long_press_active = false;
				long_press_button = 0;
				ClickedItem = null;
				return Gdk.EVENT_STOP;
			}

			if (controller.drag_manager.InternalDragActive)
				return Gdk.EVENT_STOP;

			if (HoveredItem != null && ClickedItem == null && menu_is_visible ())
				menu.hide ();

			if (event.button != Gdk.BUTTON_SECONDARY
				&& ClickedItem != null && HoveredItem == ClickedItem && !menu_is_visible ()) {
				controller.hover.hide ();
				var button = PopupButton.from_event_button (event);

				if (button == PopupButton.LEFT && controller.prefs.CategorizeItems && controller.prefs.AccordionDocklets && controller.app_provider != null) {
					if (!controller.app_provider.docklets_expanded && controller.app_provider.get_docklet_count () > 1 && DefaultApplicationDockItemProvider.is_docklet_element (ClickedItem)) {
						controller.app_provider.expand_docklets ();
						ClickedItem = null;
						return Gdk.EVENT_STOP;
					}
				}

				if (button == PopupButton.LEFT && ClickedItem is FileDockItem && ((FileDockItem) ClickedItem).is_directory ()) {
					if (controller.folder_menu.get_visible () && controller.folder_menu.TargetItem == ClickedItem) {
						controller.folder_menu.close_menu ();
					} else {
						controller.folder_menu.show_for_item ((FileDockItem) ClickedItem);
						ClickedItem.clicked (button, event.state, event.time);
					}
					ClickedItem = null;
					return Gdk.EVENT_STOP;
				}

				bool has_ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
				if (button == PopupButton.LEFT && !has_ctrl && ClickedItem is ApplicationDockItem) {
					var app_item = (ApplicationDockItem) ClickedItem;
					unowned DefaultApplicationDockItemProvider? provider = (app_item.Container as DefaultApplicationDockItemProvider);
					var show_cards = (provider != null ? provider.Prefs.ShowWindowCards : true);
					var win_count = WindowManager.get_default ().window_count_for_app (app_item.Launcher);
					if (show_cards && win_count > 1) {
						if (controller.window_cards.get_visible () && controller.window_cards.TargetItem == ClickedItem) {
							controller.window_cards.close_cards ();
						} else {
							controller.window_cards.show_for_item (app_item);
						}
						ClickedItem = null;
						return Gdk.EVENT_STOP;
					}
				}
				if (controller.window_cards.get_visible ())
					controller.window_cards.close_cards ();
				HoveredItem.clicked (button, event.state, event.time);
			}

			ClickedItem = null;

			return Gdk.EVENT_PROPAGATE;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool leave_notify_event (Gdk.EventCrossing event)
		{
			if ((bool) event.send_event)
				return Gdk.EVENT_PROPAGATE;

			if (controller.drag_manager.InternalDragActive || controller.drag_manager.ExternalDragActive)
				return Gdk.EVENT_PROPAGATE;

			if (event.detail == Gdk.NotifyType.INFERIOR || event.mode != Gdk.CrossingMode.NORMAL)
				return Gdk.EVENT_PROPAGATE;

			if (controller.folder_menu.get_visible ())
				controller.folder_menu.on_dock_leave ();

			if (controller.window_cards.get_visible ())
				controller.window_cards.on_dock_leave ();

			if (!menu_is_visible ()) {
				set_hovered_provider (null);
				set_hovered (null);
				controller.hide_manager.update_hovered_with_coords (-1, -1);
				if (controller.is_interaction_active ()) {
					if (controller.app_provider != null)
						controller.app_provider.cancel_collapse_timer ();
				} else {
					if (controller.prefs.CategorizeItems && controller.prefs.AccordionDocklets && controller.app_provider != null) {
						controller.app_provider.schedule_collapse_docklets (controller.prefs.AccordionDelay);
					}
				}
			} else
				controller.hover.hide ();

			return Gdk.EVENT_PROPAGATE;
		}

		bool is_in_docklet_zone (int x, int y)
		{
			if (controller.app_provider == null)
				return false;

			unowned PositionManager pm = controller.position_manager;
			var cursor_rect = pm.get_cursor_region ();
			if (pm.is_horizontal_dock ()) {
				if (y < cursor_rect.y - 10 || y >= cursor_rect.y + cursor_rect.height + 10)
					return false;
			} else {
				if (x < cursor_rect.x - 10 || x >= cursor_rect.x + cursor_rect.width + 10)
					return false;
			}

			int min_coord = int.MAX;
			int max_coord = int.MIN;
			bool found_docklet = false;

			foreach (var item in controller.VisibleItems) {
				if (DefaultApplicationDockItemProvider.is_docklet_element (item)) {
					var rect = pm.get_hover_region_for_element (item);
					if (pm.is_horizontal_dock ()) {
						min_coord = int.min (min_coord, rect.x);
						max_coord = int.max (max_coord, rect.x + rect.width);
					} else {
						min_coord = int.min (min_coord, rect.y);
						max_coord = int.max (max_coord, rect.y + rect.height);
					}
					found_docklet = true;
				}
			}

			if (!found_docklet)
				return false;

			// Add a comfortable margin for hover stability
			min_coord -= 8;
			max_coord += 8;

			if (pm.is_horizontal_dock ()) {
				return (x >= min_coord && x <= max_coord);
			} else {
				return (y >= min_coord && y <= max_coord);
			}
		}

		public bool is_hovering_docklets (int x, int y)
		{
			if (HoveredItem != null && DefaultApplicationDockItemProvider.is_docklet_element (HoveredItem))
				return true;
			return is_in_docklet_zone (x, y);
		}

		public override bool enter_notify_event (Gdk.EventCrossing event)
		{
			if (event.detail == Gdk.NotifyType.INFERIOR || event.mode != Gdk.CrossingMode.NORMAL)
				return Gdk.EVENT_PROPAGATE;

			if (controller.folder_menu.get_visible ())
				controller.folder_menu.cancel_dismiss_timer ();

			if (controller.window_cards.get_visible ())
				controller.window_cards.cancel_dismiss_timer ();

			controller.renderer.update_local_cursor ((int) event.x, (int) event.y);
			update_hovered ((int) event.x, (int) event.y);
			controller.hide_manager.update_hovered_with_coords ((int) event.x, (int) event.y);

			if (controller.prefs.CategorizeItems && controller.prefs.AccordionDocklets && controller.app_provider != null) {
				if (controller.app_provider.docklets_expanded) {
					controller.app_provider.cancel_collapse_timer ();
				} else if (!controller.prefs.AccordionClickToExpand && is_hovering_docklets ((int) event.x, (int) event.y)) {
					controller.app_provider.expand_docklets ();
				}
			}

			controller.renderer.animated_draw ();

			return Gdk.EVENT_PROPAGATE;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool motion_notify_event (Gdk.EventMotion event)
		{
			if (menu_is_visible ())
				return Gdk.EVENT_STOP;

			if (long_press_timer_id > 0U)
				cancel_long_press ();

			controller.renderer.update_local_cursor ((int) event.x, (int) event.y);
			update_hovered ((int) event.x, (int) event.y);
			controller.hide_manager.update_hovered_with_coords ((int) event.x, (int) event.y);

			if (controller.prefs.CategorizeItems && controller.prefs.AccordionDocklets && controller.app_provider != null) {
				if (controller.app_provider.docklets_expanded) {
					controller.app_provider.cancel_collapse_timer ();
				} else if (!controller.prefs.AccordionClickToExpand && is_hovering_docklets ((int) event.x, (int) event.y)) {
					controller.app_provider.expand_docklets ();
				}
			}

			if (controller.folder_menu.get_visible ())
				controller.folder_menu.on_dock_hover (HoveredItem);

			if (controller.window_cards.get_visible ())
				controller.window_cards.on_dock_hover (HoveredItem);
			
			return Gdk.EVENT_STOP;
		}

		/**
		 * {@inheritDoc}
		 */
		public override void drag_begin (Gdk.DragContext context)
		{
			cancel_long_press ();
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool scroll_event (Gdk.EventScroll event)
		{
			if (controller.hide_manager.Hidden)
				return Gdk.EVENT_STOP;

			if (controller.drag_manager.InternalDragActive)
				return Gdk.EVENT_STOP;

			// Retain accordion expansion during wheel scrolling
			if (controller.prefs.CategorizeItems && controller.prefs.AccordionDocklets && controller.app_provider != null) {
				if (controller.app_provider.docklets_expanded) {
					controller.app_provider.cancel_collapse_timer ();
				}
			}

			Gdk.ScrollDirection direction = event.direction;
			double raw_dx = 0.0, raw_dy = 0.0;
			bool has_deltas = (direction == Gdk.ScrollDirection.SMOOTH && event.get_scroll_deltas (out raw_dx, out raw_dy));

			if (direction == Gdk.ScrollDirection.SMOOTH) {
				if (has_deltas) {
					if (event.time - last_scroll_time > 400U) {
						smooth_scroll_dx = 0.0;
						smooth_scroll_dy = 0.0;
					}
					last_scroll_time = event.time;

					smooth_scroll_dx += raw_dx;
					smooth_scroll_dy += raw_dy;

					if (smooth_scroll_dy <= -0.7) {
						direction = Gdk.ScrollDirection.UP;
						smooth_scroll_dy = 0.0;
						smooth_scroll_dx = 0.0;
					} else if (smooth_scroll_dy >= 0.7) {
						direction = Gdk.ScrollDirection.DOWN;
						smooth_scroll_dy = 0.0;
						smooth_scroll_dx = 0.0;
					} else if (smooth_scroll_dx <= -0.7) {
						direction = Gdk.ScrollDirection.LEFT;
						smooth_scroll_dy = 0.0;
						smooth_scroll_dx = 0.0;
					} else if (smooth_scroll_dx >= 0.7) {
						direction = Gdk.ScrollDirection.RIGHT;
						smooth_scroll_dy = 0.0;
						smooth_scroll_dx = 0.0;
					} else {
						if (controller.position_manager.max_scroll_offset > 0.0) {
							string? item_type_name = (HoveredItem != null) ? HoveredItem.get_type ().name () : null;
							bool is_volume = (item_type_name != null && item_type_name.contains ("Volume"));
							bool is_brightness = (item_type_name != null && item_type_name.contains ("Brightness"));
							if (!is_volume && !is_brightness) {
								double d = (Math.fabs (raw_dx) > Math.fabs (raw_dy)) ? raw_dx : raw_dy;
								if (Math.fabs (d) > 0.02) {
									controller.position_manager.scroll_by (d * 50.0);
									return Gdk.EVENT_STOP;
								}
							}
						}
						return Gdk.EVENT_STOP;
					}
				} else {
					return Gdk.EVENT_STOP;
				}
			} else if ((uint) direction >= 4) {
				return Gdk.EVENT_STOP;
			}

			if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
				if (direction == Gdk.ScrollDirection.UP)
					controller.prefs.increase_icon_size ();
				else if (direction == Gdk.ScrollDirection.DOWN)
					controller.prefs.decrease_icon_size ();

				return Gdk.EVENT_STOP;
			}

			// =====================================================================
			// Dock Overflow Smooth Scrolling (Fork Integration by 史有虎 / IFtiger-hu)
			// =====================================================================
			if (controller.position_manager.max_scroll_offset > 0.0) {
				string? item_type_name = (HoveredItem != null) ? HoveredItem.get_type ().name () : null;
				bool is_volume = (item_type_name != null && item_type_name.contains ("Volume"));
				bool is_brightness = (item_type_name != null && item_type_name.contains ("Brightness"));
				if (!is_volume && !is_brightness) {
					if (direction == Gdk.ScrollDirection.LEFT || direction == Gdk.ScrollDirection.UP) {
						controller.position_manager.scroll_by (-80.0);
						return Gdk.EVENT_STOP;
					} else if (direction == Gdk.ScrollDirection.RIGHT || direction == Gdk.ScrollDirection.DOWN) {
						controller.position_manager.scroll_by (80.0);
						return Gdk.EVENT_STOP;
					}
				}
			}

			if (HoveredItem != null) {
				controller.hover.hide ();
				HoveredItem.scrolled (direction, event.state, event.time);
				controller.renderer.animated_draw ();
			}

			return Gdk.EVENT_STOP;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool configure_event (Gdk.EventConfigure event)
		{
			var win_rect = controller.position_manager.get_dock_window_region ();
			var needs_update = (win_rect.width != event.width || win_rect.height != event.height);

			if (needs_update) {
				if (++window_position_retry < 3) {
					update_size_and_position ();
				}
			} else {
				window_position_retry = 0;
			}

			return base.configure_event (event);
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool draw (Cairo.Context cr)
		{   
			int64 frame_time = 0;
			var frame_clock = get_frame_clock ();
			if (frame_clock != null)
				frame_time = frame_clock.get_frame_time ();

			controller.renderer.draw (cr, frame_time);

			if (controller.folder_menu.get_visible ())
				controller.folder_menu.update_position ();

			if (controller.window_cards.get_visible ())
				controller.window_cards.update_position ();

			return Gdk.EVENT_STOP;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool map_event (Gdk.EventAny event)
		{
			input_rect = { -1, -1, -1, -1 };
			set_input_mask ();
			// Trigger an immediate frame draw upon mapping to prevent waiting for a click
			controller.renderer.animated_draw ();
			return base.map_event (event);
		}

		void set_hovered_provider (DockItemProvider? provider)
		{
			if (HoveredItemProvider == provider)
				return;

			HoveredItemProvider = provider;
		}

		void set_hovered (DockItem? item)
		{
			if (HoveredItem == item)
				return;

			if (HoveredItem != null)
				HoveredItem.hovered ();

			if (item != null)
				item.hovered ();

			HoveredItem = item;

			if (controller.prefs.ZoomEnabled) {
				set_input_mask ();
			}

			if (hover_reposition_timer_id > 0U) {
				Source.remove (hover_reposition_timer_id);
				hover_reposition_timer_id = 0U;
			}

			if (controller.drag_manager.ExternalDragActive)
				return;

			controller.hover.hide ();

			if (HoveredItem == null
				|| HoveredItem is SeparatorDockItem
				|| !controller.prefs.TooltipsEnabled
				|| controller.drag_manager.InternalDragActive)
				return;

			hover_reposition_timer_id = Gdk.threads_add_timeout (HOVER_DELAY_TIME, () => {
				if (HoveredItem == null) {
					hover_reposition_timer_id = 0U;
					return false;
				}

				hover_reposition_timer_id = 0U;
				unowned HoverWindow hover = controller.hover;

				int x, y;
				string tooltip_text = HoveredItem.Text;
				if (!controller.prefs.CategorizeItems) {
					if (HoveredItem is FileDockItem) {
						tooltip_text = "%s • %s".printf (HoveredItem.Text, _("Folder"));
					} else if (HoveredItem is TransientDockItem) {
						tooltip_text = "%s • %s".printf (HoveredItem.Text, _("Running"));
					} else if ((HoveredItem is PlankDockItem || (HoveredItem.Prefs != null && HoveredItem.Prefs.Launcher.has_prefix ("docklet://"))) && !(HoveredItem is TrashDockItem)) {
						tooltip_text = "%s • %s".printf (HoveredItem.Text, _("Docklet"));
					}
				} else if (controller.prefs.AccordionDocklets && controller.app_provider != null
					&& controller.app_provider.get_docklet_count () > 1
					&& HoveredItem == controller.app_provider.get_anchor_docklet ()) {
					unowned DefaultApplicationDockItemProvider? app_prov = controller.app_provider;
					bool is_horiz = controller.position_manager.is_horizontal_dock ();
					string arrow_expand = is_horiz ? "▸" : "▾";
					string arrow_collapse = is_horiz ? "◂" : "▴";

					if (app_prov != null && !app_prov.docklets_expanded) {
						if (controller.prefs.AccordionClickToExpand) {
							tooltip_text = "%s • %s %s (%s)".printf (HoveredItem.Text, _("Docklets"), arrow_expand, _("Click to expand"));
						} else {
							tooltip_text = "%s • %s %s".printf (HoveredItem.Text, _("Docklets"), arrow_expand);
						}
					} else {
						tooltip_text = "%s • %s %s".printf (HoveredItem.Text, _("Docklets"), arrow_collapse);
					}
				}
				hover.set_text (tooltip_text);
				controller.position_manager.get_hover_position (HoveredItem, out x, out y);
				var dock_region = controller.position_manager.get_dock_window_region ();
				var dock_thickness = GtkLayerShell.is_supported ()
					? controller.position_manager.get_visual_thickness () + 40
					: (controller.position_manager.is_horizontal_dock () ? dock_region.height : dock_region.width);
				var monitor = PositionManager.get_monitor_for_plug_name (get_display (), controller.prefs.Monitor);
				hover.show_at (x, y, controller.position_manager.Position, dock_thickness, monitor);

				if (menu_is_visible () || controller.folder_menu.get_visible () || controller.window_cards.get_visible ())
					hover.hide ();

				return false;
			});
		}

		public bool update_hovered (int x, int y)
		{
			if (controller.hide_manager.Hidden) {
				set_hovered_provider (null);
				set_hovered (null);
				return false;
			}

			unowned PositionManager position_manager = controller.position_manager;
			unowned DockItem? drag_item = controller.drag_manager.DragItem;
			Gdk.Rectangle rect;

			bool drag_active = (controller.drag_manager.ExternalDragActive || controller.drag_manager.InternalDragActive);

			if (HoveredItem != null) {
				rect = position_manager.get_hover_region_for_element (HoveredItem);
				bool within_hovered = false;
				if (drag_active) {
					if (position_manager.is_horizontal_dock ()) {
						within_hovered = (x >= rect.x && x < rect.x + rect.width && y >= 0 && y < position_manager.DockHeight);
					} else {
						within_hovered = (y >= rect.y && y < rect.y + rect.height && x >= 0 && x < position_manager.DockWidth);
					}
				} else {
					within_hovered = (y >= rect.y && y < rect.y + rect.height && x >= rect.x && x < rect.x + rect.width);
				}
				if (within_hovered) {
					if (drag_item == HoveredItem) {
						set_hovered_provider (HoveredItem.Container as DockItemProvider);
						set_hovered (null);
						return false;
					} else {
						return true;
					}
				}
			}

			rect = position_manager.get_cursor_region ();
			if (y < rect.y || y >= rect.y + rect.height || x < rect.x || x >= rect.x + rect.width) {
				set_hovered_provider (null);
				set_hovered (null);
				return false;
			}

			bool found_hovered_provider = false;
			unowned DockItem? item = null;
			unowned DockItemProvider? provider = null;

			foreach (var element in controller.VisibleElements) {
				item = (element as DockItem);
				if (item != null) {
					rect = position_manager.get_hover_region_for_element (item);
					bool matches = false;
					if (drag_active) {
						if (position_manager.is_horizontal_dock ()) {
							matches = (x >= rect.x && x < rect.x + rect.width && y >= 0 && y < position_manager.DockHeight);
						} else {
							matches = (y >= rect.y && y < rect.y + rect.height && x >= 0 && x < position_manager.DockWidth);
						}
					} else {
						matches = (y >= rect.y && y < rect.y + rect.height && x >= rect.x && x < rect.x + rect.width);
					}
					if (!matches)
						continue;

					if (drag_item == item)
						break;

					set_hovered_provider (null);
					set_hovered (item as DockItem);
					return true;
				}

				provider = (element as DockItemProvider);
				if (provider == null)
					continue;

				rect = position_manager.get_hover_region_for_element (provider);
				bool matches_prov = false;
				if (drag_active) {
					if (position_manager.is_horizontal_dock ()) {
						matches_prov = (x >= rect.x && x < rect.x + rect.width && y >= 0 && y < position_manager.DockHeight);
					} else {
						matches_prov = (y >= rect.y && y < rect.y + rect.height && x >= rect.x && x < rect.x + rect.width);
					}
				} else {
					matches_prov = (y >= rect.y && y < rect.y + rect.height && x >= rect.x && x < rect.x + rect.width);
				}
				if (!matches_prov)
					continue;

				set_hovered_provider (provider);
				found_hovered_provider = true;

				foreach (var element2 in provider.VisibleElements) {
					rect = position_manager.get_hover_region_for_element (element2);
					bool matches_el2 = false;
					if (drag_active) {
						if (position_manager.is_horizontal_dock ()) {
							matches_el2 = (x >= rect.x && x < rect.x + rect.width && y >= 0 && y < position_manager.DockHeight);
						} else {
							matches_el2 = (y >= rect.y && y < rect.y + rect.height && x >= 0 && x < position_manager.DockWidth);
						}
					} else {
						matches_el2 = (y >= rect.y && y < rect.y + rect.height && x >= rect.x && x < rect.x + rect.width);
					}
					if (!matches_el2)
						continue;

					if (drag_item == element2)
						break;

					set_hovered (element2 as DockItem);
					return true;
				}
			}

			if (!found_hovered_provider)
				set_hovered_provider (null);
			set_hovered (null);
			return false;
		}

		public void update_size_and_position ()
		{
			unowned PositionManager position_manager = controller.position_manager;

			update_layer_shell_anchors ();

			var win_rect = position_manager.get_dock_window_region ();

			int width_current, height_current;
			get_size_request (out width_current, out height_current);
			var needs_resize = (win_rect.width != width_current || win_rect.height != height_current);

			if (needs_resize || width_current <= 0) {
				Logger.verbose ("DockWindow.set_size_request (width = %i, height = %i)", win_rect.width, win_rect.height);
				set_size_request (win_rect.width, win_rect.height);
				if (!GtkLayerShell.is_supported ()) {
					resize (win_rect.width, win_rect.height);
				}
				controller.renderer.reset_buffers ();

				update_icon_regions ();
				input_rect = { -1, -1, -1, -1 };
				set_input_mask ();
				set_hovered_provider (null);
				set_hovered (null);
				update_exclusive_zone ();
			} else {
				set_input_mask ();
			}

			bool ready = true;
			if (!GtkLayerShell.is_supported ()) {
				int cur_w, cur_h;
				get_size (out cur_w, out cur_h);
				if (cur_w != win_rect.width || cur_h != win_rect.height) {
					resize (win_rect.width, win_rect.height);
				}
				move (win_rect.x, win_rect.y);
				ready = WindowControl.position_dock (win_rect.x, win_rect.y, win_rect.width, win_rect.height);
			}

			if (ready) {
				show_all ();
				stick ();
				if (!GtkLayerShell.is_supported ())
					present (); 
				queue_draw ();
			} else if (!GtkLayerShell.is_supported () && get_visible ()) {
				hide ();
			}
		}

		public void update_icon_regions ()
		{
			Logger.verbose ("DockWindow.update_icon_regions ()");
		}

		public void update_icon_region (ApplicationDockItem appitem)
		{
			Logger.verbose ("DockWindow.update_icon_region ('%s')", appitem.Text);
		}

		public bool menu_is_visible ()
		{
			return (menu != null && menu.get_visible ());
		}

		bool show_menu (DockItem? item, PopupButton button, Gdk.ModifierType state, int event_x, int event_y, Gdk.Event? trigger_event)
		{
			if (menu != null) {
				foreach (var w in menu.get_children ())
					menu.remove (w);

				menu.show.disconnect (on_menu_show);
				menu.hide.disconnect (on_menu_hide);
				menu.detach ();
				menu = null;
			}

			if (controller.folder_menu.get_visible ())
				controller.folder_menu.close_menu ();

			if (controller.window_cards.get_visible ())
				controller.window_cards.close_cards ();

			menu_items = null;
			Gtk.MenuPositionFunc? position_func = null;
			message ("DockWindow: show_menu mapped_button=%u item=%s", (uint) button, item != null ? item.Text : "null");

			if ((button & PopupButton.RIGHT) != 0
				&& (item == null || item is SeparatorDockItem || (state & Gdk.ModifierType.CONTROL_MASK) != 0)) {
				if (controller.prefs.SystemMenuAccess != 4) {
					menu_items = new Gee.ArrayList<Gtk.MenuItem> ();
					PreferencesDockItem.append_full_system_menu (controller, menu_items);
				} else {
					menu_items = Factory.item_factory.get_item_for_dock ().get_menu_items ();
				}
				if ((state & Gdk.ModifierType.MOD1_MASK) != 0
					&& (state & Gdk.ModifierType.SHIFT_MASK) != 0)
					menu_items.add_all (get_dock_debug_menu_items (controller));
				set_hovered_provider (null);
				set_hovered (null);
			} else if (item != null && item.is_valid () && item.has_menu_for_button (button)) {
				menu_items = item.get_menu_items_for_button (button);
				if ((state & Gdk.ModifierType.MOD1_MASK) != 0
					&& (state & Gdk.ModifierType.SHIFT_MASK) != 0)
					menu_items.add_all (get_item_debug_menu_items (item));
				position_func = (Gtk.MenuPositionFunc) position_menu;

				if ((button & PopupButton.RIGHT) != 0 && !(item is PreferencesDockItem) && !(item is PlankDockItem)) {
					int access = controller.prefs.SystemMenuAccess;
					if (!controller.prefs.CategorizeItems && (access == 1 || access == 2)) {
						access = 3;
					}
					if (access == 3) {
						PreferencesDockItem.append_full_system_menu (controller, menu_items);
					} else if (access == 2) {
						bool is_docklet = DefaultApplicationDockItemProvider.is_docklet_element (item) || (item is TrashDockItem);
						if (is_docklet) {
							PreferencesDockItem.append_full_system_menu (controller, menu_items);
						} else {
							bool has_docklets = false;
							foreach (var it in controller.Items) {
								if (DefaultApplicationDockItemProvider.is_docklet_element (it) || (it is TrashDockItem)) {
									has_docklets = true;
									break;
								}
							}
							if (!has_docklets) {
								PreferencesDockItem.append_full_system_menu (controller, menu_items);
							}
						}
					} else if (access == 1) {
						bool is_docklet = DefaultApplicationDockItemProvider.is_docklet_element (item) || (item is TrashDockItem);
						if (is_docklet) {
							PreferencesDockItem.append_full_system_menu (controller, menu_items);
						}
					} else {
						append_global_preferences_and_quit (menu_items);
					}
				}
			}

			if (menu_items == null || menu_items.size == 0)
				return false;

			menu = new Gtk.Menu ();
			menu.attach_to_widget (this, null);
			menu.show.connect (on_menu_show);
			menu.hide.connect (on_menu_hide);

			var iterator = menu_items.bidir_list_iterator ();
			if (controller.prefs.Position == Gtk.PositionType.TOP && button != PopupButton.LEFT) {
				iterator.last ();
				do {
					var menu_item = iterator.get ();
					menu_item.show_all ();
					menu.append (menu_item);
				} while (iterator.previous ());
			} else {
				iterator.first ();
				do {
					var menu_item = iterator.get ();
					menu_item.show_all ();
					menu.append (menu_item);
				} while (iterator.next ());
			}

			Gdk.Gravity widget_anchor = Gdk.Gravity.NORTH;
			Gdk.Gravity menu_anchor = Gdk.Gravity.SOUTH;
			Gdk.Rectangle rect = Gdk.Rectangle ();
			var win_rect = controller.position_manager.get_dock_window_region ();
			int win_w = win_rect.width;
			int win_h = win_rect.height;

			int center_x = event_x;
			int center_y = event_y;
			if (item != null) {
				controller.position_manager.get_hover_position (item, out center_x, out center_y);
			}

			switch (controller.prefs.Position) {
			case Gtk.PositionType.TOP:
				widget_anchor = Gdk.Gravity.SOUTH;
				menu_anchor = Gdk.Gravity.NORTH;
				rect = Gdk.Rectangle () { x = center_x, y = win_h, width = 1, height = 1 };
				break;
			case Gtk.PositionType.LEFT:
				widget_anchor = Gdk.Gravity.EAST;
				menu_anchor = Gdk.Gravity.WEST;
				rect = Gdk.Rectangle () { x = win_w, y = center_y, width = 1, height = 1 };
				break;
			case Gtk.PositionType.RIGHT:
				widget_anchor = Gdk.Gravity.WEST;
				menu_anchor = Gdk.Gravity.EAST;
				rect = Gdk.Rectangle () { x = 0, y = center_y, width = 1, height = 1 };
				break;
			case Gtk.PositionType.BOTTOM:
			default:
				widget_anchor = Gdk.Gravity.NORTH;
				menu_anchor = Gdk.Gravity.SOUTH;
				rect = Gdk.Rectangle () { x = center_x, y = 0, width = 1, height = 1 };
				break;
			}

			var trigger = trigger_event != null ? trigger_event : last_button_event;
			menu.popup_at_rect (get_window (), rect, widget_anchor, menu_anchor, trigger);

			return true;
		}

		void append_global_preferences_and_quit (Gee.ArrayList<Gtk.MenuItem> items)
		{
			items.add (new Gtk.SeparatorMenuItem ());

			var shortcuts_item = DockElement.create_menu_item (_("_Shortcuts & Gestures..."), "help-browser", true);
			shortcuts_item.activate.connect (() => {
				Application.get_default ().activate_action ("shortcuts", null);
			});
			items.add (shortcuts_item);

			var pref_item = DockElement.create_menu_item (_("_Preferences..."), "preferences-system", true);
			pref_item.activate.connect (() => {
				Application.get_default ().activate_action ("preferences", null);
			});
			items.add (pref_item);

			var quit_item = DockElement.create_menu_item (_("_Quit"), "application-exit", true);
			quit_item.activate.connect (() => {
				Application.get_default ().activate_action ("quit", null);
			});
			items.add (quit_item);
		}

		static Gee.ArrayList<Gtk.MenuItem> get_dock_debug_menu_items (DockController controller)
		{
			var debug_items = new Gee.ArrayList<Gtk.MenuItem> ();

			debug_items.add (new Gtk.SeparatorMenuItem ());

			var dev_item = new Gtk.MenuItem.with_mnemonic (_("Developer _Tools"));
			var dev_submenu = new Gtk.Menu ();
			dev_item.set_submenu (dev_submenu);

			Gtk.MenuItem menu_item;

			menu_item = new Gtk.MenuItem.with_mnemonic (_("Open config folder"));
			menu_item.activate.connect (() => {
				System.get_default ().open (controller.config_folder);
			});
			dev_submenu.append (menu_item);

			menu_item = new Gtk.MenuItem.with_mnemonic (_("Open current theme file"));
			menu_item.activate.connect (() => {
				System.get_default ().open (controller.renderer.theme.get_backing_file ());
			});
			dev_submenu.append (menu_item);

			dev_submenu.show_all ();
			debug_items.add (dev_item);

			return debug_items;
		}

		static Gee.ArrayList<Gtk.MenuItem> get_item_debug_menu_items (DockItem item)
		{
			var debug_items = new Gee.ArrayList<Gtk.MenuItem> ();

			debug_items.add (new Gtk.SeparatorMenuItem ());

			var dev_item = new Gtk.MenuItem.with_mnemonic (_("Developer _Tools"));
			var dev_submenu = new Gtk.Menu ();
			dev_item.set_submenu (dev_submenu);

			Gtk.MenuItem menu_item;

			var dock_item_file = item.Prefs.get_backing_file ();
			menu_item = new Gtk.MenuItem.with_mnemonic (_("Print info to stdout"));
			menu_item.activate.connect (() => {
				print ("DockItemFile: '%s'\nText = '%s'\nIcon = '%s'\nLauncher = '%s'\n",
					dock_item_file != null ? dock_item_file.get_uri () : "",
					item.Text, item.Icon, item.Launcher);
			});
			dev_submenu.append (menu_item);

			menu_item = new Gtk.MenuItem.with_mnemonic (_("Open dockitem file"));
			menu_item.activate.connect (() => {
				System.get_default ().open (dock_item_file);
			});
			menu_item.sensitive = (dock_item_file != null && dock_item_file.query_exists ());
			dev_submenu.append (menu_item);

			menu_item = new Gtk.MenuItem.with_mnemonic (_("Open launcher file"));
			menu_item.activate.connect (() => {
				System.get_default ().open (File.new_for_uri (item.Launcher));
			});
			menu_item.sensitive = (item.Launcher != "");
			dev_submenu.append (menu_item);

			dev_submenu.show_all ();
			debug_items.add (dev_item);

			return debug_items;
		}

		void on_menu_hide ()
		{
			update_icon_regions ();
			unowned HideManager hide_manager = controller.hide_manager;
			hide_manager.update_hovered ();
			if (!hide_manager.Hovered) {
				set_hovered_provider (null);
				set_hovered (null);
			}

			controller.check_collapse_after_interaction ();

			menu_items = null;
		}

		void on_menu_show ()
		{
			update_icon_regions ();
			controller.hover.hide ();
			if (controller.app_provider != null)
				controller.app_provider.cancel_collapse_timer ();
			controller.renderer.animated_draw ();
		}

		[CCode (instance_pos = -1)]
		void position_menu (Gtk.Menu menu, ref int x, ref int y, out bool push_in)
		{
			Gtk.Requisition requisition;
			menu.get_preferred_size (null, out requisition);
			controller.position_manager.get_menu_position (HoveredItem, requisition, out x, out y);
			push_in = false;
		}

		Gdk.Rectangle input_rect = { 0, 0, 0, 0 };

		public void set_input_mask ()
		{
			var window = get_window ();
			if (window == null)
				return;

			var cursor_region = controller.position_manager.get_cursor_region ();
			if (cursor_region.x == input_rect.x &&
			    cursor_region.y == input_rect.y &&
			    cursor_region.width == input_rect.width &&
			    cursor_region.height == input_rect.height) {
				return;
			}
			input_rect = cursor_region;

			if (cursor_region.width <= 0 || cursor_region.height <= 0) {
				window.input_shape_combine_region (new Cairo.Region (), 0, 0);
				return;
			}

			Cairo.RectangleInt region_rect = {
				cursor_region.x,
				cursor_region.y,
				cursor_region.width,
				cursor_region.height
			};
			window.input_shape_combine_region (new Cairo.Region.rectangle (region_rect), 0, 0);
		}
	}
}