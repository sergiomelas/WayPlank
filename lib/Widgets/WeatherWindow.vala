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
	public class WeatherWindow : Gtk.Window
	{
		public static WeatherWindow? active_instance = null;

		public static void toggle_window (WeatherDockItem item)
		{
			if (active_instance != null) {
				active_instance.destroy ();
				active_instance = null;
				return;
			}

			var win = new WeatherWindow (item);
			active_instance = win;
			win.show_all ();
			win.present ();
		}

		public static void update_if_open ()
		{
			if (active_instance != null) {
				active_instance.update_ui ();
			}
		}

		private unowned WeatherDockItem? weather_item = null;
		private Gtk.Label lbl_location;
		private Gtk.Label lbl_temp;
		private Gtk.Label lbl_desc;
		private Gtk.Label lbl_details;
		private Gtk.Image img_condition;
		private Gtk.Box forecast_box;

		public WeatherWindow (WeatherDockItem item)
		{
			GLib.Object (type: Gtk.WindowType.TOPLEVEL);
			this.weather_item = item;
			update_ui ();
		}

		construct
		{
			title = _("Weather Forecast");
			set_role ("weather-dialog");
			set_decorated (true);
			set_destroy_with_parent (true);
			set_position (Gtk.WindowPosition.CENTER);
			set_default_size (420, 360);
			resizable = false;
			set_type_hint (Gdk.WindowTypeHint.DIALOG);
			set_keep_above (true);

			key_press_event.connect ((w, e) => {
				if (e.keyval == Gdk.Key.Escape) {
					destroy ();
					return true;
				}
				return false;
			});

			destroy.connect (() => {
				if (active_instance == this)
					active_instance = null;
			});

			var main_vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
			main_vbox.margin = 18;

			// 1. Header Location
			lbl_location = new Gtk.Label ("");
			lbl_location.use_markup = true;
			lbl_location.set_markup ("<span size='x-large' weight='bold'>📍 %s</span>".printf (_("Loading weather...")));
			main_vbox.pack_start (lbl_location, false, false, 0);

			// 2. Current Weather Card
			var current_card = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
			current_card.margin_top = 4;
			current_card.margin_bottom = 4;

			img_condition = new Gtk.Image.from_icon_name ("weather-few-clouds", Gtk.IconSize.DIALOG);
			img_condition.pixel_size = 64;
			current_card.pack_start (img_condition, false, false, 0);

			var temp_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
			lbl_temp = new Gtk.Label ("");
			lbl_temp.use_markup = true;
			lbl_temp.xalign = 0.0f;
			temp_box.pack_start (lbl_temp, false, false, 0);

			lbl_desc = new Gtk.Label ("");
			lbl_desc.use_markup = true;
			lbl_desc.xalign = 0.0f;
			temp_box.pack_start (lbl_desc, false, false, 0);

			lbl_details = new Gtk.Label ("");
			lbl_details.use_markup = true;
			lbl_details.xalign = 0.0f;
			lbl_details.get_style_context ().add_class ("dim-label");
			temp_box.pack_start (lbl_details, false, false, 0);

			current_card.pack_start (temp_box, true, true, 0);
			main_vbox.pack_start (current_card, false, false, 0);

			// 3. Separator
			main_vbox.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);

			// 4. 3-Day Forecast Section
			var lbl_forecast_header = new Gtk.Label (_("3-Day Forecast"));
			lbl_forecast_header.xalign = 0.0f;
			lbl_forecast_header.get_style_context ().add_class ("dim-label");
			main_vbox.pack_start (lbl_forecast_header, false, false, 0);

			forecast_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
			forecast_box.homogeneous = true;
			main_vbox.pack_start (forecast_box, true, true, 0);

			// 5. Bottom Action Buttons
			var btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
			btn_box.margin_top = 8;

			var refresh_btn = new Gtk.Button.with_label (_("🔄 Refresh"));
			refresh_btn.clicked.connect (() => {
				if (weather_item != null)
					weather_item.refresh_weather ();
			});
			btn_box.pack_start (refresh_btn, false, false, 0);

			var location_btn = new Gtk.Button.with_label (_("⚙️ Location..."));
			location_btn.clicked.connect (() => {
				if (weather_item != null)
					weather_item.open_location_dialog (this);
			});
			btn_box.pack_start (location_btn, false, false, 0);

			var close_btn = new Gtk.Button.with_label (_("Close"));
			close_btn.clicked.connect (() => {
				destroy ();
			});
			btn_box.pack_end (close_btn, false, false, 0);

			main_vbox.pack_start (btn_box, false, false, 0);

			add (main_vbox);
		}

		public void update_ui ()
		{
			if (weather_item == null)
				return;

			string loc_str = weather_item.city_name;
			if (weather_item.country_name.length > 0)
				loc_str += ", " + weather_item.country_name;
			if (loc_str.length == 0) loc_str = _("Detecting location...");

			lbl_location.set_markup ("<span size='x-large' weight='bold'>📍 %s</span>".printf (GLib.Markup.escape_text (loc_str)));

			string unit_symbol = "°" + weather_item.units;
			string wind_unit = (weather_item.units == "F") ? "mph" : "km/h";

			if (weather_item.current_code == -1) {
				lbl_temp.set_markup ("<span size='xx-large' weight='bold'>--</span>");
				lbl_desc.set_markup ("<span size='medium' weight='semibold' color='#e05555'>%s</span>".printf (GLib.Markup.escape_text (weather_item.condition_desc)));
				lbl_details.set_markup (_("Please verify internet connection or location in Settings."));
			} else {
				lbl_temp.set_markup ("<span size='xx-large' weight='bold'>%d%s</span>".printf ((int) Math.round (weather_item.current_temp), unit_symbol));
				string feels_like_str = _("Feels like %d%s").printf ((int) Math.round (weather_item.feels_like_temp), unit_symbol);
				lbl_desc.set_markup ("<span size='medium' weight='semibold'>%s</span>".printf (GLib.Markup.escape_text (weather_item.condition_desc)));
				lbl_details.set_markup ("%s   •   💧 %d%%   •   💨 %.1f %s".printf (
					feels_like_str,
					weather_item.humidity,
					weather_item.wind_speed,
					wind_unit
				));
			}

			img_condition.set_from_icon_name (weather_item.get_current_icon_name (), Gtk.IconSize.DIALOG);
			img_condition.pixel_size = 64;

			// Rebuild forecast cards
			if (forecast_box != null) {
				foreach (var child in forecast_box.get_children ()) {
					forecast_box.remove (child);
				}

				if (weather_item.forecast_days != null && weather_item.forecast_days.length > 0) {
					string[] day_names = { _("Today"), _("Tomorrow"), _("Day After") };
					for (int i = 0; i < 3 && i < weather_item.forecast_days.length; i++) {
						var day = weather_item.forecast_days[i];
						if (day == null) continue;
						var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
						card.margin = 4;
						card.get_style_context ().add_class ("card");

						var lbl_day = new Gtk.Label (day_names[i]);
						lbl_day.use_markup = true;
						lbl_day.set_markup ("<b>%s</b>".printf (day_names[i]));
						card.pack_start (lbl_day, false, false, 0);

						var day_icon = new Gtk.Image.from_icon_name (day.icon_name, Gtk.IconSize.BUTTON);
						day_icon.pixel_size = 32;
						card.pack_start (day_icon, false, false, 2);

						var lbl_day_temp = new Gtk.Label ("%d%s / %d%s".printf ((int) Math.round (day.temp_max), unit_symbol, (int) Math.round (day.temp_min), unit_symbol));
						lbl_day_temp.get_style_context ().add_class ("dim-label");
						card.pack_start (lbl_day_temp, false, false, 0);

						forecast_box.pack_start (card, true, true, 0);
					}
				} else {
					var lbl_no_data = new Gtk.Label (_("No forecast data available"));
					lbl_no_data.get_style_context ().add_class ("dim-label");
					forecast_box.pack_start (lbl_no_data, true, true, 0);
				}
				forecast_box.show_all ();
			}
		}
	}
}
