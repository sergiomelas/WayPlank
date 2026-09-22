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

		Gdk.Rectangle input_rect;
		int requested_x;
		int requested_y;
		int window_position_retry = 0;

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
			GtkLayerShell.init_for_window (this);
			GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
			GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
			GtkLayerShell.set_namespace (this, "wayplank");
			GtkLayerShell.auto_exclusive_zone_enable (this);

			// Attach to the primary monitor output
			var display = Gdk.Display.get_default ();
			if (display != null) {
				var monitor = display.get_primary_monitor () ?? display.get_monitor (0);
				if (monitor != null)
					GtkLayerShell.set_monitor (this, monitor);
			}

			// Apply dynamic anchors based on current preferences
			update_layer_shell_anchors ();

			// Track position setting changes
			controller.prefs.notify["Position"].connect (() => {
				update_layer_shell_anchors ();
				update_size_and_position ();
			});

			// Native RGBA visual setup for Wayland transparency
			var visual = get_screen ().get_rgba_visual ();
			if (visual != null)
				set_visual (visual);

			set_app_paintable (true);

			accept_focus = false;
			can_focus = false;

			add_events (Gdk.EventMask.BUTTON_PRESS_MASK |
						Gdk.EventMask.BUTTON_RELEASE_MASK |
						Gdk.EventMask.ENTER_NOTIFY_MASK |
						Gdk.EventMask.LEAVE_NOTIFY_MASK |
						Gdk.EventMask.POINTER_MOTION_MASK |
						Gdk.EventMask.SCROLL_MASK |
						Gdk.EventMask.STRUCTURE_MASK);
		}

		~DockWindow ()
		{
			if (menu != null) {
				menu.show.disconnect (on_menu_show);
				menu.hide.disconnect (on_menu_hide);
			}

			if (hover_reposition_timer_id > 0U) {
				GLib.Source.remove (hover_reposition_timer_id);
				hover_reposition_timer_id = 0U;
			}
		}

		void update_layer_shell_anchors ()
		{
			var pos = controller.prefs.Position;

			GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, pos == Gtk.PositionType.BOTTOM);
			GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, pos == Gtk.PositionType.TOP);
			GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, pos == Gtk.PositionType.LEFT);
			GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, pos == Gtk.PositionType.RIGHT);
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool button_press_event (Gdk.EventButton event)
		{
			if (menu_is_visible ())
				return Gdk.EVENT_PROPAGATE;

			if (controller.hide_manager.Hidden)
				return Gdk.EVENT_STOP;

			if (controller.drag_manager.InternalDragActive)
				return Gdk.EVENT_STOP;

			if (HoveredItem == null)
				update_hovered ((int) event.x, (int) event.y);

			ClickedItem = HoveredItem;

			if (show_menu (HoveredItem, event))
				return Gdk.EVENT_STOP;

			long_press_active = false;
			long_press_button = event.button;
			if (long_press_timer_id > 0U)
				Source.remove (long_press_timer_id);
			long_press_timer_id = Gdk.threads_add_timeout (LONG_PRESS_TIME, () => {
				long_press_active = true;
				long_press_timer_id = 0U;
				return false;
			});

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
				return Gdk.EVENT_STOP;
			}

			if (controller.drag_manager.InternalDragActive)
				return Gdk.EVENT_STOP;

			if (HoveredItem != null && ClickedItem == null && menu_is_visible ())
				menu.hide ();

			if (ClickedItem != null && HoveredItem == ClickedItem && !menu_is_visible ()) {
				controller.hover.hide ();
				HoveredItem.clicked (PopupButton.from_event_button (event), event.state, event.time);
			}

			ClickedItem = null;

			return Gdk.EVENT_PROPAGATE;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool enter_notify_event (Gdk.EventCrossing event)
		{
			controller.renderer.update_local_cursor ((int) event.x, (int) event.y);
			update_hovered ((int) event.x, (int) event.y);

			return Gdk.EVENT_STOP;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool leave_notify_event (Gdk.EventCrossing event)
		{
			if ((bool) event.send_event)
				return Gdk.EVENT_PROPAGATE;

			if (!menu_is_visible ()) {
				set_hovered_provider (null);
				set_hovered (null);
			} else
				controller.hover.hide ();

			return Gdk.EVENT_STOP;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool motion_notify_event (Gdk.EventMotion event)
		{
			if (menu_is_visible ())
				return Gdk.EVENT_STOP;

			controller.renderer.update_local_cursor ((int) event.x, (int) event.y);
			update_hovered ((int) event.x, (int) event.y);

			return Gdk.EVENT_PROPAGATE;
		}

		/**
		 * {@inheritDoc}
		 */
		public override void drag_begin (Gdk.DragContext context)
		{
			long_press_active = false;
			if (long_press_timer_id > 0U) {
				Source.remove (long_press_timer_id);
				long_press_timer_id = 0U;
			}
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

			if (event.direction >= 4)
				return Gdk.EVENT_STOP;

			if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
				if (event.direction == Gdk.ScrollDirection.UP)
					controller.prefs.increase_icon_size ();
				else if (event.direction == Gdk.ScrollDirection.DOWN)
					controller.prefs.decrease_icon_size ();

				return Gdk.EVENT_STOP;
			}

			if (HoveredItem != null) {
				controller.hover.hide ();
				HoveredItem.scrolled (event.direction, event.state, event.time);
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
			set_input_mask ();
			
			int64 frame_time = 0;
			var frame_clock = get_frame_clock ();
			if (frame_clock != null)
				frame_time = frame_clock.get_frame_time ();

			controller.renderer.draw (cr, frame_time);

			return Gdk.EVENT_STOP;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool map_event (Gdk.EventAny event)
		{
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

			if (hover_reposition_timer_id > 0U) {
				Source.remove (hover_reposition_timer_id);
				hover_reposition_timer_id = 0U;
			}

			if (controller.drag_manager.ExternalDragActive)
				return;

			controller.hover.hide ();

			if (HoveredItem == null
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
				hover.set_text (HoveredItem.Text);
				controller.position_manager.get_hover_position (HoveredItem, out x, out y);
				hover.show_at (x, y, controller.position_manager.Position);

				if (menu_is_visible ())
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

			if (HoveredItem != null) {
				rect = position_manager.get_hover_region_for_element (HoveredItem);
				if (y >= rect.y && y < rect.y + rect.height && x >= rect.x && x < rect.x + rect.width)
					if (drag_item == HoveredItem) {
						set_hovered_provider (HoveredItem.Container as DockItemProvider);
						set_hovered (null);
						return false;
					} else {
						return true;
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
					if (y < rect.y || y >= rect.y + rect.height || x < rect.x || x >= rect.x + rect.width)
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
				if (y < rect.y || y >= rect.y + rect.height || x < rect.x || x >= rect.x + rect.width)
					continue;

				set_hovered_provider (provider);
				found_hovered_provider = true;

				foreach (var element2 in provider.VisibleElements) {
					rect = position_manager.get_hover_region_for_element (element2);
					if (y < rect.y || y >= rect.y + rect.height || x < rect.x || x >= rect.x + rect.width)
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

			if (needs_resize || win_rect.width > 0) {
				Logger.verbose ("DockWindow.set_size_request (width = %i, height = %i)", win_rect.width, win_rect.height);
				set_size_request (win_rect.width, win_rect.height);
				controller.renderer.reset_buffers ();

				update_icon_regions ();
				set_hovered_provider (null);
				set_hovered (null);
			}

			show_all ();
			present (); 
			queue_draw ();
		}

		public void update_icon_regions ()
		{
			Logger.verbose ("DockWindow.update_icon_regions ()");

			var use_hidden_region = (menu_is_visible () || controller.hide_manager.Hidden);

			foreach (var item in controller.VisibleItems) {
				unowned ApplicationDockItem? appitem = (item as ApplicationDockItem);
				if (appitem == null || !appitem.is_running ())
					continue;

				var region = controller.position_manager.get_icon_geometry (appitem, use_hidden_region);
				WindowControl.update_icon_regions (appitem.App, region);
			}
		}

		public void update_icon_region (ApplicationDockItem appitem)
		{
			if (!appitem.is_running ())
				return;

			Logger.verbose ("DockWindow.update_icon_region ('%s')", appitem.Text);

			var use_hidden_region = (menu_is_visible () || controller.hide_manager.Hidden);
			var region = controller.position_manager.get_icon_geometry (appitem, use_hidden_region);
			WindowControl.update_icon_regions (appitem.App, region);
		}

		public bool menu_is_visible ()
		{
			return (menu != null && menu.get_visible ());
		}

		bool show_menu (DockItem? item, Gdk.EventButton event)
		{
			if (menu != null) {
				foreach (var w in menu.get_children ())
					menu.remove (w);

				menu.show.disconnect (on_menu_show);
				menu.hide.disconnect (on_menu_hide);
				menu.detach ();
				menu = null;
			}

			menu_items = null;
			Gtk.MenuPositionFunc? position_func = null;
			var button = PopupButton.from_event_button (event);

			if ((button & PopupButton.RIGHT) != 0
				&& (item == null || (event.state & Gdk.ModifierType.CONTROL_MASK) != 0)) {
				menu_items = Factory.item_factory.get_item_for_dock ().get_menu_items ();
				if ((event.state & Gdk.ModifierType.MOD1_MASK) != 0
					&& (event.state & Gdk.ModifierType.SHIFT_MASK) != 0)
					menu_items.add_all (get_dock_debug_menu_items (controller));
				set_hovered_provider (null);
				set_hovered (null);
			} else if (item != null && item.is_valid () && (item.Button & button) != 0) {
				menu_items = item.get_menu_items ();
				if ((event.state & Gdk.ModifierType.MOD1_MASK) != 0
					&& (event.state & Gdk.ModifierType.SHIFT_MASK) != 0)
					menu_items.add_all (get_item_debug_menu_items (item));
				position_func = (Gtk.MenuPositionFunc) position_menu;
			}

			if (menu_items == null || menu_items.size == 0)
				return false;

			menu = new Gtk.Menu ();
			menu.attach_to_widget (this, null);
			menu.show.connect (on_menu_show);
			menu.hide.connect (on_menu_hide);

			var iterator = menu_items.bidir_list_iterator ();
			if (controller.prefs.Position == Gtk.PositionType.TOP) {
				iterator.last ();
				do {
					var menu_item = iterator.get ();
					menu_item.show ();
					menu.append (menu_item);
				} while (iterator.previous ());
			} else {
				iterator.first ();
				do {
					var menu_item = iterator.get ();
					menu_item.show ();
					menu.append (menu_item);
				} while (iterator.next ());
			}

			menu.popup (null, null, position_func, event.button, event.time);

			return true;
		}

		static Gee.ArrayList<Gtk.MenuItem> get_dock_debug_menu_items (DockController controller)
		{
			var debug_items = new Gee.ArrayList<Gtk.MenuItem> ();

			debug_items.add (new Gtk.SeparatorMenuItem ());
			debug_items.add (new TitledSeparatorMenuItem.no_line ("debug this dock"));

			Gtk.MenuItem menu_item;

			menu_item = new Gtk.MenuItem.with_mnemonic ("Open config folder");
			menu_item.activate.connect (() => {
				System.get_default ().open (controller.config_folder);
			});
			debug_items.add (menu_item);

			menu_item = new Gtk.MenuItem.with_mnemonic ("Open current theme file");
			menu_item.activate.connect (() => {
				System.get_default ().open (controller.renderer.theme.get_backing_file ());
			});
			debug_items.add (menu_item);

			return debug_items;
		}

		static Gee.ArrayList<Gtk.MenuItem> get_item_debug_menu_items (DockItem item)
		{
			var debug_items = new Gee.ArrayList<Gtk.MenuItem> ();

			debug_items.add (new Gtk.SeparatorMenuItem ());
			debug_items.add (new TitledSeparatorMenuItem.no_line ("debug this item"));

			Gtk.MenuItem menu_item;

			var dock_item_file = item.Prefs.get_backing_file ();
			menu_item = new Gtk.MenuItem.with_mnemonic ("Print info to stdout");
			menu_item.activate.connect (() => {
				print ("DockItemFile: '%s'\nText = '%s'\nIcon = '%s'\nLauncher = '%s'\n",
					dock_item_file != null ? dock_item_file.get_uri () : "",
					item.Text, item.Icon, item.Launcher);
			});
			debug_items.add (menu_item);

			menu_item = new Gtk.MenuItem.with_mnemonic ("Open dockitem file");
			menu_item.activate.connect (() => {
				System.get_default ().open (dock_item_file);
			});
			menu_item.sensitive = (dock_item_file != null && dock_item_file.query_exists ());
			debug_items.add (menu_item);

			menu_item = new Gtk.MenuItem.with_mnemonic ("Open launcher file");
			menu_item.activate.connect (() => {
				System.get_default ().open (File.new_for_uri (item.Launcher));
			});
			menu_item.sensitive = (item.Launcher != "");
			debug_items.add (menu_item);

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

			menu_items = null;
		}

		void on_menu_show ()
		{
			update_icon_regions ();
			controller.hover.hide ();
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

		void set_input_mask ()
		{
			return;
		}

		void set_struts ()
		{
			return;
		}
	}
}