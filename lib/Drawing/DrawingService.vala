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
	/**
	 * Utility service for loading icons and working with pixbufs.
	 */
	public class DrawingService : GLib.Object
	{
		const string DEFAULT_ICON = "application-default-icon";
		
		const string FILE_ATTRIBUTE_CUSTOM_ICON = "metadata::custom-icon";
		const string FILE_ATTRIBUTE_CUSTOM_ICON_NAME = "metadata::custom-icon-name";
		
		// Parameters for average-color calculation
		const double SATURATION_WEIGHT = 1.5;
		const double WEIGHT_THRESHOLD = 1.0;
		const uint8 ALPHA_THRESHOLD = 24;
		
		static Mutex icon_theme_mutex;
		static Gtk.IconTheme? icon_theme;
		static Gtk.IconTheme? headless_icon_theme;
		
		DrawingService ()
		{
		}
		
		public static unowned Gtk.IconTheme get_icon_theme ()
		{
			icon_theme_mutex.lock ();
			
			if (icon_theme == null) {
				var screen = Gdk.Screen.get_default ();
				if (screen != null)
					icon_theme = Gtk.IconTheme.get_for_screen (screen);
			}
			
			if (icon_theme != null) {
				unowned Gtk.IconTheme res = icon_theme;
				icon_theme_mutex.unlock ();
				return res;
			}
			
			if (headless_icon_theme == null)
				headless_icon_theme = new Gtk.IconTheme ();
			
			unowned Gtk.IconTheme fallback_res = headless_icon_theme;
			icon_theme_mutex.unlock ();
			
			return fallback_res;
		}

		/**
		 * Mutex-protected, null-safe lookup directly against the active Gtk.IconTheme
		 * (without built-in GResource fallbacks, for graded icon-set selection).
		 */
		public static bool theme_has_icon (string icon_name)
		{
			if (icon_name == null || icon_name == "")
				return false;

			unowned Gtk.IconTheme? theme = get_icon_theme ();
			if (theme == null)
				return false;

			icon_theme_mutex.lock ();
			bool exists = theme.has_icon (icon_name);
			icon_theme_mutex.unlock ();

			return exists;
		}
		
		/**
		 * Gets the icon name from a {@link GLib.File}.
		 *
		 * @param file the file to get the icon name for
		 * @return the icon name for the file, or null if none exists
		 */
		public static string? get_icon_from_file (File file)
		{
			var hal_tok = Hal.Apps.get_file_icon_token (file);
			if (hal_tok != null && hal_tok != "" && has_icon (hal_tok))
				return hal_tok;

			try {
				var info = file.query_info (FileAttribute.STANDARD_ICON + ","
					+ FILE_ATTRIBUTE_CUSTOM_ICON_NAME + "," + FILE_ATTRIBUTE_CUSTOM_ICON + ","
					+ FileAttribute.THUMBNAIL_PATH, 0);
				
				// look for a custom icon-name
				unowned string custom_icon_name = info.get_attribute_string (FILE_ATTRIBUTE_CUSTOM_ICON_NAME);
				if (custom_icon_name != null && custom_icon_name != "") {
					if (has_icon (custom_icon_name))
						return custom_icon_name;
				}
				
				// look for a custom icon
				unowned string custom_icon = info.get_attribute_string (FILE_ATTRIBUTE_CUSTOM_ICON);
				if (custom_icon != null && custom_icon != "") {
					string? path = null;
					if (custom_icon.ascii_down ().has_prefix ("file://") || Path.is_absolute (custom_icon))
						path = custom_icon;
					else
						path = file.get_child (custom_icon).get_path ();
					if (path != null && has_icon (path))
						return path;
				}
				
				// look for a thumbnail
				unowned string thumb_icon = info.get_attribute_byte_string (FileAttribute.THUMBNAIL_PATH);
				if (thumb_icon != null && thumb_icon != "")
					return thumb_icon;
				
				// otherwise try to get the icon from the fileinfo
				return get_icon_from_gicon (info.get_icon ());
			} catch {
				debug ("Could not get file info for '%s'", file.get_path () ?? "");
			}
			
			return null;
		}

		/**
		 * Checks whether at least one of the given icon names or file paths can be resolved.
		 *
		 * @param names a delimited (with ";;") list of icon names or file paths
		 * @return true if an icon can be resolved in the theme, as a file, or as a built-in resource
		 */
		public static bool has_icon (string names)
		{
			if (names == null || names == "")
				return false;

			var all_names = names.split (";;");
			unowned Gtk.IconTheme theme = get_icon_theme ();

			foreach (unowned string name in all_names) {
				if (name == null || name == "")
					continue;

				var icon_file = try_get_icon_file (name);
				if (icon_file != null) {
					var f_path = icon_file.get_path ();
					if (f_path != null) {
						int w, h;
						if (Gdk.Pixbuf.get_file_info (f_path, out w, out h) != null)
							return true;
					} else {
						return true;
					}
				}

				if (Hal.Apps.has_native_icon (name))
					return true;

				icon_theme_mutex.lock ();
				bool exists = theme.has_icon (name);
				if (!exists && name.contains (".")) {
					var parts = name.split (".");
					exists = theme.has_icon (parts [0]);
				}
				icon_theme_mutex.unlock ();

				if (exists)
					return true;

				if (get_docklet_fallback_resource (name) != null)
					return true;
			}

			return false;
		}
		
		/**
		 * Gets an icon from a {@link GLib.Icon}.
		 *
		 * @param icon the icon to get the name for
		 * @return the icon name, or null if none exists
		 */
		public static string? get_icon_from_gicon (Icon? icon)
		{
			while (icon is EmblemedIcon)
				icon = ((EmblemedIcon) icon).get_icon ();

			if (icon is ThemedIcon) {
				var icons = string.joinv (";;", ((ThemedIcon) icon).get_names ());
				// Remove possible null values which sneaked through joinv, possibly a GTK+ bug?
				return icons.replace ("(null);;", "");
			}
			
			if (icon is FileIcon) {
				var f = ((FileIcon) icon).get_file ();
				var path = f.get_path ();
				if (path != null && path != "")
					return path;
				var uri = f.get_uri ();
				if (uri != null && uri.down ().has_prefix ("resource://"))
					return uri;
			}
			
			return null;
		}
		
		/**
		 * Loads an icon based on names and the given width/height
		 *
		 * @param names a delimited (with ";;") list of icon names, first one found is used
		 * @param width the requested width of the icon
		 * @param height the requested height of the icon
		 * @return the pixbuf representing the requested icon
		 */
		public static Gdk.Pixbuf load_icon (string names, int width, int height)
		{
			Gdk.Pixbuf? pbuf = null;
			
			var all_names = names.split (";;");
			
			foreach (unowned string name in all_names) {
				if (name == null || name == "")
					continue;

				if (name.down ().has_prefix ("resource://")) {
					pbuf = load_pixbuf_from_resource (name.substring ("resource://".length), width, height);
					if (pbuf != null)
						break;
				}

				var file = try_get_icon_file (name);
				if (file != null) {
					pbuf = load_pixbuf_from_file (file, width, height);
					if (pbuf != null)
						break;
				}
				
				pbuf = load_pixbuf (name, int.max (width, height));
				if (pbuf != null)
					break;

				pbuf = Hal.Apps.load_native_icon (name, int.max (width, height));
				if (pbuf != null)
					break;
				
				if (name != DEFAULT_ICON)
					message ("Could not find icon '%s'", name);
			}
			
			// If not found in active system theme, check integrated GResource fallback icons
			if (pbuf == null) {
				foreach (unowned string name in all_names) {
					if (name == null || name == "")
						continue;
					var fallback = get_docklet_fallback_resource (name);
					if (fallback != null) {
						pbuf = load_pixbuf_from_resource (fallback, width, height);
						if (pbuf != null)
							break;
					}
				}
			}

			// Try theme default icon before embedded last-resort icon
			if (pbuf == null)
				pbuf = load_pixbuf (DEFAULT_ICON, int.max (width, height));
			
			// Load internal default icon as last resort
			if (pbuf == null)
				pbuf = load_pixbuf_from_resource (Plank.G_RESOURCE_PATH + "/img/application-default-icon.svg", width, height);
			
			if (pbuf != null) {
				if (width != -1 && height != -1 && (width != pbuf.width || height != pbuf.height))
					return ar_scale (pbuf, width, height);
				return pbuf;
			}
			
			warning ("No icon found, return empty pixbuf");
			
			return get_empty_pixbuf (int.max (1, width), int.max (1, height));
		}
		
		static Gdk.Pixbuf get_empty_pixbuf (int width, int height)
		{
			var pbuf = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, width, height);
			pbuf.fill (0x00000000);
			return pbuf;
		}
		
		/**
		 * Try to get a {@link GLib.File} for the given icon name
		 *
		 * @param name a string which might represent an existing file
		 * @return a {@link GLib.File}, or null if it failed
		 */
		public static File? try_get_icon_file (string name)
		{
			File? file = null;
			var name_down = name.down ();

			if (name_down.has_prefix ("resource://") || name_down.has_prefix ("file://")) {
				file = File.new_for_uri (name);
			} else {
				string expanded = Hal.Runtime.expand_path_variables (name);
				if (Path.is_absolute (expanded))
					file = File.new_for_path (expanded);
			}

			if (file != null && file.query_exists ())
				return file;

			return null;
		}
		
		static Gdk.Pixbuf? load_pixbuf_from_file (File file, int width, int height)
		{
			Gdk.Pixbuf? pbuf = null;
			
			try {
				var fis = file.read ();
				pbuf = new Gdk.Pixbuf.from_stream_at_scale (fis, width, height, true);
			} catch { }
			
			return pbuf;
		}
		
		static Gdk.Pixbuf? load_pixbuf_from_resource (string resource, int width, int height)
		{
			Gdk.Pixbuf? pbuf = null;
			
			try {
				pbuf = new Gdk.Pixbuf.from_resource_at_scale (resource, width, height, true);
			} catch { }
			
			return pbuf;
		}
		
		static Gdk.Pixbuf? load_pixbuf (string icon, int size)
		{
			Gdk.Pixbuf? pbuf = null;
			unowned Gtk.IconTheme icon_theme = get_icon_theme ();
			
			icon_theme_mutex.lock ();
			
			try {
				pbuf = icon_theme.load_icon (icon, size, 0);
			} catch { }
			
			try {
				if (pbuf == null && icon.contains (".")) {
					var parts = icon.split (".");
					pbuf = icon_theme.load_icon (parts [0], size, 0);
				}
			} catch { }
			
			icon_theme_mutex.unlock ();
			
			return pbuf;
		}
		
		/**
		 * Loads an icon based on names and the given width/height
		 *
		 * @param names a delimited (with ";;") list of icon names, first one found is used
		 * @param width the requested width of the icon
		 * @param height the requested height of the icon
		 * @param scale the implicit requested scale of the icon
		 * @return the {link Cairo.Surface} containing the requested icon, do not alter this surface
		 */
		public static Cairo.Surface? load_icon_for_scale (string names, int width, int height, int scale)
		{
			Cairo.Surface? surface = null;
			
			var all_names = names.split (";;");
			
			foreach (unowned string name in all_names) {
				if (name == null || name == "")
					continue;

				if (name.down ().has_prefix ("resource://")) {
					surface = load_surface_from_resource_at_scale (name.substring ("resource://".length), width, height, scale);
					if (surface != null)
						break;
				}

				var file = try_get_icon_file (name);
				if (file != null) {
					var pbuf = load_pixbuf_from_file (file, width, height);
					if (pbuf != null) {
						surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
						var cr = new Cairo.Context (surface);
						Gdk.cairo_set_source_pixbuf (cr, pbuf, (width - pbuf.width) / 2, (height - pbuf.height) / 2);
						cr.paint ();
						surface.set_device_scale (scale, scale);
						break;
					}
				}
				
				surface = load_surface (name, int.max (width, height) / scale, scale);
				if (surface != null)
					break;

				var native_pbuf = Hal.Apps.load_native_icon (name, int.max (width, height));
				if (native_pbuf != null) {
					var scaled = (width != -1 && height != -1 && (width != native_pbuf.width || height != native_pbuf.height))
						? ar_scale (native_pbuf, width, height) : native_pbuf;
					surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
					var cr = new Cairo.Context (surface);
					Gdk.cairo_set_source_pixbuf (cr, scaled, (width - scaled.width) / 2, (height - scaled.height) / 2);
					cr.paint ();
					surface.set_device_scale (scale, scale);
					break;
				}
				
				if (name != DEFAULT_ICON)
					message ("Could not find icon '%s'", name);
			}
			
			// If not found in active system theme, check integrated GResource fallback icons
			if (surface == null) {
				foreach (unowned string name in all_names) {
					if (name == null || name == "")
						continue;
					var fallback = get_docklet_fallback_resource (name);
					if (fallback != null) {
						surface = load_surface_from_resource_at_scale (fallback, width, height, scale);
						if (surface != null)
							break;
					}
				}
			}

			// Try theme default icon before embedded last-resort icon
			if (surface == null)
				surface = load_surface (DEFAULT_ICON, int.max (width, height) / scale, scale);
			
			// Load internal default icon as last resort
			if (surface == null)
				surface = load_surface_from_resource_at_scale (Plank.G_RESOURCE_PATH + "/img/application-default-icon.svg", width, height, scale);
			
			return surface;
		}

		static string? get_docklet_fallback_resource (string name)
		{
			switch (name) {
				case "user-trash":
				case "trashcan_empty":
				case "emptytrash":
				case "gnome-fs-trash-empty":
					return Plank.G_RESOURCE_PATH + "/docklets/trash.svg";
				case "user-trash-full":
				case "trashcan_full":
				case "trashcan_full-new":
				case "gnome-fs-trash-full":
					return Plank.G_RESOURCE_PATH + "/docklets/trash-full.svg";
				case "utilities-system-monitor":
					return Plank.G_RESOURCE_PATH + "/docklets/cpu.svg";
				case "preferences-system-time":
					return Plank.G_RESOURCE_PATH + "/docklets/clock.svg";
				case "org.kde.plasma.digitalclock":
				case "digital-clock":
					return Plank.G_RESOURCE_PATH + "/docklets/digital-clock.svg";
				case "user-desktop":
				case "desktop":
					return Plank.G_RESOURCE_PATH + "/docklets/desktop.svg";
				case "multimedia-player":
				case "audio-player":
				case "applications-multimedia":
					return Plank.G_RESOURCE_PATH + "/docklets/mpris.svg";
				case "battery-full":
				case "battery":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-full.svg";
				case "battery-good":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-good.svg";
				case "battery-low":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-low.svg";
				case "battery-caution":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-caution.svg";
				case "battery-empty":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-empty.svg";
				case "battery-full-charging":
				case "battery-full-charged":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-full-charging.svg";
				case "battery-good-charging":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-good-charging.svg";
				case "battery-low-charging":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-low-charging.svg";
				case "battery-caution-charging":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-caution-charging.svg";
				case "battery-empty-charging":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-empty-charging.svg";
				case "battery-missing":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-missing.svg";
				case "battery-ac-adapter":
					return Plank.G_RESOURCE_PATH + "/docklets/battery-ac-adapter.svg";
				case "audio-volume-overamplified":
				case "audio-volume-high-warning":
				case "audio-volume-high-danger":
				case "xfce4-mixer-volume-very-high":
					return Plank.G_RESOURCE_PATH + "/docklets/volume-overamplified.svg";
				case "audio-volume":
				case "audio-volume-high":
				case "stock_volume-max":
					return Plank.G_RESOURCE_PATH + "/docklets/volume-high.svg";
				case "audio-volume-medium":
				case "stock_volume-med":
					return Plank.G_RESOURCE_PATH + "/docklets/volume-medium.svg";
				case "audio-volume-low":
				case "stock_volume-min":
					return Plank.G_RESOURCE_PATH + "/docklets/volume-low.svg";
				case "audio-volume-muted":
				case "stock_volume-mute":
					return Plank.G_RESOURCE_PATH + "/docklets/volume-muted.svg";
				case "media-playback-start":
					return Plank.G_RESOURCE_PATH + "/docklets/mpris-play.svg";
				case "media-playback-pause":
					return Plank.G_RESOURCE_PATH + "/docklets/mpris-pause.svg";
				case "applets-screenshooter":
				case "accessories-screenshot-tool":
				case "spectacle":
				case "org.kde.spectacle":
					return Plank.G_RESOURCE_PATH + "/docklets/screenshot.svg";
				case "system-shutdown":
				case "system-shutdown-symbolic":
				case "xfsm-shutdown":
					return Plank.G_RESOURCE_PATH + "/docklets/session.svg";
				case "system-lock-screen":
				case "system-lock-screen-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/session-lock.svg";
				case "system-users":
				case "system-switch-user":
				case "system-users-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/session-users.svg";
				case "system-log-out":
				case "system-log-out-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/session-logout.svg";
				case "system-suspend":
				case "system-suspend-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/session-suspend.svg";
				case "system-suspend-hibernate":
				case "system-suspend-hibernate-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/session-hibernate.svg";
				case "system-reboot":
				case "system-reboot-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/session-reboot.svg";
				case "plank":
				case "wayplank":
				case "preferences-other":
					return Plank.G_RESOURCE_PATH + "/docklets/preferences.svg";
				case "preferences-system":
				case "preferences-system-symbolic":
				case "configure":
					return Plank.G_RESOURCE_PATH + "/docklets/settings-gear.svg";
				case "starred":
				case "starred-symbolic":
				case "non-starred-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/starred.svg";
				case "list-add":
				case "list-add-symbolic":
				case "add":
					return Plank.G_RESOURCE_PATH + "/docklets/list-add.svg";
				case "help-browser":
				case "help-browser-symbolic":
				case "help-contents":
				case "help-contents-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/help-browser.svg";
				case "application-exit":
				case "application-exit-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/application-exit.svg";
				case "media-eject":
				case "media-eject-symbolic":
				case "drive-removable-media":
					return Plank.G_RESOURCE_PATH + "/docklets/ejector.svg";
				case "notification-display-brightness-full":
				case "display-brightness-full":
				case "brightness-full":
				case "display-brightness":
				case "display-brightness-symbolic":
				case "brightness":
					return Plank.G_RESOURCE_PATH + "/docklets/brightness.svg";
				case "notification-display-brightness-high":
				case "display-brightness-high":
				case "brightness-high":
				case "high-brightness":
					return Plank.G_RESOURCE_PATH + "/docklets/brightness-high.svg";
				case "notification-display-brightness-medium":
				case "display-brightness-medium":
				case "brightness-medium":
					return Plank.G_RESOURCE_PATH + "/docklets/brightness-medium.svg";
				case "notification-display-brightness-low":
				case "display-brightness-low":
				case "brightness-low":
					return Plank.G_RESOURCE_PATH + "/docklets/brightness-low.svg";
				case "weather-clear":
				case "weather-clear-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/weather-clear.svg";
				case "weather-few-clouds":
				case "weather-few-clouds-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/weather-few-clouds.svg";
				case "weather-clouds":
				case "weather-overcast":
				case "weather-many-clouds":
				case "weather-overcast-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/weather-overcast.svg";
				case "weather-showers":
				case "weather-showers-scattered":
				case "weather-rain":
				case "weather-freezing-rain":
				case "weather-showers-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/weather-showers.svg";
				case "weather-snow":
				case "weather-snow-scattered":
				case "weather-snow-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/weather-snow.svg";
				case "weather-storm":
				case "weather-severe-alert":
				case "weather-storm-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/weather-storm.svg";
				case "weather-fog":
				case "weather-mist":
				case "weather-fog-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/weather-fog.svg";
				case "weather":
					return Plank.G_RESOURCE_PATH + "/docklets/weather.svg";
				case "network-wireless-signal-excellent":
				case "network-wireless-signal-excellent-symbolic":
				case "network-wireless-connected-100":
				case "network-wireless-signal-good":
				case "network-wireless-signal-good-symbolic":
				case "network-wireless-connected-75":
				case "network-wireless-signal-ok":
				case "network-wireless-signal-ok-symbolic":
				case "network-wireless-connected-50":
				case "network-wireless-signal-weak":
				case "network-wireless-signal-weak-symbolic":
				case "network-wireless-connected-25":
				case "network-wireless-signal-none":
				case "network-wireless-signal-none-symbolic":
				case "network-wireless-connected":
				case "network-wireless":
				case "network-wired-activated":
				case "network-wired":
				case "network-workgroup":
				case "network-idle":
					return Plank.G_RESOURCE_PATH + "/docklets/network.svg";
				case "network-offline":
				case "network-offline-symbolic":
				case "network-error":
				case "network-wired-disconnected":
				case "network-wireless-disconnected":
					return Plank.G_RESOURCE_PATH + "/docklets/network-offline.svg";
				case "preferences-desktop-notification-bell":
				case "notifications":
				case "preferences-system-notifications":
				case "notification-symbolic":
					return Plank.G_RESOURCE_PATH + "/docklets/dnd.svg";
				case "notifications-disabled":
				case "notifications-disabled-symbolic":
				case "notification-disabled":
					return Plank.G_RESOURCE_PATH + "/docklets/dnd-muted.svg";
				default:
					return null;
			}
		}
		
		static Cairo.Surface? load_surface_from_resource_at_scale (string resource, int width, int height, int scale)
		{
			Gdk.Pixbuf? pbuf = null;
			Cairo.Surface? surface = null;
			
			try {
				pbuf = new Gdk.Pixbuf.from_resource_at_scale (resource, width, height, true);
			} catch { }
			
			if (pbuf != null) {
				surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
				var cr = new Cairo.Context (surface);
				Gdk.cairo_set_source_pixbuf (cr, pbuf, (width - pbuf.width) / 2, (height - pbuf.height) / 2);
				cr.paint ();
				surface.set_device_scale (scale, scale);
			}
			
			return surface;
		}
		
		static Cairo.Surface? load_surface (string icon, int size, int scale)
		{
			Cairo.Surface? surface = null;
			Gtk.IconInfo? info = null;
			unowned Gtk.IconTheme icon_theme = get_icon_theme ();
			
			icon_theme_mutex.lock ();
			
			try {
				info = icon_theme.lookup_icon_for_scale (icon, size, scale, Gtk.IconLookupFlags.FORCE_SIZE);
				if (info != null)
					surface = info.load_surface (null);
			} catch { }
			
			try {
				if (surface == null && icon.contains (".")) {
					var parts = icon.split (".");
					info = icon_theme.lookup_icon_for_scale (parts [0], size, scale, Gtk.IconLookupFlags.FORCE_SIZE);
					if (info != null)
						surface = info.load_surface (null);
				}
			} catch { }
			
			icon_theme_mutex.unlock ();
			
			return surface;
		}
		
		/**
		 * Scales a {@link Gdk.Pixbuf}, maintaining the original aspect ratio.
		 *
		 * @param source the pixbuf to scale
		 * @param width the width of the scaled pixbuf
		 * @param height the height of the scaled pixbuf
		 * @return the scaled pixbuf
		 */
		public static Gdk.Pixbuf ar_scale (Gdk.Pixbuf source, int width, int height)
		{
			var source_width = (double) source.width;
			var source_height = (double) source.height;
			
			var x_scale = width / source_width;
			var y_scale = height / source_height;
			var scale = double.min (x_scale, y_scale);
			
			if (scale == 1)
				return source;
			
			var scaled_width = int.max (1, (int) (source_width * scale));
			var scaled_height = int.max (1, (int) (source_height * scale));
			
			return source.scale_simple (scaled_width, scaled_height, Gdk.InterpType.HYPER) ?? source;
		}
		
		/**
		 * Computes and returns the average color of a {@link Gdk.Pixbuf}.
		 * The resulting color is the average of all pixels which aren't
		 * nearly transparent while saturated pixels are weighted more than
		 * "grey" ones.
		 *
		 * @param source the pixbuf to use
		 * @return the average color of the pixbuf
		 */
		public static Color average_color (Gdk.Pixbuf source)
		{
			uint8 r, g, b, a, min, max;
			double delta;

			var rTotal = 0.0;
			var gTotal = 0.0;
			var bTotal = 0.0;
			
			var bTotal2 = 0.0;
			var gTotal2 = 0.0;
			var rTotal2 = 0.0;
			var aTotal2 = 0.0;
			
			uint8* pixels_base = source.get_pixels ();
			int n_channels = source.n_channels;
			bool has_alpha = source.has_alpha;
			int width = source.width;
			int height = source.height;
			int rowstride = source.rowstride;
			if (pixels_base == null || width <= 0 || height <= 0 || n_channels < 3)
				return { 0.0, 0.0, 0.0, 0.0 };
			int length = width * height;
			double scoreTotal = 0.0;
			
			for (int y = 0; y < height; y++) {
				uint8* row = pixels_base + (size_t) y * (size_t) rowstride;
				for (int x = 0; x < width; x++) {
					uint8* p = row + x * n_channels;
					r = p[0];
					g = p[1];
					b = p[2];
					a = (has_alpha && n_channels >= 4) ? p[3] : 255;
					
					// skip (nearly) invisible pixels
					if (a <= ALPHA_THRESHOLD) {
						length--;
						continue;
					}
					
					min = uint8.min (r, uint8.min (g, b));
					max = uint8.max (r, uint8.max (g, b));
					delta = max - min;
					
					// prefer colored pixels over shades of grey
					var score = SATURATION_WEIGHT * (delta == 0 ? 0.0 : delta / max);
					
					// weighted sums, revert pre-multiplied alpha value
					bTotal += score * b / a;
					gTotal += score * g / a;
					rTotal += score * r / a;
					scoreTotal += score;
					
					// not weighted sums
					bTotal2 += b;
					gTotal2 += g;
					rTotal2 += r;
					aTotal2 += a;
				}
			}
			
			// looks like a fully transparent image
			if (length <= 0)
				return { 0.0, 0.0, 0.0, 0.0 };
			
			scoreTotal /= length;
			bTotal /= length;
			gTotal /= length;
			rTotal /= length;
			
			if (scoreTotal > 0.0) {
				bTotal /= scoreTotal;
				gTotal /= scoreTotal;
				rTotal /= scoreTotal;
			}
			
			bTotal2 /= length * uint8.MAX;
			gTotal2 /= length * uint8.MAX;
			rTotal2 /= length * uint8.MAX;
			aTotal2 /= length * uint8.MAX;
			
			// combine weighted and not weighted sum depending on the average "saturation"
			// if saturation isn't reasonable enough
			// s = 0.0 -> f = 0.0 ; s = WEIGHT_THRESHOLD -> f = 1.0
			if (scoreTotal <= WEIGHT_THRESHOLD) {
				var f = 1.0 / WEIGHT_THRESHOLD * scoreTotal;
				var rf = 1.0 - f;
				bTotal = bTotal * f + bTotal2 * rf;
				gTotal = gTotal * f + gTotal2 * rf;
				rTotal = rTotal * f + rTotal2 * rf;
			}
			
			// there shouldn't be values larger then 1.0
			var max_val = double.max (rTotal, double.max (gTotal, bTotal));
			if (max_val > 1.0) {
				bTotal /= max_val;
				gTotal /= max_val;
				rTotal /= max_val;
			}
			
			return { rTotal, gTotal, bTotal, aTotal2 };
		}
	}
}
