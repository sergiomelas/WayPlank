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

	public class DoNotDisturbDockItem : DockItem
	{
		const string ICON_ACTIVE = "preferences-desktop-notification-bell;;notifications;;preferences-system-notifications;;notification-symbolic";
		const string ICON_MUTED = "notifications-disabled;;notifications-disabled-symbolic;;notification-disabled;;preferences-desktop-notification-bell";

		private bool is_dnd_active = false;
		private uint inhibit_cookie = 0;
		private DBusConnection? session_bus = null;
		private uint dbus_signal_id = 0;
		private uint poll_timer_id = 0;
		private bool is_disposed = false;
		private bool poll_in_flight = false;
		private int state_generation = 0;
		private uint absorber_reg_id = 0;
		private uint absorber_owner_id = 0;
		private bool standalone_absorber_active = false;
		private FallbackNotificationAbsorber? absorber_obj = null;

		public DoNotDisturbDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public DoNotDisturbDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Do Not Disturb");
			Icon = ICON_ACTIVE;
			Button = PopupButton.RIGHT;

			try {
				session_bus = Bus.get_sync (BusType.SESSION, null);
			} catch (Error e) {
				session_bus = null;
			}

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

			schedule_dnd_poll ();
			start_timer ();
		}

		~DoNotDisturbDockItem ()
		{
			is_disposed = true;
			stop_timer ();
			stop_standalone_absorber ();
			if (dbus_signal_id > 0 && session_bus != null) {
				session_bus.signal_unsubscribe (dbus_signal_id);
				dbus_signal_id = 0;
			}
		}

		public override void cleanup ()
		{
			is_disposed = true;
			stop_timer ();
			stop_standalone_absorber ();
			if (dbus_signal_id > 0 && session_bus != null) {
				session_bus.signal_unsubscribe (dbus_signal_id);
				dbus_signal_id = 0;
			}
			base.cleanup ();
		}

		public override void @delete ()
		{
			is_disposed = true;
			stop_timer ();
			stop_standalone_absorber ();
			if (dbus_signal_id > 0 && session_bus != null) {
				session_bus.signal_unsubscribe (dbus_signal_id);
				dbus_signal_id = 0;
			}
			base.@delete ();
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
				absorber_reg_id = 0;
				return false;
			}

			GLib.WeakRef self_ref = GLib.WeakRef (this);
			absorber_owner_id = Bus.own_name_on_connection (
				session_bus,
				"org.freedesktop.Notifications",
				BusNameOwnerFlags.ALLOW_REPLACEMENT,
				(conn, name) => { },
				(conn, name) => {
					var self = (DoNotDisturbDockItem?) self_ref.get ();
					if (self != null && self.standalone_absorber_active) {
						self.stop_standalone_absorber ();
						if (!self.is_disposed)
							self.schedule_dnd_poll ();
					}
				}
			);
			standalone_absorber_active = true;
			return true;
		}

		private void stop_standalone_absorber ()
		{
			standalone_absorber_active = false;
			if (absorber_owner_id > 0) {
				Bus.unown_name (absorber_owner_id);
				absorber_owner_id = 0;
			}
			if (absorber_reg_id > 0 && session_bus != null) {
				session_bus.unregister_object (absorber_reg_id);
				absorber_reg_id = 0;
			}
			absorber_obj = null;
		}

		private void start_timer ()
		{
			if (poll_timer_id == 0) {
				poll_timer_id = Timeout.add_seconds (5, () => {
					schedule_dnd_poll ();
					return true;
				});
			}
		}

		private void stop_timer ()
		{
			if (poll_timer_id > 0) {
				Source.remove (poll_timer_id);
				poll_timer_id = 0;
			}
		}

		public override bool is_valid ()
		{
			return true;
		}

		private void set_dnd_state (bool active)
		{
			if (is_dnd_active != active || Icon == "") {
				is_dnd_active = active;
				Icon = is_dnd_active ? ICON_MUTED : ICON_ACTIVE;
				Text = is_dnd_active ? _("Notifications: Silenced (Do Not Disturb)") : _("Notifications: Active");
			}
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

		private static bool probe_dnd_state (DBusConnection? bus, uint cookie_snapshot, bool standalone_snapshot)
		{
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
				return (cookie_snapshot > 0);
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
				return (cookie_snapshot > 0);

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
			}

			return has_inhibited_prop ? false : (cookie_snapshot > 0);
		}

		private static void spawn_dnd_poll_worker (DoNotDisturbDockItem target, DBusConnection? bus_ref, uint cookie_snap, bool standalone_snap, int gen_snap)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-dnd-poll", () => {
				bool active = probe_dnd_state (bus_ref, cookie_snap, standalone_snap);
				Idle.add (() => {
					var self = (DoNotDisturbDockItem?) self_ref.get ();
					if (self == null)
						return false;
					self.poll_in_flight = false;
					if (self.is_disposed || gen_snap != self.state_generation)
						return false;
					self.set_dnd_state (active);
					return false;
				});
				return null;
			});
		}

		private void schedule_dnd_poll ()
		{
			if (is_disposed || poll_in_flight || session_bus == null)
				return;
			poll_in_flight = true;
			DBusConnection? bus_ref = session_bus;
			uint cookie_snap = inhibit_cookie;
			bool standalone_snap = standalone_absorber_active;
			int gen_snap = state_generation;

			spawn_dnd_poll_worker (this, bus_ref, cookie_snap, standalone_snap, gen_snap);
		}

		private void on_properties_changed (DBusConnection conn, string? sender, string path, string iface, string signal, Variant parameters)
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
					set_dnd_state (val.get_boolean ());
					break;
				}
			}
		}

		public void toggle_dnd ()
		{
			if (is_dnd_active)
				uninhibit ();
			else
				inhibit ();
		}

		public void inhibit ()
		{
			state_generation++;

			if (environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)
				&& Environment.find_program_in_path ("gsettings") != null) {
				try {
					Process.spawn_command_line_async ("gsettings set org.gnome.desktop.notifications show-banners false");
					set_dnd_state (true);
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
					set_dnd_state (true);
					return;
				} catch (Error e) {
					debug ("DoNotDisturb: DBus Inhibit unavailable: %s", e.message);
				}
			}

			if (environment_is_session_desktop (XdgSessionDesktop.KDE))
				return;

			// Fallback: SwayNC (only when owned on session bus)
			if (bus_has_owner (session_bus, "org.erikreider.swaync.cc")
				&& Environment.find_program_in_path ("swaync-client") != null) {
				try {
					int exit_status = 0;
					Process.spawn_command_line_sync ("swaync-client -dn -sw", null, null, out exit_status);
					if (exit_status == 0) {
						set_dnd_state (true);
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
							set_dnd_state (true);
							return;
						}
					} catch (Error e) { }
				}

				if ((srv.contains ("dunst") || srv == "") && Environment.find_program_in_path ("dunstctl") != null) {
					try {
						int exit_status = 0;
						Process.spawn_command_line_sync ("dunstctl set-paused true", null, null, out exit_status);
						if (exit_status == 0) {
							set_dnd_state (true);
							return;
						}
					} catch (Error e) { }
				}
			}

			// Bare Wayland / wlroots / Labwc fallback when no notification daemon owns org.freedesktop.Notifications
			if (start_standalone_absorber ()) {
				set_dnd_state (true);
				return;
			}
		}

		public void uninhibit ()
		{
			state_generation++;

			if (standalone_absorber_active) {
				stop_standalone_absorber ();
				inhibit_cookie = 0;
				set_dnd_state (false);
				return;
			}

			if (environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)
				&& Environment.find_program_in_path ("gsettings") != null) {
				try {
					Process.spawn_command_line_async ("gsettings set org.gnome.desktop.notifications show-banners true");
				} catch (Error e) { }
				inhibit_cookie = 0;
				set_dnd_state (false);
				return;
			}

			if (session_bus != null && inhibit_cookie > 0) {
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
					inhibit_cookie = 0;
					set_dnd_state (false);
					return;
				} catch (Error e) {
					debug ("DoNotDisturb: DBus UnInhibit failed: %s", e.message);
				}
			}

			// If inhibit_cookie was 0 (e.g. inhibited by another app or Plasma tray), try UnInhibit(1)
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
				inhibit_cookie = 0;
				set_dnd_state (false);
				return;
			}

			// Fallback: SwayNC (only when owned on session bus)
			if (bus_has_owner (session_bus, "org.erikreider.swaync.cc")
				&& Environment.find_program_in_path ("swaync-client") != null) {
				try {
					Process.spawn_command_line_async ("swaync-client -df -sw");
				} catch (Error e) { }
				inhibit_cookie = 0;
				set_dnd_state (false);
				return;
			}

			if (bus_has_owner (session_bus, "org.freedesktop.Notifications")) {
				string srv = get_notification_server_name (session_bus);
				if ((srv.contains ("mako") || srv == "") && Environment.find_program_in_path ("makoctl") != null) {
					try {
						Process.spawn_command_line_async ("makoctl mode -r do-not-disturb");
					} catch (Error e) { }
					inhibit_cookie = 0;
					set_dnd_state (false);
					return;
				}

				if ((srv.contains ("dunst") || srv == "") && Environment.find_program_in_path ("dunstctl") != null) {
					try {
						Process.spawn_command_line_async ("dunstctl set-paused false");
					} catch (Error e) { }
				}
			}

			inhibit_cookie = 0;
			set_dnd_state (false);
		}

		public void open_settings ()
		{
			System.launch_desktop_utility (
				{ "kcmshell6 kcm_notifications", "kcmshell5 kcm_notifications", "systemsettings kcm_notifications" },
				{ "gnome-control-center notifications" },
				{ "swaync-client -t -sw", "xfce4-notifyd-config" }
			);
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				toggle_dnd ();
				return AnimationType.NONE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var header_item = new Gtk.MenuItem.with_label (_("Do Not Disturb"));
			header_item.sensitive = false;
			items.add (header_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var toggle_item = create_menu_item (
				is_dnd_active ? _("Resume Notifications") : _("Silence Notifications"),
				is_dnd_active ? "notifications" : "notifications-disabled",
				true
			);
			toggle_item.activate.connect (toggle_dnd);
			items.add (toggle_item);

			var settings_item = create_menu_item (_("_Notification Settings..."), "preferences-system-notifications", true);
			settings_item.activate.connect (open_settings);
			items.add (settings_item);

			if (!is_dock_locked ()) {
				items.add (new Gtk.SeparatorMenuItem ());

				var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
				remove_item.activate.connect (() => {
					this.@delete ();
				});
				items.add (remove_item);
			}

			return items;
		}
	}
}
