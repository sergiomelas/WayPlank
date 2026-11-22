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
	 * Non-destructive persistent store for user-defined shortcut icons
	 * shared across pinned dock icons and folder drawer launchers (launcher-icons.ini).
	 */
	public class CustomIconService : GLib.Object
	{
		const string CONFIG_FILENAME = "launcher-icons.ini";
		const string GROUP_ICONS = "Icons";

		static CustomIconService? instance = null;

		Gee.HashMap<string, string> icons_by_lower_uri;
		Gee.HashMap<string, string> raw_key_by_lower_uri;
		bool loaded = false;

		public signal void icon_changed (string launcher_uri);

		public static CustomIconService get_default ()
		{
			if (instance == null)
				instance = new CustomIconService ();
			return instance;
		}

		CustomIconService ()
		{
			icons_by_lower_uri = new Gee.HashMap<string, string> ();
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
				if (!kf.has_group (GROUP_ICONS))
					return;
				foreach (unowned string key in kf.get_keys (GROUP_ICONS)) {
					string val = kf.get_string (GROUP_ICONS, key).strip ();
					string low = normalize_uri_key (key);
					if (low.length > 0 && val.length > 0) {
						icons_by_lower_uri.set (low, val);
						raw_key_by_lower_uri.set (low, key);
					}
				}
			} catch (Error e) {
				warning ("CustomIconService: failed to load %s: %s", path, e.message);
			}
		}

		void save_to_disk ()
		{
			var file = get_config_file ();
			string? path = file.get_path ();
			if (path == null)
				return;

			if (icons_by_lower_uri.size == 0) {
				if (FileUtils.test (path, FileTest.IS_REGULAR))
					FileUtils.unlink (path);
				return;
			}

			var kf = new KeyFile ();
			foreach (var entry in icons_by_lower_uri.entries) {
				string raw_key = raw_key_by_lower_uri.get (entry.key) ?? entry.key;
				kf.set_string (GROUP_ICONS, raw_key, entry.value);
			}

			try {
				Paths.ensure_directory_exists (Paths.AppConfigFolder);
				kf.save_to_file (path);
			} catch (Error e) {
				warning ("CustomIconService: failed to save %s: %s", path, e.message);
			}
		}

		public string get_custom_icon (string? launcher_uri)
		{
			if (launcher_uri == null || launcher_uri.strip ().length == 0)
				return "";
			ensure_loaded ();
			string low = normalize_uri_key (launcher_uri);
			return icons_by_lower_uri.get (low) ?? "";
		}

		public void set_custom_icon (string launcher_uri, string icon_token)
		{
			string clean_uri = launcher_uri.strip ();
			if (clean_uri.length == 0)
				return;
			ensure_loaded ();

			string low = normalize_uri_key (clean_uri);
			string clean_icon = icon_token.strip ();
			string prev = icons_by_lower_uri.get (low) ?? "";

			if (clean_icon.length == 0) {
				if (prev.length == 0)
					return;
				icons_by_lower_uri.unset (low);
				raw_key_by_lower_uri.unset (low);
			} else {
				if (prev == clean_icon)
					return;
				icons_by_lower_uri.set (low, clean_icon);
				raw_key_by_lower_uri.set (low, clean_uri);
			}

			save_to_disk ();
			icon_changed (clean_uri);
		}

		public void transfer_custom_icon (string old_uri, string new_uri)
		{
			string clean_old = old_uri.strip ();
			string clean_new = new_uri.strip ();
			if (clean_old.length == 0 || clean_new.length == 0)
				return;
			if (normalize_uri_key (clean_old) == normalize_uri_key (clean_new))
				return;
			ensure_loaded ();

			string old_low = normalize_uri_key (clean_old);
			string existing = icons_by_lower_uri.get (old_low) ?? "";
			if (existing.length == 0)
				return;

			string new_low = normalize_uri_key (clean_new);
			icons_by_lower_uri.unset (old_low);
			raw_key_by_lower_uri.unset (old_low);
			icons_by_lower_uri.set (new_low, existing);
			raw_key_by_lower_uri.set (new_low, clean_new);
			save_to_disk ();
			icon_changed (clean_old);
			icon_changed (clean_new);
		}
	}
}
