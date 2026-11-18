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
	/**
	 * Pure Linux kernel sysfs driver for `/sys/class/backlight` and `/sys/class/drm`
	 * internal-panel probing, hardware reads/writes, and inotify file monitoring.
	 */
	public class LinuxSysfsBacklight : GLib.Object
	{
		private static uint32 get_device_max_brightness (string dev)
		{
			string path = "/sys/class/backlight/%s/max_brightness".printf (dev);
			try {
				string content;
				GLib.FileUtils.get_contents (path, out content);
				int64 val = int64.parse (content.strip ());
				if (val > 0)
					return (uint32) val;
			} catch (GLib.Error e) { }
			return 100;
		}

		public static Gee.ArrayList<string> detect_devices (out string? preferred_device, out uint32 max_raw)
		{
			var devices = new Gee.ArrayList<string> ();
			preferred_device = null;
			max_raw = 100;

			var dir = GLib.File.new_for_path ("/sys/class/backlight");
			try {
				var enumerator = dir.enumerate_children ("standard::name", GLib.FileQueryInfoFlags.NONE);
				GLib.FileInfo? info = null;
				string? preferred_dev = null;
				string? fallback_dev = null;
				while ((info = enumerator.next_file ()) != null) {
					string dev = info.get_name ();
					string max_path = "/sys/class/backlight/%s/max_brightness".printf (dev);
					string cur_path = "/sys/class/backlight/%s/brightness".printf (dev);
					if (GLib.FileUtils.test (max_path, GLib.FileTest.EXISTS) && GLib.FileUtils.test (cur_path, GLib.FileTest.EXISTS)) {
						devices.add (dev);
						if (!dev.has_prefix ("acpi_video")) {
							if (preferred_dev == null)
								preferred_dev = dev;
						} else {
							if (fallback_dev == null)
								fallback_dev = dev;
						}
					}
				}
				preferred_device = (preferred_dev != null) ? preferred_dev : fallback_dev;
				if (preferred_device != null)
					max_raw = get_device_max_brightness (preferred_device);
			} catch (GLib.Error e) {
				preferred_device = null;
			}

			return devices;
		}

		public static bool has_internal_panel (string? backlight_device)
		{
			// 1. Direct hardware backlight device (e.g. amdgpu_bl0, intel_backlight)
			if (backlight_device != null && !backlight_device.has_prefix ("acpi_video")) {
				string dev_enabled_path = "/sys/class/backlight/%s/device/enabled".printf (backlight_device);
				if (GLib.FileUtils.test (dev_enabled_path, GLib.FileTest.EXISTS)) {
					string content;
					try {
						GLib.FileUtils.get_contents (dev_enabled_path, out content);
						if (content.strip () == "disabled") {
							return false; // Clamshell mode with external monitor
						}
					} catch (GLib.Error e) { }
				}
				// Also check drm status for eDP/LVDS
				var drm_dir = GLib.File.new_for_path ("/sys/class/drm");
				try {
					var enumerator = drm_dir.enumerate_children ("standard::name", GLib.FileQueryInfoFlags.NONE);
					GLib.FileInfo? info = null;
					while ((info = enumerator.next_file ()) != null) {
						string name = info.get_name ();
						if (name.contains ("-eDP-") || name.contains ("-LVDS-") || name.contains ("-DSI-")) {
							string enabled_path = "/sys/class/drm/%s/enabled".printf (name);
							if (GLib.FileUtils.test (enabled_path, GLib.FileTest.EXISTS)) {
								string en;
								GLib.FileUtils.get_contents (enabled_path, out en);
								if (en.strip () == "disabled") {
									return false; // Laptop lid closed / clamshell
								}
							}
						}
					}
				} catch (GLib.Error e) { }
				return true;
			}

			// 2. Fallback scan /sys/class/drm for connected and enabled internal panel (eDP, LVDS, DSI)
			var drm_dir = GLib.File.new_for_path ("/sys/class/drm");
			try {
				var enumerator = drm_dir.enumerate_children ("standard::name", GLib.FileQueryInfoFlags.NONE);
				GLib.FileInfo? info = null;
				while ((info = enumerator.next_file ()) != null) {
					string name = info.get_name ();
					if (name.contains ("-eDP-") || name.contains ("-LVDS-") || name.contains ("-DSI-")) {
						string status_path = "/sys/class/drm/%s/status".printf (name);
						string enabled_path = "/sys/class/drm/%s/enabled".printf (name);
						try {
							string status;
							GLib.FileUtils.get_contents (status_path, out status);
							if (status.strip () == "connected") {
								if (GLib.FileUtils.test (enabled_path, GLib.FileTest.EXISTS)) {
									string en;
									GLib.FileUtils.get_contents (enabled_path, out en);
									if (en.strip () == "disabled") {
										continue;
									}
								}
								return true;
							}
						} catch (GLib.Error e) { }
					}
				}
			} catch (GLib.Error e) { }

			return false;
		}

		public static int64 read_raw (string backlight_device)
		{
			string actual_path = "/sys/class/backlight/%s/actual_brightness".printf (backlight_device);
			string cur_path = "/sys/class/backlight/%s/brightness".printf (backlight_device);
			string path = GLib.FileUtils.test (actual_path, GLib.FileTest.EXISTS) ? actual_path : cur_path;
			try {
				string content;
				GLib.FileUtils.get_contents (path, out content);
				return int64.parse (content.strip ());
			} catch (GLib.Error e) {
				return -1;
			}
		}

		public static bool write_raw (string backlight_device, uint32 raw_value)
		{
			string path = "/sys/class/backlight/%s/brightness".printf (backlight_device);
			try {
				GLib.FileUtils.set_contents (path, raw_value.to_string ());
				return true;
			} catch (GLib.Error e) {
				return false;
			}
		}

		public static GLib.FileMonitor? monitor_device (string backlight_device)
		{
			string cur_path = "/sys/class/backlight/%s/brightness".printf (backlight_device);
			try {
				var f = GLib.File.new_for_path (cur_path);
				return f.monitor_file (GLib.FileMonitorFlags.NONE, null);
			} catch (GLib.Error e) {
				return null;
			}
		}
	}
}
