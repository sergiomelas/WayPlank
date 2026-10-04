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
	public class MprisDockItem : DockItem
	{
		uint timer_id = 0;
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
			Icon = "multimedia-player;;audio-player;;applications-multimedia";
			Button = PopupButton.RIGHT;
			
			refresh_player_state ();
			start_timer ();
		}
		
		~MprisDockItem ()
		{
			stop_timer ();
		}
		
		void start_timer ()
		{
			if (timer_id != 0)
				return;
			
			timer_id = Timeout.add_seconds (2, on_timer_tick);
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
			base.@delete ();
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
				string[] names = names_variant.get_child_value (0).get_strv ();
				foreach (unowned string name in names) {
					if (name.has_prefix ("org.mpris.MediaPlayer2.")) {
						active_player_bus = name;
						break;
					}
				}
				
				if (active_player_bus != null) {
					// Query PlaybackStatus
					var status_var = bus.call_sync (
						active_player_bus,
						"/org/mpris/MediaPlayer2",
						"org.freedesktop.DBus.Properties",
						"Get",
						new Variant ("(ss)", "org.mpris.MediaPlayer2.Player", "PlaybackStatus"),
						null,
						DBusCallFlags.NONE,
						500,
						null
					);
					var inner = status_var.get_child_value (0).get_variant ();
					playback_status = inner.get_string ();
					
					// Query Metadata
					var meta_var = bus.call_sync (
						active_player_bus,
						"/org/mpris/MediaPlayer2",
						"org.freedesktop.DBus.Properties",
						"Get",
						new Variant ("(ss)", "org.mpris.MediaPlayer2.Player", "Metadata"),
						null,
						DBusCallFlags.NONE,
						500,
						null
					);
					var meta_dict = meta_var.get_child_value (0).get_variant ();
					
					track_title = "";
					track_artist = "";
					
					var title_val = meta_dict.lookup_value ("xesam:title", VariantType.ANY);
					if (title_val != null)
						track_title = title_val.get_variant ().get_string ();
					
					var artist_val = meta_dict.lookup_value ("xesam:artist", VariantType.ANY);
					if (artist_val != null) {
						var artist_variant = artist_val.get_variant ();
						if (artist_variant.is_of_type (VariantType.STRING_ARRAY)) {
							string[] artists = artist_variant.get_strv ();
							if (artists.length > 0) track_artist = artists[0];
						} else if (artist_variant.is_of_type (VariantType.STRING)) {
							track_artist = artist_variant.get_string ();
						}
					}
					
					if (track_title != "") {
						if (track_artist != "")
							Text = "%s - %s (%s)".printf (track_artist, track_title, playback_status);
						else
							Text = "%s (%s)".printf (track_title, playback_status);
					} else {
						Text = _("Media Player (%s)").printf (playback_status);
					}
					
					if (playback_status == "Playing")
						Icon = "media-playback-start;;multimedia-player;;audio-player";
					else if (playback_status == "Paused")
						Icon = "media-playback-pause;;multimedia-player;;audio-player";
					else
						Icon = "multimedia-player;;audio-player;;applications-multimedia";
				} else {
					playback_status = "Stopped";
					track_title = "";
					track_artist = "";
					Text = _("Media Player (Inactive)");
					Icon = "multimedia-player;;audio-player;;applications-multimedia";
				}
			} catch (Error e) {
				playback_status = "Stopped";
				Text = _("Media Player");
				Icon = "multimedia-player;;audio-player";
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
			
			append_dock_menu_items (items);
			return items;
		}
		
		void append_dock_menu_items (Gee.ArrayList<Gtk.MenuItem> items)
		{
			if (items.size > 0)
				items.add (new Gtk.SeparatorMenuItem ());
			var dock_item = Factory.item_factory.get_item_for_dock ();
			if (dock_item != null)
				foreach (var menu_item in dock_item.get_menu_items ())
					items.add (menu_item);
		}
	}
}
