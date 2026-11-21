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
	/**
	 * Non-destructive persistent store for user-defined shortcut display names
	 * shared across pinned dock icons and folder drawer launchers (launcher-names.ini).
	 */
	public class CustomNameService : GLib.Object
	{
		const string CONFIG_FILENAME = "launcher-names.ini";
		const string GROUP_NAMES = "Names";

		static CustomNameService? instance = null;

		Gee.HashMap<string, string> names_by_lower_uri;
		Gee.HashMap<string, string> raw_key_by_lower_uri;
		bool loaded = false;

		public signal void name_changed (string launcher_uri);

		public static CustomNameService get_default ()
		{
			if (instance == null)
				instance = new CustomNameService ();
			return instance;
		}

		CustomNameService ()
		{
			names_by_lower_uri = new Gee.HashMap<string, string> ();
			raw_key_by_lower_uri = new Gee.HashMap<string, string> ();
		}

		GLib.File get_config_file ()
		{
			return Paths.AppConfigFolder.get_child (CONFIG_FILENAME);
		}

		static string normalize_uri_key (string uri)
		{
			return uri.strip ().down ();
		}

		void ensure_loaded ()
		{
			if (loaded)
				return;
			loaded = true;

			var file = get_config_file ();
			string? path = file.get_path ();
			if (path == null || !FileUtils.test (path, FileTest.IS_REGULAR))
				return;

			var kf = new KeyFile ();
			try {
				kf.load_from_file (path, KeyFileFlags.NONE);
				if (!kf.has_group (GROUP_NAMES))
					return;
				foreach (unowned string key in kf.get_keys (GROUP_NAMES)) {
					string val = kf.get_string (GROUP_NAMES, key).strip ();
					string low = normalize_uri_key (key);
					if (low.length > 0 && val.length > 0) {
						names_by_lower_uri.set (low, val);
						raw_key_by_lower_uri.set (low, key);
					}
				}
			} catch (Error e) {
				warning ("CustomNameService: failed to load %s: %s", path, e.message);
			}
		}

		void save_to_disk ()
		{
			var file = get_config_file ();
			string? path = file.get_path ();
			if (path == null)
				return;

			if (names_by_lower_uri.size == 0) {
				if (FileUtils.test (path, FileTest.IS_REGULAR))
					FileUtils.unlink (path);
				return;
			}

			var kf = new KeyFile ();
			foreach (var entry in names_by_lower_uri.entries) {
				string raw_key = raw_key_by_lower_uri.get (entry.key) ?? entry.key;
				kf.set_string (GROUP_NAMES, raw_key, entry.value);
			}

			try {
				Paths.ensure_directory_exists (Paths.AppConfigFolder);
				kf.save_to_file (path);
			} catch (Error e) {
				warning ("CustomNameService: failed to save %s: %s", path, e.message);
			}
		}

		public string get_custom_name (string? launcher_uri)
		{
			if (launcher_uri == null || launcher_uri.strip ().length == 0)
				return "";
			ensure_loaded ();
			string low = normalize_uri_key (launcher_uri);
			return names_by_lower_uri.get (low) ?? "";
		}

		public void set_custom_name (string launcher_uri, string custom_name)
		{
			string clean_uri = launcher_uri.strip ();
			if (clean_uri.length == 0)
				return;
			ensure_loaded ();

			string low = normalize_uri_key (clean_uri);
			string clean_name = custom_name.strip ();
			string prev = names_by_lower_uri.get (low) ?? "";

			if (clean_name.length == 0) {
				if (prev.length == 0)
					return;
				names_by_lower_uri.unset (low);
				raw_key_by_lower_uri.unset (low);
			} else {
				if (prev == clean_name)
					return;
				names_by_lower_uri.set (low, clean_name);
				raw_key_by_lower_uri.set (low, clean_uri);
			}

			save_to_disk ();
			name_changed (clean_uri);
		}

		public void transfer_custom_name (string old_uri, string new_uri)
		{
			string clean_old = old_uri.strip ();
			string clean_new = new_uri.strip ();
			if (clean_old.length == 0 || clean_new.length == 0)
				return;
			if (normalize_uri_key (clean_old) == normalize_uri_key (clean_new))
				return;

			string existing = get_custom_name (clean_old);
			if (existing.length > 0)
				set_custom_name (clean_new, existing);
		}
	}
}
