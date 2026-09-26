//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
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
	/**
	 * Discovers applications from desktop entries and compositor window state.
	 */
	public class ApplicationDiscovery : GLib.Object
	{
		static ApplicationDiscovery? instance;
		public signal void changed ();
		Gee.ArrayList<File> indexed_desktop_files;
		Gee.HashMap<string, ApplicationIdentity> identities;
		string last_window_signature = "";
		string[] cached_active_ids = {};
		uint refresh_timer_id = 0U;
		uint change_timer_id = 0U;
		
		public static unowned ApplicationDiscovery get_default ()
		{
			if (instance == null)
				instance = new ApplicationDiscovery ();
			return instance;
		}
		
		ApplicationDiscovery ()
		{
			indexed_desktop_files = new Gee.ArrayList<File> ();
			identities = new Gee.HashMap<string, ApplicationIdentity> ();
			refresh_desktop_index ();
			refresh_timer_id = Timeout.add_seconds (2, () => {
				refresh_desktop_index ();
				return true;
			});
			WindowControl.get_default ().state_changed.connect (schedule_changed);
		}

		~ApplicationDiscovery ()
		{
			if (refresh_timer_id > 0U)
				Source.remove (refresh_timer_id);
			if (change_timer_id > 0U)
				Source.remove (change_timer_id);
		}

		void schedule_changed ()
		{
			if (change_timer_id > 0U)
				return;
			change_timer_id = Timeout.add (50, () => {
				change_timer_id = 0U;
				changed ();
				return false;
			});
		}
		
		public Gee.ArrayList<WindowInfo> windows_for_launcher (string launcher_uri)
		{
			var result = new Gee.ArrayList<WindowInfo> ();
			var identity = identity_for_launcher (launcher_uri);
			if (identity == null)
				return result;
			foreach (var window in WindowControl.get_windows ())
				if (identity.matches (window))
					result.add (window);
			return result;
		}
		
		public File? desktop_file_for_id (string app_id)
		{
			var normalized = ApplicationIdentity.normalize (app_id);
			foreach (var file in indexed_desktop_files)
				if (ApplicationIdentity.normalize (file.get_basename ()) == normalized)
					return file;
			return null;
		}
		
		public string[] active_launcher_ids ()
		{
			var windows = WindowControl.get_windows ();
			var signature_builder = new StringBuilder ("");
			foreach (var window in windows)
				signature_builder.append ("%s|%s|%s|%s;".printf (window.Id, window.ApplicationId, window.ResourceClass, window.ResourceName));
			var signature = signature_builder.str;
			if (signature == last_window_signature)
				return cached_active_ids;

			var best_by_window = new Gee.HashMap<string, string> ();
			var score_by_window = new Gee.HashMap<string, int> ();
			foreach (var window in windows) {
				var best_score = 0;
				string? best_id = null;
				foreach (var entry in identities.entries) {
					var score = entry.value.match_score (window);
					if (score > best_score) {
						best_score = score;
						best_id = entry.key;
					}
				}
				if (best_id != null) {
					best_by_window.set (window.Id, best_id);
					score_by_window.set (window.Id, best_score);
				}
			}

			var result = new Gee.ArrayList<string> ();
			foreach (var id in best_by_window.values)
				if (!result.contains (id))
					result.add (id);
			last_window_signature = signature;
			cached_active_ids = result.to_array ();
			return cached_active_ids;
		}
		
		public ApplicationIdentity? identity_for_launcher (string launcher_uri)
		{
			var file = File.new_for_uri (launcher_uri);
			if (!file.query_exists ())
				return null;

			var id = file.get_basename ();
			if (identities.has_key (id))
				return identities.get (id);
			var identity = new ApplicationIdentity (file);
			identities.set (id, identity);
			return identity;
		}
		
		Gee.ArrayList<File> application_folders ()
		{
			var folders = new Gee.ArrayList<File> ();
			folders.add (Paths.DataHomeFolder.get_child ("applications"));
			foreach (var folder in Paths.DataDirFolders)
				folders.add (folder.get_child ("applications"));
			return folders;
		}
		
		Gee.ArrayList<File> desktop_files ()
		{
			var result = new Gee.ArrayList<File> ();
			var seen_ids = new Gee.HashSet<string> ();
			foreach (var folder in application_folders ()) {
				if (!folder.query_exists ())
					continue;
				try {
					var enumerator = folder.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
					FileInfo info;
					while ((info = enumerator.next_file ()) != null) {
						if (!info.get_name ().has_suffix (".desktop"))
							continue;
						var file = folder.get_child (info.get_name ());
						var id = ApplicationIdentity.normalize (info.get_name ());
						var self_id = ApplicationIdentity.normalize (Paths.AppName + ".desktop");
						if (id == self_id || seen_ids.contains (id) || !is_visible_application (file))
							continue;
						seen_ids.add (id);
						result.add (file);
					}
				} catch (Error e) {
					debug ("Unable to enumerate application folder '%s': %s", folder.get_path (), e.message);
				}
			}
			return result;
		}

		bool is_visible_application (File file)
		{
			try {
				var key_file = new KeyFile ();
				key_file.load_from_file (file.get_path (), KeyFileFlags.NONE);
				if (!key_file.has_key (KeyFileDesktop.GROUP, "Type")
					|| key_file.get_string (KeyFileDesktop.GROUP, "Type") != "Application")
					return false;
				if (key_file.has_key (KeyFileDesktop.GROUP, "Hidden")
					&& key_file.get_boolean (KeyFileDesktop.GROUP, "Hidden"))
					return false;
				if (key_file.has_key (KeyFileDesktop.GROUP, "NoDisplay")
					&& key_file.get_boolean (KeyFileDesktop.GROUP, "NoDisplay"))
					return false;

				var desktop = GLib.Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
				if (key_file.has_key (KeyFileDesktop.GROUP, "OnlyShowIn")) {
					var allowed = key_file.get_string_list (KeyFileDesktop.GROUP, "OnlyShowIn");
					bool matches = false;
					foreach (var name in allowed)
						if (desktop.down ().contains (name.down ()))
							matches = true;
					if (!matches)
						return false;
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, "NotShowIn"))
					foreach (var name in key_file.get_string_list (KeyFileDesktop.GROUP, "NotShowIn"))
						if (desktop.down ().contains (name.down ()))
							return false;

				if (key_file.has_key (KeyFileDesktop.GROUP, "TryExec")) {
					var try_exec = key_file.get_string (KeyFileDesktop.GROUP, "TryExec").strip ();
					if (try_exec != "" && File.new_for_path (try_exec).query_exists () == false
						&& GLib.Environment.find_program_in_path (try_exec) == null)
						return false;
				}
				return true;
			} catch (Error e) {
				return false;
			}
		}

		void refresh_desktop_index ()
		{
			var next = desktop_files ();
			var changed_index = (next.size != indexed_desktop_files.size);
			if (!changed_index) {
				foreach (var file in next) {
					bool found = false;
					foreach (var old_file in indexed_desktop_files)
						if (old_file.equal (file)) {
							found = true;
							break;
						}
					if (!found) {
						changed_index = true;
						break;
					}
				}
			}
			if (!changed_index)
				return;
			indexed_desktop_files = next;
			identities.clear ();
			foreach (var file in indexed_desktop_files)
				identities.set (file.get_basename (), new ApplicationIdentity (file));
			last_window_signature = "";
			changed ();
		}
	}
}
