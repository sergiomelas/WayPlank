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
	 * Southbound FreeBSD process inspector backed by official `libprocstat(3)`
	 * and `sysctl(3)` kernel queries via `BsdKernelBridge` (`bsd-kernel-bridge.c`).
	 * Implements the complete kernel process-inspection seam via native BSD APIs.
	 */
	public class BsdProcessInspector : GLib.Object
	{
		private const int MAX_PID_CACHE_ENTRIES = 512;

		private static GLib.Mutex cache_mutex;
		private static Gee.HashMap<int, string>? pid_cmdline_cache = null;
		private static Gee.HashMap<int, string>? pid_comm_cache = null;
		private static Gee.HashMap<int, string>? pid_cwd_cache = null;
		private static Gee.HashMap<int, string>? pid_exe_cache = null;
		private static Gee.HashMap<int, ProcessSnapshot>? pid_snapshot_cache = null;

		public static bool is_process_alive (int pid)
		{
			return BsdKernelBridge.is_process_alive (pid);
		}

		private static string format_argv_cmdline (string[] argv)
		{
			var sb = new StringBuilder ();
			for (int i = 0; i < argv.length; i++) {
				unowned string arg = argv[i];
				if (arg == "")
					continue;
				if (sb.len > 0)
					sb.append_c (' ');
				if (arg.contains (" ") || arg.contains ("\t")) {
					sb.append_c ('"');
					sb.append (arg);
					sb.append_c ('"');
				} else {
					sb.append (arg);
				}
			}
			return sb.str;
		}

		public static string get_process_cmdline (int pid)
		{
			if (pid <= 0)
				return "";

			cache_mutex.lock ();
			if (pid_cmdline_cache == null)
				pid_cmdline_cache = new Gee.HashMap<int, string> ();
			if (pid_cmdline_cache.has_key (pid)) {
				string cached = pid_cmdline_cache.get (pid);
				cache_mutex.unlock ();
				return cached;
			}
			cache_mutex.unlock ();

			string[]? argv = BsdKernelBridge.get_proc_argv (pid);
			if (argv != null && argv.length > 0) {
				string formatted = format_argv_cmdline (argv);
				if (formatted != "") {
					cache_mutex.lock ();
					if (pid_cmdline_cache.size >= MAX_PID_CACHE_ENTRIES)
						pid_cmdline_cache.clear ();
					pid_cmdline_cache.set (pid, formatted);
					cache_mutex.unlock ();
					return formatted;
				}
			}
			return "";
		}

		public static void invalidate_process_cmdline (int pid)
		{
			if (pid <= 0)
				return;
			cache_mutex.lock ();
			if (pid_cmdline_cache != null)
				pid_cmdline_cache.unset (pid);
			if (pid_comm_cache != null)
				pid_comm_cache.unset (pid);
			if (pid_cwd_cache != null)
				pid_cwd_cache.unset (pid);
			if (pid_exe_cache != null)
				pid_exe_cache.unset (pid);
			if (pid_snapshot_cache != null)
				pid_snapshot_cache.unset (pid);
			cache_mutex.unlock ();
		}

		public static void clear_all_caches ()
		{
			cache_mutex.lock ();
			if (pid_cmdline_cache != null)
				pid_cmdline_cache.clear ();
			if (pid_comm_cache != null)
				pid_comm_cache.clear ();
			if (pid_cwd_cache != null)
				pid_cwd_cache.clear ();
			if (pid_exe_cache != null)
				pid_exe_cache.clear ();
			if (pid_snapshot_cache != null)
				pid_snapshot_cache.clear ();
			cache_mutex.unlock ();
		}

		public static ProcessSnapshot inspect_process (int pid, bool include_children_and_fds = false)
		{
			var empty = new ProcessSnapshot ();
			empty.pid = pid;
			if (pid <= 0)
				return empty;

			if (!include_children_and_fds) {
				ProcessSnapshot? cached = null;
				cache_mutex.lock ();
				if (pid_snapshot_cache != null)
					cached = pid_snapshot_cache.get (pid);
				cache_mutex.unlock ();
				if (cached != null) {
					if (is_process_alive (pid))
						return cached;
					invalidate_process_cmdline (pid);
					return empty;
				}
			} else if (!is_process_alive (pid)) {
				invalidate_process_cmdline (pid);
				return empty;
			}

			int uid = -1;
			string comm = "";
			string exe_path = "";
			string cwd = "";
			if (!BsdKernelBridge.get_proc_basic (pid, out uid, out comm, out exe_path, out cwd))
				return empty;

			var snap = new ProcessSnapshot ();
			snap.pid = pid;
			snap.is_alive = true;
			snap.uid_matches_self = (uid >= 0 && (Posix.uid_t) uid == Posix.getuid ());
			snap.executable_comm = (comm ?? "").strip ();
			snap.exe_realpath = exe_path ?? "";
			snap.working_dir = (cwd ?? "").replace ("\\", "/");

			string[]? argv = BsdKernelBridge.get_proc_argv (pid);
			if (argv != null && argv.length > 0) {
				snap.cmdline_argv = argv;
				snap.full_cmdline = format_argv_cmdline (argv);
			}

			string appimg = "";
			string winepref = "";
			if (BsdKernelBridge.get_proc_env_hints (pid, out appimg, out winepref)) {
				snap.env_appimage = appimg ?? "";
				snap.env_wineprefix = winepref ?? "";
			}

			if (include_children_and_fds) {
				snap.child_pids = BsdKernelBridge.get_child_pids (pid);
				var c_cmds = new string[snap.child_pids.length];
				for (int i = 0; i < snap.child_pids.length; i++)
					c_cmds[i] = get_process_cmdline (snap.child_pids[i]);
				snap.child_cmdlines = c_cmds;

				string[]? fds = BsdKernelBridge.get_open_fd_paths (pid);
				if (fds != null)
					snap.open_fd_targets = fds;
			} else if (snap.full_cmdline != "") {
				cache_mutex.lock ();
				if (pid_snapshot_cache == null)
					pid_snapshot_cache = new Gee.HashMap<int, ProcessSnapshot> ();
				if (pid_snapshot_cache.size >= MAX_PID_CACHE_ENTRIES)
					pid_snapshot_cache.clear ();
				pid_snapshot_cache.set (pid, snap);

				if (pid_cmdline_cache == null)
					pid_cmdline_cache = new Gee.HashMap<int, string> ();
				if (pid_cmdline_cache.size >= MAX_PID_CACHE_ENTRIES)
					pid_cmdline_cache.clear ();
				pid_cmdline_cache.set (pid, snap.full_cmdline);

				if (pid_comm_cache == null)
					pid_comm_cache = new Gee.HashMap<int, string> ();
				if (pid_comm_cache.size >= MAX_PID_CACHE_ENTRIES)
					pid_comm_cache.clear ();
				pid_comm_cache.set (pid, snap.executable_comm);

				if (pid_cwd_cache == null)
					pid_cwd_cache = new Gee.HashMap<int, string> ();
				if (pid_cwd_cache.size >= MAX_PID_CACHE_ENTRIES)
					pid_cwd_cache.clear ();
				pid_cwd_cache.set (pid, snap.working_dir);

				if (pid_exe_cache == null)
					pid_exe_cache = new Gee.HashMap<int, string> ();
				if (pid_exe_cache.size >= MAX_PID_CACHE_ENTRIES)
					pid_exe_cache.clear ();
				pid_exe_cache.set (pid, snap.exe_realpath);
				cache_mutex.unlock ();
			}

			return snap;
		}

		public static Gee.ArrayList<ProcessSnapshot> scan_user_processes ()
		{
			var results = new Gee.ArrayList<ProcessSnapshot> ();
			int[] user_pids = BsdKernelBridge.list_user_pids ();
			foreach (int pid in user_pids) {
				var snap = inspect_process (pid, false);
				if (snap.is_alive && snap.uid_matches_self)
					results.add (snap);
			}
			return results;
		}

		public static int find_pid_by_app_hint (string app_hint, string caption_hint = "")
		{
			string target_cls = app_hint.down ().strip ();
			if (target_cls == "")
				return 0;

			var caption_tokens = new Gee.ArrayList<string> ();
			if (caption_hint != "") {
				var cleaned = caption_hint.down ()
					.replace ("(", " ")
					.replace (")", " ")
					.replace ("[", " ")
					.replace ("]", " ")
					.replace (":", " ")
					.replace (",", " ");
				foreach (var part in cleaned.split (" ")) {
					var tok = part.strip ();
					if (tok.length >= 2 && tok != target_cls && tok != "qemu")
						caption_tokens.add (tok);
				}
			}

			int best_pid = 0;
			int best_score = 0;
			string comm_prefix = target_cls.length > 15 ? target_cls.substring (0, 15) : target_cls;
			string short_cls = "";
			int last_dot = target_cls.last_index_of_char ('.');
			if (last_dot >= 0 && last_dot + 1 < target_cls.length)
				short_cls = target_cls.substring (last_dot + 1);
			if (target_cls.has_prefix ("chrome-") || target_cls.has_prefix ("chromium-"))
				short_cls = target_cls.has_prefix ("chromium-") ? "chromium" : "chrome";
			string short_prefix = short_cls.length > 15 ? short_cls.substring (0, 15) : short_cls;

			int[] user_pids = BsdKernelBridge.list_user_pids ();
			foreach (int pid in user_pids) {
				if (pid <= 0)
					continue;
				var snap = inspect_process (pid, false);
				if (!snap.is_alive || !snap.uid_matches_self)
					continue;

				string comm = snap.executable_comm.down ();
				if (comm == "")
					continue;
				string exe_base = snap.exe_realpath != "" ? Path.get_basename (snap.exe_realpath).down () : "";
				string cmd_lower = snap.full_cmdline.down ();

				bool exact_match = (comm == target_cls || comm == comm_prefix || exe_base == target_cls || cmd_lower.contains (target_cls));
				bool tail_match = (!exact_match && short_cls.length >= 3
					&& (comm == short_cls || comm == short_prefix || exe_base == short_cls
						|| cmd_lower.contains ("/" + short_cls)
						|| cmd_lower.has_prefix (short_cls + " ")
						|| cmd_lower == short_cls));
				if (!exact_match && !tail_match)
					continue;

				int score = exact_match ? 15 : 10;
				if (comm == target_cls || exe_base == target_cls || (short_cls.length >= 3 && (comm == short_cls || exe_base == short_cls)))
					score += 15;
				if (!cmd_lower.contains ("--type=") && !comm.contains ("crashpad"))
					score += 25;
				foreach (var tok in caption_tokens) {
					if (cmd_lower.contains (tok))
						score += 50;
				}

				if (score > best_score) {
					best_score = score;
					best_pid = pid;
				}
			}

			return best_pid;
		}
	}
}
