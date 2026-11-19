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
 *
 *  Static zero-DLL SVG loader for gdk-pixbuf backed by lunasvg.
 *  Compiled directly into libgdk_pixbuf-2.0.a by BuildWin.sh so all embedded
 *  GResource vector icons render at native HiDPI scale with 0 external DLLs.
 */

#include <cmath>
#include <cstring>
#include <lunasvg.h>

extern "C" {
#define GDK_PIXBUF_ENABLE_BACKEND
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gdk-pixbuf/gdk-pixbuf-io.h>

typedef struct {
	GdkPixbufModuleSizeFunc size_func;
	GdkPixbufModulePreparedFunc prepared_func;
	GdkPixbufModuleUpdatedFunc updated_func;
	gpointer user_data;
	GByteArray *buffer;
} LunaSvgContext;

static gpointer
svg_begin_load (GdkPixbufModuleSizeFunc size_func,
                GdkPixbufModulePreparedFunc prepared_func,
                GdkPixbufModuleUpdatedFunc updated_func,
                gpointer user_data,
                GError **error)
{
	(void) error;
	LunaSvgContext *ctx = g_new0 (LunaSvgContext, 1);
	ctx->size_func = size_func;
	ctx->prepared_func = prepared_func;
	ctx->updated_func = updated_func;
	ctx->user_data = user_data;
	ctx->buffer = g_byte_array_new ();
	return ctx;
}

static gboolean
svg_load_increment (gpointer data,
                    const guchar *buf,
                    guint size,
                    GError **error)
{
	(void) error;
	LunaSvgContext *ctx = (LunaSvgContext *) data;
	if (ctx == NULL || ctx->buffer == NULL)
		return FALSE;
	if (size > 0)
		g_byte_array_append (ctx->buffer, buf, size);
	return TRUE;
}

static gboolean
svg_stop_load (gpointer data, GError **error)
{
	LunaSvgContext *ctx = (LunaSvgContext *) data;
	if (ctx == NULL)
		return FALSE;

	gboolean ok = FALSE;
	if (ctx->buffer != NULL && ctx->buffer->len > 0) {
		auto doc = lunasvg::Document::loadFromData (
			reinterpret_cast<const char *> (ctx->buffer->data),
			static_cast<std::size_t> (ctx->buffer->len)
		);
		if (doc != nullptr) {
			gint width = (gint) std::ceil (doc->width ());
			gint height = (gint) std::ceil (doc->height ());
			if (width <= 0)
				width = 48;
			if (height <= 0)
				height = 48;

			if (ctx->size_func != NULL)
				ctx->size_func (&width, &height, ctx->user_data);

			if (width <= 0)
				width = 48;
			if (height <= 0)
				height = 48;

			auto bitmap = doc->renderToBitmap (
				static_cast<std::uint32_t> (width),
				static_cast<std::uint32_t> (height)
			);
			if (bitmap.valid ()) {
				bitmap.convertToRGBA ();
				GdkPixbuf *pixbuf = gdk_pixbuf_new (GDK_COLORSPACE_RGB, TRUE, 8, width, height);
				if (pixbuf != NULL) {
					guchar *dst = gdk_pixbuf_get_pixels (pixbuf);
					int dst_stride = gdk_pixbuf_get_rowstride (pixbuf);
					const std::uint8_t *src = bitmap.data ();
					std::uint32_t src_stride = bitmap.stride ();
					int copy_bytes = width * 4;
					for (int y = 0; y < height; y++) {
						std::memcpy (dst + y * dst_stride, src + y * src_stride, copy_bytes);
					}
					if (ctx->prepared_func != NULL)
						ctx->prepared_func (pixbuf, NULL, ctx->user_data);
					if (ctx->updated_func != NULL)
						ctx->updated_func (pixbuf, 0, 0, width, height, ctx->user_data);
					g_object_unref (pixbuf);
					ok = TRUE;
				}
			}
		}
	}

	if (!ok && error != NULL && *error == NULL) {
		g_set_error (error, GDK_PIXBUF_ERROR, GDK_PIXBUF_ERROR_CORRUPT_IMAGE,
		             "Failed to rasterize SVG via static lunasvg loader");
	}

	if (ctx->buffer != NULL)
		g_byte_array_unref (ctx->buffer);
	g_free (ctx);
	return ok;
}

void
_gdk_pixbuf__svg_fill_vtable (GdkPixbufModule *module)
{
	module->begin_load = svg_begin_load;
	module->stop_load = svg_stop_load;
	module->load_increment = svg_load_increment;
}

void
_gdk_pixbuf__svg_fill_info (GdkPixbufFormat *info)
{
	static const GdkPixbufModulePattern signature[] = {
		{ " <svg", "*    ", 100 },
		{ " <!DOCTYPE svg", "*             ", 100 },
		{ " <?xml", "*     ", 80 },
		{ NULL, NULL, 0 }
	};
	static const gchar *mime_types[] = {
		"image/svg+xml",
		"image/svg",
		"image/svg-xml",
		NULL
	};
	static const gchar *extensions[] = {
		"svg",
		"svgz",
		"svg.gz",
		NULL
	};

	info->name = (gchar *) "svg";
	info->signature = (GdkPixbufModulePattern *) signature;
	info->description = (gchar *) "Scalable Vector Graphics (static lunasvg)";
	info->mime_types = (gchar **) mime_types;
	info->extensions = (gchar **) extensions;
	info->flags = GDK_PIXBUF_FORMAT_SCALABLE | GDK_PIXBUF_FORMAT_THREADSAFE;
	info->license = (gchar *) "GPLv3";
}

} /* extern "C" */
