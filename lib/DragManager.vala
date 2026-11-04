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
	 * Handles all of the drag'n'drop events for a dock.
	 */
	public class DragManager : GLib.Object
	{
		public DockController controller { private get; construct; }
		
		public bool InternalDragActive { get; private set; default = false; }

		public bool RemovalActive { get; private set; default = false; }

		public string PendingRemovalLauncher { get; private set; default = ""; }

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
					drop_was_directly_on_item = false;
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
		uint spring_hover_timer_id = 0U;
		weak DockItem? spring_hover_target = null;
		
		Gee.ArrayList<string>? drag_data = null;
		
		int window_scale_factor = 1;
		ulong drag_item_redraw_handler_id = 0UL;
		// CRITICAL MEMORY SAFETY GUARD (DO NOT CHANGE TO WEAK):
		// Use strong references here with explicit null resets in drag_end ().
		// Using 'weak' references causes dangling pointer / use-after-free crashes if items
		// or windows are modified/destroyed while dragging.
		Gdk.DragContext? active_drag_context = null;
		DockItem? drop_target_item = null;
		bool drop_was_directly_on_item = false;
		bool last_hovered_trash = false;
		bool hovered_item_handler_connected = false;

		int drag_origin_icon_size = 48;
		uint64 next_removal_tx_id = 0ULL;
		uint64 active_removal_tx_id = 0ULL;
		DockItem? pending_removal_item = null;
		DockContainer? pending_removal_container = null;
		bool pending_was_pinned = false;
		bool pending_still_running = false;
		string pending_launcher_uri = "";
		ulong poof_completed_handler_id = 0UL;
		ulong shrink_completed_handler_id = 0UL;

		void connect_hovered_item_handler ()
		{
			if (!hovered_item_handler_connected && controller != null && controller.window != null) {
				controller.window.notify["HoveredItem"].connect (hovered_item_changed);
				hovered_item_handler_connected = true;
			}
		}

		void disconnect_hovered_item_handler ()
		{
			if (hovered_item_handler_connected && controller != null && controller.window != null) {
				controller.window.notify["HoveredItem"].disconnect (hovered_item_changed);
				hovered_item_handler_connected = false;
			}
		}
		
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
			if (controller.renderer != null)
				shrink_completed_handler_id = controller.renderer.removal_shrink_completed.connect (on_removal_shrink_completed);
			
			enable_drag_to (window);
			if (!prefs.LockItems)
				enable_drag_from (window);
		}
		
		~DragManager ()
		{
			flush_active_removal ();
			if (poof_completed_handler_id > 0UL) {
				SignalHandler.disconnect (PoofWindow.get_default (), poof_completed_handler_id);
				poof_completed_handler_id = 0UL;
			}
			if (shrink_completed_handler_id > 0UL && controller != null && controller.renderer != null) {
				SignalHandler.disconnect (controller.renderer, shrink_completed_handler_id);
				shrink_completed_handler_id = 0UL;
			}
			cancel_spring_loaded_timer ();
			disconnect_hovered_item_handler ();
			if (controller != null) {
				controller.prefs.notify["LockItems"].disconnect (lock_items_changed);
				
				if (controller.window != null) {
					unowned DockWindow window = controller.window;
					window.drag_motion.disconnect (drag_motion);
					window.drag_begin.disconnect (drag_begin);
					window.drag_data_received.disconnect (drag_data_received);
					window.drag_data_get.disconnect (drag_data_get);
					window.drag_drop.disconnect (drag_drop);
					window.drag_end.disconnect (drag_end);
					window.drag_leave.disconnect (drag_leave);
					window.drag_failed.disconnect (drag_failed);
					
					disable_drag_to (window);
					disable_drag_from (window);
				}
			}
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
			if (drag_data != null)
				return item.can_accept_drop (drag_data);

			// During drag motion (drag_data is null until drop),
			// determine acceptance based on item capability so valid drop targets are not dimmed
			if (item is TrashDockItem || item is FileDockItem)
				return true;

			if (item is ApplicationDockItem) {
				var app_item = (ApplicationDockItem) item;
				return app_item.can_accept_any_drop ();
			}

			return false;
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
			flush_active_removal ();

			unowned DockWindow window = controller.window;
			window.cancel_long_press ();
			
			DragItem = window.HoveredItem;
			
			if (RepositionMode || DragItem is SeparatorDockItem || DragItem is TrashDockItem || DragItem is PlankDockItem || DragItem is PreferencesDockItem || (DragItem.Prefs != null && DragItem.Prefs.Launcher == "docklet://preferences"))
				DragItem = null;
			
			if (DragItem == null) {
				Gdk.drag_abort (context, Gtk.get_current_event_time ());
				return;
			}
			
			connect_hovered_item_handler ();
			
			InternalDragActive = true;
			drag_canceled = false;
			dropped_on_target = false;
			left_dock_during_drag = false;
			is_outside_dock = false;
			last_hovered_trash = false;
			
			if (controller.prefs.CategorizeItems && controller.prefs.AccordionDocklets && controller.app_provider != null) {
				controller.app_provider.cancel_collapse_timer ();
				if (DefaultApplicationDockItemProvider.is_docklet_element (DragItem)) {
					controller.app_provider.expand_docklets ();
				}
			}

			drag_origin_icon_size = controller.position_manager.IconSize;
			
			active_drag_context = context;
			set_drag_icon (context, DragItem, 0.8);
			drag_item_redraw_handler_id = DragItem.needs_redraw.connect (() => {
				set_drag_icon (context, DragItem, 0.8);
			});
			
			context.get_device ().get_seat ().grab (window.get_window (), Gdk.SeatCapabilities.POINTER, true,
				null, null, null);
		}

		public static string? resolve_drop_uri (string raw_str)
		{
			string cleaned = raw_str.strip ();
			if (cleaned.length == 0 || cleaned.has_prefix ("#"))
				return null;

			if (cleaned.has_prefix ("application://") || cleaned.has_prefix ("applications://") || cleaned.has_prefix ("applications:")) {
				string desktop_id = cleaned;
				if (desktop_id.has_prefix ("applications://"))
					desktop_id = desktop_id.replace ("applications://", "");
				else if (desktop_id.has_prefix ("application://"))
					desktop_id = desktop_id.replace ("application://", "");
				else if (desktop_id.has_prefix ("applications:"))
					desktop_id = desktop_id.replace ("applications:", "");
				desktop_id = desktop_id.strip ();
				while (desktop_id.has_suffix ("/"))
					desktop_id = desktop_id.slice (0, desktop_id.length - 1);

				var app_info = new DesktopAppInfo (desktop_id);
				if (app_info == null && !desktop_id.has_suffix (".desktop"))
					app_info = new DesktopAppInfo (desktop_id + ".desktop");
				if (app_info != null && app_info.get_filename () != null)
					return File.new_for_path (app_info.get_filename ()).get_uri ();
				return cleaned;
			}

			if (cleaned.has_prefix ("file://") || cleaned.has_prefix ("http://") || cleaned.has_prefix ("https://") || cleaned.has_prefix ("ftp://"))
				return cleaned;

			if (cleaned.has_prefix ("www."))
				return "https://" + cleaned;

			if (cleaned.has_prefix ("/"))
				return File.new_for_path (cleaned).get_uri ();

			var f = File.new_for_commandline_arg (cleaned);
			if (f.query_exists ())
				return f.get_uri ();

			var app_info = new DesktopAppInfo (cleaned);
			if (app_info == null && !cleaned.has_suffix (".desktop"))
				app_info = new DesktopAppInfo (cleaned + ".desktop");
			if (app_info != null && app_info.get_filename () != null)
				return File.new_for_path (app_info.get_filename ()).get_uri ();

			return null;
		}

		public static bool is_desktop_launcher_uri (string uri)
		{
			string u = uri.strip ();

			if (u.has_suffix (".desktop")
				|| u.has_prefix ("application://")
				|| u.has_prefix ("applications://")
				|| u.has_prefix ("applications:")
				|| u.has_prefix ("appstream://"))
				return true;

			if (u.has_prefix ("file://") || u.has_prefix ("/")) {
				try {
					var f = File.new_for_uri (u.has_prefix ("/") ? File.new_for_path (u).get_uri () : u);
					var info = f.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
					var ct = info.get_content_type ();
					if (ct != null && (ct == "application/x-desktop" || ct.contains ("desktop")))
						return true;
				} catch {}
			}
			return false;
		}

		public static bool is_directory_uri (string uri)
		{
			string u = uri.strip ();
			if (u == "" || u.has_prefix ("http://") || u.has_prefix ("https://") || u.has_prefix ("ftp://"))
				return false;
			if (is_desktop_launcher_uri (u))
				return false;
			if (u.has_prefix ("file://") || u.has_prefix ("/")) {
				var f = u.has_prefix ("/") ? File.new_for_path (u) : File.new_for_uri (u);
				return f.query_exists () && f.query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY;
			}
			return false;
		}

		[CCode (instance_pos = -1)]
		void drag_data_received (Gtk.Widget w, Gdk.DragContext context, int x, int y, Gtk.SelectionData selection_data, uint info, uint time_)
		{
			if (drag_data_requested) {
				drag_data = new Gee.ArrayList<string> ();
				
				string[]? raw_uris = selection_data.get_uris ();
				if (raw_uris != null && raw_uris.length > 0) {
					foreach (unowned string s in raw_uris) {
						var resolved = resolve_drop_uri (s);
						if (resolved != null && !drag_data.contains (resolved))
							drag_data.add (resolved);
					}
				}
				
				if (drag_data.size == 0) {
					string? raw_text = selection_data.get_text ();
					if (raw_text == null || raw_text.length == 0) {
						unowned uint8[]? raw_bytes = selection_data.get_data ();
						int raw_len = selection_data.get_length ();
						if (raw_bytes != null && raw_len > 0) {
							if (raw_len >= 2 && raw_bytes[1] == 0 && raw_bytes[0] != 0) {
								try {
									raw_text = GLib.convert ((string) raw_bytes, raw_len, "UTF-8", "UTF-16LE");
								} catch {}
							}
							if (raw_text == null || raw_text.length == 0) {
								raw_text = (string?) raw_bytes;
							}
						}
					}
					
					if (raw_text != null && raw_text.length > 0) {
						var lines = raw_text.split ("\n");
						foreach (unowned string line in lines) {
							var resolved = resolve_drop_uri (line);
							if (resolved != null && !drag_data.contains (resolved))
								drag_data.add (resolved);
						}
					}
				}
				
				drag_data_requested = false;
				
				if (drag_data.size == 0) {
					if (dropped_on_target) {
						Gtk.drag_finish (context, false, false, time_);
						dropped_on_target = false;
						drop_target_item = null;
						drop_was_directly_on_item = false;
					} else {
						Gdk.drag_status (context, Gdk.DragAction.COPY, time_);
					}
					return;
				}
				
				bool all_launchers = (drag_data.size > 0);
				bool all_directories = (drag_data.size > 0);
				foreach (var u in drag_data) {
					if (!is_desktop_launcher_uri (u))
						all_launchers = false;
					if (!is_directory_uri (u))
						all_directories = false;
				}
				DragNeedsCheck = !(all_launchers || all_directories);
				
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
			if (drag_data == null || drag_data.size == 0) {
				Gtk.drag_finish (context, false, false, time_);
				drop_target_item = null;
				drop_was_directly_on_item = false;
				return;
			}

			flush_active_removal ();
			
			unowned DockWindow window = controller.window;
			unowned DockItem? item = drop_target_item;
			if (item == null && drop_was_directly_on_item)
				item = window.HoveredItem;
			drop_target_item = null;
			
			unowned DockItemProvider? provider = window.HoveredItemProvider;
			if (provider == null && item != null)
				provider = item.Container as DockItemProvider;
			if (provider == null)
				provider = controller.default_provider;

			bool all_desktop = (drag_data.size > 0);
			bool all_directories = (drag_data.size > 0);
			bool contains_directory = false;
			foreach (string uri in drag_data) {
				string u = uri.strip ();
				if (!is_desktop_launcher_uri (u))
					all_desktop = false;

				if (is_directory_uri (u)) {
					contains_directory = true;
				} else {
					all_directories = false;
				}
			}
			
			bool handled = false;

			// Direct drop onto Trash: Trash always takes precedence
			if (item is TrashDockItem && item.can_accept_drop (drag_data)) {
				handled = item.accept_drop (drag_data);
			}
			// PRIORITY 1a (FAT 11.6): Direct drop of folder(s) onto an application icon that explicitly accepts directories (e.g. Dolphin, Kate, VS Code)
			else if (all_directories && drop_was_directly_on_item && item is ApplicationDockItem && ((ApplicationDockItem) item).can_accept_directory () && item.can_accept_drop (drag_data)) {
				handled = item.accept_drop (drag_data);
			}
			// PRIORITY 1b: Direct drop of non-directory payloads (.desktop or files) onto an existing Folder (FileDockItem)
			else if (!all_directories && drop_was_directly_on_item && item is FileDockItem && item.can_accept_drop (drag_data)) {
				handled = item.accept_drop (drag_data);
			}
			// PRIORITY 2: When payload consists of .desktop launchers or folders, PINNING HAS PRIORITY
			else if (all_desktop || all_directories) {
				unowned DefaultApplicationDockItemProvider? app_prov = controller.default_provider as DefaultApplicationDockItemProvider;
				if (!controller.prefs.LockItems && app_prov != null) {
					// Use hovered item as insertion anchor if it belongs to this provider and is not Trash
					unowned DockItem? target_anchor = null;
					if (item != null && item.Container == app_prov && !(item is TrashDockItem))
						target_anchor = item;
					else
						target_anchor = controller.position_manager.get_nearest_item_at (controller.renderer.local_cursor.x, controller.renderer.local_cursor.y, app_prov);
					if (target_anchor == null)
						target_anchor = controller.position_manager.get_current_target_item (app_prov);

					// Never anchor directly onto a SeparatorDockItem because separators are regenerated dynamically
					if (target_anchor is SeparatorDockItem) {
						int sep_idx = app_prov.Elements.index_of (target_anchor);
						target_anchor = null;
						if (sep_idx >= 0) {
							for (int i = sep_idx + 1; i < app_prov.Elements.size; i++) {
								var el = app_prov.Elements.get (i) as DockItem;
								if (el != null && !(el is SeparatorDockItem)) {
									target_anchor = el;
									break;
								}
							}
						}
					}

					// In Categorized Mode: ensure folders attach into [Folders] and app launchers attach outside [Docklets]
					if (controller.prefs.CategorizeItems) {
						if (all_directories) {
							if (!(target_anchor is FileDockItem)) {
								int last_folder_idx = -1;
								for (int i = 0; i < app_prov.Elements.size; i++) {
									if (app_prov.Elements.get (i) is FileDockItem)
										last_folder_idx = i;
								}
								target_anchor = null;
								if (last_folder_idx >= 0) {
									for (int i = last_folder_idx + 1; i < app_prov.Elements.size; i++) {
										var el = app_prov.Elements.get (i) as DockItem;
										if (el != null && !(el is SeparatorDockItem)) {
											target_anchor = el;
											break;
										}
									}
								} else {
									for (int i = 0; i < app_prov.Elements.size; i++) {
										var el = app_prov.Elements.get (i) as DockItem;
										if (el == null || el is SeparatorDockItem || el is PreferencesDockItem || (el.Prefs != null && el.Prefs.Launcher == "docklet://preferences"))
											continue;
										target_anchor = el;
										break;
									}
								}
							}
						} else {
							bool in_docklets = false;
							if (target_anchor != null && DefaultApplicationDockItemProvider.is_docklet_element (target_anchor))
								in_docklets = true;
							else if (window.is_hovering_docklets (controller.renderer.local_cursor.x, controller.renderer.local_cursor.y))
								in_docklets = true;

							if (in_docklets) {
								// Application launchers cannot live inside the docklets section.
								// Natural anchor: the start of Pinned Apps (before first pinned app, or before transients/trash).
								unowned DockItem? first_pinned = null;
								foreach (var el in app_prov.Elements) {
									if (el is ApplicationDockItem && !(el is TransientDockItem) && !DefaultApplicationDockItemProvider.is_docklet_element (el)) {
										first_pinned = el as DockItem;
										break;
									}
								}
								if (first_pinned != null) {
									target_anchor = first_pinned;
								} else {
									unowned DockItem? fallback = null;
									foreach (var el in app_prov.Elements) {
										if (el is TransientDockItem || el is TrashDockItem) {
											fallback = el as DockItem;
											break;
										}
									}
									target_anchor = fallback;
								}
							}
						}
					}

					foreach (var uri in drag_data) {
						if (!app_prov.item_exists_for_uri (uri)) {
							if (app_prov.add_item_with_uri (uri, target_anchor))
								handled = true;
						} else {
							// Reposition already pinned item
							unowned DockItem? existing_item = app_prov.item_for_uri (uri);
							if (existing_item != null && target_anchor != null && existing_item != target_anchor) {
								app_prov.move_to (existing_item, target_anchor);
							}
							handled = true;
						}
					}
					if (handled && all_directories)
						ApplicationDiscovery.get_default ().refresh_index_now ();
				}
			}
			// PRIORITY 3: Direct drop onto Web Browser for Web Links / URLs
			else if (drop_was_directly_on_item && item is ApplicationDockItem && ((ApplicationDockItem) item).is_web_browser () && item.can_accept_drop (drag_data)) {
				handled = item.accept_drop (drag_data);
			}
			// PRIORITY 4: Non-desktop payloads dropped directly onto specific dock items (App)
			else if (drop_was_directly_on_item && item != null && item.can_accept_drop (drag_data)) {
				if (item is ApplicationDockItem && (!contains_directory || ((ApplicationDockItem) item).can_accept_directory ())) {
					handled = item.accept_drop (drag_data);
				}
			}
			// PRIORITY 5: Non-desktop regular files dropped on empty dock space (strictly rejecting incompatible drops on an icon per FAT 11.6)
			if (!handled && !drop_was_directly_on_item && !controller.prefs.LockItems && provider != null && provider.can_accept_drop (drag_data)) {
				handled = provider.accept_drop (drag_data);
			}

			// PRIORITY 6: Web URLs dropped on dock background -> open in default browser
			if (!handled) {
				foreach (string uri in drag_data) {
					string u = uri.strip ();
					string? target_url = null;
					if (u.has_prefix ("http://") || u.has_prefix ("https://") || u.has_prefix ("ftp://"))
						target_url = u;
					else if (!all_desktop && !all_directories)
						target_url = System.extract_link_shortcut_url (u);

					if (target_url != null) {
						try {
							AppInfo.launch_default_for_uri (target_url, null);
							handled = true;
						} catch (Error e) {
							warning ("Failed to open URL in default browser: %s", e.message);
						}
					}
				}
			}
			
			if (handled) {
				unowned DefaultApplicationDockItemProvider? def_prov = controller.default_provider as DefaultApplicationDockItemProvider;
				if (def_prov != null) {
					def_prov.refresh_separators ();
				}
				if (controller.renderer != null && controller.renderer.theme != null) {
					controller.position_manager.update (controller.renderer.theme);
				}
				controller.schedule_serialize_item_positions ();
				if (controller.renderer != null) {
					controller.renderer.reset_buffers ();
					controller.renderer.animated_draw ();
				}
				window.update_icon_regions ();
				window.set_input_mask ();
			}

			Gtk.drag_finish (context, handled, false, time_);
			ExternalDragActive = false;
			drag_data = null;
			dropped_on_target = false;
			drop_was_directly_on_item = false;
			controller.check_collapse_after_interaction ();
			if (controller.renderer != null)
				controller.renderer.animated_draw ();
		}

		[CCode (instance_pos = -1)]
		bool drag_drop (Gtk.Widget w, Gdk.DragContext context, int x, int y, uint time_)
		{
			dropped_on_target = true;
			if (controller.renderer != null)
				controller.renderer.update_local_cursor (x, y);
			controller.hide_manager.update_hovered_with_coords (x, y);
			controller.window.update_hovered (x, y);
			drop_target_item = controller.window.HoveredItem;
			cancel_spring_loaded_timer ();
			
			if (drop_target_item == null) {
				unowned PositionManager pos_mgr = controller.position_manager;
				foreach (var el in controller.default_provider.VisibleElements) {
					var item = el as DockItem;
					if (item != null && !(item is SeparatorDockItem)) {
						var r = pos_mgr.get_hover_region_for_element (item);
						bool matches = false;
						if (pos_mgr.is_horizontal_dock ())
							matches = (x >= r.x && x < r.x + r.width && y >= 0 && y < pos_mgr.DockHeight);
						else
							matches = (y >= r.y && y < r.y + r.height && x >= 0 && x < pos_mgr.DockWidth);
						if (matches) {
							drop_target_item = item;
							if (item is TrashDockItem)
								last_hovered_trash = true;
							break;
						}
					}
				}
			}

			drop_was_directly_on_item = (drop_target_item != null && !(drop_target_item is SeparatorDockItem));

			if (drop_target_item == null) {
				unowned PositionManager pos_mgr = controller.position_manager;
				var nearest = pos_mgr.get_nearest_item_at (x, y);
				if (nearest != null && nearest is TrashDockItem) {
					var r = pos_mgr.get_hover_region_for_element (nearest);
					bool matches = false;
					if (pos_mgr.is_horizontal_dock ())
						matches = (x >= r.x - 16 && x <= r.x + r.width + 16 && y >= 0 && y < pos_mgr.DockHeight);
					else
						matches = (y >= r.y - 16 && y <= r.y + r.height + 16 && x >= 0 && x < pos_mgr.DockWidth);
					if (matches) {
						drop_target_item = nearest;
						drop_was_directly_on_item = true;
						last_hovered_trash = true;
					}
				}
			}
			if (controller.window.HoveredItem is TrashDockItem || drop_target_item is TrashDockItem)
				last_hovered_trash = true;
			
			if (drag_hover_timer_id > 0U) {
				GLib.Source.remove (drag_hover_timer_id);
				drag_hover_timer_id = 0U;
			}
			
			if (ExternalDragActive || !InternalDragActive) {
				ExternalDragActive = true;
				drag_data = null;
				drag_data_requested = true;
				Gdk.Atom target_atom = Gtk.drag_dest_find_target (controller.window, context, null);
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
			cancel_spring_loaded_timer ();
			unowned HideManager hide_manager = controller.hide_manager;
			
			if (drag_item_redraw_handler_id > 0UL) {
				if (DragItem != null)
					GLib.SignalHandler.disconnect (DragItem, drag_item_redraw_handler_id);
				drag_item_redraw_handler_id = 0UL;
			}
			
			if (!drag_canceled && DragItem != null) {
				hide_manager.update_hovered ();
				
				bool dropped_on_trash = (drop_target_item is TrashDockItem || controller.window.HoveredItem is TrashDockItem || last_hovered_trash);
				if (!dropped_on_target || dropped_on_trash) {
					if (DragItem.can_be_removed ()) {
						var target_item = DragItem;
						DragItem = null;
						InternalDragActive = false;
						remove_item_with_effect (target_item, true, drag_origin_icon_size);
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
				if (DragItem != null && dropped_on_target && !dropped_on_trash && !controller.prefs.LockItems) {
					unowned DefaultApplicationDockItemProvider? provider = (DragItem.Container as DefaultApplicationDockItemProvider);
					if (provider != null) {
						unowned Gee.ArrayList<DockElement> elements = provider.Elements;
						int drag_index = elements.index_of (DragItem);
						if (drag_index >= 0) {
							int divider_idx = -1;
							int trash_idx = -1;
							for (int i = 0; i < elements.size; i++) {
								if (elements.get (i) is TrashDockItem) {
									trash_idx = i;
									break;
								}
							}

							int sep_pref_idx = -1;
							if (elements.size > 1 && elements.get (1) is SeparatorDockItem) {
								var first_el = elements.get (0);
								if (first_el is PreferencesDockItem || (first_el is DockItem && ((DockItem) first_el).Prefs != null && ((DockItem) first_el).Prefs.Launcher == "docklet://preferences")) {
									sep_pref_idx = 1;
								}
							}

							int sep_trash_idx = -1;
							if (trash_idx > 0 && elements.get (trash_idx - 1) is SeparatorDockItem) {
								sep_trash_idx = trash_idx - 1;
							}

							// Find the separator dividing pinned and transient items
							for (int i = 0; i < elements.size; i++) {
								if (elements.get (i) is SeparatorDockItem && i != sep_trash_idx && i != sep_pref_idx) {
									bool is_before_apps = false;
									bool is_after_apps = false;
									if (controller.prefs.CategorizeItems) {
										if (i > 0) {
											var prev_el = elements.get (i - 1);
											if (prev_el is FileDockItem || prev_el is PlankDockItem ||
											    (prev_el is DockItem && ((DockItem) prev_el).Prefs != null && ((DockItem) prev_el).Prefs.Launcher != null && ((DockItem) prev_el).Prefs.Launcher.has_prefix ("docklet://"))) {
												is_before_apps = true;
											}
										}
										if (i + 1 < elements.size) {
											var next_el = elements.get (i + 1);
											if (DefaultApplicationDockItemProvider.is_docklet_element (next_el) || next_el is TrashDockItem) {
												is_after_apps = true;
											}
										}
									}
									if (!is_before_apps && !is_after_apps) {
										divider_idx = i;
										break;
									}
								}
							}

							if (divider_idx >= 0) {
								if (DragItem is TransientDockItem && drag_index < divider_idx) {
									provider.pin_item (DragItem);
								} else if (!(DragItem is TransientDockItem) && DragItem is ApplicationDockItem && !(DragItem is FileDockItem) && drag_index > divider_idx) {
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
			drop_target_item = null;
			dropped_on_target = false;
			left_dock_during_drag = false;
			last_hovered_trash = false;
			context.get_device ().get_seat ().ungrab ();

			if (!RemovalActive) {
				unowned DefaultApplicationDockItemProvider? default_app_provider = controller.default_provider as DefaultApplicationDockItemProvider;
				if (default_app_provider != null) {
					default_app_provider.refresh_separators ();
				}
				controller.check_collapse_after_interaction ();
				controller.schedule_serialize_item_positions ();
			}
			
			disconnect_hovered_item_handler ();
			controller.hover.hide ();
			controller.renderer.animated_draw ();
			hide_manager.update_hovered ();
		}

		/**
		 * Executes dock item unpin/removal through the deterministic 3-beat VSync
		 * pipeline (slot hold -> PoofWindow destruction -> smooth gap shrink) when
		 * an Unpin Effect (0..7) is active, or falls back to the classic downward
		 * dock slide-out animation when Unpin Effect is None (8).
		 */
		public void remove_item_with_effect (DockItem item, bool from_drag = false, int origin_icon_size = 0)
		{
			flush_active_removal ();

			unowned ApplicationDockItem? app_item = (item as ApplicationDockItem);
			var was_pinned = !(item is TransientDockItem);
			var still_running = (app_item != null && WindowManager.get_default ().window_count_for_app (item.Launcher) > 0);
			var launcher_uri = (item.Launcher != null) ? item.Launcher : "";
			unowned DockContainer? item_container = item.Container;

			int eff_mode = controller.prefs.UnpinAnimation.clamp (0, 8);
			int eff_duration_ms = controller.prefs.EffectDuration.clamp (300, 1500);

			// When Unpin Effect is None (8) on non-drag removal (e.g. Keep in Dock uncheck),
			// preserve the classic downward slide-out animation (leave hidden_removal_item null).
			if (eff_mode == 8 && !from_drag) {
				controller.hover.hide ();
				if (item_container != null && item_container.Elements.contains (item))
					item_container.remove (item);
				item.delete ();
				if (was_pinned && still_running && item_container != null && launcher_uri.length > 0)
					spawn_transient_if_still_running (item_container, launcher_uri);
				commit_post_removal_cleanup ();
				return;
			}

			pending_removal_item = item;
			pending_removal_container = item_container;
			pending_was_pinned = was_pinned;
			pending_still_running = still_running;
			pending_launcher_uri = launcher_uri;
			PendingRemovalLauncher = pending_launcher_uri;
			active_removal_tx_id = ++next_removal_tx_id;
			RemovalActive = true;

			controller.hover.hide ();

			// Beat 1 (DESTROYING): hold the slot open & hide the icon immediately (no downward slide)
			controller.renderer.hold_removal_slot (pending_removal_item);

			int anchor_along = 0;
			int anchor_perp = 0;
			controller.position_manager.get_item_canonical_anchor (pending_removal_item, out anchor_along, out anchor_perp);

			var monitor = PositionManager.get_monitor_for_plug_name (controller.window.get_display (), controller.prefs.Monitor);
			var dock_pos = controller.position_manager.Position;
			bool reserve_active = controller.prefs.ReserveSpace && controller.prefs.HideMode == HideType.NONE && !controller.prefs.ZoomEnabled;
			int excl_thickness = reserve_active ? controller.position_manager.get_visual_thickness () : 0;

			int base_size = (origin_icon_size > 0) ? origin_icon_size : controller.position_manager.IconSize;
			int snap_logical = int.max (24, base_size);
			Color snap_accent = pending_removal_item.AverageIconColor;
			Cairo.Surface? icon_snap = null;

			if (eff_mode >= 1 && eff_mode <= 7) {
				int scale = (controller.window.get_window () != null) ? controller.window.get_window ().get_scale_factor () : 1;
				int snap_px = snap_logical * scale;
				var snap_surface = new Surface (snap_px, snap_px);
				snap_surface.Internal.set_device_scale (scale, scale);
				var item_surface = pending_removal_item.get_surface_copy (snap_px, snap_px, snap_surface);
				unowned Cairo.Context snap_cr = snap_surface.Context;
				if (scale > 1) {
					snap_cr.save ();
					snap_cr.scale (1.0 / scale, 1.0 / scale);
				}
				snap_cr.set_operator (Cairo.Operator.OVER);
				snap_cr.set_source_surface (item_surface.Internal, 0, 0);
				snap_cr.paint ();
				if (scale > 1)
					snap_cr.restore ();
				icon_snap = snap_surface.Internal;
			}

			if (poof_completed_handler_id == 0UL)
				poof_completed_handler_id = PoofWindow.get_default ().poof_completed.connect (on_poof_completed);

			PoofWindow.get_default ().show_for_icon_anchor (
				active_removal_tx_id, anchor_along, anchor_perp, snap_logical,
				dock_pos, reserve_active, excl_thickness, monitor,
				eff_mode, icon_snap, snap_accent, eff_duration_ms
			);
		}

		void on_poof_completed (uint64 tx_id)
		{
			if (!RemovalActive || tx_id == 0ULL || tx_id != active_removal_tx_id)
				return;

			// Beat 2 (SHRINKING_GAP): remove item from DockContainer while keeping its
			// visual surface hidden in DockRenderer so EASE_IN_QUINT closes the gap smoothly
			var item = pending_removal_item;
			var container = pending_removal_container;
			if (item != null && container != null && container.Elements.contains (item)) {
				container.remove (item);
			}

			if (item != null && controller.VisibleItems.size > 0 && controller.renderer.watch_removal_shrink (item, tx_id)) {
				return;
			}

			on_removal_shrink_completed (tx_id);
		}

		void on_removal_shrink_completed (uint64 tx_id)
		{
			if (!RemovalActive || tx_id == 0ULL || tx_id != active_removal_tx_id)
				return;

			// Beat 3 (FINALIZE): commit deletion, spawn TransientDockItem if still running,
			// refresh separators, update regions & input mask, and release HideManager hold
			active_removal_tx_id = 0ULL;
			controller.renderer.clear_removal_hold ();

			var item = pending_removal_item;
			var container = pending_removal_container;
			var was_pinned = pending_was_pinned;
			var still_running = pending_still_running;
			var launcher_uri = pending_launcher_uri;

			pending_removal_item = null;
			pending_removal_container = null;
			pending_was_pinned = false;
			pending_still_running = false;
			pending_launcher_uri = "";
			PendingRemovalLauncher = "";
			RemovalActive = false;

			if (item != null) {
				if (container != null && container.Elements.contains (item)) {
					item.IsVisible = false;
					container.remove (item);
				}
				item.delete ();

				if (was_pinned && still_running && container != null && launcher_uri.length > 0) {
					spawn_transient_if_still_running (container, launcher_uri);
				}
			}

			commit_post_removal_cleanup ();
		}

		void flush_active_removal ()
		{
			if (!RemovalActive && pending_removal_item == null)
				return;

			active_removal_tx_id = 0ULL;
			if (poof_completed_handler_id > 0UL)
				PoofWindow.get_default ().cancel_active ();
			if (controller != null && controller.renderer != null)
				controller.renderer.clear_removal_hold ();

			var item = pending_removal_item;
			var container = pending_removal_container;
			var was_pinned = pending_was_pinned;
			var still_running = pending_still_running;
			var launcher_uri = pending_launcher_uri;

			pending_removal_item = null;
			pending_removal_container = null;
			pending_was_pinned = false;
			pending_still_running = false;
			pending_launcher_uri = "";
			PendingRemovalLauncher = "";
			RemovalActive = false;

			if (item != null) {
				if (container != null && container.Elements.contains (item)) {
					item.IsVisible = false;
					container.remove (item);
				}
				item.delete ();

				if (was_pinned && still_running && container != null && launcher_uri.length > 0) {
					spawn_transient_if_still_running (container, launcher_uri);
				}
			}

			commit_post_removal_cleanup ();
		}

		void spawn_transient_if_still_running (DockContainer container, string launcher_uri)
		{
			unowned ApplicationDockItemProvider? app_prov = container as ApplicationDockItemProvider;
			if (app_prov != null) {
				app_prov.sync_compositor_windows ();
			}

			bool exists = false;
			var windows = WindowManager.get_default ().matching_windows (launcher_uri);
			var discovery = ApplicationDiscovery.get_default ();
			foreach (var el in container.Elements) {
				unowned ApplicationDockItem? existing = el as ApplicationDockItem;
				if (existing == null)
					continue;
				if (existing.Launcher == launcher_uri) {
					exists = true;
					break;
				}
				foreach (var w in windows) {
					if (discovery.is_best_launcher_for_window (existing.Launcher, w)) {
						exists = true;
						break;
					}
				}
				if (exists)
					break;
			}

			if (!exists && WindowManager.get_default ().window_count_for_app (launcher_uri) > 0) {
				DockElement? trash_target = null;
				foreach (var el in container.Elements) {
					if (el is TrashDockItem) {
						trash_target = el;
						break;
					}
				}
				container.add (new TransientDockItem.with_launcher (launcher_uri), trash_target);
			}
		}

		void commit_post_removal_cleanup ()
		{
			if (controller == null)
				return;

			unowned DefaultApplicationDockItemProvider? default_app_provider = controller.default_provider as DefaultApplicationDockItemProvider;
			if (default_app_provider != null) {
				default_app_provider.refresh_separators ();
			}
			controller.check_collapse_after_interaction ();
			controller.schedule_serialize_item_positions ();

			if (controller.window != null) {
				controller.window.update_icon_regions ();
				controller.window.set_input_mask ();
			}
			if (controller.renderer != null) {
				controller.renderer.animated_draw ();
			}
			if (controller.hide_manager != null) {
				controller.hide_manager.update_hovered ();
			}
		}

		[CCode (instance_pos = -1)]
		void drag_leave (Gtk.Widget w, Gdk.DragContext context, uint time_)
		{
			cancel_spring_loaded_timer ();
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
				disconnect_hovered_item_handler ();
				
				Gdk.threads_add_idle (() => {
					if (dropped_on_target)
						return false;
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
				else if ((actions & Gdk.DragAction.LINK) != 0)
					action = Gdk.DragAction.LINK;
				else if ((actions & Gdk.DragAction.MOVE) != 0)
					action = Gdk.DragAction.MOVE;
				else if ((actions & Gdk.DragAction.ASK) != 0)
					action = Gdk.DragAction.ASK;
				else
					action = Gdk.DragAction.COPY;
			}
			if (action == 0)
				action = Gdk.DragAction.COPY;
			Gdk.drag_status (context, action, time_);

			if (marker != direct_hash (context)) {
				marker = direct_hash (context);
				drag_known = false;
			}
			
			unowned DockWindow window = controller.window;
			unowned HideManager hide_manager = controller.hide_manager;
			
			if (ExternalDragActive && !drag_known) {
				drag_known = true;
				connect_hovered_item_handler ();
			}
			
			if (ExternalDragActive) {
				controller.hover.hide ();
			}
			
			controller.renderer.update_local_cursor (x, y);
			hide_manager.update_hovered_with_coords (x, y);
			window.update_hovered (x, y);
			
			if (ExternalDragActive && window.HoveredItem != null && spring_hover_timer_id == 0U && spring_hover_target != window.HoveredItem) {
				start_spring_loaded_timer (window.HoveredItem);
			}
			
			if (controller.prefs.CategorizeItems && controller.prefs.AccordionDocklets && controller.app_provider != null) {
				if (controller.app_provider.docklets_expanded) {
					controller.app_provider.cancel_collapse_timer ();
				} else if (window.is_hovering_docklets (x, y)) {
					controller.app_provider.expand_docklets ();
				}
			}
			
			bool over_trash = (window.HoveredItem is TrashDockItem);
			if (!over_trash) {
				unowned PositionManager pos_mgr = controller.position_manager;
				foreach (var el in controller.default_provider.Elements) {
					if (el is TrashDockItem) {
						var r = pos_mgr.get_hover_region_for_element (el as DockItem);
						bool matches = false;
						if (pos_mgr.is_horizontal_dock ())
							matches = (x >= r.x && x < r.x + r.width && y >= 0 && y < pos_mgr.DockHeight);
						else
							matches = (y >= r.y && y < r.y + r.height && x >= 0 && x < pos_mgr.DockWidth);
						if (matches) {
							over_trash = true;
							break;
						}
					}
				}
			}
			if (over_trash)
				last_hovered_trash = true;
			else if (window.HoveredItem != null)
				last_hovered_trash = false;
			
			is_outside_dock = false;
			left_dock_during_drag = false;
			
			return true;
		}

		enum DragCategory {
			ANCHOR,
			FOLDER,
			DOCKLET,
			APP,
			TRASH,
			SEPARATOR
		}

		DragCategory get_drag_category (DockElement el)
		{
			if (el is PreferencesDockItem || (el is DockItem && ((DockItem) el).Prefs != null && ((DockItem) el).Prefs.Launcher == "docklet://preferences"))
				return DragCategory.ANCHOR;
			if (el is FileDockItem)
				return DragCategory.FOLDER;
			if (el is TrashDockItem)
				return DragCategory.TRASH;
			if (el is SeparatorDockItem)
				return DragCategory.SEPARATOR;
			if (el is PlankDockItem || (el is DockItem && ((DockItem) el).Prefs != null && ((DockItem) el).Prefs.Launcher != null && ((DockItem) el).Prefs.Launcher.has_prefix ("docklet://")))
				return DragCategory.DOCKLET;
			if (el is DockItem)
				return DragCategory.APP;
			return DragCategory.APP;
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

				if (controller.prefs.CategorizeItems) {
					var drag_cat = get_drag_category (DragItem);
					if (drag_cat == DragCategory.TRASH)
						return;

					int first_cat_idx = -1;
					int last_cat_idx = -1;
					for (int i = 0; i < elements.size; i++) {
						if (get_drag_category (elements.get (i)) == drag_cat) {
							if (first_cat_idx < 0)
								first_cat_idx = i;
							last_cat_idx = i;
						}
					}

					if (first_cat_idx < 0 || last_cat_idx < 0)
						return;

					if (drag_cat == DragCategory.APP) {
						// Pinned and unpinned apps cannot move left into Docklets or Folders
						if (hover_idx < first_cat_idx) {
							if (drag_idx != first_cat_idx) {
								var target = elements.get (first_cat_idx);
								if (target != DragItem && get_drag_category (target) == DragCategory.APP)
									DragItem.Container.move_to (DragItem, target);
							}
							return;
						}
						// Pinned and unpinned apps cannot move right into Trash
						if (hover_idx > last_cat_idx) {
							if (drag_idx != last_cat_idx) {
								var target = elements.get (last_cat_idx);
								if (target != DragItem && get_drag_category (target) == DragCategory.APP)
									DragItem.Container.move_to (DragItem, target);
							}
							return;
						}
						// If hovering on the separator between pinned and unpinned apps, cross it
						if (hovered_item is SeparatorDockItem) {
							if (drag_idx < hover_idx && hover_idx + 1 < elements.size) {
								var target = elements.get (hover_idx + 1);
								if (target != DragItem && get_drag_category (target) == DragCategory.APP)
									DragItem.Container.move_to (DragItem, target);
							} else if (drag_idx > hover_idx && hover_idx > 0) {
								var target = elements.get (hover_idx - 1);
								if (target != DragItem && get_drag_category (target) == DragCategory.APP)
									DragItem.Container.move_to (DragItem, target);
							}
							return;
						}
						// Moving among apps (pinned or unpinned)
						if (get_drag_category (hovered_item) == DragCategory.APP)
							DragItem.Container.move_to (DragItem, hovered_item);
						return;
					}

					// For FOLDER or DOCKLET: strictly clamped to their own category range
					if (drag_cat == DragCategory.DOCKLET && hovered_item is PreferencesDockItem)
						return;

					if (hover_idx < first_cat_idx) {
						if (drag_idx != first_cat_idx) {
							var target = elements.get (first_cat_idx);
							if (target != DragItem && get_drag_category (target) == drag_cat)
								DragItem.Container.move_to (DragItem, target);
						}
						return;
					}
					if (hover_idx > last_cat_idx) {
						if (drag_idx != last_cat_idx) {
							var target = elements.get (last_cat_idx);
							if (target != DragItem && get_drag_category (target) == drag_cat)
								DragItem.Container.move_to (DragItem, target);
						}
						return;
					}
					if (hovered_item is SeparatorDockItem)
						return;

					if (get_drag_category (hovered_item) == drag_cat)
						DragItem.Container.move_to (DragItem, hovered_item);
					return;
				}
				
				// Identify Preferences anchor, separators, and Trash markers
				int sep_pref_idx = -1;
				if (elements.size > 1 && elements.get (1) is SeparatorDockItem) {
					var first_el = elements.get (0);
					if (first_el is PreferencesDockItem || (first_el is DockItem && ((DockItem) first_el).Prefs != null && ((DockItem) first_el).Prefs.Launcher == "docklet://preferences")) {
						sep_pref_idx = 1;
					}
				}

				int trash_idx = -1;
				for (int i = 0; i < elements.size; i++) {
					if (elements.get (i) is TrashDockItem) {
						trash_idx = i;
						break;
					}
				}

				int sep_trash_idx = -1;
				if (trash_idx > 0 && elements.get (trash_idx - 1) is SeparatorDockItem) {
					sep_trash_idx = trash_idx - 1;
				}

				int sep_transient_idx = -1;
				for (int i = 0; i < elements.size; i++) {
					if (elements.get (i) is SeparatorDockItem && i != sep_pref_idx && i != sep_trash_idx) {
						sep_transient_idx = i;
						break;
					}
				}

				// Rule 0: No item can ever move to index 0 or before/onto the separator after Preferences.
				if (sep_pref_idx >= 0 && hover_idx <= sep_pref_idx) {
					if (sep_pref_idx + 1 < elements.size && drag_idx != sep_pref_idx + 1) {
						var target = elements.get (sep_pref_idx + 1);
						if (target != DragItem && !(target is SeparatorDockItem) && !(target is TrashDockItem))
							DragItem.Container.move_to (DragItem, target);
					}
					return;
				}

				// Rule 1: No app (pinned or unpinned, running or not) can ever move to or beyond the separator before Trash, or onto Trash.
				int limit_trash_idx = sep_trash_idx >= 0 ? sep_trash_idx : trash_idx;
				if (limit_trash_idx >= 0 && hover_idx >= limit_trash_idx) {
					// Move DragItem to immediately before limit_trash if it isn't already there
					if (limit_trash_idx > 0 && drag_idx != limit_trash_idx - 1) {
						var target = elements.get (limit_trash_idx - 1);
						if (target != DragItem && !(target is SeparatorDockItem) && !(target is TrashDockItem))
							DragItem.Container.move_to (DragItem, target);
					}
					return;
				}

				// Rule 2: Crossing separator between pinned and transient (unpinned) items:
				if (hovered_item is SeparatorDockItem) {
					if (sep_transient_idx >= 0 && hover_idx == sep_transient_idx) {
						if (drag_idx < sep_transient_idx && sep_transient_idx + 1 < elements.size) {
							// Moving right across separator into transient section
							var target = elements.get (sep_transient_idx + 1);
							if (target != DragItem && !(target is SeparatorDockItem) && !(target is TrashDockItem))
								DragItem.Container.move_to (DragItem, target);
						} else if (drag_idx > sep_transient_idx && sep_transient_idx > 0) {
							// Moving left across separator into pinned section
							var target = elements.get (sep_transient_idx - 1);
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

			if (ExternalDragActive) {
				unowned DockItem? target = controller.window.HoveredItem;
				if (target != null) {
					if (target != spring_hover_target)
						start_spring_loaded_timer (target);
				} else {
					cancel_spring_loaded_timer ();
				}
			}
		}

		void start_spring_loaded_timer (DockItem target)
		{
			cancel_spring_loaded_timer ();
			
			spring_hover_target = target;
			spring_hover_timer_id = GLib.Timeout.add (500, () => {
				spring_hover_timer_id = 0U;
				if (ExternalDragActive && spring_hover_target != null && controller.window.HoveredItem == spring_hover_target) {
					handle_spring_loaded_hover (spring_hover_target);
				}
				return GLib.Source.REMOVE;
			});
		}

		void cancel_spring_loaded_timer ()
		{
			if (spring_hover_timer_id > 0U) {
				GLib.Source.remove (spring_hover_timer_id);
				spring_hover_timer_id = 0U;
			}
			spring_hover_target = null;
		}

		void handle_spring_loaded_hover (DockItem item)
		{
			item.trigger_bounce ();

			var launcher = item.Launcher;
			if (launcher != null && launcher != "") {
				var windows = WindowManager.get_default ().matching_windows (launcher);
				if (windows.size > 0) {
					message ("Wayplank: spring-loaded hover on '%s' -> activate window %s", item.Text, windows[0].Id);
					WindowControl.queue_command (windows[0].Id, "activate");
				}
			}
		}

		void enable_drag_to (DockWindow window)
		{
			Gtk.TargetEntry te1 = { "text/uri-list", 0, 0 };
			Gtk.TargetEntry te2 = { "text/plank-uri-list", 0, 0 };
			Gtk.TargetEntry te3 = { "application/x-desktop", 0, 0 };
			Gtk.TargetEntry te4 = { "application/x-gnome-app-info", 0, 0 };
			Gtk.TargetEntry te5 = { "application/x-kde-appmenu", 0, 0 };
			Gtk.TargetEntry te6 = { "text/plain;charset=utf-8", 0, 0 };
			Gtk.TargetEntry te7 = { "UTF8_STRING", 0, 0 };
			Gtk.TargetEntry te8 = { "text/plain", 0, 0 };
			Gtk.TargetEntry te9 = { "STRING", 0, 0 };
			Gtk.TargetEntry te10 = { "text/x-moz-url", 0, 0 };
			Gtk.TargetEntry te11 = { "text/html", 0, 0 };
			Gtk.drag_dest_set (window, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.DROP,
				{te1, te2, te3, te4, te5, te6, te7, te8, te9, te10, te11},
				Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
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

