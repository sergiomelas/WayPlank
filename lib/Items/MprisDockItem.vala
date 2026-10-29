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
	public class MprisDockItem : DockItem
	{
		uint timer_id = 0;
		uint dbus_sub_id = 0;
		string? active_player_bus = null;
		string playback_status = "Stopped";
		string track_title = "";
		string track_artist = "";
		
		public MprisDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}
		
		public MprisDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		construct
		{
			Text = _("Media Player");
			Icon = "gnome-mplayer;;applications-multimedia;;audio-player;;multimedia-player";
			Button = PopupButton.RIGHT;
			
			refresh_player_state ();
			start_timer ();
			start_dbus_listener ();
		}
		
		~MprisDockItem ()
		{
			stop_timer ();
			stop_dbus_listener ();
		}
		
		void on_dbus_properties_changed (DBusConnection conn, string? sender, string path, string iface, string signal, Variant parameters)
		{
			refresh_player_state ();
			reset_icon_buffer ();
		}

		void start_dbus_listener ()
		{
			if (dbus_sub_id != 0)
				return;
			try {
				var bus = Bus.get_sync (BusType.SESSION, null);
				dbus_sub_id = bus.signal_subscribe (
					null,
					"org.freedesktop.DBus.Properties",
					"PropertiesChanged",
					null,
					"/org/mpris/MediaPlayer2",
					DBusSignalFlags.NONE,
					on_dbus_properties_changed
				);
			} catch (Error e) { }
		}
		
		void stop_dbus_listener ()
		{
			if (dbus_sub_id != 0) {
				try {
					var bus = Bus.get_sync (BusType.SESSION, null);
					bus.signal_unsubscribe (dbus_sub_id);
				} catch (Error e) { }
				dbus_sub_id = 0;
			}
		}
		
		void start_timer ()
		{
			if (timer_id != 0)
				return;
			
			timer_id = Timeout.add_seconds (1, on_timer_tick);
		}
		
		void stop_timer ()
		{
			if (timer_id != 0) {
				Source.remove (timer_id);
				timer_id = 0;
			}
		}
		
		public override bool is_valid ()
		{
			return true;
		}
		
		public override void @delete ()
		{
			stop_timer ();
			stop_dbus_listener ();
			base.@delete ();
		}

		void extract_metadata (Variant props, out string title, out string artist)
		{
			title = "";
			artist = "";
			var meta_val = props.lookup_value ("Metadata", null);
			if (meta_val == null)
				return;
			var meta = meta_val.is_of_type (VariantType.VARIANT) ? meta_val.get_variant () : meta_val;

			var t_val = meta.lookup_value ("xesam:title", null);
			if (t_val != null) {
				title = t_val.is_of_type (VariantType.VARIANT) ? t_val.get_variant ().get_string () : t_val.get_string ();
			}

			var a_val = meta.lookup_value ("xesam:artist", null);
			if (a_val != null) {
				var a = a_val.is_of_type (VariantType.VARIANT) ? a_val.get_variant () : a_val;
				if (a.is_of_type (VariantType.STRING_ARRAY)) {
					string[] arr = a.get_strv ();
					if (arr.length > 0)
						artist = arr[0];
				} else if (a.is_of_type (VariantType.STRING)) {
					artist = a.get_string ();
				}
			}
		}
		
		void refresh_player_state ()
		{
			try {
				var bus = Bus.get_sync (BusType.SESSION, null);
				var names_variant = bus.call_sync (
					"org.freedesktop.DBus",
					"/org/freedesktop/DBus",
					"org.freedesktop.DBus",
					"ListNames",
					null,
					null,
					DBusCallFlags.NONE,
					500,
					null
				);
				
				active_player_bus = null;
				playback_status = "Stopped";
				track_title = "";
				track_artist = "";

				string[] names = names_variant.get_child_value (0).get_strv ();
				foreach (unowned string name in names) {
					if (!name.has_prefix ("org.mpris.MediaPlayer2."))
						continue;

					try {
						var all_props_var = bus.call_sync (
							name,
							"/org/mpris/MediaPlayer2",
							"org.freedesktop.DBus.Properties",
							"GetAll",
							new Variant ("(s)", "org.mpris.MediaPlayer2.Player"),
							null,
							DBusCallFlags.NO_AUTO_START,
							200,
							null
						);
						var props_dict = all_props_var.get_child_value (0);
						var status_val = props_dict.lookup_value ("PlaybackStatus", null);
						string cur_status = "Stopped";
						if (status_val != null) {
							cur_status = status_val.is_of_type (VariantType.VARIANT) ? status_val.get_variant ().get_string () : status_val.get_string ();
						}

						string cur_title = "";
						string cur_artist = "";
						extract_metadata (props_dict, out cur_title, out cur_artist);

						if (cur_status == "Playing") {
							active_player_bus = name;
							playback_status = cur_status;
							track_title = cur_title;
							track_artist = cur_artist;
							break;
						} else if (cur_status == "Paused" && (active_player_bus == null || playback_status != "Playing")) {
							active_player_bus = name;
							playback_status = cur_status;
							track_title = cur_title;
							track_artist = cur_artist;
						} else if (active_player_bus == null) {
							active_player_bus = name;
							playback_status = cur_status;
							track_title = cur_title;
							track_artist = cur_artist;
						}
					} catch {
						try {
							var status_prop = bus.call_sync (
								name,
								"/org/mpris/MediaPlayer2",
								"org.freedesktop.DBus.Properties",
								"Get",
								new Variant ("(ss)", "org.mpris.MediaPlayer2.Player", "PlaybackStatus"),
								null,
								DBusCallFlags.NO_AUTO_START,
								200,
								null
							);
							var status_val = status_prop.get_child_value (0);
							if (status_val != null) {
								var inner_val = status_val.is_of_type (VariantType.VARIANT) ? status_val.get_variant () : status_val;
								string cur_status = inner_val.get_string ();
								if (cur_status == "Playing") {
									active_player_bus = name;
									playback_status = cur_status;
									break;
								} else if (cur_status == "Paused" && (active_player_bus == null || playback_status != "Playing")) {
									active_player_bus = name;
									playback_status = cur_status;
								}
							}
						} catch { }
					}
				}
				
				if (active_player_bus != null) {
					if (track_title != "") {
						if (track_artist != "")
							Text = "%s - %s (%s)".printf (track_artist, track_title, playback_status);
						else
							Text = "%s (%s)".printf (track_title, playback_status);
					} else {
						Text = _("Media Player (%s)").printf (playback_status);
					}
					
					if (playback_status == "Playing")
						Icon = "media-playback-start;;media-playback-start-symbolic;;player_play";
					else if (playback_status == "Paused")
						Icon = "media-playback-pause;;media-playback-pause-symbolic;;player_pause";
					else
						Icon = "gnome-mplayer;;applications-multimedia;;audio-player;;multimedia-player";
				} else {
					playback_status = "Stopped";
					track_title = "";
					track_artist = "";
					Text = _("Media Player (Inactive)");
					Icon = "gnome-mplayer;;applications-multimedia;;audio-player;;multimedia-player";
				}
			} catch (Error e) {
				playback_status = "Stopped";
				Text = _("Media Player");
				Icon = "gnome-mplayer;;applications-multimedia;;audio-player;;multimedia-player";
			}
		}
		
		bool on_timer_tick ()
		{
			refresh_player_state ();
			reset_icon_buffer ();
			return true;
		}
		
		void call_player_method (string method)
		{
			if (active_player_bus == null)
				return;
			try {
				var bus = Bus.get_sync (BusType.SESSION, null);
				bus.call_sync (
					active_player_bus,
					"/org/mpris/MediaPlayer2",
					"org.mpris.MediaPlayer2.Player",
					method,
					null,
					null,
					DBusCallFlags.NONE,
					500,
					null
				);
				refresh_player_state ();
				reset_icon_buffer ();
			} catch (Error e) { }
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				call_player_method ("PlayPause");
				return AnimationType.BOUNCE;
			}
			if (button == PopupButton.MIDDLE) {
				call_player_method ("Next");
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}
		
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			
			var header_item = new Gtk.MenuItem.with_label (Text);
			header_item.sensitive = false;
			items.add (header_item);
			
			items.add (new Gtk.SeparatorMenuItem ());
			
			var play_item = create_menu_item (_("Play / _Pause"), "media-playback-start", true);
			play_item.activate.connect (() => call_player_method ("PlayPause"));
			items.add (play_item);
			
			var next_item = create_menu_item (_("_Next Track"), "media-skip-forward", true);
			next_item.activate.connect (() => call_player_method ("Next"));
			items.add (next_item);
			
			var prev_item = create_menu_item (_("P_revious Track"), "media-skip-backward", true);
			prev_item.activate.connect (() => call_player_method ("Previous"));
			items.add (prev_item);
			
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
