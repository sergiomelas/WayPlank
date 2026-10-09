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
	public class SessionWindow : Gtk.Window
	{
		enum ConfirmAction {
			LOGOUT,
			RESTART,
			SHUTDOWN
		}

		static SessionWindow? active_instance = null;

		public static void toggle_window ()
		{
			if (active_instance != null) {
				active_instance.destroy ();
				active_instance = null;
				return;
			}

			var win = new SessionWindow ();
			win.show_all ();
			win.present ();
			active_instance = win;
		}

		Gtk.Stack stack;
		Gtk.Image confirm_icon;
		Gtk.Label confirm_title;
		Gtk.Label confirm_desc;
		Gtk.Button confirm_cancel_btn;
		Gtk.Button confirm_action_btn;
		Gtk.Button actions_cancel_btn;
		ConfirmAction current_confirm_action = ConfirmAction.SHUTDOWN;

		public SessionWindow ()
		{
			Object (type: Gtk.WindowType.TOPLEVEL);
		}

		construct
		{
			title = _("Session & Power");
			set_role ("session-dialog");
			set_decorated (true);
			set_destroy_with_parent (true);
			set_position (Gtk.WindowPosition.CENTER);
			set_default_size (460, 310);
			resizable = false;
			set_type_hint (Gdk.WindowTypeHint.DIALOG);
			set_keep_above (true);
			set_focus_on_map (true);
			icon_name = "system-shutdown";
			skip_taskbar_hint = true;
			skip_pager_hint = true;

			stack = new Gtk.Stack ();
			stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
			stack.set_transition_duration (200);

			// ---------------- Page 1: Main Actions ----------------
			var actions_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
			actions_box.margin = 18;

			// Header info area
			var header_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
			var title_label = new Gtk.Label (null);
			title_label.set_markup ("<span size='large' weight='bold'>%s</span>".printf (_("Session &amp; Power")));
			title_label.halign = Gtk.Align.START;

			string user = Environment.get_real_name ();
			if (user == null || user == "" || user == "Unknown")
				user = Environment.get_user_name ();
			string host = Environment.get_host_name ();

			var subtitle_label = new Gtk.Label (null);
			subtitle_label.set_markup ("<span color='#888888'>%s <b>%s</b> @ <b>%s</b></span>".printf (_("Logged in as"), user, host));
			subtitle_label.halign = Gtk.Align.START;

			header_box.pack_start (title_label, false, false, 0);
			header_box.pack_start (subtitle_label, false, false, 0);
			actions_box.pack_start (header_box, false, false, 0);

			// Separator
			actions_box.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);

			// Grid of 6 buttons (2 rows x 3 columns)
			var grid = new Gtk.Grid ();
			grid.row_spacing = 10;
			grid.column_spacing = 10;
			grid.row_homogeneous = true;
			grid.column_homogeneous = true;
			grid.hexpand = true;
			grid.vexpand = true;

			// Col 0, Row 0: Lock Screen (direct)
			var btn_lock = create_action_button (_("Lock Screen"), "system-lock-screen", _("Lock the current session"), () => {
				destroy ();
				SessionDockItem.lock_screen ();
			});
			grid.attach (btn_lock, 0, 0, 1, 1);

			// Col 1, Row 0: Switch User (direct)
			var btn_switch = create_action_button (_("Switch User"), "system-users", _("Switch to another user or login screen"), () => {
				destroy ();
				SessionDockItem.switch_user ();
			});
			grid.attach (btn_switch, 1, 0, 1, 1);

			// Col 2, Row 0: Log Out (asks confirmation)
			var btn_logout = create_action_button (_("Log Out"), "system-log-out", _("Log out of the current session"), () => {
				show_confirmation (ConfirmAction.LOGOUT);
			});
			grid.attach (btn_logout, 2, 0, 1, 1);

			// Col 0, Row 1: Suspend (direct)
			var btn_suspend = create_action_button (_("Suspend"), "system-suspend", _("Put computer into low-power sleep mode"), () => {
				destroy ();
				SessionDockItem.suspend ();
			});
			grid.attach (btn_suspend, 0, 1, 1, 1);

			// Col 1, Row 1: Restart (asks confirmation)
			var btn_restart = create_action_button (_("Restart"), "system-reboot", _("Reboot the operating system"), () => {
				show_confirmation (ConfirmAction.RESTART);
			});
			grid.attach (btn_restart, 1, 1, 1, 1);

			// Col 2, Row 1: Shut Down (asks confirmation, Destructive styling)
			var btn_shutdown = create_action_button (_("Shut Down"), "system-shutdown", _("Power off the computer"), () => {
				show_confirmation (ConfirmAction.SHUTDOWN);
			}, true);
			grid.attach (btn_shutdown, 2, 1, 1, 1);

			actions_box.pack_start (grid, true, true, 0);

			// Bottom action area with Cancel button
			var bottom_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
			bottom_box.halign = Gtk.Align.END;

			actions_cancel_btn = new Gtk.Button.with_label (_("Cancel"));
			actions_cancel_btn.set_can_default (true);
			actions_cancel_btn.clicked.connect (() => {
				destroy ();
			});
			bottom_box.pack_end (actions_cancel_btn, false, false, 0);

			actions_box.pack_start (bottom_box, false, false, 0);
			stack.add_named (actions_box, "actions");

			// ---------------- Page 2: In-Place Confirmation ----------------
			var confirm_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
			confirm_box.margin = 24;
			confirm_box.valign = Gtk.Align.CENTER;
			confirm_box.halign = Gtk.Align.FILL;
			confirm_box.hexpand = true;
			confirm_box.vexpand = true;

			confirm_icon = new Gtk.Image ();
			confirm_icon.pixel_size = 54;
			confirm_icon.halign = Gtk.Align.CENTER;
			confirm_box.pack_start (confirm_icon, false, false, 0);

			confirm_title = new Gtk.Label (null);
			confirm_title.use_markup = true;
			confirm_title.halign = Gtk.Align.CENTER;
			confirm_box.pack_start (confirm_title, false, false, 0);

			confirm_desc = new Gtk.Label (null);
			confirm_desc.use_markup = true;
			confirm_desc.justify = Gtk.Justification.CENTER;
			confirm_desc.halign = Gtk.Align.CENTER;
			confirm_desc.max_width_chars = 44;
			confirm_desc.wrap = true;
			confirm_box.pack_start (confirm_desc, false, false, 0);

			// Spacing
			var spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
			spacer.margin_top = 10;
			confirm_box.pack_start (spacer, false, false, 0);

			// Confirmation Buttons
			var confirm_btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
			confirm_btn_box.halign = Gtk.Align.CENTER;

			confirm_cancel_btn = new Gtk.Button.with_label (_("Cancel"));
			confirm_cancel_btn.set_can_default (true);
			confirm_cancel_btn.width_request = 110;
			confirm_cancel_btn.clicked.connect (() => {
				title = _("Session & Power");
				stack.set_visible_child_name ("actions");
				actions_cancel_btn.grab_focus ();
			});
			confirm_btn_box.pack_start (confirm_cancel_btn, false, false, 0);

			confirm_action_btn = new Gtk.Button ();
			confirm_action_btn.set_can_default (true);
			confirm_action_btn.width_request = 120;
			confirm_action_btn.clicked.connect (() => {
				destroy ();
				switch (current_confirm_action) {
					case ConfirmAction.LOGOUT:
						SessionDockItem.logout (false);
						break;
					case ConfirmAction.RESTART:
						SessionDockItem.restart (false);
						break;
					case ConfirmAction.SHUTDOWN:
						SessionDockItem.shutdown (false);
						break;
				}
			});
			confirm_btn_box.pack_start (confirm_action_btn, false, false, 0);

			confirm_box.pack_start (confirm_btn_box, false, false, 0);
			stack.add_named (confirm_box, "confirm");

			add (stack);
			stack.set_visible_child_name ("actions");

			set_default (actions_cancel_btn);

			key_press_event.connect ((w, e) => {
				if (e.keyval == Gdk.Key.Escape) {
					if (stack.visible_child_name == "confirm") {
						title = _("Session & Power");
						stack.set_visible_child_name ("actions");
						actions_cancel_btn.grab_focus ();
						return Gdk.EVENT_STOP;
					}
					destroy ();
					return Gdk.EVENT_STOP;
				}
				return Gdk.EVENT_PROPAGATE;
			});

			destroy.connect (() => {
				if (active_instance == this)
					active_instance = null;
			});
		}

		void show_confirmation (ConfirmAction action)
		{
			current_confirm_action = action;
			title = _("Confirm Session Action");

			switch (action) {
				case ConfirmAction.LOGOUT:
					confirm_icon.set_from_icon_name ("system-log-out", Gtk.IconSize.DIALOG);
					confirm_title.set_markup ("<span size='large' weight='bold'>%s</span>".printf (_("Log Out of Session?")));
					confirm_desc.set_markup ("<span color='#888888'>%s</span>".printf (_("Are you sure you want to log out of your current session?")));
					confirm_action_btn.label = _("Log Out");
					confirm_action_btn.get_style_context ().remove_class ("suggested-action");
					confirm_action_btn.get_style_context ().add_class ("destructive-action");
					break;
				case ConfirmAction.RESTART:
					confirm_icon.set_from_icon_name ("system-reboot", Gtk.IconSize.DIALOG);
					confirm_title.set_markup ("<span size='large' weight='bold'>%s</span>".printf (_("Restart System?")));
					confirm_desc.set_markup ("<span color='#888888'>%s</span>".printf (_("Are you sure you want to restart your computer? Unsaved changes will be lost.")));
					confirm_action_btn.label = _("Restart");
					confirm_action_btn.get_style_context ().remove_class ("destructive-action");
					confirm_action_btn.get_style_context ().add_class ("suggested-action");
					break;
				case ConfirmAction.SHUTDOWN:
					confirm_icon.set_from_icon_name ("system-shutdown", Gtk.IconSize.DIALOG);
					confirm_title.set_markup ("<span size='large' weight='bold'>%s</span>".printf (_("Shut Down Computer?")));
					confirm_desc.set_markup ("<span color='#888888'>%s</span>".printf (_("Are you sure you want to turn off your computer? Unsaved changes will be lost.")));
					confirm_action_btn.label = _("Shut Down");
					confirm_action_btn.get_style_context ().remove_class ("suggested-action");
					confirm_action_btn.get_style_context ().add_class ("destructive-action");
					break;
			}

			stack.set_visible_child_name ("confirm");
			confirm_cancel_btn.grab_focus ();
		}

		delegate void ActionCallback ();

		Gtk.Button create_action_button (string label_text, string icon_name, string tooltip_text, owned ActionCallback callback, bool is_destructive = false)
		{
			var btn = new Gtk.Button ();
			btn.can_focus = true;
			btn.tooltip_text = tooltip_text;

			var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
			box.margin_top = 8;
			box.margin_bottom = 8;
			box.margin_start = 8;
			box.margin_end = 8;
			box.halign = Gtk.Align.CENTER;
			box.valign = Gtk.Align.CENTER;

			var img = new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.DND);
			img.pixel_size = 32;

			var lbl = new Gtk.Label (label_text);
			lbl.use_markup = true;

			box.pack_start (img, false, false, 0);
			box.pack_start (lbl, false, false, 0);

			btn.add (box);

			if (is_destructive) {
				btn.get_style_context ().add_class ("destructive-action");
			}

			btn.clicked.connect (() => {
				callback ();
			});

			return btn;
		}
	}
}
