//
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of Wayplank.
//
//  Wayplank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Wayplank is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

namespace Plank
{
	public class BrightnessDockItem : DockItem
	{
		const string ICON_NAMES_HIGH = "display-brightness-high;;display-brightness;;brightness-high";
		const string ICON_NAMES_MED = "display-brightness-medium;;display-brightness;;brightness-medium";
		const string ICON_NAMES_LOW = "display-brightness-low;;display-brightness;;brightness-low";

		private string? backlight_device = null;
		private uint32 max_raw_brightness = 100;
		private int current_percent = 100;
		private uint timer_id = 0;

		private GLib.DBusConnection? session_bus = null;
		private GLib.DBusConnection? system_bus = null;
		private uint kde_signal_id = 0;
		private uint gnome_signal_id = 0;
		private int kde_max_brightness = 0;
		private bool kde_available = false;
		private bool gnome_available = false;

		public BrightnessDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public BrightnessDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Screen Brightness");
			Icon = ICON_NAMES_HIGH;
			Button = PopupButton.RIGHT;

			init_dbus ();
			detect_backlight_device ();
			refresh_brightness ();

			timer_id = GLib.Timeout.add_seconds (2, on_timer_tick);
		}

		~BrightnessDockItem ()
		{
			cleanup ();
		}

		public override void @delete ()
		{
			cleanup ();
			base.@delete ();
		}

		private void cleanup ()
		{
			if (timer_id != 0) {
				GLib.Source.remove (timer_id);
				timer_id = 0;
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

		public override bool is_valid ()
		{
			return true;
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
			var child = sig_params.get_child_value (0);
			if (child != null) {
				int val = child.get_int32 ();
				if (kde_max_brightness <= 0)
					kde_max_brightness = 10000;
				current_percent = (int) Math.round (((double) val / (double) kde_max_brightness) * 100.0);
				current_percent = current_percent.clamp (1, 100);
				update_display ();
			}
		}

		private void on_gnome_properties_changed (GLib.DBusConnection conn, string? sender, string path, string iface, string sig_name, GLib.Variant sig_params)
		{
			string target_iface = sig_params.get_child_value (0).get_string ();
			if (target_iface == "org.gnome.SettingsDaemon.Power.Screen") {
				var changed_props = sig_params.get_child_value (1);
				var bright_var = changed_props.lookup_value ("Brightness", null);
				if (bright_var != null) {
					int val = bright_var.get_variant ().get_int32 ();
					current_percent = val.clamp (1, 100);
					update_display ();
				}
			}
		}

		private void detect_backlight_device ()
		{
			var dir = GLib.File.new_for_path ("/sys/class/backlight");
			try {
				var enumerator = dir.enumerate_children ("standard::name", GLib.FileQueryInfoFlags.NONE);
				GLib.FileInfo? info = null;
				string? fallback_dev = null;
				while ((info = enumerator.next_file ()) != null) {
					string dev = info.get_name ();
					string max_path = "/sys/class/backlight/%s/max_brightness".printf (dev);
					string cur_path = "/sys/class/backlight/%s/brightness".printf (dev);
					if (GLib.FileUtils.test (max_path, GLib.FileTest.EXISTS) && GLib.FileUtils.test (cur_path, GLib.FileTest.EXISTS)) {
						if (!dev.has_prefix ("acpi_video")) {
							backlight_device = dev;
							read_max_brightness ();
							return;
						} else {
							fallback_dev = dev;
						}
					}
				}
				if (fallback_dev != null) {
					backlight_device = fallback_dev;
					read_max_brightness ();
				}
			} catch (GLib.Error e) {
				backlight_device = null;
			}
		}

		private void read_max_brightness ()
		{
			if (backlight_device == null) return;
			string path = "/sys/class/backlight/%s/max_brightness".printf (backlight_device);
			try {
				string content;
				GLib.FileUtils.get_contents (path, out content);
				max_raw_brightness = (uint32) int64.parse (content.strip ());
				if (max_raw_brightness <= 0) max_raw_brightness = 100;
			} catch (GLib.Error e) {
				max_raw_brightness = 100;
			}
		}

		private void refresh_brightness ()
		{
			// 1. Try KDE Solid PowerManagement D-Bus
			if (session_bus != null) {
				try {
					var reply = session_bus.call_sync (
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
					if (kde_max_brightness <= 0) {
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
					}
					if (kde_max_brightness > 0) {
						current_percent = (int) Math.round (((double) cur / (double) kde_max_brightness) * 100.0);
						current_percent = current_percent.clamp (1, 100);
						kde_available = true;
						update_display ();
						return;
					}
				} catch (GLib.Error e) {
					kde_available = false;
				}

				// 2. Try GNOME SettingsDaemon Power D-Bus
				try {
					var reply = session_bus.call_sync (
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
					int val = val_var.get_int32 ();
					current_percent = val.clamp (1, 100);
					gnome_available = true;
					update_display ();
					return;
				} catch (GLib.Error e) {
					gnome_available = false;
				}
			}

			// 3. Try /sys/class/backlight/<device>/brightness (DO NOT read actual_brightness!)
			if (backlight_device != null) {
				string path = "/sys/class/backlight/%s/brightness".printf (backlight_device);
				try {
					string content;
					GLib.FileUtils.get_contents (path, out content);
					int64 raw = int64.parse (content.strip ());
					if (max_raw_brightness > 0) {
						current_percent = (int) Math.round (((double) raw / (double) max_raw_brightness) * 100.0);
						current_percent = current_percent.clamp (1, 100);
						update_display ();
						return;
					}
				} catch (GLib.Error e) { }
			}

			// 4. Try brightnessctl -m
			if (GLib.Environment.find_program_in_path ("brightnessctl") != null) {
				try {
					string out_str;
					int exit_code;
					if (GLib.Process.spawn_command_line_sync ("brightnessctl -m", out out_str, null, out exit_code) && exit_code == 0) {
						var parts = out_str.strip ().split (",");
						if (parts.length >= 4) {
							string pct_str = parts[3].replace ("%", "").strip ();
							int pct = int.parse (pct_str);
							if (pct > 0) {
								current_percent = pct.clamp (1, 100);
								update_display ();
								return;
							}
						}
					}
				} catch (GLib.Error e) { }
			}

			update_display ();
		}

		private void update_display ()
		{
			Count = current_percent;
			CountVisible = true;
			Text = _("Screen Brightness: %d%%").printf (current_percent);

			if (current_percent >= 66) {
				Icon = ICON_NAMES_HIGH;
			} else if (current_percent >= 33) {
				Icon = ICON_NAMES_MED;
			} else {
				Icon = ICON_NAMES_LOW;
			}

			reset_icon_buffer ();
		}

		private bool on_timer_tick ()
		{
			refresh_brightness ();
			return true;
		}

		public void adjust_brightness (int delta)
		{
			set_brightness_percent (current_percent + delta);
		}

		public void set_brightness_percent (int percent)
		{
			int target = percent.clamp (5, 100);
			current_percent = target;
			update_display ();

			// 1. Try KDE Solid PowerManagement D-Bus
			if (session_bus != null) {
				if (kde_max_brightness <= 0) {
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
					} catch (GLib.Error e) { }
				}

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

				// Also invoke kscreen-doctor on KDE to ensure compositor display state syncs
				if (GLib.Environment.find_program_in_path ("kscreen-doctor") != null) {
					try {
						GLib.Process.spawn_command_line_async ("kscreen-doctor output.activeOutput.brightness.%d".printf (target));
					} catch (GLib.Error e) { }
				}

				// 2. Try GNOME SettingsDaemon Power D-Bus
				session_bus.call.begin (
					"org.gnome.SettingsDaemon.Power",
					"/org/gnome/SettingsDaemon/Power",
					"org.freedesktop.DBus.Properties",
					"Set",
					new GLib.Variant ("(ssv)", "org.gnome.SettingsDaemon.Power.Screen", "Brightness", new GLib.Variant.int32 (target)),
					null,
					GLib.DBusCallFlags.NONE,
					500,
					null
				);
			}

			// 3. Try brightnessctl and light CLI tools
			if (GLib.Environment.find_program_in_path ("brightnessctl") != null) {
				try {
					GLib.Process.spawn_command_line_async ("brightnessctl set %d%%".printf (target));
				} catch (GLib.Error e) { }
			} else if (GLib.Environment.find_program_in_path ("light") != null) {
				try {
					GLib.Process.spawn_command_line_async ("light -S %d".printf (target));
				} catch (GLib.Error e) { }
			}

			// 4. Try systemd-logind system bus SetBrightness
			if (system_bus != null && backlight_device != null && max_raw_brightness > 0) {
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

				// 5. Direct sysfs write fallback (if user has write permission via udev)
				string path = "/sys/class/backlight/%s/brightness".printf (backlight_device);
				try {
					GLib.FileUtils.set_contents (path, target_raw.to_string ());
				} catch (GLib.Error e) { }
			}
		}

		protected override AnimationType on_scrolled (Gdk.ScrollDirection direction, Gdk.ModifierType mod, uint32 event_time)
		{
			if (direction == Gdk.ScrollDirection.UP) {
				adjust_brightness (5);
				return AnimationType.NONE;
			} else if (direction == Gdk.ScrollDirection.DOWN) {
				adjust_brightness (-5);
				return AnimationType.NONE;
			}
			return base.on_scrolled (direction, mod, event_time);
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				int next;
				if (current_percent < 25) next = 25;
				else if (current_percent < 50) next = 50;
				else if (current_percent < 75) next = 75;
				else if (current_percent < 100) next = 100;
				else next = 25;

				set_brightness_percent (next);
				return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var header_item = new Gtk.MenuItem.with_label (_("Brightness: %d%%").printf (current_percent));
			header_item.sensitive = false;
			items.add (header_item);

			items.add (new Gtk.SeparatorMenuItem ());

			int[] presets = { 100, 75, 50, 25, 10 };
			string[] preset_icons = { "display-brightness-high", "display-brightness-high", "display-brightness-medium", "display-brightness-low", "display-brightness-low" };

			for (int i = 0; i < presets.length; i++) {
				int p = presets[i];
				string label = "%d%% %s".printf (p, p == 100 ? _("(Maximum)") : (p == 10 ? _("(Minimum)") : ""));
				var item = create_menu_item (label, preset_icons[i], true);
				item.activate.connect (() => set_brightness_percent (p));
				items.add (item);
			}

			items.add (new Gtk.SeparatorMenuItem ());

			var settings_item = create_menu_item (_("_Display Settings..."), "preferences-desktop-display", true);
			settings_item.activate.connect (() => {
				string[] cmd_candidates = {
					"systemsettings kcm_kscreen",
					"kcmshell6 kcm_kscreen",
					"kcmshell5 kcm_kscreen",
					"gnome-control-center display",
					"wdisplays",
					"arandr"
				};
				foreach (var cmd in cmd_candidates) {
					try {
						GLib.Process.spawn_command_line_async (cmd);
						break;
					} catch (GLib.Error e) { }
				}
			});
			items.add (settings_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
			remove_item.activate.connect (() => {
				this.@delete ();
			});
			items.add (remove_item);

			append_dock_menu_items (items);

			return items;
		}

		private void append_dock_menu_items (Gee.ArrayList<Gtk.MenuItem> items)
		{
			if (items.size > 0)
				items.add (new Gtk.SeparatorMenuItem ());
			var dock_item = Factory.item_factory.get_item_for_dock ();
			if (dock_item != null)
				foreach (var menu_item in dock_item.get_menu_items ())
					items.add (menu_item);
		}
	}
}
