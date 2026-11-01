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
 *  WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#pragma once

#define PACKAGE_NAME "WayPlank"
#define PACKAGE_TARNAME "wayplank"
#define PACKAGE_VERSION "0.7.0"
#define PACKAGE_STRING "WayPlank 0.7.0"
#define PACKAGE_BUGREPORT "https://github.com/sergiomelas/wayplank/issues"
#define PACKAGE_URL "https://github.com/sergiomelas/wayplank"
#define VERSION "0.7.0"
#define GETTEXT_PACKAGE "wayplank"

#define PREFIX "/usr"
#define DATADIR "/usr/share"
#define PKGDATADIR "/usr/share/wayplank"
#define RELEASE_NAME "WayPlank"
#define VERSION_INFO "WayPlank 0.7.0 - Public Beta 1"
#define TEST_DATA_DIR ""

#include <glib/gi18n-lib.h>
const char *wayplank_i18n_get (const char *msgid);
#undef _
#define _(String) ((char *) wayplank_i18n_get (String))
