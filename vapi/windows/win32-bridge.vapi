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

[CCode (cheader_filename = "win32-bridge.h")]
namespace Win32Bridge
{
	[CCode (cname = "WIN32_ACTION_ACTIVATE")]
	public const int ACTION_ACTIVATE;
	[CCode (cname = "WIN32_ACTION_TOGGLE")]
	public const int ACTION_TOGGLE;
	[CCode (cname = "WIN32_ACTION_MINIMIZE")]
	public const int ACTION_MINIMIZE;
	[CCode (cname = "WIN32_ACTION_CLOSE")]
	public const int ACTION_CLOSE;

	[CCode (cname = "WIN32_EDGE_LEFT")]
	public const int EDGE_LEFT;
	[CCode (cname = "WIN32_EDGE_RIGHT")]
	public const int EDGE_RIGHT;
	[CCode (cname = "WIN32_EDGE_TOP")]
	public const int EDGE_TOP;
	[CCode (cname = "WIN32_EDGE_BOTTOM")]
	public const int EDGE_BOTTOM;

	[CCode (cname = "WIN32_IPC_REFRESH")]
	public const int IPC_REFRESH;
	[CCode (cname = "WIN32_IPC_PREFERENCES")]
	public const int IPC_PREFERENCES;
	[CCode (cname = "WIN32_IPC_SHORTCUTS")]
	public const int IPC_SHORTCUTS;

	[CCode (cname = "Win32WindowEventCallback", has_target = true)]
	public delegate void WindowEventCallback ();

	[CCode (cname = "Win32IpcActionCallback", has_target = true)]
	public delegate void IpcActionCallback (int action_code);

	[CCode (cname = "Win32EnumWindowCallback", has_target = true)]
	public delegate void EnumWindowCallback (
		uint64 hwnd,
		int pid,
		string caption,
		string class_name,
		string executable_path,
		string aumid,
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
		int current_desktop
	);

	[CCode (cname = "win32_bridge_get_current_pid")]
	public static int get_current_pid ();

	[CCode (cname = "win32_bridge_exit_immediately")]
	public static void exit_immediately (int status_code);

	[CCode (cname = "win32_bridge_has_virtual_desktop_manager")]
	public static int has_virtual_desktop_manager ();

	[CCode (cname = "win32_bridge_start_window_hooks")]
	public static int start_window_hooks (WindowEventCallback cb);

	[CCode (cname = "win32_bridge_stop_window_hooks")]
	public static void stop_window_hooks ();

	[CCode (cname = "win32_bridge_set_resume_callback")]
	public static void set_resume_callback (WindowEventCallback? cb);

	[CCode (cname = "win32_bridge_set_theme_callback")]
	public static void set_theme_callback (WindowEventCallback? cb);

	[CCode (cname = "win32_bridge_set_deactivate_callback")]
	public static void set_deactivate_callback (WindowEventCallback? cb);

	[CCode (cname = "win32_bridge_set_ipc_callback")]
	public static void set_ipc_callback (IpcActionCallback? cb);

	[CCode (cname = "win32_bridge_post_ipc_action")]
	public static int post_ipc_action (int action_code);

	[CCode (cname = "win32_bridge_enum_windows")]
	public static void enum_windows (EnumWindowCallback cb);

	[CCode (cname = "win32_bridge_perform_window_action")]
	public static int perform_window_action (uint64 hwnd, int action);

	[CCode (cname = "win32_bridge_toggle_show_desktop")]
	public static int toggle_show_desktop ();

	[CCode (cname = "win32_bridge_capture_window_rgba")]
	public static int capture_window_rgba (
		uint64 hwnd,
		int max_w,
		int max_h,
		out uint8* out_rgba,
		out int out_w,
		out int out_h
	);

	[CCode (cname = "win32_bridge_free_buffer")]
	public static void free_buffer (void* ptr);

	[CCode (cname = "win32_bridge_configure_window")]
	public static void configure_window (Gdk.Window gdk_window, int is_popup, int no_activate);

	[CCode (cname = "win32_bridge_set_input_rects")]
	public static void set_input_rects (Gdk.Window gdk_window, int mask_active, [CCode (array_length = false)] int[]? rects, int n_rects);

	[CCode (cname = "win32_bridge_set_appbar_strut")]
	public static void set_appbar_strut (
		Gdk.Window gdk_window,
		int enabled,
		int edge,
		int thickness_px,
		int mon_x,
		int mon_y,
		int mon_w,
		int mon_h
	);

	[CCode (cname = "win32_bridge_remove_appbar_strut")]
	public static void remove_appbar_strut (Gdk.Window gdk_window);

	[CCode (cname = "win32_bridge_move_topmost")]
	public static void move_topmost (Gdk.Window gdk_window, int x, int y, int w, int h, int scale_factor);

	[CCode (cname = "win32_bridge_get_primary_monitor_rect")]
	public static int get_primary_monitor_rect (out int out_x, out int out_y, out int out_w, out int out_h);

	[CCode (cname = "win32_bridge_get_topology_gen")]
	public static uint32 get_topology_gen ();
}
