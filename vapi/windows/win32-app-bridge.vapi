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

	[CCode (cname = "Win32EnumProcessCallback", has_target = true)]
	public delegate void EnumProcessCallback (int pid, string exe_name, string exe_path);

	[CCode (cname = "win32_app_get_known_folder")]
	public static string? get_known_folder (int folder_id);

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

	[CCode (cname = "win32_app_free_buffer")]
	public static void free_buffer (void* ptr);

	[CCode (cname = "win32_app_shell_execute")]
	public static int shell_execute (string target, string? args, string? working_dir);

	[CCode (cname = "win32_app_is_process_alive")]
	public static int is_process_alive (int pid);

	[CCode (cname = "win32_app_get_process_exe")]
	public static string? get_process_exe (int pid);

	[CCode (cname = "win32_app_enum_processes")]
	public static void enum_processes (EnumProcessCallback cb);
}
