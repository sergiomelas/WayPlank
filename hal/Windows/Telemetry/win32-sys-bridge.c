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
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <windows.h>
#include <tlhelp32.h>
#include <winioctl.h>
#include <ole2.h>
#include <objbase.h>
#include <oleauto.h>
#include <wbemcli.h>
#include <shellapi.h>
#include <shlobj.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <stdlib.h>
#include <string.h>
#endif

#include "win32-sys-bridge.h"

#ifdef _WIN32

static const GUID WP_CLSID_MMDeviceEnumerator =
	{ 0xBCDE0395, 0xE52F, 0x467C, { 0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E } };
static const GUID WP_IID_IMMDeviceEnumerator =
	{ 0xA95664D2, 0x9614, 0x4F35, { 0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6 } };
static const GUID WP_IID_IAudioEndpointVolume =
	{ 0x5CDF2C82, 0x841E, 0x4546, { 0x97, 0x22, 0x0C, 0xF7, 0x40, 0x78, 0x22, 0x9A } };

static int
sys_com_enter (void)
{
	HRESULT hr = CoInitializeEx (NULL, COINIT_MULTITHREADED);
	return SUCCEEDED (hr) ? 1 : 0;
}

static void
sys_com_leave (int did_init)
{
	if (did_init)
		CoUninitialize ();
}

static WCHAR *
sys_utf8_to_wide (const char *utf8)
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
sys_wide_to_utf8 (const WCHAR *wstr)
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

/* ============================================================================
 * 1. Trash / Recycle Bin
 * ============================================================================ */

uint32_t
win32_sys_trash_get_count (void)
{
#ifdef _WIN32
	SHQUERYRBINFO info;
	memset (&info, 0, sizeof (info));
	info.cbSize = sizeof (info);
	if (SUCCEEDED (SHQueryRecycleBinW (NULL, &info))) {
		if (info.i64NumItems < 0) return 0;
		if (info.i64NumItems > 0xFFFFFFFFLL) return 0xFFFFFFFFU;
		return (uint32_t) info.i64NumItems;
	}
	return 0;
#else
	return 0;
#endif
}

int
win32_sys_trash_move_path (const char *path)
{
#ifdef _WIN32
	if (path == NULL || path[0] == '\0')
		return 0;
	int needed = MultiByteToWideChar (CP_UTF8, 0, path, -1, NULL, 0);
	if (needed <= 0)
		return 0;
	/* SHFileOperationW requires double-NUL-terminated string */
	WCHAR *wpath = (WCHAR *) g_malloc0 ((gsize) (needed + 2) * sizeof (WCHAR));
	MultiByteToWideChar (CP_UTF8, 0, path, -1, wpath, needed);

	SHFILEOPSTRUCTW op;
	memset (&op, 0, sizeof (op));
	op.wFunc = FO_DELETE;
	op.pFrom = wpath;
	op.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;

	int res = SHFileOperationW (&op);
	g_free (wpath);
	return (res == 0 && !op.fAnyOperationsAborted) ? 1 : 0;
#else
	(void) path;
	return 0;
#endif
}

int
win32_sys_trash_empty (void)
{
#ifdef _WIN32
	HRESULT hr = SHEmptyRecycleBinW (NULL, NULL, SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
	return SUCCEEDED (hr) ? 1 : 0;
#else
	return 0;
#endif
}

void
win32_sys_trash_open_ui (void)
{
#ifdef _WIN32
	ShellExecuteW (NULL, L"open", L"shell:RecycleBinFolder", NULL, NULL, SW_SHOWNORMAL);
#endif
}

/* ============================================================================
 * 2. Removable Drives / Ejector
 * ============================================================================ */

void
win32_sys_enum_removable_drives (Win32RemovableDriveCallback cb, void *user_data)
{
#ifdef _WIN32
	if (cb == NULL)
		return;
	DWORD prev_err_mode = 0;
	SetThreadErrorMode (SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX, &prev_err_mode);
	DWORD mask = GetLogicalDrives ();
	for (int i = 0; i < 26; i++) {
		if ((mask & (1U << i)) == 0)
			continue;
		WCHAR root_w[4] = { (WCHAR) (L'A' + i), L':', L'\\', L'\0' };
		UINT dtype = GetDriveTypeW (root_w);
		if (dtype != DRIVE_REMOVABLE && dtype != DRIVE_CDROM)
			continue;

		WCHAR vol_w[MAX_PATH];
		vol_w[0] = L'\0';
		/* Skip safely-ejected or empty-slot drives where no volume is mounted */
		if (!GetVolumeInformationW (root_w, vol_w, MAX_PATH, NULL, NULL, NULL, NULL, 0))
			continue;

		char *root_u8 = sys_wide_to_utf8 (root_w);
		char *label_u8 = (vol_w[0] != L'\0') ? sys_wide_to_utf8 (vol_w) : g_strdup_printf ("Drive (%c:)", 'A' + i);
		cb (root_u8, label_u8, user_data);
		g_free (root_u8);
		g_free (label_u8);
	}
	SetThreadErrorMode (prev_err_mode, NULL);
#else
	(void) cb;
	(void) user_data;
#endif
}

int
win32_sys_eject_drive (const char *drive_root)
{
#ifdef _WIN32
	if (drive_root == NULL || drive_root[0] == '\0')
		return 0;
	WCHAR dev[16];
	dev[0] = L'\\'; dev[1] = L'\\'; dev[2] = L'.'; dev[3] = L'\\';
	dev[4] = (WCHAR) drive_root[0];
	dev[5] = L':'; dev[6] = L'\0';

	HANDLE hVol = CreateFileW (
		dev,
		GENERIC_READ | GENERIC_WRITE,
		FILE_SHARE_READ | FILE_SHARE_WRITE,
		NULL,
		OPEN_EXISTING,
		0,
		NULL
	);
	if (hVol == INVALID_HANDLE_VALUE)
		return 0;

	DWORD bytes = 0;
	DeviceIoControl (hVol, FSCTL_LOCK_VOLUME, NULL, 0, NULL, 0, &bytes, NULL);
	DeviceIoControl (hVol, FSCTL_DISMOUNT_VOLUME, NULL, 0, NULL, 0, &bytes, NULL);
	BOOL ok = DeviceIoControl (hVol, IOCTL_STORAGE_EJECT_MEDIA, NULL, 0, NULL, 0, &bytes, NULL);
	CloseHandle (hVol);
	return ok ? 1 : 0;
#else
	(void) drive_root;
	return 0;
#endif
}

/* ============================================================================
 * 3. Battery
 * ============================================================================ */

int
win32_sys_query_battery (int *has_battery, int *percent, int *is_charging, int *is_full)
{
	if (has_battery) *has_battery = 0;
	if (percent) *percent = 100;
	if (is_charging) *is_charging = 0;
	if (is_full) *is_full = 1;

#ifdef _WIN32
	SYSTEM_POWER_STATUS sps;
	if (!GetSystemPowerStatus (&sps))
		return 0;

	int present = ((sps.BatteryFlag & 128) == 0 && sps.BatteryLifePercent <= 100) ? 1 : 0;
	int pct = present ? (int) sps.BatteryLifePercent : 100;
	int charging = (present && sps.ACLineStatus == 1 && pct < 100) ? 1 : 0;
	int full = (present && sps.ACLineStatus == 1 && pct >= 99) ? 1 : 0;

	if (has_battery) *has_battery = present;
	if (percent) *percent = pct;
	if (is_charging) *is_charging = charging;
	if (is_full) *is_full = full;
	return 1;
#else
	return 0;
#endif
}

/* ============================================================================
 * 4. CPU & Memory
 * ============================================================================ */

#ifdef _WIN32
static ULONGLONG g_prev_idle = 0;
static ULONGLONG g_prev_kernel = 0;
static ULONGLONG g_prev_user = 0;
static int g_cpu_primed = 0;

static ULONGLONG
ft_to_u64 (FILETIME ft)
{
	return (((ULONGLONG) ft.dwHighDateTime) << 32) | (ULONGLONG) ft.dwLowDateTime;
}
#endif

int
win32_sys_sample_cpu_mem (int *cpu_pct, int *ram_pct, double *ram_used_gb, double *ram_total_gb)
{
	if (cpu_pct) *cpu_pct = 0;
	if (ram_pct) *ram_pct = 0;
	if (ram_used_gb) *ram_used_gb = 0.0;
	if (ram_total_gb) *ram_total_gb = 0.0;

#ifdef _WIN32
	FILETIME ft_idle, ft_kernel, ft_user;
	if (GetSystemTimes (&ft_idle, &ft_kernel, &ft_user)) {
		ULONGLONG idle = ft_to_u64 (ft_idle);
		ULONGLONG kernel = ft_to_u64 (ft_kernel);
		ULONGLONG user = ft_to_u64 (ft_user);

		if (g_cpu_primed) {
			ULONGLONG d_idle = idle - g_prev_idle;
			ULONGLONG d_total = (kernel - g_prev_kernel) + (user - g_prev_user);
			if (d_total > 0) {
				int pct = (int) (((d_total - d_idle) * 100ULL) / d_total);
				if (pct < 0) pct = 0;
				if (pct > 100) pct = 100;
				if (cpu_pct) *cpu_pct = pct;
			}
		}
		g_prev_idle = idle;
		g_prev_kernel = kernel;
		g_prev_user = user;
		g_cpu_primed = 1;
	}

	MEMORYSTATUSEX ms;
	memset (&ms, 0, sizeof (ms));
	ms.dwLength = sizeof (ms);
	if (GlobalMemoryStatusEx (&ms)) {
		double total_gb = (double) ms.ullTotalPhys / (1024.0 * 1024.0 * 1024.0);
		double used_gb = (double) (ms.ullTotalPhys - ms.ullAvailPhys) / (1024.0 * 1024.0 * 1024.0);
		if (ram_pct) *ram_pct = (int) ms.dwMemoryLoad;
		if (ram_used_gb) *ram_used_gb = used_gb;
		if (ram_total_gb) *ram_total_gb = total_gb;
	}
	return 1;
#else
	return 0;
#endif
}

/* ============================================================================
 * 5. CoreAudio Volume (IMMDeviceEnumerator -> IAudioEndpointVolume)
 * ============================================================================ */

#ifdef _WIN32

static IAudioEndpointVolume *
get_default_endpoint_volume (void)
{
	IMMDeviceEnumerator *enumerator = NULL;
	HRESULT hr = CoCreateInstance (
		&WP_CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
		&WP_IID_IMMDeviceEnumerator, (void **) &enumerator
	);
	if (FAILED (hr) || enumerator == NULL)
		return NULL;

	IMMDevice *device = NULL;
	hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint (enumerator, eRender, eMultimedia, &device);
	IMMDeviceEnumerator_Release (enumerator);
	if (FAILED (hr) || device == NULL)
		return NULL;

	IAudioEndpointVolume *vol = NULL;
	hr = IMMDevice_Activate (device, &WP_IID_IAudioEndpointVolume, CLSCTX_ALL, NULL, (void **) &vol);
	IMMDevice_Release (device);
	if (FAILED (hr))
		return NULL;
	return vol;
}

#endif

int
win32_sys_audio_probe (int *volume_percent, int *is_muted)
{
	if (volume_percent) *volume_percent = 70;
	if (is_muted) *is_muted = 0;

#ifdef _WIN32
	int com_init = sys_com_enter ();
	IAudioEndpointVolume *vol = get_default_endpoint_volume ();
	if (vol == NULL) {
		sys_com_leave (com_init);
		return 0;
	}

	float scalar = 0.0f;
	BOOL muted = FALSE;
	HRESULT hr1 = IAudioEndpointVolume_GetMasterVolumeLevelScalar (vol, &scalar);
	HRESULT hr2 = IAudioEndpointVolume_GetMute (vol, &muted);
	IAudioEndpointVolume_Release (vol);
	sys_com_leave (com_init);

	if (FAILED (hr1) && FAILED (hr2))
		return 0;

	int pct = (int) (scalar * 100.0f + 0.5f);
	if (pct < 0) pct = 0;
	if (pct > 100) pct = 100;
	if (volume_percent) *volume_percent = pct;
	if (is_muted) *is_muted = muted ? 1 : 0;
	return 1;
#else
	return 0;
#endif
}

void
win32_sys_audio_set_muted (int muted)
{
#ifdef _WIN32
	int com_init = sys_com_enter ();
	IAudioEndpointVolume *vol = get_default_endpoint_volume ();
	if (vol != NULL) {
		IAudioEndpointVolume_SetMute (vol, muted ? TRUE : FALSE, NULL);
		IAudioEndpointVolume_Release (vol);
	}
	sys_com_leave (com_init);
#else
	(void) muted;
#endif
}

void
win32_sys_audio_set_volume_percent (int percent)
{
#ifdef _WIN32
	int com_init = sys_com_enter ();
	IAudioEndpointVolume *vol = get_default_endpoint_volume ();
	if (vol != NULL) {
		if (percent < 0) percent = 0;
		if (percent > 100) percent = 100;
		IAudioEndpointVolume_SetMasterVolumeLevelScalar (vol, (float) percent / 100.0f, NULL);
		IAudioEndpointVolume_Release (vol);
	}
	sys_com_leave (com_init);
#else
	(void) percent;
#endif
}

/* ============================================================================
 * 6. Display Brightness (WMI root\WMI Laptop Backlight + Dynamic dxva2.dll Multi-Monitor DDC/CI)
 * ============================================================================ */

#ifdef _WIN32

static const GUID WP_CLSID_WbemLocator =
	{ 0x4590F811, 0x1D3A, 0x11D0, { 0x89, 0x1F, 0x00, 0xAA, 0x00, 0x4B, 0x2E, 0x24 } };
static const GUID WP_IID_IWbemLocator =
	{ 0xDC12A687, 0x737F, 0x11CF, { 0x88, 0x4D, 0x00, 0xAA, 0x00, 0x4B, 0x2E, 0x24 } };

static int g_wmi_bright_checked = 0;
static int g_wmi_bright_supported = 0;

static int
wmi_brightness_get_or_set (int do_set, int target_pct, int *out_pct)
{
	if (g_wmi_bright_checked && !g_wmi_bright_supported)
		return 0;

	int com_init = sys_com_enter ();

	IWbemLocator *loc = NULL;
	HRESULT hr = CoCreateInstance (
		&WP_CLSID_WbemLocator, NULL, CLSCTX_INPROC_SERVER,
		&WP_IID_IWbemLocator, (void **) &loc
	);
	if (FAILED (hr) || loc == NULL) {
		g_wmi_bright_checked = 1;
		g_wmi_bright_supported = 0;
		sys_com_leave (com_init);
		return 0;
	}

	BSTR ns = SysAllocString (L"ROOT\\WMI");
	IWbemServices *svc = NULL;
	hr = IWbemLocator_ConnectServer (loc, ns, NULL, NULL, NULL, 0, NULL, NULL, &svc);
	SysFreeString (ns);
	IWbemLocator_Release (loc);
	if (FAILED (hr) || svc == NULL) {
		g_wmi_bright_checked = 1;
		g_wmi_bright_supported = 0;
		sys_com_leave (com_init);
		return 0;
	}

	CoSetProxyBlanket (
		(IUnknown *) svc,
		RPC_C_AUTHN_WINNT,
		RPC_C_AUTHZ_NONE,
		NULL,
		RPC_C_AUTHN_LEVEL_CALL,
		RPC_C_IMP_LEVEL_IMPERSONATE,
		NULL,
		EOAC_NONE
	);

	BSTR wql = SysAllocString (L"WQL");
	int ok = 0;

	if (!do_set) {
		BSTR q = SysAllocString (L"SELECT CurrentBrightness FROM WmiMonitorBrightness");
		IEnumWbemClassObject *en = NULL;
		hr = IWbemServices_ExecQuery (
			svc, wql, q,
			WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
			NULL, &en
		);
		SysFreeString (q);
		if (SUCCEEDED (hr) && en != NULL) {
			IWbemClassObject *obj = NULL;
			ULONG ret = 0;
			if (SUCCEEDED (IEnumWbemClassObject_Next (en, 1000, 1, &obj, &ret)) && ret == 1 && obj != NULL) {
				VARIANT vt;
				VariantInit (&vt);
				if (SUCCEEDED (IWbemClassObject_Get (obj, L"CurrentBrightness", 0, &vt, NULL, NULL))) {
					int pct = -1;
					if (vt.vt == VT_UI1) pct = (int) vt.bVal;
					else if (vt.vt == VT_I4) pct = (int) vt.lVal;
					else if (vt.vt == VT_UI4) pct = (int) vt.ulVal;
					else if (vt.vt == VT_I2) pct = (int) vt.iVal;
					else if (vt.vt == VT_UI2) pct = (int) vt.uiVal;
					if (pct >= 0 && pct <= 100) {
						if (out_pct) *out_pct = pct;
						ok = 1;
					}
				}
				VariantClear (&vt);
				IWbemClassObject_Release (obj);
			}
			IEnumWbemClassObject_Release (en);
		}
		if (!g_wmi_bright_checked) {
			g_wmi_bright_checked = 1;
			g_wmi_bright_supported = ok;
		}
	} else {
		if (target_pct < 0) target_pct = 0;
		if (target_pct > 100) target_pct = 100;

		BSTR cls_name = SysAllocString (L"WmiMonitorBrightnessMethods");
		BSTR method_name = SysAllocString (L"WmiSetBrightness");
		IWbemClassObject *cls_obj = NULL;
		IWbemClassObject *in_def = NULL;

		if (SUCCEEDED (IWbemServices_GetObject (svc, cls_name, 0, NULL, &cls_obj, NULL)) && cls_obj != NULL) {
			if (SUCCEEDED (IWbemClassObject_GetMethod (cls_obj, L"WmiSetBrightness", 0, &in_def, NULL)) && in_def != NULL) {
				BSTR q = SysAllocString (L"SELECT InstanceName FROM WmiMonitorBrightnessMethods");
				IEnumWbemClassObject *en = NULL;
				if (SUCCEEDED (IWbemServices_ExecQuery (
					svc, wql, q,
					WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
					NULL, &en
				)) && en != NULL) {
					IWbemClassObject *obj = NULL;
					ULONG ret = 0;
					while (SUCCEEDED (IEnumWbemClassObject_Next (en, 1000, 1, &obj, &ret)) && ret == 1 && obj != NULL) {
						VARIANT vt_path;
						VariantInit (&vt_path);
						if (SUCCEEDED (IWbemClassObject_Get (obj, L"__RELPATH", 0, &vt_path, NULL, NULL))
							&& vt_path.vt == VT_BSTR && vt_path.bstrVal != NULL) {
							IWbemClassObject *in_inst = NULL;
							if (SUCCEEDED (IWbemClassObject_SpawnInstance (in_def, 0, &in_inst)) && in_inst != NULL) {
								VARIANT vt_to, vt_br;
								VariantInit (&vt_to);
								vt_to.vt = VT_I4;
								vt_to.lVal = 0;
								IWbemClassObject_Put (in_inst, L"Timeout", 0, &vt_to, 0);

								VariantInit (&vt_br);
								vt_br.vt = VT_UI1;
								vt_br.bVal = (BYTE) target_pct;
								IWbemClassObject_Put (in_inst, L"Brightness", 0, &vt_br, 0);

								IWbemClassObject *out_params = NULL;
								if (SUCCEEDED (IWbemServices_ExecMethod (
									svc, vt_path.bstrVal, method_name, 0, NULL, in_inst, &out_params, NULL
								))) {
									ok = 1;
									if (out_params != NULL)
										IWbemClassObject_Release (out_params);
								}
								IWbemClassObject_Release (in_inst);
							}
						}
						VariantClear (&vt_path);
						IWbemClassObject_Release (obj);
					}
					IEnumWbemClassObject_Release (en);
				}
				SysFreeString (q);
				IWbemClassObject_Release (in_def);
			}
			IWbemClassObject_Release (cls_obj);
		}
		SysFreeString (method_name);
		SysFreeString (cls_name);
	}

	SysFreeString (wql);
	IWbemServices_Release (svc);
	sys_com_leave (com_init);
	return ok;
}

typedef struct {
	HANDLE hPhysicalMonitor;
	WCHAR szPhysicalMonitorDescription[128];
} WP_PHYSICAL_MONITOR;

typedef BOOL (WINAPI *PFN_GetNumPhys) (HMONITOR, LPDWORD);
typedef BOOL (WINAPI *PFN_GetPhys) (HMONITOR, DWORD, WP_PHYSICAL_MONITOR *);
typedef BOOL (WINAPI *PFN_DestroyPhys) (DWORD, WP_PHYSICAL_MONITOR *);
typedef BOOL (WINAPI *PFN_GetBright) (HANDLE, LPDWORD, LPDWORD, LPDWORD);
typedef BOOL (WINAPI *PFN_SetBright) (HANDLE, DWORD);

static PFN_GetNumPhys pfn_GetNumPhys = NULL;
static PFN_GetPhys pfn_GetPhys = NULL;
static PFN_DestroyPhys pfn_DestroyPhys = NULL;
static PFN_GetBright pfn_GetBright = NULL;
static PFN_SetBright pfn_SetBright = NULL;
static int g_dxva2_loaded = 0;

static void
ensure_dxva2 (void)
{
	if (g_dxva2_loaded)
		return;
	g_dxva2_loaded = 1;
	HMODULE h = LoadLibraryW (L"dxva2.dll");
	if (h == NULL)
		return;
	pfn_GetNumPhys = (PFN_GetNumPhys) GetProcAddress (h, "GetNumberOfPhysicalMonitorsFromHMONITOR");
	pfn_GetPhys = (PFN_GetPhys) GetProcAddress (h, "GetPhysicalMonitorsFromHMONITOR");
	pfn_DestroyPhys = (PFN_DestroyPhys) GetProcAddress (h, "DestroyPhysicalMonitors");
	pfn_GetBright = (PFN_GetBright) GetProcAddress (h, "GetMonitorBrightness");
	pfn_SetBright = (PFN_SetBright) GetProcAddress (h, "SetMonitorBrightness");
}

typedef struct {
	int do_set;
	int target_pct;
	int out_pct;
	int any_ok;
} Dxva2EnumCtx;

static BOOL CALLBACK
dxva2_enum_mon_cb (HMONITOR hMon, HDC hdc, LPRECT rc, LPARAM lparam)
{
	(void) hdc;
	(void) rc;
	Dxva2EnumCtx *ctx = (Dxva2EnumCtx *) lparam;
	if (hMon == NULL)
		return TRUE;

	DWORD count = 0;
	if (!pfn_GetNumPhys (hMon, &count) || count == 0)
		return TRUE;

	WP_PHYSICAL_MONITOR *mons = (WP_PHYSICAL_MONITOR *) g_malloc0 (count * sizeof (WP_PHYSICAL_MONITOR));
	if (!pfn_GetPhys (hMon, count, mons)) {
		g_free (mons);
		return TRUE;
	}

	for (DWORD i = 0; i < count; i++) {
		DWORD min_b = 0, cur_b = 0, max_b = 0;
		if (pfn_GetBright (mons[i].hPhysicalMonitor, &min_b, &cur_b, &max_b) && max_b > min_b) {
			if (ctx->do_set) {
				int pct = ctx->target_pct;
				if (pct < 0) pct = 0;
				if (pct > 100) pct = 100;
				DWORD val = min_b + ((max_b - min_b) * (DWORD) pct) / 100;
				if (pfn_SetBright (mons[i].hPhysicalMonitor, val))
					ctx->any_ok = 1;
			} else {
				ctx->out_pct = (int) (((cur_b - min_b) * 100) / (max_b - min_b));
				ctx->any_ok = 1;
				break;
			}
		}
	}

	pfn_DestroyPhys (count, mons);
	g_free (mons);
	/* For queries, stop on first working DDC/CI monitor; for sets, update all external monitors */
	return (ctx->do_set || !ctx->any_ok) ? TRUE : FALSE;
}

static int
dxva2_get_or_set (int do_set, int target_pct, int *out_pct)
{
	ensure_dxva2 ();
	if (!pfn_GetNumPhys || !pfn_GetPhys || !pfn_DestroyPhys || !pfn_GetBright || !pfn_SetBright)
		return 0;

	Dxva2EnumCtx ctx;
	ctx.do_set = do_set;
	ctx.target_pct = target_pct;
	ctx.out_pct = 100;
	ctx.any_ok = 0;

	EnumDisplayMonitors (NULL, NULL, dxva2_enum_mon_cb, (LPARAM) &ctx);
	if (ctx.any_ok && out_pct != NULL)
		*out_pct = ctx.out_pct;
	return ctx.any_ok;
}

#endif

int
win32_sys_brightness_is_available (void)
{
#ifdef _WIN32
	int pct = 100;
	if (wmi_brightness_get_or_set (0, 0, &pct))
		return 1;
	return dxva2_get_or_set (0, 0, &pct);
#else
	return 0;
#endif
}

int
win32_sys_brightness_get_percent (void)
{
#ifdef _WIN32
	int pct = 100;
	if (wmi_brightness_get_or_set (0, 0, &pct))
		return pct;
	if (dxva2_get_or_set (0, 0, &pct))
		return pct;
	return 100;
#else
	return 100;
#endif
}

void
win32_sys_brightness_set_percent (int percent)
{
#ifdef _WIN32
	wmi_brightness_get_or_set (1, percent, NULL);
	dxva2_get_or_set (1, percent, NULL);
#else
	(void) percent;
#endif
}

/* ============================================================================
 * 7. Network (GetAdaptersAddresses)
 * ============================================================================ */

int
win32_sys_network_probe (int *is_connected, char **out_type, char **out_name, char **out_ip)
{
	if (is_connected) *is_connected = 0;
	if (out_type) *out_type = g_strdup ("none");
	if (out_name) *out_name = g_strdup ("");
	if (out_ip) *out_ip = g_strdup ("");

#ifdef _WIN32
	ULONG buf_len = 16384;
	IP_ADAPTER_ADDRESSES *addrs = (IP_ADAPTER_ADDRESSES *) g_malloc (buf_len);
	ULONG ret = GetAdaptersAddresses (AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, NULL, addrs, &buf_len);
	if (ret == ERROR_BUFFER_OVERFLOW) {
		g_free (addrs);
		addrs = (IP_ADAPTER_ADDRESSES *) g_malloc (buf_len);
		ret = GetAdaptersAddresses (AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, NULL, addrs, &buf_len);
	}
	if (ret != NO_ERROR) {
		g_free (addrs);
		return 0;
	}

	for (IP_ADAPTER_ADDRESSES *cur = addrs; cur != NULL; cur = cur->Next) {
		if (cur->OperStatus != IfOperStatusUp)
			continue;
		if (cur->IfType == IF_TYPE_SOFTWARE_LOOPBACK || cur->IfType == IF_TYPE_TUNNEL)
			continue;
		if (cur->FirstUnicastAddress == NULL)
			continue;

		struct sockaddr_in *sa = (struct sockaddr_in *) cur->FirstUnicastAddress->Address.lpSockaddr;
		if (sa == NULL || sa->sin_family != AF_INET)
			continue;

		char ip_buf[64];
		ip_buf[0] = '\0';
		const unsigned char *b = (const unsigned char *) &sa->sin_addr;
		if (b[0] == 169 && b[1] == 254)
			continue; /* Skip APIPA link-local */
		g_snprintf (ip_buf, sizeof (ip_buf), "%u.%u.%u.%u", b[0], b[1], b[2], b[3]);

		const char *ctype = (cur->IfType == IF_TYPE_IEEE80211) ? "wifi" : "ethernet";
		if (is_connected) *is_connected = 1;
		if (out_type) { g_free (*out_type); *out_type = g_strdup (ctype); }
		if (out_name) { g_free (*out_name); *out_name = sys_wide_to_utf8 (cur->FriendlyName); }
		if (out_ip) { g_free (*out_ip); *out_ip = g_strdup (ip_buf); }
		break;
	}

	g_free (addrs);
	return 1;
#else
	return 0;
#endif
}

/* ============================================================================
 * 8. Session & Power
 * ============================================================================ */

void
win32_sys_get_user_and_host (char **out_user, char **out_host)
{
#ifdef _WIN32
	WCHAR user_w[256];
	DWORD ulen = 256;
	user_w[0] = L'\0';
	GetUserNameW (user_w, &ulen);

	WCHAR host_w[256];
	DWORD hlen = 256;
	host_w[0] = L'\0';
	GetComputerNameW (host_w, &hlen);

	if (out_user) *out_user = sys_wide_to_utf8 (user_w);
	if (out_host) *out_host = sys_wide_to_utf8 (host_w);
#else
	if (out_user) *out_user = g_strdup ("");
	if (out_host) *out_host = g_strdup ("");
#endif
}

void
win32_sys_lock_workstation (void)
{
#ifdef _WIN32
	LockWorkStation ();
#endif
}

void
win32_sys_suspend (int hibernate)
{
#ifdef _WIN32
	typedef BOOLEAN (WINAPI *PFN_SetSuspendState) (BOOLEAN, BOOLEAN, BOOLEAN);
	static HMODULE hPowr = NULL;
	static PFN_SetSuspendState pfn = NULL;
	static int loaded = 0;
	if (!loaded) {
		loaded = 1;
		hPowr = LoadLibraryW (L"powrprof.dll");
		if (hPowr != NULL)
			pfn = (PFN_SetSuspendState) GetProcAddress (hPowr, "SetSuspendState");
	}
	if (pfn != NULL)
		pfn (hibernate ? TRUE : FALSE, FALSE, FALSE);
#else
	(void) hibernate;
#endif
}

void
win32_sys_logout (void)
{
#ifdef _WIN32
	ExitWindowsEx (EWX_LOGOFF, 0);
#endif
}

/* ============================================================================
 * 9. Desktop Theme (AppsUseLightTheme) & Media Keys
 * ============================================================================ */

int
win32_sys_query_prefer_dark (int *out_prefer_dark)
{
	if (out_prefer_dark) *out_prefer_dark = 0;
#ifdef _WIN32
	DWORD val = 1;
	DWORD sz = sizeof (val);
	LSTATUS st = RegGetValueW (
		HKEY_CURRENT_USER,
		L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
		L"AppsUseLightTheme",
		RRF_RT_REG_DWORD,
		NULL,
		&val,
		&sz
	);
	if (st == ERROR_SUCCESS) {
		if (out_prefer_dark) *out_prefer_dark = (val == 0) ? 1 : 0;
		return 1;
	}
	return 0;
#else
	return 0;
#endif
}

void
win32_sys_send_media_key (int kind)
{
#ifdef _WIN32
	WORD vk = VK_MEDIA_PLAY_PAUSE;
	switch (kind) {
	case 1: vk = VK_MEDIA_NEXT_TRACK; break;
	case 2: vk = VK_MEDIA_PREV_TRACK; break;
	case 3: vk = VK_MEDIA_STOP; break;
	default: vk = VK_MEDIA_PLAY_PAUSE; break;
	}
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
#else
	(void) kind;
#endif
}

/* ============================================================================
 * 10. WinHTTP Synchronous GET (Dynamic winhttp.dll — Weather Docklet)
 * ============================================================================ */

#ifdef _WIN32
typedef LPVOID HINTERNET_WP;

typedef struct {
	DWORD dwStructSize;
	LPWSTR lpszScheme;
	DWORD dwSchemeLength;
	int nScheme;
	LPWSTR lpszHostName;
	DWORD dwHostNameLength;
	WORD nPort;
	LPWSTR lpszUserName;
	DWORD dwUserNameLength;
	LPWSTR lpszPassword;
	DWORD dwPasswordLength;
	LPWSTR lpszUrlPath;
	DWORD dwUrlPathLength;
	LPWSTR lpszExtraInfo;
	DWORD dwExtraInfoLength;
} WP_URL_COMPONENTS;

#define WP_WINHTTP_ACCESS_TYPE_DEFAULT_PROXY 0
#define WP_WINHTTP_FLAG_SECURE 0x00800000
#define WP_INTERNET_SCHEME_HTTPS 2

typedef HINTERNET_WP (WINAPI *PFN_WinHttpOpen) (LPCWSTR, DWORD, LPCWSTR, LPCWSTR, DWORD);
typedef BOOL (WINAPI *PFN_WinHttpSetTimeouts) (HINTERNET_WP, int, int, int, int);
typedef BOOL (WINAPI *PFN_WinHttpCrackUrl) (LPCWSTR, DWORD, DWORD, WP_URL_COMPONENTS *);
typedef HINTERNET_WP (WINAPI *PFN_WinHttpConnect) (HINTERNET_WP, LPCWSTR, WORD, DWORD);
typedef HINTERNET_WP (WINAPI *PFN_WinHttpOpenRequest) (HINTERNET_WP, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR *, DWORD);
typedef BOOL (WINAPI *PFN_WinHttpSendRequest) (HINTERNET_WP, LPCWSTR, DWORD, LPVOID, DWORD, DWORD, DWORD_PTR);
typedef BOOL (WINAPI *PFN_WinHttpReceiveResponse) (HINTERNET_WP, LPVOID);
typedef BOOL (WINAPI *PFN_WinHttpQueryDataAvailable) (HINTERNET_WP, LPDWORD);
typedef BOOL (WINAPI *PFN_WinHttpReadData) (HINTERNET_WP, LPVOID, DWORD, LPDWORD);
typedef BOOL (WINAPI *PFN_WinHttpCloseHandle) (HINTERNET_WP);
#endif

int
win32_sys_http_get_sync (const char *url, int timeout_sec, char **out_body)
{
	if (out_body) *out_body = g_strdup ("");
#ifdef _WIN32
	if (url == NULL || url[0] == '\0')
		return 0;

	static HMODULE hHttp = NULL;
	static int http_loaded = 0;
	if (!http_loaded) {
		http_loaded = 1;
		hHttp = LoadLibraryW (L"winhttp.dll");
	}
	if (hHttp == NULL)
		return 0;

	PFN_WinHttpOpen pOpen = (PFN_WinHttpOpen) GetProcAddress (hHttp, "WinHttpOpen");
	PFN_WinHttpSetTimeouts pTimeouts = (PFN_WinHttpSetTimeouts) GetProcAddress (hHttp, "WinHttpSetTimeouts");
	PFN_WinHttpCrackUrl pCrack = (PFN_WinHttpCrackUrl) GetProcAddress (hHttp, "WinHttpCrackUrl");
	PFN_WinHttpConnect pConnect = (PFN_WinHttpConnect) GetProcAddress (hHttp, "WinHttpConnect");
	PFN_WinHttpOpenRequest pOpenReq = (PFN_WinHttpOpenRequest) GetProcAddress (hHttp, "WinHttpOpenRequest");
	PFN_WinHttpSendRequest pSend = (PFN_WinHttpSendRequest) GetProcAddress (hHttp, "WinHttpSendRequest");
	PFN_WinHttpReceiveResponse pRecv = (PFN_WinHttpReceiveResponse) GetProcAddress (hHttp, "WinHttpReceiveResponse");
	PFN_WinHttpQueryDataAvailable pAvail = (PFN_WinHttpQueryDataAvailable) GetProcAddress (hHttp, "WinHttpQueryDataAvailable");
	PFN_WinHttpReadData pRead = (PFN_WinHttpReadData) GetProcAddress (hHttp, "WinHttpReadData");
	PFN_WinHttpCloseHandle pClose = (PFN_WinHttpCloseHandle) GetProcAddress (hHttp, "WinHttpCloseHandle");

	if (!pOpen || !pCrack || !pConnect || !pOpenReq || !pSend || !pRecv || !pAvail || !pRead || !pClose)
		return 0;

	WCHAR *wurl = sys_utf8_to_wide (url);
	if (wurl == NULL)
		return 0;

	WCHAR host[512];
	WCHAR path[2048];
	WCHAR extra[1024];
	host[0] = L'\0'; path[0] = L'\0'; extra[0] = L'\0';

	WP_URL_COMPONENTS uc;
	memset (&uc, 0, sizeof (uc));
	uc.dwStructSize = sizeof (uc);
	uc.lpszHostName = host; uc.dwHostNameLength = 512;
	uc.lpszUrlPath = path; uc.dwUrlPathLength = 2048;
	uc.lpszExtraInfo = extra; uc.dwExtraInfoLength = 1024;

	if (!pCrack (wurl, 0, 0, &uc)) {
		g_free (wurl);
		return 0;
	}
	g_free (wurl);

	WCHAR full_path[3072];
	full_path[0] = L'\0';
	wcsncpy (full_path, path[0] ? path : L"/", 2047);
	if (extra[0])
		wcsncat (full_path, extra, 1023);

#define WP_WIDE_HELPER(x) L##x
#define WP_WIDE(x) WP_WIDE_HELPER(x)
	HINTERNET_WP hSession = pOpen (L"WayPlank/" WP_WIDE (PACKAGE_VERSION), WP_WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, NULL, NULL, 0);
#undef WP_WIDE
#undef WP_WIDE_HELPER
	if (!hSession)
		return 0;

	int ms = (timeout_sec > 0 ? timeout_sec : 10) * 1000;
	if (pTimeouts)
		pTimeouts (hSession, ms, ms, ms, ms);

	HINTERNET_WP hConn = pConnect (hSession, host, uc.nPort, 0);
	if (!hConn) {
		pClose (hSession);
		return 0;
	}

	DWORD flags = (uc.nScheme == WP_INTERNET_SCHEME_HTTPS) ? WP_WINHTTP_FLAG_SECURE : 0;
	HINTERNET_WP hReq = pOpenReq (hConn, L"GET", full_path, NULL, NULL, NULL, flags);
	if (!hReq) {
		pClose (hConn);
		pClose (hSession);
		return 0;
	}

	int ok = 0;
	if (pSend (hReq, NULL, 0, NULL, 0, 0, 0) && pRecv (hReq, NULL)) {
		GString *buf = g_string_new ("");
		DWORD avail = 0;
		while (pAvail (hReq, &avail) && avail > 0) {
			char *chunk = (char *) g_malloc (avail + 1);
			DWORD got = 0;
			if (pRead (hReq, chunk, avail, &got) && got > 0)
				g_string_append_len (buf, chunk, (gssize) got);
			g_free (chunk);
			if (got == 0)
				break;
		}
		if (out_body) {
			g_free (*out_body);
			*out_body = g_string_free (buf, FALSE);
		} else {
			g_string_free (buf, TRUE);
		}
		ok = 1;
	}

	pClose (hReq);
	pClose (hConn);
	pClose (hSession);
	return ok;
#else
	(void) url;
	(void) timeout_sec;
	return 0;
#endif
}

/* ============================================================================
 * 11. Registry Autostart (HKCU\Software\Microsoft\Windows\CurrentVersion\Run)
 * ============================================================================ */

int
win32_sys_is_autostart_enabled (void)
{
#ifdef _WIN32
	HKEY hKey = NULL;
	if (RegOpenKeyExW (HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_READ, &hKey) != ERROR_SUCCESS)
		return 0;
	DWORD type = 0;
	DWORD sz = 0;
	LSTATUS st = RegQueryValueExW (hKey, L"WayPlank", NULL, &type, NULL, &sz);
	RegCloseKey (hKey);
	return (st == ERROR_SUCCESS && sz > 2) ? 1 : 0;
#else
	return 0;
#endif
}

int
win32_sys_set_autostart_enabled (int enabled)
{
#ifdef _WIN32
	HKEY hKey = NULL;
	if (RegOpenKeyExW (HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_SET_VALUE, &hKey) != ERROR_SUCCESS)
		return 0;

	LSTATUS st;
	if (enabled) {
		WCHAR exe_w[MAX_PATH * 2];
		DWORD len = GetModuleFileNameW (NULL, exe_w, MAX_PATH * 2);
		if (len == 0) {
			RegCloseKey (hKey);
			return 0;
		}
		WCHAR val_w[MAX_PATH * 2 + 4];
		val_w[0] = L'"';
		wcsncpy (val_w + 1, exe_w, MAX_PATH * 2);
		wcsncat (val_w, L"\"", 2);
		DWORD bytes = (DWORD) ((wcslen (val_w) + 1) * sizeof (WCHAR));
		st = RegSetValueExW (hKey, L"WayPlank", 0, REG_SZ, (const BYTE *) val_w, bytes);
	} else {
		st = RegDeleteValueW (hKey, L"WayPlank");
		if (st == ERROR_FILE_NOT_FOUND)
			st = ERROR_SUCCESS;
	}
	RegCloseKey (hKey);
	return (st == ERROR_SUCCESS) ? 1 : 0;
#else
	(void) enabled;
	return 0;
#endif
}

/* ============================================================================
 * 12. Full-Screen Screenshot Capture & Screenshots Folder
 * ============================================================================ */

int
win32_sys_capture_screen_rgba (uint8_t **out_rgba, int *out_w, int *out_h)
{
	if (out_rgba) *out_rgba = NULL;
	if (out_w) *out_w = 0;
	if (out_h) *out_h = 0;

#ifdef _WIN32
	int vx = GetSystemMetrics (SM_XVIRTUALSCREEN);
	int vy = GetSystemMetrics (SM_YVIRTUALSCREEN);
	int w = GetSystemMetrics (SM_CXVIRTUALSCREEN);
	int h = GetSystemMetrics (SM_CYVIRTUALSCREEN);
	if (w <= 0 || h <= 0) {
		vx = 0;
		vy = 0;
		w = GetSystemMetrics (SM_CXSCREEN);
		h = GetSystemMetrics (SM_CYSCREEN);
	}
	if (w <= 0 || h <= 0)
		return 0;

	HDC hdcScreen = GetDC (NULL);
	if (!hdcScreen)
		return 0;

	BITMAPINFO bmi;
	memset (&bmi, 0, sizeof (bmi));
	bmi.bmiHeader.biSize = sizeof (BITMAPINFOHEADER);
	bmi.bmiHeader.biWidth = w;
	bmi.bmiHeader.biHeight = -h;
	bmi.bmiHeader.biPlanes = 1;
	bmi.bmiHeader.biBitCount = 32;
	bmi.bmiHeader.biCompression = BI_RGB;

	void *bits = NULL;
	HDC hdcMem = CreateCompatibleDC (hdcScreen);
	HBITMAP hbm = CreateDIBSection (hdcMem, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
	if (!hdcMem || !hbm || !bits) {
		if (hbm) DeleteObject (hbm);
		if (hdcMem) DeleteDC (hdcMem);
		ReleaseDC (NULL, hdcScreen);
		return 0;
	}

	HGDIOBJ old = SelectObject (hdcMem, hbm);
	BitBlt (hdcMem, 0, 0, w, h, hdcScreen, vx, vy, SRCCOPY);
	GdiFlush ();

	size_t byte_len = (size_t) w * (size_t) h * 4;
	uint8_t *rgba = (uint8_t *) g_malloc (byte_len);
	const uint8_t *bgra = (const uint8_t *) bits;
	for (size_t i = 0; i < byte_len; i += 4) {
		rgba[i + 0] = bgra[i + 2];
		rgba[i + 1] = bgra[i + 1];
		rgba[i + 2] = bgra[i + 0];
		rgba[i + 3] = 255;
	}

	SelectObject (hdcMem, old);
	DeleteObject (hbm);
	DeleteDC (hdcMem);
	ReleaseDC (NULL, hdcScreen);

	if (out_rgba) *out_rgba = rgba; else g_free (rgba);
	if (out_w) *out_w = w;
	if (out_h) *out_h = h;
	return 1;
#else
	return 0;
#endif
}

char *
win32_sys_get_screenshots_dir (void)
{
#ifdef _WIN32
	WCHAR pic_w[MAX_PATH * 2];
	pic_w[0] = L'\0';
	if (SUCCEEDED (SHGetFolderPathW (NULL, CSIDL_MYPICTURES, NULL, SHGFP_TYPE_CURRENT, pic_w)) && pic_w[0] != L'\0') {
		char *pic_u8 = sys_wide_to_utf8 (pic_w);
		char *full = g_build_filename (pic_u8, "Screenshots", NULL);
		g_free (pic_u8);
		return full;
	}
	return g_build_filename (g_get_home_dir (), "Pictures", "Screenshots", NULL);
#else
	return g_strdup ("");
#endif
}

#ifdef _WIN32
static HANDLE g_single_instance_mutex = NULL;
#endif

int
win32_sys_acquire_single_instance (const char *dock_name)
{
#ifdef _WIN32
	if (g_single_instance_mutex != NULL)
		return 0;

	const char *dn = (dock_name != NULL && dock_name[0] != '\0') ? dock_name : "dock1";
	char *utf8_name = g_strdup_printf ("Local\\WayPlank_SingleInstance_%s", dn);
	WCHAR *wname = sys_utf8_to_wide (utf8_name);
	g_free (utf8_name);
	if (wname == NULL)
		return 0;

	HANDLE h = CreateMutexW (NULL, TRUE, wname);
	DWORD err = GetLastError ();
	g_free (wname);

	if (h == NULL)
		return 0;

	if (err == ERROR_ALREADY_EXISTS) {
		CloseHandle (h);
		return 1; /* Another instance is already running */
	}

	/* Keep handle open until process terminates */
	g_single_instance_mutex = h;
	return 0;
#else
	(void) dock_name;
	return 0;
#endif
}

void
win32_sys_replace_running_instances (void)
{
#ifdef _WIN32
	DWORD self_pid = GetCurrentProcessId ();
	HANDLE snap = CreateToolhelp32Snapshot (TH32CS_SNAPPROCESS, 0);
	if (snap == INVALID_HANDLE_VALUE)
		return;

	PROCESSENTRY32W pe;
	memset (&pe, 0, sizeof (pe));
	pe.dwSize = sizeof (pe);

	if (Process32FirstW (snap, &pe)) {
		do {
			if (pe.th32ProcessID == 0 || pe.th32ProcessID == self_pid)
				continue;
			if (_wcsicmp (pe.szExeFile, L"wayplank.exe") == 0) {
				HANDLE hp = OpenProcess (PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pe.th32ProcessID);
				if (hp != NULL) {
					TerminateProcess (hp, 0);
					WaitForSingleObject (hp, 1500);
					CloseHandle (hp);
				}
			}
		} while (Process32NextW (snap, &pe));
	}

	CloseHandle (snap);
#endif
}
