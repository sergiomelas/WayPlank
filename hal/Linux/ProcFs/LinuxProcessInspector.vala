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
	 * Southbound Linux `/proc/<pid>` process inspector exposed via the kernel
	 * link seam so `src/` + `lib/` never touch `/proc` directly.
	 */
	public class LinuxProcessInspector : GLib.Object
	{
		static GLib.Mutex cache_mutex;
		static Gee.HashMap<int, string>? pid_cmdline_cache = null;
		static Gee.HashMap<int, string>? pid_comm_cache = null;
		static Gee.HashMap<int, string>? pid_cwd_cache = null;
		static Gee.HashMap<int, string>? pid_exe_cache = null;
		// Per-PID cached ProcessSnapshot (APPLICATION_IDENTITY_ENGINE.md §2.3) for
		// include_children_and_fds == false; children/fd snapshots stay live.
		static Gee.HashMap<int, ProcessSnapshot>? pid_snapshot_cache = null;
		const int MAX_PID_CACHE_ENTRIES = 512;

		public static bool is_process_alive (int pid)
		{
			return pid > 0 && FileUtils.test ("/proc/%d".printf (pid), FileTest.EXISTS);
		}

		static string[] parse_raw_cmdline_bytes (uint8[] data, out string formatted_cmdline)
		{
			var argv_list = new Gee.ArrayList<string> ();
			var builder = new StringBuilder ();
			int start = 0;
			for (int i = 0; i < data.length; i++) {
				if (data[i] == 0) {
					if (i > start) {
						char[] buf = new char[i - start + 1];
						Memory.copy (buf, (uint8*) data + start, i - start);
						buf[i - start] = 0;
						string arg = (string) buf;
						argv_list.add (arg);
						if (builder.len > 0)
							builder.append_c (' ');
						if (arg.contains (" ") || arg.contains ("\t")) {
							builder.append_c ('"');
							builder.append (arg);
							builder.append_c ('"');
						} else {
							builder.append (arg);
						}
					}
					start = i + 1;
				}
			}
			if (start < data.length) {
				char[] tail = new char[data.length - start + 1];
				Memory.copy (tail, (uint8*) data + start, data.length - start);
				tail[data.length - start] = 0;
				string tail_arg = (string) tail;
				if (tail_arg != "") {
					argv_list.add (tail_arg);
					if (builder.len > 0)
						builder.append_c (' ');
					if (tail_arg.contains (" ") || tail_arg.contains ("\t")) {
						builder.append_c ('"');
						builder.append (tail_arg);
						builder.append_c ('"');
					} else {
						builder.append (tail_arg);
					}
				}
			}
			formatted_cmdline = builder.str;
			return argv_list.to_array ();
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

			try {
				uint8[] data;
				if (FileUtils.get_data ("/proc/%d/cmdline".printf (pid), out data)) {
					string res = "";
					parse_raw_cmdline_bytes (data, out res);
					if (res != "") {
						cache_mutex.lock ();
						if (pid_cmdline_cache.size > 512)
							pid_cmdline_cache.clear ();
						pid_cmdline_cache.set (pid, res);
						cache_mutex.unlock ();
					}
					return res;
				}
			} catch { }
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

		public static string get_process_comm (int pid)
		{
			if (pid <= 0)
				return "";

			cache_mutex.lock ();
			if (pid_comm_cache == null)
				pid_comm_cache = new Gee.HashMap<int, string> ();
			if (pid_comm_cache.has_key (pid)) {
				string cached = pid_comm_cache.get (pid);
				cache_mutex.unlock ();
				return cached;
			}
			cache_mutex.unlock ();

			try {
				string comm = "";
				if (FileUtils.get_contents ("/proc/%d/comm".printf (pid), out comm)) {
					var res = comm.strip ();
					if (res != "") {
						cache_mutex.lock ();
						if (pid_comm_cache.size > 512)
							pid_comm_cache.clear ();
						pid_comm_cache.set (pid, res);
						cache_mutex.unlock ();
					}
					return res;
				}
			} catch { }
			return "";
		}

		public static string get_process_cwd (int pid)
		{
			if (pid <= 0)
				return "";

			cache_mutex.lock ();
			if (pid_cwd_cache == null)
				pid_cwd_cache = new Gee.HashMap<int, string> ();
			if (pid_cwd_cache.has_key (pid)) {
				string cached = pid_cwd_cache.get (pid);
				cache_mutex.unlock ();
				return cached;
			}
			cache_mutex.unlock ();

			try {
				string? cwd = FileUtils.read_link ("/proc/%d/cwd".printf (pid));
				if (cwd != null && cwd != "") {
					var res = cwd.replace ("\\", "/");
					cache_mutex.lock ();
					if (pid_cwd_cache.size > 512)
						pid_cwd_cache.clear ();
					pid_cwd_cache.set (pid, res);
					cache_mutex.unlock ();
					return res;
				}
			} catch { }
			return "";
		}

		public static string get_process_exe_realpath (int pid)
		{
			if (pid <= 0)
				return "";

			cache_mutex.lock ();
			if (pid_exe_cache == null)
				pid_exe_cache = new Gee.HashMap<int, string> ();
			if (pid_exe_cache.has_key (pid)) {
				string cached = pid_exe_cache.get (pid);
				cache_mutex.unlock ();
				return cached;
			}
			cache_mutex.unlock ();

			try {
				string? exe = FileUtils.read_link ("/proc/%d/exe".printf (pid));
				if (exe != null && exe != "") {
					string clean = exe;
					if (clean.has_suffix (" (deleted)"))
						clean = clean.substring (0, clean.length - " (deleted)".length);
					cache_mutex.lock ();
					if (pid_exe_cache.size > 512)
						pid_exe_cache.clear ();
					pid_exe_cache.set (pid, clean);
					cache_mutex.unlock ();
					return clean;
				}
			} catch { }
			return "";
		}

		static void read_environ_hints (int pid, out string env_appimage, out string env_wineprefix)
		{
			env_appimage = "";
			env_wineprefix = "";
			if (pid <= 0)
				return;

			try {
				uint8[] data;
				if (!FileUtils.get_data ("/proc/%d/environ".printf (pid), out data) || data.length == 0)
					return;
				int start = 0;
				for (int i = 0; i < data.length; i++) {
					if (data[i] == 0) {
						if (i > start) {
							char[] buf = new char[i - start + 1];
							Memory.copy (buf, (uint8*) data + start, i - start);
							buf[i - start] = 0;
							string entry = (string) buf;
							if (env_appimage == "" && entry.has_prefix ("APPIMAGE=")) {
								string p = entry.substring ("APPIMAGE=".length).strip ();
								if (p != "" && FileUtils.test (p, FileTest.EXISTS))
									env_appimage = p;
							} else if (env_wineprefix == "" && entry.has_prefix ("WINEPREFIX=")) {
								env_wineprefix = entry.substring ("WINEPREFIX=".length).strip ();
							}
							if (env_appimage != "" && env_wineprefix != "")
								return;
						}
						start = i + 1;
					}
				}
			} catch { }
		}

		static int[] read_child_pids (int pid)
		{
			if (pid <= 0)
				return {};

			string children_raw = "";
			try {
				if (!FileUtils.get_contents ("/proc/%d/task/%d/children".printf (pid, pid), out children_raw) || children_raw.strip () == "")
					FileUtils.get_contents ("/proc/%d/children".printf (pid), out children_raw);
			} catch {
				try {
					FileUtils.get_contents ("/proc/%d/children".printf (pid), out children_raw);
				} catch { }
			}

			string trimmed = children_raw.strip ();
			if (trimmed == "")
				return {};

			var list = new Gee.ArrayList<int> ();
			foreach (unowned string tok in trimmed.split (" ")) {
				int cpid = int.parse (tok.strip ());
				if (cpid > 0)
					list.add (cpid);
			}
			return list.to_array ();
		}

		static string[] read_open_fd_targets (int pid)
		{
			if (pid <= 0)
				return {};

			var targets = new Gee.ArrayList<string> ();
			try {
				string fd_dir_path = "/proc/%d/fd".printf (pid);
				var dir = Dir.open (fd_dir_path, 0);
				unowned string? name = null;
				while ((name = dir.read_name ()) != null) {
					int fd_num = int.parse (name);
					if (fd_num <= 0)
						continue;
					try {
						string link_target = FileUtils.read_link (Path.build_filename (fd_dir_path, name));
						if (link_target != "")
							targets.add (link_target);
					} catch { }
				}
			} catch { }
			return targets.to_array ();
		}

		public static ProcessSnapshot inspect_process (int pid, bool include_children_and_fds = false)
		{
			if (pid <= 0) {
				var empty = new ProcessSnapshot ();
				empty.pid = pid;
				return empty;
			}

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
					var dead = new ProcessSnapshot ();
					dead.pid = pid;
					return dead;
				}
			}

			var snap = new ProcessSnapshot ();
			snap.pid = pid;

			Posix.Stat st;
			if (Posix.stat ("/proc/%d".printf (pid), out st) != 0)
				return snap;

			snap.is_alive = true;
			snap.uid_matches_self = (st.st_uid == Posix.getuid ());
			snap.executable_comm = get_process_comm (pid);
			snap.exe_realpath = get_process_exe_realpath (pid);
			snap.working_dir = get_process_cwd (pid);

			try {
				uint8[] data;
				if (FileUtils.get_data ("/proc/%d/cmdline".printf (pid), out data) && data.length > 0) {
					string formatted = "";
					snap.cmdline_argv = parse_raw_cmdline_bytes (data, out formatted);
					snap.full_cmdline = formatted;
					if (formatted != "") {
						cache_mutex.lock ();
						if (pid_cmdline_cache == null)
							pid_cmdline_cache = new Gee.HashMap<int, string> ();
						if (pid_cmdline_cache.size > 512)
							pid_cmdline_cache.clear ();
						pid_cmdline_cache.set (pid, formatted);
						cache_mutex.unlock ();
					}
				}
			} catch { }

			string appimg = "";
			string winepref = "";
			read_environ_hints (pid, out appimg, out winepref);
			snap.env_appimage = appimg;
			snap.env_wineprefix = winepref;

			if (include_children_and_fds) {
				snap.child_pids = read_child_pids (pid);
				var c_cmds = new string[snap.child_pids.length];
				for (int i = 0; i < snap.child_pids.length; i++)
					c_cmds[i] = get_process_cmdline (snap.child_pids[i]);
				snap.child_cmdlines = c_cmds;
				snap.open_fd_targets = read_open_fd_targets (pid);
			} else if (snap.full_cmdline != "") {
				cache_mutex.lock ();
				if (pid_snapshot_cache == null)
					pid_snapshot_cache = new Gee.HashMap<int, ProcessSnapshot> ();
				if (pid_snapshot_cache.size > MAX_PID_CACHE_ENTRIES)
					pid_snapshot_cache.clear ();
				pid_snapshot_cache.set (pid, snap);
				cache_mutex.unlock ();
			}

			return snap;
		}

		public static Gee.ArrayList<ProcessSnapshot> scan_user_processes ()
		{
			var list = new Gee.ArrayList<ProcessSnapshot> ();
			var my_uid = Posix.getuid ();
			try {
				var dir = Dir.open ("/proc", 0);
				unowned string? name = null;
				while ((name = dir.read_name ()) != null) {
					int pid = int.parse (name);
					if (pid <= 0)
						continue;

					Posix.Stat st;
					if (Posix.stat ("/proc/%s".printf (name), out st) != 0 || st.st_uid != my_uid)
						continue;

					var snap = new ProcessSnapshot ();
					snap.pid = pid;
					snap.is_alive = true;
					snap.uid_matches_self = true;
					snap.executable_comm = get_process_comm (pid);
					snap.full_cmdline = get_process_cmdline (pid);
					if (snap.full_cmdline != "")
						snap.cmdline_argv = Hal.Runtime.parse_command_argv (snap.full_cmdline);
					list.add (snap);
				}
			} catch { }
			return list;
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
			var comm_prefix = target_cls.length > 15 ? target_cls.substring (0, 15) : target_cls;
			string short_cls = "";
			int last_dot = target_cls.last_index_of_char ('.');
			if (last_dot >= 0 && last_dot + 1 < target_cls.length)
				short_cls = target_cls.substring (last_dot + 1);
			if (target_cls.has_prefix ("chrome-") || target_cls.has_prefix ("chromium-"))
				short_cls = target_cls.has_prefix ("chromium-") ? "chromium" : "chrome";
			string short_prefix = short_cls.length > 15 ? short_cls.substring (0, 15) : short_cls;

			try {
				var proc_dir = Dir.open ("/proc", 0);
				unowned string? entry = null;
				while ((entry = proc_dir.read_name ()) != null) {
					int pid = int.parse (entry);
					if (pid <= 0)
						continue;

					var comm = get_process_comm (pid).down ();
					if (comm == "")
						continue;

					var cmdline = get_process_cmdline (pid);
					var cmd_lower = cmdline.down ();

					bool exact_match = (comm == target_cls || comm == comm_prefix || cmd_lower.contains (target_cls));
					bool tail_match = (!exact_match && short_cls.length >= 3
						&& (comm == short_cls || comm == short_prefix || cmd_lower.contains ("/" + short_cls) || cmd_lower.has_prefix (short_cls + " ") || cmd_lower == short_cls));
					if (!exact_match && !tail_match)
						continue;

					int score = exact_match ? 15 : 10;
					if (comm == target_cls || (short_cls.length >= 3 && comm == short_cls))
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
			} catch { }

			return best_pid;
		}
	}
}
