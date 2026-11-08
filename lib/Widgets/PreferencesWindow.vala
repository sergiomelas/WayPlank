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
	[GtkTemplate (ui = "/net/launchpad/plank/ui/preferences.ui")]
	public class PreferencesWindow : Gtk.Window
	{
		public static bool is_open { get; private set; default = false; }
		public static PreferencesWindow? active_instance { get; private set; default = null; }
		public bool suppress_destroy_on_hide { get; set; default = false; }

		/**
		 * The controller for this dock.
		 */
		public DockController controller { get; construct set; }
		
		DockPreferences prefs;
		
		[GtkChild]
		unowned Gtk.ComboBoxText cb_theme;
		[GtkChild]
		unowned Gtk.Button btn_add_theme;
		[GtkChild]
		unowned Gtk.Button btn_del_theme;
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
		unowned Gtk.Scale s_hide_delay;
		[GtkChild]
		unowned Gtk.SpinButton sp_unhide_delay;
		[GtkChild]
		unowned Gtk.Scale s_unhide_delay;
		[GtkChild]
		unowned Gtk.SpinButton sp_offset;
		[GtkChild]
		unowned Gtk.Scale s_offset;
		[GtkChild]
		unowned Gtk.SpinButton sp_zoom_percent;
		[GtkChild]
		unowned Gtk.Scale s_zoom_percent;
		[GtkChild]
		unowned Gtk.Scale s_iconsize;
		[GtkChild]
		unowned Gtk.SpinButton sp_iconsize;
		[GtkChild]
		unowned Gtk.Label l_iconsize_hint;
		[GtkChild]
		unowned Gtk.Label l_icon_alignment;
		[GtkChild]
		unowned Gtk.Label l_hide_mode;
		[GtkChild]
		unowned Gtk.Label l_pressure1;
		[GtkChild]
		unowned Gtk.Label l_pressure2;
		[GtkChild]
		unowned Gtk.Label l_pressure;
		[GtkChild]
		unowned Gtk.Label l_anticipate_zoom;
		
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
		unowned Gtk.Label l_primary_display;
		[GtkChild]
		unowned Gtk.Switch sw_primary_display;
		[GtkChild]
		unowned Gtk.Switch sw_workspace_only;
		[GtkChild]
		unowned Gtk.Switch sw_show_unpinned;
		[GtkChild]
		unowned Gtk.Switch sw_scroll_overflow;
		[GtkChild]
		unowned Gtk.Switch sw_lock_items;
		[GtkChild]
		unowned Gtk.Switch sw_pressure_reveal;
		[GtkChild]
		unowned Gtk.Label l_reserve_space;
		[GtkChild]
		unowned Gtk.Switch sw_reserve_space;
		[GtkChild]
		unowned Gtk.Switch sw_anticipate_zoom;
		[GtkChild]
		unowned Gtk.Switch sw_tooltips_enabled;
		[GtkChild]
		unowned Gtk.Switch sw_zoom_enabled;
		[GtkChild]
		unowned Gtk.Switch sw_categorize_items;
		[GtkChild]
		unowned Gtk.Button btn_reorder_free_items;
		[GtkChild]
		unowned Gtk.Label l_docklets_on_right;
		[GtkChild]
		unowned Gtk.Switch sw_docklets_on_right;
		[GtkChild]
		unowned Gtk.Switch sw_anchor_always_left;
		[GtkChild]
		unowned Gtk.Label l_accordion_docklets;
		[GtkChild]
		unowned Gtk.Switch sw_accordion_docklets;
		[GtkChild]
		unowned Gtk.Label l_accordion_click_to_expand;
		[GtkChild]
		unowned Gtk.Switch sw_accordion_click_to_expand;
		[GtkChild]
		unowned Gtk.Label l_accordion_delay;
		[GtkChild]
		unowned Gtk.Box box_accordion_delay;
		[GtkChild]
		unowned Gtk.SpinButton sp_accordion_delay;
		[GtkChild]
		unowned Gtk.Scale s_accordion_delay;
		[GtkChild]
		unowned Gtk.Adjustment adj_accordion_delay;
		[GtkChild]
		unowned Gtk.Label l_pinned_accordion;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_pinned_accordion;
		[GtkChild]
		unowned Gtk.SpinButton sp_pinned_count;
		[GtkChild]
		unowned Gtk.Adjustment adj_pinned_count;
		[GtkChild]
		unowned Gtk.Switch sw_autostart;
		[GtkChild]
		unowned Gtk.Label l_effect_duration;
		[GtkChild]
		unowned Gtk.Box box_effect_duration;
		[GtkChild]
		unowned Gtk.SpinButton sp_effect_duration;
		[GtkChild]
		unowned Gtk.Scale s_effect_duration;
		[GtkChild]
		unowned Gtk.Adjustment adj_effect_duration;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_active_highlight;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_launch_animation;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_unpin_animation;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_system_menu_access;
		[GtkChild]
		unowned Gtk.ComboBoxText cb_window_click_behavior;
		[GtkChild]
		unowned Gtk.Switch sw_show_window_cards;
		[GtkChild]
		unowned Gtk.Switch sw_restore_minimized;
		[GtkChild]
		unowned Gtk.Switch sw_show_running_indicators;
		[GtkChild]
		unowned Gtk.Switch sw_show_attention_indicators;
		[GtkChild]
		unowned Gtk.Switch sw_show_trash;
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
		unowned Gtk.Switch sw_docklet_brightness;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_ejector;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_weather;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_network;
		[GtkChild]
		unowned Gtk.Switch sw_docklet_dnd;
		[GtkChild]
		unowned Gtk.Image img_docklet_cpu;
		[GtkChild]
		unowned Gtk.Image img_docklet_dnd;
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
		unowned Gtk.Image img_docklet_brightness;
		[GtkChild]
		unowned Gtk.Image img_docklet_ejector;
		[GtkChild]
		unowned Gtk.Image img_docklet_weather;
		[GtkChild]
		unowned Gtk.Image img_docklet_network;
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
		
		Gtk.SizeGroup sg_appearance_spin;
		Gtk.SizeGroup sg_behaviour_spin;

		public PreferencesWindow (DockController controller)
		{
			Object (controller: controller);
		}

		public void show_page (string page_name)
		{
			dock_preferences.set_visible_child_name (page_name);
			clear_spinbutton_focus ();
		}

		void clear_spinbutton_focus ()
		{
			set_focus (null);
			if (sp_offset != null)
				sp_offset.select_region (0, 0);
			if (sp_iconsize != null)
				sp_iconsize.select_region (0, 0);
			if (sp_zoom_percent != null)
				sp_zoom_percent.select_region (0, 0);
			if (sp_hide_delay != null)
				sp_hide_delay.select_region (0, 0);
			if (sp_unhide_delay != null)
				sp_unhide_delay.select_region (0, 0);
			if (sp_effect_duration != null)
				sp_effect_duration.select_region (0, 0);
			if (sp_accordion_delay != null)
				sp_accordion_delay.select_region (0, 0);
			if (sp_pinned_count != null)
				sp_pinned_count.select_region (0, 0);
		}

		void on_stack_page_changed (GLib.Object sender, ParamSpec prop)
		{
			clear_spinbutton_focus ();
		}
		
		construct
		{
			active_instance = this;
			PlankCompat.i18n_translate_widget (this);
			set_title (_("WayPlank Preferences"));
			set_role ("preferences");
			configure_hide_mode_rows ();
			set_decorated (true);
			set_destroy_with_parent (true);
			set_position (Gtk.WindowPosition.CENTER);
			set_type_hint (Gdk.WindowTypeHint.DIALOG);
			set_keep_above (true);
			set_focus_on_map (true);
			set_default_size (600, 520);

			sg_appearance_spin = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
			sg_appearance_spin.add_widget (sp_offset);
			sg_appearance_spin.add_widget (sp_iconsize);

			sg_behaviour_spin = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
			sg_behaviour_spin.add_widget (sp_hide_delay);
			sg_behaviour_spin.add_widget (sp_unhide_delay);
			sg_behaviour_spin.add_widget (sp_zoom_percent);
			sg_behaviour_spin.add_widget (sp_effect_duration);
			
			dock_preferences.set_transition_type (Gtk.StackTransitionType.SLIDE_LEFT_RIGHT);
			dock_preferences.set_transition_duration (200);
			
			dock_preferences_switcher.set_homogeneous (true);
			dock_preferences_switcher.set_hexpand (true);
			dock_preferences_switcher.set_halign (Gtk.Align.FILL);
			foreach (var child in dock_preferences_switcher.get_children ()) {
				child.hexpand = true;
				child.halign = Gtk.Align.FILL;
			}

			foreach (var cell in cb_theme.get_cells ()) {
				var text_cell = cell as Gtk.CellRendererText;
				if (text_cell != null) {
					text_cell.ellipsize = Pango.EllipsizeMode.END;
				}
			}
			foreach (var cell in cb_active_highlight.get_cells ()) {
				var text_cell = cell as Gtk.CellRendererText;
				if (text_cell != null) {
					text_cell.ellipsize = Pango.EllipsizeMode.END;
				}
			}
			foreach (var cell in cb_launch_animation.get_cells ()) {
				var text_cell = cell as Gtk.CellRendererText;
				if (text_cell != null) {
					text_cell.ellipsize = Pango.EllipsizeMode.END;
				}
			}
			foreach (var cell in cb_unpin_animation.get_cells ()) {
				var text_cell = cell as Gtk.CellRendererText;
				if (text_cell != null) {
					text_cell.ellipsize = Pango.EllipsizeMode.END;
				}
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
			
			this.map.connect (() => {
				is_open = true;
				update_effect_duration_visibility ();
				update_accordion_visibility ();
				update_icon_size_feedback ();
				clear_spinbutton_focus ();
			});
			this.map_event.connect (() => {
				clear_spinbutton_focus ();
				return false;
			});
			this.show.connect (() => {
				is_open = true;
				active_instance = this;
				update_effect_duration_visibility ();
				update_accordion_visibility ();
				update_icon_size_feedback ();
				clear_spinbutton_focus ();
			});
			this.hide.connect (() => {
				flush_all_settings_to_disk ();
				if (suppress_destroy_on_hide)
					return;
				is_open = false;
				if (active_instance == this)
					active_instance = null;
			});
			this.delete_event.connect (() => {
				flush_all_settings_to_disk ();
				return false;
			});
			
			notify["controller"].connect (controller_changed);
			destroy.connect (() => {
				flush_all_settings_to_disk ();
				is_destroyed = true;
				is_open = false;
				if (active_instance == this)
					active_instance = null;
				disconnect_signals ();
				if (popup_css_screen != null && popup_css != null) {
					Gtk.StyleContext.remove_provider_for_screen (popup_css_screen, popup_css);
					popup_css = null;
				}
				if (s_iconsize != null && slider_css != null) {
					s_iconsize.get_style_context ().remove_provider (slider_css);
					slider_css = null;
				}
			});
		}

		bool is_destroyed = false;

		void flush_all_settings_to_disk ()
		{
			if (controller != null)
				controller.flush_pending_serialization ();
			if (prefs != null)
				prefs.flush_to_disk ();
			AppUsageService.flush_if_active ();
		}

		~PreferencesWindow ()
		{
			flush_all_settings_to_disk ();
			is_destroyed = true;
			is_open = false;
			if (active_instance == this)
				active_instance = null;
			disconnect_signals ();
			if (popup_css_screen != null && popup_css != null)
				Gtk.StyleContext.remove_provider_for_screen (popup_css_screen, popup_css);
			if (s_iconsize != null && slider_css != null)
				s_iconsize.get_style_context ().remove_provider (slider_css);
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
							string req_kwin = _(" (Requires KWin)");
							if (!text.contains (req_kwin))
								((Gtk.CellRendererText) cell).text = text + req_kwin;
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
				update_alignment_sensitivity ();
				break;
			case "CurrentWorkspaceOnly":
				sw_workspace_only.set_active (prefs.CurrentWorkspaceOnly);
				sw_workspace_only.sensitive = false;
				break;
			case "IconSize":
				adj_iconsize.value = prefs.IconSize;
				update_icon_size_feedback ();
				break;
			case "ScrollOverflow":
				sw_scroll_overflow.set_active (prefs.ScrollOverflow);
				update_icon_size_feedback ();
				break;
			case "ItemsAlignment":
				cb_items_alignment.active_id = ((int) prefs.ItemsAlignment).to_string ();
				break;
			case "HideMode":
				var hide_active = (prefs.HideMode != HideType.NONE);
				if (hide_active)
					cb_hidemode.active_id = ((int) prefs.HideMode).to_string ();
				if (sw_hide.get_active () != hide_active)
					sw_hide.set_active (hide_active);
				update_hide_sensitivity ();
				break;
			case "ReserveSpace":
				sw_reserve_space.set_active (prefs.ReserveSpace);
				break;
			case "LockItems":
				sw_lock_items.set_active (prefs.LockItems);
				break;
			case "Monitor":
				rebuild_monitor_list ();
				update_icon_size_feedback ();
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
				update_zoom_sensitivity ();
				break;
			case "AnticipateZoom":
				sw_anticipate_zoom.set_active (prefs.AnticipateZoom);
				break;
			case "TooltipsEnabled":
				sw_tooltips_enabled.set_active (prefs.TooltipsEnabled);
				break;
			case "CategorizeItems":
				sw_categorize_items.set_active (prefs.CategorizeItems);
				update_accordion_visibility ();
				break;
			case "AnchorAlwaysLeft":
				sw_anchor_always_left.set_active (prefs.AnchorAlwaysLeft);
				break;
			case "DockletsOnRight":
				sw_docklets_on_right.set_active (prefs.DockletsOnRight);
				break;
			case "AccordionDocklets":
				sw_accordion_docklets.set_active (prefs.AccordionDocklets);
				update_accordion_visibility ();
				break;
			case "AccordionClickToExpand":
				sw_accordion_click_to_expand.set_active (prefs.AccordionClickToExpand);
				break;
			case "AccordionDelay":
				double delay_sec = (prefs.AccordionDelay >= DockPreferences.MIN_ACCORDION_DELAY ? prefs.AccordionDelay : DockPreferences.DEFAULT_ACCORDION_DELAY) / 1000.0;
				if (Math.fabs (adj_accordion_delay.value - delay_sec) > 0.05) {
					adj_accordion_delay.value = delay_sec;
				}
				break;
			case "PinnedAccordionMode":
				cb_pinned_accordion.active_id = prefs.PinnedAccordionMode.clamp (DockPreferences.PINNED_ACCORDION_OFF, DockPreferences.PINNED_ACCORDION_TOP_N).to_string ();
				update_accordion_visibility ();
				break;
			case "PinnedAccordionCount":
				if ((int) Math.round (adj_pinned_count.value) != prefs.PinnedAccordionCount)
					adj_pinned_count.value = prefs.PinnedAccordionCount.clamp (DockPreferences.MIN_PINNED_ACCORDION_COUNT, DockPreferences.MAX_PINNED_ACCORDION_COUNT);
				break;
			case "ZoomPercent":
				adj_zoom_percent.value = prefs.ZoomPercent;
				break;
			case "WindowClickBehavior":
				cb_window_click_behavior.active_id = prefs.WindowClickBehavior.to_string ();
				break;
			case "SystemMenuAccess":
				update_system_menu_access_options ();
				break;
			case "ShowWindowCards":
				sw_show_window_cards.set_active (prefs.ShowWindowCards);
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
			case "ActiveHighlight":
				cb_active_highlight.active_id = prefs.ActiveHighlight.clamp (0, DockPreferences.MAX_ACTIVE_HIGHLIGHT).to_string ();
				update_effect_duration_visibility ();
				break;
			case "LaunchAnimation":
				cb_launch_animation.active_id = prefs.LaunchAnimation.clamp (0, DockPreferences.MAX_LAUNCH_ANIMATION).to_string ();
				update_effect_duration_visibility ();
				break;
			case "UnpinAnimation":
				cb_unpin_animation.active_id = prefs.UnpinAnimation.clamp (0, DockPreferences.MAX_UNPIN_ANIMATION).to_string ();
				update_effect_duration_visibility ();
				break;
			case "EffectDuration":
				if ((int) Math.round (adj_effect_duration.value) != prefs.EffectDuration)
					adj_effect_duration.value = prefs.EffectDuration.clamp (DockPreferences.MIN_EFFECT_DURATION, DockPreferences.MAX_EFFECT_DURATION);
				break;
			// Ignored settings
			case "DockItems":
			case "FreeDockItems":
			case "CategorizedDockItems":
			case "AutoPinning":
			case "ShowDockItem":
				break;
			default:
				warning ("%s not supported", prop.name);
				break;
			}
			
		}
		
		void theme_changed (Gtk.ComboBox widget)
		{
			var current_theme = ((Gtk.ComboBoxText) widget).get_active_text ();
			if (current_theme != null && current_theme != "") {
				prefs.Theme = current_theme;
				cb_theme.tooltip_text = current_theme;
				update_theme_buttons ();
			}
		}

		void rebuild_theme_list ()
		{
			cb_theme.changed.disconnect (theme_changed);
			var pos = 0;
			cb_theme.remove_all ();
			foreach (unowned string theme in Plank.Theme.get_theme_list ()) {
				cb_theme.append ("%i".printf (pos), theme);
				if (theme == prefs.Theme)
					cb_theme.set_active (pos);
				pos++;
			}
			cb_theme.tooltip_text = prefs.Theme;
			update_theme_buttons ();
			cb_theme.changed.connect (theme_changed);
		}

		void update_theme_buttons ()
		{
			string current = cb_theme.get_active_text () ?? prefs.Theme;
			bool is_user = ThemeManager.is_user_theme (current);
			btn_del_theme.sensitive = is_user;
			if (is_user) {
				btn_del_theme.tooltip_text = _("Delete user theme '%s'").printf (current);
			} else {
				btn_del_theme.tooltip_text = _("System themes cannot be deleted");
			}
		}

		void on_add_theme_clicked ()
		{
			// Temporarily hide PreferencesWindow while choosing theme archive
			suppress_destroy_on_hide = true;
			this.hide ();
			suppress_destroy_on_hide = false;

			var chooser = new Gtk.FileChooserNative (
				_("Install WayPlank Theme"),
				null,
				Gtk.FileChooserAction.OPEN,
				_("_Open"),
				_("_Cancel")
			);

			var filter_archives = new Gtk.FileFilter ();
			filter_archives.set_name (_("Theme Archives (*.zip, *.tar.gz, *.tar.xz, *.theme)"));
			filter_archives.add_pattern ("*.zip");
			filter_archives.add_pattern ("*.ZIP");
			filter_archives.add_pattern ("*.tar.gz");
			filter_archives.add_pattern ("*.tgz");
			filter_archives.add_pattern ("*.tar.xz");
			filter_archives.add_pattern ("*.txz");
			filter_archives.add_pattern ("*.tar.bz2");
			filter_archives.add_pattern ("*.theme");
			filter_archives.add_pattern ("dock.theme");
			chooser.add_filter (filter_archives);

			var filter_all = new Gtk.FileFilter ();
			filter_all.set_name (_("All Files"));
			filter_all.add_pattern ("*");
			chooser.add_filter (filter_all);

			string? selected_file = null;
			if (chooser.run () == Gtk.ResponseType.ACCEPT) {
				selected_file = chooser.get_filename ();
			}
			chooser.destroy ();

			if (is_destroyed)
				return;

			// Restore PreferencesWindow
			this.show ();
			this.present ();

			if (selected_file == null || selected_file == "")
				return;

			string tmp_dir;
			var themes = ThemeManager.scan_archive (selected_file, out tmp_dir);

			if (themes.size == 0) {
				var msg = new Gtk.MessageDialog (
					null,
					0,
					Gtk.MessageType.WARNING,
					Gtk.ButtonsType.OK,
					_("No valid WayPlank/Plank theme found in the selected file.\nA valid theme must contain a 'dock.theme' configuration file.")
				);
				msg.set_modal (true);
				msg.set_keep_above (true);
				msg.set_position (Gtk.WindowPosition.CENTER);
				this.set_keep_above (false);
				msg.run ();
				msg.destroy ();
				if (!is_destroyed)
					this.set_keep_above (true);
				ThemeManager.cleanup_tmp (tmp_dir);
				return;
			}

			string? last_installed = null;

			if (themes.size == 1) {
				var t = themes.get (0);
				var dest = Paths.AppThemeFolder.get_child (t.name);
				if (dest.query_exists ()) {
					var confirm = new Gtk.MessageDialog (
						null,
						0,
						Gtk.MessageType.QUESTION,
						Gtk.ButtonsType.YES_NO,
						_("A theme named '%s' already exists.\nDo you want to replace it?").printf (t.name)
					);
					confirm.set_modal (true);
					confirm.set_keep_above (true);
					confirm.set_position (Gtk.WindowPosition.CENTER);
					this.set_keep_above (false);
					int res = confirm.run ();
					confirm.destroy ();
					if (!is_destroyed)
						this.set_keep_above (true);
					if (is_destroyed || res != Gtk.ResponseType.YES) {
						ThemeManager.cleanup_tmp (tmp_dir);
						return;
					}
				}

				if (ThemeManager.install_theme (t, true)) {
					last_installed = t.name;
				}
			} else {
				// Multiple themes found in archive: show selection dialog
				var select_dialog = new Gtk.Dialog.with_buttons (
					_("Install Themes"),
					null,
					0,
					_("_Cancel"), Gtk.ResponseType.CANCEL,
					_("_Install"), Gtk.ResponseType.ACCEPT
				);
				select_dialog.set_modal (true);
				select_dialog.set_keep_above (true);
				select_dialog.set_position (Gtk.WindowPosition.CENTER);
				select_dialog.set_default_size (360, 260);

				var content_area = select_dialog.get_content_area ();
				var label = new Gtk.Label (_("The archive contains multiple themes. Select which ones to install:"));
				label.set_halign (Gtk.Align.START);
				label.margin = 12;
				content_area.pack_start (label, false, false, 0);

				var scrolled = new Gtk.ScrolledWindow (null, null);
				scrolled.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
				scrolled.margin_start = 12;
				scrolled.margin_end = 12;
				scrolled.margin_bottom = 12;

				var box_checks = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
				var check_buttons = new Gee.ArrayList<Gtk.CheckButton> ();

				foreach (var t in themes) {
					var chk = new Gtk.CheckButton.with_label (t.name);
					chk.active = true;
					box_checks.pack_start (chk, false, false, 0);
					check_buttons.add (chk);
				}

				scrolled.add (box_checks);
				content_area.pack_start (scrolled, true, true, 0);
				select_dialog.show_all ();

				this.set_keep_above (false);
				int sel_res = select_dialog.run ();
				if (!is_destroyed && sel_res == Gtk.ResponseType.ACCEPT) {
					for (int i = 0; i < themes.size; i++) {
						if (check_buttons.get (i).active) {
							var t = themes.get (i);
							if (ThemeManager.install_theme (t, true)) {
								if (last_installed == null)
									last_installed = t.name;
							}
						}
					}
				}
				select_dialog.destroy ();
				if (!is_destroyed)
					this.set_keep_above (true);
				if (is_destroyed) {
					ThemeManager.cleanup_tmp (tmp_dir);
					return;
				}
			}

			ThemeManager.cleanup_tmp (tmp_dir);

			if (!is_destroyed && last_installed != null) {
				prefs.Theme = last_installed;
				rebuild_theme_list ();
			}
		}

		void on_del_theme_clicked ()
		{
			string current_theme = cb_theme.get_active_text ();
			if (current_theme == null || !ThemeManager.is_user_theme (current_theme))
				return;

			var confirm = new Gtk.MessageDialog (
				null,
				0,
				Gtk.MessageType.QUESTION,
				Gtk.ButtonsType.YES_NO,
				_("Are you sure you want to delete the theme '%s'?\nThis will remove it from ~/.local/share/wayplank/themes/.").printf (current_theme)
			);
			confirm.set_modal (true);
			confirm.set_keep_above (true);
			confirm.set_position (Gtk.WindowPosition.CENTER);

			this.set_keep_above (false);
			int res = confirm.run ();
			confirm.destroy ();
			if (is_destroyed)
				return;
			this.set_keep_above (true);

			if (res == Gtk.ResponseType.YES) {
				if (ThemeManager.delete_user_theme (current_theme)) {
					if (Plank.Theme.is_valid_name (current_theme))
						prefs.notify_property ("Theme");
					else
						prefs.Theme = Plank.Theme.DEFAULT_NAME;
					rebuild_theme_list ();
				}
			}
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
		
		void update_alignment_sensitivity ()
		{
			bool fill_active = (prefs.Alignment == Gtk.Align.FILL);
			l_icon_alignment.sensitive = fill_active;
			cb_items_alignment.sensitive = fill_active;

			bool offset_active = (prefs.Alignment == Gtk.Align.CENTER);
			sp_offset.sensitive = offset_active;
			s_offset.sensitive = offset_active;
		}

		void update_hide_sensitivity ()
		{
			bool hide_active = (prefs.HideMode != HideType.NONE);
			l_hide_mode.sensitive = hide_active;
			cb_hidemode.sensitive = hide_active;
			l_pressure1.sensitive = hide_active;
			sp_hide_delay.sensitive = hide_active;
			s_hide_delay.sensitive = hide_active;
			l_pressure2.sensitive = hide_active;
			sp_unhide_delay.sensitive = hide_active;
			s_unhide_delay.sensitive = hide_active;
			l_pressure.sensitive = hide_active;
			sw_pressure_reveal.sensitive = hide_active;
		}

		void update_zoom_sensitivity ()
		{
			bool active = prefs.ZoomEnabled;
			sp_zoom_percent.sensitive = active;
			s_zoom_percent.sensitive = active;
			l_anticipate_zoom.sensitive = active;
			sw_anticipate_zoom.sensitive = active;
		}

		void alignment_changed (Gtk.ComboBox widget)
		{
			prefs.Alignment = (Gtk.Align) int.parse (widget.get_active_id ());
			update_alignment_sensitivity ();
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
			} else {
				if (prefs.HideMode != HideType.NONE)
					prefs.HideMode = HideType.NONE;
			}
			update_hide_sensitivity ();
		}

		void reserve_space_toggled (GLib.Object widget, ParamSpec param)
		{
			bool active = ((Gtk.Switch) widget).get_active ();
			if (prefs.ReserveSpace != active)
				prefs.ReserveSpace = active;
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
				update_icon_size_feedback ();
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
				update_icon_size_feedback ();
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
							"Name=WayPlank\n" +
							"Comment=Stupidly simple dock for Wayland\n" +
							"Exec=wayplank\n" +
							"Icon=plank\n" +
							"Terminal=false\n" +
							"X-GNOME-Autostart-enabled=true\n" +
							"X-GNOME-Autostart-Delay=2\n" +
							"X-KDE-DBUS-Restricted-Interfaces=org.kde.kwin.Screenshot,org.kde.KWin.ScreenShot2\n");
					} catch (FileError e) {
						warning ("Unable to create autostart entry '%s': %s", autostart_path, e.message);
						success = false;
					}
				}
			} else if (FileUtils.test (autostart_path, FileTest.EXISTS) && FileUtils.remove (autostart_path) != 0) {
				warning ("Unable to remove autostart entry '%s'", autostart_path);
				success = false;
			}

			if (success) {
				WindowControl.sync_autostart (enabled);
			} else {
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

		void active_highlight_changed (Gtk.ComboBox widget)
		{
			var active_id = widget.get_active_id ();
			if (active_id != null && active_id != "") {
				prefs.ActiveHighlight = int.parse (active_id).clamp (0, DockPreferences.MAX_ACTIVE_HIGHLIGHT);
				update_effect_duration_visibility ();
			}
		}

		void launch_animation_changed (Gtk.ComboBox widget)
		{
			var active_id = widget.get_active_id ();
			if (active_id != null && active_id != "") {
				prefs.LaunchAnimation = int.parse (active_id).clamp (0, DockPreferences.MAX_LAUNCH_ANIMATION);
				update_effect_duration_visibility ();
			}
		}

		void unpin_animation_changed (Gtk.ComboBox widget)
		{
			var active_id = widget.get_active_id ();
			if (active_id != null && active_id != "") {
				prefs.UnpinAnimation = int.parse (active_id).clamp (0, DockPreferences.MAX_UNPIN_ANIMATION);
				update_effect_duration_visibility ();
			}
		}

		void effect_duration_changed (Gtk.Adjustment adj)
		{
			int val = ((int) Math.round (adj.value)).clamp (DockPreferences.MIN_EFFECT_DURATION, DockPreferences.MAX_EFFECT_DURATION);
			if (prefs.EffectDuration != val)
				prefs.EffectDuration = val;
		}

		void update_effect_duration_visibility ()
		{
			bool any_effect_active = (prefs.LaunchAnimation != DockPreferences.MAX_LAUNCH_ANIMATION
				|| prefs.ActiveHighlight != DockPreferences.MAX_ACTIVE_HIGHLIGHT
				|| prefs.UnpinAnimation != DockPreferences.MAX_UNPIN_ANIMATION);
			l_effect_duration.sensitive = any_effect_active;
			box_effect_duration.sensitive = any_effect_active;
			sp_effect_duration.sensitive = any_effect_active;
			s_effect_duration.sensitive = any_effect_active;
		}

		void show_window_cards_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.ShowWindowCards = ((Gtk.Switch) widget).get_active ();
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
			bool active = ((Gtk.Switch) widget).get_active ();
			if (prefs.ZoomEnabled != active)
				prefs.ZoomEnabled = active;
			update_zoom_sensitivity ();
		}

		void anticipate_zoom_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.AnticipateZoom = ((Gtk.Switch) widget).get_active ();
			if (controller != null && controller.window != null) {
				controller.window.set_input_mask ();
			}
		}

		void tooltips_enabled_toggled (GLib.Object widget, ParamSpec param)
		{
			bool active = ((Gtk.Switch) widget).get_active ();
			if (prefs.TooltipsEnabled != active)
				prefs.TooltipsEnabled = active;
			// Dismiss any tooltip currently on screen as soon as the option is turned off
			if (!active && controller != null && controller.hover != null)
				controller.hover.hide ();
		}

		void categorize_items_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.CategorizeItems = ((Gtk.Switch) widget).get_active ();
			update_accordion_visibility ();
		}

		void docklets_on_right_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.DockletsOnRight = ((Gtk.Switch) widget).get_active ();
		}

		void anchor_always_left_toggled (GLib.Object widget, ParamSpec param)
		{
			bool active = ((Gtk.Switch) widget).get_active ();
			if (prefs.AnchorAlwaysLeft != active)
				prefs.AnchorAlwaysLeft = active;
		}

		void accordion_docklets_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.AccordionDocklets = ((Gtk.Switch) widget).get_active ();
			update_accordion_visibility ();
		}

		void accordion_click_to_expand_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.AccordionClickToExpand = ((Gtk.Switch) widget).get_active ();
		}

		void update_system_menu_access_options ()
		{
			cb_system_menu_access.changed.disconnect (system_menu_access_changed);

			cb_system_menu_access.remove_all ();
			cb_system_menu_access.append ("1", _("Docklets Only"));
			cb_system_menu_access.append ("2", _("Docklets Only (with fallback)"));
			cb_system_menu_access.append ("3", _("All Icons (integrated)"));
			cb_system_menu_access.append ("4", _("Dedicated Icon (on dock)"));

			cb_system_menu_access.active_id = prefs.SystemMenuAccess.clamp (1, 4).to_string ();
			cb_system_menu_access.changed.connect (system_menu_access_changed);
		}

		void update_accordion_visibility ()
		{
			bool cat_active = prefs.CategorizeItems;
			bool acc_active = cat_active && prefs.AccordionDocklets;
			bool pin_active = cat_active && prefs.PinnedAccordionMode != DockPreferences.PINNED_ACCORDION_OFF;
			// Click to Expand and Collapse Delay are shared by both accordions
			bool any_acc_active = acc_active || pin_active;

			btn_reorder_free_items.sensitive = !cat_active;

			l_docklets_on_right.sensitive = cat_active;
			sw_docklets_on_right.sensitive = cat_active;
			l_accordion_docklets.sensitive = cat_active;
			sw_accordion_docklets.sensitive = cat_active;
			l_pinned_accordion.sensitive = cat_active;
			cb_pinned_accordion.sensitive = cat_active;
			sp_pinned_count.sensitive = cat_active;
			sp_pinned_count.visible = (prefs.PinnedAccordionMode == DockPreferences.PINNED_ACCORDION_TOP_N);
			l_accordion_click_to_expand.sensitive = any_acc_active;
			sw_accordion_click_to_expand.sensitive = any_acc_active;

			l_accordion_delay.sensitive = any_acc_active;
			box_accordion_delay.sensitive = any_acc_active;
			sp_accordion_delay.sensitive = any_acc_active;
			s_accordion_delay.sensitive = any_acc_active;
		}

		void pinned_accordion_changed (Gtk.ComboBox widget)
		{
			var active_id = widget.get_active_id ();
			if (active_id == null || active_id == "")
				return;
			prefs.PinnedAccordionMode = int.parse (active_id).clamp (DockPreferences.PINNED_ACCORDION_OFF, DockPreferences.PINNED_ACCORDION_TOP_N);
			update_accordion_visibility ();
		}

		void pinned_count_changed (Gtk.Adjustment adj)
		{
			int val = ((int) Math.round (adj.value)).clamp (DockPreferences.MIN_PINNED_ACCORDION_COUNT, DockPreferences.MAX_PINNED_ACCORDION_COUNT);
			if (prefs.PinnedAccordionCount != val)
				prefs.PinnedAccordionCount = val;
		}

		void accordion_delay_changed (Gtk.Adjustment adj)
		{
			prefs.AccordionDelay = (uint) Math.round (adj.value * 1000.0);
		}

		void reorder_free_items_clicked ()
		{
			if (controller != null && controller.default_provider != null) {
				unowned DefaultApplicationDockItemProvider? default_provider = controller.default_provider as DefaultApplicationDockItemProvider;
				if (default_provider != null) {
					default_provider.reorder_free_items_by_category ();
				}
			}
		}
		
		void iconsize_changed (Gtk.Adjustment adj)
		{
			prefs.IconSize = (int) adj.value;
			update_icon_size_feedback ();
		}

		void scroll_overflow_toggled (GLib.Object widget, ParamSpec param)
		{
			prefs.ScrollOverflow = ((Gtk.Switch) widget).get_active ();
			update_icon_size_feedback ();
		}

		void system_menu_access_changed ()
		{
			if (cb_system_menu_access.active_id != null) {
				int val = int.parse (cb_system_menu_access.active_id);
				if (val >= 1 && val <= 4 && prefs.SystemMenuAccess != val) {
					prefs.SystemMenuAccess = val;
				}
			}
		}

		Gtk.CssProvider? slider_css = null;
		int last_fit_size = -1;
		int last_scroll_mode = -1;
		int last_val_rendered = -1;

		void update_icon_size_feedback ()
		{
			if (s_iconsize == null || adj_iconsize == null || controller == null || controller.position_manager == null)
				return;

			int fit_size = controller.position_manager.get_max_screen_fit_icon_size ();
			int current_val = (int) adj_iconsize.value;
			bool scroll_mode = prefs.ScrollOverflow;
			int current_scroll_mode_int = scroll_mode ? 1 : 0;
			bool exceeded = (current_val > fit_size);

			bool structure_changed = (fit_size != last_fit_size || current_scroll_mode_int != last_scroll_mode
				|| (exceeded && current_val != last_val_rendered)
				|| (!exceeded && last_val_rendered > fit_size));

			if (structure_changed) {
				last_fit_size = fit_size;
				last_scroll_mode = current_scroll_mode_int;
				last_val_rendered = current_val;

				s_iconsize.clear_marks ();

				if (scroll_mode) {
					s_iconsize.get_style_context ().remove_class ("slider-has-limit");
					if (slider_css != null) {
						s_iconsize.get_style_context ().remove_provider (slider_css);
					}
				} else {
					s_iconsize.get_style_context ().add_class ("slider-has-limit");

					if (fit_size < DockPreferences.MAX_ICON_SIZE) {
						s_iconsize.add_mark (fit_size, Gtk.PositionType.BOTTOM, 
							"<small><span color='#e06c75'><b>%dpx</b></span></small>".printf (fit_size));
					}

					double min_sz = DockPreferences.MIN_ICON_SIZE;
					double max_sz = DockPreferences.MAX_ICON_SIZE;
					double pct = ((fit_size - min_sz) / (max_sz - min_sz)) * 100.0;
					pct = pct.clamp (0.0, 100.0);

					double hl_pct = 100.0;
					if (exceeded && current_val > min_sz) {
						hl_pct = ((fit_size - min_sz) / (double) (current_val - min_sz)) * 100.0;
						hl_pct = hl_pct.clamp (0.0, 100.0);
					}

					if (slider_css == null) {
						slider_css = new Gtk.CssProvider ();
					} else {
						s_iconsize.get_style_context ().remove_provider (slider_css);
					}

					try {
						string css = "trough {\n" +
						             "    background-image: linear-gradient(to right, rgba(120, 120, 120, 0.25) 0%, rgba(120, 120, 120, 0.25) %.1f%%, rgba(224, 27, 36, 0.50) %.1f%%, rgba(224, 27, 36, 0.85) 100%%);\n".printf (pct, pct) +
						             "}\n" +
						             "scale.slider-exceeded highlight {\n" +
						             "    background-color: transparent;\n" +
						             "    background-image: linear-gradient(to right, #3584e4 0%, #3584e4 %.1f%%, #e01b24 %.1f%%, #e01b24 100%%);\n".printf (hl_pct, hl_pct) +
						             "}\n" +
						             "scale.slider-exceeded.marks-after slider {\n" +
						             "    background-color: transparent;\n" +
						             "    background-image: url('resource:///net/launchpad/plank/ui/slider-marks-below-red.svg');\n" +
						             "    background-repeat: no-repeat;\n" +
						             "    background-position: center bottom;\n" +
						             "    box-shadow: none;\n" +
						             "    border: none;\n" +
						             "}\n" +
						             "scale.slider-exceeded:not(.marks-after) slider {\n" +
						             "    background-color: #e01b24;\n" +
						             "    background-image: none;\n" +
						             "    border-radius: 50%;\n" +
						             "    border: 2px solid #b71c1c;\n" +
						             "}\n";
						slider_css.load_from_data (css);
						s_iconsize.get_style_context ().add_provider (slider_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
					} catch (GLib.Error e) {
						warning ("Unable to apply slider CSS: %s", e.message);
					}
				}
			}

			if (scroll_mode) {
				s_iconsize.get_style_context ().remove_class ("slider-exceeded");
				if (l_iconsize_hint != null) {
					l_iconsize_hint.set_markup ("<small><span alpha='75%'>%s</span></small>".printf (
						_("Scroll on Overflow active: %dpx preserved").printf (current_val)));
				}

				string tt = _("Target icon size: %dpx.\n'Scroll on Overflow' is enabled in Behaviour: icons will never shrink, and the dock smoothly scrolls with mouse wheel when items exceed screen space.").printf (current_val);
				s_iconsize.tooltip_text = tt;
				sp_iconsize.tooltip_text = tt;
				return;
			}

			if (exceeded) {
				s_iconsize.get_style_context ().add_class ("slider-exceeded");
				if (l_iconsize_hint != null) {
					l_iconsize_hint.set_markup (
						"<small><span foreground='#e01b24'><b>%s</b></span></small>".printf (
							_("⚠️ Limited to %dpx by screen space (auto-shrunk)").printf (fit_size)));
				}
				string tt = _("⚠️ Icon size set to %dpx, but clamped to %dpx by screen space.\nIcons will auto-shrink to fit on screen.\nTo unlock larger sizes without shrinking, enable 'Scroll on Overflow' in Behaviour.").printf (current_val, fit_size);
				s_iconsize.tooltip_text = tt;
				sp_iconsize.tooltip_text = tt;
			} else {
				s_iconsize.get_style_context ().remove_class ("slider-exceeded");
				if (l_iconsize_hint != null) {
					l_iconsize_hint.set_markup (
						"<small><span alpha='75%'>%s</span></small>".printf (
							_("Fits on screen without shrinking (limit: %dpx)").printf (fit_size)));
				}
				string tt = _("Target icon size: %dpx.\nFits comfortably on screen (screen capacity limit: %dpx before auto-shrinking activates).").printf (current_val, fit_size);
				s_iconsize.tooltip_text = tt;
				sp_iconsize.tooltip_text = tt;
			}
		}
		
		void offset_changed (Gtk.Adjustment adj)
		{
			prefs.Offset = (int) adj.value;
		}
		
		void hide_delay_changed (Gtk.Adjustment adj)
		{
			prefs.HideDelay = (uint) Math.round (double.max (0.0, adj.value));
		}
		
		void unhide_delay_changed (Gtk.Adjustment adj)
		{
			prefs.UnhideDelay = (uint) Math.round (double.max (0.0, adj.value));
		}
		
		void zoom_percent_changed (Gtk.Adjustment adj)
		{
			prefs.ZoomPercent = (uint) Math.round (double.max (100.0, adj.value));
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
				update_icon_size_feedback ();
			}
		}
		
		void on_position_manager_icon_size_changed (GLib.Object sender, ParamSpec prop)
		{
			update_icon_size_feedback ();
		}

		void connect_signals ()
		{
			if (signals_connected)
				return;
			signals_connected = true;

			prefs.notify.connect (prefs_changed);
			
			cb_theme.changed.connect (theme_changed);
			btn_add_theme.clicked.connect (on_add_theme_clicked);
			btn_del_theme.clicked.connect (on_del_theme_clicked);
			cb_hidemode.changed.connect (hidemode_changed);
			cb_position.changed.connect (position_changed);
			adj_hide_delay.value_changed.connect (hide_delay_changed);
			adj_unhide_delay.value_changed.connect (unhide_delay_changed);
			cb_display_plug.changed.connect (monitor_changed);
			adj_iconsize.value_changed.connect (iconsize_changed);
			adj_offset.value_changed.connect (offset_changed);
			adj_zoom_percent.value_changed.connect (zoom_percent_changed);
			adj_accordion_delay.value_changed.connect (accordion_delay_changed);
			cb_pinned_accordion.changed.connect (pinned_accordion_changed);
			adj_pinned_count.value_changed.connect (pinned_count_changed);
			cb_window_click_behavior.changed.connect (window_click_behavior_changed);
			cb_active_highlight.changed.connect (active_highlight_changed);
			cb_launch_animation.changed.connect (launch_animation_changed);
			cb_unpin_animation.changed.connect (unpin_animation_changed);
			adj_effect_duration.value_changed.connect (effect_duration_changed);
			cb_system_menu_access.changed.connect (system_menu_access_changed);
			sw_hide.notify["active"].connect (hide_toggled);
			sw_primary_display.notify["active"].connect (primary_display_toggled);
			sw_workspace_only.notify["active"].connect (workspace_only_toggled);
			sw_autostart.notify["active"].connect (autostart_toggled);
			sw_show_unpinned.notify["active"].connect (show_unpinned_toggled);
			sw_scroll_overflow.notify["active"].connect (scroll_overflow_toggled);
			sw_lock_items.notify["active"].connect (lock_items_toggled);
			sw_pressure_reveal.notify["active"].connect (pressure_reveal_toggled);
			sw_reserve_space.notify["active"].connect (reserve_space_toggled);
			sw_anticipate_zoom.notify["active"].connect (anticipate_zoom_toggled);
			sw_tooltips_enabled.notify["active"].connect (tooltips_enabled_toggled);
			sw_zoom_enabled.notify["active"].connect (zoom_enabled_toggled);
			sw_categorize_items.notify["active"].connect (categorize_items_toggled);
			btn_reorder_free_items.clicked.connect (reorder_free_items_clicked);
			sw_docklets_on_right.notify["active"].connect (docklets_on_right_toggled);
			sw_anchor_always_left.notify["active"].connect (anchor_always_left_toggled);
			sw_accordion_docklets.notify["active"].connect (accordion_docklets_toggled);
			sw_accordion_click_to_expand.notify["active"].connect (accordion_click_to_expand_toggled);
			sw_show_window_cards.notify["active"].connect (show_window_cards_toggled);
			sw_restore_minimized.notify["active"].connect (restore_minimized_toggled);
			sw_show_running_indicators.notify["active"].connect (show_running_indicators_toggled);
			sw_show_attention_indicators.notify["active"].connect (show_attention_indicators_toggled);
			sw_show_trash.notify["active"].connect (docklet_trash_toggled);
			sw_docklet_clock.notify["active"].connect (docklet_clock_toggled);
			sw_docklet_digital_clock.notify["active"].connect (docklet_digital_clock_toggled);
			sw_docklet_battery.notify["active"].connect (docklet_battery_toggled);
			sw_docklet_cpu.notify["active"].connect (docklet_cpu_toggled);
			sw_docklet_desktop.notify["active"].connect (docklet_desktop_toggled);
			sw_docklet_mpris.notify["active"].connect (docklet_mpris_toggled);
			sw_docklet_volume.notify["active"].connect (docklet_volume_toggled);
			sw_docklet_screenshot.notify["active"].connect (docklet_screenshot_toggled);
			sw_docklet_session.notify["active"].connect (docklet_session_toggled);
			sw_docklet_brightness.notify["active"].connect (docklet_brightness_toggled);
			sw_docklet_ejector.notify["active"].connect (docklet_ejector_toggled);
			sw_docklet_weather.notify["active"].connect (docklet_weather_toggled);
			sw_docklet_network.notify["active"].connect (docklet_network_toggled);
			sw_docklet_dnd.notify["active"].connect (docklet_dnd_toggled);
			if (controller != null && controller.default_provider != null)
				controller.default_provider.elements_changed.connect (default_provider_elements_changed);
			cb_alignment.changed.connect (alignment_changed);
			cb_items_alignment.changed.connect (items_alignment_changed);
			get_screen ().monitors_changed.connect (rebuild_monitor_list);
			WindowControl.get_default ().primary_monitor_changed.connect (rebuild_monitor_list);
			dock_preferences.notify["visible-child"].connect (on_stack_page_changed);
			dock_preferences.notify["transition-running"].connect (on_stack_page_changed);
			if (controller != null && controller.position_manager != null) {
				controller.position_manager.notify["icon-size"].connect (on_position_manager_icon_size_changed);
				controller.position_manager.notify["max-icon-size"].connect (on_position_manager_icon_size_changed);
			}
		}
		
		void disconnect_signals ()
		{
			if (!signals_connected)
				return;
			signals_connected = false;

			prefs.notify.disconnect (prefs_changed);
			
			cb_theme.changed.disconnect (theme_changed);
			btn_add_theme.clicked.disconnect (on_add_theme_clicked);
			btn_del_theme.clicked.disconnect (on_del_theme_clicked);
			cb_hidemode.changed.disconnect (hidemode_changed);
			cb_position.changed.disconnect (position_changed);
			adj_hide_delay.value_changed.disconnect (hide_delay_changed);
			adj_unhide_delay.value_changed.disconnect (unhide_delay_changed);
			cb_display_plug.changed.disconnect (monitor_changed);
			adj_iconsize.value_changed.disconnect (iconsize_changed);
			adj_offset.value_changed.disconnect (offset_changed);
			adj_zoom_percent.value_changed.disconnect (zoom_percent_changed);
			adj_accordion_delay.value_changed.disconnect (accordion_delay_changed);
			cb_pinned_accordion.changed.disconnect (pinned_accordion_changed);
			adj_pinned_count.value_changed.disconnect (pinned_count_changed);
			cb_window_click_behavior.changed.disconnect (window_click_behavior_changed);
			cb_active_highlight.changed.disconnect (active_highlight_changed);
			cb_launch_animation.changed.disconnect (launch_animation_changed);
			cb_unpin_animation.changed.disconnect (unpin_animation_changed);
			adj_effect_duration.value_changed.disconnect (effect_duration_changed);
			cb_system_menu_access.changed.disconnect (system_menu_access_changed);
			sw_hide.notify["active"].disconnect (hide_toggled);
			sw_primary_display.notify["active"].disconnect (primary_display_toggled);
			sw_workspace_only.notify["active"].disconnect (workspace_only_toggled);
			sw_autostart.notify["active"].disconnect (autostart_toggled);
			sw_show_unpinned.notify["active"].disconnect (show_unpinned_toggled);
			sw_scroll_overflow.notify["active"].disconnect (scroll_overflow_toggled);
			sw_lock_items.notify["active"].disconnect (lock_items_toggled);
			sw_pressure_reveal.notify["active"].disconnect (pressure_reveal_toggled);
			sw_reserve_space.notify["active"].disconnect (reserve_space_toggled);
			sw_anticipate_zoom.notify["active"].disconnect (anticipate_zoom_toggled);
			sw_tooltips_enabled.notify["active"].disconnect (tooltips_enabled_toggled);
			sw_zoom_enabled.notify["active"].disconnect (zoom_enabled_toggled);
			sw_categorize_items.notify["active"].disconnect (categorize_items_toggled);
			btn_reorder_free_items.clicked.disconnect (reorder_free_items_clicked);
			sw_docklets_on_right.notify["active"].disconnect (docklets_on_right_toggled);
			sw_anchor_always_left.notify["active"].disconnect (anchor_always_left_toggled);
			sw_accordion_docklets.notify["active"].disconnect (accordion_docklets_toggled);
			sw_accordion_click_to_expand.notify["active"].disconnect (accordion_click_to_expand_toggled);
			sw_show_window_cards.notify["active"].disconnect (show_window_cards_toggled);
			sw_restore_minimized.notify["active"].disconnect (restore_minimized_toggled);
			sw_show_running_indicators.notify["active"].disconnect (show_running_indicators_toggled);
			sw_show_attention_indicators.notify["active"].disconnect (show_attention_indicators_toggled);
			sw_show_trash.notify["active"].disconnect (docklet_trash_toggled);
			sw_docklet_clock.notify["active"].disconnect (docklet_clock_toggled);
			sw_docklet_digital_clock.notify["active"].disconnect (docklet_digital_clock_toggled);
			sw_docklet_battery.notify["active"].disconnect (docklet_battery_toggled);
			sw_docklet_cpu.notify["active"].disconnect (docklet_cpu_toggled);
			sw_docklet_desktop.notify["active"].disconnect (docklet_desktop_toggled);
			sw_docklet_mpris.notify["active"].disconnect (docklet_mpris_toggled);
			sw_docklet_volume.notify["active"].disconnect (docklet_volume_toggled);
			sw_docklet_screenshot.notify["active"].disconnect (docklet_screenshot_toggled);
			sw_docklet_session.notify["active"].disconnect (docklet_session_toggled);
			sw_docklet_brightness.notify["active"].disconnect (docklet_brightness_toggled);
			sw_docklet_ejector.notify["active"].disconnect (docklet_ejector_toggled);
			sw_docklet_weather.notify["active"].disconnect (docklet_weather_toggled);
			sw_docklet_network.notify["active"].disconnect (docklet_network_toggled);
			sw_docklet_dnd.notify["active"].disconnect (docklet_dnd_toggled);
			if (controller != null && controller.default_provider != null)
				controller.default_provider.elements_changed.disconnect (default_provider_elements_changed);
			cb_alignment.changed.disconnect (alignment_changed);
			cb_items_alignment.changed.disconnect (items_alignment_changed);
			get_screen ().monitors_changed.disconnect (rebuild_monitor_list);
			WindowControl.get_default ().primary_monitor_changed.disconnect (rebuild_monitor_list);
			dock_preferences.notify["visible-child"].disconnect (on_stack_page_changed);
			dock_preferences.notify["transition-running"].disconnect (on_stack_page_changed);
			if (controller != null && controller.position_manager != null) {
				controller.position_manager.notify["icon-size"].disconnect (on_position_manager_icon_size_changed);
				controller.position_manager.notify["max-icon-size"].disconnect (on_position_manager_icon_size_changed);
			}
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
			
			bool primary_supported = WindowCapabilities.primary_display_supported ();
			string primary_tt = primary_supported
				? _("Automatically display the dock on the primary monitor; disable to choose a specific display")
				: _("Not supported by this compositor");
			sw_primary_display.tooltip_text = primary_tt;
			l_primary_display.tooltip_text = primary_tt;
			if (!primary_supported) {
				sw_primary_display.set_active (false);
				sw_primary_display.sensitive = false;
				cb_display_plug.sensitive = true;
				if (active_pos >= 0) {
					cb_display_plug.set_active (active_pos);
				} else if (names.length > 0) {
					cb_display_plug.set_active (0);
				}
			} else if (prefs.Monitor == "") {
				cb_display_plug.set_active (primary_pos);
				sw_primary_display.set_active (true);
				sw_primary_display.sensitive = true;
				cb_display_plug.sensitive = false;
			} else if (active_pos >= 0) {
				cb_display_plug.set_active (active_pos);
				sw_primary_display.set_active (false);
				sw_primary_display.sensitive = true;
				cb_display_plug.sensitive = true;
				if (prefs.Monitor != names[active_pos])
					prefs.Monitor = names[active_pos];
			} else if (names.length > 0) {
				cb_display_plug.set_active (0);
				sw_primary_display.set_active (false);
				sw_primary_display.sensitive = true;
				cb_display_plug.sensitive = true;
			}
			
			updating_monitors = false;
			update_icon_size_feedback ();
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
			cb_theme.tooltip_text = prefs.Theme;
			update_theme_buttons ();

			var effective_mode = (prefs.HideMode != HideType.NONE && !WindowCapabilities.hide_mode_supported (prefs.HideMode))
				? HideType.DODGE_MAXIMIZED
				: prefs.HideMode;
			cb_hidemode.active_id = ((int) effective_mode).to_string ();
			cb_position.active_id = ((int) prefs.Position).to_string ();
			adj_hide_delay.value = prefs.HideDelay;
			adj_unhide_delay.value = prefs.UnhideDelay;

			rebuild_monitor_list ();
			
			adj_iconsize.value = prefs.IconSize;
			adj_offset.value = prefs.Offset;
			adj_zoom_percent.value = prefs.ZoomPercent;
			sw_hide.set_active (prefs.HideMode != HideType.NONE);
			bool primary_supported = WindowCapabilities.primary_display_supported ();
			sw_primary_display.set_active (primary_supported && prefs.Monitor == "");
			sw_primary_display.sensitive = primary_supported;
			sw_workspace_only.set_active (prefs.CurrentWorkspaceOnly);
			sw_workspace_only.sensitive = false;
			sw_workspace_only.tooltip_text = _("Workspace filtering is not yet supported under Wayland");
			sw_autostart.set_active (FileUtils.test (
				Path.build_filename (Environment.get_user_config_dir (), "autostart", "wayplank.desktop"),
				FileTest.IS_REGULAR));
			sw_show_unpinned.set_active (!prefs.PinnedOnly);
			sw_scroll_overflow.set_active (prefs.ScrollOverflow);
			update_system_menu_access_options ();
			sw_lock_items.set_active (prefs.LockItems);
			sw_pressure_reveal.set_active (prefs.PressureReveal);
			sw_pressure_reveal.tooltip_text = _("Requires touching the physical screen edge (1px) to reveal the dock, preventing accidental triggers; when disabled, reveals 10px before the edge for fluid unhiding");
			sw_reserve_space.set_active (prefs.ReserveSpace);
			sw_reserve_space.sensitive = true;
			l_reserve_space.sensitive = true;
			sw_reserve_space.tooltip_text = _("Reserve screen space matching the dock thickness (Panel Mode) so maximized windows tile without overlapping the dock; enabling this automatically turns off Hide Dock and Icon Zoom, and enabling either automatically turns off Reserve Screen Space");
			l_reserve_space.tooltip_text = sw_reserve_space.tooltip_text;
			sw_anticipate_zoom.set_active (prefs.AnticipateZoom);
			sw_anticipate_zoom.tooltip_text = _("Begins icon magnification as the cursor approaches the dock for a fluid, magnetic feel; disable to strictly pass mouse clicks through to windows positioned immediately behind or above the dock");
			sw_zoom_enabled.set_active (prefs.ZoomEnabled);
			sw_tooltips_enabled.set_active (prefs.TooltipsEnabled);
			sw_categorize_items.set_active (prefs.CategorizeItems);
			sw_docklets_on_right.set_active (prefs.DockletsOnRight);
			sw_anchor_always_left.set_active (prefs.AnchorAlwaysLeft);
			sw_accordion_docklets.set_active (prefs.AccordionDocklets);
			sw_accordion_click_to_expand.set_active (prefs.AccordionClickToExpand);
			adj_accordion_delay.value = (prefs.AccordionDelay >= DockPreferences.MIN_ACCORDION_DELAY ? prefs.AccordionDelay : DockPreferences.DEFAULT_ACCORDION_DELAY) / 1000.0;
			cb_pinned_accordion.active_id = prefs.PinnedAccordionMode.clamp (DockPreferences.PINNED_ACCORDION_OFF, DockPreferences.PINNED_ACCORDION_TOP_N).to_string ();
			adj_pinned_count.value = prefs.PinnedAccordionCount.clamp (DockPreferences.MIN_PINNED_ACCORDION_COUNT, DockPreferences.MAX_PINNED_ACCORDION_COUNT);
			update_accordion_visibility ();
			cb_alignment.active_id = ((int) prefs.Alignment).to_string ();
			cb_items_alignment.active_id = ((int) prefs.ItemsAlignment).to_string ();
			update_alignment_sensitivity ();
			update_hide_sensitivity ();
			update_zoom_sensitivity ();
			cb_active_highlight.active_id = prefs.ActiveHighlight.clamp (0, DockPreferences.MAX_ACTIVE_HIGHLIGHT).to_string ();
			cb_launch_animation.active_id = prefs.LaunchAnimation.clamp (0, DockPreferences.MAX_LAUNCH_ANIMATION).to_string ();
			cb_unpin_animation.active_id = prefs.UnpinAnimation.clamp (0, DockPreferences.MAX_UNPIN_ANIMATION).to_string ();
			adj_effect_duration.value = prefs.EffectDuration.clamp (DockPreferences.MIN_EFFECT_DURATION, DockPreferences.MAX_EFFECT_DURATION);
			update_effect_duration_visibility ();
			update_icon_size_feedback ();
			clear_spinbutton_focus ();
		}

		void init_window_tab ()
		{
			cb_window_click_behavior.active_id = prefs.WindowClickBehavior.to_string ();
			sw_show_window_cards.set_active (prefs.ShowWindowCards);
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
				var to_remove = new Gee.ArrayList<DockItem> ();
				foreach (var el in default_provider.Elements) {
					unowned DockItem? item = el as DockItem;
					if (item == null)
						continue;
					if (DockItemProvider.uri_matches (item.Launcher, uri) || (uri == "docklet://trash" && item is TrashDockItem))
						to_remove.add (item);
				}
				foreach (var di in to_remove) {
					if (default_provider.Elements.contains (di))
						default_provider.remove (di);
					di.delete ();
				}
			}
			default_provider.refresh_separators ();
			if (controller.renderer != null && controller.renderer.theme != null) {
				controller.update_items ();
				controller.position_manager.update (controller.renderer.theme);
				controller.renderer.reset_buffers ();
				controller.renderer.animated_draw ();
				controller.schedule_serialize_item_positions ();
				if (controller.window != null) {
					controller.window.update_icon_regions ();
					controller.window.set_input_mask ();
				}
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

		void docklet_brightness_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://brightness");
		}

		void docklet_ejector_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://ejector");
		}

		void docklet_weather_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://weather");
		}

		void docklet_network_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://network");
		}

		void docklet_dnd_toggled (GLib.Object widget, ParamSpec param)
		{
			toggle_docklet_uri (widget, "docklet://dnd");
		}

		void default_provider_elements_changed (Gee.List<DockElement> added, Gee.List<DockElement> removed)
		{
			init_docklets_tab ();
			update_icon_size_feedback ();
		}

		void init_docklets_tab ()
		{
			updating_docklets = true;
			unowned DefaultApplicationDockItemProvider? default_provider = controller.default_provider as DefaultApplicationDockItemProvider;
			if (default_provider != null) {
				sw_show_trash.set_active (default_provider.item_for_uri ("docklet://trash") != null);
				sw_docklet_clock.set_active (default_provider.item_for_uri ("docklet://clock") != null);
				sw_docklet_digital_clock.set_active (default_provider.item_for_uri ("docklet://digital-clock") != null);
				sw_docklet_battery.set_active (default_provider.item_for_uri ("docklet://battery") != null);
				sw_docklet_cpu.set_active (default_provider.item_for_uri ("docklet://cpu") != null);
				sw_docklet_desktop.set_active (default_provider.item_for_uri ("docklet://desktop") != null);
				sw_docklet_mpris.set_active (default_provider.item_for_uri ("docklet://mpris") != null);
				sw_docklet_volume.set_active (default_provider.item_for_uri ("docklet://volume") != null);
				sw_docklet_screenshot.set_active (default_provider.item_for_uri ("docklet://screenshot") != null);
				sw_docklet_session.set_active (default_provider.item_for_uri ("docklet://session") != null);
				sw_docklet_brightness.set_active (default_provider.item_for_uri ("docklet://brightness") != null);
				sw_docklet_ejector.set_active (default_provider.item_for_uri ("docklet://ejector") != null);
				sw_docklet_weather.set_active (default_provider.item_for_uri ("docklet://weather") != null);
				sw_docklet_network.set_active (default_provider.item_for_uri ("docklet://network") != null);
				sw_docklet_dnd.set_active (default_provider.item_for_uri ("docklet://dnd") != null);
			} else {
				sw_show_trash.set_active (false);
				sw_docklet_clock.set_active (false);
				sw_docklet_digital_clock.set_active (false);
				sw_docklet_battery.set_active (false);
				sw_docklet_cpu.set_active (false);
				sw_docklet_desktop.set_active (false);
				sw_docklet_mpris.set_active (false);
				sw_docklet_volume.set_active (false);
				sw_docklet_screenshot.set_active (false);
				sw_docklet_session.set_active (false);
				sw_docklet_brightness.set_active (false);
				sw_docklet_ejector.set_active (false);
				sw_docklet_weather.set_active (false);
				sw_docklet_network.set_active (false);
				sw_docklet_dnd.set_active (false);
			}
			
			update_docklet_icons ();
			updating_docklets = false;
		}

		void ensure_docklet_icon (Gtk.Image? img, string system_icon_names, string fallback_resource)
		{
			if (img == null)
				return;
			
			var default_theme = Gtk.IconTheme.get_default ();
			string? matched = null;
			foreach (var name in system_icon_names.split (";;")) {
				if (default_theme.has_icon (name)) {
					matched = name;
					break;
				}
			}

			if (matched != null) {
				img.set_from_icon_name (matched, Gtk.IconSize.DND);
			} else {
				try {
					var pb = new Gdk.Pixbuf.from_resource_at_scale (fallback_resource, 35, 35, true);
					img.set_from_pixbuf (pb);
				} catch (GLib.Error e) {
					img.set_from_icon_name (system_icon_names.split (";;")[0], Gtk.IconSize.DND);
				}
			}
			img.pixel_size = 35;
		}

		void update_docklet_icons ()
		{
			ensure_docklet_icon (img_docklet_cpu, "utilities-system-monitor", "/net/launchpad/plank/docklets/cpu.svg");
			ensure_docklet_icon (img_docklet_clock, "preferences-system-time", "/net/launchpad/plank/docklets/clock.svg");
			ensure_docklet_icon (img_docklet_desktop, "user-desktop", "/net/launchpad/plank/docklets/desktop.svg");
			ensure_docklet_icon (img_docklet_digital_clock, "org.kde.plasma.digitalclock", "/net/launchpad/plank/docklets/digital-clock.svg");
			ensure_docklet_icon (img_docklet_mpris, "gnome-mplayer;;applications-multimedia;;multimedia-player", "/net/launchpad/plank/docklets/mpris.svg");
			ensure_docklet_icon (img_docklet_battery, "battery-full", "/net/launchpad/plank/docklets/battery.svg");
			ensure_docklet_icon (img_docklet_volume, "audio-volume-high;;volume-level-high", "/net/launchpad/plank/docklets/volume-high.svg");
			ensure_docklet_icon (img_docklet_screenshot, "applets-screenshooter", "/net/launchpad/plank/docklets/screenshot.svg");
			ensure_docklet_icon (img_docklet_session, "system-shutdown", "/net/launchpad/plank/docklets/session.svg");
			ensure_docklet_icon (img_docklet_brightness, BrightnessDockItem.get_brightness_icon_name (100), "/net/launchpad/plank/docklets/brightness.svg");
			ensure_docklet_icon (img_docklet_ejector, "media-eject", "/net/launchpad/plank/docklets/ejector.svg");
			ensure_docklet_icon (img_docklet_weather, "weather-few-clouds", "/net/launchpad/plank/docklets/weather.svg");
			ensure_docklet_icon (img_docklet_network, "network-wireless-signal-good", "/net/launchpad/plank/docklets/network.svg");
			ensure_docklet_icon (img_docklet_dnd, "preferences-desktop-notification-bell;;notifications", "/net/launchpad/plank/docklets/dnd.svg");
		}
	}
}
