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
	const string DBUS_PING_NAME = "Ping";

	const string DBUS_DOCK_INTERFACE_NAME = "net.launchpad.plank";
	const string DBUS_CLIENT_INTERFACE_NAME = "net.launchpad.plank.Client";

	/**
	 * Provide an interface to manage items of the dock
	 */
	[DBus (name = "net.launchpad.plank.Items")]
	interface DBusItemsIface : GLib.Object
	{
		public signal void changed ();

		public abstract bool add (string uri) throws GLib.DBusError, GLib.IOError;
		public abstract bool remove (string uri) throws GLib.DBusError, GLib.IOError;
		public abstract int get_count () throws GLib.DBusError, GLib.IOError;
		public abstract string[] get_persistent_applications () throws GLib.DBusError, GLib.IOError;
		public abstract string[] get_transient_applications () throws GLib.DBusError, GLib.IOError;
		public abstract bool get_hover_position (string uri, out int x, out int y, out Gtk.PositionType dock_position) throws GLib.DBusError, GLib.IOError;
	}

	/**
	 * Provide an interface to manage items of the dock
	 */
	class DBusItems : GLib.Object, Plank.DBusItemsIface
	{
		IDockIpcTarget target;
		uint changed_timer_id = 0U;

		public DBusItems (IDockIpcTarget _target)
		{
			target = _target;
			target.ipc_elements_changed.connect (handle_elements_changed);
		}

		~DBusItems ()
		{
			target.ipc_elements_changed.disconnect (handle_elements_changed);

			if (changed_timer_id > 0U) {
				GLib.Source.remove (changed_timer_id);
				changed_timer_id = 0U;
			}
		}

		void handle_elements_changed ()
		{
			if (changed_timer_id > 0U)
				return;

			// Fire updates with a reasonable rate
			changed_timer_id = Timeout.add (500, () => {
				changed_timer_id = 0U;
				changed ();
				return false;
			});
		}

		public bool add (string uri)
		{
			return target.ipc_add_item (uri);
		}

		public bool remove (string uri)
		{
			return target.ipc_remove_item (uri);
		}

		public int get_count ()
		{
			return target.ipc_get_item_count ();
		}

		public string[] get_persistent_applications ()
		{
			return target.ipc_get_persistent_applications ();
		}

		public string[] get_transient_applications ()
		{
			return target.ipc_get_transient_applications ();
		}

		public bool get_hover_position (string uri, out int x, out int y, out Gtk.PositionType dock_position)
		{
			return target.ipc_get_hover_position (uri, out x, out y, out dock_position);
		}
	}

	/**
	 * Southbound Freedesktop D-Bus RPC server for a single dock instance (`net.launchpad.plank.Items`).
	 */
	public class DockIpcServer : GLib.Object, IDockIpcServer
	{
		public IDockIpcTarget target { private get; construct; }

		DBusConnection? connection = null;
		string? dock_object_path;

		uint dbus_items_signal_id = 0U;
		uint dbus_client_ping_signal_id = 0U;

		public DockIpcServer (IDockIpcTarget target)
		{
			Object (target: target);
		}

		construct
		{
			unowned GLib.Application? application = GLib.Application.get_default ();
			string? object_path = null;

			if (application != null) {
				connection = application.get_dbus_connection ();
				object_path = application.get_dbus_object_path ();
			}

			if (connection == null || object_path == null) {
				critical ("Not able to register our interfaces");
				return;
			}

			string dock_name = target.get_ipc_dock_name ();
			if (!object_path.has_suffix (dock_name))
				object_path = "%s/%s".printf (object_path, dock_name);

			// Listen for "Ping" signals coming from clients
			try {
				dbus_client_ping_signal_id = connection.signal_subscribe (null, Plank.DBUS_CLIENT_INTERFACE_NAME,
					Plank.DBUS_PING_NAME, null, null, DBusSignalFlags.NONE, (DBusSignalCallback) handle_client_ping);
			} catch (IOError e) {
				warning ("Could not subscribe for client signal (%s)", e.message);
			}

			try {
				var dbus_items = new DBusItems (target);
				dbus_items_signal_id = connection.register_object<Plank.DBusItemsIface> (object_path, dbus_items);
				WindowControl.register_dbus (connection, object_path);
			} catch (IOError e) {
				warning ("Could not register service (%s)", e.message);
			}

			dock_object_path = (owned) object_path;

			try {
				// Broadcast to inform running clients
				connection.emit_signal (null, dock_object_path, Plank.DBUS_DOCK_INTERFACE_NAME, Plank.DBUS_PING_NAME, null);
			} catch (Error e) {
				warning ("Could not ping running clients (%s)", e.message);
			}
		}

		~DockIpcServer ()
		{
			dispose_ipc ();
		}

		public void dispose_ipc ()
		{
			if (connection != null) {
				if (dbus_items_signal_id > 0U) {
					connection.unregister_object (dbus_items_signal_id);
					dbus_items_signal_id = 0U;
				}
				if (dbus_client_ping_signal_id > 0U) {
					connection.signal_unsubscribe (dbus_client_ping_signal_id);
					dbus_client_ping_signal_id = 0U;
				}
			}
		}

		[CCode (instance_pos = -1)]
		void handle_client_ping (DBusConnection connection, string sender_name, string object_path,
			string interface_name, string signal_name, Variant parameters)
		{
			try {
				// Broadcast to inform running clients
				connection.emit_signal (null, dock_object_path, Plank.DBUS_DOCK_INTERFACE_NAME, Plank.DBUS_PING_NAME, null);
			} catch (Error e) {
				warning ("Could not ping running clients (%s)", e.message);
			}
		}
	}
}
