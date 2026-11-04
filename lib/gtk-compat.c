/*
 *  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
 *  Copyright (C) 2015 Rico Tzschichholz
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

#include <gtk/gtk.h>
#include <gio/gio.h>
#include <locale.h>
#include <string.h>
#include <stdint.h>

/* Conditional compat-layer for Gtk+ 3.19.1+ */

G_GNUC_BEGIN_IGNORE_DEPRECATIONS
void
__attribute__((weak)) gtk_widget_class_set_css_name (GtkWidgetClass *widget_class, const char *name);
void
plank_compat_gtk_widget_class_set_css_name (GtkWidgetClass *widget_class, const char *name)
{
	if (gtk_widget_class_set_css_name) {
		gtk_widget_class_set_css_name (widget_class, name);
	}
}
G_GNUC_END_IGNORE_DEPRECATIONS

G_GNUC_BEGIN_IGNORE_DEPRECATIONS
void
__attribute__((weak)) gtk_widget_path_iter_set_object_name (GtkWidgetPath *path, gint pos, const char *name);
void
plank_compat_gtk_widget_path_iter_set_object_name (GtkWidgetPath *path, gint pos, const char *name)
{
	if (gtk_widget_path_iter_set_object_name) {
		gtk_widget_path_iter_set_object_name (path, pos, name);
	}
}
G_GNUC_END_IGNORE_DEPRECATIONS

/* ============================================================================
 * WayPlank Monolithic In-Memory Localization Engine (GResource .mo in RAM)
 * ============================================================================ */

#ifndef WAYPLANK_EMBEDDED_LANGS
#define WAYPLANK_EMBEDDED_LANGS ""
#endif

static GBytes *wayplank_mo_bytes = NULL;
static const uint8_t *wayplank_mo_data = NULL;
static gsize wayplank_mo_size = 0;
static uint32_t wayplank_mo_nstrings = 0;
static uint32_t wayplank_mo_orig_offset = 0;
static uint32_t wayplank_mo_trans_offset = 0;
static gboolean wayplank_i18n_initialized = FALSE;
static char wayplank_active_lang[32] = "";

static const char *
wayplank_match_embedded_lang (const char *raw)
{
	if (raw == NULL || raw[0] == '\0')
		return NULL;

	/* Strip .encoding (e.g. .UTF-8) and @modifier (e.g. @euro) */
	char clean[64];
	g_strlcpy (clean, raw, sizeof (clean));
	char *dot = strchr (clean, '.');
	if (dot != NULL)
		*dot = '\0';
	char *at = strchr (clean, '@');
	if (at != NULL)
		*at = '\0';

	if (clean[0] == '\0')
		return NULL;

	/* Extract base language code before '_' (e.g. "it_IT" -> "it") */
	char base[32];
	g_strlcpy (base, clean, sizeof (base));
	char *sep = strchr (base, '_');
	if (sep != NULL)
		*sep = '\0';

	/* Native English / POSIX locales immediately resolve to "en" (fallback to native strings) */
	if (g_ascii_strcasecmp (clean, "C") == 0 ||
	    g_ascii_strcasecmp (clean, "POSIX") == 0 ||
	    g_ascii_strcasecmp (base, "en") == 0) {
		return "en";
	}

	/* Match against compile-time encoded languages (WAYPLANK_EMBEDDED_LANGS) */
	char **avail = g_strsplit (WAYPLANK_EMBEDDED_LANGS, ":", -1);
	if (avail == NULL)
		return NULL;

	/* 1. Exact full code match (e.g. "zh_CN" == "zh_CN" or "it" == "it") */
	for (int i = 0; avail[i] != NULL; i++) {
		if (avail[i][0] != '\0' && g_ascii_strcasecmp (avail[i], clean) == 0) {
			g_strlcpy (wayplank_active_lang, avail[i], sizeof (wayplank_active_lang));
			g_strfreev (avail);
			return wayplank_active_lang;
		}
	}

	/* 2. Base language code match (e.g. "it_IT" -> "it" == "it") */
	for (int i = 0; avail[i] != NULL; i++) {
		if (avail[i][0] != '\0' && g_ascii_strcasecmp (avail[i], base) == 0) {
			g_strlcpy (wayplank_active_lang, avail[i], sizeof (wayplank_active_lang));
			g_strfreev (avail);
			return wayplank_active_lang;
		}
	}

	/* 3. Base prefix match against regional catalog (e.g. "zh" -> "zh_CN") */
	gsize base_len = strlen (base);
	for (int i = 0; avail[i] != NULL; i++) {
		if (base_len > 0 &&
		    g_ascii_strncasecmp (avail[i], base, base_len) == 0 &&
		    avail[i][base_len] == '_') {
			g_strlcpy (wayplank_active_lang, avail[i], sizeof (wayplank_active_lang));
			g_strfreev (avail);
			return wayplank_active_lang;
		}
	}

	g_strfreev (avail);
	return NULL;
}

static const char *
wayplank_resolve_lang_from_env_str (const char *env_val)
{
	if (env_val == NULL || env_val[0] == '\0')
		return NULL;

	char **tokens = g_strsplit (env_val, ":", -1);
	const char *resolved = NULL;
	for (int i = 0; tokens != NULL && tokens[i] != NULL; i++) {
		const char *cand = wayplank_match_embedded_lang (tokens[i]);
		if (cand != NULL) {
			resolved = cand;
			break;
		}
	}
	g_strfreev (tokens);
	return resolved;
}

void
wayplank_i18n_init (void)
{
	wayplank_i18n_initialized = TRUE;

	if (wayplank_mo_bytes != NULL) {
		g_bytes_unref (wayplank_mo_bytes);
		wayplank_mo_bytes = NULL;
	}
	wayplank_mo_data = NULL;
	wayplank_mo_size = 0;
	wayplank_mo_nstrings = 0;

	const char *lang = wayplank_resolve_lang_from_env_str (g_getenv ("LANGUAGE"));
	if (lang == NULL)
		lang = wayplank_resolve_lang_from_env_str (g_getenv ("LC_ALL"));
	if (lang == NULL)
		lang = wayplank_resolve_lang_from_env_str (g_getenv ("LC_MESSAGES"));
	if (lang == NULL)
		lang = wayplank_resolve_lang_from_env_str (g_getenv ("LANG"));
	if (lang == NULL)
		lang = wayplank_resolve_lang_from_env_str (setlocale (LC_MESSAGES, ""));

	if (lang == NULL || g_strcmp0 (lang, "en") == 0)
		return;

	char res_path[128];
	g_snprintf (res_path, sizeof (res_path), "/net/launchpad/plank/locale/%s/wayplank.mo", lang);

	GBytes *bytes = g_resources_lookup_data (res_path, G_RESOURCE_LOOKUP_FLAGS_NONE, NULL);
	if (bytes == NULL)
		return;

	gsize size = 0;
	const uint8_t *data = (const uint8_t *) g_bytes_get_data (bytes, &size);
	if (data == NULL || size < 28) {
		g_bytes_unref (bytes);
		return;
	}

	uint32_t magic = 0;
	memcpy (&magic, data, 4);
	if (magic != 0x950412deU) {
		g_bytes_unref (bytes);
		return;
	}

	uint32_t nstrings = 0, orig_off = 0, trans_off = 0;
	memcpy (&nstrings, data + 8, 4);
	memcpy (&orig_off, data + 12, 4);
	memcpy (&trans_off, data + 16, 4);

	if ((gsize) orig_off + (gsize) nstrings * 8U > size ||
	    (gsize) trans_off + (gsize) nstrings * 8U > size) {
		g_bytes_unref (bytes);
		return;
	}

	wayplank_mo_bytes = bytes;
	wayplank_mo_data = data;
	wayplank_mo_size = size;
	wayplank_mo_nstrings = nstrings;
	wayplank_mo_orig_offset = orig_off;
	wayplank_mo_trans_offset = trans_off;
}

const char *
wayplank_i18n_get (const char *msgid)
{
	if (msgid == NULL || msgid[0] == '\0')
		return msgid;

	if (!wayplank_i18n_initialized)
		wayplank_i18n_init ();

	if (wayplank_mo_data == NULL || wayplank_mo_nstrings == 0)
		return msgid;

	int32_t lo = 0;
	int32_t hi = (int32_t) wayplank_mo_nstrings - 1;

	while (lo <= hi) {
		int32_t mid = lo + (hi - lo) / 2;
		uint32_t o_len = 0, o_ptr = 0;
		memcpy (&o_len, wayplank_mo_data + wayplank_mo_orig_offset + (gsize) mid * 8U, 4);
		memcpy (&o_ptr, wayplank_mo_data + wayplank_mo_orig_offset + (gsize) mid * 8U + 4U, 4);

		if ((gsize) o_ptr + (gsize) o_len >= wayplank_mo_size)
			break;

		const char *orig_str = (const char *) (wayplank_mo_data + o_ptr);
		int cmp = strcmp (msgid, orig_str);
		if (cmp == 0) {
			uint32_t t_len = 0, t_ptr = 0;
			memcpy (&t_len, wayplank_mo_data + wayplank_mo_trans_offset + (gsize) mid * 8U, 4);
			memcpy (&t_ptr, wayplank_mo_data + wayplank_mo_trans_offset + (gsize) mid * 8U + 4U, 4);
			if (t_len > 0 && (gsize) t_ptr + (gsize) t_len < wayplank_mo_size) {
				return (const char *) (wayplank_mo_data + t_ptr);
			}
			return msgid;
		} else if (cmp > 0) {
			lo = mid + 1;
		} else {
			hi = mid - 1;
		}
	}

	return msgid;
}

void
wayplank_i18n_translate_widget (GtkWidget *widget)
{
	if (widget == NULL)
		return;

	char *tip = gtk_widget_get_tooltip_text (widget);
	if (tip != NULL) {
		if (tip[0] != '\0') {
			const char *tr_tip = wayplank_i18n_get (tip);
			if (tr_tip != tip && g_strcmp0 (tr_tip, tip) != 0)
				gtk_widget_set_tooltip_text (widget, tr_tip);
		}
		g_free (tip);
	}

	if (GTK_IS_LABEL (widget)) {
		const char *lbl = gtk_label_get_label (GTK_LABEL (widget));
		if (lbl != NULL && lbl[0] != '\0') {
			const char *tr_lbl = wayplank_i18n_get (lbl);
			if (tr_lbl != lbl && g_strcmp0 (tr_lbl, lbl) != 0)
				gtk_label_set_label (GTK_LABEL (widget), tr_lbl);
		}
	}

	if (GTK_IS_COMBO_BOX (widget)) {
		GtkTreeModel *model = gtk_combo_box_get_model (GTK_COMBO_BOX (widget));
		if (model != NULL && GTK_IS_LIST_STORE (model) &&
		    gtk_tree_model_get_column_type (model, 0) == G_TYPE_STRING) {
			GtkTreeIter iter;
			gboolean valid = gtk_tree_model_get_iter_first (model, &iter);
			while (valid) {
				char *item_text = NULL;
				gtk_tree_model_get (model, &iter, 0, &item_text, -1);
				if (item_text != NULL) {
					if (item_text[0] != '\0') {
						const char *tr_item = wayplank_i18n_get (item_text);
						if (tr_item != item_text && g_strcmp0 (tr_item, item_text) != 0)
							gtk_list_store_set (GTK_LIST_STORE (model), &iter, 0, tr_item, -1);
					}
					g_free (item_text);
				}
				valid = gtk_tree_model_iter_next (model, &iter);
			}
		}
	}

	if (GTK_IS_STACK (widget)) {
		GList *children = gtk_container_get_children (GTK_CONTAINER (widget));
		for (GList *l = children; l != NULL; l = l->next) {
			GtkWidget *child = GTK_WIDGET (l->data);
			char *title = NULL;
			gtk_container_child_get (GTK_CONTAINER (widget), child, "title", &title, NULL);
			if (title != NULL) {
				if (title[0] != '\0') {
					const char *tr_title = wayplank_i18n_get (title);
					if (tr_title != title && g_strcmp0 (tr_title, title) != 0)
						gtk_container_child_set (GTK_CONTAINER (widget), child, "title", tr_title, NULL);
				}
				g_free (title);
			}
		}
		g_list_free (children);
	}

	if (GTK_IS_CONTAINER (widget)) {
		GList *children = gtk_container_get_children (GTK_CONTAINER (widget));
		for (GList *l = children; l != NULL; l = l->next) {
			wayplank_i18n_translate_widget (GTK_WIDGET (l->data));
		}
		g_list_free (children);
	}
}
