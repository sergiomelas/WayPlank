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
	 * Southbound Linux/POSIX runtime driver implementing `IPlatformRuntime`.
	 * Owns POSIX signals, process titles, `/proc` instance replacement, `fork()`
	 * KeyFile isolation, `systemd-logind` / `ScreenSaver` resume listeners,
	 * `SIGWINCH` `/proc/self/exe` binary-upgrade detection, `curl`, `tar`/`unzip`,
	 * and XDG desktop utility dispatch.
	 */
	public class LinuxPlatformRuntime : GLib.Object, IPlatformRuntime
	{
		static LinuxPlatformRuntime? instance = null;

		public static LinuxPlatformRuntime get_default ()
		{
			if (instance == null)
				instance = new LinuxPlatformRuntime ();
			return instance;
		}

		string? saved_gtk_use_portal = null;
		bool lifecycle_installed = false;
		bool session_watchers_installed = false;
		uint sigint_source_id = 0U;
		uint sigterm_source_id = 0U;
		uint sighup_source_id = 0U;
		uint upgrade_signal_source_id = 0U;
		string startup_exe_path = "";
		bool upgrade_dispatched = false;

		uint login_sleep_sub_id = 0U;
		uint login_unlock_sub_id = 0U;
		Gee.ArrayList<uint>? screensaver_sub_ids = null;

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
			try {
				if (Gtk.show_uri_on_window (parent, uri, Gdk.CURRENT_TIME))
					return true;
			} catch (GLib.Error e) { }

			try {
				if (AppInfo.launch_default_for_uri (uri, null))
					return true;
			} catch (GLib.Error e) { }

			try {
				Process.spawn_command_line_async ("xdg-open " + Shell.quote (uri));
				return true;
			} catch (GLib.Error e) {
				warning ("Failed to open URI '%s': %s", uri, e.message);
			}
			return false;
		}

		public bool http_get_sync (string url, int timeout_sec, out string response_body)
		{
			response_body = "";
			int effective_timeout = timeout_sec > 0 ? timeout_sec : 5;
			string cmd = "curl -s --max-time %d %s".printf (effective_timeout, Shell.quote (url));
			string stdout_str = "";
			int exit_status = -1;
			try {
				if (Process.spawn_command_line_sync (cmd, out stdout_str, null, out exit_status) && exit_status == 0) {
					response_body = stdout_str ?? "";
					return true;
				}
			} catch (GLib.Error e) {
				warning ("HTTP GET failed for '%s': %s", url, e.message);
			}
			return false;
		}

		public bool extract_archive (string archive_path, string dest_dir)
		{
			string lower = archive_path.down ();
			int exit_status = -1;
			string q_archive = Shell.quote (archive_path);
			string q_tmp = Shell.quote (dest_dir);

			try {
				if (lower.has_suffix (".zip")) {
					Process.spawn_command_line_sync ("unzip -q -o %s -d %s".printf (q_archive, q_tmp), null, null, out exit_status);
					return exit_status == 0;
				} else if (lower.has_suffix (".tar.gz") || lower.has_suffix (".tgz")) {
					Process.spawn_command_line_sync ("tar -xzf %s -C %s".printf (q_archive, q_tmp), null, null, out exit_status);
					return exit_status == 0;
				} else if (lower.has_suffix (".tar.xz") || lower.has_suffix (".txz")) {
					Process.spawn_command_line_sync ("tar -xJf %s -C %s".printf (q_archive, q_tmp), null, null, out exit_status);
					return exit_status == 0;
				} else if (lower.has_suffix (".tar.bz2")) {
					Process.spawn_command_line_sync ("tar -xjf %s -C %s".printf (q_archive, q_tmp), null, null, out exit_status);
					return exit_status == 0;
				}
			} catch (GLib.Error e) {
				warning ("Archive extraction failed for '%s': %s", archive_path, e.message);
			}
			return false;
		}

		public bool validate_keyfile_isolated (string path)
		{
			Posix.pid_t pid = Posix.fork ();
			if (pid < 0)
				return true;
			if (pid == 0) {
				try {
					var kf = new KeyFile ();
					kf.load_from_file (path, KeyFileFlags.NONE);
					if (!kf.has_group ("LatchState") && !kf.has_group ("DockPreferences"))
						Posix._exit (1);
					foreach (unowned string grp in kf.get_groups ())
						foreach (unowned string k in kf.get_keys (grp))
							kf.get_value (grp, k);
					Posix._exit (0);
				} catch (Error e) {
					Posix._exit (1);
				}
				Posix._exit (1);
			}
			int status = 0;
			Posix.pid_t waited = -1;
			do {
				waited = Posix.waitpid (pid, out status, 0);
			} while (waited == -1 && Posix.errno == Posix.EINTR);
			return (waited == pid && Process.if_exited (status) && Process.exit_status (status) == 0);
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
			try {
				if (Path.get_basename (Environment.get_prgname () ?? "wayplank") != "plank")
					Process.spawn_command_line_sync ("killall -q plank");
			} catch (GLib.Error e) { }
		}

		private static string extract_dock_name_from_args (string[] args)
		{
			for (int i = 1; i < args.length; i++) {
				unowned string a = args[i];
				if (a == "--")
					break;
				if ((a == "-n" || a == "--name") && i + 1 < args.length)
					return args[i + 1];
				if (a.has_prefix ("--name="))
					return a.substring ("--name=".length);
				if (a.has_prefix ("-n") && a.length > 2 && !a.has_prefix ("--"))
					return a.substring (2);
			}
			return "";
		}

		private static bool pid_matches_replace_target (int pid, Posix.uid_t self_uid, string target_dock_name)
		{
			Posix.Stat st;
			if (Posix.stat ("/proc/%d".printf (pid), out st) != 0 || st.st_uid != self_uid)
				return false;
			try {
				uint8[] raw;
				if (!FileUtils.get_data ("/proc/%d/cmdline".printf (pid), out raw) || raw.length == 0)
					return false;
				var tokens = new Gee.ArrayList<string> ();
				int start = 0;
				for (int i = 0; i < raw.length; i++) {
					if (raw[i] == 0) {
						if (i > start) {
							unowned string s = (string) (&raw[start]);
							tokens.add (s);
						} else {
							tokens.add ("");
						}
						start = i + 1;
					}
				}
				if (start < raw.length) {
					var tail = new uint8[raw.length - start + 1];
					Memory.copy (tail, &raw[start], raw.length - start);
					tail[raw.length - start] = 0;
					tokens.add ((string) tail);
				}
				if (tokens.size == 0)
					return false;
				var exe_base = Path.get_basename (tokens[0]);
				if (exe_base != "wayplank" && exe_base != "plank")
					return false;
				return extract_dock_name_from_args (tokens.to_array ()) == target_dock_name;
			} catch (Error e) {
				return false;
			}
		}

		public void replace_running_instances (string target_dock_name)
		{
			int self_pid = (int) Posix.getpid ();
			Posix.uid_t self_uid = Posix.getuid ();
			bool sent_term = false;
			try {
				string out_pids = "";
				Process.spawn_command_line_sync ("pidof wayplank plank", out out_pids);
				foreach (unowned string tok in out_pids.strip ().split (" ")) {
					int p = int.parse (tok);
					if (p > 0 && p != self_pid && pid_matches_replace_target (p, self_uid, target_dock_name)) {
						Posix.kill ((Posix.pid_t) p, Posix.Signal.TERM);
						sent_term = true;
					}
				}
			} catch (Error e) { }
			if (sent_term) {
				Thread.usleep (200000);
				try {
					string out_pids = "";
					Process.spawn_command_line_sync ("pidof wayplank plank", out out_pids);
					foreach (unowned string tok in out_pids.strip ().split (" ")) {
						int p = int.parse (tok);
						if (p > 0 && p != self_pid && pid_matches_replace_target (p, self_uid, target_dock_name))
							Posix.kill ((Posix.pid_t) p, Posix.Signal.KILL);
					}
				} catch (Error e) { }
				Thread.usleep (50000);
			}
		}

		public void prepare_process_environment ()
		{
			saved_gtk_use_portal = Environment.get_variable ("GTK_USE_PORTAL");
			Environment.set_variable ("GTK_USE_PORTAL", "0", true);
		}

		public void restore_process_environment ()
		{
			if (saved_gtk_use_portal != null)
				Environment.set_variable ("GTK_USE_PORTAL", saved_gtk_use_portal, true);
			else
				Environment.unset_variable ("GTK_USE_PORTAL");
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
			return "wayplank.desktop";
		}

		public string get_system_data_dir ()
		{
			return Build.DATADIR;
		}

		public int get_current_pid ()
		{
			return getpid ();
		}

		public void set_process_title (string title)
		{
#if HAVE_SYS_PRCTL_H
			prctl (15, title);
#else
			setproctitle (title);
#endif
		}

		public string os_release_summary ()
		{
			return Posix.utsname ().release;
		}

		public void install_lifecycle_signals ()
		{
			if (lifecycle_installed)
				return;
			lifecycle_installed = true;

			sigint_source_id = GLib.Unix.signal_add ((int) Posix.Signal.INT, () => {
				sigint_source_id = 0U;
				termination_requested ((int) Posix.Signal.INT);
				return false;
			});
			sigterm_source_id = GLib.Unix.signal_add ((int) Posix.Signal.TERM, () => {
				sigterm_source_id = 0U;
				termination_requested ((int) Posix.Signal.TERM);
				return false;
			});
			sighup_source_id = GLib.Unix.signal_add ((int) Posix.Signal.HUP, () => {
				sighup_source_id = 0U;
				termination_requested ((int) Posix.Signal.HUP);
				return false;
			});
		}

		public void install_session_and_upgrade_watchers ()
		{
			if (session_watchers_installed)
				return;
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

			// 3. Binary package upgrade hot-reload watcher (SIGWINCH + /proc/self/exe)
			try {
				var resolved = FileUtils.read_link ("/proc/self/exe");
				if (resolved.has_suffix (" (deleted)"))
					resolved = resolved.substring (0, resolved.length - " (deleted)".length);
				startup_exe_path = resolved;
			} catch (Error e) {
				startup_exe_path = "";
			}

			upgrade_signal_source_id = GLib.Unix.signal_add ((int) Posix.Signal.WINCH, () => {
				if (upgrade_dispatched || startup_exe_path == "")
					return true;
				try {
					var current_link = FileUtils.read_link ("/proc/self/exe");
					if (current_link.has_suffix (" (deleted)") && FileUtils.test (startup_exe_path, FileTest.IS_EXECUTABLE)) {
						upgrade_dispatched = true;
						upgrade_signal_source_id = 0U;
						binary_upgrade_detected (startup_exe_path);
						return false;
					}
				} catch (Error e) {
					warning ("Failed to inspect upgraded WayPlank binary: %s", e.message);
				}
				return true;
			});
		}

		public void reexec_self_on_upgrade (string executable_path, string? dock_name)
		{
			try {
				string[] spawn_argv = { executable_path, "--replace" };
				if (dock_name != null && dock_name != "")
					spawn_argv = { executable_path, "--replace", "-n", dock_name };
				Process.spawn_async (null, spawn_argv, null, SpawnFlags.SEARCH_PATH, null, null);
				Posix.exit (0);
			} catch (Error e) {
				warning ("Failed to hot-reload upgraded WayPlank binary: %s", e.message);
			}
		}

		public void exit_immediately (int status_code)
		{
			Posix.exit (status_code);
		}

		public string[] parse_command_argv (string cmdline)
		{
			string[] argv = {};
			try {
				Shell.parse_argv (cmdline, out argv);
			} catch (ShellError e) {
				return {};
			}
			return argv;
		}

		public void cleanup ()
		{
			if (sigint_source_id > 0U) {
				GLib.Source.remove (sigint_source_id);
				sigint_source_id = 0U;
			}
			if (sigterm_source_id > 0U) {
				GLib.Source.remove (sigterm_source_id);
				sigterm_source_id = 0U;
			}
			if (sighup_source_id > 0U) {
				GLib.Source.remove (sighup_source_id);
				sighup_source_id = 0U;
			}
			if (upgrade_signal_source_id > 0U) {
				GLib.Source.remove (upgrade_signal_source_id);
				upgrade_signal_source_id = 0U;
			}

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
		}

		public void invalidate_process_cache (int pid)
		{
			LinuxProcessInspector.invalidate_process_cmdline (pid);
		}
	}
}
