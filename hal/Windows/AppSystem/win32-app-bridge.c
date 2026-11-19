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
#include <ole2.h>
#include <objbase.h>
#include <propsys.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <commoncontrols.h>
#include <tlhelp32.h>
#include <stdlib.h>
#include <string.h>
#endif

#include "win32-app-bridge.h"

#ifdef _WIN32

static const GUID WP_CLSID_ShellLink =
	{ 0x00021401, 0x0000, 0x0000, { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
static const GUID WP_IID_IShellLinkW =
	{ 0x000214F9, 0x0000, 0x0000, { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
static const GUID WP_IID_IPersistFile =
	{ 0x0000010B, 0x0000, 0x0000, { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
static const GUID WP_IID_IImageList =
	{ 0x46EB5926, 0x582E, 0x4017, { 0x9F, 0xDF, 0xE8, 0x99, 0x8D, 0xAA, 0x09, 0x50 } };
static const GUID WP_APP_IID_IPropertyStore =
	{ 0x886D8EEB, 0x8CF2, 0x4446, { 0x8D, 0x02, 0xCD, 0xBA, 0x1D, 0xBD, 0xCF, 0x99 } };
static const PROPERTYKEY WP_APP_PKEY_AppUserModel_ID =
	{ { 0x9F4C2855, 0x9F79, 0x4B39, { 0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3 } }, 5 };

typedef HRESULT (WINAPI *PFN_SHGetImageList) (int iImageList, REFIID riid, void **ppvObj);

static int g_com_initialized = 0;

static void
ensure_com (void)
{
	if (!g_com_initialized) {
		HRESULT hr = OleInitialize (NULL);
		if (SUCCEEDED (hr) || hr == RPC_E_CHANGED_MODE)
			g_com_initialized = 1;
	}
}

static WCHAR *
utf8_to_wide (const char *utf8)
{
	if (utf8 == NULL || utf8[0] == '\0')
		return NULL;
	int needed = MultiByteToWideChar (CP_UTF8, 0, utf8, -1, NULL, 0);
	if (needed <= 0)
		return NULL;
	WCHAR *out = (WCHAR *) g_malloc ((gsize) needed * sizeof (WCHAR));
	MultiByteToWideChar (CP_UTF8, 0, utf8, -1, out, needed);
	return out;
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

#endif /* _WIN32 */

char *
win32_app_get_known_folder (int folder_id)
{
#ifdef _WIN32
	int csidl = -1;
	switch (folder_id) {
	case WIN32_FOLDER_COMMON_PROGRAMS:   csidl = CSIDL_COMMON_PROGRAMS; break;
	case WIN32_FOLDER_USER_PROGRAMS:     csidl = CSIDL_PROGRAMS; break;
	case WIN32_FOLDER_USER_DESKTOP:      csidl = CSIDL_DESKTOPDIRECTORY; break;
	case WIN32_FOLDER_COMMON_DESKTOP:    csidl = CSIDL_COMMON_DESKTOPDIRECTORY; break;
	case WIN32_FOLDER_RECENT:            csidl = CSIDL_RECENT; break;
	case WIN32_FOLDER_PROGRAM_FILES:     csidl = CSIDL_PROGRAM_FILES; break;
	case WIN32_FOLDER_PROGRAM_FILES_X86: csidl = CSIDL_PROGRAM_FILESX86; break;
	case WIN32_FOLDER_LOCAL_APPDATA:     csidl = CSIDL_LOCAL_APPDATA; break;
	case WIN32_FOLDER_ROAMING_APPDATA:   csidl = CSIDL_APPDATA; break;
	default: return NULL;
	}

	WCHAR path_w[MAX_PATH * 2];
	path_w[0] = L'\0';
	if (SUCCEEDED (SHGetFolderPathW (NULL, csidl, NULL, SHGFP_TYPE_CURRENT, path_w)) && path_w[0] != L'\0')
		return wide_to_utf8 (path_w);
	return NULL;
#else
	(void) folder_id;
	return NULL;
#endif
}

int
win32_app_resolve_lnk (
	const char *lnk_path,
	char **out_target,
	char **out_args,
	char **out_workdir,
	char **out_description,
	char **out_icon_path,
	int *out_icon_index,
	char **out_aumid
)
{
	if (out_target) *out_target = NULL;
	if (out_args) *out_args = NULL;
	if (out_workdir) *out_workdir = NULL;
	if (out_description) *out_description = NULL;
	if (out_icon_path) *out_icon_path = NULL;
	if (out_icon_index) *out_icon_index = 0;
	if (out_aumid) *out_aumid = NULL;

#ifdef _WIN32
	if (lnk_path == NULL || lnk_path[0] == '\0')
		return 0;

	ensure_com ();
	WCHAR *wlnk = utf8_to_wide (lnk_path);
	if (wlnk == NULL)
		return 0;

	IShellLinkW *psl = NULL;
	HRESULT hr = CoCreateInstance (&WP_CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, &WP_IID_IShellLinkW, (void **) &psl);
	if (FAILED (hr) || psl == NULL) {
		g_free (wlnk);
		return 0;
	}

	IPersistFile *ppf = NULL;
	hr = IShellLinkW_QueryInterface (psl, &WP_IID_IPersistFile, (void **) &ppf);
	if (FAILED (hr) || ppf == NULL) {
		IShellLinkW_Release (psl);
		g_free (wlnk);
		return 0;
	}

	hr = IPersistFile_Load (ppf, wlnk, STGM_READ);
	g_free (wlnk);
	if (FAILED (hr)) {
		IPersistFile_Release (ppf);
		IShellLinkW_Release (psl);
		return 0;
	}

	WCHAR target_w[MAX_PATH * 4];
	WCHAR args_w[2048];
	WCHAR workdir_w[MAX_PATH * 4];
	WCHAR desc_w[1024];
	WCHAR icon_w[MAX_PATH * 4];
	int icon_idx = 0;

	target_w[0] = L'\0';
	args_w[0] = L'\0';
	workdir_w[0] = L'\0';
	desc_w[0] = L'\0';
	icon_w[0] = L'\0';

	WIN32_FIND_DATAW wfd;
	memset (&wfd, 0, sizeof (wfd));
	IShellLinkW_GetPath (psl, target_w, (int) (sizeof (target_w) / sizeof (target_w[0])), &wfd, SLGP_RAWPATH);
	if (target_w[0] == L'\0')
		IShellLinkW_GetPath (psl, target_w, (int) (sizeof (target_w) / sizeof (target_w[0])), &wfd, 0);

	/* Expand any %ENVVAR% in target/icon paths */
	WCHAR expanded_target[MAX_PATH * 4];
	if (target_w[0] != L'\0' && ExpandEnvironmentStringsW (target_w, expanded_target, (DWORD) (sizeof (expanded_target) / sizeof (expanded_target[0]))) > 0)
		wcsncpy (target_w, expanded_target, (sizeof (target_w) / sizeof (target_w[0])) - 1);

	IShellLinkW_GetArguments (psl, args_w, (int) (sizeof (args_w) / sizeof (args_w[0])));
	IShellLinkW_GetWorkingDirectory (psl, workdir_w, (int) (sizeof (workdir_w) / sizeof (workdir_w[0])));
	IShellLinkW_GetDescription (psl, desc_w, (int) (sizeof (desc_w) / sizeof (desc_w[0])));
	IShellLinkW_GetIconLocation (psl, icon_w, (int) (sizeof (icon_w) / sizeof (icon_w[0])), &icon_idx);

	WCHAR expanded_icon[MAX_PATH * 4];
	if (icon_w[0] != L'\0' && ExpandEnvironmentStringsW (icon_w, expanded_icon, (DWORD) (sizeof (expanded_icon) / sizeof (expanded_icon[0]))) > 0)
		wcsncpy (icon_w, expanded_icon, (sizeof (icon_w) / sizeof (icon_w[0])) - 1);

	char *aumid_utf8 = g_strdup ("");
	IPropertyStore *ps = NULL;
	if (SUCCEEDED (IShellLinkW_QueryInterface (psl, &WP_APP_IID_IPropertyStore, (void **) &ps)) && ps != NULL) {
		PROPVARIANT pv;
		memset (&pv, 0, sizeof (pv));
		if (SUCCEEDED (IPropertyStore_GetValue (ps, &WP_APP_PKEY_AppUserModel_ID, &pv))) {
			if (pv.vt == VT_LPWSTR && pv.pwszVal != NULL && pv.pwszVal[0] != L'\0') {
				g_free (aumid_utf8);
				aumid_utf8 = wide_to_utf8 (pv.pwszVal);
			}
			if (pv.vt == VT_LPWSTR && pv.pwszVal != NULL)
				CoTaskMemFree (pv.pwszVal);
		}
		IPropertyStore_Release (ps);
	}

	IPersistFile_Release (ppf);
	IShellLinkW_Release (psl);

	if (out_target) *out_target = wide_to_utf8 (target_w);
	if (out_args) *out_args = wide_to_utf8 (args_w);
	if (out_workdir) *out_workdir = wide_to_utf8 (workdir_w);
	if (out_description) *out_description = wide_to_utf8 (desc_w);
	if (out_icon_path) *out_icon_path = wide_to_utf8 (icon_w);
	if (out_icon_index) *out_icon_index = icon_idx;
	if (out_aumid) *out_aumid = aumid_utf8; else g_free (aumid_utf8);
	return 1;
#else
	(void) lnk_path;
	return 0;
#endif
}

#ifdef _WIN32

static HICON
load_best_hicon (const WCHAR *wpath, int icon_index, int desired_size)
{
	HICON hIcon = NULL;

	/* 1. Explicit icon index or .ico/.exe/.dll via PrivateExtractIconsW (crisp up to 256px) */
	if (icon_index != 0 || desired_size >= 48) {
		UINT icon_id = 0;
		UINT extracted = PrivateExtractIconsW (
			wpath, icon_index, desired_size, desired_size,
			&hIcon, &icon_id, 1, LR_DEFAULTCOLOR
		);
		if (extracted > 0 && hIcon != NULL)
			return hIcon;
	}

	/* 2. SHGetImageList(SHIL_JUMBO = 256x256, fallback SHIL_EXTRALARGE = 48x48) */
	if (icon_index == 0) {
		SHFILEINFOW sfi;
		memset (&sfi, 0, sizeof (sfi));
		if (SHGetFileInfoW (wpath, 0, &sfi, sizeof (sfi), SHGFI_SYSICONINDEX) != 0) {
			HMODULE hShell = GetModuleHandleW (L"shell32.dll");
			PFN_SHGetImageList pfn_SHGetImageList = NULL;
			if (hShell != NULL) {
				pfn_SHGetImageList = (PFN_SHGetImageList) GetProcAddress (hShell, "SHGetImageList");
				if (pfn_SHGetImageList == NULL)
					pfn_SHGetImageList = (PFN_SHGetImageList) GetProcAddress (hShell, MAKEINTRESOURCEA (727));
			}
			if (pfn_SHGetImageList != NULL) {
				int shil_order[2] = { SHIL_JUMBO, SHIL_EXTRALARGE };
				for (int k = 0; k < 2; k++) {
					IImageList *iml = NULL;
					if (SUCCEEDED (pfn_SHGetImageList (shil_order[k], &WP_IID_IImageList, (void **) &iml)) && iml != NULL) {
						HRESULT hr = IImageList_GetIcon (iml, sfi.iIcon, ILD_TRANSPARENT, &hIcon);
						IImageList_Release (iml);
						if (SUCCEEDED (hr) && hIcon != NULL)
							return hIcon;
					}
				}
			}
		}
	}

	/* 3. ExtractIconExW fallback */
	if (ExtractIconExW (wpath, icon_index, &hIcon, NULL, 1) > 0 && hIcon != NULL)
		return hIcon;

	/* 4. SHGetFileInfoW large icon fallback */
	SHFILEINFOW sfi;
	memset (&sfi, 0, sizeof (sfi));
	if (SHGetFileInfoW (wpath, 0, &sfi, sizeof (sfi), SHGFI_ICON | SHGFI_LARGEICON) != 0 && sfi.hIcon != NULL)
		return sfi.hIcon;

	return NULL;
}

static int
render_hicon_to_rgba (HICON hIcon, int size, uint8_t **out_rgba, int *out_w, int *out_h)
{
	if (hIcon == NULL || size <= 0)
		return 0;

	HDC hdcScreen = GetDC (NULL);
	if (hdcScreen == NULL)
		return 0;

	BITMAPINFO bmi;
	memset (&bmi, 0, sizeof (bmi));
	bmi.bmiHeader.biSize = sizeof (BITMAPINFOHEADER);
	bmi.bmiHeader.biWidth = size;
	bmi.bmiHeader.biHeight = -size; /* Top-down */
	bmi.bmiHeader.biPlanes = 1;
	bmi.bmiHeader.biBitCount = 32;
	bmi.bmiHeader.biCompression = BI_RGB;

	void *color_bits = NULL;
	HDC hdcColor = CreateCompatibleDC (hdcScreen);
	HBITMAP hbmColor = CreateDIBSection (hdcColor, &bmi, DIB_RGB_COLORS, &color_bits, NULL, 0);
	if (hdcColor == NULL || hbmColor == NULL || color_bits == NULL) {
		if (hbmColor) DeleteObject (hbmColor);
		if (hdcColor) DeleteDC (hdcColor);
		ReleaseDC (NULL, hdcScreen);
		return 0;
	}

	size_t byte_len = (size_t) size * (size_t) size * 4;
	memset (color_bits, 0, byte_len);

	HGDIOBJ oldColor = SelectObject (hdcColor, hbmColor);
	DrawIconEx (hdcColor, 0, 0, hIcon, size, size, 0, NULL, DI_NORMAL);
	GdiFlush ();

	const uint8_t *bgra = (const uint8_t *) color_bits;
	int has_alpha = 0;
	for (size_t i = 3; i < byte_len; i += 4) {
		if (bgra[i] != 0) {
			has_alpha = 1;
			break;
		}
	}

	uint8_t *rgba = (uint8_t *) g_malloc (byte_len);

	if (has_alpha) {
		for (size_t i = 0; i < byte_len; i += 4) {
			rgba[i + 0] = bgra[i + 2];
			rgba[i + 1] = bgra[i + 1];
			rgba[i + 2] = bgra[i + 0];
			rgba[i + 3] = bgra[i + 3];
		}
	} else {
		/* Legacy 24-bit icon without alpha channel: render DI_MASK for transparency */
		void *mask_bits = NULL;
		HDC hdcMask = CreateCompatibleDC (hdcScreen);
		HBITMAP hbmMask = CreateDIBSection (hdcMask, &bmi, DIB_RGB_COLORS, &mask_bits, NULL, 0);
		if (hdcMask != NULL && hbmMask != NULL && mask_bits != NULL) {
			memset (mask_bits, 0xFF, byte_len);
			HGDIOBJ oldMask = SelectObject (hdcMask, hbmMask);
			DrawIconEx (hdcMask, 0, 0, hIcon, size, size, 0, NULL, DI_MASK);
			GdiFlush ();
			const uint8_t *m = (const uint8_t *) mask_bits;
			for (size_t i = 0; i < byte_len; i += 4) {
				rgba[i + 0] = bgra[i + 2];
				rgba[i + 1] = bgra[i + 1];
				rgba[i + 2] = bgra[i + 0];
				rgba[i + 3] = (m[i] == 0) ? 255 : 0;
			}
			SelectObject (hdcMask, oldMask);
		} else {
			for (size_t i = 0; i < byte_len; i += 4) {
				rgba[i + 0] = bgra[i + 2];
				rgba[i + 1] = bgra[i + 1];
				rgba[i + 2] = bgra[i + 0];
				rgba[i + 3] = (bgra[i] | bgra[i + 1] | bgra[i + 2]) ? 255 : 0;
			}
		}
		if (hbmMask) DeleteObject (hbmMask);
		if (hdcMask) DeleteDC (hdcMask);
	}

	SelectObject (hdcColor, oldColor);
	DeleteObject (hbmColor);
	DeleteDC (hdcColor);
	ReleaseDC (NULL, hdcScreen);

	if (out_rgba) *out_rgba = rgba; else g_free (rgba);
	if (out_w) *out_w = size;
	if (out_h) *out_h = size;
	return 1;
}

#endif /* _WIN32 */

int
win32_app_extract_icon_rgba (
	const char *path_or_icon_spec,
	int desired_size,
	uint8_t **out_rgba,
	int *out_w,
	int *out_h
)
{
	if (out_rgba) *out_rgba = NULL;
	if (out_w) *out_w = 0;
	if (out_h) *out_h = 0;

#ifdef _WIN32
	if (path_or_icon_spec == NULL || path_or_icon_spec[0] == '\0')
		return 0;

	ensure_com ();
	int size = (desired_size > 0) ? desired_size : 64;
	if (size > 256) size = 256;

	/* Parse optional ",<index>" suffix (e.g. "C:\...\app.exe,0" or "shell32.dll,-4") */
	char *path_copy = g_strdup (path_or_icon_spec);
	int icon_index = 0;
	char *comma = strrchr (path_copy, ',');
	if (comma != NULL && comma[1] != '\0') {
		char *endptr = NULL;
		long val = strtol (comma + 1, &endptr, 10);
		if (endptr != NULL && *endptr == '\0') {
			*comma = '\0';
			icon_index = (int) val;
		}
	}

	WCHAR *wpath = utf8_to_wide (path_copy);
	g_free (path_copy);
	if (wpath == NULL)
		return 0;

	HICON hIcon = load_best_hicon (wpath, icon_index, size);
	g_free (wpath);
	if (hIcon == NULL)
		return 0;

	int ok = render_hicon_to_rgba (hIcon, size, out_rgba, out_w, out_h);
	DestroyIcon (hIcon);
	return ok;
#else
	(void) path_or_icon_spec;
	(void) desired_size;
	return 0;
#endif
}

void
win32_app_free_buffer (void *ptr)
{
	if (ptr != NULL)
		g_free (ptr);
}

int
win32_app_shell_execute (
	const char *target,
	const char *args,
	const char *working_dir
)
{
#ifdef _WIN32
	if (target == NULL || target[0] == '\0')
		return 0;
	ensure_com ();

	WCHAR *wtarget = utf8_to_wide (target);
	WCHAR *wargs = (args != NULL && args[0] != '\0') ? utf8_to_wide (args) : NULL;
	WCHAR *wdir = (working_dir != NULL && working_dir[0] != '\0') ? utf8_to_wide (working_dir) : NULL;

	HINSTANCE res = ShellExecuteW (NULL, L"open", wtarget, wargs, wdir, SW_SHOWNORMAL);

	g_free (wtarget);
	g_free (wargs);
	g_free (wdir);
	return ((intptr_t) res > 32) ? 1 : 0;
#else
	(void) target;
	(void) args;
	(void) working_dir;
	return 0;
#endif
}

int
win32_app_is_process_alive (int pid)
{
#ifdef _WIN32
	if (pid <= 0)
		return 0;
	HANDLE hProc = OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD) pid);
	if (hProc == NULL)
		return (GetLastError () == ERROR_ACCESS_DENIED) ? 1 : 0;
	DWORD exit_code = 0;
	int alive = (GetExitCodeProcess (hProc, &exit_code) && exit_code == STILL_ACTIVE) ? 1 : 0;
	CloseHandle (hProc);
	return alive;
#else
	(void) pid;
	return 0;
#endif
}

char *
win32_app_get_process_exe (int pid)
{
#ifdef _WIN32
	if (pid <= 0)
		return g_strdup ("");
	HANDLE hProc = OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD) pid);
	if (hProc != NULL) {
		WCHAR buf[MAX_PATH * 4];
		DWORD size = (DWORD) (sizeof (buf) / sizeof (buf[0]));
		char *res = NULL;
		if (QueryFullProcessImageNameW (hProc, 0, buf, &size))
			res = wide_to_utf8 (buf);
		CloseHandle (hProc);
		if (res != NULL && res[0] != '\0')
			return res;
		g_free (res);
	}
	HANDLE hSnap = CreateToolhelp32Snapshot (TH32CS_SNAPPROCESS, 0);
	if (hSnap != INVALID_HANDLE_VALUE) {
		PROCESSENTRY32W pe;
		memset (&pe, 0, sizeof (pe));
		pe.dwSize = sizeof (pe);
		if (Process32FirstW (hSnap, &pe)) {
			do {
				if (pe.th32ProcessID == (DWORD) pid && pe.szExeFile[0] != L'\0') {
					char *res = wide_to_utf8 (pe.szExeFile);
					CloseHandle (hSnap);
					return res;
				}
			} while (Process32NextW (hSnap, &pe));
		}
		CloseHandle (hSnap);
	}
	return g_strdup ("");
#else
	(void) pid;
	return g_strdup ("");
#endif
}

void
win32_app_enum_processes (Win32EnumProcessCallback cb, void *user_data)
{
#ifdef _WIN32
	if (cb == NULL)
		return;
	HANDLE hSnap = CreateToolhelp32Snapshot (TH32CS_SNAPPROCESS, 0);
	if (hSnap == INVALID_HANDLE_VALUE)
		return;

	PROCESSENTRY32W pe;
	pe.dwSize = sizeof (pe);
	if (Process32FirstW (hSnap, &pe)) {
		do {
			char *exe_name = wide_to_utf8 (pe.szExeFile);
			char *exe_path = win32_app_get_process_exe ((int) pe.th32ProcessID);
			cb ((int) pe.th32ProcessID, exe_name, exe_path, user_data);
			g_free (exe_name);
			g_free (exe_path);
		} while (Process32NextW (hSnap, &pe));
	}
	CloseHandle (hSnap);
#else
	(void) cb;
	(void) user_data;
#endif
}
