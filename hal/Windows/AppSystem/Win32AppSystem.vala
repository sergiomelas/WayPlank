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
	 * Native Windows (`Win 7 <-> 11+`) implementation of `IAppSystem`.
	 * Discovers Start Menu & Desktop `.lnk` shortcuts via COM `IShellLinkW`,
	 * extracts native `256x256` icons via `SHGetImageList(SHIL_JUMBO)` /
	 * `PrivateExtractIconsW`, launches apps via `ShellExecuteW`, inspects
	 * live processes via `QueryFullProcessImageNameW` / Toolhelp32, and reads
	 * Windows Recent Jump-Lists (`%APPDATA%\Microsoft\Windows\Recent\*.lnk`).
	 */
	public class Win32AppSystem : GLib.Object, IAppSystem
	{
		static Win32AppSystem? instance = null;

		public static Win32AppSystem get_default ()
		{
			if (instance == null)
				instance = new Win32AppSystem ();
			return instance;
		}

		Gee.ArrayList<AppDescriptor>? cached_apps = null;
		Gee.HashMap<string, Gdk.Pixbuf> icon_cache;
		Gee.HashMap<string, string> custom_icon_overrides;
		Gee.HashMap<BrowserFamily, Gee.ArrayList<GLib.FileMonitor>> browser_monitors;

		construct
		{
			icon_cache = new Gee.HashMap<string, Gdk.Pixbuf> ();
			custom_icon_overrides = new Gee.HashMap<string, string> ();
			browser_monitors = new Gee.HashMap<BrowserFamily, Gee.ArrayList<GLib.FileMonitor>> ();
		}

		static string to_local_path (string uri_or_path)
		{
			if (uri_or_path.length == 0)
				return "";
			if (uri_or_path.has_prefix ("file://")) {
				var f = File.new_for_uri (uri_or_path);
				string? p = f.get_path ();
				if (p != null && p.length > 0)
					return p;
			}
			return uri_or_path;
		}

		static string to_file_uri (string path)
		{
			if (path.length == 0)
				return "";
			if (path.has_prefix ("file://") || path.has_prefix ("aumid://") || path.has_prefix ("docklet://"))
				return path;
			return File.new_for_path (path).get_uri ();
		}

		static string normalize_app_id (string raw)
		{
			string s = raw.down ();
			if (s.contains ("++"))
				s = s.replace ("++", "plusplus");
			return s;
		}

		static string path_stem (string path)
		{
			int slash = path.last_index_of_char ('\\');
			int fslash = path.last_index_of_char ('/');
			int sep = int.max (slash, fslash);
			string base_name = (sep >= 0) ? path.substring (sep + 1) : path;
			int dot = base_name.last_index_of_char ('.');
			if (dot > 0)
				return base_name.substring (0, dot);
			return base_name;
		}

		static string get_synthetic_dir ()
		{
			string? local = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_LOCAL_APPDATA);
			if (local == null || local.length == 0)
				local = Environment.get_user_data_dir ();
			string dir = Path.build_filename (local, "wayplank", "synthetic-launchers");
			DirUtils.create_with_parents (dir, 0755);
			return dir;
		}

		static bool is_uninstaller_name (string lower_name)
		{
			return lower_name.contains ("uninstall")
				|| lower_name.contains ("uninst")
				|| lower_name.has_prefix ("remove ")
				|| lower_name.contains ("readme")
				|| lower_name.contains ("license");
		}

		static string quote_win_arg (string s)
		{
			if (s.length == 0)
				return "\"\"";
			if (!s.contains (" ") && !s.contains ("\t") && !s.contains ("\""))
				return s;
			return "\"" + s.replace ("\"", "\\\"") + "\"";
		}

		public Gee.ArrayList<GLib.File> get_extra_data_dirs ()
		{
			return new Gee.ArrayList<GLib.File> ();
		}

		public Gee.ArrayList<GLib.File> discover_launcher_dirs ()
		{
			var dirs = new Gee.ArrayList<GLib.File> ();

			/* Put user synthetic-launchers dir FIRST (index 0) matching the IAppSystem
			 * GC contract in ApplicationDiscovery.vala so stale unpinned .wayplank-app
			 * files are garbage-collected automatically on Windows just like Linux. */
			string synth = get_synthetic_dir ();
			if (FileUtils.test (synth, FileTest.IS_DIR))
				dirs.add (File.new_for_path (synth));

			int[] folder_ids = {
				Win32AppBridge.FOLDER_COMMON_PROGRAMS,
				Win32AppBridge.FOLDER_USER_PROGRAMS,
				Win32AppBridge.FOLDER_COMMON_DESKTOP,
				Win32AppBridge.FOLDER_USER_DESKTOP
			};

			var seen = new Gee.HashSet<string> ();
			foreach (int fid in folder_ids) {
				string? p = Win32AppBridge.get_known_folder (fid);
				if (p != null && p.length > 0 && FileUtils.test (p, FileTest.IS_DIR)) {
					string key = p.down ();
					if (!seen.contains (key)) {
						seen.add (key);
						dirs.add (File.new_for_path (p));
					}
				}
			}

			return dirs;
		}

		void scan_dir_recursive (string dir_path, int depth, Gee.ArrayList<AppDescriptor> out_apps, Gee.HashSet<string> seen_uris)
		{
			if (depth > 4)
				return;
			try {
				var dir = Dir.open (dir_path);
				string? name;
				while ((name = dir.read_name ()) != null) {
					string full = Path.build_filename (dir_path, name);
					if (FileUtils.test (full, FileTest.IS_DIR)) {
						scan_dir_recursive (full, depth + 1, out_apps, seen_uris);
						continue;
					}
					string lower = name.down ();
					if (lower.has_suffix (".lnk")) {
						if (is_uninstaller_name (lower))
							continue;
						var desc = load_launcher (full);
						if (desc != null && desc.is_launchable && !desc.is_non_app_launcher) {
							string ukey = desc.uri.down ();
							if (!seen_uris.contains (ukey)) {
								seen_uris.add (ukey);
								out_apps.add (desc);
							}
						}
					} else if (lower.has_suffix (".wayplank-app")) {
						var desc = load_launcher (full);
						if (desc != null && desc.is_launchable) {
							string ukey = desc.uri.down ();
							if (!seen_uris.contains (ukey)) {
								seen_uris.add (ukey);
								out_apps.add (desc);
							}
						}
					}
				}
			} catch (Error e) {
				// Ignore unreadable Start Menu subdirectories
			}
		}

		public Gee.ArrayList<AppDescriptor> discover_installed_apps (bool include_nodisplay = true)
		{
			if (cached_apps == null) {
				cached_apps = new Gee.ArrayList<AppDescriptor> ();
				var seen = new Gee.HashSet<string> ();
				foreach (var d in discover_launcher_dirs ()) {
					string? p = d.get_path ();
					if (p != null && p.length > 0)
						scan_dir_recursive (p, 0, cached_apps, seen);
				}
			}
			var copy = new Gee.ArrayList<AppDescriptor> ();
			foreach (var a in cached_apps) {
				if (include_nodisplay || !a.is_nodisplay)
					copy.add (a);
			}
			return copy;
		}

		public void set_extra_watched_directories (string[] folder_uris)
		{
		}

		public void invalidate_cache ()
		{
			cached_apps = null;
			apps_changed ();
		}

		AppDescriptor? load_lnk_descriptor (string path)
		{
			string? target = null;
			string? args = null;
			string? workdir = null;
			string? desc_str = null;
			string? icon_path = null;
			int icon_idx = 0;
			string? aumid = null;

			if (Win32AppBridge.resolve_lnk (path, out target, out args, out workdir, out desc_str, out icon_path, out icon_idx, out aumid) == 0)
				return null;

			string tgt = target ?? "";
			if (tgt.length == 0)
				return null;

			var d = new AppDescriptor ();
			d.uri = to_file_uri (path);
			string lnk_stem = path_stem (path);
			string tgt_stem = path_stem (tgt);

			if (FileUtils.test (tgt, FileTest.IS_DIR)) {
				d.display_name = lnk_stem;
				d.unlocalized_name = lnk_stem;
				d.base_id = lnk_stem.down ();
				d.is_non_app_launcher = true;
				d.is_launchable = false;
				return d;
			}

			string lower_tgt = tgt.down ();
			bool is_exec = lower_tgt.has_suffix (".exe")
				|| lower_tgt.has_suffix (".bat")
				|| lower_tgt.has_suffix (".cmd")
				|| lower_tgt.has_suffix (".com")
				|| lower_tgt.has_suffix (".msc");

			string arg_str = (args != null) ? args.strip () : "";
			string tgt_base = Path.get_basename (tgt);
			bool is_wrapper_shortcut = (arg_str.length > 0 && is_os_wrapper_binary (tgt_base));

			d.display_name = lnk_stem;
			d.unlocalized_name = lnk_stem;
			d.comment = desc_str ?? "";
			d.working_dir = workdir ?? "";
			d.base_id = (!is_wrapper_shortcut && tgt_stem.length > 0)
				? normalize_app_id (tgt_stem)
				: normalize_app_id (lnk_stem);
			if (normalize_app_id (lnk_stem) != d.base_id)
				d.alias_ids.add (normalize_app_id (lnk_stem));
			d.alias_ids.add (normalize_app_id (lnk_stem).replace (" ", "-"));
			if (!is_wrapper_shortcut && tgt_stem.length > 0)
				d.wm_classes_or_aumids.add (normalize_app_id (tgt_stem));
			if (aumid != null && aumid.strip ().length > 0) {
				string clean_aumid = aumid.strip ();
				d.startup_wm_class_or_aumid = clean_aumid;
				if (!d.wm_classes_or_aumids.contains (clean_aumid.down ()))
					d.wm_classes_or_aumids.add (clean_aumid.down ());
			}

			d.exec_command = (arg_str.length > 0)
				? "%s %s".printf (quote_win_arg (tgt), arg_str)
				: quote_win_arg (tgt);

			string ip = (icon_path != null) ? icon_path.strip () : "";
			string chosen_icon = "";
			if (ip.length > 0 && FileUtils.test (ip, FileTest.EXISTS)) {
				string candidate = ip.down ().has_suffix (".ico")
					? ("winico:" + ip)
					: ((icon_idx != 0) ? "%s,%d".printf (ip, icon_idx) : ip);
				if (load_native_icon (candidate, 48) != null)
					chosen_icon = candidate;
			}
			if (chosen_icon.length == 0 && FileUtils.test (tgt, FileTest.EXISTS)) {
				if (load_native_icon (tgt, 48) != null)
					chosen_icon = tgt;
			}
			if (chosen_icon.length == 0 && load_native_icon (path, 48) != null)
				chosen_icon = path;
			d.icon_token = (chosen_icon.length > 0) ? chosen_icon : "application-default-icon";

			if (custom_icon_overrides.has_key (d.uri.down ())) {
				d.icon_token = custom_icon_overrides.get (d.uri.down ());
				d.has_custom_icon_override = true;
			}

			d.is_launchable = is_exec;
			d.is_non_app_launcher = !is_exec;
			d.has_explicit_app_type = is_exec;
			d.try_exec_satisfied = FileUtils.test (tgt, FileTest.EXISTS);
			d.supports_files = is_exec;
			d.supports_uris = is_exec;
			d.is_shown_in_current_desktop = true;
			return d;
		}

		AppDescriptor? load_exe_descriptor (string path)
		{
			if (!FileUtils.test (path, FileTest.IS_REGULAR))
				return null;
			string stem = path_stem (path);
			var d = new AppDescriptor ();
			d.uri = to_file_uri (path);
			d.display_name = stem;
			d.unlocalized_name = stem;
			d.base_id = normalize_app_id (stem);
			d.wm_classes_or_aumids.add (normalize_app_id (stem));
			d.exec_command = quote_win_arg (path);
			d.icon_token = path;
			if (custom_icon_overrides.has_key (d.uri.down ())) {
				d.icon_token = custom_icon_overrides.get (d.uri.down ());
				d.has_custom_icon_override = true;
			}
			d.is_launchable = true;
			d.has_explicit_app_type = true;
			d.try_exec_satisfied = true;
			d.supports_files = true;
			d.supports_uris = true;
			d.is_shown_in_current_desktop = true;
			return d;
		}

		AppDescriptor? load_synthetic_descriptor (string path)
		{
			var kf = new KeyFile ();
			try {
				kf.load_from_file (path, KeyFileFlags.NONE);
				if (!kf.has_group ("WayPlankApp"))
					return null;
				/* Self-heal poisoned legacy synthetic files keyed on shared OS host classes
				 * (e.g. consolewindowclass.wayplank-app) so GC deletes them cleanly on upgrade. */
				string file_stem = path_stem (path);
				if (Win32Backend.is_generic_win32_class (file_stem))
					return null;

				var d = new AppDescriptor ();
				d.uri = to_file_uri (path);
				d.display_name = kf.has_key ("WayPlankApp", "Name") ? kf.get_string ("WayPlankApp", "Name") : file_stem;
				d.unlocalized_name = d.display_name;
				d.exec_command = kf.has_key ("WayPlankApp", "Exec") ? kf.get_string ("WayPlankApp", "Exec") : "";
				d.icon_token = kf.has_key ("WayPlankApp", "Icon") ? kf.get_string ("WayPlankApp", "Icon") : "";
				d.working_dir = kf.has_key ("WayPlankApp", "WorkingDir") ? kf.get_string ("WayPlankApp", "WorkingDir") : "";
				string raw_wm = kf.has_key ("WayPlankApp", "WmClass") ? kf.get_string ("WayPlankApp", "WmClass") : "";
				d.startup_wm_class_or_aumid = Win32Backend.is_generic_win32_class (raw_wm) ? "" : raw_wm;

				string stem = file_stem;
				if (d.exec_command.length > 0) {
					var argv = Hal.Runtime.parse_command_argv (d.exec_command);
					if (argv.length > 0) {
						stem = path_stem (argv[0]);
						if (!is_win_icon_spec (d.icon_token) && FileUtils.test (argv[0], FileTest.EXISTS))
							d.icon_token = argv[0];
					}
				}
				d.base_id = normalize_app_id (stem);
				if (d.startup_wm_class_or_aumid.length > 0)
					d.wm_classes_or_aumids.add (d.startup_wm_class_or_aumid.down ());
				d.is_launchable = d.exec_command.length > 0;
				d.has_explicit_app_type = true;
				d.is_synthetic = true;
				d.try_exec_satisfied = true;
				d.supports_files = true;
				d.supports_uris = true;
				d.is_shown_in_current_desktop = true;
				return d;
			} catch (Error e) {
				return null;
			}
		}

		public AppDescriptor? load_launcher (string uri_or_path)
		{
			if (uri_or_path.length == 0 || uri_or_path.has_prefix ("docklet://"))
				return null;

			string path = to_local_path (uri_or_path);
			string lower = path.down ();

			if (lower.has_suffix (".url")) {
				string? url = extract_link_shortcut_url (path);
				var d = new AppDescriptor ();
				d.uri = to_file_uri (path);
				d.display_name = path_stem (path);
				d.unlocalized_name = d.display_name;
				d.base_id = d.display_name.down ();
				d.url_target = url ?? "";
				d.is_non_app_launcher = true;
				d.is_launchable = false;
				return d;
			}

			if (lower.has_suffix (".lnk"))
				return load_lnk_descriptor (path);

			if (lower.has_suffix (".wayplank-app"))
				return load_synthetic_descriptor (path);

			if (lower.has_suffix (".exe"))
				return load_exe_descriptor (path);

			return null;
		}

		public string resolve_launcher_uri (string raw_id_or_uri)
		{
			if (raw_id_or_uri.length == 0 || raw_id_or_uri.has_prefix ("file://")
				|| raw_id_or_uri.has_prefix ("aumid://") || raw_id_or_uri.has_prefix ("docklet://"))
				return raw_id_or_uri;

			if (Path.is_absolute (raw_id_or_uri) && FileUtils.test (raw_id_or_uri, FileTest.EXISTS))
				return to_file_uri (raw_id_or_uri);

			string needle = strip_launcher_extension (raw_id_or_uri).down ();
			foreach (var app in discover_installed_apps (true)) {
				if (app.base_id == needle || app.display_name.down () == needle)
					return app.uri;
			}
			return raw_id_or_uri;
		}

		public bool is_launcher_uri (string uri_or_path)
		{
			if (uri_or_path.length == 0 || uri_or_path.has_prefix ("docklet://"))
				return false;
			if (uri_or_path.has_prefix ("aumid://"))
				return true;

			string path = to_local_path (uri_or_path);
			string lower = path.down ();
			if (lower.has_suffix (".url"))
				return false;
			if (lower.has_suffix (".wayplank-app") || lower.has_suffix (".exe"))
				return true;
			if (lower.has_suffix (".lnk")) {
				var d = load_lnk_descriptor (path);
				return d != null && d.is_launchable && !d.is_non_app_launcher;
			}
			return false;
		}

		public bool is_self_launcher (string id_or_uri)
		{
			string stem = launcher_id_stem (id_or_uri).down ();
			return stem == "wayplank" || stem == "plank";
		}

		public bool launcher_uris_match (string uri_a, string uri_b)
		{
			return uri_a.down () == uri_b.down ();
		}

		public string strip_launcher_extension (string raw_id)
		{
			string lower = raw_id.down ();
			if (lower.has_suffix (".wayplank-app"))
				return raw_id.substring (0, raw_id.length - 13);
			if (lower.has_suffix (".lnk") || lower.has_suffix (".exe") || lower.has_suffix (".url"))
				return raw_id.substring (0, raw_id.length - 4);
			return raw_id;
		}

		public string launcher_id_stem (string uri_or_id)
		{
			if (uri_or_id.has_prefix ("aumid://"))
				return uri_or_id.substring (8);
			string path = to_local_path (uri_or_id);
			return strip_launcher_extension (path_stem (path));
		}

		public bool launcher_exists (string uri_or_path)
		{
			if (uri_or_path.length == 0)
				return false;
			if (uri_or_path.has_prefix ("aumid://"))
				return uri_or_path.length > 8;
			string path = to_local_path (uri_or_path);
			return FileUtils.test (path, FileTest.EXISTS);
		}

		public GLib.FileMonitor? monitor_launcher (GLib.File launcher_file)
		{
			try {
				return launcher_file.monitor_file (FileMonitorFlags.NONE);
			} catch (Error e) {
				return null;
			}
		}

		public string? extract_link_shortcut_url (string uri_or_path)
		{
			string path = to_local_path (uri_or_path);
			if (!path.down ().has_suffix (".url") || !FileUtils.test (path, FileTest.IS_REGULAR))
				return null;
			var kf = new KeyFile ();
			try {
				kf.load_from_file (path, KeyFileFlags.NONE);
				if (kf.has_group ("InternetShortcut") && kf.has_key ("InternetShortcut", "URL")) {
					string url = kf.get_string ("InternetShortcut", "URL").strip ();
					if (url.length > 0)
						return url;
				}
			} catch (Error e) {
				// Fallback manual line parse for non-UTF8 .url files
				try {
					string content;
					if (FileUtils.get_contents (path, out content)) {
						foreach (var line in content.split ("\n")) {
							string t = line.strip ();
							if (t.down ().has_prefix ("url="))
								return t.substring (4).strip ();
						}
					}
				} catch (Error e2) {}
			}
			return null;
		}

		public bool can_launcher_accept_uri (string launcher_uri, string candidate_uri)
		{
			return is_launcher_uri (launcher_uri) && candidate_uri.length > 0;
		}

		public bool launch_app (string launcher_uri, string[] uris)
		{
			if (launcher_uri.length == 0)
				return false;

			string path = to_local_path (launcher_uri);
			string lower = path.down ();

			if (lower.has_suffix (".lnk")) {
				if (uris.length == 0)
					return Win32AppBridge.shell_execute (path, null, null) != 0;

				string? target = null;
				string? args = null;
				string? workdir = null;
				string? desc_str = null;
				string? icon_path = null;
				int icon_idx = 0;
				string? aumid = null;
				if (Win32AppBridge.resolve_lnk (path, out target, out args, out workdir, out desc_str, out icon_path, out icon_idx, out aumid) != 0
					&& target != null && target.length > 0) {
					var sb = new StringBuilder ();
					if (args != null && args.strip ().length > 0)
						sb.append (args.strip ());
					foreach (var u in uris) {
						if (sb.len > 0) sb.append_c (' ');
						sb.append (quote_win_arg (to_local_path (u)));
					}
					return Win32AppBridge.shell_execute (target, sb.str, workdir) != 0;
				}
				return Win32AppBridge.shell_execute (path, null, null) != 0;
			}

			if (lower.has_suffix (".wayplank-app")) {
				var d = load_synthetic_descriptor (path);
				if (d == null || d.exec_command.length == 0)
					return false;
				var sb = new StringBuilder (d.exec_command);
				foreach (var u in uris) {
					sb.append_c (' ');
					sb.append (quote_win_arg (to_local_path (u)));
				}
				return launch_command (sb.str, d.working_dir);
			}

			if (lower.has_suffix (".exe")) {
				var sb = new StringBuilder ();
				foreach (var u in uris) {
					if (sb.len > 0) sb.append_c (' ');
					sb.append (quote_win_arg (to_local_path (u)));
				}
				return Win32AppBridge.shell_execute (path, sb.len > 0 ? sb.str : null, null) != 0;
			}

			return Win32AppBridge.shell_execute (path, null, null) != 0;
		}

		public bool launch_action (string launcher_uri, string action_id, string fallback_exec = "")
		{
			if (fallback_exec.length > 0)
				return launch_command (fallback_exec);
			return launch_app (launcher_uri, {});
		}

		public bool launch_command (string cmdline, string working_dir = "")
		{
			string trimmed = cmdline.strip ();
			if (trimmed.length == 0)
				return false;
			var argv = Hal.Runtime.parse_command_argv (trimmed);
			if (argv.length == 0)
				return false;

			string target = argv[0];
			var sb = new StringBuilder ();
			for (int i = 1; i < argv.length; i++) {
				if (i > 1) sb.append_c (' ');
				sb.append (quote_win_arg (argv[i]));
			}
			return Win32AppBridge.shell_execute (target, sb.len > 0 ? sb.str : null, working_dir.length > 0 ? working_dir : null) != 0;
		}

		public string get_default_app_for_role (DefaultAppRole role)
		{
			switch (role) {
			case DefaultAppRole.FILE_MANAGER:
				return to_file_uri ("C:\\Windows\\explorer.exe");
			case DefaultAppRole.TERMINAL:
				return to_file_uri ("C:\\Windows\\System32\\cmd.exe");
			case DefaultAppRole.TEXT_EDITOR:
				return to_file_uri ("C:\\Windows\\System32\\notepad.exe");
			case DefaultAppRole.WEB_BROWSER:
				string chrome = find_installed_browser_binary (BrowserFamily.CHROME);
				if (chrome.length > 0) return to_file_uri (chrome);
				string edge = find_installed_browser_binary (BrowserFamily.EDGE);
				if (edge.length > 0) return to_file_uri (edge);
				return "";
			default:
				return "";
			}
		}

		public Gee.ArrayList<string> discover_default_seed_apps ()
		{
			var seeds = new Gee.ArrayList<string> ();
			string explorer = get_default_app_for_role (DefaultAppRole.FILE_MANAGER);
			if (explorer.length > 0 && launcher_exists (explorer))
				seeds.add (explorer);
			string browser = get_default_app_for_role (DefaultAppRole.WEB_BROWSER);
			if (browser.length > 0 && launcher_exists (browser))
				seeds.add (browser);
			return seeds;
		}

		public int populate_category_folder (GLib.File folder, string icon_name, string[] priority_ids, string[] category_tags, int max_items = 6)
		{
			return 0;
		}

		public bool ensure_launcher_folder (GLib.File folder, string display_name = "", string icon_token = "")
		{
			string? p = folder.get_path ();
			if (p == null || p.length == 0)
				return false;
			return DirUtils.create_with_parents (p, 0755) == 0;
		}

		public string get_folder_display_name (GLib.File folder)
		{
			return folder.get_basename () ?? "";
		}

		public bool is_folder_metadata_file (string filename)
		{
			string lower = filename.down ();
			return lower == "desktop.ini" || lower == "thumbs.db";
		}

		public GLib.File? copy_launcher_to_directory (GLib.File src_launcher, GLib.File dest_dir)
		{
			string? base_name = src_launcher.get_basename ();
			if (base_name == null || base_name.length == 0)
				return null;
			var dest = dest_dir.get_child (base_name);
			try {
				src_launcher.copy (dest, FileCopyFlags.OVERWRITE);
				return dest;
			} catch (Error e) {
				return null;
			}
		}

		public GLib.File? relocate_launcher_for_dock_pin (GLib.File folder_launcher)
		{
			return copy_launcher_to_directory (folder_launcher, File.new_for_path (get_synthetic_dir ()));
		}

		public GLib.File? synthesize_fallback_launcher (string safe_stem, string app_name, string exec_cmd, string icon_token, string wm_class_or_aumid = "", bool preserve_existing_fields = false)
		{
			if (safe_stem.length == 0 || exec_cmd.length == 0)
				return null;

			string dir = get_synthetic_dir ();
			string clean = safe_stem.replace ("/", "_").replace ("\\", "_").replace (":", "_");
			if (Win32Backend.is_generic_win32_class (clean)) {
				var cmd_argv = Hal.Runtime.parse_command_argv (exec_cmd);
				string fallback_stem = (cmd_argv.length > 0) ? normalize_app_id (path_stem (cmd_argv[0])) : "";
				if (fallback_stem.length == 0 || Win32Backend.is_generic_win32_class (fallback_stem))
					return null;
				clean = fallback_stem;
			}
			string file_path = Path.build_filename (dir, clean + ".wayplank-app");

			var kf = new KeyFile ();
			if (preserve_existing_fields && FileUtils.test (file_path, FileTest.IS_REGULAR)) {
				try { kf.load_from_file (file_path, KeyFileFlags.NONE); } catch (Error e) {}
			}

			kf.set_string ("WayPlankApp", "Name", app_name.length > 0 ? app_name : safe_stem);
			kf.set_string ("WayPlankApp", "Exec", exec_cmd);
			string resolved_icon = icon_token;
			if (!is_win_icon_spec (resolved_icon)) {
				var argv = Hal.Runtime.parse_command_argv (exec_cmd);
				if (argv.length > 0 && FileUtils.test (argv[0], FileTest.EXISTS)) {
					resolved_icon = argv[0];
				} else {
					/* Fallback: match running window executable by stem/class */
					string needle = safe_stem.down ();
					string wm_needle = wm_class_or_aumid.down ();
					foreach (var w in Hal.Windows.get_windows ()) {
						if (w.Executable.length == 0 || !FileUtils.test (w.Executable, FileTest.EXISTS))
							continue;
						if (w.ApplicationId.down () == needle
							|| w.ResourceName.down () == needle
							|| (wm_needle.length > 0 && w.ResourceClass.down () == wm_needle)) {
							resolved_icon = w.Executable;
							break;
						}
					}
				}
			}
			if (resolved_icon.length > 0)
				kf.set_string ("WayPlankApp", "Icon", resolved_icon);
			if (wm_class_or_aumid.length > 0 && !Win32Backend.is_generic_win32_class (wm_class_or_aumid))
				kf.set_string ("WayPlankApp", "WmClass", wm_class_or_aumid);

			try {
				string new_data = kf.to_data ();
				if (FileUtils.test (file_path, FileTest.IS_REGULAR)) {
					string existing = "";
					if (FileUtils.get_contents (file_path, out existing) && existing == new_data)
						return File.new_for_path (file_path);
				}
				FileUtils.set_contents (file_path, new_data);
				if (cached_apps != null) {
					var updated = load_synthetic_descriptor (file_path);
					if (updated != null && updated.is_launchable) {
						string ukey = updated.uri.down ();
						bool replaced = false;
						for (int i = 0; i < cached_apps.size; i++) {
							if (cached_apps.get (i).uri.down () == ukey) {
								cached_apps.set (i, updated);
								replaced = true;
								break;
							}
						}
						if (!replaced)
							cached_apps.add (updated);
					}
				}
				return File.new_for_path (file_path);
			} catch (Error e) {
				return null;
			}
		}

		public bool is_synthetic_launcher (string uri_or_id)
		{
			string path = to_local_path (uri_or_id).down ();
			return path.has_suffix (".wayplank-app");
		}

		public bool delete_synthetic_launcher (string launcher_uri, bool keep_shared_assets = false)
		{
			if (!is_synthetic_launcher (launcher_uri))
				return false;
			string path = to_local_path (launcher_uri);
			return FileUtils.unlink (path) == 0;
		}

		public string apply_custom_launcher_icon (string launcher_uri, string new_icon_token)
		{
			if (launcher_uri.length == 0 || new_icon_token.length == 0)
				return "";
			custom_icon_overrides.set (launcher_uri.down (), new_icon_token);
			return launcher_uri;
		}

		public string reset_custom_launcher_icon (string launcher_uri, out string restored_icon_token)
		{
			restored_icon_token = "";
			custom_icon_overrides.unset (launcher_uri.down ());
			var d = load_launcher (launcher_uri);
			if (d != null)
				restored_icon_token = d.icon_token;
			return launcher_uri;
		}

		public string find_installed_browser_binary (BrowserFamily family, string fallback_executable = "")
		{
			string? pf = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_PROGRAM_FILES);
			string? pf86 = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_PROGRAM_FILES_X86);
			string? local = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_LOCAL_APPDATA);

			string[] rels = {};
			switch (family) {
			case BrowserFamily.CHROME:
				rels = { "Google\\Chrome\\Application\\chrome.exe" };
				break;
			case BrowserFamily.EDGE:
				rels = { "Microsoft\\Edge\\Application\\msedge.exe" };
				break;
			case BrowserFamily.BRAVE:
				rels = { "BraveSoftware\\Brave-Browser\\Application\\brave.exe" };
				break;
			case BrowserFamily.FIREFOX:
				rels = { "Mozilla Firefox\\firefox.exe" };
				break;
			case BrowserFamily.VIVALDI:
				rels = { "Vivaldi\\Application\\vivaldi.exe" };
				break;
			case BrowserFamily.OPERA:
				rels = { "Programs\\Opera\\opera.exe", "Opera\\opera.exe" };
				break;
			default:
				break;
			}

			string?[] roots = { pf, pf86, local };
			foreach (var r in roots) {
				if (r == null || r.length == 0) continue;
				foreach (var rel in rels) {
					string full = Path.build_filename (r, rel);
					if (FileUtils.test (full, FileTest.IS_REGULAR))
						return full;
				}
			}
			return fallback_executable;
		}

		public string[] get_browser_local_state_paths (BrowserFamily family)
		{
			string? local = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_LOCAL_APPDATA);
			if (local == null || local.length == 0)
				return {};

			string rel = "";
			switch (family) {
			case BrowserFamily.CHROME:  rel = "Google\\Chrome\\User Data\\Local State"; break;
			case BrowserFamily.EDGE:    rel = "Microsoft\\Edge\\User Data\\Local State"; break;
			case BrowserFamily.BRAVE:   rel = "BraveSoftware\\Brave-Browser\\User Data\\Local State"; break;
			case BrowserFamily.VIVALDI: rel = "Vivaldi\\User Data\\Local State"; break;
			default: return {};
			}

			string full = Path.build_filename (local, rel);
			return FileUtils.test (full, FileTest.IS_REGULAR) ? new string[] { full } : new string[] {};
		}

		public void set_browser_session_watch (BrowserFamily family, bool active)
		{
			if (!active) {
				var existing = browser_monitors.get (family);
				if (existing != null) {
					foreach (var mon in existing)
						mon.cancel ();
					browser_monitors.unset (family);
				}
				return;
			}

			if (browser_monitors.has_key (family))
				return;

			var paths = get_browser_local_state_paths (family);
			if (paths.length == 0)
				return;

			var list = new Gee.ArrayList<GLib.FileMonitor> ();
			foreach (var p in paths) {
				try {
					var mon = File.new_for_path (p).monitor_file (FileMonitorFlags.NONE);
					mon.changed.connect ((f, other, ev) => {
						if (ev == FileMonitorEvent.CHANGES_DONE_HINT
							|| ev == FileMonitorEvent.CHANGED
							|| ev == FileMonitorEvent.CREATED
							|| ev == FileMonitorEvent.MOVED_IN) {
							browser_sessions_changed ();
						}
					});
					list.add (mon);
				} catch (Error e) {}
			}
			if (list.size > 0)
				browser_monitors.set (family, list);
		}

		public bool is_os_wrapper_binary (string exe_basename)
		{
			string lower = exe_basename.down ();
			return lower == "cmd.exe" || lower == "powershell.exe" || lower == "pwsh.exe"
				|| lower == "wscript.exe" || lower == "cscript.exe";
		}

		public string read_wrapper_script (string exe_or_path, out string resolved_path)
		{
			resolved_path = "";
			return "";
		}

		public ProcessSnapshot inspect_process (int pid, bool include_children_and_fds = false)
		{
			var snap = new ProcessSnapshot ();
			snap.pid = pid;
			if (pid <= 0)
				return snap;

			snap.is_alive = Win32AppBridge.is_process_alive (pid) != 0;
			snap.uid_matches_self = true;
			string? exe = Win32AppBridge.get_process_exe (pid);
			if (exe != null && exe.length > 0) {
				snap.exe_realpath = exe;
				snap.executable_comm = path_stem (exe);
				snap.full_cmdline = quote_win_arg (exe);
				snap.cmdline_argv = new string[] { exe };
			}
			return snap;
		}

		public bool is_process_alive (int pid)
		{
			return Win32AppBridge.is_process_alive (pid) != 0;
		}

		public Gee.ArrayList<ProcessSnapshot> scan_user_processes ()
		{
			var list = new Gee.ArrayList<ProcessSnapshot> ();
			Win32AppBridge.enum_processes ((pid, exe_name, exe_path) => {
				if (pid <= 0 || exe_path.length == 0)
					return;
				var snap = new ProcessSnapshot ();
				snap.pid = pid;
				snap.is_alive = true;
				snap.uid_matches_self = true;
				snap.executable_comm = path_stem (exe_name);
				snap.exe_realpath = exe_path;
				snap.full_cmdline = quote_win_arg (exe_path);
				snap.cmdline_argv = new string[] { exe_path };
				list.add (snap);
			});
			return list;
		}

		public int find_pid_by_app_hint (string app_hint, string caption_hint = "")
		{
			string needle = app_hint.down ();
			if (needle.length == 0)
				return 0;
			int found = 0;
			Win32AppBridge.enum_processes ((pid, exe_name, exe_path) => {
				if (found != 0)
					return;
				if (path_stem (exe_name).down () == needle)
					found = pid;
			});
			return found;
		}

		public Gee.ArrayList<RecentDocInfo> get_recent_documents (string launcher_uri, int max_items = 10)
		{
			var results = new Gee.ArrayList<RecentDocInfo> ();
			string? recent_dir = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_RECENT);
			if (recent_dir == null || !FileUtils.test (recent_dir, FileTest.IS_DIR))
				return results;

			try {
				var dir = Dir.open (recent_dir);
				string? name;
				while ((name = dir.read_name ()) != null) {
					if (!name.down ().has_suffix (".lnk"))
						continue;
					string full = Path.build_filename (recent_dir, name);
					string? target = null;
					string? args = null;
					string? workdir = null;
					string? desc_str = null;
					string? icon_path = null;
					int icon_idx = 0;
					string? aumid = null;
					if (Win32AppBridge.resolve_lnk (full, out target, out args, out workdir, out desc_str, out icon_path, out icon_idx, out aumid) == 0)
						continue;
					if (target == null || target.length == 0 || !FileUtils.test (target, FileTest.IS_REGULAR))
						continue;

					var info = new RecentDocInfo ();
					info.uri = to_file_uri (target);
					info.display_name = Path.get_basename (target);
					info.tooltip_path = target;
					info.icon_token = target;
					try {
						var fi = File.new_for_path (full).query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
						info.modified_unix = (int64) fi.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
					} catch (Error e) {}
					results.add (info);
				}
			} catch (Error e) {}

			results.sort ((a, b) => {
				if (a.modified_unix > b.modified_unix) return -1;
				if (a.modified_unix < b.modified_unix) return 1;
				return 0;
			});

			if (max_items > 0 && results.size > max_items) {
				var trimmed = new Gee.ArrayList<RecentDocInfo> ();
				for (int i = 0; i < max_items; i++)
					trimmed.add (results[i]);
				return trimmed;
			}
			return results;
		}

		static bool is_win_icon_spec (string token)
		{
			if (token.length == 0)
				return false;
			if (token.has_prefix ("resource://"))
				return false;
			string base_path = token.has_prefix ("winico:") ? token.substring (7) : token;
			int comma = base_path.last_index_of_char (',');
			if (comma > 0)
				base_path = base_path.substring (0, comma);
			if (Path.is_absolute (base_path) && FileUtils.test (base_path, FileTest.EXISTS))
				return true;
			return false;
		}

		static uint16 read_u16_le (uint8[] data, int off)
		{
			return (uint16) data[off] | ((uint16) data[off + 1] << 8);
		}

		static uint32 read_u32_le (uint8[] data, int off)
		{
			return (uint32) data[off]
				| ((uint32) data[off + 1] << 8)
				| ((uint32) data[off + 2] << 16)
				| ((uint32) data[off + 3] << 24);
		}

		static Gdk.Pixbuf? decode_ico_file (string path, int req_size)
		{
			uint8[] data;
			try {
				if (!FileUtils.get_data (path, out data) || data.length < 22)
					return null;
			} catch (Error e) {
				return null;
			}

			uint16 reserved = read_u16_le (data, 0);
			uint16 ico_type = read_u16_le (data, 2);
			uint16 count = read_u16_le (data, 4);
			if (reserved != 0 || (ico_type != 1 && ico_type != 2) || count == 0)
				return null;

			int best_png_off = -1, best_png_sz = 0, best_png_dim = 0;
			int best_dib_off = -1, best_dib_sz = 0, best_dib_dim = 0;

			for (int i = 0; i < count; i++) {
				int entry = 6 + i * 16;
				if (entry + 16 > data.length)
					break;
				int w = (data[entry] == 0) ? 256 : (int) data[entry];
				int h = (data[entry + 1] == 0) ? 256 : (int) data[entry + 1];
				int dim = int.max (w, h);
				uint32 sz = read_u32_le (data, entry + 8);
				uint32 off = read_u32_le (data, entry + 12);
				if (off + sz > (uint32) data.length || sz < 16)
					continue;

				int ioff = (int) off;
				int isz = (int) sz;
				/* Embedded PNG entry (e.g. Chrome/Edge 256x256 Google Profile.ico) */
				if (data[ioff] == 0x89 && data[ioff + 1] == 0x50 && data[ioff + 2] == 0x4E && data[ioff + 3] == 0x47) {
					if (dim >= best_png_dim) {
						best_png_dim = dim;
						best_png_off = ioff;
						best_png_sz = isz;
					}
				} else if (isz >= 40) {
					uint32 bi_size = read_u32_le (data, ioff);
					uint16 bi_bpp = read_u16_le (data, ioff + 14);
					uint32 bi_comp = read_u32_le (data, ioff + 16);
					if (bi_size == 40 && bi_bpp == 32 && bi_comp == 0 && dim >= best_dib_dim) {
						best_dib_dim = dim;
						best_dib_off = ioff;
						best_dib_sz = isz;
					}
				}
			}

			if (best_png_off >= 0 && best_png_sz > 0) {
				try {
					var loader = new Gdk.PixbufLoader.with_type ("png");
					loader.set_size (req_size, req_size);
					loader.write (data[best_png_off : best_png_off + best_png_sz]);
					loader.close ();
					var pb = loader.get_pixbuf ();
					if (pb != null)
						return pb;
				} catch (Error e) {}
			}

			if (best_dib_off >= 0 && best_dib_sz >= 40) {
				int w = (int) read_u32_le (data, best_dib_off + 4);
				int h_total = (int) read_u32_le (data, best_dib_off + 8);
				int h = (h_total > 0) ? (h_total / 2) : (-h_total / 2);
				int px_off = best_dib_off + 40;
				int byte_len = w * h * 4;
				if (w > 0 && h > 0 && px_off + byte_len <= data.length) {
					uint8[] rgba = new uint8[byte_len];
					for (int y = 0; y < h; y++) {
						int src_row = px_off + (h - 1 - y) * w * 4;
						int dst_row = y * w * 4;
						for (int x = 0; x < w; x++) {
							int s = src_row + x * 4;
							int d = dst_row + x * 4;
							rgba[d + 0] = data[s + 2];
							rgba[d + 1] = data[s + 1];
							rgba[d + 2] = data[s + 0];
							rgba[d + 3] = data[s + 3];
						}
					}
					var pb = new Gdk.Pixbuf.from_data ((owned) rgba, Gdk.Colorspace.RGB, true, 8, w, h, w * 4);
					if (w != req_size || h != req_size)
						return pb.scale_simple (req_size, req_size, Gdk.InterpType.BILINEAR);
					return pb;
				}
			}

			return null;
		}

		public Gdk.Pixbuf? load_native_icon (string token, int size)
		{
			if (!is_win_icon_spec (token))
				return null;

			int req = (size > 0) ? size : 64;
			string key = "%s@%d".printf (token.down (), req);
			if (icon_cache.has_key (key))
				return icon_cache.get (key);

			/* Direct raster/vector/ico image files */
			string base_path = token.has_prefix ("winico:") ? token.substring (7) : token;
			int comma = base_path.last_index_of_char (',');
			if (comma > 0)
				base_path = base_path.substring (0, comma);
			string lower = base_path.down ();
			if (lower.has_suffix (".ico")) {
				var ico_pb = decode_ico_file (base_path, req);
				if (ico_pb != null) {
					icon_cache.set (key, ico_pb);
					return ico_pb;
				}
				return null;
			}
			if (lower.has_suffix (".png") || lower.has_suffix (".svg") || lower.has_suffix (".bmp") || lower.has_suffix (".gif")) {
				try {
					var pb = new Gdk.Pixbuf.from_file_at_scale (base_path, req, req, true);
					icon_cache.set (key, pb);
					return pb;
				} catch (Error e) {
					return null;
				}
			}

			uint8* rgba_ptr = null;
			int out_w = 0;
			int out_h = 0;
			if (Win32AppBridge.extract_icon_rgba (token, req, out rgba_ptr, out out_w, out out_h) == 0
				|| rgba_ptr == null || out_w <= 0 || out_h <= 0) {
				if (rgba_ptr != null)
					Win32AppBridge.free_buffer (rgba_ptr);
				/* Fallback: if .lnk failed, extract directly from its target .exe */
				if (lower.has_suffix (".lnk")) {
					string? target = null, args = null, workdir = null, desc_str = null, icon_p = null, aumid = null;
					int icon_i = 0;
					if (Win32AppBridge.resolve_lnk (base_path, out target, out args, out workdir, out desc_str, out icon_p, out icon_i, out aumid) != 0
						&& target != null && target.length > 0 && target.down () != base_path.down ()) {
						return load_native_icon (target, req);
					}
				}
				return null;
			}

			int rowstride = out_w * 4;
			int total_bytes = rowstride * out_h;
			uint8[] pixels = new uint8[total_bytes];
			Memory.copy (pixels, rgba_ptr, total_bytes);
			Win32AppBridge.free_buffer (rgba_ptr);

			var pixbuf = new Gdk.Pixbuf.from_data (
				(owned) pixels,
				Gdk.Colorspace.RGB,
				true,
				8,
				out_w,
				out_h,
				rowstride
			);
			if (icon_cache.size > 512)
				icon_cache.clear ();
			icon_cache.set (key, pixbuf);
			return pixbuf;
		}

		public bool has_native_icon (string token)
		{
			return is_win_icon_spec (token);
		}

		public string? get_file_icon_token (GLib.File file)
		{
			string? p = file.get_path ();
			if (p != null && p.length > 0 && FileUtils.test (p, FileTest.EXISTS))
				return p;
			return null;
		}

		public string[] get_extra_drop_target_atoms ()
		{
			return {};
		}

		public Gee.ArrayList<string> decode_native_drop_selection (Gtk.SelectionData selection_data)
		{
			return new Gee.ArrayList<string> ();
		}

		public void cleanup ()
		{
			foreach (var list in browser_monitors.values) {
				foreach (var mon in list)
					mon.cancel ();
			}
			browser_monitors.clear ();
			icon_cache.clear ();
			cached_apps = null;
		}
	}
}
