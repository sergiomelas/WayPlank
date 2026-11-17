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
	 * Agnostic fallback process matcher used when no compositor window backend state is active.
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

		public static void cleanup_if_active ()
		{
			if (matcher != null) {
				var inst = (owned) matcher;
				inst.cleanup ();
			}
		}

		// CRITICAL GOBJECT LIFECYCLE INITIALIZATION:
		// These collections MUST be initialized inline at field declaration.
		// In GObject/Vala, the 'construct {}' block executes BEFORE the 'Matcher ()'
		// constructor body. Delaying initialization to Matcher () causes scan_running_applications ()
		// to trigger critical assertions (gee_abstract_map_has_key: assertion 'self != NULL').
		Gee.HashMap<string, Gee.HashSet<int>> app_pids = new Gee.HashMap<string, Gee.HashSet<int>> ();
		Gee.HashSet<string> active_apps = new Gee.HashSet<string> ();
		Gee.HashSet<int> known_pids = new Gee.HashSet<int> ();
		bool initial_scan_done = false;
		bool is_cleaned_up = false;
		uint scan_timer_id = 0U;

		private Matcher ()
		{
		}

		static void schedule_scan_timer (Matcher target)
		{
			if (target.scan_timer_id > 0U)
				return;
			GLib.WeakRef weak_self = GLib.WeakRef (target);
			target.scan_timer_id = GLib.Timeout.add_seconds (5, () => {
				var self = (Matcher?) weak_self.get ();
				if (self == null || self.is_cleaned_up)
					return GLib.Source.REMOVE;
				if (!Hal.Windows.has_state ())
					self.scan_running_applications ();
				return GLib.Source.CONTINUE;
			});
		}

		construct
		{
			// Only scan user processes if no compositor window backend is providing live state
			if (!Hal.Windows.has_state ()) {
				scan_running_applications ();
				schedule_scan_timer (this);
			}

			Hal.Windows.state_changed.connect (on_window_control_state_changed);
		}

		void on_window_control_state_changed ()
		{
			if (is_cleaned_up)
				return;
			if (Hal.Windows.has_state () && scan_timer_id > 0U) {
				GLib.Source.remove (scan_timer_id);
				scan_timer_id = 0U;
			} else if (!Hal.Windows.has_state () && scan_timer_id == 0U) {
				scan_running_applications ();
				schedule_scan_timer (this);
			}
		}

		public void cleanup ()
		{
			if (is_cleaned_up)
				return;
			is_cleaned_up = true;
			Hal.Windows.state_changed.disconnect (on_window_control_state_changed);
			if (scan_timer_id > 0U) {
				GLib.Source.remove (scan_timer_id);
				scan_timer_id = 0U;
			}
		}

		~Matcher ()
		{
			cleanup ();
		}

		static string basename_any_slash (string raw)
		{
			string s = raw.replace ("\\", "/");
			while (s.length > 1 && s.has_suffix ("/"))
				s = s.substring (0, s.length - 1);
			int idx = s.last_index_of_char ('/');
			return idx >= 0 ? s.substring (idx + 1) : s;
		}

		private string resolve_trackable_launcher_uri (string comm)
		{
			string resolved = Hal.Apps.resolve_launcher_uri (comm);
			if (resolved == "")
				resolved = Hal.Apps.resolve_launcher_uri (comm.down ());
			if (resolved == "") {
				var df = ApplicationDiscovery.get_default ().desktop_file_for_id (comm);
				if (df != null)
					resolved = df.get_uri ();
			}
			if (resolved == "")
				return "";

			var desc = Hal.Apps.load_launcher (resolved);
			if (desc == null || desc.is_non_app_launcher || desc.is_nodisplay || desc.is_hidden)
				return "";

			string low_id = desc.base_id.down ();
			foreach (var cat in desc.categories) {
				if (cat == "Core" || cat == "System" || cat == "Settings") {
					if (low_id.contains ("kded") || low_id.contains ("kwallet") || low_id.contains ("at-spi"))
						return "";
				}
			}

			return desc.uri != "" ? desc.uri : resolved;
		}

		private void scan_running_applications ()
		{
			var snapshots = Hal.Apps.scan_user_processes ();
			var current_pids = new Gee.HashSet<int> ();

			foreach (var snap in snapshots) {
				if (snap.pid <= 0 || !snap.uid_matches_self)
					continue;

				current_pids.add (snap.pid);
				if (!initial_scan_done || !known_pids.contains (snap.pid)) {
					string comm = snap.executable_comm.strip ();
					if (comm != "" && !Hal.Apps.is_self_launcher (comm) && !ApplicationDiscovery.is_ignored_app (comm)) {
						string app_uri = resolve_trackable_launcher_uri (comm);
						if (app_uri != "")
							register_process_for_app (app_uri, snap.pid);
					}
				}
			}

			// Remove PIDs that are no longer alive
			foreach (var app_id in app_pids.keys.to_array ()) {
				var pids = app_pids.get (app_id);
				var dead_pids = new Gee.HashSet<int> ();
				foreach (var pid in pids) {
					if (!current_pids.contains (pid))
						dead_pids.add (pid);
				}
				foreach (var dead in dead_pids)
					unregister_process_for_app (app_id, dead);
			}

			bool pids_changed = !initial_scan_done || (current_pids.size != known_pids.size);
			if (!pids_changed) {
				foreach (var pid in current_pids) {
					if (!known_pids.contains (pid)) {
						pids_changed = true;
						break;
					}
				}
			}

			if (pids_changed) {
				known_pids.clear ();
				known_pids.add_all (current_pids);
				initial_scan_done = true;
				processes_changed ();
			}
		}

		public Gee.ArrayList<string> active_launchers ()
		{
			var list = new Gee.ArrayList<string> ();
			foreach (var app in active_apps)
				list.add (app);
			return list;
		}

		public bool is_launcher_running (string launcher_uri)
		{
			if (launcher_uri == "")
				return false;

			var desc = Hal.Apps.load_launcher (launcher_uri);
			if (desc == null)
				return false;

			var swmc = desc.startup_wm_class_or_aumid.strip ().down ();
			if (swmc.has_prefix ("crx_") || swmc.contains ("_crx_"))
				return false;

			var candidates = new Gee.ArrayList<string> ();
			if (desc.base_id != "")
				candidates.add (desc.base_id.down ());
			string stem = Hal.Apps.launcher_id_stem (launcher_uri).down ();
			if (stem != "" && !candidates.contains (stem))
				candidates.add (stem);

			var exec = desc.exec_command.strip ();
			string[] parts = exec != "" ? Hal.Runtime.parse_command_argv (exec) : new string[] {};
			if (parts.length == 0 && exec != "")
				parts = exec.split (" ");

			if (parts.length > 0) {
				var executable = Hal.Runtime.expand_path_variables (parts[0]).replace ("\"", "").replace ("'", "");
				if (executable != "") {
					string exe_base = basename_any_slash (executable).down ();
					if (exe_base != "" && !candidates.contains (exe_base))
						candidates.add (exe_base);
					add_script_candidates (executable, candidates, 0);
				}
			}

			string? specific_arg = null;
			for (int i = 1; i < parts.length; i++) {
				var p = Hal.Runtime.expand_path_variables (parts[i]).strip ().replace ("\"", "").replace ("'", "");
				if (p.has_prefix ("--app-id=") || p.has_prefix ("--app="))
					return false;
				if (p.has_prefix ("--profile-directory=")) {
					specific_arg = p.slice (20, p.length).down ();
					break;
				}
				bool is_field_code = (p.length == 2 && p[0] == '%');
				if (p != "" && !p.has_prefix ("-") && !is_field_code) {
					var basename = basename_any_slash (p).down ();
					if (basename != "" && basename != ".") {
						specific_arg = basename;
						break;
					}
				}
			}

			var snapshots = Hal.Apps.scan_user_processes ();
			foreach (var snap in snapshots) {
				if (snap.pid <= 0 || !snap.uid_matches_self)
					continue;

				var comm = snap.executable_comm.strip ().down ();
				var cmdline_down = snap.full_cmdline.down ();

				if (specific_arg != null && specific_arg != "") {
					if (cmdline_down.contains (specific_arg))
						return true;
					continue;
				}

				string argv0 = snap.cmdline_argv.length > 0
					? snap.cmdline_argv[0].down ()
					: cmdline_down.split (" ")[0];
				var bin_name = basename_any_slash (argv0);
				foreach (var candidate in candidates) {
					if (candidate != "" && (comm == candidate || bin_name == candidate || (comm.length >= 15 && candidate.has_prefix (comm))))
						return true;
				}
			}

			return false;
		}

		void add_script_candidates (string script_exe, Gee.ArrayList<string> candidates, int depth)
		{
			if (depth >= 4 || script_exe == "")
				return;

			string resolved_path = "";
			string script = Hal.Apps.read_wrapper_script (script_exe, out resolved_path);
			if (script == "" || resolved_path == "" || !script.has_prefix ("#!"))
				return;

			var script_dir = File.new_for_path (resolved_path).get_parent ();
			foreach (var token in script.split (" ")) {
				var path = token.strip ().replace ("\"", "").replace ("'", "").replace ("\n", "");
				if (path.has_prefix ("$HERE/") && script_dir != null) {
					string? joined = script_dir.get_child (path.substring (6)).get_path ();
					if (joined != null)
						path = joined;
				}
				if (!Path.is_absolute (path))
					continue;

				var candidate = basename_any_slash (path).down ();
				if (candidate == "")
					continue;

				if (!candidates.contains (candidate))
					candidates.add (candidate);
				add_script_candidates (path, candidates, depth + 1);
			}
		}

		public string? app_for_uri (string uri)
		{
			if (!uri.has_prefix ("file://"))
				return uri != "" ? uri : null;
			try {
				return Filename.from_uri (uri);
			} catch (ConvertError e) {
				warning (e.message);
				return null;
			}
		}

		public void set_favorites (Gee.ArrayList<string> favs)
		{
			// Kept for backward compatibility with docklet provider calls
		}

		public void register_process_for_app (string app_id, int pid)
		{
			if (!app_pids.has_key (app_id))
				app_pids.set (app_id, new Gee.HashSet<int> ());
			app_pids.get (app_id).add (pid);

			if (active_apps.add (app_id))
				application_opened (app_id);
		}

		public void unregister_process_for_app (string app_id, int pid)
		{
			if (app_pids.has_key (app_id)) {
				var pids = app_pids.get (app_id);
				pids.remove (pid);
				if (pids.size == 0) {
					app_pids.unset (app_id);
					if (active_apps.remove (app_id))
						application_closed (app_id);
				}
			}
		}
	}
}
