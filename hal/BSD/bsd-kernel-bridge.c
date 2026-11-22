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
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/user.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libprocstat.h>

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
	if (out_uid != NULL)
		*out_uid = -1;
	if (out_comm != NULL)
		*out_comm = g_strdup ("");
	if (out_exe_path != NULL)
		*out_exe_path = g_strdup ("");
	if (out_cwd != NULL)
		*out_cwd = g_strdup ("");
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
	if (out_appimage != NULL)
		*out_appimage = g_strdup ("");
	if (out_wineprefix != NULL)
		*out_wineprefix = g_strdup ("");
	return FALSE;
}

int *
bsd_kernel_get_child_pids (int pid, int *out_len)
{
	(void) pid;
	if (out_len != NULL)
		*out_len = 0;
	return NULL;
}

char **
bsd_kernel_get_open_fd_paths (int pid)
{
	(void) pid;
	return NULL;
}

#endif
