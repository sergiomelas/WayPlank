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

#pragma once

#include <glib.h>

G_BEGIN_DECLS

gboolean bsd_kernel_is_process_alive (int pid);
char    *bsd_kernel_get_self_exe_path (void);
int     *bsd_kernel_list_user_pids (int *out_len);
gboolean bsd_kernel_get_proc_basic (int pid,
                                    int *out_uid,
                                    char **out_comm,
                                    char **out_exe_path,
                                    char **out_cwd);
char   **bsd_kernel_get_proc_argv (int pid);
gboolean bsd_kernel_get_proc_env_hints (int pid,
                                        char **out_appimage,
                                        char **out_wineprefix);
int     *bsd_kernel_get_child_pids (int pid, int *out_len);
char   **bsd_kernel_get_open_fd_paths (int pid);

/* Milestone B3: Hardware Telemetry, Audio OSS, Backlight & Network */
gboolean bsd_kernel_read_cpu_ticks (guint64 *out_total, guint64 *out_idle);
gboolean bsd_kernel_read_memory (guint64 *out_total_bytes, guint64 *out_avail_bytes);
gboolean bsd_kernel_read_disk_busy_ms (guint64 *out_busy_ms);

gboolean bsd_kernel_read_battery (gboolean *out_has_battery,
                                  int *out_percentage,
                                  gboolean *out_is_charging,
                                  gboolean *out_is_full,
                                  char **out_raw_status);

gboolean bsd_kernel_oss_get_volume (int *out_percent);
gboolean bsd_kernel_oss_set_volume (int percent);

char   **bsd_kernel_backlight_list_devices (char **out_preferred, guint32 *out_max_raw);
gboolean bsd_kernel_backlight_lid_is_open (void);
gint64   bsd_kernel_backlight_read_raw (const char *device);
gboolean bsd_kernel_backlight_write_raw (const char *device, guint32 raw_value);

typedef void (*BsdNetInterfaceCallback) (
	const char *iface_id,
	const char *display_name,
	const char *kind,
	int wifi_strength,
	const char *ip_address,
	const char *gateway,
	guint64 rx_bytes,
	guint64 tx_bytes,
	gpointer user_data
);

gboolean bsd_kernel_probe_network (char **out_type,
                                   char **out_name,
                                   int *out_strength,
                                   char **out_ip,
                                   char **out_gateway);
void     bsd_kernel_list_network_interfaces (BsdNetInterfaceCallback cb, gpointer user_data);

G_END_DECLS
