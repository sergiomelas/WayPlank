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
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#include "win32-bridge.h"

int
win32_bridge_get_current_pid (void)
{
#ifdef _WIN32
	return (int) GetCurrentProcessId ();
#else
	return 0;
#endif
}

void
win32_bridge_exit_immediately (int status_code)
{
#ifdef _WIN32
	TerminateProcess (GetCurrentProcess (), (UINT) status_code);
#endif
}

#ifdef _WIN32
/* Compatibility forwarders for gtk3 objects compiled against proxy-libintl headers */
extern char *libintl_bindtextdomain (const char *domainname, const char *dirname);
extern char *libintl_bind_textdomain_codeset (const char *domainname, const char *codeset);
extern char *libintl_dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n);

char *
g_libintl_bindtextdomain (const char *domainname, const char *dirname)
{
	return libintl_bindtextdomain (domainname, dirname);
}

char *
g_libintl_bind_textdomain_codeset (const char *domainname, const char *codeset)
{
	return libintl_bind_textdomain_codeset (domainname, codeset);
}

char *
g_libintl_dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n)
{
	return libintl_dngettext (domainname, msgid1, msgid2, n);
}
#endif
