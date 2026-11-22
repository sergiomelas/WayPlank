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
#include <ole2.h>
#include <objbase.h>
#include <propsys.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <commoncontrols.h>
#include <tlhelp32.h>
#include <ctype.h>
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
static const GUID WP_CLSID_ApplicationDocumentLists =
	{ 0x86BEC222, 0x30F2, 0x47E0, { 0x9F, 0x25, 0x60, 0xD1, 0x1C, 0xD7, 0x5C, 0x28 } };
static const GUID WP_IID_IApplicationDocumentLists =
	{ 0x3C594F9F, 0x9F30, 0x47A1, { 0x97, 0x9A, 0xC9, 0xE8, 0x3D, 0x3D, 0x0A, 0x06 } };
static const GUID WP_IID_IObjectArray =
	{ 0x92CA9DCD, 0x5622, 0x4BBA, { 0xA8, 0x05, 0x5E, 0x9F, 0x54, 0x1B, 0xD8, 0xC9 } };
static const GUID WP_IID_IShellItem =
	{ 0x43826D1E, 0xE718, 0x42EE, { 0xBC, 0x55, 0xA1, 0xE2, 0x61, 0xC3, 0x7B, 0xFE } };
static const PROPERTYKEY WP_APP_PKEY_AppUserModel_ID =
	{ { 0x9F4C2855, 0x9F79, 0x4B39, { 0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3 } }, 5 };
static const PROPERTYKEY WP_APP_PKEY_AppUserModel_PackageInstallPath =
	{ { 0x9F4C2855, 0x9F79, 0x4B39, { 0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3 } }, 15 };
static const GUID WP_CLSID_ApplicationActivationManager =
	{ 0x45BA127D, 0x10A8, 0x46EA, { 0x8A, 0xB7, 0x56, 0xEA, 0x90, 0x78, 0x94, 0x3C } };
static const GUID WP_IID_IApplicationActivationManager =
	{ 0x2E941141, 0x7F97, 0x4756, { 0xBA, 0x1D, 0x9D, 0xEC, 0xDE, 0x89, 0x4A, 0x3D } };
static const GUID WP_FOLDERID_AppsFolder =
	{ 0x1E87508D, 0x89C2, 0x42F0, { 0x8A, 0x7E, 0x64, 0x5A, 0x0F, 0x50, 0xCA, 0x58 } };
static const GUID WP_BHID_EnumItems =
	{ 0x94F60519, 0x2850, 0x4924, { 0xAA, 0x5A, 0xD1, 0x5E, 0x84, 0x86, 0x80, 0x39 } };
static const GUID WP_IID_IEnumShellItems =
	{ 0x70629033, 0xE363, 0x4A28, { 0xA5, 0x67, 0x0D, 0xB7, 0x80, 0x06, 0xE6, 0xD7 } };
static const GUID WP_IID_IShellItem2 =
	{ 0x7E9FB0D3, 0x919F, 0x4307, { 0xAB, 0x2E, 0x9B, 0x18, 0x60, 0x31, 0x0C, 0x93 } };
static const GUID WP_IID_IShellItemImageFactory =
	{ 0xBCC18B79, 0xBA16, 0x442F, { 0x80, 0xC4, 0x8A, 0x59, 0xC3, 0x0C, 0x46, 0x3B } };

typedef HRESULT (WINAPI *PFN_SHGetImageList) (int iImageList, REFIID riid, void **ppvObj);
typedef HRESULT (WINAPI *PFN_SHGetStockIconInfo) (SHSTOCKICONID siid, UINT uFlags, SHSTOCKICONINFO *psii);
typedef HRESULT (WINAPI *PFN_SHGetKnownFolderItem) (REFKNOWNFOLDERID rfid, DWORD flags, HANDLE hToken, REFIID riid, void **ppv);
typedef HRESULT (WINAPI *PFN_SHCreateItemFromParsingName) (PCWSTR pszPath, IBindCtx *pbc, REFIID riid, void **ppv);
typedef LONG (WINAPI *PFN_GetApplicationUserModelId) (HANDLE hProcess, UINT32 *applicationUserModelIdLength, PWSTR applicationUserModelId);

/* Explicit Vista+ COM IShellItemImageFactory vtable */
typedef struct WP_IShellItemImageFactory WP_IShellItemImageFactory;
typedef struct WP_IShellItemImageFactoryVtbl {
	HRESULT (STDMETHODCALLTYPE *QueryInterface) (WP_IShellItemImageFactory *This, REFIID riid, void **ppvObject);
	ULONG   (STDMETHODCALLTYPE *AddRef) (WP_IShellItemImageFactory *This);
	ULONG   (STDMETHODCALLTYPE *Release) (WP_IShellItemImageFactory *This);
	HRESULT (STDMETHODCALLTYPE *GetImage) (WP_IShellItemImageFactory *This, SIZE size, int flags, HBITMAP *phbm);
} WP_IShellItemImageFactoryVtbl;
struct WP_IShellItemImageFactory {
	const WP_IShellItemImageFactoryVtbl *lpVtbl;
};

/* Explicit Win8+ COM IApplicationActivationManager vtable (safe with _WIN32_WINNT=0x0601) */
typedef struct WP_IApplicationActivationManager WP_IApplicationActivationManager;
typedef struct WP_IApplicationActivationManagerVtbl {
	HRESULT (STDMETHODCALLTYPE *QueryInterface) (WP_IApplicationActivationManager *This, REFIID riid, void **ppvObject);
	ULONG   (STDMETHODCALLTYPE *AddRef) (WP_IApplicationActivationManager *This);
	ULONG   (STDMETHODCALLTYPE *Release) (WP_IApplicationActivationManager *This);
	HRESULT (STDMETHODCALLTYPE *ActivateApplication) (WP_IApplicationActivationManager *This, LPCWSTR appUserModelId, LPCWSTR arguments, DWORD options, DWORD *processId);
	HRESULT (STDMETHODCALLTYPE *ActivateForFile) (WP_IApplicationActivationManager *This, LPCWSTR appUserModelId, IShellItemArray *itemArray, LPCWSTR verb, DWORD *processId);
	HRESULT (STDMETHODCALLTYPE *ActivateForProtocol) (WP_IApplicationActivationManager *This, LPCWSTR appUserModelId, IShellItemArray *itemArray, DWORD *processId);
} WP_IApplicationActivationManagerVtbl;
struct WP_IApplicationActivationManager {
	const WP_IApplicationActivationManagerVtbl *lpVtbl;
};

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
	case WIN32_FOLDER_COMMON_STARTMENU:  csidl = CSIDL_COMMON_STARTMENU; break;
	case WIN32_FOLDER_USER_STARTMENU:    csidl = CSIDL_STARTMENU; break;
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
win32_app_get_file_stamp (const char *path, int64_t *out_mtime_sec, int64_t *out_size)
{
	if (out_mtime_sec) *out_mtime_sec = 0;
	if (out_size) *out_size = 0;

#ifdef _WIN32
	if (path == NULL || path[0] == '\0')
		return 0;
	WCHAR *wpath = utf8_to_wide (path);
	if (wpath == NULL)
		return 0;

	WIN32_FILE_ATTRIBUTE_DATA fad;
	BOOL ok = GetFileAttributesExW (wpath, GetFileExInfoStandard, &fad);
	g_free (wpath);
	if (!ok || (fad.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
		return 0;

	uint64_t ft = (((uint64_t) fad.ftLastWriteTime.dwHighDateTime) << 32)
		| (uint64_t) fad.ftLastWriteTime.dwLowDateTime;
	uint64_t fsz = (((uint64_t) fad.nFileSizeHigh) << 32)
		| (uint64_t) fad.nFileSizeLow;

	if (out_mtime_sec) *out_mtime_sec = (int64_t) (ft / 10000000ULL);
	if (out_size) *out_size = (int64_t) fsz;
	return 1;
#else
	(void) path;
	return 0;
#endif
}

#ifdef _WIN32
static volatile gint g_drive_type_cache[26] = { 0 };
#endif

int
win32_app_is_fixed_local_drive (const char *path)
{
#ifdef _WIN32
	if (path == NULL || path[0] == '\0')
		return 0;
	if ((path[0] == '\\' && path[1] == '\\') || (path[0] == '/' && path[1] == '/'))
		return 0;
	if (path[1] != ':')
		return 0;

	char c = path[0];
	if (c >= 'a' && c <= 'z')
		c = (char) (c - 'a' + 'A');
	if (c < 'A' || c > 'Z')
		return 0;

	int idx = c - 'A';
	gint cached = g_atomic_int_get (&g_drive_type_cache[idx]);
	if (cached == 0) {
		WCHAR root[4] = { (WCHAR) c, L':', L'\\', L'\0' };
		UINT dtype = GetDriveTypeW (root);
		cached = (dtype == DRIVE_FIXED) ? 1 : 2;
		g_atomic_int_set (&g_drive_type_cache[idx], cached);
	}
	return (cached == 1) ? 1 : 0;
#else
	(void) path;
	return 1;
#endif
}

void
win32_app_set_thread_low_priority (void)
{
#ifdef _WIN32
	SetThreadPriority (GetCurrentThread (), THREAD_PRIORITY_BELOW_NORMAL);
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

	HRESULT com_hr = CoInitializeEx (NULL, COINIT_APARTMENTTHREADED);
	int com_did_init = SUCCEEDED (com_hr) ? 1 : 0;

	WCHAR *wlnk = utf8_to_wide (lnk_path);
	if (wlnk == NULL) {
		if (com_did_init) CoUninitialize ();
		return 0;
	}

	IShellLinkW *psl = NULL;
	HRESULT hr = CoCreateInstance (&WP_CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, &WP_IID_IShellLinkW, (void **) &psl);
	if (FAILED (hr) || psl == NULL) {
		g_free (wlnk);
		if (com_did_init) CoUninitialize ();
		return 0;
	}

	IPersistFile *ppf = NULL;
	hr = IShellLinkW_QueryInterface (psl, &WP_IID_IPersistFile, (void **) &ppf);
	if (FAILED (hr) || ppf == NULL) {
		IShellLinkW_Release (psl);
		g_free (wlnk);
		if (com_did_init) CoUninitialize ();
		return 0;
	}

	hr = IPersistFile_Load (ppf, wlnk, STGM_READ);
	g_free (wlnk);
	if (FAILED (hr)) {
		IPersistFile_Release (ppf);
		IShellLinkW_Release (psl);
		if (com_did_init) CoUninitialize ();
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
	/* Strictly non-blocking path extraction: use SLGP_RAWPATH + in-memory PIDL only.
	 * NEVER call GetPath(..., 0), which triggers 20-45s MSI Advertised Shortcut /
	 * Distributed Link Tracking / SMB timeouts on Start Menu subdirectories. */
	IShellLinkW_GetPath (psl, target_w, (int) (sizeof (target_w) / sizeof (target_w[0])), &wfd, SLGP_RAWPATH);
	if (target_w[0] == L'\0') {
		LPITEMIDLIST pidl = NULL;
		if (SUCCEEDED (IShellLinkW_GetIDList (psl, &pidl)) && pidl != NULL) {
			SHGetPathFromIDListW (pidl, target_w);
			CoTaskMemFree (pidl);
		}
	}

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
	if (com_did_init) CoUninitialize ();

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
load_sys_image_list_icon (int sys_icon_index)
{
	HICON hIcon = NULL;
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
				HRESULT hr = IImageList_GetIcon (iml, sys_icon_index, ILD_TRANSPARENT, &hIcon);
				IImageList_Release (iml);
				if (SUCCEEDED (hr) && hIcon != NULL)
					return hIcon;
			}
		}
	}
	return NULL;
}

#ifdef _WIN32
#ifndef LOAD_LIBRARY_AS_IMAGE_RESOURCE
#define LOAD_LIBRARY_AS_IMAGE_RESOURCE 0x00000020
#endif

typedef struct {
	WCHAR wpath[MAX_PATH];
	char *utf8_path;
	HMODULE hmod;
} Win32IconStoreEntry;

static const WCHAR * const WIN32_EXPLORER_ICON_STORES[] = {
	L"imageres.dll",
	L"ddores.dll",
	L"shell32.dll",
	NULL
};

static Win32IconStoreEntry win32_icon_stores[4];
static int win32_icon_store_count = 0;
static int win32_icon_stores_initialized = 0;

static void
ensure_icon_stores_loaded (void)
{
	if (win32_icon_stores_initialized)
		return;
	win32_icon_stores_initialized = 1;

	WCHAR sys_dir[MAX_PATH];
	UINT sys_len = GetSystemDirectoryW (sys_dir, MAX_PATH);
	if (sys_len == 0 || sys_len >= MAX_PATH - 32)
		return;

	for (int i = 0; WIN32_EXPLORER_ICON_STORES[i] != NULL && win32_icon_store_count < 4; i++) {
		WCHAR full_path[MAX_PATH];
		wcsncpy (full_path, sys_dir, MAX_PATH - 1);
		full_path[MAX_PATH - 1] = L'\0';
		size_t cur_len = wcslen (full_path);
		if (cur_len > 0 && full_path[cur_len - 1] != L'\\' && cur_len + 1 < MAX_PATH) {
			full_path[cur_len++] = L'\\';
			full_path[cur_len] = L'\0';
		}
		wcsncat (full_path, WIN32_EXPLORER_ICON_STORES[i], MAX_PATH - 1 - cur_len);

		HMODULE hmod = LoadLibraryExW (
			full_path,
			NULL,
			LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE
		);
		if (hmod == NULL)
			hmod = LoadLibraryExW (full_path, NULL, LOAD_LIBRARY_AS_DATAFILE);
		if (hmod == NULL)
			continue;

		char *u8 = wide_to_utf8 (full_path);
		if (u8 == NULL) {
			FreeLibrary (hmod);
			continue;
		}
		Win32IconStoreEntry *ent = &win32_icon_stores[win32_icon_store_count++];
		wcsncpy (ent->wpath, full_path, MAX_PATH - 1);
		ent->wpath[MAX_PATH - 1] = L'\0';
		ent->utf8_path = u8;
		ent->hmod = hmod;
	}
}

static HICON
load_hicon_from_cached_store (const WCHAR *wpath, int icon_index, int desired_size)
{
	if (wpath == NULL || icon_index >= 0)
		return NULL;

	ensure_icon_stores_loaded ();
	unsigned int res_id = (unsigned int) (-icon_index);
	if (res_id == 0 || res_id > 0xFFFFU)
		return NULL;

	for (int i = 0; i < win32_icon_store_count; i++) {
		if (_wcsicmp (wpath, win32_icon_stores[i].wpath) != 0)
			continue;
		HMODULE hmod = win32_icon_stores[i].hmod;
		HRSRC hGrp = FindResourceW (hmod, MAKEINTRESOURCEW ((WORD) res_id), MAKEINTRESOURCEW ((WORD) (uintptr_t) RT_GROUP_ICON));
		if (hGrp == NULL)
			return NULL;
		HGLOBAL hGrpMem = LoadResource (hmod, hGrp);
		if (hGrpMem == NULL)
			return NULL;
		PBYTE grp_bits = (PBYTE) LockResource (hGrpMem);
		if (grp_bits == NULL)
			return NULL;

		int want_sz = (desired_size <= 48) ? 64 : ((desired_size < 256) ? 256 : desired_size);
		int best_id = LookupIconIdFromDirectoryEx (grp_bits, TRUE, want_sz, want_sz, LR_DEFAULTCOLOR);
		if (best_id <= 0)
			return NULL;

		HRSRC hIco = FindResourceW (hmod, MAKEINTRESOURCEW ((WORD) best_id), MAKEINTRESOURCEW ((WORD) (uintptr_t) RT_ICON));
		if (hIco == NULL)
			return NULL;
		HGLOBAL hIcoMem = LoadResource (hmod, hIco);
		DWORD ico_sz = SizeofResource (hmod, hIco);
		if (hIcoMem == NULL || ico_sz == 0)
			return NULL;
		PBYTE ico_bits = (PBYTE) LockResource (hIcoMem);
		if (ico_bits == NULL)
			return NULL;

		return CreateIconFromResourceEx (
			ico_bits, ico_sz, TRUE, 0x00030000, want_sz, want_sz, LR_DEFAULTCOLOR
		);
	}
	return NULL;
}

typedef struct {
	const char *utf8_path;
	Win32EnumIconTokenCallback cb;
	void *user_data;
} Win32EnumStoreCtx;

static BOOL CALLBACK
enum_res_group_icon_cb (HMODULE hModule, LPCWSTR lpType, LPWSTR lpName, LONG_PTR lParam)
{
	(void) hModule;
	(void) lpType;
	Win32EnumStoreCtx *ctx = (Win32EnumStoreCtx *) lParam;
	if (ctx == NULL || ctx->cb == NULL || ctx->utf8_path == NULL)
		return FALSE;

	if (IS_INTRESOURCE (lpName)) {
		unsigned int res_id = (unsigned int) (uintptr_t) lpName;
		if (res_id > 0 && res_id <= 0xFFFFU) {
			char token[MAX_PATH * 4];
			g_snprintf (token, sizeof (token), "%s,-%u", ctx->utf8_path, res_id);
			ctx->cb (token, ctx->user_data);
		}
	}
	return TRUE;
}
#endif

static HICON
load_best_hicon (const WCHAR *wpath, int icon_index, int desired_size)
{
	HICON hIcon = NULL;
	int hi_size = (desired_size <= 48) ? 64 : ((desired_size < 256) ? 256 : desired_size);

	/* 0. Fast zero-NTFS-reopen path for cached read-only system Explorer icon stores */
	if (icon_index < 0) {
		hIcon = load_hicon_from_cached_store (wpath, icon_index, desired_size);
		if (hIcon != NULL)
			return hIcon;
	}

	/* 1. For index 0, prefer SHGetImageList(SHIL_JUMBO = 256x256) first so Windows
	 * returns native 256px Fluent/Aero/Flat icons instead of upscaling 32x32 resources. */
	if (icon_index == 0) {
		SHFILEINFOW sfi;
		memset (&sfi, 0, sizeof (sfi));
		if (SHGetFileInfoW (wpath, 0, &sfi, sizeof (sfi), SHGFI_SYSICONINDEX) != 0) {
			hIcon = load_sys_image_list_icon (sfi.iIcon);
			if (hIcon != NULL)
				return hIcon;
		}
	}

	/* 2. Explicit icon index or direct .exe/.dll/.ico via PrivateExtractIconsW at 256px first */
	{
		UINT icon_id = 0;
		UINT extracted = PrivateExtractIconsW (
			wpath, icon_index, hi_size, hi_size,
			&hIcon, &icon_id, 1, LR_DEFAULTCOLOR
		);
		if (extracted > 0 && hIcon != NULL)
			return hIcon;
		if (hi_size != desired_size) {
			extracted = PrivateExtractIconsW (
				wpath, icon_index, desired_size, desired_size,
				&hIcon, &icon_id, 1, LR_DEFAULTCOLOR
			);
			if (extracted > 0 && hIcon != NULL)
				return hIcon;
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

	/* Reject completely transparent/empty bitmaps (e.g. deprecated/empty Windows 11 stock slots) */
	int has_visible = 0;
	for (size_t i = 3; i < byte_len; i += 4) {
		if (rgba[i] > 0) {
			has_visible = 1;
			break;
		}
	}
	if (!has_visible) {
		g_free (rgba);
		return 0;
	}

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

	/* Render with 2x supersampling for small chooser tiles and >=128px for dock icons */
	int render_sz = (size <= 48) ? 64 : ((size < 128) ? 128 : size);
	int ok = render_hicon_to_rgba (hIcon, render_sz, out_rgba, out_w, out_h);
	DestroyIcon (hIcon);
	return ok;
#else
	(void) path_or_icon_spec;
	(void) desired_size;
	return 0;
#endif
}

int
win32_app_extract_stock_icon_rgba (
	int stock_id,
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
	if (stock_id < 0)
		return 0;

	ensure_com ();
	int size = (desired_size > 0) ? desired_size : 64;
	if (size > 256) size = 256;
	int render_sz = (size <= 48) ? 64 : ((size < 128) ? 128 : size);

	HMODULE hShell = GetModuleHandleW (L"shell32.dll");
	if (hShell == NULL)
		hShell = LoadLibraryW (L"shell32.dll");
	if (hShell == NULL)
		return 0;

	PFN_SHGetStockIconInfo pfn_SHGetStockIconInfo =
		(PFN_SHGetStockIconInfo) GetProcAddress (hShell, "SHGetStockIconInfo");
	if (pfn_SHGetStockIconInfo == NULL)
		return 0;

	SHSTOCKICONINFO sii;
	memset (&sii, 0, sizeof (sii));
	sii.cbSize = sizeof (sii);
	if (SUCCEEDED (pfn_SHGetStockIconInfo ((SHSTOCKICONID) stock_id, SHGSI_SYSICONINDEX, &sii))) {
		HICON hIcon = load_sys_image_list_icon (sii.iSysImageIndex);
		if (hIcon != NULL) {
			int ok = render_hicon_to_rgba (hIcon, render_sz, out_rgba, out_w, out_h);
			DestroyIcon (hIcon);
			if (ok != 0)
				return ok;
		}
	}

	memset (&sii, 0, sizeof (sii));
	sii.cbSize = sizeof (sii);
	if (SUCCEEDED (pfn_SHGetStockIconInfo ((SHSTOCKICONID) stock_id, SHGSI_ICON | SHGSI_LARGEICON, &sii))
		&& sii.hIcon != NULL) {
		int ok = render_hicon_to_rgba (sii.hIcon, render_sz, out_rgba, out_w, out_h);
		DestroyIcon (sii.hIcon);
		if (ok != 0)
			return ok;
	}
	return 0;
#else
	(void) stock_id;
	(void) desired_size;
	return 0;
#endif
}

int
win32_app_extract_aumid_icon_rgba (
	const char *aumid,
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
	if (aumid == NULL || aumid[0] == '\0')
		return 0;
	ensure_com ();

	static PFN_SHCreateItemFromParsingName pfn_create_item = NULL;
	static int resolved = 0;
	if (!resolved) {
		resolved = 1;
		HMODULE hShell = GetModuleHandleW (L"shell32.dll");
		if (hShell == NULL)
			hShell = LoadLibraryW (L"shell32.dll");
		if (hShell != NULL)
			pfn_create_item = (PFN_SHCreateItemFromParsingName) (void *) GetProcAddress (hShell, "SHCreateItemFromParsingName");
	}
	if (pfn_create_item == NULL)
		return 0;

	WCHAR *waumid = utf8_to_wide (aumid);
	if (waumid == NULL)
		return 0;

	gsize prefix_len = wcslen (L"shell:AppsFolder\\");
	gsize id_len = wcslen (waumid);
	WCHAR *parse_name = (WCHAR *) g_malloc ((prefix_len + id_len + 1) * sizeof (WCHAR));
	memcpy (parse_name, L"shell:AppsFolder\\", prefix_len * sizeof (WCHAR));
	memcpy (parse_name + prefix_len, waumid, (id_len + 1) * sizeof (WCHAR));
	g_free (waumid);

	WP_IShellItemImageFactory *factory = NULL;
	HRESULT hr = pfn_create_item (parse_name, NULL, &WP_IID_IShellItemImageFactory, (void **) &factory);
	g_free (parse_name);
	if (FAILED (hr) || factory == NULL)
		return 0;

	int size = (desired_size > 0) ? desired_size : 64;
	if (size > 256) size = 256;
	int render_sz = (size <= 48) ? 64 : ((size < 128) ? 128 : size);

	SIZE sz;
	sz.cx = render_sz;
	sz.cy = render_sz;
	HBITMAP hbm = NULL;
	/* Prefer clean transparent icon logo without solid UWP Start tile background */
	hr = factory->lpVtbl->GetImage (factory, sz, 0x04 | 0x01 /* SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK */, &hbm);
	if (FAILED (hr) || hbm == NULL) {
		hbm = NULL;
		hr = factory->lpVtbl->GetImage (factory, sz, 0x01 /* SIIGBF_BIGGERSIZEOK */, &hbm);
	}
	factory->lpVtbl->Release (factory);
	if (FAILED (hr) || hbm == NULL)
		return 0;

	BITMAP bm;
	memset (&bm, 0, sizeof (bm));
	if (GetObjectW (hbm, sizeof (bm), &bm) == 0 || bm.bmWidth <= 0 || bm.bmHeight <= 0) {
		DeleteObject (hbm);
		return 0;
	}

	int w = bm.bmWidth;
	int h = bm.bmHeight;
	size_t byte_len = (size_t) w * (size_t) h * 4;
	uint8_t *bgra = (uint8_t *) g_malloc0 (byte_len);

	BITMAPINFO bmi;
	memset (&bmi, 0, sizeof (bmi));
	bmi.bmiHeader.biSize = sizeof (BITMAPINFOHEADER);
	bmi.bmiHeader.biWidth = w;
	bmi.bmiHeader.biHeight = -h; /* Top-down */
	bmi.bmiHeader.biPlanes = 1;
	bmi.bmiHeader.biBitCount = 32;
	bmi.bmiHeader.biCompression = BI_RGB;

	HDC hdc = GetDC (NULL);
	int got = (hdc != NULL) ? GetDIBits (hdc, hbm, 0, (UINT) h, bgra, &bmi, DIB_RGB_COLORS) : 0;
	if (hdc != NULL)
		ReleaseDC (NULL, hdc);
	DeleteObject (hbm);

	if (got == 0) {
		g_free (bgra);
		return 0;
	}

	int has_alpha = 0;
	for (size_t i = 3; i < byte_len; i += 4) {
		if (bgra[i] != 0) {
			has_alpha = 1;
			break;
		}
	}

	uint8_t *rgba = (uint8_t *) g_malloc (byte_len);
	if (has_alpha) {
		/* Un-premultiply 32-bit BGRA Shell bitmap -> straight RGBA for GdkPixbuf */
		for (size_t i = 0; i < byte_len; i += 4) {
			uint8_t a = bgra[i + 3];
			if (a == 0) {
				rgba[i + 0] = 0;
				rgba[i + 1] = 0;
				rgba[i + 2] = 0;
				rgba[i + 3] = 0;
			} else if (a == 255) {
				rgba[i + 0] = bgra[i + 2];
				rgba[i + 1] = bgra[i + 1];
				rgba[i + 2] = bgra[i + 0];
				rgba[i + 3] = 255;
			} else {
				unsigned int r = ((unsigned int) bgra[i + 2] * 255U + (unsigned int) (a / 2)) / (unsigned int) a;
				unsigned int g = ((unsigned int) bgra[i + 1] * 255U + (unsigned int) (a / 2)) / (unsigned int) a;
				unsigned int b = ((unsigned int) bgra[i + 0] * 255U + (unsigned int) (a / 2)) / (unsigned int) a;
				rgba[i + 0] = (uint8_t) (r > 255U ? 255U : r);
				rgba[i + 1] = (uint8_t) (g > 255U ? 255U : g);
				rgba[i + 2] = (uint8_t) (b > 255U ? 255U : b);
				rgba[i + 3] = a;
			}
		}
	} else {
		for (size_t i = 0; i < byte_len; i += 4) {
			rgba[i + 0] = bgra[i + 2];
			rgba[i + 1] = bgra[i + 1];
			rgba[i + 2] = bgra[i + 0];
			rgba[i + 3] = 255;
		}
	}
	g_free (bgra);

	if (out_rgba) *out_rgba = rgba;
	else g_free (rgba);
	if (out_w) *out_w = w;
	if (out_h) *out_h = h;
	return 1;
#else
	(void) aumid;
	(void) desired_size;
	return 0;
#endif
}

void
win32_app_enum_system_icon_stores (Win32EnumIconTokenCallback cb, void *user_data)
{
#ifdef _WIN32
	if (cb == NULL)
		return;
	ensure_icon_stores_loaded ();
	for (int i = 0; i < win32_icon_store_count; i++) {
		Win32EnumStoreCtx ctx;
		ctx.utf8_path = win32_icon_stores[i].utf8_path;
		ctx.cb = cb;
		ctx.user_data = user_data;
		EnumResourceNamesW (
			win32_icon_stores[i].hmod,
			MAKEINTRESOURCEW ((WORD) (uintptr_t) RT_GROUP_ICON),
			enum_res_group_icon_cb,
			(LONG_PTR) &ctx
		);
	}
#else
	(void) cb;
	(void) user_data;
#endif
}

#ifdef _WIN32
static void
extract_exe_basename_lower (const WCHAR *cmd, char *out_buf, size_t out_sz)
{
	out_buf[0] = '\0';
	if (cmd == NULL || cmd[0] == L'\0' || out_sz < 2)
		return;

	while (*cmd == L' ' || *cmd == L'\t')
		cmd++;
	WCHAR tok[MAX_PATH * 2];
	size_t ti = 0;
	if (*cmd == L'"') {
		cmd++;
		while (*cmd != L'\0' && *cmd != L'"' && ti + 1 < sizeof (tok) / sizeof (tok[0]))
			tok[ti++] = *cmd++;
	} else {
		while (*cmd != L'\0' && *cmd != L' ' && *cmd != L'\t' && ti + 1 < sizeof (tok) / sizeof (tok[0]))
			tok[ti++] = *cmd++;
	}
	tok[ti] = L'\0';
	if (tok[0] == L'\0')
		return;

	const WCHAR *base = tok;
	for (const WCHAR *p = tok; *p != L'\0'; p++) {
		if (*p == L'\\' || *p == L'/')
			base = p + 1;
	}
	char *u8 = wide_to_utf8 (base);
	if (u8 != NULL) {
		size_t i = 0;
		for (; u8[i] != '\0' && i + 1 < out_sz; i++)
			out_buf[i] = (char) tolower ((unsigned char) u8[i]);
		out_buf[i] = '\0';
		g_free (u8);
	}
}

static int
progid_matches_exe (const WCHAR *progid, const char *target_exe)
{
	if (progid == NULL || progid[0] == L'\0')
		return 0;
	static const WCHAR *verbs[2] = { L"open", L"edit" };
	for (int v = 0; v < 2; v++) {
		WCHAR subkey[512];
		if (_snwprintf (subkey, sizeof (subkey) / sizeof (subkey[0]), L"%ls\\shell\\%ls\\command", progid, verbs[v]) <= 0)
			continue;
		subkey[(sizeof (subkey) / sizeof (subkey[0])) - 1] = L'\0';
		WCHAR cmd[MAX_PATH * 4];
		DWORD sz = sizeof (cmd);
		DWORD type = 0;
		if (RegGetValueW (HKEY_CLASSES_ROOT, subkey, NULL, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ, &type, cmd, &sz) == ERROR_SUCCESS) {
			char exe_low[260];
			extract_exe_basename_lower (cmd, exe_low, sizeof (exe_low));
			if (exe_low[0] != '\0' && strcmp (exe_low, target_exe) == 0)
				return 1;
		}
	}
	return 0;
}
#endif

int
win32_app_exe_handles_ext (const char *exe_basename, const char *dot_ext)
{
#ifdef _WIN32
	if (exe_basename == NULL || exe_basename[0] == '\0'
		|| dot_ext == NULL || dot_ext[0] != '.' || dot_ext[1] == '\0')
		return 0;

	char target_exe[260];
	size_t n = 0;
	for (; exe_basename[n] != '\0' && n + 1 < sizeof (target_exe); n++)
		target_exe[n] = (char) tolower ((unsigned char) exe_basename[n]);
	target_exe[n] = '\0';

	WCHAR *wext = utf8_to_wide (dot_ext);
	if (wext == NULL)
		return 0;

	/* 1. Default handler via AssocQueryStringW (shlwapi.dll) */
	WCHAR assoc_buf[MAX_PATH * 2];
	DWORD assoc_len = (DWORD) (sizeof (assoc_buf) / sizeof (assoc_buf[0]));
	if (SUCCEEDED (AssocQueryStringW (ASSOCF_NONE, ASSOCSTR_EXECUTABLE, wext, NULL, assoc_buf, &assoc_len)) && assoc_buf[0] != L'\0') {
		char def_exe[260];
		extract_exe_basename_lower (assoc_buf, def_exe, sizeof (def_exe));
		if (def_exe[0] != '\0' && strcmp (def_exe, target_exe) == 0) {
			g_free (wext);
			return 2;
		}
	}

	/* 2. HKCU Explorer\FileExts\<ext>\UserChoice */
	WCHAR fe_key[512];
	if (_snwprintf (fe_key, sizeof (fe_key) / sizeof (fe_key[0]),
		L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\%ls\\UserChoice", wext) > 0) {
		WCHAR progid[256];
		DWORD sz = sizeof (progid);
		if (RegGetValueW (HKEY_CURRENT_USER, fe_key, L"ProgId", RRF_RT_REG_SZ, NULL, progid, &sz) == ERROR_SUCCESS) {
			if (progid_matches_exe (progid, target_exe)) {
				g_free (wext);
				return 2;
			}
		}
	}

	/* 3. HKCU Explorer\FileExts\<ext>\OpenWithList */
	if (_snwprintf (fe_key, sizeof (fe_key) / sizeof (fe_key[0]),
		L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\%ls\\OpenWithList", wext) > 0) {
		HKEY hKey = NULL;
		if (RegOpenKeyExW (HKEY_CURRENT_USER, fe_key, 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
			for (DWORD i = 0; i < 64; i++) {
				WCHAR vname[128];
				DWORD vname_len = (DWORD) (sizeof (vname) / sizeof (vname[0]));
				WCHAR vdata[260];
				DWORD vdata_sz = sizeof (vdata);
				DWORD type = 0;
				if (RegEnumValueW (hKey, i, vname, &vname_len, NULL, &type, (LPBYTE) vdata, &vdata_sz) != ERROR_SUCCESS)
					break;
				if (type == REG_SZ && _wcsicmp (vname, L"MRUList") != 0) {
					char cand[260];
					extract_exe_basename_lower (vdata, cand, sizeof (cand));
					if (cand[0] != '\0' && strcmp (cand, target_exe) == 0) {
						RegCloseKey (hKey);
						g_free (wext);
						return 1;
					}
				}
			}
			RegCloseKey (hKey);
		}
	}

	/* 4. HKCU FileExts\<ext>\OpenWithProgids and HKCR\<ext>\OpenWithProgids */
	HKEY roots[2] = { HKEY_CURRENT_USER, HKEY_CLASSES_ROOT };
	WCHAR pid_keys[2][512];
	_snwprintf (pid_keys[0], 512, L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\%ls\\OpenWithProgids", wext);
	_snwprintf (pid_keys[1], 512, L"%ls\\OpenWithProgids", wext);
	for (int r = 0; r < 2; r++) {
		HKEY hKey = NULL;
		if (RegOpenKeyExW (roots[r], pid_keys[r], 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
			for (DWORD i = 0; i < 64; i++) {
				WCHAR vname[256];
				DWORD vname_len = (DWORD) (sizeof (vname) / sizeof (vname[0]));
				if (RegEnumValueW (hKey, i, vname, &vname_len, NULL, NULL, NULL, NULL) != ERROR_SUCCESS)
					break;
				if (vname[0] != L'\0' && progid_matches_exe (vname, target_exe)) {
					RegCloseKey (hKey);
					g_free (wext);
					return 1;
				}
			}
			RegCloseKey (hKey);
		}
	}

	/* 5. HKCR\<ext>\OpenWithList\<exe_basename> and HKCR\Applications\<exe_basename>\SupportedTypes\<ext> */
	WCHAR *wexe = utf8_to_wide (target_exe);
	if (wexe != NULL) {
		WCHAR owl_sub[512];
		if (_snwprintf (owl_sub, 512, L"%ls\\OpenWithList\\%ls", wext, wexe) > 0) {
			HKEY hTest = NULL;
			if (RegOpenKeyExW (HKEY_CLASSES_ROOT, owl_sub, 0, KEY_READ, &hTest) == ERROR_SUCCESS) {
				RegCloseKey (hTest);
				g_free (wexe);
				g_free (wext);
				return 1;
			}
		}
		WCHAR sup_sub[512];
		if (_snwprintf (sup_sub, 512, L"Applications\\%ls\\SupportedTypes", wexe) > 0) {
			HKEY hSup = NULL;
			if (RegOpenKeyExW (HKEY_CLASSES_ROOT, sup_sub, 0, KEY_READ, &hSup) == ERROR_SUCCESS) {
				LONG st = RegQueryValueExW (hSup, wext, NULL, NULL, NULL, NULL);
				RegCloseKey (hSup);
				if (st == ERROR_SUCCESS) {
					g_free (wexe);
					g_free (wext);
					return 1;
				}
			}
		}
		g_free (wexe);
	}

	g_free (wext);
	return 0;
#else
	(void) exe_basename;
	(void) dot_ext;
	return 0;
#endif
}

int
win32_app_enum_jump_list_recent (
	const char *app_id,
	int max_items,
	Win32EnumRecentDocCallback cb,
	void *user_data)
{
#ifdef _WIN32
	if (app_id == NULL || app_id[0] == '\0' || max_items <= 0 || cb == NULL)
		return 0;

	WCHAR *wapp_id = utf8_to_wide (app_id);
	if (wapp_id == NULL)
		return 0;

	HRESULT hr_com = CoInitializeEx (NULL, COINIT_APARTMENTTHREADED);
	BOOL need_uninit = SUCCEEDED (hr_com);

	int emitted = 0;
	IApplicationDocumentLists *pDocLists = NULL;
	HRESULT hr = CoCreateInstance (
		&WP_CLSID_ApplicationDocumentLists,
		NULL,
		CLSCTX_INPROC_SERVER,
		&WP_IID_IApplicationDocumentLists,
		(void **) &pDocLists);

	if (SUCCEEDED (hr) && pDocLists != NULL) {
		if (SUCCEEDED (pDocLists->lpVtbl->SetAppID (pDocLists, wapp_id))) {
			APPDOCLISTTYPE list_types[2] = { ADLT_RECENT, ADLT_FREQUENT };
			for (int lt = 0; lt < 2 && emitted == 0; lt++) {
				IObjectArray *pArr = NULL;
				hr = pDocLists->lpVtbl->GetList (
					pDocLists,
					list_types[lt],
					(UINT) max_items,
					&WP_IID_IObjectArray,
					(void **) &pArr);
				if (FAILED (hr) || pArr == NULL)
					continue;

				UINT count = 0;
				if (SUCCEEDED (pArr->lpVtbl->GetCount (pArr, &count))) {
					for (UINT i = 0; i < count && emitted < max_items; i++) {
						char *resolved = NULL;

						IShellItem *pItem = NULL;
						if (SUCCEEDED (pArr->lpVtbl->GetAt (pArr, i, &WP_IID_IShellItem, (void **) &pItem)) && pItem != NULL) {
							PWSTR wpath = NULL;
							if (SUCCEEDED (pItem->lpVtbl->GetDisplayName (pItem, SIGDN_FILESYSPATH, &wpath)) && wpath != NULL) {
								if (wpath[0] != L'\0')
									resolved = wide_to_utf8 (wpath);
								CoTaskMemFree (wpath);
							}
							pItem->lpVtbl->Release (pItem);
						} else {
							IShellLinkW *pLink = NULL;
							if (SUCCEEDED (pArr->lpVtbl->GetAt (pArr, i, &WP_IID_IShellLinkW, (void **) &pLink)) && pLink != NULL) {
								WCHAR buf[MAX_PATH * 4];
								buf[0] = L'\0';
								if (SUCCEEDED (pLink->lpVtbl->GetPath (pLink, buf, MAX_PATH * 4, NULL, SLGP_RAWPATH)) && buf[0] != L'\0') {
									resolved = wide_to_utf8 (buf);
								} else {
									PIDLIST_ABSOLUTE pidl = NULL;
									if (SUCCEEDED (pLink->lpVtbl->GetIDList (pLink, &pidl)) && pidl != NULL) {
										if (SHGetPathFromIDListW (pidl, buf) && buf[0] != L'\0')
											resolved = wide_to_utf8 (buf);
										CoTaskMemFree (pidl);
									}
								}
								pLink->lpVtbl->Release (pLink);
							}
						}

						if (resolved != NULL && resolved[0] != '\0') {
							if (win32_app_is_fixed_local_drive (resolved) != 0) {
								cb (resolved, user_data);
								emitted++;
							}
						}
						g_free (resolved);
					}
				}
				pArr->lpVtbl->Release (pArr);
			}
		}
		pDocLists->lpVtbl->Release (pDocLists);
	}

	if (need_uninit)
		CoUninitialize ();
	g_free (wapp_id);
	return emitted;
#else
	(void) app_id;
	(void) max_items;
	(void) cb;
	(void) user_data;
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
win32_app_activate_aumid (
	const char *aumid,
	const char *args
)
{
#ifdef _WIN32
	if (aumid == NULL || aumid[0] == '\0')
		return 0;
	ensure_com ();

	WCHAR *waumid = utf8_to_wide (aumid);
	if (waumid == NULL)
		return 0;
	WCHAR *wargs = (args != NULL && args[0] != '\0') ? utf8_to_wide (args) : NULL;

	int launched = 0;
	WP_IApplicationActivationManager *paam = NULL;
	HRESULT hr = CoCreateInstance (
		&WP_CLSID_ApplicationActivationManager,
		NULL,
		CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER,
		&WP_IID_IApplicationActivationManager,
		(void **) &paam
	);
	if (SUCCEEDED (hr) && paam != NULL) {
		DWORD pid = 0;
		hr = paam->lpVtbl->ActivateApplication (paam, waumid, wargs, 0 /* AO_NONE */, &pid);
		if (SUCCEEDED (hr))
			launched = 1;
		paam->lpVtbl->Release (paam);
	}

	if (!launched) {
		gsize prefix_len = wcslen (L"shell:AppsFolder\\");
		gsize id_len = wcslen (waumid);
		WCHAR *shell_uri = (WCHAR *) g_malloc ((prefix_len + id_len + 1) * sizeof (WCHAR));
		memcpy (shell_uri, L"shell:AppsFolder\\", prefix_len * sizeof (WCHAR));
		memcpy (shell_uri + prefix_len, waumid, (id_len + 1) * sizeof (WCHAR));
		HINSTANCE res = ShellExecuteW (NULL, L"open", shell_uri, wargs, NULL, SW_SHOWNORMAL);
		g_free (shell_uri);
		if ((intptr_t) res > 32)
			launched = 1;
	}

	g_free (waumid);
	g_free (wargs);
	return launched;
#else
	(void) aumid;
	(void) args;
	return 0;
#endif
}

char *
win32_app_get_process_aumid (int pid)
{
#ifdef _WIN32
	if (pid <= 0)
		return NULL;
	static PFN_GetApplicationUserModelId pfn_get_aumid = NULL;
	static int resolved = 0;
	if (!resolved) {
		resolved = 1;
		HMODULE hKernel = GetModuleHandleW (L"kernel32.dll");
		if (hKernel != NULL)
			pfn_get_aumid = (PFN_GetApplicationUserModelId) (void *) GetProcAddress (hKernel, "GetApplicationUserModelId");
	}
	if (pfn_get_aumid == NULL)
		return NULL;

	HANDLE hProc = OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD) pid);
	if (hProc == NULL)
		return NULL;

	UINT32 len = 0;
	LONG rc = pfn_get_aumid (hProc, &len, NULL);
	char *result = NULL;
	if (rc == ERROR_INSUFFICIENT_BUFFER && len > 1 && len < 2048) {
		WCHAR *buf = (WCHAR *) g_malloc0 ((gsize) (len + 2) * sizeof (WCHAR));
		if (pfn_get_aumid (hProc, &len, buf) == ERROR_SUCCESS && buf[0] != L'\0')
			result = wide_to_utf8 (buf);
		g_free (buf);
	}
	CloseHandle (hProc);
	return result;
#else
	(void) pid;
	return NULL;
#endif
}

#ifdef _WIN32
static int
extract_windowsapps_family_and_stem (const char *exe_path, char **out_family, char **out_stem)
{
	if (out_family) *out_family = NULL;
	if (out_stem) *out_stem = NULL;
	if (exe_path == NULL || exe_path[0] == '\0')
		return 0;

	char *lower = g_ascii_strdown (exe_path, -1);
	const char *marker = strstr (lower, "\\windowsapps\\");
	if (marker == NULL)
		marker = strstr (lower, "/windowsapps/");
	if (marker == NULL) {
		g_free (lower);
		return 0;
	}

	gsize offset = (gsize) (marker - lower) + 13;
	const char *pkg_start = exe_path + offset;
	const char *pkg_end = pkg_start;
	while (*pkg_end != '\0' && *pkg_end != '\\' && *pkg_end != '/')
		pkg_end++;
	if (pkg_end <= pkg_start) {
		g_free (lower);
		return 0;
	}

	char *pkg_full = g_strndup (pkg_start, (gsize) (pkg_end - pkg_start));
	const char *first_us = strchr (pkg_full, '_');
	const char *last_us = strrchr (pkg_full, '_');
	if (first_us != NULL && last_us != NULL && last_us > first_us && last_us[1] != '\0') {
		char *pkg_name = g_strndup (pkg_full, (gsize) (first_us - pkg_full));
		char *family = g_strdup_printf ("%s_%s", pkg_name, last_us + 1);
		if (out_family) *out_family = family;
		else g_free (family);
		g_free (pkg_name);
	}
	g_free (pkg_full);

	const char *base = strrchr (exe_path, '\\');
	const char *slash = strrchr (exe_path, '/');
	if (slash != NULL && (base == NULL || slash > base))
		base = slash;
	base = (base != NULL) ? (base + 1) : exe_path;
	const char *dot = strrchr (base, '.');
	if (out_stem) {
		*out_stem = (dot != NULL && dot > base)
			? g_strndup (base, (gsize) (dot - base))
			: g_strdup (base);
	}

	g_free (lower);
	return 1;
}
#endif

char *
win32_app_find_aumid_for_package_path (const char *exe_path)
{
#ifdef _WIN32
	if (exe_path == NULL || exe_path[0] == '\0')
		return NULL;
	ensure_com ();

	static PFN_SHGetKnownFolderItem pfn_get_kf_item = NULL;
	static int kf_resolved = 0;
	if (!kf_resolved) {
		kf_resolved = 1;
		HMODULE hShell = GetModuleHandleW (L"shell32.dll");
		if (hShell == NULL)
			hShell = LoadLibraryW (L"shell32.dll");
		if (hShell != NULL)
			pfn_get_kf_item = (PFN_SHGetKnownFolderItem) (void *) GetProcAddress (hShell, "SHGetKnownFolderItem");
	}
	if (pfn_get_kf_item == NULL)
		return NULL;

	char *expected_family = NULL;
	char *exe_stem = NULL;
	extract_windowsapps_family_and_stem (exe_path, &expected_family, &exe_stem);
	char *exe_lower = g_ascii_strdown (exe_path, -1);
	for (char *p = exe_lower; *p != '\0'; p++) {
		if (*p == '/') *p = '\\';
	}
	char *fam_lower = (expected_family != NULL) ? g_ascii_strdown (expected_family, -1) : NULL;
	char *stem_lower = (exe_stem != NULL) ? g_ascii_strdown (exe_stem, -1) : NULL;

	IShellItem *apps_folder = NULL;
	HRESULT hr = pfn_get_kf_item (&WP_FOLDERID_AppsFolder, 0, NULL, &WP_IID_IShellItem, (void **) &apps_folder);
	if (FAILED (hr) || apps_folder == NULL) {
		g_free (expected_family);
		g_free (exe_stem);
		g_free (exe_lower);
		g_free (fam_lower);
		g_free (stem_lower);
		return NULL;
	}

	IEnumShellItems *enum_items = NULL;
	hr = IShellItem_BindToHandler (apps_folder, NULL, &WP_BHID_EnumItems, &WP_IID_IEnumShellItems, (void **) &enum_items);
	IShellItem_Release (apps_folder);

	char *best_aumid = NULL;
	int best_score = 0;

	if (SUCCEEDED (hr) && enum_items != NULL) {
		IShellItem *item = NULL;
		ULONG fetched = 0;
		while (IEnumShellItems_Next (enum_items, 1, &item, &fetched) == S_OK && fetched == 1 && item != NULL) {
			IShellItem2 *item2 = NULL;
			if (SUCCEEDED (IShellItem_QueryInterface (item, &WP_IID_IShellItem2, (void **) &item2)) && item2 != NULL) {
				PWSTR waumid = NULL;
				if (SUCCEEDED (IShellItem2_GetString (item2, &WP_APP_PKEY_AppUserModel_ID, &waumid)) && waumid != NULL) {
					char *aumid = wide_to_utf8 (waumid);
					CoTaskMemFree (waumid);

					int score = 0;
					PWSTR winstall = NULL;
					if (SUCCEEDED (IShellItem2_GetString (item2, &WP_APP_PKEY_AppUserModel_PackageInstallPath, &winstall)) && winstall != NULL) {
						char *install = wide_to_utf8 (winstall);
						CoTaskMemFree (winstall);
						char *inst_lower = g_ascii_strdown (install, -1);
						gsize ilen = strlen (inst_lower);
						while (ilen > 0 && (inst_lower[ilen - 1] == '\\' || inst_lower[ilen - 1] == '/'))
							inst_lower[--ilen] = '\0';
						if (ilen > 0 && strncmp (exe_lower, inst_lower, ilen) == 0
							&& (exe_lower[ilen] == '\\' || exe_lower[ilen] == '\0')) {
							score = 20;
						}
						g_free (inst_lower);
						g_free (install);
					}

					if (score == 0 && fam_lower != NULL && aumid != NULL) {
						char *aumid_lower = g_ascii_strdown (aumid, -1);
						char *bang = strchr (aumid_lower, '!');
						if (bang != NULL) {
							*bang = '\0';
							if (strcmp (aumid_lower, fam_lower) == 0)
								score = 10;
						}
						g_free (aumid_lower);
					}

					if (score > 0 && stem_lower != NULL && aumid != NULL) {
						char *aumid_lower = g_ascii_strdown (aumid, -1);
						const char *bang = strchr (aumid_lower, '!');
						if (bang != NULL && strstr (bang + 1, stem_lower) != NULL)
							score += 5;
						g_free (aumid_lower);
					}

					if (score > best_score) {
						g_free (best_aumid);
						best_aumid = aumid;
						best_score = score;
					} else {
						g_free (aumid);
					}
				}
				IShellItem2_Release (item2);
			}
			IShellItem_Release (item);
		}
		IEnumShellItems_Release (enum_items);
	}

	g_free (expected_family);
	g_free (exe_stem);
	g_free (exe_lower);
	g_free (fam_lower);
	g_free (stem_lower);
	return best_aumid;
#else
	(void) exe_path;
	return NULL;
#endif
}

void
win32_app_enum_uwp_apps (Win32EnumUwpAppCallback cb, void *user_data)
{
#ifdef _WIN32
	if (cb == NULL)
		return;
	ensure_com ();

	static PFN_SHGetKnownFolderItem pfn_get_kf_item = NULL;
	static int kf_resolved = 0;
	if (!kf_resolved) {
		kf_resolved = 1;
		HMODULE hShell = GetModuleHandleW (L"shell32.dll");
		if (hShell == NULL)
			hShell = LoadLibraryW (L"shell32.dll");
		if (hShell != NULL)
			pfn_get_kf_item = (PFN_SHGetKnownFolderItem) (void *) GetProcAddress (hShell, "SHGetKnownFolderItem");
	}
	if (pfn_get_kf_item == NULL)
		return;

	IShellItem *apps_folder = NULL;
	HRESULT hr = pfn_get_kf_item (&WP_FOLDERID_AppsFolder, 0, NULL, &WP_IID_IShellItem, (void **) &apps_folder);
	if (FAILED (hr) || apps_folder == NULL)
		return;

	IEnumShellItems *enum_items = NULL;
	hr = IShellItem_BindToHandler (apps_folder, NULL, &WP_BHID_EnumItems, &WP_IID_IEnumShellItems, (void **) &enum_items);
	IShellItem_Release (apps_folder);
	if (FAILED (hr) || enum_items == NULL)
		return;

	IShellItem *item = NULL;
	ULONG fetched = 0;
	while (IEnumShellItems_Next (enum_items, 1, &item, &fetched) == S_OK && fetched == 1 && item != NULL) {
		IShellItem2 *item2 = NULL;
		if (SUCCEEDED (IShellItem_QueryInterface (item, &WP_IID_IShellItem2, (void **) &item2)) && item2 != NULL) {
			PWSTR waumid = NULL;
			if (SUCCEEDED (IShellItem2_GetString (item2, &WP_APP_PKEY_AppUserModel_ID, &waumid)) && waumid != NULL) {
				char *aumid = wide_to_utf8 (waumid);
				CoTaskMemFree (waumid);

				/* Only emit packaged UWP/MSIX apps (AUMID contains '!' and has PackageInstallPath or packaged family) */
				if (aumid != NULL && strchr (aumid, '!') != NULL) {
					char *install = NULL;
					PWSTR winstall = NULL;
					if (SUCCEEDED (IShellItem2_GetString (item2, &WP_APP_PKEY_AppUserModel_PackageInstallPath, &winstall)) && winstall != NULL) {
						install = wide_to_utf8 (winstall);
						CoTaskMemFree (winstall);
					}
					char *display = NULL;
					PWSTR wdisp = NULL;
					if (SUCCEEDED (IShellItem_GetDisplayName (item, SIGDN_NORMALDISPLAY, &wdisp)) && wdisp != NULL) {
						display = wide_to_utf8 (wdisp);
						CoTaskMemFree (wdisp);
					}
					if (display != NULL && display[0] != '\0')
						cb (aumid, display, install != NULL ? install : "", user_data);
					g_free (display);
					g_free (install);
				}
				g_free (aumid);
			}
			IShellItem2_Release (item2);
		}
		IShellItem_Release (item);
	}
	IEnumShellItems_Release (enum_items);
#else
	(void) cb;
	(void) user_data;
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
			char *exe_path = NULL;
			HANDLE hProc = OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pe.th32ProcessID);
			if (hProc != NULL) {
				WCHAR buf[MAX_PATH * 4];
				DWORD size = (DWORD) (sizeof (buf) / sizeof (buf[0]));
				if (QueryFullProcessImageNameW (hProc, 0, buf, &size))
					exe_path = wide_to_utf8 (buf);
				CloseHandle (hProc);
			}
			if (exe_path == NULL || exe_path[0] == '\0') {
				g_free (exe_path);
				exe_path = g_strdup (exe_name);
			}
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
