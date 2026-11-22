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

		static int kind_rank (string kind)
		{
			if (kind == "wifi") return 0;
			if (kind == "ethernet") return 1;
			return 2;
		}

		static string extract_variant_string (Variant? val)
		{
			if (val == null)
				return "";
			var v = val.is_of_type (VariantType.VARIANT) ? val.get_variant () : val;
			if (v.is_of_type (VariantType.STRING) || v.is_of_type (VariantType.OBJECT_PATH))
				return v.get_string ();
			return "";
		}

		static bool is_nm_virtual_type (string nm_type)
		{
			string low = nm_type.ascii_down ();
			return low.contains ("bridge")
				|| low.contains ("tun")
				|| low.contains ("tap")
				|| low.contains ("vpn")
				|| low.contains ("wireguard")
				|| low.contains ("veth")
				|| low.contains ("dummy")
				|| low.contains ("loopback");
		}

		static void enrich_from_network_manager (Gee.ArrayList<NetworkInterfaceInfo> interfaces)
		{
			try {
				var bus = DbusBroker.get_default ().get_system_bus ();
				if (bus == null)
					return;

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
				var active_val = nm_props.lookup_value ("ActiveConnections", null);
				if (active_val == null)
					return;
				var active_arr = active_val.is_of_type (VariantType.VARIANT) ? active_val.get_variant () : active_val;
				size_t n_active = active_arr.n_children ();

				var by_iface = new Gee.HashMap<string, NetworkInterfaceInfo> ();
				foreach (var info in interfaces)
					by_iface.set (info.iface_id, info);

				for (size_t i = 0; i < n_active; i++) {
					string conn_path = extract_variant_string (active_arr.get_child_value (i));
					if (conn_path == "" || conn_path == "/")
						continue;

					Variant conn_props_var;
					try {
						conn_props_var = bus.call_sync (
							"org.freedesktop.NetworkManager",
							conn_path,
							"org.freedesktop.DBus.Properties",
							"GetAll",
							new Variant ("(s)", "org.freedesktop.NetworkManager.Connection.Active"),
							null,
							DBusCallFlags.NO_AUTO_START,
							250,
							null
						);
					} catch { continue; }

					var conn_props = conn_props_var.get_child_value (0);
					string cid = extract_variant_string (conn_props.lookup_value ("Id", null));
					string ctype_raw = extract_variant_string (conn_props.lookup_value ("Type", null));
					string spec_path = extract_variant_string (conn_props.lookup_value ("SpecificObject", null));
					string ip4_path = extract_variant_string (conn_props.lookup_value ("Ip4Config", null));

					/* Skip loopback or non-activated connections */
					var state_val = conn_props.lookup_value ("State", null);
					if (state_val != null) {
						var sv = state_val.is_of_type (VariantType.VARIANT) ? state_val.get_variant () : state_val;
						if (sv.is_of_type (VariantType.UINT32) && sv.get_uint32 () != 2U) /* NM_ACTIVE_CONNECTION_STATE_ACTIVATED */
							continue;
					}
					if (ctype_raw == "loopback")
						continue;

					/* Resolve kernel device interface name */
					string dev_iface = "";
					var devs_val = conn_props.lookup_value ("Devices", null);
					if (devs_val != null) {
						var dv = devs_val.is_of_type (VariantType.VARIANT) ? devs_val.get_variant () : devs_val;
						if (dv.n_children () > 0) {
							string dev_path = extract_variant_string (dv.get_child_value (0));
							if (dev_path != "" && dev_path != "/") {
								try {
									var dev_if_var = bus.call_sync (
										"org.freedesktop.NetworkManager",
										dev_path,
										"org.freedesktop.DBus.Properties",
										"Get",
										new Variant ("(ss)", "org.freedesktop.NetworkManager.Device", "Interface"),
										null,
										DBusCallFlags.NO_AUTO_START,
										150,
										null
									);
									dev_iface = extract_variant_string (dev_if_var.get_child_value (0));
								} catch {}
							}
						}
					}

					int strength = -1;
					if (ctype_raw.contains ("wireless") && spec_path != "" && spec_path != "/") {
						try {
							var ap_props_var = bus.call_sync (
								"org.freedesktop.NetworkManager",
								spec_path,
								"org.freedesktop.DBus.Properties",
								"Get",
								new Variant ("(ss)", "org.freedesktop.NetworkManager.AccessPoint", "Strength"),
								null,
								DBusCallFlags.NO_AUTO_START,
								150,
								null
							);
							var sv = ap_props_var.get_child_value (0);
							if (sv.is_of_type (VariantType.VARIANT))
								sv = sv.get_variant ();
							if (sv.is_of_type (VariantType.BYTE))
								strength = (int) sv.get_byte ();
						} catch {}
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
								150,
								null
							);
							var ip_props = ip_props_var.get_child_value (0);
							var addr_data_val = ip_props.lookup_value ("AddressData", null);
							if (addr_data_val != null) {
								var v = addr_data_val.is_of_type (VariantType.VARIANT) ? addr_data_val.get_variant () : addr_data_val;
								if (v.n_children () > 0) {
									var first_dict = v.get_child_value (0);
									ip = extract_variant_string (first_dict.lookup_value ("address", null));
								}
							}
							gw = extract_variant_string (ip_props.lookup_value ("Gateway", null));
						} catch {}
					}

					if (dev_iface != "" && by_iface.has_key (dev_iface)) {
						var existing = by_iface.get (dev_iface);
						if (cid != "")
							existing.display_name = cid;
						if (ctype_raw.contains ("wireless"))
							existing.kind = "wifi";
						else if (is_nm_virtual_type (ctype_raw))
							existing.kind = "virtual";
						if (strength >= 0)
							existing.wifi_strength = strength;
						if (existing.ip_address == "" && ip != "")
							existing.ip_address = ip;
						if (existing.gateway == "" && gw != "")
							existing.gateway = gw;
					} else if (ip != "" || ctype_raw.contains ("wireless")) {
						var info = new NetworkInterfaceInfo ();
						info.iface_id = (dev_iface != "") ? dev_iface : conn_path;
						info.display_name = (cid != "") ? cid : info.iface_id;
						info.kind = ctype_raw.contains ("wireless")
							? "wifi"
							: (is_nm_virtual_type (ctype_raw) ? "virtual" : "ethernet");
						info.wifi_strength = (strength >= 0) ? strength : 0;
						info.ip_address = ip;
						info.gateway = gw;
						interfaces.add (info);
						by_iface.set (info.iface_id, info);
					}
				}
			} catch {}
		}

		public Gee.ArrayList<NetworkInterfaceInfo> list_interfaces_sync ()
		{
			var list = hal_kernel_list_network_interfaces ();
			enrich_from_network_manager (list);

			/* Strict priority: Wi-Fi -> Physical Ethernet -> Virtual (gateway first, signal desc) */
			list.sort ((a, b) => {
				int ra = kind_rank (a.kind);
				int rb = kind_rank (b.kind);
				if (ra != rb) return ra - rb;
				int ga = (a.gateway != "") ? 0 : 1;
				int gb = (b.gateway != "") ? 0 : 1;
				if (ga != gb) return ga - gb;
				if (ra == 0 && a.wifi_strength != b.wifi_strength)
					return b.wifi_strength - a.wifi_strength;
				return 0;
			});

			return list;
		}

		public NetworkState probe_state_sync ()
		{
			var list = list_interfaces_sync ();
			if (list.size > 0) {
				var top = list.get (0);
				return NetworkState () {
					is_connected = true,
					connection_type = top.kind,
					connection_name = top.display_name,
					wifi_strength = top.wifi_strength,
					ip_address = top.ip_address,
					gateway = top.gateway
				};
			}

			string fb_type, fb_name, fb_ip, fb_gw;
			int fb_strength;
			if (hal_kernel_probe_network_fallback (out fb_type, out fb_name, out fb_strength, out fb_ip, out fb_gw)) {
				return NetworkState () {
					is_connected = true,
					connection_type = fb_type,
					connection_name = fb_name,
					wifi_strength = fb_strength,
					ip_address = fb_ip,
					gateway = fb_gw
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
