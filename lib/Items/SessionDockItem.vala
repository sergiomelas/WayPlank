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
				SessionWindow.toggle_window (event_time);
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

			var hibernate_item = create_menu_item (_("_Hibernate"), "system-suspend-hibernate", true);
			hibernate_item.sensitive = can_hibernate ();
			hibernate_item.activate.connect (() => { hibernate (); });
			items.add (hibernate_item);

			var hybrid_item = create_menu_item (_("H_ybrid Sleep"), "system-suspend-hibernate", true);
			hybrid_item.sensitive = can_hybrid_sleep ();
			hybrid_item.activate.connect (() => { hybrid_sleep (); });
			items.add (hybrid_item);

			var reboot_item = create_menu_item (_("_Restart..."), "system-reboot", true);
			reboot_item.activate.connect (() => { restart (true); });
			items.add (reboot_item);

			var uefi_item = create_menu_item (_("_UEFI / BIOS..."), "preferences-system", true);
			uefi_item.sensitive = can_reboot_to_firmware ();
			uefi_item.activate.connect (() => { reboot_to_firmware (true); });
			items.add (uefi_item);

			var shutdown_item = create_menu_item (_("_Shut Down..."), "system-shutdown", true);
			shutdown_item.activate.connect (() => { shutdown (true); });
			items.add (shutdown_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var session_win_item = create_menu_item (_("Session _Dialog..."), "system-shutdown-symbolic", true);
			session_win_item.activate.connect (() => { SessionWindow.toggle_window (Gtk.get_current_event_time ()); });
			items.add (session_win_item);

			if (!is_dock_locked ()) {
				items.add (new Gtk.SeparatorMenuItem ());

				var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
				remove_item.activate.connect (() => {
					this.@delete ();
				});
				items.add (remove_item);
			}

			return items;
		}

		public static void lock_screen ()
		{
			Hal.Telemetry.SessionPower.lock_screen ();
		}

		public static void switch_user ()
		{
			Hal.Telemetry.SessionPower.switch_user ();
		}

		public static bool can_hibernate ()
		{
			return Hal.Telemetry.SessionPower.can_hibernate ();
		}

		public static bool can_hybrid_sleep ()
		{
			return Hal.Telemetry.SessionPower.can_hybrid_sleep ();
		}

		public static bool can_reboot_to_firmware ()
		{
			return Hal.Telemetry.SessionPower.can_reboot_to_firmware ();
		}

		public static void suspend ()
		{
			Hal.Telemetry.SessionPower.suspend ();
		}

		public static void hibernate ()
		{
			Hal.Telemetry.SessionPower.hibernate ();
		}

		public static void hybrid_sleep ()
		{
			Hal.Telemetry.SessionPower.hybrid_sleep ();
		}

		public static void reboot_to_firmware (bool prompt_if_needed)
		{
			if (prompt_if_needed && !confirm_dialog (_("Reboot to UEFI / BIOS"), _("Are you sure you want to restart your computer and enter the UEFI / BIOS firmware settings?"), _("UEFI / BIOS"))) {
				return;
			}
			Hal.Telemetry.SessionPower.reboot_to_firmware ();
		}

		public static void logout (bool prompt_if_needed)
		{
			if (prompt_if_needed && !confirm_dialog (_("Log Out"), _("Are you sure you want to log out of this session?"), _("Log Out"))) {
				return;
			}
			Hal.Telemetry.SessionPower.logout ();
		}

		public static void restart (bool prompt_if_needed)
		{
			if (prompt_if_needed && !confirm_dialog (_("Restart System"), _("Are you sure you want to restart your computer?"), _("Restart"))) {
				return;
			}
			Hal.Telemetry.SessionPower.restart ();
		}

		public static void shutdown (bool prompt_if_needed)
		{
			if (prompt_if_needed && !confirm_dialog (_("Shut Down System"), _("Are you sure you want to shut down your computer?"), _("Shut Down"), true)) {
				return;
			}
			Hal.Telemetry.SessionPower.shutdown ();
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
			dialog.set_role ("help");
			dialog.window_position = Gtk.WindowPosition.CENTER;
			dialog.gravity = Gdk.Gravity.CENTER;
			dialog.set_type_hint (Gdk.WindowTypeHint.DIALOG);
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
