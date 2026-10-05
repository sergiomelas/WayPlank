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

#include "wlr-toplevel-bridge.h"
#include "wlr-foreign-toplevel-management-client-protocol.h"

#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#include <wayland-client.h>
#include <string.h>
#include <stdlib.h>

typedef struct {
    uint32_t id;
    char uuid[32];
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *title;
    char *app_id;
    gboolean minimized;
    gboolean active;
    gboolean maximized;
    gboolean fullscreen;
    int minimized_sequence;
} WlrToplevel;

static struct wl_display *wl_display_conn = NULL;
static struct wl_registry *wl_registry_obj = NULL;
static struct zwlr_foreign_toplevel_manager_v1 *toplevel_manager = NULL;
static struct wl_seat *default_seat = NULL;
static WlrStateChangedCallback state_changed_cb = NULL;

static GList *toplevel_list = NULL;
static GList *desktop_hidden_list = NULL;
static gboolean showing_desktop = FALSE;
static uint32_t next_toplevel_id = 0;
static int global_min_seq = 0;
static gboolean bridge_initialized = FALSE;

/* Forward declarations */
static void handle_toplevel_title (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title);
static void handle_toplevel_app_id (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *app_id);
static void handle_toplevel_output_enter (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output);
static void handle_toplevel_output_leave (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output);
static void handle_toplevel_state (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_array *state);
static void handle_toplevel_done (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle);
static void handle_toplevel_closed (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle);
static void handle_toplevel_parent (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct zwlr_foreign_toplevel_handle_v1 *parent);

static const struct zwlr_foreign_toplevel_handle_v1_listener handle_listener = {
    .title = handle_toplevel_title,
    .app_id = handle_toplevel_app_id,
    .output_enter = handle_toplevel_output_enter,
    .output_leave = handle_toplevel_output_leave,
    .state = handle_toplevel_state,
    .done = handle_toplevel_done,
    .closed = handle_toplevel_closed,
    .parent = handle_toplevel_parent,
};

static void
handle_toplevel_title (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title)
{
    (void)handle;
    WlrToplevel *t = (WlrToplevel *)data;
    if (!t) return;
    g_free (t->title);
    t->title = g_strdup (title ? title : "");
}

static void
handle_toplevel_app_id (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *app_id)
{
    (void)handle;
    WlrToplevel *t = (WlrToplevel *)data;
    if (!t) return;
    g_free (t->app_id);
    t->app_id = g_strdup (app_id ? app_id : "");
}

static void
handle_toplevel_output_enter (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output)
{
    (void)data; (void)handle; (void)output;
}

static void
handle_toplevel_output_leave (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output)
{
    (void)data; (void)handle; (void)output;
}

static void
handle_toplevel_state (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_array *state)
{
    (void)handle;
    WlrToplevel *t = (WlrToplevel *)data;
    if (!t) return;

    uint32_t *entry;
    gboolean is_max = FALSE;
    gboolean is_min = FALSE;
    gboolean is_act = FALSE;
    gboolean is_full = FALSE;

    wl_array_for_each (entry, state) {
        if (*entry == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED)
            is_max = TRUE;
        else if (*entry == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED)
            is_min = TRUE;
        else if (*entry == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED)
            is_act = TRUE;
        else if (*entry == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_FULLSCREEN)
            is_full = TRUE;
    }

    if (!t->minimized && is_min) {
        t->minimized_sequence = ++global_min_seq;
    }

    t->maximized = is_max;
    t->minimized = is_min;
    t->active = is_act;
    t->fullscreen = is_full;
}

static void
handle_toplevel_done (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle)
{
    (void)data; (void)handle;
    if (state_changed_cb) {
        state_changed_cb ();
    }
}

static void
handle_toplevel_closed (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle)
{
    WlrToplevel *t = (WlrToplevel *)data;
    if (t) {
        for (GList *h = desktop_hidden_list; h != NULL; h = h->next) {
            if (g_strcmp0 ((const gchar *)h->data, t->uuid) == 0) {
                desktop_hidden_list = g_list_delete_link (desktop_hidden_list, h);
                break;
            }
        }
        toplevel_list = g_list_remove (toplevel_list, t);
        g_free (t->title);
        g_free (t->app_id);
        g_free (t);
    }
    if (handle) {
        zwlr_foreign_toplevel_handle_v1_destroy (handle);
    }
    if (state_changed_cb) {
        state_changed_cb ();
    }
}

static void
handle_toplevel_parent (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct zwlr_foreign_toplevel_handle_v1 *parent)
{
    (void)data; (void)handle; (void)parent;
}

/* Manager listener */
static void
manager_handle_toplevel (void *data, struct zwlr_foreign_toplevel_manager_v1 *manager,
                         struct zwlr_foreign_toplevel_handle_v1 *handle)
{
    (void)data; (void)manager;
    WlrToplevel *t = g_new0 (WlrToplevel, 1);
    t->id = ++next_toplevel_id;
    g_snprintf (t->uuid, sizeof (t->uuid), "wlr-%u", t->id);
    t->handle = handle;
    t->title = g_strdup ("");
    t->app_id = g_strdup ("");
    toplevel_list = g_list_append (toplevel_list, t);

    zwlr_foreign_toplevel_handle_v1_add_listener (handle, &handle_listener, t);
}

static void
manager_handle_finished (void *data, struct zwlr_foreign_toplevel_manager_v1 *manager)
{
    (void)data; (void)manager;
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = manager_handle_toplevel,
    .finished = manager_handle_finished,
};

/* Registry listener */
static void
registry_handle_global (void *data, struct wl_registry *registry, uint32_t name,
                        const char *interface, uint32_t version)
{
    (void)data;
    if (strcmp (interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        uint32_t bind_ver = (version < 3) ? version : 3;
        toplevel_manager = wl_registry_bind (registry, name,
            &zwlr_foreign_toplevel_manager_v1_interface, bind_ver);
        zwlr_foreign_toplevel_manager_v1_add_listener (toplevel_manager, &manager_listener, NULL);
    } else if (strcmp (interface, wl_seat_interface.name) == 0 && !default_seat) {
        default_seat = wl_registry_bind (registry, name, &wl_seat_interface, 1);
    }
}

static void
registry_handle_global_remove (void *data, struct wl_registry *registry, uint32_t name)
{
    (void)data; (void)registry; (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove,
};

gboolean
wlr_toplevel_bridge_init (WlrStateChangedCallback callback)
{
    if (bridge_initialized)
        return (toplevel_manager != NULL);

    state_changed_cb = callback;

#ifdef GDK_WINDOWING_WAYLAND
    GdkDisplay *gdk_display = gdk_display_get_default ();
    if (!gdk_display || !GDK_IS_WAYLAND_DISPLAY (gdk_display)) {
        return FALSE;
    }
    wl_display_conn = gdk_wayland_display_get_wl_display (gdk_display);
    if (!wl_display_conn) {
        return FALSE;
    }

    wl_registry_obj = wl_display_get_registry (wl_display_conn);
    if (!wl_registry_obj) {
        return FALSE;
    }

    wl_registry_add_listener (wl_registry_obj, &registry_listener, NULL);

    /* Roundtrip to bind globals and register listeners */
    wl_display_roundtrip (wl_display_conn);
    /* Second roundtrip to receive initial toplevel list */
    if (toplevel_manager) {
        wl_display_roundtrip (wl_display_conn);
    }

    bridge_initialized = TRUE;
    return (toplevel_manager != NULL);
#else
    return FALSE;
#endif
}

void
wlr_toplevel_bridge_cleanup (void)
{
    for (GList *l = toplevel_list; l != NULL; l = l->next) {
        WlrToplevel *t = (WlrToplevel *)l->data;
        if (t->handle) {
            zwlr_foreign_toplevel_handle_v1_destroy (t->handle);
        }
        g_free (t->title);
        g_free (t->app_id);
        g_free (t);
    }
    g_list_free (toplevel_list);
    toplevel_list = NULL;

    g_list_free_full (desktop_hidden_list, g_free);
    desktop_hidden_list = NULL;

    if (toplevel_manager) {
        zwlr_foreign_toplevel_manager_v1_stop (toplevel_manager);
        zwlr_foreign_toplevel_manager_v1_destroy (toplevel_manager);
        toplevel_manager = NULL;
    }
    if (default_seat) {
        wl_seat_destroy (default_seat);
        default_seat = NULL;
    }
    if (wl_registry_obj) {
        wl_registry_destroy (wl_registry_obj);
        wl_registry_obj = NULL;
    }

    bridge_initialized = FALSE;
}

gboolean
wlr_toplevel_bridge_is_available (void)
{
    return (toplevel_manager != NULL);
}

gchar *
wlr_toplevel_bridge_get_window_json (void)
{
    GString *json = g_string_new ("[");
    gboolean first = TRUE;

    for (GList *l = toplevel_list; l != NULL; l = l->next) {
        WlrToplevel *t = (WlrToplevel *)l->data;
        if (!first)
            g_string_append (json, ",");
        first = FALSE;

        gchar *escaped_title = g_strescape (t->title ? t->title : "", NULL);
        gchar *escaped_app_id = g_strescape (t->app_id ? t->app_id : "", NULL);

        g_string_append_printf (json,
            "{\"uuid\":\"%s\","
            "\"caption\":\"%s\","
            "\"desktopFileName\":\"%s\","
            "\"resourceClass\":\"%s\","
            "\"resourceName\":\"%s\","
            "\"minimized\":%s,"
            "\"active\":%s,"
            "\"maximized\":%s,"
            "\"normal\":true,"
            "\"visible\":%s,"
            "\"minimizedSequence\":%d}",
            t->uuid,
            escaped_title,
            escaped_app_id,
            escaped_app_id,
            escaped_app_id,
            t->minimized ? "true" : "false",
            t->active ? "true" : "false",
            t->maximized ? "true" : "false",
            t->minimized ? "false" : "true",
            t->minimized_sequence
        );

        g_free (escaped_title);
        g_free (escaped_app_id);
    }

    g_string_append (json, "]");
    return g_string_free (json, FALSE);
}

gboolean
wlr_toplevel_bridge_queue_command (const gchar *target, const gchar *action)
{
    if (!target || !action || !toplevel_manager)
        return FALSE;

    if (g_strcmp0 (target, "desktop") == 0 || g_strcmp0 (action, "toggle_desktop") == 0) {
        gboolean any_unminimized = FALSE;
        for (GList *l = toplevel_list; l != NULL; l = l->next) {
            WlrToplevel *t = (WlrToplevel *)l->data;
            if (!t->minimized) {
                any_unminimized = TRUE;
                break;
            }
        }

        if (any_unminimized) {
            g_list_free_full (desktop_hidden_list, g_free);
            desktop_hidden_list = NULL;
            for (GList *l = toplevel_list; l != NULL; l = l->next) {
                WlrToplevel *t = (WlrToplevel *)l->data;
                if (!t->minimized && t->handle) {
                    desktop_hidden_list = g_list_append (desktop_hidden_list, g_strdup (t->uuid));
                    zwlr_foreign_toplevel_handle_v1_set_minimized (t->handle);
                }
            }
            showing_desktop = TRUE;
        } else {
            WlrToplevel *last_restored = NULL;
            for (GList *l = toplevel_list; l != NULL; l = l->next) {
                WlrToplevel *t = (WlrToplevel *)l->data;
                gboolean should_restore = FALSE;
                if (desktop_hidden_list != NULL) {
                    for (GList *h = desktop_hidden_list; h != NULL; h = h->next) {
                        if (g_strcmp0 ((const gchar *)h->data, t->uuid) == 0) {
                            should_restore = TRUE;
                            break;
                        }
                    }
                } else {
                    should_restore = TRUE;
                }

                if (should_restore && t->handle) {
                    zwlr_foreign_toplevel_handle_v1_unset_minimized (t->handle);
                    if (default_seat) {
                        zwlr_foreign_toplevel_handle_v1_activate (t->handle, default_seat);
                    }
                    last_restored = t;
                }
            }
            if (last_restored && last_restored->handle && default_seat) {
                zwlr_foreign_toplevel_handle_v1_activate (last_restored->handle, default_seat);
            }
            g_list_free_full (desktop_hidden_list, g_free);
            desktop_hidden_list = NULL;
            showing_desktop = FALSE;
        }
        if (wl_display_conn)
            wl_display_flush (wl_display_conn);
        return TRUE;
    }

    WlrToplevel *found_toplevel = NULL;
    for (GList *l = toplevel_list; l != NULL; l = l->next) {
        WlrToplevel *t = (WlrToplevel *)l->data;
        if (g_strcmp0 (t->uuid, target) == 0) {
            found_toplevel = t;
            break;
        }
    }

    if (!found_toplevel || !found_toplevel->handle)
        return FALSE;

    if (g_strcmp0 (action, "activate") == 0) {
        if (found_toplevel->minimized) {
            zwlr_foreign_toplevel_handle_v1_unset_minimized (found_toplevel->handle);
        }
        if (default_seat) {
            zwlr_foreign_toplevel_handle_v1_activate (found_toplevel->handle, default_seat);
        }
    } else if (g_strcmp0 (action, "toggle") == 0) {
        if (found_toplevel->minimized) {
            zwlr_foreign_toplevel_handle_v1_unset_minimized (found_toplevel->handle);
            if (default_seat) {
                zwlr_foreign_toplevel_handle_v1_activate (found_toplevel->handle, default_seat);
            }
        } else if (found_toplevel->active) {
            zwlr_foreign_toplevel_handle_v1_set_minimized (found_toplevel->handle);
        } else {
            if (default_seat) {
                zwlr_foreign_toplevel_handle_v1_activate (found_toplevel->handle, default_seat);
            }
        }
    } else if (g_strcmp0 (action, "close") == 0) {
        zwlr_foreign_toplevel_handle_v1_close (found_toplevel->handle);
    }

    if (wl_display_conn)
        wl_display_flush (wl_display_conn);

    return TRUE;
}

gboolean
wlr_toplevel_bridge_any_window_intersects (int x, int y, int width, int height)
{
    (void)x; (void)y; (void)width; (void)height;
    for (GList *l = toplevel_list; l != NULL; l = l->next) {
        WlrToplevel *t = (WlrToplevel *)l->data;
        if (!t->minimized) {
            return TRUE;
        }
    }
    return FALSE;
}

gboolean
wlr_toplevel_bridge_active_window_intersects (int x, int y, int width, int height)
{
    (void)x; (void)y; (void)width; (void)height;
    for (GList *l = toplevel_list; l != NULL; l = l->next) {
        WlrToplevel *t = (WlrToplevel *)l->data;
        if (t->active && !t->minimized) {
            return TRUE;
        }
    }
    return FALSE;
}

gboolean
wlr_toplevel_bridge_maximized_window_intersects (int x, int y, int width, int height)
{
    (void)x; (void)y; (void)width; (void)height;
    for (GList *l = toplevel_list; l != NULL; l = l->next) {
        WlrToplevel *t = (WlrToplevel *)l->data;
        if (!t->minimized && (t->maximized || t->fullscreen)) {
            return TRUE;
        }
    }
    return FALSE;
}
