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
	 * Southbound Freedesktop / systemd-logind / DisplayManager / Wayland session & power provider (`ISessionPowerProvider`).
	 */
	public class FreedesktopSessionPower : GLib.Object, ISessionPowerProvider
	{
		static FreedesktopSessionPower? default_instance = null;

		public static FreedesktopSessionPower get_default ()
		{
			if (default_instance == null)
				default_instance = new FreedesktopSessionPower ();
			return default_instance;
		}

		static bool is_kde_session ()
		{
			if (WindowControl.is_kwin ())
				return true;
			var desktop = GLib.Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
			return desktop.down ().contains ("kde") || desktop.down ().contains ("plasma");
		}

		static bool is_gnome_session ()
		{
			if (WindowControl.is_mutter ())
				return true;
			var desktop = GLib.Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
			return desktop.down ().contains ("gnome") || desktop.down ().contains ("ubuntu");
		}

		public void get_session_user_and_host (out string user, out string host)
		{
			string? real_user = Environment.get_real_name ();
			if (real_user == null || real_user == "" || real_user == "Unknown")
				real_user = Environment.get_user_name ();
			user = real_user ?? "";
			host = Environment.get_host_name () ?? "";
		}

		static bool query_login1_capability (string method_name)
		{
			try {
				var bus = DbusBroker.get_default ().get_system_bus ();
				if (bus == null)
					return false;
				var res = bus.call_sync (
					"org.freedesktop.login1",
					"/org/freedesktop/login1",
					"org.freedesktop.login1.Manager",
					method_name,
					null,
					new VariantType ("(s)"),
					DBusCallFlags.NONE,
					1000,
					null
				);
				string status = "";
				res.get ("(s)", out status);
				return (status == "yes" || status == "challenge");
			} catch (Error e) {
				debug ("FreedesktopSessionPower: %s query failed: %s", method_name, e.message);
				return false;
			}
		}

		public bool can_hibernate ()
		{
			return query_login1_capability ("CanHibernate");
		}

		public bool can_hybrid_sleep ()
		{
			return query_login1_capability ("CanHybridSleep");
		}

		public bool can_reboot_to_firmware ()
		{
			return query_login1_capability ("CanRebootToFirmwareSetup");
		}

		public void lock_screen ()
		{
			debug ("FreedesktopSessionPower: locking session");

			if (is_gnome_session ()) {
				try {
					var bus = DbusBroker.get_default ().get_session_bus ();
					if (bus != null) {
						bus.call_sync (
							"org.gnome.ScreenSaver",
							"/org/gnome/ScreenSaver",
							"org.gnome.ScreenSaver",
							"Lock",
							null,
							null,
							DBusCallFlags.NONE,
							1500,
							null
						);
						return;
					}
				} catch (Error e) {
					debug ("GNOME ScreenSaver Lock D-Bus call failed (non-GDM display manager or ScreenShield unavailable): %s", e.message);
				}

				if (Environment.find_program_in_path ("gnome-screensaver-command") != null) {
					try {
						Process.spawn_command_line_async ("gnome-screensaver-command -l");
						return;
					} catch (Error e) { }
				}
			}

			if (is_kde_session ()) {
				try {
					var bus = DbusBroker.get_default ().get_session_bus ();
					if (bus != null) {
						bus.call_sync (
							"org.freedesktop.ScreenSaver",
							"/ScreenSaver",
							"org.freedesktop.ScreenSaver",
							"Lock",
							null,
							null,
							DBusCallFlags.NONE,
							1500,
							null
						);
						return;
					}
				} catch (Error e) {
					debug ("KDE ScreenSaver Lock D-Bus call failed: %s", e.message);
				}
				try {
					Process.spawn_command_line_async ("qdbus org.freedesktop.ScreenSaver /ScreenSaver Lock");
					return;
				} catch (Error e) { }
			}

			try {
				var bus = DbusBroker.get_default ().get_session_bus ();
				if (bus != null) {
					bus.call_sync (
						"org.freedesktop.ScreenSaver",
						"/ScreenSaver",
						"org.freedesktop.ScreenSaver",
						"Lock",
						null,
						null,
						DBusCallFlags.NONE,
						1500,
						null
					);
					return;
				}
			} catch (Error e) { }

			var seat_path = Environment.get_variable ("XDG_SEAT_PATH");
			if (seat_path == null || seat_path == "" || !Variant.is_object_path (seat_path))
				seat_path = "/org/freedesktop/DisplayManager/Seat0";

			try {
				var bus = DbusBroker.get_default ().get_system_bus ();
				if (bus != null) {
					bus.call_sync (
						"org.freedesktop.DisplayManager",
						seat_path,
						"org.freedesktop.DisplayManager.Seat",
						"SwitchToGreeter",
						null,
						null,
						DBusCallFlags.NONE,
						1500,
						null
					);
					return;
				}
			} catch (Error e) {
				debug ("DisplayManager SwitchToGreeter lock fallback failed: %s", e.message);
			}

			string[] lockers = { "swaylock", "waylock", "hyprlock" };
			foreach (var locker in lockers) {
				if (Environment.find_program_in_path (locker) != null) {
					try {
						Process.spawn_command_line_async (locker);
						return;
					} catch (Error e) { }
				}
			}

			try {
				var bus = DbusBroker.get_default ().get_system_bus ();
				if (bus != null) {
					bus.call_sync (
						"org.freedesktop.login1",
						"/org/freedesktop/login1",
						"org.freedesktop.login1.Manager",
						"LockSessions",
						null,
						null,
						DBusCallFlags.NONE,
						1500,
						null
					);
					return;
				}
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("loginctl lock-sessions");
				return;
			} catch (Error e) { }
		}

		public void switch_user ()
		{
			debug ("FreedesktopSessionPower: switching to user greeter");

			var seat_path = Environment.get_variable ("XDG_SEAT_PATH");
			if (seat_path == null || seat_path == "" || !Variant.is_object_path (seat_path))
				seat_path = "/org/freedesktop/DisplayManager/Seat0";

			try {
				var bus = DbusBroker.get_default ().get_system_bus ();
				if (bus != null) {
					bus.call_sync (
						"org.freedesktop.DisplayManager",
						seat_path,
						"org.freedesktop.DisplayManager.Seat",
						"SwitchToGreeter",
						null,
						null,
						DBusCallFlags.NONE,
						1000,
						null
					);
					return;
				}
			} catch (Error e) {
				debug ("DisplayManager SwitchToGreeter unavailable: %s", e.message);
			}

			if (Environment.find_program_in_path ("dm-tool") != null) {
				try {
					Process.spawn_command_line_async ("dm-tool switch-to-greeter");
					return;
				} catch (Error e) { }
			}

			lock_screen ();
		}

		public void suspend ()
		{
			debug ("FreedesktopSessionPower: suspending system");
			try {
				Process.spawn_command_line_async ("systemctl suspend");
				return;
			} catch (Error e) { }
			try {
				Process.spawn_command_line_async ("gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.Suspend true");
			} catch (Error e) {
				warning ("Failed to suspend: %s", e.message);
			}
		}

		public void hibernate ()
		{
			debug ("FreedesktopSessionPower: hibernating system");
			try {
				Process.spawn_command_line_async ("systemctl hibernate");
				return;
			} catch (Error e) { }
			try {
				Process.spawn_command_line_async ("gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.Hibernate true");
			} catch (Error e) {
				warning ("Failed to hibernate: %s", e.message);
			}
		}

		public void hybrid_sleep ()
		{
			debug ("FreedesktopSessionPower: hybrid-sleeping system");
			try {
				Process.spawn_command_line_async ("systemctl hybrid-sleep");
				return;
			} catch (Error e) { }
			try {
				Process.spawn_command_line_async ("gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.HybridSleep true");
			} catch (Error e) {
				warning ("Failed to hybrid-sleep: %s", e.message);
			}
		}

		public void reboot_to_firmware ()
		{
			debug ("FreedesktopSessionPower: reboot to UEFI/BIOS firmware setup");

			try {
				Process.spawn_command_line_async ("systemctl reboot --firmware-setup");
				return;
			} catch (Error e) { }

			try {
				var bus = DbusBroker.get_default ().get_system_bus ();
				if (bus != null) {
					bus.call_sync (
						"org.freedesktop.login1",
						"/org/freedesktop/login1",
						"org.freedesktop.login1.Manager",
						"SetRebootToFirmwareSetup",
						new Variant ("(b)", true),
						null,
						DBusCallFlags.NONE,
						1500,
						null
					);
					restart ();
					return;
				}
			} catch (Error e) {
				warning ("Failed to reboot to firmware setup: %s", e.message);
			}
		}

		public void logout ()
		{
			debug ("FreedesktopSessionPower: logout");

			if (is_kde_session ()) {
				try {
					Process.spawn_command_line_async ("qdbus org.kde.Shutdown /Shutdown logout");
					return;
				} catch (Error e) { }
				try {
					Process.spawn_command_line_async ("plasma-shutdown --logout");
					return;
				} catch (Error e) { }
			}

			if (is_gnome_session ()) {
				try {
					Process.spawn_command_line_async ("gnome-session-quit --logout --no-prompt");
					return;
				} catch (Error e) { }
			}

			if (WindowControl.is_labwc () || Environment.find_program_in_path ("labwc") != null) {
				try {
					Process.spawn_command_line_async ("labwc --exit");
					return;
				} catch (Error e) { }
			}

			var session_id = Environment.get_variable ("XDG_SESSION_ID");
			if (session_id != null && session_id != "") {
				try {
					Process.spawn_command_line_async ("loginctl terminate-session " + Shell.quote (session_id));
					return;
				} catch (Error e) { }
			}

			var user = Environment.get_user_name ();
			try {
				Process.spawn_command_line_async ("loginctl terminate-user " + Shell.quote (user));
			} catch (Error e) {
				warning ("Failed to log out: %s", e.message);
			}
		}

		public void restart ()
		{
			debug ("FreedesktopSessionPower: restart");

			if (is_gnome_session ()) {
				try {
					Process.spawn_command_line_async ("gnome-session-quit --reboot --no-prompt");
					return;
				} catch (Error e) { }
			}

			try {
				Process.spawn_command_line_async ("systemctl reboot");
				return;
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("loginctl reboot");
				return;
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.Reboot false");
				return;
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("reboot");
			} catch (Error e) {
				warning ("Failed to reboot: %s", e.message);
			}
		}

		public void shutdown ()
		{
			debug ("FreedesktopSessionPower: shutdown");

			if (is_gnome_session ()) {
				try {
					Process.spawn_command_line_async ("gnome-session-quit --power-off --no-prompt");
					return;
				} catch (Error e) { }
			}

			try {
				Process.spawn_command_line_async ("systemctl poweroff");
				return;
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("loginctl poweroff");
				return;
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.PowerOff false");
				return;
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("poweroff");
			} catch (Error e) {
				warning ("Failed to power off: %s", e.message);
			}
		}
	}
}
