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
	 * Southbound FreeBSD ACPI battery provider.
	 * Milestone B1 skeleton; full `sysctl hw.acpi.battery.*` implementation arrives in Milestone B3.
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
			return false;
		}

		public BatteryState query_state ()
		{
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
