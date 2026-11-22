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

		const int LNK_CACHE_VERSION = 1;

		class CachedLnkRecord : GLib.Object
		{
			public string path = "";
			public int64 mtime = 0;
			public int64 size = 0;
			public string target = "";
			public string args = "";
			public string workdir = "";
			public string description = "";
			public string icon_path = "";
			public int icon_idx = 0;
			public string aumid = "";
			public bool is_dir = false;
			public bool tgt_exists = true;
			public bool icon_exists = false;
		}

		Gee.ArrayList<AppDescriptor>? cached_apps = null;
		Gee.ArrayList<GLib.File>? cached_launcher_dirs = null;
		Gee.ArrayList<string>? cached_native_icon_tokens = null;
		Gee.HashMap<string, CachedLnkRecord> disk_lnk_records;
		Gee.HashMap<string, AppDescriptor?> lnk_cache;
		Gee.HashMap<string, AppDescriptor> uwp_apps_by_aumid;
		bool uwp_apps_enumerated = false;
		Gee.HashMap<string, string> apps_by_id;
		Gee.HashSet<string> failed_icon_keys;
		Gee.HashMap<string, Gdk.Pixbuf> icon_cache;
		Gee.HashMap<string, string> custom_icon_overrides;
		Gee.HashMap<BrowserFamily, Gee.ArrayList<GLib.FileMonitor>> browser_monitors;
		bool disk_cache_initialized = false;
		bool bg_sync_running = false;
		bool is_cleaned_up = false;
		uint bg_sync_timer_id = 0U;
		uint save_cache_timer_id = 0U;

		construct
		{
			disk_lnk_records = new Gee.HashMap<string, CachedLnkRecord> ();
			lnk_cache = new Gee.HashMap<string, AppDescriptor?> ();
			uwp_apps_by_aumid = new Gee.HashMap<string, AppDescriptor> ();
			apps_by_id = new Gee.HashMap<string, string> ();
			failed_icon_keys = new Gee.HashSet<string> ();
			icon_cache = new Gee.HashMap<string, Gdk.Pixbuf> ();
			custom_icon_overrides = new Gee.HashMap<string, string> ();
			browser_monitors = new Gee.HashMap<BrowserFamily, Gee.ArrayList<GLib.FileMonitor>> ();
		}

		~Win32AppSystem ()
		{
			cleanup ();
		}

		static bool is_network_path (string path)
		{
			return path.has_prefix ("\\\\") || path.has_prefix ("//");
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

		static string get_lnk_cache_file_path ()
		{
			string? local = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_LOCAL_APPDATA);
			if (local == null || local.length == 0)
				local = Environment.get_user_data_dir ();
			string dir = Path.build_filename (local, "WayPlank");
			DirUtils.create_with_parents (dir, 0755);
			return Path.build_filename (dir, "lnk-index-cache.ini");
		}

		static void collect_dir_tree (string dir_path, int depth, Gee.ArrayList<string> out_dirs, Gee.HashSet<string> seen)
		{
			if (depth > 4 || dir_path.length == 0 || !FileUtils.test (dir_path, FileTest.IS_DIR))
				return;
			string key = dir_path.down ();
			if (!seen.contains (key)) {
				seen.add (key);
				out_dirs.add (dir_path);
			}
			if (depth >= 4)
				return;
			try {
				var dir = Dir.open (dir_path);
				string? name;
				while ((name = dir.read_name ()) != null) {
					if (name == "." || name == "..")
						continue;
					string sub = Path.build_filename (dir_path, name);
					if (FileUtils.test (sub, FileTest.IS_DIR))
						collect_dir_tree (sub, depth + 1, out_dirs, seen);
				}
			} catch (Error e) {}
		}

		static Gee.ArrayList<string> collect_all_index_dirs ()
		{
			var dirs = new Gee.ArrayList<string> ();
			var seen = new Gee.HashSet<string> ();

			int[] recursive_roots = {
				Win32AppBridge.FOLDER_COMMON_STARTMENU,
				Win32AppBridge.FOLDER_COMMON_PROGRAMS,
				Win32AppBridge.FOLDER_USER_STARTMENU,
				Win32AppBridge.FOLDER_USER_PROGRAMS
			};
			foreach (int fid in recursive_roots) {
				string? p = Win32AppBridge.get_known_folder (fid);
				if (p != null && p.length > 0)
					collect_dir_tree (p, 0, dirs, seen);
			}

			int[] flat_roots = {
				Win32AppBridge.FOLDER_COMMON_DESKTOP,
				Win32AppBridge.FOLDER_USER_DESKTOP
			};
			foreach (int fid in flat_roots) {
				string? p = Win32AppBridge.get_known_folder (fid);
				if (p != null && p.length > 0 && FileUtils.test (p, FileTest.IS_DIR)) {
					string key = p.down ();
					if (!seen.contains (key)) {
						seen.add (key);
						dirs.add (p);
					}
				}
			}
			return dirs;
		}

		public Gee.ArrayList<GLib.File> discover_launcher_dirs ()
		{
			/* Mirror Linux's flat 5-directory layout so ApplicationDiscovery attaches only
			 * 5 lightweight root monitors at startup; full Start Menu subtrees are indexed
			 * instantaneously via persistent disk cache in discover_installed_apps(). */
			if (cached_launcher_dirs == null) {
				var dirs = new Gee.ArrayList<GLib.File> ();
				var seen = new Gee.HashSet<string> ();

				string synth = get_synthetic_dir ();
				if (FileUtils.test (synth, FileTest.IS_DIR)) {
					seen.add (synth.down ());
					dirs.add (File.new_for_path (synth));
				}

				int[] root_ids = {
					Win32AppBridge.FOLDER_COMMON_PROGRAMS,
					Win32AppBridge.FOLDER_USER_PROGRAMS,
					Win32AppBridge.FOLDER_COMMON_DESKTOP,
					Win32AppBridge.FOLDER_USER_DESKTOP
				};
				foreach (int fid in root_ids) {
					string? p = Win32AppBridge.get_known_folder (fid);
					if (p != null && p.length > 0 && FileUtils.test (p, FileTest.IS_DIR)) {
						string key = p.down ();
						if (!seen.contains (key)) {
							seen.add (key);
							dirs.add (File.new_for_path (p));
						}
					}
				}

				cached_launcher_dirs = dirs;
			}

			var copy = new Gee.ArrayList<GLib.File> ();
			foreach (var d in cached_launcher_dirs)
				copy.add (d);
			return copy;
		}

		static CachedLnkRecord? resolve_lnk_to_record (string path, int64 mtime, int64 size)
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

			var rec = new CachedLnkRecord ();
			rec.path = path;
			rec.mtime = mtime;
			rec.size = size;
			rec.target = tgt;
			rec.args = (args != null) ? args.strip () : "";
			rec.workdir = workdir ?? "";
			rec.description = desc_str ?? "";
			rec.icon_path = (icon_path != null) ? icon_path.strip () : "";
			rec.icon_idx = icon_idx;
			rec.aumid = (aumid != null) ? aumid.strip () : "";

			/* Never call stat() on UNC, mapped network (DRIVE_REMOTE), optical, or removable
			 * drives — avoids 20-45s SMB/hardware stalls on offline or sleeping targets. */
			if (Win32AppBridge.is_fixed_local_drive (tgt) != 0) {
				rec.is_dir = FileUtils.test (tgt, FileTest.IS_DIR);
				rec.tgt_exists = rec.is_dir || FileUtils.test (tgt, FileTest.EXISTS);
			} else {
				rec.is_dir = false;
				rec.tgt_exists = !is_network_path (tgt);
			}

			if (rec.icon_path.length > 0 && Win32AppBridge.is_fixed_local_drive (rec.icon_path) != 0)
				rec.icon_exists = FileUtils.test (rec.icon_path, FileTest.EXISTS);
			else
				rec.icon_exists = false;

			return rec;
		}

		AppDescriptor build_descriptor_from_record (CachedLnkRecord rec)
		{
			var d = new AppDescriptor ();
			d.uri = to_file_uri (rec.path);
			string lnk_stem = path_stem (rec.path);
			string tgt = rec.target;
			string tgt_stem = path_stem (tgt);

			if (rec.is_dir) {
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

			string arg_str = rec.args;
			string arg_low = arg_str.down ();
			string tgt_base = Path.get_basename (tgt);
			string tgt_base_low = tgt_base.down ();
			bool is_wrapper_shortcut = (arg_str.length > 0 && is_os_wrapper_binary (tgt_base));
			bool is_pwa_or_specialized = (tgt_base_low == "chrome_proxy.exe"
				|| tgt_base_low == "msedge_proxy.exe"
				|| tgt_base_low == "brave_proxy.exe"
				|| arg_low.contains ("--app-id=")
				|| arg_low.contains ("--app="));
			bool use_lnk_stem = (is_wrapper_shortcut || is_pwa_or_specialized);

			d.display_name = lnk_stem;
			d.unlocalized_name = lnk_stem;
			d.comment = rec.description;
			d.working_dir = rec.workdir;
			d.base_id = (!use_lnk_stem && tgt_stem.length > 0)
				? normalize_app_id (tgt_stem)
				: normalize_app_id (lnk_stem);
			if (normalize_app_id (lnk_stem) != d.base_id)
				d.alias_ids.add (normalize_app_id (lnk_stem));
			d.alias_ids.add (normalize_app_id (lnk_stem).replace (" ", "-"));
			if (!use_lnk_stem && tgt_stem.length > 0)
				d.wm_classes_or_aumids.add (normalize_app_id (tgt_stem));
			if (rec.aumid.length > 0) {
				d.startup_wm_class_or_aumid = rec.aumid;
				if (!d.wm_classes_or_aumids.contains (rec.aumid.down ()))
					d.wm_classes_or_aumids.add (rec.aumid.down ());
			}

			d.exec_command = (arg_str.length > 0)
				? "%s %s".printf (quote_win_arg (tgt), arg_str)
				: quote_win_arg (tgt);

			string chosen_icon = "";
			if (rec.icon_exists && rec.icon_path.length > 0) {
				chosen_icon = rec.icon_path.down ().has_suffix (".ico")
					? ("winico:" + rec.icon_path)
					: ((rec.icon_idx != 0) ? "%s,%d".printf (rec.icon_path, rec.icon_idx) : rec.icon_path);
			}
			if (chosen_icon.length == 0 && rec.tgt_exists)
				chosen_icon = tgt;
			if (chosen_icon.length == 0 && !is_network_path (rec.path))
				chosen_icon = rec.path;
			d.icon_token = (chosen_icon.length > 0) ? chosen_icon : "application-default-icon";

			if (custom_icon_overrides.has_key (d.uri.down ())) {
				d.icon_token = custom_icon_overrides.get (d.uri.down ());
				d.has_custom_icon_override = true;
			}

			d.is_launchable = is_exec;
			d.is_non_app_launcher = !is_exec;
			d.has_explicit_app_type = is_exec;
			d.try_exec_satisfied = rec.tgt_exists;
			d.supports_files = is_exec;
			d.supports_uris = is_exec;
			d.is_shown_in_current_desktop = true;
			return d;
		}

		void rebuild_apps_memory_index ()
		{
			var next_apps = new Gee.ArrayList<AppDescriptor> ();
			var next_by_id = new Gee.HashMap<string, string> ();
			var seen_uris = new Gee.HashSet<string> ();

			/* 1. Include user synthetic .wayplank-app launchers first */
			string synth_dir = get_synthetic_dir ();
			if (FileUtils.test (synth_dir, FileTest.IS_DIR)) {
				try {
					var dir = Dir.open (synth_dir);
					string? name;
					while ((name = dir.read_name ()) != null) {
						if (!name.down ().has_suffix (".wayplank-app"))
							continue;
						var sdesc = load_synthetic_descriptor (Path.build_filename (synth_dir, name));
						if (sdesc != null && sdesc.is_launchable) {
							string ukey = sdesc.uri.down ();
							if (seen_uris.add (ukey)) {
								next_apps.add (sdesc);
								if (sdesc.base_id.length > 0 && !next_by_id.has_key (sdesc.base_id))
									next_by_id.set (sdesc.base_id, sdesc.uri);
								string dlow = sdesc.display_name.down ();
								if (dlow.length > 0 && !next_by_id.has_key (dlow))
									next_by_id.set (dlow, sdesc.uri);
							}
						}
					}
				} catch (Error e) {}
			}

			/* 2. Build descriptors purely in RAM from persistent disk_lnk_records */
			foreach (var entry in disk_lnk_records.entries) {
				var rec = entry.value;
				string lower_name = Path.get_basename (rec.path).down ();
				if (is_uninstaller_name (lower_name))
					continue;
				var desc = build_descriptor_from_record (rec);
				lnk_cache.set (entry.key, desc);
				if (desc.is_launchable && !desc.is_non_app_launcher) {
					string ukey = desc.uri.down ();
					if (seen_uris.add (ukey)) {
						next_apps.add (desc);
						if (desc.base_id.length > 0 && !next_by_id.has_key (desc.base_id))
							next_by_id.set (desc.base_id, desc.uri);
						string dlow = desc.display_name.down ();
						if (dlow.length > 0 && !next_by_id.has_key (dlow))
							next_by_id.set (dlow, desc.uri);
					}
				}
			}

			/* 3. Include cold-discovered packaged UWP/MSIX apps from FOLDERID_AppsFolder */
			ensure_uwp_apps_loaded ();
			foreach (var uwp_desc in uwp_apps_by_aumid.values) {
				string ukey = uwp_desc.uri.down ();
				if (seen_uris.add (ukey)) {
					next_apps.add (uwp_desc);
					if (uwp_desc.base_id.length > 0 && !next_by_id.has_key (uwp_desc.base_id))
						next_by_id.set (uwp_desc.base_id, uwp_desc.uri);
					string dlow = uwp_desc.display_name.down ();
					if (dlow.length > 0 && !next_by_id.has_key (dlow))
						next_by_id.set (dlow, uwp_desc.uri);
				}
			}

			cached_apps = next_apps;
			apps_by_id = next_by_id;
		}

		void ensure_uwp_apps_loaded ()
		{
			if (uwp_apps_enumerated)
				return;
			uwp_apps_enumerated = true;
			Win32AppBridge.enum_uwp_apps ((aumid, display_name, install_path) => {
				string clean_id = aumid.strip ();
				string clean_name = display_name.strip ();
				if (clean_id.length == 0 || clean_name.length == 0)
					return;
				string akey = clean_id.down ();
				if (uwp_apps_by_aumid.has_key (akey))
					return;

				var d = new AppDescriptor ();
				d.uri = "aumid://" + clean_id;
				d.display_name = clean_name;
				d.unlocalized_name = clean_name;
				int bang = clean_id.index_of_char ('!');
				string pkg_prefix = (bang > 0) ? clean_id.substring (0, bang) : clean_id;
				int us = pkg_prefix.index_of_char ('_');
				string short_pkg = (us > 0) ? pkg_prefix.substring (0, us) : pkg_prefix;
				d.base_id = normalize_app_id (short_pkg);
				d.startup_wm_class_or_aumid = clean_id;
				d.wm_classes_or_aumids.add (akey);
				if (short_pkg.length > 0)
					d.wm_classes_or_aumids.add (normalize_app_id (short_pkg));
				d.exec_command = (install_path.length > 0) ? quote_win_arg (install_path) : clean_id;
				d.icon_token = "aumidico:" + clean_id;
				if (custom_icon_overrides.has_key (d.uri.down ())) {
					d.icon_token = custom_icon_overrides.get (d.uri.down ());
					d.has_custom_icon_override = true;
				}
				d.is_launchable = true;
				d.has_explicit_app_type = true;
				d.try_exec_satisfied = true;
				d.supports_files = false;
				d.supports_uris = true;
				d.is_shown_in_current_desktop = true;
				uwp_apps_by_aumid.set (akey, d);
			});
		}

		bool load_disk_cache_file ()
		{
			string cache_path = get_lnk_cache_file_path ();
			if (!FileUtils.test (cache_path, FileTest.IS_REGULAR))
				return false;

			var kf = new KeyFile ();
			try {
				kf.load_from_file (cache_path, KeyFileFlags.NONE);
				if (!kf.has_group ("Meta") || !kf.has_key ("Meta", "CacheVersion"))
					return false;
				if (kf.get_integer ("Meta", "CacheVersion") != LNK_CACHE_VERSION)
					return false;

				int count = kf.has_key ("Meta", "Count") ? kf.get_integer ("Meta", "Count") : 0;
				if (count <= 0)
					return false;

				var loaded = new Gee.HashMap<string, CachedLnkRecord> ();
				for (int i = 0; i < count; i++) {
					string grp = "%d".printf (i);
					if (!kf.has_group (grp))
						continue;
					string p = kf.has_key (grp, "Path") ? kf.get_string (grp, "Path") : "";
					string tgt = kf.has_key (grp, "Target") ? kf.get_string (grp, "Target") : "";
					if (p.length == 0 || tgt.length == 0)
						continue;

					var rec = new CachedLnkRecord ();
					rec.path = p;
					rec.mtime = kf.has_key (grp, "Mtime") ? kf.get_int64 (grp, "Mtime") : 0;
					rec.size = kf.has_key (grp, "Size") ? kf.get_int64 (grp, "Size") : 0;
					rec.target = tgt;
					rec.args = kf.has_key (grp, "Args") ? kf.get_string (grp, "Args") : "";
					rec.workdir = kf.has_key (grp, "WorkDir") ? kf.get_string (grp, "WorkDir") : "";
					rec.description = kf.has_key (grp, "Desc") ? kf.get_string (grp, "Desc") : "";
					rec.icon_path = kf.has_key (grp, "Icon") ? kf.get_string (grp, "Icon") : "";
					rec.icon_idx = kf.has_key (grp, "IconIdx") ? kf.get_integer (grp, "IconIdx") : 0;
					rec.aumid = kf.has_key (grp, "Aumid") ? kf.get_string (grp, "Aumid") : "";
					rec.is_dir = kf.has_key (grp, "IsDir") && kf.get_boolean (grp, "IsDir");
					rec.tgt_exists = !kf.has_key (grp, "TgtExists") || kf.get_boolean (grp, "TgtExists");
					rec.icon_exists = kf.has_key (grp, "IconExists") && kf.get_boolean (grp, "IconExists");
					loaded.set (p.down (), rec);
				}

				if (loaded.size == 0)
					return false;

				disk_lnk_records = loaded;
				return true;
			} catch (Error e) {
				return false;
			}
		}

		void save_disk_cache_file ()
		{
			string cache_path = get_lnk_cache_file_path ();
			var kf = new KeyFile ();
			kf.set_integer ("Meta", "CacheVersion", LNK_CACHE_VERSION);
			int idx = 0;
			foreach (var rec in disk_lnk_records.values) {
				string grp = "%d".printf (idx++);
				kf.set_string (grp, "Path", rec.path);
				kf.set_int64 (grp, "Mtime", rec.mtime);
				kf.set_int64 (grp, "Size", rec.size);
				kf.set_string (grp, "Target", rec.target);
				if (rec.args.length > 0) kf.set_string (grp, "Args", rec.args);
				if (rec.workdir.length > 0) kf.set_string (grp, "WorkDir", rec.workdir);
				if (rec.description.length > 0) kf.set_string (grp, "Desc", rec.description);
				if (rec.icon_path.length > 0) kf.set_string (grp, "Icon", rec.icon_path);
				if (rec.icon_idx != 0) kf.set_integer (grp, "IconIdx", rec.icon_idx);
				if (rec.aumid.length > 0) kf.set_string (grp, "Aumid", rec.aumid);
				if (rec.is_dir) kf.set_boolean (grp, "IsDir", true);
				if (!rec.tgt_exists) kf.set_boolean (grp, "TgtExists", false);
				if (rec.icon_exists) kf.set_boolean (grp, "IconExists", true);
			}
			kf.set_integer ("Meta", "Count", idx);
			try {
				FileUtils.set_contents (cache_path, kf.to_data ());
			} catch (Error e) {}
		}

		void schedule_save_disk_cache ()
		{
			if (is_cleaned_up || save_cache_timer_id != 0U)
				return;
			GLib.WeakRef weak_self = GLib.WeakRef (this);
			save_cache_timer_id = GLib.Timeout.add (1500, () => {
				var self = (Win32AppSystem?) weak_self.get ();
				if (self == null || self.is_cleaned_up)
					return Source.REMOVE;
				self.save_cache_timer_id = 0U;
				self.save_disk_cache_file ();
				return Source.REMOVE;
			});
		}

		void scan_all_start_menu_cold_sync ()
		{
			int64 t0 = GLib.get_monotonic_time ();
			var dirs = collect_all_index_dirs ();
			foreach (var dir_path in dirs) {
				try {
					var dir = Dir.open (dir_path);
					string? name;
					while ((name = dir.read_name ()) != null) {
						if (name == "." || name == "..")
							continue;
						string lower = name.down ();
						if (!lower.has_suffix (".lnk") || is_uninstaller_name (lower))
							continue;
						string full = Path.build_filename (dir_path, name);
						string pkey = full.down ();
						if (disk_lnk_records.has_key (pkey))
							continue;
						int64 mtime = 0, fsz = 0;
						if (Win32AppBridge.get_file_stamp (full, out mtime, out fsz) == 0)
							continue;
						var rec = resolve_lnk_to_record (full, mtime, fsz);
						if (rec != null)
							disk_lnk_records.set (pkey, rec);
					}
				} catch (Error e) {}
			}
			int64 elapsed_ms = (GLib.get_monotonic_time () - t0) / 1000;
			if (elapsed_ms > 500)
				message ("Win32AppSystem: initial cold .lnk index built (%d entries in %lld ms)", disk_lnk_records.size, elapsed_ms);
			save_disk_cache_file ();
		}

		void schedule_bg_delta_sync (uint delay_ms)
		{
			if (is_cleaned_up || bg_sync_running)
				return;
			if (bg_sync_timer_id != 0U) {
				Source.remove (bg_sync_timer_id);
				bg_sync_timer_id = 0U;
			}
			GLib.WeakRef weak_self = GLib.WeakRef (this);
			bg_sync_timer_id = GLib.Timeout.add (delay_ms, () => {
				var self = (Win32AppSystem?) weak_self.get ();
				if (self == null || self.is_cleaned_up)
					return Source.REMOVE;
				self.bg_sync_timer_id = 0U;
				self.launch_bg_delta_sync ();
				return Source.REMOVE;
			});
		}

		void launch_bg_delta_sync ()
		{
			if (is_cleaned_up || bg_sync_running)
				return;
			bg_sync_running = true;

			/* Immutable snapshot of known path -> "mtime:size" handed to worker thread */
			var snapshot = new Gee.HashMap<string, string> ();
			foreach (var e in disk_lnk_records.entries)
				snapshot.set (e.key, "%lld:%lld".printf (e.value.mtime, e.value.size));

			GLib.WeakRef weak_self = GLib.WeakRef (this);
			new Thread<void*> ("wayplank-lnk-delta", () => {
				Win32AppBridge.set_thread_low_priority ();
				var dirs = collect_all_index_dirs ();
				var live_keys = new Gee.HashSet<string> ();
				var updated = new Gee.HashMap<string, CachedLnkRecord> ();

				foreach (var dir_path in dirs) {
					try {
						var dir = Dir.open (dir_path);
						string? name;
						while ((name = dir.read_name ()) != null) {
							if (name == "." || name == "..")
								continue;
							string lower = name.down ();
							if (!lower.has_suffix (".lnk") || is_uninstaller_name (lower))
								continue;
							string full = Path.build_filename (dir_path, name);
							string pkey = full.down ();
							if (!live_keys.add (pkey))
								continue;

							int64 mtime = 0, fsz = 0;
							if (Win32AppBridge.get_file_stamp (full, out mtime, out fsz) == 0)
								continue;
							string stamp = "%lld:%lld".printf (mtime, fsz);
							if (snapshot.has_key (pkey) && snapshot.get (pkey) == stamp)
								continue;

							var rec = resolve_lnk_to_record (full, mtime, fsz);
							if (rec != null)
								updated.set (pkey, rec);
						}
					} catch (Error e) {}
				}

				var removed = new Gee.ArrayList<string> ();
				foreach (var old_key in snapshot.keys) {
					if (!live_keys.contains (old_key))
						removed.add (old_key);
				}

				GLib.Idle.add (() => {
					var self = (Win32AppSystem?) weak_self.get ();
					if (self == null || self.is_cleaned_up)
						return Source.REMOVE;
					self.bg_sync_running = false;
					if (updated.size > 0 || removed.size > 0) {
						foreach (var rk in removed) {
							self.disk_lnk_records.unset (rk);
							self.lnk_cache.unset (rk);
						}
						foreach (var ue in updated.entries)
							self.disk_lnk_records.set (ue.key, ue.value);
						self.rebuild_apps_memory_index ();
						self.save_disk_cache_file ();
						self.apps_changed ();
					}
					return Source.REMOVE;
				});
				return null;
			});
		}

		void ensure_disk_cache_initialized ()
		{
			if (disk_cache_initialized)
				return;
			disk_cache_initialized = true;

			if (load_disk_cache_file ()) {
				rebuild_apps_memory_index ();
				schedule_bg_delta_sync (1500);
			} else {
				scan_all_start_menu_cold_sync ();
				rebuild_apps_memory_index ();
			}
		}

		public Gee.ArrayList<AppDescriptor> discover_installed_apps (bool include_nodisplay = true)
		{
			ensure_disk_cache_initialized ();
			var copy = new Gee.ArrayList<AppDescriptor> ();
			if (cached_apps != null) {
				foreach (var a in cached_apps) {
					if (include_nodisplay || !a.is_nodisplay)
						copy.add (a);
				}
			}
			return copy;
		}

		public void set_extra_watched_directories (string[] folder_uris)
		{
		}

		public void invalidate_cache ()
		{
			failed_icon_keys.clear ();
			if (disk_cache_initialized)
				schedule_bg_delta_sync (200);
			apps_changed ();
		}

		AppDescriptor? load_lnk_descriptor (string path)
		{
			ensure_disk_cache_initialized ();
			string pkey = path.down ();
			if (lnk_cache.has_key (pkey))
				return lnk_cache.get (pkey);

			int64 mtime = 0, fsz = 0;
			bool has_stamp = (Win32AppBridge.get_file_stamp (path, out mtime, out fsz) != 0);

			if (!has_stamp && Win32AppBridge.is_fixed_local_drive (path) != 0) {
				if (disk_lnk_records.unset (pkey))
					schedule_save_disk_cache ();
				lnk_cache.unset (pkey);
				return null;
			}

			if (disk_lnk_records.has_key (pkey)) {
				var cached_rec = disk_lnk_records.get (pkey);
				if (!has_stamp || (cached_rec.mtime == mtime && cached_rec.size == fsz)) {
					var desc = build_descriptor_from_record (cached_rec);
					if (lnk_cache.size > 4096)
						lnk_cache.clear ();
					lnk_cache.set (pkey, desc);
					return desc;
				}
			}

			if (lnk_cache.size > 4096)
				lnk_cache.clear ();

			var rec = resolve_lnk_to_record (path, mtime, fsz);
			if (rec == null) {
				lnk_cache.set (pkey, null);
				return null;
			}

			var d = build_descriptor_from_record (rec);
			if (disk_lnk_records.size < 4096) {
				disk_lnk_records.set (pkey, rec);
				schedule_save_disk_cache ();
			}
			lnk_cache.set (pkey, d);
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
				string raw_aumid = kf.has_key ("WayPlankApp", "Aumid") ? kf.get_string ("WayPlankApp", "Aumid").strip () : "";
				if (raw_aumid.length > 0) {
					d.startup_wm_class_or_aumid = raw_aumid;
					d.wm_classes_or_aumids.add (raw_aumid.down ());
				} else {
					d.startup_wm_class_or_aumid = Win32Backend.is_generic_win32_class (raw_wm) ? "" : raw_wm;
				}
				if (raw_wm.length > 0 && !Win32Backend.is_generic_win32_class (raw_wm) && !d.wm_classes_or_aumids.contains (raw_wm.down ()))
					d.wm_classes_or_aumids.add (raw_wm.down ());

				string stem = file_stem;
				if (d.exec_command.length > 0) {
					var argv = Hal.Runtime.parse_command_argv (d.exec_command);
					if (argv.length > 0) {
						stem = path_stem (argv[0]);
						if (!is_win_icon_spec (d.icon_token) && FileUtils.test (argv[0], FileTest.EXISTS))
							d.icon_token = argv[0];
					}
				}
				/* Pure fallback: only use aumidico: if no valid native icon exists on disk */
				if (raw_aumid.length > 0 && !is_win_icon_spec (d.icon_token))
					d.icon_token = "aumidico:" + raw_aumid;
				d.base_id = normalize_app_id (stem);
				if (d.startup_wm_class_or_aumid.length > 0 && !d.wm_classes_or_aumids.contains (d.startup_wm_class_or_aumid.down ()))
					d.wm_classes_or_aumids.add (d.startup_wm_class_or_aumid.down ());
				d.is_launchable = (d.exec_command.length > 0 || raw_aumid.length > 0);
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

			if (uri_or_path.down ().has_prefix ("aumid://")) {
				string aumid = uri_or_path.substring (8).strip ();
				if (aumid.length == 0)
					return null;
				ensure_uwp_apps_loaded ();
				string akey = aumid.down ();
				if (uwp_apps_by_aumid.has_key (akey))
					return uwp_apps_by_aumid.get (akey);

				var d = new AppDescriptor ();
				d.uri = "aumid://" + aumid;
				int bang = aumid.index_of_char ('!');
				string tail = (bang >= 0 && bang + 1 < aumid.length) ? aumid.substring (bang + 1) : aumid;
				d.display_name = tail;
				d.unlocalized_name = tail;
				d.base_id = normalize_app_id (tail);
				d.startup_wm_class_or_aumid = aumid;
				d.wm_classes_or_aumids.add (akey);
				d.exec_command = aumid;
				d.icon_token = "aumidico:" + aumid;
				d.is_launchable = true;
				d.has_explicit_app_type = true;
				d.try_exec_satisfied = true;
				d.is_shown_in_current_desktop = true;
				return d;
			}

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
			if (raw_id_or_uri.length == 0 || raw_id_or_uri.has_prefix ("aumid://") || raw_id_or_uri.has_prefix ("docklet://"))
				return raw_id_or_uri;

			if (raw_id_or_uri.has_prefix ("file://")) {
				string local = to_local_path (raw_id_or_uri);
				if (local.length > 0 && FileUtils.test (local, FileTest.EXISTS))
					return raw_id_or_uri;
				/* Self-heal deleted Desktop .lnk (e.g. PWA removed from Desktop while Start Menu copy exists) */
				string missing_stem = normalize_app_id (launcher_id_stem (raw_id_or_uri));
				if (missing_stem.length > 0) {
					foreach (var app in discover_installed_apps (true)) {
						if (app.base_id == missing_stem || normalize_app_id (app.display_name) == missing_stem) {
							string cand_path = to_local_path (app.uri);
							if (cand_path.length > 0 && FileUtils.test (cand_path, FileTest.EXISTS))
								return app.uri;
						}
					}
				}
				return raw_id_or_uri;
			}

			if (Path.is_absolute (raw_id_or_uri) && FileUtils.test (raw_id_or_uri, FileTest.EXISTS))
				return to_file_uri (raw_id_or_uri);

			ensure_disk_cache_initialized ();
			string needle = normalize_app_id (strip_launcher_extension (raw_id_or_uri));
			if (needle.length > 0 && apps_by_id.has_key (needle))
				return apps_by_id.get (needle);
			string raw_low = strip_launcher_extension (raw_id_or_uri).down ();
			if (raw_low.length > 0 && apps_by_id.has_key (raw_low))
				return apps_by_id.get (raw_low);
			return "";
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

		static bool is_windows_apps_path (string path)
		{
			string low = path.down ().replace ("/", "\\");
			return low.contains ("\\windowsapps\\");
		}

		static string read_synthetic_aumid (string path)
		{
			var kf = new KeyFile ();
			try {
				kf.load_from_file (path, KeyFileFlags.NONE);
				if (kf.has_group ("WayPlankApp") && kf.has_key ("WayPlankApp", "Aumid"))
					return kf.get_string ("WayPlankApp", "Aumid").strip ();
			} catch (Error e) {}
			return "";
		}

		static void persist_synthetic_aumid (string path, string aumid)
		{
			if (path.length == 0 || aumid.length == 0)
				return;
			var kf = new KeyFile ();
			try {
				kf.load_from_file (path, KeyFileFlags.NONE);
				if (!kf.has_group ("WayPlankApp"))
					return;
				kf.set_string ("WayPlankApp", "Aumid", aumid);
				FileUtils.set_contents (path, kf.to_data ());
			} catch (Error e) {}
		}

		static string build_uri_args (string[] uris)
		{
			var sb = new StringBuilder ();
			foreach (var u in uris) {
				if (sb.len > 0) sb.append_c (' ');
				sb.append (quote_win_arg (to_local_path (u)));
			}
			return sb.str;
		}

		public bool launch_app (string launcher_uri, string[] uris)
		{
			if (launcher_uri.length == 0)
				return false;

			if (launcher_uri.down ().has_prefix ("aumid://")) {
				string aumid = launcher_uri.substring (8).strip ();
				if (aumid.length == 0)
					return false;
				string uargs = build_uri_args (uris);
				return Win32AppBridge.activate_aumid (aumid, uargs.length > 0 ? uargs : null) != 0;
			}

			string path = to_local_path (launcher_uri);
			string lower = path.down ();

			if (lower.has_suffix (".lnk")) {
				string? target = null;
				string? args = null;
				string? workdir = null;
				string? desc_str = null;
				string? icon_path = null;
				int icon_idx = 0;
				string? aumid = null;
				if (Win32AppBridge.resolve_lnk (path, out target, out args, out workdir, out desc_str, out icon_path, out icon_idx, out aumid) != 0) {
					bool target_is_uwp = (target != null && target.length > 0 && is_windows_apps_path (target));
					if (aumid != null && aumid.strip ().length > 0 && (target == null || target.length == 0 || target_is_uwp)) {
						string uargs = build_uri_args (uris);
						if (Win32AppBridge.activate_aumid (aumid.strip (), uargs.length > 0 ? uargs : null) != 0)
							return true;
					}
					if (uris.length == 0)
						return Win32AppBridge.shell_execute (path, null, null) != 0;
					if (target != null && target.length > 0) {
						var sb = new StringBuilder ();
						if (args != null && args.strip ().length > 0)
							sb.append (args.strip ());
						foreach (var u in uris) {
							if (sb.len > 0) sb.append_c (' ');
							sb.append (quote_win_arg (to_local_path (u)));
						}
						return Win32AppBridge.shell_execute (target, sb.str, workdir) != 0;
					}
				}
				return Win32AppBridge.shell_execute (path, null, null) != 0;
			}

			if (lower.has_suffix (".wayplank-app")) {
				var d = load_synthetic_descriptor (path);
				if (d == null)
					return false;
				string aumid = read_synthetic_aumid (path);
				if (aumid.length == 0 && d.exec_command.length > 0) {
					var argv = Hal.Runtime.parse_command_argv (d.exec_command);
					if (argv.length > 0 && is_windows_apps_path (argv[0])) {
						string? found = Win32AppBridge.find_aumid_for_package_path (argv[0]);
						if (found != null && found.strip ().length > 0) {
							aumid = found.strip ();
							persist_synthetic_aumid (path, aumid);
						}
					}
				}
				if (aumid.length > 0) {
					string uargs = build_uri_args (uris);
					if (Win32AppBridge.activate_aumid (aumid, uargs.length > 0 ? uargs : null) != 0)
						return true;
				}
				if (d.exec_command.length == 0)
					return false;
				var sb = new StringBuilder (d.exec_command);
				foreach (var u in uris) {
					sb.append_c (' ');
					sb.append (quote_win_arg (to_local_path (u)));
				}
				return launch_command (sb.str, d.working_dir);
			}

			if (lower.has_suffix (".exe")) {
				if (is_windows_apps_path (path)) {
					string? found = Win32AppBridge.find_aumid_for_package_path (path);
					if (found != null && found.strip ().length > 0) {
						string uargs = build_uri_args (uris);
						if (Win32AppBridge.activate_aumid (found.strip (), uargs.length > 0 ? uargs : null) != 0)
							return true;
					}
				}
				string uargs = build_uri_args (uris);
				return Win32AppBridge.shell_execute (path, uargs.length > 0 ? uargs : null, null) != 0;
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
			string windir = Environment.get_variable ("WINDIR") ?? "C:\\Windows";
			switch (role) {
			case DefaultAppRole.FILE_MANAGER:
				return to_file_uri (Path.build_filename (windir, "explorer.exe"));
			case DefaultAppRole.TERMINAL:
				ensure_uwp_apps_loaded ();
				foreach (var entry in uwp_apps_by_aumid.entries) {
					if (entry.key.contains ("windowsterminal"))
						return entry.value.uri;
				}
				string ps = Path.build_filename (windir, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
				if (FileUtils.test (ps, FileTest.EXISTS))
					return to_file_uri (ps);
				return to_file_uri (Path.build_filename (windir, "System32", "cmd.exe"));
			case DefaultAppRole.TEXT_EDITOR:
				return to_file_uri (Path.build_filename (windir, "System32", "notepad.exe"));
			case DefaultAppRole.WEB_BROWSER:
				BrowserFamily[] fams = {
					BrowserFamily.CHROME, BrowserFamily.EDGE, BrowserFamily.BRAVE,
					BrowserFamily.FIREFOX, BrowserFamily.VIVALDI, BrowserFamily.OPERA
				};
				foreach (var fam in fams) {
					string bin = find_installed_browser_binary (fam);
					if (bin.length > 0)
						return to_file_uri (bin);
				}
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

		static bool matches_windows_category_keywords (AppDescriptor desc, string[] category_tags)
		{
			string hay = "%s %s %s".printf (desc.display_name, desc.base_id, desc.exec_command).down ();
			bool want_internet = false, want_office = false, want_media = false, want_games = false, want_utils = false;
			foreach (unowned string tag in category_tags) {
				string t = tag.down ();
				if (t == "webbrowser" || t == "network" || t == "email" || t == "chat") want_internet = true;
				else if (t == "office" || t == "development" || t == "ide" || t == "texteditor" || t == "calculator") want_office = true;
				else if (t == "audiovideo" || t == "audio" || t == "video" || t == "graphics" || t == "music") want_media = true;
				else if (t == "game" || t == "emulator") want_games = true;
				else if (t == "system" || t == "utility" || t == "settings" || t == "filemanager") want_utils = true;
			}

			if (want_internet) {
				string[] kws = { "chrome", "msedge", "edge", "firefox", "brave", "vivaldi", "opera", "thunderbird", "outlook", "teams", "whatsapp", "telegram", "discord", "slack", "zoom" };
				foreach (unowned string kw in kws) { if (hay.contains (kw)) return true; }
			}
			if (want_office) {
				string[] kws = { "winword", "excel", "powerpnt", "onenote", "libreoffice", "soffice", "code.exe", "visual studio", "notepad", "calc", "calculator", "acrobat", "foxit", "obsidian", "notion" };
				foreach (unowned string kw in kws) { if (hay.contains (kw)) return true; }
			}
			if (want_media) {
				string[] kws = { "vlc", "spotify", "gimp", "inkscape", "blender", "obs64", "audacity", "photos", "mediaplayer", "paint", "snipping", "photoshop", "itunes", "mpv" };
				foreach (unowned string kw in kws) { if (hay.contains (kw)) return true; }
			}
			if (want_games) {
				string[] kws = { "steam", "epicgames", "xbox", "gog galaxy", "retroarch", "minecraft", "battle.net", "ea desktop", "ubisoft", "solitaire" };
				foreach (unowned string kw in kws) { if (hay.contains (kw)) return true; }
			}
			if (want_utils) {
				string[] kws = { "windowsterminal", "powershell", "cmd.exe", "taskmgr", "explorer", "7-zip", "7zfm", "winrar", "settings", "control.exe", "regedit", "putty" };
				foreach (unowned string kw in kws) { if (hay.contains (kw)) return true; }
			}
			return false;
		}

		bool write_uwp_app_into_dir (AppDescriptor desc, GLib.File dest_dir)
		{
			string aumid = desc.startup_wm_class_or_aumid;
			if (aumid.length == 0 && desc.uri.has_prefix ("aumid://"))
				aumid = desc.uri.substring (8);
			if (aumid.length == 0)
				return false;
			string safe = (desc.base_id.length > 0 ? desc.base_id : desc.display_name)
				.replace ("/", "_").replace ("\\", "_").replace (":", "_").replace ("!", "_").replace (" ", "_");
			if (safe.length == 0)
				return false;
			var dest = dest_dir.get_child (safe + ".wayplank-app");
			string? dp = dest.get_path ();
			if (dp == null || dp.length == 0)
				return false;
			var kf = new KeyFile ();
			kf.set_string ("WayPlankApp", "Name", desc.display_name);
			kf.set_string ("WayPlankApp", "Exec", desc.exec_command.length > 0 ? desc.exec_command : aumid);
			kf.set_string ("WayPlankApp", "Aumid", aumid);
			kf.set_string ("WayPlankApp", "Icon", "aumidico:" + aumid);
			try {
				FileUtils.set_contents (dp, kf.to_data ());
				return true;
			} catch (Error e) {
				return false;
			}
		}

		public int populate_category_folder (GLib.File folder, string icon_name, string[] priority_ids, string[] category_tags, int max_items = 6)
		{
			var apps = discover_installed_apps (false);
			var matched = new Gee.ArrayList<AppDescriptor> ();
			var seen_names = new Gee.HashSet<string> ();

			foreach (var app in apps) {
				if (matched.size >= max_items)
					break;
				if (!app.is_launchable || app.is_non_app_launcher || app.is_synthetic)
					continue;
				if (!matches_windows_category_keywords (app, category_tags))
					continue;
				string nkey = app.display_name.down ();
				if (nkey.length == 0 || !seen_names.add (nkey))
					continue;
				matched.add (app);
			}

			if (matched.size == 0)
				return 0;

			if (!ensure_launcher_folder (folder, "", icon_name))
				return 0;

			int written = 0;
			foreach (var app in matched) {
				if (app.uri.has_prefix ("aumid://")) {
					if (write_uwp_app_into_dir (app, folder))
						written++;
				} else {
					var src = File.new_for_uri (app.uri);
					if (copy_launcher_to_directory (src, folder) != null)
						written++;
				}
			}
			return written;
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
			string lower = filename.ascii_down ();
			return (lower == "desktop.ini" || lower.has_prefix ("desktop.ini.")
				|| lower == "thumbs.db"
				|| filename == ".directory" || filename.has_prefix (".directory."));
		}

		public GLib.File? copy_launcher_to_directory (GLib.File src_launcher, GLib.File dest_dir)
		{
			if (!src_launcher.query_exists ())
				return null;
			string? base_name = src_launcher.get_basename ();
			if (base_name == null || base_name.length == 0)
				return null;

			try {
				if (!dest_dir.query_exists ())
					dest_dir.make_directory_with_parents ();
			} catch (Error e) {
				return null;
			}

			string? src_path = src_launcher.get_path ();
			if (src_path != null && src_path.down ().has_suffix (".exe")) {
				var desc = load_exe_descriptor (src_path);
				if (desc == null || desc.exec_command.length == 0)
					return null;
				string stem = path_stem (src_path).replace ("/", "_").replace ("\\", "_").replace (":", "_");
				if (stem.length == 0)
					return null;
				var dest = dest_dir.get_child (stem + ".wayplank-app");
				var kf = new KeyFile ();
				kf.set_string ("WayPlankApp", "Name", desc.display_name.length > 0 ? desc.display_name : stem);
				kf.set_string ("WayPlankApp", "Exec", desc.exec_command);
				kf.set_string ("WayPlankApp", "Icon", desc.icon_token.length > 0 ? desc.icon_token : src_path);
				if (is_windows_apps_path (src_path)) {
					string? found_aumid = Win32AppBridge.find_aumid_for_package_path (src_path);
					if (found_aumid != null && found_aumid.strip ().length > 0)
						kf.set_string ("WayPlankApp", "Aumid", found_aumid.strip ());
				}
				try {
					string? dp = dest.get_path ();
					if (dp == null || dp.length == 0)
						return null;
					FileUtils.set_contents (dp, kf.to_data ());
					return dest;
				} catch (Error e) {
					return null;
				}
			}

			var dest = dest_dir.get_child (base_name);
			if (src_launcher.equal (dest))
				return dest;
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

			/* Persist official UWP/MSIX AUMID so packaged WindowsApps (Teams, Calculator,
			 * Terminal, Settings, WhatsApp, etc.) launch via IApplicationActivationManager. */
			string detected_aumid = "";
			try {
				if (kf.has_key ("WayPlankApp", "Aumid"))
					detected_aumid = kf.get_string ("WayPlankApp", "Aumid").strip ();
			} catch (Error e) {}
			if (detected_aumid.length == 0) {
				var exec_argv = Hal.Runtime.parse_command_argv (exec_cmd);
				string exec_exe = (exec_argv.length > 0) ? exec_argv[0] : "";
				string exec_exe_low = exec_exe.down ();
				string needle = safe_stem.down ();
				string wm_needle = wm_class_or_aumid.down ();
				foreach (var w in Hal.Windows.get_windows ()) {
					if (w.Pid <= 0)
						continue;
					bool matches_win = (exec_exe_low.length > 0 && w.Executable.down () == exec_exe_low)
						|| w.ApplicationId.down () == needle
						|| w.ResourceName.down () == needle
						|| (wm_needle.length > 0 && w.ResourceClass.down () == wm_needle);
					if (matches_win) {
						string? proc_aumid = Win32AppBridge.get_process_aumid (w.Pid);
						if (proc_aumid != null && proc_aumid.strip ().length > 0) {
							detected_aumid = proc_aumid.strip ();
							break;
						}
					}
				}
				if (detected_aumid.length == 0 && exec_exe.length > 0 && is_windows_apps_path (exec_exe)) {
					string? found_aumid = Win32AppBridge.find_aumid_for_package_path (exec_exe);
					if (found_aumid != null && found_aumid.strip ().length > 0)
						detected_aumid = found_aumid.strip ();
				}
			}
			if (detected_aumid.length > 0) {
				kf.set_string ("WayPlankApp", "Aumid", detected_aumid);
				/* Pure fallback: only assign aumidico: if no extractable Win32 icon was resolved */
				if (!is_win_icon_spec (resolved_icon)) {
					resolved_icon = "aumidico:" + detected_aumid;
					kf.set_string ("WayPlankApp", "Icon", resolved_icon);
				}
			}

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
			lnk_cache.unset (to_local_path (launcher_uri).down ());
			return launcher_uri;
		}

		public string reset_custom_launcher_icon (string launcher_uri, out string restored_icon_token)
		{
			restored_icon_token = "";
			custom_icon_overrides.unset (launcher_uri.down ());
			lnk_cache.unset (to_local_path (launcher_uri).down ());
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

		static bool is_non_document_ext (string dot_ext_low)
		{
			return dot_ext_low == ".exe" || dot_ext_low == ".lnk" || dot_ext_low == ".bat"
				|| dot_ext_low == ".cmd" || dot_ext_low == ".msi" || dot_ext_low == ".dll"
				|| dot_ext_low == ".url" || dot_ext_low == ".com" || dot_ext_low == ".scr"
				|| dot_ext_low == ".sys" || dot_ext_low == ".cpl";
		}

		public Gee.ArrayList<RecentDocInfo> get_recent_documents (string launcher_uri, int max_items = 10)
		{
			var results = new Gee.ArrayList<RecentDocInfo> ();
			if (launcher_uri.length == 0 || launcher_uri.has_prefix ("docklet://") || max_items <= 0)
				return results;

			var desc = load_launcher (launcher_uri);
			if (desc == null || !desc.is_launchable)
				return results;

			string exec_low = desc.exec_command.down ();
			if (exec_low.contains ("--app-id=") || exec_low.contains ("--app="))
				return results;

			var seen_targets = new Gee.HashSet<string> ();
			var app_ids = new Gee.ArrayList<string> ();

			if (launcher_uri.down ().has_prefix ("aumid://")) {
				string uwp_id = launcher_uri.substring (8).strip ();
				if (uwp_id.length > 0)
					app_ids.add (uwp_id);
			}
			if (desc.startup_wm_class_or_aumid.length > 0 && !app_ids.contains (desc.startup_wm_class_or_aumid))
				app_ids.add (desc.startup_wm_class_or_aumid);

			string exe_base = "";
			string exe_full = "";
			if (desc.exec_command.length > 0) {
				var argv = Hal.Runtime.parse_command_argv (desc.exec_command);
				if (argv.length > 0) {
					exe_full = argv[0].strip ();
					exe_base = Path.get_basename (exe_full).down ();
				}
			}

			bool is_blocked_proxy = (exe_base == "chrome_proxy.exe" || exe_base == "msedge_proxy.exe"
				|| exe_base == "brave_proxy.exe" || is_os_wrapper_binary (exe_base));
			if (is_blocked_proxy && app_ids.size == 0)
				return results;

			if (!is_blocked_proxy && exe_full.length > 0 && exe_base.has_suffix (".exe")
				&& GLib.Path.is_absolute (exe_full) && !app_ids.contains (exe_full)) {
				app_ids.add (exe_full);
			}

			/* 1. Primary: Official Windows Shell per-app Jump List (IApplicationDocumentLists).
			 * Returns the exact documents opened in this specific Win32 or UWP app. */
			foreach (var app_id in app_ids) {
				if (results.size >= max_items)
					break;
				Win32AppBridge.enum_jump_list_recent (app_id, max_items * 2, (doc_path) => {
					if (results.size >= max_items || doc_path.length == 0)
						return;
					if (!FileUtils.test (doc_path, FileTest.IS_REGULAR))
						return;
					string tgt_key = doc_path.down ();
					if (seen_targets.contains (tgt_key))
						return;
					string bname = Path.get_basename (doc_path);
					int dot = bname.last_index_of_char ('.');
					if (dot > 0 && dot + 1 < bname.length) {
						if (is_non_document_ext (bname.substring (dot).down ()))
							return;
					}
					seen_targets.add (tgt_key);
					var info = new RecentDocInfo ();
					info.uri = to_file_uri (doc_path);
					info.display_name = bname;
					info.tooltip_path = doc_path;
					info.icon_token = doc_path;
					info.direct_app_match = true;
					try {
						var fi = File.new_for_path (doc_path).query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
						info.modified_unix = (int64) fi.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
					} catch (Error e) {}
					results.add (info);
				});
			}

			if (results.size > 0)
				return results;

			/* 2. Fallback for classic Win32 apps without Jump List entries:
			 * Strictly match ONLY extensions where this executable is the actual
			 * system default handler (match_level >= 2: AssocQueryStringW / UserChoice),
			 * never loose OpenWithProgids entries (which would pollute Chrome/editors
			 * with unrelated global .pdf files). */
			if (exe_base.length == 0 || !exe_base.has_suffix (".exe") || is_blocked_proxy)
				return results;

			string? recent_dir = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_RECENT);
			if (recent_dir == null || !FileUtils.test (recent_dir, FileTest.IS_DIR))
				return results;

			var ext_cache = new Gee.HashMap<string, int> ();

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
					if (target == null || target.length == 0 || Win32AppBridge.is_fixed_local_drive (target) == 0)
						continue;
					if (!FileUtils.test (target, FileTest.IS_REGULAR))
						continue;

					string tgt_key = target.down ();
					if (seen_targets.contains (tgt_key))
						continue;

					string bname = Path.get_basename (target);
					int dot = bname.last_index_of_char ('.');
					if (dot <= 0 || dot + 1 >= bname.length)
						continue;
					string dot_ext = bname.substring (dot).down ();
					if (is_non_document_ext (dot_ext))
						continue;

					int match_level = 0;
					if (ext_cache.has_key (dot_ext)) {
						match_level = ext_cache.get (dot_ext);
					} else {
						match_level = Win32AppBridge.exe_handles_ext (exe_base, dot_ext);
						ext_cache.set (dot_ext, match_level);
					}
					if (match_level < 2)
						continue;

					seen_targets.add (tgt_key);
					var info = new RecentDocInfo ();
					info.uri = to_file_uri (target);
					info.display_name = bname;
					info.tooltip_path = target;
					info.icon_token = target;
					info.direct_app_match = true;
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
			if (token.has_prefix ("aumidico:"))
				return token.length > 9;
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

		/* Documented Binary Container Exception (Architecture/README.md §1.1 Rule 5):
		 * Microsoft's Vista+ ICO container specification (ICONDIR / ICONDIRENTRY) carries
		 * either a 32-bit DIB or an embedded 256x256 PNG payload with no format enum field
		 * in ICONDIRENTRY (PNG vs DIB is defined by the leading 4-byte PNG signature vs
		 * BITMAPINFOHEADER.biSize == 40). Static gdk-pixbuf ICO / legacy Win32 GDI loaders
		 * fail or degrade alpha on PNG-in-ICO files (e.g. browser profile/PWA .ico files),
		 * so Zone 3 parses the published ICONDIR table with full bounds checks and hands
		 * the PNG payload directly to the official Gdk.PixbufLoader.with_type("png") API. */
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

		/* Native Windows 7 <-> 11+ Stock Icon mapping (SHSTOCKICONID from shellapi.h).
		 * Fishes version-consistent OS icons (Aero on Win 7, Flat on Win 10, Fluent on
		 * Win 11+) live from imageres.dll / shell32.dll at 256x256 SHIL_JUMBO for dock,
		 * menus, and Change Icon dialog, falling back cleanly to embedded SVGs. */
		static int map_stock_icon_id (string token)
		{
			switch (token.down ()) {
			case "text-x-generic":
			case "image-missing":
				return 0;   /* SIID_DOCNOASSOC */
			case "x-office-document":
			case "document-properties":
				return 1;   /* SIID_DOCASSOC */
			case "application-x-executable":
				return 2;   /* SIID_APPLICATION */
			case "folder":
			case "inode-directory":
				return 3;   /* SIID_FOLDER */
			case "folder-open":
			case "document-open":
			case "document-open-symbolic":
			case "gtk-open":
				return 4;   /* SIID_FOLDEROPEN */
			case "media-floppy":
				return 6;   /* SIID_DRIVE35 */
			case "drive-removable-media":
				return 7;   /* SIID_DRIVEREMOVE */
			case "drive-harddisk":
				return 8;   /* SIID_DRIVEFIXED */
			case "folder-remote":
			case "network-server":
				return 9;   /* SIID_DRIVENET */
			case "drive-optical":
			case "media-optical":
				return 11;  /* SIID_DRIVECD */
			case "preferences-system-network":
			case "applications-internet":
				return 13;  /* SIID_WORLD */
			case "network-workgroup":
				return 15;  /* SIID_SERVER */
			case "printer":
			case "document-print":
				return 16;  /* SIID_PRINTER */
			case "network-wired":
			case "network-idle":
				return 17;  /* SIID_MYNETWORK */
			case "edit-find":
			case "system-search":
				return 22;  /* SIID_FIND */
			case "help-contents":
			case "help-browser":
				return 23;  /* SIID_HELP */
			case "media-optical-audio":
				return 40;  /* SIID_MEDIACDAUDIO */
			case "system-lock-screen":
			case "system-lock-screen-symbolic":
				return 47;  /* SIID_LOCK */
			case "printer-network":
				return 50;  /* SIID_PRINTERNET */
			case "folder-documents":
			case "folder-templates":
				return 57;  /* SIID_STUFFEDFOLDER */
			case "media-optical-dvd":
				return 59;  /* SIID_DRIVEDVD */
			case "folder-music":
			case "audio-x-generic":
				return 71;  /* SIID_AUDIOFILES */
			case "folder-pictures":
			case "image-x-generic":
				return 72;  /* SIID_IMAGEFILES */
			case "folder-videos":
			case "video-x-generic":
				return 73;  /* SIID_VIDEOFILES */
			case "folder-download":
				return 74;  /* SIID_MIXEDFILES */
			case "security-high":
			case "dialog-password":
				return 77;  /* SIID_SHIELD */
			case "dialog-warning":
				return 78;  /* SIID_WARNING */
			case "help-about":
			case "dialog-information":
				return 79;  /* SIID_INFO */
			case "dialog-error":
				return 80;  /* SIID_ERROR */
			case "dialog-key":
			case "changes-prevent":
				return 81;  /* SIID_KEY */
			case "system-software-install":
				return 82;  /* SIID_SOFTWARE */
			case "edit-rename":
				return 83;  /* SIID_RENAME */
			case "edit-delete":
				return 84;  /* SIID_DELETE */
			case "computer":
			case "video-display":
			case "preferences-desktop-display":
				return 94;  /* SIID_DESKTOPPC */
			case "computer-laptop":
				return 95;  /* SIID_MOBILEPC */
			case "system-users":
			case "system-switch-user":
			case "system-users-symbolic":
				return 96;  /* SIID_USERS */
			case "media-flash":
				return 97;  /* SIID_MEDIASMARTMEDIA */
			case "phone":
				return 99;  /* SIID_DEVICECELLPHONE */
			case "camera-photo":
				return 100; /* SIID_DEVICECAMERA */
			case "camera-video":
				return 101; /* SIID_DEVICEVIDEOCAMERA */
			case "multimedia-player":
				return 102; /* SIID_DEVICEAUDIOPLAYER */
			case "network-transmit-receive":
				return 103; /* SIID_NETWORKCONNECT */
			case "web-browser":
				return 104; /* SIID_INTERNET */
			case "application-x-archive":
			case "package-x-generic":
				return 105; /* SIID_ZIPFILE */
			default:
				return -1;
			}
		}

		public Gdk.Pixbuf? load_native_icon (string token, int size)
		{
			int req = (size > 0) ? size : 64;

			int stock_id = map_stock_icon_id (token);
			if (stock_id >= 0) {
				string skey = "stock:%d@%d".printf (stock_id, req);
				if (icon_cache.has_key (skey))
					return icon_cache.get (skey);

				uint8* s_rgba = null;
				int sw = 0, sh = 0;
				if (Win32AppBridge.extract_stock_icon_rgba (stock_id, req, out s_rgba, out sw, out sh) != 0
					&& s_rgba != null && sw > 0 && sh > 0) {
					int s_row = sw * 4;
					int s_bytes = s_row * sh;
					uint8[] s_px = new uint8[s_bytes];
					Memory.copy (s_px, s_rgba, s_bytes);
					Win32AppBridge.free_buffer (s_rgba);

					var spb = new Gdk.Pixbuf.from_data ((owned) s_px, Gdk.Colorspace.RGB, true, 8, sw, sh, s_row);
					if (sw != req || sh != req)
						spb = spb.scale_simple (req, req, Gdk.InterpType.BILINEAR);
					if (icon_cache.size > 1024)
						icon_cache.clear ();
					icon_cache.set (skey, spb);
					return spb;
				}
				if (s_rgba != null)
					Win32AppBridge.free_buffer (s_rgba);
				return null;
			}

			if (!is_win_icon_spec (token))
				return null;

			string key = "%s@%d".printf (token.down (), req);
			if (icon_cache.has_key (key))
				return icon_cache.get (key);
			if (failed_icon_keys.contains (key))
				return null;

			if (token.has_prefix ("aumidico:")) {
				string aumid = token.substring (9).strip ();
				uint8* a_rgba = null;
				int aw = 0, ah = 0;
				if (aumid.length > 0
					&& Win32AppBridge.extract_aumid_icon_rgba (aumid, req, out a_rgba, out aw, out ah) != 0
					&& a_rgba != null && aw > 0 && ah > 0) {
					int a_row = aw * 4;
					int a_bytes = a_row * ah;
					uint8[] a_px = new uint8[a_bytes];
					Memory.copy (a_px, a_rgba, a_bytes);
					Win32AppBridge.free_buffer (a_rgba);
					var apb = new Gdk.Pixbuf.from_data ((owned) a_px, Gdk.Colorspace.RGB, true, 8, aw, ah, a_row);
					if (aw != req || ah != req)
						apb = apb.scale_simple (req, req, Gdk.InterpType.BILINEAR);
					if (icon_cache.size > 1024)
						icon_cache.clear ();
					icon_cache.set (key, apb);
					return apb;
				}
				if (a_rgba != null)
					Win32AppBridge.free_buffer (a_rgba);
				if (failed_icon_keys.size > 1024)
					failed_icon_keys.clear ();
				failed_icon_keys.add (key);
				return null;
			}

			/* Direct raster/vector/ico image files */
			string base_path = token.has_prefix ("winico:") ? token.substring (7) : token;
			int comma = base_path.last_index_of_char (',');
			if (comma > 0)
				base_path = base_path.substring (0, comma);
			if (is_network_path (base_path)) {
				failed_icon_keys.add (key);
				return null;
			}
			string lower = base_path.down ();
			if (lower.has_suffix (".ico")) {
				var ico_pb = decode_ico_file (base_path, req);
				if (ico_pb != null) {
					icon_cache.set (key, ico_pb);
					return ico_pb;
				}
				/* Fall through to Win32 SHIL_JUMBO / PrivateExtractIconsW for non-standard .ico */
			}
			if (lower.has_suffix (".png") || lower.has_suffix (".svg") || lower.has_suffix (".bmp") || lower.has_suffix (".gif")) {
				try {
					var pb = new Gdk.Pixbuf.from_file_at_scale (base_path, req, req, true);
					icon_cache.set (key, pb);
					return pb;
				} catch (Error e) {
					failed_icon_keys.add (key);
					return null;
				}
			}

			uint8* rgba_ptr = null;
			int out_w = 0;
			int out_h = 0;
			string extract_spec = token.has_prefix ("winico:") ? base_path : token;
			if (Win32AppBridge.extract_icon_rgba (extract_spec, req, out rgba_ptr, out out_w, out out_h) == 0
				|| rgba_ptr == null || out_w <= 0 || out_h <= 0) {
				if (rgba_ptr != null)
					Win32AppBridge.free_buffer (rgba_ptr);
				/* Fallback: if .lnk failed, extract from target .exe or UWP AUMID;
				 * if a WindowsApps .exe has no embedded Win32 icon, fall back to shell:AppsFolder\<AUMID>. */
				if (lower.has_suffix (".lnk")) {
					string? target = null, args = null, workdir = null, desc_str = null, icon_p = null, aumid = null;
					int icon_i = 0;
					if (Win32AppBridge.resolve_lnk (base_path, out target, out args, out workdir, out desc_str, out icon_p, out icon_i, out aumid) != 0) {
						if (target != null && target.length > 0 && target.down () != base_path.down ()) {
							var fallback_pb = load_native_icon (target, req);
							if (fallback_pb != null)
								return fallback_pb;
						}
						if (aumid != null && aumid.strip ().length > 0) {
							var uwp_pb = load_native_icon ("aumidico:" + aumid.strip (), req);
							if (uwp_pb != null)
								return uwp_pb;
						}
					}
				} else if (is_windows_apps_path (base_path)) {
					string? found_aumid = Win32AppBridge.find_aumid_for_package_path (base_path);
					if (found_aumid != null && found_aumid.strip ().length > 0) {
						var uwp_pb = load_native_icon ("aumidico:" + found_aumid.strip (), req);
						if (uwp_pb != null) {
							if (icon_cache.size > 1024)
								icon_cache.clear ();
							icon_cache.set (key, uwp_pb);
							return uwp_pb;
						}
					}
				}
				if (failed_icon_keys.size > 1024)
					failed_icon_keys.clear ();
				failed_icon_keys.add (key);
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
			if (out_w != req || out_h != req)
				pixbuf = pixbuf.scale_simple (req, req, Gdk.InterpType.BILINEAR);
			if (icon_cache.size > 1024)
				icon_cache.clear ();
			icon_cache.set (key, pixbuf);
			return pixbuf;
		}

		public bool has_native_icon (string token)
		{
			if (map_stock_icon_id (token) >= 0)
				return load_native_icon (token, 36) != null;
			return is_win_icon_spec (token);
		}

		public Gee.ArrayList<string> list_native_icon_tokens ()
		{
			if (cached_native_icon_tokens == null) {
				var list = new Gee.ArrayList<string> ();
				var seen = new Gee.HashSet<string> ();
				Win32AppBridge.enum_system_icon_stores ((token) => {
					if (token != "" && seen.add (token.down ()))
						list.add (token);
				});
				cached_native_icon_tokens = list;
			}
			var copy = new Gee.ArrayList<string> ();
			copy.add_all (cached_native_icon_tokens);
			return copy;
		}

		public string? get_file_icon_token (GLib.File file)
		{
			string? p = file.get_path ();
			if (p != null && p.length > 0 && !is_network_path (p) && FileUtils.test (p, FileTest.EXISTS)) {
				if (FileUtils.test (p, FileTest.IS_DIR))
					return "inode-directory;;folder";
				return p;
			}
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
			is_cleaned_up = true;
			if (bg_sync_timer_id != 0U) {
				Source.remove (bg_sync_timer_id);
				bg_sync_timer_id = 0U;
			}
			if (save_cache_timer_id != 0U) {
				Source.remove (save_cache_timer_id);
				save_cache_timer_id = 0U;
			}
			foreach (var list in browser_monitors.values) {
				foreach (var mon in list)
					mon.cancel ();
			}
			browser_monitors.clear ();
			icon_cache.clear ();
			failed_icon_keys.clear ();
			lnk_cache.clear ();
			disk_lnk_records.clear ();
			apps_by_id.clear ();
			cached_launcher_dirs = null;
			cached_native_icon_tokens = null;
			cached_apps = null;
		}
	}
}
