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
	/**
	 * Discovers applications from desktop entries and compositor window state.
	 */
	public class ApplicationDiscovery : GLib.Object
	{
		static ApplicationDiscovery? instance;
		static Gee.HashMap<int, string>? pid_cmdline_cache;
		static Gee.HashMap<int, string>? pid_comm_cache;
		static Gee.HashMap<string, bool>? desktop_exec_cache;
		public signal void changed ();
		Gee.ArrayList<File> indexed_desktop_files;
		Gee.HashMap<string, ApplicationIdentity> identities;
		Gee.HashMap<string, ApplicationIdentity> uri_identities;
		Gee.HashMap<string, ApplicationIdentity> raw_uri_identities;
		Gee.HashMap<string, File> desktop_files_by_norm_id;
		Gee.ArrayList<ApplicationIdentity> web_app_identities;
		Gee.ArrayList<ApplicationIdentity> specialized_exec_identities;
		Gee.HashSet<string> suppressed_nodisplay_tokens;
		Gee.HashSet<string> pinned_launcher_uris;
		Gee.HashSet<string> dock_drawer_file_uris;
		Gee.HashSet<string> drawer_file_uris;
		Gee.HashMap<string, string> launcher_profile_hints;
		Gee.HashMap<string, string> disk_profile_hints;
		Gee.HashMap<int, string> item_profile_uris;
		Gee.HashMap<int, string> item_profile_values;
		int next_profile_reg_id = 0;
		Gee.HashSet<string> monitored_folder_uris;
		Gee.ArrayList<FileMonitor> folder_monitors;
		string last_window_signature = "";
		string[] cached_active_ids = {};
		uint debounce_timer_id = 0U;
		uint change_timer_id = 0U;
		bool initial_gc_done = false;
		
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
			uri_identities = new Gee.HashMap<string, ApplicationIdentity> ();
			raw_uri_identities = new Gee.HashMap<string, ApplicationIdentity> ();
			desktop_files_by_norm_id = new Gee.HashMap<string, File> ();
			web_app_identities = new Gee.ArrayList<ApplicationIdentity> ();
			specialized_exec_identities = new Gee.ArrayList<ApplicationIdentity> ();
			suppressed_nodisplay_tokens = new Gee.HashSet<string> ();
			pinned_launcher_uris = new Gee.HashSet<string> ();
			dock_drawer_file_uris = new Gee.HashSet<string> ();
			drawer_file_uris = new Gee.HashSet<string> ();
			launcher_profile_hints = new Gee.HashMap<string, string> ();
			disk_profile_hints = new Gee.HashMap<string, string> ();
			item_profile_uris = new Gee.HashMap<int, string> ();
			item_profile_values = new Gee.HashMap<int, string> ();
			monitored_folder_uris = new Gee.HashSet<string> ();
			folder_monitors = new Gee.ArrayList<FileMonitor> ();
			refresh_desktop_index ();
			ensure_folder_monitors ();

			WindowControl.get_default ().state_changed.connect (schedule_changed);
		}

		bool recompute_effective_profile_hints ()
		{
			var next_hints = new Gee.HashMap<string, string> ();
			foreach (var e in disk_profile_hints.entries)
				next_hints.set (e.key, e.value);
			foreach (var e in item_profile_uris.entries) {
				var prof = item_profile_values.get (e.key) ?? "";
				if (e.value != "" && prof != "")
					next_hints.set (e.value, prof);
			}

			bool diff = (next_hints.size != launcher_profile_hints.size);
			if (!diff) {
				foreach (var e in next_hints.entries) {
					if ((launcher_profile_hints.get (e.key) ?? "") != e.value) {
						diff = true;
						break;
					}
				}
			}
			if (diff)
				launcher_profile_hints = next_hints;
			return diff;
		}

		public int update_item_browser_profile (int reg_id, string launcher_uri, string profile)
		{
			if (reg_id <= 0) {
				if (launcher_uri == "" || profile.strip () == "")
					return 0;
				reg_id = ++next_profile_reg_id;
			}

			string prev_uri = item_profile_uris.get (reg_id) ?? "";
			string canonical_uri = "";
			if (launcher_uri != "") {
				canonical_uri = launcher_uri.contains ("://")
					? File.new_for_uri (launcher_uri).get_uri ()
					: File.new_for_path (launcher_uri).get_uri ();
			}
			var clean = profile.strip ();

			if (prev_uri != "" && prev_uri != canonical_uri)
				disk_profile_hints.unset (prev_uri);

			if (canonical_uri == "" || clean == "") {
				if (prev_uri != "")
					disk_profile_hints.unset (prev_uri);
				item_profile_uris.unset (reg_id);
				item_profile_values.unset (reg_id);
			} else {
				disk_profile_hints.unset (canonical_uri);
				item_profile_uris.set (reg_id, canonical_uri);
				item_profile_values.set (reg_id, clean);
			}

			if (recompute_effective_profile_hints ()) {
				rebuild_fast_indexes ();
				last_window_signature = "";
				schedule_changed ();
			}
			return (canonical_uri != "" && clean != "") ? reg_id : 0;
		}

		public void set_launcher_browser_profile (string launcher_uri, string profile)
		{
			if (launcher_uri == "")
				return;
			var canonical_uri = launcher_uri.contains ("://")
				? File.new_for_uri (launcher_uri).get_uri ()
				: File.new_for_path (launcher_uri).get_uri ();
			var clean = profile.strip ();
			if (clean != "")
				disk_profile_hints.set (canonical_uri, clean);
			else
				disk_profile_hints.unset (canonical_uri);
			if (recompute_effective_profile_hints ()) {
				rebuild_fast_indexes ();
				last_window_signature = "";
				schedule_changed ();
			}
		}

		void rebuild_fast_indexes ()
		{
			desktop_files_by_norm_id.clear ();
			foreach (var file in indexed_desktop_files) {
				var norm = ApplicationIdentity.normalize (file.get_basename ());
				if (norm != "" && !desktop_files_by_norm_id.has_key (norm))
					desktop_files_by_norm_id.set (norm, file);
			}

			web_app_identities.clear ();
			specialized_exec_identities.clear ();
			foreach (var identity in identities.values) {
				if (identity.is_web_app ())
					web_app_identities.add (identity);
				var prof_hint = identity.desktop_uri != "" ? launcher_profile_hints.get (identity.desktop_uri) : null;
				if ((identity.is_specialized () || (prof_hint != null && prof_hint != "")) && identity.has_exec)
					specialized_exec_identities.add (identity);
			}
			ApplicationIdentity.prune_locked_launcher_uris (uri_identities.keys);
		}

		void ensure_folder_monitors ()
		{
			foreach (var folder in application_folders ()) {
				if (!folder.query_exists ())
					continue;
				var f_uri = folder.get_uri ();
				if (monitored_folder_uris.contains (f_uri))
					continue;
				try {
					var monitor = folder.monitor_directory (FileMonitorFlags.NONE, null);
					monitor.changed.connect (on_folder_changed);
					folder_monitors.add (monitor);
					monitored_folder_uris.add (f_uri);
				} catch (Error e) {
					debug ("Unable to monitor folder '%s': %s", folder.get_path (), e.message);
				}
			}
		}

		public void refresh_index_now ()
		{
			ensure_folder_monitors ();
			refresh_desktop_index (true);
		}

		~ApplicationDiscovery ()
		{
			WindowControl.get_default ().state_changed.disconnect (schedule_changed);
			if (debounce_timer_id > 0U)
				Source.remove (debounce_timer_id);
			if (change_timer_id > 0U)
				Source.remove (change_timer_id);
			foreach (var monitor in folder_monitors) {
				monitor.changed.disconnect (on_folder_changed);
				monitor.cancel ();
			}
			folder_monitors.clear ();
		}

		void on_folder_changed (File file, File? other_file, FileMonitorEvent event_type)
		{
			if (debounce_timer_id > 0U)
				Source.remove (debounce_timer_id);
			debounce_timer_id = Timeout.add (300, () => {
				debounce_timer_id = 0U;
				uri_identities.clear ();
				raw_uri_identities.clear ();
				refresh_desktop_index ();
				return false;
			});
		}

		void schedule_changed ()
		{
			if (change_timer_id > 0U)
				return;
			change_timer_id = Timeout.add (50, () => {
				change_timer_id = 0U;
				gc_synthetic_launchers ();
				changed ();
				return false;
			});
		}

		void gc_synthetic_launchers ()
		{
			if (!WindowControl.has_state ())
				return;

			if (initial_gc_done) {
				bool has_synth_in_ram = false;
				foreach (var k in identities.keys) {
					if (k.has_prefix ("wayplank-app-")) {
						has_synth_in_ram = true;
						break;
					}
				}
				if (!has_synth_in_ram)
					return;
			}
			initial_gc_done = true;

			var user_app_dir = Paths.DataHomeFolder.get_child ("applications");
			if (!user_app_dir.query_exists ())
				return;

			var pinned_ids = new Gee.HashSet<string> ();
			var dock_config_dir = Paths.ConfigHomeFolder.get_child ("wayplank");
			if (dock_config_dir.query_exists ()) {
				try {
					var d_enum = dock_config_dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
					FileInfo? d_info = null;
					while ((d_info = d_enum.next_file ()) != null) {
						var launchers_dir = dock_config_dir.get_child (d_info.get_name ()).get_child ("launchers");
						if (!launchers_dir.query_exists ())
							continue;
						var l_enum = launchers_dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
						FileInfo? l_info = null;
						while ((l_info = l_enum.next_file ()) != null) {
							var item_file = launchers_dir.get_child (l_info.get_name ());
							var kf = new KeyFile ();
							try {
								kf.load_from_file (item_file.get_path (), KeyFileFlags.NONE);
								if (kf.has_key ("PlankDockItemPreferences", "Launcher")) {
									var uri = kf.get_string ("PlankDockItemPreferences", "Launcher");
									if (uri != null && uri.contains ("wayplank-app-")) {
										var target = File.new_for_uri (uri);
										var bname = target.get_basename ();
										if (bname != null)
											pinned_ids.add (bname);
									}
								}
							} catch { }
						}
					}
				} catch { }
			}

			var windows = WindowControl.get_windows ();
			bool removed_any = false;
			try {
				var enumerator = user_app_dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
				FileInfo? info = null;
				while ((info = enumerator.next_file ()) != null) {
					var bname = info.get_name ();
					if (!bname.has_prefix ("wayplank-app-") || !bname.has_suffix (".desktop"))
						continue;
					if (pinned_ids.contains (bname))
						continue;

					var synth_file = user_app_dir.get_child (bname);
					var synth_uri = synth_file.get_uri ();
					if (pinned_launcher_uris.contains (synth_uri)
						|| dock_drawer_file_uris.contains (synth_uri)
						|| drawer_file_uris.contains (synth_uri)
						|| ApplicationIdentity.is_uri_locked_by_any_window (synth_uri))
						continue;

					var identity = identities.has_key (bname) ? identities.get (bname) : new ApplicationIdentity (synth_file);
					if (identity.detected_browser_profile != "")
						continue;

					bool has_open_window = false;
					foreach (var w in windows) {
						if (!is_ignored_app (w.ApplicationId) && !is_ignored_app (w.ResourceClass) && identity.matches (w)) {
							has_open_window = true;
							break;
						}
					}

					if (!has_open_window) {
						identities.unset (bname);
						uri_identities.unset (synth_file.get_uri ());
						raw_uri_identities.unset (synth_file.get_uri ());
						for (int i = indexed_desktop_files.size - 1; i >= 0; i--) {
							if (indexed_desktop_files[i].get_basename () == bname)
								indexed_desktop_files.remove_at (i);
						}
						if (desktop_exec_cache != null && synth_file.get_path () != null)
							desktop_exec_cache.unset (synth_file.get_path ());
						try { synth_file.delete (); } catch { }
						removed_any = true;
					}
				}
			} catch { }
			if (removed_any)
				rebuild_fast_indexes ();
		}
		
		public int effective_match_score (ApplicationIdentity identity, WindowInfo window)
		{
			string? profile_hint = identity.desktop_uri != "" ? launcher_profile_hints.get (identity.desktop_uri) : null;
			int score = identity.match_score (window, profile_hint);
			if (score <= 0 && !identity.is_web_app ())
				return 0;

			if (identity.is_terminal_emulator_launcher () && ApplicationIdentity.window_has_terminal_command (window)) {
				foreach (var other in identities.values) {
					if (other == identity || !other.has_exec || other.is_terminal_emulator_launcher ())
						continue;
					if (other.match_score (window) >= 115)
						return 0;
				}
			}

			if (identity.is_browser_launcher () && !ApplicationIdentity.is_plain_browser_window (window)) {
				foreach (var other in web_app_identities) {
					string? other_hint = other.desktop_uri != "" ? launcher_profile_hints.get (other.desktop_uri) : null;
					if (other.match_score (window, other_hint) >= 118)
						return 0;
				}
			}

			if (!identity.is_web_app ())
				return score;
			if (ApplicationIdentity.is_plain_browser_window (window))
				return 0;
			if (score <= 0 && identity.pwa_app_id != "")
				return 0;

			if (score == 119) {
				foreach (var other in web_app_identities) {
					if (other == identity)
						continue;
					string? other_hint = other.desktop_uri != "" ? launcher_profile_hints.get (other.desktop_uri) : null;
					if (other.match_score (window, other_hint) >= 124)
						return 0;
				}
				score = 120;
			}

			bool has_direct_owner = false;
			bool matches_direct_owner = false;
			int direct_owner_score = 120;
			foreach (var other in web_app_identities) {
				if (other == identity)
					continue;
				string? other_hint = other.desktop_uri != "" ? launcher_profile_hints.get (other.desktop_uri) : null;
				int other_score = other.match_score (window, other_hint);
				if (other_score == 119)
					other_score = 120;
				if (other_score >= 120) {
					has_direct_owner = true;
					if (identity.matches_web_app_identity (other)) {
						matches_direct_owner = true;
						if (other_score > direct_owner_score)
							direct_owner_score = other_score;
					}
				}
			}

			if (has_direct_owner)
				return matches_direct_owner ? int.max (score, direct_owner_score) : 0;

			if (score >= 120)
				return score;

			if (score >= 115)
				return 120;

			return score;
		}

		private int launcher_priority_rank_for_identity (ApplicationIdentity id_obj)
		{
			unowned string u = id_obj.desktop_uri;
			if (u != "") {
				if (pinned_launcher_uris.contains (u))
					return 4;
				if (dock_drawer_file_uris.contains (u))
					return 3;
				if (drawer_file_uris.contains (u))
					return 2;
			}
			if (id_obj.is_nodisplay_desktop)
				return 0;
			return 1;
		}

		private bool has_specialized_or_terminal_override (WindowInfo window, ApplicationIdentity? exclude = null)
		{
			foreach (var spec in specialized_exec_identities) {
				if (spec == exclude)
					continue;
				if (effective_match_score (spec, window) >= 115)
					return true;
			}
			if (ApplicationIdentity.window_has_terminal_command (window)) {
				foreach (var cand in identities.values) {
					if (cand == exclude || !cand.has_exec || cand.is_terminal_emulator_launcher ())
						continue;
					if (effective_match_score (cand, window) >= 115)
						return true;
				}
			}
			return false;
		}

		public Gee.ArrayList<WindowInfo> windows_for_launcher (string launcher_uri)
		{
			var result = new Gee.ArrayList<WindowInfo> ();
			var identity = identity_for_launcher (launcher_uri);
			if (identity == null)
				return result;
			foreach (var window in WindowControl.get_windows ())
				if (is_best_launcher_for_window (launcher_uri, window))
					result.add (window);
			return result;
		}
		
		public File? desktop_file_for_id (string app_id)
		{
			if (app_id.has_prefix ("file://")) {
				var cached_id = uri_identities.get (app_id);
				if (cached_id != null)
					return cached_id.desktop_file;
				var uri_file = File.new_for_uri (app_id);
				return uri_file.query_exists () ? uri_file : null;
			}
			var normalized = ApplicationIdentity.normalize (app_id);
			if (normalized == "")
				return null;
			var exact = desktop_files_by_norm_id.get (normalized);
			if (exact != null)
				return exact;

			// Prefix fallback: e.g. qemu-system-x86_64 matches qemu.desktop
			var first_dash = normalized.index_of_char ('-');
			if (first_dash > 0) {
				var prefix = normalized.substring (0, first_dash);
				var pref_file = desktop_files_by_norm_id.get (prefix);
				if (pref_file != null)
					return pref_file;
			}
			return null;
		}

		// Downstream contribution by IFtiger-hu (史有虎): Shield dock from ghost helper windows (xwaylandvideobridge)
		public static bool is_ignored_app (string? app_id)
		{
			if (app_id == null || app_id == "")
				return false;
			var lower = app_id.down ().strip ();
			return lower.contains ("xwaylandvideobridge")
				|| lower == "wayplank"
				|| lower == "wayplank-hover"
				|| lower == "plank"
				|| lower.has_prefix ("wayplank-build")
				|| lower.has_prefix ("wayplank-others")
				|| lower.has_prefix ("wayplank-dev");
		}

		private bool is_suppressed_nodisplay_window (WindowInfo window)
		{
			if (window.IsDialog)
				return true;

			string[] candidates = { window.DesktopFileName, window.ApplicationId, window.ResourceClass };
			foreach (unowned string c in candidates) {
				if (c == null || c == "")
					continue;
				var norm = ApplicationIdentity.normalize (c);
				if (norm != "" && suppressed_nodisplay_tokens.contains (norm))
					return true;
			}
			return false;
		}

		private static string resolve_appimage_cmdline (int pid, string cmdline)
		{
			if (pid <= 0 || !cmdline.contains ("/tmp/.mount_"))
				return cmdline;
			try {
				uint8[] data;
				if (FileUtils.get_data ("/proc/%d/environ".printf (pid), out data)) {
					int start = 0;
					for (int i = 0; i < data.length; i++) {
						if (data[i] == 0) {
							if (i > start) {
								char[] buf = new char[i - start + 1];
								Memory.copy (buf, (uint8*) data + start, i - start);
								buf[i - start] = 0;
								string entry = (string) buf;
								if (entry.has_prefix ("APPIMAGE=")) {
									var appimage_path = entry.substring ("APPIMAGE=".length).strip ();
									if (appimage_path != "" && FileUtils.test (appimage_path, FileTest.EXISTS)) {
										string quoted_app = appimage_path.contains (" ") ? "\"%s\"".printf (appimage_path) : appimage_path;
										try {
											string[] parsed_argv;
											if (Shell.parse_argv (cmdline, out parsed_argv) && parsed_argv.length > 1) {
												var sb = new StringBuilder (quoted_app);
												for (int a = 1; a < parsed_argv.length; a++) {
													sb.append_c (' ');
													string arg = parsed_argv[a];
													if (arg == "" || arg.contains (" ") || arg.contains ("\"") || arg.contains ("'"))
														sb.append (Shell.quote (arg));
													else
														sb.append (arg);
												}
												return sb.str;
											}
										} catch { }
										return quoted_app;
									}
								}
							}
							start = i + 1;
						}
					}
				}
			} catch { }
			return cmdline;
		}

		private static bool desktop_file_has_exec (File file)
		{
			try {
				var path = file.get_path ();
				if (path == null)
					return false;
				if (desktop_exec_cache == null)
					desktop_exec_cache = new Gee.HashMap<string, bool> ();
				if (desktop_exec_cache.has_key (path))
					return desktop_exec_cache.get (path);
				bool has_exec = false;
				var kf = new KeyFile ();
				if (kf.load_from_file (path, KeyFileFlags.NONE)) {
					if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
						var exec_val = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
						has_exec = (exec_val != "");
					}
				}
				desktop_exec_cache.set (path, has_exec);
				return has_exec;
			} catch { }
			return false;
		}

		public static string get_process_cmdline (int pid)
		{
			if (pid <= 0)
				return "";
			if (pid_cmdline_cache == null)
				pid_cmdline_cache = new Gee.HashMap<int, string> ();
			if (pid_cmdline_cache.has_key (pid))
				return pid_cmdline_cache.get (pid);
			try {
				uint8[] data;
				if (FileUtils.get_data ("/proc/%d/cmdline".printf (pid), out data)) {
					var builder = new StringBuilder ();
					int start = 0;
					for (int i = 0; i < data.length; i++) {
						if (data[i] == 0) {
							if (i > start) {
								char[] buf = new char[i - start + 1];
								Memory.copy (buf, (uint8*) data + start, i - start);
								buf[i - start] = 0;
								string arg = (string) buf;
								if (builder.len > 0)
									builder.append_c (' ');
								if (arg.contains (" ") || arg.contains ("\t")) {
									builder.append_c ('"');
									builder.append (arg);
									builder.append_c ('"');
								} else {
									builder.append (arg);
								}
							}
							start = i + 1;
						}
					}
					var res = builder.str;
					if (res != "") {
						if (pid_cmdline_cache.size > 512)
							pid_cmdline_cache.clear ();
						pid_cmdline_cache.set (pid, res);
					}
					return res;
				}
			} catch { }
			return "";
		}

		public static void invalidate_process_cmdline (int pid)
		{
			if (pid > 0 && pid_cmdline_cache != null)
				pid_cmdline_cache.unset (pid);
		}

		public static string get_process_comm (int pid)
		{
			if (pid <= 0)
				return "";
			if (pid_comm_cache == null)
				pid_comm_cache = new Gee.HashMap<int, string> ();
			if (pid_comm_cache.has_key (pid))
				return pid_comm_cache.get (pid);
			try {
				string comm = "";
				if (FileUtils.get_contents ("/proc/%d/comm".printf (pid), out comm)) {
					var res = comm.strip ();
					if (res != "") {
						if (pid_comm_cache.size > 512)
							pid_comm_cache.clear ();
						pid_comm_cache.set (pid, res);
					}
					return res;
				}
			} catch { }
			return "";
		}

		public File? best_desktop_file_for_window (WindowInfo window)
		{
			if (window.Id != "") {
				string locked_uri = ApplicationIdentity.get_locked_window_launcher_uri (window);
				if (locked_uri != "")
					return File.new_for_uri (locked_uri);
			}
			return compute_best_desktop_file_for_window (window);
		}

		public File? compute_best_desktop_file_for_window (WindowInfo window)
		{
			if (is_ignored_app (window.ApplicationId)
				|| is_ignored_app (window.ResourceClass)
				|| is_ignored_app (window.ResourceName)
				|| is_ignored_app (window.DesktopFileName))
				return null;

			bool matched_exec_less_desktop = false;
			bool is_plain_browser = ApplicationIdentity.is_plain_browser_window (window) && !ApplicationIdentity.has_explicit_webapp_window_id (window);
			string win_browser_prof = is_plain_browser ? ApplicationIdentity.get_window_browser_profile (window) : "";
			bool has_specialized_override = has_specialized_or_terminal_override (window) || (win_browser_prof != "");

			// Fast path: Exact desktop file or application ID match with authoritative score
			if (!has_specialized_override && window.DesktopFileName != "") {
				var canonical_file = desktop_file_for_id (window.DesktopFileName);
				if (canonical_file != null) {
					var cid = canonical_file.get_basename () ?? "";
					var c_id_obj = identities.get (cid);
					if (c_id_obj != null ? c_id_obj.has_exec : desktop_file_has_exec (canonical_file)) {
						if (c_id_obj != null && !c_id_obj.is_specialized () && effective_match_score (c_id_obj, window) > 0)
							return canonical_file;
					} else {
						matched_exec_less_desktop = true;
					}
				}
			}
			if (!has_specialized_override && window.ApplicationId != "") {
				var direct_app_file = desktop_file_for_id (window.ApplicationId);
				if (direct_app_file != null) {
					var id = direct_app_file.get_basename () ?? "";
					var d_id_obj = identities.get (id);
					if (d_id_obj != null ? d_id_obj.has_exec : desktop_file_has_exec (direct_app_file)) {
						if (d_id_obj != null && !d_id_obj.is_specialized () && effective_match_score (d_id_obj, window) >= 70)
							return direct_app_file;
					} else {
						matched_exec_less_desktop = true;
					}
				}
			}
			if (!has_specialized_override && window.ResourceClass != "") {
				var direct_class_file = desktop_file_for_id (window.ResourceClass);
				if (direct_class_file != null) {
					var id = direct_class_file.get_basename () ?? "";
					var cl_id_obj = identities.get (id);
					if (cl_id_obj != null ? cl_id_obj.has_exec : desktop_file_has_exec (direct_class_file)) {
						if (cl_id_obj != null && !cl_id_obj.is_specialized () && effective_match_score (cl_id_obj, window) >= 70)
							return direct_class_file;
					} else {
						matched_exec_less_desktop = true;
					}
				}
			}

			var best_score = 0;
			var best_rank = 0;
			string? best_id = null;
			ApplicationIdentity? best_identity = null;
			foreach (var entry in identities.entries) {
				var score = effective_match_score (entry.value, window);
				if (score < 50)
					continue;
				if (!entry.value.has_exec) {
					matched_exec_less_desktop = true;
					continue;
				}
				var rank = launcher_priority_rank_for_identity (entry.value);
				if (score > best_score || (score == best_score && rank > best_rank)) {
					best_score = score;
					best_rank = rank;
					best_id = entry.key;
					best_identity = entry.value;
				}
			}

			if (win_browser_prof != "" && !ApplicationIdentity.is_window_profile_pending (window) && best_score < 118) {
				var prof_file = synthesize_browser_profile_desktop_file (window, win_browser_prof);
				if (prof_file != null)
					return prof_file;
			}

			if (best_id != null && best_score >= 50) {
				if (best_id.has_prefix ("wayplank-app-") && !is_plain_browser && best_score < 124 && (window.Pid > 0 || window.Cmdline != ""))
					return synthesize_fallback_desktop_file (window, matched_exec_less_desktop);
				return best_identity != null ? best_identity.desktop_file : desktop_file_for_id (best_id);
			}

			// Synthesize a fallback launcher for standalone CLI / AppImage / VM GUI windows
			// lacking an installed .desktop file, while strictly suppressing non-normal dialogs
			// and helpers whose system .desktop entry declares XDG NoDisplay=true with Exec=.
			if (!is_suppressed_nodisplay_window (window))
				return synthesize_fallback_desktop_file (window, matched_exec_less_desktop);

			return null;
		}

		public static string sanitize_name_for_app (string raw_name, string fallback_id)
		{
			var safe_name = ApplicationIdentity.normalize (raw_name);
			if (safe_name == "")
				safe_name = fallback_id;

			var sanitized = new StringBuilder ();
			int idx = 0;
			unichar c;
			while (safe_name.get_next_char (ref idx, out c)) {
				if (c.isalnum () || c == '-' || c == '_') {
					sanitized.append_unichar (c);
				} else if (sanitized.len > 0 && !sanitized.str.has_suffix ("-")) {
					sanitized.append_c ('-');
				}
			}
			var clean_safe_name = sanitized.str.strip ();
			while (clean_safe_name.has_suffix ("-"))
				clean_safe_name = clean_safe_name.substring (0, clean_safe_name.length - 1);
			if (clean_safe_name == "")
				clean_safe_name = fallback_id;
			return clean_safe_name;
		}

		private File? synthesize_browser_profile_desktop_file (WindowInfo window, string profile_dir)
		{
			if (profile_dir == "")
				return null;
			var raw_id = window.ResourceClass != "" ? window.ResourceClass : (window.ApplicationId != "" ? window.ApplicationId : window.ResourceName);
			if (raw_id == "" || is_ignored_app (raw_id))
				raw_id = "google-chrome";
			var norm_id = ApplicationIdentity.normalize (raw_id);
			if (norm_id == "")
				norm_id = "google-chrome";

			string app_name = ApplicationIdentity.format_chrome_profile_identity_name (profile_dir);
			if (app_name == "")
				app_name = "Google Chrome (%s)".printf (profile_dir);

			string exec_bin = "/usr/bin/google-chrome-stable";
			if (!FileUtils.test (exec_bin, FileTest.IS_EXECUTABLE)) {
				if (FileUtils.test ("/opt/google/chrome/google-chrome", FileTest.IS_EXECUTABLE))
					exec_bin = "/opt/google/chrome/google-chrome";
				else if (window.Executable != "" && FileUtils.test (window.Executable, FileTest.IS_EXECUTABLE))
					exec_bin = window.Executable;
				else
					exec_bin = "google-chrome";
			}

			string prof_arg = profile_dir.contains (" ")
				? "\"--profile-directory=%s\"".printf (profile_dir)
				: "--profile-directory=%s".printf (profile_dir);
			string exec_cmd = "%s %s".printf (exec_bin.contains (" ") ? "\"%s\"".printf (exec_bin) : exec_bin, prof_arg);

			string prof_slug = sanitize_name_for_app (profile_dir, "profile");
			string clean_safe_name = "%s-%s".printf (sanitize_name_for_app (norm_id, "google-chrome"), prof_slug);

			var user_app_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			var dir = File.new_for_path (user_app_dir);
			try {
				if (!dir.query_exists ())
					dir.make_directory_with_parents ();
			} catch { }

			var file_path = Path.build_filename (user_app_dir, "wayplank-app-%s.desktop".printf (clean_safe_name));
			var synth_file = File.new_for_path (file_path);

			string icon_name = norm_id.has_prefix ("google-chrome") ? "google-chrome" : resolve_fallback_icon (window, norm_id);
			var wm_class = window.ResourceClass != "" ? window.ResourceClass : "Google-chrome";
			string content = "[Desktop Entry]\nType=Application\nName=%s\nStartupWMClass=%s\nExec=%s\nIcon=%s\nTerminal=false\nNoDisplay=true\n".printf (
				app_name, wm_class, exec_cmd, icon_name
			);

			string existing_content = "";
			bool content_unchanged = false;
			if (FileUtils.test (file_path, FileTest.EXISTS)) {
				try {
					if (FileUtils.get_contents (file_path, out existing_content) && existing_content == content)
						content_unchanged = true;
				} catch { }
			}

			try {
				if (!content_unchanged) {
					FileUtils.set_contents (file_path, content);
					if (desktop_exec_cache != null)
						desktop_exec_cache.unset (file_path);
				}
				var id = synth_file.get_basename ();
				if (!content_unchanged || !identities.has_key (id)) {
					var synth_identity = new ApplicationIdentity (synth_file);
					bool exists_in_index = identities.has_key (id);
					identities.set (id, synth_identity);
					uri_identities.set (synth_identity.desktop_uri, synth_identity);
					raw_uri_identities.set (synth_identity.desktop_uri, synth_identity);
					if (!exists_in_index)
						indexed_desktop_files.add (synth_file);
					rebuild_fast_indexes ();
					last_window_signature = "";
				}
				return synth_file;
			} catch (Error e) {
				debug ("Unable to create synthetic browser profile launcher: %s", e.message);
			}
			return null;
		}

		private File? synthesize_fallback_desktop_file (WindowInfo window, bool instance_isolated = false)
		{
			var raw_id = window.ResourceClass != "" ? window.ResourceClass : (window.ApplicationId != "" ? window.ApplicationId : window.ResourceName);
			if (raw_id == "" || is_ignored_app (raw_id))
				return null;

			var norm_id = ApplicationIdentity.normalize (raw_id);
			if (norm_id == "")
				return null;

			var app_name = window.Caption != "" ? window.Caption : (window.ResourceName != "" ? window.ResourceName : window.ResourceClass);
			if (app_name == "")
				app_name = raw_id;

			// Retrieve full command line from /proc/<pid>/cmdline or window.Cmdline (resolving AppImage FUSE mounts)
			var exec_cmd = resolve_appimage_cmdline (window.Pid, get_process_cmdline (window.Pid));
			if (exec_cmd == "")
				exec_cmd = window.Cmdline != "" ? resolve_appimage_cmdline (window.Pid, window.Cmdline) : (window.Executable != "" ? window.Executable : raw_id);

			bool per_instance = instance_isolated || exec_cmd.contains (" -name ") || exec_cmd.contains (" --name ");
			var clean_safe_name = per_instance
				? sanitize_name_for_app (app_name, norm_id)
				: sanitize_name_for_app (norm_id, norm_id);

			var user_app_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			var dir = File.new_for_path (user_app_dir);
			try {
				if (!dir.query_exists ())
					dir.make_directory_with_parents ();
			} catch { }

			var file_path = Path.build_filename (user_app_dir, "wayplank-app-%s.desktop".printf (clean_safe_name));
			var synth_file = File.new_for_path (file_path);

			// Find an icon from icon theme matching norm_id or resource_name, else generic executable
			var icon_name = resolve_fallback_icon (window, norm_id);

			if (synth_file.query_exists ()) {
				try {
					var existing_kf = new KeyFile ();
					if (existing_kf.load_from_file (file_path, KeyFileFlags.NONE)) {
						if (!exec_cmd.contains (" ") && existing_kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
							var existing_exec = existing_kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
							if (existing_exec.contains (" "))
								exec_cmd = existing_exec;
						}
						if (!per_instance && existing_kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME)) {
							var existing_name = existing_kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME).strip ();
							if (existing_name != "")
								app_name = existing_name;
						}
					}
				} catch { }
			}

			string content;
			if (per_instance) {
				content = "[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\nTerminal=false\nNoDisplay=true\n".printf (
					app_name, exec_cmd, icon_name
				);
			} else {
				var wm_class = window.ResourceClass != "" ? window.ResourceClass : raw_id;
				content = "[Desktop Entry]\nType=Application\nName=%s\nStartupWMClass=%s\nExec=%s\nIcon=%s\nTerminal=false\nNoDisplay=true\n".printf (
					app_name, wm_class, exec_cmd, icon_name
				);
			}

			string existing_content = "";
			bool content_unchanged = false;
			if (FileUtils.test (file_path, FileTest.EXISTS)) {
				try {
					if (FileUtils.get_contents (file_path, out existing_content) && existing_content == content)
						content_unchanged = true;
				} catch { }
			}

			try {
				if (!content_unchanged) {
					FileUtils.set_contents (file_path, content);
					if (desktop_exec_cache != null)
						desktop_exec_cache.unset (file_path);
				}
				var id = synth_file.get_basename ();
				if (!content_unchanged || !identities.has_key (id)) {
					var synth_identity = new ApplicationIdentity (synth_file);
					bool exists_in_index = identities.has_key (id);
					identities.set (id, synth_identity);
					uri_identities.set (synth_identity.desktop_uri, synth_identity);
					raw_uri_identities.set (synth_identity.desktop_uri, synth_identity);
					if (!exists_in_index)
						indexed_desktop_files.add (synth_file);
					rebuild_fast_indexes ();
					last_window_signature = "";
				}
				return synth_file;
			} catch (Error e) {
				debug ("Unable to create synthetic launcher: %s", e.message);
			}
			return null;
		}

		private string resolve_fallback_icon (WindowInfo window, string norm_id)
		{
			if (Gdk.Screen.get_default () == null)
				return "application-x-executable";
			unowned Gtk.IconTheme? theme = Gtk.IconTheme.get_default ();
			if (theme == null)
				return "application-x-executable";
			if (window.ResourceClass != "" && theme.has_icon (window.ResourceClass))
				return window.ResourceClass;
			if (window.ResourceName != "" && theme.has_icon (window.ResourceName))
				return window.ResourceName;
			if (theme.has_icon (norm_id))
				return norm_id;
			var first_dash = norm_id.index_of_char ('-');
			if (first_dash > 0) {
				var prefix = norm_id.substring (0, first_dash);
				if (theme.has_icon (prefix))
					return prefix;
			}
			return "application-x-executable";
		}
		
		public string[] active_launcher_ids ()
		{
			var windows = WindowControl.get_windows ();
			var signature_builder = new StringBuilder ("");
			foreach (var window in windows)
				signature_builder.append ("%s|%s|%s|%s|%s|%s|%s;".printf (window.Id, window.ApplicationId, window.ResourceClass, window.ResourceName, window.Caption, ApplicationIdentity.get_window_browser_profile (window), ApplicationIdentity.get_locked_window_launcher_uri (window)));
			var signature = signature_builder.str;
			if (signature == last_window_signature)
				return cached_active_ids;

			var best_by_window = new Gee.HashMap<string, string> ();
			var score_by_window = new Gee.HashMap<string, int> ();
			foreach (var window in windows) {
				if (is_ignored_app (window.ApplicationId)
					|| is_ignored_app (window.ResourceClass)
					|| is_ignored_app (window.ResourceName)
					|| is_ignored_app (window.DesktopFileName))
					continue;

				if (window.Id != "") {
					string locked_uri = ApplicationIdentity.get_locked_window_launcher_uri (window);
					if (locked_uri != "") {
						var locked_file = File.new_for_uri (locked_uri);
						var locked_bname = locked_file.get_basename () ?? locked_uri;
						best_by_window.set (window.Id, identities.has_key (locked_bname) ? locked_bname : locked_uri);
						score_by_window.set (window.Id, 120);
						continue;
					}
				}

				bool has_specialized_override = has_specialized_or_terminal_override (window);

				// Fast path: Exact desktop file or application ID match with authoritative score
				if (!has_specialized_override && window.DesktopFileName != "") {
					var canonical_file = desktop_file_for_id (window.DesktopFileName);
					if (canonical_file != null) {
						var cid = canonical_file.get_basename () ?? "";
						var c_id_obj = identities.get (cid);
						if (c_id_obj != null ? c_id_obj.has_exec : desktop_file_has_exec (canonical_file)) {
							if (c_id_obj != null && !c_id_obj.is_specialized () && effective_match_score (c_id_obj, window) > 0) {
								best_by_window.set (window.Id, cid);
								score_by_window.set (window.Id, 100);
								continue;
							}
						}
					}
				}

				string? fast_id = null;
				if (!has_specialized_override && window.DesktopFileName != "") {
					var norm_dfn = ApplicationIdentity.normalize (window.DesktopFileName);
					foreach (var entry in identities.entries) {
						if (!entry.value.is_specialized () && entry.value.normalized_id == norm_dfn && effective_match_score (entry.value, window) >= 95) {
							fast_id = entry.key;
							break;
						}
					}
				}
				if (!has_specialized_override && fast_id == null && window.ApplicationId != "") {
					var norm_appid = ApplicationIdentity.normalize (window.ApplicationId);
					foreach (var entry in identities.entries) {
						if (!entry.value.is_specialized () && entry.value.normalized_id == norm_appid && effective_match_score (entry.value, window) >= 95) {
							fast_id = entry.key;
							break;
						}
					}
				}

				if (fast_id != null) {
					best_by_window.set (window.Id, fast_id);
					score_by_window.set (window.Id, 100);
					continue;
				}

				var best_score = 0;
				var best_rank = 0;
				string? best_id = null;
				foreach (var entry in identities.entries) {
					var score = effective_match_score (entry.value, window);
					var rank = (score > 0) ? launcher_priority_rank_for_identity (entry.value) : 0;
					if (score > best_score || (score == best_score && score > 0 && rank > best_rank)) {
						best_score = score;
						best_rank = rank;
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
			var raw_cached = raw_uri_identities.get (launcher_uri);
			if (raw_cached != null)
				return raw_cached;

			var file = launcher_uri.contains ("://") ? File.new_for_uri (launcher_uri) : File.new_for_path (launcher_uri);
			var canonical_uri = file.get_uri ();
			var uri_cached = uri_identities.get (canonical_uri);
			if (uri_cached != null) {
				raw_uri_identities.set (launcher_uri, uri_cached);
				return uri_cached;
			}

			if (!file.query_exists ()) {
				var missing_id = file.get_basename ();
				if (missing_id != null && identities.has_key (missing_id)) {
					var fallback_id = identities.get (missing_id);
					raw_uri_identities.set (launcher_uri, fallback_id);
					return fallback_id;
				}
				return null;
			}

			var identity = new ApplicationIdentity (file);
			foreach (var existing in identities.values) {
				identity.inherit_sibling_wm_classes (existing);
				existing.inherit_sibling_wm_classes (identity);
			}
			uri_identities.set (canonical_uri, identity);
			raw_uri_identities.set (launcher_uri, identity);
			var id = file.get_basename ();
			if (id != null && !identities.has_key (id))
				identities.set (id, identity);
			else if (!identities.has_key (canonical_uri))
				identities.set (canonical_uri, identity);
			bool in_indexed = false;
			foreach (var f in indexed_desktop_files) {
				if (f.equal (file)) {
					in_indexed = true;
					break;
				}
			}
			if (!in_indexed)
				indexed_desktop_files.add (file);
			rebuild_fast_indexes ();
			return identity;
		}
		
		public bool is_best_launcher_for_window (string launcher_uri, WindowInfo window)
		{
			if (is_ignored_app (window.ApplicationId)
				|| is_ignored_app (window.ResourceClass)
				|| is_ignored_app (window.ResourceName)
				|| is_ignored_app (window.DesktopFileName))
				return false;

			var my_identity = identity_for_launcher (launcher_uri);
			if (my_identity == null)
				return false;

			if (window.Id != "" && (ApplicationIdentity.is_plain_browser_window (window) || ApplicationIdentity.is_terminal_window (window))) {
				string locked_uri = ApplicationIdentity.get_locked_window_launcher_uri (window);
				if (locked_uri != "") {
					if (my_identity.desktop_uri != "" && my_identity.desktop_uri == locked_uri)
						return true;
					var locked_id = identity_for_launcher (locked_uri);
					if (locked_id != null) {
						if (my_identity.normalized_id != "" && my_identity.normalized_id == locked_id.normalized_id)
							return true;
						string my_hint = my_identity.desktop_uri != "" ? (launcher_profile_hints.get (my_identity.desktop_uri) ?? "") : "";
						string locked_hint = locked_id.desktop_uri != "" ? (launcher_profile_hints.get (locked_id.desktop_uri) ?? "") : "";
						if (!my_identity.is_web_app () && !locked_id.is_web_app ()) {
							string my_prof = my_identity.get_effective_browser_profile (my_hint);
							string locked_prof = locked_id.get_effective_browser_profile (locked_hint);
							if (my_prof != "" && locked_prof != "")
								return ApplicationIdentity.profiles_match (my_prof, locked_prof);
						}
						if (!my_identity.is_specialized () && !locked_id.is_specialized () && my_hint == "" && locked_hint == "")
							return my_identity.shares_application_with (locked_id);
						return false;
					}
				}
			}

			var my_score = effective_match_score (my_identity, window);
			if (my_score <= 0)
				return false;

			if (my_score >= 124)
				return true;

			unowned string my_uri = my_identity.desktop_uri;
			unowned string norm_target = my_identity.normalized_id;
			string my_prof_hint = my_uri != "" ? (launcher_profile_hints.get (my_uri) ?? "") : "";

			// Guard 2: Canonical Exact Match (only for non-specialized base application entries)
			bool my_is_canonical = !my_identity.is_specialized () && my_prof_hint == "" && norm_target != "" && (
				(window.DesktopFileName != "" && ApplicationIdentity.normalize (window.DesktopFileName) == norm_target) ||
				(window.ApplicationId != "" && ApplicationIdentity.normalize (window.ApplicationId) == norm_target)
			);

			if (my_is_canonical) {
				if (has_specialized_or_terminal_override (window, my_identity))
					return false;
				return true;
			}

			// Reverse Canonical Guard:
			// Prevent unrelated non-canonical / folder / profile launchers (score < 115) from hijacking
			// a window whose compositor DesktopFileName or ApplicationId canonically belongs to a different application,
			// while explicitly permitting alias launchers that invoke the same dedicated binary (e.g. "Visual Studio Code.desktop" <-> "code.desktop").
			if (my_score < 115) {
				string[] canonical_candidates = { window.DesktopFileName, window.ApplicationId };
				foreach (unowned string cand in canonical_candidates) {
					if (cand == null || cand == "")
						continue;
					var norm_cand = ApplicationIdentity.normalize (cand);
					if (norm_cand == "")
						continue;
					foreach (var entry in identities.entries) {
						string cand_prof_hint = entry.value.desktop_uri != "" ? (launcher_profile_hints.get (entry.value.desktop_uri) ?? "") : "";
						if (!entry.value.is_specialized () && cand_prof_hint == "" && entry.value.normalized_id == norm_cand) {
							if (my_identity.shares_application_with (entry.value))
								continue;
							if (entry.value.has_exec && effective_match_score (entry.value, window) >= 80)
								return false;
						}
					}
				}
			}

			foreach (var entry in identities.entries) {
				var other = entry.value;
				if (other == my_identity || (my_uri != "" && other.desktop_uri == my_uri))
					continue;
				if (!my_identity.is_specialized () && !other.is_specialized () && my_identity.shares_application_with (other))
					continue;
				if (effective_match_score (other, window) > my_score) {
					if (!other.has_exec)
						continue;
					return false;
				}
			}
			return true;
		}
		
		private static void add_unique_folder (Gee.ArrayList<File> list, File folder)
		{
			foreach (var f in list) {
				if (f.equal (folder))
					return;
			}
			list.add (folder);
		}

		Gee.ArrayList<File> application_folders (Gee.HashSet<string>? drawer_uris_out = null, Gee.ArrayList<File>? pinned_files_out = null, Gee.HashSet<string>? dock_drawer_uris_out = null)
		{
			var folders = new Gee.ArrayList<File> ();
			folders.add (Paths.DataHomeFolder.get_child ("applications"));
			foreach (var folder in Paths.DataDirFolders)
				folders.add (folder.get_child ("applications"));

			if (pinned_files_out != null)
				disk_profile_hints.clear ();

			// Discover any drawer / folder launchers (and 1st-level subfolders) and pinned .desktop files configured on any dock first
			var dock_config_dir = Paths.ConfigHomeFolder.get_child ("wayplank");
			if (dock_config_dir.query_exists ()) {
				try {
					var d_enum = dock_config_dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
					FileInfo? d_info = null;
					while ((d_info = d_enum.next_file ()) != null) {
						var launchers_dir = dock_config_dir.get_child (d_info.get_name ()).get_child ("launchers");
						if (!launchers_dir.query_exists ())
							continue;
						var l_enum = launchers_dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
						FileInfo? l_info = null;
						while ((l_info = l_enum.next_file ()) != null) {
							var item_file = launchers_dir.get_child (l_info.get_name ());
							var key_file = new KeyFile ();
							try {
								key_file.load_from_file (item_file.get_path (), KeyFileFlags.NONE);
								if (key_file.has_key ("PlankDockItemPreferences", "Launcher")) {
									var uri = key_file.get_string ("PlankDockItemPreferences", "Launcher");
									if (uri != null && uri.has_prefix ("file://")) {
										var target = File.new_for_uri (uri);
										if (target.query_exists ()) {
											var ftype = target.query_file_type (FileQueryInfoFlags.NONE);
											if (ftype == FileType.DIRECTORY) {
												add_unique_folder (folders, target);
												if (drawer_uris_out != null)
													drawer_uris_out.add (target.get_uri ());
												if (dock_drawer_uris_out != null)
													dock_drawer_uris_out.add (target.get_uri ());
												try {
													var sub_enum = target.enumerate_children (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_IS_HIDDEN, FileQueryInfoFlags.NONE);
													FileInfo? sub_info = null;
													while ((sub_info = sub_enum.next_file ()) != null) {
														if (!sub_info.get_is_hidden () && sub_info.get_file_type () == FileType.DIRECTORY) {
															var sub_dir = target.get_child (sub_info.get_name ());
															add_unique_folder (folders, sub_dir);
															if (drawer_uris_out != null)
																drawer_uris_out.add (sub_dir.get_uri ());
															if (dock_drawer_uris_out != null)
																dock_drawer_uris_out.add (sub_dir.get_uri ());
														}
													}
												} catch { }
											} else if (ftype == FileType.REGULAR && uri.down ().has_suffix (".desktop") && pinned_files_out != null) {
												add_unique_folder (pinned_files_out, target);
												if (key_file.has_key ("PlankDockItemPreferences", "BrowserProfile")) {
													var bp = key_file.get_string ("PlankDockItemPreferences", "BrowserProfile").strip ();
													if (bp != "")
														disk_profile_hints.set (target.get_uri (), bp);
												}
											}
										}
									}
								}
							} catch (Error e) { }
						}
					}
				} catch (Error e) { }
			}

			var desktop_dir_path = Environment.get_user_special_dir (UserDirectory.DESKTOP);
			if (desktop_dir_path != null && desktop_dir_path != "") {
				var desktop_folder = File.new_for_path (desktop_dir_path);
				if (desktop_folder.query_exists ()) {
					add_unique_folder (folders, desktop_folder);
					if (drawer_uris_out != null)
						drawer_uris_out.add (desktop_folder.get_uri ());
				}
			}

			if (pinned_files_out != null)
				recompute_effective_profile_hints ();

			return folders;
		}
		
		Gee.ArrayList<File> desktop_files ()
		{
			var result = new Gee.ArrayList<File> ();
			var seen_ids = new Gee.HashSet<string> ();
			var seen_uris = new Gee.HashSet<string> ();
			var drawer_uris = new Gee.HashSet<string> ();
			var dock_drawer_uris = new Gee.HashSet<string> ();
			var pinned_files = new Gee.ArrayList<File> ();
			var next_suppressed = new Gee.HashSet<string> ();
			var next_pinned_uris = new Gee.HashSet<string> ();
			var next_dock_drawer_file_uris = new Gee.HashSet<string> ();
			var next_drawer_file_uris = new Gee.HashSet<string> ();
			var folders = application_folders (drawer_uris, pinned_files, dock_drawer_uris);
			var self_id = ApplicationIdentity.normalize (Paths.AppName + ".desktop");

			// 1. Index pinned dock .desktop launchers first so pinned entries win tie-breaks even if NoDisplay=true
			foreach (var pfile in pinned_files) {
				var p_uri = pfile.get_uri ();
				next_pinned_uris.add (p_uri);
				if (seen_uris.contains (p_uri))
					continue;
				var bname = pfile.get_basename () ?? "";
				var id = ApplicationIdentity.normalize (bname);
				if (id == self_id || id == "wayplank.desktop" || id == "plank.desktop")
					continue;
				if (!is_visible_application (pfile, null, true))
					continue;
				seen_uris.add (p_uri);
				seen_ids.add (id);
				result.add (pfile);
			}

			// 2. Index standard XDG application folders and user folder-menu drawers
			foreach (var folder in folders) {
				if (!folder.query_exists ())
					continue;
				var f_uri = folder.get_uri ();
				bool is_drawer = drawer_uris.contains (f_uri);
				bool is_dock_drawer = dock_drawer_uris.contains (f_uri);
				try {
					var enumerator = folder.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
					FileInfo info;
					while ((info = enumerator.next_file ()) != null) {
						if (!info.get_name ().has_suffix (".desktop"))
							continue;
						var file = folder.get_child (info.get_name ());
						var file_uri = file.get_uri ();
						if (is_drawer)
							next_drawer_file_uris.add (file_uri);
						if (is_dock_drawer)
							next_dock_drawer_file_uris.add (file_uri);
						if (seen_uris.contains (file_uri))
							continue;
						var id = ApplicationIdentity.normalize (info.get_name ());
						if (id == self_id || id == "wayplank.desktop" || id == "plank.desktop")
							continue;
						if (!is_drawer && seen_ids.contains (id))
							continue;
						if (!is_visible_application (file, is_drawer ? null : next_suppressed, is_drawer))
							continue;
						seen_uris.add (file_uri);
						seen_ids.add (id);
						result.add (file);
					}
				} catch (Error e) {
					debug ("Unable to enumerate application folder '%s': %s", folder.get_path (), e.message);
				}
			}
			pinned_launcher_uris = next_pinned_uris;
			dock_drawer_file_uris = next_dock_drawer_file_uris;
			drawer_file_uris = next_drawer_file_uris;
			suppressed_nodisplay_tokens = next_suppressed;
			return result;
		}

		bool is_visible_application (File file, Gee.HashSet<string>? suppressed_out = null, bool ignore_visibility_filters = false)
		{
			try {
				var bname = file.get_basename () ?? "";
				if (is_ignored_app (bname))
					return false;

				var key_file = new KeyFile ();
				key_file.load_from_file (file.get_path (), KeyFileFlags.NONE);
				if (!key_file.has_key (KeyFileDesktop.GROUP, "Type")
					|| key_file.get_string (KeyFileDesktop.GROUP, "Type") != "Application")
					return false;
				if (key_file.has_key (KeyFileDesktop.GROUP, "Hidden")
					&& key_file.get_boolean (KeyFileDesktop.GROUP, "Hidden"))
					return false;

				if (ignore_visibility_filters)
					return true;

				if (key_file.has_key (KeyFileDesktop.GROUP, "NoDisplay")
					&& key_file.get_boolean (KeyFileDesktop.GROUP, "NoDisplay")) {
					bool is_webapp_entry = false;
					if (key_file.has_key (KeyFileDesktop.GROUP, "StartupWMClass")) {
						var swmc_raw = key_file.get_string (KeyFileDesktop.GROUP, "StartupWMClass").down ().strip ();
						if (swmc_raw.has_prefix ("crx_") || swmc_raw.has_prefix ("chrome-") || swmc_raw.has_prefix ("brave-") || swmc_raw.has_prefix ("msedge-"))
							is_webapp_entry = true;
					}
					if (!is_webapp_entry && key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
						var exec_raw = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).down ();
						if (exec_raw.contains ("--app-id=") || exec_raw.contains ("--app="))
							is_webapp_entry = true;
					}
					if (!is_webapp_entry && !bname.has_prefix ("wayplank-app-") && desktop_file_has_exec (file)) {
						if (suppressed_out != null) {
							var norm_base = ApplicationIdentity.normalize (bname);
							if (norm_base != "")
								suppressed_out.add (norm_base);
							if (key_file.has_key (KeyFileDesktop.GROUP, "StartupWMClass")) {
								var swmc = ApplicationIdentity.normalize (key_file.get_string (KeyFileDesktop.GROUP, "StartupWMClass"));
								if (swmc != "")
									suppressed_out.add (swmc);
							}
							if (key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
								var exec_str = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
								if (exec_str != "") {
									var first_tok = exec_str.split (" ")[0].replace ("\"", "");
									var bin_name = ApplicationIdentity.normalize (Path.get_basename (first_tok));
									if (bin_name != "" && (norm_base == bin_name || norm_base.has_suffix ("." + bin_name)))
										suppressed_out.add (bin_name);
								}
							}
						}
						return false;
					}
				}

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

		void refresh_desktop_index (bool force = false)
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
			if (!force && !changed_index && uri_identities.size > 0)
				return;
			var new_identities = new Gee.HashMap<string, ApplicationIdentity> ();
			var identity_list = new Gee.ArrayList<ApplicationIdentity> ();
			uri_identities.clear ();
			raw_uri_identities.clear ();
			foreach (var file in next) {
				var id = file.get_basename () ?? file.get_uri ();
				var f_uri = file.get_uri ();
				var identity = new ApplicationIdentity (file);
				identity_list.add (identity);
				uri_identities.set (f_uri, identity);
				raw_uri_identities.set (f_uri, identity);
				if (!new_identities.has_key (id))
					new_identities.set (id, identity);
				else
					new_identities.set (f_uri, identity);
			}
			for (int i = 0; i < identity_list.size; i++) {
				var id_a = identity_list.get (i);
				if (!id_a.is_nodisplay_desktop || pinned_launcher_uris.contains (id_a.desktop_uri) || drawer_file_uris.contains (id_a.desktop_uri)) {
					foreach (var ptok in id_a.get_primary_tokens ())
						suppressed_nodisplay_tokens.remove (ptok);
				}
				if (id_a.is_specialized ())
					continue;
				for (int j = i + 1; j < identity_list.size; j++) {
					var id_b = identity_list.get (j);
					if (id_b.is_specialized ())
						continue;
					if (id_a.shares_application_with (id_b)) {
						id_a.inherit_sibling_wm_classes (id_b);
						id_b.inherit_sibling_wm_classes (id_a);
					}
				}
			}
			if (desktop_exec_cache != null)
				desktop_exec_cache.clear ();
			identities = new_identities;
			indexed_desktop_files = next;
			rebuild_fast_indexes ();
			last_window_signature = "";
			changed ();
		}
	}
}
