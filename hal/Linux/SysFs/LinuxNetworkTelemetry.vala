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
	 * Southbound Linux `/sys/class/net`, `/proc/net/{route,wireless}` & `getifaddrs(3)`
	 * multi-interface network enumerator with 64-bit RX/TX byte counters and physical vs
	 * virtual classification (`/sys/class/net/<iface>/device`).
	 */
	public class LinuxNetworkTelemetry : GLib.Object
	{
		const uint IFF_UP_FLAG = 0x1;
		const uint IFF_LOOPBACK_FLAG = 0x8;

		static bool is_virtual_name (string iface)
		{
			string low = iface.ascii_down ();
			string[] prefixes = {
				"lo", "docker", "br-", "virbr", "vmnet", "vboxnet", "veth",
				"wg", "tun", "tap", "tailscale", "zt", "cni", "flannel",
				"podman", "lxc", "lxd", "dummy", "sit", "gre", "ip6tnl",
				"nordlynx", "proton", "utun", "ham"
			};
			foreach (unowned string p in prefixes) {
				if (low.has_prefix (p))
					return true;
			}
			return false;
		}

		static uint64 read_sysfs_u64 (string path)
		{
			string content;
			try {
				if (FileUtils.get_contents (path, out content))
					return uint64.parse (content.strip ());
			} catch (Error e) {}
			return 0;
		}

		static string read_sysfs_str (string path)
		{
			string content;
			try {
				if (FileUtils.get_contents (path, out content))
					return content.strip ();
			} catch (Error e) {}
			return "";
		}

		static Gee.HashMap<string, string> read_ipv4_addresses (out Gee.HashSet<string> up_ifaces)
		{
			var ips = new Gee.HashMap<string, string> ();
			up_ifaces = new Gee.HashSet<string> ();

			UnixIfAddrs? ifap = null;
			if (unix_getifaddrs (out ifap) != 0 || ifap == null)
				return ips;

			for (unowned UnixIfAddrs? cur = ifap; cur != null; cur = cur.ifa_next) {
				if (cur.ifa_name == null || (cur.ifa_flags & IFF_LOOPBACK_FLAG) != 0)
					continue;
				if ((cur.ifa_flags & IFF_UP_FLAG) == 0)
					continue;

				up_ifaces.add (cur.ifa_name);

				if (cur.ifa_addr == null || cur.ifa_addr->sa_family != Posix.AF_INET)
					continue;

				if (ips.has_key (cur.ifa_name))
					continue;

				unowned Posix.SockAddrIn* sin = (Posix.SockAddrIn*) cur.ifa_addr;
				uint8[] buf = new uint8[64];
				unowned string? ip = Posix.inet_ntop (Posix.AF_INET, &sin->sin_addr, buf);
				if (ip == null || ip == "" || ip.has_prefix ("127.") || ip.has_prefix ("169.254."))
					continue;

				ips.set (cur.ifa_name, ip);
			}

			return ips;
		}

		static Gee.HashMap<string, string> read_default_gateways ()
		{
			var gws = new Gee.HashMap<string, string> ();
			string content;
			try {
				if (!FileUtils.get_contents ("/proc/net/route", out content))
					return gws;
			} catch (Error e) {
				return gws;
			}

			var lines = content.split ("\n");
			for (int i = 1; i < lines.length; i++) {
				string line = lines[i].strip ();
				if (line == "")
					continue;
				var cols = line.split ("\t");
				if (cols.length < 3)
					continue;
				string iface = cols[0].strip ();
				string dest_hex = cols[1].strip ();
				string gw_hex = cols[2].strip ();
				if (dest_hex != "00000000" || gw_hex == "00000000" || gw_hex.length != 8)
					continue;
				if (gws.has_key (iface))
					continue;

				uint64 val = 0;
				if (!uint64.try_parse ("0x" + gw_hex, out val) || val == 0)
					continue;
				uint b0 = (uint) (val & 0xFF);
				uint b1 = (uint) ((val >> 8) & 0xFF);
				uint b2 = (uint) ((val >> 16) & 0xFF);
				uint b3 = (uint) ((val >> 24) & 0xFF);
				gws.set (iface, "%u.%u.%u.%u".printf (b0, b1, b2, b3));
			}
			return gws;
		}

		static Gee.HashMap<string, int> read_wifi_strengths ()
		{
			var map = new Gee.HashMap<string, int> ();
			string content;
			try {
				if (!FileUtils.get_contents ("/proc/net/wireless", out content))
					return map;
			} catch (Error e) {
				return map;
			}

			var lines = content.split ("\n");
			for (int i = 2; i < lines.length; i++) {
				string line = lines[i].strip ();
				int colon = line.index_of_char (':');
				if (colon <= 0)
					continue;
				string iface = line.substring (0, colon).strip ();
				string rest = line.substring (colon + 1).strip ();
				var parts = rest.split (" ");
				int col = 0;
				for (int j = 0; j < parts.length; j++) {
					string tok = parts[j].strip ();
					if (tok == "")
						continue;
					if (col == 1) {
						double raw = double.parse (tok.replace (".", ""));
						/* /proc/net/wireless link quality is typically 0..70 */
						int pct = (int) Math.round ((raw <= 70.0) ? (raw * 100.0 / 70.0) : raw);
						if (pct < 0) pct = 0;
						if (pct > 100) pct = 100;
						map.set (iface, pct);
						break;
					}
					col++;
				}
			}
			return map;
		}

		public static Gee.ArrayList<NetworkInterfaceInfo> list_interfaces ()
		{
			var list = new Gee.ArrayList<NetworkInterfaceInfo> ();

			Gee.HashSet<string> up_ifaces;
			var ips = read_ipv4_addresses (out up_ifaces);
			var gws = read_default_gateways ();
			var wifi_sig = read_wifi_strengths ();

			Dir? dir = null;
			try {
				dir = Dir.open ("/sys/class/net", 0);
			} catch (Error e) {
				return list;
			}

			var names = new Gee.ArrayList<string> ();
			unowned string? entry;
			while ((entry = dir.read_name ()) != null) {
				if (entry == "lo")
					continue;
				names.add (entry);
			}
			names.sort ();

			foreach (string iface in names) {
				string base_dir = "/sys/class/net/" + iface;
				string operstate = read_sysfs_str (base_dir + "/operstate");
				string ip = ips.has_key (iface) ? ips.get (iface) : "";
				bool is_up = (operstate == "up")
					|| (operstate == "unknown" && ip != "" && up_ifaces.contains (iface));

				if (!is_up || ip == "")
					continue;

				bool is_wifi = FileUtils.test (base_dir + "/wireless", FileTest.IS_DIR)
					|| FileUtils.test (base_dir + "/phy80211", FileTest.EXISTS);
				bool has_hw_device = FileUtils.test (base_dir + "/device", FileTest.EXISTS);
				bool is_virtual = !is_wifi && (!has_hw_device || is_virtual_name (iface));

				var info = new NetworkInterfaceInfo ();
				info.iface_id = iface;
				info.display_name = iface;
				info.kind = is_wifi ? "wifi" : (is_virtual ? "virtual" : "ethernet");
				info.wifi_strength = (is_wifi && wifi_sig.has_key (iface)) ? wifi_sig.get (iface) : 0;
				info.ip_address = ip;
				info.gateway = gws.has_key (iface) ? gws.get (iface) : "";
				info.rx_bytes = read_sysfs_u64 (base_dir + "/statistics/rx_bytes");
				info.tx_bytes = read_sysfs_u64 (base_dir + "/statistics/tx_bytes");
				list.add (info);
			}

			return list;
		}
	}
}
