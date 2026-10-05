//
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of Wayplank.
//
//  Wayplank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Wayplank is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#ifndef WLR_TOPLEVEL_BRIDGE_H
#define WLR_TOPLEVEL_BRIDGE_H

#include <glib.h>

G_BEGIN_DECLS

typedef void (*WlrStateChangedCallback) (void);

gboolean wlr_toplevel_bridge_init (WlrStateChangedCallback callback);
void wlr_toplevel_bridge_cleanup (void);
gboolean wlr_toplevel_bridge_is_available (void);
gchar *wlr_toplevel_bridge_get_window_json (void);
gboolean wlr_toplevel_bridge_queue_command (const gchar *target, const gchar *action);
gboolean wlr_toplevel_bridge_any_window_intersects (int x, int y, int width, int height);
gboolean wlr_toplevel_bridge_active_window_intersects (int x, int y, int width, int height);
gboolean wlr_toplevel_bridge_maximized_window_intersects (int x, int y, int width, int height);

G_END_DECLS

#endif /* WLR_TOPLEVEL_BRIDGE_H */
