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
	 * Southbound FreeBSD runtime driver implementing `IPlatformRuntime`.
	 * Uses official FreeBSD APIs (`setproctitle`, `KERN_PROC_PATHNAME`,
	 * `libprocstat` PID enumeration, `fork()`, `SIGWINCH`, `/usr/bin/fetch`,
	 * and base `bsdtar`).
	 */
	public class BsdPlatformRuntime : GLib.Object, IPlatformRuntime
	{
		static BsdPlatformRuntime? instance = null;

		public static BsdPlatformRuntime get_default ()
		{
			if (instance == null)
				instance = new BsdPlatformRuntime ();
			return instance;
		}

		bool lifecycle_installed = false;
		bool session_watchers_installed = false;
		uint sigint_source_id = 0U;
		uint sigterm_source_id = 0U;
		uint sighup_source_id = 0U;
		uint upgrade_signal_source_id = 0U;
		string startup_exe_path = "";
		uint64 startup_exe_dev = 0;
		uint64 startup_exe_ino = 0;
		bool has_startup_exe_stat = false;
		bool upgrade_dispatched = false;

		public bool open_system_utility (DesktopUtilityKind kind)
		{
			return false;
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
			string quoted_url = Shell.quote (url);
			string stdout_str = "";
			int exit_status = -1;

			if (FileUtils.test ("/usr/bin/fetch", FileTest.IS_EXECUTABLE)) {
				string cmd = "/usr/bin/fetch -q -T %d -o - %s".printf (effective_timeout, quoted_url);
				try {
					if (Process.spawn_command_line_sync (cmd, out stdout_str, null, out exit_status) && exit_status == 0) {
						response_body = stdout_str ?? "";
						return true;
					}
				} catch (GLib.Error e) {
					warning ("FreeBSD fetch failed for '%s': %s", url, e.message);
				}
			}

			if (Environment.find_program_in_path ("curl") != null) {
				string cmd = "curl -s --max-time %d %s".printf (effective_timeout, quoted_url);
				try {
					if (Process.spawn_command_line_sync (cmd, out stdout_str, null, out exit_status) && exit_status == 0) {
						response_body = stdout_str ?? "";
						return true;
					}
				} catch (GLib.Error e) {
					warning ("HTTP GET failed for '%s': %s", url, e.message);
				}
			}

			return false;
		}

		public bool extract_archive (string archive_path, string dest_dir)
		{
			string lower = archive_path.down ();
			if (!lower.has_suffix (".zip") && !lower.has_suffix (".tar.gz") && !lower.has_suffix (".tgz")
				&& !lower.has_suffix (".tar.xz") && !lower.has_suffix (".txz") && !lower.has_suffix (".tar.bz2"))
				return false;

			int exit_status = -1;
			string q_archive = Shell.quote (archive_path);
			string q_dest = Shell.quote (dest_dir);

			// FreeBSD base `tar` is libarchive `bsdtar`, supporting zip/gz/xz/bz2 natively.
			try {
				Process.spawn_command_line_sync ("tar -xf %s -C %s".printf (q_archive, q_dest), null, null, out exit_status);
				return exit_status == 0;
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
			return false;
		}

		public bool set_autostart_enabled (bool enabled)
		{
			return false;
		}

		public void terminate_legacy_competing_docks ()
		{
			if (Path.get_basename (Environment.get_prgname () ?? "wayplank") == "plank")
				return;
			int self_pid = (int) Posix.getpid ();
			int[] user_pids = BsdKernelBridge.list_user_pids ();
			foreach (int p in user_pids) {
				if (p <= 0 || p == self_pid)
					continue;
				int uid;
				string comm;
				string exe_path;
				string cwd;
				if (!BsdKernelBridge.get_proc_basic (p, out uid, out comm, out exe_path, out cwd))
					continue;
				if (comm == "plank" || Path.get_basename (exe_path) == "plank")
					Posix.kill ((Posix.pid_t) p, Posix.Signal.TERM);
			}
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

		private static bool pid_matches_replace_target (int pid, string target_dock_name)
		{
			string[]? argv = BsdKernelBridge.get_proc_argv (pid);
			if (argv == null || argv.length == 0)
				return false;
			var exe_base = Path.get_basename (argv[0]);
			if (exe_base != "wayplank" && exe_base != "plank")
				return false;
			return extract_dock_name_from_args (argv) == target_dock_name;
		}

		public void replace_running_instances (string target_dock_name)
		{
			int self_pid = (int) Posix.getpid ();
			bool sent_term = false;
			int[] user_pids = BsdKernelBridge.list_user_pids ();
			foreach (int p in user_pids) {
				if (p > 0 && p != self_pid && pid_matches_replace_target (p, target_dock_name)) {
					Posix.kill ((Posix.pid_t) p, Posix.Signal.TERM);
					sent_term = true;
				}
			}
			if (sent_term) {
				Thread.usleep (200000);
				int[] remaining = BsdKernelBridge.list_user_pids ();
				foreach (int p in remaining) {
					if (p > 0 && p != self_pid && pid_matches_replace_target (p, target_dock_name))
						Posix.kill ((Posix.pid_t) p, Posix.Signal.KILL);
				}
				Thread.usleep (50000);
			}
		}

		public void prepare_process_environment ()
		{
			Environment.set_variable ("GTK_USE_PORTAL", "0", true);
		}

		public void restore_process_environment ()
		{
		}

		public bool verify_supported_display (Gdk.Display? display, out string error_message)
		{
			error_message = "";
			return display != null;
		}

		public string get_self_launcher_id ()
		{
			return "wayplank.desktop";
		}

		public string get_system_data_dir ()
		{
			return "/usr/local/share";
		}

		public string[] get_extra_schema_dirs ()
		{
			return {
				"/usr/local/share/glib-2.0/schemas",
				Path.build_filename (Build.DATADIR, "glib-2.0", "schemas"),
				"/usr/share/glib-2.0/schemas"
			};
		}

		public string canonicalize_path (string path)
		{
			if (path == "")
				return "";
			string? real = Posix.realpath (path);
			if (real != null && real != "")
				return real;
			string parent = Path.get_dirname (path);
			string bname = Path.get_basename (path);
			if (parent != "" && parent != "." && bname != "" && bname != "." && bname != "/") {
				string? real_parent = Posix.realpath (parent);
				if (real_parent != null && real_parent != "")
					return Path.build_filename (real_parent, bname);
			}
			return Path.build_filename (path);
		}

		public bool paths_equal (string path_a, string path_b)
		{
			if (path_a == path_b)
				return true;
			if (path_a == "" || path_b == "")
				return false;
			return canonicalize_path (path_a) == canonicalize_path (path_b);
		}

		public string expand_path_variables (string raw, Gee.HashMap<string, string>? extra_vars = null)
		{
			string s = raw.strip ();
			if (extra_vars != null && extra_vars.size > 0 && s.contains ("$")) {
				var sorted_keys = new Gee.ArrayList<string> ();
				sorted_keys.add_all (extra_vars.keys);
				sorted_keys.sort ((a, b) => {
					if (a.length != b.length)
						return b.length - a.length;
					return strcmp (a, b);
				});
				foreach (var k in sorted_keys) {
					var val = extra_vars.get (k) ?? "";
					s = s.replace ("${" + k + "}", val);
					s = s.replace ("$" + k, val);
				}
			}
			string home = GLib.Environment.get_home_dir ();
			string user = GLib.Environment.get_user_name ();
			string cfg = GLib.Environment.get_user_config_dir ();
			string data = GLib.Environment.get_user_data_dir ();
			if (cfg != "") {
				if (home != "")
					s = s.replace ("${XDG_CONFIG_HOME:-$HOME/.config}", cfg).replace ("${XDG_CONFIG_HOME:-${HOME}/.config}", cfg);
				s = s.replace ("${XDG_CONFIG_HOME}", cfg).replace ("$XDG_CONFIG_HOME", cfg);
			}
			if (data != "") {
				if (home != "")
					s = s.replace ("${XDG_DATA_HOME:-$HOME/.local/share}", data).replace ("${XDG_DATA_HOME:-${HOME}/.local/share}", data);
				s = s.replace ("${XDG_DATA_HOME}", data).replace ("$XDG_DATA_HOME", data);
			}
			if (home != "") {
				s = s.replace ("${HOME}", home).replace ("$HOME", home);
				if (s == "~")
					s = home;
				else if (s.has_prefix ("~/"))
					s = home + s.substring (1);
			}
			if (user != "")
				s = s.replace ("${USER}", user).replace ("$USER", user);
			return s;
		}

		public int get_current_pid ()
		{
			return getpid ();
		}

		public void set_process_title (string title)
		{
			setproctitle ("%s", title);
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

			startup_exe_path = BsdKernelBridge.get_self_exe_path () ?? "";
			if (startup_exe_path != "") {
				Posix.Stat st;
				if (Posix.stat (startup_exe_path, out st) == 0) {
					startup_exe_dev = (uint64) st.st_dev;
					startup_exe_ino = (uint64) st.st_ino;
					has_startup_exe_stat = true;
				}
			}

			upgrade_signal_source_id = GLib.Unix.signal_add ((int) Posix.Signal.WINCH, () => {
				if (upgrade_dispatched || startup_exe_path == "" || !has_startup_exe_stat)
					return true;
				Posix.Stat cur;
				if (Posix.stat (startup_exe_path, out cur) == 0
					&& ((uint64) cur.st_dev != startup_exe_dev || (uint64) cur.st_ino != startup_exe_ino)
					&& FileUtils.test (startup_exe_path, FileTest.IS_EXECUTABLE)) {
					upgrade_dispatched = true;
					upgrade_signal_source_id = 0U;
					binary_upgrade_detected (startup_exe_path);
					return false;
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

		public string quote_command_arg (string arg)
		{
			if (arg == "")
				return "\"\"";
			if (!arg.contains (" ") && !arg.contains ("\t") && !arg.contains ("\"") && !arg.contains ("'"))
				return arg;
			return "\"" + arg.replace ("\\", "\\\\").replace ("\"", "\\\"") + "\"";
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
		}

		public void invalidate_process_cache (int pid)
		{
			BsdProcessInspector.invalidate_process_cmdline (pid);
		}
	}
}
