//
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
	public class FolderMenuWindow : Gtk.Window
	{
		const int GAP = 8;
		const int ICON_SIZE = 24;
		const int MAX_HEIGHT = 440;
		const int MIN_WIDTH = 220;
		public const uint DISMISS_DELAY = 150U;

		public DockController controller { get; construct; }
		public FileDockItem? TargetItem { get; protected set; default = null; }

		File? current_dir = null;
		Gee.ArrayList<File> history = new Gee.ArrayList<File> ();

		Gtk.Box main_box;
		Gtk.Box items_box;
		Gtk.ScrolledWindow scrolled;

		uint dismiss_timer_id = 0U;
		bool pointer_inside = false;

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
			main_box.pack_start (scrolled, true, true, 0);

			items_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
			scrolled.add (items_box);

			apply_theme_style ();

			add_events (
				Gdk.EventMask.ENTER_NOTIFY_MASK |
				Gdk.EventMask.LEAVE_NOTIFY_MASK |
				Gdk.EventMask.POINTER_MOTION_MASK
			);

			enter_notify_event.connect (on_enter);
			leave_notify_event.connect (on_leave);
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
					close_menu ();
				}
				return false;
			});
		}

		public void on_dock_hover (DockItem? hovered_item)
		{
			if (!get_visible () || TargetItem == null)
				return;

			if (hovered_item != TargetItem) {
				close_menu ();
			} else {
				cancel_dismiss_timer ();
				update_position ();
			}
		}

		public void on_dock_leave ()
		{
			if (!get_visible ())
				return;

			if (!pointer_inside)
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
					.folder-menu-label,
					.folder-menu-item label {
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
					.folder-menu-item:hover label,
					.folder-menu-item.hovered label,
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

		public void close_menu ()
		{
			cancel_dismiss_timer ();
			hide ();
			TargetItem = null;
			current_dir = null;
			history.clear ();
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

					var row = create_row (icon, text, false);
					row.button_press_event.connect (() => {
						System.get_default ().launch (child);
						if (TargetItem != null)
							TargetItem.clicked (PopupButton.LEFT, 0, Gtk.get_current_event_time ());
						close_menu ();
						return true;
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
					row.button_press_event.connect (() => {
						System.get_default ().open (child);
						if (TargetItem != null)
							TargetItem.clicked (PopupButton.LEFT, 0, Gtk.get_current_event_time ());
						close_menu ();
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

		Gtk.EventBox create_row (string icon_name, string title, bool is_folder)
		{
			var eb = new Gtk.EventBox ();
			eb.get_style_context ().add_class ("folder-menu-item");

			eb.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK);
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

			if (is_folder) {
				var arrow = new Gtk.Image.from_icon_name ("go-next-symbolic", Gtk.IconSize.MENU);
				arrow.set_opacity (0.6);
				box.pack_start (arrow, false, false, 0);
			}

			eb.add (box);
			return eb;
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

				switch (pm.Position) {
				case Gtk.PositionType.BOTTOM:
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, false);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);

					int bottom_margin = pm.get_visual_thickness_for_item (TargetItem) + GAP;

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

					int top_margin = pm.get_visual_thickness_for_item (TargetItem) + GAP;

					if (monitor != null) {
						var work = monitor.get_workarea ();
						int top_panel = int.max (0, work.y - geo.y);
						if (top_panel > 0)
							top_margin += top_panel + 2;
					}

					int clamped_top_x = int.max (GAP, int.min (mon_w - width - GAP, center_x - width / 2));
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, top_margin);
					GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, clamped_top_x);
					break;

				case Gtk.PositionType.LEFT:
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
					GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);

					int left_margin = pm.get_visual_thickness_for_item (TargetItem) + GAP;

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

					int right_margin = pm.get_visual_thickness_for_item (TargetItem) + GAP;

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
				// X11 fallback
				int win_x = 0, win_y = 0;
				if (controller.window.get_window () != null)
					controller.window.get_window ().get_origin (out win_x, out win_y);

				int target_x = win_x + center_x - width / 2;
				int target_y = win_y;
				var dock_region = pm.get_dock_window_region ();

				switch (pm.Position) {
				case Gtk.PositionType.BOTTOM:
					target_y = win_y + dock_region.height - pm.get_visual_thickness_for_item (TargetItem) - height - GAP;
					break;
				case Gtk.PositionType.TOP:
					target_y = win_y + pm.get_visual_thickness_for_item (TargetItem) + GAP;
					break;
				case Gtk.PositionType.LEFT:
					target_x = win_x + pm.get_visual_thickness_for_item (TargetItem) + GAP;
					target_y = win_y + center_y - height / 2;
					break;
				case Gtk.PositionType.RIGHT:
					target_x = win_x + dock_region.width - pm.get_visual_thickness_for_item (TargetItem) - width - GAP;
					target_y = win_y + center_y - height / 2;
					break;
				}

				target_x = int.max (geo.x + GAP, int.min (geo.x + mon_w - width - GAP, target_x));
				target_y = int.max (geo.y + GAP, int.min (geo.y + mon_h - height - GAP, target_y));
				move (target_x, target_y);
			}
		}
	}
}
