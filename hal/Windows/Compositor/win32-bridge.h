/*
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

#ifndef WAYPLANK_WIN32_BRIDGE_H
#define WAYPLANK_WIN32_BRIDGE_H

#include <stdint.h>
#include <glib.h>
#include <gdk/gdk.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Action codes matching Plank.WindowAction */
#define WIN32_ACTION_ACTIVATE 0
#define WIN32_ACTION_TOGGLE   1
#define WIN32_ACTION_MINIMIZE 2
#define WIN32_ACTION_CLOSE    3

/* Edge codes matching Gtk.PositionType (LEFT=0, RIGHT=1, TOP=2, BOTTOM=3) */
#define WIN32_EDGE_LEFT   0
#define WIN32_EDGE_RIGHT  1
#define WIN32_EDGE_TOP    2
#define WIN32_EDGE_BOTTOM 3

/* Single-instance CLI IPC action codes */
#define WIN32_IPC_REFRESH     0
#define WIN32_IPC_PREFERENCES 1
#define WIN32_IPC_SHORTCUTS   2

typedef void (*Win32WindowEventCallback) (void *user_data);
typedef void (*Win32IpcActionCallback) (int action_code, void *user_data);

typedef void (*Win32EnumWindowCallback) (
	uint64_t hwnd,
	int pid,
	const char *caption,
	const char *class_name,
	const char *executable_path,
	const char *aumid,
	int x,
	int y,
	int width,
	int height,
	int minimized,
	int active,
	int maximized,
	int fullscreen,
	int is_dialog,
	int urgent,
	int current_desktop,
	void *user_data
);

/* Process lifecycle */
int win32_bridge_get_current_pid (void);
void win32_bridge_exit_immediately (int status_code);

/* Window tracking & control (Milestone W2) */
int win32_bridge_has_virtual_desktop_manager (void);
int win32_bridge_start_window_hooks (Win32WindowEventCallback cb, void *user_data);
void win32_bridge_stop_window_hooks (void);
void win32_bridge_set_resume_callback (Win32WindowEventCallback cb, void *user_data);
void win32_bridge_set_theme_callback (Win32WindowEventCallback cb, void *user_data);
void win32_bridge_set_deactivate_callback (Win32WindowEventCallback cb, void *user_data);
void win32_bridge_set_ipc_callback (Win32IpcActionCallback cb, void *user_data);
int win32_bridge_post_ipc_action (int action_code);
void win32_bridge_enum_windows (Win32EnumWindowCallback cb, void *user_data);
int win32_bridge_perform_window_action (uint64_t hwnd, int action);
int win32_bridge_toggle_show_desktop (void);

/* Live window thumbnail capture (Milestone W2) */
int win32_bridge_capture_window_rgba (
	uint64_t hwnd,
	int max_w,
	int max_h,
	uint8_t **out_rgba,
	int *out_w,
	int *out_h
);
void win32_bridge_free_buffer (void *ptr);

/* Native Win32 dock shell, click-through & AppBar struts (Milestone W3) */
void win32_bridge_configure_window (GdkWindow *gdk_window, int is_popup, int no_activate);
void win32_bridge_set_input_rects (GdkWindow *gdk_window, int mask_active, const int *rects, int n_rects);
void win32_bridge_set_appbar_strut (
	GdkWindow *gdk_window,
	int enabled,
	int edge,
	int thickness_px,
	int mon_x,
	int mon_y,
	int mon_w,
	int mon_h
);
void win32_bridge_remove_appbar_strut (GdkWindow *gdk_window);
void win32_bridge_move_topmost (GdkWindow *gdk_window, int x, int y, int w, int h, int scale_factor);
int win32_bridge_get_primary_monitor_rect (int *out_x, int *out_y, int *out_w, int *out_h);
uint32_t win32_bridge_get_topology_gen (void);

#ifdef __cplusplus
}
#endif

#endif /* WAYPLANK_WIN32_BRIDGE_H */
