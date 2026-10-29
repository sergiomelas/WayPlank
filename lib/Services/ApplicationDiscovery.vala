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
		public signal void changed ();
		Gee.ArrayList<File> indexed_desktop_files;
		Gee.HashMap<string, ApplicationIdentity> identities;
		Gee.ArrayList<FileMonitor> folder_monitors;
		string last_window_signature = "";
		string[] cached_active_ids = {};
		uint debounce_timer_id = 0U;
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
			folder_monitors = new Gee.ArrayList<FileMonitor> ();
			refresh_desktop_index ();

			foreach (var folder in application_folders ()) {
				if (!folder.query_exists ())
					continue;
				try {
					var monitor = folder.monitor_directory (FileMonitorFlags.NONE, null);
					monitor.changed.connect (on_folder_changed);
					folder_monitors.add (monitor);
				} catch (Error e) {
					debug ("Unable to monitor folder '%s': %s", folder.get_path (), e.message);
				}
			}

			WindowControl.get_default ().state_changed.connect (schedule_changed);
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

			// Prefix fallback: e.g. qemu-system-x86_64 matches qemu.desktop
			var first_dash = normalized.index_of_char ('-');
			if (first_dash > 0) {
				var prefix = normalized.substring (0, first_dash);
				foreach (var file in indexed_desktop_files)
					if (ApplicationIdentity.normalize (file.get_basename ()) == prefix)
						return file;
			}
			return null;
		}

		// Downstream contribution by IFtiger-hu (史有虎): Shield dock from ghost helper windows (xwaylandvideobridge)
		public static bool is_ignored_app (string? app_id)
		{
			if (app_id == null || app_id == "")
				return false;
			var lower = app_id.down ();
			return lower.contains ("xwaylandvideobridge")
				|| lower == "wayplank"
				|| lower == "wayplank-hover"
				|| lower == "plank"
				|| lower.has_prefix ("wayplank-build")
				|| lower.has_prefix ("wayplank-others")
				|| lower.has_prefix ("wayplank-dev");
		}

		private static bool desktop_file_has_exec (File file)
		{
			try {
				var path = file.get_path ();
				if (path == null)
					return false;
				var kf = new KeyFile ();
				if (kf.load_from_file (path, KeyFileFlags.NONE)) {
					if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
						var exec_val = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
						return exec_val != "";
					}
				}
			} catch { }
			return false;
		}

		public static string get_process_cmdline (int pid)
		{
			if (pid <= 0)
				return "";
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
					return builder.str;
				}
			} catch { }
			return "";
		}

		public File? best_desktop_file_for_window (WindowInfo window)
		{
			if (is_ignored_app (window.ApplicationId)
				|| is_ignored_app (window.ResourceClass)
				|| is_ignored_app (window.ResourceName)
				|| is_ignored_app (window.DesktopFileName))
				return null;

			// Fast path: Exact desktop file or application ID match with authoritative score
			if (window.DesktopFileName != "") {
				var canonical_file = desktop_file_for_id (window.DesktopFileName);
				if (canonical_file != null && desktop_file_has_exec (canonical_file)) {
					var cid = canonical_file.get_basename ();
					if (identities.has_key (cid) && identities.get (cid).match_score (window) > 0)
						return canonical_file;
				}
			}
			if (window.ApplicationId != "") {
				var direct_app_file = desktop_file_for_id (window.ApplicationId);
				if (direct_app_file != null && desktop_file_has_exec (direct_app_file)) {
					var id = direct_app_file.get_basename ();
					if (identities.has_key (id) && identities.get (id).match_score (window) >= 70)
						return direct_app_file;
				}
			}
			if (window.ResourceClass != "") {
				var direct_class_file = desktop_file_for_id (window.ResourceClass);
				if (direct_class_file != null && desktop_file_has_exec (direct_class_file)) {
					var id = direct_class_file.get_basename ();
					if (identities.has_key (id) && identities.get (id).match_score (window) >= 70)
						return direct_class_file;
				}
			}

			var best_score = 0;
			string? best_id = null;
			foreach (var entry in identities.entries) {
				var candidate_file = desktop_file_for_id (entry.key);
				if (candidate_file == null || !desktop_file_has_exec (candidate_file))
					continue;
				var score = entry.value.match_score (window);
				if (score > best_score) {
					best_score = score;
					best_id = entry.key;
				}
			}
			if (best_id != null && best_score >= 50)
				return desktop_file_for_id (best_id);

			// Fallback: If no desktop file with an Exec line matched, synthesize a dedicated launcher
			// containing the exact process command line so the application/VM can be launched and relaunched!
			return synthesize_fallback_desktop_file (window);
		}

		public static string sanitize_name_for_app (string raw_name, string fallback_id)
		{
			var safe_name = ApplicationIdentity.normalize (raw_name);
			if (safe_name == "")
				safe_name = fallback_id;

			var sanitized = new StringBuilder ();
			for (int i = 0; i < safe_name.length; i++) {
				unichar c = safe_name.get_char (safe_name.index_of_nth_char (i));
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

		private File? synthesize_fallback_desktop_file (WindowInfo window)
		{
			var app_name = window.Caption != "" ? window.Caption : (window.ResourceName != "" ? window.ResourceName : window.ResourceClass);
			if (app_name == "")
				return null;

			var raw_id = window.ResourceClass != "" ? window.ResourceClass : (window.ApplicationId != "" ? window.ApplicationId : window.ResourceName);
			if (raw_id == "" || is_ignored_app (raw_id))
				return null;

			var norm_id = ApplicationIdentity.normalize (raw_id);
			if (norm_id == "")
				return null;

			var clean_safe_name = sanitize_name_for_app (app_name, norm_id);

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

			// Retrieve full command line from /proc/<pid>/cmdline or window.Cmdline
			var exec_cmd = get_process_cmdline (window.Pid);
			if (exec_cmd == "")
				exec_cmd = window.Cmdline != "" ? window.Cmdline : (window.Executable != "" ? window.Executable : norm_id);

			var content = "[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\nTerminal=false\nNoDisplay=true\n".printf (
				app_name, exec_cmd, icon_name
			);

			try {
				FileUtils.set_contents (file_path, content);
				var id = synth_file.get_basename ();
				if (!identities.has_key (id)) {
					identities.set (id, new ApplicationIdentity (synth_file));
					indexed_desktop_files.add (synth_file);
				}
				return synth_file;
			} catch (Error e) {
				debug ("Unable to create synthetic launcher: %s", e.message);
			}
			return null;
		}

		private string resolve_fallback_icon (WindowInfo window, string norm_id)
		{
			var theme = Gtk.IconTheme.get_default ();
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
				signature_builder.append ("%s|%s|%s|%s;".printf (window.Id, window.ApplicationId, window.ResourceClass, window.ResourceName));
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

				// Fast path: Exact desktop file or application ID match with authoritative score
				if (window.DesktopFileName != "") {
					var canonical_file = desktop_file_for_id (window.DesktopFileName);
					if (canonical_file != null && desktop_file_has_exec (canonical_file)) {
						var cid = canonical_file.get_basename ();
						if (identities.has_key (cid) && identities.get (cid).match_score (window) > 0) {
							best_by_window.set (window.Id, cid);
							score_by_window.set (window.Id, 100);
							continue;
						}
					}
				}

				string? fast_id = null;
				if (window.DesktopFileName != "") {
					var norm_dfn = ApplicationIdentity.normalize (window.DesktopFileName);
					foreach (var entry in identities.entries) {
						if (ApplicationIdentity.normalize (entry.key) == norm_dfn && entry.value.match_score (window) >= 95) {
							fast_id = entry.key;
							break;
						}
					}
				}
				if (fast_id == null && window.ApplicationId != "") {
					var norm_appid = ApplicationIdentity.normalize (window.ApplicationId);
					foreach (var entry in identities.entries) {
						if (ApplicationIdentity.normalize (entry.key) == norm_appid && entry.value.match_score (window) >= 95) {
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
		
		public bool is_best_launcher_for_window (string launcher_uri, WindowInfo window)
		{
			var my_identity = identity_for_launcher (launcher_uri);
			if (my_identity == null)
				return false;
			var my_score = my_identity.match_score (window);
			if (my_score <= 0)
				return false;

			var file = File.new_for_uri (launcher_uri);
			var target_id = file.get_basename ();

			// Guard 2: Canonical Exact Match
			// If window's DesktopFileName or ApplicationId matches this launcher's desktop file name exactly,
			// this launcher is the authoritative match for this window.
			var norm_target = ApplicationIdentity.normalize (target_id);
			if ((window.DesktopFileName != "" && ApplicationIdentity.normalize (window.DesktopFileName) == norm_target) ||
			    (window.ApplicationId != "" && ApplicationIdentity.normalize (window.ApplicationId) == norm_target)) {
				return true;
			}

			foreach (var entry in identities.entries) {
				if (entry.key != target_id && entry.value.match_score (window) > my_score) {
					var other_file = desktop_file_for_id (entry.key);
					if (other_file != null && !desktop_file_has_exec (other_file))
						continue;
					return false;
				}
			}
			return true;
		}
		
		Gee.ArrayList<File> application_folders ()
		{
			var folders = new Gee.ArrayList<File> ();
			folders.add (Paths.DataHomeFolder.get_child ("applications"));
			foreach (var folder in Paths.DataDirFolders)
				folders.add (folder.get_child ("applications"));

			// Also discover any drawer / folder launchers configured on any dock
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
										if (target.query_exists () && target.query_file_type (FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
											bool already_has = false;
											foreach (var f in folders) {
												if (f.equal (target)) {
													already_has = true;
													break;
												}
											}
											if (!already_has)
												folders.add (target);
										}
									}
								}
							} catch (Error e) { }
						}
					}
				} catch (Error e) { }
			}

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
						if (id == self_id || id == "wayplank.desktop" || id == "plank.desktop" || seen_ids.contains (id) || !is_visible_application (file))
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
			var new_identities = new Gee.HashMap<string, ApplicationIdentity> ();
			foreach (var file in next) {
				var id = file.get_basename ();
				if (identities.has_key (id))
					new_identities.set (id, identities.get (id));
				else
					new_identities.set (id, new ApplicationIdentity (file));
			}
			// Preserve custom pinned identities that were loaded outside standard XDG directories
			foreach (var entry in identities.entries) {
				if (!new_identities.has_key (entry.key))
					new_identities.set (entry.key, entry.value);
			}
			identities = new_identities;
			indexed_desktop_files = next;
			last_window_signature = "";
			changed ();
		}
	}
}
