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
	 * Handles all of the drag'n'drop events for a dock.
	 */
	public class DragManager : GLib.Object
	{
		public DockController controller { private get; construct; }
		
		public bool InternalDragActive { get; private set; default = false; }

		public DockItem? DragItem { get; private set; default = null; }
		
		public bool DragNeedsCheck { get; private set; default = true; }
		
		bool external_drag_active = false;
		public bool ExternalDragActive {
			get { return external_drag_active; }
			private set {
				if (external_drag_active == value)
					return;
				external_drag_active = value;
				
				if (!value) {
					drag_known = false;
					drag_data = null;
					drag_data_requested = false;
					DragNeedsCheck = true;
				}
			}
		}
		
		bool dropped_on_target = false;
		bool left_dock_during_drag = false;
		bool is_outside_dock = false;
		bool reposition_mode = false;
		public bool RepositionMode {
			get { return reposition_mode; }
			private set {
				if (reposition_mode == value)
					return;
				reposition_mode = value;
				
				if (reposition_mode)
					disable_drag_to (controller.window);
				else
					enable_drag_to (controller.window);
			}
		}
		
		bool drag_canceled = false;
		bool drag_known = false;
		bool drag_data_requested = false;
		uint marker = 0U;
		uint drag_hover_timer_id = 0U;
		
		Gee.ArrayList<string>? drag_data = null;
		
		int window_scale_factor = 1;
		ulong drag_item_redraw_handler_id = 0UL;
		weak Gdk.DragContext? active_drag_context = null;
		
		/**
		 * Creates a new instance of a DragManager, which handles
		 * drag'n'drop interactions of a dock.
		 *
		 * @param controller the {@link DockController} to manage drag'n'drop for
		 */
		public DragManager (DockController controller)
		{
			GLib.Object (controller : controller);
		}
		
		/**
		 * Initializes the drag-manager.  Call after the DockWindow is constructed.
		 */
		public void initialize ()
			requires (controller.window != null)
		{
			unowned DockWindow window = controller.window;
			unowned DockPreferences prefs = controller.prefs;
			
			window.drag_motion.connect (drag_motion);
			window.drag_begin.connect (drag_begin);
			window.drag_data_received.connect (drag_data_received);
			window.drag_data_get.connect (drag_data_get);
			window.drag_drop.connect (drag_drop);
			window.drag_end.connect (drag_end);
			window.drag_leave.connect (drag_leave);
			window.drag_failed.connect (drag_failed);
			
			prefs.notify["LockItems"].connect (lock_items_changed);
			
			enable_drag_to (window);
			if (!prefs.LockItems)
				enable_drag_from (window);
		}
		
		~DragManager ()
		{
			unowned DockWindow window = controller.window;
			
			window.drag_motion.disconnect (drag_motion);
			window.drag_begin.disconnect (drag_begin);
			window.drag_data_received.disconnect (drag_data_received);
			window.drag_data_get.disconnect (drag_data_get);
			window.drag_drop.disconnect (drag_drop);
			window.drag_end.disconnect (drag_end);
			window.drag_leave.disconnect (drag_leave);
			window.drag_failed.disconnect (drag_failed);
			
			controller.prefs.notify["LockItems"].disconnect (lock_items_changed);
			
			disable_drag_to (window);
			disable_drag_from (window);
		}
		
		void lock_items_changed ()
		{
			unowned DockWindow window = controller.window;
			
			if (controller.prefs.LockItems)
				disable_drag_from (window);
			else
				enable_drag_from (window);
		}
		
		[CCode (instance_pos = -1)]
		void drag_data_get (Gtk.Widget w, Gdk.DragContext context, Gtk.SelectionData selection_data, uint info, uint time_)
		{
			if (InternalDragActive && DragItem != null) {
				string uri = "%s\r\n".printf (DragItem.as_uri ());
				selection_data.set (selection_data.get_target (), 8, (uchar[]) uri.to_utf8 ());
			}
		}
		
		/**
		 * Whether the current dragged-data is accepted by the given dock-item
		 *
		 * @param item the dock-item
		 */
		public bool drop_is_accepted_by (DockItem item)
		{
			if (drag_data == null)
				return false;
			
			return item.can_accept_drop (drag_data);
		}
		
		void set_drag_icon (Gdk.DragContext context, DockItem? item, double opacity = 1.0)
		{
			if (item == null) {
				Gtk.drag_set_icon_default (context);
				return;
			}

			window_scale_factor = controller.window.get_window ().get_scale_factor ();
			var drag_icon_size = (int) (1.2 * controller.position_manager.ZoomIconSize);
			if (drag_icon_size % 2 == 1)
				drag_icon_size++;
			drag_icon_size *= window_scale_factor;
			var drag_surface = new Surface (drag_icon_size, drag_icon_size);
			drag_surface.Internal.set_device_scale (window_scale_factor, window_scale_factor);
			
			var item_surface = item.get_surface_copy (drag_icon_size, drag_icon_size, drag_surface);
			unowned Cairo.Context cr = drag_surface.Context;
			if (window_scale_factor > 1) {
				cr.save ();
				cr.scale (1.0 / window_scale_factor, 1.0 / window_scale_factor);
			}
			cr.set_operator (Cairo.Operator.OVER);
			cr.set_source_surface (item_surface.Internal, 0, 0);
			cr.paint_with_alpha (opacity);
			if (window_scale_factor > 1)
				cr.restore ();
			
			unowned Cairo.Surface surface = drag_surface.Internal;
			surface.set_device_offset (-drag_icon_size / 2.0, -drag_icon_size / 2.0);
			Gtk.drag_set_icon_surface (context, surface);
		}
		
		[CCode (instance_pos = -1)]
		void drag_begin (Gtk.Widget w, Gdk.DragContext context)
		{
			unowned DockWindow window = controller.window;
			
			window.notify["HoveredItem"].connect (hovered_item_changed);
			
			InternalDragActive = true;
			drag_canceled = false;
			dropped_on_target = false;
			left_dock_during_drag = false;
			is_outside_dock = false;
			
			DragItem = window.HoveredItem;
			
			if (RepositionMode || DragItem is SeparatorDockItem)
				DragItem = null;
			
			if (DragItem == null) {
				Gdk.drag_abort (context, Gtk.get_current_event_time ());
				return;
			}
			
			active_drag_context = context;
			set_drag_icon (context, DragItem, 0.8);
			drag_item_redraw_handler_id = DragItem.needs_redraw.connect (() => {
				set_drag_icon (context, DragItem, 0.8);
			});
			
			context.get_device ().get_seat ().grab (window.get_window (), Gdk.SeatCapabilities.POINTER, true,
				null, null, null);
		}

		[CCode (instance_pos = -1)]
		void drag_data_received (Gtk.Widget w, Gdk.DragContext context, int x, int y, Gtk.SelectionData selection_data, uint info, uint time_)
		{
			if (drag_data_requested) {
				unowned string? data = (string?) selection_data.get_data ();
				if (data == null) {
					drag_data_requested = false;
					Gdk.drag_status (context, Gdk.DragAction.COPY, time_);
					return;
				}
				
				var uris = Uri.list_extract_uris (data);
				
				drag_data = new Gee.ArrayList<string> ();
				if (uris.length == 0) {
					var plain_uri = data.strip ();
					if (plain_uri.has_prefix ("application://") || plain_uri.has_prefix ("file://"))
						drag_data.add (plain_uri);
					else if (plain_uri.has_suffix (".desktop") && File.new_for_path (plain_uri).query_exists ())
						drag_data.add (File.new_for_path (plain_uri).get_uri ());
				}

				foreach (unowned string s in uris) {
					var uri = File.new_for_uri (s).get_uri ();
					if (uri != null)
						drag_data.add (uri);
				}
				
				drag_data_requested = false;
				
				if (drag_data.size == 1) {
					var uri = drag_data[0];
					DragNeedsCheck = !uri.has_suffix (".desktop");
				} else {
					DragNeedsCheck = true;
				}
				
				controller.renderer.animated_draw ();
				hovered_item_changed ();

				if (dropped_on_target)
					accept_external_drop (context, time_);
			}
			
			Gdk.drag_status (context, Gdk.DragAction.COPY, time_);
		}

		[CCode (instance_pos = -1)]
		void accept_external_drop (Gdk.DragContext context, uint time_)
		{
			if (drag_data == null)
				return;
			
			unowned DockWindow window = controller.window;
			unowned DockItem? item = window.HoveredItem;
			unowned DockItemProvider? provider = window.HoveredItemProvider;
			bool contains_directory = false;
			foreach (string uri in drag_data) {
				if (File.new_for_uri (uri).query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY) {
					contains_directory = true;
					break;
				}
			}
			
			if (!contains_directory && DragNeedsCheck && item != null && item.can_accept_drop (drag_data))
				item.accept_drop (drag_data);
			else if (!controller.prefs.LockItems && provider != null && provider.can_accept_drop (drag_data))
				provider.accept_drop (drag_data);
			
			Gtk.drag_finish (context, true, false, time_);
			ExternalDragActive = false;
		}

		[CCode (instance_pos = -1)]
		bool drag_drop (Gtk.Widget w, Gdk.DragContext context, int x, int y, uint time_)
		{
			dropped_on_target = true;
			
			if (drag_hover_timer_id > 0U) {
				GLib.Source.remove (drag_hover_timer_id);
				drag_hover_timer_id = 0U;
			}
			
			if (drag_data == null) {
				drag_data_requested = true;
				var target_atom = Gtk.drag_dest_find_target (controller.window, context, null);
				if (target_atom != Gdk.Atom.NONE)
					Gtk.drag_get_data (controller.window, context, target_atom, time_);
				else
					Gtk.drag_get_data (controller.window, context, Gdk.Atom.intern ("text/uri-list", false), time_);
				return true;
			}

			accept_external_drop (context, time_);
			return true;
		}
		
		[CCode (instance_pos = -1)]
		void drag_end (Gtk.Widget w, Gdk.DragContext context)
		{
			unowned HideManager hide_manager = controller.hide_manager;
			
			if (drag_item_redraw_handler_id > 0UL) {
				if (DragItem != null)
					GLib.SignalHandler.disconnect (DragItem, drag_item_redraw_handler_id);
				drag_item_redraw_handler_id = 0UL;
			}
			
			if (!drag_canceled && DragItem != null) {
				hide_manager.update_hovered ();
				
				if (!dropped_on_target) {
					if (DragItem.can_be_removed ()) {
						unowned ApplicationDockItem? app_item = (DragItem as ApplicationDockItem);
						var was_pinned = !(DragItem is TransientDockItem);
						var still_running = (app_item != null && app_item.is_running ());
						var launcher_uri = DragItem.Launcher;
						unowned DockContainer? drag_container = DragItem.Container;
						
						if (app_item == null || !(still_running || app_item.has_unity_info ())) {
							DragItem.IsVisible = false;
							DragItem.Container.remove (DragItem);
						}
						DragItem.delete ();
						
						// A pinned app that's still running should keep a temporary icon
						// instead of disappearing entirely once dragged out of the dock.
						if (was_pinned && still_running && drag_container != null)
							drag_container.add (new TransientDockItem.with_launcher (launcher_uri));
						
						var local_cursor = controller.renderer.local_cursor;
						var x = local_cursor.x;
						var y = local_cursor.y;
						var display = controller.window.get_display ();
						var dock_window = controller.window.get_window ();
						var monitor = display != null && dock_window != null
							? display.get_monitor_at_window (dock_window) : null;
						if (monitor == null && display != null)
							monitor = display.get_primary_monitor () ?? display.get_monitor (0);

						if (monitor != null) {
							var geometry = monitor.get_geometry ();
							var dock_width = controller.window.get_allocated_width ();
							var dock_height = controller.window.get_allocated_height ();
							switch (controller.position_manager.Position) {
							case Gtk.PositionType.TOP:
								x += geometry.x + (geometry.width - dock_width) / 2;
								y += geometry.y;
								break;
							case Gtk.PositionType.BOTTOM:
								x += geometry.x + (geometry.width - dock_width) / 2;
								y += geometry.y + geometry.height - dock_height;
								break;
							case Gtk.PositionType.LEFT:
								x += geometry.x;
								y += geometry.y + (geometry.height - dock_height) / 2;
								break;
							case Gtk.PositionType.RIGHT:
								x += geometry.x + geometry.width - dock_width;
								y += geometry.y + (geometry.height - dock_height) / 2;
								break;
							}
						}

						PoofWindow.get_default ().show_at (x, y);
					}
				} else if (controller.window.HoveredItem == null) {
					if (controller.prefs.AutoPinning && DragItem is TransientDockItem) {
						unowned DefaultApplicationDockItemProvider? provider = (DragItem.Container as DefaultApplicationDockItemProvider);
						if (provider != null)
							provider.pin_item (DragItem);
					}
				}
				
				// Keep items on the correct side of the pinned/temporary divider after any
				// reorder: a temporary item resting left of it gets pinned, a pinned item
				// resting at/right of it gets unpinned - regardless of exact drop target.
				if (dropped_on_target && !controller.prefs.LockItems) {
					unowned DefaultApplicationDockItemProvider? provider = (DragItem.Container as DefaultApplicationDockItemProvider);
					if (provider != null) {
						unowned Gee.ArrayList<DockElement> elements = provider.Elements;
						var boundary = -1;
						for (var i = 0; i < elements.size; i++) {
							if (elements.get (i) is TransientDockItem) {
								boundary = i;
								break;
							}
						}
						
						if (boundary >= 0) {
							var drag_index = elements.index_of (DragItem);
							if (drag_index >= 0) {
								if (DragItem is TransientDockItem && drag_index < boundary)
									provider.pin_item (DragItem);
								else if (!(DragItem is TransientDockItem) && drag_index >= boundary)
									provider.pin_item (DragItem);
							}
						}
					}
				}
			}
			
			InternalDragActive = false;
			DragItem = null;
			active_drag_context = null;
			dropped_on_target = false;
			left_dock_during_drag = false;
			context.get_device ().get_seat ().ungrab ();
			
			controller.window.notify["HoveredItem"].disconnect (hovered_item_changed);
			controller.hover.hide ();
			controller.renderer.animated_draw ();
			hide_manager.update_hovered ();
		}

		[CCode (instance_pos = -1)]
		void drag_leave (Gtk.Widget w, Gdk.DragContext context, uint time_)
		{
			if (InternalDragActive) {
				left_dock_during_drag = true;
				is_outside_dock = true;
			}

			if (drag_hover_timer_id > 0U) {
				GLib.Source.remove (drag_hover_timer_id);
				drag_hover_timer_id = 0U;
			}
			
			controller.hide_manager.update_hovered ();
			drag_known = false;
			
			if (ExternalDragActive) {
				controller.window.notify["HoveredItem"].disconnect (hovered_item_changed);
				
				Gdk.threads_add_idle (() => {
					ExternalDragActive = false;
					controller.hover.hide ();
					controller.window.update_hovered (-1, -1);
					controller.renderer.animated_draw ();
					controller.hide_manager.update_hovered ();
					return false;
				});
			}
			
			if (DragItem == null)
				return;
			
			if (!controller.hide_manager.Hovered) {
				controller.window.update_hovered (-1, -1);
				controller.renderer.animated_draw ();
			}
		}
		
		[CCode (instance_pos = -1)]
		bool drag_failed (Gtk.Widget w, Gdk.DragContext context, Gtk.DragResult result)
		{
			drag_canceled = result == Gtk.DragResult.USER_CANCELLED;
			return !drag_canceled;
		}

[CCode (instance_pos = -1)]
		bool drag_motion (Gtk.Widget w, Gdk.DragContext context, int x, int y, uint time_)
		{
			if (RepositionMode)
				return true;

			if (ExternalDragActive == InternalDragActive)
				ExternalDragActive = !InternalDragActive;
			
			var actions = context.get_actions ();
			var action = context.get_suggested_action ();
			if ((actions & action) == 0) {
				if ((actions & Gdk.DragAction.COPY) != 0)
					action = Gdk.DragAction.COPY;
				else if ((actions & Gdk.DragAction.MOVE) != 0)
					action = Gdk.DragAction.MOVE;
				else if ((actions & Gdk.DragAction.LINK) != 0)
					action = Gdk.DragAction.LINK;
				else if ((actions & Gdk.DragAction.ASK) != 0)
					action = Gdk.DragAction.ASK;
			}
			Gdk.drag_status (context, action, time_);

			if (marker != direct_hash (context)) {
				marker = direct_hash (context);
				drag_known = false;
			}
			
			unowned DockWindow window = controller.window;
			unowned HideManager hide_manager = controller.hide_manager;
			
			if (ExternalDragActive && !drag_known) {
				drag_known = true;
				window.notify["HoveredItem"].connect (hovered_item_changed);
			}
			
			if (ExternalDragActive) {
				controller.hover.hide ();
			}
			
			controller.renderer.update_local_cursor (x, y);
			hide_manager.update_hovered_with_coords (x, y);
			window.update_hovered (x, y);
			
			is_outside_dock = false;
			left_dock_during_drag = false;
			
			return true;
		}

		void hovered_item_changed ()
		{
			unowned DockItem hovered_item = controller.window.HoveredItem;
			
			if (InternalDragActive && DragItem != null && hovered_item != null
				&& DragItem != hovered_item
				&& DragItem.Container == hovered_item.Container) {
				DragItem.Container.move_to (DragItem, hovered_item);
				convert_drag_item_if_crossed_boundary ();
			}
			
			if (drag_hover_timer_id > 0U) {
				GLib.Source.remove (drag_hover_timer_id);
				drag_hover_timer_id = 0U;
			}
			
			if (ExternalDragActive && drag_data != null)
				drag_hover_timer_id = Gdk.threads_add_timeout (1500, () => {
					unowned DockItem item = controller.window.HoveredItem;
					if (item != null)
						item.scrolled (Gdk.ScrollDirection.DOWN, 0, Gtk.get_current_event_time ());
					else
						drag_hover_timer_id = 0U;
					return item != null;
				});
		}
		
		/**
		 * Pins/unpins the dragged item the moment it crosses the pinned/temporary
		 * divider, so its slide-into-place animation matches its final state
		 * instead of a mismatched state being converted only after the drop.
		 */
		void convert_drag_item_if_crossed_boundary ()
		{
			if (DragItem == null || controller.prefs.LockItems)
				return;
			
			unowned DefaultApplicationDockItemProvider? provider = (DragItem.Container as DefaultApplicationDockItemProvider);
			if (provider == null)
				return;
			
			unowned Gee.ArrayList<DockElement> elements = provider.Elements;
			var boundary = -1;
			for (var i = 0; i < elements.size; i++) {
				if (elements.get (i) is TransientDockItem) {
					boundary = i;
					break;
				}
			}
			if (boundary < 0)
				return;
			
			var drag_index = elements.index_of (DragItem);
			if (drag_index < 0)
				return;
			
			var was_transient = (DragItem is TransientDockItem);
			// Already on the correct side of the divider - nothing to do.
			if (was_transient == (drag_index >= boundary))
				return;
			
			var launcher_uri = DragItem.Launcher;
			
			if (drag_item_redraw_handler_id > 0UL) {
				GLib.SignalHandler.disconnect (DragItem, drag_item_redraw_handler_id);
				drag_item_redraw_handler_id = 0UL;
			}
			
			provider.pin_item (DragItem);
			
			unowned DockItem? replacement = provider.item_for_uri (launcher_uri);
			if (replacement == null)
				return;
			
			DragItem = replacement;
			
			if (active_drag_context != null) {
				unowned Gdk.DragContext context = active_drag_context;
				set_drag_icon (context, DragItem, 0.8);
				drag_item_redraw_handler_id = DragItem.needs_redraw.connect (() => {
					set_drag_icon (context, DragItem, 0.8);
				});
			}
		}

		void enable_drag_to (DockWindow window)
		{
			Gtk.TargetEntry te1 = { "text/uri-list", 0, 0 };
			Gtk.TargetEntry te2 = { "text/plank-uri-list", 0, 0 };
			Gtk.TargetEntry te3 = { "text/plain", 0, 0 };
			Gtk.TargetEntry te4 = { "application/x-desktop", 0, 0 };
			Gtk.TargetEntry te5 = { "application/x-gnome-app-info", 0, 0 };
			Gtk.TargetEntry te6 = { "application/x-kde-appmenu", 0, 0 };
			Gtk.TargetEntry te7 = { "text/x-moz-url", 0, 0 };
			Gtk.drag_dest_set (window, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.DROP, {te1, te2, te3, te4, te5, te6, te7}, Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
		}
		
		void disable_drag_to (DockWindow window)
		{
			Gtk.drag_dest_unset (window);
		}
		
		void enable_drag_from (DockWindow window)
		{
			Gtk.TargetEntry te = { "text/plank-uri-list", Gtk.TargetFlags.SAME_APP, 0};
			Gtk.drag_source_set (window, Gdk.ModifierType.BUTTON1_MASK, { te }, Gdk.DragAction.PRIVATE);
		}
		
		void disable_drag_from (DockWindow window)
		{
			Gtk.drag_source_unset (window);
		}
	}
}

