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
	 * Southbound `com.canonical.Unity.LauncherEntry` D-Bus driver (`ILauncherBadgeBus`),
	 * rate-limiting incoming `(sa{sv})` signals and unpacking them into `LauncherBadgeState`.
	 */
	public class LauncherEntryDbusService : GLib.Object, ILauncherBadgeBus
	{
		class LauncherEntry
		{
			public uint fast_count = 0U;
			public int64 last_update = 0LL;
			public string? sender_name;
			public Variant? parameters;
			public uint timer_id = 0U;
			public bool warned = false;
		}

		const string DBUS_NAME = "com.canonical.Unity";
		const string INTERFACE_NAME = "com.canonical.Unity.LauncherEntry";
		const string SIGNAL_NAME = "Update";

		static LauncherEntryDbusService? instance = null;
		static DBusConnection? connection = null;
		static uint unity_bus_id = 0U;
		static VariantType payload_variant_type;

		public static unowned LauncherEntryDbusService get_default ()
		{
			if (instance == null)
				instance = new LauncherEntryDbusService ();

			return instance;
		}

		static construct
		{
			payload_variant_type = new VariantType ("(sa{sv})");
		}

		static void acquire_unity_dbus ()
		{
			if (connection == null)
				connection = DbusBroker.get_default ().get_session_bus ();
			if (connection == null)
				return;

			if (unity_bus_id == 0U) {
				unity_bus_id = Bus.own_name (BusType.SESSION, DBUS_NAME, BusNameOwnerFlags.ALLOW_REPLACEMENT,
					(BusAcquiredCallback) handle_bus_acquired, (BusNameAcquiredCallback) handle_name_acquired,
					(BusNameLostCallback) handle_name_lost);
			}
		}

		static void handle_bus_acquired (DBusConnection conn, string name)
		{
		}

		static void handle_name_acquired (DBusConnection conn, string name)
		{
			debug ("%s acquired", name);
		}

		static void handle_name_lost (DBusConnection conn, string name)
		{
			if (conn == null)
				warning ("%s failed", name);
			else
				debug ("%s lost", name);
		}

		Gee.HashSet<ILauncherBadgeClient>? clients;
		uint launcher_entry_dbus_signal_id = 0U;
		uint dbus_name_owner_changed_signal_id = 0U;
		Gee.HashMap<string, LauncherEntry>? launcher_entries;
		uint launcher_entries_timer_id = 0U;

		LauncherEntryDbusService ()
		{
			Object ();
		}

		construct
		{
			clients = new Gee.HashSet<ILauncherBadgeClient> ();
			launcher_entries = new Gee.HashMap<string, LauncherEntry> ();

			acquire_unity_dbus ();

			if (connection != null) {
				debug ("Initializing LauncherEntry support");

				launcher_entry_dbus_signal_id = connection.signal_subscribe (null, INTERFACE_NAME,
					null, null, null, DBusSignalFlags.NONE, (DBusSignalCallback) handle_entry_signal);
				dbus_name_owner_changed_signal_id = connection.signal_subscribe ("org.freedesktop.DBus", "org.freedesktop.DBus",
					"NameOwnerChanged", "/org/freedesktop/DBus", null, DBusSignalFlags.NONE, (DBusSignalCallback) handle_name_owner_changed);
			}
		}

		~LauncherEntryDbusService ()
		{
			cleanup ();
		}

		public void cleanup ()
		{
			if (launcher_entries_timer_id > 0U) {
				Source.remove (launcher_entries_timer_id);
				launcher_entries_timer_id = 0U;
			}

			if (launcher_entries != null) {
				foreach (var entry in launcher_entries.values) {
					if (entry.timer_id > 0U) {
						Source.remove (entry.timer_id);
						entry.timer_id = 0U;
					}
				}
				launcher_entries = null;
			}

			clients = null;

			if (unity_bus_id > 0U) {
				Bus.unown_name (unity_bus_id);
				unity_bus_id = 0U;
			}

			if (connection != null) {
				if (launcher_entry_dbus_signal_id > 0U) {
					connection.signal_unsubscribe (launcher_entry_dbus_signal_id);
					launcher_entry_dbus_signal_id = 0U;
				}
				if (dbus_name_owner_changed_signal_id > 0U) {
					connection.signal_unsubscribe (dbus_name_owner_changed_signal_id);
					dbus_name_owner_changed_signal_id = 0U;
				}
			}
		}

		public void add_client (ILauncherBadgeClient client)
		{
			if (clients != null)
				clients.add (client);
		}

		public void remove_client (ILauncherBadgeClient client)
		{
			if (clients != null)
				clients.remove (client);
		}

		[CCode (instance_pos = -1)]
		void handle_entry_signal (DBusConnection connection, string sender_name, string object_path,
			string interface_name, string signal_name, Variant parameters)
		{
			if (parameters == null || signal_name == null || sender_name == null)
				return;

			if (signal_name == SIGNAL_NAME)
				handle_update_request (sender_name, parameters);
		}

		[CCode (instance_pos = -1)]
		void handle_name_owner_changed (DBusConnection connection, string sender_name, string object_path,
			string interface_name, string signal_name, Variant parameters)
		{
			if (clients == null)
				return;

			string name, before, after;
			parameters.get ("(sss)", out name, out before, out after);

			if (after != null && after != "")
				return;

			clients.foreach ((client) => {
				client.remove_launcher_entry (name);
				return true;
			});
		}

		const uint UPDATE_THRESHOLD_DURATION_MS = 32;
		const uint UPDATE_THRESHOLD_FAST_COUNT = 3;

		void handle_update_request (string sender_name, Variant parameters)
		{
			if (launcher_entries == null)
				return;

			var current_time = GLib.get_monotonic_time ();
			LauncherEntry? entry;
			if ((entry = launcher_entries.get (sender_name)) != null) {
				entry.parameters = parameters;
				if (current_time - entry.last_update < UPDATE_THRESHOLD_DURATION_MS * 1000
					&& entry.fast_count > UPDATE_THRESHOLD_FAST_COUNT) {
					if (entry.timer_id <= 0U) {
						if (!entry.warned) {
							warning ("LauncherEntry '%s' is behaving badly, skipping requests", sender_name);
							entry.warned = true;
						}
						entry.timer_id = Timeout.add (UPDATE_THRESHOLD_DURATION_MS, () => {
							entry.timer_id = 0U;
							entry.last_update = GLib.get_monotonic_time ();
							if (entry.sender_name != null && entry.parameters != null)
								perform_update (entry.sender_name, entry.parameters);
							return false;
						});
					}
				} else {
					entry.fast_count++;
					entry.last_update = current_time;
					if (entry.sender_name != null && entry.parameters != null)
						perform_update (entry.sender_name, entry.parameters);
				}
			} else {
				entry = new LauncherEntry ();
				entry.fast_count++;
				entry.last_update = current_time;
				entry.sender_name = sender_name;
				entry.parameters = parameters;
				launcher_entries.set (sender_name, entry);
				perform_update (sender_name, parameters);
			}

			if (launcher_entries_timer_id <= 0U)
				launcher_entries_timer_id = Timeout.add (60 * 1000, (SourceFunc) clean_up_launcher_entries);
		}

		bool clean_up_launcher_entries ()
		{
			if (launcher_entries == null) {
				launcher_entries_timer_id = 0U;
				return false;
			}

			var current_time = GLib.get_monotonic_time ();

			var launcher_entries_it = launcher_entries.map_iterator ();
			while (launcher_entries_it.next ()) {
				var entry = launcher_entries_it.get_value ();
				if (current_time - entry.last_update > 10 * UPDATE_THRESHOLD_DURATION_MS * 1000) {
					if (entry.timer_id > 0U) {
						Source.remove (entry.timer_id);
						entry.timer_id = 0U;
					}
					launcher_entries_it.unset ();
				}
			}

			var keep_running = (launcher_entries.size > 0);
			if (!keep_running)
				launcher_entries_timer_id = 0U;

			debug ("[LauncherEntry] Keeping %i active LauncherEntries", launcher_entries.size);

			return keep_running;
		}

		static bool try_extract_int64 (Variant v, out int64 result)
		{
			unowned string ts = v.get_type_string ();
			if (ts == "x") { result = v.get_int64 (); return true; }
			if (ts == "i") { result = (int64) v.get_int32 (); return true; }
			if (ts == "u") { result = (int64) v.get_uint32 (); return true; }
			if (ts == "t") { result = (int64) v.get_uint64 (); return true; }
			if (ts == "n") { result = (int64) v.get_int16 (); return true; }
			if (ts == "q") { result = (int64) v.get_uint16 (); return true; }
			if (ts == "y") { result = (int64) v.get_byte (); return true; }
			if (ts == "d") { result = (int64) v.get_double (); return true; }
			result = 0;
			return false;
		}

		static bool try_extract_double (Variant v, out double result)
		{
			if (v.is_of_type (VariantType.DOUBLE)) {
				result = v.get_double ();
				return true;
			}
			int64 ival;
			if (try_extract_int64 (v, out ival)) {
				result = (double) ival;
				return true;
			}
			result = 0.0;
			return false;
		}

		static LauncherBadgeState unpack_payload (Variant parameters)
		{
			var state = LauncherBadgeState () {
				app_uri = "",
				has_count = false,
				count = 0,
				has_count_visible = false,
				count_visible = false,
				has_progress = false,
				progress = 0.0,
				has_progress_visible = false,
				progress_visible = false,
				has_urgent = false,
				urgent = false
			};

			VariantIter prop_iter;
			string app_uri = "";
			parameters.get ("(sa{sv})", out app_uri, out prop_iter);
			string clean_uri = app_uri != null ? app_uri.strip () : "";
			if (clean_uri.has_prefix ("application://"))
				clean_uri = clean_uri.substring ("application://".length);
			while (clean_uri.has_prefix ("/"))
				clean_uri = clean_uri.substring (1);
			state.app_uri = clean_uri;

			string prop_key;
			Variant prop_value;
			while (prop_iter.next ("{sv}", out prop_key, out prop_value)) {
				if (prop_key == "count") {
					int64 cval;
					if (try_extract_int64 (prop_value, out cval)) {
						state.has_count = true;
						state.count = cval;
					}
				} else if (prop_key == "count-visible") {
					if (prop_value.is_of_type (VariantType.BOOLEAN)) {
						state.has_count_visible = true;
						state.count_visible = prop_value.get_boolean ();
					}
				} else if (prop_key == "progress") {
					double pval;
					if (try_extract_double (prop_value, out pval)) {
						state.has_progress = true;
						state.progress = pval;
					}
				} else if (prop_key == "progress-visible") {
					if (prop_value.is_of_type (VariantType.BOOLEAN)) {
						state.has_progress_visible = true;
						state.progress_visible = prop_value.get_boolean ();
					}
				} else if (prop_key == "urgent") {
					if (prop_value.is_of_type (VariantType.BOOLEAN)) {
						state.has_urgent = true;
						state.urgent = prop_value.get_boolean ();
					}
				}
			}

			return state;
		}

		void perform_update (string sender_name, Variant parameters)
		{
			if (clients == null)
				return;

			if (!parameters.is_of_type (payload_variant_type)) {
				warning ("Illegal payload signature '%s' from %s. expected '(sa{sv})'", parameters.get_type_string (), sender_name);
				return;
			}

			var state = unpack_payload (parameters);
			clients.foreach ((client) => {
				client.update_launcher_entry (sender_name, state);
				return true;
			});
		}
	}
}
