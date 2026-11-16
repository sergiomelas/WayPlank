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
	public class FolderMenuWindow : Gtk.Window
	{
		const int GAP = 4;
		const int ICON_SIZE = 24;
		const int MAX_HEIGHT = 440;
		const int MIN_WIDTH = 220;
		public const uint DISMISS_DELAY = 450U;

		weak DockController? _controller = null;
		public weak DockController controller {
			get { return _controller; }
			construct { _controller = value; }
		}
		bool is_window_cleaned_up = false;
		public FileDockItem? TargetItem { get; protected set; default = null; }

		File? current_dir = null;
		Gee.ArrayList<File> history = new Gee.ArrayList<File> ();

		Gtk.Box main_box;
		Gtk.Box items_box;
		Gtk.ScrolledWindow scrolled;

		uint dismiss_timer_id = 0U;
		bool pointer_inside = false;
		bool context_menu_active = false;
		string? hovered_app_uri = null;
		int hovered_win_count = 0;
		double smooth_scroll_dx = 0.0;
		double smooth_scroll_dy = 0.0;
		uint32 last_scroll_time = 0U;

		bool has_last_pos = false;
		int last_center_x = -1;
		int last_center_y = -1;
		int last_pos_w = -1;
		int last_pos_h = -1;
		Gtk.PositionType last_pos_edge = Gtk.PositionType.BOTTOM;
		int last_thickness = -1;

		public FolderMenuWindow (DockController controller)
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
			Hal.Shell.init_popup_surface (this, PopupSurfaceKind.FOLDER_MENU);

			unowned Gdk.Screen screen = get_screen ();
			var visual = screen.get_rgba_visual ();
			if (visual != null)
				set_visual (visual);

			get_style_context ().add_class ("wayplank-folder-menu");

			main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
			main_box.margin = 8;
			add (main_box);

			scrolled = new Gtk.ScrolledWindow (null, null);
			scrolled.set_shadow_type (Gtk.ShadowType.NONE);
			scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			scrolled.set_propagate_natural_width (true);
			scrolled.set_propagate_natural_height (true);
			scrolled.set_max_content_height (MAX_HEIGHT);
			scrolled.set_min_content_width (MIN_WIDTH);
			scrolled.add_events (Gdk.EventMask.SCROLL_MASK);
			scrolled.scroll_event.connect ((event) => {
				if (hovered_app_uri != null && hovered_win_count > 0)
					return handle_app_scroll (hovered_app_uri, hovered_win_count, event);
				return false;
			});
			main_box.pack_start (scrolled, true, true, 0);

			items_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
			scrolled.add (items_box);

			apply_theme_style ();

			add_events (
				Gdk.EventMask.ENTER_NOTIFY_MASK |
				Gdk.EventMask.LEAVE_NOTIFY_MASK |
				Gdk.EventMask.POINTER_MOTION_MASK |
				Gdk.EventMask.SCROLL_MASK
			);

			enter_notify_event.connect (on_enter);
			leave_notify_event.connect (on_leave);
			scroll_event.connect ((event) => {
				if (hovered_app_uri != null && hovered_win_count > 0)
					return handle_app_scroll (hovered_app_uri, hovered_win_count, event);
				return false;
			});

			setup_drag_dest ();

			hide.connect (() => {
				has_last_pos = false;
				cancel_dismiss_timer ();
				cancel_position_timer ();
			});
			unmap.connect (() => {
				has_last_pos = false;
			});

			WindowManager.get_default ().windows_refreshed.connect (on_windows_refreshed);
		}

		void cancel_position_timer ()
		{
			Hal.Shell.cancel_popup_sync (this);
		}

		bool folder_drop_pending = false;

		void setup_drag_dest ()
		{
			string[] core_atoms = {
				"text/uri-list",
				"text/plain;charset=utf-8",
				"UTF8_STRING",
				"text/plain"
			};
			string[] extra_atoms = Hal.Apps.get_extra_drop_target_atoms ();
			var entries = new Gtk.TargetEntry[core_atoms.length + extra_atoms.length];
			int idx = 0;
			foreach (unowned string atom in core_atoms)
				entries[idx++] = { atom, 0, 0 };
			foreach (unowned string atom in extra_atoms)
				entries[idx++] = { atom, 0, 0 };

			Gtk.drag_dest_set (this, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.DROP,
				entries,
				Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK);

			drag_motion.connect ((context, x, y, time_) => {
				pointer_inside = true;
				cancel_dismiss_timer ();
				Gdk.drag_status (context, Gdk.DragAction.COPY, time_);
				return true;
			});

			drag_leave.connect ((context, time_) => {
				if (folder_drop_pending)
					return;
				pointer_inside = false;
				if (!context_menu_active)
					schedule_dismiss (DISMISS_DELAY);
			});

			drag_drop.connect ((context, x, y, time_) => {
				if (current_dir == null)
					return false;
				folder_drop_pending = true;
				pointer_inside = true;
				cancel_dismiss_timer ();
				Gdk.Atom target_atom = Gtk.drag_dest_find_target (this, context, null);
				if (target_atom != Gdk.Atom.NONE)
					Gtk.drag_get_data (this, context, target_atom, time_);
				else
					Gtk.drag_get_data (this, context, Gdk.Atom.intern ("text/uri-list", false), time_);
				return true;
			});

			drag_data_received.connect ((context, x, y, selection_data, info, time_) => {
				if (!folder_drop_pending)
					return;
				folder_drop_pending = false;

				var uris = new Gee.ArrayList<string> ();
				foreach (var native_uri in Hal.Apps.decode_native_drop_selection (selection_data)) {
					var resolved = DragManager.resolve_drop_uri (native_uri);
					if (resolved != null && !uris.contains (resolved))
						uris.add (resolved);
				}
				if (uris.size == 0) {
					string[]? raw_uris = selection_data.get_uris ();
					if (raw_uris != null && raw_uris.length > 0) {
						foreach (unowned string s in raw_uris) {
							var resolved = DragManager.resolve_drop_uri (s);
							if (resolved != null && !uris.contains (resolved))
								uris.add (resolved);
						}
					}
				}
				if (uris.size == 0) {
					string? raw_text = selection_data.get_text ();
					if (raw_text != null && raw_text.length > 0) {
						foreach (unowned string line in raw_text.split ("\n")) {
							var resolved = DragManager.resolve_drop_uri (line);
							if (resolved != null && !uris.contains (resolved))
								uris.add (resolved);
						}
					}
				}

				bool copied = false;
				if (current_dir != null && uris.size > 0) {
					copied = FileDockItem.copy_uris_into_directory (current_dir, uris);
					if (copied) {
						if (TargetItem != null)
							TargetItem.refresh_launchers ();
						ApplicationDiscovery.get_default ().refresh_index_now ();
						populate_items ();
						show_all ();
						update_position (true);
					}
				}
				Gtk.drag_finish (context, copied, false, time_);
			});
		}

		void on_windows_refreshed ()
		{
			if (get_visible () && current_dir != null && !context_menu_active) {
				populate_items ();
				show_all ();
				update_position (true);
			}
		}

		public void refresh_if_visible ()
		{
			on_windows_refreshed ();
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
				if (!context_menu_active)
					schedule_dismiss (DISMISS_DELAY);
			}
			return false;
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
			if (context_menu_active)
				return;
			cancel_dismiss_timer ();
			dismiss_timer_id = Timeout.add (delay_ms, () => {
				dismiss_timer_id = 0U;
				if (!pointer_inside && !context_menu_active) {
					close_menu ();
				}
				return false;
			});
		}

		public void on_dock_hover (DockItem? hovered_item)
		{
			if (!get_visible () || TargetItem == null || context_menu_active)
				return;

			if (hovered_item == TargetItem) {
				cancel_dismiss_timer ();
				update_position ();
				return;
			}

			// If another dock item is actively hovered, dismiss immediately
			if (hovered_item != null) {
				close_menu ();
				return;
			}

			// When moving from the folder icon towards the menu, hovered_item becomes null
			// as the cursor passes through the dock window padding/edge.
			// Give the user a graceful window to cross into the menu without abruptly closing.
			if (!pointer_inside && !context_menu_active) {
				schedule_dismiss (DISMISS_DELAY);
			}
		}

		public void on_dock_leave ()
		{
			if (!get_visible () || context_menu_active)
				return;

			if (!pointer_inside && !context_menu_active)
				schedule_dismiss (DISMISS_DELAY);
		}

		Gtk.CssProvider? css_provider = null;

		void remove_theme_style ()
		{
			if (css_provider != null) {
				unowned Gdk.Screen? screen = get_screen () ?? Gdk.Screen.get_default ();
				if (screen != null)
					Gtk.StyleContext.remove_provider_for_screen (screen, css_provider);
				css_provider = null;
			}
		}

		void clear_items ()
		{
			if (items_box == null)
				return;
			foreach (var w in items_box.get_children ())
				w.destroy ();
		}

		void cleanup_window_resources ()
		{
			if (is_window_cleaned_up)
				return;
			is_window_cleaned_up = true;
			has_last_pos = false;
			WindowManager.get_default ().windows_refreshed.disconnect (on_windows_refreshed);
			cancel_dismiss_timer ();
			cancel_position_timer ();
			remove_theme_style ();
			_controller = null;
		}

		public override void destroy ()
		{
			cleanup_window_resources ();
			clear_items ();
			base.destroy ();
		}

		~FolderMenuWindow ()
		{
			cleanup_window_resources ();
		}

		void apply_theme_style ()
		{
			if (css_provider != null)
				return;

			css_provider = new Gtk.CssProvider ();
			try {
				var css = """
					.wayplank-folder-menu,
					window.wayplank-folder-menu {
						background-color: transparent;
						background: transparent;
					}
					.wayplank-folder-menu scrolledwindow,
					.wayplank-folder-menu viewport,
					.wayplank-folder-menu box {
						background-color: transparent;
						background: transparent;
					}
					.folder-menu-label {
						color: #ffffff;
						font-size: 13px;
						font-weight: 500;
					}
					.folder-menu-header {
						color: rgba(255, 255, 255, 0.70);
						font-size: 12px;
						font-weight: 600;
						padding: 4px 8px;
					}
					.wayplank-folder-menu image {
						color: #ffffff;
					}
					.folder-menu-item {
						border-radius: 6px;
						padding: 6px 10px;
						transition: background-color 0.08s ease;
						background-color: transparent;
						border: 1px solid transparent;
					}
					.folder-menu-item:hover,
					.folder-menu-item.hovered {
						background-color: rgba(255, 255, 255, 0.20);
						border: 1px solid rgba(255, 255, 255, 0.35);
					}
					.folder-menu-item:hover .folder-menu-label,
					.folder-menu-item.hovered .folder-menu-label {
						color: #ffffff;
						font-weight: 600;
					}
					.folder-menu-item:hover image,
					.folder-menu-item.hovered image {
						color: #ffffff;
					}
					.folder-menu-back {
						border-radius: 6px;
						padding: 5px 8px;
						background-color: rgba(255, 255, 255, 0.10);
						border: 1px solid transparent;
					}
					.folder-menu-back:hover,
					.folder-menu-back.hovered {
						background-color: rgba(255, 255, 255, 0.25);
						border: 1px solid rgba(255, 255, 255, 0.40);
					}
					.wayplank-folder-menu separator {
						background-color: rgba(255, 255, 255, 0.16);
						min-height: 1px;
					}
				""";

				css_provider.load_from_data (css);
				unowned Gdk.Screen? screen = get_screen () ?? Gdk.Screen.get_default ();
				if (screen != null) {
					Gtk.StyleContext.add_provider_for_screen (screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 20);
				}
			} catch (GLib.Error e) { }
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

			double radius = 7.0;
			double line_width = 1.0;

			// Draw rounded cornered rectangle matching tooltips
			Theme.draw_rounded_rect (cr,
				line_width / 2.0, line_width / 2.0,
				width - line_width, height - line_width,
				radius, radius, line_width);

			// Tooltip background: black/dark charcoal rgba(28, 28, 30, 0.95)
			cr.set_source_rgba (28.0 / 255.0, 28.0 / 255.0, 30.0 / 255.0, 0.95);
			cr.fill_preserve ();

			// Tooltip border: 1px solid rgba(255, 255, 255, 0.18)
			cr.set_source_rgba (1.0, 1.0, 1.0, 0.18);
			cr.set_line_width (line_width);
			cr.stroke ();

			cr.restore ();

			return base.draw (cr);
		}

		public void show_for_item (FileDockItem item)
		{
			TargetItem = item;
			current_dir = item.OwnedFile;
			history.clear ();
			pointer_inside = false;
			cancel_dismiss_timer ();
			cancel_position_timer ();

			apply_theme_style ();

			populate_items ();
			show_all ();

			var display = get_display ();
			var monitor = (display != null) ? PositionManager.get_monitor_for_plug_name (display, controller.prefs.Monitor) : null;
			Hal.Shell.set_surface_monitor (this, monitor);

			update_position (true);
			if (TargetItem != null) {
				unowned PositionManager pm = controller.position_manager;
				var val = pm.get_draw_value_for_item (TargetItem);
				Hal.Shell.sync_popup_after_show (
					this, PopupSurfaceKind.FOLDER_MENU, monitor, pm.Position,
					(int) Math.round (val.center.x), (int) Math.round (val.center.y),
					pm.get_visual_thickness_for_item (TargetItem), GAP
				);
			}
		}

		public void close_menu (bool force = false)
		{
			if (!force && context_menu_active)
				return;
			cancel_dismiss_timer ();
			cancel_position_timer ();
			has_last_pos = false;
			context_menu_active = false;
			pointer_inside = false;
			hovered_app_uri = null;
			hovered_win_count = 0;
			hide ();
			clear_items ();
			TargetItem = null;
			current_dir = null;
			history.clear ();
			controller.check_collapse_after_interaction (this);
		}

		void populate_items ()
		{
			clear_items ();

			if (current_dir == null || !current_dir.query_exists ()) {
				var empty_lbl = new Gtk.Label (_("Empty Folder"));
				empty_lbl.get_style_context ().add_class ("folder-menu-header");
				items_box.pack_start (empty_lbl, false, false, 8);
				items_box.show_all ();
				return;
			}

			// If drilled down, show a back button
			if (history.size > 0) {
				var back_eb = new Gtk.EventBox ();
				back_eb.get_style_context ().add_class ("folder-menu-item");
				back_eb.get_style_context ().add_class ("folder-menu-back");

				back_eb.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK);
				back_eb.enter_notify_event.connect (() => {
					back_eb.set_state_flags (Gtk.StateFlags.PRELIGHT, false);
					back_eb.get_style_context ().add_class ("hovered");
					cancel_dismiss_timer ();
					pointer_inside = true;
					return false;
				});
				back_eb.leave_notify_event.connect (() => {
					back_eb.unset_state_flags (Gtk.StateFlags.PRELIGHT);
					back_eb.get_style_context ().remove_class ("hovered");
					return false;
				});
				back_eb.realize.connect (() => {
					if (back_eb.get_window () != null)
						back_eb.get_window ().set_cursor (new Gdk.Cursor.for_display (back_eb.get_display (), Gdk.CursorType.HAND2));
				});

				var back_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
				string back_icon_name = DrawingService.theme_has_icon ("go-previous-symbolic")
					? "go-previous-symbolic" : "pan-start-symbolic";
				var back_icon = new Gtk.Image.from_icon_name (back_icon_name, Gtk.IconSize.MENU);
				var back_lbl = new Gtk.Label (_("Back"));
				back_lbl.get_style_context ().add_class ("folder-menu-label");
				back_lbl.set_xalign (0.0f);
				back_box.pack_start (back_icon, false, false, 0);
				back_box.pack_start (back_lbl, true, true, 0);
				back_eb.add (back_box);

				back_eb.button_press_event.connect ((event) => {
					if (event.button != Gdk.BUTTON_PRIMARY)
						return false;
					if (history.size > 0) {
						current_dir = history.remove_at (history.size - 1);
						populate_items ();
						show_all ();
						update_position (true);
					}
					return true;
				});
				items_box.pack_start (back_eb, false, false, 0);

				var sep = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
				items_box.pack_start (sep, false, false, 3);
			}

			var dir_keys = new Gee.ArrayList<string> ();
			var dir_map = new Gee.HashMap<string, File> ();
			var file_keys = new Gee.ArrayList<string> ();
			var file_map = new Gee.HashMap<string, File> ();

			try {
				var enumerator = current_dir.enumerate_children (
					FileAttribute.STANDARD_NAME + "," +
					FileAttribute.STANDARD_DISPLAY_NAME + "," +
					FileAttribute.STANDARD_IS_HIDDEN + "," +
					FileAttribute.STANDARD_TYPE,
					0,
					null
				);

				FileInfo info;
				uint count = 0U;
				while ((info = enumerator.next_file ()) != null) {
					if (info.get_is_hidden ())
						continue;
					var name = info.get_name ();
					if (name == ".directory" || name.ascii_down () == "desktop.ini")
						continue;
					if (count++ >= FOLDER_MAX_FILE_COUNT)
						break;

					var display_name = info.get_display_name () ?? name;
					var child = current_dir.get_child (name);
					var key = "%s_%s".printf (display_name.down (), child.get_uri ());

					if (info.get_file_type () == FileType.DIRECTORY) {
						dir_keys.add (key);
						dir_map.set (key, child);
					} else {
						file_keys.add (key);
						file_map.set (key, child);
					}
				}
				try { enumerator.close (null); } catch { }
			} catch (Error e) {
				debug ("FolderMenuWindow: Failed to enumerate '%s': %s", current_dir.get_path () ?? "", e.message);
			}

			dir_keys.sort ();
			file_keys.sort ();

			int item_count = 0;
			bool show_running = controller.prefs.ShowRunningIndicators;

			// Add Subdirectories
			foreach (var k in dir_keys) {
				var child = dir_map.get (k);
				var display_name = child.get_basename ();
				try {
					var info = child.query_info (FileAttribute.STANDARD_DISPLAY_NAME, 0);
					display_name = info.get_display_name () ?? display_name;
				} catch { }

				int sub_win_count = show_running ? count_subdir_running_windows (child) : 0;
				var row = create_row ("folder", display_name, true, sub_win_count);
				row.enter_notify_event.connect (() => {
					hovered_app_uri = null;
					hovered_win_count = 0;
					return false;
				});
				row.button_press_event.connect ((event) => {
					if (event.button != Gdk.BUTTON_PRIMARY)
						return false;
					history.add (current_dir);
					current_dir = child;
					populate_items ();
					show_all ();
					update_position (true);
					return true;
				});
				items_box.pack_start (row, false, false, 0);
				item_count++;
			}

			// Add App Launchers and Files
			foreach (var k in file_keys) {
				var child = file_map.get (k);
				var uri = child.get_uri ();
				string icon, text;

				if (Hal.Apps.is_launcher_uri (uri)) {
					ApplicationDockItem.parse_launcher (uri, out icon, out text);
					if (text == null || text == "")
						text = child.get_basename ();
					if (icon == null || icon == "")
						icon = "application-x-executable";

					int win_count = WindowManager.get_default ().window_count_for_app (uri);
					var row = create_row (icon, text, false, show_running ? win_count : 0);
					row.add_events (Gdk.EventMask.SCROLL_MASK);
					row.enter_notify_event.connect (() => {
						hovered_app_uri = uri;
						hovered_win_count = win_count;
						return false;
					});
					row.leave_notify_event.connect (() => {
						if (hovered_app_uri == uri) {
							hovered_app_uri = null;
							hovered_win_count = 0;
						}
						return false;
					});
					row.scroll_event.connect ((event) => {
						return handle_app_scroll (uri, win_count, event);
					});
					row.button_press_event.connect ((event) => {
						bool is_ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
						if (event.button == 2 || (event.button == 1 && is_ctrl)) {
							// Middle click or Ctrl+Left click: force launch new instance
							System.get_default ().launch (child);
							if (TargetItem != null)
								TargetItem.clicked (PopupButton.LEFT, 0, Gtk.get_current_event_time ());
							close_menu (true);
							return true;
						} else if (event.button == 1) {
							bool is_shift = (event.state & Gdk.ModifierType.SHIFT_MASK) != 0;
							if (win_count > 0) {
								if (is_shift) {
									string? cycle_uuid;
									if (WindowManager.get_default ().cycle_window (uri, true, out cycle_uuid)) {
										Hal.Windows.perform_window_action (cycle_uuid, WindowAction.ACTIVATE);
										close_menu (true);
										return true;
									}
								}
								int click_behavior = controller.prefs.WindowClickBehavior;
								bool restore_minimized = controller.prefs.RestoreMinimizedWindows;
								string? uuid;
								string action;
								if (WindowManager.get_default ().resolve_click_command (uri, click_behavior, restore_minimized, out uuid, out action)) {
									Hal.Windows.perform_window_action (uuid, WindowAction.from_command_name (action));
									if (TargetItem != null)
										TargetItem.clicked (PopupButton.LEFT, 0, Gtk.get_current_event_time ());
									close_menu (true);
									return true;
								}
							}
							System.get_default ().launch (child);
							if (TargetItem != null)
								TargetItem.clicked (PopupButton.LEFT, 0, Gtk.get_current_event_time ());
							close_menu (true);
							return true;
						} else if (event.button == 3) {
							// Right click: show app context menu anchored to row
							show_app_context_menu (row, event, child, uri, text, win_count);
							return true;
						}
						return false;
					});
					items_box.pack_start (row, false, false, 0);
					item_count++;
				} else {
					icon = DrawingService.get_icon_from_file (child) ?? "text-x-generic";
					text = child.get_basename ();
					try {
						var info = child.query_info (FileAttribute.STANDARD_DISPLAY_NAME, 0);
						text = info.get_display_name () ?? text;
					} catch { }

					var row = create_row (icon, text, false);
					row.enter_notify_event.connect (() => {
						hovered_app_uri = null;
						hovered_win_count = 0;
						return false;
					});
					row.button_press_event.connect ((event) => {
						if (event.button != Gdk.BUTTON_PRIMARY)
							return false;
						System.get_default ().open (child);
						if (TargetItem != null)
							TargetItem.clicked (PopupButton.LEFT, 0, Gtk.get_current_event_time ());
						close_menu (true);
						return true;
					});
					items_box.pack_start (row, false, false, 0);
					item_count++;
				}
			}

			if (item_count == 0) {
				var empty_lbl = new Gtk.Label (_("Empty Folder"));
				empty_lbl.get_style_context ().add_class ("folder-menu-header");
				items_box.pack_start (empty_lbl, false, false, 8);
			}

			items_box.show_all ();
		}

		int count_subdir_running_windows (File dir)
		{
			int total = 0;
			try {
				var enumerator = dir.enumerate_children (
					FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_IS_HIDDEN,
					FileQueryInfoFlags.NONE,
					null
				);
				FileInfo? info;
				while ((info = enumerator.next_file (null)) != null) {
					if (info.get_is_hidden ())
						continue;
					var name = info.get_name ();
					if (name == ".directory" || name.ascii_down () == "desktop.ini")
						continue;
					var child_uri = dir.get_child (name).get_uri ();
					if (Hal.Apps.is_launcher_uri (child_uri)) {
						total += WindowManager.get_default ().window_count_for_app (child_uri);
					}
				}
				try { enumerator.close (null); } catch { }
			} catch { }
			return total;
		}

		bool handle_app_scroll (string app_uri, int win_count, Gdk.EventScroll event)
		{
			if (win_count <= 0)
				return false;

			bool forward = false;
			if (event.direction == Gdk.ScrollDirection.UP || event.direction == Gdk.ScrollDirection.RIGHT) {
				forward = true;
			} else if (event.direction == Gdk.ScrollDirection.DOWN || event.direction == Gdk.ScrollDirection.LEFT) {
				forward = false;
			} else if (event.direction == Gdk.ScrollDirection.SMOOTH) {
				double dx = 0.0, dy = 0.0;
				if (!event.get_scroll_deltas (out dx, out dy)) {
					dx = event.delta_x;
					dy = event.delta_y;
				}
				if (dx == 0.0 && dy == 0.0)
					return true;
				if (event.time - last_scroll_time > 400U) {
					smooth_scroll_dx = 0.0;
					smooth_scroll_dy = 0.0;
				}
				last_scroll_time = event.time;
				smooth_scroll_dx += dx;
				smooth_scroll_dy += dy;

				if (smooth_scroll_dy <= -0.7) {
					forward = true;
					smooth_scroll_dx = 0.0;
					smooth_scroll_dy = 0.0;
				} else if (smooth_scroll_dy >= 0.7) {
					forward = false;
					smooth_scroll_dx = 0.0;
					smooth_scroll_dy = 0.0;
				} else if (smooth_scroll_dx <= -0.7) {
					forward = false;
					smooth_scroll_dx = 0.0;
					smooth_scroll_dy = 0.0;
				} else if (smooth_scroll_dx >= 0.7) {
					forward = true;
					smooth_scroll_dx = 0.0;
					smooth_scroll_dy = 0.0;
				} else {
					return true;
				}
			} else {
				return true;
			}

			string? uuid;
			if (WindowManager.get_default ().cycle_window (app_uri, forward, out uuid)) {
				Hal.Windows.perform_window_action (uuid, WindowAction.ACTIVATE);
				return true;
			}
			return false;
		}

		Gtk.EventBox create_row (string icon_name, string title, bool is_folder, int win_count = 0)
		{
			var eb = new Gtk.EventBox ();
			eb.get_style_context ().add_class ("folder-menu-item");
			eb.set_above_child (true);

			eb.add_events (
				Gdk.EventMask.ENTER_NOTIFY_MASK |
				Gdk.EventMask.LEAVE_NOTIFY_MASK |
				Gdk.EventMask.SCROLL_MASK
			);
			eb.enter_notify_event.connect (() => {
				eb.set_state_flags (Gtk.StateFlags.PRELIGHT, false);
				eb.get_style_context ().add_class ("hovered");
				cancel_dismiss_timer ();
				pointer_inside = true;
				return false;
			});
			eb.leave_notify_event.connect (() => {
				eb.unset_state_flags (Gtk.StateFlags.PRELIGHT);
				eb.get_style_context ().remove_class ("hovered");
				return false;
			});
			eb.realize.connect (() => {
				if (eb.get_window () != null)
					eb.get_window ().set_cursor (new Gdk.Cursor.for_display (eb.get_display (), Gdk.CursorType.HAND2));
			});

			var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

			var pixbuf = DrawingService.load_icon (icon_name, ICON_SIZE, ICON_SIZE);
			var img = new Gtk.Image.from_pixbuf (pixbuf);
			box.pack_start (img, false, false, 0);

			var lbl = new Gtk.Label (title);
			lbl.get_style_context ().add_class ("folder-menu-label");
			lbl.set_xalign (0.0f);
			lbl.set_ellipsize (Pango.EllipsizeMode.END);
			box.pack_start (lbl, true, true, 0);

			if (win_count > 0) {
				var dot_da = new Gtk.DrawingArea ();
				int w = (win_count > 1) ? 22 : 14;
				dot_da.set_size_request (w, 14);
				dot_da.valign = Gtk.Align.CENTER;
				dot_da.halign = Gtk.Align.CENTER;
				dot_da.draw.connect ((cr) => {
					double[] centers = (win_count > 1) ? new double[] { 5.0, 15.0 } : new double[] { 7.0 };
					double size = 10.0;

					foreach (var cx in centers) {
						double cy = 7.0;
						cr.move_to (cx, cy);
						cr.arc (cx, cy, size / 2.0, 0, Math.PI * 2);
						cr.close_path ();

						var rg = new Cairo.Pattern.radial (cx, cy, 0, cx, cy, size / 2.0);
						rg.add_color_stop_rgba (0.0, 1.0, 1.0, 1.0, 1.0);
						rg.add_color_stop_rgba (0.22, 56.0 / 255.0, 189.0 / 255.0, 248.0 / 255.0, 1.0);
						rg.add_color_stop_rgba (0.45, 14.0 / 255.0, 165.0 / 255.0, 233.0 / 255.0, 0.75);
						rg.add_color_stop_rgba (0.75, 2.0 / 255.0, 132.0 / 255.0, 199.0 / 255.0, 0.30);
						rg.add_color_stop_rgba (1.0, 2.0 / 255.0, 132.0 / 255.0, 199.0 / 255.0, 0.0);

						cr.set_source (rg);
						cr.fill ();
					}
					return false;
				});
				dot_da.set_tooltip_text (_("Application is running (%d windows)").printf (win_count));
				box.pack_start (dot_da, false, false, 4);
			}

			if (is_folder) {
				string next_icon_name = DrawingService.theme_has_icon ("go-next-symbolic")
					? "go-next-symbolic" : "pan-end-symbolic";
				var arrow = new Gtk.Image.from_icon_name (next_icon_name, Gtk.IconSize.MENU);
				arrow.set_opacity (0.6);
				box.pack_start (arrow, false, false, 0);
			}

			eb.add (box);
			return eb;
		}

		void show_app_context_menu (Gtk.Widget row, Gdk.EventButton event, File child, string uri, string title, int win_count)
		{
			cancel_dismiss_timer ();
			context_menu_active = true;
			var menu = new Gtk.Menu ();
			menu.attach_to_widget (row, null);

			// 1. Windows list & window management
			if (win_count > 0) {
				var windows = WindowManager.get_default ().matching_windows (uri);
				if (windows.size > 1) {
					foreach (var w in windows) {
						var win_title = (w.Caption != null && w.Caption != "") ? w.Caption : title;
						if (win_title.char_count () > 50)
							win_title = win_title.substring (0, win_title.index_of_nth_char (47)) + "...";
						var w_item = new Gtk.MenuItem.with_label (win_title);
						var target_uuid = w.Id;
						w_item.activate.connect (() => {
							Hal.Windows.perform_window_action (target_uuid, WindowAction.ACTIVATE);
							close_menu (true);
						});
						menu.append (w_item);
					}
					menu.append (new Gtk.SeparatorMenuItem ());
					var close_all_item = DockElement.create_menu_item (_("Close _All"), "window-close", true);
					close_all_item.activate.connect (() => {
						foreach (var w in windows) {
							Hal.Windows.perform_window_action (w.Id, WindowAction.CLOSE);
						}
						close_menu (true);
					});
					menu.append (close_all_item);
				} else if (windows.size == 1) {
					var target_uuid = windows[0].Id;
					var close_item = DockElement.create_menu_item (_("_Close"), "window-close", true);
					close_item.activate.connect (() => {
						Hal.Windows.perform_window_action (target_uuid, WindowAction.CLOSE);
						close_menu (true);
					});
					menu.append (close_item);
				}
			}

			// 2. Quicklist Actions & Shortcuts from launcher metadata (e.g. "New Window", "New Incognito Window")
			var actions = new Gee.ArrayList<string> ();
			var actions_map = new Gee.HashMap<string, string> ();
			var desktop_action_ids = new Gee.HashMap<string, string> ();
			string unused_icon, unused_text;
			ApplicationDockItem.parse_launcher (uri, out unused_icon, out unused_text, actions, actions_map, null, desktop_action_ids);

			if (actions.size > 0) {
				if (menu.get_children ().length () > 0)
					menu.append (new Gtk.SeparatorMenuItem ());

				foreach (var s in actions) {
					var values = actions_map.get (s).split (";;");
					var action_id = desktop_action_ids.get (s);
					var fallback_cmd = (values.length > 0) ? values[0] : "";
					var item = DockElement.create_menu_item (s, values.length > 1 ? values[1] : "", true);
					item.activate.connect (() => {
						if (action_id != null && action_id != "") {
							Hal.Apps.launch_action (uri, action_id, fallback_cmd, System.get_default ().context);
						} else if (fallback_cmd != "") {
							Hal.Apps.launch_command (fallback_cmd, "", System.get_default ().context);
						}
						close_menu (true);
					});
					menu.append (item);
				}
			} else {
				if (menu.get_children ().length () > 0)
					menu.append (new Gtk.SeparatorMenuItem ());

				if (win_count > 0) {
					var new_win_item = DockElement.create_menu_item (_("_New Window"), "window-new", true);
					new_win_item.activate.connect (() => {
						System.get_default ().launch (child);
						close_menu (true);
					});
					menu.append (new_win_item);
				} else {
					var open_item = DockElement.create_menu_item (_("_Open"), "document-open", true);
					open_item.activate.connect (() => {
						System.get_default ().launch (child);
						close_menu (true);
					});
					menu.append (open_item);
				}
			}

			var recent_item = RecentFilesService.build_submenu_item (uri, () => {
				close_menu (true);
			});
			if (recent_item != null) {
				if (menu.get_children ().length () > 0)
					menu.append (new Gtk.SeparatorMenuItem ());
				menu.append (recent_item);
			}

			// Context menu dismiss handling: keep folder menu open if context menu is cancelled
			menu.hide.connect (() => {
				context_menu_active = false;
				if (!pointer_inside)
					schedule_dismiss (DISMISS_DELAY);
			});

			menu.show_all ();
			menu.popup_at_pointer ((Gdk.Event) event);
		}

		public void update_position (bool force = false)
		{
			if (TargetItem == null || !TargetItem.is_valid () || !get_visible ())
				return;

			unowned PositionManager pm = controller.position_manager;
			var val = pm.get_draw_value_for_item (TargetItem);

			Gtk.Requisition req;
			get_preferred_size (null, out req);
			int width = req.width > 0 ? req.width : MIN_WIDTH;
			int height = req.height > 0 ? req.height : 100;

			var display = get_display ();
			var monitor = (display != null) ? PositionManager.get_monitor_for_plug_name (display, controller.prefs.Monitor) : null;

			int center_x = (int) Math.round (val.center.x);
			int center_y = (int) Math.round (val.center.y);
			int visual_thickness = pm.get_visual_thickness_for_item (TargetItem);

			if (!force && has_last_pos
				&& center_x == last_center_x
				&& center_y == last_center_y
				&& width == last_pos_w
				&& height == last_pos_h
				&& pm.Position == last_pos_edge
				&& visual_thickness == last_thickness) {
				return;
			}
			has_last_pos = true;
			last_center_x = center_x;
			last_center_y = center_y;
			last_pos_w = width;
			last_pos_h = height;
			last_pos_edge = pm.Position;
			last_thickness = visual_thickness;

			Hal.Shell.position_popup_surface (
				this, PopupSurfaceKind.FOLDER_MENU, monitor, pm.Position,
				center_x, center_y, width, height, visual_thickness, GAP
			);
		}
	}
}
