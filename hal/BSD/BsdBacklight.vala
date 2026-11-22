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
	 * Southbound FreeBSD hardware backlight helper backed by native
	 * `/dev/backlight/*` ioctls and `hw.acpi.video.*` / `hw.acpi.lid_switch_state`.
	 */
	public class BsdBacklight : GLib.Object
	{
		public static Gee.ArrayList<string> detect_devices (out string? preferred_device, out uint32 max_raw)
		{
			var list = new Gee.ArrayList<string> ();
			preferred_device = null;
			max_raw = 100;

			string? pref = null;
			uint32 mraw = 100;
			string[]? devs = BsdKernelBridge.backlight_list_devices (out pref, out mraw);
			if (devs != null) {
				foreach (unowned string d in devs) {
					if (d != "")
						list.add (d);
				}
			}
			preferred_device = pref;
			max_raw = mraw > 0 ? mraw : 100;
			return list;
		}

		public static bool has_internal_panel (string? backlight_device)
		{
			if (backlight_device == null || backlight_device == "")
				return false;
			return BsdKernelBridge.backlight_lid_is_open ();
		}

		public static int64 read_raw (string backlight_device)
		{
			return BsdKernelBridge.backlight_read_raw (backlight_device);
		}

		public static bool write_raw (string backlight_device, uint32 raw_value)
		{
			return BsdKernelBridge.backlight_write_raw (backlight_device, raw_value);
		}

		public static GLib.FileMonitor? monitor_device (string backlight_device)
		{
			return null;
		}
	}
}
