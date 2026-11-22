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

#include "bsd-kernel-bridge.h"

#ifdef __FreeBSD__
#include <sys/types.h>
#include <sys/param.h>
#include <sys/queue.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/sysctl.h>
#include <sys/user.h>
#include <sys/soundcard.h>
#include <sys/backlight.h>
#include <net/if.h>
#include <net/if_media.h>
#include <net/route.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net80211/ieee80211_ioctl.h>
#include <devstat.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <limits.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libprocstat.h>

/* ============================================================================
 * Process Inspection (`libprocstat(3)` & `sysctl(3)`)
 * ============================================================================ */

gboolean
bsd_kernel_is_process_alive (int pid)
{
	if (pid <= 0)
		return FALSE;

	if (kill ((pid_t) pid, 0) == 0 || errno == EPERM)
		return TRUE;

	return FALSE;
}

char *
bsd_kernel_get_self_exe_path (void)
{
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1 };
	char buf[PATH_MAX];
	size_t len = sizeof (buf);

	if (sysctl (mib, 4, buf, &len, NULL, 0) == 0 && len > 0 && buf[0] != '\0') {
		buf[sizeof (buf) - 1] = '\0';
		return g_strdup (buf);
	}

	return NULL;
}

int *
bsd_kernel_list_user_pids (int *out_len)
{
	struct procstat *prstat;
	struct kinfo_proc *procs;
	unsigned int cnt = 0;
	int *pids = NULL;

	if (out_len != NULL)
		*out_len = 0;

	prstat = procstat_open_sysctl ();
	if (prstat == NULL)
		return NULL;

	procs = procstat_getprocs (prstat, KERN_PROC_UID, (int) getuid (), &cnt);
	if (procs != NULL && cnt > 0) {
		unsigned int i;
		int n = 0;
		pids = g_new (int, cnt);
		for (i = 0; i < cnt; i++) {
			if (procs[i].ki_pid > 0)
				pids[n++] = (int) procs[i].ki_pid;
		}
		if (n == 0) {
			g_free (pids);
			pids = NULL;
		} else if (out_len != NULL) {
			*out_len = n;
		}
		procstat_freeprocs (prstat, procs);
	}

	procstat_close (prstat);
	return pids;
}

gboolean
bsd_kernel_get_proc_basic (int pid,
                           int *out_uid,
                           char **out_comm,
                           char **out_exe_path,
                           char **out_cwd)
{
	struct procstat *prstat;
	struct kinfo_proc *procs;
	unsigned int cnt = 0;
	char pathbuf[PATH_MAX];
	struct filestat_list *head;
	struct filestat *fst;
	char *cwd_found = NULL;

	if (out_uid != NULL)
		*out_uid = -1;
	if (out_comm != NULL)
		*out_comm = g_strdup ("");
	if (out_exe_path != NULL)
		*out_exe_path = g_strdup ("");
	if (out_cwd != NULL)
		*out_cwd = g_strdup ("");

	if (pid <= 0)
		return FALSE;

	prstat = procstat_open_sysctl ();
	if (prstat == NULL)
		return FALSE;

	procs = procstat_getprocs (prstat, KERN_PROC_PID, pid, &cnt);
	if (procs == NULL || cnt == 0) {
		if (procs != NULL)
			procstat_freeprocs (prstat, procs);
		procstat_close (prstat);
		return FALSE;
	}

	if (out_uid != NULL)
		*out_uid = (int) procs[0].ki_uid;

	if (out_comm != NULL) {
		g_free (*out_comm);
		*out_comm = g_strdup (procs[0].ki_comm);
	}

	if (out_exe_path != NULL) {
		memset (pathbuf, 0, sizeof (pathbuf));
		if (procstat_getpathname (prstat, &procs[0], pathbuf, sizeof (pathbuf)) == 0 && pathbuf[0] != '\0') {
			g_free (*out_exe_path);
			*out_exe_path = g_strdup (pathbuf);
		} else {
			int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, pid };
			size_t len = sizeof (pathbuf);
			if (sysctl (mib, 4, pathbuf, &len, NULL, 0) == 0 && len > 0 && pathbuf[0] != '\0') {
				pathbuf[sizeof (pathbuf) - 1] = '\0';
				g_free (*out_exe_path);
				*out_exe_path = g_strdup (pathbuf);
			}
		}
	}

	if (out_cwd != NULL) {
		head = procstat_getfiles (prstat, &procs[0], 0);
		if (head != NULL) {
			STAILQ_FOREACH (fst, head, next) {
				if ((fst->fs_uflags & PS_FST_UFLAG_CDIR) != 0 &&
				    fst->fs_path != NULL && fst->fs_path[0] != '\0') {
					cwd_found = g_strdup (fst->fs_path);
					break;
				}
			}
			procstat_freefiles (prstat, head);
		}
		if (cwd_found != NULL) {
			g_free (*out_cwd);
			*out_cwd = cwd_found;
		}
	}

	procstat_freeprocs (prstat, procs);
	procstat_close (prstat);
	return TRUE;
}

char **
bsd_kernel_get_proc_argv (int pid)
{
	struct procstat *prstat;
	struct kinfo_proc *procs;
	unsigned int cnt = 0;
	char **argv_internal;
	char **result = NULL;

	if (pid <= 0)
		return NULL;

	prstat = procstat_open_sysctl ();
	if (prstat == NULL)
		return NULL;

	procs = procstat_getprocs (prstat, KERN_PROC_PID, pid, &cnt);
	if (procs != NULL && cnt > 0) {
		argv_internal = procstat_getargv (prstat, &procs[0], 0);
		if (argv_internal != NULL)
			result = g_strdupv (argv_internal);
		procstat_freeprocs (prstat, procs);
	}

	procstat_close (prstat);
	return result;
}

gboolean
bsd_kernel_get_proc_env_hints (int pid,
                               char **out_appimage,
                               char **out_wineprefix)
{
	struct procstat *prstat;
	struct kinfo_proc *procs;
	unsigned int cnt = 0;
	char **envv;
	gboolean ok = FALSE;

	if (out_appimage != NULL)
		*out_appimage = g_strdup ("");
	if (out_wineprefix != NULL)
		*out_wineprefix = g_strdup ("");

	if (pid <= 0)
		return FALSE;

	prstat = procstat_open_sysctl ();
	if (prstat == NULL)
		return FALSE;

	procs = procstat_getprocs (prstat, KERN_PROC_PID, pid, &cnt);
	if (procs != NULL && cnt > 0) {
		ok = TRUE;
		envv = procstat_getenvv (prstat, &procs[0], 0);
		if (envv != NULL) {
			gboolean found_appimage = (out_appimage == NULL);
			gboolean found_wineprefix = (out_wineprefix == NULL);
			for (size_t i = 0; envv[i] != NULL && !(found_appimage && found_wineprefix); i++) {
				if (!found_appimage && g_str_has_prefix (envv[i], "APPIMAGE=")) {
					char *val = g_strstrip (g_strdup (envv[i] + 9));
					if (val[0] != '\0' && g_file_test (val, G_FILE_TEST_EXISTS)) {
						g_free (*out_appimage);
						*out_appimage = val;
						found_appimage = TRUE;
					} else {
						g_free (val);
					}
				} else if (!found_wineprefix && g_str_has_prefix (envv[i], "WINEPREFIX=")) {
					char *val = g_strstrip (g_strdup (envv[i] + 11));
					g_free (*out_wineprefix);
					*out_wineprefix = val;
					found_wineprefix = TRUE;
				}
			}
		}
		procstat_freeprocs (prstat, procs);
	}

	procstat_close (prstat);
	return ok;
}

int *
bsd_kernel_get_child_pids (int pid, int *out_len)
{
	struct procstat *prstat;
	struct kinfo_proc *procs;
	unsigned int cnt = 0;
	int *children = NULL;

	if (out_len != NULL)
		*out_len = 0;

	if (pid <= 0)
		return NULL;

	prstat = procstat_open_sysctl ();
	if (prstat == NULL)
		return NULL;

	procs = procstat_getprocs (prstat, KERN_PROC_PROC, 0, &cnt);
	if (procs != NULL && cnt > 0) {
		unsigned int i;
		int match_cnt = 0;
		for (i = 0; i < cnt; i++) {
			if (procs[i].ki_ppid == (pid_t) pid &&
			    procs[i].ki_pid > 0 &&
			    procs[i].ki_pid != (pid_t) pid) {
				match_cnt++;
			}
		}
		if (match_cnt > 0) {
			int idx = 0;
			children = g_new (int, match_cnt);
			for (i = 0; i < cnt && idx < match_cnt; i++) {
				if (procs[i].ki_ppid == (pid_t) pid &&
				    procs[i].ki_pid > 0 &&
				    procs[i].ki_pid != (pid_t) pid) {
					children[idx++] = (int) procs[i].ki_pid;
				}
			}
			if (out_len != NULL)
				*out_len = idx;
		}
		procstat_freeprocs (prstat, procs);
	}

	procstat_close (prstat);
	return children;
}

char **
bsd_kernel_get_open_fd_paths (int pid)
{
	struct procstat *prstat;
	struct kinfo_proc *procs;
	unsigned int cnt = 0;
	struct filestat_list *head;
	struct filestat *fst;
	GPtrArray *paths;

	if (pid <= 0)
		return NULL;

	prstat = procstat_open_sysctl ();
	if (prstat == NULL)
		return NULL;

	procs = procstat_getprocs (prstat, KERN_PROC_PID, pid, &cnt);
	if (procs == NULL || cnt == 0) {
		if (procs != NULL)
			procstat_freeprocs (prstat, procs);
		procstat_close (prstat);
		return NULL;
	}

	paths = g_ptr_array_new ();
	head = procstat_getfiles (prstat, &procs[0], 0);
	if (head != NULL) {
		STAILQ_FOREACH (fst, head, next) {
			if (fst->fs_type == PS_FST_TYPE_VNODE &&
			    fst->fs_fd > 0 &&
			    fst->fs_path != NULL &&
			    fst->fs_path[0] != '\0') {
				g_ptr_array_add (paths, g_strdup (fst->fs_path));
			}
		}
		procstat_freefiles (prstat, head);
	}

	procstat_freeprocs (prstat, procs);
	procstat_close (prstat);

	g_ptr_array_add (paths, NULL);
	return (char **) g_ptr_array_free (paths, FALSE);
}

/* ============================================================================
 * CPU, RAM (ZFS ARC-aware) & Disk I/O (`sysctl(3)` & `libdevstat(3)`)
 * ============================================================================ */

static gboolean
read_sysctl_u64 (const char *name, guint64 *out_val)
{
	guint64 v64 = 0;
	size_t sz = sizeof (v64);
	if (sysctlbyname (name, &v64, &sz, NULL, 0) == 0) {
		if (sz == sizeof (guint64)) {
			*out_val = v64;
			return TRUE;
		}
		if (sz == sizeof (guint32)) {
			guint32 v32 = 0;
			sz = sizeof (v32);
			if (sysctlbyname (name, &v32, &sz, NULL, 0) == 0) {
				*out_val = (guint64) v32;
				return TRUE;
			}
		}
	}
	return FALSE;
}

static gboolean
read_sysctl_int (const char *name, int *out_val)
{
	int v = 0;
	size_t sz = sizeof (v);
	if (sysctlbyname (name, &v, &sz, NULL, 0) == 0 && sz == sizeof (v)) {
		*out_val = v;
		return TRUE;
	}
	return FALSE;
}

gboolean
bsd_kernel_read_cpu_ticks (guint64 *out_total, guint64 *out_idle)
{
	long cp_time[CPUSTATES];
	size_t sz = sizeof (cp_time);
	guint64 total = 0;

	if (out_total != NULL)
		*out_total = 0;
	if (out_idle != NULL)
		*out_idle = 0;

	if (sysctlbyname ("kern.cp_time", cp_time, &sz, NULL, 0) != 0)
		return FALSE;

	for (int i = 0; i < CPUSTATES; i++) {
		if (cp_time[i] > 0)
			total += (guint64) cp_time[i];
	}

	if (out_total != NULL)
		*out_total = total;
	if (out_idle != NULL)
		*out_idle = (cp_time[CP_IDLE] > 0) ? (guint64) cp_time[CP_IDLE] : 0;

	return TRUE;
}

gboolean
bsd_kernel_read_memory (guint64 *out_total_bytes, guint64 *out_avail_bytes)
{
	guint64 physmem = 0;
	guint64 pagesize = 4096;
	guint64 free_cnt = 0;
	guint64 inactive_cnt = 0;
	guint64 cache_cnt = 0;
	guint64 avail = 0;
	guint64 arc_size = 0;
	guint64 arc_min = 0;

	if (out_total_bytes != NULL)
		*out_total_bytes = 0;
	if (out_avail_bytes != NULL)
		*out_avail_bytes = 0;

	if (!read_sysctl_u64 ("hw.physmem", &physmem) || physmem == 0)
		return FALSE;

	read_sysctl_u64 ("hw.pagesize", &pagesize);
	if (pagesize == 0)
		pagesize = 4096;

	read_sysctl_u64 ("vm.stats.vm.v_free_count", &free_cnt);
	read_sysctl_u64 ("vm.stats.vm.v_inactive_count", &inactive_cnt);
	read_sysctl_u64 ("vm.stats.vm.v_cache_count", &cache_cnt);

	avail = (free_cnt + inactive_cnt + cache_cnt) * pagesize;

	/* OpenZFS ARC reclaimable memory (kstat.zfs.misc.arcstats.{size,c_min}) */
	if (read_sysctl_u64 ("kstat.zfs.misc.arcstats.size", &arc_size)) {
		read_sysctl_u64 ("kstat.zfs.misc.arcstats.c_min", &arc_min);
		if (arc_size > arc_min)
			avail += (arc_size - arc_min);
	}

	if (avail > physmem)
		avail = physmem;

	if (out_total_bytes != NULL)
		*out_total_bytes = physmem;
	if (out_avail_bytes != NULL)
		*out_avail_bytes = avail;

	return TRUE;
}

gboolean
bsd_kernel_read_disk_busy_ms (guint64 *out_busy_ms)
{
	struct statinfo sinfo;
	struct devinfo dinfo;
	guint64 total_ms = 0;

	if (out_busy_ms != NULL)
		*out_busy_ms = 0;

	memset (&sinfo, 0, sizeof (sinfo));
	memset (&dinfo, 0, sizeof (dinfo));
	sinfo.dinfo = &dinfo;

	if (devstat_getdevs (NULL, &sinfo) < 0) {
		free (dinfo.mem_ptr);
		return FALSE;
	}

	for (int i = 0; i < dinfo.numdevs; i++) {
		struct devstat *ds = &dinfo.devices[i];
		if ((ds->device_type & DEVSTAT_TYPE_MASK) != DEVSTAT_TYPE_DIRECT)
			continue;
		long double sec = devstat_compute_etime (&ds->busy_time, NULL);
		if (sec > 0.0L)
			total_ms += (guint64) (sec * 1000.0L);
	}

	free (dinfo.mem_ptr);

	if (out_busy_ms != NULL)
		*out_busy_ms = total_ms;
	return TRUE;
}

/* ============================================================================
 * Battery & AC Power (`sysctl(3)` ACPI)
 * ============================================================================ */

gboolean
bsd_kernel_read_battery (gboolean *out_has_battery,
                         int *out_percentage,
                         gboolean *out_is_charging,
                         gboolean *out_is_full,
                         char **out_raw_status)
{
	int units = 0;
	int life = 100;
	int state = 0;
	int acline = 1;

	if (out_has_battery != NULL)
		*out_has_battery = FALSE;
	if (out_percentage != NULL)
		*out_percentage = 100;
	if (out_is_charging != NULL)
		*out_is_charging = FALSE;
	if (out_is_full != NULL)
		*out_is_full = TRUE;
	if (out_raw_status != NULL)
		*out_raw_status = g_strdup ("");

	if (!read_sysctl_int ("hw.acpi.battery.units", &units) || units <= 0)
		return TRUE;

	if (!read_sysctl_int ("hw.acpi.battery.life", &life) || life < 0)
		return TRUE;

	read_sysctl_int ("hw.acpi.battery.state", &state);
	read_sysctl_int ("hw.acpi.acline", &acline);

	/* ACPI state bitmask: 0=full/idle, 1=discharging, 2=charging, 4=critical, 7=absent */
	if (state == 7)
		return TRUE;

	if (life > 100)
		life = 100;

	gboolean is_charging = ((state & 0x02) != 0);
	gboolean is_discharging = ((state & 0x01) != 0);
	gboolean is_full = (!is_charging && !is_discharging && (acline == 1 || life >= 99));

	const char *status_str = "Discharging";
	if (is_charging)
		status_str = "Charging";
	else if (is_full)
		status_str = "Full";
	else if (!is_discharging && acline == 1)
		status_str = "Not charging";

	if (out_has_battery != NULL)
		*out_has_battery = TRUE;
	if (out_percentage != NULL)
		*out_percentage = life;
	if (out_is_charging != NULL)
		*out_is_charging = is_charging;
	if (out_is_full != NULL)
		*out_is_full = is_full;
	if (out_raw_status != NULL) {
		g_free (*out_raw_status);
		*out_raw_status = g_strdup (status_str);
	}
	return TRUE;
}

/* ============================================================================
 * Native FreeBSD OSS Audio (`<sys/soundcard.h>` `/dev/mixer*`)
 * ============================================================================ */

static int
open_oss_mixer (int flags)
{
	int fd = open ("/dev/mixer", flags);
	if (fd >= 0)
		return fd;

	int unit = 0;
	if (read_sysctl_int ("hw.snd.default_unit", &unit) && unit >= 0) {
		char devpath[64];
		g_snprintf (devpath, sizeof (devpath), "/dev/mixer%d", unit);
		fd = open (devpath, flags);
		if (fd >= 0)
			return fd;
	}

	return open ("/dev/mixer0", flags);
}

gboolean
bsd_kernel_oss_get_volume (int *out_percent)
{
	int fd;
	int vol = 0;

	if (out_percent != NULL)
		*out_percent = 70;

	fd = open_oss_mixer (O_RDONLY);
	if (fd < 0)
		return FALSE;

	if (ioctl (fd, SOUND_MIXER_READ_VOLUME, &vol) < 0) {
		close (fd);
		return FALSE;
	}
	close (fd);

	int left = vol & 0x7f;
	int right = (vol >> 8) & 0x7f;
	int avg = (left + right + 1) / 2;
	if (avg < 0) avg = 0;
	if (avg > 100) avg = 100;

	if (out_percent != NULL)
		*out_percent = avg;
	return TRUE;
}

gboolean
bsd_kernel_oss_set_volume (int percent)
{
	int fd;
	int clamped = percent;
	int packed;

	if (clamped < 0) clamped = 0;
	if (clamped > 100) clamped = 100;

	fd = open_oss_mixer (O_RDWR);
	if (fd < 0)
		return FALSE;

	packed = (clamped & 0x7f) | ((clamped & 0x7f) << 8);
	gboolean ok = (ioctl (fd, SOUND_MIXER_WRITE_VOLUME, &packed) == 0);
	close (fd);
	return ok;
}

/* ============================================================================
 * Hardware Backlight (`<sys/backlight.h>` `/dev/backlight/backlightN` & `hw.acpi.video.*`)
 * ============================================================================ */

char **
bsd_kernel_backlight_list_devices (char **out_preferred, guint32 *out_max_raw)
{
	GPtrArray *list = g_ptr_array_new ();
	char *preferred = NULL;
	guint32 max_raw = BACKLIGHTMAXLEVELS;
	DIR *dir;

	if (out_preferred != NULL)
		*out_preferred = NULL;
	if (out_max_raw != NULL)
		*out_max_raw = BACKLIGHTMAXLEVELS;

	dir = opendir ("/dev/backlight");
	if (dir != NULL) {
		struct dirent *ent;
		while ((ent = readdir (dir)) != NULL) {
			if (!g_str_has_prefix (ent->d_name, "backlight"))
				continue;
			char path[PATH_MAX];
			g_snprintf (path, sizeof (path), "/dev/backlight/%s", ent->d_name);
			int fd = open (path, O_RDONLY);
			if (fd < 0)
				continue;
			struct backlight_info info;
			memset (&info, 0, sizeof (info));
			gboolean is_panel = TRUE;
			if (ioctl (fd, BACKLIGHTGETINFO, &info) == 0) {
				if (info.type != BACKLIGHT_TYPE_PANEL)
					is_panel = FALSE;
			}
			close (fd);
			if (!is_panel)
				continue;
			g_ptr_array_add (list, g_strdup (ent->d_name));
			if (preferred == NULL)
				preferred = g_strdup (ent->d_name);
		}
		closedir (dir);
	}

	/* Fallback: acpi_video(4) sysctl */
	int acpi_val = -1;
	if (read_sysctl_int ("hw.acpi.video.lcd0.brightness", &acpi_val) && acpi_val >= 0) {
		g_ptr_array_add (list, g_strdup ("acpi:lcd0"));
		if (preferred == NULL)
			preferred = g_strdup ("acpi:lcd0");
	}

	if (out_preferred != NULL)
		*out_preferred = preferred;
	else
		g_free (preferred);

	if (out_max_raw != NULL)
		*out_max_raw = max_raw;

	g_ptr_array_add (list, NULL);
	return (char **) g_ptr_array_free (list, FALSE);
}

gboolean
bsd_kernel_backlight_lid_is_open (void)
{
	int lid = 1;
	if (read_sysctl_int ("hw.acpi.lid_switch_state", &lid)) {
		if (lid == 0)
			return FALSE;
	}
	return TRUE;
}

gint64
bsd_kernel_backlight_read_raw (const char *device)
{
	if (device == NULL || device[0] == '\0')
		return -1;

	if (g_strcmp0 (device, "acpi:lcd0") == 0) {
		int val = -1;
		if (read_sysctl_int ("hw.acpi.video.lcd0.brightness", &val) && val >= 0)
			return (gint64) val;
		return -1;
	}

	char path[PATH_MAX];
	g_snprintf (path, sizeof (path), "/dev/backlight/%s", device);
	int fd = open (path, O_RDONLY);
	if (fd < 0)
		return -1;

	struct backlight_props props;
	memset (&props, 0, sizeof (props));
	gint64 result = -1;
	if (ioctl (fd, BACKLIGHTGETSTATUS, &props) == 0)
		result = (gint64) props.brightness;
	close (fd);
	return result;
}

gboolean
bsd_kernel_backlight_write_raw (const char *device, guint32 raw_value)
{
	if (device == NULL || device[0] == '\0')
		return FALSE;

	if (raw_value > BACKLIGHTMAXLEVELS)
		raw_value = BACKLIGHTMAXLEVELS;

	if (g_strcmp0 (device, "acpi:lcd0") == 0) {
		int val = (int) raw_value;
		return (sysctlbyname ("hw.acpi.video.lcd0.brightness", NULL, NULL, &val, sizeof (val)) == 0);
	}

	char path[PATH_MAX];
	g_snprintf (path, sizeof (path), "/dev/backlight/%s", device);
	int fd = open (path, O_RDWR);
	if (fd < 0)
		return FALSE;

	struct backlight_props props;
	memset (&props, 0, sizeof (props));
	props.brightness = raw_value;
	gboolean ok = (ioctl (fd, BACKLIGHTUPDATESTATUS, &props) == 0);
	close (fd);
	return ok;
}

/* ============================================================================
 * Native Network Probe (`getifaddrs` + `SIOCGIFMEDIA` + `SIOCG80211` + `PF_ROUTE`)
 * ============================================================================ */

static void
read_default_ipv4_gateway (char *out_gw, size_t out_gw_len)
{
	int mib[6] = { CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0 };
	size_t needed = 0;
	char *buf;
	char *next;
	char *lim;

	out_gw[0] = '\0';

	if (sysctl (mib, 6, NULL, &needed, NULL, 0) < 0 || needed == 0)
		return;

	buf = g_malloc (needed);
	if (sysctl (mib, 6, buf, &needed, NULL, 0) < 0) {
		g_free (buf);
		return;
	}

	lim = buf + needed;
	for (next = buf; next < lim; ) {
		struct rt_msghdr *rtm = (struct rt_msghdr *) next;
		if (rtm->rtm_msglen == 0)
			break;
		next += rtm->rtm_msglen;

		if (rtm->rtm_version != RTM_VERSION)
			continue;
		if ((rtm->rtm_addrs & (RTA_DST | RTA_GATEWAY)) != (RTA_DST | RTA_GATEWAY))
			continue;

		struct sockaddr *sa = (struct sockaddr *) (rtm + 1);
		struct sockaddr *sa_tab[RTAX_MAX];
		memset (sa_tab, 0, sizeof (sa_tab));
		for (int i = 0; i < RTAX_MAX; i++) {
			if ((rtm->rtm_addrs & (1 << i)) != 0) {
				sa_tab[i] = sa;
				size_t step = (sa->sa_len > 0)
					? ((size_t) ((sa->sa_len + sizeof (long) - 1) & ~(sizeof (long) - 1)))
					: sizeof (long);
				sa = (struct sockaddr *) ((char *) sa + step);
			}
		}

		struct sockaddr *dst = sa_tab[RTAX_DST];
		struct sockaddr *gw = sa_tab[RTAX_GATEWAY];
		struct sockaddr *mask = sa_tab[RTAX_NETMASK];

		if (dst == NULL || dst->sa_family != AF_INET)
			continue;
		if (((struct sockaddr_in *) dst)->sin_addr.s_addr != INADDR_ANY)
			continue;
		if (mask != NULL && mask->sa_len > 0 && mask->sa_family == AF_INET) {
			if (((struct sockaddr_in *) mask)->sin_addr.s_addr != INADDR_ANY)
				continue;
		}
		if (gw != NULL && gw->sa_family == AF_INET) {
			inet_ntop (AF_INET, &((struct sockaddr_in *) gw)->sin_addr, out_gw, (socklen_t) out_gw_len);
			break;
		}
	}

	g_free (buf);
}

gboolean
bsd_kernel_probe_network (char **out_type,
                          char **out_name,
                          int *out_strength,
                          char **out_ip,
                          char **out_gateway)
{
	struct ifaddrs *ifap = NULL;
	struct ifaddrs *ifa;
	int sock = -1;
	gboolean found = FALSE;
	gboolean found_wifi = FALSE;
	char best_if[IFNAMSIZ] = { 0 };
	char best_ip[INET_ADDRSTRLEN] = { 0 };
	char best_ssid[64] = { 0 };
	int best_strength = 0;

	if (out_type != NULL) *out_type = g_strdup ("none");
	if (out_name != NULL) *out_name = g_strdup ("");
	if (out_strength != NULL) *out_strength = 0;
	if (out_ip != NULL) *out_ip = g_strdup ("");
	if (out_gateway != NULL) *out_gateway = g_strdup ("");

	if (getifaddrs (&ifap) != 0 || ifap == NULL)
		return FALSE;

	sock = socket (AF_INET, SOCK_DGRAM, 0);

	for (ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
		if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != AF_INET)
			continue;
		if ((ifa->ifa_flags & IFF_LOOPBACK) != 0)
			continue;
		if ((ifa->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING))
			continue;

		char ipbuf[INET_ADDRSTRLEN];
		if (inet_ntop (AF_INET, &((struct sockaddr_in *) ifa->ifa_addr)->sin_addr, ipbuf, sizeof (ipbuf)) == NULL)
			continue;
		if (g_str_has_prefix (ipbuf, "127.") || g_str_has_prefix (ipbuf, "169.254."))
			continue;

		gboolean is_wifi = FALSE;
		char ssid[64] = { 0 };
		int strength = 0;

		if (sock >= 0) {
			struct ifmediareq ifmr;
			memset (&ifmr, 0, sizeof (ifmr));
			g_strlcpy (ifmr.ifm_name, ifa->ifa_name, sizeof (ifmr.ifm_name));
			if (ioctl (sock, SIOCGIFMEDIA, &ifmr) == 0) {
				if (IFM_TYPE (ifmr.ifm_active) == IFM_IEEE80211 || IFM_TYPE (ifmr.ifm_current) == IFM_IEEE80211)
					is_wifi = TRUE;
			}
			if (is_wifi) {
				struct ieee80211req ireq;
				memset (&ireq, 0, sizeof (ireq));
				g_strlcpy (ireq.i_name, ifa->ifa_name, sizeof (ireq.i_name));
				ireq.i_type = IEEE80211_IOC_SSID;
				ireq.i_val = -1;
				ireq.i_data = ssid;
				ireq.i_len = sizeof (ssid) - 1;
				if (ioctl (sock, SIOCG80211, &ireq) == 0 && ireq.i_len > 0) {
					if ((size_t) ireq.i_len < sizeof (ssid))
						ssid[ireq.i_len] = '\0';
					else
						ssid[sizeof (ssid) - 1] = '\0';
				}
				strength = 75;
			}
		}

		/* Prefer wired ethernet if already found, otherwise take first active */
		if (!found || (found_wifi && !is_wifi)) {
			found = TRUE;
			found_wifi = is_wifi;
			g_strlcpy (best_if, ifa->ifa_name, sizeof (best_if));
			g_strlcpy (best_ip, ipbuf, sizeof (best_ip));
			g_strlcpy (best_ssid, ssid, sizeof (best_ssid));
			best_strength = strength;
		}
	}

	if (sock >= 0)
		close (sock);
	freeifaddrs (ifap);

	if (!found)
		return FALSE;

	char gwbuf[INET_ADDRSTRLEN] = { 0 };
	read_default_ipv4_gateway (gwbuf, sizeof (gwbuf));

	if (out_type != NULL) {
		g_free (*out_type);
		*out_type = g_strdup (found_wifi ? "wifi" : "ethernet");
	}
	if (out_name != NULL) {
		g_free (*out_name);
		*out_name = g_strdup ((found_wifi && best_ssid[0] != '\0') ? best_ssid : best_if);
	}
	if (out_strength != NULL)
		*out_strength = best_strength;
	if (out_ip != NULL) {
		g_free (*out_ip);
		*out_ip = g_strdup (best_ip);
	}
	if (out_gateway != NULL) {
		g_free (*out_gateway);
		*out_gateway = g_strdup (gwbuf);
	}

	return TRUE;
}

#else

gboolean
bsd_kernel_is_process_alive (int pid)
{
	(void) pid;
	return FALSE;
}

char *
bsd_kernel_get_self_exe_path (void)
{
	return NULL;
}

int *
bsd_kernel_list_user_pids (int *out_len)
{
	if (out_len != NULL)
		*out_len = 0;
	return NULL;
}

gboolean
bsd_kernel_get_proc_basic (int pid,
                           int *out_uid,
                           char **out_comm,
                           char **out_exe_path,
                           char **out_cwd)
{
	(void) pid;
	if (out_uid != NULL) *out_uid = -1;
	if (out_comm != NULL) *out_comm = g_strdup ("");
	if (out_exe_path != NULL) *out_exe_path = g_strdup ("");
	if (out_cwd != NULL) *out_cwd = g_strdup ("");
	return FALSE;
}

char **
bsd_kernel_get_proc_argv (int pid)
{
	(void) pid;
	return NULL;
}

gboolean
bsd_kernel_get_proc_env_hints (int pid,
                               char **out_appimage,
                               char **out_wineprefix)
{
	(void) pid;
	if (out_appimage != NULL) *out_appimage = g_strdup ("");
	if (out_wineprefix != NULL) *out_wineprefix = g_strdup ("");
	return FALSE;
}

int *
bsd_kernel_get_child_pids (int pid, int *out_len)
{
	(void) pid;
	if (out_len != NULL) *out_len = 0;
	return NULL;
}

char **
bsd_kernel_get_open_fd_paths (int pid)
{
	(void) pid;
	return NULL;
}

gboolean
bsd_kernel_read_cpu_ticks (guint64 *out_total, guint64 *out_idle)
{
	if (out_total != NULL) *out_total = 0;
	if (out_idle != NULL) *out_idle = 0;
	return FALSE;
}

gboolean
bsd_kernel_read_memory (guint64 *out_total_bytes, guint64 *out_avail_bytes)
{
	if (out_total_bytes != NULL) *out_total_bytes = 0;
	if (out_avail_bytes != NULL) *out_avail_bytes = 0;
	return FALSE;
}

gboolean
bsd_kernel_read_disk_busy_ms (guint64 *out_busy_ms)
{
	if (out_busy_ms != NULL) *out_busy_ms = 0;
	return FALSE;
}

gboolean
bsd_kernel_read_battery (gboolean *out_has_battery,
                         int *out_percentage,
                         gboolean *out_is_charging,
                         gboolean *out_is_full,
                         char **out_raw_status)
{
	if (out_has_battery != NULL) *out_has_battery = FALSE;
	if (out_percentage != NULL) *out_percentage = 100;
	if (out_is_charging != NULL) *out_is_charging = FALSE;
	if (out_is_full != NULL) *out_is_full = TRUE;
	if (out_raw_status != NULL) *out_raw_status = g_strdup ("");
	return FALSE;
}

gboolean
bsd_kernel_oss_get_volume (int *out_percent)
{
	if (out_percent != NULL) *out_percent = 70;
	return FALSE;
}

gboolean
bsd_kernel_oss_set_volume (int percent)
{
	(void) percent;
	return FALSE;
}

char **
bsd_kernel_backlight_list_devices (char **out_preferred, guint32 *out_max_raw)
{
	if (out_preferred != NULL) *out_preferred = NULL;
	if (out_max_raw != NULL) *out_max_raw = 100;
	return NULL;
}

gboolean
bsd_kernel_backlight_lid_is_open (void)
{
	return TRUE;
}

gint64
bsd_kernel_backlight_read_raw (const char *device)
{
	(void) device;
	return -1;
}

gboolean
bsd_kernel_backlight_write_raw (const char *device, guint32 raw_value)
{
	(void) device;
	(void) raw_value;
	return FALSE;
}

gboolean
bsd_kernel_probe_network (char **out_type,
                          char **out_name,
                          int *out_strength,
                          char **out_ip,
                          char **out_gateway)
{
	if (out_type != NULL) *out_type = g_strdup ("none");
	if (out_name != NULL) *out_name = g_strdup ("");
	if (out_strength != NULL) *out_strength = 0;
	if (out_ip != NULL) *out_ip = g_strdup ("");
	if (out_gateway != NULL) *out_gateway = g_strdup ("");
	return FALSE;
}

#endif
