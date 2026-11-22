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
	 * Agnostic session & power management provider (`SessionDockItem` & `SessionWindow`).
	 */
	public interface ISessionPowerProvider : GLib.Object
	{
		public abstract void get_session_user_and_host (out string user, out string host);
		public abstract bool can_hibernate ();
		public abstract bool can_hybrid_sleep ();
		public abstract bool can_reboot_to_firmware ();
		public abstract void lock_screen ();
		public abstract void switch_user ();
		public abstract void suspend ();
		public abstract void hibernate ();
		public abstract void hybrid_sleep ();
		public abstract void reboot_to_firmware ();
		public abstract void logout ();
		public abstract void restart ();
		public abstract void shutdown ();
	}

	public struct BatteryState
	{
		public bool has_battery;
		public int percentage;
		public bool is_charging;
		public bool is_full;
		public string raw_status;
	}

	/**
	 * Agnostic battery & AC power telemetry provider (`BatteryDockItem`).
	 */
	public interface IBatteryProvider : GLib.Object
	{
		public abstract BatteryState query_state ();
		public abstract bool has_battery ();
	}

	/**
	 * Agnostic display backlight & external monitor brightness provider (`BrightnessDockItem`).
	 */
	public interface IBrightnessProvider : GLib.Object
	{
		public signal void brightness_changed (int percent);
		public abstract bool is_available ();
		public abstract int get_percent ();
		public abstract void set_percent (int percent, bool immediate = false);
		public abstract void adjust_percent (int delta);
		public abstract void cleanup ();
	}

	public struct CpuMemDiskSample
	{
		public int cpu_pct;
		public int ram_pct;
		public int io_pct;
		public int system_pressure;
		public double ram_used_gb;
		public double ram_total_gb;
	}

	/**
	 * Agnostic CPU, RAM, and Disk I/O telemetry sampler (`CpuDockItem`).
	 */
	public interface ICpuMemoryProvider : GLib.Object
	{
		public abstract CpuMemDiskSample sample ();
	}

	public struct NetworkState
	{
		public bool is_connected;
		public string connection_type;
		public string connection_name;
		public int wifi_strength;
		public string ip_address;
		public string gateway;
	}

	/**
	 * Normalized active network interface snapshot with 64-bit byte counters
	 * for multi-interface priority selection and live throughput telemetry.
	 */
	public class NetworkInterfaceInfo : GLib.Object
	{
		public string iface_id = "";
		public string display_name = "";
		/** One of "wifi", "ethernet", or "virtual". */
		public string kind = "ethernet";
		public int wifi_strength = 0;
		public string ip_address = "";
		public string gateway = "";
		public uint64 rx_bytes = 0;
		public uint64 tx_bytes = 0;
	}

	/**
	 * Agnostic network connectivity & Wi-Fi strength provider (`NetworkDockItem`).
	 */
	public interface INetworkProvider : GLib.Object
	{
		public signal void network_changed ();
		public abstract NetworkState probe_state_sync ();
		public abstract Gee.ArrayList<NetworkInterfaceInfo> list_interfaces_sync ();
		public abstract void cleanup ();
	}

	public struct AudioState
	{
		public bool ok;
		public int volume_percent;
		public bool is_muted;
	}

	/**
	 * Agnostic system audio sink volume & mute provider (`VolumeDockItem`).
	 */
	public interface IAudioProvider : GLib.Object
	{
		public abstract AudioState probe_state_sync ();
		public abstract void set_muted (bool muted);
		public abstract void toggle_mute (bool target_muted_fallback);
		public abstract void set_volume_percent (int percent);
	}

	public class RemovableDriveInfo : GLib.Object
	{
		public string id = "";
		public string display_name = "";
		public string icon_name = "media-eject";
	}

	public delegate void DriveEjectCallback (bool success, string drive_name, string error_message);

	/**
	 * Agnostic removable storage monitor & safe-eject provider (`EjectorDockItem`).
	 */
	public interface IEjectorProvider : GLib.Object
	{
		public signal void drives_changed ();
		public abstract Gee.ArrayList<RemovableDriveInfo> get_removable_drives ();
		public abstract void eject_drive (string id, owned DriveEjectCallback? callback = null);
		public abstract void eject_all (owned DriveEjectCallback? per_drive_callback = null);
		public abstract void cleanup ();
	}

	/**
	 * Agnostic screen, window, and region capture provider (`ScreenshotDockItem`).
	 */
	public interface IScreenshotProvider : GLib.Object
	{
		public abstract void capture_interactive_region ();
		public abstract void capture_full_screen ();
		public abstract void capture_active_window ();
		public abstract void open_screenshots_folder ();
	}

	public class TrashItemInfo : GLib.Object
	{
		public string id = "";
		public string display_name = "";
		public string original_path = "";
		public string deletion_date = "";
		public bool is_directory = false;
	}

	/**
	 * Agnostic Trash / Recycle Bin provider (`TrashDockItem`).
	 */
	public interface ITrashProvider : GLib.Object
	{
		public signal void trash_changed ();
		public abstract uint get_item_count ();
		public abstract Gee.ArrayList<TrashItemInfo> list_items ();
		public abstract bool move_uri_to_trash (string uri);
		public abstract bool restore_item (string id);
		public abstract bool delete_item_permanently (string id);
		public abstract bool empty_trash ();
		public abstract void open_trash_ui ();
		public abstract void cleanup ();
	}

	/**
	 * Aggregate northbound hardware, storage & session telemetry contract (`Hal.Telemetry`).
	 */
	public interface ISystemTelemetry : GLib.Object
	{
		public abstract ISessionPowerProvider SessionPower { get; }
		public abstract IBatteryProvider Battery { get; }
		public abstract IBrightnessProvider Brightness { get; }
		public abstract ICpuMemoryProvider CpuMemory { get; }
		public abstract INetworkProvider Network { get; }
		public abstract IAudioProvider Audio { get; }
		public abstract IEjectorProvider Ejector { get; }
		public abstract IScreenshotProvider Screenshot { get; }
		public abstract ITrashProvider Trash { get; }
		public abstract void cleanup ();
	}

	internal class NullSessionPowerProvider : GLib.Object, ISessionPowerProvider
	{
		public void get_session_user_and_host (out string user, out string host)
		{
			user = "";
			host = "";
		}
		public bool can_hibernate () { return false; }
		public bool can_hybrid_sleep () { return false; }
		public bool can_reboot_to_firmware () { return false; }
		public void lock_screen () {}
		public void switch_user () {}
		public void suspend () {}
		public void hibernate () {}
		public void hybrid_sleep () {}
		public void reboot_to_firmware () {}
		public void logout () {}
		public void restart () {}
		public void shutdown () {}
	}

	internal class NullBatteryProvider : GLib.Object, IBatteryProvider
	{
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
		public bool has_battery () { return false; }
	}

	internal class NullBrightnessProvider : GLib.Object, IBrightnessProvider
	{
		public bool is_available () { return false; }
		public int get_percent () { return 100; }
		public void set_percent (int percent, bool immediate = false) {}
		public void adjust_percent (int delta) {}
		public void cleanup () {}
	}

	internal class NullCpuMemoryProvider : GLib.Object, ICpuMemoryProvider
	{
		public CpuMemDiskSample sample ()
		{
			return CpuMemDiskSample ();
		}
	}

	internal class NullNetworkProvider : GLib.Object, INetworkProvider
	{
		public NetworkState probe_state_sync ()
		{
			return NetworkState () {
				is_connected = false,
				connection_type = "none",
				connection_name = "",
				wifi_strength = 0,
				ip_address = "",
				gateway = ""
			};
		}

		public Gee.ArrayList<NetworkInterfaceInfo> list_interfaces_sync ()
		{
			return new Gee.ArrayList<NetworkInterfaceInfo> ();
		}

		public void cleanup () {}
	}

	internal class NullAudioProvider : GLib.Object, IAudioProvider
	{
		public AudioState probe_state_sync ()
		{
			return AudioState () { ok = false, volume_percent = 70, is_muted = false };
		}
		public void set_muted (bool muted) {}
		public void toggle_mute (bool target_muted_fallback) {}
		public void set_volume_percent (int percent) {}
	}

	internal class NullEjectorProvider : GLib.Object, IEjectorProvider
	{
		public Gee.ArrayList<RemovableDriveInfo> get_removable_drives ()
		{
			return new Gee.ArrayList<RemovableDriveInfo> ();
		}
		public void eject_drive (string id, owned DriveEjectCallback? callback = null)
		{
			if (callback != null)
				callback (false, id, _("Drive not available"));
		}
		public void eject_all (owned DriveEjectCallback? per_drive_callback = null) {}
		public void cleanup () {}
	}

	internal class NullScreenshotProvider : GLib.Object, IScreenshotProvider
	{
		public void capture_interactive_region () {}
		public void capture_full_screen () {}
		public void capture_active_window () {}
		public void open_screenshots_folder () {}
	}

	internal class NullTrashProvider : GLib.Object, ITrashProvider
	{
		public uint get_item_count () { return 0; }
		public Gee.ArrayList<TrashItemInfo> list_items ()
		{
			return new Gee.ArrayList<TrashItemInfo> ();
		}
		public bool move_uri_to_trash (string uri) { return false; }
		public bool restore_item (string id) { return false; }
		public bool delete_item_permanently (string id) { return false; }
		public bool empty_trash () { return false; }
		public void open_trash_ui () {}
		public void cleanup () {}
	}

	internal class NullSystemTelemetry : GLib.Object, ISystemTelemetry
	{
		ISessionPowerProvider session_power = new NullSessionPowerProvider ();
		IBatteryProvider battery = new NullBatteryProvider ();
		IBrightnessProvider brightness = new NullBrightnessProvider ();
		ICpuMemoryProvider cpu_memory = new NullCpuMemoryProvider ();
		INetworkProvider network = new NullNetworkProvider ();
		IAudioProvider audio = new NullAudioProvider ();
		IEjectorProvider ejector = new NullEjectorProvider ();
		IScreenshotProvider screenshot = new NullScreenshotProvider ();
		ITrashProvider trash = new NullTrashProvider ();

		public ISessionPowerProvider SessionPower { get { return session_power; } }
		public IBatteryProvider Battery { get { return battery; } }
		public IBrightnessProvider Brightness { get { return brightness; } }
		public ICpuMemoryProvider CpuMemory { get { return cpu_memory; } }
		public INetworkProvider Network { get { return network; } }
		public IAudioProvider Audio { get { return audio; } }
		public IEjectorProvider Ejector { get { return ejector; } }
		public IScreenshotProvider Screenshot { get { return screenshot; } }
		public ITrashProvider Trash { get { return trash; } }
		public void cleanup () {}
	}
}
