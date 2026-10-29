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
		public static bool is_open { get; private set; default = false; }

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

			is_open = true;
			this.show.connect (() => { is_open = true; });
			this.hide.connect (() => { is_open = false; });

			this.original_icon = current_icon;
			this.item_name = item_name;
			this.selected_icon = current_icon;

			build_ui ();
			load_theme_icons_async ();
		}

		public override void destroy ()
		{
			is_open = false;
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
			var controls_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

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
			var chooser = new Gtk.FileChooserDialog (
				_("Select Icon File"),
				this,
				Gtk.FileChooserAction.OPEN,
				_("Cancel"), Gtk.ResponseType.CANCEL,
				_("Select"), Gtk.ResponseType.ACCEPT
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

			if (chooser.run () == Gtk.ResponseType.ACCEPT) {
				string? chosen_path = chooser.get_filename ();
				if (chosen_path != null && chosen_path != "") {
					selected_icon = chosen_path;
					is_reset_to_default = false;
					update_preview_image (selected_icon);
					preview_label.set_text (selected_icon);
					btn_apply.sensitive = true;
				}
			}

			chooser.destroy ();
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
			var dlg = new IconChooserDialog (item.Icon, item.Text);
			dlg.response.connect ((resp) => {
				if (resp == Gtk.ResponseType.OK && dlg.selected_icon != null) {
					apply_launcher_icon (item, dlg.selected_icon);
				} else if (resp == Gtk.ResponseType.APPLY || dlg.is_reset_to_default) {
					reset_launcher_icon (item);
				}
				dlg.destroy ();
			});
			dlg.destroy.connect (() => {
				item.get_dock ()?.check_collapse_after_interaction (dlg);
			});
			dlg.present ();
		}

		private static void apply_launcher_icon (ApplicationDockItem item, string new_icon)
		{
			string launcher_uri = item.Prefs.Launcher;
			if (launcher_uri == "" || !launcher_uri.has_prefix ("file://"))
				return;

			string src_path = File.new_for_uri (launcher_uri).get_path ();
			if (src_path == null || !FileUtils.test (src_path, FileTest.EXISTS))
				return;

			string user_apps_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			DirUtils.create_with_parents (user_apps_dir, 0755);

			string dest_path = Path.build_filename (user_apps_dir, Path.get_basename (src_path));

			try {
				var kf = new KeyFile ();
				kf.load_from_file (src_path, KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS);
				kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON, new_icon);
				kf.save_to_file (dest_path);

				// Update launcher to point to the user desktop file
				try {
					item.Prefs.Launcher = Filename.to_uri (dest_path);
				} catch (ConvertError e) {
					warning ("Could not convert dest_path to uri: %s", e.message);
				}
				item.Icon = new_icon;
			} catch (Error e) {
				critical ("Could not save custom launcher desktop file: %s", e.message);
			}
		}

		private static void reset_launcher_icon (ApplicationDockItem item)
		{
			string launcher_uri = item.Prefs.Launcher;
			if (launcher_uri == "" || !launcher_uri.has_prefix ("file://"))
				return;

			string cur_path = File.new_for_uri (launcher_uri).get_path ();
			if (cur_path == null)
				return;

			string basename = Path.get_basename (cur_path);
			string sys_path = Path.build_filename ("/usr/share/applications", basename);
			if (!FileUtils.test (sys_path, FileTest.EXISTS))
				sys_path = Path.build_filename ("/usr/local/share/applications", basename);

			if (FileUtils.test (sys_path, FileTest.EXISTS)) {
				// Remove user override if present
				string user_apps_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
				string user_desktop = Path.build_filename (user_apps_dir, basename);
				if (FileUtils.test (user_desktop, FileTest.EXISTS)) {
					FileUtils.unlink (user_desktop);
				}

				try {
					item.Prefs.Launcher = Filename.to_uri (sys_path);
				} catch (ConvertError e) {
					warning ("Could not convert sys_path to uri: %s", e.message);
				}
			}

			// Reload icon from desktop file
			string icon, text;
			ApplicationDockItem.parse_launcher (item.Prefs.Launcher, out icon, out text);
			item.Icon = icon;
		}

		public static void show_for_folder (FileDockItem item)
		{
			var dlg = new IconChooserDialog (item.Icon, item.Text);
			dlg.response.connect ((resp) => {
				if (resp == Gtk.ResponseType.OK && dlg.selected_icon != null) {
					apply_folder_icon (item, dlg.selected_icon);
				} else if (resp == Gtk.ResponseType.APPLY || dlg.is_reset_to_default) {
					reset_folder_icon (item);
				}
				dlg.destroy ();
			});
			dlg.destroy.connect (() => {
				item.get_dock ()?.check_collapse_after_interaction (dlg);
			});
			dlg.present ();
		}

		private static void apply_folder_icon (FileDockItem item, string new_icon)
		{
			if (item.OwnedFile == null)
				return;

			try {
				var info = new FileInfo ();
				if (new_icon.has_prefix ("/") || new_icon.has_prefix ("file://")) {
					string path = new_icon;
					if (path.has_prefix ("file://"))
						path = Filename.from_uri (path);
					info.set_attribute_string ("metadata::custom-icon", path);
					info.set_attribute_string ("metadata::custom-icon-name", "");
				} else {
					info.set_attribute_string ("metadata::custom-icon-name", new_icon);
					info.set_attribute_string ("metadata::custom-icon", "");
				}
				item.OwnedFile.set_attributes_from_info (info, FileQueryInfoFlags.NONE, null);
				item.Icon = new_icon;
			} catch (Error e) {
				warning ("Failed to set folder custom icon: %s", e.message);
			}
		}

		private static void reset_folder_icon (FileDockItem item)
		{
			item.restore_default_icon ();
		}
	}
}
