//
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of WayPlank.
//
//  WayPlank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  WayPlank is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

[CCode (cheader_filename = "bsd-kernel-bridge.h")]
namespace Plank.BsdKernelBridge
{
	[CCode (cname = "bsd_kernel_is_process_alive")]
	public bool is_process_alive (int pid);

	[CCode (cname = "bsd_kernel_get_self_exe_path")]
	public string? get_self_exe_path ();

	[CCode (cname = "bsd_kernel_list_user_pids", array_length_type = "int")]
	public int[] list_user_pids ();

	[CCode (cname = "bsd_kernel_get_proc_basic")]
	public bool get_proc_basic (int pid, out int uid, out string comm, out string exe_path, out string cwd);

	[CCode (cname = "bsd_kernel_get_proc_argv", array_length = false, array_null_terminated = true)]
	public string[]? get_proc_argv (int pid);
}
