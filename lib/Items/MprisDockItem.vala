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
		class MprisPlayerInfo : GLib.Object
		{
			public string bus_name = "";
			public string identity = "";
			public string status = "Stopped";
			public string title = "";
			public string artist = "";
			public bool is_browser = false;
			public bool can_pause = true;
		}

		uint timer_id = 0;
		uint dbus_sub_id = 0;
		uint dbus_owner_sub_id = 0;
		static Gee.HashMap<string, string>? cached_player_identities = null;
		static Mutex identity_cache_mutex;
		string? active_player_bus = null;
		string playback_status = "Stopped";
		string track_title = "";
		string track_artist = "";
		bool is_disposed = false;
		bool poll_in_flight = false;
		bool poll_pending = false;
		Gee.HashMap<string, string> last_known_status = new Gee.HashMap<string, string> ();
		Gee.HashMap<string, int> pending_pause_polls = new Gee.HashMap<string, int> ();
		Gee.ArrayList<MprisPlayerInfo> current_players = new Gee.ArrayList<MprisPlayerInfo> ();
		
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
			
			notify["IsAttached"].connect (on_attached_changed);
			schedule_player_poll ();
			start_timer ();
			start_dbus_listener ();
		}
		
		~MprisDockItem ()
		{
			is_disposed = true;
			notify["IsAttached"].disconnect (on_attached_changed);
			stop_timer ();
			stop_dbus_listener ();
		}

		public override void cleanup ()
		{
			is_disposed = true;
			notify["IsAttached"].disconnect (on_attached_changed);
			stop_timer ();
			stop_dbus_listener ();
			base.cleanup ();
		}

		void on_attached_changed ()
		{
			if (IsAttached && current_players.size > 0)
				schedule_player_poll ();
		}
		
		void on_dbus_properties_changed (DBusConnection conn, string? sender, string path, string iface, string signal, Variant parameters)
		{
			schedule_player_poll ();
		}

		void on_dbus_name_owner_changed (DBusConnection conn, string? sender, string path, string iface, string signal, Variant parameters)
		{
			if (parameters.n_children () < 3)
				return;
			string name = parameters.get_child_value (0).get_string ();
			if (name.has_prefix ("org.mpris.MediaPlayer2."))
				schedule_player_poll ();
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
					"/org/mpris/MediaPlayer2",
					null,
					DBusSignalFlags.NONE,
					on_dbus_properties_changed
				);
				dbus_owner_sub_id = bus.signal_subscribe (
					"org.freedesktop.DBus",
					"org.freedesktop.DBus",
					"NameOwnerChanged",
					"/org/freedesktop/DBus",
					null,
					DBusSignalFlags.NONE,
					on_dbus_name_owner_changed
				);
			} catch (Error e) { }
		}
		
		void stop_dbus_listener ()
		{
			if (dbus_sub_id != 0 || dbus_owner_sub_id != 0) {
				try {
					var bus = Bus.get_sync (BusType.SESSION, null);
					if (dbus_sub_id != 0)
						bus.signal_unsubscribe (dbus_sub_id);
					if (dbus_owner_sub_id != 0)
						bus.signal_unsubscribe (dbus_owner_sub_id);
				} catch (Error e) { }
				dbus_sub_id = 0;
				dbus_owner_sub_id = 0;
			}
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
			is_disposed = true;
			stop_timer ();
			stop_dbus_listener ();
			base.@delete ();
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

		static string truncate_utf8 (string s, int max_chars)
		{
			if (s.char_count () <= max_chars)
				return s;
			int byte_idx = s.index_of_nth_char (max_chars);
			return s.substring (0, byte_idx) + "…";
		}

		static int status_rank (string status)
		{
			if (status == "Playing")
				return 3;
			if (status == "Paused")
				return 2;
			return 1;
		}

		static bool probe_mpris_players (out Gee.ArrayList<MprisPlayerInfo> players)
		{
			players = new Gee.ArrayList<MprisPlayerInfo> ();

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

						cur_identity = ApplicationIdentity.get_identity_for_pid_or_bus (0, name, cur_identity);
						if (cur_identity != "") {
							identity_cache_mutex.lock ();
							if (cached_player_identities.size > 64)
								cached_player_identities.clear ();
							cached_player_identities.set (name, cur_identity);
							identity_cache_mutex.unlock ();
						}
					}

					var info = new MprisPlayerInfo ();
					info.bus_name = name;
					info.identity = cur_identity;
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

		MprisPlayerInfo? pick_default_player (Gee.ArrayList<MprisPlayerInfo> players)
		{
			MprisPlayerInfo? best = null;
			int best_rank = -1;

			foreach (var p in players) {
				int r = status_rank (p.status);
				bool better = false;
				if (best == null) {
					better = true;
				} else if (r != best_rank) {
					better = (r > best_rank);
				} else if (p.is_browser != best.is_browser) {
					better = !p.is_browser;
				} else {
					better = (GLib.strcmp (p.bus_name, best.bus_name) < 0);
				}

				if (better) {
					best = p;
					best_rank = r;
				}
			}

			return best;
		}

		private static void spawn_pause_buses_worker (MprisDockItem target, Gee.ArrayList<string> buses_to_pause)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-mpris-interlock", () => {
				var failed = new Gee.ArrayList<string> ();
				try {
					var bus = Bus.get_sync (BusType.SESSION, null);
					foreach (string b in buses_to_pause) {
						try {
							bus.call_sync (
								b,
								"/org/mpris/MediaPlayer2",
								"org.mpris.MediaPlayer2.Player",
								"Pause",
								null,
								null,
								DBusCallFlags.NO_AUTO_START,
								400,
								null
							);
						} catch (Error e) {
							failed.add (b);
						}
					}
				} catch (Error e) {
					foreach (string b in buses_to_pause)
						failed.add (b);
				}
				Idle.add (() => {
					var self = (MprisDockItem?) self_ref.get ();
					if (self == null || self.is_disposed)
						return false;
					foreach (string b in buses_to_pause) {
						if (failed.contains (b))
							self.pending_pause_polls.unset (b);
						else if (self.pending_pause_polls.has_key (b))
							self.pending_pause_polls.set (b, 1);
					}
					self.schedule_player_poll ();
					return false;
				});
				return null;
			});
		}

		void pause_buses_async (Gee.ArrayList<string> buses_to_pause)
		{
			if (buses_to_pause.size == 0)
				return;

			spawn_pause_buses_worker (this, buses_to_pause);
		}

		void pause_other_players (string keep_bus, Gee.ArrayList<MprisPlayerInfo> players)
		{
			var to_pause = new Gee.ArrayList<string> ();
			foreach (var p in players) {
				if (p.bus_name != keep_bus && p.can_pause && p.status == "Playing" && !pending_pause_polls.has_key (p.bus_name)) {
					pending_pause_polls.set (p.bus_name, 2);
					to_pause.add (p.bus_name);
				}
			}
			pause_buses_async (to_pause);
		}

		void update_ui_for_chosen (MprisPlayerInfo? chosen)
		{
			if (chosen != null) {
				active_player_bus = chosen.bus_name;
				bool awaiting_pause = pending_pause_polls.has_key (chosen.bus_name);
				playback_status = awaiting_pause ? "Paused" : chosen.status;
				track_title = chosen.title;
				track_artist = chosen.artist;

				string status_text = (playback_status == "Playing")
					? _("Playing")
					: ((playback_status == "Paused") ? _("Paused") : _("Stopped"));
				if (track_title != "") {
					if (track_artist != "")
						Text = "%s - %s (%s)".printf (track_artist, track_title, status_text);
					else
						Text = "%s (%s)".printf (track_title, status_text);
				} else if (chosen.identity != "") {
					Text = "%s (%s)".printf (chosen.identity, status_text);
				} else {
					Text = _("Media Player (%s)").printf (status_text);
				}

				if (playback_status == "Playing")
					Icon = "media-playback-pause;;media-playback-pause-symbolic;;player_pause";
				else
					Icon = "media-playback-start;;media-playback-start-symbolic;;player_play";
			} else {
				active_player_bus = null;
				playback_status = "Stopped";
				track_title = "";
				track_artist = "";
				Text = _("Media Player (Inactive)");
				Icon = "gnome-mplayer;;applications-multimedia;;audio-player;;multimedia-player";
			}
		}

		void apply_players_snapshot (bool ok, Gee.ArrayList<MprisPlayerInfo> players)
		{
			if (!ok) {
				active_player_bus = null;
				current_players.clear ();
				last_known_status.clear ();
				pending_pause_polls.clear ();
				playback_status = "Stopped";
				track_title = "";
				track_artist = "";
				Text = _("Media Player");
				Icon = "gnome-mplayer;;applications-multimedia;;audio-player;;multimedia-player";
				return;
			}

			var live_buses = new Gee.HashSet<string> ();
			foreach (var p in players)
				live_buses.add (p.bus_name);

			var stale = new Gee.ArrayList<string> ();
			foreach (var k in last_known_status.keys) {
				if (!live_buses.contains (k))
					stale.add (k);
			}
			foreach (var k in stale)
				last_known_status.unset (k);

			var stale_ack = new Gee.ArrayList<string> ();
			foreach (var k in pending_pause_polls.keys) {
				if (!live_buses.contains (k))
					stale_ack.add (k);
			}
			foreach (var k in stale_ack)
				pending_pause_polls.unset (k);

			if (active_player_bus != null && !live_buses.contains (active_player_bus))
				active_player_bus = null;

			bool had_existing = (last_known_status.size > 0);
			string? rising_bus = null;
			foreach (var p in players) {
				if (pending_pause_polls.has_key (p.bus_name)) {
					if (p.status != "Playing") {
						pending_pause_polls.unset (p.bus_name);
					} else {
						int rem = pending_pause_polls.get (p.bus_name) - 1;
						if (rem <= 0)
							pending_pause_polls.unset (p.bus_name);
						else
							pending_pause_polls.set (p.bus_name, rem);
					}
				}

				string? prev = last_known_status.get (p.bus_name);
				if (had_existing && !pending_pause_polls.has_key (p.bus_name)) {
					if ((prev == null && p.status == "Playing")
						|| (prev != null && prev != "Playing" && p.status == "Playing")) {
						rising_bus = p.bus_name;
					}
				}
				last_known_status.set (p.bus_name, p.status);
			}

			if (rising_bus != null) {
				active_player_bus = rising_bus;
				pause_other_players (rising_bus, players);
			} else if (active_player_bus == null && players.size > 0) {
				MprisPlayerInfo? def = pick_default_player (players);
				if (def != null) {
					active_player_bus = def.bus_name;
				}
			}

			current_players = players;
			MprisPlayerInfo? chosen = null;
			if (active_player_bus != null) {
				foreach (var p in players) {
					if (p.bus_name == active_player_bus) {
						chosen = p;
						break;
					}
				}
			}

			update_ui_for_chosen (chosen);
		}

		private static void spawn_player_poll_worker (MprisDockItem target)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-mpris-poll", () => {
				Gee.ArrayList<MprisPlayerInfo> players;
				bool ok = probe_mpris_players (out players);
				Idle.add (() => {
					var self = (MprisDockItem?) self_ref.get ();
					if (self == null)
						return false;
					self.poll_in_flight = false;
					if (self.is_disposed)
						return false;
					self.apply_players_snapshot (ok, players);
					if (self.poll_pending) {
						self.poll_pending = false;
						self.schedule_player_poll ();
					}
					return false;
				});
				return null;
			});
		}

		void schedule_player_poll ()
		{
			if (is_disposed)
				return;
			if (poll_in_flight) {
				poll_pending = true;
				return;
			}
			poll_in_flight = true;

			spawn_player_poll_worker (this);
		}
		
		bool on_timer_tick ()
		{
			// When NameOwnerChanged & PropertiesChanged are active, skip 2s polling when no players exist or collapsed
			if (dbus_sub_id != 0 && dbus_owner_sub_id != 0 && (current_players.size == 0 || !IsAttached))
				return true;
			schedule_player_poll ();
			return true;
		}
		
		private static void spawn_player_cmd_worker (MprisDockItem target, string target_bus, string method)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-mpris-cmd", () => {
				try {
					var bus = Bus.get_sync (BusType.SESSION, null);
					bus.call_sync (
						target_bus,
						"/org/mpris/MediaPlayer2",
						"org.mpris.MediaPlayer2.Player",
						method,
						null,
						null,
						DBusCallFlags.NONE,
						500,
						null
					);
				} catch (Error e) { }
				Idle.add (() => {
					var self = (MprisDockItem?) self_ref.get ();
					if (self != null && !self.is_disposed)
						self.schedule_player_poll ();
					return false;
				});
				return null;
			});
		}

		void call_player_method (string method)
		{
			if (active_player_bus == null)
				return;
			string target_bus = active_player_bus;
			pending_pause_polls.unset (target_bus);
			spawn_player_cmd_worker (this, target_bus, method);
		}
		
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT || button == PopupButton.MIDDLE) {
				call_player_method ("PlayPause");
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}

		protected override AnimationType on_scrolled (Gdk.ScrollDirection direction, Gdk.ModifierType mod, uint32 event_time)
		{
			if (GLib.get_monotonic_time () - LastScrolled < 250000)
				return AnimationType.NONE;

			base.on_scrolled (direction, mod, event_time);

			if (direction == Gdk.ScrollDirection.UP || direction == Gdk.ScrollDirection.RIGHT)
				call_player_method ("Next");
			else if (direction == Gdk.ScrollDirection.DOWN || direction == Gdk.ScrollDirection.LEFT)
				call_player_method ("Previous");

			return AnimationType.NONE;
		}
		
		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			if (current_players.size >= 2) {
				foreach (var p in current_players) {
					string st_text = (p.status == "Playing")
						? _("Playing")
						: ((p.status == "Paused") ? _("Paused") : _("Stopped"));
					string label = (p.title != "")
						? "%s — %s (%s)".printf (p.identity, truncate_utf8 (p.title, 32), st_text)
						: "%s (%s)".printf (p.identity, st_text);

					var p_item = new Gtk.CheckMenuItem.with_label (label);
					p_item.draw_as_radio = true;
					p_item.active = (p.bus_name == active_player_bus);
					string target = p.bus_name;
					p_item.activate.connect (() => {
						if (target != active_player_bus) {
							pause_other_players (target, current_players);
							active_player_bus = target;
							MprisPlayerInfo? sel = null;
							foreach (var cp in current_players) {
								if (cp.bus_name == target) {
									sel = cp;
									break;
								}
							}
							update_ui_for_chosen (sel);
						}
					});
					items.add (p_item);
				}
			} else {
				var header_item = new Gtk.MenuItem.with_label (Text);
				header_item.sensitive = false;
				items.add (header_item);
			}
			
			items.add (new Gtk.SeparatorMenuItem ());
			
			string toggle_icon = (playback_status == "Playing") ? "media-playback-pause" : "media-playback-start";
			var play_item = create_menu_item (_("Play / _Pause"), toggle_icon, true);
			play_item.activate.connect (() => call_player_method ("PlayPause"));
			items.add (play_item);
			
			var next_item = create_menu_item (_("_Next Track"), "media-skip-forward", true);
			next_item.activate.connect (() => call_player_method ("Next"));
			items.add (next_item);
			
			var prev_item = create_menu_item (_("P_revious Track"), "media-skip-backward", true);
			prev_item.activate.connect (() => call_player_method ("Previous"));
			items.add (prev_item);
			
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
	}
}
