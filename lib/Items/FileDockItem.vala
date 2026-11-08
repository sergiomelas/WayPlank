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
	 * A dock item for files or folders on the dock.
	 *
	 * Folders act like stacks and display the contents of the folder in the
	 * popup menu. Files just open the associated file.
	 */
	public class FileDockItem : DockItem
	{
		const string DEFAULT_ICONS = "inode-directory;;folder";
		
		public File OwnedFile { get; protected construct set; }
		
		FileMonitor? dir_monitor;
		Gee.ArrayList<string> contained_launchers = new Gee.ArrayList<string> ();
		string[]? cached_tile_icons = null;
		Gdk.Pixbuf?[]? cached_tile_pixbufs = null;
		bool is_window_connected = false;
		
		/**
		 * {@inheritDoc}
		 */
		public FileDockItem.with_file (GLib.File file)
		{
			var prefs = new DockItemPreferences ();
			prefs.Launcher = file.get_uri ();
			
			GLib.Object (Prefs: prefs, OwnedFile: file);
		}
		
		/**
		 * {@inheritDoc}
		 */
		public FileDockItem.with_dockitem_file (GLib.File file)
		{
			var prefs = new DockItemPreferences.with_file (file);
			
			GLib.Object (Prefs: prefs, OwnedFile: File.new_for_uri (prefs.Launcher));
		}

		/**
		 * {@inheritDoc}
		 */
		public FileDockItem.with_dockitem_filename (string filename)
		{
			var prefs = new DockItemPreferences.with_filename (filename);
			
			GLib.Object (Prefs: prefs, OwnedFile: File.new_for_uri (prefs.Launcher));
		}
		
		construct
		{
			load_from_launcher ();
		}
		
		~FileDockItem ()
		{
			stop_monitor ();
			cached_tile_icons = null;
			cached_tile_pixbufs = null;
		}

		public override void cleanup ()
		{
			stop_monitor ();
			cached_tile_icons = null;
			cached_tile_pixbufs = null;
			base.cleanup ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override void load_from_launcher ()
		{
			stop_monitor ();
			cached_tile_icons = null;
			cached_tile_pixbufs = null;
			
			if (Prefs.Launcher == "")
				return;
			
			OwnedFile = File.new_for_uri (Prefs.Launcher);
			Icon = resolve_folder_icon ();
			
			if (!OwnedFile.is_native ()) {
				Text = OwnedFile.get_uri ();
				return;
			}
			
			Text = get_display_name (OwnedFile);
			
			if (OwnedFile.query_file_type (0) == FileType.DIRECTORY) {
				try {
					dir_monitor = OwnedFile.monitor_directory (0);
					dir_monitor.changed.connect (handle_dir_changed);
				} catch {
					critical ("Unable to watch the stack directory '%s'.", OwnedFile.get_path () ?? "");
				}
				refresh_contained_launchers ();
				if (!is_window_connected) {
					WindowManager.get_default ().windows_refreshed.connect (update_indicator);
					is_window_connected = true;
				}
				update_indicator ();
			}
		}

		string resolve_folder_icon ()
		{
			if (Prefs.CustomIcon != "" && DrawingService.has_icon (Prefs.CustomIcon))
				return Prefs.CustomIcon;

			if (OwnedFile != null) {
				var resolved = DrawingService.get_icon_from_file (OwnedFile);
				if (resolved != null && DrawingService.has_icon (resolved))
					return resolved;
			}

			return is_directory () ? DEFAULT_ICONS : "text-x-generic";
		}

		public void apply_custom_icon (string new_icon)
		{
			Prefs.CustomIcon = new_icon;
			if (OwnedFile != null) {
				try {
					var info = new FileInfo ();
					if (new_icon.has_prefix ("/") || new_icon.has_prefix ("file://")) {
						string uri = new_icon.has_prefix ("file://") ? new_icon : File.new_for_path (new_icon).get_uri ();
						info.set_attribute_string ("metadata::custom-icon", uri);
						info.set_attribute_string ("metadata::custom-icon-name", "");
					} else {
						info.set_attribute_string ("metadata::custom-icon-name", new_icon);
						info.set_attribute_string ("metadata::custom-icon", "");
					}
					OwnedFile.set_attributes_from_info (info, FileQueryInfoFlags.NONE, null);
				} catch (Error e) {
					debug ("FileDockItem: GVFS metadata::custom-icon unavailable (persisted in .dockitem): %s", e.message);
				}
			}
			Icon = new_icon;
			cached_tile_icons = null;
			cached_tile_pixbufs = null;
			reset_icon_buffer ();
		}

		/**
		 * Restores this folder item to its default icon and presentation.
		 * Clears custom icon metadata on disk when user explicitly resets in IconChooserDialog.
		 */
		public void restore_default_icon ()
		{
			Prefs.CustomIcon = "";
			if (OwnedFile != null) {
				try {
					var info = new FileInfo ();
					info.set_attribute_string ("metadata::custom-icon", "");
					info.set_attribute_string ("metadata::custom-icon-name", "");
					OwnedFile.set_attributes_from_info (info, FileQueryInfoFlags.NONE, null);
				} catch (Error e) {
					debug ("Failed to clear folder custom icon metadata: %s", e.message);
				}
			}
			Icon = resolve_folder_icon ();
			cached_tile_icons = null;
			cached_tile_pixbufs = null;
			reset_icon_buffer ();
		}

		protected override void on_icon_theme_changed ()
		{
			base.on_icon_theme_changed ();
			if (OwnedFile == null)
				return;

			// Re-resolve icon from file against the newly active theme.
			// If the custom icon exists in this theme, use it. If not, fall back to DEFAULT_ICONS.
			// IMPORTANT: Never erase the folder's metadata on disk, so returning to the original theme
			// automatically restores the custom icon!
			Icon = resolve_folder_icon ();
			cached_tile_icons = null;
			cached_tile_pixbufs = null;
			reset_icon_buffer ();
		}
		
		void stop_monitor ()
		{
			if (dir_monitor != null) {
				dir_monitor.changed.disconnect (handle_dir_changed);
				dir_monitor.cancel ();
				dir_monitor = null;
			}
			if (is_window_connected) {
				WindowManager.get_default ().windows_refreshed.disconnect (update_indicator);
				is_window_connected = false;
			}
		}
		
		[CCode (instance_pos = -1)]
		void handle_dir_changed (File f, File? other, FileMonitorEvent event)
		{
			cached_tile_icons = null;
			cached_tile_pixbufs = null;
			reset_icon_buffer ();
			refresh_contained_launchers ();
			if (event == FileMonitorEvent.CREATED
				|| event == FileMonitorEvent.DELETED
				|| event == FileMonitorEvent.MOVED_IN
				|| event == FileMonitorEvent.MOVED_OUT
				|| event == FileMonitorEvent.CHANGES_DONE_HINT) {
				ApplicationDiscovery.get_default ().refresh_index_now ();
			}
			update_indicator ();
		}

		public void refresh_launchers ()
		{
			cached_tile_icons = null;
			cached_tile_pixbufs = null;
			reset_icon_buffer ();
			refresh_contained_launchers ();
			update_indicator ();
			needs_redraw ();
		}

		void refresh_contained_launchers ()
		{
			contained_launchers.clear ();
			if (!is_directory ())
				return;

			try {
				var enumerator = OwnedFile.enumerate_children (
					FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_IS_HIDDEN + "," + FileAttribute.STANDARD_TYPE,
					FileQueryInfoFlags.NONE,
					null
				);
				FileInfo? info;
				while ((info = enumerator.next_file (null)) != null) {
					if (info.get_is_hidden ())
						continue;
					var name = info.get_name ();
					if (name.has_suffix (".desktop")) {
						contained_launchers.add (OwnedFile.get_child (name).get_uri ());
					} else if (info.get_file_type () == FileType.DIRECTORY) {
						var sub_dir = OwnedFile.get_child (name);
						try {
							var sub_enum = sub_dir.enumerate_children (
								FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_IS_HIDDEN,
								FileQueryInfoFlags.NONE,
								null
							);
							FileInfo? sub_info;
							while ((sub_info = sub_enum.next_file (null)) != null) {
								if (!sub_info.get_is_hidden () && sub_info.get_name ().has_suffix (".desktop"))
									contained_launchers.add (sub_dir.get_child (sub_info.get_name ()).get_uri ());
							}
						} catch { }
					}
				}
			} catch (Error e) {
				debug ("FileDockItem: Failed to enumerate directory '%s': %s", OwnedFile.get_path () ?? "", e.message);
			}
		}

		public void update_indicator ()
		{
			unowned DefaultApplicationDockItemProvider? provider = (Container as DefaultApplicationDockItemProvider);
			var show_running = (provider == null || provider.Prefs.ShowRunningIndicators);
			if (!show_running || !is_directory () || contained_launchers.size == 0) {
				if (Indicator != IndicatorState.NONE)
					Indicator = IndicatorState.NONE;
				return;
			}

			var wm = WindowManager.get_default ();
			int total_windows = 0;
			int running_apps = 0;
			foreach (var uri in contained_launchers) {
				int count = wm.window_count_for_app (uri);
				if (count > 0) {
					running_apps++;
					total_windows += count;
				}
			}

			IndicatorState new_state = IndicatorState.NONE;
			if (total_windows > 1 || running_apps > 1) {
				new_state = IndicatorState.SINGLE_PLUS;
			} else if (total_windows == 1) {
				new_state = IndicatorState.SINGLE;
			}

			if (Indicator != new_state) {
				Indicator = new_state;
			}
		}
		
		bool has_default_icon_match ()
		{
			if (Icon == DEFAULT_ICONS)
				return true;
			
			var default_icons = DEFAULT_ICONS.split (";;");
			foreach (unowned string icon in Icon.split (";;"))
				if (icon in default_icons)
					return true;
			
			return false;
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override void draw_icon_fast (Surface surface)
		{
			unowned Cairo.Context cr = surface.Context;
			var width = surface.Width;
			var height = surface.Height;
			var radius = 3 + 6 * height / (128 - 48);
			double x_scale = 1.0, y_scale = 1.0;
			surface.Internal.get_device_scale (out x_scale, out y_scale);
			var line_width_half = 0.5 * (int) double.max (x_scale, y_scale);
			
			cr.move_to (radius, line_width_half);
			cr.arc (width - radius - line_width_half, radius + line_width_half, radius, -Math.PI_2, 0);
			cr.arc (width - radius - line_width_half, height - radius - line_width_half, radius, 0, Math.PI_2);
			cr.arc (radius + line_width_half, height - radius - line_width_half, radius, Math.PI_2, Math.PI);
			cr.arc (radius + line_width_half, radius + line_width_half, radius, Math.PI, -Math.PI_2);
			cr.close_path ();
			
			cr.set_source_rgba (1, 1, 1, 0.6);
			cr.set_line_width (2 * line_width_half);
			cr.stroke_preserve ();
			
			var rg = new Cairo.Pattern.radial (width / 2, height, height / 8, width / 2, height, height);
			rg.add_color_stop_rgba (0, 0, 0, 0, 1);
			rg.add_color_stop_rgba (1, 0, 0, 0, 0.6);
			
			cr.set_source (rg);
			cr.fill ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override void draw_icon (Surface surface)
		{
			if (!is_valid ()) {
				base.draw_icon (surface);
				return;
			}
			
			if (!has_default_icon_match ()) {
				if (DrawingService.has_icon (Icon)) {
					base.draw_icon (surface);
					return;
				}
				
				// Custom icon not available in active theme: fall back to default presentation at runtime.
				// Keep metadata intact so returning to the original theme will restore the custom icon.
			}
			
			unowned Cairo.Context cr = surface.Context;
			var width = surface.Width;
			var height = surface.Height;
			var radius = 3 + 6 * height / (128 - 48);
			
			draw_icon_fast (surface);
			
			unowned string[] tile_icons = get_cached_tile_icons ();
			var icon_width = (int) ((width - 80 * radius / 33.0) / 2.0);
			var icon_height = (int) ((height - 80 * radius / 33.0) / 2.0);
			var offset = (int) ((width - 2 * icon_width) / 3.0);
			
			if (tile_icons.length == 0) {
				// Empty folder: draw centered default folder icon on the tray instead of leaving it completely blank
				var folder_pbuf = DrawingService.load_icon (DEFAULT_ICONS, (int) (width * 0.7), (int) (height * 0.7));
				if (folder_pbuf != null) {
					Gdk.cairo_set_source_pixbuf (cr, folder_pbuf,
						(width - folder_pbuf.width) / 2,
						(height - folder_pbuf.height) / 2);
					cr.paint ();
				}
				return;
			}
			
			unowned Gdk.Pixbuf?[] tile_pbufs = get_cached_tile_pixbufs ();
			for (int pos = 0; pos < tile_pbufs.length; pos++) {
				var x = pos % 2;
				int y = pos / 2;
				var src_pbuf = tile_pbufs[pos];
				var pbuf = (src_pbuf != null && icon_width > 0 && icon_height > 0)
					? DrawingService.ar_scale (src_pbuf, icon_width, icon_height)
					: null;
				if (pbuf != null) {
					Gdk.cairo_set_source_pixbuf (cr, pbuf,
						x * (icon_width + offset) + offset + (icon_width - pbuf.width) / 2,
						y * (icon_height + offset) + offset + (icon_height - pbuf.height) / 2);
					cr.paint ();
				}
			}
		}

		unowned Gdk.Pixbuf?[] get_cached_tile_pixbufs ()
		{
			unowned string[] tile_icons = get_cached_tile_icons ();
			if (cached_tile_pixbufs != null && cached_tile_pixbufs.length == tile_icons.length)
				return cached_tile_pixbufs;

			var pbufs = new Gdk.Pixbuf?[tile_icons.length];
			for (int i = 0; i < tile_icons.length; i++)
				pbufs[i] = DrawingService.load_icon (tile_icons[i], 128, 128);

			cached_tile_pixbufs = (owned) pbufs;
			return cached_tile_pixbufs;
		}

		unowned string[] get_cached_tile_icons ()
		{
			if (cached_tile_icons != null)
				return cached_tile_icons;

			var icons = new Gee.HashMap<string, string> ();
			var keys = new Gee.ArrayList<string> ();

			get_files (OwnedFile).map_iterator ().foreach ((display_name, file) => {
				string icon, text;
				var uri = file.get_uri ();
				if (uri.has_suffix (".desktop")) {
					ApplicationDockItem.parse_launcher (uri, out icon, out text);
				} else {
					icon = DrawingService.get_icon_from_file (file) ?? "";
					text = display_name ?? "";
				}

				var key = "%s%s".printf (text, uri);
				icons.set (key, icon);
				keys.add (key);

				return true;
			});

			keys.sort ();
			int limit = int.min (4, keys.size);
			var resolved = new string[limit];
			for (int i = 0; i < limit; i++)
				resolved[i] = icons.get (keys.get (i)) ?? "";

			cached_tile_icons = (owned) resolved;
			return cached_tile_icons;
		}
		
		/**
		 * Launches the application associated with this item.
		 */
		public void launch ()
		{
			System.get_default ().open (OwnedFile);
			ClickedAnimation = AnimationType.BOUNCE;
			LastClicked = GLib.get_monotonic_time ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.MIDDLE) {
				launch ();
				return AnimationType.BOUNCE;
			}
			
			if (button == PopupButton.LEFT) {
				if (is_directory ())
					return AnimationType.BOUNCE;
				
				launch ();
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}

		public bool is_directory ()
		{
			return OwnedFile.query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY;
		}

		public override string get_drop_text ()
		{
			if (is_directory ())
				return _("Drop to copy into %s").printf (Text);
			return base.get_drop_text ();
		}

		public override bool can_accept_drop (Gee.ArrayList<string> uris)
		{
			if (uris == null || uris.size == 0)
				return false;
			
			if (!is_directory ())
				return false;
			
			if (!OwnedFile.query_exists ())
				return false;

			return true;
		}

		static void copy_file_or_dir (File src, File dest) throws Error
		{
			var type = src.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
			if (type == FileType.DIRECTORY) {
				if (!dest.query_exists ())
					dest.make_directory_with_parents (null);
				var enumerator = src.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					var child_name = info.get_name ();
					copy_file_or_dir (src.get_child (child_name), dest.get_child (child_name));
				}
			} else {
				src.copy (dest, FileCopyFlags.OVERWRITE, null, null);
			}
		}

		public static bool copy_uris_into_directory (File target_dir, Gee.ArrayList<string> uris)
		{
			if (!target_dir.query_exists () || target_dir.query_file_type (FileQueryInfoFlags.NONE, null) != FileType.DIRECTORY)
				return false;

			bool any_copied = false;
			foreach (var uri in uris) {
				try {
					File src;
					if (uri.has_prefix ("application://")) {
						var desktop_id = uri.replace ("application://", "").strip ();
						while (desktop_id.has_suffix ("/"))
							desktop_id = desktop_id.slice (0, desktop_id.length - 1);
						var app_info = new DesktopAppInfo (desktop_id);
						if (app_info == null && !desktop_id.has_suffix (".desktop"))
							app_info = new DesktopAppInfo (desktop_id + ".desktop");
						if (app_info != null && app_info.get_filename () != null)
							src = File.new_for_path (app_info.get_filename ());
						else
							continue;
					} else if (uri.has_prefix ("file://")) {
						src = File.new_for_uri (uri);
					} else if (uri.has_prefix ("/")) {
						src = File.new_for_path (uri);
					} else {
						src = File.new_for_commandline_arg (uri);
					}

					if (!src.query_exists ())
						continue;

					var basename = src.get_basename ();
					if (basename == null || basename == "")
						continue;

					var dest = target_dir.get_child (basename);

					// Avoid copying onto itself or copying a parent directory into its own child
					if (src.equal (dest) || dest.has_prefix (src))
						continue;

					copy_file_or_dir (src, dest);
					if (basename.has_suffix (".desktop") && dest.get_path () != null) {
						FileUtils.chmod (dest.get_path (), 0755);
					}
					any_copied = true;
				} catch (Error e) {
					warning ("Failed to copy '%s' into '%s': %s", uri, target_dir.get_path () ?? "", e.message);
				}
			}
			return any_copied;
		}

		public override bool accept_drop (Gee.ArrayList<string> uris)
		{
			if (!is_directory ())
				return false;

			bool any_copied = copy_uris_into_directory (OwnedFile, uris);
			if (any_copied) {
				cached_tile_icons = null;
			cached_tile_pixbufs = null;
				reset_icon_buffer ();
				refresh_contained_launchers ();
				ApplicationDiscovery.get_default ().refresh_index_now ();
				update_indicator ();
				needs_redraw ();
				ClickedAnimation = AnimationType.BOUNCE;
				LastClicked = GLib.get_monotonic_time ();
			}

			return any_copied;
		}
		
		public override bool has_menu_for_button (PopupButton button)
		{
			if (button == PopupButton.LEFT && is_directory ())
				return true;
			return base.has_menu_for_button (button);
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items_for_button (PopupButton button)
		{
			if (button == PopupButton.LEFT && is_directory ())
				return get_launcher_popup_items ();
			return get_menu_items ();
		}

		/**
		 * {@inheritDoc}
		 */
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			if (is_directory ())
				return get_dir_menu_items ();
			
			return get_file_menu_items ();
		}

		Gee.ArrayList<Gtk.MenuItem> get_launcher_popup_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			populate_items_from_dir (OwnedFile, items, 0);

			if (items.size == 0) {
				var empty_item = new Gtk.MenuItem.with_label (_("Empty Folder"));
				empty_item.sensitive = false;
				items.add (empty_item);
			}

			return items;
		}

		Gee.ArrayList<Gtk.MenuItem> get_dir_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			unowned DefaultApplicationDockItemProvider? default_provider = (Container as DefaultApplicationDockItemProvider);
			if (default_provider != null
				&& !default_provider.Prefs.LockItems) {
				var delete_item = new Gtk.CheckMenuItem.with_mnemonic (_("_Keep in Dock"));
				delete_item.active = true;
				delete_item.activate.connect (() => {
					unowned DockController? dock = get_dock ();
					if (dock != null && dock.drag_manager != null)
						dock.drag_manager.remove_item_with_effect (this, false, dock.position_manager.IconSize);
					else
						@delete ();
				});
				items.add (delete_item);
			}

			var item = create_menu_item (_("_Open in File Browser"), "gtk-open");
			item.activate.connect (() => {
				launch ();
			});
			items.add (item);

			var icon_item = create_menu_item (_("Change _Icon..."), "preferences-desktop-theme");
			icon_item.activate.connect (() => {
				IconChooserDialog.show_for_folder (this);
			});
			items.add (icon_item);

			return items;
		}

		void populate_items_from_dir (File dir, Gee.ArrayList<Gtk.MenuItem> target_list, int depth = 0, Gee.HashSet<string>? visited = null)
		{
			var visited_set = (visited != null) ? visited : new Gee.HashSet<string> ();

			var dir_path = dir.get_path ();
			if (dir_path != null) {
				if (visited_set.contains (dir_path))
					return;
				visited_set.add (dir_path);
			}

			var menu_items = new Gee.HashMap<string, Gtk.MenuItem> ();
			var keys = new Gee.ArrayList<string> ();
			uint count = 0U;

			try {
				var enumerator = dir.enumerate_children (
					FileAttribute.STANDARD_NAME + "," +
					FileAttribute.STANDARD_DISPLAY_NAME + "," +
					FileAttribute.STANDARD_IS_HIDDEN + "," +
					FileAttribute.STANDARD_TYPE + "," +
					FileAttribute.ACCESS_CAN_READ,
					0,
					null
				);

				FileInfo info;
				while ((info = enumerator.next_file ()) != null) {
					if (info.get_is_hidden ())
						continue;

					if (count++ >= FOLDER_MAX_FILE_COUNT) {
						critical ("There are way too many files (%u+) in '%s'.", FOLDER_MAX_FILE_COUNT, dir.get_path ());
						break;
					}

					var name = info.get_name ();
					var display_name = info.get_display_name () ?? name;
					var child = dir.get_child (name);
					var uri = child.get_uri ();
					var file_type = info.get_file_type ();

					Gtk.MenuItem item;
					string sort_key;

					if (file_type == FileType.DIRECTORY) {
						item = create_literal_menu_item (display_name, "folder");
						if (depth < 3) {
							var submenu = new Gtk.Menu ();
							var sub_items = new Gee.ArrayList<Gtk.MenuItem> ();
							populate_items_from_dir (child, sub_items, depth + 1, visited_set);

							if (sub_items.size == 0) {
								var empty_child = new Gtk.MenuItem.with_label (_("Empty"));
								empty_child.sensitive = false;
								submenu.append (empty_child);
							} else {
								foreach (var sub_it in sub_items)
									submenu.append (sub_it);
							}

							submenu.show_all ();
							item.set_submenu (submenu);
						} else {
							item.activate.connect (() => {
								System.get_default ().open (child);
								ClickedAnimation = AnimationType.BOUNCE;
								LastClicked = GLib.get_monotonic_time ();
							});
						}
						sort_key = "0_" + display_name.down ();
					} else if (uri.has_suffix (".desktop")) {
						string icon, text;
						ApplicationDockItem.parse_launcher (uri, out icon, out text);
						if (text == null || text == "")
							text = display_name;
						if (icon == null || icon == "")
							icon = "application-x-executable";
						item = create_literal_menu_item (text, icon, true);
						item.activate.connect (() => {
							System.get_default ().launch (child);
							ClickedAnimation = AnimationType.BOUNCE;
							LastClicked = GLib.get_monotonic_time ();
						});
						sort_key = "1_" + text.down ();
					} else {
						var icon = DrawingService.get_icon_from_file (child) ?? "text-x-generic";
						item = create_literal_menu_item (display_name, icon);
						item.activate.connect (() => {
							System.get_default ().open (child);
							ClickedAnimation = AnimationType.BOUNCE;
							LastClicked = GLib.get_monotonic_time ();
						});
						sort_key = "1_" + display_name.down ();
					}

					var unique_key = "%s_%s".printf (sort_key, uri);
					menu_items.set (unique_key, item);
					keys.add (unique_key);
				}
			} catch (Error e) {
				debug ("Error enumerating folder '%s': %s", dir.get_path () ?? "", e.message);
			}

			keys.sort ();
			foreach (var k in keys) {
				target_list.add (menu_items.get (k));
			}
		}
		
		Gee.ArrayList<Gtk.MenuItem> get_file_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			
			unowned DefaultApplicationDockItemProvider? default_provider = (Container as DefaultApplicationDockItemProvider);
			if (default_provider != null
				&& !default_provider.Prefs.LockItems) {
				var delete_item = new Gtk.CheckMenuItem.with_mnemonic (_("_Keep in Dock"));
				delete_item.active = true;
				delete_item.activate.connect (() => {
					unowned DockController? dock = get_dock ();
					if (dock != null && dock.drag_manager != null)
						dock.drag_manager.remove_item_with_effect (this, false, dock.position_manager.IconSize);
					else
						@delete ();
				});
				items.add (delete_item);
			}
			
			var item = create_menu_item (_("_Open"), "gtk-open");
			item.activate.connect (launch);
			items.add (item);
			
			item = create_menu_item (_("Open Containing _Folder"), "folder");
			item.activate.connect (() => {
				System.get_default ().open (OwnedFile.get_parent ());
				ClickedAnimation = AnimationType.BOUNCE;
				LastClicked = GLib.get_monotonic_time ();
			});
			items.add (item);

			var icon_item = create_menu_item (_("Change _Icon..."), "preferences-desktop-theme");
			icon_item.activate.connect (() => {
				IconChooserDialog.show_for_folder (this);
			});
			items.add (icon_item);
			
			return items;
		}

		static Gee.HashMap<string,File> get_files (File file)
		{
			var files = new Gee.HashMap<string,File> ();
			var count = 0U;
			
			try {
				var enumerator = file.enumerate_children (FileAttribute.STANDARD_NAME + ","
					+ FileAttribute.STANDARD_DISPLAY_NAME + ","
					+ FileAttribute.STANDARD_IS_HIDDEN + ","
					+ FileAttribute.ACCESS_CAN_READ, 0);
				
				FileInfo info;
				
				while ((info = enumerator.next_file ()) != null) {
					if (info.get_is_hidden ())
						continue;
					
					if (count++ >= FOLDER_MAX_FILE_COUNT) {
						critical ("There are way too many files (%u+) in '%s'.", FOLDER_MAX_FILE_COUNT, file.get_path ());
						break;
					}
					
					unowned string name = info.get_name ();
					files.set (info.get_display_name () ?? name, file.get_child (name));
				}
			} catch { }
			
			return files;
		}
		
		static string get_display_name (File file)
		{
			try {
				var info = file.query_info (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_DISPLAY_NAME, 0);
				var raw_name = info.get_display_name () ?? info.get_name ();
				switch (raw_name) {
				case "Internet":
					return _("Internet");
				case "Office":
					return _("Office");
				case "Media":
					return _("Media");
				case "Games":
					return _("Games");
				case "Utilities":
					return _("Utilities");
				default:
					return raw_name;
				}
			} catch { }
			
			debug ("Could not get display-name for '%s'", file.get_path () ?? "");
			
			return _("Unknown");
		}
	}
}
