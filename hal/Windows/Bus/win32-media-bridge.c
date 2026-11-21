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
#include <objbase.h>
#include <mmdeviceapi.h>
#include <audiopolicy.h>
#include <endpointvolume.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#endif

#include "win32-media-bridge.h"

#ifdef _WIN32

/* Minimal zero-dependency WinRT / COM ABI definitions (loaded dynamically via combase.dll) */
typedef void *WP_HSTRING;

typedef HRESULT (WINAPI *PFN_RoInitialize) (int initType);
typedef void (WINAPI *PFN_RoUninitialize) (void);
typedef HRESULT (WINAPI *PFN_RoGetActivationFactory) (WP_HSTRING activatableClassId, REFIID iid, void **factory);
typedef HRESULT (WINAPI *PFN_WindowsCreateString) (LPCWSTR sourceString, UINT32 length, WP_HSTRING *string);
typedef HRESULT (WINAPI *PFN_WindowsDeleteString) (WP_HSTRING string);
typedef LPCWSTR (WINAPI *PFN_WindowsGetStringRawBuffer) (WP_HSTRING string, UINT32 *length);

static const GUID WP_IID_IGSMTCManagerStatics =
	{ 0x2050C4EE, 0x11A0, 0x57DE, { 0xAE, 0xD7, 0xC9, 0x7C, 0x70, 0x33, 0x82, 0x45 } };
static const GUID WP_IID_IAsyncInfo =
	{ 0x00000036, 0x0000, 0x0000, { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };

static const GUID WP_CLSID_MMDeviceEnumerator =
	{ 0xBCDE0395, 0xE52F, 0x467C, { 0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E } };
static const GUID WP_IID_IMMDeviceEnumerator =
	{ 0xA95664D2, 0x9614, 0x4F35, { 0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6 } };
static const GUID WP_IID_IAudioSessionManager2 =
	{ 0x77AA99A0, 0x1BD6, 0x484F, { 0x8B, 0xC7, 0x2C, 0x65, 0x4C, 0x9A, 0x9B, 0x6F } };
static const GUID WP_IID_IAudioSessionControl2 =
	{ 0xBFB7FF88, 0x7239, 0x4FC9, { 0x8F, 0xA2, 0x07, 0xC9, 0x50, 0xBE, 0x9C, 0x6D } };
static const GUID WP_IID_IAudioMeterInformation =
	{ 0xC02216F6, 0x8C67, 0x4B5B, { 0x9D, 0x00, 0xD0, 0x08, 0xE7, 0x3E, 0x00, 0x64 } };

typedef struct WP_IInspectable {
	void **lpVtbl;
} WP_IInspectable;

typedef HRESULT (STDMETHODCALLTYPE *PFN_QI) (void *This, REFIID riid, void **ppv);
typedef ULONG (STDMETHODCALLTYPE *PFN_Release) (void *This);
typedef HRESULT (STDMETHODCALLTYPE *PFN_GetPtr) (void *This, void **out_ptr);
typedef HRESULT (STDMETHODCALLTYPE *PFN_GetHStr) (void *This, WP_HSTRING *out_str);
typedef HRESULT (STDMETHODCALLTYPE *PFN_GetInt32) (void *This, int32_t *out_val);
typedef HRESULT (STDMETHODCALLTYPE *PFN_GetUInt32) (void *This, uint32_t *out_val);
typedef HRESULT (STDMETHODCALLTYPE *PFN_GetAt) (void *This, uint32_t index, void **out_ptr);
typedef HRESULT (STDMETHODCALLTYPE *PFN_GetBool) (void *This, uint8_t *out_val);
typedef HRESULT (STDMETHODCALLTYPE *PFN_GetPeakValue) (void *This, float *pfPeak);

static HMODULE g_combase = NULL;
static PFN_RoInitialize pfn_RoInitialize = NULL;
static PFN_RoUninitialize pfn_RoUninitialize = NULL;
static PFN_RoGetActivationFactory pfn_RoGetActivationFactory = NULL;
static PFN_WindowsCreateString pfn_WindowsCreateString = NULL;
static PFN_WindowsDeleteString pfn_WindowsDeleteString = NULL;
static PFN_WindowsGetStringRawBuffer pfn_WindowsGetStringRawBuffer = NULL;
static int g_combase_checked = 0;

static int
ensure_combase_loaded (void)
{
	if (!g_combase_checked) {
		g_combase_checked = 1;
		g_combase = LoadLibraryW (L"combase.dll");
		if (g_combase != NULL) {
			pfn_RoInitialize = (PFN_RoInitialize) GetProcAddress (g_combase, "RoInitialize");
			pfn_RoUninitialize = (PFN_RoUninitialize) GetProcAddress (g_combase, "RoUninitialize");
			pfn_RoGetActivationFactory = (PFN_RoGetActivationFactory) GetProcAddress (g_combase, "RoGetActivationFactory");
			pfn_WindowsCreateString = (PFN_WindowsCreateString) GetProcAddress (g_combase, "WindowsCreateString");
			pfn_WindowsDeleteString = (PFN_WindowsDeleteString) GetProcAddress (g_combase, "WindowsDeleteString");
			pfn_WindowsGetStringRawBuffer = (PFN_WindowsGetStringRawBuffer) GetProcAddress (g_combase, "WindowsGetStringRawBuffer");
		}
	}
	return (pfn_RoGetActivationFactory != NULL
		&& pfn_WindowsCreateString != NULL
		&& pfn_WindowsDeleteString != NULL
		&& pfn_WindowsGetStringRawBuffer != NULL);
}

/* Returns: 0 = already initialized / no-op, 1 = RoInitialize (call RoUninitialize),
 * 2 = CoInitializeEx (call CoUninitialize). Prevents WinRT/COM apartment leaks on
 * short-lived polling worker threads. */
static int
ensure_thread_com_init (void)
{
	if (ensure_combase_loaded () && pfn_RoInitialize != NULL) {
		HRESULT hr = pfn_RoInitialize (1 /* RO_INIT_MULTITHREADED */);
		if (SUCCEEDED (hr))
			return 1;
		if (hr == RPC_E_CHANGED_MODE)
			return 0;
	}
	HRESULT hr = CoInitializeEx (NULL, COINIT_MULTITHREADED);
	return SUCCEEDED (hr) ? 2 : 0;
}

static void
uninit_thread_com (int init_kind)
{
	if (init_kind == 1 && pfn_RoUninitialize != NULL)
		pfn_RoUninitialize ();
	else if (init_kind == 2)
		CoUninitialize ();
}

static void
com_release (void *obj)
{
	if (obj == NULL)
		return;
	WP_IInspectable *ins = (WP_IInspectable *) obj;
	((PFN_Release) ins->lpVtbl[2]) (obj);
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

static char *
hstring_to_utf8 (WP_HSTRING hs)
{
	if (hs == NULL || pfn_WindowsGetStringRawBuffer == NULL)
		return g_strdup ("");
	UINT32 len = 0;
	LPCWSTR raw = pfn_WindowsGetStringRawBuffer (hs, &len);
	if (raw == NULL || len == 0)
		return g_strdup ("");
	return wide_to_utf8 (raw);
}

static int
wait_async_op (void *async_op, int timeout_ms)
{
	if (async_op == NULL)
		return 0;
	WP_IInspectable *op = (WP_IInspectable *) async_op;
	void *async_info = NULL;
	HRESULT hr = ((PFN_QI) op->lpVtbl[0]) (async_op, &WP_IID_IAsyncInfo, &async_info);
	if (FAILED (hr) || async_info == NULL)
		return 0;

	WP_IInspectable *ai = (WP_IInspectable *) async_info;
	int waited = 0;
	int32_t st = 0;
	while (waited < timeout_ms) {
		st = 0;
		hr = ((PFN_GetInt32) ai->lpVtbl[7]) (async_info, &st);
		if (FAILED (hr)) {
			com_release (async_info);
			return 0;
		}
		if (st != 0) /* 0=Started, 1=Completed, 2=Canceled, 3=Error */
			break;
		Sleep (5);
		waited += 5;
	}
	com_release (async_info);
	return (st == 1) ? 1 : 0;
}

static void *
acquire_gsmtc_manager (void)
{
	if (!ensure_combase_loaded ())
		return NULL;

	static const WCHAR kClassName[] = L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager";
	WP_HSTRING hClass = NULL;
	if (FAILED (pfn_WindowsCreateString (kClassName, (UINT32) wcslen (kClassName), &hClass)) || hClass == NULL)
		return NULL;

	void *statics = NULL;
	HRESULT hr = pfn_RoGetActivationFactory (hClass, &WP_IID_IGSMTCManagerStatics, &statics);
	pfn_WindowsDeleteString (hClass);
	if (FAILED (hr) || statics == NULL)
		return NULL;

	WP_IInspectable *st_ins = (WP_IInspectable *) statics;
	void *req_op = NULL;
	hr = ((PFN_GetPtr) st_ins->lpVtbl[6]) (statics, &req_op);
	com_release (statics);
	if (FAILED (hr) || req_op == NULL)
		return NULL;

	void *manager = NULL;
	if (wait_async_op (req_op, 600)) {
		WP_IInspectable *op_ins = (WP_IInspectable *) req_op;
		((PFN_GetPtr) op_ins->lpVtbl[8]) (req_op, &manager);
	}
	com_release (req_op);
	return manager;
}

static int
is_browser_aumid_or_exe (const char *s)
{
	if (s == NULL || s[0] == '\0')
		return 0;
	char *low = g_ascii_strdown (s, -1);
	int res = (strstr (low, "chrome") != NULL
		|| strstr (low, "msedge") != NULL
		|| strstr (low, "edge") != NULL
		|| strstr (low, "firefox") != NULL
		|| strstr (low, "brave") != NULL
		|| strstr (low, "opera") != NULL
		|| strstr (low, "vivaldi") != NULL
		|| strstr (low, "waterfox") != NULL
		|| strstr (low, "zen") != NULL);
	g_free (low);
	return res;
}

static void
prettify_aumid_identity (const char *aumid, char *out_buf, size_t out_sz)
{
	out_buf[0] = '\0';
	if (aumid == NULL || aumid[0] == '\0') {
		g_strlcpy (out_buf, "Media", out_sz);
		return;
	}
	char *low = g_ascii_strdown (aumid, -1);
	if (strstr (low, "chrome") != NULL) {
		g_strlcpy (out_buf, "Google Chrome", out_sz);
		g_free (low);
		return;
	}
	if (strstr (low, "msedge") != NULL) {
		g_strlcpy (out_buf, "Microsoft Edge", out_sz);
		g_free (low);
		return;
	}
	if (strstr (low, "firefox") != NULL) {
		g_strlcpy (out_buf, "Firefox", out_sz);
		g_free (low);
		return;
	}
	if (strstr (low, "brave") != NULL) {
		g_strlcpy (out_buf, "Brave", out_sz);
		g_free (low);
		return;
	}
	if (strstr (low, "spotify") != NULL) {
		g_strlcpy (out_buf, "Spotify", out_sz);
		g_free (low);
		return;
	}
	if (strstr (low, "vlc") != NULL) {
		g_strlcpy (out_buf, "VLC media player", out_sz);
		g_free (low);
		return;
	}
	if (strstr (low, "zunemusic") != NULL || strstr (low, "windowsmediaplayer") != NULL) {
		g_strlcpy (out_buf, "Media Player", out_sz);
		g_free (low);
		return;
	}
	g_free (low);

	/* Trim package suffix ("!App") and ".exe" */
	char *copy = g_strdup (aumid);
	char *bang = strchr (copy, '!');
	if (bang != NULL) *bang = '\0';
	char *sep = strrchr (copy, '\\');
	char *base = (sep != NULL) ? sep + 1 : copy;
	char *us = strchr (base, '_');
	if (us != NULL && us > base) *us = '\0';
	size_t blen = strlen (base);
	if (blen > 4 && g_ascii_strcasecmp (base + blen - 4, ".exe") == 0)
		base[blen - 4] = '\0';
	if (base[0] != '\0') {
		base[0] = (char) toupper ((unsigned char) base[0]);
		g_strlcpy (out_buf, base, out_sz);
	} else {
		g_strlcpy (out_buf, "Media", out_sz);
	}
	g_free (copy);
}

static void
send_extended_media_key (WORD vk)
{
	WORD scan = (WORD) MapVirtualKeyW (vk, MAPVK_VK_TO_VSC);
	INPUT inputs[2];
	memset (inputs, 0, sizeof (inputs));
	inputs[0].type = INPUT_KEYBOARD;
	inputs[0].ki.wVk = vk;
	inputs[0].ki.wScan = scan;
	inputs[0].ki.dwFlags = KEYEVENTF_EXTENDEDKEY;
	inputs[1].type = INPUT_KEYBOARD;
	inputs[1].ki.wVk = vk;
	inputs[1].ki.wScan = scan;
	inputs[1].ki.dwFlags = KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP;
	SendInput (2, inputs, sizeof (INPUT));
}

typedef struct {
	DWORD pid;
	HWND best_hwnd;
	char title[256];
} FindWindowCtx;

static BOOL CALLBACK
enum_pid_window_cb (HWND hwnd, LPARAM lparam)
{
	FindWindowCtx *ctx = (FindWindowCtx *) lparam;
	if (!IsWindowVisible (hwnd))
		return TRUE;
	DWORD wpid = 0;
	GetWindowThreadProcessId (hwnd, &wpid);
	if (wpid != ctx->pid)
		return TRUE;
	if (GetWindow (hwnd, GW_OWNER) != NULL)
		return TRUE;
	WCHAR cap[256];
	int len = GetWindowTextW (hwnd, cap, (int) (sizeof (cap) / sizeof (cap[0])));
	if (len <= 0)
		return TRUE;
	ctx->best_hwnd = hwnd;
	char *u8 = wide_to_utf8 (cap);
	if (u8 != NULL) {
		g_strlcpy (ctx->title, u8, sizeof (ctx->title));
		g_free (u8);
	}
	return FALSE;
}

static void
get_pid_exe_basename (DWORD pid, char *out_buf, size_t out_sz)
{
	out_buf[0] = '\0';
	HANDLE hProc = OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (hProc == NULL)
		return;
	WCHAR buf[MAX_PATH * 2];
	DWORD sz = (DWORD) (sizeof (buf) / sizeof (buf[0]));
	if (QueryFullProcessImageNameW (hProc, 0, buf, &sz)) {
		const WCHAR *base = buf;
		for (const WCHAR *p = buf; *p != L'\0'; p++) {
			if (*p == L'\\' || *p == L'/')
				base = p + 1;
		}
		char *u8 = wide_to_utf8 (base);
		if (u8 != NULL) {
			g_strlcpy (out_buf, u8, out_sz);
			g_free (u8);
		}
	}
	CloseHandle (hProc);
}

static void
strip_player_window_suffix (char *title, const char *exe_low)
{
	if (title == NULL || title[0] == '\0')
		return;
	static const char *suffixes[] = {
		" - VLC media player",
		" - mpv",
		" - Media Player Classic",
		" - MPC-HC",
		" - foobar2000",
		" - Winamp",
		" - Windows Media Player",
		NULL
	};
	for (int i = 0; suffixes[i] != NULL; i++) {
		size_t tlen = strlen (title);
		size_t slen = strlen (suffixes[i]);
		if (tlen > slen && g_ascii_strcasecmp (title + tlen - slen, suffixes[i]) == 0) {
			title[tlen - slen] = '\0';
			return;
		}
	}
	(void) exe_low;
}

static int
is_win32_media_player_exe (const char *exe_low)
{
	if (exe_low == NULL || exe_low[0] == '\0')
		return 0;
	return (strcmp (exe_low, "vlc.exe") == 0
		|| strcmp (exe_low, "mpv.exe") == 0
		|| strcmp (exe_low, "mpc-hc.exe") == 0
		|| strcmp (exe_low, "mpc-hc64.exe") == 0
		|| strcmp (exe_low, "mpc-be.exe") == 0
		|| strcmp (exe_low, "mpc-be64.exe") == 0
		|| strcmp (exe_low, "potplayermini.exe") == 0
		|| strcmp (exe_low, "potplayermini64.exe") == 0
		|| strcmp (exe_low, "foobar2000.exe") == 0
		|| strcmp (exe_low, "musicbee.exe") == 0
		|| strcmp (exe_low, "aimp.exe") == 0
		|| strcmp (exe_low, "winamp.exe") == 0
		|| strcmp (exe_low, "wmplayer.exe") == 0
		|| strcmp (exe_low, "smplayer.exe") == 0
		|| strcmp (exe_low, "kodi.exe") == 0
		|| strcmp (exe_low, "itunes.exe") == 0);
}

static int
coreaudio_is_pid_playing (DWORD target_pid)
{
	IMMDeviceEnumerator *enumerator = NULL;
	if (FAILED (CoCreateInstance (&WP_CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &WP_IID_IMMDeviceEnumerator, (void **) &enumerator)) || enumerator == NULL)
		return 0;

	IMMDevice *device = NULL;
	if (FAILED (IMMDeviceEnumerator_GetDefaultAudioEndpoint (enumerator, eRender, eConsole, &device)) || device == NULL) {
		IMMDeviceEnumerator_Release (enumerator);
		return 0;
	}

	IAudioSessionManager2 *mgr = NULL;
	if (FAILED (IMMDevice_Activate (device, &WP_IID_IAudioSessionManager2, CLSCTX_ALL, NULL, (void **) &mgr)) || mgr == NULL) {
		IMMDevice_Release (device);
		IMMDeviceEnumerator_Release (enumerator);
		return 0;
	}

	IAudioSessionEnumerator *senum = NULL;
	int playing = 0;
	if (SUCCEEDED (IAudioSessionManager2_GetSessionEnumerator (mgr, &senum)) && senum != NULL) {
		int count = 0;
		if (SUCCEEDED (IAudioSessionEnumerator_GetCount (senum, &count))) {
			for (int i = 0; i < count; i++) {
				IAudioSessionControl *ctl = NULL;
				if (FAILED (IAudioSessionEnumerator_GetSession (senum, i, &ctl)) || ctl == NULL)
					continue;
				IAudioSessionControl2 *ctl2 = NULL;
				if (SUCCEEDED (IAudioSessionControl_QueryInterface (ctl, &WP_IID_IAudioSessionControl2, (void **) &ctl2)) && ctl2 != NULL) {
					DWORD spid = 0;
					AudioSessionState st = AudioSessionStateInactive;
					if (SUCCEEDED (IAudioSessionControl2_GetProcessId (ctl2, &spid)) && spid == target_pid) {
						IAudioSessionControl_GetState (ctl, &st);
						if (st == AudioSessionStateActive) {
							float peak = 0.0f;
							void *meter = NULL;
							if (SUCCEEDED (IAudioSessionControl_QueryInterface (ctl, &WP_IID_IAudioMeterInformation, &meter)) && meter != NULL) {
								WP_IInspectable *m_ins = (WP_IInspectable *) meter;
								((PFN_GetPeakValue) m_ins->lpVtbl[3]) (meter, &peak);
								com_release (meter);
								if (peak > 0.0005f)
									playing = 1;
							} else {
								playing = 1;
							}
						}
					}
					IAudioSessionControl2_Release (ctl2);
				}
				IAudioSessionControl_Release (ctl);
				if (playing)
					break;
			}
		}
		IAudioSessionEnumerator_Release (senum);
	}

	IAudioSessionManager2_Release (mgr);
	IMMDevice_Release (device);
	IMMDeviceEnumerator_Release (enumerator);
	return playing;
}

#endif /* _WIN32 */

int
win32_media_probe_players (Win32MediaPlayerCallback cb, void *user_data)
{
#ifdef _WIN32
	if (cb == NULL)
		return 0;

	int com_init = ensure_thread_com_init ();

	GHashTable *gsmtc_aumids = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);
	GHashTable *seen_pids = g_hash_table_new (g_direct_hash, g_direct_equal);
	int emitted = 0;

	/* 1. WinRT GSMTC sessions (Win 10/11: Chrome/Edge/Brave/Firefox YouTube, Spotify, Media Player, etc.) */
	void *manager = acquire_gsmtc_manager ();
	if (manager != NULL) {
		WP_IInspectable *mgr_ins = (WP_IInspectable *) manager;
		void *sessions = NULL;
		if (SUCCEEDED (((PFN_GetPtr) mgr_ins->lpVtbl[7]) (manager, &sessions)) && sessions != NULL) {
			WP_IInspectable *vec_ins = (WP_IInspectable *) sessions;
			uint32_t count = 0;
			if (SUCCEEDED (((PFN_GetUInt32) vec_ins->lpVtbl[7]) (sessions, &count))) {
				for (uint32_t i = 0; i < count && i < 16; i++) {
					void *sess = NULL;
					if (FAILED (((PFN_GetAt) vec_ins->lpVtbl[6]) (sessions, i, &sess)) || sess == NULL)
						continue;

					WP_IInspectable *s_ins = (WP_IInspectable *) sess;
					WP_HSTRING hAumid = NULL;
					char *aumid_str = NULL;
					if (SUCCEEDED (((PFN_GetHStr) s_ins->lpVtbl[6]) (sess, &hAumid)) && hAumid != NULL) {
						aumid_str = hstring_to_utf8 (hAumid);
						pfn_WindowsDeleteString (hAumid);
					}
					if (aumid_str == NULL)
						aumid_str = g_strdup ("");

					const char *status_str = "Stopped";
					void *pb_info = NULL;
					if (SUCCEEDED (((PFN_GetPtr) s_ins->lpVtbl[9]) (sess, &pb_info)) && pb_info != NULL) {
						WP_IInspectable *pb_ins = (WP_IInspectable *) pb_info;
						int32_t pb_status = 0;
						if (SUCCEEDED (((PFN_GetInt32) pb_ins->lpVtbl[7]) (pb_info, &pb_status))) {
							if (pb_status == 4)
								status_str = "Playing";
							else if (pb_status == 5)
								status_str = "Paused";
						}
						com_release (pb_info);
					}

					char *title_str = NULL;
					char *artist_str = NULL;
					void *prop_op = NULL;
					if (SUCCEEDED (((PFN_GetPtr) s_ins->lpVtbl[7]) (sess, &prop_op)) && prop_op != NULL) {
						if (wait_async_op (prop_op, 400)) {
							WP_IInspectable *pop_ins = (WP_IInspectable *) prop_op;
							void *props = NULL;
							if (SUCCEEDED (((PFN_GetPtr) pop_ins->lpVtbl[8]) (prop_op, &props)) && props != NULL) {
								WP_IInspectable *pr_ins = (WP_IInspectable *) props;
								WP_HSTRING hTitle = NULL;
								if (SUCCEEDED (((PFN_GetHStr) pr_ins->lpVtbl[6]) (props, &hTitle)) && hTitle != NULL) {
									title_str = hstring_to_utf8 (hTitle);
									pfn_WindowsDeleteString (hTitle);
								}
								WP_HSTRING hArtist = NULL;
								if (SUCCEEDED (((PFN_GetHStr) pr_ins->lpVtbl[9]) (props, &hArtist)) && hArtist != NULL) {
									artist_str = hstring_to_utf8 (hArtist);
									pfn_WindowsDeleteString (hArtist);
								}
								com_release (props);
							}
						}
						com_release (prop_op);
					}
					if (title_str == NULL) title_str = g_strdup ("");
					if (artist_str == NULL) artist_str = g_strdup ("");

					char identity[128];
					prettify_aumid_identity (aumid_str, identity, sizeof (identity));
					char *player_id = g_strdup_printf ("gsmtc:%u:%s", (unsigned) i, aumid_str);
					int is_browser = is_browser_aumid_or_exe (aumid_str);

					g_hash_table_add (gsmtc_aumids, g_ascii_strdown (aumid_str, -1));
					cb (player_id, identity, identity, status_str, title_str, artist_str, 1, is_browser, 0, user_data);
					emitted++;

					g_free (player_id);
					g_free (title_str);
					g_free (artist_str);
					g_free (aumid_str);
					com_release (sess);
				}
			}
			com_release (sessions);
		}
		com_release (manager);
	}

	/* 2. CoreAudio IAudioSessionManager2 -> detect non-GSMTC Win32 players (VLC, mpv, MPC-HC, etc.) */
	IMMDeviceEnumerator *enumerator = NULL;
	if (SUCCEEDED (CoCreateInstance (&WP_CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &WP_IID_IMMDeviceEnumerator, (void **) &enumerator)) && enumerator != NULL) {
		IMMDevice *device = NULL;
		if (SUCCEEDED (IMMDeviceEnumerator_GetDefaultAudioEndpoint (enumerator, eRender, eConsole, &device)) && device != NULL) {
			IAudioSessionManager2 *amgr = NULL;
			if (SUCCEEDED (IMMDevice_Activate (device, &WP_IID_IAudioSessionManager2, CLSCTX_ALL, NULL, (void **) &amgr)) && amgr != NULL) {
				IAudioSessionEnumerator *senum = NULL;
				if (SUCCEEDED (IAudioSessionManager2_GetSessionEnumerator (amgr, &senum)) && senum != NULL) {
					int count = 0;
					if (SUCCEEDED (IAudioSessionEnumerator_GetCount (senum, &count))) {
						for (int i = 0; i < count; i++) {
							IAudioSessionControl *ctl = NULL;
							if (FAILED (IAudioSessionEnumerator_GetSession (senum, i, &ctl)) || ctl == NULL)
								continue;
							IAudioSessionControl2 *ctl2 = NULL;
							if (SUCCEEDED (IAudioSessionControl_QueryInterface (ctl, &WP_IID_IAudioSessionControl2, (void **) &ctl2)) && ctl2 != NULL) {
								DWORD spid = 0;
								AudioSessionState st = AudioSessionStateInactive;
								if (SUCCEEDED (IAudioSessionControl2_GetProcessId (ctl2, &spid)) && spid != 0
									&& spid != GetCurrentProcessId ()
									&& !g_hash_table_contains (seen_pids, GUINT_TO_POINTER ((guint) spid))) {
									IAudioSessionControl_GetState (ctl, &st);
									if (st == AudioSessionStateActive || st == AudioSessionStateInactive) {
										char exe_name[260];
										get_pid_exe_basename (spid, exe_name, sizeof (exe_name));
										char *exe_low = g_ascii_strdown (exe_name, -1);

										/* Skip processes already reported by GSMTC (e.g. chrome.exe, msedge.exe, spotify.exe) */
										int covered_by_gsmtc = 0;
										GHashTableIter iter;
										gpointer k = NULL;
										g_hash_table_iter_init (&iter, gsmtc_aumids);
										while (g_hash_table_iter_next (&iter, &k, NULL)) {
											const char *ga = (const char *) k;
											if (exe_low[0] != '\0' && ga != NULL && strstr (ga, exe_low) != NULL) {
												covered_by_gsmtc = 1;
												break;
											}
											if (is_browser_aumid_or_exe (exe_low) && is_browser_aumid_or_exe (ga)) {
												/* Compare same browser family */
												if ((strstr (exe_low, "chrome") && strstr (ga, "chrome"))
													|| (strstr (exe_low, "msedge") && strstr (ga, "msedge"))
													|| (strstr (exe_low, "firefox") && strstr (ga, "firefox"))
													|| (strstr (exe_low, "brave") && strstr (ga, "brave"))) {
													covered_by_gsmtc = 1;
													break;
												}
											}
										}

										if (!covered_by_gsmtc && is_win32_media_player_exe (exe_low)) {
											FindWindowCtx fctx;
											memset (&fctx, 0, sizeof (fctx));
											fctx.pid = spid;
											EnumWindows (enum_pid_window_cb, (LPARAM) &fctx);
											if (fctx.best_hwnd != NULL) {
												g_hash_table_add (seen_pids, GUINT_TO_POINTER ((guint) spid));
												int is_playing = 0;
												if (st == AudioSessionStateActive) {
													float peak = 0.0f;
													void *meter = NULL;
													if (SUCCEEDED (IAudioSessionControl_QueryInterface (ctl, &WP_IID_IAudioMeterInformation, &meter)) && meter != NULL) {
														WP_IInspectable *m_ins = (WP_IInspectable *) meter;
														((PFN_GetPeakValue) m_ins->lpVtbl[3]) (meter, &peak);
														com_release (meter);
														is_playing = (peak > 0.0005f) ? 1 : 0;
													} else {
														is_playing = 1;
													}
												}
												char identity[128];
												prettify_aumid_identity (exe_name, identity, sizeof (identity));
												strip_player_window_suffix (fctx.title, exe_low);
												if (g_ascii_strcasecmp (fctx.title, identity) == 0)
													fctx.title[0] = '\0';

												char *pid_str = g_strdup_printf ("hwnd:0x%016llx:%lu",
													(unsigned long long) (uintptr_t) fctx.best_hwnd,
													(unsigned long) spid);
												cb (pid_str, identity, identity,
													is_playing ? "Playing" : "Paused",
													fctx.title, "", 1, 0, (int) spid, user_data);
												emitted++;
												g_free (pid_str);
											}
										}
										g_free (exe_low);
									}
								}
								IAudioSessionControl2_Release (ctl2);
							}
							IAudioSessionControl_Release (ctl);
						}
					}
					IAudioSessionEnumerator_Release (senum);
				}
				IAudioSessionManager2_Release (amgr);
			}
			IMMDevice_Release (device);
		}
		IMMDeviceEnumerator_Release (enumerator);
	}

	g_hash_table_destroy (gsmtc_aumids);
	g_hash_table_destroy (seen_pids);
	uninit_thread_com (com_init);
	return 1;
#else
	(void) cb;
	(void) user_data;
	return 0;
#endif
}

int
win32_media_send_command (const char *player_id, const char *command)
{
#ifdef _WIN32
	if (command == NULL || command[0] == '\0')
		return 0;

	int com_init = ensure_thread_com_init ();

	/* 1. Targeted WinRT GSMTC session command ("gsmtc:<idx>:<aumid>") */
	if (player_id != NULL && strncmp (player_id, "gsmtc:", 6) == 0) {
		const char *p = player_id + 6;
		char *colon = strchr (p, ':');
		const char *target_aumid = (colon != NULL) ? (colon + 1) : "";
		unsigned target_idx = (unsigned) strtoul (p, NULL, 10);

		void *manager = acquire_gsmtc_manager ();
		if (manager != NULL) {
			WP_IInspectable *mgr_ins = (WP_IInspectable *) manager;
			void *sessions = NULL;
			int sent = 0;
			if (SUCCEEDED (((PFN_GetPtr) mgr_ins->lpVtbl[7]) (manager, &sessions)) && sessions != NULL) {
				WP_IInspectable *vec_ins = (WP_IInspectable *) sessions;
				uint32_t count = 0;
				if (SUCCEEDED (((PFN_GetUInt32) vec_ins->lpVtbl[7]) (sessions, &count))) {
					void *matched_sess = NULL;
					for (uint32_t i = 0; i < count; i++) {
						void *sess = NULL;
						if (FAILED (((PFN_GetAt) vec_ins->lpVtbl[6]) (sessions, i, &sess)) || sess == NULL)
							continue;
						WP_IInspectable *s_ins = (WP_IInspectable *) sess;
						WP_HSTRING hAumid = NULL;
						char *aumid_str = NULL;
						if (SUCCEEDED (((PFN_GetHStr) s_ins->lpVtbl[6]) (sess, &hAumid)) && hAumid != NULL) {
							aumid_str = hstring_to_utf8 (hAumid);
							pfn_WindowsDeleteString (hAumid);
						}
						int match = (target_aumid[0] != '\0' && aumid_str != NULL && g_ascii_strcasecmp (aumid_str, target_aumid) == 0);
						if (!match && i == target_idx && matched_sess == NULL)
							matched_sess = sess;
						else if (match) {
							if (matched_sess != NULL) com_release (matched_sess);
							matched_sess = sess;
							g_free (aumid_str);
							break;
						} else {
							com_release (sess);
						}
						g_free (aumid_str);
					}

					if (matched_sess != NULL) {
						WP_IInspectable *s_ins = (WP_IInspectable *) matched_sess;
						int vslot = 20; /* TryTogglePlayPauseAsync */
						if (g_ascii_strcasecmp (command, "play") == 0)
							vslot = 10; /* TryPlayAsync */
						else if (g_ascii_strcasecmp (command, "pause") == 0)
							vslot = 11; /* TryPauseAsync */
						else if (g_ascii_strcasecmp (command, "stop") == 0)
							vslot = 12; /* TryStopAsync */
						else if (g_ascii_strcasecmp (command, "next") == 0)
							vslot = 16; /* TrySkipNextAsync */
						else if (g_ascii_strcasecmp (command, "previous") == 0)
							vslot = 17; /* TrySkipPreviousAsync */

						void *cmd_op = NULL;
						if (SUCCEEDED (((PFN_GetPtr) s_ins->lpVtbl[vslot]) (matched_sess, &cmd_op)) && cmd_op != NULL) {
							wait_async_op (cmd_op, 500);
							com_release (cmd_op);
							sent = 1;
						}
						com_release (matched_sess);
					}
				}
				com_release (sessions);
			}
			com_release (manager);
			if (sent) {
				uninit_thread_com (com_init);
				return 1;
			}
		}
	}

	/* 2. Targeted Win32 HWND player command ("hwnd:0x...:<pid>", e.g. VLC, mpv, MPC-HC) */
	if (player_id != NULL && strncmp (player_id, "hwnd:0x", 7) == 0) {
		unsigned long long raw_hwnd = 0;
		unsigned long raw_pid = 0;
		if (sscanf (player_id + 7, "%llx:%lu", &raw_hwnd, &raw_pid) >= 1 && raw_hwnd != 0) {
			HWND hwnd = (HWND) (uintptr_t) raw_hwnd;
			if (IsWindow (hwnd)) {
				/* For explicit "pause" (multi-player interlock), only toggle if actually playing */
				if (g_ascii_strcasecmp (command, "pause") == 0 && raw_pid != 0) {
					if (!coreaudio_is_pid_playing ((DWORD) raw_pid)) {
						uninit_thread_com (com_init);
						return 1;
					}
				}
				WORD appcmd = APPCOMMAND_MEDIA_PLAY_PAUSE;
				if (g_ascii_strcasecmp (command, "next") == 0)
					appcmd = APPCOMMAND_MEDIA_NEXTTRACK;
				else if (g_ascii_strcasecmp (command, "previous") == 0)
					appcmd = APPCOMMAND_MEDIA_PREVIOUSTRACK;
				else if (g_ascii_strcasecmp (command, "stop") == 0)
					appcmd = APPCOMMAND_MEDIA_STOP;
				else if (g_ascii_strcasecmp (command, "play") == 0)
					appcmd = APPCOMMAND_MEDIA_PLAY;
				else if (g_ascii_strcasecmp (command, "pause") == 0)
					appcmd = APPCOMMAND_MEDIA_PLAY_PAUSE;

				PostMessageW (hwnd, WM_APPCOMMAND, (WPARAM) hwnd, MAKELPARAM (0, appcmd));
				uninit_thread_com (com_init);
				return 1;
			}
		}
	}

	/* 3. Universal extended media key fallback (Windows 7/8 or unfocused player) */
	WORD vk = VK_MEDIA_PLAY_PAUSE;
	if (g_ascii_strcasecmp (command, "next") == 0)
		vk = VK_MEDIA_NEXT_TRACK;
	else if (g_ascii_strcasecmp (command, "previous") == 0)
		vk = VK_MEDIA_PREV_TRACK;
	else if (g_ascii_strcasecmp (command, "stop") == 0)
		vk = VK_MEDIA_STOP;
	send_extended_media_key (vk);
	uninit_thread_com (com_init);
	return 1;
#else
	(void) player_id;
	(void) command;
	return 0;
#endif
}
