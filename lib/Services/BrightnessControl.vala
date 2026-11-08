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
	 * Compositor-agnostic Hardware Abstraction Layer (HAL) service for screen brightness.
	 * Encapsulates kernel PWM backlight, multi-monitor output discovery, KWin kscreen-doctor,
	 * Mutter / wlroots DDC/CI worker, and bi-directional auto-sync across heterogeneous Wayland compositors.
	 */
	public class BrightnessControl : GLib.Object
	{
		private static BrightnessControl? instance = null;

		public static unowned BrightnessControl get_default ()
		{
			if (instance == null) {
				instance = new BrightnessControl ();
			}
			return instance;
		}

		public static void cleanup_if_active ()
		{
			if (instance != null) {
				instance.cleanup ();
			}
		}

		/**
		 * Emitted whenever screen brightness changes, whether initiated by user action,
		 * desktop power management, ambient light sensors, or laptop Fn hotkeys.
		 */
		public signal void brightness_changed (int percent);

		private string? backlight_device = null;
		private uint32 max_raw_brightness = 100;
		private int target_sp = 100;
		private int current_percent = 100;
		private bool user_has_set_sp = false;
		private uint timer_id = 0;
		private uint sp_reset_timer_id = 0;
		private uint apply_timer_id = 0;
		private uint inbound_sync_timer_id = 0;
		private GLib.FileMonitor? sysfs_monitor = null;
		private int pending_hardware_target = -1;
		private int pending_auto_sync_target = -1;
		private int64 last_user_action_time = 0;
		private int64 last_auto_sync_time = 0;

		private GLib.DBusConnection? session_bus = null;
		private GLib.DBusConnection? system_bus = null;
		private uint kde_signal_id = 0;
		private uint gnome_signal_id = 0;
		private int kde_max_brightness = 0;
		private bool kde_available = false;
		private bool gnome_available = false;

		private Gee.ArrayList<string> kscreen_outputs = new Gee.ArrayList<string> ();
		private bool kscreen_probe_running = false;
		private Gee.ArrayList<int> ddcutil_displays = new Gee.ArrayList<int> ();
		private bool ddcutil_probe_running = false;
		private Gee.ArrayList<string> backlight_devices = new Gee.ArrayList<string> ();
		private Mutex ddc_mutex;
		private int pending_ddc_target = -1;
		private bool ddc_worker_active = false;
		private ulong mon_add_id = 0;
		private ulong mon_rem_id = 0;
		private bool shutting_down = false;
		private bool brightness_poll_running = false;

		public int get_percent ()
		{
			return current_percent;
		}

		public bool is_available ()
		{
			return (backlight_device != null || kde_available || gnome_available || !ddcutil_displays.is_empty);
		}

		public bool has_active_internal_display ()
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

		public bool is_standalone_internal_display ()
		{
			var display = Gdk.Display.get_default ();
			if (display != null && display.get_n_monitors () > 1) {
				return false;
			}
			return has_active_internal_display ();
		}

		private BrightnessControl ()
		{
			ddc_mutex = Mutex ();

			init_dbus ();
			detect_backlight_device ();
			refresh_kscreen_outputs ();
			refresh_ddcutil_displays ();
			refresh_brightness (true);

			var display = Gdk.Display.get_default ();
			if (display != null) {
				mon_add_id = display.monitor_added.connect ((m) => {
					detect_backlight_device ();
					refresh_kscreen_outputs ();
					refresh_ddcutil_displays ();
					update_polling_strategy ();
				});
				mon_rem_id = display.monitor_removed.connect ((m) => {
					detect_backlight_device ();
					refresh_kscreen_outputs ();
					refresh_ddcutil_displays ();
					update_polling_strategy ();
				});
			}

			update_polling_strategy ();
		}

		private void stop_sysfs_monitor ()
		{
			if (sysfs_monitor != null) {
				sysfs_monitor.cancel ();
				sysfs_monitor = null;
			}
		}

		private void setup_sysfs_monitor ()
		{
			stop_sysfs_monitor ();
			if (shutting_down || backlight_device == null)
				return;

			string cur_path = "/sys/class/backlight/%s/brightness".printf (backlight_device);
			try {
				var f = GLib.File.new_for_path (cur_path);
				sysfs_monitor = f.monitor_file (GLib.FileMonitorFlags.NONE, null);
				sysfs_monitor.changed.connect ((file, other, ev) => {
					if (shutting_down)
						return;
					if (ev == GLib.FileMonitorEvent.CHANGED || ev == GLib.FileMonitorEvent.CHANGES_DONE_HINT) {
						if (last_user_action_time > 0 && (GLib.get_monotonic_time () - last_user_action_time) < 250000)
							return;
						refresh_brightness (false);
					}
				});
			} catch (GLib.Error e) {
				sysfs_monitor = null;
			}
		}

		private void update_polling_strategy ()
		{
			if (timer_id != 0) {
				GLib.Source.remove (timer_id);
				timer_id = 0;
			}
			if (shutting_down)
				return;

			// Event-driven D-Bus signals handle KDE & GNOME; desktop PCs without backlight need zero timers.
			bool has_dbus_events = (kde_available && kde_signal_id != 0) || (gnome_available && gnome_signal_id != 0);
			bool has_any_pollable_backend = (backlight_device != null || kde_available || gnome_available);
			if (!has_dbus_events && has_any_pollable_backend) {
				timer_id = GLib.Timeout.add_seconds (5, on_timer_tick);
			}
		}

		~BrightnessControl ()
		{
			cleanup ();
		}

		public void cleanup ()
		{
			shutting_down = true;
			stop_sysfs_monitor ();

			if (timer_id != 0) {
				GLib.Source.remove (timer_id);
				timer_id = 0;
			}

			if (sp_reset_timer_id != 0) {
				GLib.Source.remove (sp_reset_timer_id);
				sp_reset_timer_id = 0;
			}

			if (apply_timer_id != 0) {
				GLib.Source.remove (apply_timer_id);
				apply_timer_id = 0;
			}

			if (inbound_sync_timer_id != 0) {
				GLib.Source.remove (inbound_sync_timer_id);
				inbound_sync_timer_id = 0;
			}

			var display = Gdk.Display.get_default ();
			if (display != null) {
				if (mon_add_id != 0) {
					display.disconnect (mon_add_id);
					mon_add_id = 0;
				}
				if (mon_rem_id != 0) {
					display.disconnect (mon_rem_id);
					mon_rem_id = 0;
				}
			}

			if (session_bus != null) {
				if (kde_signal_id != 0) {
					session_bus.signal_unsubscribe (kde_signal_id);
					kde_signal_id = 0;
				}
				if (gnome_signal_id != 0) {
					session_bus.signal_unsubscribe (gnome_signal_id);
					gnome_signal_id = 0;
				}
			}
		}

		private void init_dbus ()
		{
			try {
				session_bus = GLib.Bus.get_sync (GLib.BusType.SESSION, null);
				if (session_bus != null) {
					// 1. Fetch KDE brightness max if available
					try {
						var reply_max = session_bus.call_sync (
							"org.kde.Solid.PowerManagement",
							"/org/kde/Solid/PowerManagement/Actions/BrightnessControl",
							"org.kde.Solid.PowerManagement.Actions.BrightnessControl",
							"brightnessMax",
							null,
							null,
							GLib.DBusCallFlags.NONE,
							200,
							null
						);
						kde_max_brightness = reply_max.get_child_value (0).get_int32 ();
						kde_available = (kde_max_brightness > 0);
					} catch (GLib.Error e) {
						kde_available = false;
					}

					// 2. Subscribe to real-time KDE brightness changes
					kde_signal_id = session_bus.signal_subscribe (
						"org.kde.Solid.PowerManagement",
						"org.kde.Solid.PowerManagement.Actions.BrightnessControl",
						"brightnessChanged",
						"/org/kde/Solid/PowerManagement/Actions/BrightnessControl",
						null,
						GLib.DBusSignalFlags.NONE,
						on_kde_brightness_changed
					);

					// 3. Subscribe to real-time GNOME brightness changes
					gnome_signal_id = session_bus.signal_subscribe (
						"org.gnome.SettingsDaemon.Power",
						"org.freedesktop.DBus.Properties",
						"PropertiesChanged",
						"/org/gnome/SettingsDaemon/Power",
						null,
						GLib.DBusSignalFlags.NONE,
						on_gnome_properties_changed
					);
				}
			} catch (GLib.Error e) {
				session_bus = null;
			}

			try {
				system_bus = GLib.Bus.get_sync (GLib.BusType.SYSTEM, null);
			} catch (GLib.Error e) {
				system_bus = null;
			}
		}

		private void on_kde_brightness_changed (GLib.DBusConnection conn, string? sender, string path, string iface, string sig_name, GLib.Variant sig_params)
		{
			// Ignore self-echo during and right after user action (250ms settling window)
			if (last_user_action_time > 0 && (GLib.get_monotonic_time () - last_user_action_time) < 250000)
				return;

			// Ignore echo from our own auto-sync command to external monitors (350ms settle window)
			if (last_auto_sync_time > 0 && (GLib.get_monotonic_time () - last_auto_sync_time) < 350000)
				return;

			if (sig_params.n_children () < 1)
				return;

			var child = sig_params.get_child_value (0);
			if (child != null) {
				int val = child.get_int32 ();
				if (kde_max_brightness <= 0)
					kde_max_brightness = 10000;
				int new_pct = (int) Math.round (((double) val / (double) kde_max_brightness) * 100.0);
				new_pct = new_pct.clamp (0, 100);
				if ((new_pct - target_sp).abs () > 2) {
					target_sp = new_pct;
					current_percent = new_pct;
					brightness_changed (target_sp);
					schedule_inbound_auto_sync (target_sp);
				}
			}
		}

		private void on_gnome_properties_changed (GLib.DBusConnection conn, string? sender, string path, string iface, string sig_name, GLib.Variant sig_params)
		{
			// Ignore self-echo during and right after user action (250ms settling window)
			if (last_user_action_time > 0 && (GLib.get_monotonic_time () - last_user_action_time) < 250000)
				return;

			// Ignore echo from our own auto-sync command (350ms settle window)
			if (last_auto_sync_time > 0 && (GLib.get_monotonic_time () - last_auto_sync_time) < 350000)
				return;

			if (sig_params.n_children () < 2)
				return;

			string target_iface = sig_params.get_child_value (0).get_string ();
			if (target_iface == "org.gnome.SettingsDaemon.Power.Screen") {
				var changed_props = sig_params.get_child_value (1);
				var bright_var = changed_props.lookup_value ("Brightness", null);
				if (bright_var != null) {
					int val = bright_var.get_variant ().get_int32 ();
					int new_pct = val.clamp (0, 100);
					if ((new_pct - target_sp).abs () > 2) {
						target_sp = new_pct;
						current_percent = new_pct;
						brightness_changed (target_sp);
						schedule_inbound_auto_sync (target_sp);
					}
				}
			}
		}

		private void detect_backlight_device ()
		{
			backlight_devices.clear ();
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
						backlight_devices.add (dev);
						if (!dev.has_prefix ("acpi_video")) {
							if (preferred_dev == null)
								preferred_dev = dev;
						} else {
							if (fallback_dev == null)
								fallback_dev = dev;
						}
					}
				}
				backlight_device = (preferred_dev != null) ? preferred_dev : fallback_dev;
				if (backlight_device != null)
					read_max_brightness ();
			} catch (GLib.Error e) {
				backlight_device = null;
			}
			setup_sysfs_monitor ();
		}

		private uint32 get_device_max_brightness (string dev)
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

		private void read_max_brightness ()
		{
			if (backlight_device == null) return;
			max_raw_brightness = get_device_max_brightness (backlight_device);
		}

		private void refresh_kscreen_outputs ()
		{
			if (shutting_down)
				return;

			if (is_standalone_internal_display ()) {
				kscreen_outputs.clear ();
				return;
			}

			if (!kde_available && !environment_is_session_desktop (XdgSessionDesktop.KDE))
				return;

			if (GLib.Environment.find_program_in_path ("kscreen-doctor") == null)
				return;

			ddc_mutex.lock ();
			if (kscreen_probe_running) {
				ddc_mutex.unlock ();
				return;
			}
			kscreen_probe_running = true;
			ddc_mutex.unlock ();

			new GLib.Thread<void*> ("kscreen-probe", () => {
				var detected = new Gee.ArrayList<string> ();
				try {
					string json_out;
					int exit_code;
					if (GLib.Process.spawn_command_line_sync ("kscreen-doctor -j", out json_out, null, out exit_code) && exit_code == 0) {
						var parser = new Json.Parser ();
						parser.load_from_data (json_out);
						var root = parser.get_root ();
						if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
							var obj = root.get_object ();
							if (obj.has_member ("outputs") && !obj.get_null_member ("outputs")) {
								var arr = obj.get_array_member ("outputs");
								if (arr != null) {
									for (uint i = 0; i < arr.get_length (); i++) {
										var out_obj = arr.get_object_element (i);
										if (out_obj == null)
											continue;
										bool connected = (out_obj.has_member ("connected") && !out_obj.get_null_member ("connected")) ? out_obj.get_boolean_member ("connected") : false;
										bool enabled = (out_obj.has_member ("enabled") && !out_obj.get_null_member ("enabled")) ? out_obj.get_boolean_member ("enabled") : true;
										if (connected && enabled && out_obj.has_member ("name") && !out_obj.get_null_member ("name")) {
											string name = out_obj.get_string_member ("name") ?? "";
											if (name.length > 0) {
												detected.add (name);
											}
										}
									}
								}
							}
						}
					}
				} catch (GLib.Error e) {
					warning ("Failed to query kscreen-doctor outputs: %s", e.message);
				}

				GLib.Idle.add (() => {
					ddc_mutex.lock ();
					kscreen_probe_running = false;
					ddc_mutex.unlock ();
					if (shutting_down)
						return GLib.Source.REMOVE;
					bool was_empty = kscreen_outputs.is_empty;
					kscreen_outputs.clear ();
					kscreen_outputs.add_all (detected);
					if (was_empty && !kscreen_outputs.is_empty)
						brightness_changed (current_percent);
					return GLib.Source.REMOVE;
				});
				return null;
			});
		}

		private void refresh_ddcutil_displays ()
		{
			if (shutting_down)
				return;

			if (is_standalone_internal_display () || GLib.Environment.find_program_in_path ("ddcutil") == null) {
				ddc_mutex.lock ();
				ddcutil_displays.clear ();
				ddc_mutex.unlock ();
				return;
			}

			if (environment_is_session_desktop (XdgSessionDesktop.KDE)) {
				// Under KDE, kscreen-doctor handles unified DRM/DDC hardware sync
				return;
			}

			ddc_mutex.lock ();
			if (ddcutil_probe_running) {
				ddc_mutex.unlock ();
				return;
			}
			ddcutil_probe_running = true;
			ddc_mutex.unlock ();

			new GLib.Thread<void*> ("ddcutil-probe", () => {
				var detected = new Gee.ArrayList<int> ();
				bool ok = false;
				try {
					string out_str;
					int exit_code;
					if (GLib.Process.spawn_command_line_sync ("ddcutil detect --terse", out out_str, null, out exit_code) && exit_code == 0) {
						ok = true;
						var lines = out_str.split ("\n");
						foreach (var line in lines) {
							var trimmed = line.strip ();
							if (trimmed.has_prefix ("Display ")) {
								var parts = trimmed.split (" ");
								if (parts.length >= 2) {
									int d_num = int.parse (parts[1]);
									if (d_num > 0 && !detected.contains (d_num)) {
										detected.add (d_num);
									}
								}
							}
						}
					}
				} catch (GLib.Error e) { }
				GLib.Idle.add (() => {
					ddc_mutex.lock ();
					ddcutil_probe_running = false;
					if (shutting_down) {
						ddc_mutex.unlock ();
						return GLib.Source.REMOVE;
					}
					bool became_available = false;
					if (ok) {
						bool was_empty = ddcutil_displays.is_empty;
						ddcutil_displays.clear ();
						ddcutil_displays.add_all (detected);
						became_available = (was_empty && !ddcutil_displays.is_empty);
					}
					ddc_mutex.unlock ();
					if (became_available)
						brightness_changed (current_percent);
					return GLib.Source.REMOVE;
				});
				return null;
			});
		}

		private static int query_fallback_brightness_blocking (DBusConnection? bus, string? bl_dev, ref int cached_kde_max, bool in_kde_avail, bool in_gnome_avail, out bool out_kde_avail, out bool out_gnome_avail)
		{
			int pct_result = -1;
			out_kde_avail = in_kde_avail;
			out_gnome_avail = in_gnome_avail;

			// 2. Try KDE Solid PowerManagement D-Bus (Desktop PC or when backlight_device is null)
			if (pct_result < 0 && bus != null && environment_is_session_desktop (XdgSessionDesktop.KDE)) {
				try {
					var reply = bus.call_sync (
						"org.kde.Solid.PowerManagement",
						"/org/kde/Solid/PowerManagement/Actions/BrightnessControl",
						"org.kde.Solid.PowerManagement.Actions.BrightnessControl",
						"brightness",
						null,
						null,
						GLib.DBusCallFlags.NONE,
						200,
						null
					);
					int cur = reply.get_child_value (0).get_int32 ();
					if (cached_kde_max <= 0) {
						var reply_max = bus.call_sync (
							"org.kde.Solid.PowerManagement",
							"/org/kde/Solid/PowerManagement/Actions/BrightnessControl",
							"org.kde.Solid.PowerManagement.Actions.BrightnessControl",
							"brightnessMax",
							null,
							null,
							GLib.DBusCallFlags.NONE,
							200,
							null
						);
						cached_kde_max = reply_max.get_child_value (0).get_int32 ();
					}
					if (cached_kde_max > 0) {
						pct_result = (int) Math.round (((double) cur / (double) cached_kde_max) * 100.0);
						out_kde_avail = true;
					}
				} catch (GLib.Error e) {
					out_kde_avail = false;
				}
			}

			// 3. Try GNOME SettingsDaemon Power D-Bus
			if (pct_result < 0 && bus != null && environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)) {
				try {
					var reply = bus.call_sync (
						"org.gnome.SettingsDaemon.Power",
						"/org/gnome/SettingsDaemon/Power",
						"org.freedesktop.DBus.Properties",
						"Get",
						new GLib.Variant ("(ss)", "org.gnome.SettingsDaemon.Power.Screen", "Brightness"),
						null,
						GLib.DBusCallFlags.NONE,
						200,
						null
					);
					GLib.Variant val_var = reply.get_child_value (0).get_variant ();
					int val = -1;
					if (val_var.is_of_type (GLib.VariantType.INT32)) val = val_var.get_int32 ();
					else if (val_var.is_of_type (GLib.VariantType.UINT32)) val = (int) val_var.get_uint32 ();
					else if (val_var.is_of_type (GLib.VariantType.DOUBLE)) val = (int) Math.round (val_var.get_double ());
					if (val >= 0) {
						pct_result = val;
						out_gnome_avail = true;
					}
				} catch (GLib.Error e) {
					out_gnome_avail = false;
				}
			}

			// 4. Try brightnessctl -m fallback (only when a kernel backlight device exists)
			if (pct_result < 0 && bl_dev != null && GLib.Environment.find_program_in_path ("brightnessctl") != null) {
				try {
					string out_str;
					int exit_code;
					if (GLib.Process.spawn_command_line_sync ("brightnessctl -m", out out_str, null, out exit_code) && exit_code == 0) {
						var parts = out_str.strip ().split (",");
						if (parts.length >= 4) {
							string pct_str = parts[3].replace ("%", "").strip ();
							int pct = int.parse (pct_str);
							if (pct_str.length > 0 && (pct > 0 || pct_str == "0")) {
								pct_result = pct;
							}
						}
					}
				} catch (GLib.Error e) { }
			}

			return pct_result;
		}

		private void apply_polled_brightness (int polled_pct, bool is_initial_read)
		{
			if (polled_pct >= 0 && !user_has_set_sp) {
				int clamped = polled_pct.clamp (0, 100);
				if (is_initial_read || (clamped - target_sp).abs () > 2) {
					target_sp = clamped;
					current_percent = target_sp;
					brightness_changed (target_sp);
					if (!is_initial_read)
						schedule_inbound_auto_sync (target_sp);
				}
			}
		}

		private void refresh_brightness (bool is_initial_read = false)
		{
			if (user_has_set_sp && last_user_action_time > 0 && (GLib.get_monotonic_time () - last_user_action_time) > 2500000) {
				user_has_set_sp = false;
			}

			// If user has set an authoritative Set Point (SP), do not let periodic polling overwrite it!
			if (user_has_set_sp)
				return;

			int initial_pct = -1;

			// 1. Direct hardware backlight device (Physical ground truth for laptop internal panels: AMD, Intel, NVIDIA/ACPI)
			if (backlight_device != null) {
				string actual_path = "/sys/class/backlight/%s/actual_brightness".printf (backlight_device);
				string cur_path = "/sys/class/backlight/%s/brightness".printf (backlight_device);
				string path = GLib.FileUtils.test (actual_path, GLib.FileTest.EXISTS) ? actual_path : cur_path;
				try {
					string content;
					GLib.FileUtils.get_contents (path, out content);
					int64 raw = int64.parse (content.strip ());
					if (raw >= 0) {
						if (raw > max_raw_brightness)
							max_raw_brightness = (uint32) raw;
						if (max_raw_brightness > 0) {
							initial_pct = (int) Math.round (((double) raw / (double) max_raw_brightness) * 100.0);
						}
					}
				} catch (GLib.Error e) { }
			}

			if (initial_pct >= 0) {
				apply_polled_brightness (initial_pct, is_initial_read);
				return;
			}

			if (is_initial_read) {
				int km = kde_max_brightness;
				bool ka, ga;
				initial_pct = query_fallback_brightness_blocking (session_bus, backlight_device, ref km, kde_available, gnome_available, out ka, out ga);
				kde_max_brightness = km;
				kde_available = ka;
				gnome_available = ga;
				apply_polled_brightness (initial_pct, true);
				return;
			}

			// Real-time D-Bus signals handle KDE/GNOME updates immediately; skip polling when signals are active or no backend exists
			if ((kde_available && kde_signal_id != 0) || (gnome_available && gnome_signal_id != 0) || (!kde_available && !gnome_available))
				return;

			if (brightness_poll_running || shutting_down)
				return;

			brightness_poll_running = true;
			spawn_brightness_poll_worker (this, session_bus, backlight_device, kde_max_brightness, kde_available, gnome_available);
		}

		private static void spawn_brightness_poll_worker (BrightnessControl ctrl, DBusConnection? bus_snap, string? bl_snapshot, int km_snapshot, bool ka_snapshot, bool ga_snapshot)
		{
			GLib.WeakRef ctrl_ref = GLib.WeakRef (ctrl);
			new GLib.Thread<void*> ("wayplank-brightness-poll", () => {
				int km_local = km_snapshot;
				bool ka_local, ga_local;
				int polled = query_fallback_brightness_blocking (bus_snap, bl_snapshot, ref km_local, ka_snapshot, ga_snapshot, out ka_local, out ga_local);
				GLib.Idle.add (() => {
					var self = (BrightnessControl?) ctrl_ref.get ();
					if (self == null)
						return GLib.Source.REMOVE;
					self.brightness_poll_running = false;
					if (self.shutting_down)
						return GLib.Source.REMOVE;
					if (km_local > 0)
						self.kde_max_brightness = km_local;
					self.kde_available = ka_local;
					self.gnome_available = ga_local;
					self.apply_polled_brightness (polled, false);
					return GLib.Source.REMOVE;
				});
				return null;
			});
		}

		private bool on_timer_tick ()
		{
			// Reset user_has_set_sp after 2.5 seconds of user inactivity so external adjustments (Fn keys, OS power dimming) resume syncing
			if (user_has_set_sp && last_user_action_time > 0 && (GLib.get_monotonic_time () - last_user_action_time) > 2500000) {
				user_has_set_sp = false;
			}
			refresh_brightness ();
			return true;
		}

		public void adjust_percent (int delta)
		{
			int next = target_sp + delta;
			// Snap to nearest multiple of 5 for clean increments
			next = ((next + 2) / 5) * 5;
			set_percent (next, false);
		}

		public void set_percent (int percent, bool immediate = false)
		{
			int target = percent.clamp (5, 100);
			target_sp = target;
			current_percent = target;
			user_has_set_sp = true;
			last_user_action_time = GLib.get_monotonic_time ();
			if (sp_reset_timer_id != 0) {
				GLib.Source.remove (sp_reset_timer_id);
				sp_reset_timer_id = 0;
			}
			sp_reset_timer_id = GLib.Timeout.add (2500, () => {
				sp_reset_timer_id = 0;
				user_has_set_sp = false;
				if (!shutting_down)
					refresh_brightness (false);
				return GLib.Source.REMOVE;
			});
			brightness_changed (target_sp);

			// Cancel any pending inbound auto-sync so user selection takes immediate priority
			if (inbound_sync_timer_id != 0) {
				GLib.Source.remove (inbound_sync_timer_id);
				inbound_sync_timer_id = 0;
				pending_auto_sync_target = -1;
			}

			pending_hardware_target = target;

			if (apply_timer_id != 0) {
				GLib.Source.remove (apply_timer_id);
				apply_timer_id = 0;
			}

			if (immediate) {
				int t = pending_hardware_target;
				pending_hardware_target = -1;
				apply_hardware_brightness (t);
			} else if (is_standalone_internal_display ()) {
				// Standalone internal screen fast-path: 20ms micro-coalesce for buttery 60fps wheel scrolling with zero lag
				apply_timer_id = GLib.Timeout.add (20, () => {
					apply_timer_id = 0;
					if (pending_hardware_target >= 0) {
						int t = pending_hardware_target;
						pending_hardware_target = -1;
						apply_hardware_brightness (t);
					}
					return GLib.Source.REMOVE;
				});
			} else {
				// External display or multi-monitor settle debounce window (250ms): allows smooth mouse wheel scrolling and eliminates I2C DDC/CI packet collisions
				apply_timer_id = GLib.Timeout.add (250, () => {
					apply_timer_id = 0;
					if (pending_hardware_target >= 0) {
						int t = pending_hardware_target;
						pending_hardware_target = -1;
						apply_hardware_brightness (t);
					}
					return GLib.Source.REMOVE;
				});
			}
		}

		/**
		 * Schedules a debounced external display sync when an inbound brightness change arrives
		 * from desktop power daemon, ambient light sensor, or laptop Fn keys.
		 */
		private void schedule_inbound_auto_sync (int target)
		{
			if (is_standalone_internal_display ())
				return;

			pending_auto_sync_target = target;

			if (inbound_sync_timer_id != 0) {
				GLib.Source.remove (inbound_sync_timer_id);
				inbound_sync_timer_id = 0;
			}

			// Inbound settle debounce window (350ms): allows continuous ambient light transitions
			// or fast OS idle dimming ramp to settle before firing a single atomic hardware write to external displays!
			inbound_sync_timer_id = GLib.Timeout.add (350, () => {
				inbound_sync_timer_id = 0;
				if (pending_auto_sync_target >= 0) {
					int t = pending_auto_sync_target;
					pending_auto_sync_target = -1;
					apply_external_brightness_sync (t);
				}
				return GLib.Source.REMOVE;
			});
		}

		private void apply_external_brightness_sync (int target)
		{
			if (is_standalone_internal_display ())
				return;

			last_auto_sync_time = GLib.get_monotonic_time ();
			bool is_kde = kde_available || environment_is_session_desktop (XdgSessionDesktop.KDE);

			// 1. External / Multi-monitor KDE: invoke kscreen-doctor to atomically adjust all connected displays
			if (is_kde && GLib.Environment.find_program_in_path ("kscreen-doctor") != null) {
				if (kscreen_outputs.is_empty) {
					refresh_kscreen_outputs ();
				}
				if (!kscreen_outputs.is_empty) {
					var sb = new StringBuilder ("kscreen-doctor");
					foreach (var out_name in kscreen_outputs) {
						sb.append_printf (" output.%s.brightness.%d", out_name, target);
					}
					try {
						GLib.Process.spawn_command_line_async (sb.str);
					} catch (GLib.Error e) {
						warning ("Failed to invoke kscreen-doctor for external sync: %s", e.message);
					}
				}
				return;
			}

			// 2. Non-KDE External Display Synchronization via Dedicated Serialized Coalescing Worker
			queue_ddc_target (target);
		}

		private void apply_hardware_brightness (int target)
		{
			bool is_kde = kde_available || environment_is_session_desktop (XdgSessionDesktop.KDE);
			bool standalone_internal = is_standalone_internal_display ();

			// 1. External / Multi-monitor KDE: invoke kscreen-doctor to atomically adjust all connected displays
			if (!standalone_internal && is_kde && GLib.Environment.find_program_in_path ("kscreen-doctor") != null) {
				if (kscreen_outputs.is_empty) {
					refresh_kscreen_outputs ();
				}
				if (!kscreen_outputs.is_empty) {
					var sb = new StringBuilder ("kscreen-doctor");
					foreach (var out_name in kscreen_outputs) {
						sb.append_printf (" output.%s.brightness.%d", out_name, target);
					}
					try {
						GLib.Process.spawn_command_line_async (sb.str);
					} catch (GLib.Error e) {
						warning ("Failed to invoke kscreen-doctor: %s", e.message);
					}
				}
			}

			// 2. KDE Solid PowerManagement D-Bus: direct, instantaneous (<1ms) internal backlight control
			if (session_bus != null && is_kde) {
				if (kde_max_brightness > 0) {
					int kde_val = (int) Math.round (((double) target / 100.0) * (double) kde_max_brightness);
					session_bus.call.begin (
						"org.kde.Solid.PowerManagement",
						"/org/kde/Solid/PowerManagement/Actions/BrightnessControl",
						"org.kde.Solid.PowerManagement.Actions.BrightnessControl",
						"setBrightness",
						new GLib.Variant ("(i)", kde_val),
						null,
						GLib.DBusCallFlags.NONE,
						500,
						null
					);
				}
			}

			// 3. For Non-KDE (Mutter / Labwc): Single clean hardware write to internal panel (zero PWM flicker)
			if (!is_kde) {
				if (GLib.Environment.find_program_in_path ("brightnessctl") != null) {
					if (!backlight_devices.is_empty) {
						foreach (var dev in backlight_devices) {
							try {
								GLib.Process.spawn_command_line_async ("brightnessctl -d %s set %d%%".printf (dev, target));
							} catch (GLib.Error e) { }
						}
					} else {
						try {
							GLib.Process.spawn_command_line_async ("brightnessctl set %d%%".printf (target));
						} catch (GLib.Error e) { }
					}
				} else if (system_bus != null && backlight_device != null && max_raw_brightness > 0) {
					uint32 target_raw = (uint32) Math.round (((double) target / 100.0) * (double) max_raw_brightness);
					if (target_raw < 1) target_raw = 1;
					system_bus.call.begin (
						"org.freedesktop.login1",
						"/org/freedesktop/login1/session/auto",
						"org.freedesktop.login1.Session",
						"SetBrightness",
						new GLib.Variant ("(ssu)", "backlight", backlight_device, target_raw),
						null,
						GLib.DBusCallFlags.NONE,
						500,
						null
					);
				} else if (backlight_device != null) {
					uint32 target_raw = (uint32) Math.round (((double) target / 100.0) * (double) max_raw_brightness);
					if (target_raw < 1) target_raw = 1;
					string path = "/sys/class/backlight/%s/brightness".printf (backlight_device);
					try {
						GLib.FileUtils.set_contents (path, target_raw.to_string ());
					} catch (GLib.Error e) { }
				}

				// 4. Non-KDE External Display Synchronization via Dedicated Serialized Coalescing Worker
				if (!standalone_internal) {
					queue_ddc_target (target);
				}
			}
		}

		private void queue_ddc_target (int target)
		{
			bool is_kde = kde_available || environment_is_session_desktop (XdgSessionDesktop.KDE);
			if (is_kde || is_standalone_internal_display () || GLib.Environment.find_program_in_path ("ddcutil") == null)
				return;

			ddc_mutex.lock ();
			if (ddcutil_displays.is_empty) {
				ddc_mutex.unlock ();
				return;
			}
			pending_ddc_target = target;
			if (!ddc_worker_active) {
				ddc_worker_active = true;
				ddc_mutex.unlock ();
				new GLib.Thread<void*> ("ddc-sync-worker", () => {
					run_ddc_worker ();
					return null;
				});
			} else {
				ddc_mutex.unlock ();
			}
		}

		private void run_ddc_worker ()
		{
			while (true) {
				int target_to_apply = -1;
				ddc_mutex.lock ();
				if (pending_ddc_target < 0) {
					ddc_worker_active = false;
					ddc_mutex.unlock ();
					break;
				}
				target_to_apply = pending_ddc_target;
				pending_ddc_target = -1;
				ddc_mutex.unlock ();

				// Snapshot of displays to process
				var displays = new Gee.ArrayList<int> ();
				ddc_mutex.lock ();
				if (!ddcutil_displays.is_empty) {
					displays.add_all (ddcutil_displays);
				}
				ddc_mutex.unlock ();
				if (displays.is_empty) {
					ddc_mutex.lock ();
					pending_ddc_target = -1;
					ddc_worker_active = false;
					ddc_mutex.unlock ();
					break;
				}

				foreach (int d_num in displays) {
					// Check if a newer target arrived while waiting for slow I2C bus!
					ddc_mutex.lock ();
					if (pending_ddc_target >= 0) {
						ddc_mutex.unlock ();
						break; // Break early to discard stale target and apply newest!
					}
					ddc_mutex.unlock ();

					string cmd = "ddcutil setvcp 10 %d --display %d --noverify --sleep-multiplier .1".printf (target_to_apply, d_num);
					try {
						int exit_code;
						GLib.Process.spawn_command_line_sync (cmd, null, null, out exit_code);
					} catch (GLib.Error e) { }
				}
			}
		}
	}
}
