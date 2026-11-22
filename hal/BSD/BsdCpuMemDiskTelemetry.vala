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
	 * Southbound FreeBSD CPU, ZFS ARC-aware RAM, and `libdevstat` Disk I/O
	 * telemetry provider implementing `ICpuMemoryProvider`.
	 */
	public class BsdCpuMemDiskTelemetry : GLib.Object, ICpuMemoryProvider
	{
		static BsdCpuMemDiskTelemetry? instance = null;

		public static BsdCpuMemDiskTelemetry get_default ()
		{
			if (instance == null)
				instance = new BsdCpuMemDiskTelemetry ();
			return instance;
		}

		uint64 prev_cpu_total = 0;
		uint64 prev_cpu_idle = 0;
		bool has_prev_cpu = false;

		uint64 prev_io_busy_ms = 0;
		int64 prev_io_time_us = 0;
		bool has_prev_io = false;

		public CpuMemDiskSample sample ()
		{
			int cpu_pct = 0;
			int ram_pct = 0;
			int io_pct = 0;
			double ram_used_gb = 0.0;
			double ram_total_gb = 0.0;

			uint64 total_ticks = 0;
			uint64 idle_ticks = 0;
			if (BsdKernelBridge.read_cpu_ticks (out total_ticks, out idle_ticks)) {
				if (has_prev_cpu && total_ticks > prev_cpu_total) {
					uint64 d_total = total_ticks - prev_cpu_total;
					uint64 d_idle = (idle_ticks >= prev_cpu_idle) ? (idle_ticks - prev_cpu_idle) : 0;
					if (d_total > 0) {
						double busy = 100.0 * (1.0 - ((double) d_idle / (double) d_total));
						cpu_pct = ((int) Math.round (busy)).clamp (0, 100);
					}
				}
				prev_cpu_total = total_ticks;
				prev_cpu_idle = idle_ticks;
				has_prev_cpu = true;
			}

			uint64 total_bytes = 0;
			uint64 avail_bytes = 0;
			if (BsdKernelBridge.read_memory (out total_bytes, out avail_bytes) && total_bytes > 0) {
				uint64 used_bytes = (total_bytes > avail_bytes) ? (total_bytes - avail_bytes) : 0;
				const double GIB = 1024.0 * 1024.0 * 1024.0;
				ram_total_gb = (double) total_bytes / GIB;
				ram_used_gb = (double) used_bytes / GIB;
				ram_pct = ((int) Math.round (100.0 * ((double) used_bytes / (double) total_bytes))).clamp (0, 100);
			}

			uint64 io_busy_ms = 0;
			int64 now_us = GLib.get_monotonic_time ();
			if (BsdKernelBridge.read_disk_busy_ms (out io_busy_ms)) {
				if (has_prev_io && now_us > prev_io_time_us && io_busy_ms >= prev_io_busy_ms) {
					double elapsed_ms = (double) (now_us - prev_io_time_us) / 1000.0;
					if (elapsed_ms > 1.0) {
						double pct = 100.0 * ((double) (io_busy_ms - prev_io_busy_ms) / elapsed_ms);
						io_pct = ((int) Math.round (pct)).clamp (0, 100);
					}
				}
				prev_io_busy_ms = io_busy_ms;
				prev_io_time_us = now_us;
				has_prev_io = true;
			}

			int peak = int.max (cpu_pct, int.max (ram_pct, io_pct));
			double mean = (cpu_pct + ram_pct + io_pct) / 3.0;
			int pressure = ((int) Math.round (0.60 * (double) peak + 0.40 * mean)).clamp (0, 100);

			return CpuMemDiskSample () {
				cpu_pct = cpu_pct,
				ram_pct = ram_pct,
				io_pct = io_pct,
				system_pressure = pressure,
				ram_used_gb = ram_used_gb,
				ram_total_gb = ram_total_gb
			};
		}
	}
}
