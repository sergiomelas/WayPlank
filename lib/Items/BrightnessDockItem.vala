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
	/**
	 * Screen Brightness Docklet.
	 * 100% Compositor-Agnostic UI Layer following the HAL Prime Directive.
	 * All hardware, multi-monitor output discovery, kscreen-doctor and DDC/CI
	 * control reside strictly in BrightnessControl (lib/Services/).
	 */
	public class BrightnessDockItem : DockItem
	{
		public static string get_brightness_icon_name (int percent)
		{
			var default_theme = Gtk.IconTheme.get_default ();

			// 100% Maximum Brightness: Full solid sun icon
			if (percent >= 100) {
				if (default_theme.has_icon ("notification-display-brightness-full"))
					return "notification-display-brightness-full";
				if (default_theme.has_icon ("display-brightness-full"))
					return "display-brightness-full";
				if (default_theme.has_icon ("brightness-full"))
					return "brightness-full";
				return "brightness";
			}

			string tier = (percent >= 66) ? "high" : (percent >= 33) ? "medium" : "low";

			// Set 1: notification-display-brightness-* (Haptic-SML, GNOME notification spec)
			if (default_theme.has_icon ("notification-display-brightness-high") &&
			    default_theme.has_icon ("notification-display-brightness-medium") &&
			    default_theme.has_icon ("notification-display-brightness-low")) {
				return "notification-display-brightness-" + tier;
			}

			// Set 2: display-brightness-* (FreeDesktop status spec)
			if (default_theme.has_icon ("display-brightness-high") &&
			    default_theme.has_icon ("display-brightness-medium") &&
			    default_theme.has_icon ("display-brightness-low")) {
				return "display-brightness-" + tier;
			}

			// Set 3: brightness-* (Breeze / legacy status spec)
			if (default_theme.has_icon ("brightness-high") &&
			    default_theme.has_icon ("brightness-medium") &&
			    default_theme.has_icon ("brightness-low")) {
				return "brightness-" + tier;
			}

			// If no complete graded set exists in active theme, ALWAYS use our internal graded fallback set directly!
			return "brightness-" + tier;
		}

		private ulong changed_signal_id = 0;
		private int current_percent = 100;

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
			Button = PopupButton.RIGHT;

			unowned BrightnessControl ctrl = BrightnessControl.get_default ();
			current_percent = ctrl.get_percent ();
			Icon = get_brightness_icon_name (current_percent);
			update_display (current_percent);

			changed_signal_id = ctrl.brightness_changed.connect ((pct) => {
				update_display (pct);
			});
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

		public override void cleanup ()
		{
			if (changed_signal_id != 0) {
				BrightnessControl.get_default ().disconnect (changed_signal_id);
				changed_signal_id = 0;
			}

			base.cleanup ();
		}

		public override bool is_valid ()
		{
			return BrightnessControl.get_default ().is_available ();
		}

		private void update_display (int percent)
		{
			current_percent = percent;
			Count = percent;
			BadgeText = "%d%%".printf (percent);
			CountVisible = true;
			Text = _("Screen Brightness: %d%%").printf (percent);
			Icon = get_brightness_icon_name (percent);

			reset_icon_buffer ();
		}

		protected override AnimationType on_scrolled (Gdk.ScrollDirection direction, Gdk.ModifierType mod, uint32 event_time)
		{
			if (direction == Gdk.ScrollDirection.UP) {
				BrightnessControl.get_default ().adjust_percent (5);
				return AnimationType.NONE;
			} else if (direction == Gdk.ScrollDirection.DOWN) {
				BrightnessControl.get_default ().adjust_percent (-5);
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

				BrightnessControl.get_default ().set_percent (next, true);
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
			string[] preset_icons = { get_brightness_icon_name (100), "display-brightness-high", "display-brightness-medium", "display-brightness-low", "display-brightness-low" };

			for (int i = 0; i < presets.length; i++) {
				int p = presets[i];
				string label = "%d%% %s".printf (p, p == 100 ? _("(Maximum)") : (p == 10 ? _("(Minimum)") : ""));
				var item = create_menu_item (label, preset_icons[i], true);
				item.activate.connect (() => BrightnessControl.get_default ().set_percent (p, true));
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

			return items;
		}
	}
}
