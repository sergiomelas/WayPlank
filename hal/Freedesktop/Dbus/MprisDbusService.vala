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
	 * Southbound `org.mpris.MediaPlayer2` D-Bus driver (`IMediaController`),
	 * preserving 1-to-1 player probing, browser proxy deduplication, identity cache,
	 * and playback transport commands.
	 */
	public class MprisDbusService : GLib.Object, IMediaController
	{
		static MprisDbusService? default_instance = null;
		static Gee.HashMap<string, string>? cached_player_identities = null;
		static Mutex identity_cache_mutex;

		public static MprisDbusService get_default ()
		{
			if (default_instance == null)
				default_instance = new MprisDbusService ();
			return default_instance;
		}

		uint dbus_sub_id = 0U;
		uint dbus_owner_sub_id = 0U;
		DBusConnection? session_bus = null;
		bool shutting_down = false;

		construct
		{
			start_dbus_listener ();
		}

		~MprisDbusService ()
		{
			cleanup ();
		}

		public bool has_event_subscription ()
		{
			return (dbus_sub_id != 0U && dbus_owner_sub_id != 0U);
		}

		void on_dbus_properties_changed (DBusConnection conn, string? sender, string path, string iface, string sig, Variant parameters)
		{
			if (!shutting_down)
				players_changed ();
		}

		void on_dbus_name_owner_changed (DBusConnection conn, string? sender, string path, string iface, string sig, Variant parameters)
		{
			if (shutting_down || parameters.n_children () < 3)
				return;
			string name = parameters.get_child_value (0).get_string ();
			if (name.has_prefix ("org.mpris.MediaPlayer2."))
				players_changed ();
		}

		void start_dbus_listener ()
		{
			if (dbus_sub_id != 0U)
				return;
			session_bus = DbusBroker.get_default ().get_session_bus ();
			if (session_bus == null)
				return;

			dbus_sub_id = session_bus.signal_subscribe (
				null,
				"org.freedesktop.DBus.Properties",
				"PropertiesChanged",
				"/org/mpris/MediaPlayer2",
				null,
				DBusSignalFlags.NONE,
				on_dbus_properties_changed
			);
			dbus_owner_sub_id = session_bus.signal_subscribe (
				"org.freedesktop.DBus",
				"org.freedesktop.DBus",
				"NameOwnerChanged",
				"/org/freedesktop/DBus",
				null,
				DBusSignalFlags.NONE,
				on_dbus_name_owner_changed
			);
		}

		public void cleanup ()
		{
			shutting_down = true;
			if (session_bus != null) {
				if (dbus_sub_id != 0U) {
					session_bus.signal_unsubscribe (dbus_sub_id);
					dbus_sub_id = 0U;
				}
				if (dbus_owner_sub_id != 0U) {
					session_bus.signal_unsubscribe (dbus_owner_sub_id);
					dbus_owner_sub_id = 0U;
				}
			}
		}

		static void extract_metadata (Variant props, out string title, out string artist)
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

		static bool is_plasma_browser_proxy (string bus_name)
		{
			return bus_name == "org.mpris.MediaPlayer2.plasma-browser-integration"
				|| bus_name.has_prefix ("org.mpris.MediaPlayer2.plasma-browser-integration.");
		}

		static bool is_browser_bus (string bus_name)
		{
			if (is_plasma_browser_proxy (bus_name))
				return true;
			string low = bus_name.ascii_down ();
			return low.contains (".chromium")
				|| low.contains (".chrome")
				|| low.contains (".google-chrome")
				|| low.contains (".firefox")
				|| low.contains (".brave")
				|| low.contains (".vivaldi")
				|| low.contains (".opera")
				|| low.contains (".edge")
				|| low.contains (".msedge")
				|| low.contains (".librewolf")
				|| low.contains (".waterfox")
				|| low.contains (".zen")
				|| low.contains (".epiphany");
		}

		public bool probe_players_sync (out Gee.ArrayList<MediaPlayerInfo> players)
		{
			players = new Gee.ArrayList<MediaPlayerInfo> ();

			try {
				var bus = DbusBroker.get_default ().get_session_bus ();
				if (bus == null)
					return false;
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

				string[] raw_names = names_variant.get_child_value (0).get_strv ();
				var candidate_names = new Gee.ArrayList<string> ();
				bool has_native_browser = false;

				foreach (unowned string name in raw_names) {
					if (!name.has_prefix ("org.mpris.MediaPlayer2."))
						continue;
					if (name == "org.mpris.MediaPlayer2.playerctld")
						continue;
					candidate_names.add (name);
					if (is_browser_bus (name) && !is_plasma_browser_proxy (name))
						has_native_browser = true;
				}

				candidate_names.sort ((a, b) => GLib.strcmp (a, b));

				foreach (string name in candidate_names) {
					if (has_native_browser && is_plasma_browser_proxy (name))
						continue;

					string cur_status = "Stopped";
					string cur_title = "";
					string cur_artist = "";
					string cur_identity = "";
					bool cur_can_pause = true;
					bool got_player = false;

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
						if (status_val != null) {
							cur_status = status_val.is_of_type (VariantType.VARIANT) ? status_val.get_variant ().get_string () : status_val.get_string ();
						}
						var can_pause_val = props_dict.lookup_value ("CanPause", null);
						if (can_pause_val != null) {
							var inner_cp = can_pause_val.is_of_type (VariantType.VARIANT) ? can_pause_val.get_variant () : can_pause_val;
							if (inner_cp.is_of_type (VariantType.BOOLEAN))
								cur_can_pause = inner_cp.get_boolean ();
						}
						extract_metadata (props_dict, out cur_title, out cur_artist);
						got_player = true;
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
								cur_status = inner_val.get_string ();
								got_player = true;
							}
						} catch { }
					}

					if (!got_player)
						continue;

					identity_cache_mutex.lock ();
					if (cached_player_identities == null)
						cached_player_identities = new Gee.HashMap<string, string> ();
					string? cached_id = cached_player_identities.get (name);
					identity_cache_mutex.unlock ();

					if (cached_id != null) {
						cur_identity = cached_id;
					} else {
						try {
							var id_prop = bus.call_sync (
								name,
								"/org/mpris/MediaPlayer2",
								"org.freedesktop.DBus.Properties",
								"Get",
								new Variant ("(ss)", "org.mpris.MediaPlayer2", "Identity"),
								null,
								DBusCallFlags.NO_AUTO_START,
								150,
								null
							);
							var id_val = id_prop.get_child_value (0);
							if (id_val != null) {
								cur_identity = id_val.is_of_type (VariantType.VARIANT) ? id_val.get_variant ().get_string () : id_val.get_string ();
							}
						} catch { }

						if (cur_identity != "") {
							identity_cache_mutex.lock ();
							if (cached_player_identities.size > 64)
								cached_player_identities.clear ();
							cached_player_identities.set (name, cur_identity);
							identity_cache_mutex.unlock ();
						}
					}

					int resolved_pid = (int) DbusBroker.get_default ().resolve_sender_pid (name);
					if (resolved_pid <= 0) {
						int inst_idx = name.index_of (".instance");
						if (inst_idx > 0 && inst_idx + 9 < name.length)
							resolved_pid = int.parse (name.substring (inst_idx + 9));
					}

					string clean_bus = name.has_prefix ("org.mpris.MediaPlayer2.")
						? name.substring ("org.mpris.MediaPlayer2.".length)
						: name;
					int fb_inst_idx = clean_bus.index_of (".instance");
					if (fb_inst_idx > 0)
						clean_bus = clean_bus.substring (0, fb_inst_idx);
					string fallback_name = clean_bus.length > 0
						? (clean_bus.substring (0, 1).ascii_up () + clean_bus.substring (1))
						: "";

					var info = new MediaPlayerInfo ();
					info.player_id = name;
					info.identity = cur_identity;
					info.fallback_app_name = fallback_name;
					info.owner_pid = resolved_pid > 0 ? resolved_pid : 0;
					info.status = cur_status;
					info.title = cur_title;
					info.artist = cur_artist;
					info.is_browser = is_browser_bus (name);
					info.can_pause = cur_can_pause;
					players.add (info);
				}
				return true;
			} catch (Error e) {
				return false;
			}
		}

		public bool pause_player_sync (string player_id)
		{
			try {
				var bus = DbusBroker.get_default ().get_session_bus ();
				if (bus == null)
					return false;
				bus.call_sync (
					player_id,
					"/org/mpris/MediaPlayer2",
					"org.mpris.MediaPlayer2.Player",
					"Pause",
					null,
					null,
					DBusCallFlags.NO_AUTO_START,
					400,
					null
				);
				return true;
			} catch (Error e) {
				return false;
			}
		}

		public bool send_player_command_sync (string player_id, string command)
		{
			try {
				var bus = DbusBroker.get_default ().get_session_bus ();
				if (bus == null)
					return false;
				bus.call_sync (
					player_id,
					"/org/mpris/MediaPlayer2",
					"org.mpris.MediaPlayer2.Player",
					command,
					null,
					null,
					DBusCallFlags.NONE,
					500,
					null
				);
				return true;
			} catch (Error e) {
				return false;
			}
		}
	}
}
