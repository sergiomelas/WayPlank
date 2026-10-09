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
	public class SessionDockItem : DockItem
	{
		const string ICON_NAMES = "system-shutdown;;system-shutdown-symbolic;;xfsm-shutdown;;application-exit;;system-log-out";

		public SessionDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public SessionDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Session / Power");
			Icon = ICON_NAMES;
			Button = PopupButton.RIGHT;
		}

		public override bool is_valid ()
		{
			return true;
		}

		public override void @delete ()
		{
			base.@delete ();
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				SessionWindow.toggle_window ();
				return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var header_item = new Gtk.MenuItem.with_label (Text);
			header_item.sensitive = false;
			items.add (header_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var lock_item = create_menu_item (_("_Lock Screen"), "system-lock-screen", true);
			lock_item.activate.connect (() => { lock_screen (); });
			items.add (lock_item);

			var switch_item = create_menu_item (_("_Switch User..."), "system-users", true);
			switch_item.activate.connect (() => { switch_user (); });
			items.add (switch_item);

			var logout_item = create_menu_item (_("Log _Out..."), "system-log-out", true);
			logout_item.activate.connect (() => { logout (true); });
			items.add (logout_item);

			var suspend_item = create_menu_item (_("_Suspend"), "system-suspend", true);
			suspend_item.activate.connect (() => { suspend (); });
			items.add (suspend_item);

			var reboot_item = create_menu_item (_("_Restart..."), "system-reboot", true);
			reboot_item.activate.connect (() => { restart (true); });
			items.add (reboot_item);

			var shutdown_item = create_menu_item (_("_Shut Down..."), "system-shutdown", true);
			shutdown_item.activate.connect (() => { shutdown (true); });
			items.add (shutdown_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var session_win_item = create_menu_item (_("Session _Dialog..."), "system-shutdown-symbolic", true);
			session_win_item.activate.connect (() => { SessionWindow.toggle_window (); });
			items.add (session_win_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
			remove_item.activate.connect (() => {
				this.@delete ();
			});
			items.add (remove_item);

			append_dock_menu_items (items);
			return items;
		}

		void append_dock_menu_items (Gee.ArrayList<Gtk.MenuItem> items)
		{
			if (items.size > 0)
				items.add (new Gtk.SeparatorMenuItem ());
			var dock_item = Factory.item_factory.get_item_for_dock ();
			if (dock_item != null)
				foreach (var menu_item in dock_item.get_menu_items ())
					items.add (menu_item);
		}

		public static bool is_kde_session ()
		{
			if (WindowControl.is_kwin ())
				return true;
			var desktop = GLib.Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
			return desktop.down ().contains ("kde") || desktop.down ().contains ("plasma");
		}

		public static bool is_gnome_session ()
		{
			if (WindowControl.is_mutter ())
				return true;
			var desktop = GLib.Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
			return desktop.down ().contains ("gnome") || desktop.down ().contains ("ubuntu");
		}

		public static void lock_screen ()
		{
			debug ("SessionDockItem: locking session");

			// 1. GNOME Shell (Mutter) native ScreenSaver (active when GDM is the display manager)
			if (is_gnome_session ()) {
				try {
					var bus = Bus.get_sync (BusType.SESSION, null);
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

			// 2. KDE Plasma (KWin) ScreenSaver
			if (is_kde_session ()) {
				try {
					var bus = Bus.get_sync (BusType.SESSION, null);
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
				} catch (Error e) {
					debug ("KDE ScreenSaver Lock D-Bus call failed: %s", e.message);
				}
				try {
					Process.spawn_command_line_async ("qdbus org.freedesktop.ScreenSaver /ScreenSaver Lock");
					return;
				} catch (Error e) { }
			}

			// 3. FreeDesktop ScreenSaver (generic D-Bus interface)
			try {
				var bus = Bus.get_sync (BusType.SESSION, null);
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
			} catch (Error e) { }

			// 4. FreeDesktop DisplayManager Seat SwitchToGreeter (SDDM / LightDM / multi-DM fallback)
			// When GNOME is run under SDDM, GNOME Shell intentionally disables ScreenShield because it lacks GDM's PAM backend.
			// The display manager (SDDM) provides the secure lock & authentication via SwitchToGreeter.
			var seat_path = Environment.get_variable ("XDG_SEAT_PATH");
			if (seat_path == null || seat_path == "")
				seat_path = "/org/freedesktop/DisplayManager/Seat0";

			try {
				var bus = Bus.get_sync (BusType.SYSTEM, null);
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
			} catch (Error e) {
				debug ("DisplayManager SwitchToGreeter lock fallback failed: %s", e.message);
			}

			// 5. Standalone Wayland lockers (Labwc / Sway / Hyprland)
			string[] lockers = { "swaylock", "waylock", "hyprlock" };
			foreach (var locker in lockers) {
				if (Environment.find_program_in_path (locker) != null) {
					try {
						Process.spawn_command_line_async (locker);
						return;
					} catch (Error e) { }
				}
			}

			// 6. systemd-logind fallback
			try {
				var bus = Bus.get_sync (BusType.SYSTEM, null);
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
			} catch (Error e) { }

			try {
				Process.spawn_command_line_async ("loginctl lock-sessions");
				return;
			} catch (Error e) { }
		}

		public static void switch_user ()
		{
			debug ("SessionDockItem: switching to user greeter");

			// 1. FreeDesktop DisplayManager Seat0 (LightDM, SDDM, GDM)
			var seat_path = Environment.get_variable ("XDG_SEAT_PATH");
			if (seat_path == null || seat_path == "")
				seat_path = "/org/freedesktop/DisplayManager/Seat0";

			try {
				var bus = Bus.get_sync (BusType.SYSTEM, null);
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
			} catch (Error e) {
				debug ("DisplayManager SwitchToGreeter unavailable: %s", e.message);
			}

			// 2. dm-tool
			if (Environment.find_program_in_path ("dm-tool") != null) {
				try {
					Process.spawn_command_line_async ("dm-tool switch-to-greeter");
					return;
				} catch (Error e) { }
			}

			// 3. Fallback: lock session
			lock_screen ();
		}

		public static void suspend ()
		{
			debug ("SessionDockItem: suspending system");
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

		public static void logout (bool prompt_if_needed)
		{
			debug ("SessionDockItem: logout requested (prompt=%s)", prompt_if_needed.to_string ());

			if (prompt_if_needed && !confirm_dialog (_("Log Out"), _("Are you sure you want to log out of this session?"), _("Log Out"))) {
				return;
			}

			// 1. KDE Plasma (via org.kde.Shutdown / plasma-shutdown)
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

			// 2. GNOME Shell
			if (is_gnome_session ()) {
				try {
					Process.spawn_command_line_async ("gnome-session-quit --logout --no-prompt");
					return;
				} catch (Error e) { }
			}

			// 3. Labwc
			if (WindowControl.is_labwc () || Environment.find_program_in_path ("labwc") != null) {
				try {
					Process.spawn_command_line_async ("labwc --exit");
					return;
				} catch (Error e) { }
			}

			// 4. loginctl terminate-session
			var session_id = Environment.get_variable ("XDG_SESSION_ID");
			if (session_id != null && session_id != "") {
				try {
					Process.spawn_command_line_async ("loginctl terminate-session " + session_id);
					return;
				} catch (Error e) { }
			}

			var user = Environment.get_user_name ();
			try {
				Process.spawn_command_line_async ("loginctl terminate-user " + user);
			} catch (Error e) {
				warning ("Failed to log out: %s", e.message);
			}
		}

		public static void restart (bool prompt_if_needed)
		{
			debug ("SessionDockItem: restart requested (prompt=%s)", prompt_if_needed.to_string ());

			if (prompt_if_needed && !confirm_dialog (_("Restart System"), _("Are you sure you want to restart your computer?"), _("Restart"))) {
				return;
			}

			// 1. GNOME Shell
			if (is_gnome_session ()) {
				try {
					Process.spawn_command_line_async ("gnome-session-quit --reboot --no-prompt");
					return;
				} catch (Error e) { }
			}

			// 2. systemctl reboot (standard across KDE Plasma, Labwc, wlroots, systemd)
			try {
				Process.spawn_command_line_async ("systemctl reboot");
				return;
			} catch (Error e) { }

			// 3. loginctl reboot (elogind / systemd)
			try {
				Process.spawn_command_line_async ("loginctl reboot");
				return;
			} catch (Error e) { }

			// 4. FreeDesktop login1 D-Bus interface
			try {
				Process.spawn_command_line_async ("gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.Reboot false");
				return;
			} catch (Error e) { }

			// 5. Traditional fallback
			try {
				Process.spawn_command_line_async ("reboot");
			} catch (Error e) {
				warning ("Failed to reboot: %s", e.message);
			}
		}

		public static void shutdown (bool prompt_if_needed)
		{
			debug ("SessionDockItem: shutdown requested (prompt=%s)", prompt_if_needed.to_string ());

			if (prompt_if_needed && !confirm_dialog (_("Shut Down System"), _("Are you sure you want to shut down your computer?"), _("Shut Down"), true)) {
				return;
			}

			// 1. GNOME Shell
			if (is_gnome_session ()) {
				try {
					Process.spawn_command_line_async ("gnome-session-quit --power-off --no-prompt");
					return;
				} catch (Error e) { }
			}

			// 2. systemctl poweroff (standard across KDE Plasma, Labwc, wlroots, systemd)
			try {
				Process.spawn_command_line_async ("systemctl poweroff");
				return;
			} catch (Error e) { }

			// 3. loginctl poweroff (elogind / systemd)
			try {
				Process.spawn_command_line_async ("loginctl poweroff");
				return;
			} catch (Error e) { }

			// 4. FreeDesktop login1 D-Bus interface
			try {
				Process.spawn_command_line_async ("gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.PowerOff false");
				return;
			} catch (Error e) { }

			// 5. Traditional fallback
			try {
				Process.spawn_command_line_async ("poweroff");
			} catch (Error e) {
				warning ("Failed to power off: %s", e.message);
			}
		}

		public static bool confirm_dialog (string title, string message, string action_label, bool is_destructive = false)
		{
			var dialog = new Gtk.MessageDialog (
				null,
				Gtk.DialogFlags.MODAL,
				Gtk.MessageType.QUESTION,
				Gtk.ButtonsType.NONE,
				"%s", message
			);
			dialog.title = title;
			dialog.window_position = Gtk.WindowPosition.CENTER;
			dialog.skip_taskbar_hint = true;
			dialog.set_keep_above (true);

			var cancel_btn = dialog.add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
			cancel_btn.set_can_default (true);

			var act_btn = dialog.add_button (action_label, Gtk.ResponseType.ACCEPT);
			act_btn.set_can_default (true);
			if (is_destructive) {
				act_btn.get_style_context ().add_class ("destructive-action");
			}

			dialog.set_default_response (Gtk.ResponseType.CANCEL);

			int response = dialog.run ();
			dialog.destroy ();
			return response == Gtk.ResponseType.ACCEPT;
		}
	}
}
