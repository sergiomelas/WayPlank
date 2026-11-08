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
	public class IconChooserDialog : Gtk.Dialog
	{
		private static int open_count = 0;
		private static Gee.HashMap<DockItem, unowned IconChooserDialog>? active_item_dialogs = null;
		public static bool is_open {
			get { return open_count > 0; }
		}
		private bool counted_open = false;
		private bool is_destroyed = false;
		private bool browse_in_progress = false;

		private const int ICON_DISPLAY_SIZE = 36;
		private const int MAX_VISIBLE_ICONS = 180;

		public string? selected_icon { get; private set; default = null; }
		public bool is_reset_to_default { get; private set; default = false; }

		private string original_icon;
		private string item_name;

		private Gtk.Image preview_image;
		private Gtk.Label preview_label;
		private Gtk.SearchEntry search_entry;
		private Gtk.FlowBox flowbox;
		private Gtk.Button btn_apply;
		private Gtk.Button btn_default;

		private Gee.ArrayList<string> all_theme_icons;
		private uint search_debounce_id = 0;

		public IconChooserDialog (string current_icon, string item_name, Gtk.Window? parent = null)
		{
			GLib.Object (
				title: _("Change Icon - %s").printf (item_name),
				window_position: Gtk.WindowPosition.CENTER
			);

			set_role ("help");
			set_type_hint (Gdk.WindowTypeHint.DIALOG);
			set_position (Gtk.WindowPosition.CENTER);
			window_position = Gtk.WindowPosition.CENTER;
			gravity = Gdk.Gravity.CENTER;
			set_keep_above (true);
			set_skip_taskbar_hint (true);
			set_skip_pager_hint (true);

			counted_open = true;
			open_count++;
			this.show.connect (() => {
				if (!is_destroyed && !counted_open) {
					counted_open = true;
					open_count++;
				}
			});
			this.hide.connect (() => {
				if (!browse_in_progress && counted_open) {
					counted_open = false;
					if (open_count > 0)
						open_count--;
				}
			});
			this.destroy.connect (() => {
				is_destroyed = true;
				if (counted_open) {
					counted_open = false;
					if (open_count > 0)
						open_count--;
				}
			});

			this.original_icon = current_icon;
			this.item_name = item_name;
			this.selected_icon = current_icon;

			build_ui ();
			load_theme_icons_async ();
		}

		~IconChooserDialog ()
		{
			is_destroyed = true;
			if (counted_open) {
				counted_open = false;
				if (open_count > 0)
					open_count--;
			}
			if (search_debounce_id > 0) {
				GLib.Source.remove (search_debounce_id);
				search_debounce_id = 0;
			}
		}

		public override void destroy ()
		{
			if (counted_open) {
				counted_open = false;
				if (open_count > 0)
					open_count--;
			}
			if (search_debounce_id > 0) {
				GLib.Source.remove (search_debounce_id);
				search_debounce_id = 0;
			}
			base.destroy ();
		}

		private void build_ui ()
		{
			set_default_size (640, 520);
			set_border_width (8);

			var content = get_content_area () as Gtk.Box;
			content.spacing = 10;
			content.margin = 12;

			// Header with current preview
			var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
			header_box.margin_bottom = 4;

			preview_image = new Gtk.Image ();
			preview_image.pixel_size = 48;
			update_preview_image (selected_icon);
			header_box.pack_start (preview_image, false, false, 0);

			var info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
			var title_lbl = new Gtk.Label ("");
			title_lbl.xalign = 0.0f;
			title_lbl.set_markup ("<b>" + _("Select icon for: ") + Markup.escape_text (item_name) + "</b>");

			preview_label = new Gtk.Label (selected_icon);
			preview_label.xalign = 0.0f;
			preview_label.get_style_context ().add_class ("dim-label");

			info_box.pack_start (title_lbl, false, false, 0);
			info_box.pack_start (preview_label, false, false, 0);
			header_box.pack_start (info_box, true, true, 0);

			content.pack_start (header_box, false, false, 0);

			// Controls: Search bar + Browse button
			var controls_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

			search_entry = new Gtk.SearchEntry ();
			search_entry.placeholder_text = _("Search theme icons (e.g. browser, folder, games, edit)...");
			search_entry.search_changed.connect (on_search_changed);
			controls_box.pack_start (search_entry, true, true, 0);

			var btn_browse = new Gtk.Button.with_mnemonic (_("_Browse File..."));
			btn_browse.image = new Gtk.Image.from_icon_name ("document-open-symbolic", Gtk.IconSize.BUTTON);
			btn_browse.always_show_image = true;
			btn_browse.tooltip_text = _("Choose a custom image file (PNG, SVG, ICO) from disk");
			btn_browse.clicked.connect (on_browse_file_clicked);
			controls_box.pack_start (btn_browse, false, false, 0);

			content.pack_start (controls_box, false, false, 0);

			// Scrolled Window with FlowBox
			var scrolled = new Gtk.ScrolledWindow (null, null);
			scrolled.shadow_type = Gtk.ShadowType.IN;
			scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
			scrolled.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;

			flowbox = new Gtk.FlowBox ();
			flowbox.valign = Gtk.Align.START;
			flowbox.max_children_per_line = 14;
			flowbox.min_children_per_line = 6;
			flowbox.row_spacing = 6;
			flowbox.column_spacing = 6;
			flowbox.homogeneous = true;
			flowbox.selection_mode = Gtk.SelectionMode.SINGLE;
			flowbox.child_activated.connect (on_child_activated);

			scrolled.add (flowbox);
			content.pack_start (scrolled, true, true, 0);

			// Action area buttons
			btn_default = add_button (_("Restore Default"), Gtk.ResponseType.APPLY) as Gtk.Button;
			btn_default.tooltip_text = _("Revert to the original default icon");
			btn_default.get_style_context ().add_class ("destructive-action");

			add_button (_("Cancel"), Gtk.ResponseType.CANCEL);

			btn_apply = add_button (_("Apply"), Gtk.ResponseType.OK) as Gtk.Button;
			btn_apply.get_style_context ().add_class ("suggested-action");
			set_default_response (Gtk.ResponseType.OK);

			response.connect (handle_response);
			this.map.connect (() => {
				set_focus (null);
				if (search_entry != null)
					search_entry.select_region (0, 0);
			});
			this.map_event.connect (() => {
				set_focus (null);
				if (search_entry != null)
					search_entry.select_region (0, 0);
				return false;
			});
			show_all ();
		}

		private void update_preview_image (string? icon_name_or_path)
		{
			if (icon_name_or_path == null || icon_name_or_path == "") {
				preview_image.set_from_icon_name ("application-x-executable", Gtk.IconSize.DIALOG);
				return;
			}

			if (icon_name_or_path.has_prefix ("/") || icon_name_or_path.has_prefix ("file://")) {
				try {
					string path = icon_name_or_path;
					if (path.has_prefix ("file://"))
						path = Filename.from_uri (path);
					var pix = new Gdk.Pixbuf.from_file_at_scale (path, 48, 48, true);
					preview_image.set_from_pixbuf (pix);
				} catch {
					preview_image.set_from_icon_name ("image-missing", Gtk.IconSize.DIALOG);
				}
			} else {
				// Handle multi-icon split (e.g. "icon1;;icon2")
				string first_icon = icon_name_or_path.split (";;")[0];
				preview_image.set_from_icon_name (first_icon, Gtk.IconSize.DIALOG);
			}
		}

		private void load_theme_icons_async ()
		{
			all_theme_icons = new Gee.ArrayList<string> ();

			var theme = Gtk.IconTheme.get_default ();
			GLib.List<string> icons = theme.list_icons (null);

			Gee.HashSet<string> seen = new Gee.HashSet<string> ();

			foreach (unowned string name in icons) {
				if (name == null || name.length < 2)
					continue;
				if (!seen.add (name))
					continue;
				all_theme_icons.add (name);
			}

			all_theme_icons.sort ();
			populate_flowbox ("");
		}

		private void populate_flowbox (string query)
		{
			flowbox.foreach ((child) => {
				flowbox.remove (child);
			});

			string lower_query = query.strip ().down ();
			int count = 0;

			foreach (var name in all_theme_icons) {
				if (lower_query != "" && !(lower_query in name.down ()))
					continue;

				var item_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
				item_box.margin = 4;

				var img = new Gtk.Image.from_icon_name (name, Gtk.IconSize.DND);
				img.pixel_size = ICON_DISPLAY_SIZE;
				item_box.pack_start (img, true, true, 0);

				var child = new Gtk.FlowBoxChild ();
				child.tooltip_text = name;
				child.set_data<string> ("icon_name", name);
				child.add (item_box);
				child.show_all ();

				flowbox.add (child);

				if (++count >= MAX_VISIBLE_ICONS)
					break;
			}

			flowbox.show_all ();
		}

		private void on_search_changed ()
		{
			if (search_debounce_id > 0)
				GLib.Source.remove (search_debounce_id);

			search_debounce_id = GLib.Timeout.add (120, () => {
				search_debounce_id = 0;
				populate_flowbox (search_entry.text);
				return false;
			});
		}

		private void on_child_activated (Gtk.FlowBoxChild child)
		{
			string? icon_name = child.get_data<string> ("icon_name");
			if (icon_name != null && icon_name != "") {
				selected_icon = icon_name;
				is_reset_to_default = false;
				update_preview_image (selected_icon);
				preview_label.set_text (selected_icon);
				btn_apply.sensitive = true;
			}
		}

		private void on_browse_file_clicked ()
		{
			if (browse_in_progress || is_destroyed)
				return;

			browse_in_progress = true;
			this.hide ();

			var chooser = new Gtk.FileChooserNative (
				_("Select Icon File"),
				null,
				Gtk.FileChooserAction.OPEN,
				_("Select"),
				_("Cancel")
			);

			var filter = new Gtk.FileFilter ();
			filter.set_name (_("Image Files (*.png, *.svg, *.ico, *.jpg)"));
			filter.add_mime_type ("image/png");
			filter.add_mime_type ("image/svg+xml");
			filter.add_mime_type ("image/x-icon");
			filter.add_mime_type ("image/jpeg");
			filter.add_pattern ("*.png");
			filter.add_pattern ("*.svg");
			filter.add_pattern ("*.ico");
			filter.add_pattern ("*.jpg");
			filter.add_pattern ("*.jpeg");
			chooser.add_filter (filter);

			var all_filter = new Gtk.FileFilter ();
			all_filter.set_name (_("All Files"));
			all_filter.add_pattern ("*");
			chooser.add_filter (all_filter);

			string? chosen_path = null;
			if (chooser.run () == Gtk.ResponseType.ACCEPT) {
				chosen_path = chooser.get_filename ();
			}

			chooser.destroy ();
			browse_in_progress = false;

			if (is_destroyed)
				return;

			this.show ();
			this.present ();

			if (chosen_path != null && chosen_path != "") {
				selected_icon = chosen_path;
				is_reset_to_default = false;
				update_preview_image (selected_icon);
				preview_label.set_text (selected_icon);
				btn_apply.sensitive = true;
			}
		}

		private void handle_response (int response_id)
		{
			if (response_id == Gtk.ResponseType.APPLY) {
				is_reset_to_default = true;
				selected_icon = null;
			} else if (response_id == Gtk.ResponseType.OK) {
				is_reset_to_default = false;
			}
		}

		// ──────────────────────────────────────────────────────────────────────────
		// Static Handlers for Items
		// ──────────────────────────────────────────────────────────────────────────

		public static void show_for_launcher (ApplicationDockItem item)
		{
			if (active_item_dialogs == null)
				active_item_dialogs = new Gee.HashMap<DockItem, unowned IconChooserDialog> ();
			var existing = active_item_dialogs.get (item);
			if (existing != null && !existing.is_destroyed) {
				existing.present ();
				return;
			}

			var dlg = new IconChooserDialog (item.Icon, item.Text);
			active_item_dialogs.set (item, dlg);
			dlg.response.connect ((resp) => {
				if (item.Container != null) {
					if (resp == Gtk.ResponseType.OK && dlg.selected_icon != null) {
						apply_launcher_icon (item, dlg.selected_icon);
					} else if (resp == Gtk.ResponseType.APPLY || dlg.is_reset_to_default) {
						reset_launcher_icon (item);
					}
				}
				dlg.destroy ();
			});
			dlg.destroy.connect (() => {
				if (active_item_dialogs != null && active_item_dialogs.get (item) == dlg)
					active_item_dialogs.unset (item);
				item.get_dock ()?.check_collapse_after_interaction (dlg);
			});
			dlg.present ();
		}

		private static void apply_launcher_icon (ApplicationDockItem item, string new_icon)
		{
			if (item.Container == null)
				return;
			string launcher_uri = item.Prefs.Launcher;
			if (launcher_uri == "" || !launcher_uri.has_prefix ("file://"))
				return;

			string src_path = File.new_for_uri (launcher_uri).get_path ();
			if (src_path == null || !FileUtils.test (src_path, FileTest.EXISTS))
				return;

			string user_apps_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			DirUtils.create_with_parents (user_apps_dir, 0755);

			string dest_path = Path.build_filename (user_apps_dir, Path.get_basename (src_path));
			bool created_by_wayplank = !FileUtils.test (dest_path, FileTest.EXISTS);

			try {
				var kf = new KeyFile ();
				kf.load_from_file (src_path, KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS);
				if (created_by_wayplank)
					kf.set_boolean (KeyFileDesktop.GROUP, "X-WayPlank-Created", true);
				if (!kf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon")) {
					try {
						string orig_icon = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
						if (orig_icon != null && orig_icon != "")
							kf.set_string (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon", orig_icon);
					} catch { }
				}
				try {
					foreach (unowned string k in kf.get_keys (KeyFileDesktop.GROUP)) {
						if (k.has_prefix ("Icon["))
							kf.remove_key (KeyFileDesktop.GROUP, k);
					}
				} catch { }
				kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON, new_icon);
				kf.save_to_file (dest_path);

				// Update launcher to point to the user desktop file
				try {
					item.Prefs.Launcher = Filename.to_uri (dest_path);
				} catch (ConvertError e) {
					warning ("Could not convert dest_path to uri: %s", e.message);
				}
				item.Icon = new_icon;
				ApplicationDiscovery.get_default ().refresh_index_now ();
			} catch (Error e) {
				critical ("Could not save custom launcher desktop file: %s", e.message);
			}
		}

		private static void reset_launcher_icon (ApplicationDockItem item)
		{
			if (item.Container == null)
				return;
			string launcher_uri = item.Prefs.Launcher;
			if (launcher_uri == "" || !launcher_uri.has_prefix ("file://"))
				return;

			string cur_path = File.new_for_uri (launcher_uri).get_path ();
			if (cur_path == null)
				return;

			string basename = Path.get_basename (cur_path);
			string user_apps_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			string user_desktop = Path.build_filename (user_apps_dir, basename);

			string? sys_path = null;
			foreach (unowned string data_dir in Environment.get_system_data_dirs ()) {
				string candidate = Path.build_filename (data_dir, "applications", basename);
				if (candidate != user_desktop && FileUtils.test (candidate, FileTest.EXISTS)) {
					sys_path = candidate;
					break;
				}
			}
			if (sys_path == null) {
				string[] extra_dirs = {
					Path.build_filename (Environment.get_user_data_dir (), "flatpak", "exports", "share", "applications"),
					"/var/lib/flatpak/exports/share/applications",
					"/var/lib/snapd/desktop/applications",
					"/usr/local/share/applications",
					"/usr/share/applications"
				};
				foreach (unowned string dir in extra_dirs) {
					string candidate = Path.build_filename (dir, basename);
					if (candidate != user_desktop && FileUtils.test (candidate, FileTest.EXISTS)) {
						sys_path = candidate;
						break;
					}
				}
			}

			bool can_unlink_user_override = false;
			if (sys_path != null && FileUtils.test (user_desktop, FileTest.EXISTS)) {
				try {
					var ukf = new KeyFile ();
					ukf.load_from_file (user_desktop, KeyFileFlags.NONE);
					if (ukf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-Created")
						&& ukf.get_boolean (KeyFileDesktop.GROUP, "X-WayPlank-Created")) {
						can_unlink_user_override = true;
					}
				} catch { }
			}

			if (sys_path != null && (!FileUtils.test (user_desktop, FileTest.EXISTS) || can_unlink_user_override)) {
				if (FileUtils.test (user_desktop, FileTest.EXISTS)) {
					FileUtils.unlink (user_desktop);
				}

				try {
					item.Prefs.Launcher = Filename.to_uri (sys_path);
				} catch (ConvertError e) {
					warning ("Could not convert sys_path to uri: %s", e.message);
				}
			} else if (FileUtils.test (cur_path, FileTest.EXISTS)) {
				// Pre-existing user .desktop (or user-only .desktop): preserve custom keys and restore original icon
				try {
					var kf = new KeyFile ();
					kf.load_from_file (cur_path, KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS);
					string? restored_icon = null;
					if (kf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon")) {
						restored_icon = kf.get_string (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon");
						kf.remove_key (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon");
					} else if (sys_path != null) {
						try {
							var skf = new KeyFile ();
							skf.load_from_file (sys_path, KeyFileFlags.NONE);
							if (skf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON))
								restored_icon = skf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
						} catch { }
					}
					if (restored_icon != null && restored_icon != "") {
						kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON, restored_icon);
						kf.save_to_file (cur_path);
					}
				} catch { }
			}

			// Reload icon from desktop file
			string icon, text;
			ApplicationDockItem.parse_launcher (item.Prefs.Launcher, out icon, out text);
			item.Icon = icon;
			ApplicationDiscovery.get_default ().refresh_index_now ();
		}

		public static void show_for_folder (FileDockItem item)
		{
			if (active_item_dialogs == null)
				active_item_dialogs = new Gee.HashMap<DockItem, unowned IconChooserDialog> ();
			var existing = active_item_dialogs.get (item);
			if (existing != null && !existing.is_destroyed) {
				existing.present ();
				return;
			}

			var dlg = new IconChooserDialog (item.Icon, item.Text);
			active_item_dialogs.set (item, dlg);
			dlg.response.connect ((resp) => {
				if (item.Container != null) {
					if (resp == Gtk.ResponseType.OK && dlg.selected_icon != null) {
						apply_folder_icon (item, dlg.selected_icon);
					} else if (resp == Gtk.ResponseType.APPLY || dlg.is_reset_to_default) {
						reset_folder_icon (item);
					}
				}
				dlg.destroy ();
			});
			dlg.destroy.connect (() => {
				if (active_item_dialogs != null && active_item_dialogs.get (item) == dlg)
					active_item_dialogs.unset (item);
				item.get_dock ()?.check_collapse_after_interaction (dlg);
			});
			dlg.present ();
		}

		private static void apply_folder_icon (FileDockItem item, string new_icon)
		{
			item.apply_custom_icon (new_icon);
		}

		private static void reset_folder_icon (FileDockItem item)
		{
			item.restore_default_icon ();
		}
	}
}
