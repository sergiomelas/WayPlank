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
	public class VolumeDockItem : DockItem
	{
		uint timer_id = 0;
		int volume = 70;
		bool is_muted = false;
		
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
			
			refresh_volume_status ();
			start_timer ();
		}
		
		~VolumeDockItem ()
		{
			stop_timer ();
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
		
		void refresh_volume_status ()
		{
			int exit_status;
			string output;
			
			// 1. Try WirePlumber (PipeWire) native wpctl if available
			if (Environment.find_program_in_path ("wpctl") != null) {
				try {
					if (Process.spawn_command_line_sync ("wpctl get-volume @DEFAULT_AUDIO_SINK@", out output, null, out exit_status) && exit_status == 0) {
						is_muted = output.contains ("[MUTED]");
						var idx = output.index_of ("Volume: ");
						if (idx >= 0) {
							var num_part = output.substring (idx + 8).strip ();
							var space_idx = num_part.index_of (" ");
							if (space_idx >= 0)
								num_part = num_part.substring (0, space_idx);
							double val = double.parse (num_part);
							volume = (int) Math.round (val * 100.0);
							if (volume < 0) volume = 0;
							update_display ();
							return;
						}
					}
				} catch (Error e) { }
			}
			
			// 2. PulseAudio / pactl single invocation for both mute and volume
			try {
				if (Process.spawn_command_line_sync ("sh -c 'pactl get-sink-mute @DEFAULT_SINK@; pactl get-sink-volume @DEFAULT_SINK@'", out output, null, out exit_status) && exit_status == 0) {
					is_muted = output.contains ("Mute: yes");
					var idx = output.index_of ("%");
					if (idx > 0) {
						var sub = output.slice (0, idx);
						var last_space = sub.last_index_of (" ");
						if (last_space >= 0) {
							string num_str = sub.slice (last_space + 1, sub.length).strip ();
							int v = int.parse (num_str);
							if (v >= 0)
								volume = v;
						}
					}
				}
			} catch (Error e) { }
			
			update_display ();
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
				Count = volume;
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
			refresh_volume_status ();
			reset_icon_buffer ();
			return true;
		}
		
		public void change_volume (int delta)
		{
			// If already at or above maximum and trying to increase, block
			if (delta > 0 && volume >= 150)
				return;
			// If already at zero or below and trying to decrease, block
			if (delta < 0 && volume <= 0)
				return;

			// If muted and raising volume, unmute immediately!
			if (is_muted && delta > 0) {
				is_muted = false;
				if (Environment.find_program_in_path ("wpctl") != null) {
					try {
						Process.spawn_command_line_async ("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0");
					} catch (Error e) { }
				} else {
					try {
						Process.spawn_command_line_async ("pactl set-sink-mute @DEFAULT_SINK@ 0");
					} catch (Error e) {
						try {
							Process.spawn_command_line_async ("amixer set Master unmute");
						} catch (Error e2) { }
					}
				}
			}
			
			int base_vol = (volume > 150) ? 150 : volume;
			int new_volume = base_vol + delta;
			if (new_volume < 0) new_volume = 0;
			if (new_volume > 150) new_volume = 150;
			volume = new_volume;
			
			// Always set ABSOLUTE volume to prevent unlimited relative runaway
			if (Environment.find_program_in_path ("wpctl") != null) {
				try {
					Process.spawn_command_line_async ("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ %d%%".printf (volume));
				} catch (Error e) { }
			} else {
				try {
					Process.spawn_command_line_async ("pactl set-sink-volume @DEFAULT_SINK@ %d%%".printf (volume));
				} catch (Error e) {
					try {
						Process.spawn_command_line_async ("amixer set Master %d%%".printf (volume));
					} catch (Error e2) { }
				}
			}
			
			update_display ();
			reset_icon_buffer ();
		}
		
		public void toggle_mute ()
		{
			is_muted = !is_muted;
			
			if (Environment.find_program_in_path ("wpctl") != null) {
				try {
					Process.spawn_command_line_async ("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle");
				} catch (Error e) { }
			} else {
				try {
					Process.spawn_command_line_async ("pactl set-sink-mute @DEFAULT_SINK@ %s".printf (is_muted ? "1" : "0"));
				} catch (Error e) {
					try {
						Process.spawn_command_line_async ("amixer set Master toggle");
					} catch (Error e2) { }
				}
			}
			
			update_display ();
			reset_icon_buffer ();
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
				string[] mixers = { "kcmshell6 kcm_pulseaudio", "kcmshell5 kcm_pulseaudio", "pavucontrol" };
				foreach (var m in mixers) {
					try {
						Process.spawn_command_line_async (m);
						break;
					} catch (Error e) { }
				}
			});
			items.add (mixer_item);
			
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
