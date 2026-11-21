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
	 * OS-blind desktop control-panel & utility targets (`Hal.Runtime.open_system_utility`).
	 */
	public enum DesktopUtilityKind
	{
		DATE_TIME_SETTINGS,
		CALENDAR,
		POWER_SETTINGS,
		SOUND_SETTINGS,
		NETWORK_SETTINGS,
		DISPLAY_SETTINGS,
		NOTIFICATION_SETTINGS,
		SYSTEM_MONITOR
	}

	/**
	 * Northbound OS lifecycle, process isolation, autostart, HTTP & archive translator (`Hal.Runtime`).
	 */
	public interface IPlatformRuntime : GLib.Object
	{
		public signal void termination_requested (int signal_number);
		public signal void binary_upgrade_detected (string executable_path);
		public signal void system_resumed (uint recommended_delay_ms);
		public signal void remote_action_requested (string dock_name, string action);

		public abstract bool open_system_utility (DesktopUtilityKind kind);
		public abstract bool open_uri (string uri, Gtk.Window? parent = null);
		public abstract bool http_get_sync (string url, int timeout_sec, out string response_body);
		public abstract bool extract_archive (string archive_path, string dest_dir);
		public abstract bool validate_keyfile_isolated (string path);
		public abstract bool is_autostart_enabled ();
		public abstract bool set_autostart_enabled (bool enabled);
		public abstract void terminate_legacy_competing_docks ();
		public abstract void replace_running_instances (string target_dock_name);
		public abstract void prepare_process_environment ();
		public abstract void restore_process_environment ();
		public abstract bool verify_supported_display (Gdk.Display? display, out string error_message);
		public abstract string get_self_launcher_id ();
		public abstract string get_system_data_dir ();
		public abstract string[] get_extra_schema_dirs ();
		public abstract string canonicalize_path (string path);
		public abstract bool paths_equal (string path_a, string path_b);
		public abstract string expand_path_variables (string raw, Gee.HashMap<string, string>? extra_vars = null);
		public virtual bool uses_native_single_instance_ipc () { return false; }
		public virtual bool try_forward_cli_to_running_instance (string dock_name, string action) { return false; }
		public virtual string sanitize_dock_name (string? raw_name)
		{
			if (raw_name == null)
				return "dock1";
			string s = raw_name.strip ();
			if (s.length == 0 || s.length > 64)
				return "dock1";
			char first = s[0];
			if (!((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z') || first == '_'))
				return "dock1";
			for (int i = 1; i < s.length; i++) {
				char c = s[i];
				if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-'))
					return "dock1";
			}
			string upper = s.up ();
			if (upper == "CON" || upper == "PRN" || upper == "AUX" || upper == "NUL")
				return "dock1";
			if (upper.length == 4 && (upper.has_prefix ("COM") || upper.has_prefix ("LPT"))
				&& upper[3] >= '1' && upper[3] <= '9')
				return "dock1";
			return s;
		}
		public abstract int get_current_pid ();
		public abstract void set_process_title (string title);
		public abstract string os_release_summary ();
		public abstract void install_lifecycle_signals ();
		public abstract void install_session_and_upgrade_watchers ();
		public abstract void reexec_self_on_upgrade (string executable_path, string? dock_name);
		public abstract void exit_immediately (int status_code);
		public abstract string[] parse_command_argv (string cmdline);
		public virtual string quote_command_arg (string arg)
		{
			if (arg == "")
				return "\"\"";
			if (!arg.contains (" ") && !arg.contains ("\t") && !arg.contains ("\""))
				return arg;
			return "\"" + arg.replace ("\"", "\\\"") + "\"";
		}
		public virtual void invalidate_process_cache (int pid) {}
		public abstract void cleanup ();
	}

	internal class NullPlatformRuntime : GLib.Object, IPlatformRuntime
	{
		public bool open_system_utility (DesktopUtilityKind kind) { return false; }
		public bool open_uri (string uri, Gtk.Window? parent = null) { return false; }
		public bool http_get_sync (string url, int timeout_sec, out string response_body)
		{
			response_body = "";
			return false;
		}
		public bool extract_archive (string archive_path, string dest_dir) { return false; }
		public bool validate_keyfile_isolated (string path) { return true; }
		public bool is_autostart_enabled () { return false; }
		public bool set_autostart_enabled (bool enabled) { return false; }
		public void terminate_legacy_competing_docks () {}
		public void replace_running_instances (string target_dock_name) {}
		public void prepare_process_environment () {}
		public void restore_process_environment () {}
		public bool verify_supported_display (Gdk.Display? display, out string error_message)
		{
			error_message = "";
			return display != null;
		}
		public string get_self_launcher_id () { return ""; }
		public string get_system_data_dir () { return Build.DATADIR; }
		public string[] get_extra_schema_dirs () { return {}; }
		public string canonicalize_path (string path) { return path; }
		public bool paths_equal (string path_a, string path_b) { return path_a == path_b; }
		public string expand_path_variables (string raw, Gee.HashMap<string, string>? extra_vars = null) { return raw; }
		public int get_current_pid () { return 0; }
		public void set_process_title (string title) {}
		public string os_release_summary () { return "unknown"; }
		public void install_lifecycle_signals () {}
		public void install_session_and_upgrade_watchers () {}
		public void reexec_self_on_upgrade (string executable_path, string? dock_name) {}
		public void exit_immediately (int status_code) {}
		public string[] parse_command_argv (string cmdline) { return {}; }
		public void cleanup () {}
	}
}
