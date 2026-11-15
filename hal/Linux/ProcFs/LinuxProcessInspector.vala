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
	 * Southbound Linux `/proc/<pid>/{cmdline,comm}` reader used inside Zone 3
	 * compositor drivers so `hal/` never reaches upward into `lib/Services/`.
	 */
	public class LinuxProcessInspector : GLib.Object
	{
		static GLib.Mutex cache_mutex;
		static Gee.HashMap<int, string>? pid_cmdline_cache = null;
		static Gee.HashMap<int, string>? pid_comm_cache = null;

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
					var builder = new StringBuilder ();
					int start = 0;
					for (int i = 0; i < data.length; i++) {
						if (data[i] == 0) {
							if (i > start) {
								char[] buf = new char[i - start + 1];
								Memory.copy (buf, (uint8*) data + start, i - start);
								buf[i - start] = 0;
								string arg = (string) buf;
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
					var res = builder.str;
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
	}
}
