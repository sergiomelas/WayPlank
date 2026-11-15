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
	 * Southbound `com.canonical.dbusmenu` / `/com/canonical/menu/<hex>` driver (`IAppMenuBus`).
	 * Resolves per-window Chromium profile checkmarks (`id=61` or known profile labels)
	 * across KDE Plasma, GNOME Shell, and Labwc without exposing D-Bus wire details to `lib/`.
	 */
	public class AppMenuDbusService : GLib.Object, IAppMenuBus
	{
		static AppMenuDbusService? default_instance = null;

		public static AppMenuDbusService get_default ()
		{
			if (default_instance == null)
				default_instance = new AppMenuDbusService ();
			return default_instance;
		}

		DBusConnection? session_bus = null;
		uint layout_sub_id = 0U;
		uint props_sub_id = 0U;
		ulong owner_changed_handler_id = 0UL;
		bool shutting_down = false;

		Gee.HashMap<int, string> pid_to_dbus_sender = new Gee.HashMap<int, string> ();
		Gee.HashSet<string> dead_dbus_senders = new Gee.HashSet<string> ();

		construct
		{
			start_listeners ();
		}

		~AppMenuDbusService ()
		{
			cleanup ();
		}

		void start_listeners ()
		{
			if (layout_sub_id != 0U)
				return;

			var broker = DbusBroker.get_default ();
			session_bus = broker.get_session_bus ();
			if (session_bus == null)
				return;

			layout_sub_id = session_bus.signal_subscribe (
				null,
				"com.canonical.dbusmenu",
				"LayoutUpdated",
				null,
				null,
				DBusSignalFlags.NONE,
				on_dbusmenu_signal
			);

			props_sub_id = session_bus.signal_subscribe (
				null,
				"com.canonical.dbusmenu",
				"ItemsPropertiesUpdated",
				null,
				null,
				DBusSignalFlags.NONE,
				on_dbusmenu_signal
			);

			if (owner_changed_handler_id == 0UL) {
				owner_changed_handler_id = broker.session_name_owner_changed.connect ((name, old_owner, new_owner) => {
					if (old_owner != "" && new_owner == "") {
						dead_dbus_senders.remove (old_owner);
						var stale_pids = new Gee.ArrayList<int> ();
						foreach (var e in pid_to_dbus_sender.entries) {
							if (e.value == old_owner || e.value == name)
								stale_pids.add (e.key);
						}
						foreach (int sp in stale_pids)
							pid_to_dbus_sender.unset (sp);
					}
				});
			}
		}

		void on_dbusmenu_signal (DBusConnection conn, string? sender_name,
			string object_path, string interface_name, string signal_name, Variant parameters)
		{
			if (shutting_down || sender_name == null || sender_name == "" || !object_path.has_prefix ("/com/canonical/menu/"))
				return;

			int sender_pid = (int) DbusBroker.get_default ().resolve_sender_pid (sender_name);
			if (sender_pid <= 0)
				return;

			pid_to_dbus_sender.set (sender_pid, sender_name);
			menu_changed (sender_pid, sender_name + "|" + object_path);
		}

		string resolve_menu_dest_for_pid (int pid)
		{
			if (pid <= 0)
				return "";

			start_listeners ();
			if (session_bus == null)
				return "";

			if (pid_to_dbus_sender.has_key (pid)) {
				string cached = pid_to_dbus_sender.get (pid);
				if (cached != "" && !dead_dbus_senders.contains (cached))
					return cached;
				pid_to_dbus_sender.unset (pid);
			}

			var matching_conns = DbusBroker.get_default ().resolve_unique_senders_for_pid (pid);
			int probed = 0;
			for (int idx = 0; idx < matching_conns.size && probed < 2; idx++) {
				string conn_name = matching_conns[idx];
				if (dead_dbus_senders.contains (conn_name))
					continue;
				probed++;
				try {
					var intro = session_bus.call_sync (
						conn_name,
						"/com/canonical/menu",
						"org.freedesktop.DBus.Introspectable",
						"Introspect",
						null,
						new VariantType ("(s)"),
						DBusCallFlags.NONE,
						60,
						null
					);
					string xml = "";
					intro.get ("(s)", out xml);
					if (xml.contains ("<node name=")) {
						pid_to_dbus_sender.set (pid, conn_name);
						return conn_name;
					}
				} catch (Error e) {
					if (idx > 0)
						dead_dbus_senders.add (conn_name);
				}
			}

			return "";
		}

		Gee.ArrayList<string> list_menu_paths (int pid, string? explicit_dest = null)
		{
			var result = new Gee.ArrayList<string> ();
			if (pid <= 0)
				return result;

			start_listeners ();
			if (session_bus == null)
				return result;

			string dest = (explicit_dest != null && explicit_dest != "") ? explicit_dest : resolve_menu_dest_for_pid (pid);
			if (dest == "")
				return result;

			try {
				var intro_res = session_bus.call_sync (
					dest,
					"/com/canonical/menu",
					"org.freedesktop.DBus.Introspectable",
					"Introspect",
					null,
					new VariantType ("(s)"),
					DBusCallFlags.NONE,
					80,
					null
				);
				string xml = "";
				intro_res.get ("(s)", out xml);

				int search_pos = 0;
				while (search_pos < xml.length) {
					int node_idx = xml.index_of ("<node name=\"", search_pos);
					if (node_idx < 0)
						break;
					int q_start = node_idx + 12;
					int q_end = xml.index_of_char ('"', q_start);
					if (q_end <= q_start)
						break;
					string node_name = xml.substring (q_start, q_end - q_start);
					search_pos = q_end + 1;
					if (node_name == "")
						continue;
					uint64 node_num = 0;
					if (!uint64.try_parse (node_name, out node_num, null, 16) || node_num == 0)
						continue;
					string path = "/com/canonical/menu/" + node_name;
					if (!result.contains (path))
						result.add (path);
				}

				result.sort ((a, b) => {
					uint64 na = 0;
					uint64 nb = 0;
					uint64.try_parse (a.substring ("/com/canonical/menu/".length), out na, null, 16);
					uint64.try_parse (b.substring ("/com/canonical/menu/".length), out nb, null, 16);
					if (na < nb) return -1;
					if (na > nb) return 1;
					return 0;
				});
			} catch (Error e) {
				if (pid_to_dbus_sender.has_key (pid) && pid_to_dbus_sender.get (pid) == dest)
					pid_to_dbus_sender.unset (pid);
			}

			return result;
		}

		static string normalize_label_key (string raw)
		{
			return raw.strip ().replace ("\"", "").replace ("'", "").down ().replace (" ", "_");
		}

		static bool matches_known_label (string clean_lbl, string[]? known_labels)
		{
			if (known_labels == null || known_labels.length == 0 || clean_lbl == "")
				return false;
			string ldown = clean_lbl.down ();
			string lnorm = normalize_label_key (clean_lbl);
			foreach (unowned string kl in known_labels) {
				if (kl == null || kl == "")
					continue;
				string kdown = kl.down ();
				if (kdown == ldown || normalize_label_key (kl) == lnorm)
					return true;
			}
			return false;
		}

		string query_checked_label_on_path (int pid, string dest, string menu_path, string[]? known_profile_labels)
		{
			if (pid <= 0 || dest == "" || menu_path == "" || session_bus == null)
				return "";

			try {
				string[] prop_names = { "label", "toggle-type", "toggle-state" };
				var res = session_bus.call_sync (
					dest,
					menu_path,
					"com.canonical.dbusmenu",
					"GetLayout",
					new Variant ("(ii^as)", 0, -1, prop_names),
					new VariantType ("(u(ia{sv}av))"),
					DBusCallFlags.NONE,
					80,
					null
				);
				uint rev = 0U;
				Variant root_item;
				res.get ("(u@(ia{sv}av))", out rev, out root_item);

				int root_id = 0;
				Variant root_props;
				VariantIter top_children;
				root_item.get ("(i@a{sv}av)", out root_id, out root_props, out top_children);

				Variant? sub_var = null;
				while (top_children.next ("v", out sub_var)) {
					if (sub_var == null)
						continue;
					int sub_id = 0;
					Variant sub_props;
					VariantIter item_iter;
					sub_var.get ("(i@a{sv}av)", out sub_id, out sub_props, out item_iter);

					bool has_profile_checkmarks = (sub_id == 61);
					string checked_label = "";
					Variant? child_var = null;
					while (item_iter.next ("v", out child_var)) {
						if (child_var == null)
							continue;
						int cid = 0;
						Variant cprops;
						VariantIter dummy_iter;
						child_var.get ("(i@a{sv}av)", out cid, out cprops, out dummy_iter);
						string? ttype = null;
						cprops.lookup ("toggle-type", "s", out ttype);
						if (ttype == "checkmark") {
							string? lbl = null;
							cprops.lookup ("label", "s", out lbl);
							string clean_lbl = (lbl != null) ? lbl.strip ().replace ("_", "") : "";
							if (clean_lbl != "" && matches_known_label (clean_lbl, known_profile_labels))
								has_profile_checkmarks = true;
							int tstate = 0;
							cprops.lookup ("toggle-state", "i", out tstate);
							if (tstate == 1 && clean_lbl != "")
								checked_label = clean_lbl;
						}
					}
					if (has_profile_checkmarks && checked_label != "")
						return checked_label;
				}
			} catch (Error e) { }

			return "";
		}

		public Gee.ArrayList<string> query_ordered_window_profile_labels (int pid, string[]? known_profile_labels = null)
		{
			var labels = new Gee.ArrayList<string> ();
			if (pid <= 0)
				return labels;

			string dest = resolve_menu_dest_for_pid (pid);
			if (dest == "")
				return labels;

			var paths = list_menu_paths (pid, dest);
			foreach (string p in paths) {
				string lbl = query_checked_label_on_path (pid, dest, p, known_profile_labels);
				if (lbl != "")
					labels.add (lbl);
			}
			return labels;
		}

		public string query_profile_label_at_token (int pid, string menu_token, string[]? known_profile_labels = null)
		{
			if (pid <= 0 || menu_token == "")
				return "";

			start_listeners ();
			string explicit_dest = "";
			string menu_path = menu_token;
			int pipe_idx = menu_token.index_of_char ('|');
			if (pipe_idx > 0 && pipe_idx + 1 < menu_token.length) {
				explicit_dest = menu_token.substring (0, pipe_idx);
				menu_path = menu_token.substring (pipe_idx + 1);
			}

			string dest = explicit_dest != "" ? explicit_dest : resolve_menu_dest_for_pid (pid);
			if (dest == "" || menu_path == "")
				return "";

			return query_checked_label_on_path (pid, dest, menu_path, known_profile_labels);
		}

		public void cleanup ()
		{
			shutting_down = true;
			if (session_bus != null) {
				if (layout_sub_id != 0U) {
					session_bus.signal_unsubscribe (layout_sub_id);
					layout_sub_id = 0U;
				}
				if (props_sub_id != 0U) {
					session_bus.signal_unsubscribe (props_sub_id);
					props_sub_id = 0U;
				}
			}
			if (owner_changed_handler_id != 0UL) {
				DbusBroker.get_default ().disconnect (owner_changed_handler_id);
				owner_changed_handler_id = 0UL;
			}
			pid_to_dbus_sender.clear ();
			dead_dbus_senders.clear ();
		}
	}
}
