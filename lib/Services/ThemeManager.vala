//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//  Copyright (C) 2026 史有虎 (IFtiger-hu)
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
	public class ThemePackageInfo : GLib.Object
	{
		public string name { get; construct set; }
		public string source_dir { get; construct set; }
		public bool selected { get; set; default = true; }

		public ThemePackageInfo (string name, string source_dir)
		{
			GLib.Object (name: name, source_dir: source_dir);
		}
	}

	public class ThemeManager
	{
		/**
		 * Checks whether the given theme is a user-installed theme (residing in user's home folder).
		 */
		public static bool is_user_theme (string name)
		{
			if (name == Theme.DEFAULT_NAME || name == "Transparent")
				return false;

			var folder = Theme.get_theme_folder (name);
			if (folder == null)
				return false;

			string? path = folder.get_path ();
			return (path != null && path.has_prefix (Environment.get_home_dir ()));
		}

		/**
		 * Deletes a user theme folder permanently.
		 */
		public static bool delete_user_theme (string name)
		{
			if (!is_user_theme (name))
				return false;

			var folder = Theme.get_theme_folder (name);
			if (folder == null)
				return false;

			return remove_directory_recursive (folder);
		}

		/**
		 * Recursively deletes a directory and its contents.
		 */
		public static bool remove_directory_recursive (File file)
		{
			try {
				if (file.query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY) {
					var enumerator = file.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
					FileInfo? info;
					while ((info = enumerator.next_file (null)) != null) {
						var child = file.get_child (info.get_name ());
						remove_directory_recursive (child);
					}
				}
				file.delete (null);
				return true;
			} catch (Error e) {
				warning ("Failed to delete '%s': %s", file.get_parse_name (), e.message);
				return false;
			}
		}

		/**
		 * Recursively copies a directory to destination.
		 */
		public static bool copy_directory_recursive (File src, File dest)
		{
			try {
				if (!dest.query_exists ()) {
					dest.make_directory_with_parents (null);
				}
				var enumerator = src.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
				FileInfo? info;
				while ((info = enumerator.next_file (null)) != null) {
					var src_child = src.get_child (info.get_name ());
					var dest_child = dest.get_child (info.get_name ());
					if (src_child.query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY) {
						copy_directory_recursive (src_child, dest_child);
					} else {
						src_child.copy (dest_child, FileCopyFlags.OVERWRITE, null, null);
					}
				}
				return true;
			} catch (Error e) {
				warning ("Failed to copy '%s' to '%s': %s", src.get_parse_name (), dest.get_parse_name (), e.message);
				return false;
			}
		}

		/**
		 * Scans an archive (.zip, .tar.gz, .tar.xz, .theme) for valid dock.theme structures.
		 */
		public static Gee.ArrayList<ThemePackageInfo> scan_archive (string archive_path, out string tmp_dir_out)
		{
			var list = new Gee.ArrayList<ThemePackageInfo> ();
			tmp_dir_out = "";

			try {
				string tmp_dir = DirUtils.make_tmp ("wayplank_theme_XXXXXX");
				tmp_dir_out = tmp_dir;

				string lower = archive_path.down ();
				int exit_status;

				string q_archive = Shell.quote (archive_path);
				string q_tmp = Shell.quote (tmp_dir);

				if (lower.has_suffix (".zip")) {
					Process.spawn_command_line_sync ("unzip -q -o %s -d %s".printf (q_archive, q_tmp), null, null, out exit_status);
				} else if (lower.has_suffix (".tar.gz") || lower.has_suffix (".tgz")) {
					Process.spawn_command_line_sync ("tar -xzf %s -C %s".printf (q_archive, q_tmp), null, null, out exit_status);
				} else if (lower.has_suffix (".tar.xz") || lower.has_suffix (".txz")) {
					Process.spawn_command_line_sync ("tar -xJf %s -C %s".printf (q_archive, q_tmp), null, null, out exit_status);
				} else if (lower.has_suffix (".tar.bz2")) {
					Process.spawn_command_line_sync ("tar -xjf %s -C %s".printf (q_archive, q_tmp), null, null, out exit_status);
				} else if (lower.has_suffix (".theme")) {
					// Standalone .theme file
					var src_file = File.new_for_path (archive_path);
					string theme_name = src_file.get_basename ().replace (".theme", "");
					if (theme_name == "dock" || theme_name == "") {
						theme_name = src_file.get_parent ().get_basename ();
					}
					var t_dir = File.new_for_path (Path.build_filename (tmp_dir, theme_name));
					t_dir.make_directory_with_parents (null);
					src_file.copy (t_dir.get_child ("dock.theme"), FileCopyFlags.OVERWRITE, null, null);
				}

				find_themes_recursive (File.new_for_path (tmp_dir), tmp_dir, archive_path, list);
			} catch (Error e) {
				warning ("Error scanning archive for themes: %s", e.message);
			}

			return list;
		}

		static void find_themes_recursive (File dir, string root_tmp, string archive_path, Gee.ArrayList<ThemePackageInfo> list)
		{
			try {
				var dock_theme = dir.get_child ("dock.theme");
				if (dock_theme.query_exists ()) {
					string dir_path = dir.get_path ();
					string name;
					if (dir_path == root_tmp) {
						var f = File.new_for_path (archive_path);
						name = f.get_basename ();
						string[] exts = { ".tar.gz", ".tar.xz", ".tar.bz2", ".zip", ".tgz", ".txz", ".theme" };
						foreach (var ext in exts) {
							if (name.down ().has_suffix (ext)) {
								name = name.slice (0, name.length - ext.length);
								break;
							}
						}
					} else {
						name = dir.get_basename ();
					}

					bool exists = false;
					foreach (var info in list) {
						if (info.name == name) {
							exists = true;
							break;
						}
					}
					if (!exists) {
						list.add (new ThemePackageInfo (name, dir_path));
					}
					return;
				}

				var enumerator = dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
				FileInfo? info;
				while ((info = enumerator.next_file (null)) != null) {
					var child = dir.get_child (info.get_name ());
					if (child.query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY) {
						find_themes_recursive (child, root_tmp, archive_path, list);
					}
				}
			} catch (Error e) {
				warning ("Error searching themes: %s", e.message);
			}
		}

		/**
		 * Installs a theme into ~/.local/share/wayplank/themes/<theme_name>
		 */
		public static bool install_theme (ThemePackageInfo info, bool overwrite = true)
		{
			Paths.ensure_directory_exists (Paths.AppThemeFolder);
			var target_dir = Paths.AppThemeFolder.get_child (info.name);
			if (target_dir.query_exists ()) {
				if (!overwrite)
					return false;
				remove_directory_recursive (target_dir);
			}
			return copy_directory_recursive (File.new_for_path (info.source_dir), target_dir);
		}

		/**
		 * Cleans up temporary extraction folder.
		 */
		public static void cleanup_tmp (string tmp_dir)
		{
			if (tmp_dir != "" && tmp_dir.contains ("wayplank_theme_")) {
				remove_directory_recursive (File.new_for_path (tmp_dir));
			}
		}
	}
}

