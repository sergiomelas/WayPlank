//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
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

namespace Plank
{
#if HAVE_SYS_PRCTL_H
	[CCode (cheader_filename = "sys/prctl.h", cname = "prctl", sentinel = "")]
	public int prctl (int option, ...);
#else
	[CCode (cheader_filename = "unistd.h", cname = "setproctitle", sentinel = "")]
	public void setproctitle (string fmt, ...);
#endif

	[CCode (cheader_filename = "unistd.h", cname = "getpid")]
	public int getpid ();
}
