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

G_END_DECLS
