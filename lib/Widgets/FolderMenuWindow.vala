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
	public class FolderMenuWindow : Gtk.Window
	{
		const int GAP = 4;
		const int ICON_SIZE = 24;
		const int MAX_HEIGHT = 440;
		const int MIN_WIDTH = 220;
		public const uint DISMISS_DELAY = 450U;

		public DockController controller { get; construct; }
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
			set_decorated (false);
			set_title ("wayplank-folder-menu");
			set_role ("popup-menu");

			if (GtkLayerShell.is_supported ()) {
				GtkLayerShell.init_for_window (this);
				GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
				GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
				GtkLayerShell.set_namespace (this, "wayplank-folder-menu");
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

		public override void destroy ()
		{
			remove_theme_style ();
			base.destroy ();
		}

		~FolderMenuWindow ()
		{
			remove_theme_style ();
		}

		void apply_theme_style ()
		{
			remove_theme_style ();

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

			apply_theme_style ();

			populate_items ();
			show_all ();

			var display = get_display ();
			var monitor = (display != null) ? PositionManager.get_monitor_for_plug_name (display, controller.prefs.Monitor) : null;
			if (monitor != null && GtkLayerShell.is_supported ())
				GtkLayerShell.set_monitor (this, monitor);

			update_position ();
		}

		public void close_menu (bool force = false)
		{
			if (!force && context_menu_active)
				return;
			cancel_dismiss_timer ();
			context_menu_active = false;
			pointer_inside = false;
			hovered_app_uri = null;
			hovered_win_count = 0;
			hide ();
			TargetItem = null;
			current_dir = null;
			history.clear ();
			controller.check_collapse_after_interaction (this);
		}

		void populate_items ()
		{
			foreach (var w in items_box.get_children ())
				items_box.remove (w);

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
				var back_icon = new Gtk.Image.from_icon_name ("go-previous-symbolic", Gtk.IconSize.MENU);
				var back_lbl = new Gtk.Label (_("Back"));
				back_lbl.get_style_context ().add_class ("folder-menu-label");
				back_lbl.set_xalign (0.0f);
				back_box.pack_start (back_icon, false, false, 0);
				back_box.pack_start (back_lbl, true, true, 0);
				back_eb.add (back_box);

				back_eb.button_press_event.connect (() => {
					if (history.size > 0) {
						current_dir = history.remove_at (history.size - 1);
						populate_items ();
						show_all ();
						update_position ();
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
					if (count++ >= FOLDER_MAX_FILE_COUNT)
						break;

					var name = info.get_name ();
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
			} catch (Error e) {
				debug ("FolderMenuWindow: Failed to enumerate '%s': %s", current_dir.get_path () ?? "", e.message);
			}

			dir_keys.sort ();
			file_keys.sort ();

			int item_count = 0;

			// Add Subdirectories
			foreach (var k in dir_keys) {
				var child = dir_map.get (k);
				var display_name = child.get_basename ();
				try {
					var info = child.query_info (FileAttribute.STANDARD_DISPLAY_NAME, 0);
					display_name = info.get_display_name () ?? display_name;
				} catch { }

				var row = create_row ("folder", display_name, true);
				row.enter_notify_event.connect (() => {
					hovered_app_uri = null;
					hovered_win_count = 0;
					return false;
				});
				row.button_press_event.connect (() => {
					history.add (current_dir);
					current_dir = child;
					populate_items ();
					show_all ();
					update_position ();
					return true;
				});
				items_box.pack_start (row, false, false, 0);
				item_count++;
			}

			// Add Desktop Launchers and Files
			foreach (var k in file_keys) {
				var child = file_map.get (k);
				var uri = child.get_uri ();
				string icon, text;

				if (uri.has_suffix (".desktop")) {
					ApplicationDockItem.parse_launcher (uri, out icon, out text);
					if (text == null || text == "")
						text = child.get_basename ();
					if (icon == null || icon == "")
						icon = "application-x-executable";

					int win_count = WindowManager.get_default ().window_count_for_app (uri);
					var row = create_row (icon, text, false, win_count);
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
							if (win_count > 0) {
								int click_behavior = controller.prefs.WindowClickBehavior;
								bool restore_minimized = controller.prefs.RestoreMinimizedWindows;
								string? uuid;
								string action;
								if (WindowManager.get_default ().resolve_click_command (uri, click_behavior, restore_minimized, out uuid, out action)) {
									WindowControl.queue_command (uuid, action);
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
					row.button_press_event.connect (() => {
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

		bool handle_app_scroll (string app_uri, int win_count, Gdk.EventScroll event)
		{
			if (win_count <= 0)
				return false;

			double dx = 0.0, dy = 0.0;
			bool has_deltas = (event.direction == Gdk.ScrollDirection.SMOOTH && event.get_scroll_deltas (out dx, out dy));
			bool forward = false;

			if (event.direction == Gdk.ScrollDirection.UP || event.direction == Gdk.ScrollDirection.RIGHT) {
				forward = true;
			} else if (event.direction == Gdk.ScrollDirection.DOWN || event.direction == Gdk.ScrollDirection.LEFT) {
				forward = false;
			} else if (event.direction == Gdk.ScrollDirection.SMOOTH) {
				if (has_deltas) {
					if (Math.fabs (dy) < 0.1 && Math.fabs (dx) < 0.1)
						return false;
					forward = (dy < 0.0 || dx < 0.0);
				} else {
					forward = (event.delta_y < 0.0);
				}
			}

			string? uuid;
			if (WindowManager.get_default ().cycle_window (app_uri, forward, out uuid)) {
				WindowControl.queue_command (uuid, "activate");
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
				var arrow = new Gtk.Image.from_icon_name ("go-next-symbolic", Gtk.IconSize.MENU);
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
						if (win_title.length > 50)
							win_title = win_title.substring (0, 47) + "...";
						var w_item = new Gtk.MenuItem.with_label (win_title);
						var target_uuid = w.Id;
						w_item.activate.connect (() => {
							WindowControl.queue_command (target_uuid, "activate");
							close_menu (true);
						});
						menu.append (w_item);
					}
					menu.append (new Gtk.SeparatorMenuItem ());
					var close_all_item = DockElement.create_menu_item (_("Close _All"), "window-close", true);
					close_all_item.activate.connect (() => {
						foreach (var w in windows) {
							WindowControl.queue_command (w.Id, "close");
						}
						close_menu (true);
					});
					menu.append (close_all_item);
				} else if (windows.size == 1) {
					var target_uuid = windows[0].Id;
					var close_item = DockElement.create_menu_item (_("_Close"), "window-close", true);
					close_item.activate.connect (() => {
						WindowControl.queue_command (target_uuid, "close");
						close_menu (true);
					});
					menu.append (close_item);
				}
			}

			// 2. Desktop Actions & Shortcuts from .desktop file (e.g. "New Window", "New Incognito Window")
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
					var item = DockElement.create_menu_item (s, values.length > 1 ? values[1] : "", true);
					item.activate.connect (() => {
						if (action_id != null) {
							string? path = null;
							if (uri.has_prefix ("file://"))
								path = File.new_for_uri (uri).get_path ();
							else
								path = uri;
							if (path != null) {
								var desktop_info = new DesktopAppInfo.from_filename (path);
								if (desktop_info != null) {
									desktop_info.launch_action (action_id, System.get_default ().context);
									close_menu (true);
									return;
								}
							}
						}
						if (values.length > 0 && values[0] != "") {
							try {
								AppInfo.create_from_commandline (values[0], null, AppInfoCreateFlags.NONE).launch (null, null);
							} catch { }
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

			// Context menu dismiss handling: keep folder menu open if context menu is cancelled
			menu.hide.connect (() => {
				context_menu_active = false;
				if (!pointer_inside)
					schedule_dismiss (DISMISS_DELAY);
			});

			menu.show_all ();
			menu.popup_at_pointer ((Gdk.Event) event);
		}

		public void update_position ()
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
					top_margin += WindowControl.get_top_panel_floating_offset ();

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
	}
}
