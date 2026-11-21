//
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
		GLib.Mutex cache_mutex;
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

		public uint own_session_name (string name, BusNameOwnerFlags flags,
			owned BusAcquiredCallback? bus_acquired,
			owned BusNameAcquiredCallback? name_acquired,
			owned BusNameLostCallback? name_lost)
		{
			return Bus.own_name (BusType.SESSION, name, flags,
				(owned) bus_acquired, (owned) name_acquired, (owned) name_lost);
		}

		public uint own_name_on_connection (DBusConnection conn, string name, BusNameOwnerFlags flags,
			owned BusNameAcquiredCallback? name_acquired,
			owned BusNameLostCallback? name_lost)
		{
			return Bus.own_name_on_connection (conn, name, flags,
				(owned) name_acquired, (owned) name_lost);
		}

		public void unown_name (uint owner_id)
		{
			if (owner_id > 0U)
				Bus.unown_name (owner_id);
		}

		public uint watch_session_name (string name, BusNameWatcherFlags flags,
			owned BusNameAppearedCallback? name_appeared,
			owned BusNameVanishedCallback? name_vanished)
		{
			return Bus.watch_name (BusType.SESSION, name, flags,
				(owned) name_appeared, (owned) name_vanished);
		}

		public void unwatch_name (uint watcher_id)
		{
			if (watcher_id > 0U)
				Bus.unwatch_name (watcher_id);
		}

		public uint resolve_sender_pid (string bus_or_sender)
		{
			if (bus_or_sender == "")
				return 0U;

			cache_mutex.lock ();
			if (sender_pid_cache.has_key (bus_or_sender)) {
				uint cached = sender_pid_cache.get (bus_or_sender);
				cache_mutex.unlock ();
				return cached;
			}
			cache_mutex.unlock ();

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
				if (pid > 0U) {
					cache_mutex.lock ();
					if (sender_pid_cache.size > 256)
						sender_pid_cache.clear ();
					sender_pid_cache.set (bus_or_sender, pid);
					cache_mutex.unlock ();
				}
				return pid;
			} catch (Error e) {
				return 0U;
			}
		}

		static int parse_unique_conn_serial (string name)
		{
			if (!name.has_prefix (":1."))
				return int.MAX;
			return int.parse (name.substring (3));
		}

		/**
		 * Enumerates all unique session-bus connections (`:1.N`) owned by `pid`
		 * sorted in ascending serial order so main UI connections precede worker threads.
		 */
		public Gee.ArrayList<string> resolve_unique_senders_for_pid (int pid)
		{
			var result = new Gee.ArrayList<string> ();
			if (pid <= 0)
				return result;

			var bus = get_session_bus ();
			if (bus == null)
				return result;

			try {
				var names_res = bus.call_sync (
					"org.freedesktop.DBus",
					"/org/freedesktop/DBus",
					"org.freedesktop.DBus",
					"ListNames",
					null,
					new VariantType ("(as)"),
					DBusCallFlags.NONE,
					100,
					null
				);
				string[] names = names_res.get_child_value (0).get_strv ();
				foreach (unowned string n in names) {
					if (!n.has_prefix (":1."))
						continue;
					if ((int) resolve_sender_pid (n) == pid)
						result.add (n);
				}
				result.sort ((a, b) => {
					int sa = parse_unique_conn_serial (a);
					int sb = parse_unique_conn_serial (b);
					return (sa < sb) ? -1 : ((sa > sb) ? 1 : 0);
				});
			} catch (Error e) { }

			return result;
		}

		[CCode (instance_pos = -1)]
		void on_session_name_owner_changed (DBusConnection conn, string sender, string obj_path,
			string iface_name, string sig_name, Variant parameters)
		{
			string name = "", old_owner = "", new_owner = "";
			parameters.get ("(sss)", out name, out old_owner, out new_owner);
			cache_mutex.lock ();
			if (old_owner != "")
				sender_pid_cache.unset (old_owner);
			if (name != "" && new_owner == "")
				sender_pid_cache.unset (name);
			cache_mutex.unlock ();
			session_name_owner_changed (name, old_owner, new_owner);
		}

		public void cleanup ()
		{
			if (session_conn != null && name_owner_sub_id > 0U) {
				session_conn.signal_unsubscribe (name_owner_sub_id);
				name_owner_sub_id = 0U;
			}
			cache_mutex.lock ();
			sender_pid_cache.clear ();
			cache_mutex.unlock ();
		}
	}
}
