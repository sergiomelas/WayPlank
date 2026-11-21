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
	 * Southbound PipeWire (`wpctl`) / PulseAudio (`pactl`) / ALSA (`amixer`)
	 * system audio sink provider (`IAudioProvider`).
	 */
	public class LinuxAudioTelemetry : GLib.Object, IAudioProvider
	{
		static LinuxAudioTelemetry? default_instance = null;
		static GLib.Mutex init_mutex;
		static string? cached_wpctl_path = null;
		static bool wpctl_probed = false;
		static string[]? c_locale_env = null;

		public static LinuxAudioTelemetry get_default ()
		{
			if (default_instance == null)
				default_instance = new LinuxAudioTelemetry ();
			return default_instance;
		}

		public AudioState probe_state_sync ()
		{
			int out_vol = 70;
			bool out_muted = false;
			int exit_status;
			string output;

			init_mutex.lock ();
			if (!wpctl_probed) {
				cached_wpctl_path = Environment.find_program_in_path ("wpctl");
				c_locale_env = Environ.set_variable (Environ.get (), "LC_ALL", "C", true);
				wpctl_probed = true;
			}
			string? wpctl_path = cached_wpctl_path;
			string[]? locale_env = c_locale_env;
			init_mutex.unlock ();

			if (wpctl_path != null) {
				try {
					string[] argv = { wpctl_path, "get-volume", "@DEFAULT_AUDIO_SINK@" };
					if (Process.spawn_sync (null, argv, locale_env, SpawnFlags.STDERR_TO_DEV_NULL, null, out output, null, out exit_status) && exit_status == 0) {
						var idx = output.index_of ("Volume: ");
						if (idx >= 0) {
							bool parsed_muted = output.contains ("[MUTED]");
							var num_part = output.substring (idx + 8).strip ();
							var space_idx = num_part.index_of (" ");
							if (space_idx >= 0)
								num_part = num_part.substring (0, space_idx);
							num_part = num_part.replace (",", ".");
							double val = double.parse (num_part);
							int parsed_vol = (int) Math.round (val * 100.0);
							if (parsed_vol < 0) parsed_vol = 0;
							return AudioState () { ok = true, volume_percent = parsed_vol, is_muted = parsed_muted };
						}
					}
				} catch (Error e) { }
			}

			try {
				if (Process.spawn_command_line_sync ("sh -c 'LC_ALL=C pactl get-sink-mute @DEFAULT_SINK@; LC_ALL=C pactl get-sink-volume @DEFAULT_SINK@'", out output, null, out exit_status) && exit_status == 0) {
					var idx = output.index_of ("%");
					if (idx > 0) {
						bool parsed_muted = output.contains ("Mute: yes");
						var sub = output.slice (0, idx);
						var last_space = sub.last_index_of (" ");
						if (last_space >= 0) {
							string num_str = sub.slice (last_space + 1, sub.length).strip ();
							int v = int.parse (num_str);
							if (v >= 0) {
								return AudioState () { ok = true, volume_percent = v, is_muted = parsed_muted };
							}
						}
					}
				}
			} catch (Error e) { }

			return AudioState () { ok = false, volume_percent = out_vol, is_muted = out_muted };
		}

		public void set_muted (bool muted)
		{
			if (Environment.find_program_in_path ("wpctl") != null) {
				try {
					Process.spawn_command_line_async ("wpctl set-mute @DEFAULT_AUDIO_SINK@ %s".printf (muted ? "1" : "0"));
				} catch (Error e) { }
			} else {
				try {
					Process.spawn_command_line_async ("pactl set-sink-mute @DEFAULT_SINK@ %s".printf (muted ? "1" : "0"));
				} catch (Error e) {
					try {
						Process.spawn_command_line_async ("amixer set Master %s".printf (muted ? "mute" : "unmute"));
					} catch (Error e2) { }
				}
			}
		}

		public void toggle_mute (bool target_muted_fallback)
		{
			if (Environment.find_program_in_path ("wpctl") != null) {
				try {
					Process.spawn_command_line_async ("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle");
				} catch (Error e) { }
			} else {
				try {
					Process.spawn_command_line_async ("pactl set-sink-mute @DEFAULT_SINK@ %s".printf (target_muted_fallback ? "1" : "0"));
				} catch (Error e) {
					try {
						Process.spawn_command_line_async ("amixer set Master toggle");
					} catch (Error e2) { }
				}
			}
		}

		public void set_volume_percent (int percent)
		{
			int clamped = percent.clamp (0, 150);
			if (Environment.find_program_in_path ("wpctl") != null) {
				try {
					Process.spawn_command_line_async ("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ %d%%".printf (clamped));
				} catch (Error e) { }
			} else {
				try {
					Process.spawn_command_line_async ("pactl set-sink-volume @DEFAULT_SINK@ %d%%".printf (clamped));
				} catch (Error e) {
					try {
						Process.spawn_command_line_async ("amixer set Master %d%%".printf (clamped));
					} catch (Error e2) { }
				}
			}
		}
	}
}
