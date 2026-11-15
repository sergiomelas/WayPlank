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
	[DBus (name = "org.freedesktop.Notifications")]
	private class FallbackNotificationAbsorber : GLib.Object
	{
		private uint32 next_id = 1;
		public bool inhibited { get; set; default = true; }

		public string[] get_capabilities () throws DBusError, IOError
		{
			return { "body", "inhibitions" };
		}

		[DBus (name = "Notify")]
		public uint32 handle_notify (
			string app_name,
			uint32 replaces_id,
			string app_icon,
			string summary,
			string body,
			string[] actions,
			HashTable<string, Variant> hints,
			int32 expire_timeout
		) throws DBusError, IOError
		{
			if (replaces_id > 0)
				return replaces_id;
			return next_id++;
		}

		public void close_notification (uint32 id) throws DBusError, IOError
		{
		}

		public void get_server_information (
			out string name,
			out string vendor,
			out string version,
			out string spec_version
		) throws DBusError, IOError
		{
			name = "WayPlank DND Absorber";
			vendor = "WayPlank";
			version = Build.VERSION;
			spec_version = "1.2";
		}
	}

	/**
	 * Southbound Freedesktop notification, Do-Not-Disturb, and launcher badge-visibility driver.
	 */
	public class NotificationDbusService : GLib.Object, INotificationBus
	{
		static NotificationDbusService? default_instance = null;

		public static NotificationDbusService get_default ()
		{
			if (default_instance == null)
				default_instance = new NotificationDbusService ();
			return default_instance;
		}

		bool show_badges = true;
		public bool show_launcher_badges {
			get { return show_badges; }
		}

		GLib.Settings? badge_settings = null;
		string badge_settings_key = "";
		bool badge_invert_boolean = false;
		ulong badge_settings_handler_id = 0UL;
		DBusConnection? session_bus = null;
		uint dbus_signal_id = 0U;
		uint inhibit_cookie = 0U;
		uint absorber_reg_id = 0U;
		uint absorber_owner_id = 0U;
		bool standalone_absorber_active = false;
		FallbackNotificationAbsorber? absorber_obj = null;
		GLib.Settings? gnome_notif_settings = null;
		ulong gnome_notif_handler_id = 0UL;
		bool is_disposed = false;

		construct
		{
			var schema_src = SettingsSchemaSource.get_default ();
			if (schema_src != null) {
				if (environment_is_session_desktop (XdgSessionDesktop.GNOME)) {
					var schema = schema_src.lookup ("org.gnome.desktop.notifications", true);
					if (schema != null && schema.has_key ("show-banners")) {
						badge_settings = new GLib.Settings ("org.gnome.desktop.notifications");
						badge_settings_key = "show-banners";
						badge_invert_boolean = false;
					}
				} else if (environment_is_session_desktop (XdgSessionDesktop.PANTHEON)) {
					var schema = schema_src.lookup ("org.pantheon.desktop.gala.notifications", true);
					if (schema != null && schema.has_key ("do-not-disturb")) {
						badge_settings = new GLib.Settings ("org.pantheon.desktop.gala.notifications");
						badge_settings_key = "do-not-disturb";
						badge_invert_boolean = true;
					}
				}
			}

			if (badge_settings != null && badge_settings_key != "") {
				show_badges = read_badge_setting ();
				badge_settings_handler_id = badge_settings.changed[badge_settings_key].connect (on_badge_notifications_changed);
			}

			session_bus = DbusBroker.get_default ().get_session_bus ();
			if (session_bus != null) {
				dbus_signal_id = session_bus.signal_subscribe (
					"org.freedesktop.Notifications",
					"org.freedesktop.DBus.Properties",
					"PropertiesChanged",
					"/org/freedesktop/Notifications",
					null,
					DBusSignalFlags.NONE,
					on_properties_changed
				);
			}

			if (environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU) && schema_src != null) {
				var notif_schema = schema_src.lookup ("org.gnome.desktop.notifications", true);
				if (notif_schema != null && notif_schema.has_key ("show-banners")) {
					gnome_notif_settings = new GLib.Settings ("org.gnome.desktop.notifications");
					gnome_notif_handler_id = gnome_notif_settings.changed["show-banners"].connect (() => {
						if (!is_disposed && gnome_notif_settings != null)
							dnd_state_changed (!gnome_notif_settings.get_boolean ("show-banners"));
					});
				}
			}
		}

		~NotificationDbusService ()
		{
			cleanup ();
		}

		bool read_badge_setting ()
		{
			if (badge_settings == null || badge_settings_key == "")
				return true;
			bool val = badge_settings.get_boolean (badge_settings_key);
			return badge_invert_boolean ? !val : val;
		}

		void on_badge_notifications_changed ()
		{
			if (is_disposed || badge_settings == null)
				return;
			bool next_val = read_badge_setting ();
			if (show_badges != next_val) {
				show_badges = next_val;
				show_launcher_badges_changed ();
			}
		}

		public bool has_instant_dnd_settings ()
		{
			return (gnome_notif_settings != null);
		}

		public bool has_push_dnd_subscription ()
		{
			return (gnome_notif_settings != null)
				|| (dbus_signal_id > 0U && environment_is_session_desktop (XdgSessionDesktop.KDE));
		}

		public bool get_instant_dnd_inhibited ()
		{
			if (gnome_notif_settings != null && gnome_notif_settings.settings_schema.has_key ("show-banners"))
				return !gnome_notif_settings.get_boolean ("show-banners");
			return false;
		}

		private bool start_standalone_absorber ()
		{
			if (standalone_absorber_active)
				return true;
			if (is_disposed || session_bus == null)
				return false;
			if (bus_has_owner (session_bus, "org.freedesktop.Notifications"))
				return false;

			try {
				absorber_obj = new FallbackNotificationAbsorber ();
				absorber_reg_id = session_bus.register_object ("/org/freedesktop/Notifications", absorber_obj);
			} catch (Error e) {
				absorber_obj = null;
				absorber_reg_id = 0U;
				return false;
			}

			absorber_owner_id = register_absorber_owner (session_bus, this);
			standalone_absorber_active = true;
			return true;
		}

		private static uint register_absorber_owner (DBusConnection bus, NotificationDbusService target)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);
			return Bus.own_name_on_connection (
				bus,
				"org.freedesktop.Notifications",
				BusNameOwnerFlags.ALLOW_REPLACEMENT,
				(conn, name) => { },
				(conn, name) => {
					var self = (NotificationDbusService?) self_ref.get ();
					if (self != null && self.standalone_absorber_active) {
						self.stop_standalone_absorber ();
						if (!self.is_disposed)
							self.dnd_state_changed (false);
					}
				}
			);
		}

		private void stop_standalone_absorber ()
		{
			standalone_absorber_active = false;
			if (absorber_owner_id > 0U) {
				Bus.unown_name (absorber_owner_id);
				absorber_owner_id = 0U;
			}
			if (absorber_reg_id > 0U && session_bus != null) {
				session_bus.unregister_object (absorber_reg_id);
				absorber_reg_id = 0U;
			}
			absorber_obj = null;
		}

		private static bool bus_has_owner (DBusConnection? bus, string name)
		{
			if (bus == null)
				return false;
			try {
				var res = bus.call_sync (
					"org.freedesktop.DBus",
					"/org/freedesktop/DBus",
					"org.freedesktop.DBus",
					"NameHasOwner",
					new Variant ("(s)", name),
					new VariantType ("(b)"),
					DBusCallFlags.NONE,
					150,
					null
				);
				return res.get_child_value (0).get_boolean ();
			} catch (Error e) {
				return false;
			}
		}

		private static string get_notification_server_name (DBusConnection? bus)
		{
			if (bus == null)
				return "";
			try {
				var res = bus.call_sync (
					"org.freedesktop.Notifications",
					"/org/freedesktop/Notifications",
					"org.freedesktop.Notifications",
					"GetServerInformation",
					null,
					new VariantType ("(ssss)"),
					DBusCallFlags.NO_AUTO_START,
					150,
					null
				);
				return res.get_child_value (0).get_string ().ascii_down ();
			} catch (Error e) {
				return "";
			}
		}

		public bool probe_dnd_inhibited_sync ()
		{
			DBusConnection? bus = session_bus;
			uint cookie_snapshot = inhibit_cookie;
			bool standalone_snapshot = standalone_absorber_active;

			if (standalone_snapshot)
				return true;

			if (environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)
				&& Environment.find_program_in_path ("gsettings") != null) {
				try {
					string stdout_out;
					int exit_status = 0;
					Process.spawn_command_line_sync ("gsettings get org.gnome.desktop.notifications show-banners", out stdout_out, null, out exit_status);
					if (exit_status == 0)
						return (stdout_out.strip () == "false");
				} catch (Error e) { }
				return (cookie_snapshot > 0U);
			}

			bool has_inhibited_prop = false;
			if (bus != null) {
				try {
					var res = bus.call_sync (
						"org.freedesktop.Notifications",
						"/org/freedesktop/Notifications",
						"org.freedesktop.DBus.Properties",
						"Get",
						new Variant ("(ss)", "org.freedesktop.Notifications", "Inhibited"),
						new VariantType ("(v)"),
						DBusCallFlags.NO_AUTO_START,
						150,
						null
					);
					var inner = res.get_child_value (0).get_variant ();
					if (inner.get_boolean ())
						return true;
					has_inhibited_prop = true;
					if (environment_is_session_desktop (XdgSessionDesktop.KDE))
						return false;
				} catch (Error e) { }
			}

			if (environment_is_session_desktop (XdgSessionDesktop.KDE))
				return (cookie_snapshot > 0U);

			if (bus_has_owner (bus, "org.erikreider.swaync.cc")
				&& Environment.find_program_in_path ("swaync-client") != null) {
				try {
					string stdout_out;
					int exit_status = 0;
					Process.spawn_command_line_sync ("swaync-client -D -sw", out stdout_out, null, out exit_status);
					if (exit_status == 0)
						return (stdout_out.strip () == "true");
				} catch (Error e) { }
			}

			if (bus_has_owner (bus, "org.freedesktop.Notifications")) {
				string srv = get_notification_server_name (bus);
				if ((srv.contains ("mako") || srv == "") && Environment.find_program_in_path ("makoctl") != null) {
					try {
						string stdout_out;
						int exit_status = 0;
						Process.spawn_command_line_sync ("makoctl mode", out stdout_out, null, out exit_status);
						if (exit_status == 0) {
							foreach (unowned string line in stdout_out.split ("\n")) {
								if (line.strip () == "do-not-disturb")
									return true;
							}
							return false;
						}
					} catch (Error e) { }
				}

				if ((srv.contains ("dunst") || srv == "") && Environment.find_program_in_path ("dunstctl") != null) {
					try {
						string stdout_out;
						int exit_status = 0;
						Process.spawn_command_line_sync ("dunstctl is-paused", out stdout_out, null, out exit_status);
						if (exit_status == 0)
							return (stdout_out.strip () == "true");
					} catch (Error e) { }
				}

				if (srv.contains ("xfce") && Environment.find_program_in_path ("xfconf-query") != null) {
					try {
						string stdout_out;
						int exit_status = 0;
						Process.spawn_command_line_sync ("xfconf-query -c xfce4-notifyd -p /do-not-disturb", out stdout_out, null, out exit_status);
						if (exit_status == 0)
							return (stdout_out.strip () == "true");
					} catch (Error e) { }
				}
			}

			return has_inhibited_prop ? false : (cookie_snapshot > 0U);
		}

		private void on_properties_changed (DBusConnection conn, string? sender, string path, string iface, string sig, Variant parameters)
		{
			if (parameters.n_children () < 2)
				return;

			string interface_name = parameters.get_child_value (0).get_string ();
			if (interface_name != "org.freedesktop.Notifications")
				return;

			var dict = parameters.get_child_value (1);
			for (size_t i = 0; i < dict.n_children (); i++) {
				var entry = dict.get_child_value (i);
				string key = entry.get_child_value (0).get_string ();
				if (key == "Inhibited") {
					var val = entry.get_child_value (1).get_variant ();
					dnd_state_changed (val.get_boolean ());
					break;
				}
			}
		}

		public void inhibit_dnd ()
		{
			if (environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)
				&& Environment.find_program_in_path ("gsettings") != null) {
				try {
					Process.spawn_command_line_async ("gsettings set org.gnome.desktop.notifications show-banners false");
					dnd_state_changed (true);
					return;
				} catch (Error e) { }
			}

			if (session_bus != null && !standalone_absorber_active) {
				try {
					var builder = new VariantBuilder (new VariantType ("a{sv}"));
					var res = session_bus.call_sync (
						"org.freedesktop.Notifications",
						"/org/freedesktop/Notifications",
						"org.freedesktop.Notifications",
						"Inhibit",
						new Variant ("(ssa{sv})", "WayPlank", "Do Not Disturb", builder),
						new VariantType ("(u)"),
						DBusCallFlags.NO_AUTO_START,
						1500,
						null
					);
					inhibit_cookie = res.get_child_value (0).get_uint32 ();
					dnd_state_changed (true);
					return;
				} catch (Error e) {
					debug ("DoNotDisturb: DBus Inhibit unavailable: %s", e.message);
				}
			}

			if (environment_is_session_desktop (XdgSessionDesktop.KDE))
				return;

			if (bus_has_owner (session_bus, "org.erikreider.swaync.cc")
				&& Environment.find_program_in_path ("swaync-client") != null) {
				try {
					int exit_status = 0;
					Process.spawn_command_line_sync ("swaync-client -dn -sw", null, null, out exit_status);
					if (exit_status == 0) {
						dnd_state_changed (true);
						return;
					}
				} catch (Error e) { }
			}

			if (bus_has_owner (session_bus, "org.freedesktop.Notifications")) {
				string srv = get_notification_server_name (session_bus);
				if ((srv.contains ("mako") || srv == "") && Environment.find_program_in_path ("makoctl") != null) {
					try {
						int exit_status = 0;
						Process.spawn_command_line_sync ("makoctl mode -a do-not-disturb", null, null, out exit_status);
						if (exit_status == 0) {
							dnd_state_changed (true);
							return;
						}
					} catch (Error e) { }
				}

				if ((srv.contains ("dunst") || srv == "") && Environment.find_program_in_path ("dunstctl") != null) {
					try {
						int exit_status = 0;
						Process.spawn_command_line_sync ("dunstctl set-paused true", null, null, out exit_status);
						if (exit_status == 0) {
							dnd_state_changed (true);
							return;
						}
					} catch (Error e) { }
				}

				if (srv.contains ("xfce") && Environment.find_program_in_path ("xfconf-query") != null) {
					try {
						int exit_status = 0;
						Process.spawn_command_line_sync ("xfconf-query -c xfce4-notifyd -p /do-not-disturb -n -t bool -s true", null, null, out exit_status);
						if (exit_status == 0) {
							dnd_state_changed (true);
							return;
						}
					} catch (Error e) { }
				}
			}

			if (start_standalone_absorber ()) {
				dnd_state_changed (true);
				return;
			}
		}

		public void uninhibit_dnd ()
		{
			if (standalone_absorber_active) {
				stop_standalone_absorber ();
				inhibit_cookie = 0U;
				dnd_state_changed (false);
				return;
			}

			if (environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)
				&& Environment.find_program_in_path ("gsettings") != null) {
				try {
					Process.spawn_command_line_async ("gsettings set org.gnome.desktop.notifications show-banners true");
				} catch (Error e) { }
				inhibit_cookie = 0U;
				dnd_state_changed (false);
				return;
			}

			if (session_bus != null && inhibit_cookie > 0U) {
				try {
					session_bus.call_sync (
						"org.freedesktop.Notifications",
						"/org/freedesktop/Notifications",
						"org.freedesktop.Notifications",
						"UnInhibit",
						new Variant ("(u)", inhibit_cookie),
						null,
						DBusCallFlags.NO_AUTO_START,
						1500,
						null
					);
					inhibit_cookie = 0U;
					dnd_state_changed (false);
					return;
				} catch (Error e) {
					debug ("DoNotDisturb: DBus UnInhibit failed: %s", e.message);
				}
			}

			if (session_bus != null) {
				try {
					session_bus.call_sync (
						"org.freedesktop.Notifications",
						"/org/freedesktop/Notifications",
						"org.freedesktop.Notifications",
						"UnInhibit",
						new Variant ("(u)", 1),
						null,
						DBusCallFlags.NO_AUTO_START,
						1000,
						null
					);
				} catch (Error e) { }
			}

			if (environment_is_session_desktop (XdgSessionDesktop.KDE)) {
				inhibit_cookie = 0U;
				dnd_state_changed (false);
				return;
			}

			if (bus_has_owner (session_bus, "org.erikreider.swaync.cc")
				&& Environment.find_program_in_path ("swaync-client") != null) {
				try {
					Process.spawn_command_line_async ("swaync-client -df -sw");
				} catch (Error e) { }
				inhibit_cookie = 0U;
				dnd_state_changed (false);
				return;
			}

			if (bus_has_owner (session_bus, "org.freedesktop.Notifications")) {
				string srv = get_notification_server_name (session_bus);
				if ((srv.contains ("mako") || srv == "") && Environment.find_program_in_path ("makoctl") != null) {
					try {
						Process.spawn_command_line_async ("makoctl mode -r do-not-disturb");
					} catch (Error e) { }
					inhibit_cookie = 0U;
					dnd_state_changed (false);
					return;
				}

				if ((srv.contains ("dunst") || srv == "") && Environment.find_program_in_path ("dunstctl") != null) {
					try {
						Process.spawn_command_line_async ("dunstctl set-paused false");
					} catch (Error e) { }
				}

				if (srv.contains ("xfce") && Environment.find_program_in_path ("xfconf-query") != null) {
					try {
						Process.spawn_command_line_async ("xfconf-query -c xfce4-notifyd -p /do-not-disturb -n -t bool -s false");
					} catch (Error e) { }
				}
			}

			inhibit_cookie = 0U;
			dnd_state_changed (false);
		}

		public void send_toast (string summary, string body, string icon_name)
		{
			string safe_icon = icon_name ?? "";
			string safe_summary = summary ?? "";
			string safe_body = body ?? "";

			var bus = session_bus ?? DbusBroker.get_default ().get_session_bus ();
			if (bus != null && bus_has_owner (bus, "org.freedesktop.Notifications")) {
				var builder = new GLib.VariantBuilder (new GLib.VariantType ("(susssasa{sv}i)"));
				builder.add ("s", "WayPlank");
				builder.add ("u", 0U);
				builder.add ("s", safe_icon);
				builder.add ("s", safe_summary);
				builder.add ("s", safe_body);
				builder.open (new GLib.VariantType ("as"));
				builder.close ();
				builder.open (new GLib.VariantType ("a{sv}"));
				builder.close ();
				builder.add ("i", 3000);

				bus.call.begin (
					"org.freedesktop.Notifications",
					"/org/freedesktop/Notifications",
					"org.freedesktop.Notifications",
					"Notify",
					builder.end (),
					null,
					GLib.DBusCallFlags.NONE,
					-1,
					null
				);
				return;
			}

			try {
				Process.spawn_command_line_async ("notify-send -i %s %s %s".printf (
					Shell.quote (safe_icon),
					Shell.quote (safe_summary),
					Shell.quote (safe_body)
				));
			} catch (Error e2) { }
		}

		public void cleanup ()
		{
			is_disposed = true;
			if (badge_settings != null) {
				if (badge_settings_handler_id > 0UL) {
					SignalHandler.disconnect (badge_settings, badge_settings_handler_id);
					badge_settings_handler_id = 0UL;
				}
				badge_settings = null;
			}
			if (gnome_notif_settings != null) {
				if (gnome_notif_handler_id > 0UL) {
					SignalHandler.disconnect (gnome_notif_settings, gnome_notif_handler_id);
					gnome_notif_handler_id = 0UL;
				}
				gnome_notif_settings = null;
			}
			stop_standalone_absorber ();
			if (dbus_signal_id > 0U && session_bus != null) {
				session_bus.signal_unsubscribe (dbus_signal_id);
				dbus_signal_id = 0U;
			}
		}
	}
}
