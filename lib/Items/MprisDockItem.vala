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
	public class MprisDockItem : DockItem
	{
		uint timer_id = 0;
		ulong media_changed_id = 0;
		string? active_player_id = null;
		string playback_status = "Stopped";
		string track_title = "";
		string track_artist = "";
		bool is_disposed = false;
		bool poll_in_flight = false;
		bool poll_pending = false;
		Gee.HashMap<string, string> last_known_status = new Gee.HashMap<string, string> ();
		Gee.HashMap<string, int> pending_pause_polls = new Gee.HashMap<string, int> ();
		Gee.ArrayList<MediaPlayerInfo> current_players = new Gee.ArrayList<MediaPlayerInfo> ();

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
			media_changed_id = Hal.Bus.Media.players_changed.connect (schedule_player_poll);
			schedule_player_poll ();
			start_timer ();
		}

		private bool cleaned_up = false;

		~MprisDockItem ()
		{
			is_disposed = true;
			if (!cleaned_up) {
				cleaned_up = true;
				notify["IsAttached"].disconnect (on_attached_changed);
			}
			stop_timer ();
			disconnect_media_listener ();
		}

		public override void cleanup ()
		{
			is_disposed = true;
			if (!cleaned_up) {
				cleaned_up = true;
				notify["IsAttached"].disconnect (on_attached_changed);
			}
			stop_timer ();
			disconnect_media_listener ();
			base.cleanup ();
		}

		void disconnect_media_listener ()
		{
			if (media_changed_id != 0) {
				Hal.Bus.Media.disconnect (media_changed_id);
				media_changed_id = 0;
			}
		}

		void on_attached_changed ()
		{
			if (IsAttached && current_players.size > 0)
				schedule_player_poll ();
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
			disconnect_media_listener ();
			base.@delete ();
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

		MediaPlayerInfo? pick_default_player (Gee.ArrayList<MediaPlayerInfo> players)
		{
			MediaPlayerInfo? best = null;
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
					better = (GLib.strcmp (p.player_id, best.player_id) < 0);
				}

				if (better) {
					best = p;
					best_rank = r;
				}
			}

			return best;
		}

		private static void spawn_pause_players_worker (MprisDockItem target, Gee.ArrayList<string> players_to_pause)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-mpris-interlock", () => {
				var failed = new Gee.ArrayList<string> ();
				foreach (string pid in players_to_pause) {
					if (!Hal.Bus.Media.pause_player_sync (pid))
						failed.add (pid);
				}
				Idle.add (() => {
					var self = (MprisDockItem?) self_ref.get ();
					if (self == null || self.is_disposed)
						return false;
					foreach (string pid in players_to_pause) {
						if (failed.contains (pid))
							self.pending_pause_polls.unset (pid);
						else if (self.pending_pause_polls.has_key (pid))
							self.pending_pause_polls.set (pid, 1);
					}
					self.schedule_player_poll ();
					return false;
				});
				return null;
			});
		}

		void pause_players_async (Gee.ArrayList<string> players_to_pause)
		{
			if (players_to_pause.size == 0)
				return;

			spawn_pause_players_worker (this, players_to_pause);
		}

		void pause_other_players (string keep_id, Gee.ArrayList<MediaPlayerInfo> players)
		{
			var to_pause = new Gee.ArrayList<string> ();
			foreach (var p in players) {
				if (p.player_id != keep_id && p.can_pause && p.status == "Playing" && !pending_pause_polls.has_key (p.player_id)) {
					pending_pause_polls.set (p.player_id, 2);
					to_pause.add (p.player_id);
				}
			}
			pause_players_async (to_pause);
		}

		void update_ui_for_chosen (MediaPlayerInfo? chosen)
		{
			if (chosen != null) {
				active_player_id = chosen.player_id;
				bool awaiting_pause = pending_pause_polls.has_key (chosen.player_id);
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
				active_player_id = null;
				playback_status = "Stopped";
				track_title = "";
				track_artist = "";
				Text = _("Media Player (Inactive)");
				Icon = "gnome-mplayer;;applications-multimedia;;audio-player;;multimedia-player";
			}
		}

		void apply_players_snapshot (bool ok, Gee.ArrayList<MediaPlayerInfo> players)
		{
			if (!ok) {
				active_player_id = null;
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

			var live_ids = new Gee.HashSet<string> ();
			foreach (var p in players) {
				string seed_identity = p.identity.strip () != "" ? p.identity : p.fallback_app_name;
				p.identity = ApplicationIdentity.get_identity_for_pid_or_bus (p.owner_pid, "", seed_identity);
				live_ids.add (p.player_id);
			}

			var stale = new Gee.ArrayList<string> ();
			foreach (var k in last_known_status.keys) {
				if (!live_ids.contains (k))
					stale.add (k);
			}
			foreach (var k in stale)
				last_known_status.unset (k);

			var stale_ack = new Gee.ArrayList<string> ();
			foreach (var k in pending_pause_polls.keys) {
				if (!live_ids.contains (k))
					stale_ack.add (k);
			}
			foreach (var k in stale_ack)
				pending_pause_polls.unset (k);

			if (active_player_id != null && !live_ids.contains (active_player_id))
				active_player_id = null;

			bool had_existing = (last_known_status.size > 0);
			string? rising_id = null;
			foreach (var p in players) {
				if (pending_pause_polls.has_key (p.player_id)) {
					if (p.status != "Playing") {
						pending_pause_polls.unset (p.player_id);
					} else {
						int rem = pending_pause_polls.get (p.player_id) - 1;
						if (rem <= 0)
							pending_pause_polls.unset (p.player_id);
						else
							pending_pause_polls.set (p.player_id, rem);
					}
				}

				string? prev = last_known_status.get (p.player_id);
				if (had_existing && !pending_pause_polls.has_key (p.player_id)) {
					if ((prev == null && p.status == "Playing")
						|| (prev != null && prev != "Playing" && p.status == "Playing")) {
						rising_id = p.player_id;
					}
				}
				last_known_status.set (p.player_id, p.status);
			}

			if (rising_id != null) {
				active_player_id = rising_id;
				pause_other_players (rising_id, players);
			} else if (active_player_id == null && players.size > 0) {
				MediaPlayerInfo? def = pick_default_player (players);
				if (def != null) {
					active_player_id = def.player_id;
				}
			}

			current_players = players;
			MediaPlayerInfo? chosen = null;
			if (active_player_id != null) {
				foreach (var p in players) {
					if (p.player_id == active_player_id) {
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
				Gee.ArrayList<MediaPlayerInfo> players;
				bool ok = Hal.Bus.Media.probe_players_sync (out players);
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
			if (Hal.Bus.Media.has_event_subscription () && (current_players.size == 0 || !IsAttached))
				return true;
			schedule_player_poll ();
			return true;
		}

		private static void spawn_player_cmd_worker (MprisDockItem target, string target_id, string method)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-mpris-cmd", () => {
				Hal.Bus.Media.send_player_command_sync (target_id, method);
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
			if (active_player_id == null)
				return;
			string target_id = active_player_id;
			pending_pause_polls.unset (target_id);
			spawn_player_cmd_worker (this, target_id, method);
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
					p_item.active = (p.player_id == active_player_id);
					string target = p.player_id;
					p_item.activate.connect (() => {
						if (target != active_player_id) {
							pause_other_players (target, current_players);
							active_player_id = target;
							MediaPlayerInfo? sel = null;
							foreach (var cp in current_players) {
								if (cp.player_id == target) {
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
