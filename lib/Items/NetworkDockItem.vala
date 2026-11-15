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
		uint signal_debounce_id = 0;
		ulong net_changed_id = 0UL;
		bool is_disposed = false;
		bool poll_in_flight = false;

		bool is_connected = false;
		string connection_type = "none";
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

			notify["IsAttached"].connect (on_attached_changed);
			schedule_network_poll ();
			start_timer ();
			start_listeners ();
		}

		private bool cleaned_up = false;

		~NetworkDockItem ()
		{
			is_disposed = true;
			if (!cleaned_up) {
				cleaned_up = true;
				notify["IsAttached"].disconnect (on_attached_changed);
			}
			stop_timer ();
			stop_listeners ();
		}

		public override void cleanup ()
		{
			is_disposed = true;
			if (!cleaned_up) {
				cleaned_up = true;
				notify["IsAttached"].disconnect (on_attached_changed);
			}
			stop_timer ();
			stop_listeners ();
			base.cleanup ();
		}

		void on_attached_changed ()
		{
			if (IsAttached)
				schedule_network_poll ();
		}

		public override void @delete ()
		{
			is_disposed = true;
			stop_timer ();
			stop_listeners ();
			base.@delete ();
		}

		void start_timer ()
		{
			if (timer_id != 0)
				return;
			timer_id = Timeout.add_seconds (15, on_timer_tick);
		}

		void stop_timer ()
		{
			if (timer_id != 0) {
				Source.remove (timer_id);
				timer_id = 0;
			}
			if (signal_debounce_id != 0) {
				Source.remove (signal_debounce_id);
				signal_debounce_id = 0;
			}
		}

		void start_listeners ()
		{
			net_changed_id = Hal.Telemetry.Network.network_changed.connect (on_network_event);
		}

		void stop_listeners ()
		{
			if (net_changed_id != 0UL) {
				Hal.Telemetry.Network.disconnect (net_changed_id);
				net_changed_id = 0UL;
			}
		}

		void on_network_event ()
		{
			if (is_disposed || !IsAttached || signal_debounce_id != 0)
				return;
			signal_debounce_id = Timeout.add (300, () => {
				signal_debounce_id = 0;
				if (!is_disposed && IsAttached)
					schedule_network_poll ();
				return false;
			});
		}

		bool on_timer_tick ()
		{
			if (!IsAttached)
				return true;
			schedule_network_poll ();
			return true;
		}

		public override bool is_valid ()
		{
			return true;
		}

		void apply_network_status (NetworkState st)
		{
			is_connected = st.is_connected;
			connection_type = st.connection_type;
			connection_name = (st.connection_name == "" && st.is_connected && st.connection_type == "ethernet")
				? _("Wired Connection")
				: st.connection_name;
			wifi_strength = st.wifi_strength;
			ip_address = st.ip_address;
			gateway = st.gateway;

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

					Count = 1;
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

		private static void spawn_network_poll_worker (NetworkDockItem target)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-network-poll", () => {
				NetworkState st = Hal.Telemetry.Network.probe_state_sync ();
				Idle.add (() => {
					var self = (NetworkDockItem?) self_ref.get ();
					if (self == null)
						return false;
					self.poll_in_flight = false;
					if (self.is_disposed)
						return false;
					self.apply_network_status (st);
					return false;
				});
				return null;
			});
		}

		void schedule_network_poll ()
		{
			if (is_disposed || poll_in_flight)
				return;
			poll_in_flight = true;

			spawn_network_poll_worker (this);
		}

		public void open_network_settings ()
		{
			Hal.Runtime.open_system_utility (DesktopUtilityKind.NETWORK_SETTINGS);
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
