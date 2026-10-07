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
		weak DockItem? drop_target_item = null;
		
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
			window.cancel_long_press ();
			
			window.notify["HoveredItem"].connect (hovered_item_changed);
			
			InternalDragActive = true;
			drag_canceled = false;
			dropped_on_target = false;
			left_dock_during_drag = false;
			is_outside_dock = false;
			
			DragItem = window.HoveredItem;
			
			if (RepositionMode || DragItem is SeparatorDockItem || DragItem is TrashDockItem)
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
				
				drag_data = new Gee.ArrayList<string> ();
				
				string[]? raw_uris = selection_data.get_uris ();
				if (raw_uris != null && raw_uris.length > 0) {
					foreach (unowned string s in raw_uris) {
						string cleaned = s.strip ();
						if (cleaned.length > 0 && !drag_data.contains (cleaned))
							drag_data.add (cleaned);
					}
				}
				
				if (drag_data.size == 0 && data != null) {
					var uris = Uri.list_extract_uris (data);
					if (uris.length == 0) {
						var plain_uri = data.strip ();
						if (plain_uri.has_prefix ("application://") || plain_uri.has_prefix ("file://")) {
							drag_data.add (plain_uri);
						} else {
							var f = File.new_for_commandline_arg (plain_uri);
							if (f.query_exists ())
								drag_data.add (f.get_uri ());
						}
					}

					foreach (unowned string s in uris) {
						string cleaned = s.strip ();
						if (cleaned.length == 0)
							continue;
						
						string? uri = null;
						if (cleaned.has_prefix ("file://") || cleaned.has_prefix ("application://")) {
							uri = File.new_for_uri (cleaned).get_uri ();
						} else {
							var f = File.new_for_commandline_arg (cleaned);
							if (f.query_exists ())
								uri = f.get_uri ();
						}
						
						if (uri != null && !drag_data.contains (uri))
							drag_data.add (uri);
					}
				}
				
				drag_data_requested = false;
				
				if (drag_data.size == 0) {
					if (dropped_on_target) {
						Gtk.drag_finish (context, false, false, time_);
						dropped_on_target = false;
						drop_target_item = null;
					} else {
						Gdk.drag_status (context, Gdk.DragAction.COPY, time_);
					}
					return;
				}
				
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
			if (drag_data == null) {
				Gtk.drag_finish (context, false, false, time_);
				drop_target_item = null;
				return;
			}
			
			unowned DockWindow window = controller.window;
			unowned DockItem? item = drop_target_item;
			if (item == null)
				item = window.HoveredItem;
			drop_target_item = null;
			
			unowned DockItemProvider? provider = window.HoveredItemProvider;
			if (provider == null && item != null)
				provider = item.Container as DockItemProvider;
			if (provider == null)
				provider = controller.default_provider;

			bool contains_directory = false;
			foreach (string uri in drag_data) {
				if (File.new_for_uri (uri).query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY) {
					contains_directory = true;
					break;
				}
			}
			
			bool handled = false;
			bool item_can_drop = (item != null && item.can_accept_drop (drag_data));
			if (item_can_drop && (item is TrashDockItem || item is FileDockItem || (!contains_directory && DragNeedsCheck)))
				handled = item.accept_drop (drag_data);
			else if (!controller.prefs.LockItems && provider != null && provider.can_accept_drop (drag_data))
				handled = provider.accept_drop (drag_data);
			
			Gtk.drag_finish (context, handled, false, time_);
			ExternalDragActive = false;
			drag_data = null;
			dropped_on_target = false;
			controller.renderer.animated_draw ();
		}

		[CCode (instance_pos = -1)]
		bool drag_drop (Gtk.Widget w, Gdk.DragContext context, int x, int y, uint time_)
		{
			dropped_on_target = true;
			controller.renderer.update_local_cursor (x, y);
			controller.hide_manager.update_hovered_with_coords (x, y);
			controller.window.update_hovered (x, y);
			drop_target_item = controller.window.HoveredItem;
			
			if (drag_hover_timer_id > 0U) {
				GLib.Source.remove (drag_hover_timer_id);
				drag_hover_timer_id = 0U;
			}
			
			if (ExternalDragActive) {
				drag_data = null;
				drag_data_requested = true;
				var target_atom = Gtk.drag_dest_find_target (controller.window, context, null);
				if (target_atom != Gdk.Atom.NONE)
					Gtk.drag_get_data (controller.window, context, target_atom, time_);
				else
					Gtk.drag_get_data (controller.window, context, Gdk.Atom.intern ("text/uri-list", false), time_);
			} else {
				Gtk.drag_finish (context, true, false, time_);
			}
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
						
						// Compute poof position using dock origin (exact same way as tooltips / HoverWindow)
						int poof_x = 0;
						int poof_y = 0;
						controller.position_manager.get_hover_position (DragItem, out poof_x, out poof_y);
						var dock_region = controller.position_manager.get_dock_window_region ();
						var dock_thickness = controller.position_manager.is_horizontal_dock ()
							? dock_region.height : dock_region.width;
						var monitor = PositionManager.get_monitor_for_plug_name (controller.window.get_display (), controller.prefs.Monitor);
						var dock_pos = controller.position_manager.Position;

						if (app_item == null || !(still_running || app_item.has_unity_info ())) {
							DragItem.IsVisible = false;
							DragItem.Container.remove (DragItem);
						}
						DragItem.delete ();
						
						// A pinned app that's still running should keep a temporary icon
						// instead of disappearing entirely once dragged out of the dock.
						if (was_pinned && still_running && drag_container != null)
							drag_container.add (new TransientDockItem.with_launcher (launcher_uri));

						PoofWindow.get_default ().show_at (poof_x, poof_y, dock_pos, dock_thickness, monitor);
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
				// resting right of it gets unpinned.
				if (dropped_on_target && !controller.prefs.LockItems) {
					unowned DefaultApplicationDockItemProvider? provider = (DragItem.Container as DefaultApplicationDockItemProvider);
					if (provider != null) {
						unowned Gee.ArrayList<DockElement> elements = provider.Elements;
						int drag_index = elements.index_of (DragItem);
						if (drag_index >= 0) {
							int sep1_index = -1;
							int transient_count = 0;
							for (int i = 0; i < elements.size; i++) {
								var el = elements.get (i);
								if (el is SeparatorDockItem) {
									if (sep1_index < 0)
										sep1_index = i;
								} else if (el is TransientDockItem) {
									transient_count++;
								}
							}
							
							// Only treat sep1 as pinned/transient divider if transient items exist.
							// Never unpin an item just because it was dragged before Trash.
							int divider_idx = (transient_count > 0) ? sep1_index : -1;

							if (divider_idx >= 0) {
								if (DragItem is TransientDockItem && drag_index < divider_idx) {
									provider.pin_item (DragItem);
								} else if (!(DragItem is TransientDockItem) && drag_index > divider_idx) {
									provider.pin_item (DragItem);
								}
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

			unowned DefaultApplicationDockItemProvider? default_app_provider = controller.default_provider as DefaultApplicationDockItemProvider;
			if (default_app_provider != null)
				default_app_provider.refresh_separators ();
			
			controller.window.notify["HoveredItem"].disconnect (hovered_item_changed);
			controller.hover.hide ();
			controller.renderer.animated_draw ();
			hide_manager.update_hovered ();
		}

		[CCode (instance_pos = -1)]
		void drag_leave (Gtk.Widget w, Gdk.DragContext context, uint time_)
		{
			if (dropped_on_target)
				return;

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
				unowned Gee.ArrayList<DockElement> elements = DragItem.Container.Elements;
				int drag_idx = elements.index_of (DragItem);
				int hover_idx = elements.index_of (hovered_item);
				
				// Identify separators and Trash markers
				int sep1_idx = -1;
				int sep2_idx = -1;
				int trash_idx = -1;
				for (int i = 0; i < elements.size; i++) {
					var el = elements.get (i);
					if (el is SeparatorDockItem) {
						if (sep1_idx < 0)
							sep1_idx = i;
						else
							sep2_idx = i;
					} else if (el is TrashDockItem) {
						trash_idx = i;
					}
				}
				
				// Identify separator preceding Trash
				int sep_trash_idx = -1;
				if (trash_idx >= 0) {
					if (sep2_idx >= 0)
						sep_trash_idx = sep2_idx;
					else if (sep1_idx >= 0)
						sep_trash_idx = sep1_idx;
				}
				
				// Rule 1: No app (pinned or unpinned, running or not) can ever move to or beyond the separator before Trash.
				if (sep_trash_idx >= 0 && hover_idx >= sep_trash_idx) {
					// Move DragItem to immediately before sep_trash if it isn't already there
					if (sep_trash_idx > 0 && drag_idx != sep_trash_idx - 1) {
						var target = elements.get (sep_trash_idx - 1);
						if (target != DragItem && !(target is SeparatorDockItem))
							DragItem.Container.move_to (DragItem, target);
					}
					return;
				}
				
				// Rule 2: Crossing Separator 1 (between pinned and transient):
				if (hovered_item is SeparatorDockItem) {
					if (hover_idx == sep1_idx) {
						if (drag_idx < sep1_idx && sep1_idx + 1 < elements.size) {
							// Moving right across Separator 1 into transient section
							var target = elements.get (sep1_idx + 1);
							if (target != DragItem && !(target is SeparatorDockItem) && !(target is TrashDockItem))
								DragItem.Container.move_to (DragItem, target);
						} else if (drag_idx > sep1_idx && sep1_idx > 0) {
							// Moving left across Separator 1 into pinned section
							var target = elements.get (sep1_idx - 1);
							if (target != DragItem && !(target is SeparatorDockItem))
								DragItem.Container.move_to (DragItem, target);
						}
					}
					return;
				}
				
				// Rule 3: Ordinary item hover within allowed bounds
				DragItem.Container.move_to (DragItem, hovered_item);
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

