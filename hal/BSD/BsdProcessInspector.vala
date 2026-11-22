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

		public static void invalidate_process_cmdline (int pid)
		{
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

			if (!is_process_alive (pid)) {
				invalidate_process_cmdline (pid);
				return empty;
			}

			if (!include_children_and_fds) {
				cache_mutex.lock ();
				if (pid_snapshot_cache != null && pid_snapshot_cache.has_key (pid)) {
					var cached = pid_snapshot_cache.get (pid);
					cache_mutex.unlock ();
					return cached;
				}
				cache_mutex.unlock ();
			}

			int uid = -1;
			string comm = "";
			string exe_path = "";
			string cwd = "";
			if (!BsdKernelBridge.get_proc_basic (pid, out uid, out comm, out exe_path, out cwd))
				return empty;

			string[]? argv = BsdKernelBridge.get_proc_argv (pid);
			var snap = new ProcessSnapshot ();
			snap.pid = pid;
			snap.is_alive = true;
			snap.uid_matches_self = (uid >= 0 && (Posix.uid_t) uid == Posix.getuid ());
			snap.executable_comm = comm ?? "";
			snap.exe_realpath = exe_path ?? "";
			snap.working_dir = cwd ?? "";

			if (argv != null && argv.length > 0) {
				snap.cmdline_argv = argv;
				var sb = new StringBuilder ();
				for (int i = 0; i < argv.length; i++) {
					if (i > 0)
						sb.append_c (' ');
					sb.append (argv[i]);
				}
				snap.full_cmdline = sb.str;
			}

			if (!include_children_and_fds) {
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
			string hint = app_hint.strip ().down ();
			if (hint == "")
				return 0;

			string tail = hint;
			int last_dot = hint.last_index_of_char ('.');
			if (last_dot >= 0 && last_dot + 1 < hint.length)
				tail = hint.substring (last_dot + 1);

			string cap_lower = caption_hint.strip ().down ();
			string[] cap_tokens = cap_lower != "" ? cap_lower.split_set (" -_:|/()[]") : new string[0];

			int best_pid = 0;
			int best_score = 0;

			int[] user_pids = BsdKernelBridge.list_user_pids ();
			foreach (int pid in user_pids) {
				var snap = inspect_process (pid, false);
				if (!snap.is_alive || !snap.uid_matches_self)
					continue;

				string comm = snap.executable_comm.down ();
				string exe_base = snap.exe_realpath != "" ? Path.get_basename (snap.exe_realpath).down () : "";
				string cmd = snap.full_cmdline.down ();

				int score = 0;
				if (comm == hint || exe_base == hint)
					score += 100;
				else if (tail.length >= 2 && (comm == tail || exe_base == tail))
					score += 90;
				else if (tail.length >= 3 && (comm.contains (tail) || exe_base.contains (tail) || cmd.contains (tail)))
					score += 50;

				if (score == 0)
					continue;

				if (!cmd.contains ("--type=") && !cmd.contains ("crashpad"))
					score += 20;

				foreach (unowned string tok in cap_tokens) {
					if (tok.length >= 3 && cmd.contains (tok))
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
