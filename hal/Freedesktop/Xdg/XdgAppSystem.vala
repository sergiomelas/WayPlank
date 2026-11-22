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
	 * Freedesktop / XDG implementation of {@link IAppSystem} (`Hal.Apps`).
	 *
	 * Owns all southbound `.desktop` / `KeyFileDesktop` / `DesktopAppInfo` / GIO MIME /
	 * XDG directory / Flatpak & Snap export / `Gtk.RecentManager` / `Gtk.IconTheme` /
	 * kernel process-inspector seam calls so Zone 1 (`src/`, `lib/`) remains 100% OS-blind.
	 */
	public class XdgAppSystem : GLib.Object, IAppSystem
	{
		const string DESKTOP_ACTION_KEY = "Actions";
		const string DESKTOP_ACTION_GROUP_NAME = "Desktop Action %s";
		const string UNITY_QUICKLISTS_KEY = "X-Ayatana-Desktop-Shortcuts";
		const string UNITY_QUICKLISTS_SHORTCUT_GROUP_NAME = "%s Shortcut Group";
		const string UNITY_QUICKLISTS_TARGET_KEY = "TargetEnvironment";
		const string UNITY_QUICKLISTS_TARGET_VALUE = "Unity";
		const string ORIGINAL_ICON_NONE_SENTINEL = "__WAYPLANK_NONE__";
		const string FILE_ATTRIBUTE_CUSTOM_ICON_NAME = "metadata::custom-icon-name";
		const string FILE_ATTRIBUTE_CUSTOM_ICON = "metadata::custom-icon";

		const string[] SUPPORTED_GETTEXT_DOMAINS_KEYS = {
			"X-Ubuntu-Gettext-Domain",
			"X-GNOME-Gettext-Domain"
		};

		const string[] FALLBACK_FILE_MANAGERS = {
			"org.gnome.Nautilus.desktop",
			"org.kde.dolphin.desktop",
			"nemo.desktop",
			"thunar.desktop",
			"pcmanfm.desktop",
			"org.xfce.FileManager.desktop"
		};

		const string[] FALLBACK_BROWSERS = {
			"google-chrome.desktop",
			"firefox.desktop",
			"chromium-browser.desktop",
			"chromium.desktop",
			"brave-browser.desktop",
			"microsoft-edge.desktop",
			"org.gnome.Epiphany.desktop"
		};

		const string[] FALLBACK_TERMINALS = {
			"org.gnome.Terminal.desktop",
			"org.gnome.Ptyxis.desktop",
			"ptyxis.desktop",
			"org.kde.konsole.desktop",
			"alacritty.desktop",
			"kitty.desktop",
			"xfce4-terminal.desktop",
			"foot.desktop",
			"terminator.desktop"
		};

		const string[] FALLBACK_EDITORS = {
			"org.gnome.TextEditor.desktop",
			"gedit.desktop",
			"org.kde.kate.desktop",
			"code.desktop",
			"com.microsoft.VSCode.desktop",
			"mousepad.desktop"
		};

		const string[] EXTRA_DROP_TARGET_ATOMS = {
			"application/x-desktop",
			"application/x-gnome-app-info",
			"application/x-kde-appmenu"
		};

		const string[] DOS_RESERVED_STEMS = {
			"CON", "PRN", "AUX", "NUL",
			"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
			"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
		};

		class CachedLauncher : GLib.Object
		{
			public uint64 mtime_sec;
			public uint32 mtime_usec;
			public AppDescriptor descriptor;

			public CachedLauncher (uint64 sec, uint32 usec, AppDescriptor desc)
			{
				this.mtime_sec = sec;
				this.mtime_usec = usec;
				this.descriptor = desc;
			}
		}

		class RecentCandidate : GLib.Object
		{
			public Gtk.RecentInfo info;
			public string uri;
			public string display_name;
			public Icon? gicon;
			public string mime_type;
			public int64 modified_ts;
			public bool direct_app_match;

			public RecentCandidate (Gtk.RecentInfo info, string uri, string display_name,
				Icon? gicon, string mime_type, int64 modified_ts, bool direct_app_match)
			{
				this.info = info;
				this.uri = uri;
				this.display_name = display_name;
				this.gicon = gicon;
				this.mime_type = mime_type;
				this.modified_ts = modified_ts;
				this.direct_app_match = direct_app_match;
			}
		}

		static XdgAppSystem? default_instance = null;
		static GLib.Mutex icon_mutex;

		public static XdgAppSystem get_default ()
		{
			if (default_instance == null)
				default_instance = new XdgAppSystem ();
			return default_instance;
		}

		Gee.HashMap<string, CachedLauncher> launcher_cache = new Gee.HashMap<string, CachedLauncher> ();
		Gee.ArrayList<FileMonitor> dir_monitors = new Gee.ArrayList<FileMonitor> ();
		Gee.ArrayList<FileMonitor> browser_session_monitors = new Gee.ArrayList<FileMonitor> ();
		Gee.HashSet<string> watched_browser_session_dirs = new Gee.HashSet<string> ();
		bool browser_session_watch_active = false;
		Gee.ArrayList<string> extra_watched_uris = new Gee.ArrayList<string> ();
		uint debounce_timer_id = 0U;

		private XdgAppSystem ()
		{
			refresh_directory_monitors ();
		}

		static void schedule_apps_changed_timer (XdgAppSystem target)
		{
			if (target.debounce_timer_id > 0U) {
				GLib.Source.remove (target.debounce_timer_id);
				target.debounce_timer_id = 0U;
			}
			GLib.WeakRef weak_self = GLib.WeakRef (target);
			target.debounce_timer_id = GLib.Timeout.add (250, () => {
				var self = (XdgAppSystem?) weak_self.get ();
				if (self == null)
					return GLib.Source.REMOVE;
				self.debounce_timer_id = 0U;
				self.launcher_cache.clear ();
				self.apps_changed ();
				return GLib.Source.REMOVE;
			});
		}

		void cancel_directory_monitors ()
		{
			foreach (var mon in dir_monitors)
				mon.cancel ();
			dir_monitors.clear ();
		}

		void refresh_directory_monitors ()
		{
			cancel_directory_monitors ();

			var watch_dirs = new Gee.ArrayList<File> ();
			var seen_uris = new Gee.HashSet<string> ();

			foreach (var d in discover_launcher_dirs ()) {
				string u = d.get_uri ();
				if (!seen_uris.contains (u)) {
					seen_uris.add (u);
					watch_dirs.add (d);
				}
			}

			string? desktop_dir = Environment.get_user_special_dir (UserDirectory.DESKTOP);
			if (desktop_dir != null && desktop_dir != "") {
				var df = File.new_for_path (desktop_dir);
				string du = df.get_uri ();
				if (!seen_uris.contains (du)) {
					seen_uris.add (du);
					watch_dirs.add (df);
				}
			}

			foreach (var extra_uri in extra_watched_uris) {
				if (extra_uri == "" || seen_uris.contains (extra_uri))
					continue;
				seen_uris.add (extra_uri);
				watch_dirs.add (extra_uri.has_prefix ("/") ? File.new_for_path (extra_uri) : File.new_for_uri (extra_uri));
			}

			GLib.WeakRef weak_self = GLib.WeakRef (this);
			foreach (var dir in watch_dirs) {
				try {
					var mon = dir.monitor_directory (FileMonitorFlags.NONE, null);
					mon.changed.connect ((f, other, ev) => {
						var self = (XdgAppSystem?) weak_self.get ();
						if (self != null)
							schedule_apps_changed_timer (self);
					});
					dir_monitors.add (mon);
				} catch { }
			}
		}

		public static bool load_keyfile_safe (KeyFile kf, string file_path, KeyFileFlags flags = KeyFileFlags.NONE)
		{
			try {
				if (kf.load_from_file (file_path, flags))
					return true;
			} catch (Error e) {
				try {
					var gfile = File.new_for_path (file_path);
					uint8[] raw_bytes;
					if (gfile.load_contents (null, out raw_bytes, null)) {
						string content = (string) raw_bytes;
						content = content.replace ("[$e]=", "=");
						content = content.replace ("[$i]=", "=");
						content = content.replace ("[$d]=", "=");
						return kf.load_from_data (content, content.length, flags);
					}
				} catch { }
			}
			return false;
		}

		static string? uri_or_path_to_local_path (string uri_or_path)
		{
			string s = uri_or_path.strip ();
			if (s == "")
				return null;
			if (s.has_prefix ("file://")) {
				try {
					return Filename.from_uri (s);
				} catch {
					return File.new_for_uri (s).get_path ();
				}
			}
			if (s.has_prefix ("/"))
				return s;
			return null;
		}

		static bool is_known_terminal_stem (string stem)
		{
			string s = stem.down ();
			return (s == "konsole" || s == "org.kde.konsole"
				|| s == "gnome-terminal" || s == "org.gnome.terminal"
				|| s == "ptyxis" || s == "org.gnome.ptyxis"
				|| s == "kgx" || s == "org.gnome.console"
				|| s == "alacritty" || s == "org.alacritty.alacritty"
				|| s == "kitty" || s == "foot" || s == "wezterm" || s == "org.wezfurlong.wezterm"
				|| s == "xfce4-terminal" || s == "tilix" || s == "terminator"
				|| s == "mate-terminal" || s == "lxterminal" || s == "qterminal"
				|| s == "yakuake" || s == "guake" || s == "xterm" || s == "urxvt"
				|| s == "ghostty" || s == "com.mitchellh.ghostty" || s == "contour" || s == "tabby");
		}

		public Gee.ArrayList<GLib.File> get_extra_data_dirs ()
		{
			var list = new Gee.ArrayList<GLib.File> ();
			string[] extra_paths = {
				"/var/lib/snapd/desktop",
				"/var/lib/flatpak/exports/share",
				Path.build_filename (Environment.get_user_data_dir (), "flatpak", "exports", "share")
			};
			foreach (unowned string ep in extra_paths) {
				var f = File.new_for_path (ep);
				if (f.query_exists ())
					list.add (f);
			}
			return list;
		}

		public Gee.ArrayList<GLib.File> discover_launcher_dirs ()
		{
			var dirs = new Gee.ArrayList<GLib.File> ();
			var seen = new Gee.HashSet<string> ();

			var user_apps = File.new_for_path (Path.build_filename (Environment.get_user_data_dir (), "applications"));
			seen.add (user_apps.get_uri ());
			dirs.add (user_apps);

			foreach (unowned string s in Environment.get_system_data_dirs ()) {
				var d = File.new_for_path (Path.build_filename (s, "applications"));
				string u = d.get_uri ();
				if (!seen.contains (u)) {
					seen.add (u);
					dirs.add (d);
				}
			}

			foreach (var extra in get_extra_data_dirs ()) {
				var d = extra.get_child ("applications");
				string u = d.get_uri ();
				if (!seen.contains (u)) {
					seen.add (u);
					dirs.add (d);
				}
			}

			return dirs;
		}

		public Gee.ArrayList<AppDescriptor> discover_installed_apps (bool include_nodisplay = true)
		{
			var result = new Gee.ArrayList<AppDescriptor> ();
			var seen_ids = new Gee.HashSet<string> ();

			foreach (var folder in discover_launcher_dirs ()) {
				if (!folder.query_exists ())
					continue;
				try {
					var enumerator = folder.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
					FileInfo? info = null;
					while ((info = enumerator.next_file ()) != null) {
						string name = info.get_name ();
						if (!name.has_suffix (".desktop") || is_self_launcher (name))
							continue;
						string id_key = strip_launcher_extension (name).down ();
						if (seen_ids.contains (id_key))
							continue;

						var file = folder.get_child (name);
						var desc = load_launcher (file.get_uri ());
						if (desc == null || desc.is_non_app_launcher || desc.is_hidden)
							continue;

						if (!include_nodisplay) {
							if (desc.is_nodisplay || !desc.is_shown_in_current_desktop || !desc.try_exec_satisfied)
								continue;
						}

						seen_ids.add (id_key);
						result.add (desc);
					}
				} catch { }
			}

			return result;
		}

		public void set_extra_watched_directories (string[] folder_uris)
		{
			bool changed = (folder_uris.length != extra_watched_uris.size);
			if (!changed) {
				for (int i = 0; i < folder_uris.length; i++) {
					if (!extra_watched_uris.contains (folder_uris[i])) {
						changed = true;
						break;
					}
				}
			}
			if (!changed)
				return;

			extra_watched_uris.clear ();
			foreach (unowned string u in folder_uris) {
				if (u != null && u != "" && !extra_watched_uris.contains (u))
					extra_watched_uris.add (u);
			}
			refresh_directory_monitors ();
		}

		public void invalidate_cache ()
		{
			// load_launcher() validates (mtime_sec, mtime_usec) per file on every hit
			// and apply/reset_custom_launcher_icon() explicitly evict modified entries.
			// Prune only deleted files here instead of discarding all ~500 valid entries.
			var stale_paths = new Gee.ArrayList<string> ();
			foreach (var p in launcher_cache.keys) {
				if (!FileUtils.test (p, FileTest.EXISTS))
					stale_paths.add (p);
			}
			foreach (var p in stale_paths)
				launcher_cache.unset (p);
			hal_kernel_clear_process_caches ();
		}

		public AppDescriptor? load_launcher (string uri_or_path)
		{
			if (uri_or_path == null || uri_or_path == "" || uri_or_path.has_prefix ("docklet://"))
				return null;

			string? local_path = uri_or_path_to_local_path (uri_or_path);
			if (local_path == null) {
				string resolved = resolve_launcher_uri (uri_or_path);
				local_path = uri_or_path_to_local_path (resolved);
			}
			if (local_path == null || !FileUtils.test (local_path, FileTest.EXISTS))
				return null;

			var gfile = File.new_for_path (local_path);
			uint64 mtime_sec = 0;
			uint32 mtime_usec = 0;
			try {
				var fi = gfile.query_info (FileAttribute.TIME_MODIFIED + "," + FileAttribute.TIME_MODIFIED_USEC, FileQueryInfoFlags.NONE);
				mtime_sec = fi.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
				mtime_usec = fi.get_attribute_uint32 (FileAttribute.TIME_MODIFIED_USEC);
			} catch { }

			if (mtime_sec > 0 && launcher_cache.has_key (local_path)) {
				var cached = launcher_cache.get (local_path);
				if (cached.mtime_sec == mtime_sec && cached.mtime_usec == mtime_usec)
					return cached.descriptor;
			}

			var kf = new KeyFile ();
			if (!load_keyfile_safe (kf, local_path, KeyFileFlags.NONE))
				return null;
			if (!kf.has_group (KeyFileDesktop.GROUP))
				return null;

			var desc = new AppDescriptor ();
			desc.uri = gfile.get_uri ();
			string bname = Path.get_basename (local_path);
			desc.base_id = strip_launcher_extension (bname).down ();
			desc.is_synthetic = bname.has_prefix ("wayplank-app-");

			if (FileUtils.test (local_path, FileTest.IS_SYMLINK)) {
				string? real_target = Posix.realpath (local_path);
				if (real_target != null && real_target != "") {
					string real_base = Path.get_basename (real_target);
					if (real_base.down ().has_suffix (".desktop")) {
						string alias = strip_launcher_extension (real_base).down ();
						if (alias != "" && alias != desc.base_id && !desc.alias_ids.contains (alias))
							desc.alias_ids.add (alias);
					}
				}
			}

			string effective_path = local_path;
			string dtype = "Application";
			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE)) {
					dtype = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE).strip ();
					if (dtype == KeyFileDesktop.TYPE_APPLICATION)
						desc.has_explicit_app_type = true;
				}

				if (dtype == KeyFileDesktop.TYPE_LINK) {
					string link_target = "";
					if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_URL))
						link_target = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_URL).strip ();
					else if (kf.has_key (KeyFileDesktop.GROUP, "URL[$e]"))
						link_target = kf.get_string (KeyFileDesktop.GROUP, "URL[$e]").strip ();

					string? linked_desktop = uri_or_path_to_local_path (link_target);
					if (linked_desktop != null && linked_desktop.down ().has_suffix (".desktop")
						&& FileUtils.test (linked_desktop, FileTest.EXISTS)) {
						string linked_alias = strip_launcher_extension (Path.get_basename (linked_desktop)).down ();
						if (linked_alias != "" && linked_alias != desc.base_id && !desc.alias_ids.contains (linked_alias))
							desc.alias_ids.add (linked_alias);

						var target_kf = new KeyFile ();
						if (load_keyfile_safe (target_kf, linked_desktop, KeyFileFlags.NONE) && target_kf.has_group (KeyFileDesktop.GROUP)) {
							kf = target_kf;
							effective_path = linked_desktop;
							dtype = KeyFileDesktop.TYPE_APPLICATION;
							if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE))
								dtype = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE).strip ();
							if (dtype == KeyFileDesktop.TYPE_APPLICATION)
								desc.has_explicit_app_type = true;
						} else {
							desc.is_non_app_launcher = true;
						}
					} else {
						desc.is_non_app_launcher = true;
					}
				} else if (dtype != "" && dtype != KeyFileDesktop.TYPE_APPLICATION) {
					desc.is_non_app_launcher = true;
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME)) {
					desc.unlocalized_name = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME).strip ();
					desc.display_name = kf.get_locale_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME).strip ();
					if (desc.display_name == "")
						desc.display_name = desc.unlocalized_name;
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_GENERIC_NAME))
					desc.generic_name = kf.get_locale_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_GENERIC_NAME).strip ();
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_COMMENT))
					desc.comment = kf.get_locale_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_COMMENT).strip ();
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON))
					desc.icon_token = kf.get_locale_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON).strip ();
			} catch { }

			if (desc.icon_token == "") {
				if (dtype == KeyFileDesktop.TYPE_DIRECTORY)
					desc.icon_token = "inode-directory";
				else if (dtype == KeyFileDesktop.TYPE_LINK)
					desc.icon_token = "text-html";
			}

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
					desc.exec_command = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
					desc.is_launchable = (desc.exec_command != "");
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_PATH)) {
					string raw_wd = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_PATH).strip ();
					if (raw_wd != "")
						desc.working_dir = Hal.Runtime.expand_path_variables (raw_wd);
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_URL))
					desc.url_target = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_URL).strip ();
				else if (kf.has_key (KeyFileDesktop.GROUP, "URL[$e]"))
					desc.url_target = kf.get_string (KeyFileDesktop.GROUP, "URL[$e]").strip ();
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, "StartupWMClass")) {
					string swmc = kf.get_string (KeyFileDesktop.GROUP, "StartupWMClass").strip ();
					if (swmc != "") {
						desc.startup_wm_class_or_aumid = swmc;
						desc.wm_classes_or_aumids.add (swmc);
					}
				}
				if (kf.has_key (KeyFileDesktop.GROUP, "X-GNOME-WMClass")) {
					string gmc = kf.get_string (KeyFileDesktop.GROUP, "X-GNOME-WMClass").strip ();
					if (gmc != "" && !desc.wm_classes_or_aumids.contains (gmc))
						desc.wm_classes_or_aumids.add (gmc);
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, "X-Flatpak")) {
					string fp = kf.get_string (KeyFileDesktop.GROUP, "X-Flatpak").strip ();
					if (fp != "")
						desc.sandbox_ids.add (fp);
				}
				if (kf.has_key (KeyFileDesktop.GROUP, "X-SnapInstanceName")) {
					string sn = kf.get_string (KeyFileDesktop.GROUP, "X-SnapInstanceName").strip ();
					if (sn != "" && !desc.sandbox_ids.contains (sn))
						desc.sandbox_ids.add (sn);
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_CATEGORIES)) {
					foreach (unowned string cat in kf.get_string_list (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_CATEGORIES)) {
						string c = cat.strip ();
						if (c != "" && !desc.categories.contains (c))
							desc.categories.add (c);
					}
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_MIME_TYPE)) {
					foreach (unowned string mime in kf.get_string_list (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_MIME_TYPE)) {
						string m = mime.strip ();
						if (m != "") {
							string ct = ContentType.from_mime_type (m);
							if (ct != "" && !desc.mime_types.contains (ct))
								desc.mime_types.add (ct);
						}
					}
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, "Keywords")) {
					foreach (unowned string kw in kf.get_locale_string_list (KeyFileDesktop.GROUP, "Keywords", null)) {
						string k = kw.strip ();
						if (k != "" && !desc.keywords.contains (k))
							desc.keywords.add (k);
					}
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-BrowserProfile"))
					desc.browser_profile = kf.get_string (KeyFileDesktop.GROUP, "X-WayPlank-BrowserProfile").strip ();
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NO_DISPLAY))
					desc.is_nodisplay = kf.get_boolean (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NO_DISPLAY);
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_HIDDEN))
					desc.is_hidden = kf.get_boolean (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_HIDDEN);
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TERMINAL))
					desc.is_terminal = kf.get_boolean (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TERMINAL);
			} catch { }

			desc.is_terminal_emulator = desc.categories.contains ("TerminalEmulator") || is_known_terminal_stem (desc.base_id);

			try {
				bool has_orig = kf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon");
				bool created_override = kf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-Created")
					&& kf.get_boolean (KeyFileDesktop.GROUP, "X-WayPlank-Created");
				desc.has_custom_icon_override = (has_orig || created_override);
			} catch { }

			try {
				string desktop_env = (Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "").down ();
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ONLY_SHOW_IN)) {
					bool matched = false;
					foreach (unowned string allowed in kf.get_string_list (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ONLY_SHOW_IN)) {
						string a = allowed.strip ().down ();
						if (a != "" && desktop_env.contains (a)) {
							matched = true;
							break;
						}
					}
					if (!matched)
						desc.is_shown_in_current_desktop = false;
				}
				if (desc.is_shown_in_current_desktop && kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NOT_SHOW_IN)) {
					foreach (unowned string blocked in kf.get_string_list (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NOT_SHOW_IN)) {
						string b = blocked.strip ().down ();
						if (b != "" && desktop_env.contains (b)) {
							desc.is_shown_in_current_desktop = false;
							break;
						}
					}
				}
			} catch { }

			try {
				if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TRY_EXEC)) {
					string try_exec = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TRY_EXEC).strip ();
					if (try_exec != "" && !File.new_for_path (try_exec).query_exists ()
						&& Environment.find_program_in_path (try_exec) == null)
						desc.try_exec_satisfied = false;
				}
			} catch { }

			if (!desc.is_non_app_launcher) {
				DesktopAppInfo? d_info = new DesktopAppInfo.from_filename (effective_path);

				if (d_info != null) {
					desc.supports_files = d_info.supports_files ();
					desc.supports_uris = d_info.supports_uris ();
				}
				if (!desc.supports_files && (desc.exec_command.contains ("%f") || desc.exec_command.contains ("%F")))
					desc.supports_files = true;
				if (!desc.supports_uris && (desc.exec_command.contains ("%u") || desc.exec_command.contains ("%U")))
					desc.supports_uris = true;

				parse_quicklist_actions (kf, effective_path, d_info, desc.quicklist_actions);
			}

			if (mtime_sec > 0) {
				if (launcher_cache.size > 2048)
					launcher_cache.clear ();
				launcher_cache.set (local_path, new CachedLauncher (mtime_sec, mtime_usec, desc));
			}

			return desc;
		}

		static void parse_quicklist_actions (KeyFile file, string file_path, DesktopAppInfo? desktop_info,
			Gee.ArrayList<QuicklistAction> out_actions)
		{
			try {
				string? textdomain = null;
				foreach (unowned string domain_key in SUPPORTED_GETTEXT_DOMAINS_KEYS) {
					if (file.has_key (KeyFileDesktop.GROUP, domain_key)) {
						textdomain = file.get_string (KeyFileDesktop.GROUP, domain_key);
						break;
					}
				}

				string[] keys = { DESKTOP_ACTION_KEY, UNITY_QUICKLISTS_KEY };
				foreach (unowned string key in keys) {
					if (!file.has_key (KeyFileDesktop.GROUP, key))
						continue;

					foreach (unowned string action in file.get_string_list (KeyFileDesktop.GROUP, key)) {
						string group = DESKTOP_ACTION_GROUP_NAME.printf (action);
						bool is_native = true;
						if (!file.has_group (group)) {
							group = UNITY_QUICKLISTS_SHORTCUT_GROUP_NAME.printf (action);
							is_native = false;
							if (!file.has_group (group))
								continue;
						}

						if (file.has_key (group, UNITY_QUICKLISTS_TARGET_KEY)) {
							string target = file.get_string (group, UNITY_QUICKLISTS_TARGET_KEY);
							if (target != UNITY_QUICKLISTS_TARGET_VALUE && target != "Plank")
								continue;
						}

						if (file.has_key (group, KeyFileDesktop.KEY_NOT_SHOW_IN)) {
							bool blocked = false;
							foreach (unowned string s in file.get_string_list (group, KeyFileDesktop.KEY_NOT_SHOW_IN)) {
								if (s == "Plank") {
									blocked = true;
									break;
								}
							}
							if (blocked)
								continue;
						}

						if (file.has_key (group, KeyFileDesktop.KEY_ONLY_SHOW_IN)) {
							bool allowed = false;
							foreach (unowned string s in file.get_string_list (group, KeyFileDesktop.KEY_ONLY_SHOW_IN)) {
								if (s == UNITY_QUICKLISTS_TARGET_VALUE || s == "Plank") {
									allowed = true;
									break;
								}
							}
							if (!allowed)
								continue;
						}

						if (!file.has_key (group, KeyFileDesktop.KEY_NAME))
							continue;

						string action_name = file.get_locale_string (group, KeyFileDesktop.KEY_NAME);
						if (textdomain != null && textdomain != "")
							action_name = GLib.dgettext (textdomain, action_name).dup ();
						if (action_name == "")
							continue;

						string action_icon = "";
						if (file.has_key (group, KeyFileDesktop.KEY_ICON))
							action_icon = file.get_locale_string (group, KeyFileDesktop.KEY_ICON);

						string action_exec = "";
						if (file.has_key (group, KeyFileDesktop.KEY_EXEC))
							action_exec = file.get_string (group, KeyFileDesktop.KEY_EXEC);

						var qa = new QuicklistAction ();
						qa.id = action;
						qa.name = action_name;
						qa.icon_token = action_icon;
						qa.exec = action_exec;
						qa.is_native_action = (key == DESKTOP_ACTION_KEY && is_native);
						out_actions.add (qa);
					}
				}

				if (out_actions.size == 0 && desktop_info != null) {
					foreach (unowned string act in desktop_info.list_actions ()) {
						string? act_name = desktop_info.get_action_name (act);
						if (act_name != null && act_name != "") {
							var qa = new QuicklistAction ();
							qa.id = act;
							qa.name = act_name;
							qa.is_native_action = true;
							out_actions.add (qa);
						}
					}
				}
			} catch { }
		}

		public string resolve_launcher_uri (string raw_id_or_uri)
		{
			string cleaned = raw_id_or_uri.strip ();
			if (cleaned.length == 0 || cleaned.has_prefix ("#"))
				return "";

			if (cleaned.has_prefix ("docklet://"))
				return cleaned;

			if (cleaned.has_prefix ("application://")
				|| cleaned.has_prefix ("applications://")
				|| cleaned.has_prefix ("applications:")
				|| cleaned.has_prefix ("appstream://")) {
				string desktop_id = cleaned;
				if (desktop_id.has_prefix ("applications://"))
					desktop_id = desktop_id.substring ("applications://".length);
				else if (desktop_id.has_prefix ("application://"))
					desktop_id = desktop_id.substring ("application://".length);
				else if (desktop_id.has_prefix ("applications:"))
					desktop_id = desktop_id.substring ("applications:".length);
				else if (desktop_id.has_prefix ("appstream://"))
					desktop_id = desktop_id.substring ("appstream://".length);
				desktop_id = desktop_id.strip ();
				while (desktop_id.has_suffix ("/"))
					desktop_id = desktop_id.substring (0, desktop_id.length - 1);

				var app_info = new DesktopAppInfo (desktop_id);
				if (app_info == null && !desktop_id.has_suffix (".desktop"))
					app_info = new DesktopAppInfo (desktop_id + ".desktop");
				if (app_info != null && app_info.get_filename () != null)
					return File.new_for_path (app_info.get_filename ()).get_uri ();
				return cleaned;
			}

			if (cleaned.has_prefix ("file://") || cleaned.has_prefix ("http://")
				|| cleaned.has_prefix ("https://") || cleaned.has_prefix ("ftp://"))
				return cleaned;

			if (cleaned.has_prefix ("www."))
				return "https://" + cleaned;

			if (cleaned.has_prefix ("/"))
				return File.new_for_path (cleaned).get_uri ();

			var f = File.new_for_commandline_arg (cleaned);
			if (f.query_exists ())
				return f.get_uri ();

			var d_info = new DesktopAppInfo (cleaned);
			if (d_info == null && !cleaned.has_suffix (".desktop"))
				d_info = new DesktopAppInfo (cleaned + ".desktop");
			if (d_info != null && d_info.get_filename () != null)
				return File.new_for_path (d_info.get_filename ()).get_uri ();

			return "";
		}

		public bool is_launcher_uri (string uri_or_path)
		{
			string u = uri_or_path.strip ();
			if (u == "")
				return false;

			string low = u.down ();
			if (low.has_suffix (".url"))
				return false;

			if (u.has_prefix ("application://")
				|| u.has_prefix ("applications://")
				|| u.has_prefix ("applications:")
				|| u.has_prefix ("appstream://")) {
				var desc = load_launcher (u);
				return (desc == null || !desc.is_non_app_launcher);
			}

			if (low.has_suffix (".desktop")) {
				var desc = load_launcher (u);
				if (desc != null && desc.is_non_app_launcher)
					return false;
				return true;
			}

			if (u.has_prefix ("file://") || u.has_prefix ("/")) {
				try {
					var f = u.has_prefix ("/") ? File.new_for_path (u) : File.new_for_uri (u);
					var info = f.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
					unowned string? ct = info.get_content_type ();
					if (ct != null && (ct == "application/x-desktop" || ct.contains ("desktop"))) {
						var desc = load_launcher (u);
						return (desc == null || !desc.is_non_app_launcher);
					}
				} catch { }
			}
			return false;
		}

		public bool is_self_launcher (string id_or_uri)
		{
			string stem = launcher_id_stem (id_or_uri).down ();
			return (stem == "wayplank" || stem == "plank"
				|| stem == "net.launchpad.plank" || stem == "org.wayplank.wayplank");
		}

		public bool launcher_uris_match (string uri_a, string uri_b)
		{
			if (uri_a == uri_b)
				return true;
			if (uri_a == "" || uri_b == "")
				return false;

			string? pa = uri_or_path_to_local_path (uri_a);
			string? pb = uri_or_path_to_local_path (uri_b);
			if (pa != null && pb != null) {
				if (Hal.Runtime.paths_equal (pa, pb))
					return true;
				if (pa.down ().has_suffix (".desktop") && pb.down ().has_suffix (".desktop")
					&& Path.get_basename (pa) == Path.get_basename (pb))
					return true;
			}

			return false;
		}

		public string strip_launcher_extension (string raw_id)
		{
			string s = raw_id.strip ();
			string low = s.down ();
			if (low.has_suffix (".desktop"))
				return s.substring (0, s.length - ".desktop".length);
			if (low.has_suffix (".url"))
				return s.substring (0, s.length - ".url".length);
			if (low.has_suffix (".dockitem"))
				return s.substring (0, s.length - ".dockitem".length);
			return s;
		}

		public string launcher_id_stem (string uri_or_id)
		{
			string s = uri_or_id.strip ();
			if (s == "")
				return "item";

			string? local = uri_or_path_to_local_path (s);
			if (local != null) {
				s = Path.get_basename (local);
			} else {
				int scheme_sep = s.index_of ("://");
				if (scheme_sep >= 0)
					s = s.substring (scheme_sep + 3);
				else if (s.has_prefix ("applications:"))
					s = s.substring ("applications:".length);

				s = s.replace ("\\", "/");
				while (s.length > 1 && s.has_suffix ("/"))
					s = s.substring (0, s.length - 1);
				int slash = s.last_index_of_char ('/');
				if (slash >= 0 && slash + 1 < s.length)
					s = s.substring (slash + 1);
			}

			s = strip_launcher_extension (s);

			var sb = new StringBuilder ();
			for (int i = 0; i < s.length; i++) {
				char c = s[i];
				if (c < 0x20 || c == '<' || c == '>' || c == ':' || c == '"'
					|| c == '/' || c == '\\' || c == '|' || c == '?' || c == '*')
					sb.append_c ('_');
				else
					sb.append_c (c);
			}
			string cleaned = sb.str.strip ();
			while (cleaned.has_suffix (".") || cleaned.has_suffix (" "))
				cleaned = cleaned.substring (0, cleaned.length - 1);
			if (cleaned == "")
				cleaned = "item";

			string up = cleaned.up ();
			foreach (unowned string reserved in DOS_RESERVED_STEMS) {
				if (up == reserved) {
					cleaned = cleaned + "_app";
					break;
				}
			}
			return cleaned;
		}

		public bool launcher_exists (string uri_or_path)
		{
			string s = uri_or_path.strip ();
			if (s == "" || s.has_prefix ("docklet://"))
				return false;

			string? local = uri_or_path_to_local_path (s);
			if (local != null)
				return FileUtils.test (local, FileTest.EXISTS);

			string resolved = resolve_launcher_uri (s);
			string? res_local = uri_or_path_to_local_path (resolved);
			if (res_local != null)
				return FileUtils.test (res_local, FileTest.EXISTS);

			return false;
		}

		public GLib.FileMonitor? monitor_launcher (GLib.File launcher_file)
		{
			try {
				return launcher_file.monitor_file (FileMonitorFlags.NONE, null);
			} catch {
				return null;
			}
		}

		public string? extract_link_shortcut_url (string uri_or_path)
		{
			string? path = uri_or_path_to_local_path (uri_or_path);
			if (path == null)
				path = uri_or_path.strip ();

			string low_path = path.down ();
			if (!low_path.has_suffix (".desktop") && !low_path.has_suffix (".url"))
				return null;

			try {
				var file = File.new_for_path (path);
				if (!file.query_exists ())
					return null;

				uint8[] contents;
				if (!file.load_contents (null, out contents, null))
					return null;

				string raw = (string) contents;
				bool is_link_desktop = raw.contains ("Type=Link");
				var lines = raw.split ("\n");
				string? found_url = null;

				foreach (unowned string line in lines) {
					string s = line.strip ();
					if ((low_path.has_suffix (".url") || is_link_desktop)
						&& (s.has_prefix ("URL=") || s.has_prefix ("URL[$e]=") || s.has_prefix ("URL["))) {
						int eq = s.index_of ("=");
						if (eq >= 0)
							found_url = s.slice (eq + 1, s.length).strip ();
					} else if (s.has_prefix ("Exec=")) {
						int app_idx = s.index_of ("--app=");
						if (app_idx >= 0) {
							string candidate = s.slice (app_idx + 6, s.length).strip ();
							if (candidate.has_prefix ("http://") || candidate.has_prefix ("https://")) {
								int space_idx = candidate.index_of (" ");
								if (space_idx >= 0)
									candidate = candidate.slice (0, space_idx).strip ();
								found_url = candidate;
							}
						} else {
							int http_idx = s.index_of ("http://");
							if (http_idx < 0)
								http_idx = s.index_of ("https://");
							if (http_idx >= 0) {
								string candidate = s.slice (http_idx, s.length).strip ();
								int space_idx = candidate.index_of (" ");
								if (space_idx >= 0)
									candidate = candidate.slice (0, space_idx).strip ();
								found_url = candidate;
							}
						}
					}
				}

				if (found_url != null && (found_url.has_prefix ("http://")
					|| found_url.has_prefix ("https://") || found_url.has_prefix ("ftp://")))
					return found_url;
			} catch { }

			return null;
		}

		public bool can_launcher_accept_uri (string launcher_uri, string candidate_uri)
		{
			var desc = load_launcher (launcher_uri);
			if (desc == null || candidate_uri == "")
				return false;

			bool is_remote = candidate_uri.has_prefix ("http://")
				|| candidate_uri.has_prefix ("https://")
				|| candidate_uri.has_prefix ("ftp://");

			if (desc.mime_types.size == 1 && desc.mime_types.contains ("inode/directory")) {
				if (is_remote)
					return false;
				var f = candidate_uri.has_prefix ("/") ? File.new_for_path (candidate_uri) : File.new_for_uri (candidate_uri);
				return f.query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY;
			}

			if (desc.mime_types.size > 0) {
				if (is_remote) {
					foreach (var mt in desc.mime_types) {
						if (mt.contains ("html") || mt.contains ("http") || mt.contains ("url"))
							return true;
					}
					return false;
				}

				var file = candidate_uri.has_prefix ("/") ? File.new_for_path (candidate_uri) : File.new_for_uri (candidate_uri);
				string? uri_ct = null;
				try {
					var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
					uri_ct = info.get_content_type ();
				} catch { }

				if (uri_ct == null || uri_ct == "application/x-zerosize") {
					bool uncertain;
					uri_ct = ContentType.guess (candidate_uri, null, out uncertain);
				}
				if (uri_ct == null)
					return false;

				foreach (var sup in desc.mime_types) {
					if (ContentType.is_a (uri_ct, sup) || ContentType.equals (uri_ct, sup))
						return true;
				}
				return false;
			}

			return desc.supports_files || desc.supports_uris;
		}

		static bool path_is_mounted (string path)
		{
			foreach (var m in VolumeMonitor.get ().get_mounts ()) {
				var m_root = m.get_root ();
				if (m_root == null)
					continue;
				var m_path = m_root.get_path ();
				if (m_path != null && path.contains (m_path))
					return true;
			}
			return false;
		}

		static bool open_single_default_uri (string uri, GLib.AppLaunchContext? context)
		{
			try {
				if (AppInfo.launch_default_for_uri (uri, null))
					return true;
				if (AppInfo.launch_default_for_uri (uri, context))
					return true;
			} catch {
				try {
					if (AppInfo.launch_default_for_uri (uri, context))
						return true;
				} catch { }
			}

			try {
				string arg = uri;
				if (uri.has_prefix ("file://")) {
					string? p = File.new_for_uri (uri).get_path ();
					if (p != null)
						arg = p;
				}
				Process.spawn_async (null, { "xdg-open", arg }, null, SpawnFlags.SEARCH_PATH, null, null);
				return true;
			} catch (Error e) {
				critical ("Failed to open URI '%s': %s", uri, e.message);
				return false;
			}
		}

		static GLib.AppLaunchContext get_display_launch_context ()
		{
			var display = Gdk.Display.get_default ();
			GLib.AppLaunchContext ctx = display != null ? display.get_app_launch_context () : new GLib.AppLaunchContext ();
			ctx.unsetenv ("GTK_USE_PORTAL");
			ctx.unsetenv ("GIO_LAUNCHED_DESKTOP_FILE");
			ctx.unsetenv ("GIO_LAUNCHED_DESKTOP_FILE_PID");
			return ctx;
		}

		static string strip_xdg_field_codes (string cmd)
		{
			string[] codes = { "%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%i", "%c", "%k", "%v", "%m" };
			string res = cmd;
			foreach (unowned string code in codes)
				res = res.replace (code, "");
			return res.strip ();
		}

		static bool script_forwards_positional_args (string script_body)
		{
			foreach (unowned string raw_line in script_body.split ("\n")) {
				string s = raw_line.strip ();
				if (s == "" || s.has_prefix ("#"))
					continue;
				if (s.contains ("$@") || s.contains ("$*") || s.contains ("$1")
					|| s.contains ("${@") || s.contains ("${*") || s.contains ("${1"))
					return true;
			}
			return false;
		}

		static bool is_non_exec_script_statement (string s)
		{
			string[] prefixes = {
				"echo ", "echo\t", "echo\"", "echo'", "printf ", "sleep ",
				"mkdir ", "rm ", "touch ", "killall ", "pkill ", "set ",
				"if ", "then", "else", "elif ", "fi", "for ", "while ", "do", "done", "case ", "esac"
			};
			if (s == "echo" || s == "true" || s == "false" || s == "exit" || s.has_prefix ("exit "))
				return true;
			foreach (unowned string p in prefixes) {
				if (s.has_prefix (p))
					return true;
			}
			return false;
		}

		string try_build_forwarded_exec_command (string launcher_path, string[] uris, out string out_workdir)
		{
			out_workdir = "";
			var desc = load_launcher (launcher_path);
			if (desc == null || desc.exec_command.strip () == "")
				return "";

			string raw_exec = desc.exec_command.strip ();
			out_workdir = desc.working_dir;
			bool exec_has_field_code = raw_exec.contains ("%u") || raw_exec.contains ("%U")
				|| raw_exec.contains ("%f") || raw_exec.contains ("%F");

			string[] argv = Hal.Runtime.parse_command_argv (strip_xdg_field_codes (raw_exec));
			int exe_idx = 0;
			while (exe_idx < argv.length) {
				string tok = argv[exe_idx];
				if (tok == "env") {
					exe_idx++;
					continue;
				}
				if (!tok.has_prefix ("-") && tok.contains ("=")) {
					exe_idx++;
					continue;
				}
				break;
			}

			string base_cmd = "";
			var env_exports = new Gee.ArrayList<string> ();

			if (exe_idx < argv.length && argv[exe_idx].down ().has_suffix (".sh")) {
				string script_path = Hal.Runtime.expand_path_variables (argv[exe_idx]);
				if (!Path.is_absolute (script_path) && out_workdir != "")
					script_path = Path.build_filename (out_workdir, script_path);

				try {
					var sf = File.new_for_path (script_path);
					if (sf.query_exists ()) {
						var sinfo = sf.query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
						if (sinfo.get_size () > 0 && sinfo.get_size () < 16384) {
							uint8[] bytes;
							if (sf.load_contents (null, out bytes, null)) {
								string body = (string) bytes;
								if (script_forwards_positional_args (body)) {
									if (exec_has_field_code)
										return "";
									base_cmd = strip_xdg_field_codes (raw_exec);
								} else {
									string primary_line = "";
									foreach (unowned string raw_line in body.split ("\n")) {
										string s = raw_line.strip ();
										if (s == "" || s.has_prefix ("#"))
											continue;
										if (s.has_prefix ("cd ")) {
											string dir_tok = s.substring (3).strip ();
											if (dir_tok.length >= 2 && ((dir_tok.has_prefix ("\"") && dir_tok.has_suffix ("\""))
												|| (dir_tok.has_prefix ("'") && dir_tok.has_suffix ("'"))))
												dir_tok = dir_tok.substring (1, dir_tok.length - 2);
											if (out_workdir == "" && dir_tok != "")
												out_workdir = Hal.Runtime.expand_path_variables (dir_tok);
											continue;
										}
										if (s.has_prefix ("export ")) {
											string exp_val = s.substring (7).strip ();
											if (exp_val.contains ("="))
												env_exports.add (exp_val);
											continue;
										}
										if (is_non_exec_script_statement (s))
											continue;
										primary_line = s;
									}
									if (primary_line != "") {
										if (primary_line.has_prefix ("exec "))
											primary_line = primary_line.substring (5).strip ();
										while (primary_line.has_suffix ("&") || primary_line.has_suffix (";"))
											primary_line = primary_line.substring (0, primary_line.length - 1).strip ();
										base_cmd = primary_line;
									}
								}
							}
						}
					}
				} catch { }
			} else if (!exec_has_field_code) {
				base_cmd = strip_xdg_field_codes (raw_exec);
			}

			if (base_cmd == "")
				return "";

			var sb = new StringBuilder ();
			if (env_exports.size > 0) {
				sb.append ("env ");
				foreach (var exp in env_exports) {
					sb.append (exp);
					sb.append_c (' ');
				}
			}
			sb.append (base_cmd);

			for (int i = exe_idx + 1; i < argv.length && argv[exe_idx].down ().has_suffix (".sh") && base_cmd != strip_xdg_field_codes (raw_exec); i++) {
				sb.append_c (' ');
				sb.append (Shell.quote (argv[i]));
			}

			foreach (unowned string u in uris) {
				string arg = u;
				if (u.has_prefix ("file://")) {
					string? local_p = File.new_for_uri (u).get_path ();
					if (local_p != null && local_p != "")
						arg = local_p;
				}
				sb.append_c (' ');
				sb.append (Shell.quote (arg));
			}
			return sb.str;
		}

		public bool launch_app (string launcher_uri, string[] uris)
		{
			var context = get_display_launch_context ();
			if (launcher_uri == null || launcher_uri.strip () == "") {
				bool ok = false;
				foreach (unowned string u in uris) {
					if (open_single_default_uri (u, context))
						ok = true;
				}
				return ok;
			}

			string? launcher_path = uri_or_path_to_local_path (launcher_uri);
			if (launcher_path == null) {
				string resolved = resolve_launcher_uri (launcher_uri);
				launcher_path = uri_or_path_to_local_path (resolved);
			}
			if (launcher_path == null || !FileUtils.test (launcher_path, FileTest.EXISTS)) {
				warning ("Application '%s' doesn't exist", launcher_uri);
				return false;
			}

			var keyfile = new KeyFile ();
			if (load_keyfile_safe (keyfile, launcher_path, KeyFileFlags.NONE)) {
				try {
					if (keyfile.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE)
						&& keyfile.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE).strip () == KeyFileDesktop.TYPE_LINK) {
						string? url = null;
						if (keyfile.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_URL))
							url = keyfile.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_URL).strip ();
						else if (keyfile.has_key (KeyFileDesktop.GROUP, "URL[$e]"))
							url = keyfile.get_string (KeyFileDesktop.GROUP, "URL[$e]").strip ();
						if (url == null || url == "")
							url = extract_link_shortcut_url (launcher_path);
						if (url != null && url != "")
							return open_single_default_uri (url, context);
						return false;
					}
				} catch { }
			}

			var info = new DesktopAppInfo.from_filename (launcher_path);
			if (info == null) {
				critical ("Unable to use application '%s' for execution.", launcher_path);
				return false;
			}

			try {
				if (uris.length == 0)
					return info.launch (null, context);

				string fwd_workdir;
				string forwarded_cmd = try_build_forwarded_exec_command (launcher_path, uris, out fwd_workdir);
				if (forwarded_cmd != "")
					return launch_command (forwarded_cmd, fwd_workdir);

				var uri_list = new GLib.List<string> ();
				var file_list = new GLib.List<File> ();
				bool has_remote_uri = false;

				foreach (unowned string u in uris) {
					uri_list.append (u);
					if (u.has_prefix ("file://") || u.has_prefix ("/")) {
						var f = u.has_prefix ("/") ? File.new_for_path (u) : File.new_for_uri (u);
						string? p = f.get_path ();
						if (p != null && p != "" && !f.is_native () && !path_is_mounted (p))
							f.mount_enclosing_volume.begin (0, null);
						file_list.append (f);
					} else {
						has_remote_uri = true;
						file_list.append (File.new_for_uri (u));
					}
				}

				if (has_remote_uri) {
					try {
						return info.launch_uris (uri_list, context);
					} catch (Error e) {
						warning ("Failed to launch '%s' with remote URIs: %s", info.get_name (), e.message);
					}
				}

				if (info.supports_files ()) {
					try {
						return info.launch (file_list, context);
					} catch (Error e) {
						warning ("Failed to launch '%s' with files: %s", info.get_name (), e.message);
					}
				}

				try {
					return info.launch_uris (uri_list, context);
				} catch (Error e) {
					warning ("launch_uris failed for '%s', falling back to basic launch: %s", info.get_name (), e.message);
					return info.launch (null, context);
				}
			} catch (Error e) {
				critical ("%s: %s", launcher_path, e.message);
				return false;
			}
		}

		public bool launch_action (string launcher_uri, string action_id, string fallback_exec = "")
		{
			var context = get_display_launch_context ();
			if (action_id != "" && launcher_uri != "") {
				string? path = uri_or_path_to_local_path (launcher_uri);
				if (path == null) {
					string resolved = resolve_launcher_uri (launcher_uri);
					path = uri_or_path_to_local_path (resolved);
				}
				if (path != null && FileUtils.test (path, FileTest.EXISTS)) {
					var desktop_info = new DesktopAppInfo.from_filename (path);
					if (desktop_info != null) {
						desktop_info.launch_action (action_id, context);
						return true;
					}
				}
			}
			if (fallback_exec != "")
				return launch_command (fallback_exec, "");
			return false;
		}

		public bool launch_command (string cmdline, string working_dir = "")
		{
			var context = get_display_launch_context ();
			string clean = cmdline.strip ();
			if (clean == "")
				return false;

			if (working_dir != "") {
				try {
					string[] argv;
					if (Shell.parse_argv (clean, out argv) && argv.length > 0) {
						Process.spawn_async (working_dir, argv, null, SpawnFlags.SEARCH_PATH, null, null);
						return true;
					}
				} catch { }
			}

			try {
				var app = AppInfo.create_from_commandline (clean, null, AppInfoCreateFlags.NONE);
				if (app != null && app.launch (null, context))
					return true;
			} catch { }

			try {
				Process.spawn_command_line_async (clean);
				return true;
			} catch {
				return false;
			}
		}

		static string resolve_desktop_id_to_uri (string id)
		{
			string desktop_id = id.has_suffix (".desktop") ? id : id + ".desktop";
			var app_info = new DesktopAppInfo (desktop_id);
			if (app_info == null)
				return "";
			unowned string? fn = app_info.get_filename ();
			if (fn == null || fn == "")
				return "";
			return File.new_for_path (fn).get_uri ();
		}

		public string get_default_app_for_role (DefaultAppRole role)
		{
			switch (role) {
			case DefaultAppRole.FILE_MANAGER:
				var fm = AppInfo.get_default_for_type ("inode/directory", false);
				if (fm != null && fm.get_id () != null) {
					string u = resolve_desktop_id_to_uri (fm.get_id ());
					if (u != "")
						return u;
				}
				foreach (unowned string fb in FALLBACK_FILE_MANAGERS) {
					string u = resolve_desktop_id_to_uri (fb);
					if (u != "")
						return u;
				}
				return "";

			case DefaultAppRole.WEB_BROWSER:
				var br = AppInfo.get_default_for_type ("x-scheme-handler/http", false);
				if (br != null && br.get_id () != null) {
					string u = resolve_desktop_id_to_uri (br.get_id ());
					if (u != "")
						return u;
				}
				foreach (unowned string fb in FALLBACK_BROWSERS) {
					string u = resolve_desktop_id_to_uri (fb);
					if (u != "")
						return u;
				}
				return "";

			case DefaultAppRole.TERMINAL:
				foreach (unowned string fb in FALLBACK_TERMINALS) {
					string u = resolve_desktop_id_to_uri (fb);
					if (u != "")
						return u;
				}
				return "";

			case DefaultAppRole.TEXT_EDITOR:
				var ed = AppInfo.get_default_for_type ("text/plain", false);
				if (ed != null && ed.get_id () != null) {
					string u = resolve_desktop_id_to_uri (ed.get_id ());
					if (u != "")
						return u;
				}
				foreach (unowned string fb in FALLBACK_EDITORS) {
					string u = resolve_desktop_id_to_uri (fb);
					if (u != "")
						return u;
				}
				return "";
			}
			return "";
		}

		public Gee.ArrayList<string> discover_default_seed_apps ()
		{
			var list = new Gee.ArrayList<string> ();
			DefaultAppRole[] roles = {
				DefaultAppRole.FILE_MANAGER,
				DefaultAppRole.WEB_BROWSER,
				DefaultAppRole.TERMINAL,
				DefaultAppRole.TEXT_EDITOR
			};
			foreach (var role in roles) {
				string u = get_default_app_for_role (role);
				if (u != "" && !list.contains (u))
					list.add (u);
			}
			return list;
		}

		static bool categories_contain (string? categories, string[] search_tags)
		{
			if (categories == null || categories == "")
				return false;
			foreach (unowned string raw_cat in categories.split (";")) {
				string cat = raw_cat.strip ();
				if (cat == "")
					continue;
				foreach (unowned string tag in search_tags) {
					if (cat == tag)
						return true;
				}
			}
			return false;
		}

		public int populate_category_folder (GLib.File folder, string icon_name, string[] priority_ids,
			string[] category_tags, int max_items = 6)
		{
			var matched_paths = new Gee.ArrayList<string> ();
			var seen_paths = new Gee.HashSet<string> ();

			foreach (unowned string id in priority_ids) {
				if (matched_paths.size >= max_items)
					break;
				string desktop_id = id.has_suffix (".desktop") ? id : id + ".desktop";
				var app = new DesktopAppInfo (desktop_id);
				if (app == null && !id.has_suffix (".desktop"))
					app = new DesktopAppInfo (desktop_id + ".desktop");
				if (app != null && app.should_show ()) {
					unowned string? fn = app.get_filename ();
					if (fn != null && !seen_paths.contains (fn)) {
						seen_paths.add (fn);
						matched_paths.add (fn);
					}
				}
			}

			if (matched_paths.size < max_items) {
				foreach (var info in AppInfo.get_all ()) {
					if (matched_paths.size >= max_items)
						break;
					var d_info = info as DesktopAppInfo;
					if (d_info == null || !d_info.should_show ())
						continue;
					unowned string? fn = d_info.get_filename ();
					if (fn == null || seen_paths.contains (fn))
						continue;
					if (categories_contain (d_info.get_categories (), category_tags)) {
						seen_paths.add (fn);
						matched_paths.add (fn);
					}
				}
			}

			if (matched_paths.size == 0)
				return 0;

			try {
				if (!folder.query_exists ())
					folder.make_directory_with_parents ();
			} catch { }

			var dot_dir = folder.get_child (".directory");
			if (!dot_dir.query_exists ()) {
				string? dot_path = dot_dir.get_path ();
				if (dot_path != null) {
					try {
						FileUtils.set_contents (dot_path, "[Desktop Entry]\nType=Directory\nIcon=%s\n".printf (icon_name));
					} catch { }
				}
			}

			try {
				folder.set_attribute_string (FILE_ATTRIBUTE_CUSTOM_ICON_NAME, icon_name, FileQueryInfoFlags.NONE, null);
			} catch { }

			int added_count = 0;
			foreach (string fn in matched_paths) {
				var copied = copy_launcher_to_directory (File.new_for_path (fn), folder);
				if (copied != null)
					added_count++;
			}

			return added_count;
		}

		public bool ensure_launcher_folder (GLib.File folder, string display_name = "", string icon_token = "")
		{
			string? folder_path = folder.get_path ();
			if (folder_path == null || folder_path == "")
				return false;

			if (DirUtils.create_with_parents (folder_path, 0755) != 0 && !FileUtils.test (folder_path, FileTest.IS_DIR))
				return false;

			var dot_dir = folder.get_child (".directory");
			string? dot_path = dot_dir.get_path ();
			if (dot_path != null && (display_name != "" || icon_token != "" || !dot_dir.query_exists ())) {
				var kf = new KeyFile ();
				if (dot_dir.query_exists ())
					load_keyfile_safe (kf, dot_path, KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS);
				kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE, KeyFileDesktop.TYPE_DIRECTORY);
				if (display_name != "")
					kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME, display_name);
				if (icon_token == "-") {
					try {
						if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON))
							kf.remove_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
					} catch { }
				} else if (icon_token != "") {
					kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON, icon_token);
				} else {
					bool has_icon = false;
					try {
						has_icon = kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
					} catch { }
					if (!has_icon)
						kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON, "folder");
				}
				try {
					FileUtils.set_contents (dot_path, kf.to_data ());
				} catch { }
			}

			if (icon_token == "-") {
				try {
					folder.set_attribute (FILE_ATTRIBUTE_CUSTOM_ICON_NAME, FileAttributeType.INVALID, null, FileQueryInfoFlags.NONE, null);
				} catch { }
			} else if (icon_token != "") {
				try {
					folder.set_attribute_string (FILE_ATTRIBUTE_CUSTOM_ICON_NAME, icon_token, FileQueryInfoFlags.NONE, null);
				} catch { }
			}

			return true;
		}

		public bool is_folder_metadata_file (string filename)
		{
			string lower = filename.ascii_down ();
			return (filename == ".directory" || filename.has_prefix (".directory.")
				|| lower == "desktop.ini" || lower.has_prefix ("desktop.ini."));
		}

		public string get_folder_display_name (GLib.File folder)
		{
			var dot_dir = folder.get_child (".directory");
			string? dot_path = dot_dir.get_path ();
			if (dot_path == null || !FileUtils.test (dot_path, FileTest.IS_REGULAR))
				return "";

			var kf = new KeyFile ();
			if (!load_keyfile_safe (kf, dot_path, KeyFileFlags.KEEP_TRANSLATIONS))
				return "";
			try {
				if (kf.has_group (KeyFileDesktop.GROUP) && kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME)) {
					string loc = kf.get_locale_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME, null).strip ();
					if (loc != "")
						return loc;
				}
			} catch { }
			try {
				if (kf.has_group (KeyFileDesktop.GROUP) && kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME))
					return kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME).strip ();
			} catch { }
			return "";
		}

		public GLib.File? copy_launcher_to_directory (GLib.File src_launcher, GLib.File dest_dir)
		{
			if (!src_launcher.query_exists ())
				return null;
			string? bname = src_launcher.get_basename ();
			if (bname == null || bname == "")
				return null;

			try {
				if (!dest_dir.query_exists ())
					dest_dir.make_directory_with_parents ();
				var dst = dest_dir.get_child (bname);
				if (src_launcher.equal (dst))
					return dst;
				src_launcher.copy (dst, FileCopyFlags.OVERWRITE, null, null);
				string? dst_path = dst.get_path ();
				if (dst_path != null && bname.has_suffix (".desktop")) {
					FileUtils.chmod (dst_path, 0755);
					launcher_cache.unset (dst_path);
				}
				return dst;
			} catch {
				return null;
			}
		}

		public GLib.File? relocate_launcher_for_dock_pin (GLib.File folder_launcher)
		{
			if (!folder_launcher.query_exists ())
				return null;
			string? src_path = folder_launcher.get_path ();
			string? bname = folder_launcher.get_basename ();
			if (src_path == null || bname == null || !bname.down ().has_suffix (".desktop"))
				return null;

			var parent_dir = folder_launcher.get_parent ();
			if (parent_dir != null) {
				foreach (var app_dir in discover_launcher_dirs ()) {
					if (parent_dir.equal (app_dir))
						return folder_launcher;
				}
			}

			if (!bname.has_prefix ("wayplank-app-")) {
				var src_desc = load_launcher (src_path);
				string resolved_uri = resolve_launcher_uri (bname);
				string? resolved_path = uri_or_path_to_local_path (resolved_uri);
				if (src_desc != null && !src_desc.has_custom_icon_override
					&& resolved_path != null && resolved_path != src_path
					&& FileUtils.test (resolved_path, FileTest.IS_REGULAR)) {
					var existing_desc = load_launcher (resolved_path);
					if (existing_desc != null
						&& existing_desc.exec_command == src_desc.exec_command
						&& existing_desc.icon_token == src_desc.icon_token
						&& existing_desc.unlocalized_name == src_desc.unlocalized_name) {
						return File.new_for_path (resolved_path);
					}
				}
			}

			string user_apps_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			DirUtils.create_with_parents (user_apps_dir, 0755);
			var dest_dir = File.new_for_path (user_apps_dir);
			return copy_launcher_to_directory (folder_launcher, dest_dir);
		}

		static string extract_primary_exec_path (string exec_cmd)
		{
			string clean = exec_cmd.strip ();
			if (clean == "")
				return "";

			try {
				string[] argv;
				if (Shell.parse_argv (clean, out argv) && argv.length > 0) {
					for (int i = 0; i < argv.length; i++) {
						string tok = argv[i].strip ();
						if (tok == "" || tok.has_prefix ("-"))
							continue;
						if (tok.contains ("=") && !tok.has_prefix ("/"))
							continue;
						if (tok == "env" || tok == "exec" || tok == "nohup" || tok == "setsid"
							|| tok == "firejail" || tok == "gamemoderun" || tok == "prime-run")
							continue;
						if ((tok == "sh" || tok == "bash" || tok == "dash" || tok == "zsh"
							|| tok == "/bin/sh" || tok == "/bin/bash" || tok == "/usr/bin/sh" || tok == "/usr/bin/bash")
							&& i + 2 < argv.length && argv[i + 1] == "-c") {
							return extract_primary_exec_path (argv[i + 2]);
						}
						return tok;
					}
				}
			} catch { }

			return clean.split (" ")[0].replace ("\"", "").replace ("'", "");
		}

		static string strip_portable_bundle_stem (string raw_name)
		{
			string s = Path.get_basename (raw_name).down ().strip ();
			string[] exts = { ".appimage", ".run", ".bin", ".sh", ".py", ".exe" };
			foreach (unowned string ext in exts) {
				if (s.has_suffix (ext) && s.length > ext.length) {
					s = s.substring (0, s.length - ext.length);
					break;
				}
			}
			string[] arches = {
				"-x86_64", "_x86_64", "-x64", "_x64", "-amd64", "_amd64",
				"-linux", "_linux", "-i386", "_i386", "-arm64", "_arm64", "-aarch64", "_aarch64"
			};
			foreach (unowned string arch in arches) {
				if (s.has_suffix (arch) && s.length > arch.length) {
					s = s.substring (0, s.length - arch.length);
					break;
				}
			}
			try {
				var ver_re = new GLib.Regex ("[-_vV]+[0-9]+(\\.[0-9]+)*.*$");
				string stripped = ver_re.replace_literal (s, -1, 0, "");
				if (stripped.length >= 2)
					s = stripped;
			} catch { }
			return s;
		}

		static string detect_bundle_image_extension (string src_path)
		{
			int w = 0, h = 0;
			unowned Gdk.PixbufFormat? fmt = Gdk.Pixbuf.get_file_info (src_path, out w, out h);
			if (fmt != null) {
				string? fname = fmt.get_name ();
				if (fname != null) {
					switch (fname.down ()) {
					case "png":
						return ".png";
					case "svg":
						return ".svg";
					case "xpm":
						return ".xpm";
					default:
						break;
					}
				}
			}

			string low = src_path.down ();
			if (low.has_suffix (".svg"))
				return ".svg";
			if (low.has_suffix (".png"))
				return ".png";
			if (low.has_suffix (".xpm"))
				return ".xpm";
			return "";
		}

		static string safe_bundle_icon_target (string mount_real, string candidate)
		{
			if (!FileUtils.test (candidate, FileTest.EXISTS))
				return "";
			string? real = Posix.realpath (candidate);
			if (real == null || real == "")
				return "";
			if (real != mount_real && !real.has_prefix (mount_real + "/"))
				return "";
			if (!FileUtils.test (real, FileTest.IS_REGULAR))
				return "";
			return real;
		}

		static string find_bundle_mount_icon_source (string mount_dir)
		{
			string? mount_real = Posix.realpath (mount_dir);
			if (mount_real == null || mount_real == "" || !FileUtils.test (mount_real, FileTest.IS_DIR))
				return "";

			string dir_icon = safe_bundle_icon_target (mount_real, Path.build_filename (mount_real, ".DirIcon"));
			if (dir_icon != "")
				return dir_icon;

			string desktop_icon_name = "";
			try {
				var d = Dir.open (mount_real, 0);
				unowned string? entry = null;
				while ((entry = d.read_name ()) != null) {
					if (!entry.down ().has_suffix (".desktop"))
						continue;
					string dp = Path.build_filename (mount_real, entry);
					var kf = new KeyFile ();
					if (load_keyfile_safe (kf, dp, KeyFileFlags.NONE) && kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON)) {
						desktop_icon_name = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON).strip ();
						if (desktop_icon_name != "")
							break;
					}
				}
			} catch { }

			string[] exts = { "", ".svg", ".png", ".xpm" };
			string[] subdirs = {
				"",
				"usr/share/icons/hicolor/scalable/apps",
				"usr/share/icons/hicolor/512x512/apps",
				"usr/share/icons/hicolor/256x256/apps",
				"usr/share/icons/hicolor/128x128/apps",
				"usr/share/icons/hicolor/64x64/apps",
				"usr/share/icons/hicolor/48x48/apps",
				"usr/share/pixmaps"
			};

			if (desktop_icon_name != "" && !desktop_icon_name.contains ("/")) {
				foreach (unowned string sub in subdirs) {
					foreach (unowned string ext in exts) {
						string cand = (sub == "")
							? Path.build_filename (mount_real, desktop_icon_name + ext)
							: Path.build_filename (mount_real, sub, desktop_icon_name + ext);
						string resolved = safe_bundle_icon_target (mount_real, cand);
						if (resolved != "")
							return resolved;
					}
				}
			}

			try {
				var d2 = Dir.open (mount_real, 0);
				unowned string? entry2 = null;
				while ((entry2 = d2.read_name ()) != null) {
					string low2 = entry2.down ();
					if (low2.has_suffix (".svg") || low2.has_suffix (".png") || low2.has_suffix (".xpm")) {
						string resolved = safe_bundle_icon_target (mount_real, Path.build_filename (mount_real, entry2));
						if (resolved != "")
							return resolved;
					}
				}
			} catch { }

			return "";
		}

		static string extract_mount_root_prefix (string raw_path)
		{
			int idx = raw_path.index_of ("/tmp/.mount_");
			if (idx < 0)
				return "";
			string tail = raw_path.substring (idx + "/tmp/".length);
			int slash = tail.index_of_char ('/');
			string mount_name = (slash > 0) ? tail.substring (0, slash) : tail;
			if (mount_name == "" || mount_name.contains (".."))
				return "";
			string full = Path.build_filename ("/tmp", mount_name);
			return FileUtils.test (full, FileTest.IS_DIR) ? full : "";
		}

		static string persist_synthetic_bundle_icon (string clean_stem, string src_icon_path)
		{
			try {
				uint8[] data;
				if (!FileUtils.get_data (src_icon_path, out data) || data.length < 8 || data.length > 4 * 1024 * 1024)
					return "";

				string ext = detect_bundle_image_extension (src_icon_path);
				if (ext == "")
					return "";

				string icon_dir = Path.build_filename (Environment.get_user_data_dir (), "wayplank", "synthetic-icons");
				DirUtils.create_with_parents (icon_dir, 0755);

				string[] all_exts = { ".svg", ".png", ".xpm" };
				foreach (unowned string old_ext in all_exts) {
					if (old_ext != ext) {
						string stale = Path.build_filename (icon_dir, "wayplank-app-%s%s".printf (clean_stem, old_ext));
						if (FileUtils.test (stale, FileTest.EXISTS))
							FileUtils.unlink (stale);
					}
				}

				string dst_path = Path.build_filename (icon_dir, "wayplank-app-%s%s".printf (clean_stem, ext));
				FileUtils.set_data (dst_path, data);
				return dst_path;
			} catch {
				return "";
			}
		}

		static void delete_synthetic_bundle_icons (string clean_stem)
		{
			if (clean_stem == "")
				return;
			string icon_dir = Path.build_filename (Environment.get_user_data_dir (), "wayplank", "synthetic-icons");
			string[] all_exts = { ".svg", ".png", ".xpm" };
			foreach (unowned string ext in all_exts) {
				string p = Path.build_filename (icon_dir, "wayplank-app-%s%s".printf (clean_stem, ext));
				if (FileUtils.test (p, FileTest.EXISTS))
					FileUtils.unlink (p);
			}
		}

		static string resolve_portable_bundle_icon (string clean_stem, string exec_cmd)
		{
			string exec_path = extract_primary_exec_path (exec_cmd);
			string exec_base = exec_path != "" ? Path.get_basename (exec_path).down () : "";
			string exec_stem = exec_path != "" ? strip_portable_bundle_stem (exec_path) : clean_stem;

			string mount_dir = extract_mount_root_prefix (exec_path);

			if (mount_dir == "" && exec_path != "") {
				foreach (var proc_entry in hal_kernel_scan_user_processes ()) {
					var snap = hal_kernel_inspect_process (proc_entry.pid, false);
					if (!snap.is_alive)
						continue;
					bool matched_proc = false;
					if (snap.env_appimage != "") {
						if (snap.env_appimage == exec_path || Path.get_basename (snap.env_appimage).down () == exec_base)
							matched_proc = true;
					}
					if (!matched_proc && exec_stem.length >= 3 && snap.exe_realpath.has_prefix ("/tmp/.mount_")) {
						string exe_b = strip_portable_bundle_stem (snap.exe_realpath);
						if (exe_b == exec_stem || exe_b == clean_stem)
							matched_proc = true;
					}
					if (matched_proc) {
						mount_dir = extract_mount_root_prefix (snap.exe_realpath);
						if (mount_dir == "")
							mount_dir = extract_mount_root_prefix (snap.working_dir);
						if (mount_dir == "")
							mount_dir = extract_mount_root_prefix (snap.full_cmdline);
						if (mount_dir != "")
							break;
					}
				}
			}

			if (mount_dir == "" && exec_stem.length >= 3) {
				try {
					var tmp_dir = Dir.open ("/tmp", 0);
					unowned string? t_entry = null;
					while ((t_entry = tmp_dir.read_name ()) != null) {
						if (!t_entry.has_prefix (".mount_"))
							continue;
						string m_tail = t_entry.substring (".mount_".length).down ();
						if (m_tail.has_prefix (exec_stem) || (clean_stem.length >= 3 && m_tail.has_prefix (clean_stem))) {
							string cand_mount = Path.build_filename ("/tmp", t_entry);
							if (FileUtils.test (cand_mount, FileTest.IS_DIR)) {
								mount_dir = cand_mount;
								break;
							}
						}
					}
				} catch { }
			}

			if (mount_dir != "") {
				string src_icon = find_bundle_mount_icon_source (mount_dir);
				if (src_icon != "") {
					string persisted = persist_synthetic_bundle_icon (clean_stem, src_icon);
					if (persisted != "")
						return persisted;
				}
			}

			string icon_dir = Path.build_filename (Environment.get_user_data_dir (), "wayplank", "synthetic-icons");
			string[] cached_exts = { ".svg", ".png", ".xpm" };
			foreach (unowned string ext in cached_exts) {
				string cached = Path.build_filename (icon_dir, "wayplank-app-%s%s".printf (clean_stem, ext));
				if (FileUtils.test (cached, FileTest.IS_REGULAR))
					return cached;
			}

			if (exec_path.has_prefix ("/") && !exec_path.has_prefix ("/usr/") && !exec_path.has_prefix ("/bin/")) {
				string install_dir = Path.get_dirname (exec_path);
				string adj_icon = find_bundle_mount_icon_source (install_dir);
				if (adj_icon != "")
					return adj_icon;
			}

			string[] pixmap_stems = { exec_stem, clean_stem };
			foreach (unowned string p_stem in pixmap_stems) {
				if (p_stem == "")
					continue;
				foreach (unowned string ext in cached_exts) {
					string pix = Path.build_filename ("/usr/share/pixmaps", p_stem + ext);
					if (FileUtils.test (pix, FileTest.IS_REGULAR))
						return pix;
				}
			}

			return "";
		}

		public GLib.File? synthesize_fallback_launcher (string safe_stem, string app_name, string exec_cmd,
			string icon_token, string wm_class_or_aumid = "", bool preserve_existing_fields = false)
		{
			string clean_stem = launcher_id_stem (safe_stem);
			if (clean_stem == "")
				return null;

			string user_app_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			DirUtils.create_with_parents (user_app_dir, 0755);

			string file_path = Path.build_filename (user_app_dir, "wayplank-app-%s.desktop".printf (clean_stem));
			var synth_file = File.new_for_path (file_path);

			string eff_name = app_name;
			string eff_exec = exec_cmd;
			string existing_icon = "";

			if (FileUtils.test (file_path, FileTest.EXISTS)) {
				try {
					var existing_kf = new KeyFile ();
					if (existing_kf.load_from_file (file_path, KeyFileFlags.NONE)) {
						if (!eff_exec.contains (" ") && existing_kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
							string ex = existing_kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
							if (ex.contains (" "))
								eff_exec = ex;
						}
						if (preserve_existing_fields && existing_kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME)) {
							string en = existing_kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME).strip ();
							if (en != "")
								eff_name = en;
						}
						if (existing_kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON))
							existing_icon = existing_kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON).strip ();
					}
				} catch { }
			}

			string eff_icon = icon_token.strip ();
			bool needs_bundle_probe = (eff_icon == "" || eff_icon == "application-x-executable"
				|| (!Path.is_absolute (eff_icon) && !has_native_icon (eff_icon)));
			if (needs_bundle_probe) {
				string bundle_icon = resolve_portable_bundle_icon (clean_stem, eff_exec);
				if (bundle_icon != "") {
					eff_icon = bundle_icon;
				} else if (existing_icon != "" && existing_icon != "application-x-executable"
					&& ((Path.is_absolute (existing_icon) && FileUtils.test (existing_icon, FileTest.EXISTS))
						|| (!Path.is_absolute (existing_icon) && has_native_icon (existing_icon)))) {
					eff_icon = existing_icon;
				}
			}
			if (eff_icon == "")
				eff_icon = "application-x-executable";

			string content;
			if (wm_class_or_aumid != "") {
				content = "[Desktop Entry]\nType=Application\nName=%s\nStartupWMClass=%s\nExec=%s\nIcon=%s\nTerminal=false\nNoDisplay=true\n".printf (
					eff_name, wm_class_or_aumid, eff_exec, eff_icon
				);
			} else {
				content = "[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\nTerminal=false\nNoDisplay=true\n".printf (
					eff_name, eff_exec, eff_icon
				);
			}

			bool content_unchanged = false;
			if (FileUtils.test (file_path, FileTest.EXISTS)) {
				try {
					string existing_content = "";
					if (FileUtils.get_contents (file_path, out existing_content) && existing_content == content)
						content_unchanged = true;
				} catch { }
			}

			try {
				if (!content_unchanged) {
					FileUtils.set_contents (file_path, content);
					launcher_cache.unset (file_path);
				}
				return synth_file;
			} catch {
				return null;
			}
		}

		public bool is_synthetic_launcher (string uri_or_id)
		{
			string? local = uri_or_path_to_local_path (uri_or_id);
			string bname = (local != null) ? Path.get_basename (local) : Path.get_basename (uri_or_id);
			return bname.has_prefix ("wayplank-app-");
		}

		public bool delete_synthetic_launcher (string launcher_uri, bool keep_shared_assets = false)
		{
			if (!is_synthetic_launcher (launcher_uri))
				return false;
			string? local = uri_or_path_to_local_path (launcher_uri);
			if (local == null || !FileUtils.test (local, FileTest.EXISTS))
				return false;
			string stem = strip_launcher_extension (Path.get_basename (local));
			if (stem.has_prefix ("wayplank-app-"))
				stem = stem.substring ("wayplank-app-".length);
			if (FileUtils.unlink (local) == 0) {
				launcher_cache.unset (local);
				if (!keep_shared_assets)
					delete_synthetic_bundle_icons (stem);
				return true;
			}
			return false;
		}

		public string apply_custom_launcher_icon (string launcher_uri, string new_icon_token)
		{
			string? src_path = uri_or_path_to_local_path (launcher_uri);
			if (src_path == null || !FileUtils.test (src_path, FileTest.EXISTS))
				return "";

			string user_apps_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			DirUtils.create_with_parents (user_apps_dir, 0755);

			string dest_path = Path.build_filename (user_apps_dir, Path.get_basename (src_path));
			bool created_by_wayplank = !FileUtils.test (dest_path, FileTest.EXISTS);

			try {
				var kf = new KeyFile ();
				if (!load_keyfile_safe (kf, src_path, KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS))
					return "";

				if (created_by_wayplank)
					kf.set_boolean (KeyFileDesktop.GROUP, "X-WayPlank-Created", true);

				if (!kf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon")) {
					string orig_icon = ORIGINAL_ICON_NONE_SENTINEL;
					try {
						if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON)) {
							string existing_ic = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
							if (existing_ic != null && existing_ic != "")
								orig_icon = existing_ic;
						}
					} catch { }
					kf.set_string (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon", orig_icon);
				}

				try {
					foreach (unowned string k in kf.get_keys (KeyFileDesktop.GROUP)) {
						if (k.has_prefix ("Icon["))
							kf.remove_key (KeyFileDesktop.GROUP, k);
					}
				} catch { }

				kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON, new_icon_token);
				kf.save_to_file (dest_path);
				launcher_cache.unset (src_path);
				launcher_cache.unset (dest_path);
				return File.new_for_path (dest_path).get_uri ();
			} catch (Error e) {
				critical ("Could not save custom launcher desktop file: %s", e.message);
				return "";
			}
		}

		public string reset_custom_launcher_icon (string launcher_uri, out string restored_icon_token)
		{
			restored_icon_token = "";
			string? cur_path = uri_or_path_to_local_path (launcher_uri);
			if (cur_path == null)
				return "";

			string basename = Path.get_basename (cur_path);
			string user_apps_dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			string user_desktop = Path.build_filename (user_apps_dir, basename);

			string? sys_path = null;
			foreach (unowned string data_dir in Environment.get_system_data_dirs ()) {
				string candidate = Path.build_filename (data_dir, "applications", basename);
				if (candidate != user_desktop && FileUtils.test (candidate, FileTest.EXISTS)) {
					sys_path = candidate;
					break;
				}
			}
			if (sys_path == null) {
				string[] extra_dirs = {
					Path.build_filename (Environment.get_user_data_dir (), "flatpak", "exports", "share", "applications"),
					"/var/lib/flatpak/exports/share/applications",
					"/var/lib/snapd/desktop/applications",
					"/usr/local/share/applications",
					"/usr/share/applications"
				};
				foreach (unowned string dir in extra_dirs) {
					string candidate = Path.build_filename (dir, basename);
					if (candidate != user_desktop && FileUtils.test (candidate, FileTest.EXISTS)) {
						sys_path = candidate;
						break;
					}
				}
			}

			bool can_unlink_user_override = false;
			if (sys_path != null && FileUtils.test (user_desktop, FileTest.EXISTS)) {
				try {
					var ukf = new KeyFile ();
					if (load_keyfile_safe (ukf, user_desktop, KeyFileFlags.NONE)
						&& ukf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-Created")
						&& ukf.get_boolean (KeyFileDesktop.GROUP, "X-WayPlank-Created")) {
						can_unlink_user_override = true;
					}
				} catch { }
			}

			string target_uri = launcher_uri;
			if (sys_path != null && (!FileUtils.test (user_desktop, FileTest.EXISTS) || can_unlink_user_override)) {
				if (FileUtils.test (user_desktop, FileTest.EXISTS)) {
					FileUtils.unlink (user_desktop);
					launcher_cache.unset (user_desktop);
				}
				launcher_cache.unset (sys_path);
				target_uri = File.new_for_path (sys_path).get_uri ();
				var sys_desc = load_launcher (target_uri);
				if (sys_desc != null)
					restored_icon_token = sys_desc.icon_token;
				return target_uri;
			}

			if (FileUtils.test (cur_path, FileTest.EXISTS)) {
				try {
					var kf = new KeyFile ();
					if (load_keyfile_safe (kf, cur_path, KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS)) {
						string? orig = null;
						if (kf.has_key (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon")) {
							orig = kf.get_string (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon");
							kf.remove_key (KeyFileDesktop.GROUP, "X-WayPlank-Original-Icon");
						} else if (sys_path != null) {
							var skf = new KeyFile ();
							if (load_keyfile_safe (skf, sys_path, KeyFileFlags.NONE)
								&& skf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON))
								orig = skf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
						}

						if (orig == ORIGINAL_ICON_NONE_SENTINEL) {
							if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON))
								kf.remove_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
							kf.save_to_file (cur_path);
							restored_icon_token = "";
						} else if (orig != null && orig != "") {
							kf.set_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON, orig);
							kf.save_to_file (cur_path);
							restored_icon_token = orig;
						}
						launcher_cache.unset (cur_path);
					}
				} catch { }
			}

			return target_uri;
		}

		public string find_installed_browser_binary (BrowserFamily family, string fallback_executable = "")
		{
			string[] candidates = {};
			switch (family) {
			case BrowserFamily.CHROME:
				candidates = {
					"/usr/bin/google-chrome-stable",
					"/opt/google/chrome/google-chrome",
					"google-chrome-stable",
					"google-chrome"
				};
				break;
			case BrowserFamily.CHROMIUM:
				candidates = {
					"/usr/bin/chromium-browser",
					"/usr/bin/chromium",
					"/snap/bin/chromium",
					"chromium-browser",
					"chromium"
				};
				break;
			case BrowserFamily.BRAVE:
				candidates = {
					"/usr/bin/brave-browser-stable",
					"/usr/bin/brave-browser",
					"/opt/brave.com/brave/brave-browser",
					"brave-browser-stable",
					"brave-browser",
					"brave"
				};
				break;
			case BrowserFamily.EDGE:
				candidates = {
					"/usr/bin/microsoft-edge-stable",
					"/usr/bin/microsoft-edge",
					"/opt/microsoft/msedge/msedge",
					"microsoft-edge-stable",
					"microsoft-edge"
				};
				break;
			case BrowserFamily.VIVALDI:
				candidates = {
					"/usr/bin/vivaldi-stable",
					"/opt/vivaldi/vivaldi",
					"vivaldi-stable",
					"vivaldi"
				};
				break;
			case BrowserFamily.OPERA:
				candidates = {
					"/usr/bin/opera",
					"opera"
				};
				break;
			case BrowserFamily.FIREFOX:
				candidates = {
					"/usr/bin/firefox",
					"/snap/bin/firefox",
					"firefox"
				};
				break;
			}

			foreach (unowned string cand in candidates) {
				if (cand.has_prefix ("/")) {
					if (FileUtils.test (cand, FileTest.IS_EXECUTABLE))
						return cand;
				} else {
					string? found = Environment.find_program_in_path (cand);
					if (found != null && found != "")
						return found;
				}
			}

			if (fallback_executable != "" && FileUtils.test (fallback_executable, FileTest.IS_EXECUTABLE))
				return fallback_executable;

			return fallback_executable;
		}

		public string[] get_browser_local_state_paths (BrowserFamily family)
		{
			var list = new Gee.ArrayList<string> ();
			string cfg = Environment.get_user_config_dir ();
			string home = Environment.get_home_dir ();

			switch (family) {
			case BrowserFamily.CHROME:
				if (cfg != "")
					list.add (Path.build_filename (cfg, "google-chrome", "Local State"));
				if (home != "")
					list.add (Path.build_filename (home, ".var", "app", "com.google.Chrome", "config", "google-chrome", "Local State"));
				break;

			case BrowserFamily.CHROMIUM:
				if (cfg != "")
					list.add (Path.build_filename (cfg, "chromium", "Local State"));
				if (home != "") {
					list.add (Path.build_filename (home, "snap", "chromium", "current", ".config", "chromium", "Local State"));
					list.add (Path.build_filename (home, ".var", "app", "org.chromium.Chromium", "config", "chromium", "Local State"));
				}
				break;

			case BrowserFamily.BRAVE:
				if (cfg != "")
					list.add (Path.build_filename (cfg, "BraveSoftware", "Brave-Browser", "Local State"));
				if (home != "") {
					list.add (Path.build_filename (home, ".var", "app", "com.brave.Browser", "config", "BraveSoftware", "Brave-Browser", "Local State"));
					list.add (Path.build_filename (home, "snap", "brave", "current", ".config", "BraveSoftware", "Brave-Browser", "Local State"));
				}
				break;

			case BrowserFamily.EDGE:
				if (cfg != "")
					list.add (Path.build_filename (cfg, "microsoft-edge", "Local State"));
				if (home != "")
					list.add (Path.build_filename (home, ".var", "app", "com.microsoft.Edge", "config", "microsoft-edge", "Local State"));
				break;

			case BrowserFamily.VIVALDI:
				if (cfg != "")
					list.add (Path.build_filename (cfg, "vivaldi", "Local State"));
				if (home != "")
					list.add (Path.build_filename (home, ".var", "app", "com.vivaldi.Vivaldi", "config", "vivaldi", "Local State"));
				break;

			case BrowserFamily.OPERA:
				if (cfg != "")
					list.add (Path.build_filename (cfg, "opera", "Local State"));
				if (home != "")
					list.add (Path.build_filename (home, ".var", "app", "com.opera.Opera", "config", "opera", "Local State"));
				break;

			case BrowserFamily.FIREFOX:
				if (home != "") {
					list.add (Path.build_filename (home, ".mozilla", "firefox", "profiles.ini"));
					list.add (Path.build_filename (home, "snap", "firefox", "common", ".mozilla", "firefox", "profiles.ini"));
					list.add (Path.build_filename (home, ".var", "app", "org.mozilla.firefox", ".mozilla", "firefox", "profiles.ini"));
				}
				break;
			}

			return list.to_array ();
		}

		void cancel_browser_session_monitors ()
		{
			foreach (var mon in browser_session_monitors)
				mon.cancel ();
			browser_session_monitors.clear ();
			watched_browser_session_dirs.clear ();
			browser_session_watch_active = false;
		}

		static void attach_browser_session_dir_monitor (XdgAppSystem target, string dir_path, int level)
		{
			if (dir_path == "" || target.watched_browser_session_dirs.contains (dir_path))
				return;
			if (!FileUtils.test (dir_path, FileTest.IS_DIR))
				return;
			try {
				var mon = File.new_for_path (dir_path).monitor_directory (FileMonitorFlags.NONE, null);
				target.watched_browser_session_dirs.add (dir_path);
				target.browser_session_monitors.add (mon);
				GLib.WeakRef weak_self = GLib.WeakRef (target);
				mon.changed.connect ((f, other, ev) => {
					var self = (XdgAppSystem?) weak_self.get ();
					if (self == null || !self.browser_session_watch_active)
						return;
					string? p = f.get_path ();
					if (p == null || p == "")
						return;
					string bname = Path.get_basename (p);
					string bdown = bname.down ();
					if (level == 0) {
						if (bname == "Local State") {
							self.browser_sessions_changed ();
						} else if (bdown == "default" || bdown.has_prefix ("profile ")) {
							attach_browser_session_dir_monitor (self, p, 1);
							attach_browser_session_dir_monitor (self, Path.build_filename (p, "Sessions"), 2);
							attach_browser_session_dir_monitor (self, Path.build_filename (p, "Sessions_Encrypted"), 2);
							self.browser_sessions_changed ();
						}
					} else if (level == 1) {
						if (bdown == "sessions" || bdown == "sessions_encrypted") {
							attach_browser_session_dir_monitor (self, p, 2);
							self.browser_sessions_changed ();
						}
					} else {
						if (bdown.has_prefix ("session_"))
							self.browser_sessions_changed ();
					}
				});
			} catch { }
		}

		public void set_browser_session_watch (BrowserFamily family, bool active)
		{
			if (!active) {
				if (browser_session_watch_active)
					cancel_browser_session_monitors ();
				return;
			}
			if (browser_session_watch_active)
				return;

			browser_session_watch_active = true;
			foreach (unowned string ls_path in get_browser_local_state_paths (family)) {
				string user_data_dir = Path.get_dirname (ls_path);
				if (!FileUtils.test (user_data_dir, FileTest.IS_DIR))
					continue;
				attach_browser_session_dir_monitor (this, user_data_dir, 0);
				try {
					var d = Dir.open (user_data_dir, 0);
					unowned string? entry = null;
					while ((entry = d.read_name ()) != null) {
						string edown = entry.down ();
						if (edown == "default" || edown.has_prefix ("profile ")) {
							string prof_dir = Path.build_filename (user_data_dir, entry);
							attach_browser_session_dir_monitor (this, prof_dir, 1);
							attach_browser_session_dir_monitor (this, Path.build_filename (prof_dir, "Sessions"), 2);
							attach_browser_session_dir_monitor (this, Path.build_filename (prof_dir, "Sessions_Encrypted"), 2);
						}
					}
				} catch { }
			}
		}

		public bool is_os_wrapper_binary (string exe_basename)
		{
			string b = Path.get_basename (exe_basename).down ();
			return (b == "env" || b == "sh" || b == "bash" || b == "dash" || b == "zsh"
				|| b == "ksh" || b == "fish" || b == "flatpak" || b == "flatpak-spawn" || b == "snap"
				|| b == "firejail" || b == "bwrap" || b == "xdg-open" || b == "gio"
				|| b == "kde-open" || b == "kde-open5" || b == "kioclient" || b == "kioclient5"
				|| b == "exo-open" || b == "gtk-launch"
				|| b == "steam-runtime-launch-client" || b == "pressure-vessel-wrap"
				|| b.has_prefix ("ld-linux"));
		}

		public string read_wrapper_script (string exe_or_path, out string resolved_path)
		{
			resolved_path = "";
			if (exe_or_path.contains ("/")) {
				if (FileUtils.test (exe_or_path, FileTest.IS_REGULAR))
					resolved_path = exe_or_path;
			} else {
				string? found = Environment.find_program_in_path (exe_or_path);
				if (found != null && FileUtils.test (found, FileTest.IS_REGULAR))
					resolved_path = found;
			}
			if (resolved_path == "")
				return "";

			Posix.Stat st;
			if (Posix.stat (resolved_path, out st) != 0 || st.st_size <= 2 || st.st_size > 16384) {
				resolved_path = "";
				return "";
			}

			try {
				uint8[] raw;
				if (!FileUtils.get_data (resolved_path, out raw) || raw.length < 3) {
					resolved_path = "";
					return "";
				}

				int check_len = int.min (raw.length, 512);
				for (int i = 0; i < check_len; i++) {
					if (raw[i] == 0) {
						resolved_path = "";
						return "";
					}
				}

				string content = (string) raw;
				if (!content.has_prefix ("#!") && !resolved_path.down ().has_suffix (".sh")) {
					resolved_path = "";
					return "";
				}

				return content;
			} catch {
				resolved_path = "";
				return "";
			}
		}

		public ProcessSnapshot inspect_process (int pid, bool include_children_and_fds = false)
		{
			return hal_kernel_inspect_process (pid, include_children_and_fds);
		}

		public bool is_process_alive (int pid)
		{
			return hal_kernel_is_process_alive (pid);
		}

		public Gee.ArrayList<ProcessSnapshot> scan_user_processes ()
		{
			return hal_kernel_scan_user_processes ();
		}

		public int find_pid_by_app_hint (string app_hint, string caption_hint = "")
		{
			return hal_kernel_find_pid_by_app_hint (app_hint, caption_hint);
		}

		static bool is_generic_recent_wrapper_bin (string bin)
		{
			return (bin == "env" || bin == "sh" || bin == "bash" || bin == "dash" || bin == "zsh"
				|| bin == "flatpak" || bin == "snap" || bin == "python" || bin == "python3"
				|| bin == "java" || bin == "javaw" || bin == "wine" || bin == "wine64");
		}

		static string? icon_token_from_gicon (Icon? icon)
		{
			Icon? cur = icon;
			while (cur is EmblemedIcon)
				cur = ((EmblemedIcon) cur).get_icon ();

			if (cur is ThemedIcon) {
				string joined = string.joinv (";;", ((ThemedIcon) cur).get_names ());
				return joined.replace ("(null);;", "");
			}

			if (cur is FileIcon) {
				var f = ((FileIcon) cur).get_file ();
				string? p = f.get_path ();
				if (p != null && p != "")
					return p;
				string u = f.get_uri ();
				if (u.down ().has_prefix ("resource://"))
					return u;
			}

			return null;
		}

		public Gee.ArrayList<RecentDocInfo> get_recent_documents (string launcher_uri, int max_items = 10)
		{
			var result = new Gee.ArrayList<RecentDocInfo> ();
			if (launcher_uri == null || launcher_uri == "" || launcher_uri.has_prefix ("docklet://") || max_items <= 0)
				return result;

			string? desktop_path = uri_or_path_to_local_path (launcher_uri);
			if (desktop_path == null || !desktop_path.has_suffix (".desktop"))
				return result;

			DesktopAppInfo? desktop_info = new DesktopAppInfo.from_filename (desktop_path);
			if (desktop_info == null)
				return result;

			if (!desktop_info.supports_files () && !desktop_info.supports_uris ()) {
				unowned string[]? sup_check = desktop_info.get_supported_types ();
				if (sup_check == null || sup_check.length == 0)
					return result;
			}

			string exec_bin = "";
			string? raw_exe = desktop_info.get_executable ();
			if (raw_exe != null && raw_exe != "") {
				exec_bin = Path.get_basename (raw_exe).down ();
				if (is_generic_recent_wrapper_bin (exec_bin))
					exec_bin = "";
			}

			string alt_app_token = "";
			if (exec_bin == "") {
				string? cmdline = desktop_info.get_commandline ();
				if (cmdline != null && cmdline != "") {
					try {
						string[] argv_tokens;
						if (Shell.parse_argv (cmdline, out argv_tokens) && argv_tokens.length > 0) {
							string first = Path.get_basename (argv_tokens[0]).down ();
							if (first == "env") {
								for (int i = 1; i < argv_tokens.length; i++) {
									string tok = argv_tokens[i];
									if (tok.has_prefix ("-") || tok.contains ("="))
										continue;
									string cand = Path.get_basename (tok).down ();
									if (!is_generic_recent_wrapper_bin (cand))
										exec_bin = cand;
									break;
								}
							} else if (first == "flatpak") {
								for (int i = 1; i < argv_tokens.length; i++) {
									string tok = argv_tokens[i];
									if (tok.has_prefix ("--command=")) {
										string cand = Path.get_basename (tok.substring ("--command=".length)).down ();
										if (!is_generic_recent_wrapper_bin (cand))
											exec_bin = cand;
									} else if (!tok.has_prefix ("-") && tok != "run" && tok.contains (".")) {
										int last_dot = tok.last_index_of_char ('.');
										if (last_dot >= 0 && last_dot + 1 < tok.length) {
											string tail = tok.substring (last_dot + 1).down ();
											if (tail.length >= 3 && !is_generic_recent_wrapper_bin (tail))
												alt_app_token = tail;
										}
									}
								}
							}
						}
					} catch { }
				}
			}

			string desktop_base = strip_launcher_extension (Path.get_basename (desktop_path)).down ();
			if (alt_app_token == "" && desktop_base.contains ("_")
				&& (desktop_path.contains ("/snapd/") || (raw_exe != null && Path.get_basename (raw_exe).down () == "snap"))) {
				int us = desktop_base.index_of_char ('_');
				if (us > 0 && us + 1 < desktop_base.length) {
					string snap_app = desktop_base.substring (us + 1);
					if (snap_app.length >= 3 && !is_generic_recent_wrapper_bin (snap_app))
						alt_app_token = snap_app;
				}
			}

			var supported_mimes = new Gee.ArrayList<string> ();
			unowned string[]? raw_types = desktop_info.get_supported_types ();
			if (raw_types != null) {
				foreach (unowned string mt in raw_types) {
					if (mt != null && mt != "")
						supported_mimes.add (mt);
				}
			}

			if (exec_bin == "" && desktop_base == "" && supported_mimes.size == 0)
				return result;

			unowned Gtk.RecentManager? manager = Gtk.RecentManager.get_default ();
			if (manager == null)
				return result;

			GLib.List<Gtk.RecentInfo> all_items = manager.get_items ();
			if (all_items == null)
				return result;

			var candidates = new Gee.ArrayList<RecentCandidate> ();
			var seen_uris = new Gee.HashSet<string> ();

			foreach (Gtk.RecentInfo info in all_items) {
				unowned string? u = info.get_uri ();
				if (u == null || !u.has_prefix ("file://") || seen_uris.contains (u))
					continue;

				bool app_matched = false;
				string[] apps = info.get_applications ();
				if (apps != null) {
					foreach (unowned string app_name in apps) {
						if (app_name == null || app_name == "")
							continue;
						string low = app_name.down ();
						if ((exec_bin != "" && (low == exec_bin || Path.get_basename (low) == exec_bin))
							|| (alt_app_token != "" && (low == alt_app_token || Path.get_basename (low) == alt_app_token))
							|| (desktop_base != "" && (low == desktop_base || low == desktop_base + ".desktop"))) {
							app_matched = true;
							break;
						}
					}
				}

				bool mime_matched = false;
				unowned string? item_mime = info.get_mime_type ();
				if (!app_matched && supported_mimes.size > 0 && item_mime != null && item_mime != "") {
					foreach (var sup in supported_mimes) {
						if (item_mime == sup || ContentType.is_a (item_mime, sup)) {
							mime_matched = true;
							break;
						}
					}
				}

				if (!app_matched && !mime_matched)
					continue;

				seen_uris.add (u);
				string label = info.get_display_name ();
				if (label == null || label == "")
					label = File.new_for_uri (u).get_basename () ?? u;

				candidates.add (new RecentCandidate (
					info,
					u,
					label,
					info.get_gicon (),
					item_mime ?? "",
					(int64) info.get_modified (),
					app_matched
				));
			}

			if (candidates.size == 0)
				return result;

			candidates.sort ((a, b) => {
				if (a.direct_app_match != b.direct_app_match)
					return a.direct_app_match ? -1 : 1;
				if (b.modified_ts > a.modified_ts)
					return 1;
				if (b.modified_ts < a.modified_ts)
					return -1;
				return 0;
			});

			foreach (var cand in candidates) {
				if (!cand.info.exists ())
					continue;
				var doc = new RecentDocInfo ();
				doc.uri = cand.uri;
				doc.display_name = cand.display_name;
				string? tip = File.new_for_uri (cand.uri).get_path ();
				doc.tooltip_path = (tip != null && tip != "") ? tip : cand.uri;
				doc.icon_token = icon_token_from_gicon (cand.gicon) ?? "text-x-generic";
				doc.mime_type = cand.mime_type;
				doc.modified_unix = cand.modified_ts;
				doc.direct_app_match = cand.direct_app_match;
				result.add (doc);
				if (result.size >= max_items)
					break;
			}

			return result;
		}

		public Gdk.Pixbuf? load_native_icon (string token, int size)
		{
			if (token == "" || size <= 0 || Gdk.Screen.get_default () == null)
				return null;

			unowned Gtk.IconTheme? theme = Gtk.IconTheme.get_default ();
			if (theme == null)
				return null;

			Gdk.Pixbuf? pbuf = null;
			icon_mutex.lock ();
			try {
				pbuf = theme.load_icon (token, size, Gtk.IconLookupFlags.GENERIC_FALLBACK);
			} catch { }
			if (pbuf == null && token.contains (".")) {
				var parts = token.split (".");
				try {
					pbuf = theme.load_icon (parts[0], size, Gtk.IconLookupFlags.GENERIC_FALLBACK);
				} catch { }
			}
			icon_mutex.unlock ();
			return pbuf;
		}

		public bool has_native_icon (string token)
		{
			if (token == "" || Gdk.Screen.get_default () == null)
				return false;

			unowned Gtk.IconTheme? theme = Gtk.IconTheme.get_default ();
			if (theme == null)
				return false;

			icon_mutex.lock ();
			bool exists = theme.has_icon (token);
			if (!exists && token.contains (".")) {
				var parts = token.split (".");
				exists = theme.has_icon (parts[0]);
			}
			icon_mutex.unlock ();
			return exists;
		}

		public Gee.ArrayList<string> list_native_icon_tokens ()
		{
			return new Gee.ArrayList<string> ();
		}

		public string? get_file_icon_token (GLib.File file)
		{
			try {
				var info = file.query_info (FileAttribute.STANDARD_ICON + ","
					+ FILE_ATTRIBUTE_CUSTOM_ICON_NAME + "," + FILE_ATTRIBUTE_CUSTOM_ICON + ","
					+ FileAttribute.THUMBNAIL_PATH, FileQueryInfoFlags.NONE);

				unowned string? custom_icon_name = info.get_attribute_string (FILE_ATTRIBUTE_CUSTOM_ICON_NAME);
				if (custom_icon_name != null && custom_icon_name != "") {
					if (has_native_icon (custom_icon_name))
						return custom_icon_name;
				}

				unowned string? custom_icon = info.get_attribute_string (FILE_ATTRIBUTE_CUSTOM_ICON);
				if (custom_icon != null && custom_icon != "") {
					string? path = null;
					if (custom_icon.has_prefix ("file://") || custom_icon.has_prefix ("/"))
						path = custom_icon;
					else
						path = file.get_child (custom_icon).get_path ();
					if (path != null) {
						string? lp = uri_or_path_to_local_path (path);
						if ((lp != null && FileUtils.test (lp, FileTest.EXISTS)) || has_native_icon (path))
							return path;
					}
				}

				unowned string? thumb_icon = info.get_attribute_byte_string (FileAttribute.THUMBNAIL_PATH);
				if (thumb_icon != null && thumb_icon != "")
					return thumb_icon;

				return icon_token_from_gicon (info.get_icon ());
			} catch {
				return null;
			}
		}

		public string[] get_extra_drop_target_atoms ()
		{
			return EXTRA_DROP_TARGET_ATOMS;
		}

		public Gee.ArrayList<string> decode_native_drop_selection (Gtk.SelectionData selection_data)
		{
			var result = new Gee.ArrayList<string> ();

			string[]? raw_uris = selection_data.get_uris ();
			if (raw_uris != null && raw_uris.length > 0) {
				foreach (unowned string s in raw_uris) {
					string resolved = resolve_launcher_uri (s);
					if (resolved != "" && !result.contains (resolved))
						result.add (resolved);
				}
			}

			if (result.size == 0) {
				string? raw_text = selection_data.get_text ();
				if (raw_text == null || raw_text.length == 0) {
					unowned uint8[]? raw_bytes = selection_data.get_data ();
					int raw_len = selection_data.get_length ();
					if (raw_bytes != null && raw_len > 0) {
						if (raw_len >= 2 && raw_bytes[1] == 0 && raw_bytes[0] != 0) {
							try {
								raw_text = GLib.convert ((string) raw_bytes, raw_len, "UTF-8", "UTF-16LE");
							} catch { }
						}
						if (raw_text == null || raw_text.length == 0)
							raw_text = (string?) raw_bytes;
					}
				}

				if (raw_text != null && raw_text.length > 0) {
					foreach (unowned string line in raw_text.split ("\n")) {
						string resolved = resolve_launcher_uri (line);
						if (resolved != "" && !result.contains (resolved))
							result.add (resolved);
					}
				}
			}

			return result;
		}

		public void cleanup ()
		{
			if (debounce_timer_id > 0U) {
				GLib.Source.remove (debounce_timer_id);
				debounce_timer_id = 0U;
			}
			cancel_browser_session_monitors ();
			cancel_directory_monitors ();
			launcher_cache.clear ();
			hal_kernel_clear_process_caches ();
		}
	}
}
