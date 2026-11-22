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
	 * Southbound FreeBSD hardware backlight helper.
	 * Milestone B1 skeleton; full `<sys/backlight.h>` ioctl + `hw.acpi.video.*` implementation arrives in Milestone B3.
	 */
	public class BsdBacklight : GLib.Object
	{
		public static Gee.ArrayList<string> detect_devices (out string? preferred_device, out uint32 max_raw)
		{
			preferred_device = null;
			max_raw = 0;
			return new Gee.ArrayList<string> ();
		}

		public static bool has_internal_panel (string? backlight_device)
		{
			return false;
		}

		public static int64 read_raw (string backlight_device)
		{
			return -1;
		}

		public static bool write_raw (string backlight_device, uint32 raw_value)
		{
			return false;
		}

		public static GLib.FileMonitor? monitor_device (string backlight_device)
		{
			return null;
		}
	}
}
