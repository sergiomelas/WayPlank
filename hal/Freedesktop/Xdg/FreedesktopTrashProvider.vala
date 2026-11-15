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
	 * Southbound GIO `trash:///`, XDG `~/.local/share/Trash/{files,info}`, and
	 * `KWinTrashBridge` provider (`ITrashProvider`).
	 */
	public class FreedesktopTrashProvider : GLib.Object, ITrashProvider
	{
		const string TRASH_URI = "trash:///";

		static FreedesktopTrashProvider? default_instance = null;

		public static FreedesktopTrashProvider get_default ()
		{
			if (default_instance == null)
				default_instance = new FreedesktopTrashProvider ();
			return default_instance;
		}

		File trash_file;
		FileMonitor? trash_monitor = null;
		FileMonitor? xdg_trash_monitor = null;
		bool kwin_bridge_connected = false;

		construct
		{
			trash_file = File.new_for_uri (TRASH_URI);
			start_monitoring ();
		}

		~FreedesktopTrashProvider ()
		{
			cleanup ();
		}

		static File get_xdg_trash_files_dir ()
		{
			var data_dir = Environment.get_user_data_dir ();
			return File.new_for_path (Path.build_filename (data_dir, "Trash", "files"));
		}

		static File get_xdg_trash_info_dir ()
		{
			var data_dir = Environment.get_user_data_dir ();
			return File.new_for_path (Path.build_filename (data_dir, "Trash", "info"));
		}

		void on_external_trash_changed ()
		{
			trash_changed ();
		}

		void on_file_monitor_changed (File file, File? other_file, FileMonitorEvent event_type)
		{
			trash_changed ();
		}

		void start_monitoring ()
		{
			try {
				trash_monitor = trash_file.monitor_directory (FileMonitorFlags.NONE, null);
				trash_monitor.changed.connect (on_file_monitor_changed);
			} catch (Error e) {
				debug ("GIO trash monitor unavailable: %s", e.message);
			}

			try {
				var xdg_files = get_xdg_trash_files_dir ();
				if (!xdg_files.query_exists ())
					xdg_files.make_directory_with_parents (null);
				xdg_trash_monitor = xdg_files.monitor_directory (FileMonitorFlags.NONE, null);
				xdg_trash_monitor.changed.connect (on_file_monitor_changed);
			} catch (Error e) {
				debug ("XDG trash monitor unavailable: %s", e.message);
			}

			if (!kwin_bridge_connected) {
				KWinTrashBridge.get_default ().trash_state_changed_externally.connect (on_external_trash_changed);
				kwin_bridge_connected = true;
			}
		}

		public void cleanup ()
		{
			if (trash_monitor != null) {
				trash_monitor.changed.disconnect (on_file_monitor_changed);
				trash_monitor.cancel ();
				trash_monitor = null;
			}
			if (xdg_trash_monitor != null) {
				xdg_trash_monitor.changed.disconnect (on_file_monitor_changed);
				xdg_trash_monitor.cancel ();
				xdg_trash_monitor = null;
			}
			if (kwin_bridge_connected) {
				KWinTrashBridge.get_default ().trash_state_changed_externally.disconnect (on_external_trash_changed);
				kwin_bridge_connected = false;
			}
		}

		public uint get_item_count ()
		{
			uint count = 0;
			try {
				var enumerator = trash_file.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE, null);
				while (enumerator.next_file (null) != null) {
					count++;
				}
				return count;
			} catch (Error e) { }

			var xdg_files = get_xdg_trash_files_dir ();
			if (xdg_files.query_exists ()) {
				try {
					var enumerator = xdg_files.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE, null);
					while (enumerator.next_file (null) != null) {
						count++;
					}
				} catch (Error e) { }
			}
			return count;
		}

		public Gee.ArrayList<TrashItemInfo> list_items ()
		{
			var items = new Gee.ArrayList<TrashItemInfo> ();
			var xdg_files = get_xdg_trash_files_dir ();
			var xdg_info = get_xdg_trash_info_dir ();
			if (!xdg_files.query_exists ())
				return items;

			try {
				var enumerator = xdg_files.enumerate_children (
					FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE,
					FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
				FileInfo? finfo;
				while ((finfo = enumerator.next_file (null)) != null) {
					string name = finfo.get_name ();
					string orig_path = "";
					string del_date = "";
					var info_file = xdg_info.get_child (name + ".trashinfo");
					if (info_file.query_exists ()) {
						try {
							var kf = new KeyFile ();
							kf.load_from_file (info_file.get_path (), KeyFileFlags.NONE);
							if (kf.has_key ("Trash Info", "Path"))
								orig_path = kf.get_string ("Trash Info", "Path");
							if (kf.has_key ("Trash Info", "DeletionDate"))
								del_date = kf.get_string ("Trash Info", "DeletionDate");
						} catch { }
					}
					items.add (new TrashItemInfo () {
						id = name,
						display_name = name,
						original_path = orig_path,
						deletion_date = del_date,
						is_directory = (finfo.get_file_type () == FileType.DIRECTORY)
					});
				}
			} catch { }

			return items;
		}

		public bool restore_item (string id)
		{
			if (id == "")
				return false;
			try {
				var files_dir = get_xdg_trash_files_dir ();
				var info_dir = get_xdg_trash_info_dir ();
				var src_file = files_dir.get_child (id);
				var info_file = info_dir.get_child (id + ".trashinfo");
				if (!src_file.query_exists () || !info_file.query_exists ())
					return false;

				var kf = new KeyFile ();
				kf.load_from_file (info_file.get_path (), KeyFileFlags.NONE);
				if (!kf.has_key ("Trash Info", "Path"))
					return false;

				string orig_path = Uri.unescape_string (kf.get_string ("Trash Info", "Path")) ?? "";
				if (orig_path == "")
					return false;

				var dest_file = orig_path.has_prefix ("file://")
					? File.new_for_uri (orig_path)
					: File.new_for_path (orig_path);
				var parent_dir = dest_file.get_parent ();
				if (parent_dir != null && !parent_dir.query_exists ())
					parent_dir.make_directory_with_parents (null);

				try {
					src_file.move (dest_file, FileCopyFlags.NONE, null, null);
				} catch (Error move_err) {
					copy_recursively (src_file, dest_file);
					delete_recursively (src_file);
				}
				try {
					info_file.@delete (null);
				} catch { }
				KWinTrashBridge.notify_items_removed ();
				trash_changed ();
				return true;
			} catch (Error e) {
				warning ("Failed to restore trash item '%s': %s", id, e.message);
				return false;
			}
		}

		public bool delete_item_permanently (string id)
		{
			if (id == "")
				return false;
			bool removed = false;
			try {
				var child = trash_file.get_child (id);
				if (child.query_exists ()) {
					child.@delete (null);
					removed = true;
				}
			} catch { }
			try {
				var src_file = get_xdg_trash_files_dir ().get_child (id);
				if (src_file.query_exists ()) {
					delete_recursively (src_file);
					removed = true;
				}
			} catch { }
			try {
				var info_file = get_xdg_trash_info_dir ().get_child (id + ".trashinfo");
				if (info_file.query_exists ())
					info_file.@delete (null);
			} catch { }
			if (removed) {
				KWinTrashBridge.notify_items_removed ();
				trash_changed ();
			}
			return removed;
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
					} catch (Error e) { }
				}
			} catch (Error e) { }
		}

		public bool move_uri_to_trash (string uri)
		{
			if (KWinTrashBridge.is_kwin_or_kde () && KWinTrashBridge.move_to_trash (uri))
				return true;

			File file;
			if (uri.has_prefix ("file://"))
				file = File.new_for_uri (uri);
			else
				file = File.new_for_commandline_arg (uri);

			try {
				file.trash (null);
				KWinTrashBridge.notify_items_added (uri);
				return true;
			} catch (Error e) {
				debug ("GIO file.trash() failed for '%s': %s, attempting XDG trash fallback", uri, e.message);
			}

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

				var now = new DateTime.now_local ();
				string date_str = now.format ("%Y-%m-%dT%H:%M:%S");
				string? orig_path = file.get_path ();
				if (orig_path == null)
					orig_path = file.get_uri ();

				string info_content = "[Trash Info]\nPath=%s\nDeletionDate=%s\n".printf (orig_path, date_str);
				FileUtils.set_contents (dest_info.get_path (), info_content);

				try {
					file.move (dest_file, FileCopyFlags.NONE, null, null);
				} catch (Error move_err) {
					copy_recursively (file, dest_file);
					delete_recursively (file);
				}

				KWinTrashBridge.notify_items_added (uri);
				return true;
			} catch (Error e2) {
				warning ("Failed to trash file '%s' via XDG fallback: %s", uri, e2.message);
			}

			return false;
		}

		public bool empty_trash ()
		{
			KWinTrashBridge.empty_trash ();

			try {
				var enumerator = trash_file.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE, null);
				FileInfo? info;
				while ((info = enumerator.next_file (null)) != null) {
					var child = trash_file.get_child (info.get_name ());
					try {
						child.@delete (null);
					} catch (Error e) { }
				}
			} catch (Error e) { }

			delete_dir_children (get_xdg_trash_files_dir ());
			delete_dir_children (get_xdg_trash_info_dir ());

			KWinTrashBridge.notify_items_removed ();
			trash_changed ();
			return true;
		}

		public void open_trash_ui ()
		{
			if (KWinTrashBridge.is_kwin_or_kde ()) {
				try {
					Process.spawn_command_line_async ("kioclient exec trash:/");
					return;
				} catch (Error e) { }

				try {
					Process.spawn_command_line_async ("kioclient5 exec trash:/");
					return;
				} catch (Error e) { }
			}

			try {
				if (Gtk.show_uri_on_window (null, TRASH_URI, Gdk.CURRENT_TIME))
					return;
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("xdg-open trash:///");
				return;
			} catch (Error e) { }

			var data_dir = Environment.get_user_data_dir ();
			var trash_dir = Path.build_filename (data_dir, "Trash");
			try {
				Gtk.show_uri_on_window (null, "file://" + trash_dir, Gdk.CURRENT_TIME);
			} catch (Error e) { }
		}
	}
}
