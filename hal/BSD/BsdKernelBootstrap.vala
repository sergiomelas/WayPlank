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
	 * Southbound FreeBSD kernel link-seam exports consumed by `hal/Freedesktop/`
	 * without introducing compile-time Vala dependencies between `hal/Freedesktop/`
	 * and `hal/BSD/`.
	 */
	public class BsdKernelBootstrap : GLib.Object
	{
		[CCode (cname = "wayplank_hal_kernel_get_runtime")]
		public static IPlatformRuntime get_runtime ()
		{
			return BsdPlatformRuntime.get_default ();
		}

		[CCode (cname = "wayplank_hal_kernel_get_battery")]
		public static IBatteryProvider get_battery ()
		{
			return BsdBatteryProvider.get_default ();
		}

		[CCode (cname = "wayplank_hal_kernel_get_cpu_memory")]
		public static ICpuMemoryProvider get_cpu_memory ()
		{
			return BsdCpuMemDiskTelemetry.get_default ();
		}

		[CCode (cname = "wayplank_hal_kernel_get_audio")]
		public static IAudioProvider get_audio ()
		{
			return BsdAudioTelemetry.get_default ();
		}

		[CCode (cname = "wayplank_hal_kernel_inspect_process")]
		public static ProcessSnapshot inspect_process (int pid, bool include_children_and_fds)
		{
			return BsdProcessInspector.inspect_process (pid, include_children_and_fds);
		}

		[CCode (cname = "wayplank_hal_kernel_is_process_alive")]
		public static bool is_process_alive (int pid)
		{
			return BsdProcessInspector.is_process_alive (pid);
		}

		[CCode (cname = "wayplank_hal_kernel_scan_user_processes")]
		public static Gee.ArrayList<ProcessSnapshot> scan_user_processes ()
		{
			return BsdProcessInspector.scan_user_processes ();
		}

		[CCode (cname = "wayplank_hal_kernel_find_pid_by_app_hint")]
		public static int find_pid_by_app_hint (string app_hint, string caption_hint)
		{
			return BsdProcessInspector.find_pid_by_app_hint (app_hint, caption_hint);
		}

		[CCode (cname = "wayplank_hal_kernel_clear_process_caches")]
		public static void clear_process_caches ()
		{
			BsdProcessInspector.clear_all_caches ();
		}

		[CCode (cname = "wayplank_hal_kernel_backlight_detect_devices")]
		public static Gee.ArrayList<string> backlight_detect_devices (out string? preferred_device, out uint32 max_raw)
		{
			return BsdBacklight.detect_devices (out preferred_device, out max_raw);
		}

		[CCode (cname = "wayplank_hal_kernel_backlight_has_internal_panel")]
		public static bool backlight_has_internal_panel (string? backlight_device)
		{
			return BsdBacklight.has_internal_panel (backlight_device);
		}

		[CCode (cname = "wayplank_hal_kernel_backlight_read_raw")]
		public static int64 backlight_read_raw (string backlight_device)
		{
			return BsdBacklight.read_raw (backlight_device);
		}

		[CCode (cname = "wayplank_hal_kernel_backlight_write_raw")]
		public static bool backlight_write_raw (string backlight_device, uint32 raw_value)
		{
			return BsdBacklight.write_raw (backlight_device, raw_value);
		}

		[CCode (cname = "wayplank_hal_kernel_backlight_monitor_device")]
		public static GLib.FileMonitor? backlight_monitor_device (string backlight_device)
		{
			return BsdBacklight.monitor_device (backlight_device);
		}
	}
}
