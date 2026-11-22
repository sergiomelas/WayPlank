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
	public class IconChooserDialog : Gtk.Dialog
	{
		private static int open_count = 0;
		private static Gee.HashMap<DockItem, unowned IconChooserDialog>? active_item_dialogs = null;
		private static Gee.HashMap<string, unowned IconChooserDialog>? active_uri_dialogs = null;
		public static bool is_open {
			get { return open_count > 0; }
		}
		private bool counted_open = false;
		private bool is_destroyed = false;
		private bool browse_in_progress = false;

		private const int ICON_DISPLAY_SIZE = 36;
		private const int MAX_VISIBLE_ICONS = 320;
		private const int POPULATE_BATCH_SIZE = 24;

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
		private Gee.ArrayList<string> pending_populate_icons;
		private int pending_populate_idx = 0;
		private int pending_populate_added = 0;
		private uint search_debounce_id = 0;
		private uint populate_idle_id = 0;

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
			cancel_populate ();
		}

		private void cancel_populate ()
		{
			if (populate_idle_id > 0) {
				GLib.Source.remove (populate_idle_id);
				populate_idle_id = 0;
			}
		}

		public override void destroy ()
		{
			is_destroyed = true;
			cancel_populate ();
			if (search_debounce_id > 0) {
				GLib.Source.remove (search_debounce_id);
				search_debounce_id = 0;
			}
			if (counted_open) {
				counted_open = false;
				if (open_count > 0)
					open_count--;
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
				var def_pix = DrawingService.load_icon ("application-x-executable", 48, 48);
				preview_image.set_from_pixbuf (def_pix);
				return;
			}

			if (DrawingService.has_icon (icon_name_or_path)) {
				var pix = DrawingService.load_icon (icon_name_or_path, 48, 48);
				preview_image.set_from_pixbuf (pix);
			} else {
				var miss_pix = DrawingService.load_icon ("image-missing", 48, 48);
				preview_image.set_from_pixbuf (miss_pix);
			}
		}

		const string[] STANDARD_SYSTEM_ICONS = {
			"folder", "folder-open", "folder-documents", "folder-download",
			"folder-music", "folder-pictures", "folder-videos", "folder-remote",
			"computer", "computer-laptop", "video-display",
			"drive-harddisk", "drive-removable-media", "drive-optical",
			"media-optical-dvd", "media-optical-audio", "media-flash", "media-floppy",
			"printer", "printer-network", "camera-photo", "camera-video", "phone",
			"network-wired", "network-idle", "network-workgroup", "network-server",
			"network-transmit-receive", "web-browser", "applications-internet",
			"preferences-system", "preferences-system-network", "preferences-desktop-display",
			"system-users", "system-lock-screen", "security-high", "dialog-key",
			"dialog-information", "dialog-warning", "dialog-error", "help-about",
			"help-browser", "edit-find", "edit-delete", "edit-rename",
			"package-x-generic", "application-x-archive", "system-software-install",
			"application-x-executable", "x-office-document", "text-x-generic"
		};

		private void load_theme_icons_async ()
		{
			all_theme_icons = new Gee.ArrayList<string> ();
			pending_populate_icons = new Gee.ArrayList<string> ();

			unowned Gtk.IconTheme theme = DrawingService.get_icon_theme ();
			GLib.List<string> icons = theme.list_icons (null);

			Gee.HashSet<string> seen = new Gee.HashSet<string> ();
			var named_icons = new Gee.ArrayList<string> ();

			// 1. Named standard system icons resolvable via HAL or real disk theme
			foreach (unowned string std_name in STANDARD_SYSTEM_ICONS) {
				if (DrawingService.has_icon (std_name) && seen.add (std_name))
					named_icons.add (std_name);
			}

			// 2. Real disk-installed desktop theme icons (exclude GTK3's internal Tango/GTK2 PNGs)
			foreach (unowned string name in icons) {
				if (name == null || name.length < 2)
					continue;
				if (seen.contains (name))
					continue;
				var info = theme.lookup_icon (name, 48, 0);
				if (info == null || DrawingService.is_builtin_gtk_icon_info (info))
					continue;
				seen.add (name);
				named_icons.add (name);
			}
			named_icons.sort ();
			all_theme_icons.add_all (named_icons);

			// 3. Curated embedded crisp WayPlank vector SVG icons (Anchor & essentials first)
			foreach (unowned string emb_name in DrawingService.get_embedded_icon_names ()) {
				if (DrawingService.has_icon (emb_name) && seen.add (emb_name))
					all_theme_icons.add (emb_name);
			}

			// 4. Native OS icon stores (e.g. Explorer DLL resource catalogs on Windows; empty on Linux)
			foreach (var native_tok in Hal.Apps.list_native_icon_tokens ()) {
				if (native_tok != "" && seen.add (native_tok))
					all_theme_icons.add (native_tok);
			}

			populate_flowbox ("");
		}

		private void populate_flowbox (string query)
		{
			cancel_populate ();

			flowbox.foreach ((child) => {
				flowbox.remove (child);
			});

			pending_populate_icons.clear ();
			pending_populate_idx = 0;
			pending_populate_added = 0;

			string lower_query = query.strip ().down ();
			foreach (var name in all_theme_icons) {
				if (lower_query != "" && !(lower_query in name.down ()))
					continue;
				pending_populate_icons.add (name);
			}

			if (pending_populate_icons.size == 0)
				return;

			populate_idle_id = GLib.Idle.add (on_populate_idle_batch);
		}

		private bool on_populate_idle_batch ()
		{
			if (is_destroyed || flowbox == null) {
				populate_idle_id = 0;
				return false;
			}

			int processed = 0;
			while (pending_populate_idx < pending_populate_icons.size
				&& pending_populate_added < MAX_VISIBLE_ICONS
				&& processed < POPULATE_BATCH_SIZE) {
				string name = pending_populate_icons[pending_populate_idx++];
				processed++;

				var pix = DrawingService.try_load_icon (name, ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE);
				if (pix == null)
					continue;

				var item_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
				item_box.margin = 4;

				var img = new Gtk.Image.from_pixbuf (pix);
				item_box.pack_start (img, true, true, 0);

				var child = new Gtk.FlowBoxChild ();
				child.tooltip_text = name;
				child.set_data<string> ("icon_name", name);
				child.add (item_box);
				child.show_all ();

				flowbox.add (child);
				pending_populate_added++;
			}

			flowbox.show_all ();

			if (pending_populate_idx >= pending_populate_icons.size
				|| pending_populate_added >= MAX_VISIBLE_ICONS) {
				populate_idle_id = 0;
				return false;
			}
			return true;
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

			var chooser = new Gtk.FileChooserDialog (
				_("Select Icon File"),
				null,
				Gtk.FileChooserAction.OPEN,
				_("Cancel"), Gtk.ResponseType.CANCEL,
				_("Select"), Gtk.ResponseType.ACCEPT
			);

			var filter = new Gtk.FileFilter ();
			filter.set_name (_("Image Files (*.png, *.svg, *.ico, *.jpg)"));
			filter.add_pattern ("*.png");
			filter.add_pattern ("*.PNG");
			filter.add_pattern ("*.svg");
			filter.add_pattern ("*.SVG");
			filter.add_pattern ("*.ico");
			filter.add_pattern ("*.ICO");
			filter.add_pattern ("*.jpg");
			filter.add_pattern ("*.JPG");
			filter.add_pattern ("*.jpeg");
			filter.add_pattern ("*.JPEG");
			filter.add_pattern ("*.xpm");
			filter.add_pattern ("*.XPM");
			filter.add_pattern ("*.exe");
			filter.add_pattern ("*.EXE");
			filter.add_pattern ("*.lnk");
			filter.add_pattern ("*.LNK");
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
			if (item.Container == null || item.Prefs.Launcher == "")
				return;

			string old_uri = item.Prefs.Launcher;
			string updated_uri = Hal.Apps.apply_custom_launcher_icon (old_uri, new_icon);
			if (updated_uri != "") {
				item.Prefs.Launcher = updated_uri;
				if (updated_uri.strip ().down () != old_uri.strip ().down ())
					CustomIconService.get_default ().set_custom_icon (old_uri, "");
			}
			item.Prefs.CustomIcon = new_icon;
			CustomIconService.get_default ().set_custom_icon (item.Prefs.Launcher, new_icon);
			item.Icon = new_icon;
			ApplicationDiscovery.get_default ().schedule_refresh ();
		}

		private static void reset_launcher_icon (ApplicationDockItem item)
		{
			if (item.Container == null || item.Prefs.Launcher == "")
				return;

			string old_uri = item.Prefs.Launcher;
			string restored_icon;
			string updated_uri = Hal.Apps.reset_custom_launcher_icon (old_uri, out restored_icon);
			item.Prefs.CustomIcon = "";
			CustomIconService.get_default ().set_custom_icon (old_uri, "");
			if (updated_uri != "") {
				item.Prefs.Launcher = updated_uri;
				CustomIconService.get_default ().set_custom_icon (updated_uri, "");
			}

			if (restored_icon != "") {
				item.Icon = restored_icon;
			} else {
				string icon, text;
				ApplicationDockItem.parse_launcher (item.Prefs.Launcher, out icon, out text);
				item.Icon = icon;
			}
			ApplicationDiscovery.get_default ().schedule_refresh ();
		}

		public static void show_for_launcher_uri (string launcher_uri, string current_icon, string display_title, DockController? controller = null)
		{
			string clean_uri = launcher_uri.strip ();
			if (clean_uri.length == 0)
				return;

			string key = clean_uri.down ();
			if (active_uri_dialogs == null)
				active_uri_dialogs = new Gee.HashMap<string, unowned IconChooserDialog> ();
			var existing = active_uri_dialogs.get (key);
			if (existing != null && !existing.is_destroyed) {
				existing.present ();
				return;
			}

			string initial_icon = (current_icon != null && current_icon != "") ? current_icon : "application-x-executable";
			string title_label = (display_title != null && display_title != "") ? display_title : clean_uri;
			var dlg = new IconChooserDialog (initial_icon, title_label);
			var ctrl_ref = GLib.WeakRef (controller);
			active_uri_dialogs.set (key, dlg);
			dlg.response.connect ((resp) => {
				if (resp == Gtk.ResponseType.OK && dlg.selected_icon != null) {
					CustomIconService.get_default ().set_custom_icon (clean_uri, dlg.selected_icon);
				} else if (resp == Gtk.ResponseType.APPLY || dlg.is_reset_to_default) {
					CustomIconService.get_default ().set_custom_icon (clean_uri, "");
				}
				dlg.destroy ();
			});
			dlg.destroy.connect (() => {
				if (active_uri_dialogs != null && active_uri_dialogs.get (key) == dlg)
					active_uri_dialogs.unset (key);
				var ctrl = ctrl_ref.get () as DockController;
				if (ctrl != null)
					ctrl.check_collapse_after_interaction (dlg);
			});
			dlg.present ();
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
