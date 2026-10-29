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
	public class NetworkDockItem : DockItem
	{
		uint timer_id = 0;
		uint dbus_sub_id = 0;
		ulong netmon_handler_id = 0UL;

		bool is_connected = false;
		string connection_type = "none"; // "wifi", "ethernet", "none"
		string connection_name = "";
		int wifi_strength = 0;
		string ip_address = "";
		string gateway = "";

		public NetworkDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public NetworkDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Network");
			Icon = "network-wireless-signal-good;;network-wired;;network-idle";
			Button = PopupButton.RIGHT;

			refresh_network_status ();
			start_timer ();
			start_listeners ();
		}

		~NetworkDockItem ()
		{
			stop_timer ();
			stop_listeners ();
		}

		public override void @delete ()
		{
			stop_timer ();
			stop_listeners ();
			base.@delete ();
		}

		void start_timer ()
		{
			if (timer_id != 0)
				return;
			timer_id = Timeout.add_seconds (4, on_timer_tick);
		}

		void stop_timer ()
		{
			if (timer_id != 0) {
				Source.remove (timer_id);
				timer_id = 0;
			}
		}

		void start_listeners ()
		{
			try {
				var bus = Bus.get_sync (BusType.SYSTEM, null);
				dbus_sub_id = bus.signal_subscribe (
					"org.freedesktop.NetworkManager",
					"org.freedesktop.DBus.Properties",
					"PropertiesChanged",
					null,
					null,
					DBusSignalFlags.NONE,
					on_dbus_signal
				);
			} catch (Error e) { }

			var netmon = NetworkMonitor.get_default ();
			if (netmon != null) {
				netmon_handler_id = netmon.network_changed.connect ((available) => {
					refresh_network_status ();
					reset_icon_buffer ();
				});
			}
		}

		void stop_listeners ()
		{
			if (dbus_sub_id != 0) {
				try {
					var bus = Bus.get_sync (BusType.SYSTEM, null);
					bus.signal_unsubscribe (dbus_sub_id);
				} catch (Error e) { }
				dbus_sub_id = 0;
			}

			if (netmon_handler_id != 0UL) {
				var netmon = NetworkMonitor.get_default ();
				if (netmon != null)
					netmon.disconnect (netmon_handler_id);
				netmon_handler_id = 0UL;
			}
		}

		void on_dbus_signal (DBusConnection conn, string? sender, string path, string iface, string signal, Variant parameters)
		{
			refresh_network_status ();
			reset_icon_buffer ();
		}

		bool on_timer_tick ()
		{
			refresh_network_status ();
			reset_icon_buffer ();
			return true;
		}

		public override bool is_valid ()
		{
			return true;
		}

		void refresh_network_status ()
		{
			bool found_nm = false;

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
					if (spec_path != "" && spec_path != "/") {
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

					is_connected = true;
					connection_name = cid;
					wifi_strength = strength;
					ip_address = ip;
					gateway = gw;

					if (raw_type.contains ("wireless")) {
						connection_type = "wifi";
					} else {
						connection_type = "ethernet";
					}
					found_nm = true;
				}
			} catch { }

			if (!found_nm) {
				var netmon = NetworkMonitor.get_default ();
				if (netmon != null && netmon.get_network_available ()) {
					is_connected = true;
					connection_type = "ethernet";
					connection_name = _("Wired Connection");
				} else {
					is_connected = false;
					connection_type = "none";
					connection_name = "";
					ip_address = "";
					gateway = "";
					wifi_strength = 0;
				}
			}

			// Update Text (tooltip) and Icon
			if (is_connected) {
				if (connection_type == "wifi") {
					if (ip_address != "")
						Text = _("Wi-Fi: %s (%d%%) - %s").printf (connection_name, wifi_strength, ip_address);
					else
						Text = _("Wi-Fi: %s (%d%%)").printf (connection_name, wifi_strength);

					if (wifi_strength >= 80)
						Icon = "network-wireless-signal-excellent;;network-wireless-signal-excellent-symbolic;;network-wireless-connected-100";
					else if (wifi_strength >= 55)
						Icon = "network-wireless-signal-good;;network-wireless-signal-good-symbolic;;network-wireless-connected-75";
					else if (wifi_strength >= 30)
						Icon = "network-wireless-signal-ok;;network-wireless-signal-ok-symbolic;;network-wireless-connected-50";
					else if (wifi_strength >= 10)
						Icon = "network-wireless-signal-weak;;network-wireless-signal-weak-symbolic;;network-wireless-connected-25";
					else
						Icon = "network-wireless-signal-none;;network-wireless-signal-none-symbolic;;network-wireless-disconnected";

					Count = wifi_strength;
					BadgeText = "%d%%".printf (wifi_strength);
					CountVisible = true;
				} else {
					if (ip_address != "")
						Text = _("Ethernet: %s - %s").printf (connection_name != "" ? connection_name : _("Connected"), ip_address);
					else
						Text = _("Ethernet: %s").printf (connection_name != "" ? connection_name : _("Connected"));

					Icon = "network-wired-activated;;network-wired;;network-workgroup";
					BadgeText = null;
					CountVisible = false;
				}
			} else {
				Text = _("Network: Disconnected");
				Icon = "network-offline;;network-idle;;network-error;;network-wired-disconnected";
				BadgeText = null;
				CountVisible = false;
			}
		}

		public void open_network_settings ()
		{
			string[] cmds = {
				"kcmshell6 kcm_networkmanagement",
				"kcmshell5 kcm_networkmanagement",
				"gnome-control-center wifi",
				"gnome-control-center network",
				"nm-connection-editor"
			};

			foreach (var cmd in cmds) {
				try {
					AppInfo.create_from_commandline (cmd, null, AppInfoCreateFlags.NONE).launch (null, null);
					return;
				} catch { }
			}
		}

		public void copy_ip_to_clipboard ()
		{
			if (ip_address != "") {
				var display = Gdk.Display.get_default ();
				if (display != null) {
					var clipboard = Gtk.Clipboard.get_default (display);
					clipboard.set_text (ip_address, -1);
				}
			}
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				open_network_settings ();
				return AnimationType.BOUNCE;
			}
			if (button == PopupButton.MIDDLE) {
				copy_ip_to_clipboard ();
				return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			string header_label;
			if (is_connected) {
				if (connection_type == "wifi")
					header_label = _("Wi-Fi: %s (%d%%)").printf (connection_name, wifi_strength);
				else
					header_label = _("Ethernet: %s").printf (connection_name != "" ? connection_name : _("Connected"));
			} else {
				header_label = _("Network: Disconnected");
			}

			var header_item = new Gtk.MenuItem.with_label (header_label);
			header_item.sensitive = false;
			items.add (header_item);

			if (ip_address != "") {
				var ip_item = new Gtk.MenuItem.with_label (_("IP: %s").printf (ip_address));
				ip_item.sensitive = false;
				items.add (ip_item);
			}

			if (gateway != "") {
				var gw_item = new Gtk.MenuItem.with_label (_("Gateway: %s").printf (gateway));
				gw_item.sensitive = false;
				items.add (gw_item);
			}

			items.add (new Gtk.SeparatorMenuItem ());

			if (ip_address != "") {
				var copy_item = create_menu_item (_("Copy _IP Address"), "edit-copy", true);
				copy_item.activate.connect (copy_ip_to_clipboard);
				items.add (copy_item);
			}

			var settings_item = create_menu_item (_("_Network Settings..."), "preferences-system-network", true);
			settings_item.activate.connect (open_network_settings);
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

