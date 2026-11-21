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
	 * Southbound `/proc/stat`, `/proc/meminfo`, and `/proc/diskstats` telemetry sampler (`ICpuMemoryProvider`).
	 */
	public class LinuxCpuMemDiskTelemetry : GLib.Object, ICpuMemoryProvider
	{
		static LinuxCpuMemDiskTelemetry? default_instance = null;

		public static LinuxCpuMemDiskTelemetry get_default ()
		{
			if (default_instance == null)
				default_instance = new LinuxCpuMemDiskTelemetry ();
			return default_instance;
		}

		uint64 prev_total = 0;
		uint64 prev_idle = 0;
		uint64 prev_io_ticks = 0;
		int64 prev_io_time_ms = 0;
		int cpu_pct = 0;
		int ram_pct = 0;
		int io_pct = 0;
		int system_pressure = 0;
		double ram_used_gb = 0.0;
		double ram_total_gb = 0.0;

		public CpuMemDiskSample sample ()
		{
			// 1. CPU Usage via /proc/stat
			string stat_content;
			try {
				if (FileUtils.get_contents ("/proc/stat", out stat_content)) {
					var lines = stat_content.split ("\n");
					if (lines.length > 0 && lines[0].has_prefix ("cpu ")) {
						var parts = lines[0].split (" ");
						uint64 user = 0, nice = 0, system = 0, idle = 0, iowait = 0, irq = 0, softirq = 0, steal = 0;
						int part_idx = 0;
						for (int i = 1; i < parts.length; i++) {
							if (parts[i].strip () == "") continue;
							uint64 val = (uint64) uint64.parse (parts[i]);
							if (part_idx == 0) user = val;
							else if (part_idx == 1) nice = val;
							else if (part_idx == 2) system = val;
							else if (part_idx == 3) idle = val;
							else if (part_idx == 4) iowait = val;
							else if (part_idx == 5) irq = val;
							else if (part_idx == 6) softirq = val;
							else if (part_idx == 7) steal = val;
							part_idx++;
						}

						uint64 total = user + nice + system + idle + iowait + irq + softirq + steal;
						uint64 idle_all = idle + iowait;

						if (prev_total > 0 && total > prev_total) {
							uint64 diff_total = total - prev_total;
							uint64 diff_idle = (idle_all >= prev_idle) ? (idle_all - prev_idle) : 0;
							cpu_pct = (int) Math.round (100.0 * (double) (diff_total - diff_idle) / (double) diff_total);
							if (cpu_pct < 0) cpu_pct = 0;
							if (cpu_pct > 100) cpu_pct = 100;
						}
						prev_total = total;
						prev_idle = idle_all;
					}
				}
			} catch (Error e) { }

			// 2. RAM Usage via /proc/meminfo
			string mem_content;
			try {
				if (FileUtils.get_contents ("/proc/meminfo", out mem_content)) {
					uint64 total_kb = 0, avail_kb = 0;
					foreach (unowned string line in mem_content.split ("\n")) {
						if (line.has_prefix ("MemTotal:")) {
							var parts = line.split (":");
							if (parts.length > 1) total_kb = (uint64) uint64.parse (parts[1].strip ().replace ("kB", "").strip ());
						} else if (line.has_prefix ("MemAvailable:")) {
							var parts = line.split (":");
							if (parts.length > 1) avail_kb = (uint64) uint64.parse (parts[1].strip ().replace ("kB", "").strip ());
						}
					}

					if (total_kb > 0) {
						ram_total_gb = total_kb / (1024.0 * 1024.0);
						ram_used_gb = (total_kb - avail_kb) / (1024.0 * 1024.0);
						ram_pct = (int) Math.round (100.0 * (double) (total_kb - avail_kb) / (double) total_kb);
						if (ram_pct < 0) ram_pct = 0;
						if (ram_pct > 100) ram_pct = 100;
					}
				}
			} catch (Error e) { }

			// 3. Disk I/O Usage via /proc/diskstats
			string disk_content;
			try {
				if (FileUtils.get_contents ("/proc/diskstats", out disk_content)) {
					uint64 current_io_ticks = 0;
					foreach (unowned string line in disk_content.split ("\n")) {
						var parts = line.strip ().split (" ");
						int tok_idx = 0;
						unowned string? dev = null;
						unowned string? io_ticks_str = null;
						foreach (unowned string p in parts) {
							if (p == "")
								continue;
							if (tok_idx == 2)
								dev = p;
							else if (tok_idx == 12)
								io_ticks_str = p;
							tok_idx++;
						}
						if (tok_idx >= 13 && dev != null && io_ticks_str != null) {
							if ((dev.has_prefix ("sd") && dev.length == 3) ||
							    (dev.has_prefix ("vd") && dev.length == 3) ||
							    (dev.has_prefix ("nvme") && !dev.contains ("p")) ||
							    (dev.has_prefix ("mmcblk") && !dev.contains ("p"))) {
								current_io_ticks += (uint64) uint64.parse (io_ticks_str);
							}
						}
					}

					int64 now_ms = GLib.get_monotonic_time () / 1000;
					if (prev_io_time_ms > 0 && now_ms > prev_io_time_ms && current_io_ticks >= prev_io_ticks) {
						int64 elapsed_ms = now_ms - prev_io_time_ms;
						uint64 diff_ticks = current_io_ticks - prev_io_ticks;
						io_pct = (int) Math.round (100.0 * (double) diff_ticks / (double) elapsed_ms);
						if (io_pct < 0) io_pct = 0;
						if (io_pct > 100) io_pct = 100;
					}
					prev_io_ticks = current_io_ticks;
					prev_io_time_ms = now_ms;
				}
			} catch (Error e) { }

			// 4. Bottleneck-Dominant Global System Pressure
			int max_comp = int.max (cpu_pct, int.max (ram_pct, io_pct));
			double mean_comp = (cpu_pct + ram_pct + io_pct) / 3.0;
			system_pressure = (int) Math.round (0.60 * (double) max_comp + 0.40 * mean_comp);
			if (system_pressure < 0) system_pressure = 0;
			if (system_pressure > 100) system_pressure = 100;

			return CpuMemDiskSample () {
				cpu_pct = cpu_pct,
				ram_pct = ram_pct,
				io_pct = io_pct,
				system_pressure = system_pressure,
				ram_used_gb = ram_used_gb,
				ram_total_gb = ram_total_gb
			};
		}
	}
}
