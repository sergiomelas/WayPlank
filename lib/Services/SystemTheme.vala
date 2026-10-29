//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//  Copyright (C) 2026 史有虎 (IFtiger-hu)
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
	 * Service for tracking the desktop environment's Light/Dark mode via
	 * the XDG Desktop Portal (FreeDesktop standard for KDE Plasma, GNOME, etc.)
	 */
	public class SystemTheme : GLib.Object
	{
		static SystemTheme? default_instance = null;

		public bool is_dark { get; private set; default = false; }
		public signal void theme_changed (bool is_dark);

		uint subscription_id = 0;
		uint kde_subscription_id = 0;
		DBusConnection? bus = null;
		FileMonitor? kdeglobals_monitor = null;
		GLib.Settings? gnome_settings = null;

		public static SystemTheme get_default ()
		{
			if (default_instance == null) {
				default_instance = new SystemTheme ();
			}
			return default_instance;
		}

		construct
		{
			refresh_state ();
			init_dbus_listener ();
			init_kde_monitor ();

			// Direct GNOME interface color-scheme tracking
			var source = SettingsSchemaSource.get_default ();
			if (source != null && source.lookup ("org.gnome.desktop.interface", true) != null) {
				try {
					gnome_settings = new GLib.Settings ("org.gnome.desktop.interface");
					gnome_settings.changed["color-scheme"].connect (() => {
						refresh_state ();
					});
				} catch (Error e) { }
			}

			// Fallback: observe GTK theme name changes
			unowned Gtk.Settings? gtk_settings = Gtk.Settings.get_default ();
			if (gtk_settings != null) {
				gtk_settings.notify["gtk-theme-name"].connect (() => {
					refresh_state ();
				});
				gtk_settings.notify["gtk-application-prefer-dark-theme"].connect (() => {
					refresh_state ();
				});
			}
		}

		~SystemTheme ()
		{
			if (bus != null) {
				if (subscription_id > 0) {
					bus.signal_unsubscribe (subscription_id);
					subscription_id = 0;
				}
				if (kde_subscription_id > 0) {
					bus.signal_unsubscribe (kde_subscription_id);
					kde_subscription_id = 0;
				}
			}
			if (kdeglobals_monitor != null) {
				kdeglobals_monitor.cancel ();
				kdeglobals_monitor = null;
			}
		}

		public void refresh_state ()
		{
			bool detected_dark = false;
			bool detected = false;

			// 1. Try XDG Desktop Portal (standard across modern Wayland desktops: KDE Plasma 6+, GNOME 42+)
			try {
				var session_bus = Bus.get_sync (BusType.SESSION, null);
				var res = session_bus.call_sync (
					"org.freedesktop.portal.Desktop",
					"/org/freedesktop/portal/desktop",
					"org.freedesktop.portal.Settings",
					"Read",
					new Variant ("(ss)", "org.freedesktop.appearance", "color-scheme"),
					null,
					DBusCallFlags.NONE,
					500,
					null
				);

				Variant outer_v;
				res.get ("(v)", out outer_v);
				Variant val = outer_v;
				while (val.is_of_type (VariantType.VARIANT))
					val = val.get_variant ();

				if (val.is_of_type (VariantType.UINT32)) {
					uint32 code = val.get_uint32 ();
					if (code == 1) { // 1: Prefer dark
						detected_dark = true;
						detected = true;
					} else if (code == 2) { // 2: Prefer light
						detected_dark = false;
						detected = true;
					}
				}
			} catch (Error e) {
				debug ("SystemTheme: portal read error: %s", e.message);
			}

			// 2. Check KDE Plasma kdeglobals
			if (!detected) {
				var kdeglobals_path = Path.build_filename (Environment.get_user_config_dir (), "kdeglobals");
				if (FileUtils.test (kdeglobals_path, FileTest.EXISTS)) {
					try {
						string contents;
						FileUtils.get_contents (kdeglobals_path, out contents);
						bool in_colors_window = false;
						foreach (var line in contents.split ("\n")) {
							var trimmed = line.strip ();
							if (trimmed.has_prefix ("[") && trimmed.has_suffix ("]")) {
								in_colors_window = (trimmed == "[Colors:Window]");
								continue;
							}
							if (in_colors_window && trimmed.has_prefix ("BackgroundNormal=")) {
								var parts = trimmed.substring (17).split (",");
								if (parts.length >= 3) {
									int r = int.parse (parts[0].strip ());
									int g = int.parse (parts[1].strip ());
									int b = int.parse (parts[2].strip ());
									int lum = (r * 299 + g * 587 + b * 114) / 1000;
									detected_dark = (lum < 128);
									detected = true;
									break;
								}
							} else if (trimmed.has_prefix ("LookAndFeelPackage=")) {
								var pkg = trimmed.substring (19).down ();
								if (pkg.contains ("dark") || pkg.contains ("black")) {
									detected_dark = true;
									detected = true;
								}
							}
						}
					} catch (Error e) { }
				}
			}

			// 3. Fallback to GNOME Settings schema if portal was inconclusive (code == 0)
			if (!detected) {
				var source = SettingsSchemaSource.get_default ();
				if (source != null && source.lookup ("org.gnome.desktop.interface", true) != null) {
					var gs = new GLib.Settings ("org.gnome.desktop.interface");
					var scheme = gs.get_string ("color-scheme");
					if (scheme != null) {
						if (scheme == "prefer-dark") {
							detected_dark = true;
							detected = true;
						} else if (scheme == "prefer-light") {
							detected_dark = false;
							detected = true;
						}
					}
				}
			}

			// 4. Fallback to GTK theme name heuristics
			if (!detected) {
				var theme_name = Gtk.Settings.get_default ().gtk_theme_name ?? "";
				if (theme_name.down ().contains ("dark") || theme_name.down ().contains ("black")) {
					detected_dark = true;
				} else {
					detected_dark = false;
				}
			}

			if (is_dark != detected_dark) {
				is_dark = detected_dark;
				theme_changed (is_dark);
			}
		}

		void init_dbus_listener ()
		{
			try {
				bus = Bus.get_sync (BusType.SESSION, null);
				subscription_id = bus.signal_subscribe (
					null,
					"org.freedesktop.portal.Settings",
					"SettingChanged",
					"/org/freedesktop/portal/desktop",
					null,
					DBusSignalFlags.NONE,
					(DBusSignalCallback) handle_portal_setting_changed
				);

				kde_subscription_id = bus.signal_subscribe (
					null,
					"org.kde.kconfig.notify",
					"ConfigChanged",
					null,
					null,
					DBusSignalFlags.NONE,
					() => { refresh_state (); }
				);
			} catch (Error e) {
				warning ("SystemTheme: failed to subscribe to portal settings: %s", e.message);
			}
		}

		void init_kde_monitor ()
		{
			var kdeglobals_path = Path.build_filename (Environment.get_user_config_dir (), "kdeglobals");
			var kdeglobals_file = File.new_for_path (kdeglobals_path);
			if (kdeglobals_file.query_exists ()) {
				try {
					kdeglobals_monitor = kdeglobals_file.monitor_file (FileMonitorFlags.NONE, null);
					kdeglobals_monitor.changed.connect ((f, other_f, ev) => {
						refresh_state ();
					});
				} catch (Error e) { }
			}
		}

		[CCode (instance_pos = -1)]
		void handle_portal_setting_changed (DBusConnection connection, string sender_name, string object_path,
			string interface_name, string signal_name, Variant parameters)
		{
			string ns, key;
			Variant val_outer;
			parameters.get ("(ssv)", out ns, out key, out val_outer);
			if (key == "color-scheme") {
				Variant val = val_outer;
				while (val.is_of_type (VariantType.VARIANT))
					val = val.get_variant ();

				if (val.is_of_type (VariantType.UINT32)) {
					uint32 code = val.get_uint32 ();
					if (code == 1) { // 1: Prefer dark
						if (!is_dark) {
							is_dark = true;
							theme_changed (is_dark);
						}
						return;
					} else if (code == 2) { // 2: Prefer light
						if (is_dark) {
							is_dark = false;
							theme_changed (is_dark);
						}
						return;
					}
				} else if (val.is_of_type (VariantType.STRING)) {
					string str = val.get_string ();
					if (str == "prefer-dark") {
						if (!is_dark) {
							is_dark = true;
							theme_changed (is_dark);
						}
						return;
					} else if (str == "prefer-light" || str == "default") {
						if (is_dark) {
							is_dark = false;
							theme_changed (is_dark);
						}
						return;
					}
				}
				refresh_state ();
			}
		}
	}
}

