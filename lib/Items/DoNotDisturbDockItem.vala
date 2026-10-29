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
	public class DoNotDisturbDockItem : DockItem
	{
		const string ICON_ACTIVE = "preferences-desktop-notification-bell;;notifications;;preferences-system-notifications;;notification-symbolic";
		const string ICON_MUTED = "notifications-disabled;;notifications-disabled-symbolic;;notification-disabled;;preferences-desktop-notification-bell";

		private bool is_dnd_active = false;
		private uint inhibit_cookie = 0;
		private DBusConnection? session_bus = null;
		private uint dbus_signal_id = 0;
		private uint poll_timer_id = 0;

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

			query_initial_state ();
			start_timer ();
		}

		~DoNotDisturbDockItem ()
		{
			stop_timer ();
			if (dbus_signal_id > 0 && session_bus != null) {
				session_bus.signal_unsubscribe (dbus_signal_id);
				dbus_signal_id = 0;
			}
		}

		private void start_timer ()
		{
			if (poll_timer_id == 0) {
				poll_timer_id = Timeout.add_seconds (5, () => {
					query_initial_state ();
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

		private void query_initial_state ()
		{
			if (session_bus == null)
				return;

			// 1. Query org.freedesktop.Notifications.Inhibited property
			try {
				var res = session_bus.call_sync (
					"org.freedesktop.Notifications",
					"/org/freedesktop/Notifications",
					"org.freedesktop.DBus.Properties",
					"Get",
					new Variant ("(ss)", "org.freedesktop.Notifications", "Inhibited"),
					new VariantType ("(v)"),
					DBusCallFlags.NONE,
					1000,
					null
				);
				var inner = res.get_child_value (0).get_variant ();
				set_dnd_state (inner.get_boolean ());
				return;
			} catch (Error e) { }

			// 2. GNOME GSettings fallback
			if (Environment.find_program_in_path ("gsettings") != null) {
				try {
					string stdout_out;
					Process.spawn_command_line_sync ("gsettings get org.gnome.desktop.notifications show-banners", out stdout_out, null, null);
					if (stdout_out.strip () == "false") {
						set_dnd_state (true);
						return;
					}
				} catch (Error e) { }
			}

			// 3. Dunst fallback
			if (Environment.find_program_in_path ("dunstctl") != null) {
				try {
					string stdout_out;
					Process.spawn_command_line_sync ("dunstctl is-paused", out stdout_out, null, null);
					if (stdout_out.strip () == "true") {
						set_dnd_state (true);
						return;
					}
				} catch (Error e) { }
			}

			set_dnd_state (inhibit_cookie > 0);
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
			if (session_bus != null) {
				try {
					var builder = new VariantBuilder (new VariantType ("a{sv}"));
					var res = session_bus.call_sync (
						"org.freedesktop.Notifications",
						"/org/freedesktop/Notifications",
						"org.freedesktop.Notifications",
						"Inhibit",
						new Variant ("(ssa{sv})", "WayPlank", "Do Not Disturb", builder),
						new VariantType ("(u)"),
						DBusCallFlags.NONE,
						1500,
						null
					);
					inhibit_cookie = res.get_child_value (0).get_uint32 ();
					set_dnd_state (true);
					return;
				} catch (Error e) {
					warning ("Failed to inhibit notifications via DBus: %s", e.message);
				}
			}

			// Fallback: GNOME gsettings
			if (Environment.find_program_in_path ("gsettings") != null) {
				try {
					Process.spawn_command_line_async ("gsettings set org.gnome.desktop.notifications show-banners false");
					set_dnd_state (true);
					return;
				} catch (Error e) { }
			}

			// Fallback: Dunst
			if (Environment.find_program_in_path ("dunstctl") != null) {
				try {
					Process.spawn_command_line_async ("dunstctl set-paused true");
					set_dnd_state (true);
					return;
				} catch (Error e) { }
			}

			// Fallback: SwayNC
			if (Environment.find_program_in_path ("swaync-client") != null) {
				try {
					Process.spawn_command_line_async ("swaync-client -d -on");
					set_dnd_state (true);
					return;
				} catch (Error e) { }
			}
		}

		public void uninhibit ()
		{
			if (session_bus != null && inhibit_cookie > 0) {
				try {
					session_bus.call_sync (
						"org.freedesktop.Notifications",
						"/org/freedesktop/Notifications",
						"org.freedesktop.Notifications",
						"UnInhibit",
						new Variant ("(u)", inhibit_cookie),
						null,
						DBusCallFlags.NONE,
						1500,
						null
					);
					inhibit_cookie = 0;
					set_dnd_state (false);
					return;
				} catch (Error e) {
					warning ("Failed to uninhibit notifications via DBus: %s", e.message);
				}
			}

			// If inhibit_cookie was 0 (e.g. inhibited by another app or Plasma tray), try UnInhibit(1) or toggle
			if (session_bus != null) {
				try {
					session_bus.call_sync (
						"org.freedesktop.Notifications",
						"/org/freedesktop/Notifications",
						"org.freedesktop.Notifications",
						"UnInhibit",
						new Variant ("(u)", 1),
						null,
						DBusCallFlags.NONE,
						1000,
						null
					);
				} catch (Error e) { }
			}

			// Fallback: GNOME gsettings
			if (Environment.find_program_in_path ("gsettings") != null) {
				try {
					Process.spawn_command_line_async ("gsettings set org.gnome.desktop.notifications show-banners true");
				} catch (Error e) { }
			}

			// Fallback: Dunst
			if (Environment.find_program_in_path ("dunstctl") != null) {
				try {
					Process.spawn_command_line_async ("dunstctl set-paused false");
				} catch (Error e) { }
			}

			// Fallback: SwayNC
			if (Environment.find_program_in_path ("swaync-client") != null) {
				try {
					Process.spawn_command_line_async ("swaync-client -d -off");
				} catch (Error e) { }
			}

			inhibit_cookie = 0;
			set_dnd_state (false);
		}

		public void open_settings ()
		{
			string[] commands = {
				"kcmshell6 kcm_notifications",
				"kcmshell5 kcm_notifications",
				"gnome-control-center notifications",
				"xfce4-notifyd-config",
				"swaync-client -t",
				"systemsettings kcm_notifications"
			};

			foreach (var cmd in commands) {
				var prog = cmd.split (" ")[0];
				if (Environment.find_program_in_path (prog) != null) {
					try {
						Process.spawn_command_line_async (cmd);
						return;
					} catch (Error e) { }
				}
			}
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

			items.add (new Gtk.SeparatorMenuItem ());

			var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
			remove_item.activate.connect (() => {
				this.@delete ();
			});
			items.add (remove_item);

			return items;
		}
	}
}
