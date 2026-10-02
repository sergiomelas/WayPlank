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
	 * Wayland-native process matcher.
	 */
	public class Matcher : GLib.Object
	{

		public signal void active_window_changed (string? old_win_id, string? new_win_id);
		public signal void window_opened (string win_id);
		public signal void window_closed (string win_id);

		public signal void active_application_changed (string? old_app_id, string? new_app_id);
		public signal void application_opened (string app_id);
		public signal void application_closed (string app_id);
		public signal void processes_changed ();

		static Matcher? matcher = null;

		public static Matcher get_default ()
		{
			if (matcher == null)
				matcher = new Matcher ();
			return matcher;
		}

		Gee.HashMap<string, Gee.HashSet<int>> app_pids;
		Gee.HashSet<string> active_apps;

		private Matcher ()
		{
			app_pids = new Gee.HashMap<string, Gee.HashSet<int>> ();
			active_apps = new Gee.HashSet<string> ();
		}

		uint scan_timer_id = 0U;

		construct
		{
			// Only scan /proc if no compositor window-control is providing live state
			if (!WindowControl.has_state ()) {
				scan_timer_id = GLib.Timeout.add_seconds (3, () => {
					if (!WindowControl.has_state ())
						scan_running_applications ();
					return true;
				});
			}

			WindowControl.get_default ().state_changed.connect (() => {
				if (WindowControl.has_state () && scan_timer_id > 0U) {
					GLib.Source.remove (scan_timer_id);
					scan_timer_id = 0U;
				}
			});
		}

		~Matcher ()
		{
			if (scan_timer_id > 0U) {
				GLib.Source.remove (scan_timer_id);
				scan_timer_id = 0U;
			}
			matcher = null;
		}

		private void scan_running_applications ()
		{
			try {
				var dir = GLib.Dir.open ("/proc", 0);
				string? name = null;
				Gee.HashSet<int> current_pids = new Gee.HashSet<int> ();
				var my_uid = Posix.getuid ();

				while ((name = dir.read_name ()) != null) {
					int pid = int.parse (name);
					if (pid <= 0)
						continue;

					Posix.Stat st;
					if (Posix.stat ("/proc/%s".printf (name), out st) != 0 || st.st_uid != my_uid)
						continue;

					current_pids.add (pid);
					string comm_path = "/proc/%s/comm".printf (name);
					string comm = "";
					if (GLib.FileUtils.get_contents (comm_path, out comm)) {
						comm = comm.strip ();
						if (comm != "" && comm != "wayplank") {
							// Check common desktop file ID patterns generically
							string[] possible_ids = {
								comm + ".desktop",
								"org.kde." + comm + ".desktop",
								"org.gnome." + comm + ".desktop",
								comm.down () + ".desktop"
							};

							foreach (var id in possible_ids) {
								if (desktop_file_exists_in_system (id)) {
									register_process_for_app (id, pid);
									break;
								}
							}
						}
					}
				}

				// Remove PIDs that no longer exist in /proc
				foreach (var app_id in app_pids.keys.to_array ()) {
					var pids = app_pids.get (app_id);
					var dead_pids = new Gee.HashSet<int> ();
					foreach (var pid in pids) {
						if (!current_pids.contains (pid)) {
							dead_pids.add (pid);
						}
					}
					foreach (var dead in dead_pids) {
						unregister_process_for_app (app_id, dead);
					}
				}

				processes_changed ();
			} catch (Error e) {
				warning ("Errors during Process Scan: %s", e.message);
			}
		}

		private bool desktop_file_exists_in_system (string app_id)
		{
			var search_dirs = new Gee.ArrayList<File> ();
			search_dirs.add (Paths.DataHomeFolder.get_child ("applications"));
			foreach (var folder in Paths.DataDirFolders) {
				search_dirs.add (folder.get_child ("applications"));
			}

			foreach (var app_dir in search_dirs) {
				var desktop_file = app_dir.get_child (app_id);
				if (desktop_file.query_exists ()) {
					// Filter system daemons, KDED/KWallet services, and hidden apps
					try {
						var key_file = new GLib.KeyFile ();
						key_file.load_from_file (desktop_file.get_path (), GLib.KeyFileFlags.NONE);
						
						if (key_file.has_key ("Desktop Entry", "NoDisplay") && key_file.get_boolean ("Desktop Entry", "NoDisplay"))
							return false;
						if (key_file.has_key ("Desktop Entry", "Hidden") && key_file.get_boolean ("Desktop Entry", "Hidden"))
							return false;
							
						string[] categories = {};
						if (key_file.has_key ("Desktop Entry", "Categories"))
							categories = key_file.get_string_list ("Desktop Entry", "Categories");
							
						// Discard system services or pure daemons without user categories
						bool is_service = false;
						foreach (var cat in categories) {
							if (cat == "Core" || cat == "System" || cat == "Settings") {
								// Check whether it is a valid settings app or a pure service
								if (app_id.contains ("kded") || app_id.contains ("kwallet") || app_id.contains ("at-spi")) {
									is_service = true;
								}
							}
						}
						if (is_service)
							return false;

						return true;
					} catch (Error e) {
						return true; // Fallback if parsing fails but the file exists
					}
				}
			}
			return false;
		}

		public Gee.ArrayList<string> active_launchers ()
		{
			var list = new Gee.ArrayList<string> ();
			foreach (var app in active_apps) {
				list.add (app);
			}
			return list;
		}

		public bool is_launcher_running (string launcher_uri)
		{
			try {
				var launcher_file = File.new_for_uri (launcher_uri);
				var launcher_name = launcher_file.get_basename ().down ();
				var keyfile = new KeyFile ();
				keyfile.load_from_file (launcher_file.get_path (), KeyFileFlags.NONE);

				var candidates = new Gee.ArrayList<string> ();
				candidates.add (launcher_name);

				var exec = keyfile.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
				var parts = exec.split (" ");
				var executable = parts[0].replace ("\"", "").replace ("'", "");
				if (executable != "") {
					candidates.add (File.new_for_path (executable).get_basename ().down ());
					add_script_candidates (executable, candidates, 0);
				}

				string? specific_arg = null;
				for (int i = 1; i < parts.length; i++) {
					var p = parts[i].strip ().replace ("\"", "").replace ("'", "");
					if (p != "" && !p.has_prefix ("-") && !p.has_prefix ("%")) {
						var basename = File.new_for_path (p).get_basename ().down ();
						if (basename != "" && basename != ".") {
							specific_arg = basename;
							break;
						}
					}
				}

				var my_uid = Posix.getuid ();
				var dir = GLib.Dir.open ("/proc", 0);
				string? name = null;
				while ((name = dir.read_name ()) != null) {
					int pid = int.parse (name);
					if (pid <= 0)
						continue;

					Posix.Stat st;
					if (Posix.stat ("/proc/%s".printf (name), out st) != 0 || st.st_uid != my_uid)
						continue;

					string comm = "";
					string cmdline = "";
					GLib.FileUtils.get_contents ("/proc/%s/comm".printf (name), out comm);
					GLib.FileUtils.get_contents ("/proc/%s/cmdline".printf (name), out cmdline);
					comm = comm.strip ().down ();
					var cmdline_down = cmdline.replace ("\0", " ").down ();

					if (specific_arg != null && specific_arg != "") {
						if (cmdline_down.contains (specific_arg))
							return true;
						continue;
					}

					var argv0 = cmdline_down.split (" ")[0];
					var bin_name = File.new_for_path (argv0).get_basename ();
					foreach (var candidate in candidates) {
						if (candidate != "" && (comm == candidate || bin_name == candidate))
							return true;
					}
				}
			} catch (Error e) {
				debug ("Unable to match launcher process '%s': %s", launcher_uri, e.message);
			}

			return false;
		}

		void add_script_candidates (string script_path, Gee.ArrayList<string> candidates, int depth)
		{
			if (depth >= 4 || !File.new_for_path (script_path).query_exists ())
				return;

			string script = "";
			try {
				if (!GLib.FileUtils.get_contents (script_path, out script) || !script.has_prefix ("#!"))
					return;
			} catch (FileError e) {
				debug ("Unable to read launcher script '%s': %s", script_path, e.message);
				return;
			}

			var script_dir = File.new_for_path (script_path).get_parent ();
			foreach (var token in script.split (" ")) {
				var path = token.strip ().replace ("\"", "").replace ("'", "").replace ("\n", "");
				if (path.has_prefix ("$HERE/"))
					path = script_dir.get_child (path.substring (6)).get_path ();
				if (!path.has_prefix ("/"))
					continue;

				var candidate = File.new_for_path (path).get_basename ().down ();
				if (candidate == null || candidate == "")
					continue;

				candidates.add (candidate);
				add_script_candidates (path, candidates, depth + 1);
			}
		}

		public string? app_for_uri (string uri)
		{
			string launcher;
			try {
				launcher = Filename.from_uri (uri);
			} catch (ConvertError e) {
				warning (e.message);
				return null;
			}

			return launcher;
		}

		public void set_favorites (Gee.ArrayList<string> favs)
		{
			// Kept for backward compatibility with docklet provider calls
		}

		public void register_process_for_app (string app_id, int pid)
		{
			if (!app_pids.has_key (app_id)) {
				app_pids.set (app_id, new Gee.HashSet<int> ());
			}
			app_pids.get (app_id).add (pid);

			if (active_apps.add (app_id)) {
				application_opened (app_id);
			}
		}

		public void unregister_process_for_app (string app_id, int pid)
		{
			if (app_pids.has_key (app_id)) {
				var pids = app_pids.get (app_id);
				pids.remove (pid);
				if (pids.size == 0) {
					app_pids.unset (app_id);
					if (active_apps.remove (app_id)) {
						application_closed (app_id);
					}
				}
			}
		}
	}
}
