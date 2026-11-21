//
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
	 * Southbound XDG Desktop Portal, KDE `kdeglobals` / `kconfig`, and GNOME `interface`
	 * dark/light color-scheme driver (`IDesktopThemeBus`).
	 */
	public class DesktopThemeDbusService : GLib.Object, IDesktopThemeBus
	{
		static DesktopThemeDbusService? default_instance = null;

		public static DesktopThemeDbusService get_default ()
		{
			if (default_instance == null)
				default_instance = new DesktopThemeDbusService ();
			return default_instance;
		}

		uint subscription_id = 0U;
		uint kde_subscription_id = 0U;
		DBusConnection? bus = null;
		FileMonitor? kdeglobals_monitor = null;
		GLib.Settings? gnome_settings = null;
		ulong color_scheme_handler_id = 0UL;
		ulong gtk_theme_handler_id = 0UL;
		bool shutting_down = false;

		construct
		{
			init_dbus_listener ();
			init_kde_monitor ();

			var source = SettingsSchemaSource.get_default ();
			var iface_schema = source != null ? source.lookup ("org.gnome.desktop.interface", true) : null;
			if (iface_schema != null) {
				try {
					gnome_settings = new GLib.Settings ("org.gnome.desktop.interface");
					if (iface_schema.has_key ("color-scheme")) {
						color_scheme_handler_id = gnome_settings.changed["color-scheme"].connect (() => {
							if (!shutting_down)
								color_scheme_changed ();
						});
					}
					if (iface_schema.has_key ("gtk-theme")) {
						gtk_theme_handler_id = gnome_settings.changed["gtk-theme"].connect (() => {
							if (!shutting_down)
								gtk_theme_changed ();
						});
					}
				} catch (Error e) { }
			}
		}

		~DesktopThemeDbusService ()
		{
			cleanup ();
		}

		public void cleanup ()
		{
			shutting_down = true;
			if (gnome_settings != null) {
				if (color_scheme_handler_id > 0UL) {
					SignalHandler.disconnect (gnome_settings, color_scheme_handler_id);
					color_scheme_handler_id = 0UL;
				}
				if (gtk_theme_handler_id > 0UL) {
					SignalHandler.disconnect (gnome_settings, gtk_theme_handler_id);
					gtk_theme_handler_id = 0UL;
				}
				gnome_settings = null;
			}
			if (bus != null) {
				if (subscription_id > 0U) {
					bus.signal_unsubscribe (subscription_id);
					subscription_id = 0U;
				}
				if (kde_subscription_id > 0U) {
					bus.signal_unsubscribe (kde_subscription_id);
					kde_subscription_id = 0U;
				}
			}
			if (kdeglobals_monitor != null) {
				kdeglobals_monitor.cancel ();
				kdeglobals_monitor = null;
			}
		}

		public double get_font_scale_factor ()
		{
			if (gnome_settings != null && gnome_settings.settings_schema.has_key ("text-scaling-factor"))
				return gnome_settings.get_double ("text-scaling-factor");
			return 1.0;
		}

		public bool query_prefer_dark (out bool prefer_dark)
		{
			prefer_dark = false;
			if (shutting_down)
				return false;

			bool detected_dark = false;
			bool detected = false;

			// 1. Try XDG Desktop Portal (standard across modern Wayland desktops: KDE Plasma 6+, GNOME 42+)
			try {
				var session_bus = bus ?? DbusBroker.get_default ().get_session_bus ();
				if (session_bus != null) {
					var owner_res = session_bus.call_sync (
						"org.freedesktop.DBus",
						"/org/freedesktop/DBus",
						"org.freedesktop.DBus",
						"NameHasOwner",
						new Variant ("(s)", "org.freedesktop.portal.Desktop"),
						new VariantType ("(b)"),
						DBusCallFlags.NONE,
						100,
						null
					);
					bool portal_ready = false;
					owner_res.get ("(b)", out portal_ready);
					if (portal_ready) {
						var res = session_bus.call_sync (
							"org.freedesktop.portal.Desktop",
							"/org/freedesktop/portal/desktop",
							"org.freedesktop.portal.Settings",
							"Read",
							new Variant ("(ss)", "org.freedesktop.appearance", "color-scheme"),
							null,
							DBusCallFlags.NO_AUTO_START,
							150,
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
					}
				}
			} catch (Error e) {
				debug ("DesktopThemeDbusService: portal read error: %s", e.message);
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
				var iface_schema = source != null ? source.lookup ("org.gnome.desktop.interface", true) : null;
				if (iface_schema != null && iface_schema.has_key ("color-scheme")) {
					var gs = gnome_settings ?? new GLib.Settings ("org.gnome.desktop.interface");
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

			prefer_dark = detected_dark;
			return detected;
		}

		void init_dbus_listener ()
		{
			bus = DbusBroker.get_default ().get_session_bus ();
			if (bus == null)
				return;

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
				() => {
					if (!shutting_down)
						color_scheme_changed ();
				}
			);
		}

		void init_kde_monitor ()
		{
			var kdeglobals_path = Path.build_filename (Environment.get_user_config_dir (), "kdeglobals");
			var kdeglobals_file = File.new_for_path (kdeglobals_path);
			if (kdeglobals_file.query_exists ()) {
				try {
					kdeglobals_monitor = kdeglobals_file.monitor_file (FileMonitorFlags.NONE, null);
					kdeglobals_monitor.changed.connect ((f, other_f, ev) => {
						if (!shutting_down)
							color_scheme_changed ();
					});
				} catch (Error e) { }
			}
		}

		[CCode (instance_pos = -1)]
		void handle_portal_setting_changed (DBusConnection connection, string sender_name, string object_path,
			string interface_name, string signal_name, Variant parameters)
		{
			if (shutting_down)
				return;
			string ns, key;
			Variant val_outer;
			parameters.get ("(ssv)", out ns, out key, out val_outer);
			if (key == "color-scheme")
				color_scheme_changed ();
		}
	}
}
