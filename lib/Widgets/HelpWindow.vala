//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
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
	public class HelpWindow : Gtk.Window
	{
		public HelpWindow ()
		{
			set_decorated (true);
			set_destroy_with_parent (true);
			set_position (Gtk.WindowPosition.CENTER);
			set_default_size (560, 420);
			resizable = false;
			set_type_hint (Gdk.WindowTypeHint.DIALOG);
			set_keep_above (true);
			set_focus_on_map (true);
			icon_name = "help-browser";

			// Stack for multi-page categories
			var stack = new Gtk.Stack ();
			stack.set_transition_type (Gtk.StackTransitionType.SLIDE_LEFT_RIGHT);
			stack.set_transition_duration (200);

			// Page 1: Mouse Actions
			var grid_mouse = create_shortcuts_grid ();
			add_shortcut_row (grid_mouse, 0, _("Left Click"), _("Launch application, or activate / cycle open windows"));
			add_shortcut_row (grid_mouse, 1, _("Middle Click (or Ctrl + Left)"), _("Force launch a NEW instance of the application"));
			add_shortcut_row (grid_mouse, 2, _("Right Click"), _("Open application context menu (Quicklists, Keep in Dock)"));
			add_shortcut_row (grid_mouse, 3, _("Mouse Scroll on Icon"), _("Cycle between all open windows of this application"));
			add_shortcut_row (grid_mouse, 4, _("Shift + Left Click"), _("Focus the next open window of this application"));
			stack.add_titled (create_page (_("Interactions and gestures on application icons and windows"), grid_mouse), "mouse", _("Mouse Actions"));

			// Page 2: Drag & Drop
			var grid_drag = create_shortcuts_grid ();
			add_shortcut_row (grid_drag, 0, _("Drag icon off dock"), _("Unpin / remove launcher from dock (with smoke animation)"));
			add_shortcut_row (grid_drag, 1, _("Drag icon along dock"), _("Reorder pinned application launchers directly on the dock"));
			add_shortcut_row (grid_drag, 2, _("Drop file on app icon"), _("Open the dropped file directly with that application"));
			add_shortcut_row (grid_drag, 3, _("Drop .desktop or folder"), _("Pin a new application or folder launcher to the dock"));
			stack.add_titled (create_page (_("Organizing, pinning and interacting with dock items"), grid_drag), "drag", _("Drag & Drop"));

			// Page 3: Shortcuts & Tools
			var grid_tools = create_shortcuts_grid ();
			add_shortcut_row (grid_tools, 0, _("Ctrl + Mouse Scroll Up"), _("Increase dock icon size dynamically in real-time"));
			add_shortcut_row (grid_tools, 1, _("Ctrl + Mouse Scroll Down"), _("Decrease dock icon size dynamically in real-time"));
			add_shortcut_row (grid_tools, 2, _("Ctrl + Right Click"), _("Open dock preferences menu directly, even over an icon"));
			add_shortcut_row (grid_tools, 3, _("Right Click on space"), _("Open dock preferences menu from any empty dock area"));
			add_shortcut_row (grid_tools, 4, _("Ctrl + Alt + Shift + Right Click"), _("Open Developer Tools submenu (inspect launcher, config, theme)"));
			stack.add_titled (create_page (_("Dynamic zoom, dock settings and hidden developer tools"), grid_tools), "tools", _("Shortcuts & Tools"));

			// HeaderBar with StackSwitcher (Identical to PreferencesWindow)
			var header = new Gtk.HeaderBar ();
			header.show_close_button = true;
			header.title = _("Shortcuts & Gestures");

			var switcher = new Gtk.StackSwitcher ();
			switcher.set_stack (stack);
			switcher.set_halign (Gtk.Align.CENTER);
			header.set_custom_title (switcher);
			header.show_all ();
			set_titlebar (header);

			// Main vertical content layout
			var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
			content.pack_start (stack, true, true, 0);

			content.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);

			// Centered OK Action button (Identical to PreferencesWindow)
			var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
			actions.set_margin_start (12);
			actions.set_margin_end (12);
			actions.set_margin_top (10);
			actions.set_margin_bottom (12);
			actions.set_halign (Gtk.Align.CENTER);

			var ok_button = new Gtk.Button.with_label (_("OK"));
			ok_button.set_size_request (160, 36);
			ok_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			ok_button.clicked.connect (() => hide ());
			actions.pack_end (ok_button, false, false, 0);

			content.pack_end (actions, false, false, 0);
			add (content);

			set_default (ok_button);

			// Close on Escape key
			key_press_event.connect ((event) => {
				if (event.keyval == Gdk.Key.Escape) {
					hide ();
					return true;
				}
				return false;
			});

			content.show_all ();
		}

		Gtk.Widget create_page (string subtitle, Gtk.Grid grid)
		{
			var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
			box.set_margin_start (20);
			box.set_margin_end (20);
			box.set_margin_top (18);
			box.set_margin_bottom (18);

			var sub_lbl = new Gtk.Label (subtitle);
			sub_lbl.get_style_context ().add_class ("dim-label");
			sub_lbl.set_xalign (0.0f);
			sub_lbl.set_margin_bottom (12);
			box.pack_start (sub_lbl, false, false, 0);

			box.pack_start (grid, true, true, 0);

			var scrolled = new Gtk.ScrolledWindow (null, null);
			scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			scrolled.set_shadow_type (Gtk.ShadowType.NONE);
			scrolled.add (box);

			return scrolled;
		}

		Gtk.Grid create_shortcuts_grid ()
		{
			var grid = new Gtk.Grid ();
			grid.column_spacing = 20;
			grid.row_spacing = 10;
			grid.set_margin_start (6);
			grid.set_margin_end (6);
			grid.set_halign (Gtk.Align.FILL);
			return grid;
		}

		void add_shortcut_row (Gtk.Grid grid, int row, string shortcut, string description)
		{
			var lbl_shortcut = new Gtk.Label (null);
			lbl_shortcut.set_markup ("<tt><b>%s</b></tt>".printf (GLib.Markup.escape_text (shortcut)));
			lbl_shortcut.set_xalign (0.0f);
			lbl_shortcut.set_yalign (0.5f);

			var lbl_desc = new Gtk.Label (description);
			lbl_desc.set_xalign (0.0f);
			lbl_desc.set_yalign (0.5f);
			lbl_desc.set_line_wrap (true);
			lbl_desc.set_hexpand (true);

			grid.attach (lbl_shortcut, 0, row, 1, 1);
			grid.attach (lbl_desc, 1, row, 1, 1);
		}
	}
}
