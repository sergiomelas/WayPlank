/*
 *  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
 *  Copyright (C) 2026 Sergio Melas
 *
 *  This file is part of WayPlank.
 *
 *  WayPlank is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  WayPlank is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef WAYPLANK_WIN32_APP_BRIDGE_H
#define WAYPLANK_WIN32_APP_BRIDGE_H

#include <stdint.h>
#include <glib.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Known folder IDs */
#define WIN32_FOLDER_COMMON_PROGRAMS  0
#define WIN32_FOLDER_USER_PROGRAMS    1
#define WIN32_FOLDER_USER_DESKTOP     2
#define WIN32_FOLDER_COMMON_DESKTOP   3
#define WIN32_FOLDER_RECENT           4
#define WIN32_FOLDER_PROGRAM_FILES    5
#define WIN32_FOLDER_PROGRAM_FILES_X86 6
#define WIN32_FOLDER_LOCAL_APPDATA    7
#define WIN32_FOLDER_ROAMING_APPDATA  8

typedef void (*Win32EnumProcessCallback) (
	int pid,
	const char *exe_name,
	const char *exe_path,
	void *user_data
);

/* Known folders */
char *win32_app_get_known_folder (int folder_id);

/* COM IShellLinkW .lnk resolution */
int win32_app_resolve_lnk (
	const char *lnk_path,
	char **out_target,
	char **out_args,
	char **out_workdir,
	char **out_description,
	char **out_icon_path,
	int *out_icon_index,
	char **out_aumid
);

/* Native 256x256 (SHIL_JUMBO / ExtractIconExW) icon extraction -> 32-bit RGBA */
int win32_app_extract_icon_rgba (
	const char *path_or_icon_spec,
	int desired_size,
	uint8_t **out_rgba,
	int *out_w,
	int *out_h
);
void win32_app_free_buffer (void *ptr);

/* Native launching via ShellExecuteW */
int win32_app_shell_execute (
	const char *target,
	const char *args,
	const char *working_dir
);

/* Process inspection */
int win32_app_is_process_alive (int pid);
char *win32_app_get_process_exe (int pid);
void win32_app_enum_processes (Win32EnumProcessCallback cb, void *user_data);

#ifdef __cplusplus
}
#endif

#endif /* WAYPLANK_WIN32_APP_BRIDGE_H */
