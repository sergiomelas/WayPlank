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
	public class TrashDockItem : DockItem
	{
		const string TRASH_URI = "trash:///";
		const string ICON_EMPTY = "trashcan_empty;;user-trash;;emptytrash;;gnome-fs-trash-empty";
		const string ICON_FULL = "trashcan_full;;user-trash-full;;trashcan_full-new;;gnome-fs-trash-full";
		
		File trash_file;
		FileMonitor? trash_monitor = null;
		FileMonitor? xdg_trash_monitor = null;
		uint trash_count = 0;
		
		public TrashDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		public TrashDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			trash_file = File.new_for_uri (TRASH_URI);
			Text = _("Trash");
			Icon = ICON_EMPTY;
			Button = PopupButton.RIGHT;
			
			start_monitoring ();
			update_trash_state ();

			// Listen for external D-Bus notifications from KWin/KDE Plasma
			KWinTrashBridge.get_default ().trash_state_changed_externally.connect (() => {
				update_trash_state ();
			});
		}
		
		~TrashDockItem ()
		{
			stop_monitor ();
		}
		
		File get_xdg_trash_files_dir ()
		{
			var data_dir = Environment.get_user_data_dir ();
			return File.new_for_path (Path.build_filename (data_dir, "Trash", "files"));
		}

		File get_xdg_trash_info_dir ()
		{
			var data_dir = Environment.get_user_data_dir ();
			return File.new_for_path (Path.build_filename (data_dir, "Trash", "info"));
		}

		void start_monitoring ()
		{
			// 1. Try monitoring GIO virtual trash:///
			try {
				trash_monitor = trash_file.monitor_directory (FileMonitorFlags.NONE, null);
				trash_monitor.changed.connect (on_trash_changed);
			} catch (Error e) {
				debug ("GIO trash monitor unavailable: %s", e.message);
			}

			// 2. Also monitor local XDG Trash/files directory (works on KDE, XFCE, and non-GVFS sessions)
			try {
				var xdg_files = get_xdg_trash_files_dir ();
				if (!xdg_files.query_exists ())
					xdg_files.make_directory_with_parents (null);
				xdg_trash_monitor = xdg_files.monitor_directory (FileMonitorFlags.NONE, null);
				xdg_trash_monitor.changed.connect (on_trash_changed);
			} catch (Error e) {
				debug ("XDG trash monitor unavailable: %s", e.message);
			}
		}

		void stop_monitor ()
		{
			if (trash_monitor != null) {
				trash_monitor.changed.disconnect (on_trash_changed);
				trash_monitor.cancel ();
				trash_monitor = null;
			}
			if (xdg_trash_monitor != null) {
				xdg_trash_monitor.changed.disconnect (on_trash_changed);
				xdg_trash_monitor.cancel ();
				xdg_trash_monitor = null;
			}
		}
		
		public override bool is_valid ()
		{
			return true;
		}
		
		public override void @delete ()
		{
			stop_monitor ();
			base.@delete ();
		}
		
		void on_trash_changed (File file, File? other_file, FileMonitorEvent event_type)
		{
			update_trash_state ();
		}
		
		uint count_trash_items ()
		{
			uint count = 0;
			// 1. First attempt via GIO trash:///
			try {
				var enumerator = trash_file.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE, null);
				while (enumerator.next_file (null) != null) {
					count++;
				}
				return count;
			} catch (Error e) {
				// GIO trash:/// not supported in current environment
			}

			// 2. Fallback to reading XDG ~/.local/share/Trash/files
			var xdg_files = get_xdg_trash_files_dir ();
			if (xdg_files.query_exists ()) {
				try {
					var enumerator = xdg_files.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE, null);
					while (enumerator.next_file (null) != null) {
						count++;
					}
				} catch (Error e) {
				}
			}
			return count;
		}

		void update_trash_state ()
		{
			trash_count = count_trash_items ();
			
			if (trash_count == 0) {
				Icon = ICON_EMPTY;
				Text = _("Trash (Empty)");
			} else if (trash_count == 1) {
				Icon = ICON_FULL;
				Text = _("Trash (1 item)");
			} else {
				Icon = ICON_FULL;
				Text = _("Trash (%u items)").printf (trash_count);
			}
			
			reset_icon_buffer ();
		}
		
		void open_trash ()
		{
			// 1. On KDE Plasma / KWin, use native kioclient for trash:/
			if (KWinTrashBridge.is_kwin_or_kde ()) {
				try {
					Process.spawn_command_line_async ("kioclient exec trash:/");
					return;
				} catch (Error e) {
				}

				try {
					Process.spawn_command_line_async ("kioclient5 exec trash:/");
					return;
				} catch (Error e) {
				}
			}

			// 2. Try standard GIO open
			try {
				if (Gtk.show_uri_on_window (null, TRASH_URI, Gdk.CURRENT_TIME))
					return;
			} catch (Error e) {
			}

			// 3. Try xdg-open
			try {
				Process.spawn_command_line_async ("xdg-open trash:///");
				return;
			} catch (Error e) {
			}

			// 4. Fallback to opening ~/.local/share/Trash
			var data_dir = Environment.get_user_data_dir ();
			var trash_dir = Path.build_filename (data_dir, "Trash");
			try {
				Gtk.show_uri_on_window (null, "file://" + trash_dir, Gdk.CURRENT_TIME);
			} catch (Error e) {
			}
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				open_trash ();
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}
		
		public override bool can_accept_drop (Gee.ArrayList<string> uris)
		{
			return uris != null && uris.size > 0;
		}
		
		static void copy_recursively (File src, File dest) throws Error
		{
			var type = src.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
			if (type == FileType.DIRECTORY) {
				if (!dest.query_exists ())
					dest.make_directory_with_parents (null);
				var enumerator = src.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					var child_name = info.get_name ();
					copy_recursively (src.get_child (child_name), dest.get_child (child_name));
				}
			} else {
				src.copy (dest, FileCopyFlags.OVERWRITE, null, null);
			}
		}

		static void delete_recursively (File file) throws Error
		{
			var type = file.query_file_type (FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
			if (type == FileType.DIRECTORY) {
				var enumerator = file.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					delete_recursively (file.get_child (info.get_name ()));
				}
			}
			file.@delete (null);
		}

		static void delete_dir_children (File dir)
		{
			if (!dir.query_exists ())
				return;
			try {
				var enumerator = dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					try {
						delete_recursively (dir.get_child (info.get_name ()));
					} catch (Error e) {
					}
				}
			} catch (Error e) {
			}
		}

		bool trash_single_uri (string uri)
		{
			// 1. If running under KWin / KDE Plasma, delegate to kioclient for native KIO trashing
			if (KWinTrashBridge.is_kwin_or_kde () && KWinTrashBridge.move_to_trash (uri)) {
				return true;
			}

			File file;
			if (uri.has_prefix ("file://"))
				file = File.new_for_uri (uri);
			else
				file = File.new_for_commandline_arg (uri);
			
			// 2. Try native GIO file.trash ()
			try {
				file.trash (null);
				KWinTrashBridge.notify_items_added (uri);
				return true;
			} catch (Error e) {
				debug ("GIO file.trash() failed for '%s': %s, attempting XDG trash fallback", uri, e.message);
			}

			// 3. Fallback: XDG FreeDesktop Trash Specification
			// Moves file into ~/.local/share/Trash/files/ and writes ~/.local/share/Trash/info/<name>.trashinfo
			try {
				var files_dir = get_xdg_trash_files_dir ();
				var info_dir = get_xdg_trash_info_dir ();
				
				if (!files_dir.query_exists ())
					files_dir.make_directory_with_parents (null);
				if (!info_dir.query_exists ())
					info_dir.make_directory_with_parents (null);
				
				string base_name = file.get_basename ();
				string dest_name = base_name;
				var dest_file = files_dir.get_child (dest_name);
				var dest_info = info_dir.get_child (dest_name + ".trashinfo");
				
				int counter = 1;
				while (dest_file.query_exists () || dest_info.query_exists ()) {
					dest_name = "%s.%d".printf (base_name, counter++);
					dest_file = files_dir.get_child (dest_name);
					dest_info = info_dir.get_child (dest_name + ".trashinfo");
				}
				
				// Write metadata first (.trashinfo)
				var now = new DateTime.now_local ();
				string date_str = now.format ("%Y-%m-%dT%H:%M:%S");
				string orig_path = file.get_path ();
				if (orig_path == null)
					orig_path = file.get_uri ();
				
				string info_content = "[Trash Info]\nPath=%s\nDeletionDate=%s\n".printf (orig_path, date_str);
				FileUtils.set_contents (dest_info.get_path (), info_content);
				
				// Move file into files/ (use move with fallback copy+delete)
				try {
					file.move (dest_file, FileCopyFlags.NONE, null, null);
				} catch (Error move_err) {
					copy_recursively (file, dest_file);
					delete_recursively (file);
				}
				
				// Broadcast KDirNotify so KDE Plasma and all compositors sync
				KWinTrashBridge.notify_items_added (uri);
				return true;
			} catch (Error e2) {
				warning ("Failed to trash file '%s' via XDG fallback: %s", uri, e2.message);
			}

			return false;
		}

		public override bool accept_drop (Gee.ArrayList<string> uris)
		{
			if (uris == null || uris.size == 0)
				return false;
			
			bool any_trashed = false;
			foreach (var uri in uris) {
				if (trash_single_uri (uri))
					any_trashed = true;
			}
			
			if (any_trashed) {
				update_trash_state ();
				ClickedAnimation = AnimationType.BOUNCE;
				LastClicked = GLib.get_monotonic_time ();
			}
			
			return any_trashed;
		}
		
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			
			var open_item = create_menu_item (_("_Open Trash"), "document-open", true);
			open_item.activate.connect (open_trash);
			items.add (open_item);
			
			var empty_item = create_menu_item (_("_Empty Trash"), "edit-clear", true);
			empty_item.sensitive = (trash_count > 0);
			empty_item.activate.connect (empty_trash);
			items.add (empty_item);
			
			items.add (new Gtk.SeparatorMenuItem ());
			
			var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
			remove_item.activate.connect (() => {
				this.@delete ();
			});
			items.add (remove_item);
			
			append_dock_menu_items (items);
			return items;
		}
		
		void empty_trash ()
		{
			// 1. Try KWinTrashBridge / gio trash --empty
			KWinTrashBridge.empty_trash ();

			// 2. Clear GIO virtual trash:///
			try {
				var enumerator = trash_file.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE, null);
				FileInfo? info;
				while ((info = enumerator.next_file (null)) != null) {
					var child = trash_file.get_child (info.get_name ());
					try {
						child.@delete (null);
					} catch (Error e) {
					}
				}
			} catch (Error e) {
			}

			// 3. Clear XDG ~/.local/share/Trash/files and info
			delete_dir_children (get_xdg_trash_files_dir ());
			delete_dir_children (get_xdg_trash_info_dir ());
			
			// 4. Notify KDE Plasma / KWin via D-Bus that trash is completely empty!
			KWinTrashBridge.notify_items_removed ();

			update_trash_state ();
			ClickedAnimation = AnimationType.BOUNCE;
			LastClicked = GLib.get_monotonic_time ();
		}
		
		void append_dock_menu_items (Gee.ArrayList<Gtk.MenuItem> items)
		{
			if (items.size > 0)
				items.add (new Gtk.SeparatorMenuItem ());
			var dock_item = Factory.item_factory.get_item_for_dock ();
			if (dock_item != null)
				foreach (var menu_item in dock_item.get_menu_items ())
					items.add (menu_item);
		}
	}
}
