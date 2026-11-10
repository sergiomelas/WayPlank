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
	public class FirstRunWindow : Gtk.Window
	{
		public static bool is_open { get; private set; default = false; }
		public static FirstRunWindow? active_instance { get; private set; default = null; }

		unowned DockController controller;
		bool choice_applied = false;

		public void cancel_without_applying ()
		{
			choice_applied = true;
		}
		Gtk.CssProvider? css_provider = null;
		Gdk.Screen? css_screen = null;

		~FirstRunWindow ()
		{
			is_open = false;
			if (active_instance == this)
				active_instance = null;
			if (css_screen != null && css_provider != null) {
				Gtk.StyleContext.remove_provider_for_screen (css_screen, css_provider);
				css_provider = null;
			}
		}

		public FirstRunWindow (DockController controller)
		{
			this.controller = controller;
			is_open = true;
			active_instance = this;

			this.show.connect (() => {
				is_open = true;
				active_instance = this;
			});
			this.hide.connect (() => {
				is_open = false;
				if (active_instance == this)
					active_instance = null;
			});
			this.delete_event.connect (() => {
				if (!choice_applied && this.controller != null) {
					choice_applied = true;
					this.controller.apply_onboarding_profile (false);
				}
				return false;
			});
			this.destroy.connect (() => {
				if (!choice_applied && this.controller != null) {
					choice_applied = true;
					this.controller.apply_onboarding_profile (false);
				}
				is_open = false;
				if (active_instance == this)
					active_instance = null;
				if (css_screen != null && css_provider != null) {
					Gtk.StyleContext.remove_provider_for_screen (css_screen, css_provider);
					css_provider = null;
				}
			});

			set_role ("first-run");
			set_decorated (true);
			set_destroy_with_parent (false);
			set_position (Gtk.WindowPosition.CENTER);
			gravity = Gdk.Gravity.CENTER;
			set_default_size (620, 380);
			resizable = false;
			set_type_hint (Gdk.WindowTypeHint.DIALOG);
			set_skip_taskbar_hint (true);
			set_skip_pager_hint (true);
			set_keep_above (true);
			set_focus_on_map (true);
			icon_name = "plank";

			var header = new Gtk.HeaderBar ();
			header.show_close_button = true;
			header.title = _("Welcome to WayPlank");
			set_titlebar (header);
			set_title (_("Welcome to WayPlank"));

			css_provider = new Gtk.CssProvider ();
			css_screen = get_screen ();
			try {
				css_provider.load_from_data (
					".onboarding-card { border-radius: 10px; border: 1px solid alpha(currentColor, 0.18); padding: 16px; background-color: alpha(currentColor, 0.04); }\n" +
					".onboarding-title { font-size: 1.15em; font-weight: bold; }\n" +
					".onboarding-sub { font-weight: 600; opacity: 0.9; }\n"
				);
				if (css_screen != null)
					Gtk.StyleContext.add_provider_for_screen (css_screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			} catch (GLib.Error e) {
				warning ("Unable to load first-run window CSS: %s", e.message);
			}

			var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
			root.set_margin_start (22);
			root.set_margin_end (22);
			root.set_margin_top (18);
			root.set_margin_bottom (20);

			string status_heading = controller.migrated_from_legacy_plank
				? _("Migrating your Plank configuration...")
				: _("Creating your WayPlank experience...");

			var status_lbl = new Gtk.Label (null);
			status_lbl.set_use_markup (true);
			status_lbl.set_markup ("<span size=\"large\"><b>%s</b></span>".printf (GLib.Markup.escape_text (status_heading)));
			status_lbl.set_xalign (0.0f);
			root.pack_start (status_lbl, false, false, 0);

			string intro_text = controller.migrated_from_legacy_plank
				? _("Your existing Plank launchers, folders and compatible settings have been imported safely without modifying ~/.config/plank. Choose how you want WayPlank to start:")
				: _("Choose how you want to initialize your dock:");

			var intro_lbl = new Gtk.Label (intro_text);
			intro_lbl.set_xalign (0.0f);
			intro_lbl.set_line_wrap (true);
			intro_lbl.set_max_width_chars (72);
			root.pack_start (intro_lbl, false, false, 0);

			var cards_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
			cards_box.set_homogeneous (true);

			var classic_card = build_profile_card (
				"preferences-system-symbolic",
				_("WayPlank Classic"),
				_("Start classical near old Plank and discover at your pace"),
				_("Keeps your dock minimal in Free Mode with your existing items, core pinned applications and Trash, without auto-adding category folders or accordion drawers."),
				_("Start Classic"),
				false
			);
			cards_box.pack_start (classic_card, true, true, 0);

			var explorer_card = build_profile_card (
				"starred-symbolic",
				_("WayPlank Explorer"),
				_("Start modern with all new features in the best experience spot"),
				_("Enables Smart Categorized Layout, 4 Application Folder Drawers, System Tray Docklets with Accordion, Smart Pinned Apps Accordion, and Window Preview Cards."),
				_("Start Explorer"),
				true
			);
			cards_box.pack_start (explorer_card, true, true, 0);

			root.pack_start (cards_box, true, true, 0);

			var x11_note_lbl = new Gtk.Label (_("Note: Please remove any custom launchers or autostart workarounds (such as GDK_BACKEND=x11) previously created to force legacy Plank to run in X11 mode on Wayland."));
			x11_note_lbl.get_style_context ().add_class ("dim-label");
			x11_note_lbl.set_xalign (0.5f);
			x11_note_lbl.set_justify (Gtk.Justification.CENTER);
			x11_note_lbl.set_line_wrap (true);
			x11_note_lbl.set_max_width_chars (76);
			root.pack_start (x11_note_lbl, false, false, 0);

			var footer_lbl = new Gtk.Label (_("You can switch or customize any feature at any time in WayPlank Preferences."));
			footer_lbl.get_style_context ().add_class ("dim-label");
			footer_lbl.set_xalign (0.5f);
			root.pack_start (footer_lbl, false, false, 0);

			add (root);

			key_press_event.connect ((event) => {
				if (event.keyval == Gdk.Key.Escape) {
					close ();
					return true;
				}
				return false;
			});

			show_all ();
		}

		Gtk.Widget build_profile_card (string icon_sym, string title, string subtitle, string body, string button_label, bool explorer_mode)
		{
			var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
			card.get_style_context ().add_class ("onboarding-card");

			var top_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
			var img = new Gtk.Image.from_icon_name (icon_sym, Gtk.IconSize.LARGE_TOOLBAR);
			top_row.pack_start (img, false, false, 0);

			var title_lbl = new Gtk.Label (title);
			title_lbl.get_style_context ().add_class ("onboarding-title");
			title_lbl.set_xalign (0.0f);
			top_row.pack_start (title_lbl, true, true, 0);
			card.pack_start (top_row, false, false, 0);

			var sub_lbl = new Gtk.Label (subtitle);
			sub_lbl.get_style_context ().add_class ("onboarding-sub");
			sub_lbl.set_xalign (0.0f);
			sub_lbl.set_line_wrap (true);
			sub_lbl.set_max_width_chars (34);
			card.pack_start (sub_lbl, false, false, 0);

			var body_lbl = new Gtk.Label (body);
			body_lbl.get_style_context ().add_class ("dim-label");
			body_lbl.set_xalign (0.0f);
			body_lbl.set_yalign (0.0f);
			body_lbl.set_line_wrap (true);
			body_lbl.set_max_width_chars (34);
			card.pack_start (body_lbl, true, true, 0);

			var btn = new Gtk.Button.with_label (button_label);
			btn.set_size_request (-1, 36);
			if (explorer_mode)
				btn.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			btn.clicked.connect (() => {
				if (!choice_applied && this.controller != null) {
					choice_applied = true;
					this.controller.apply_onboarding_profile (explorer_mode);
				}
				destroy ();
			});
			card.pack_end (btn, false, false, 4);

			return card;
		}
	}
}
