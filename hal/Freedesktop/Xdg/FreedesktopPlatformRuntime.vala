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
	 * Southbound Freedesktop/XDG runtime decorator implementing `IPlatformRuntime`.
	 * Owns XDG desktop-utility dispatch, XDG autostart, Wayland display validation,
	 * and `systemd-logind` / `ScreenSaver` resume/unlock D-Bus listeners while
	 * delegating kernel/POSIX primitives cleanly to `hal_kernel_get_runtime ()`.
	 */
	public class FreedesktopPlatformRuntime : GLib.Object, IPlatformRuntime
	{
		static FreedesktopPlatformRuntime? instance = null;

		public static FreedesktopPlatformRuntime get_default ()
		{
			if (instance == null)
				instance = new FreedesktopPlatformRuntime ();
			return instance;
		}

		IPlatformRuntime kernel_runtime;
		bool session_watchers_installed = false;
		uint login_sleep_sub_id = 0U;
		uint login_unlock_sub_id = 0U;
		Gee.ArrayList<uint>? screensaver_sub_ids = null;

		construct
		{
			kernel_runtime = hal_kernel_get_runtime ();
			kernel_runtime.termination_requested.connect ((sig) => {
				termination_requested (sig);
			});
			kernel_runtime.binary_upgrade_detected.connect ((exe) => {
				binary_upgrade_detected (exe);
			});
		}

		private static bool launch_desktop_commands (string[] kde_cmds, string[] gnome_cmds, string[] generic_cmds)
		{
			var ordered = new Gee.ArrayList<string> ();
			if (environment_is_session_desktop (XdgSessionDesktop.KDE)) {
				foreach (unowned string c in kde_cmds) ordered.add (c);
				foreach (unowned string c in generic_cmds) ordered.add (c);
				foreach (unowned string c in gnome_cmds) ordered.add (c);
			} else if (environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)) {
				foreach (unowned string c in gnome_cmds) ordered.add (c);
				foreach (unowned string c in generic_cmds) ordered.add (c);
				foreach (unowned string c in kde_cmds) ordered.add (c);
			} else {
				foreach (unowned string c in generic_cmds) ordered.add (c);
				foreach (unowned string c in gnome_cmds) ordered.add (c);
				foreach (unowned string c in kde_cmds) ordered.add (c);
			}

			foreach (var cmd in ordered) {
				var trimmed = cmd.strip ();
				if (trimmed == "")
					continue;
				var prog = trimmed.split (" ")[0];
				if (GLib.Environment.find_program_in_path (prog) != null) {
					try {
						GLib.Process.spawn_command_line_async (trimmed);
						return true;
					} catch (GLib.Error e) { }
				}
			}

			return false;
		}

		public bool open_system_utility (DesktopUtilityKind kind)
		{
			switch (kind) {
			case DesktopUtilityKind.DATE_TIME_SETTINGS:
				return launch_desktop_commands (
					{ "kcmshell6 kcm_clock", "kcmshell5 kcm_clock" },
					{ "gnome-control-center datetime" },
					{ "xfce4-datetime-settings" }
				);
			case DesktopUtilityKind.CALENDAR:
				return launch_desktop_commands (
					{ "merkuro-calendar", "kalendar", "korganizer" },
					{ "gnome-calendar" },
					{ "xfce4-calendar" }
				);
			case DesktopUtilityKind.POWER_SETTINGS:
				return launch_desktop_commands (
					{ "kcmshell6 powerdevilprofilesconfig", "kcmshell5 powerdevilprofilesconfig" },
					{ "gnome-control-center power" },
					{ "xfce4-power-manager-settings" }
				);
			case DesktopUtilityKind.SOUND_SETTINGS:
				return launch_desktop_commands (
					{ "kcmshell6 kcm_pulseaudio", "kcmshell5 kcm_pulseaudio" },
					{ "gnome-control-center sound" },
					{ "pavucontrol" }
				);
			case DesktopUtilityKind.NETWORK_SETTINGS:
				return launch_desktop_commands (
					{ "kcmshell6 kcm_networkmanagement", "kcmshell5 kcm_networkmanagement" },
					{ "gnome-control-center wifi", "gnome-control-center network" },
					{ "nm-connection-editor" }
				);
			case DesktopUtilityKind.DISPLAY_SETTINGS:
				return launch_desktop_commands (
					{ "systemsettings kcm_kscreen", "kcmshell6 kcm_kscreen", "kcmshell5 kcm_kscreen" },
					{ "gnome-control-center display" },
					{ "wdisplays", "arandr" }
				);
			case DesktopUtilityKind.NOTIFICATION_SETTINGS:
				return launch_desktop_commands (
					{ "kcmshell6 kcm_notifications", "kcmshell5 kcm_notifications", "systemsettings kcm_notifications" },
					{ "gnome-control-center notifications" },
					{ "swaync-client -t -sw", "xfce4-notifyd-config" }
				);
			case DesktopUtilityKind.SYSTEM_MONITOR:
				return launch_desktop_commands (
					{ "plasma-systemmonitor", "ksysguard" },
					{ "gnome-system-monitor" },
					{ "xfce4-taskmanager", "lxtask" }
				);
			default:
				return false;
			}
		}

		public bool open_uri (string uri, Gtk.Window? parent = null)
		{
			return kernel_runtime.open_uri (uri, parent);
		}

		public bool http_get_sync (string url, int timeout_sec, out string response_body)
		{
			return kernel_runtime.http_get_sync (url, timeout_sec, out response_body);
		}

		public bool extract_archive (string archive_path, string dest_dir)
		{
			return kernel_runtime.extract_archive (archive_path, dest_dir);
		}

		public bool validate_keyfile_isolated (string path)
		{
			return kernel_runtime.validate_keyfile_isolated (path);
		}

		public bool is_autostart_enabled ()
		{
			return XdgAutostart.is_enabled ();
		}

		public bool set_autostart_enabled (bool enabled)
		{
			return XdgAutostart.set_enabled (enabled);
		}

		public void terminate_legacy_competing_docks ()
		{
			kernel_runtime.terminate_legacy_competing_docks ();
		}

		public void replace_running_instances (string target_dock_name)
		{
			kernel_runtime.replace_running_instances (target_dock_name);
		}

		public void prepare_process_environment ()
		{
			kernel_runtime.prepare_process_environment ();
		}

		public void restore_process_environment ()
		{
			kernel_runtime.restore_process_environment ();
		}

		public bool verify_supported_display (Gdk.Display? display, out string error_message)
		{
			if (display != null && display.get_type ().name () == "GdkWaylandDisplay") {
				error_message = "";
				return true;
			}
			error_message = _("WayPlank is designed exclusively for Wayland sessions.");
			return false;
		}

		public string get_self_launcher_id ()
		{
			return kernel_runtime.get_self_launcher_id ();
		}

		public string get_system_data_dir ()
		{
			return kernel_runtime.get_system_data_dir ();
		}

		public string[] get_extra_schema_dirs ()
		{
			return kernel_runtime.get_extra_schema_dirs ();
		}

		public string canonicalize_path (string path)
		{
			return kernel_runtime.canonicalize_path (path);
		}

		public bool paths_equal (string path_a, string path_b)
		{
			return kernel_runtime.paths_equal (path_a, path_b);
		}

		public string expand_path_variables (string raw, Gee.HashMap<string, string>? extra_vars = null)
		{
			return kernel_runtime.expand_path_variables (raw, extra_vars);
		}

		public int get_current_pid ()
		{
			return kernel_runtime.get_current_pid ();
		}

		public void set_process_title (string title)
		{
			kernel_runtime.set_process_title (title);
		}

		public string os_release_summary ()
		{
			return kernel_runtime.os_release_summary ();
		}

		public void install_lifecycle_signals ()
		{
			kernel_runtime.install_lifecycle_signals ();
		}

		public void install_session_and_upgrade_watchers ()
		{
			if (!session_watchers_installed) {
				session_watchers_installed = true;

				// 1. systemd-logind sleep/resume + session unlock signals (system bus)
				var system_bus = DbusBroker.get_default ().get_system_bus ();
				if (system_bus != null) {
					login_sleep_sub_id = system_bus.signal_subscribe (
						"org.freedesktop.login1",
						"org.freedesktop.login1.Manager",
						"PrepareForSleep",
						"/org/freedesktop/login1",
						null,
						DBusSignalFlags.NONE,
						(conn, sender, path, iface, signal_name, parameters) => {
							bool is_sleeping = false;
							parameters.get ("(b)", out is_sleeping);
							if (!is_sleeping) {
								message ("System resumed from suspend/hibernate! Scheduling dock refresh...");
								system_resumed (800);
							}
						}
					);
					debug ("Subscribed to systemd-logind PrepareForSleep signal");

					login_unlock_sub_id = system_bus.signal_subscribe (
						"org.freedesktop.login1",
						"org.freedesktop.login1.Session",
						"Unlock",
						null,
						null,
						DBusSignalFlags.NONE,
						(conn, sender, path, iface, signal_name, parameters) => {
							message ("systemd-logind Session Unlock detected! Scheduling dock refresh...");
							system_resumed (500);
						}
					);
					debug ("Subscribed to systemd-logind Session.Unlock signal");
				} else {
					debug ("Unable to subscribe to systemd-logind signals: system bus unavailable");
				}

				// 2. ScreenSaver / Screen Lock unlock events (session bus: freedesktop + GNOME)
				var session_bus = DbusBroker.get_default ().get_session_bus ();
				if (session_bus != null) {
					screensaver_sub_ids = new Gee.ArrayList<uint> ();
					string[] screensaver_ifaces = {
						"org.freedesktop.ScreenSaver",
						"org.gnome.ScreenSaver"
					};
					foreach (unowned string ss_iface in screensaver_ifaces) {
						uint sub_id = session_bus.signal_subscribe (
							null,
							ss_iface,
							"ActiveChanged",
							null,
							null,
							DBusSignalFlags.NONE,
							(conn, sender, path, iface, signal_name, parameters) => {
								bool is_active = false;
								parameters.get ("(b)", out is_active);
								if (!is_active) {
									message ("Screen unlocked (%s)! Scheduling dock refresh...", iface);
									system_resumed (500);
								}
							}
						);
						screensaver_sub_ids.add (sub_id);
					}
					debug ("Subscribed to ScreenSaver ActiveChanged signals");
				} else {
					debug ("Unable to subscribe to ScreenSaver ActiveChanged: session bus unavailable");
				}
			}

			kernel_runtime.install_session_and_upgrade_watchers ();
		}

		public void reexec_self_on_upgrade (string executable_path, string? dock_name)
		{
			kernel_runtime.reexec_self_on_upgrade (executable_path, dock_name);
		}

		public void exit_immediately (int status_code)
		{
			kernel_runtime.exit_immediately (status_code);
		}

		public string[] parse_command_argv (string cmdline)
		{
			return kernel_runtime.parse_command_argv (cmdline);
		}

		public string quote_command_arg (string arg)
		{
			return kernel_runtime.quote_command_arg (arg);
		}

		public void invalidate_process_cache (int pid)
		{
			kernel_runtime.invalidate_process_cache (pid);
		}

		public void cleanup ()
		{
			var system_bus = DbusBroker.get_default ().get_system_bus ();
			if (system_bus != null) {
				if (login_sleep_sub_id > 0U) {
					system_bus.signal_unsubscribe (login_sleep_sub_id);
					login_sleep_sub_id = 0U;
				}
				if (login_unlock_sub_id > 0U) {
					system_bus.signal_unsubscribe (login_unlock_sub_id);
					login_unlock_sub_id = 0U;
				}
			}

			if (screensaver_sub_ids != null && screensaver_sub_ids.size > 0) {
				var session_bus = DbusBroker.get_default ().get_session_bus ();
				if (session_bus != null) {
					foreach (uint id in screensaver_sub_ids) {
						if (id > 0U)
							session_bus.signal_unsubscribe (id);
					}
				}
				screensaver_sub_ids.clear ();
			}

			kernel_runtime.cleanup ();
		}
	}
}
