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
		public abstract bool verify_supported_display (Gdk.Display? display);
		public abstract int get_current_pid ();
		public abstract void set_process_title (string title);
		public abstract string os_release_summary ();
		public abstract void install_lifecycle_signals ();
		public abstract void install_session_and_upgrade_watchers ();
		public abstract void reexec_self_on_upgrade (string executable_path, string? dock_name);
		public abstract void exit_immediately (int status_code);
		public abstract string[] parse_command_argv (string cmdline);
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
		public bool verify_supported_display (Gdk.Display? display) { return display != null; }
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
