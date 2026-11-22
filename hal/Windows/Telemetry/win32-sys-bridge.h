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

#ifndef WAYPLANK_WIN32_SYS_BRIDGE_H
#define WAYPLANK_WIN32_SYS_BRIDGE_H

#include <stdint.h>
#include <glib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*Win32RemovableDriveCallback) (const char *drive_root, const char *label, void *user_data);
typedef void (*Win32TrashItemCallback) (const char *id, const char *display_name, const char *original_path, int is_directory, void *user_data);
typedef void (*Win32NetInterfaceCallback) (
	const char *iface_id,
	const char *display_name,
	const char *kind,
	int wifi_strength,
	const char *ip_address,
	const char *gateway,
	uint64_t rx_bytes,
	uint64_t tx_bytes,
	void *user_data
);

/* Trash / Recycle Bin */
uint32_t win32_sys_trash_get_count (void);
void win32_sys_trash_list_items (Win32TrashItemCallback cb, void *user_data);
int win32_sys_trash_restore_item (const char *id);
int win32_sys_trash_delete_item (const char *id);
int win32_sys_trash_move_path (const char *path);
int win32_sys_trash_empty (void);
void win32_sys_trash_open_ui (void);

/* Removable Drives / Ejector */
void win32_sys_enum_removable_drives (Win32RemovableDriveCallback cb, void *user_data);
int win32_sys_eject_drive (const char *drive_root);

/* Battery */
int win32_sys_query_battery (int *has_battery, int *percent, int *is_charging, int *is_full);

/* CPU, Memory & Disk I/O */
int win32_sys_sample_cpu_mem (int *cpu_pct, int *ram_pct, double *ram_used_gb, double *ram_total_gb);
int win32_sys_sample_disk_io (void);

/* CoreAudio Volume */
int win32_sys_audio_probe (int *volume_percent, int *is_muted);
void win32_sys_audio_set_muted (int muted);
void win32_sys_audio_set_volume_percent (int percent);

/* Display Brightness (DDC/CI via dynamic dxva2.dll) */
int win32_sys_brightness_is_available (void);
int win32_sys_brightness_get_percent (void);
void win32_sys_brightness_set_percent (int percent);

/* Network */
int win32_sys_network_probe (
	int *is_connected,
	char **out_type,
	char **out_name,
	char **out_ip,
	char **out_gateway,
	int *out_wifi_strength
);
void win32_sys_network_list_interfaces (Win32NetInterfaceCallback cb, void *user_data);

/* Session & Power */
void win32_sys_get_user_and_host (char **out_user, char **out_host);
void win32_sys_query_power_caps (int *can_hibernate, int *can_hybrid_sleep);
void win32_sys_lock_workstation (void);
void win32_sys_suspend (int hibernate);
void win32_sys_logout (void);

/* Desktop Theme (AppsUseLightTheme), Accessibility Font Scale, Focus Assist DND & Toast */
int win32_sys_query_prefer_dark (int *out_prefer_dark);
double win32_sys_query_font_scale_factor (void);
int win32_sys_query_dnd_inhibited (void);
void win32_sys_send_toast (const char *summary, const char *body);

/* Media Keys (VK_MEDIA_*) */
void win32_sys_send_media_key (int kind); /* 0=play/pause, 1=next, 2=prev, 3=stop */

/* WinHTTP synchronous GET (dynamic winhttp.dll) */
int win32_sys_http_get_sync (const char *url, int timeout_sec, char **out_body);

/* Registry Autostart (HKCU\...\Run\WayPlank) */
int win32_sys_is_autostart_enabled (void);
int win32_sys_set_autostart_enabled (int enabled);

/* Screenshot helper (full screen capture -> 32-bit RGBA) */
int win32_sys_capture_screen_rgba (uint8_t **out_rgba, int *out_w, int *out_h);
char *win32_sys_get_screenshots_dir (void);

/* Single-instance Mutex & --replace process cleanup */
int win32_sys_acquire_single_instance (const char *dock_name);
void win32_sys_replace_running_instances (void);

#ifdef __cplusplus
}
#endif

#endif /* WAYPLANK_WIN32_SYS_BRIDGE_H */
