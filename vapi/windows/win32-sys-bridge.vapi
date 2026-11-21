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

[CCode (cheader_filename = "win32-sys-bridge.h")]
namespace Win32SysBridge
{
	[CCode (cname = "Win32RemovableDriveCallback", has_target = true)]
	public delegate void RemovableDriveCallback (string drive_root, string label);

	[CCode (cname = "win32_sys_trash_get_count")]
	public static uint32 trash_get_count ();

	[CCode (cname = "win32_sys_trash_move_path")]
	public static int trash_move_path (string path);

	[CCode (cname = "win32_sys_trash_empty")]
	public static int trash_empty ();

	[CCode (cname = "win32_sys_trash_open_ui")]
	public static void trash_open_ui ();

	[CCode (cname = "win32_sys_enum_removable_drives")]
	public static void enum_removable_drives (RemovableDriveCallback cb);

	[CCode (cname = "win32_sys_eject_drive")]
	public static int eject_drive (string drive_root);

	[CCode (cname = "win32_sys_query_battery")]
	public static int query_battery (out int has_battery, out int percent, out int is_charging, out int is_full);

	[CCode (cname = "win32_sys_sample_cpu_mem")]
	public static int sample_cpu_mem (out int cpu_pct, out int ram_pct, out double ram_used_gb, out double ram_total_gb);

	[CCode (cname = "win32_sys_audio_probe")]
	public static int audio_probe (out int volume_percent, out int is_muted);

	[CCode (cname = "win32_sys_audio_set_muted")]
	public static void audio_set_muted (int muted);

	[CCode (cname = "win32_sys_audio_set_volume_percent")]
	public static void audio_set_volume_percent (int percent);

	[CCode (cname = "win32_sys_brightness_is_available")]
	public static int brightness_is_available ();

	[CCode (cname = "win32_sys_brightness_get_percent")]
	public static int brightness_get_percent ();

	[CCode (cname = "win32_sys_brightness_set_percent")]
	public static void brightness_set_percent (int percent);

	[CCode (cname = "win32_sys_network_probe")]
	public static int network_probe (out int is_connected, out string? out_type, out string? out_name, out string? out_ip);

	[CCode (cname = "win32_sys_get_user_and_host")]
	public static void get_user_and_host (out string? out_user, out string? out_host);

	[CCode (cname = "win32_sys_lock_workstation")]
	public static void lock_workstation ();

	[CCode (cname = "win32_sys_suspend")]
	public static void suspend (int hibernate);

	[CCode (cname = "win32_sys_logout")]
	public static void logout ();

	[CCode (cname = "win32_sys_query_prefer_dark")]
	public static int query_prefer_dark (out int out_prefer_dark);

	[CCode (cname = "win32_sys_send_media_key")]
	public static void send_media_key (int kind);

	[CCode (cname = "win32_sys_http_get_sync")]
	public static int http_get_sync (string url, int timeout_sec, out string? out_body);

	[CCode (cname = "win32_sys_is_autostart_enabled")]
	public static int is_autostart_enabled ();

	[CCode (cname = "win32_sys_set_autostart_enabled")]
	public static int set_autostart_enabled (int enabled);

	[CCode (cname = "win32_sys_capture_screen_rgba")]
	public static int capture_screen_rgba (out uint8* out_rgba, out int out_w, out int out_h);

	[CCode (cname = "win32_sys_get_screenshots_dir")]
	public static string? get_screenshots_dir ();

	[CCode (cname = "win32_sys_acquire_single_instance")]
	public static int acquire_single_instance (string dock_name);

	[CCode (cname = "win32_sys_replace_running_instances")]
	public static void replace_running_instances ();
}
