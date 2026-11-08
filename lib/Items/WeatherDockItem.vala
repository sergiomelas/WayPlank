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
	public class WeatherForecastDay
	{
		public double temp_min = 0.0;
		public double temp_max = 0.0;
		public int weather_code = 0;
		public string icon_name = "weather-few-clouds";
		public int humidity = 0;
		public double wind_speed = 0.0;
	}

	public class WeatherDockItemPreferences : DockItemPreferences
	{
		[Description (nick = "City", blurb = "City name for weather (empty for automatic IP location)")]
		public string City { get; set; default = ""; }

		[Description (nick = "Units", blurb = "Temperature units: C or F")]
		public string Units { get; set; default = "C"; }

		public WeatherDockItemPreferences ()
		{
			base ();
			City = "";
			Units = "C";
		}

		public WeatherDockItemPreferences.with_file (GLib.File file)
		{
			base.with_file (file);
		}
	}

	public class WeatherDockItem : DockItem
	{
		const string DEFAULT_ICON = "weather-few-clouds;;weather-clear;;weather";

		public string city_name { get; private set; default = ""; }
		public string country_name { get; private set; default = ""; }
		public double current_temp { get; private set; default = 0.0; }
		public double feels_like_temp { get; private set; default = 0.0; }
		public string condition_desc { get; private set; default = _("Checking weather..."); }
		public int humidity { get; private set; default = 0; }
		public double wind_speed { get; private set; default = 0.0; }
		public string units { get; private set; default = "C"; }
		public int current_code { get; private set; default = 1; }
		public double today_temp_max { get; private set; default = 0.0; }
		public double today_temp_min { get; private set; default = 0.0; }
		public bool has_today_minmax { get; private set; default = false; }
		public WeatherForecastDay[] forecast_days;
		public string yr_location_id { get; private set; default = ""; }

		private enum WeatherFetchOutcome
		{
			OK,
			NOT_FOUND,
			OFFLINE
		}

		private class WeatherFetchResult
		{
			public WeatherFetchOutcome outcome = WeatherFetchOutcome.OFFLINE;
			public string city_name = "";
			public string country_name = "";
			public string detected_place = "";
			public string condition_desc = "";
			public double current_temp = 0.0;
			public double feels_like_temp = 0.0;
			public int humidity = 0;
			public double wind_speed = 0.0;
			public int current_code = -1;
			public double today_temp_max = 0.0;
			public double today_temp_min = 0.0;
			public bool has_today_minmax = false;
			public WeatherForecastDay[] forecast_days = new WeatherForecastDay[0];
			public string yr_location_id = "";
		}

		private unowned WeatherDockItemPreferences weather_prefs;
		private uint timer_id = 0;
		private bool is_fetching = false;
		private bool is_disposed = false;
		private int fetch_generation = 0;

		public WeatherDockItem ()
		{
			GLib.Object (Prefs: new WeatherDockItemPreferences ());
		}

		public WeatherDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new WeatherDockItemPreferences.with_file (file));
		}

		construct
		{
			weather_prefs = (WeatherDockItemPreferences) Prefs;
			units = (weather_prefs.Units.up () == "F") ? "F" : "C";

			Text = _("Weather");
			Icon = DEFAULT_ICON;
			Button = PopupButton.RIGHT;
			forecast_days = new WeatherForecastDay[0];

			refresh_weather ();

			// Refresh every 20 minutes (1200 seconds)
			timer_id = GLib.Timeout.add_seconds (1200, () => {
				refresh_weather ();
				return true;
			});
		}

		~WeatherDockItem ()
		{
			is_disposed = true;
			if (timer_id != 0) {
				GLib.Source.remove (timer_id);
				timer_id = 0;
			}
			WeatherWindow.detach_item (this);
			WeatherCityDialog.detach_item (this);
		}

		public override void cleanup ()
		{
			is_disposed = true;
			if (timer_id != 0) {
				GLib.Source.remove (timer_id);
				timer_id = 0;
			}
			WeatherWindow.detach_item (this);
			WeatherCityDialog.detach_item (this);
			base.cleanup ();
		}

		public override void @delete ()
		{
			is_disposed = true;
			if (timer_id != 0) {
				GLib.Source.remove (timer_id);
				timer_id = 0;
			}
			WeatherWindow.detach_item (this);
			WeatherCityDialog.detach_item (this);
			base.@delete ();
		}

		public override bool is_valid ()
		{
			return true;
		}

		public void set_location_and_units (string new_city, string new_units)
		{
			weather_prefs.City = new_city;
			weather_prefs.Units = new_units;
			units = (new_units.up () == "F") ? "F" : "C";
			city_name = (new_city.length > 0) ? new_city : _("Detecting location...");
			country_name = "";
			condition_desc = _("Updating weather...");
			yr_location_id = "";
			fetch_generation++;
			is_fetching = false;
			WeatherWindow.update_if_open ();
			refresh_weather ();
		}

		public void open_location_dialog (Gtk.Window? parent = null)
		{
			var existing = WeatherCityDialog.find_for_item (this);
			if (existing != null) {
				existing.present ();
				return;
			}
			Gtk.Window? dlg_parent = parent != null ? parent : WeatherWindow.active_instance;
			var dlg = new WeatherCityDialog (this, dlg_parent);
			string initial_city = weather_prefs.City.strip ();
			if (initial_city.length == 0 && city_name.length > 0 && city_name != _("Offline") && city_name != _("Checking weather...")) {
				initial_city = (country_name.length > 0) ? "%s, %s".printf (city_name, country_name) : city_name;
			}
			dlg.init_values (initial_city, weather_prefs.Units);
		}

		public string get_current_icon_name ()
		{
			if (current_code == -1)
				return "dialog-warning;;weather-severe-alert;;weather-few-clouds;;weather";
			return code_to_icon_name (current_code);
		}

		public string get_details_url (int day_offset = 0)
		{
			if (yr_location_id.length > 0) {
				if (day_offset > 0)
					return "https://www.yr.no/en/forecast/hourly-table/%s?i=%d".printf (yr_location_id, day_offset);
				else
					return "https://www.yr.no/en/forecast/daily-table/" + yr_location_id;
			}

			string query = city_name;
			if (country_name.length > 0)
				query += " " + country_name;
			if (query.length == 0 || query == _("Detecting location...") || query == _("Offline") || query == _("Checking weather..."))
				query = "weather";
			return "https://www.yr.no/en/search?q=" + GLib.Uri.escape_string (query);
		}

		private static void spawn_weather_worker (WeatherDockItem target, int gen, string configured_city, string unit_snap)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new GLib.Thread<void*> ("weather-worker", () => {
				var res = perform_fetch (configured_city, unit_snap);
				GLib.Idle.add (() => {
					var self = (WeatherDockItem?) self_ref.get ();
					if (self == null || self.is_disposed)
						return false;
					if (gen != self.fetch_generation)
						return false;
					self.is_fetching = false;
					self.apply_fetch_result (res);
					return false;
				});
				return null;
			});
		}

		public void refresh_weather ()
		{
			if (is_disposed || is_fetching)
				return;
			is_fetching = true;
			int gen = ++fetch_generation;
			string configured_city = weather_prefs.City.strip ();
			string unit_snap = units;

			spawn_weather_worker (this, gen, configured_city, unit_snap);
		}

		private void apply_fetch_result (WeatherFetchResult res)
		{
			if (res.detected_place.length > 0 && weather_prefs.City.strip ().length == 0)
				weather_prefs.City = res.detected_place;

			city_name = res.city_name;
			country_name = res.country_name;
			condition_desc = res.condition_desc;
			current_code = res.current_code;
			forecast_days = res.forecast_days;

			if (res.outcome == WeatherFetchOutcome.NOT_FOUND) {
				has_today_minmax = false;
				yr_location_id = "";
				CountVisible = false;
				BadgeText = null;
				Text = "%s: %s".printf (city_name, condition_desc);
				Icon = "dialog-warning;;weather-severe-alert;;weather-few-clouds";
				reset_icon_buffer ();
				WeatherWindow.update_if_open ();
				return;
			}

			if (res.outcome == WeatherFetchOutcome.OFFLINE) {
				has_today_minmax = false;
				CountVisible = false;
				BadgeText = null;
				Text = "%s: %s".printf (city_name, condition_desc);
				Icon = "weather-few-clouds;;weather";
				reset_icon_buffer ();
				WeatherWindow.update_if_open ();
				return;
			}

			current_temp = res.current_temp;
			feels_like_temp = res.feels_like_temp;
			humidity = res.humidity;
			wind_speed = res.wind_speed;
			today_temp_max = res.today_temp_max;
			today_temp_min = res.today_temp_min;
			has_today_minmax = res.has_today_minmax;
			if (res.yr_location_id.length > 0)
				yr_location_id = res.yr_location_id;

			update_display ();
		}

		private static WeatherFetchResult perform_fetch (string configured_city, string unit_snap)
		{
			var res = new WeatherFetchResult ();
			double lat = 0.0;
			double lon = 0.0;
			string resolved_city = "";
			string resolved_country = "";

			// 1. Resolve coordinates
			if (configured_city.length > 0) {
				string geo_cmd = "curl -s --max-time 5 'https://geocoding-api.open-meteo.com/v1/search?name=%s&count=1&language=en&format=json'".printf (GLib.Uri.escape_string (configured_city));
				string geo_out;
				int status;
				try {
					if (Process.spawn_command_line_sync (geo_cmd, out geo_out, null, out status) && status == 0) {
						var parser = new Json.Parser ();
						parser.load_from_data (geo_out);
						var root = parser.get_root ();
						if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
							var obj = root.get_object ();
							if (obj.has_member ("results") && !obj.get_null_member ("results")) {
								var results = obj.get_array_member ("results");
								if (results != null && results.get_length () > 0) {
									var first = results.get_object_element (0);
									if (first != null) {
										if (first.has_member ("latitude") && !first.get_null_member ("latitude"))
											lat = first.get_double_member ("latitude");
										if (first.has_member ("longitude") && !first.get_null_member ("longitude"))
											lon = first.get_double_member ("longitude");
										if (first.has_member ("name") && !first.get_null_member ("name"))
											resolved_city = first.get_string_member ("name") ?? "";
										if (first.has_member ("country") && !first.get_null_member ("country"))
											resolved_country = first.get_string_member ("country") ?? "";
									}
								}
							}
						}
					}
				} catch (GLib.Error e) { }
			}

			// 1b. Handle Geocoding resolution result
			if (lat == 0.0 && lon == 0.0) {
				if (configured_city.length > 0) {
					res.outcome = WeatherFetchOutcome.NOT_FOUND;
					res.city_name = configured_city;
					res.country_name = "";
					res.condition_desc = _("Location not found");
					res.current_code = -1;
					res.forecast_days = new WeatherForecastDay[0];
					return res;
				}

				// Only if configured_city was EMPTY -> perform automatic IP Geolocation detection
				string ip_out;
				int status;
				try {
					if (Process.spawn_command_line_sync ("curl -s --max-time 4 'http://ip-api.com/json'", out ip_out, null, out status) && status == 0) {
						var parser = new Json.Parser ();
						parser.load_from_data (ip_out);
						var root = parser.get_root ();
						if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
							var obj = root.get_object ();
							if (obj.has_member ("lat") && !obj.get_null_member ("lat") && obj.has_member ("lon") && !obj.get_null_member ("lon")) {
								lat = obj.get_double_member ("lat");
								lon = obj.get_double_member ("lon");
								if (obj.has_member ("city") && !obj.get_null_member ("city"))
									resolved_city = obj.get_string_member ("city") ?? "";
								if (obj.has_member ("country") && !obj.get_null_member ("country"))
									resolved_country = obj.get_string_member ("country") ?? "";

								if (configured_city.length == 0 && resolved_city.length > 0)
									res.detected_place = (resolved_country.length > 0) ? "%s, %s".printf (resolved_city, resolved_country) : resolved_city;
							}
						}
					}
				} catch (GLib.Error e) { }
			}

			// If network failed completely (offline / no internet):
			if (lat == 0.0 && lon == 0.0) {
				res.outcome = WeatherFetchOutcome.OFFLINE;
				res.city_name = (configured_city.length > 0) ? configured_city : _("Offline");
				res.country_name = "";
				res.condition_desc = _("No internet connection");
				res.current_code = -1;
				res.forecast_days = new WeatherForecastDay[0];
				return res;
			}

			// 2. Fetch Open-Meteo forecast
			string unit_param = (unit_snap == "F") ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "";
			string forecast_cmd = "curl -s --max-time 5 'https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,wind_speed_10m_max,relative_humidity_2m_max,relative_humidity_2m_min&timezone=auto%s'".printf (lat, lon, unit_param);
			string forecast_out;
			int f_status;
			bool fetched_ok = false;

			try {
				if (Process.spawn_command_line_sync (forecast_cmd, out forecast_out, null, out f_status) && f_status == 0) {
					var parser = new Json.Parser ();
					parser.load_from_data (forecast_out);
					var root = parser.get_root ();
					if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
						var obj = root.get_object ();
						if (obj.has_member ("current") && !obj.get_null_member ("current")) {
							var cur = obj.get_object_member ("current");
							if (cur != null) {
								res.current_temp = cur.has_member ("temperature_2m") && !cur.get_null_member ("temperature_2m") ? cur.get_double_member ("temperature_2m") : 0.0;
								res.feels_like_temp = cur.has_member ("apparent_temperature") && !cur.get_null_member ("apparent_temperature") ? cur.get_double_member ("apparent_temperature") : res.current_temp;
								res.humidity = cur.has_member ("relative_humidity_2m") && !cur.get_null_member ("relative_humidity_2m") ? (int) cur.get_int_member ("relative_humidity_2m") : 0;
								res.wind_speed = cur.has_member ("wind_speed_10m") && !cur.get_null_member ("wind_speed_10m") ? cur.get_double_member ("wind_speed_10m") : 0.0;
								res.current_code = cur.has_member ("weather_code") && !cur.get_null_member ("weather_code") ? (int) cur.get_int_member ("weather_code") : 0;
								res.condition_desc = code_to_description (res.current_code);
								fetched_ok = true;
							}
						}

						res.city_name = resolved_city;
						res.country_name = resolved_country;

						// Daily forecast
						if (obj.has_member ("daily") && !obj.get_null_member ("daily")) {
							var daily = obj.get_object_member ("daily");
							var max_arr = (daily != null && daily.has_member ("temperature_2m_max") && !daily.get_null_member ("temperature_2m_max")) ? daily.get_array_member ("temperature_2m_max") : null;
							var min_arr = (daily != null && daily.has_member ("temperature_2m_min") && !daily.get_null_member ("temperature_2m_min")) ? daily.get_array_member ("temperature_2m_min") : null;
							var code_arr = (daily != null && daily.has_member ("weather_code") && !daily.get_null_member ("weather_code")) ? daily.get_array_member ("weather_code") : null;
							var wind_arr = (daily != null && daily.has_member ("wind_speed_10m_max") && !daily.get_null_member ("wind_speed_10m_max")) ? daily.get_array_member ("wind_speed_10m_max") : null;
							var h_max_arr = (daily != null && daily.has_member ("relative_humidity_2m_max") && !daily.get_null_member ("relative_humidity_2m_max")) ? daily.get_array_member ("relative_humidity_2m_max") : null;
							var h_min_arr = (daily != null && daily.has_member ("relative_humidity_2m_min") && !daily.get_null_member ("relative_humidity_2m_min")) ? daily.get_array_member ("relative_humidity_2m_min") : null;

							if (max_arr != null && min_arr != null && code_arr != null) {
								if (max_arr.get_length () > 0 && min_arr.get_length () > 0) {
									res.today_temp_max = max_arr.get_double_element (0);
									res.today_temp_min = min_arr.get_double_element (0);
									res.has_today_minmax = true;
								}

								uint total_days = (uint) max_arr.get_length ();
								uint len = (uint) uint.min (4, (uint) uint.min (total_days, (uint) uint.min ((uint) min_arr.get_length (), (uint) code_arr.get_length ())));
								var days = new WeatherForecastDay[len];
								for (uint i = 0; i < len; i++) {
									days[i] = new WeatherForecastDay ();
									days[i].temp_max = max_arr.get_double_element (i);
									days[i].temp_min = min_arr.get_double_element (i);
									days[i].weather_code = (int) code_arr.get_int_element (i);
									days[i].icon_name = code_to_icon_name (days[i].weather_code);
									if (wind_arr != null && i < wind_arr.get_length ())
										days[i].wind_speed = wind_arr.get_double_element (i);
									if (h_max_arr != null && h_min_arr != null && i < h_max_arr.get_length () && i < h_min_arr.get_length ()) {
										int h_max = (int) h_max_arr.get_int_element (i);
										int h_min = (int) h_min_arr.get_int_element (i);
										days[i].humidity = (h_max + h_min) / 2;
									}
								}
								res.forecast_days = days;
							}
						}
					}
				}
			} catch (GLib.Error e) {
				warning ("WeatherDockItem: error fetching forecast: %s", e.message);
			}

			if (!fetched_ok) {
				res.outcome = WeatherFetchOutcome.OFFLINE;
				res.city_name = (resolved_city.length > 0) ? resolved_city : ((configured_city.length > 0) ? configured_city : _("Offline"));
				res.country_name = resolved_country;
				res.condition_desc = _("No internet connection");
				res.current_code = -1;
				res.forecast_days = new WeatherForecastDay[0];
				return res;
			}

			res.outcome = WeatherFetchOutcome.OK;

			// 2b. Resolve Yr.no direct location URL
			string yr_target_city = (resolved_city.length > 0) ? resolved_city : configured_city;
			if (yr_target_city.length > 0)
				res.yr_location_id = resolve_yr_direct_url (yr_target_city, lat, lon);

			return res;
		}

		private static string resolve_yr_direct_url (string query, double target_lat, double target_lon)
		{
			if (query.length == 0 || query == _("Detecting location...") || query == _("Offline") || query == _("Checking weather..."))
				return "";

			string yr_search_cmd = "curl -s --max-time 4 'https://www.yr.no/api/v0/locations/search?q=%s'".printf (GLib.Uri.escape_string (query));
			string yr_out;
			int yr_status;
			try {
				if (Process.spawn_command_line_sync (yr_search_cmd, out yr_out, null, out yr_status) && yr_status == 0) {
					var parser = new Json.Parser ();
					parser.load_from_data (yr_out);
					var root = parser.get_root ();
					if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
						var obj = root.get_object ();
						if (obj.has_member ("_embedded") && !obj.get_null_member ("_embedded")) {
							var embedded = obj.get_object_member ("_embedded");
							if (embedded != null && embedded.has_member ("location") && !embedded.get_null_member ("location")) {
								var loc_arr = embedded.get_array_member ("location");
								string best_id = "";
								double min_dist = 1e12;
								for (uint i = 0; loc_arr != null && i < loc_arr.get_length (); i++) {
									var loc = loc_arr.get_object_element (i);
									if (loc == null || !loc.has_member ("id") || loc.get_null_member ("id"))
										continue;
									string id = loc.get_string_member ("id") ?? "";
									if (loc.has_member ("position") && !loc.get_null_member ("position") && (target_lat != 0.0 || target_lon != 0.0)) {
										var pos = loc.get_object_member ("position");
										if (pos != null && pos.has_member ("lat") && !pos.get_null_member ("lat") && pos.has_member ("lon") && !pos.get_null_member ("lon")) {
											double plat = pos.get_double_member ("lat");
											double plon = pos.get_double_member ("lon");
											double d = (plat - target_lat) * (plat - target_lat) + (plon - target_lon) * (plon - target_lon);
											if (d < min_dist) {
												min_dist = d;
												best_id = id;
											}
										}
									} else if (best_id.length == 0) {
										best_id = id;
									}
								}
								if (best_id.length > 0)
									return best_id;
							}
						}
					}
				}
			} catch (GLib.Error e) {
				warning ("WeatherDockItem: error resolving Yr.no URL: %s", e.message);
			}
			return "";
		}

		private void update_display ()
		{
			Count = (int64) Math.round (current_temp);
			BadgeText = "%d°%s".printf ((int) Math.round (current_temp), units);
			CountVisible = (current_code != -1);
			Text = "%s: %d°%s, %s".printf (city_name, (int) Math.round (current_temp), units, condition_desc);
			Icon = get_current_icon_name ();
			reset_icon_buffer ();
			WeatherWindow.update_if_open ();
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				WeatherWindow.toggle_window (this, event_time);
				return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var refresh_item = create_menu_item (_("Refresh Weather"), "view-refresh", true);
			refresh_item.activate.connect (() => {
				refresh_weather ();
			});
			items.add (refresh_item);

			var location_item = create_menu_item (_("Set Location..."), "preferences-system", true);
			location_item.activate.connect (() => {
				open_location_dialog ();
			});
			items.add (location_item);

			string toggle_unit_label = (units == "C") ? _("Switch to Fahrenheit (°F)") : _("Switch to Celsius (°C)");
			var unit_item = create_menu_item (toggle_unit_label, "weather-clear", true);
			unit_item.activate.connect (() => {
				string new_units = (units == "C") ? "F" : "C";
				set_location_and_units (weather_prefs.City, new_units);
			});
			items.add (unit_item);

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

		public static string code_to_description (int code)
		{
			switch (code) {
				case 0: return _("Clear sky");
				case 1: return _("Mainly clear");
				case 2: return _("Partly cloudy");
				case 3: return _("Overcast");
				case 45:
				case 48: return _("Foggy");
				case 51:
				case 53:
				case 55: return _("Drizzle");
				case 56:
				case 57: return _("Freezing drizzle");
				case 61:
				case 63: return _("Rain");
				case 65: return _("Heavy rain");
				case 66:
				case 67: return _("Freezing rain");
				case 71:
				case 73: return _("Snow");
				case 75: return _("Heavy snow");
				case 77: return _("Snow grains");
				case 80:
				case 81: return _("Rain showers");
				case 82: return _("Violent rain showers");
				case 85:
				case 86: return _("Snow showers");
				case 95: return _("Thunderstorm");
				case 96:
				case 99: return _("Thunderstorm with hail");
				default: return _("Partly cloudy");
			}
		}

		public static string code_to_icon_name (int code)
		{
			switch (code) {
				case 0:
					return "weather-clear;;weather-clear-symbolic";
				case 1:
				case 2:
					return "weather-few-clouds;;weather-few-clouds-symbolic";
				case 3:
					return "weather-overcast;;weather-clouds;;weather-many-clouds";
				case 45:
				case 48:
					return "weather-fog;;weather-mist";
				case 51:
				case 53:
				case 55:
				case 56:
				case 57:
					return "weather-showers-scattered;;weather-showers";
				case 61:
				case 63:
				case 65:
				case 66:
				case 67:
				case 80:
				case 81:
				case 82:
					return "weather-showers;;weather-freezing-rain";
				case 71:
				case 73:
				case 75:
				case 77:
				case 85:
				case 86:
					return "weather-snow;;weather-snow-symbolic";
				case 95:
				case 96:
				case 99:
					return "weather-storm;;weather-severe-alert";
				default:
					return "weather-few-clouds;;weather-clear";
			}
		}
	}
}
