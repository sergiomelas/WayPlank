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
	 * Southbound `org.freedesktop.NetworkManager` System D-Bus & `GLib.NetworkMonitor`
	 * connectivity provider (`INetworkProvider`).
	 */
	public class NetworkManagerDbusService : GLib.Object, INetworkProvider
	{
		static NetworkManagerDbusService? default_instance = null;

		public static NetworkManagerDbusService get_default ()
		{
			if (default_instance == null)
				default_instance = new NetworkManagerDbusService ();
			return default_instance;
		}

		uint dbus_sub_id = 0U;
		uint signal_debounce_id = 0U;
		ulong netmon_handler_id = 0UL;
		DBusConnection? system_bus = null;
		bool is_disposed = false;

		construct
		{
			start_listeners ();
		}

		~NetworkManagerDbusService ()
		{
			cleanup ();
		}

		void start_listeners ()
		{
			system_bus = DbusBroker.get_default ().get_system_bus ();
			if (system_bus != null) {
				dbus_sub_id = system_bus.signal_subscribe (
					"org.freedesktop.NetworkManager",
					"org.freedesktop.DBus.Properties",
					"PropertiesChanged",
					null,
					null,
					DBusSignalFlags.NONE,
					on_dbus_signal
				);
			}

			var netmon = NetworkMonitor.get_default ();
			if (netmon != null) {
				netmon_handler_id = netmon.network_changed.connect ((available) => {
					if (!is_disposed)
						network_changed ();
				});
			}
		}

		void on_dbus_signal (DBusConnection conn, string? sender, string path, string iface, string sig, Variant parameters)
		{
			if (is_disposed || signal_debounce_id != 0U)
				return;
			signal_debounce_id = Timeout.add (300, () => {
				signal_debounce_id = 0U;
				if (!is_disposed)
					network_changed ();
				return false;
			});
		}

		public void cleanup ()
		{
			is_disposed = true;
			if (signal_debounce_id != 0U) {
				Source.remove (signal_debounce_id);
				signal_debounce_id = 0U;
			}
			if (dbus_sub_id != 0U && system_bus != null) {
				system_bus.signal_unsubscribe (dbus_sub_id);
				dbus_sub_id = 0U;
			}
			if (netmon_handler_id != 0UL) {
				var netmon = NetworkMonitor.get_default ();
				if (netmon != null)
					netmon.disconnect (netmon_handler_id);
				netmon_handler_id = 0UL;
			}
		}

		static bool probe_network_manager (out string out_type, out string out_name, out int out_strength, out string out_ip, out string out_gw)
		{
			out_type = "none";
			out_name = "";
			out_strength = 0;
			out_ip = "";
			out_gw = "";

			try {
				var bus = Bus.get_sync (BusType.SYSTEM, null);
				var nm_props_var = bus.call_sync (
					"org.freedesktop.NetworkManager",
					"/org/freedesktop/NetworkManager",
					"org.freedesktop.DBus.Properties",
					"GetAll",
					new Variant ("(s)", "org.freedesktop.NetworkManager"),
					null,
					DBusCallFlags.NO_AUTO_START,
					300,
					null
				);

				var nm_props = nm_props_var.get_child_value (0);
				var primary_conn_type_val = nm_props.lookup_value ("PrimaryConnectionType", null);
				string raw_type = "";
				if (primary_conn_type_val != null) {
					var v = primary_conn_type_val.is_of_type (VariantType.VARIANT)
						? primary_conn_type_val.get_variant () : primary_conn_type_val;
					raw_type = v.get_string ();
				}

				var primary_conn_val = nm_props.lookup_value ("PrimaryConnection", null);
				string primary_conn_path = "";
				if (primary_conn_val != null) {
					var v = primary_conn_val.is_of_type (VariantType.VARIANT)
						? primary_conn_val.get_variant () : primary_conn_val;
					primary_conn_path = v.get_string ();
				}

				if (primary_conn_path != "" && primary_conn_path != "/") {
					var conn_props_var = bus.call_sync (
						"org.freedesktop.NetworkManager",
						primary_conn_path,
						"org.freedesktop.DBus.Properties",
						"GetAll",
						new Variant ("(s)", "org.freedesktop.NetworkManager.Connection.Active"),
						null,
						DBusCallFlags.NO_AUTO_START,
						300,
						null
					);

					var conn_props = conn_props_var.get_child_value (0);
					var id_val = conn_props.lookup_value ("Id", null);
					string cid = "";
					if (id_val != null) {
						var v = id_val.is_of_type (VariantType.VARIANT) ? id_val.get_variant () : id_val;
						cid = v.get_string ();
					}

					var spec_val = conn_props.lookup_value ("SpecificObject", null);
					string spec_path = "";
					if (spec_val != null) {
						var v = spec_val.is_of_type (VariantType.VARIANT) ? spec_val.get_variant () : spec_val;
						spec_path = v.get_string ();
					}

					var ip4_val = conn_props.lookup_value ("Ip4Config", null);
					string ip4_path = "";
					if (ip4_val != null) {
						var v = ip4_val.is_of_type (VariantType.VARIANT) ? ip4_val.get_variant () : ip4_val;
						ip4_path = v.get_string ();
					}

					int strength = 0;
					if (raw_type.contains ("wireless") && spec_path != "" && spec_path != "/") {
						try {
							var ap_props_var = bus.call_sync (
								"org.freedesktop.NetworkManager",
								spec_path,
								"org.freedesktop.DBus.Properties",
								"GetAll",
								new Variant ("(s)", "org.freedesktop.NetworkManager.AccessPoint"),
								null,
								DBusCallFlags.NO_AUTO_START,
								200,
								null
							);
							var ap_props = ap_props_var.get_child_value (0);
							var strength_val = ap_props.lookup_value ("Strength", null);
							if (strength_val != null) {
								var v = strength_val.is_of_type (VariantType.VARIANT) ? strength_val.get_variant () : strength_val;
								strength = (int) v.get_byte ();
							}
						} catch { }
					}

					string ip = "";
					string gw = "";
					if (ip4_path != "" && ip4_path != "/") {
						try {
							var ip_props_var = bus.call_sync (
								"org.freedesktop.NetworkManager",
								ip4_path,
								"org.freedesktop.DBus.Properties",
								"GetAll",
								new Variant ("(s)", "org.freedesktop.NetworkManager.IP4Config"),
								null,
								DBusCallFlags.NO_AUTO_START,
								200,
								null
							);
							var ip_props = ip_props_var.get_child_value (0);
							var addr_data_val = ip_props.lookup_value ("AddressData", null);
							if (addr_data_val != null) {
								var v = addr_data_val.is_of_type (VariantType.VARIANT) ? addr_data_val.get_variant () : addr_data_val;
								if (v.n_children () > 0) {
									var first_dict = v.get_child_value (0);
									var a_val = first_dict.lookup_value ("address", null);
									if (a_val != null) {
										var av = a_val.is_of_type (VariantType.VARIANT) ? a_val.get_variant () : a_val;
										ip = av.get_string ();
									}
								}
							}
							var gw_val = ip_props.lookup_value ("Gateway", null);
							if (gw_val != null) {
								var v = gw_val.is_of_type (VariantType.VARIANT) ? gw_val.get_variant () : gw_val;
								gw = v.get_string ();
							}
						} catch { }
					}

					out_name = cid;
					out_strength = strength;
					out_ip = ip;
					out_gw = gw;
					out_type = raw_type.contains ("wireless") ? "wifi" : "ethernet";
					return true;
				}
			} catch { }

			return false;
		}

		public NetworkState probe_state_sync ()
		{
			string nm_type, nm_name, nm_ip, nm_gw;
			int nm_strength;
			bool found_nm = probe_network_manager (out nm_type, out nm_name, out nm_strength, out nm_ip, out nm_gw);

			if (found_nm) {
				return NetworkState () {
					is_connected = true,
					connection_type = nm_type,
					connection_name = nm_name,
					wifi_strength = nm_strength,
					ip_address = nm_ip,
					gateway = nm_gw
				};
			}

			var netmon = NetworkMonitor.get_default ();
			if (netmon != null && netmon.get_network_available ()) {
				return NetworkState () {
					is_connected = true,
					connection_type = "ethernet",
					connection_name = _("Wired Connection"),
					wifi_strength = 0,
					ip_address = "",
					gateway = ""
				};
			}

			return NetworkState () {
				is_connected = false,
				connection_type = "none",
				connection_name = "",
				wifi_strength = 0,
				ip_address = "",
				gateway = ""
			};
		}
	}
}
