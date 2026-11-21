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
	 * Southbound `/sys/class/power_supply` battery & AC power provider (`IBatteryProvider`).
	 */
	public class LinuxBatteryProvider : GLib.Object, IBatteryProvider
	{
		static LinuxBatteryProvider? default_instance = null;

		public static LinuxBatteryProvider get_default ()
		{
			if (default_instance == null)
				default_instance = new LinuxBatteryProvider ();
			return default_instance;
		}

		string? cached_bat_dir_path = null;
		bool bat_probed = false;

		string? resolve_battery_dir ()
		{
			if (!bat_probed || (cached_bat_dir_path != null && !FileUtils.test (cached_bat_dir_path, FileTest.IS_DIR))) {
				cached_bat_dir_path = null;
				var ps_dir = File.new_for_path ("/sys/class/power_supply");
				try {
					var enumerator = ps_dir.enumerate_children ("standard::name", FileQueryInfoFlags.NONE, null);
					FileInfo? info = null;
					while ((info = enumerator.next_file (null)) != null) {
						var candidate = Path.build_filename ("/sys/class/power_supply", info.get_name ());
						var type_file = Path.build_filename (candidate, "type");
						string type_str;
						if (FileUtils.get_contents (type_file, out type_str) && type_str.strip () == "Battery") {
							cached_bat_dir_path = candidate;
							break;
						}
					}
				} catch (Error e) { }

				if (cached_bat_dir_path == null) {
					for (int i = 0; i <= 3; i++) {
						string test_path = "/sys/class/power_supply/BAT%d".printf (i);
						if (FileUtils.test (test_path, FileTest.IS_DIR)) {
							cached_bat_dir_path = test_path;
							break;
						}
					}
				}
				bat_probed = true;
			}
			return cached_bat_dir_path;
		}

		public bool has_battery ()
		{
			return (resolve_battery_dir () != null);
		}

		public BatteryState query_state ()
		{
			string? bat_dir_path = resolve_battery_dir ();
			if (bat_dir_path == null) {
				return BatteryState () {
					has_battery = false,
					percentage = 100,
					is_charging = false,
					is_full = true,
					raw_status = ""
				};
			}

			int percentage = 100;
			bool is_charging = false;
			bool is_full = false;
			string raw_status = "Unknown";

			string cap_str, stat_str;
			try {
				if (FileUtils.get_contents (Path.build_filename (bat_dir_path, "capacity"), out cap_str)) {
					percentage = int.parse (cap_str.strip ());
					if (percentage < 0) percentage = 0;
					if (percentage > 100) percentage = 100;
				}
			} catch (Error e) { }

			try {
				if (FileUtils.get_contents (Path.build_filename (bat_dir_path, "status"), out stat_str)) {
					raw_status = stat_str.strip ();
					is_charging = (raw_status == "Charging");
					is_full = (raw_status == "Full");
				}
			} catch (Error e) { }

			return BatteryState () {
				has_battery = true,
				percentage = percentage,
				is_charging = is_charging,
				is_full = is_full,
				raw_status = raw_status
			};
		}
	}
}
