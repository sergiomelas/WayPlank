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
	public class WeatherWindow : Gtk.Window
	{
		public static WeatherWindow? active_instance = null;

		public static bool is_open ()
		{
			return (active_instance != null && active_instance.get_visible ());
		}

		public static void toggle_window (WeatherDockItem item, uint32 event_time = 0)
		{
			uint32 click_time = event_time != 0 ? event_time : Gtk.get_current_event_time ();
			if (active_instance != null) {
				if (active_instance.is_active || active_instance.has_toplevel_focus) {
					active_instance.destroy ();
					active_instance = null;
					return;
				}
				raise_and_focus_instance (active_instance, click_time);
				return;
			}

			var win = new WeatherWindow (item);
			active_instance = win;
			raise_and_focus_instance (win, click_time);
		}

		static void raise_and_focus_instance (Gtk.Window window, uint32 event_time = 0)
		{
			window.show_all ();
			window.deiconify ();
			window.set_keep_above (true);
			uint32 time = event_time != 0 ? event_time : Gtk.get_current_event_time ();
			if (time != 0) {
				window.present_with_time (time);
			} else {
				window.present ();
			}
			var gdk_win = window.get_window ();
			if (gdk_win != null) {
				gdk_win.raise ();
				gdk_win.focus (time != 0 ? time : Gdk.CURRENT_TIME);
			}
			window.grab_focus ();

			if (!window.get_mapped ()) {
				ulong map_handler = 0;
				map_handler = window.map.connect (() => {
					if (window.get_visible ()) {
						uint32 t = event_time != 0 ? event_time : Gtk.get_current_event_time ();
						if (t != 0)
							window.present_with_time (t);
						else
							window.present ();
						window.grab_focus ();
					}
					if (map_handler != 0) {
						GLib.SignalHandler.disconnect (window, map_handler);
						map_handler = 0;
					}
				});
			}
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
			set_role ("help");
			set_decorated (true);
			set_destroy_with_parent (false);
			set_position (Gtk.WindowPosition.CENTER);
			window_position = Gtk.WindowPosition.CENTER;
			gravity = Gdk.Gravity.CENTER;
			set_default_size (480, 430);
			resizable = false;
			set_type_hint (Gdk.WindowTypeHint.DIALOG);
			set_keep_above (true);
			set_skip_taskbar_hint (true);
			set_skip_pager_hint (true);

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
				if (weather_item != null)
					weather_item.get_dock ()?.check_collapse_after_interaction (this);
				else
					AbstractMain.check_collapse_all_docks (this);
			});

			hide.connect (() => {
				if (active_instance == this)
					active_instance = null;
				if (weather_item != null)
					weather_item.get_dock ()?.check_collapse_after_interaction (this);
				else
					AbstractMain.check_collapse_all_docks (this);
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

			img_condition = new Gtk.Image ();
			set_image_icon (img_condition, "weather-few-clouds;;weather", 64);

			var img_event_box = new Gtk.EventBox ();
			img_event_box.set_visible_window (false);
			img_event_box.add (img_condition);
			img_event_box.button_press_event.connect ((e) => {
				if (e.button == 1 && weather_item != null && weather_item.yr_location_id.length > 0) {
					open_weather_details ();
					return true;
				}
				return false;
			});
			img_event_box.enter_notify_event.connect ((e) => {
				if (weather_item != null && weather_item.yr_location_id.length > 0) {
					var win = img_event_box.get_window ();
					if (win != null) {
						var cursor = new Gdk.Cursor.for_display (img_event_box.get_display (), Gdk.CursorType.HAND2);
						win.set_cursor (cursor);
					}
				}
				return false;
			});
			img_event_box.leave_notify_event.connect ((e) => {
				var win = img_event_box.get_window ();
				if (win != null)
					win.set_cursor (null);
				return false;
			});

			current_card.pack_start (img_event_box, false, false, 0);

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
				string temp_markup = "<span size='xx-large' weight='bold'>%d%s</span>".printf ((int) Math.round (weather_item.current_temp), unit_symbol);
				if (weather_item.has_today_minmax) {
					temp_markup += "   <span size='medium' weight='normal' color='#888888'>▲ %d%s   ▼ %d%s</span>".printf (
						(int) Math.round (weather_item.today_temp_max), unit_symbol,
						(int) Math.round (weather_item.today_temp_min), unit_symbol
					);
				}
				lbl_temp.set_markup (temp_markup);
				var now = new GLib.DateTime.now_local ();
				string today_day = format_weekday (now);
				lbl_desc.set_markup ("<span size='medium' weight='semibold'>%s, %s — %s</span>".printf (
					_("Today"),
					today_day,
					GLib.Markup.escape_text (weather_item.condition_desc)
				));
				string feels_like_str = _("Feels like %d%s").printf ((int) Math.round (weather_item.feels_like_temp), unit_symbol);
				lbl_details.set_markup ("%s   •   💧 %d%%   •   💨 %.1f %s".printf (
					feels_like_str,
					weather_item.humidity,
					weather_item.wind_speed,
					wind_unit
				));
			}

			set_image_icon (img_condition, weather_item.get_current_icon_name (), 64);

			// Rebuild forecast cards
			if (forecast_box != null) {
				foreach (var child in forecast_box.get_children ()) {
					forecast_box.remove (child);
				}

				if (weather_item.forecast_days != null && weather_item.forecast_days.length > 1) {
					var now = new GLib.DateTime.now_local ();
					for (int i = 1; i <= 3 && i < weather_item.forecast_days.length; i++) {
						var day = weather_item.forecast_days[i];
						if (day == null) continue;

						var event_box = new Gtk.EventBox ();
						event_box.set_visible_window (false);

						var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
						card.margin = 4;
						card.get_style_context ().add_class ("card");

						var target_dt = now.add_days (i);
						string day_label = format_weekday (target_dt);
						var lbl_day = new Gtk.Label (day_label);
						lbl_day.use_markup = true;
						lbl_day.set_markup ("<b>%s</b>".printf (day_label));
						card.pack_start (lbl_day, false, false, 0);

						var day_icon = new Gtk.Image ();
						set_image_icon (day_icon, day.icon_name, 64);
						card.pack_start (day_icon, false, false, 2);

						var lbl_day_temp = new Gtk.Label ("%d%s / %d%s".printf ((int) Math.round (day.temp_max), unit_symbol, (int) Math.round (day.temp_min), unit_symbol));
						lbl_day_temp.get_style_context ().add_class ("dim-label");
						card.pack_start (lbl_day_temp, false, false, 0);

						string day_wind_str = "%.0f %s".printf (day.wind_speed, wind_unit);
						var lbl_day_details = new Gtk.Label ("<span size='small'>💧 %d%%   💨 %s</span>".printf (day.humidity, day_wind_str));
						lbl_day_details.use_markup = true;
						lbl_day_details.get_style_context ().add_class ("dim-label");
						card.pack_start (lbl_day_details, false, false, 0);

						event_box.add (card);

						int day_offset = i;
						event_box.button_press_event.connect ((e) => {
							if (e.button == 1 && weather_item != null && weather_item.yr_location_id.length > 0) {
								open_weather_details (day_offset);
								return true;
							}
							return false;
						});

						event_box.enter_notify_event.connect ((e) => {
							if (weather_item != null && weather_item.yr_location_id.length > 0) {
								var win = event_box.get_window ();
								if (win != null) {
									var display = event_box.get_display ();
									var cursor = new Gdk.Cursor.for_display (display, Gdk.CursorType.HAND2);
									win.set_cursor (cursor);
								}
							}
							return false;
						});

						event_box.leave_notify_event.connect ((e) => {
							var win = event_box.get_window ();
							if (win != null)
								win.set_cursor (null);
							return false;
						});

						forecast_box.pack_start (event_box, true, true, 0);
					}
				} else {
					var lbl_no_data = new Gtk.Label (_("No forecast data available"));
					lbl_no_data.get_style_context ().add_class ("dim-label");
					forecast_box.pack_start (lbl_no_data, true, true, 0);
				}
				forecast_box.show_all ();
			}
		}

		private void open_weather_details (int day_offset = 0)
		{
			if (weather_item == null || weather_item.yr_location_id.length == 0)
				return;
			string url = weather_item.get_details_url (day_offset);
			try {
				Gtk.show_uri_on_window (this, url, Gdk.CURRENT_TIME);
			} catch (GLib.Error e) {
				warning ("WeatherWindow: failed to open details URL '%s': %s", url, e.message);
			}
		}

		private void set_image_icon (Gtk.Image img, string icon_names, int pixel_size)
		{
			var pb = DrawingService.load_icon (icon_names, pixel_size, pixel_size);
			if (pb != null) {
				img.set_from_pixbuf (pb);
			} else {
				img.set_from_icon_name ("weather-few-clouds", Gtk.IconSize.DIALOG);
			}
			img.pixel_size = pixel_size;
		}

		private string format_weekday (GLib.DateTime dt)
		{
			string formatted = dt.format ("%A");
			if (formatted == null || formatted.length == 0)
				return "";
			return formatted.substring (0, 1).up () + formatted.substring (1);
		}
	}
}
