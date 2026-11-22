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

[CCode (cheader_filename = "bsd-kernel-bridge.h")]
namespace Plank.BsdKernelBridge
{
	[CCode (cname = "bsd_kernel_is_process_alive")]
	public bool is_process_alive (int pid);

	[CCode (cname = "bsd_kernel_get_self_exe_path")]
	public string? get_self_exe_path ();

	[CCode (cname = "bsd_kernel_list_user_pids", array_length_type = "int")]
	public int[] list_user_pids ();

	[CCode (cname = "bsd_kernel_get_proc_basic")]
	public bool get_proc_basic (int pid, out int uid, out string comm, out string exe_path, out string cwd);

	[CCode (cname = "bsd_kernel_get_proc_argv", array_length = false, array_null_terminated = true)]
	public string[]? get_proc_argv (int pid);

	[CCode (cname = "bsd_kernel_get_proc_env_hints")]
	public bool get_proc_env_hints (int pid, out string appimage, out string wineprefix);

	[CCode (cname = "bsd_kernel_get_child_pids", array_length_type = "int")]
	public int[] get_child_pids (int pid);

	[CCode (cname = "bsd_kernel_get_open_fd_paths", array_length = false, array_null_terminated = true)]
	public string[]? get_open_fd_paths (int pid);

	[CCode (cname = "bsd_kernel_read_cpu_ticks")]
	public bool read_cpu_ticks (out uint64 total, out uint64 idle);

	[CCode (cname = "bsd_kernel_read_memory")]
	public bool read_memory (out uint64 total_bytes, out uint64 avail_bytes);

	[CCode (cname = "bsd_kernel_read_disk_busy_ms")]
	public bool read_disk_busy_ms (out uint64 busy_ms);

	[CCode (cname = "bsd_kernel_read_battery")]
	public bool read_battery (out bool has_battery, out int percentage, out bool is_charging, out bool is_full, out string raw_status);

	[CCode (cname = "bsd_kernel_oss_get_volume")]
	public bool oss_get_volume (out int percent);

	[CCode (cname = "bsd_kernel_oss_set_volume")]
	public bool oss_set_volume (int percent);

	[CCode (cname = "bsd_kernel_backlight_list_devices", array_length = false, array_null_terminated = true)]
	public string[]? backlight_list_devices (out string? preferred, out uint32 max_raw);

	[CCode (cname = "bsd_kernel_backlight_lid_is_open")]
	public bool backlight_lid_is_open ();

	[CCode (cname = "bsd_kernel_backlight_read_raw")]
	public int64 backlight_read_raw (string device);

	[CCode (cname = "bsd_kernel_backlight_write_raw")]
	public bool backlight_write_raw (string device, uint32 raw_value);

	[CCode (cname = "BsdNetInterfaceCallback", has_target = true)]
	public delegate void NetInterfaceCallback (
		string iface_id,
		string display_name,
		string kind,
		int wifi_strength,
		string ip_address,
		string gateway,
		uint64 rx_bytes,
		uint64 tx_bytes
	);

	[CCode (cname = "bsd_kernel_probe_network")]
	public bool probe_network (out string conn_type, out string conn_name, out int wifi_strength, out string ip_address, out string gateway);

	[CCode (cname = "bsd_kernel_list_network_interfaces")]
	public void list_network_interfaces (NetInterfaceCallback cb);
}
