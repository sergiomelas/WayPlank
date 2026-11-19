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

#ifdef _WIN32
#ifdef DATADIR
#undef DATADIR
#endif
#ifndef COBJMACROS
#define COBJMACROS
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <windowsx.h>
#include <objbase.h>
#include <propsys.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gdk/gdkwin32.h>
#endif

#include "win32-bridge.h"

#ifdef _WIN32

#ifndef ATTACH_PARENT_PROCESS
#define ATTACH_PARENT_PROCESS ((DWORD) -1)
#endif

/* Attach stdout/stderr to the launching terminal (cmd.exe / PowerShell) when
 * invoked from a console, without ever spawning a new console window on GUI
 * launches, and without disturbing explicit `> file` / pipe redirections. */
__attribute__((constructor))
static void
win32_attach_parent_console (void)
{
	HANDLE hOut = GetStdHandle (STD_OUTPUT_HANDLE);
	HANDLE hErr = GetStdHandle (STD_ERROR_HANDLE);
	DWORD outType = (hOut != NULL && hOut != INVALID_HANDLE_VALUE) ? GetFileType (hOut) : FILE_TYPE_UNKNOWN;
	DWORD errType = (hErr != NULL && hErr != INVALID_HANDLE_VALUE) ? GetFileType (hErr) : FILE_TYPE_UNKNOWN;
	if ((outType == FILE_TYPE_UNKNOWN || errType == FILE_TYPE_UNKNOWN)
		&& AttachConsole (ATTACH_PARENT_PROCESS)) {
		if (outType == FILE_TYPE_UNKNOWN) {
			if (freopen ("CONOUT$", "w", stdout) != NULL)
				setvbuf (stdout, NULL, _IOLBF, 4096);
		}
		if (errType == FILE_TYPE_UNKNOWN) {
			if (freopen ("CONOUT$", "w", stderr) != NULL)
				setvbuf (stderr, NULL, _IOLBF, 4096);
		}
	}
}

#ifndef DWMWA_EXTENDED_FRAME_BOUNDS
#define DWMWA_EXTENDED_FRAME_BOUNDS 9
#endif

#ifndef DWMWA_CLOAKED
#define DWMWA_CLOAKED 14
#endif

#ifndef PW_RENDERFULLCONTENT
#define PW_RENDERFULLCONTENT 0x00000002
#endif

#ifndef WM_DPICHANGED
#define WM_DPICHANGED 0x02E0
#endif

#define WAYPLANK_APPBAR_CALLBACK_MSG (WM_USER + 0x410)
#define WAYPLANK_IPC_MSG             (WM_USER + 0x411)
#define WAYPLANK_LEAVE_TIMER_ID  ((UINT_PTR) 0x57504C56)
#define WAYPLANK_REVEAL_TIMER_ID ((UINT_PTR) 0x57505256)
#define WAYPLANK_PROP_STATE L"WayPlankWin32ShellState"
#define WAYPLANK_MAX_CACHED_MONITORS 16

typedef HRESULT (WINAPI *PFN_DwmGetWindowAttribute) (HWND, DWORD, PVOID, DWORD);
typedef UINT    (WINAPI *PFN_GetDpiForWindow) (HWND);
typedef HRESULT (WINAPI *PFN_GetDpiForMonitor) (HMONITOR, int, UINT *, UINT *);
typedef HRESULT (WINAPI *PFN_SHGetPropertyStoreForWindow) (HWND, REFIID, void **);

static const GUID WP_IID_IPropertyStore =
	{ 0x886D8EEB, 0x8CF2, 0x4446, { 0x8D, 0x02, 0xCD, 0xBA, 0x1D, 0xBD, 0xCF, 0x99 } };
static const PROPERTYKEY WP_PKEY_AppUserModel_ID =
	{ { 0x9F4C2855, 0x9F79, 0x4B39, { 0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3 } }, 5 };

static PFN_DwmGetWindowAttribute pfn_DwmGetWindowAttribute = NULL;
static PFN_GetDpiForWindow pfn_GetDpiForWindow = NULL;
static PFN_GetDpiForMonitor pfn_GetDpiForMonitor = NULL;
static PFN_SHGetPropertyStoreForWindow pfn_SHGetPropertyStoreForWindow = NULL;
static int g_dyn_resolved = 0;

static void
ensure_dynamic_apis (void)
{
	if (g_dyn_resolved)
		return;
	g_dyn_resolved = 1;

	HMODULE hDwm = LoadLibraryW (L"dwmapi.dll");
	if (hDwm != NULL) {
		pfn_DwmGetWindowAttribute = (PFN_DwmGetWindowAttribute)
			GetProcAddress (hDwm, "DwmGetWindowAttribute");
	}

	HMODULE hUser = GetModuleHandleW (L"user32.dll");
	if (hUser != NULL) {
		pfn_GetDpiForWindow = (PFN_GetDpiForWindow)
			GetProcAddress (hUser, "GetDpiForWindow");
	}

	HMODULE hShcore = LoadLibraryW (L"shcore.dll");
	if (hShcore != NULL) {
		pfn_GetDpiForMonitor = (PFN_GetDpiForMonitor)
			GetProcAddress (hShcore, "GetDpiForMonitor");
	}

	HMODULE hShell = GetModuleHandleW (L"shell32.dll");
	if (hShell != NULL) {
		pfn_SHGetPropertyStoreForWindow = (PFN_SHGetPropertyStoreForWindow)
			GetProcAddress (hShell, "SHGetPropertyStoreForWindow");
	}
}

/* Single Source of Truth matching GTK+ 3.24.43 gdkdisplay-win32.c:1266
 * exact integer scale factor: max(1, dpix / 96). */
static int
query_monitor_gdk_scale_uncached (HMONITOR hMon, HWND hwnd)
{
	ensure_dynamic_apis ();
	UINT dpi = 96;
	if (hMon == NULL && hwnd != NULL)
		hMon = MonitorFromWindow (hwnd, MONITOR_DEFAULTTONEAREST);

	if (pfn_GetDpiForMonitor != NULL && hMon != NULL) {
		UINT dpix = 96, dpiy = 96;
		if (pfn_GetDpiForMonitor (hMon, 0 /* MDT_EFFECTIVE_DPI */, &dpix, &dpiy) == S_OK && dpix >= 96)
			dpi = dpix;
	} else if (pfn_GetDpiForWindow != NULL && hwnd != NULL) {
		UINT wdpi = pfn_GetDpiForWindow (hwnd);
		if (wdpi >= 96)
			dpi = wdpi;
	} else {
		HDC hdc = GetDC (hwnd);
		if (hdc != NULL) {
			int gx = GetDeviceCaps (hdc, LOGPIXELSX);
			if (gx >= 96)
				dpi = (UINT) gx;
			ReleaseDC (hwnd, hdc);
		}
	}

	int scale = (int) (dpi / 96U);
	return (scale > 1) ? scale : 1;
}

typedef struct {
	HMONITOR hmon;
	int scale;
} CachedMonScale;

static int g_mon_cache_valid = 0;
static int g_cached_off_x = 0;
static int g_cached_off_y = 0;
static CachedMonScale g_cached_mons[WAYPLANK_MAX_CACHED_MONITORS];
static int g_cached_mon_count = 0;
static volatile gint g_topology_gen = 1;

static void
invalidate_monitor_cache (void)
{
	g_mon_cache_valid = 0;
	g_atomic_int_inc (&g_topology_gen);
}

typedef struct {
	int off_x;
	int off_y;
	int count;
} GdkOffsetQuery;

static BOOL CALLBACK
enum_monitor_offset_proc (HMONITOR hMon, HDC hdc, LPRECT lprc, LPARAM lParam)
{
	(void) hdc;
	(void) lprc;
	GdkOffsetQuery *q = (GdkOffsetQuery *) lParam;
	MONITORINFO mi;
	mi.cbSize = sizeof (mi);
	if (!GetMonitorInfoW (hMon, &mi))
		return TRUE;
	int scale = query_monitor_gdk_scale_uncached (hMon, NULL);
	if (g_cached_mon_count < WAYPLANK_MAX_CACHED_MONITORS) {
		g_cached_mons[g_cached_mon_count].hmon = hMon;
		g_cached_mons[g_cached_mon_count].scale = scale;
		g_cached_mon_count++;
	}
	int rx = mi.rcMonitor.left / scale;
	int ry = mi.rcMonitor.top / scale;
	int ox = -rx * scale;
	int oy = -ry * scale;
	if (q->count == 0 || ox > q->off_x) q->off_x = ox;
	if (q->count == 0 || oy > q->off_y) q->off_y = oy;
	q->count++;
	return TRUE;
}

static void
ensure_monitor_cache (void)
{
	if (g_mon_cache_valid)
		return;
	g_cached_mon_count = 0;
	GdkOffsetQuery q = { 0, 0, 0 };
	EnumDisplayMonitors (NULL, NULL, enum_monitor_offset_proc, (LPARAM) &q);
	if (q.count == 0) {
		q.off_x = -GetSystemMetrics (SM_XVIRTUALSCREEN);
		q.off_y = -GetSystemMetrics (SM_YVIRTUALSCREEN);
	}
	g_cached_off_x = q.off_x;
	g_cached_off_y = q.off_y;
	g_mon_cache_valid = 1;
}

static int
get_monitor_gdk_scale (HMONITOR hMon, HWND hwnd)
{
	ensure_monitor_cache ();
	if (hMon == NULL && hwnd != NULL)
		hMon = MonitorFromWindow (hwnd, MONITOR_DEFAULTTONEAREST);
	if (hMon != NULL) {
		for (int i = 0; i < g_cached_mon_count; i++) {
			if (g_cached_mons[i].hmon == hMon)
				return g_cached_mons[i].scale;
		}
	}
	return query_monitor_gdk_scale_uncached (hMon, hwnd);
}

/* Cached O(1) lookup of GTK+ 3.24.43 gdkmonitor-win32.c:898 _gdk_offset_x / _gdk_offset_y
 * invalidated only on WM_DISPLAYCHANGE / WM_DPICHANGED / WM_POWERBROADCAST / SPI_SETWORKAREA. */
static void
win32_query_gdk_origin_offset (int *out_off_x, int *out_off_y)
{
	ensure_monitor_cache ();
	if (out_off_x != NULL) *out_off_x = g_cached_off_x;
	if (out_off_y != NULL) *out_off_y = g_cached_off_y;
}

static char *
wide_to_utf8 (const WCHAR *wstr)
{
	if (wstr == NULL || wstr[0] == L'\0')
		return g_strdup ("");
	int needed = WideCharToMultiByte (CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
	if (needed <= 0)
		return g_strdup ("");
	char *out = (char *) g_malloc ((gsize) needed);
	WideCharToMultiByte (CP_UTF8, 0, wstr, -1, out, needed, NULL, NULL);
	return out;
}

static HWND
gdk_to_hwnd (GdkWindow *gdk_window)
{
	if (gdk_window == NULL)
		return NULL;
	return (HWND) gdk_win32_window_get_handle (gdk_window);
}

#endif /* _WIN32 */

int
win32_bridge_get_current_pid (void)
{
#ifdef _WIN32
	return (int) GetCurrentProcessId ();
#else
	return 0;
#endif
}

void
win32_bridge_exit_immediately (int status_code)
{
#ifdef _WIN32
	TerminateProcess (GetCurrentProcess (), (UINT) status_code);
#else
	(void) status_code;
#endif
}

/* ============================================================================
 * Milestone W2 — Real-Time Window Tracking (SetWinEventHook + EnumWindows)
 * ============================================================================ */

#ifdef _WIN32

static HWINEVENTHOOK g_hook_sys = NULL;
static HWINEVENTHOOK g_hook_obj = NULL;
static HWINEVENTHOOK g_hook_loc = NULL;
static Win32WindowEventCallback g_event_cb = NULL;
static void *g_event_user_data = NULL;
static volatile gint g_event_pending = 0;

static Win32WindowEventCallback g_resume_cb = NULL;
static void *g_resume_user_data = NULL;
static volatile gint g_resume_pending = 0;

static Win32IpcActionCallback g_ipc_cb = NULL;
static void *g_ipc_user_data = NULL;

static gboolean
dispatch_ipc_idle (gpointer user_data)
{
	int action_code = GPOINTER_TO_INT (user_data);
	if (g_ipc_cb != NULL)
		g_ipc_cb (action_code, g_ipc_user_data);
	return G_SOURCE_REMOVE;
}

static void
notify_ipc_async (int action_code)
{
	if (g_ipc_cb == NULL)
		return;
	g_idle_add (dispatch_ipc_idle, GINT_TO_POINTER (action_code));
}

static gboolean
dispatch_resume_idle (gpointer user_data)
{
	(void) user_data;
	g_atomic_int_set (&g_resume_pending, 0);
	if (g_resume_cb != NULL)
		g_resume_cb (g_resume_user_data);
	return G_SOURCE_REMOVE;
}

static void
notify_resume_async (void)
{
	if (g_resume_cb == NULL)
		return;
	if (g_atomic_int_compare_and_exchange (&g_resume_pending, 0, 1))
		g_idle_add (dispatch_resume_idle, NULL);
}

static gboolean
dispatch_window_event_idle (gpointer user_data)
{
	(void) user_data;
	g_atomic_int_set (&g_event_pending, 0);
	if (g_event_cb != NULL)
		g_event_cb (g_event_user_data);
	return G_SOURCE_REMOVE;
}

static void
notify_window_event_async (void)
{
	if (g_event_cb == NULL)
		return;
	if (g_atomic_int_compare_and_exchange (&g_event_pending, 0, 1))
		g_idle_add (dispatch_window_event_idle, NULL);
}

static void CALLBACK
win_event_proc (
	HWINEVENTHOOK hook,
	DWORD event,
	HWND hwnd,
	LONG idObject,
	LONG idChild,
	DWORD dwEventThread,
	DWORD dwmsEventTime
)
{
	(void) hook;
	(void) idChild;
	(void) dwEventThread;
	(void) dwmsEventTime;

	if (hwnd == NULL)
		return;
	if (idObject != OBJID_WINDOW && event != EVENT_SYSTEM_FOREGROUND)
		return;
	if (GetAncestor (hwnd, GA_ROOT) != hwnd)
		return;

	DWORD pid = 0;
	GetWindowThreadProcessId (hwnd, &pid);
	if (pid == GetCurrentProcessId ())
		return;

	if (event == EVENT_OBJECT_LOCATIONCHANGE
		|| event == EVENT_OBJECT_NAMECHANGE
		|| event == EVENT_OBJECT_CREATE
		|| event == EVENT_OBJECT_SHOW) {
		if (!IsWindowVisible (hwnd))
			return;
		LONG_PTR ex = GetWindowLongPtrW (hwnd, GWL_EXSTYLE);
		if ((ex & WS_EX_TOOLWINDOW) != 0)
			return;
	}

	notify_window_event_async ();
}

#endif /* _WIN32 */

int
win32_bridge_start_window_hooks (Win32WindowEventCallback cb, void *user_data)
{
#ifdef _WIN32
	win32_bridge_stop_window_hooks ();
	g_event_cb = cb;
	g_event_user_data = user_data;
	g_atomic_int_set (&g_event_pending, 0);

	DWORD flags = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS;
	g_hook_sys = SetWinEventHook (
		EVENT_SYSTEM_FOREGROUND,
		EVENT_SYSTEM_MINIMIZEEND,
		NULL, win_event_proc, 0, 0, flags
	);
	g_hook_obj = SetWinEventHook (
		EVENT_OBJECT_CREATE,
		EVENT_OBJECT_HIDE,
		NULL, win_event_proc, 0, 0, flags
	);
	g_hook_loc = SetWinEventHook (
		EVENT_OBJECT_LOCATIONCHANGE,
		EVENT_OBJECT_NAMECHANGE,
		NULL, win_event_proc, 0, 0, flags
	);

	return (g_hook_sys != NULL || g_hook_obj != NULL || g_hook_loc != NULL) ? 1 : 0;
#else
	(void) cb;
	(void) user_data;
	return 0;
#endif
}

void
win32_bridge_stop_window_hooks (void)
{
#ifdef _WIN32
	if (g_hook_sys != NULL) {
		UnhookWinEvent (g_hook_sys);
		g_hook_sys = NULL;
	}
	if (g_hook_obj != NULL) {
		UnhookWinEvent (g_hook_obj);
		g_hook_obj = NULL;
	}
	if (g_hook_loc != NULL) {
		UnhookWinEvent (g_hook_loc);
		g_hook_loc = NULL;
	}
	g_event_cb = NULL;
	g_event_user_data = NULL;
#endif
}

void
win32_bridge_set_resume_callback (Win32WindowEventCallback cb, void *user_data)
{
#ifdef _WIN32
	g_resume_cb = cb;
	g_resume_user_data = user_data;
	g_atomic_int_set (&g_resume_pending, 0);
#else
	(void) cb;
	(void) user_data;
#endif
}

void
win32_bridge_set_ipc_callback (Win32IpcActionCallback cb, void *user_data)
{
#ifdef _WIN32
	g_ipc_cb = cb;
	g_ipc_user_data = user_data;
#else
	(void) cb;
	(void) user_data;
#endif
}

#ifdef _WIN32
typedef struct {
	DWORD self_pid;
	HWND found;
} FindDockCtx;

static BOOL CALLBACK
find_running_dock_proc (HWND hwnd, LPARAM lParam)
{
	FindDockCtx *ctx = (FindDockCtx *) lParam;
	DWORD pid = 0;
	GetWindowThreadProcessId (hwnd, &pid);
	if (pid == 0 || pid == ctx->self_pid)
		return TRUE;
	WCHAR title[32];
	title[0] = L'\0';
	GetWindowTextW (hwnd, title, 32);
	if (wcscmp (title, L"wayplank") == 0) {
		ctx->found = hwnd;
		return FALSE;
	}
	return TRUE;
}
#endif

int
win32_bridge_post_ipc_action (int action_code)
{
#ifdef _WIN32
	FindDockCtx ctx = { GetCurrentProcessId (), NULL };
	EnumWindows (find_running_dock_proc, (LPARAM) &ctx);
	if (ctx.found != NULL) {
		PostMessageW (ctx.found, WAYPLANK_IPC_MSG, (WPARAM) action_code, 0);
		return 1;
	}
	return 0;
#else
	(void) action_code;
	return 0;
#endif
}

#ifdef _WIN32

typedef struct {
	Win32EnumWindowCallback cb;
	void *user_data;
	HWND fg_hwnd;
	DWORD self_pid;
	int off_x;
	int off_y;
	HANDLE proc_snap;
	int proc_snap_tried;
} EnumCtx;

static int
is_cloaked_window (HWND hwnd)
{
	ensure_dynamic_apis ();
	if (pfn_DwmGetWindowAttribute == NULL)
		return 0;
	DWORD cloaked = 0;
	HRESULT hr = pfn_DwmGetWindowAttribute (hwnd, DWMWA_CLOAKED, &cloaked, sizeof (cloaked));
	return (SUCCEEDED (hr) && cloaked != 0) ? 1 : 0;
}

static char *
query_window_aumid_utf8 (HWND hwnd)
{
	ensure_dynamic_apis ();
	if (pfn_SHGetPropertyStoreForWindow == NULL || hwnd == NULL)
		return g_strdup ("");

	IPropertyStore *ps = NULL;
	if (FAILED (pfn_SHGetPropertyStoreForWindow (hwnd, &WP_IID_IPropertyStore, (void **) &ps)) || ps == NULL)
		return g_strdup ("");

	PROPVARIANT pv;
	memset (&pv, 0, sizeof (pv));
	char *out = g_strdup ("");
	if (SUCCEEDED (IPropertyStore_GetValue (ps, &WP_PKEY_AppUserModel_ID, &pv))) {
		if (pv.vt == VT_LPWSTR && pv.pwszVal != NULL && pv.pwszVal[0] != L'\0') {
			g_free (out);
			out = wide_to_utf8 (pv.pwszVal);
		}
		if (pv.vt == VT_LPWSTR && pv.pwszVal != NULL)
			CoTaskMemFree (pv.pwszVal);
	}
	IPropertyStore_Release (ps);
	return out;
}

static char *
query_process_exe_from_snapshot (EnumCtx *ctx, DWORD pid)
{
	if (ctx == NULL || pid == 0)
		return g_strdup ("");
	if (!ctx->proc_snap_tried) {
		ctx->proc_snap_tried = 1;
		ctx->proc_snap = CreateToolhelp32Snapshot (TH32CS_SNAPPROCESS, 0);
	}
	if (ctx->proc_snap == INVALID_HANDLE_VALUE || ctx->proc_snap == NULL)
		return g_strdup ("");

	PROCESSENTRY32W pe;
	memset (&pe, 0, sizeof (pe));
	pe.dwSize = sizeof (pe);
	if (Process32FirstW (ctx->proc_snap, &pe)) {
		do {
			if (pe.th32ProcessID == pid && pe.szExeFile[0] != L'\0')
				return wide_to_utf8 (pe.szExeFile);
		} while (Process32NextW (ctx->proc_snap, &pe));
	}
	return g_strdup ("");
}

static char *
query_process_exe_utf8 (EnumCtx *ctx, DWORD pid)
{
	HANDLE hProc = OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (hProc == NULL)
		return query_process_exe_from_snapshot (ctx, pid);
	WCHAR buf[MAX_PATH * 4];
	DWORD size = (DWORD) (sizeof (buf) / sizeof (buf[0]));
	char *res = NULL;
	if (QueryFullProcessImageNameW (hProc, 0, buf, &size))
		res = wide_to_utf8 (buf);
	else
		res = query_process_exe_from_snapshot (ctx, pid);
	CloseHandle (hProc);
	return res;
}

typedef struct {
	DWORD host_pid;
	DWORD child_pid;
} UwpFindCtx;

static BOOL CALLBACK
find_uwp_child_proc (HWND child, LPARAM lParam)
{
	UwpFindCtx *uctx = (UwpFindCtx *) lParam;
	DWORD cpid = 0;
	GetWindowThreadProcessId (child, &cpid);
	if (cpid != 0 && cpid != uctx->host_pid) {
		uctx->child_pid = cpid;
		return FALSE;
	}
	return TRUE;
}

static DWORD
unwrap_uwp_child_pid (HWND hwnd, DWORD host_pid)
{
	UwpFindCtx uctx;
	uctx.host_pid = host_pid;
	uctx.child_pid = host_pid;
	EnumChildWindows (hwnd, find_uwp_child_proc, (LPARAM) &uctx);
	return uctx.child_pid;
}

static BOOL CALLBACK
enum_windows_proc (HWND hwnd, LPARAM lParam)
{
	EnumCtx *ctx = (EnumCtx *) lParam;

	if (!IsWindowVisible (hwnd))
		return TRUE;

	DWORD pid = 0;
	GetWindowThreadProcessId (hwnd, &pid);
	if (pid == 0 || pid == ctx->self_pid)
		return TRUE;

	LONG_PTR ex_style = GetWindowLongPtrW (hwnd, GWL_EXSTYLE);
	LONG_PTR style = GetWindowLongPtrW (hwnd, GWL_STYLE);

	if ((ex_style & WS_EX_TOOLWINDOW) != 0)
		return TRUE;
	if ((ex_style & WS_EX_NOACTIVATE) != 0 && (ex_style & WS_EX_APPWINDOW) == 0)
		return TRUE;

	HWND owner = GetWindow (hwnd, GW_OWNER);
	if (owner != NULL && (ex_style & WS_EX_APPWINDOW) == 0)
		return TRUE;

	if (is_cloaked_window (hwnd))
		return TRUE;

	WCHAR cls_w[256];
	cls_w[0] = L'\0';
	GetClassNameW (hwnd, cls_w, 256);

	if (wcscmp (cls_w, L"Shell_TrayWnd") == 0
		|| wcscmp (cls_w, L"Shell_SecondaryTrayWnd") == 0
		|| wcscmp (cls_w, L"Progman") == 0
		|| wcscmp (cls_w, L"WorkerW") == 0
		|| wcscmp (cls_w, L"Windows.UI.Core.CoreWindow") == 0) {
		return TRUE;
	}

	int title_len = GetWindowTextLengthW (hwnd);
	if (title_len <= 0)
		return TRUE;

	WCHAR *title_w = (WCHAR *) g_malloc0 ((gsize) (title_len + 2) * sizeof (WCHAR));
	GetWindowTextW (hwnd, title_w, title_len + 1);

	int minimized = IsIconic (hwnd) ? 1 : 0;
	int maximized = IsZoomed (hwnd) ? 1 : 0;
	int active = (hwnd == ctx->fg_hwnd) ? 1 : 0;
	int is_dialog = ((ex_style & WS_EX_DLGMODALFRAME) != 0 || wcscmp (cls_w, L"#32770") == 0) ? 1 : 0;

	RECT rc = { 0, 0, 0, 0 };
	if (!minimized) {
		ensure_dynamic_apis ();
		if (pfn_DwmGetWindowAttribute == NULL
			|| FAILED (pfn_DwmGetWindowAttribute (hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &rc, sizeof (rc)))) {
			GetWindowRect (hwnd, &rc);
		}
		if ((rc.right - rc.left) <= 1 || (rc.bottom - rc.top) <= 1) {
			g_free (title_w);
			return TRUE;
		}
	}

	int fullscreen = 0;
	HMONITOR hMon = NULL;
	if (!minimized) {
		hMon = MonitorFromWindow (hwnd, MONITOR_DEFAULTTONEAREST);
		if (hMon != NULL) {
			MONITORINFO mi;
			mi.cbSize = sizeof (mi);
			if (GetMonitorInfoW (hMon, &mi)) {
				if (rc.left <= mi.rcMonitor.left
					&& rc.top <= mi.rcMonitor.top
					&& rc.right >= mi.rcMonitor.right
					&& rc.bottom >= mi.rcMonitor.bottom
					&& (style & WS_CAPTION) != WS_CAPTION) {
					fullscreen = 1;
				}
			}
		}
	}

	/* Translate Win32 virtual-screen bounds into GDK logical space matching
	 * GTK+ 3.24.43 gdkmonitor-win32.c:917 (exact integer scale + _gdk_offset). */
	int scale = get_monitor_gdk_scale (hMon, hwnd);
	int lx = minimized ? 0 : (rc.left / scale) + (ctx->off_x / scale);
	int ly = minimized ? 0 : (rc.top / scale) + (ctx->off_y / scale);
	int lw = minimized ? 0 : (rc.right - rc.left) / scale;
	int lh = minimized ? 0 : (rc.bottom - rc.top) / scale;

	if (wcscmp (cls_w, L"ApplicationFrameWindow") == 0) {
		pid = unwrap_uwp_child_pid (hwnd, pid);
	}

	char *caption_utf8 = wide_to_utf8 (title_w);
	char *class_utf8 = wide_to_utf8 (cls_w);
	char *exe_utf8 = query_process_exe_utf8 (ctx, pid);
	char *aumid_utf8 = query_window_aumid_utf8 (hwnd);

	ctx->cb (
		(uint64_t) (uintptr_t) hwnd,
		(int) pid,
		caption_utf8,
		class_utf8,
		exe_utf8,
		aumid_utf8,
		lx, ly, lw, lh,
		minimized,
		active,
		maximized,
		fullscreen,
		is_dialog,
		0,
		ctx->user_data
	);

	g_free (aumid_utf8);
	g_free (caption_utf8);
	g_free (class_utf8);
	g_free (exe_utf8);
	g_free (title_w);
	return TRUE;
}

#endif /* _WIN32 */

void
win32_bridge_enum_windows (Win32EnumWindowCallback cb, void *user_data)
{
#ifdef _WIN32
	if (cb == NULL)
		return;
	EnumCtx ctx;
	memset (&ctx, 0, sizeof (ctx));
	ctx.cb = cb;
	ctx.user_data = user_data;
	ctx.fg_hwnd = GetForegroundWindow ();
	ctx.self_pid = GetCurrentProcessId ();
	ctx.proc_snap = INVALID_HANDLE_VALUE;
	win32_query_gdk_origin_offset (&ctx.off_x, &ctx.off_y);
	EnumWindows (enum_windows_proc, (LPARAM) &ctx);
	if (ctx.proc_snap != INVALID_HANDLE_VALUE && ctx.proc_snap != NULL)
		CloseHandle (ctx.proc_snap);
#else
	(void) cb;
	(void) user_data;
#endif
}

int
win32_bridge_perform_window_action (uint64_t hwnd_val, int action)
{
#ifdef _WIN32
	HWND hwnd = (HWND) (uintptr_t) hwnd_val;
	if (hwnd == NULL || !IsWindow (hwnd))
		return 0;

	if (action == WIN32_ACTION_CLOSE) {
		PostMessageW (hwnd, WM_CLOSE, 0, 0);
		return 1;
	}

	if (action == WIN32_ACTION_MINIMIZE) {
		ShowWindowAsync (hwnd, SW_MINIMIZE);
		return 1;
	}

	if (action == WIN32_ACTION_TOGGLE) {
		if (!IsIconic (hwnd) && GetForegroundWindow () == hwnd) {
			ShowWindowAsync (hwnd, SW_MINIMIZE);
			return 1;
		}
		/* Fall through to ACTIVATE */
	}

	/* ACTIVATE: restore if minimized, then attach foreground thread to focus reliably */
	if (IsIconic (hwnd))
		ShowWindowAsync (hwnd, SW_RESTORE);

	HWND fg = GetForegroundWindow ();
	DWORD cur_tid = GetCurrentThreadId ();
	DWORD fg_tid = (fg != NULL) ? GetWindowThreadProcessId (fg, NULL) : 0;
	DWORD target_tid = GetWindowThreadProcessId (hwnd, NULL);

	BOOL attached_fg = FALSE;
	BOOL attached_target = FALSE;
	if (fg_tid != 0 && fg_tid != cur_tid)
		attached_fg = AttachThreadInput (cur_tid, fg_tid, TRUE);
	if (target_tid != 0 && target_tid != cur_tid && target_tid != fg_tid)
		attached_target = AttachThreadInput (cur_tid, target_tid, TRUE);

	BringWindowToTop (hwnd);
	SetForegroundWindow (hwnd);

	if (attached_target)
		AttachThreadInput (cur_tid, target_tid, FALSE);
	if (attached_fg)
		AttachThreadInput (cur_tid, fg_tid, FALSE);

	return 1;
#else
	(void) hwnd_val;
	(void) action;
	return 0;
#endif
}

int
win32_bridge_toggle_show_desktop (void)
{
#ifdef _WIN32
	HWND tray = FindWindowW (L"Shell_TrayWnd", NULL);
	if (tray != NULL) {
		PostMessageW (tray, WM_COMMAND, (WPARAM) 407, 0);
		return 1;
	}
	return 0;
#else
	return 0;
#endif
}

/* ============================================================================
 * Milestone W2 — Live Window Thumbnail Capture (PrintWindow -> 32-bit RGBA)
 * ============================================================================ */

int
win32_bridge_capture_window_rgba (
	uint64_t hwnd_val,
	int max_w,
	int max_h,
	uint8_t **out_rgba,
	int *out_w,
	int *out_h
)
{
	if (out_rgba != NULL) *out_rgba = NULL;
	if (out_w != NULL) *out_w = 0;
	if (out_h != NULL) *out_h = 0;

#ifdef _WIN32
	HWND hwnd = (HWND) (uintptr_t) hwnd_val;
	if (hwnd == NULL || !IsWindow (hwnd) || IsIconic (hwnd))
		return 0;

	RECT rc;
	if (!GetWindowRect (hwnd, &rc))
		return 0;

	int src_w = rc.right - rc.left;
	int src_h = rc.bottom - rc.top;
	if (src_w <= 1 || src_h <= 1)
		return 0;

	int dst_w = src_w;
	int dst_h = src_h;
	if (max_w > 0 && max_h > 0 && (dst_w > max_w || dst_h > max_h)) {
		double sx = (double) max_w / (double) src_w;
		double sy = (double) max_h / (double) src_h;
		double s = (sx < sy) ? sx : sy;
		dst_w = (int) (src_w * s);
		dst_h = (int) (src_h * s);
		if (dst_w < 1) dst_w = 1;
		if (dst_h < 1) dst_h = 1;
	}

	HDC hdcScreen = GetDC (NULL);
	if (hdcScreen == NULL)
		return 0;

	HDC hdcSrc = CreateCompatibleDC (hdcScreen);
	HBITMAP hbmSrc = CreateCompatibleBitmap (hdcScreen, src_w, src_h);
	if (hdcSrc == NULL || hbmSrc == NULL) {
		if (hbmSrc) DeleteObject (hbmSrc);
		if (hdcSrc) DeleteDC (hdcSrc);
		ReleaseDC (NULL, hdcScreen);
		return 0;
	}

	HGDIOBJ oldSrc = SelectObject (hdcSrc, hbmSrc);
	BOOL ok = PrintWindow (hwnd, hdcSrc, PW_RENDERFULLCONTENT);
	if (!ok)
		ok = PrintWindow (hwnd, hdcSrc, 0);
	if (!ok) {
		HDC hdcWin = GetWindowDC (hwnd);
		if (hdcWin != NULL) {
			ok = BitBlt (hdcSrc, 0, 0, src_w, src_h, hdcWin, 0, 0, SRCCOPY);
			ReleaseDC (hwnd, hdcWin);
		}
	}

	if (!ok) {
		SelectObject (hdcSrc, oldSrc);
		DeleteObject (hbmSrc);
		DeleteDC (hdcSrc);
		ReleaseDC (NULL, hdcScreen);
		return 0;
	}

	BITMAPINFO bmi;
	memset (&bmi, 0, sizeof (bmi));
	bmi.bmiHeader.biSize = sizeof (BITMAPINFOHEADER);
	bmi.bmiHeader.biWidth = dst_w;
	bmi.bmiHeader.biHeight = -dst_h; /* Top-down DIB */
	bmi.bmiHeader.biPlanes = 1;
	bmi.bmiHeader.biBitCount = 32;
	bmi.bmiHeader.biCompression = BI_RGB;

	void *bits = NULL;
	HDC hdcDst = CreateCompatibleDC (hdcScreen);
	HBITMAP hbmDst = CreateDIBSection (hdcDst, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
	if (hdcDst == NULL || hbmDst == NULL || bits == NULL) {
		if (hbmDst) DeleteObject (hbmDst);
		if (hdcDst) DeleteDC (hdcDst);
		SelectObject (hdcSrc, oldSrc);
		DeleteObject (hbmSrc);
		DeleteDC (hdcSrc);
		ReleaseDC (NULL, hdcScreen);
		return 0;
	}

	HGDIOBJ oldDst = SelectObject (hdcDst, hbmDst);
	SetStretchBltMode (hdcDst, HALFTONE);
	SetBrushOrgEx (hdcDst, 0, 0, NULL);
	StretchBlt (hdcDst, 0, 0, dst_w, dst_h, hdcSrc, 0, 0, src_w, src_h, SRCCOPY);
	GdiFlush ();

	size_t byte_len = (size_t) dst_w * (size_t) dst_h * 4;
	uint8_t *rgba = (uint8_t *) g_malloc (byte_len);
	const uint8_t *bgra = (const uint8_t *) bits;

	/* Convert BGRA -> RGBA and enforce full opacity (alpha = 255) */
	for (size_t i = 0; i < byte_len; i += 4) {
		rgba[i + 0] = bgra[i + 2]; /* R */
		rgba[i + 1] = bgra[i + 1]; /* G */
		rgba[i + 2] = bgra[i + 0]; /* B */
		rgba[i + 3] = 255;         /* A (Pitfall #3: mandatory full opacity) */
	}

	SelectObject (hdcDst, oldDst);
	DeleteObject (hbmDst);
	DeleteDC (hdcDst);
	SelectObject (hdcSrc, oldSrc);
	DeleteObject (hbmSrc);
	DeleteDC (hdcSrc);
	ReleaseDC (NULL, hdcScreen);

	if (out_rgba != NULL) *out_rgba = rgba; else g_free (rgba);
	if (out_w != NULL) *out_w = dst_w;
	if (out_h != NULL) *out_h = dst_h;
	return 1;
#else
	(void) hwnd_val;
	(void) max_w;
	(void) max_h;
	return 0;
#endif
}

void
win32_bridge_free_buffer (void *ptr)
{
	if (ptr != NULL)
		g_free (ptr);
}

/* ============================================================================
 * Milestone W3 — Native Dock Shell, WM_NCHITTEST Click-Through & AppBar Struts
 * ============================================================================ */

#ifdef _WIN32

typedef struct {
	WNDPROC orig_proc;
	GdkWindow *gdk_window;
	int mask_active;
	int *rects;       /* [x, y, w, h, ...] in client physical pixels */
	int n_rects;
	int no_activate;
	int pointer_inside;
	int leave_timer_active;
	int reveal_timer_active;
	int appbar_registered;
	int last_edge;
	int last_thickness;
	int last_vx;
	int last_vy;
	int last_vw;
	int last_vh;
} Win32ShellState;

static Win32ShellState *
get_or_create_shell_state (HWND hwnd)
{
	Win32ShellState *st = (Win32ShellState *) GetPropW (hwnd, WAYPLANK_PROP_STATE);
	if (st != NULL)
		return st;
	st = (Win32ShellState *) g_malloc0 (sizeof (Win32ShellState));
	SetPropW (hwnd, WAYPLANK_PROP_STATE, (HANDLE) st);
	return st;
}

static int
point_in_shell_rects (const Win32ShellState *st, HWND hwnd, POINT screen_pt)
{
	if (st == NULL)
		return 0;
	POINT pt = screen_pt;
	ScreenToClient (hwnd, &pt);
	if (!st->mask_active) {
		RECT cr;
		if (!GetClientRect (hwnd, &cr))
			return 0;
		return PtInRect (&cr, pt) ? 1 : 0;
	}
	if (st->n_rects <= 0 || st->rects == NULL)
		return 0;
	for (int i = 0; i < st->n_rects; i++) {
		int rx = st->rects[i * 4 + 0];
		int ry = st->rects[i * 4 + 1];
		int rw = st->rects[i * 4 + 2];
		int rh = st->rects[i * 4 + 3];
		if (pt.x >= rx && pt.x < (rx + rw) && pt.y >= ry && pt.y < (ry + rh))
			return 1;
	}
	return 0;
}

/* Synthesize a real GDK_ENTER_NOTIFY or GDK_LEAVE_NOTIFY on our DockWindow.
 * Needed on Win32 WS_EX_LAYERED (ULW_ALPHA) surfaces for two kernel behaviors:
 *  1. GTK+ 3.24.43 gdkevents-win32.c:2836 swallows WM_MOUSELEAVE whenever
 *     WindowFromPoint(pt) still hits our HWND (transparent zoom headroom).
 *  2. Windows win32k never delivers WM_NCHITTEST / WM_MOUSEMOVE to alpha==0
 *     pixels, so a hidden dock's 10px edge strip cannot wake up natively. */
static void
emit_synthetic_gdk_crossing (Win32ShellState *st, GdkEventType type, double x, double y, double x_root, double y_root)
{
	if (st == NULL || st->gdk_window == NULL || gdk_window_is_destroyed (st->gdk_window))
		return;
	GdkEvent *ev = gdk_event_new (type);
	ev->crossing.window = g_object_ref (st->gdk_window);
	ev->crossing.send_event = FALSE;
	ev->crossing.subwindow = NULL;
	ev->crossing.time = GDK_CURRENT_TIME;
	ev->crossing.x = x;
	ev->crossing.y = y;
	ev->crossing.x_root = x_root;
	ev->crossing.y_root = y_root;
	ev->crossing.mode = GDK_CROSSING_NORMAL;
	ev->crossing.detail = GDK_NOTIFY_NONLINEAR;
	ev->crossing.focus = FALSE;
	ev->crossing.state = 0;
	GdkDisplay *display = gdk_window_get_display (st->gdk_window);
	if (display != NULL) {
		GdkSeat *seat = gdk_display_get_default_seat (display);
		GdkDevice *ptr = (seat != NULL) ? gdk_seat_get_pointer (seat) : NULL;
		if (ptr != NULL)
			gdk_event_set_device (ev, ptr);
	}
	gdk_event_put (ev);
	gdk_event_free (ev);
}

static void
emit_synthetic_gdk_leave (Win32ShellState *st)
{
	emit_synthetic_gdk_crossing (st, GDK_LEAVE_NOTIFY, -1.0, -1.0, -1.0, -1.0);
}

static void
emit_synthetic_gdk_enter (Win32ShellState *st, HWND hwnd, POINT screen_pt)
{
	if (st == NULL || st->gdk_window == NULL || gdk_window_is_destroyed (st->gdk_window))
		return;
	POINT client_pt = screen_pt;
	ScreenToClient (hwnd, &client_pt);
	int sf = gdk_window_get_scale_factor (st->gdk_window);
	if (sf < 1) sf = 1;
	int off_x = 0, off_y = 0;
	win32_query_gdk_origin_offset (&off_x, &off_y);
	double lx = (double) client_pt.x / (double) sf;
	double ly = (double) client_pt.y / (double) sf;
	double rx = (double) (screen_pt.x + off_x) / (double) sf;
	double ry = (double) (screen_pt.y + off_y) / (double) sf;
	emit_synthetic_gdk_crossing (st, GDK_ENTER_NOTIFY, lx, ly, rx, ry);
}

static LRESULT CALLBACK
wayplank_wnd_proc (HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	Win32ShellState *st = (Win32ShellState *) GetPropW (hwnd, WAYPLANK_PROP_STATE);
	WNDPROC orig = (st != NULL && st->orig_proc != NULL) ? st->orig_proc : DefWindowProcW;

	if (msg == WAYPLANK_IPC_MSG) {
		notify_ipc_async ((int) wParam);
		return 0;
	}

	if (msg == WM_MOUSEACTIVATE && st != NULL && st->no_activate) {
		return MA_NOACTIVATE;
	}

	if (msg == WM_NCHITTEST && st != NULL && st->mask_active) {
		POINT pt;
		pt.x = GET_X_LPARAM (lParam);
		pt.y = GET_Y_LPARAM (lParam);
		if (!point_in_shell_rects (st, hwnd, pt))
			return HTTRANSPARENT;
	}

	if (msg == WM_MOUSEMOVE && st != NULL && st->mask_active) {
		st->pointer_inside = 1;
		if (!st->leave_timer_active) {
			if (SetTimer (hwnd, WAYPLANK_LEAVE_TIMER_ID, 150, NULL) != 0)
				st->leave_timer_active = 1;
		}
	}

	if (msg == WM_TIMER && wParam == WAYPLANK_LEAVE_TIMER_ID) {
		if (st != NULL && st->pointer_inside) {
			POINT pt;
			int still_in = 0;
			if (IsWindowVisible (hwnd) && GetCursorPos (&pt)) {
				if (point_in_shell_rects (st, hwnd, pt))
					still_in = 1;
			}
			if (!still_in) {
				st->pointer_inside = 0;
				if (st->leave_timer_active) {
					KillTimer (hwnd, WAYPLANK_LEAVE_TIMER_ID);
					st->leave_timer_active = 0;
				}
				emit_synthetic_gdk_leave (st);
			}
		} else if (st != NULL && st->leave_timer_active) {
			KillTimer (hwnd, WAYPLANK_LEAVE_TIMER_ID);
			st->leave_timer_active = 0;
		}
		return 0;
	}

	if (msg == WM_TIMER && wParam == WAYPLANK_REVEAL_TIMER_ID) {
		if (st != NULL && st->mask_active && st->n_rects > 0) {
			POINT pt;
			if (IsWindowVisible (hwnd) && GetCursorPos (&pt)) {
				int in_strip = point_in_shell_rects (st, hwnd, pt);
				if (in_strip && !st->pointer_inside) {
					st->pointer_inside = 1;
					if (!st->leave_timer_active) {
						if (SetTimer (hwnd, WAYPLANK_LEAVE_TIMER_ID, 150, NULL) != 0)
							st->leave_timer_active = 1;
					}
					emit_synthetic_gdk_enter (st, hwnd, pt);
				}
			}
		} else if (st != NULL && st->reveal_timer_active) {
			KillTimer (hwnd, WAYPLANK_REVEAL_TIMER_ID);
			st->reveal_timer_active = 0;
		}
		return 0;
	}

	if (msg == WM_MOUSELEAVE && st != NULL && st->mask_active) {
		LRESULT res = CallWindowProcW (orig, hwnd, msg, wParam, lParam);
		if (st->pointer_inside) {
			POINT pt;
			if (GetCursorPos (&pt)) {
				if (!point_in_shell_rects (st, hwnd, pt)) {
					HWND under = WindowFromPoint (pt);
					st->pointer_inside = 0;
					if (st->leave_timer_active) {
						KillTimer (hwnd, WAYPLANK_LEAVE_TIMER_ID);
						st->leave_timer_active = 0;
					}
					/* If WindowFromPoint still hit our HWND (transparent headroom),
					 * GTK3 swallowed WM_MOUSELEAVE without emitting GDK_LEAVE_NOTIFY. */
					if (under == hwnd)
						emit_synthetic_gdk_leave (st);
				}
			}
		}
		return res;
	}

	if (msg == WAYPLANK_APPBAR_CALLBACK_MSG) {
		if (wParam == ABN_FULLSCREENAPP) {
			/* Fullscreen app entered/left: notify window backend to re-evaluate hide */
			notify_window_event_async ();
		}
		return 0;
	}

	if (msg == WM_DPICHANGED || (msg == WM_SETTINGCHANGE && wParam == SPI_SETWORKAREA)) {
		invalidate_monitor_cache ();
	}

	if ((msg == WM_POWERBROADCAST && (wParam == PBT_APMRESUMEAUTOMATIC || wParam == PBT_APMRESUMESUSPEND))
		|| msg == WM_DISPLAYCHANGE) {
		invalidate_monitor_cache ();
		if (st != NULL) {
			st->last_thickness = -1;
			if (!st->no_activate) {
				SetWindowPos (hwnd, HWND_TOPMOST, 0, 0, 0, 0,
					SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
			}
		}
		notify_window_event_async ();
		notify_resume_async ();
	}

	if (msg == WM_NCDESTROY && st != NULL) {
		if (st->leave_timer_active) {
			KillTimer (hwnd, WAYPLANK_LEAVE_TIMER_ID);
			st->leave_timer_active = 0;
		}
		if (st->reveal_timer_active) {
			KillTimer (hwnd, WAYPLANK_REVEAL_TIMER_ID);
			st->reveal_timer_active = 0;
		}
		st->gdk_window = NULL;
		if (st->appbar_registered) {
			APPBARDATA abd;
			memset (&abd, 0, sizeof (abd));
			abd.cbSize = sizeof (abd);
			abd.hWnd = hwnd;
			SHAppBarMessage (ABM_REMOVE, &abd);
			st->appbar_registered = 0;
		}
		SetWindowLongPtrW (hwnd, GWLP_WNDPROC, (LONG_PTR) orig);
		RemovePropW (hwnd, WAYPLANK_PROP_STATE);
		g_free (st->rects);
		g_free (st);
		return CallWindowProcW (orig, hwnd, msg, wParam, lParam);
	}

	return CallWindowProcW (orig, hwnd, msg, wParam, lParam);
}

#endif /* _WIN32 */

void
win32_bridge_configure_window (GdkWindow *gdk_window, int is_popup, int no_activate)
{
#ifdef _WIN32
	HWND hwnd = gdk_to_hwnd (gdk_window);
	if (hwnd == NULL || !IsWindow (hwnd))
		return;

	LONG_PTR ex = GetWindowLongPtrW (hwnd, GWL_EXSTYLE);
	LONG_PTR target_ex = (ex | WS_EX_TOOLWINDOW | WS_EX_TOPMOST) & ~WS_EX_APPWINDOW;
	if (no_activate)
		target_ex |= WS_EX_NOACTIVATE;
	else
		target_ex &= ~WS_EX_NOACTIVATE;

	Win32ShellState *st = get_or_create_shell_state (hwnd);
	st->gdk_window = gdk_window;
	st->no_activate = no_activate ? 1 : 0;
	int need_subclass = (st->orig_proc == NULL);
	if (need_subclass) {
		WNDPROC prev = (WNDPROC) SetWindowLongPtrW (hwnd, GWLP_WNDPROC, (LONG_PTR) wayplank_wnd_proc);
		if (prev != NULL && prev != wayplank_wnd_proc)
			st->orig_proc = prev;
	}

	if (target_ex != ex)
		SetWindowLongPtrW (hwnd, GWL_EXSTYLE, target_ex);

	UINT swp_flags = SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_NOACTIVATE;
	if (is_popup)
		swp_flags |= SWP_NOOWNERZORDER;
	SetWindowPos (hwnd, HWND_TOPMOST, 0, 0, 0, 0, swp_flags);
#else
	(void) gdk_window;
	(void) is_popup;
	(void) no_activate;
#endif
}

void
win32_bridge_set_input_rects (GdkWindow *gdk_window, int mask_active, const int *rects, int n_rects)
{
#ifdef _WIN32
	HWND hwnd = gdk_to_hwnd (gdk_window);
	if (hwnd == NULL || !IsWindow (hwnd))
		return;

	Win32ShellState *st = get_or_create_shell_state (hwnd);
	st->gdk_window = gdk_window;
	if (st->orig_proc == NULL) {
		WNDPROC prev = (WNDPROC) SetWindowLongPtrW (hwnd, GWLP_WNDPROC, (LONG_PTR) wayplank_wnd_proc);
		if (prev != NULL && prev != wayplank_wnd_proc)
			st->orig_proc = prev;
	}

	g_free (st->rects);
	st->rects = NULL;
	st->n_rects = 0;
	st->mask_active = mask_active ? 1 : 0;

	if (mask_active && rects != NULL && n_rects > 0) {
		size_t count = (size_t) n_rects * 4;
		st->rects = (int *) g_malloc (count * sizeof (int));
		memcpy (st->rects, rects, count * sizeof (int));
		st->n_rects = n_rects;
	}

	/* On WS_EX_LAYERED (ULW_ALPHA), alpha==0 pixels never receive WM_MOUSEMOVE.
	 * When DockWindow shrinks its input mask to the thin 10px hidden edge strip,
	 * arm a lightweight 50 ms edge-reveal timer; disarm it when unhidden or
	 * fullscreen-inhibited (n_rects == 0). */
	int is_edge_strip = 0;
	if (st->mask_active && st->n_rects == 1 && st->rects != NULL) {
		int sf = gdk_window_get_scale_factor (gdk_window);
		if (sf < 1) sf = 1;
		int edge_thresh = 10 * sf * sf + 2;
		int rw = st->rects[2];
		int rh = st->rects[3];
		if ((rw > 0 && rw <= edge_thresh) || (rh > 0 && rh <= edge_thresh))
			is_edge_strip = 1;
	}

	if (is_edge_strip) {
		if (!st->reveal_timer_active) {
			if (SetTimer (hwnd, WAYPLANK_REVEAL_TIMER_ID, 50, NULL) != 0)
				st->reveal_timer_active = 1;
		}
	} else {
		if (st->reveal_timer_active) {
			KillTimer (hwnd, WAYPLANK_REVEAL_TIMER_ID);
			st->reveal_timer_active = 0;
		}
		if (st->mask_active && st->n_rects == 0) {
			st->pointer_inside = 0;
			if (st->leave_timer_active) {
				KillTimer (hwnd, WAYPLANK_LEAVE_TIMER_ID);
				st->leave_timer_active = 0;
			}
		}
	}
#else
	(void) gdk_window;
	(void) mask_active;
	(void) rects;
	(void) n_rects;
#endif
}

void
win32_bridge_set_appbar_strut (
	GdkWindow *gdk_window,
	int enabled,
	int edge,
	int thickness_px,
	int mon_x,
	int mon_y,
	int mon_w,
	int mon_h
)
{
#ifdef _WIN32
	HWND hwnd = gdk_to_hwnd (gdk_window);
	if (hwnd == NULL || !IsWindow (hwnd))
		return;

	Win32ShellState *st = get_or_create_shell_state (hwnd);
	APPBARDATA abd;
	memset (&abd, 0, sizeof (abd));
	abd.cbSize = sizeof (abd);
	abd.hWnd = hwnd;
	abd.uCallbackMessage = WAYPLANK_APPBAR_CALLBACK_MSG;

	if (!enabled || thickness_px <= 0) {
		if (st->appbar_registered) {
			SHAppBarMessage (ABM_REMOVE, &abd);
			st->appbar_registered = 0;
			st->last_edge = -1;
			st->last_thickness = 0;
		}
		return;
	}

	int off_x = 0, off_y = 0;
	win32_query_gdk_origin_offset (&off_x, &off_y);
	int vx = mon_x - off_x;
	int vy = mon_y - off_y;

	if (st->appbar_registered && st->last_edge == edge && st->last_thickness == thickness_px
		&& st->last_vx == vx && st->last_vy == vy && st->last_vw == mon_w && st->last_vh == mon_h)
		return;

	if (!st->appbar_registered) {
		SHAppBarMessage (ABM_NEW, &abd);
		st->appbar_registered = 1;
	}

	switch (edge) {
	case WIN32_EDGE_LEFT:
		abd.uEdge = ABE_LEFT;
		abd.rc.left = vx;
		abd.rc.top = vy;
		abd.rc.right = vx + thickness_px;
		abd.rc.bottom = vy + mon_h;
		break;
	case WIN32_EDGE_RIGHT:
		abd.uEdge = ABE_RIGHT;
		abd.rc.left = vx + mon_w - thickness_px;
		abd.rc.top = vy;
		abd.rc.right = vx + mon_w;
		abd.rc.bottom = vy + mon_h;
		break;
	case WIN32_EDGE_TOP:
		abd.uEdge = ABE_TOP;
		abd.rc.left = vx;
		abd.rc.top = vy;
		abd.rc.right = vx + mon_w;
		abd.rc.bottom = vy + thickness_px;
		break;
	default:
	case WIN32_EDGE_BOTTOM:
		abd.uEdge = ABE_BOTTOM;
		abd.rc.left = vx;
		abd.rc.top = vy + mon_h - thickness_px;
		abd.rc.right = vx + mon_w;
		abd.rc.bottom = vy + mon_h;
		break;
	}

	SHAppBarMessage (ABM_QUERYPOS, &abd);
	switch (abd.uEdge) {
	case ABE_LEFT:   abd.rc.right = abd.rc.left + thickness_px; break;
	case ABE_RIGHT:  abd.rc.left = abd.rc.right - thickness_px; break;
	case ABE_TOP:    abd.rc.bottom = abd.rc.top + thickness_px; break;
	case ABE_BOTTOM: abd.rc.top = abd.rc.bottom - thickness_px; break;
	}
	SHAppBarMessage (ABM_SETPOS, &abd);

	st->last_edge = edge;
	st->last_thickness = thickness_px;
	st->last_vx = vx;
	st->last_vy = vy;
	st->last_vw = mon_w;
	st->last_vh = mon_h;
#else
	(void) gdk_window;
	(void) enabled;
	(void) edge;
	(void) thickness_px;
	(void) mon_x;
	(void) mon_y;
	(void) mon_w;
	(void) mon_h;
#endif
}

void
win32_bridge_remove_appbar_strut (GdkWindow *gdk_window)
{
	win32_bridge_set_appbar_strut (gdk_window, 0, 0, 0, 0, 0, 0, 0);
}

void
win32_bridge_move_topmost (GdkWindow *gdk_window, int x, int y, int w, int h, int scale_factor)
{
#ifdef _WIN32
	HWND hwnd = gdk_to_hwnd (gdk_window);
	if (hwnd == NULL || !IsWindow (hwnd))
		return;
	int sf = (scale_factor > 0) ? scale_factor : 1;
	int off_x = 0, off_y = 0;
	win32_query_gdk_origin_offset (&off_x, &off_y);
	int vx = x * sf - off_x;
	int vy = y * sf - off_y;
	UINT flags = SWP_NOACTIVATE | SWP_NOOWNERZORDER;
	if (w <= 0 || h <= 0)
		flags |= SWP_NOSIZE;
	SetWindowPos (hwnd, HWND_TOPMOST, vx, vy, w * sf, h * sf, flags);
#else
	(void) gdk_window;
	(void) x;
	(void) y;
	(void) w;
	(void) h;
	(void) scale_factor;
#endif
}

int
win32_bridge_get_primary_monitor_rect (int *out_x, int *out_y, int *out_w, int *out_h)
{
#ifdef _WIN32
	POINT pt = { 0, 0 };
	HMONITOR hMon = MonitorFromPoint (pt, MONITOR_DEFAULTTOPRIMARY);
	if (hMon == NULL)
		return 0;
	MONITORINFO mi;
	mi.cbSize = sizeof (mi);
	if (!GetMonitorInfoW (hMon, &mi))
		return 0;
	int off_x = 0, off_y = 0;
	win32_query_gdk_origin_offset (&off_x, &off_y);
	int scale = get_monitor_gdk_scale (hMon, NULL);
	if (out_x != NULL) *out_x = (mi.rcMonitor.left / scale) + (off_x / scale);
	if (out_y != NULL) *out_y = (mi.rcMonitor.top / scale) + (off_y / scale);
	if (out_w != NULL) *out_w = (mi.rcMonitor.right - mi.rcMonitor.left) / scale;
	if (out_h != NULL) *out_h = (mi.rcMonitor.bottom - mi.rcMonitor.top) / scale;
	return 1;
#else
	if (out_x != NULL) *out_x = 0;
	if (out_y != NULL) *out_y = 0;
	if (out_w != NULL) *out_w = 0;
	if (out_h != NULL) *out_h = 0;
	return 0;
#endif
}

uint32_t
win32_bridge_get_topology_gen (void)
{
#ifdef _WIN32
	return (uint32_t) g_atomic_int_get (&g_topology_gen);
#else
	return 1U;
#endif
}

#ifdef _WIN32
/* Compatibility forwarders for gtk3 objects compiled against proxy-libintl headers */
extern char *libintl_bindtextdomain (const char *domainname, const char *dirname);
extern char *libintl_bind_textdomain_codeset (const char *domainname, const char *codeset);
extern char *libintl_dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n);

char *
g_libintl_bindtextdomain (const char *domainname, const char *dirname)
{
	return libintl_bindtextdomain (domainname, dirname);
}

char *
g_libintl_bind_textdomain_codeset (const char *domainname, const char *codeset)
{
	return libintl_bind_textdomain_codeset (domainname, codeset);
}

char *
g_libintl_dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n)
{
	return libintl_dngettext (domainname, msgid1, msgid2, n);
}
#endif
