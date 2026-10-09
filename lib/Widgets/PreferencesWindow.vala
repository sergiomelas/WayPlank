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
	[GtkTemplate (ui = "/net/launchpad/plank/ui/preferences.ui")]
	public class PreferencesWindow : Gtk.Window
	{
		/**
		 * The controller for this dock.
		 */
		public DockController controller { get; construct set; }
		
		DockPreferences prefs;
		
		[GtkChild]
		unowned Gtk.ComboBoxText cb_theme;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_hidemode;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_display_plug;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_position;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_alignment;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_items_alignment;
		
		[GtkChild]
		unowned Gtk.SpinButton sp_hide_delay;
		[GtkChild]
		unowned Gtk.SpinButton sp_unhide_delay;
		[GtkChild]
		unowned Gtk.Scale s_offset;
		[GtkChild]
		unowned Gtk.Scale s_zoom_percent;
		
		[GtkChild]
		unowned Gtk.Adjustment adj_hide_delay;
		[GtkChild]
		unowned Gtk.Adjustment adj_unhide_delay;
		[GtkChild]
		unowned Gtk.Adjustment adj_iconsize;
		[GtkChild]
		unowned Gtk.Adjustment adj_offset;
		[GtkChild]
		unowned Gtk.Adjustment adj_zoom_percent;
		
		[GtkChild]
		unowned Gtk.Switch sw_hide;
		[GtkChild]
		unowned Gtk.Switch sw_primary_display;
		[GtkChild]
		unowned Gtk.Switch sw_workspace_only;
		[GtkChild]
		unowned Gtk.Switch sw_show_unpinned;
		[GtkChild]
		unowned Gtk.Switch sw_lock_items;
		[GtkChild]
		unowned Gtk.Switch sw_pressure_reveal;
		[GtkChild]
		unowned Gtk.Switch sw_zoom_enabled;
		[GtkChild]
		unowned Gtk.Switch sw_autostart;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_window_click_behavior;
		[GtkChild]
		unowned Gtk.Switch sw_restore_minimized;
		[GtkChild]
		unowned Gtk.Switch sw_show_running_indicators;
		[GtkChild]
		unowned Gtk.Switch sw_show_attention_indicators;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_trash;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_clock;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_digital_clock;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_battery;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_cpu;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_desktop;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_mpris;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_volume;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_screenshot;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_session;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_preferences;
		[GtkChild]
		unowned Gtk.Image img_docklet_trash;
		[GtkChild]
		unowned Gtk.Image img_docklet_cpu;
		[GtkChild]
		unowned Gtk.Image img_docklet_clock;
		[GtkChild]
		unowned Gtk.Image img_docklet_desktop;
		[GtkChild]
		unowned Gtk.Image img_docklet_digital_clock;
		[GtkChild]
		unowned Gtk.Image img_docklet_mpris;
		[GtkChild]
		unowned Gtk.Image img_docklet_battery;
		[GtkChild]
		unowned Gtk.Image img_docklet_volume;
		[GtkChild]
		unowned Gtk.Image img_docklet_screenshot;
		[GtkChild]
		unowned Gtk.Image img_docklet_session;
		[GtkChild]
		unowned Gtk.Image img_docklet_preferences;
		[GtkChild]
		unowned Gtk.Stack dock_preferences;
		[GtkChild]
		unowned Gtk.StackSwitcher dock_preferences_switcher;
		
		bool updating_docklets = false;
		bool updating_monitors = false;
		bool signals_connected = false;
		string previous_monitor = "";
		
		Gtk.CssProvider popup_css;
		Gdk.Screen popup_css_screen;
		
		public PreferencesWindow (DockController controller)
		{
			Object (controller: controller);
		}

		public void show_page (string page_name)
		{
			dock_preferences.set_visible_child_name (page_name);
		}
		
		construct
		{
			set_title (_("Wayplank Preferences"));
			set_role ("preferences");
			configure_hide_mode_rows ();
			set_decorated (true);
			set_destroy_with_parent (true);
			set_position (Gtk.WindowPosition.CENTER);
			set_type_hint (Gdk.WindowTypeHint.DIALOG);
			set_keep_above (true);
			set_focus_on_map (true);
			set_default_size (640, 520);
			
			dock_preferences.set_transition_type (Gtk.StackTransitionType.SLIDE_LEFT_RIGHT);
			dock_preferences.set_transition_duration (200);
			
			dock_preferences_switcher.set_homogeneous (true);
			dock_preferences_switcher.set_hexpand (true);
			dock_preferences_switcher.set_halign (Gtk.Align.FILL);
			foreach (var child in dock_preferences_switcher.get_children ()) {
				child.hexpand = true;
				child.halign = Gtk.Align.FILL;
			}
			
			popup_css = new Gtk.CssProvider ();
			try {
				popup_css.load_from_data (
					"menu > arrow.top, menu > arrow.bottom { min-height: 0; min-width: 0; padding: 0; border-width: 0; -gtk-icon-source: none; }\n" +
					"headerbar stackswitcher, headerbar .stack-switcher { margin-left: 2px; margin-right: 2px; }\n" +
					"headerbar stackswitcher button, headerbar .stack-switcher button { padding-left: 14px; padding-right: 14px; font-weight: bold; }\n"
				);
			} catch (GLib.Error e) {
				warning ("Unable to load preferences menu CSS: %s", e.message);
			}
			popup_css_screen = get_screen ();
			Gtk.StyleContext.add_provider_for_screen (popup_css_screen, popup_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			
			prefs = controller.prefs;
			var stack = (get_child () as Gtk.Widget);
			remove (stack);
			var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
			content.pack_start (stack, true, true, 0);
			var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
			actions.set_margin_start (12);
			actions.set_margin_end (12);
			actions.set_margin_top (8);
			actions.set_margin_bottom (12);
			actions.set_halign (Gtk.Align.CENTER);
			var ok_button = new Gtk.Button.with_label (_("OK"));
			ok_button.set_size_request (160, 36);
			ok_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			ok_button.clicked.connect (() => hide ());
			actions.pack_end (ok_button, false, false, 0);
			content.pack_end (actions, false, false, 0);
			add (content);
			ok_button.set_can_default (true);
			set_default (ok_button);
			content.show_all ();
			
			init_dock_tab ();
			init_window_tab ();
			init_docklets_tab ();
			connect_signals ();
			
			notify["controller"].connect (controller_changed);
			destroy.connect (() => {
				disconnect_signals ();
			});
		}

		~PreferencesWindow ()
		{
			disconnect_signals ();
			if (popup_css_screen != null && popup_css != null)
				Gtk.StyleContext.remove_provider_for_screen (popup_css_screen, popup_css);
		}

		void configure_hide_mode_rows ()
		{
			foreach (unowned Gtk.CellRenderer renderer in cb_hidemode.get_cells ()) {
				cb_hidemode.set_cell_data_func (renderer, (layout, cell, model, iter) => {
					string id = "";
					model.get (iter, 1, out id);
					if (id != "") {
						var mode = (HideType) int.parse (id);
						bool supported = WindowCapabilities.hide_mode_supported (mode);
						cell.sensitive = supported;
						if (cell is Gtk.CellRendererText && WindowControl.is_labwc () && !supported) {
							string text = "";
							model.get (iter, 0, out text);
							if (!text.contains ("(Requires KWin)"))
								((Gtk.CellRendererText) cell).text = text + " (Requires KWin)";
						}
					}
				});
			}
		}

		void controller_changed ()
		{
			disconnect_signals ();
			
			prefs = controller.prefs;
			
			init_dock_tab ();
			init_window_tab ();
			init_docklets_tab ();
			connect_signals ();
		}
		
		public override bool key_press_event (Gdk.EventKey event)
		{
			if (event.keyval == Gdk.Key.Escape)
				hide ();
			
			return base.key_press_event (event);
		}
		
		void prefs_changed (Object o, ParamSpec prop)
		{
			switch (prop.name) {
			case "Alignment":
				cb_alignment.active_id = ((int) prefs.Alignment).to_string ();
				break;
			case "CurrentWorkspaceOnly":
				sw_workspace_only.set_active (prefs.CurrentWorkspaceOnly);
				break;
			case "IconSize":
				adj_iconsize.value = prefs.IconSize;
				break;
			case "ItemsAlignment":
				cb_items_alignment.active_id = ((int) prefs.ItemsAlignment).to_string ();
				break;
			case "HideMode":
				var hide_active = (prefs.HideMode != HideType.NONE);
				sw_hide.set_active (hide_active);
				if (hide_active)
					cb_hidemode.active_id = ((int) prefs.HideMode).to_string ();
				break;
			case "LockItems":
				sw_lock_items.set_active (prefs.LockItems);
				break;
			case "Monitor":
				rebuild_monitor_list ();
				break;
			case "Offset":
				adj_offset.value = prefs.Offset;
				break;
			case "PinnedOnly":
				sw_show_unpinned.set_active (!prefs.PinnedOnly);
				break;
			case "Position":
				cb_position.active_id = ((int) prefs.Position).to_string ();
				break;
			case "PressureReveal":
				sw_pressure_reveal.set_active (prefs.PressureReveal);
				break;
			case "Theme":
				var pos = 0;
				foreach (unowned string theme in Plank.Theme.get_theme_list ()) {
					if (theme == prefs.Theme)
						cb_theme.set_active (pos);
					pos++;
				}
				break;
			case "HideDelay":
				adj_hide_delay.value = prefs.HideDelay;
				break;
			case "UnhideDelay":
				adj_unhide_delay.value = prefs.UnhideDelay;
				break;
			case "ZoomEnabled":
				sw_zoom_enabled.set_active (prefs.ZoomEnabled);
				break;
			case "ZoomPercent":
				adj_zoom_percent.value = prefs.ZoomPercent;
				break;
			case "WindowClickBehavior":
				cb_window_click_behavior.active_id = prefs.WindowClickBehavior.to_string ();
				break;
			case "RestoreMinimizedWindows":
				sw_restore_minimized.set_active (prefs.RestoreMinimizedWindows);
				break;
			case "ShowRunningIndicators":
				sw_show_running_indicators.set_active (prefs.ShowRunningIndicators);
				break;
			case "ShowAttentionIndicators":
				sw_show_attention_indicators.set_active (prefs.ShowAttentionIndicators);
				break;
			// Ignored settings
			case "DockItems":
				break;
			default:
				warning ("%s not supported", prop.name);
				break;
			}
			
		}
		
		void theme_changed (Gtk.ComboBox widget)
		{
			prefs.Theme = ((Gtk.ComboBoxText) widget).get_active_text ();
		}
		
		void hidemode_changed (Gtk.ComboBox widget)
		{
			var mode = (HideType) int.parse (widget.get_active_id ());
			if (WindowCapabilities.hide_mode_supported (mode))
				prefs.HideMode = mode;
			else
				cb_hidemode.active_id = ((int) HideType.DODGE_MAXIMIZED).to_string ();
		}
		
		void position_changed (Gtk.ComboBox widget)
		{
			prefs.Position = (Gtk.PositionType) int.parse (widget.get_active_id ());
		}
		
		void alignment_changed (Gtk.ComboBox widget)
		{
			prefs.Alignment = (Gtk.Align) int.parse (widget.get_active_id ());
			cb_items_alignment.sensitive = (prefs.Alignment == Gtk.Align.FILL);
			s_offset.sensitive = (prefs.Alignment == Gtk.Align.CENTER);
		}
		
		void items_alignment_changed (Gtk.ComboBox widget)
		{
			prefs.ItemsAlignment = (Gtk.Align) int.parse (widget.get_active_id ());
		}
		
		void hide_toggled (GLib.Object widget, ParamSpec param)
		{
			if (((Gtk.Switch) widget).get_active ()) {
				var active_id = cb_hidemode.get_active_id ();
				var mode = (active_id != null && active_id != "") ? (HideType) int.parse (active_id) : HideType.INTELLIGENT;
				if (mode == HideType.NONE)
					mode = HideType.INTELLIGENT;
				if (WindowCapabilities.hide_mode_supported (mode))
					prefs.HideMode = mode;
				else
					prefs.HideMode = HideType.DODGE_MAXIMIZED;
				cb_hidemode.active_id = ((int) prefs.HideMode).to_string ();
				cb_hidemode.sensitive = true;
				sp_hide_delay.sensitive = true;
				sp_unhide_delay.sensitive = true;
				sw_pressure_reveal.sensitive = true;
			} else {
				prefs.HideMode = HideType.NONE;
				cb_hidemode.sensitive = false;
				sp_hide_delay.sensitive = false;
				sp_unhide_delay.sensitive = false;
				sw_pressure_reveal.sensitive = false;
			}
		}
		
		void primary_display_toggled (GLib.Object widget, ParamSpec param)
		{
			if (updating_monitors)
				return;
			var is_primary = ((Gtk.Switch) widget).get_active ();
			var display = get_display ();
			var names = Plank.PositionManager.get_monitor_plug_names (display);

			if (is_primary) {
				if (prefs.Monitor != "") {
					previous_monitor = prefs.Monitor;
					if (controller != null)
						controller.last_explicit_monitor = prefs.Monitor;
				}
				prefs.Monitor = "";
				updating_monitors = true;
				var primary_mon = Plank.PositionManager.get_monitor_for_plug_name (display, "");
				for (int i = 0; i < display.get_n_monitors (); i++) {
					if (display.get_monitor (i) == primary_mon) {
						cb_display_plug.set_active (i);
						break;
					}
				}
				cb_display_plug.sensitive = false;
				updating_monitors = false;
			} else {
				cb_display_plug.sensitive = true;
				string target_name = "";
				if (previous_monitor != "") {
					target_name = previous_monitor;
				} else if (controller != null && controller.last_explicit_monitor != "") {
					target_name = controller.last_explicit_monitor;
				}

				int target_pos = -1;
				if (target_name != "") {
					var target_mon = Plank.PositionManager.get_monitor_for_plug_name (display, target_name);
					if (target_mon != null) {
						for (int i = 0; i < display.get_n_monitors (); i++) {
							if (display.get_monitor (i) == target_mon) {
								target_pos = i;
								break;
							}
						}
					}
				}

				// If previous monitor was not found or no longer exists,
				// pick the first monitor that is NOT the primary monitor!
				if (target_pos < 0) {
					var primary_mon = Plank.PositionManager.get_monitor_for_plug_name (display, "");
					for (int i = 0; i < display.get_n_monitors (); i++) {
						if (display.get_monitor (i) != primary_mon) {
							target_pos = i;
							break;
						}
					}
				}

				if (target_pos < 0 && names.length > 0)
					target_pos = 0;

				if (target_pos >= 0 && target_pos < names.length) {
					updating_monitors = true;
					cb_display_plug.set_active (target_pos);
					prefs.Monitor = names[target_pos];
					previous_monitor = names[target_pos];
					if (controller != null)
						controller.last_explicit_monitor = names[target_pos];
					updating_monitors = false;
				} else {
					var active_text = cb_display_plug.get_active_text ();
					if (active_text != null && active_text != "")
						prefs.Monitor = active_text;
				}
			}
		}
		
		void workspace_only_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.CurrentWorkspaceOnly = ((Gtk.Switch) widget).get_active ();
		}

		void autostart_toggled (GLib.Object widget, ParamSpec param)
		{
			var enabled = ((Gtk.Switch) widget).get_active ();
			var autostart_dir = Path.build_filename (Environment.get_user_config_dir (), "autostart");
			var autostart_path = Path.build_filename (autostart_dir, "wayplank.desktop");
			var success = true;

			if (enabled) {
				if (DirUtils.create_with_parents (autostart_dir, 0755) != 0) {
					warning ("Unable to create autostart directory '%s'", autostart_dir);
					success = false;
				} else {
					try {
						FileUtils.set_contents (autostart_path,
							"[Desktop Entry]\n" +
							"Type=Application\n" +
							"Name=Wayplank\n" +
							"Comment=Stupidly simple dock for Wayland\n" +
							"Exec=wayplank\n" +
							"Icon=plank\n" +
							"Terminal=false\n" +
							"X-GNOME-Autostart-enabled=true\n" +
							"X-GNOME-Autostart-Delay=2\n");
					} catch (FileError e) {
						warning ("Unable to create autostart entry '%s': %s", autostart_path, e.message);
						success = false;
					}
				}
			} else if (FileUtils.test (autostart_path, FileTest.EXISTS) && FileUtils.remove (autostart_path) != 0) {
				warning ("Unable to remove autostart entry '%s'", autostart_path);
				success = false;
			}

			if (!success) {
				sw_autostart.notify["active"].disconnect (autostart_toggled);
				sw_autostart.set_active (!enabled);
				sw_autostart.notify["active"].connect (autostart_toggled);
			}
		}
		
		void show_unpinned_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.PinnedOnly = !((Gtk.Switch) widget).get_active ();
		}
		
		void lock_items_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.LockItems = ((Gtk.Switch) widget).get_active ();
		}
		
		void pressure_reveal_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.PressureReveal = ((Gtk.Switch) widget).get_active ();
		}

		void window_click_behavior_changed (Gtk.ComboBox widget)
		{
			prefs.WindowClickBehavior = int.parse (widget.get_active_id ());
		}

		void restore_minimized_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.RestoreMinimizedWindows = ((Gtk.Switch) widget).get_active ();
		}

		void show_running_indicators_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.ShowRunningIndicators = ((Gtk.Switch) widget).get_active ();
		}

		void show_attention_indicators_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.ShowAttentionIndicators = ((Gtk.Switch) widget).get_active ();
		}
		
		void zoom_enabled_toggled (GLib.Object widget, ParamSpec param)
		{
			if (((Gtk.Switch) widget).get_active ()) {
				prefs.ZoomEnabled = true;
				s_zoom_percent.sensitive = true;
			} else {
				prefs.ZoomEnabled = false;
				s_zoom_percent.sensitive = false;
			}
		}
		
		void iconsize_changed (Gtk.Adjustment adj)
		{
			prefs.IconSize = (int) adj.value;
		}
		
		void offset_changed (Gtk.Adjustment adj)
		{
			prefs.Offset = (int) adj.value;
		}
		
		void hide_delay_changed (Gtk.Adjustment adj)
		{
			prefs.HideDelay = (int) adj.value;
		}
		
		void unhide_delay_changed (Gtk.Adjustment adj)
		{
			prefs.UnhideDelay = (int) adj.value;
		}
		
		void zoom_percent_changed (Gtk.Adjustment adj)
		{
			prefs.ZoomPercent = (int) adj.value;
		}
		
		void monitor_changed (Gtk.ComboBox widget)
		{
			if (updating_monitors)
				return;
			var text = ((Gtk.ComboBoxText) widget).get_active_text ();
			if (text != null && text != "") {
				previous_monitor = text;
				if (controller != null)
					controller.last_explicit_monitor = text;
				prefs.Monitor = text;
				updating_monitors = true;
				sw_primary_display.set_active (false);
				cb_display_plug.sensitive = true;
				updating_monitors = false;
			}
		}
		
		void connect_signals ()
		{
			if (signals_connected)
				return;
			signals_connected = true;

			prefs.notify.connect (prefs_changed);
			
			cb_theme.changed.connect (theme_changed);
			cb_hidemode.changed.connect (hidemode_changed);
			cb_position.changed.connect (position_changed);
			adj_hide_delay.value_changed.connect (hide_delay_changed);
			adj_unhide_delay.value_changed.connect (unhide_delay_changed);
			cb_display_plug.changed.connect (monitor_changed);
			adj_iconsize.value_changed.connect (iconsize_changed);
			adj_offset.value_changed.connect (offset_changed);
			adj_zoom_percent.value_changed.connect (zoom_percent_changed);
			cb_window_click_behavior.changed.connect (window_click_behavior_changed);
			sw_hide.notify["active"].connect (hide_toggled);
			sw_primary_display.notify["active"].connect (primary_display_toggled);
			sw_workspace_only.notify["active"].connect (workspace_only_toggled);
			sw_autostart.notify["active"].connect (autostart_toggled);
			sw_show_unpinned.notify["active"].connect (show_unpinned_toggled);
			sw_lock_items.notify["active"].connect (lock_items_toggled);
			sw_pressure_reveal.notify["active"].connect (pressure_reveal_toggled);
			sw_zoom_enabled.notify["active"].connect (zoom_enabled_toggled);
			sw_restore_minimized.notify["active"].connect (restore_minimized_toggled);
			sw_show_running_indicators.notify["active"].connect (show_running_indicators_toggled);
			sw_show_attention_indicators.notify["active"].connect (show_attention_indicators_toggled);
			sw_docklet_trash.notify["active"].connect (docklet_trash_toggled);
			sw_docklet_clock.notify["active"].connect (docklet_clock_toggled);
			sw_docklet_digital_clock.notify["active"].connect (docklet_digital_clock_toggled);
			sw_docklet_battery.notify["active"].connect (docklet_battery_toggled);
			sw_docklet_cpu.notify["active"].connect (docklet_cpu_toggled);
			sw_docklet_desktop.notify["active"].connect (docklet_desktop_toggled);
			sw_docklet_mpris.notify["active"].connect (docklet_mpris_toggled);
			sw_docklet_volume.notify["active"].connect (docklet_volume_toggled);
			sw_docklet_screenshot.notify["active"].connect (docklet_screenshot_toggled);
			sw_docklet_session.notify["active"].connect (docklet_session_toggled);
			sw_docklet_preferences.notify["active"].connect (docklet_preferences_toggled);
			if (controller != null && controller.default_provider != null)
				controller.default_provider.elements_changed.connect (default_provider_elements_changed);
			cb_alignment.changed.connect (alignment_changed);
			cb_items_alignment.changed.connect (items_alignment_changed);
			get_screen ().monitors_changed.connect (rebuild_monitor_list);
		}
		
		void disconnect_signals ()
		{
			if (!signals_connected)
				return;
			signals_connected = false;

			prefs.notify.disconnect (prefs_changed);
			
			cb_theme.changed.disconnect (theme_changed);
			cb_hidemode.changed.disconnect (hidemode_changed);
			cb_position.changed.disconnect (position_changed);
			adj_hide_delay.value_changed.disconnect (hide_delay_changed);
			adj_unhide_delay.value_changed.disconnect (unhide_delay_changed);
			cb_display_plug.changed.disconnect (monitor_changed);
			adj_iconsize.value_changed.disconnect (iconsize_changed);
			adj_offset.value_changed.disconnect (offset_changed);
			adj_zoom_percent.value_changed.disconnect (zoom_percent_changed);
			cb_window_click_behavior.changed.disconnect (window_click_behavior_changed);
			sw_hide.notify["active"].disconnect (hide_toggled);
			sw_primary_display.notify["active"].disconnect (primary_display_toggled);
			sw_workspace_only.notify["active"].disconnect (workspace_only_toggled);
			sw_autostart.notify["active"].disconnect (autostart_toggled);
			sw_show_unpinned.notify["active"].disconnect (show_unpinned_toggled);
			sw_lock_items.notify["active"].disconnect (lock_items_toggled);
			sw_pressure_reveal.notify["active"].disconnect (pressure_reveal_toggled);
			sw_zoom_enabled.notify["active"].disconnect (zoom_enabled_toggled);
			sw_restore_minimized.notify["active"].disconnect (restore_minimized_toggled);
			sw_show_running_indicators.notify["active"].disconnect (show_running_indicators_toggled);
			sw_show_attention_indicators.notify["active"].disconnect (show_attention_indicators_toggled);
			sw_docklet_trash.notify["active"].disconnect (docklet_trash_toggled);
			sw_docklet_clock.notify["active"].disconnect (docklet_clock_toggled);
			sw_docklet_digital_clock.notify["active"].disconnect (docklet_digital_clock_toggled);
			sw_docklet_battery.notify["active"].disconnect (docklet_battery_toggled);
			sw_docklet_cpu.notify["active"].disconnect (docklet_cpu_toggled);
			sw_docklet_desktop.notify["active"].disconnect (docklet_desktop_toggled);
			sw_docklet_mpris.notify["active"].disconnect (docklet_mpris_toggled);
			sw_docklet_volume.notify["active"].disconnect (docklet_volume_toggled);
			sw_docklet_screenshot.notify["active"].disconnect (docklet_screenshot_toggled);
			sw_docklet_session.notify["active"].disconnect (docklet_session_toggled);
			sw_docklet_preferences.notify["active"].disconnect (docklet_preferences_toggled);
			if (controller != null && controller.default_provider != null)
				controller.default_provider.elements_changed.disconnect (default_provider_elements_changed);
			cb_alignment.changed.disconnect (alignment_changed);
			cb_items_alignment.changed.disconnect (items_alignment_changed);
			get_screen ().monitors_changed.disconnect (rebuild_monitor_list);
		}
		
		void rebuild_monitor_list ()
		{
			updating_monitors = true;
			cb_display_plug.remove_all ();
			
			var display = get_display ();
			var names = Plank.PositionManager.get_monitor_plug_names (display);
			int primary_pos = 0;
			int active_pos = -1;
			var primary_mon = Plank.PositionManager.get_monitor_for_plug_name (display, "");
			var current_mon = Plank.PositionManager.get_monitor_for_plug_name (display, prefs.Monitor);
			
			for (int pos = 0; pos < names.length; pos++) {
				cb_display_plug.append ("%i".printf (pos), names[pos]);
				if (primary_mon != null && display.get_monitor (pos) == primary_mon)
					primary_pos = pos;
				if (current_mon != null && display.get_monitor (pos) == current_mon)
					active_pos = pos;
			}
			
			if (prefs.Monitor == "") {
				cb_display_plug.set_active (primary_pos);
				sw_primary_display.set_active (true);
				cb_display_plug.sensitive = false;
			} else if (active_pos >= 0) {
				cb_display_plug.set_active (active_pos);
				sw_primary_display.set_active (false);
				cb_display_plug.sensitive = true;
				if (prefs.Monitor != names[active_pos])
					prefs.Monitor = names[active_pos];
			} else if (names.length > 0) {
				cb_display_plug.set_active (0);
				sw_primary_display.set_active (false);
				cb_display_plug.sensitive = true;
			}
			
			updating_monitors = false;
		}

		void init_dock_tab ()
		{
			if (prefs.Monitor != "") {
				previous_monitor = prefs.Monitor;
				if (controller != null)
					controller.last_explicit_monitor = prefs.Monitor;
			} else if (controller != null && controller.last_explicit_monitor != "") {
				previous_monitor = controller.last_explicit_monitor;
			}

			var pos = 0;
			cb_theme.remove_all ();
			foreach (unowned string theme in Plank.Theme.get_theme_list ()) {
				cb_theme.append ("%i".printf (pos), theme);
				if (theme == prefs.Theme)
					cb_theme.set_active (pos);
				pos++;
			}

			var effective_mode = (prefs.HideMode != HideType.NONE && !WindowCapabilities.hide_mode_supported (prefs.HideMode))
				? HideType.DODGE_MAXIMIZED
				: prefs.HideMode;
			cb_hidemode.active_id = ((int) effective_mode).to_string ();
			cb_hidemode.sensitive = (prefs.HideMode != HideType.NONE);
			cb_position.active_id = ((int) prefs.Position).to_string ();
			adj_hide_delay.value = prefs.HideDelay;
			adj_unhide_delay.value = prefs.UnhideDelay;

			rebuild_monitor_list ();
			
			sp_hide_delay.sensitive = (prefs.HideMode != HideType.NONE);
			sp_unhide_delay.sensitive = (prefs.HideMode != HideType.NONE);
			
			adj_iconsize.value = prefs.IconSize;
			adj_offset.value = prefs.Offset;
			adj_zoom_percent.value = prefs.ZoomPercent;
			s_offset.sensitive = (prefs.Alignment == Gtk.Align.CENTER);
			s_zoom_percent.sensitive = prefs.ZoomEnabled;
			sw_hide.set_active (prefs.HideMode != HideType.NONE);
			sw_primary_display.set_active (prefs.Monitor == "");
			sw_workspace_only.set_active (prefs.CurrentWorkspaceOnly);
			sw_autostart.set_active (FileUtils.test (
				Path.build_filename (Environment.get_user_config_dir (), "autostart", "wayplank.desktop"),
				FileTest.IS_REGULAR));
			sw_show_unpinned.set_active (!prefs.PinnedOnly);
			sw_lock_items.set_active (prefs.LockItems);
			bool is_wayland = environment_is_session_type (XdgSessionType.WAYLAND);
			sw_pressure_reveal.set_active (prefs.PressureReveal);
			sw_pressure_reveal.sensitive = (prefs.HideMode != HideType.NONE) && !is_wayland;
			if (is_wayland)
				sw_pressure_reveal.tooltip_text = _("Pressure Reveal is not supported under Wayland");
			sw_zoom_enabled.set_active (prefs.ZoomEnabled);
			cb_alignment.active_id = ((int) prefs.Alignment).to_string ();
			cb_items_alignment.active_id = ((int) prefs.ItemsAlignment).to_string ();
			cb_items_alignment.sensitive = (prefs.Alignment == Gtk.Align.FILL);
		}

		void init_window_tab ()
		{
			cb_window_click_behavior.active_id = prefs.WindowClickBehavior.to_string ();
			sw_restore_minimized.set_active (prefs.RestoreMinimizedWindows);
			sw_show_running_indicators.set_active (prefs.ShowRunningIndicators);
			sw_show_attention_indicators.set_active (prefs.ShowAttentionIndicators);
		}
		
		void toggle_docklet_uri (GLib.Object widget, string uri)
		{
			if (updating_docklets)
				return;
			var enabled = ((Gtk.Switch) widget).get_active ();
			unowned DefaultApplicationDockItemProvider? default_provider = controller.default_provider as DefaultApplicationDockItemProvider;
			if (default_provider == null)
				return;
			if (enabled) {
				if (default_provider.item_for_uri (uri) == null)
					default_provider.add_item_with_uri (uri);
			} else {
				unowned DockItem? di = default_provider.item_for_uri (uri);
				if (di != null)
					di.delete ();
			}
		}

		void docklet_trash_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://trash");
		}

		void docklet_clock_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://clock");
		}

		void docklet_digital_clock_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://digital-clock");
		}

		void docklet_battery_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://battery");
		}

		void docklet_cpu_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://cpu");
		}

		void docklet_desktop_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://desktop");
		}

		void docklet_mpris_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://mpris");
		}

		void docklet_volume_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://volume");
		}

		void docklet_screenshot_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://screenshot");
		}

		void docklet_session_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://session");
		}

		void docklet_preferences_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://preferences");
		}

		void default_provider_elements_changed (Gee.List<DockElement> added, Gee.List<DockElement> removed)
		{
			init_docklets_tab ();
		}

		void init_docklets_tab ()
		{
			updating_docklets = true;
			unowned DefaultApplicationDockItemProvider? default_provider = controller.default_provider as DefaultApplicationDockItemProvider;
			if (default_provider != null) {
				sw_docklet_trash.set_active (default_provider.item_for_uri ("docklet://trash") != null);
				sw_docklet_clock.set_active (default_provider.item_for_uri ("docklet://clock") != null);
				sw_docklet_digital_clock.set_active (default_provider.item_for_uri ("docklet://digital-clock") != null);
				sw_docklet_battery.set_active (default_provider.item_for_uri ("docklet://battery") != null);
				sw_docklet_cpu.set_active (default_provider.item_for_uri ("docklet://cpu") != null);
				sw_docklet_desktop.set_active (default_provider.item_for_uri ("docklet://desktop") != null);
				sw_docklet_mpris.set_active (default_provider.item_for_uri ("docklet://mpris") != null);
				sw_docklet_volume.set_active (default_provider.item_for_uri ("docklet://volume") != null);
				sw_docklet_screenshot.set_active (default_provider.item_for_uri ("docklet://screenshot") != null);
				sw_docklet_session.set_active (default_provider.item_for_uri ("docklet://session") != null);
				sw_docklet_preferences.set_active (default_provider.item_for_uri ("docklet://preferences") != null);
			} else {
				sw_docklet_trash.set_active (false);
				sw_docklet_clock.set_active (false);
				sw_docklet_digital_clock.set_active (false);
				sw_docklet_battery.set_active (false);
				sw_docklet_cpu.set_active (false);
				sw_docklet_desktop.set_active (false);
				sw_docklet_mpris.set_active (false);
				sw_docklet_volume.set_active (false);
				sw_docklet_screenshot.set_active (false);
				sw_docklet_session.set_active (false);
				sw_docklet_preferences.set_active (false);
			}
			
			update_docklet_icons ();
			updating_docklets = false;
		}

		void ensure_docklet_icon (Gtk.Image? img, string system_icon_name, string fallback_resource)
		{
			if (img == null)
				return;
			
			var default_theme = Gtk.IconTheme.get_default ();
			if (default_theme.has_icon (system_icon_name)) {
				img.set_from_icon_name (system_icon_name, Gtk.IconSize.DND);
			} else {
				try {
					var pb = new Gdk.Pixbuf.from_resource_at_scale (fallback_resource, 35, 35, true);
					img.set_from_pixbuf (pb);
				} catch (GLib.Error e) {
					img.set_from_icon_name (system_icon_name, Gtk.IconSize.DND);
				}
			}
			img.pixel_size = 35;
		}

		void update_docklet_icons ()
		{
			ensure_docklet_icon (img_docklet_trash, "user-trash", "/net/launchpad/plank/docklets/trash.svg");
			ensure_docklet_icon (img_docklet_cpu, "utilities-system-monitor", "/net/launchpad/plank/docklets/cpu.svg");
			ensure_docklet_icon (img_docklet_clock, "preferences-system-time", "/net/launchpad/plank/docklets/clock.svg");
			ensure_docklet_icon (img_docklet_desktop, "user-desktop", "/net/launchpad/plank/docklets/desktop.svg");
			ensure_docklet_icon (img_docklet_digital_clock, "org.kde.plasma.digitalclock", "/net/launchpad/plank/docklets/digital-clock.svg");
			ensure_docklet_icon (img_docklet_mpris, "multimedia-player", "/net/launchpad/plank/docklets/mpris.svg");
			ensure_docklet_icon (img_docklet_battery, "battery-full", "/net/launchpad/plank/docklets/battery.svg");
			ensure_docklet_icon (img_docklet_volume, "audio-volume-high", "/net/launchpad/plank/docklets/volume.svg");
			ensure_docklet_icon (img_docklet_screenshot, "applets-screenshooter", "/net/launchpad/plank/docklets/screenshot.svg");
			ensure_docklet_icon (img_docklet_session, "system-shutdown", "/net/launchpad/plank/docklets/session.svg");
			ensure_docklet_icon (img_docklet_preferences, "plank", "/net/launchpad/plank/docklets/preferences.svg");
		}
	}
}
