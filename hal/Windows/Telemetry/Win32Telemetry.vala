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
	class Win32SessionPowerProvider : GLib.Object, ISessionPowerProvider
	{
		public void get_session_user_and_host (out string user, out string host)
		{
			string? u = null;
			string? h = null;
			Win32SysBridge.get_user_and_host (out u, out h);
			user = u ?? Environment.get_user_name ();
			host = h ?? Environment.get_host_name ();
		}

		public bool can_hibernate () { return true; }
		public bool can_hybrid_sleep () { return true; }
		public bool can_reboot_to_firmware () { return true; }

		public void lock_screen ()
		{
			Win32SysBridge.lock_workstation ();
		}

		public void switch_user ()
		{
			Win32AppBridge.shell_execute ("tsdiscon.exe", null, null);
		}

		public void suspend ()
		{
			Win32SysBridge.suspend (0);
		}

		public void hibernate ()
		{
			Win32SysBridge.suspend (1);
		}

		public void hybrid_sleep ()
		{
			Win32SysBridge.suspend (0);
		}

		public void reboot_to_firmware ()
		{
			Win32AppBridge.shell_execute ("shutdown.exe", "/r /fw /t 0", null);
		}

		public void logout ()
		{
			Win32SysBridge.logout ();
		}

		public void restart ()
		{
			Win32AppBridge.shell_execute ("shutdown.exe", "/r /t 0", null);
		}

		public void shutdown ()
		{
			Win32AppBridge.shell_execute ("shutdown.exe", "/s /t 0", null);
		}
	}

	class Win32BatteryProvider : GLib.Object, IBatteryProvider
	{
		public BatteryState query_state ()
		{
			int present = 0, pct = 100, charging = 0, full = 1;
			Win32SysBridge.query_battery (out present, out pct, out charging, out full);
			return BatteryState () {
				has_battery = (present != 0),
				percentage = pct,
				is_charging = (charging != 0),
				is_full = (full != 0),
				raw_status = (charging != 0) ? "Charging" : ((full != 0) ? "Full" : "Discharging")
			};
		}

		public bool has_battery ()
		{
			int present = 0, pct = 100, charging = 0, full = 1;
			Win32SysBridge.query_battery (out present, out pct, out charging, out full);
			return present != 0;
		}
	}

	class Win32BrightnessProvider : GLib.Object, IBrightnessProvider
	{
		int cached_percent = 100;
		bool probed = false;
		bool probe_in_flight = false;
		bool available = true;
		bool has_cached_availability = false;
		bool is_cleaned_up = false;

		static string get_caps_cache_path ()
		{
			string? local = Win32AppBridge.get_known_folder (Win32AppBridge.FOLDER_LOCAL_APPDATA);
			if (local == null || local.length == 0)
				local = Environment.get_user_data_dir ();
			string dir = Path.build_filename (local, "WayPlank");
			DirUtils.create_with_parents (dir, 0755);
			return Path.build_filename (dir, "hw-caps-cache.ini");
		}

		public bool get_cached_availability ()
		{
			if (!has_cached_availability) {
				has_cached_availability = true;
				string path = get_caps_cache_path ();
				if (FileUtils.test (path, FileTest.IS_REGULAR)) {
					var kf = new KeyFile ();
					try {
						kf.load_from_file (path, KeyFileFlags.NONE);
						if (kf.has_key ("Caps", "HardwareBrightnessSupported"))
							available = kf.get_boolean ("Caps", "HardwareBrightnessSupported");
					} catch (Error e) {}
				}
			}
			return available;
		}

		static void save_cached_availability (bool supp)
		{
			string path = get_caps_cache_path ();
			var kf = new KeyFile ();
			kf.set_boolean ("Caps", "HardwareBrightnessSupported", supp);
			try {
				FileUtils.set_contents (path, kf.to_data ());
			} catch (Error e) {}
		}

		public void start_async_probe ()
		{
			if (probed || probe_in_flight || is_cleaned_up)
				return;
			probe_in_flight = true;
			GLib.WeakRef weak_self = GLib.WeakRef (this);
			new Thread<void*> ("wayplank-bright-probe", () => {
				Win32AppBridge.set_thread_low_priority ();
				bool supp = (Win32SysBridge.brightness_is_available () != 0);
				int pct = supp ? Win32SysBridge.brightness_get_percent () : 100;
				GLib.Idle.add (() => {
					var self = (Win32BrightnessProvider?) weak_self.get ();
					if (self == null || self.is_cleaned_up)
						return Source.REMOVE;
					self.probe_in_flight = false;
					self.probed = true;
					self.available = supp;
					self.has_cached_availability = true;
					self.cached_percent = pct;
					Hal.Capabilities.supports_hardware_brightness = supp;
					save_cached_availability (supp);
					if (supp)
						self.brightness_changed (pct);
					return Source.REMOVE;
				});
				return null;
			});
		}

		public bool is_available ()
		{
			if (!probed) {
				start_async_probe ();
				return get_cached_availability ();
			}
			return available;
		}

		public int get_percent ()
		{
			if (!probed) {
				start_async_probe ();
				return cached_percent;
			}
			if (!available)
				return 100;
			cached_percent = Win32SysBridge.brightness_get_percent ();
			return cached_percent;
		}

		public void set_percent (int percent, bool immediate = false)
		{
			if (!probed && !get_cached_availability ())
				return;
			if (probed && !available)
				return;
			int clamped = int.max (5, int.min (100, percent));
			Win32SysBridge.brightness_set_percent (clamped);
			cached_percent = clamped;
			brightness_changed (clamped);
		}

		public void adjust_percent (int delta)
		{
			set_percent (get_percent () + delta, true);
		}

		public void cleanup ()
		{
			is_cleaned_up = true;
		}
	}

	class Win32CpuMemoryProvider : GLib.Object, ICpuMemoryProvider
	{
		public CpuMemDiskSample sample ()
		{
			int cpu = 0, ram = 0;
			double used_gb = 0.0, total_gb = 0.0;
			Win32SysBridge.sample_cpu_mem (out cpu, out ram, out used_gb, out total_gb);
			int pressure = int.max (cpu, ram);
			return CpuMemDiskSample () {
				cpu_pct = cpu,
				ram_pct = ram,
				io_pct = 0,
				system_pressure = pressure,
				ram_used_gb = used_gb,
				ram_total_gb = total_gb
			};
		}
	}

	class Win32NetworkProvider : GLib.Object, INetworkProvider
	{
		public NetworkState probe_state_sync ()
		{
			int conn = 0;
			string? ctype = null;
			string? cname = null;
			string? ip = null;
			Win32SysBridge.network_probe (out conn, out ctype, out cname, out ip);
			return NetworkState () {
				is_connected = (conn != 0),
				connection_type = ctype ?? "none",
				connection_name = cname ?? "",
				wifi_strength = (conn != 0 && ctype == "wifi") ? 80 : 0,
				ip_address = ip ?? "",
				gateway = ""
			};
		}

		public void cleanup () {}
	}

	class Win32AudioProvider : GLib.Object, IAudioProvider
	{
		public AudioState probe_state_sync ()
		{
			int vol = 70, muted = 0;
			int ok = Win32SysBridge.audio_probe (out vol, out muted);
			return AudioState () {
				ok = (ok != 0),
				volume_percent = vol,
				is_muted = (muted != 0)
			};
		}

		public void set_muted (bool muted)
		{
			Win32SysBridge.audio_set_muted (muted ? 1 : 0);
		}

		public void toggle_mute (bool target_muted_fallback)
		{
			var st = probe_state_sync ();
			bool next = st.ok ? !st.is_muted : target_muted_fallback;
			Win32SysBridge.audio_set_muted (next ? 1 : 0);
		}

		public void set_volume_percent (int percent)
		{
			Win32SysBridge.audio_set_volume_percent (int.max (0, int.min (100, percent)));
		}
	}

	class Win32EjectorProvider : GLib.Object, IEjectorProvider
	{
		string last_signature = "";
		uint poll_timer_id = 0U;
		uint init_idle_id = 0U;

		construct
		{
			GLib.WeakRef weak_self = GLib.WeakRef (this);
			init_idle_id = GLib.Idle.add (() => {
				var self = (Win32EjectorProvider?) weak_self.get ();
				if (self == null)
					return Source.REMOVE;
				self.init_idle_id = 0U;
				string cur = self.build_signature ();
				if (cur != self.last_signature) {
					self.last_signature = cur;
					self.drives_changed ();
				}
				return Source.REMOVE;
			});
			poll_timer_id = GLib.Timeout.add_seconds (3, on_poll_tick);
		}

		~Win32EjectorProvider ()
		{
			cleanup ();
		}

		string build_signature ()
		{
			var sb = new StringBuilder ();
			Win32SysBridge.enum_removable_drives ((root, label) => {
				sb.append (root);
				sb.append_c ('|');
				sb.append (label);
				sb.append_c (';');
			});
			return sb.str;
		}

		bool on_poll_tick ()
		{
			string cur = build_signature ();
			if (cur != last_signature) {
				last_signature = cur;
				drives_changed ();
			}
			return Source.CONTINUE;
		}

		public Gee.ArrayList<RemovableDriveInfo> get_removable_drives ()
		{
			var list = new Gee.ArrayList<RemovableDriveInfo> ();
			Win32SysBridge.enum_removable_drives ((root, label) => {
				var info = new RemovableDriveInfo ();
				info.id = root;
				info.display_name = "%s (%s)".printf (label, root.substring (0, int.min (2, root.length)));
				info.icon_name = "media-eject";
				list.add (info);
			});
			return list;
		}

		public void eject_drive (string id, owned DriveEjectCallback? callback = null)
		{
			bool ok = Win32SysBridge.eject_drive (id) != 0;
			last_signature = build_signature ();
			if (callback != null)
				callback (ok, id, ok ? "" : _("Drive not available"));
			if (ok)
				drives_changed ();
		}

		public void eject_all (owned DriveEjectCallback? per_drive_callback = null)
		{
			var drives = get_removable_drives ();
			foreach (var d in drives) {
				bool ok = Win32SysBridge.eject_drive (d.id) != 0;
				if (per_drive_callback != null)
					per_drive_callback (ok, d.display_name, ok ? "" : _("Drive not available"));
			}
			last_signature = build_signature ();
			drives_changed ();
		}

		public void cleanup ()
		{
			if (init_idle_id != 0U) {
				Source.remove (init_idle_id);
				init_idle_id = 0U;
			}
			if (poll_timer_id != 0U) {
				Source.remove (poll_timer_id);
				poll_timer_id = 0U;
			}
		}
	}

	class Win32ScreenshotProvider : GLib.Object, IScreenshotProvider
	{
		static string ensure_dir ()
		{
			string? dir = Win32SysBridge.get_screenshots_dir ();
			if (dir == null || dir.length == 0)
				dir = Path.build_filename (Environment.get_home_dir (), "Pictures", "Screenshots");
			DirUtils.create_with_parents (dir, 0755);
			return dir;
		}

		public void capture_interactive_region ()
		{
			Win32AppBridge.shell_execute ("ms-screenclip:", null, null);
		}

		public void capture_full_screen ()
		{
			uint8* rgba = null;
			int w = 0, h = 0;
			if (Win32SysBridge.capture_screen_rgba (out rgba, out w, out h) == 0 || rgba == null || w <= 0 || h <= 0) {
				if (rgba != null) Win32Bridge.free_buffer (rgba);
				return;
			}
			int rowstride = w * 4;
			int total = rowstride * h;
			uint8[] pixels = new uint8[total];
			Memory.copy (pixels, rgba, total);
			Win32Bridge.free_buffer (rgba);

			var pixbuf = new Gdk.Pixbuf.from_data ((owned) pixels, Gdk.Colorspace.RGB, true, 8, w, h, rowstride);
			var now = new DateTime.now_local ();
			string fname = "WayPlank_%s.png".printf (now.format ("%Y%m%d_%H%M%S"));
			string out_path = Path.build_filename (ensure_dir (), fname);
			try {
				pixbuf.save (out_path, "png");
			} catch (Error e) {
				warning ("Win32ScreenshotProvider: failed to save screenshot: %s", e.message);
			}
		}

		public void capture_active_window ()
		{
			uint64 target_hwnd = 0;
			foreach (var w in Hal.Windows.get_windows ()) {
				if (w.Active && !w.Minimized && Win32Backend.parse_hwnd (w.Id, out target_hwnd) && target_hwnd != 0)
					break;
			}
			if (target_hwnd == 0) {
				capture_full_screen ();
				return;
			}

			uint8* rgba = null;
			int w = 0, h = 0;
			if (Win32Bridge.capture_window_rgba (target_hwnd, 0, 0, out rgba, out w, out h) == 0
				|| rgba == null || w <= 0 || h <= 0) {
				if (rgba != null) Win32Bridge.free_buffer (rgba);
				capture_full_screen ();
				return;
			}

			int rowstride = w * 4;
			int total = rowstride * h;
			uint8[] pixels = new uint8[total];
			Memory.copy (pixels, rgba, total);
			Win32Bridge.free_buffer (rgba);

			var pixbuf = new Gdk.Pixbuf.from_data ((owned) pixels, Gdk.Colorspace.RGB, true, 8, w, h, rowstride);
			var now = new DateTime.now_local ();
			string fname = "WayPlank_Window_%s.png".printf (now.format ("%Y%m%d_%H%M%S"));
			string out_path = Path.build_filename (ensure_dir (), fname);
			try {
				pixbuf.save (out_path, "png");
			} catch (Error e) {
				warning ("Win32ScreenshotProvider: failed to save window screenshot: %s", e.message);
			}
		}

		public void open_screenshots_folder ()
		{
			Win32AppBridge.shell_execute (ensure_dir (), null, null);
		}
	}

	class Win32TrashProvider : GLib.Object, ITrashProvider
	{
		uint last_count = 0;
		uint poll_timer_id = 0U;
		uint init_idle_id = 0U;

		construct
		{
			GLib.WeakRef weak_self = GLib.WeakRef (this);
			init_idle_id = GLib.Idle.add (() => {
				var self = (Win32TrashProvider?) weak_self.get ();
				if (self == null)
					return Source.REMOVE;
				self.init_idle_id = 0U;
				uint cur = Win32SysBridge.trash_get_count ();
				if (cur != self.last_count) {
					self.last_count = cur;
					self.trash_changed ();
				}
				return Source.REMOVE;
			});
			poll_timer_id = GLib.Timeout.add_seconds (3, on_poll_tick);
		}

		~Win32TrashProvider ()
		{
			cleanup ();
		}

		bool on_poll_tick ()
		{
			uint cur = Win32SysBridge.trash_get_count ();
			if (cur != last_count) {
				last_count = cur;
				trash_changed ();
			}
			return Source.CONTINUE;
		}

		public uint get_item_count ()
		{
			last_count = Win32SysBridge.trash_get_count ();
			return last_count;
		}

		public Gee.ArrayList<TrashItemInfo> list_items ()
		{
			return new Gee.ArrayList<TrashItemInfo> ();
		}

		public bool move_uri_to_trash (string uri)
		{
			string path = uri;
			if (uri.has_prefix ("file://")) {
				string? p = File.new_for_uri (uri).get_path ();
				if (p != null) path = p;
			}
			bool ok = Win32SysBridge.trash_move_path (path) != 0;
			if (ok) {
				last_count = Win32SysBridge.trash_get_count ();
				trash_changed ();
			}
			return ok;
		}

		public bool restore_item (string id) { return false; }
		public bool delete_item_permanently (string id) { return false; }

		public bool empty_trash ()
		{
			bool ok = Win32SysBridge.trash_empty () != 0;
			last_count = Win32SysBridge.trash_get_count ();
			trash_changed ();
			return ok;
		}

		public void open_trash_ui ()
		{
			Win32SysBridge.trash_open_ui ();
		}

		public void cleanup ()
		{
			if (init_idle_id != 0U) {
				Source.remove (init_idle_id);
				init_idle_id = 0U;
			}
			if (poll_timer_id != 0U) {
				Source.remove (poll_timer_id);
				poll_timer_id = 0U;
			}
		}
	}

	/**
	 * Native Windows implementation of `ISystemTelemetry` powering all hardware
	 * and system docklets via pure evergreen Win32 APIs.
	 */
	public class Win32Telemetry : GLib.Object, ISystemTelemetry
	{
		Win32SessionPowerProvider session_power = new Win32SessionPowerProvider ();
		Win32BatteryProvider battery = new Win32BatteryProvider ();
		Win32BrightnessProvider brightness = new Win32BrightnessProvider ();
		Win32CpuMemoryProvider cpu_memory = new Win32CpuMemoryProvider ();
		Win32NetworkProvider network = new Win32NetworkProvider ();
		Win32AudioProvider audio = new Win32AudioProvider ();
		Win32EjectorProvider ejector = new Win32EjectorProvider ();
		Win32ScreenshotProvider screenshot = new Win32ScreenshotProvider ();
		Win32TrashProvider trash = new Win32TrashProvider ();

		public bool get_cached_brightness_available ()
		{
			return brightness.get_cached_availability ();
		}

		public void start_async_probes ()
		{
			brightness.start_async_probe ();
		}

		public ISessionPowerProvider SessionPower { get { return session_power; } }
		public IBatteryProvider Battery { get { return battery; } }
		public IBrightnessProvider Brightness { get { return brightness; } }
		public ICpuMemoryProvider CpuMemory { get { return cpu_memory; } }
		public INetworkProvider Network { get { return network; } }
		public IAudioProvider Audio { get { return audio; } }
		public IEjectorProvider Ejector { get { return ejector; } }
		public IScreenshotProvider Screenshot { get { return screenshot; } }
		public ITrashProvider Trash { get { return trash; } }

		public void cleanup ()
		{
			brightness.cleanup ();
			network.cleanup ();
			ejector.cleanup ();
			trash.cleanup ();
		}
	}
}
