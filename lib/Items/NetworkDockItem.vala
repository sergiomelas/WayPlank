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
	public class NetworkDockItem : DockItem
	{
		class LiveNetRow : GLib.Object
		{
			public string iface_id;
			public GLib.WeakRef label_ref;
			public GLib.WeakRef image_ref;

			public LiveNetRow (string id, Gtk.Label label, Gtk.Image? image)
			{
				iface_id = id;
				label_ref = GLib.WeakRef (label);
				image_ref = GLib.WeakRef (image);
			}
		}

		uint timer_id = 0;
		uint signal_debounce_id = 0;
		uint menu_live_timer_id = 0;
		ulong net_changed_id = 0UL;
		bool is_disposed = false;
		bool poll_in_flight = false;

		bool is_connected = false;
		string connection_type = "none";
		string connection_name = "";
		int wifi_strength = 0;
		string ip_address = "";
		string gateway = "";

		Gee.ArrayList<NetworkInterfaceInfo> interfaces = new Gee.ArrayList<NetworkInterfaceInfo> ();
		Gee.HashMap<string, uint64?> prev_rx_bytes = new Gee.HashMap<string, uint64?> ();
		Gee.HashMap<string, uint64?> prev_tx_bytes = new Gee.HashMap<string, uint64?> ();
		Gee.HashMap<string, double?> rx_bps_map = new Gee.HashMap<string, double?> ();
		Gee.HashMap<string, double?> tx_bps_map = new Gee.HashMap<string, double?> ();
		int64 prev_sample_us = 0;
		Gee.ArrayList<LiveNetRow> live_menu_rows = new Gee.ArrayList<LiveNetRow> ();

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
			Icon = "network-wireless-signal-good;;network-wireless-80;;network-wired;;network-idle";
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
			stop_live_menu_timer ();
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
			stop_live_menu_timer ();
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
			stop_live_menu_timer ();
			stop_listeners ();
			base.@delete ();
		}

		void start_timer ()
		{
			if (timer_id != 0)
				return;
			timer_id = Timeout.add_seconds (5, on_timer_tick);
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

		void start_live_menu_timer ()
		{
			if (is_disposed)
				return;
			schedule_network_poll ();
			if (menu_live_timer_id != 0)
				return;
			menu_live_timer_id = Timeout.add_seconds (1, on_live_menu_tick);
		}

		void stop_live_menu_timer ()
		{
			if (menu_live_timer_id != 0) {
				Source.remove (menu_live_timer_id);
				menu_live_timer_id = 0;
			}
			live_menu_rows.clear ();
		}

		bool on_live_menu_tick ()
		{
			if (is_disposed || live_menu_rows.size == 0) {
				menu_live_timer_id = 0;
				return Source.REMOVE;
			}
			schedule_network_poll ();
			return Source.CONTINUE;
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

		static int kind_rank (string kind)
		{
			if (kind == "wifi") return 0;
			if (kind == "ethernet") return 1;
			return 2;
		}

		static string wifi_icon_for_strength (int strength)
		{
			if (strength >= 85)
				return "network-wireless-signal-excellent;;network-wireless-100;;network-wireless-signal-excellent-symbolic;;network-wireless-connected-100";
			if (strength >= 60)
				return "network-wireless-signal-good;;network-wireless-80;;network-wireless-signal-good-symbolic;;network-wireless-connected-75";
			if (strength >= 35)
				return "network-wireless-signal-ok;;network-wireless-60;;network-wireless-signal-ok-symbolic;;network-wireless-connected-50";
			if (strength >= 10)
				return "network-wireless-signal-weak;;network-wireless-40;;network-wireless-20;;network-wireless-signal-weak-symbolic;;network-wireless-connected-25";
			return "network-wireless-signal-none;;network-wireless-0;;network-wireless-signal-none-symbolic";
		}

		static string icon_for_interface (NetworkInterfaceInfo info)
		{
			if (info.kind == "wifi")
				return wifi_icon_for_strength (info.wifi_strength);
			if (info.kind == "virtual")
				return "network-virtual;;network-vpn;;network-workgroup";
			return "network-wired-activated;;network-wired;;network-workgroup";
		}

		static string format_rate (double bps)
		{
			if (bps < 0.0)
				bps = 0.0;
			if (bps < 1024.0)
				return "%.0f B/s".printf (bps);
			if (bps < 1024.0 * 1024.0)
				return "%.1f KB/s".printf (bps / 1024.0);
			if (bps < 1024.0 * 1024.0 * 1024.0)
				return "%.2f MB/s".printf (bps / (1024.0 * 1024.0));
			return "%.2f GB/s".printf (bps / (1024.0 * 1024.0 * 1024.0));
		}

		string format_interface_row (NetworkInterfaceInfo info)
		{
			string title;
			if (info.kind == "wifi") {
				string n = (info.display_name != "") ? info.display_name : info.iface_id;
				title = _("Wi-Fi: %s (%d%%)").printf (n, info.wifi_strength);
			} else if (info.kind == "virtual") {
				string n = (info.display_name != "") ? info.display_name : info.iface_id;
				title = _("Virtual: %s").printf (n);
			} else {
				string n = (info.display_name != "") ? info.display_name : _("Connected");
				title = _("Ethernet: %s").printf (n);
			}

			double rx = rx_bps_map.has_key (info.iface_id) ? rx_bps_map.get (info.iface_id) : 0.0;
			double tx = tx_bps_map.has_key (info.iface_id) ? tx_bps_map.get (info.iface_id) : 0.0;
			string traffic = "↓ %s  ↑ %s".printf (format_rate (rx), format_rate (tx));

			if (info.ip_address != "")
				return "%s  •  %s  •  %s".printf (title, info.ip_address, traffic);
			return "%s  •  %s".printf (title, traffic);
		}

		void update_live_menu_rows ()
		{
			if (live_menu_rows.size == 0)
				return;

			var by_id = new Gee.HashMap<string, NetworkInterfaceInfo> ();
			foreach (var info in interfaces)
				by_id.set (info.iface_id, info);

			int w = 16, h = 16;
			Gtk.icon_size_lookup (Gtk.IconSize.MENU, out w, out h);

			for (int i = live_menu_rows.size - 1; i >= 0; i--) {
				var row = live_menu_rows.get (i);
				var label = (Gtk.Label?) row.label_ref.get ();
				if (label == null) {
					live_menu_rows.remove_at (i);
					continue;
				}
				if (by_id.has_key (row.iface_id)) {
					var info = by_id.get (row.iface_id);
					label.set_text (format_interface_row (info));
					var img = (Gtk.Image?) row.image_ref.get ();
					if (img != null && info.kind == "wifi") {
						var pix = DrawingService.load_icon (icon_for_interface (info), w, h);
						if (pix != null)
							img.set_from_pixbuf (pix);
					}
				}
			}

			if (live_menu_rows.size == 0)
				stop_live_menu_timer ();
		}

		void apply_network_snapshot (Gee.ArrayList<NetworkInterfaceInfo> list, NetworkState fallback_st, int64 now_us)
		{
			/* Ensure strict priority order: 1. Wi-Fi -> 2. Physical Ethernet -> 3. Virtual */
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

			/* Compute live RX/TX throughput (bytes/sec) from monotonic 64-bit byte deltas */
			double dt_sec = (prev_sample_us > 0 && now_us > prev_sample_us)
				? ((double) (now_us - prev_sample_us) / 1000000.0)
				: 0.0;

			var next_rx = new Gee.HashMap<string, uint64?> ();
			var next_tx = new Gee.HashMap<string, uint64?> ();

			foreach (var info in list) {
				double rx_rate = 0.0;
				double tx_rate = 0.0;
				if (dt_sec >= 0.2 && prev_rx_bytes.has_key (info.iface_id) && prev_tx_bytes.has_key (info.iface_id)) {
					uint64 old_rx = prev_rx_bytes.get (info.iface_id);
					uint64 old_tx = prev_tx_bytes.get (info.iface_id);
					if (info.rx_bytes >= old_rx)
						rx_rate = (double) (info.rx_bytes - old_rx) / dt_sec;
					if (info.tx_bytes >= old_tx)
						tx_rate = (double) (info.tx_bytes - old_tx) / dt_sec;
				}
				next_rx.set (info.iface_id, info.rx_bytes);
				next_tx.set (info.iface_id, info.tx_bytes);
				rx_bps_map.set (info.iface_id, rx_rate);
				tx_bps_map.set (info.iface_id, tx_rate);
			}

			prev_rx_bytes = next_rx;
			prev_tx_bytes = next_tx;
			prev_sample_us = now_us;
			interfaces = list;

			if (list.size > 0) {
				var top = list.get (0);
				is_connected = true;
				connection_type = top.kind;
				connection_name = (top.display_name == "" && top.kind == "ethernet")
					? _("Wired Connection")
					: top.display_name;
				wifi_strength = top.wifi_strength;
				ip_address = top.ip_address;
				gateway = top.gateway;
			} else {
				is_connected = fallback_st.is_connected;
				connection_type = fallback_st.connection_type;
				connection_name = (fallback_st.connection_name == "" && fallback_st.is_connected && fallback_st.connection_type == "ethernet")
					? _("Wired Connection")
					: fallback_st.connection_name;
				wifi_strength = fallback_st.wifi_strength;
				ip_address = fallback_st.ip_address;
				gateway = fallback_st.gateway;
			}

			if (is_connected) {
				if (connection_type == "wifi") {
					if (ip_address != "")
						Text = _("Wi-Fi: %s (%d%%) - %s").printf (connection_name, wifi_strength, ip_address);
					else
						Text = _("Wi-Fi: %s (%d%%)").printf (connection_name, wifi_strength);

					Icon = wifi_icon_for_strength (wifi_strength);
					Count = 1;
					BadgeText = "%d%%".printf (wifi_strength);
					CountVisible = true;
				} else if (connection_type == "virtual") {
					if (ip_address != "")
						Text = _("Virtual: %s - %s").printf (connection_name != "" ? connection_name : _("Connected"), ip_address);
					else
						Text = _("Virtual: %s").printf (connection_name != "" ? connection_name : _("Connected"));

					Icon = "network-virtual;;network-vpn;;network-workgroup";
					BadgeText = null;
					CountVisible = false;
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

			update_live_menu_rows ();
		}

		private static void spawn_network_poll_worker (NetworkDockItem target)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-network-poll", () => {
				var list = Hal.Telemetry.Network.list_interfaces_sync ();
				NetworkState fallback_st = NetworkState () {
					is_connected = false,
					connection_type = "none",
					connection_name = "",
					wifi_strength = 0,
					ip_address = "",
					gateway = ""
				};
				if (list.size == 0)
					fallback_st = Hal.Telemetry.Network.probe_state_sync ();
				int64 now_us = get_monotonic_time ();

				Idle.add (() => {
					var self = (NetworkDockItem?) self_ref.get ();
					if (self == null)
						return false;
					self.poll_in_flight = false;
					if (self.is_disposed)
						return false;
					self.apply_network_snapshot (list, fallback_st, now_us);
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

		void copy_text_to_clipboard (string text)
		{
			if (text == "")
				return;
			var display = Gdk.Display.get_default ();
			if (display != null) {
				var clipboard = Gtk.Clipboard.get_default (display);
				clipboard.set_text (text, -1);
			}
		}

		public void copy_ip_to_clipboard ()
		{
			var sb = new StringBuilder ();
			foreach (var info in interfaces) {
				if (info.ip_address == "")
					continue;
				string name = (info.display_name != "") ? info.display_name : info.iface_id;
				if (sb.len > 0)
					sb.append_c ('\n');
				if (name != "")
					sb.append_printf ("%s: %s", name, info.ip_address);
				else
					sb.append (info.ip_address);
			}

			if (sb.len > 0) {
				copy_text_to_clipboard (sb.str);
			} else if (ip_address != "") {
				string name = (connection_name != "") ? connection_name : _("Network");
				copy_text_to_clipboard ("%s: %s".printf (name, ip_address));
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

		Gtk.MenuItem create_live_interface_menu_item (NetworkInterfaceInfo info, out Gtk.Label out_label, out Gtk.Image out_image)
		{
			int w = 16, h = 16;
			Gtk.icon_size_lookup (Gtk.IconSize.MENU, out w, out h);

			var pix = DrawingService.load_icon (icon_for_interface (info), w, h);
			var img = (pix != null) ? new Gtk.Image.from_pixbuf (pix) : new Gtk.Image ();
			var lbl = new Gtk.Label (format_interface_row (info));
			lbl.xalign = 0.0f;

			var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			box.pack_start (img, false, false, 0);
			box.pack_start (lbl, true, true, 0);

			var mi = new Gtk.MenuItem ();
			mi.add (box);

			if (info.ip_address != "") {
				string ip_copy = info.ip_address;
				mi.activate.connect (() => {
					copy_text_to_clipboard (ip_copy);
				});
				if (info.gateway != "")
					mi.tooltip_text = "%s (%s: %s)".printf (_("Click to copy IP address"), _("Gateway"), info.gateway);
				else
					mi.tooltip_text = _("Click to copy IP address");
			} else {
				mi.sensitive = false;
			}

			out_label = lbl;
			out_image = img;
			return mi;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			stop_live_menu_timer ();

			if (interfaces.size > 0) {
				bool hooked_lifecycle = false;
				foreach (var info in interfaces) {
					Gtk.Label lbl;
					Gtk.Image img;
					var row_item = create_live_interface_menu_item (info, out lbl, out img);
					live_menu_rows.add (new LiveNetRow (info.iface_id, lbl, img));

					if (!hooked_lifecycle) {
						hooked_lifecycle = true;
						row_item.map.connect (start_live_menu_timer);
						row_item.unmap.connect (stop_live_menu_timer);
						row_item.destroy.connect (stop_live_menu_timer);
					}
					items.add (row_item);
				}

				if (gateway != "") {
					var gw_item = new Gtk.MenuItem.with_label (_("Gateway: %s").printf (gateway));
					gw_item.sensitive = false;
					items.add (gw_item);
				}
			} else {
				string header_label;
				if (is_connected) {
					if (connection_type == "wifi")
						header_label = _("Wi-Fi: %s (%d%%)").printf (connection_name, wifi_strength);
					else if (connection_type == "virtual")
						header_label = _("Virtual: %s").printf (connection_name != "" ? connection_name : _("Connected"));
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
