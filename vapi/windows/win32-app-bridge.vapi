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

[CCode (cheader_filename = "win32-app-bridge.h")]
namespace Win32AppBridge
{
	[CCode (cname = "WIN32_FOLDER_COMMON_PROGRAMS")]
	public const int FOLDER_COMMON_PROGRAMS;
	[CCode (cname = "WIN32_FOLDER_USER_PROGRAMS")]
	public const int FOLDER_USER_PROGRAMS;
	[CCode (cname = "WIN32_FOLDER_USER_DESKTOP")]
	public const int FOLDER_USER_DESKTOP;
	[CCode (cname = "WIN32_FOLDER_COMMON_DESKTOP")]
	public const int FOLDER_COMMON_DESKTOP;
	[CCode (cname = "WIN32_FOLDER_RECENT")]
	public const int FOLDER_RECENT;
	[CCode (cname = "WIN32_FOLDER_PROGRAM_FILES")]
	public const int FOLDER_PROGRAM_FILES;
	[CCode (cname = "WIN32_FOLDER_PROGRAM_FILES_X86")]
	public const int FOLDER_PROGRAM_FILES_X86;
	[CCode (cname = "WIN32_FOLDER_LOCAL_APPDATA")]
	public const int FOLDER_LOCAL_APPDATA;
	[CCode (cname = "WIN32_FOLDER_ROAMING_APPDATA")]
	public const int FOLDER_ROAMING_APPDATA;
	[CCode (cname = "WIN32_FOLDER_COMMON_STARTMENU")]
	public const int FOLDER_COMMON_STARTMENU;
	[CCode (cname = "WIN32_FOLDER_USER_STARTMENU")]
	public const int FOLDER_USER_STARTMENU;

	[CCode (cname = "Win32EnumProcessCallback", has_target = true)]
	public delegate void EnumProcessCallback (int pid, string exe_name, string exe_path);

	[CCode (cname = "Win32EnumIconTokenCallback", has_target = true)]
	public delegate void EnumIconTokenCallback (string token);

	[CCode (cname = "Win32EnumRecentDocCallback", has_target = true)]
	public delegate void EnumRecentDocCallback (string doc_path);

	[CCode (cname = "Win32EnumUwpAppCallback", has_target = true)]
	public delegate void EnumUwpAppCallback (string aumid, string display_name, string install_path);

	[CCode (cname = "win32_app_get_known_folder")]
	public static string? get_known_folder (int folder_id);

	[CCode (cname = "win32_app_get_file_stamp")]
	public static int get_file_stamp (string path, out int64 out_mtime_sec, out int64 out_size);

	[CCode (cname = "win32_app_is_fixed_local_drive")]
	public static int is_fixed_local_drive (string path);

	[CCode (cname = "win32_app_set_thread_low_priority")]
	public static void set_thread_low_priority ();

	[CCode (cname = "win32_app_resolve_lnk")]
	public static int resolve_lnk (
		string lnk_path,
		out string? out_target,
		out string? out_args,
		out string? out_workdir,
		out string? out_description,
		out string? out_icon_path,
		out int out_icon_index,
		out string? out_aumid
	);

	[CCode (cname = "win32_app_extract_icon_rgba")]
	public static int extract_icon_rgba (
		string path_or_icon_spec,
		int desired_size,
		out uint8* out_rgba,
		out int out_w,
		out int out_h
	);

	[CCode (cname = "win32_app_extract_stock_icon_rgba")]
	public static int extract_stock_icon_rgba (
		int stock_id,
		int desired_size,
		out uint8* out_rgba,
		out int out_w,
		out int out_h
	);

	[CCode (cname = "win32_app_extract_aumid_icon_rgba")]
	public static int extract_aumid_icon_rgba (
		string aumid,
		int desired_size,
		out uint8* out_rgba,
		out int out_w,
		out int out_h
	);

	[CCode (cname = "win32_app_enum_system_icon_stores")]
	public static void enum_system_icon_stores (EnumIconTokenCallback cb);

	[CCode (cname = "win32_app_free_buffer")]
	public static void free_buffer (void* ptr);

	[CCode (cname = "win32_app_exe_handles_ext")]
	public static int exe_handles_ext (string exe_basename, string dot_ext);

	[CCode (cname = "win32_app_enum_jump_list_recent")]
	public static int enum_jump_list_recent (string app_id, int max_items, EnumRecentDocCallback cb);

	[CCode (cname = "win32_app_shell_execute")]
	public static int shell_execute (string target, string? args, string? working_dir);

	[CCode (cname = "win32_app_activate_aumid")]
	public static int activate_aumid (string aumid, string? args);

	[CCode (cname = "win32_app_get_process_aumid")]
	public static string? get_process_aumid (int pid);

	[CCode (cname = "win32_app_find_aumid_for_package_path")]
	public static string? find_aumid_for_package_path (string exe_path);

	[CCode (cname = "win32_app_enum_uwp_apps")]
	public static void enum_uwp_apps (EnumUwpAppCallback cb);

	[CCode (cname = "win32_app_is_process_alive")]
	public static int is_process_alive (int pid);

	[CCode (cname = "win32_app_get_process_exe")]
	public static string? get_process_exe (int pid);

	[CCode (cname = "win32_app_enum_processes")]
	public static void enum_processes (EnumProcessCallback cb);
}
