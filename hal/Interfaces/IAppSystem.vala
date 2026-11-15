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
	 * OS-blind default user application roles (`Hal.Apps.get_default_app_for_role`).
	 */
	public enum DefaultAppRole
	{
		FILE_MANAGER,
		WEB_BROWSER,
		TERMINAL,
		TEXT_EDITOR
	}

	/**
	 * OS-blind web browser families for profile & state lookup.
	 */
	public enum BrowserFamily
	{
		CHROME,
		CHROMIUM,
		BRAVE,
		EDGE,
		VIVALDI,
		OPERA,
		FIREFOX
	}

	/**
	 * OS-blind static jump-list / quicklist action unpacked south of `hal/Interfaces/`.
	 */
	public class QuicklistAction : GLib.Object
	{
		public string id = "";
		public string name = "";
		public string icon_token = "";
		public string exec = "";
		public bool is_native_action = false;
	}

	/**
	 * OS-blind application launcher metadata descriptor (`Hal.Apps.load_launcher`).
	 */
	public class AppDescriptor : GLib.Object
	{
		public string uri = "";
		public string base_id = "";
		public Gee.ArrayList<string> alias_ids = new Gee.ArrayList<string> ();
		public string display_name = "";
		public string unlocalized_name = "";
		public string generic_name = "";
		public string comment = "";
		public string icon_token = "";
		public string exec_command = "";
		public string working_dir = "";
		public string url_target = "";
		public string startup_wm_class_or_aumid = "";
		public Gee.ArrayList<string> wm_classes_or_aumids = new Gee.ArrayList<string> ();
		public Gee.ArrayList<string> sandbox_ids = new Gee.ArrayList<string> ();
		public Gee.ArrayList<string> categories = new Gee.ArrayList<string> ();
		public Gee.ArrayList<string> mime_types = new Gee.ArrayList<string> ();
		public Gee.ArrayList<string> keywords = new Gee.ArrayList<string> ();
		public Gee.ArrayList<QuicklistAction> quicklist_actions = new Gee.ArrayList<QuicklistAction> ();
		public string browser_profile = "";
		public bool is_launchable = false;
		public bool try_exec_satisfied = true;
		public bool supports_files = false;
		public bool supports_uris = false;
		public bool is_nodisplay = false;
		public bool is_hidden = false;
		public bool is_non_app_launcher = false;
		public bool is_shown_in_current_desktop = true;
		public bool is_terminal = false;
		public bool is_terminal_emulator = false;
		public bool is_synthetic = false;
		public bool has_custom_icon_override = false;
	}

	/**
	 * OS-blind live process snapshot (`Hal.Apps.inspect_process`).
	 */
	public class ProcessSnapshot : GLib.Object
	{
		public int pid = 0;
		public bool is_alive = false;
		public bool uid_matches_self = false;
		public string executable_comm = "";
		public string exe_realpath = "";
		public string full_cmdline = "";
		public string[] cmdline_argv = {};
		public string working_dir = "";
		public string env_appimage = "";
		public string env_wineprefix = "";
		public int[] child_pids = {};
		public string[] child_cmdlines = {};
		public string[] open_fd_targets = {};
	}

	/**
	 * OS-blind recent document jump-list entry (`Hal.Apps.get_recent_documents`).
	 */
	public class RecentDocInfo : GLib.Object
	{
		public string uri = "";
		public string display_name = "";
		public string tooltip_path = "";
		public string icon_token = "";
		public string mime_type = "";
		public int64 modified_unix = 0;
		public bool direct_app_match = false;
	}

	/**
	 * Northbound OS-blind application catalog, launcher, process & recent-document contract (`Hal.Apps`).
	 */
	public interface IAppSystem : GLib.Object
	{
		public signal void apps_changed ();

		public abstract Gee.ArrayList<GLib.File> get_extra_data_dirs ();
		public abstract Gee.ArrayList<GLib.File> discover_launcher_dirs ();
		public abstract Gee.ArrayList<AppDescriptor> discover_installed_apps (bool include_nodisplay = true);
		public abstract void set_extra_watched_directories (string[] folder_uris);
		public abstract void invalidate_cache ();

		public abstract AppDescriptor? load_launcher (string uri_or_path);
		public abstract string resolve_launcher_uri (string raw_id_or_uri);
		public abstract bool is_launcher_uri (string uri_or_path);
		public abstract bool is_self_launcher (string id_or_uri);
		public abstract bool launcher_uris_match (string uri_a, string uri_b);
		public abstract string strip_launcher_extension (string raw_id);
		public abstract string launcher_id_stem (string uri_or_id);
		public abstract bool launcher_exists (string uri_or_path);
		public abstract GLib.FileMonitor? monitor_launcher (GLib.File launcher_file);
		public abstract string? extract_link_shortcut_url (string uri_or_path);
		public abstract bool can_launcher_accept_uri (string launcher_uri, string candidate_uri);

		public abstract bool launch_app (string launcher_uri, string[] uris, GLib.AppLaunchContext? context = null);
		public abstract bool launch_action (string launcher_uri, string action_id, string fallback_exec = "", GLib.AppLaunchContext? context = null);
		public abstract bool launch_command (string cmdline, string working_dir = "", GLib.AppLaunchContext? context = null);

		public abstract string get_default_app_for_role (DefaultAppRole role);
		public abstract Gee.ArrayList<string> discover_default_seed_apps ();
		public abstract int populate_category_folder (GLib.File folder, string icon_name, string[] priority_ids, string[] category_tags, int max_items = 6);
		public abstract GLib.File? copy_launcher_to_directory (GLib.File src_launcher, GLib.File dest_dir);

		public abstract GLib.File? synthesize_fallback_launcher (string safe_stem, string app_name, string exec_cmd, string icon_token, string wm_class_or_aumid = "", bool preserve_existing_fields = false);
		public abstract bool is_synthetic_launcher (string uri_or_id);
		public abstract bool delete_synthetic_launcher (string launcher_uri);

		public abstract string apply_custom_launcher_icon (string launcher_uri, string new_icon_token);
		public abstract string reset_custom_launcher_icon (string launcher_uri, out string restored_icon_token);

		public abstract string find_installed_browser_binary (BrowserFamily family, string fallback_executable = "");
		public abstract string[] get_browser_local_state_paths (BrowserFamily family);
		public abstract bool is_os_wrapper_binary (string exe_basename);
		public abstract string read_wrapper_script (string exe_or_path);

		public abstract ProcessSnapshot inspect_process (int pid, bool include_children_and_fds = false);
		public abstract bool is_process_alive (int pid);
		public abstract Gee.ArrayList<ProcessSnapshot> scan_user_processes ();
		public abstract int find_pid_by_app_hint (string app_hint, string caption_hint = "");

		public abstract Gee.ArrayList<RecentDocInfo> get_recent_documents (string launcher_uri, int max_items = 10);

		public abstract Gdk.Pixbuf? load_native_icon (string token, int size);
		public abstract bool has_native_icon (string token);
		public abstract string? get_file_icon_token (GLib.File file);

		public abstract string[] get_extra_drop_target_atoms ();
		public abstract Gee.ArrayList<string> decode_native_drop_selection (Gtk.SelectionData selection_data);

		public abstract void cleanup ();
	}

	internal class NullAppSystem : GLib.Object, IAppSystem
	{
		public Gee.ArrayList<GLib.File> get_extra_data_dirs () { return new Gee.ArrayList<GLib.File> (); }
		public Gee.ArrayList<GLib.File> discover_launcher_dirs () { return new Gee.ArrayList<GLib.File> (); }
		public Gee.ArrayList<AppDescriptor> discover_installed_apps (bool include_nodisplay = true) { return new Gee.ArrayList<AppDescriptor> (); }
		public void set_extra_watched_directories (string[] folder_uris) {}
		public void invalidate_cache () {}

		public AppDescriptor? load_launcher (string uri_or_path) { return null; }
		public string resolve_launcher_uri (string raw_id_or_uri) { return raw_id_or_uri; }
		public bool is_launcher_uri (string uri_or_path) { return false; }
		public bool is_self_launcher (string id_or_uri) { return false; }
		public bool launcher_uris_match (string uri_a, string uri_b) { return uri_a == uri_b; }
		public string strip_launcher_extension (string raw_id) { return raw_id; }
		public string launcher_id_stem (string uri_or_id) { return uri_or_id; }
		public bool launcher_exists (string uri_or_path) { return false; }
		public GLib.FileMonitor? monitor_launcher (GLib.File launcher_file) { return null; }
		public string? extract_link_shortcut_url (string uri_or_path) { return null; }
		public bool can_launcher_accept_uri (string launcher_uri, string candidate_uri) { return false; }

		public bool launch_app (string launcher_uri, string[] uris, GLib.AppLaunchContext? context = null) { return false; }
		public bool launch_action (string launcher_uri, string action_id, string fallback_exec = "", GLib.AppLaunchContext? context = null) { return false; }
		public bool launch_command (string cmdline, string working_dir = "", GLib.AppLaunchContext? context = null) { return false; }

		public string get_default_app_for_role (DefaultAppRole role) { return ""; }
		public Gee.ArrayList<string> discover_default_seed_apps () { return new Gee.ArrayList<string> (); }
		public int populate_category_folder (GLib.File folder, string icon_name, string[] priority_ids, string[] category_tags, int max_items = 6) { return 0; }
		public GLib.File? copy_launcher_to_directory (GLib.File src_launcher, GLib.File dest_dir) { return null; }

		public GLib.File? synthesize_fallback_launcher (string safe_stem, string app_name, string exec_cmd, string icon_token, string wm_class_or_aumid = "", bool preserve_existing_fields = false) { return null; }
		public bool is_synthetic_launcher (string uri_or_id) { return false; }
		public bool delete_synthetic_launcher (string launcher_uri) { return false; }

		public string apply_custom_launcher_icon (string launcher_uri, string new_icon_token) { return ""; }
		public string reset_custom_launcher_icon (string launcher_uri, out string restored_icon_token)
		{
			restored_icon_token = "";
			return "";
		}

		public string find_installed_browser_binary (BrowserFamily family, string fallback_executable = "") { return fallback_executable; }
		public string[] get_browser_local_state_paths (BrowserFamily family) { return {}; }
		public bool is_os_wrapper_binary (string exe_basename) { return false; }
		public string read_wrapper_script (string exe_or_path) { return ""; }

		public ProcessSnapshot inspect_process (int pid, bool include_children_and_fds = false) { return new ProcessSnapshot (); }
		public bool is_process_alive (int pid) { return false; }
		public Gee.ArrayList<ProcessSnapshot> scan_user_processes () { return new Gee.ArrayList<ProcessSnapshot> (); }
		public int find_pid_by_app_hint (string app_hint, string caption_hint = "") { return 0; }

		public Gee.ArrayList<RecentDocInfo> get_recent_documents (string launcher_uri, int max_items = 10) { return new Gee.ArrayList<RecentDocInfo> (); }

		public Gdk.Pixbuf? load_native_icon (string token, int size) { return null; }
		public bool has_native_icon (string token) { return false; }
		public string? get_file_icon_token (GLib.File file) { return null; }

		public string[] get_extra_drop_target_atoms () { return {}; }
		public Gee.ArrayList<string> decode_native_drop_selection (Gtk.SelectionData selection_data) { return new Gee.ArrayList<string> (); }

		public void cleanup () {}
	}
}
