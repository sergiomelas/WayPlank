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
	public class VolumeDockItem : DockItem
	{
		uint timer_id = 0;
		uint init_timer_1 = 0;
		uint init_timer_2 = 0;
		int volume = 70;
		bool is_muted = false;
		bool is_disposed = false;
		bool poll_in_flight = false;

		public VolumeDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public VolumeDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Volume");
			Icon = "audio-volume-medium";
			Button = PopupButton.RIGHT;

			refresh_volume_status (true);
			notify["IsAttached"].connect (on_attached_changed);
			init_timer_1 = Timeout.add (800, () => {
				init_timer_1 = 0;
				schedule_volume_poll ();
				return false;
			});
			init_timer_2 = Timeout.add (1800, () => {
				init_timer_2 = 0;
				schedule_volume_poll ();
				return false;
			});
			start_timer ();
		}

		private bool cleaned_up = false;

		~VolumeDockItem ()
		{
			is_disposed = true;
			if (!cleaned_up) {
				cleaned_up = true;
				notify["IsAttached"].disconnect (on_attached_changed);
			}
			stop_timer ();
		}

		public override void cleanup ()
		{
			is_disposed = true;
			if (!cleaned_up) {
				cleaned_up = true;
				notify["IsAttached"].disconnect (on_attached_changed);
			}
			stop_timer ();
			base.cleanup ();
		}

		void on_attached_changed ()
		{
			if (IsAttached)
				schedule_volume_poll ();
		}

		void start_timer ()
		{
			if (timer_id != 0)
				return;

			timer_id = Timeout.add_seconds (3, on_timer_tick);
		}

		void stop_timer ()
		{
			if (timer_id != 0) {
				Source.remove (timer_id);
				timer_id = 0;
			}
			if (init_timer_1 != 0) {
				Source.remove (init_timer_1);
				init_timer_1 = 0;
			}
			if (init_timer_2 != 0) {
				Source.remove (init_timer_2);
				init_timer_2 = 0;
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
			base.@delete ();
		}

		void refresh_volume_status (bool is_initial = false)
		{
			var st = Hal.Telemetry.Audio.probe_state_sync ();
			if (st.ok) {
				if (is_initial && (st.is_muted || st.volume_percent == 0))
					return;
				is_muted = st.is_muted;
				volume = st.volume_percent;
				update_display ();
			} else if (!is_initial) {
				update_display ();
			}
		}

		private static void spawn_volume_poll_worker (VolumeDockItem target)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-volume-poll", () => {
				AudioState st = Hal.Telemetry.Audio.probe_state_sync ();
				Idle.add (() => {
					var self = (VolumeDockItem?) self_ref.get ();
					if (self == null)
						return false;
					self.poll_in_flight = false;
					if (self.is_disposed)
						return false;
					if (st.ok && (self.volume != st.volume_percent || self.is_muted != st.is_muted)) {
						self.volume = st.volume_percent;
						self.is_muted = st.is_muted;
						self.update_display ();
					}
					return false;
				});
				return null;
			});
		}

		void schedule_volume_poll ()
		{
			if (is_disposed || poll_in_flight)
				return;
			poll_in_flight = true;

			spawn_volume_poll_worker (this);
		}

		void update_display ()
		{
			if (is_muted) {
				Text = _("Volume: %d%% (Muted)").printf (volume);
				Icon = "audio-volume-muted;;stock_volume-mute";
				BadgeText = null;
				CountVisible = false;
			} else {
				Text = _("Volume: %d%%").printf (volume);
				Count = 1;
				BadgeText = "%d%%".printf (volume);
				CountVisible = true;
				if (volume == 0)
					Icon = "audio-volume-muted;;stock_volume-mute";
				else if (volume < 35)
					Icon = "audio-volume-low;;stock_volume-min";
				else if (volume < 75)
					Icon = "audio-volume-medium;;stock_volume-med";
				else if (volume <= 100)
					Icon = "audio-volume-high;;stock_volume-max";
				else
					Icon = "audio-volume-overamplified;;audio-volume-high-warning;;audio-volume-high-danger;;xfce4-mixer-volume-very-high";
			}
		}

		bool on_timer_tick ()
		{
			if (!IsAttached)
				return true;
			schedule_volume_poll ();
			return true;
		}

		public void change_volume (int delta)
		{
			if (delta > 0 && volume >= 150)
				return;
			if (delta < 0 && volume <= 0)
				return;

			if (is_muted && delta > 0) {
				is_muted = false;
				Hal.Telemetry.Audio.set_muted (false);
			}

			int base_vol = (volume > 150) ? 150 : volume;
			int new_volume = base_vol + delta;
			if (new_volume < 0) new_volume = 0;
			if (new_volume > 150) new_volume = 150;
			volume = new_volume;

			Hal.Telemetry.Audio.set_volume_percent (volume);
			update_display ();
		}

		public void toggle_mute ()
		{
			is_muted = !is_muted;
			Hal.Telemetry.Audio.toggle_mute (is_muted);
			update_display ();
		}

		protected override AnimationType on_scrolled (Gdk.ScrollDirection direction, Gdk.ModifierType mod, uint32 event_time)
		{
			if (direction == Gdk.ScrollDirection.UP) {
				change_volume (5);
				return AnimationType.NONE;
			} else if (direction == Gdk.ScrollDirection.DOWN) {
				change_volume (-5);
				return AnimationType.NONE;
			}
			return base.on_scrolled (direction, mod, event_time);
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				toggle_mute ();
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

			var mute_item = create_menu_item (is_muted ? _("Un_mute") : _("_Mute"), "audio-volume-muted", true);
			mute_item.activate.connect (toggle_mute);
			items.add (mute_item);

			var mixer_item = create_menu_item (_("_Audio Settings..."), "multimedia-volume-control", true);
			mixer_item.activate.connect (() => {
				Hal.Runtime.open_system_utility (DesktopUtilityKind.SOUND_SETTINGS);
			});
			items.add (mixer_item);

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
