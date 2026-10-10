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
	public class WeatherCityDialog : Gtk.Dialog
	{
		private Gtk.Entry city_entry;
		private Gtk.Label lbl_status;
		private Gtk.RadioButton unit_c_radio;
		private Gtk.RadioButton unit_f_radio;
		private unowned WeatherDockItem weather_item;

		private Gtk.EntryCompletion completion;
		private Gtk.ListStore completion_store;
		private uint search_timer_id = 0;
		private bool is_valid_selection = false;
		private string last_queried_text = "";

		public WeatherCityDialog (WeatherDockItem item, Gtk.Window? parent = null)
		{
			GLib.Object (
				title: _("Weather Location Settings"),
				transient_for: parent,
				modal: true,
				destroy_with_parent: true,
				window_position: Gtk.WindowPosition.CENTER
			);
			this.weather_item = item;
		}

		construct
		{
			set_default_size (420, 240);
			resizable = false;

			var content_area = get_content_area () as Gtk.Box;
			content_area.margin = 18;
			content_area.spacing = 10;

			// Header label
			var lbl_city = new Gtk.Label (_("City / Location:"));
			lbl_city.xalign = 0.0f;
			lbl_city.get_style_context ().add_class ("dim-label");
			content_area.pack_start (lbl_city, false, false, 0);

			// City input entry with autocomplete and clear icon
			city_entry = new Gtk.Entry ();
			city_entry.placeholder_text = _("e.g. Rome, London, New York...");
			city_entry.set_icon_from_icon_name (Gtk.EntryIconPosition.SECONDARY, "edit-clear-symbolic");
			city_entry.set_icon_tooltip_text (Gtk.EntryIconPosition.SECONDARY, _("Clear location (re-detect via IP)"));
			city_entry.icon_press.connect ((pos, event) => {
				if (pos == Gtk.EntryIconPosition.SECONDARY) {
					city_entry.text = "";
					is_valid_selection = false;
					lbl_status.hide ();
				}
			});

			setup_autocomplete ();
			city_entry.changed.connect (on_city_entry_changed);
			city_entry.activate.connect (() => {
				response (Gtk.ResponseType.OK);
			});
			content_area.pack_start (city_entry, false, false, 0);

			// Permanent intuitive helper label
			var lbl_helper = new Gtk.Label (_("ℹ️ Leave blank (or click ✖ to clear) to re-detect your location using IP."));
			lbl_helper.xalign = 0.0f;
			lbl_helper.use_markup = true;
			lbl_helper.get_style_context ().add_class ("dim-label");
			content_area.pack_start (lbl_helper, false, false, 0);

			// Status / validation error label
			lbl_status = new Gtk.Label ("");
			lbl_status.xalign = 0.0f;
			lbl_status.use_markup = true;
			lbl_status.no_show_all = true;
			lbl_status.hide ();
			content_area.pack_start (lbl_status, false, false, 0);

			// Units selection
			var unit_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
			unit_box.margin_top = 4;
			var lbl_units = new Gtk.Label (_("Units:"));
			unit_box.pack_start (lbl_units, false, false, 0);

			unit_c_radio = new Gtk.RadioButton.with_label (null, "°C (Celsius)");
			unit_f_radio = new Gtk.RadioButton.with_label_from_widget (unit_c_radio, "°F (Fahrenheit)");
			unit_box.pack_start (unit_c_radio, false, false, 0);
			unit_box.pack_start (unit_f_radio, false, false, 0);
			content_area.pack_start (unit_box, false, false, 0);

			// Dialog action buttons
			add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
			var save_btn = add_button (_("Save & Apply"), Gtk.ResponseType.OK);
			set_default_response (Gtk.ResponseType.OK);
			save_btn.get_style_context ().add_class ("suggested-action");

			show_all ();
		}

		~WeatherCityDialog ()
		{
			if (search_timer_id != 0) {
				GLib.Source.remove (search_timer_id);
				search_timer_id = 0;
			}
		}

		private void setup_autocomplete ()
		{
			completion = new Gtk.EntryCompletion ();
			completion_store = new Gtk.ListStore (2, typeof (string), typeof (string));
			completion.set_model (completion_store);
			completion.set_text_column (0);
			completion.set_minimum_key_length (2);
			completion.set_popup_completion (true);
			completion.set_inline_completion (false);

			completion.match_selected.connect ((model, iter) => {
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string chosen = (string) val;
				city_entry.text = chosen;
				city_entry.set_position (-1);
				is_valid_selection = true;
				lbl_status.hide ();
				return true;
			});

			city_entry.set_completion (completion);
		}

		private void on_city_entry_changed ()
		{
			is_valid_selection = false;
			lbl_status.hide ();

			if (search_timer_id != 0) {
				GLib.Source.remove (search_timer_id);
				search_timer_id = 0;
			}

			string query = city_entry.text.strip ();
			if (query.length < 2) {
				completion_store.clear ();
				return;
			}

			search_timer_id = GLib.Timeout.add (350, () => {
				search_timer_id = 0;
				query_geocoding_suggestions (query);
				return false;
			});
		}

		private void query_geocoding_suggestions (string query)
		{
			last_queried_text = query;

			new GLib.Thread<void*> ("geo-autocomplete", () => {
				string geo_cmd = "curl -s --max-time 4 'https://geocoding-api.open-meteo.com/v1/search?name=%s&count=6&language=en&format=json'".printf (GLib.Uri.escape_string (query));
				string geo_out;
				int status;
				var suggestions = new Gee.ArrayList<string> ();

				try {
					if (Process.spawn_command_line_sync (geo_cmd, out geo_out, null, out status) && status == 0) {
						var parser = new Json.Parser ();
						parser.load_from_data (geo_out);
						var root = parser.get_root ();
						if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
							var obj = root.get_object ();
							if (obj.has_member ("results")) {
								var results = obj.get_array_member ("results");
								uint len = results.get_length ();
								for (uint i = 0; i < len; i++) {
									var item = results.get_object_element (i);
									string name = item.get_string_member ("name");
									string country = item.has_member ("country") ? item.get_string_member ("country") : "";
									string admin1 = item.has_member ("admin1") ? item.get_string_member ("admin1") : "";

									string display_str;
									if (admin1.length > 0 && admin1.down () != name.down ()) {
										display_str = (country.length > 0) ? "%s, %s, %s".printf (name, admin1, country) : "%s, %s".printf (name, admin1);
									} else if (country.length > 0) {
										display_str = "%s, %s".printf (name, country);
									} else {
										display_str = name;
									}

									suggestions.add (display_str);
								}
							}
						}
					}
				} catch (GLib.Error e) { }

				GLib.Idle.add (() => {
					if (city_entry.text.strip () == query) {
						completion_store.clear ();
						Gtk.TreeIter iter;
						foreach (var s in suggestions) {
							completion_store.append (out iter);
							completion_store.set (iter, 0, s, 1, s);
						}
						if (suggestions.size > 0) {
							completion.complete ();
						}
					}
					return false;
				});

				return null;
			});
		}

		public void init_values (string current_city, string current_units)
		{
			city_entry.text = current_city;
			if (current_city.strip ().length > 0)
				is_valid_selection = true;

			if (current_units.up () == "F") {
				unit_f_radio.active = true;
			} else {
				unit_c_radio.active = true;
			}
		}

		private bool check_location_validity_sync (string query)
		{
			string geo_cmd = "curl -s --max-time 4 'https://geocoding-api.open-meteo.com/v1/search?name=%s&count=1&language=en&format=json'".printf (GLib.Uri.escape_string (query));
			string geo_out;
			int status;
			try {
				if (Process.spawn_command_line_sync (geo_cmd, out geo_out, null, out status) && status == 0) {
					var parser = new Json.Parser ();
					parser.load_from_data (geo_out);
					var root = parser.get_root ();
					if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
						var obj = root.get_object ();
						if (obj.has_member ("results")) {
							var results = obj.get_array_member ("results");
							return (results.get_length () > 0);
						}
					}
				}
			} catch (GLib.Error e) { }
			return false;
		}

		public override void response (int response_id)
		{
			if (response_id == Gtk.ResponseType.OK) {
				string new_city = city_entry.text.strip ();

				// If blank, user explicitly wants automatic IP detection
				if (new_city.length == 0) {
					string new_units = unit_f_radio.active ? "F" : "C";
					weather_item.set_location_and_units ("", new_units);
					destroy ();
					return;
				}

				// If custom text entered, validate that it resolves to a real place
				if (!is_valid_selection) {
					if (!check_location_validity_sync (new_city)) {
						lbl_status.set_markup ("<span color='#e05555' weight='bold'>⚠️ %s</span>".printf (
							_("Location not found. Please choose from suggestions or leave blank.")
						));
						lbl_status.show ();
						city_entry.grab_focus ();
						return; // Do NOT close the dialog!
					}
				}

				string new_units = unit_f_radio.active ? "F" : "C";
				weather_item.set_location_and_units (new_city, new_units);
			}

			destroy ();
		}
	}
}
