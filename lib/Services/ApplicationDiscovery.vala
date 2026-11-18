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
	 * Discovers applications from launcher catalogs and compositor window state.
	 */
	public class ApplicationDiscovery : GLib.Object
	{
		static ApplicationDiscovery? instance;
		static Gee.HashMap<int, string>? pid_cmdline_cache;
		static Gee.HashMap<int, string>? pid_comm_cache;
		public signal void changed ();
		Gee.ArrayList<File> indexed_desktop_files;
		Gee.ArrayList<string> indexed_launcher_uris;
		Gee.HashMap<string, ApplicationIdentity> identities;
		Gee.HashMap<string, ApplicationIdentity> uri_identities;
		Gee.HashMap<string, ApplicationIdentity> raw_uri_identities;
		Gee.HashMap<string, File> desktop_files_by_norm_id;
		Gee.HashMap<string, string> launcher_uris_by_norm_id;
		Gee.HashMap<string, string> synth_signature_cache;
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
		uint gc_timer_id = 0U;
		bool is_cleaned_up = false;
		bool initial_gc_done = false;
		int last_gc_window_count = -1;

		public static unowned ApplicationDiscovery get_default ()
		{
			if (instance == null)
				instance = new ApplicationDiscovery ();
			return instance;
		}

		public static void cleanup_if_active ()
		{
			if (instance != null) {
				instance.cleanup_instance ();
				instance = null;
			}
			if (pid_cmdline_cache != null) {
				pid_cmdline_cache.clear ();
				pid_cmdline_cache = null;
			}
			if (pid_comm_cache != null) {
				pid_comm_cache.clear ();
				pid_comm_cache = null;
			}
		}

		static string canonicalize_launcher_uri (string raw_uri_or_path)
		{
			string clean = raw_uri_or_path.strip ();
			if (clean == "")
				return "";
			if (clean.down ().has_prefix ("file://"))
				return File.new_for_uri (clean).get_uri ();
			if (clean.contains ("://"))
				return clean;
			return File.new_for_path (clean).get_uri ();
		}

		static string launcher_key_for_uri (string canonical_uri)
		{
			if (canonical_uri.down ().has_prefix ("file://")) {
				string? bname = File.new_for_uri (canonical_uri).get_basename ();
				if (bname != null && bname != "")
					return bname;
			}
			return canonical_uri;
		}

		static string basename_any_slash (string raw)
		{
			string s = raw.strip ();
			while (s.length > 1 && (s.has_suffix ("/") || s.has_suffix ("\\")))
				s = s.substring (0, s.length - 1);
			int fwd = s.last_index_of_char ('/');
			int back = s.last_index_of_char ('\\');
			int sep = int.max (fwd, back);
			if (sep >= 0 && sep + 1 < s.length)
				return s.substring (sep + 1);
			return s;
		}

		ApplicationDiscovery ()
		{
			indexed_desktop_files = new Gee.ArrayList<File> ();
			indexed_launcher_uris = new Gee.ArrayList<string> ();
			identities = new Gee.HashMap<string, ApplicationIdentity> ();
			uri_identities = new Gee.HashMap<string, ApplicationIdentity> ();
			raw_uri_identities = new Gee.HashMap<string, ApplicationIdentity> ();
			desktop_files_by_norm_id = new Gee.HashMap<string, File> ();
			launcher_uris_by_norm_id = new Gee.HashMap<string, string> ();
			synth_signature_cache = new Gee.HashMap<string, string> ();
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

			Hal.Windows.state_changed.connect (on_windows_state_changed);
			Hal.Apps.apps_changed.connect (on_hal_apps_changed);
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
			string canonical_uri = canonicalize_launcher_uri (launcher_uri);
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
			var canonical_uri = canonicalize_launcher_uri (launcher_uri);
			if (canonical_uri == "")
				return;
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

		public string get_launcher_profile_hint (string launcher_uri)
		{
			if (launcher_uri == "")
				return "";
			var canonical_uri = canonicalize_launcher_uri (launcher_uri);
			if (canonical_uri == "")
				return "";
			return launcher_profile_hints.get (canonical_uri) ?? "";
		}

		void rebuild_fast_indexes ()
		{
			desktop_files_by_norm_id.clear ();
			launcher_uris_by_norm_id.clear ();
			foreach (var file in indexed_desktop_files) {
				var norm = ApplicationIdentity.normalize (file.get_basename ());
				if (norm != "" && !desktop_files_by_norm_id.has_key (norm))
					desktop_files_by_norm_id.set (norm, file);
				if (norm != "" && !launcher_uris_by_norm_id.has_key (norm))
					launcher_uris_by_norm_id.set (norm, file.get_uri ());
			}
			foreach (var u in indexed_launcher_uris) {
				var id_obj = uri_identities.get (u);
				var norm = id_obj != null ? id_obj.normalized_id : ApplicationIdentity.normalize (Hal.Apps.launcher_id_stem (u));
				if (norm != "" && !launcher_uris_by_norm_id.has_key (norm))
					launcher_uris_by_norm_id.set (norm, u);
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
			var extra_uris = new Gee.ArrayList<string> ();
			foreach (var folder in application_folders ()) {
				if (!folder.query_exists ())
					continue;
				var f_uri = folder.get_uri ();
				extra_uris.add (f_uri);
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
			Hal.Apps.set_extra_watched_directories (extra_uris.to_array ());
		}

		public void refresh_index_now ()
		{
			Hal.Apps.invalidate_cache ();
			ensure_folder_monitors ();
			refresh_desktop_index (true);
		}

		void cleanup_instance ()
		{
			if (is_cleaned_up)
				return;
			is_cleaned_up = true;

			Hal.Windows.state_changed.disconnect (on_windows_state_changed);
			Hal.Apps.apps_changed.disconnect (on_hal_apps_changed);
			if (debounce_timer_id > 0U) {
				Source.remove (debounce_timer_id);
				debounce_timer_id = 0U;
			}
			if (change_timer_id > 0U) {
				Source.remove (change_timer_id);
				change_timer_id = 0U;
			}
			if (gc_timer_id > 0U) {
				Source.remove (gc_timer_id);
				gc_timer_id = 0U;
			}
			foreach (var monitor in folder_monitors) {
				monitor.changed.disconnect (on_folder_changed);
				monitor.cancel ();
			}
			folder_monitors.clear ();
			monitored_folder_uris.clear ();
		}

		~ApplicationDiscovery ()
		{
			cleanup_instance ();
		}

		static void arm_debounce_timer (ApplicationDiscovery target)
		{
			if (target.debounce_timer_id > 0U) {
				Source.remove (target.debounce_timer_id);
				target.debounce_timer_id = 0U;
			}
			GLib.WeakRef weak_self = GLib.WeakRef (target);
			target.debounce_timer_id = Timeout.add (300, () => {
				var self = (ApplicationDiscovery?) weak_self.get ();
				if (self == null || self.is_cleaned_up)
					return false;
				self.debounce_timer_id = 0U;
				self.uri_identities.clear ();
				self.raw_uri_identities.clear ();
				self.refresh_desktop_index ();
				return false;
			});
		}

		void on_hal_apps_changed ()
		{
			if (is_cleaned_up)
				return;
			arm_debounce_timer (this);
		}

		void on_folder_changed (File file, File? other_file, FileMonitorEvent event_type)
		{
			if (is_cleaned_up)
				return;
			arm_debounce_timer (this);
		}

		void on_windows_state_changed ()
		{
			if (is_cleaned_up || !Hal.Windows.has_state ())
				return;
			int cur_count = Hal.Windows.get_windows ().size;
			bool should_gc = (!initial_gc_done || (last_gc_window_count >= 0 && cur_count < last_gc_window_count));
			last_gc_window_count = cur_count;
			if (!should_gc)
				return;
			if (gc_timer_id > 0U)
				return;
			GLib.WeakRef weak_self = GLib.WeakRef (this);
			gc_timer_id = Timeout.add (50, () => {
				var self = (ApplicationDiscovery?) weak_self.get ();
				if (self == null || self.is_cleaned_up)
					return false;
				self.gc_timer_id = 0U;
				if (self.gc_synthetic_launchers ())
					self.changed ();
				return false;
			});
		}

		void schedule_changed ()
		{
			if (is_cleaned_up || change_timer_id > 0U)
				return;
			GLib.WeakRef weak_self = GLib.WeakRef (this);
			change_timer_id = Timeout.add (50, () => {
				var self = (ApplicationDiscovery?) weak_self.get ();
				if (self == null || self.is_cleaned_up)
					return false;
				self.change_timer_id = 0U;
				self.gc_synthetic_launchers ();
				self.changed ();
				return false;
			});
		}

		bool gc_synthetic_launchers ()
		{
			if (!Hal.Windows.has_state ())
				return false;

			if (initial_gc_done) {
				bool has_synth_in_ram = false;
				foreach (var k in identities.keys) {
					if (Hal.Apps.is_synthetic_launcher (k)) {
						has_synth_in_ram = true;
						break;
					}
				}
				if (!has_synth_in_ram)
					return false;
			}
			initial_gc_done = true;

			var launcher_dirs = Hal.Apps.discover_launcher_dirs ();
			if (launcher_dirs.size == 0)
				return false;
			var user_app_dir = launcher_dirs[0];
			if (!user_app_dir.query_exists ())
				return false;

			var pinned_synth_stems = new Gee.HashSet<string> ();
			var pinned_synth_uris = new Gee.HashSet<string> ();
			var dock_config_dir = Paths.AppConfigFolder;
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
									if (uri != null && Hal.Apps.is_synthetic_launcher (uri)) {
										pinned_synth_stems.add (Hal.Apps.launcher_id_stem (uri));
										pinned_synth_uris.add (canonicalize_launcher_uri (uri));
									} else if (uri != null && uri.has_prefix ("file://")) {
										var maybe_dir = File.new_for_uri (uri);
										if (maybe_dir.query_exists () && maybe_dir.query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY) {
											collect_folder_synthetic_launchers (maybe_dir, pinned_synth_stems, pinned_synth_uris, 0);
										}
									}
								}
							} catch { }
						}
						try { l_enum.close (null); } catch { }
					}
					try { d_enum.close (null); } catch { }
				} catch { }
			}

			var windows = Hal.Windows.get_windows ();
			bool removed_any = false;
			try {
				var enumerator = user_app_dir.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
				FileInfo? info = null;
				while ((info = enumerator.next_file ()) != null) {
					var bname = info.get_name ();
					if (!Hal.Apps.is_synthetic_launcher (bname))
						continue;
					var synth_file = user_app_dir.get_child (bname);
					var synth_uri = synth_file.get_uri ();
					if (!Hal.Apps.is_launcher_uri (synth_uri))
						continue;
					var stem = Hal.Apps.launcher_id_stem (bname);
					if (pinned_synth_stems.contains (stem) || pinned_synth_uris.contains (synth_uri))
						continue;

					if (pinned_launcher_uris.contains (synth_uri)
						|| dock_drawer_file_uris.contains (synth_uri)
						|| drawer_file_uris.contains (synth_uri)
						|| ApplicationIdentity.is_uri_locked_by_any_window (synth_uri))
						continue;

					var identity = identities.has_key (bname) ? identities.get (bname) : new ApplicationIdentity (synth_file);
					if (identity.detected_browser_profile != "" && bname.has_prefix ("wayplank-app-google-chrome-"))
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
						uri_identities.unset (synth_uri);
						raw_uri_identities.unset (synth_uri);
						synth_signature_cache.unset (stem);
						indexed_launcher_uris.remove (synth_uri);
						for (int i = indexed_desktop_files.size - 1; i >= 0; i--) {
							if (indexed_desktop_files[i].get_basename () == bname)
								indexed_desktop_files.remove_at (i);
						}
						Hal.Apps.delete_synthetic_launcher (synth_uri, pinned_synth_stems.contains (stem));
						removed_any = true;
					}
				}
				try { enumerator.close (null); } catch { }
			} catch { }
			if (removed_any)
				rebuild_fast_indexes ();
			return removed_any;
		}

		void collect_folder_synthetic_launchers (File dir, Gee.HashSet<string> stems, Gee.HashSet<string> uris, int depth)
		{
			if (depth > 3)
				return;
			try {
				var f_enum = dir.enumerate_children (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE, FileQueryInfoFlags.NONE);
				FileInfo? f_info = null;
				while ((f_info = f_enum.next_file ()) != null) {
					var cname = f_info.get_name ();
					var child = dir.get_child (cname);
					if (f_info.get_file_type () == FileType.DIRECTORY) {
						collect_folder_synthetic_launchers (child, stems, uris, depth + 1);
					} else if (Hal.Apps.is_synthetic_launcher (cname)) {
						stems.add (Hal.Apps.launcher_id_stem (cname));
						uris.add (canonicalize_launcher_uri (child.get_uri ()));
					}
				}
				try { f_enum.close (null); } catch { }
			} catch { }
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
				if (other_score >= 118) {
					has_direct_owner = true;
					if (identity.matches_web_app_identity (other)) {
						matches_direct_owner = true;
						int promoted_score = int.max (120, other_score);
						if (promoted_score > direct_owner_score)
							direct_owner_score = promoted_score;
					}
				}
			}

			if (has_direct_owner)
				return matches_direct_owner ? int.max (score, direct_owner_score) : 0;

			if (score <= 0 && identity.pwa_app_id != "")
				return 0;

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

		private bool is_unpinned_synthetic_browser_profile (ApplicationIdentity id_obj)
		{
			return id_obj.is_nodisplay_desktop
				&& id_obj.detected_browser_profile != ""
				&& Hal.Apps.is_synthetic_launcher (id_obj.desktop_uri != "" ? id_obj.desktop_uri : id_obj.normalized_id)
				&& (id_obj.desktop_uri == "" || !pinned_launcher_uris.contains (id_obj.desktop_uri));
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
			foreach (var window in Hal.Windows.get_windows ())
				if (is_best_launcher_for_window (launcher_uri, window))
					result.add (window);
			return result;
		}

		public string launcher_uri_for_id (string app_id)
		{
			if (app_id.down ().has_prefix ("file://")) {
				var canon = canonicalize_launcher_uri (app_id);
				var cached_id = uri_identities.get (canon);
				if (cached_id != null)
					return cached_id.desktop_uri;
				return Hal.Apps.launcher_exists (canon) ? canon : "";
			}
			if (app_id.contains ("://")) {
				var cached_id = uri_identities.get (app_id);
				if (cached_id != null)
					return cached_id.desktop_uri;
				return Hal.Apps.launcher_exists (app_id) ? app_id : "";
			}
			var normalized = ApplicationIdentity.normalize (app_id);
			if (normalized == "")
				return "";
			var exact = launcher_uris_by_norm_id.get (normalized);
			if (exact != null && exact != "")
				return exact;

			var first_dash = normalized.index_of_char ('-');
			if (first_dash > 0) {
				var prefix = normalized.substring (0, first_dash);
				var pref_uri = launcher_uris_by_norm_id.get (prefix);
				if (pref_uri != null && pref_uri != "")
					return pref_uri;
			}
			return "";
		}

		public File? desktop_file_for_id (string app_id)
		{
			if (app_id.down ().has_prefix ("file://")) {
				var canon = canonicalize_launcher_uri (app_id);
				var cached_id = uri_identities.get (canon);
				if (cached_id != null)
					return cached_id.desktop_file;
				var uri_file = File.new_for_uri (canon);
				return uri_file.query_exists () ? uri_file : null;
			}
			var normalized = ApplicationIdentity.normalize (app_id);
			if (normalized == "")
				return null;
			var exact = desktop_files_by_norm_id.get (normalized);
			if (exact != null)
				return exact;

			// Prefix fallback: e.g. qemu-system-x86_64 matches base launcher stem
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
			var lower = basename_any_slash (app_id).down ().strip ();
			lower = Hal.Apps.strip_launcher_extension (lower).down ();
			if (lower.has_suffix (".exe") || lower.has_suffix (".lnk"))
				lower = lower.substring (0, lower.length - 4);
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
			if (pid <= 0 || cmdline == "")
				return cmdline;
			var snap = Hal.Apps.inspect_process (pid, false);
			var appimage_path = snap.env_appimage.strip ();
			if (appimage_path == "" || !FileUtils.test (appimage_path, FileTest.EXISTS))
				return cmdline;
			if (cmdline.has_prefix (appimage_path) || cmdline.has_prefix ("\"" + appimage_path + "\""))
				return cmdline;

			string quoted_app = Hal.Runtime.quote_command_arg (appimage_path);
			string[] parsed_argv = Hal.Runtime.parse_command_argv (cmdline);
			if (parsed_argv.length > 1) {
				var sb = new StringBuilder (quoted_app);
				for (int a = 1; a < parsed_argv.length; a++) {
					sb.append_c (' ');
					sb.append (Hal.Runtime.quote_command_arg (parsed_argv[a]));
				}
				return sb.str;
			}
			return quoted_app;
		}

		private static bool launcher_uri_is_launchable (string uri)
		{
			if (uri == "")
				return false;
			var desc = Hal.Apps.load_launcher (uri);
			return desc != null && desc.is_launchable;
		}

		public static string get_process_cmdline (int pid)
		{
			if (pid <= 0)
				return "";
			if (pid_cmdline_cache == null)
				pid_cmdline_cache = new Gee.HashMap<int, string> ();
			if (pid_cmdline_cache.has_key (pid))
				return pid_cmdline_cache.get (pid);
			var snap = Hal.Apps.inspect_process (pid, false);
			var res = snap.full_cmdline;
			if (res != "") {
				if (pid_cmdline_cache.size > 512)
					pid_cmdline_cache.clear ();
				pid_cmdline_cache.set (pid, res);
			}
			return res;
		}

		public static void invalidate_process_cmdline (int pid)
		{
			if (pid > 0) {
				if (pid_cmdline_cache != null)
					pid_cmdline_cache.unset (pid);
				if (pid_comm_cache != null)
					pid_comm_cache.unset (pid);
				Hal.Runtime.invalidate_process_cache (pid);
			}
		}

		public static string get_process_comm (int pid)
		{
			if (pid <= 0)
				return "";
			if (pid_comm_cache == null)
				pid_comm_cache = new Gee.HashMap<int, string> ();
			if (pid_comm_cache.has_key (pid))
				return pid_comm_cache.get (pid);
			var snap = Hal.Apps.inspect_process (pid, false);
			var res = snap.executable_comm.strip ();
			if (res != "") {
				if (pid_comm_cache.size > 512)
					pid_comm_cache.clear ();
				pid_comm_cache.set (pid, res);
			}
			return res;
		}

		public string best_launcher_uri_for_window (WindowInfo window)
		{
			if (window.Id != "") {
				string locked_uri = ApplicationIdentity.get_locked_window_launcher_uri (window);
				if (locked_uri != "")
					return locked_uri;
			}
			return compute_best_launcher_uri_for_window (window);
		}

		public File? best_desktop_file_for_window (WindowInfo window)
		{
			string uri = best_launcher_uri_for_window (window);
			if (uri == "")
				return null;
			var id_obj = uri_identities.get (uri);
			if (id_obj != null)
				return id_obj.desktop_file;
			return File.new_for_uri (uri);
		}

		public string compute_best_launcher_uri_for_window (WindowInfo window)
		{
			if (is_ignored_app (window.ApplicationId)
				|| is_ignored_app (window.ResourceClass)
				|| is_ignored_app (window.ResourceName)
				|| is_ignored_app (window.DesktopFileName))
				return "";

			bool matched_exec_less_desktop = false;
			bool is_plain_browser = ApplicationIdentity.is_plain_browser_window (window) && !ApplicationIdentity.has_explicit_webapp_window_id (window);
			string win_browser_prof = (is_plain_browser && ApplicationIdentity.is_google_chrome_window (window))
				? ApplicationIdentity.get_window_browser_profile (window)
				: "";
			bool has_specialized_override = has_specialized_or_terminal_override (window) || (win_browser_prof != "");

			// Fast path: Exact launcher ID or application ID match with authoritative score
			if (!has_specialized_override && window.DesktopFileName != "") {
				var canonical_uri = launcher_uri_for_id (window.DesktopFileName);
				if (canonical_uri != "") {
					var cid = launcher_key_for_uri (canonical_uri);
					var c_id_obj = identities.get (cid) ?? uri_identities.get (canonical_uri);
					if (c_id_obj != null ? c_id_obj.has_exec : launcher_uri_is_launchable (canonical_uri)) {
						if (c_id_obj != null && !c_id_obj.is_specialized () && effective_match_score (c_id_obj, window) > 0)
							return canonical_uri;
					} else {
						matched_exec_less_desktop = true;
					}
				}
			}
			if (!has_specialized_override && window.ApplicationId != "") {
				var direct_app_uri = launcher_uri_for_id (window.ApplicationId);
				if (direct_app_uri != "") {
					var id = launcher_key_for_uri (direct_app_uri);
					var d_id_obj = identities.get (id) ?? uri_identities.get (direct_app_uri);
					if (d_id_obj != null ? d_id_obj.has_exec : launcher_uri_is_launchable (direct_app_uri)) {
						if (d_id_obj != null && !d_id_obj.is_specialized () && effective_match_score (d_id_obj, window) >= 70)
							return direct_app_uri;
					} else {
						matched_exec_less_desktop = true;
					}
				}
			}
			if (!has_specialized_override && window.ResourceClass != "") {
				var direct_class_uri = launcher_uri_for_id (window.ResourceClass);
				if (direct_class_uri != "") {
					var id = launcher_key_for_uri (direct_class_uri);
					var cl_id_obj = identities.get (id) ?? uri_identities.get (direct_class_uri);
					if (cl_id_obj != null ? cl_id_obj.has_exec : launcher_uri_is_launchable (direct_class_uri)) {
						if (cl_id_obj != null && !cl_id_obj.is_specialized () && effective_match_score (cl_id_obj, window) >= 70)
							return direct_class_uri;
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
				if (score > 118 && is_unpinned_synthetic_browser_profile (entry.value))
					score = 118;
				var rank = launcher_priority_rank_for_identity (entry.value);
				if (score > best_score || (score == best_score && rank > best_rank)) {
					best_score = score;
					best_rank = rank;
					best_id = entry.key;
					best_identity = entry.value;
				}
			}

			if (win_browser_prof != "" && ApplicationIdentity.is_google_chrome_window (window) && !ApplicationIdentity.is_window_profile_pending (window) && best_score < 118) {
				var prof_file = synthesize_browser_profile_desktop_file (window, win_browser_prof);
				if (prof_file != null)
					return prof_file.get_uri ();
			}

			if (best_id != null && best_score >= 50) {
				if (Hal.Apps.is_synthetic_launcher (best_id) && !is_plain_browser && best_score < 124 && (window.Pid > 0 || window.Cmdline != "")) {
					var synth = synthesize_fallback_desktop_file (window, matched_exec_less_desktop);
					return synth != null ? synth.get_uri () : "";
				}
				return best_identity != null ? best_identity.desktop_uri : launcher_uri_for_id (best_id);
			}

			// Synthesize a fallback launcher for standalone CLI / portable / VM GUI windows
			// lacking an installed launcher entry, while strictly suppressing non-normal dialogs
			// and background helpers whose system launcher entry declares NoDisplay=true with Exec.
			if (!is_suppressed_nodisplay_window (window)) {
				var synth = synthesize_fallback_desktop_file (window, matched_exec_less_desktop);
				return synth != null ? synth.get_uri () : "";
			}

			return "";
		}

		public File? compute_best_desktop_file_for_window (WindowInfo window)
		{
			string uri = compute_best_launcher_uri_for_window (window);
			if (uri == "")
				return null;
			var id_obj = uri_identities.get (uri);
			if (id_obj != null)
				return id_obj.desktop_file;
			return File.new_for_uri (uri);
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

		private void register_synthesized_launcher (File synth_file, string stem, string signature)
		{
			var id = synth_file.get_basename () ?? synth_file.get_uri ();
			bool unchanged = (synth_signature_cache.get (stem) == signature) && identities.has_key (id);
			if (!unchanged) {
				synth_signature_cache.set (stem, signature);
				var synth_identity = new ApplicationIdentity (synth_file);
				bool exists_in_index = identities.has_key (id);
				identities.set (id, synth_identity);
				uri_identities.set (synth_identity.desktop_uri, synth_identity);
				raw_uri_identities.set (synth_identity.desktop_uri, synth_identity);
				if (!exists_in_index)
					indexed_desktop_files.add (synth_file);
				if (!indexed_launcher_uris.contains (synth_identity.desktop_uri))
					indexed_launcher_uris.add (synth_identity.desktop_uri);
				rebuild_fast_indexes ();
				last_window_signature = "";
			}
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

			string exec_bin = Hal.Apps.find_installed_browser_binary (BrowserFamily.CHROME, window.Executable);
			if (exec_bin == "")
				exec_bin = "google-chrome";

			string prof_arg = profile_dir.contains (" ")
				? "\"--profile-directory=%s\"".printf (profile_dir)
				: "--profile-directory=%s".printf (profile_dir);
			string exec_cmd = "%s %s".printf (exec_bin.contains (" ") ? "\"%s\"".printf (exec_bin) : exec_bin, prof_arg);

			string prof_slug = sanitize_name_for_app (profile_dir, "profile");
			string clean_safe_name = "%s-%s".printf (sanitize_name_for_app (norm_id, "google-chrome"), prof_slug);

			string icon_name = norm_id.has_prefix ("google-chrome") ? "google-chrome" : resolve_fallback_icon (window, norm_id, exec_cmd);
			var wm_class = window.ResourceClass != "" ? window.ResourceClass : "Google-chrome";

			var synth_file = Hal.Apps.synthesize_fallback_launcher (clean_safe_name, app_name, exec_cmd, icon_name, wm_class, false);
			if (synth_file == null)
				return null;

			var synth_desc = Hal.Apps.load_launcher (synth_file.get_uri ());
			string eff_icon = (synth_desc != null && synth_desc.icon_token != "") ? synth_desc.icon_token : icon_name;
			string sig = "%s|%s|%s|%s".printf (app_name, exec_cmd, eff_icon, wm_class);
			register_synthesized_launcher (synth_file, Hal.Apps.launcher_id_stem (clean_safe_name), sig);
			return synth_file;
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

			// Retrieve full command line from live process snapshot or window.Cmdline (resolving portable AppImage mounts)
			var exec_cmd = resolve_appimage_cmdline (window.Pid, get_process_cmdline (window.Pid));
			if (exec_cmd == "")
				exec_cmd = window.Cmdline != "" ? resolve_appimage_cmdline (window.Pid, window.Cmdline) : (window.Executable != "" ? window.Executable : raw_id);

			bool per_instance = instance_isolated || exec_cmd.contains (" -name ") || exec_cmd.contains (" --name ");
			var clean_safe_name = per_instance
				? sanitize_name_for_app (app_name, norm_id)
				: sanitize_name_for_app (norm_id, norm_id);

			var icon_name = resolve_fallback_icon (window, norm_id, exec_cmd);
			var wm_class = per_instance ? "" : (window.ResourceClass != "" ? window.ResourceClass : raw_id);

			var synth_file = Hal.Apps.synthesize_fallback_launcher (clean_safe_name, app_name, exec_cmd, icon_name, wm_class, !per_instance);
			if (synth_file == null)
				return null;

			var synth_desc = Hal.Apps.load_launcher (synth_file.get_uri ());
			string eff_icon = (synth_desc != null && synth_desc.icon_token != "") ? synth_desc.icon_token : icon_name;
			string sig = "%s|%s|%s|%s|%d".printf (app_name, exec_cmd, eff_icon, wm_class, per_instance ? 1 : 0);
			register_synthesized_launcher (synth_file, Hal.Apps.launcher_id_stem (clean_safe_name), sig);
			return synth_file;
		}

		private static string extract_primary_command_token (string exec_cmd)
		{
			if (exec_cmd == "")
				return "";
			string[] argv = Hal.Runtime.parse_command_argv (exec_cmd);
			for (int i = 0; i < argv.length; i++) {
				string tok = argv[i].strip ();
				if (tok == "" || tok.has_prefix ("-"))
					continue;
				if (tok.contains ("=") && !Path.is_absolute (tok))
					continue;
				string base_tok = basename_any_slash (tok);
				if (Hal.Apps.is_os_wrapper_binary (base_tok))
					continue;
				return tok;
			}
			return argv.length > 0 ? argv[0].strip () : "";
		}

		private string resolve_fallback_icon (WindowInfo window, string norm_id, string exec_cmd = "")
		{
			if (window.ResourceClass != "") {
				if (Hal.Apps.has_native_icon (window.ResourceClass))
					return window.ResourceClass;
				string rc_low = window.ResourceClass.down ();
				if (Hal.Apps.has_native_icon (rc_low))
					return rc_low;
			}
			if (window.ResourceName != "") {
				if (Hal.Apps.has_native_icon (window.ResourceName))
					return window.ResourceName;
				string rn_low = window.ResourceName.down ();
				if (Hal.Apps.has_native_icon (rn_low))
					return rn_low;
			}
			if (Hal.Apps.has_native_icon (norm_id))
				return norm_id;
			var first_dash = norm_id.index_of_char ('-');
			if (first_dash > 0) {
				var prefix = norm_id.substring (0, first_dash);
				if (Hal.Apps.has_native_icon (prefix))
					return prefix;
			}

			if (window.Executable != "") {
				string exe_base = basename_any_slash (window.Executable).strip ();
				if (exe_base != "" && !Hal.Apps.is_os_wrapper_binary (exe_base)) {
					if (Hal.Apps.has_native_icon (exe_base))
						return exe_base;
					string exe_low = exe_base.down ();
					if (Hal.Apps.has_native_icon (exe_low))
						return exe_low;
					string exe_stem = ApplicationIdentity.clean_executable_stem (exe_base);
					if (exe_stem != "" && Hal.Apps.has_native_icon (exe_stem))
						return exe_stem;
				}
			}

			string cmd_tok = extract_primary_command_token (exec_cmd);
			if (cmd_tok != "") {
				string cmd_base = basename_any_slash (cmd_tok).strip ();
				if (cmd_base != "") {
					if (Hal.Apps.has_native_icon (cmd_base))
						return cmd_base;
					string cmd_low = cmd_base.down ();
					if (Hal.Apps.has_native_icon (cmd_low))
						return cmd_low;
					string cmd_stem = ApplicationIdentity.clean_executable_stem (cmd_base);
					if (cmd_stem != "") {
						if (Hal.Apps.has_native_icon (cmd_stem))
							return cmd_stem;
						int cmd_dash = cmd_stem.index_of_char ('-');
						if (cmd_dash > 0) {
							string cmd_pref = cmd_stem.substring (0, cmd_dash);
							if (Hal.Apps.has_native_icon (cmd_pref))
								return cmd_pref;
						}
					}
				}
			}

			return "application-x-executable";
		}

		public string[] active_launcher_ids ()
		{
			var windows = Hal.Windows.get_windows ();
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
						var locked_bname = launcher_key_for_uri (locked_uri);
						best_by_window.set (window.Id, identities.has_key (locked_bname) ? locked_bname : locked_uri);
						score_by_window.set (window.Id, 120);
						continue;
					}
				}

				bool has_specialized_override = has_specialized_or_terminal_override (window);

				// Fast path: Exact launcher entry or application ID match with authoritative score
				if (!has_specialized_override && window.DesktopFileName != "") {
					var canonical_uri = launcher_uri_for_id (window.DesktopFileName);
					if (canonical_uri != "") {
						var cid = launcher_key_for_uri (canonical_uri);
						var c_id_obj = identities.get (cid) ?? uri_identities.get (canonical_uri);
						if (c_id_obj != null ? c_id_obj.has_exec : launcher_uri_is_launchable (canonical_uri)) {
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

			var canonical_uri = canonicalize_launcher_uri (launcher_uri);
			if (canonical_uri == "")
				return null;

			var uri_cached = uri_identities.get (canonical_uri);
			if (uri_cached != null) {
				raw_uri_identities.set (launcher_uri, uri_cached);
				return uri_cached;
			}

			bool is_local_file = canonical_uri.down ().has_prefix ("file://");
			File? file = is_local_file ? File.new_for_uri (canonical_uri) : null;

			if (!Hal.Apps.launcher_exists (canonical_uri)) {
				var missing_id = launcher_key_for_uri (canonical_uri);
				if (missing_id != "" && identities.has_key (missing_id)) {
					var fallback_id = identities.get (missing_id);
					raw_uri_identities.set (launcher_uri, fallback_id);
					return fallback_id;
				}
				return null;
			}

			var identity = file != null
				? new ApplicationIdentity (file)
				: new ApplicationIdentity.from_uri (canonical_uri);
			foreach (var existing in identities.values) {
				identity.inherit_sibling_wm_classes (existing);
				existing.inherit_sibling_wm_classes (identity);
			}
			uri_identities.set (canonical_uri, identity);
			raw_uri_identities.set (launcher_uri, identity);
			var id = launcher_key_for_uri (canonical_uri);
			if (id != "" && !identities.has_key (id))
				identities.set (id, identity);
			else if (!identities.has_key (canonical_uri))
				identities.set (canonical_uri, identity);

			if (!indexed_launcher_uris.contains (canonical_uri))
				indexed_launcher_uris.add (canonical_uri);
			if (file != null) {
				bool in_indexed = false;
				foreach (var f in indexed_desktop_files) {
					if (f.equal (file)) {
						in_indexed = true;
						break;
					}
				}
				if (!in_indexed)
					indexed_desktop_files.add (file);
			}
			rebuild_fast_indexes ();
			return identity;
		}

		public bool launchers_share_runtime_identity (string uri_a, string uri_b,
			string? profile_hint_a = null, string? profile_hint_b = null)
		{
			if (uri_a == "" || uri_b == "")
				return false;
			if (uri_a.has_prefix ("docklet://") || uri_b.has_prefix ("docklet://"))
				return (uri_a == uri_b);
			if (Hal.Apps.launcher_uris_match (uri_a, uri_b))
				return true;

			var id_a = identity_for_launcher (uri_a);
			var id_b = identity_for_launcher (uri_b);
			if (id_a == null || id_b == null)
				return false;

			string eff_a = id_a.get_effective_browser_profile (profile_hint_a);
			string eff_b = id_b.get_effective_browser_profile (profile_hint_b);

			if (id_a.is_web_app () && id_b.is_web_app ()) {
				if (eff_a != "" && eff_b != "" && !ApplicationIdentity.profiles_match (eff_a, eff_b))
					return false;
				return id_a.matches_web_app_identity (id_b);
			}

			if (!id_a.is_specialized () && !id_b.is_specialized () && eff_a == "" && eff_b == "")
				return id_a.shares_application_with (id_b);

			return false;
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
						if (!my_identity.is_web_app () && !locked_id.is_web_app () && my_identity.shares_browser_family_with (locked_id)) {
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
			// while explicitly permitting alias launchers that invoke the same dedicated binary (e.g. VS Code alias launchers).
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
				var other_score = effective_match_score (other, window);
				if (other_score > 118 && is_unpinned_synthetic_browser_profile (other))
					other_score = 118;
				if (other_score > my_score) {
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

		private static void add_unique_uri (Gee.ArrayList<string> list, string uri)
		{
			if (uri != "" && !list.contains (uri))
				list.add (uri);
		}

		Gee.ArrayList<File> application_folders (Gee.HashSet<string>? drawer_uris_out = null, Gee.ArrayList<string>? pinned_uris_out = null, Gee.HashSet<string>? dock_drawer_uris_out = null)
		{
			var folders = new Gee.ArrayList<File> ();
			foreach (var folder in Hal.Apps.discover_launcher_dirs ())
				add_unique_folder (folders, folder);

			if (pinned_uris_out != null)
				disk_profile_hints.clear ();

			// Discover any drawer / folder launchers (and 1st-level subfolders) and pinned app launchers configured on any dock first
			var dock_config_dir = Paths.AppConfigFolder;
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
									if (uri != null && uri.down ().has_prefix ("file://")) {
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
													try { sub_enum.close (null); } catch { }
												} catch { }
											} else if (ftype == FileType.REGULAR && Hal.Apps.is_launcher_uri (target.get_uri ()) && pinned_uris_out != null) {
												string canon_uri = target.get_uri ();
												add_unique_uri (pinned_uris_out, canon_uri);
												if (key_file.has_key ("PlankDockItemPreferences", "BrowserProfile")) {
													var bp = key_file.get_string ("PlankDockItemPreferences", "BrowserProfile").strip ();
													if (bp != "")
														disk_profile_hints.set (canon_uri, bp);
												}
											}
										}
									} else if (uri != null && uri != "" && !uri.down ().has_prefix ("docklet://") && pinned_uris_out != null) {
										string canon_uri = canonicalize_launcher_uri (uri);
										if (canon_uri != "" && Hal.Apps.launcher_exists (canon_uri)) {
											add_unique_uri (pinned_uris_out, canon_uri);
											if (key_file.has_key ("PlankDockItemPreferences", "BrowserProfile")) {
												var bp = key_file.get_string ("PlankDockItemPreferences", "BrowserProfile").strip ();
												if (bp != "")
													disk_profile_hints.set (canon_uri, bp);
											}
										}
									}
								}
							} catch (Error e) { }
						}
						try { l_enum.close (null); } catch { }
					}
					try { d_enum.close (null); } catch { }
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

			if (pinned_uris_out != null)
				recompute_effective_profile_hints ();

			return folders;
		}

		Gee.ArrayList<string> discover_all_launcher_uris (out Gee.ArrayList<File> files_out)
		{
			files_out = new Gee.ArrayList<File> ();
			var uris = new Gee.ArrayList<string> ();
			var seen_ids = new Gee.HashSet<string> ();
			var seen_uris = new Gee.HashSet<string> ();
			var drawer_uris = new Gee.HashSet<string> ();
			var dock_drawer_uris = new Gee.HashSet<string> ();
			var pinned_uris = new Gee.ArrayList<string> ();
			var next_suppressed = new Gee.HashSet<string> ();
			var next_pinned_uris = new Gee.HashSet<string> ();
			var next_dock_drawer_file_uris = new Gee.HashSet<string> ();
			var next_drawer_file_uris = new Gee.HashSet<string> ();
			var folders = application_folders (drawer_uris, pinned_uris, dock_drawer_uris);

			// 1. Index pinned dock launchers first so pinned entries win tie-breaks even if NoDisplay=true
			foreach (var p_uri in pinned_uris) {
				next_pinned_uris.add (p_uri);
				if (seen_uris.contains (p_uri))
					continue;
				var key_name = launcher_key_for_uri (p_uri);
				var id = ApplicationIdentity.normalize (key_name);
				if (Hal.Apps.is_self_launcher (p_uri) || Hal.Apps.is_self_launcher (key_name))
					continue;
				if (!is_visible_application (p_uri, null, true))
					continue;
				seen_uris.add (p_uri);
				seen_ids.add (id);
				uris.add (p_uri);
				if (p_uri.down ().has_prefix ("file://"))
					files_out.add (File.new_for_uri (p_uri));
			}

			// 2. Index standard application launcher folders and user folder-menu drawers
			foreach (var folder in folders) {
				if (!folder.query_exists ())
					continue;
				var f_uri = folder.get_uri ();
				bool is_drawer = drawer_uris.contains (f_uri);
				bool is_dock_drawer = dock_drawer_uris.contains (f_uri);
				try {
					var enumerator = folder.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
					FileInfo? info = null;
					while ((info = enumerator.next_file ()) != null) {
						var child_name = info.get_name ();
						var file = folder.get_child (child_name);
						var file_uri = file.get_uri ();
						if (!Hal.Apps.is_launcher_uri (file_uri))
							continue;
						if (is_drawer)
							next_drawer_file_uris.add (file_uri);
						if (is_dock_drawer)
							next_dock_drawer_file_uris.add (file_uri);
						if (seen_uris.contains (file_uri))
							continue;
						var id = ApplicationIdentity.normalize (child_name);
						if (Hal.Apps.is_self_launcher (child_name))
							continue;
						if (!is_drawer && seen_ids.contains (id))
							continue;
						if (!is_visible_application (file_uri, is_drawer ? null : next_suppressed, is_drawer))
							continue;
						seen_uris.add (file_uri);
						seen_ids.add (id);
						uris.add (file_uri);
						files_out.add (file);
					}
					try { enumerator.close (null); } catch { }
				} catch (Error e) {
					debug ("Unable to enumerate application folder '%s': %s", folder.get_path (), e.message);
				}
			}

			// 3. Index any non-filesystem native platform apps (e.g. Store AUMIDs) returned by Hal.Apps
			foreach (var desc in Hal.Apps.discover_installed_apps (true)) {
				if (desc.uri == "" || desc.uri.down ().has_prefix ("file://") || seen_uris.contains (desc.uri))
					continue;
				if (Hal.Apps.is_self_launcher (desc.uri))
					continue;
				var id = ApplicationIdentity.normalize (desc.base_id != "" ? desc.base_id : Hal.Apps.launcher_id_stem (desc.uri));
				if (seen_ids.contains (id))
					continue;
				if (!is_visible_application (desc.uri, next_suppressed, false))
					continue;
				seen_uris.add (desc.uri);
				seen_ids.add (id);
				uris.add (desc.uri);
			}

			pinned_launcher_uris = next_pinned_uris;
			dock_drawer_file_uris = next_dock_drawer_file_uris;
			drawer_file_uris = next_drawer_file_uris;
			suppressed_nodisplay_tokens = next_suppressed;
			return uris;
		}

		bool is_visible_application (string uri_or_path, Gee.HashSet<string>? suppressed_out = null, bool ignore_visibility_filters = false)
		{
			var bname = launcher_key_for_uri (canonicalize_launcher_uri (uri_or_path));
			if (is_ignored_app (bname))
				return false;

			var desc = Hal.Apps.load_launcher (uri_or_path);
			if (desc == null || !desc.has_explicit_app_type || desc.is_non_app_launcher || desc.is_hidden)
				return false;

			if (ignore_visibility_filters)
				return true;

			if (desc.is_nodisplay) {
				bool is_webapp_entry = false;
				if (desc.startup_wm_class_or_aumid != "") {
					var swmc_raw = desc.startup_wm_class_or_aumid.down ().strip ();
					if (swmc_raw.has_prefix ("crx_") || swmc_raw.contains ("_crx_") ||
					    ((swmc_raw.has_prefix ("chrome-") || swmc_raw.has_prefix ("brave-") || swmc_raw.has_prefix ("msedge-")) &&
					     !ApplicationIdentity.is_browser_binary (swmc_raw)))
						is_webapp_entry = true;
				}
				if (!is_webapp_entry && desc.exec_command != "") {
					var exec_raw = desc.exec_command.down ();
					if (exec_raw.contains ("--app-id=") || exec_raw.contains ("--app="))
						is_webapp_entry = true;
				}
				if (!is_webapp_entry && !desc.is_synthetic && desc.is_launchable) {
					if (suppressed_out != null) {
						var norm_base = ApplicationIdentity.normalize (bname);
						if (norm_base != "")
							suppressed_out.add (norm_base);
						if (desc.startup_wm_class_or_aumid != "") {
							var swmc = ApplicationIdentity.normalize (desc.startup_wm_class_or_aumid);
							if (swmc != "")
								suppressed_out.add (swmc);
						}
						if (desc.exec_command != "") {
							string[] argv = Hal.Runtime.parse_command_argv (desc.exec_command);
							string first_tok = argv.length > 0 ? argv[0] : desc.exec_command.split (" ")[0].replace ("\"", "");
							var bin_name = ApplicationIdentity.normalize (basename_any_slash (first_tok));
							if (bin_name != "" && (norm_base == bin_name || norm_base.has_suffix ("." + bin_name)))
								suppressed_out.add (bin_name);
						}
					}
					return false;
				}
			}

			if (!desc.is_shown_in_current_desktop)
				return false;
			if (!desc.try_exec_satisfied)
				return false;

			return true;
		}

		void refresh_desktop_index (bool force = false)
		{
			Gee.ArrayList<File> next_files;
			var next_uris = discover_all_launcher_uris (out next_files);
			var changed_index = (next_uris.size != indexed_launcher_uris.size);
			if (!changed_index) {
				foreach (var u in next_uris) {
					if (!indexed_launcher_uris.contains (u)) {
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
			foreach (var f_uri in next_uris) {
				var id = launcher_key_for_uri (f_uri);
				var identity = f_uri.down ().has_prefix ("file://")
					? new ApplicationIdentity (File.new_for_uri (f_uri))
					: new ApplicationIdentity.from_uri (f_uri);
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
			identities = new_identities;
			indexed_desktop_files = next_files;
			indexed_launcher_uris = next_uris;
			rebuild_fast_indexes ();
			last_window_signature = "";
			changed ();
		}
	}
}
