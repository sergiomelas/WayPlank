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
	 * Shared southbound Session & System D-Bus connection pool and sender <-> PID cache.
	 */
	public class DbusBroker : GLib.Object
	{
		static DbusBroker? default_instance = null;

		public signal void session_name_owner_changed (string name, string old_owner, string new_owner);

		DBusConnection? session_conn = null;
		DBusConnection? system_conn = null;
		uint name_owner_sub_id = 0U;
		Gee.HashMap<string, uint> sender_pid_cache;

		public static DbusBroker get_default ()
		{
			if (default_instance == null)
				default_instance = new DbusBroker ();
			return default_instance;
		}

		construct
		{
			sender_pid_cache = new Gee.HashMap<string, uint> ();
		}

		~DbusBroker ()
		{
			cleanup ();
		}

		public DBusConnection? get_session_bus ()
		{
			if (session_conn == null) {
				try {
					session_conn = Bus.get_sync (BusType.SESSION, null);
					if (session_conn != null && name_owner_sub_id == 0U) {
						name_owner_sub_id = session_conn.signal_subscribe (
							"org.freedesktop.DBus",
							"org.freedesktop.DBus",
							"NameOwnerChanged",
							"/org/freedesktop/DBus",
							null,
							DBusSignalFlags.NONE,
							(DBusSignalCallback) on_session_name_owner_changed
						);
					}
				} catch (Error e) {
					debug ("DbusBroker: session bus unavailable: %s", e.message);
				}
			}
			return session_conn;
		}

		public DBusConnection? get_system_bus ()
		{
			if (system_conn == null) {
				try {
					system_conn = Bus.get_sync (BusType.SYSTEM, null);
				} catch (Error e) {
					debug ("DbusBroker: system bus unavailable: %s", e.message);
				}
			}
			return system_conn;
		}

		public uint resolve_sender_pid (string bus_or_sender)
		{
			if (bus_or_sender == "")
				return 0U;
			if (sender_pid_cache.has_key (bus_or_sender))
				return sender_pid_cache.get (bus_or_sender);

			var bus = get_session_bus ();
			if (bus == null)
				return 0U;

			try {
				var res = bus.call_sync (
					"org.freedesktop.DBus",
					"/org/freedesktop/DBus",
					"org.freedesktop.DBus",
					"GetConnectionUnixProcessID",
					new Variant ("(s)", bus_or_sender),
					new VariantType ("(u)"),
					DBusCallFlags.NONE,
					400,
					null
				);
				uint pid = 0U;
				res.get ("(u)", out pid);
				if (pid > 0U)
					sender_pid_cache.set (bus_or_sender, pid);
				return pid;
			} catch (Error e) {
				return 0U;
			}
		}

		[CCode (instance_pos = -1)]
		void on_session_name_owner_changed (DBusConnection conn, string sender, string obj_path,
			string iface_name, string sig_name, Variant parameters)
		{
			string name = "", old_owner = "", new_owner = "";
			parameters.get ("(sss)", out name, out old_owner, out new_owner);
			if (old_owner != "")
				sender_pid_cache.unset (old_owner);
			if (name != "" && new_owner == "")
				sender_pid_cache.unset (name);
			session_name_owner_changed (name, old_owner, new_owner);
		}

		public void cleanup ()
		{
			if (session_conn != null && name_owner_sub_id > 0U) {
				session_conn.signal_unsubscribe (name_owner_sub_id);
				name_owner_sub_id = 0U;
			}
			sender_pid_cache.clear ();
		}
	}
}
