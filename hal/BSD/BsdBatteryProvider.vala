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
	 * Southbound FreeBSD ACPI battery provider backed by `sysctl(3)`
	 * (`hw.acpi.battery.*` and `hw.acpi.acline`).
	 */
	public class BsdBatteryProvider : GLib.Object, IBatteryProvider
	{
		static BsdBatteryProvider? instance = null;

		public static BsdBatteryProvider get_default ()
		{
			if (instance == null)
				instance = new BsdBatteryProvider ();
			return instance;
		}

		public bool has_battery ()
		{
			bool present = false;
			int pct = 100;
			bool charging = false;
			bool full = true;
			string raw = "";
			if (BsdKernelBridge.read_battery (out present, out pct, out charging, out full, out raw))
				return present;
			return false;
		}

		public BatteryState query_state ()
		{
			bool present = false;
			int pct = 100;
			bool charging = false;
			bool full = true;
			string raw = "";
			if (BsdKernelBridge.read_battery (out present, out pct, out charging, out full, out raw)) {
				return BatteryState () {
					has_battery = present,
					percentage = pct.clamp (0, 100),
					is_charging = charging,
					is_full = full,
					raw_status = raw ?? ""
				};
			}

			return BatteryState () {
				has_battery = false,
				percentage = 100,
				is_charging = false,
				is_full = true,
				raw_status = ""
			};
		}
	}
}
