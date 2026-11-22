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
	 * Southbound FreeBSD audio sink provider (`IAudioProvider`):
	 * Priority 1: PipeWire (`wpctl`) / PulseAudio (`pactl`) with `LC_ALL=C`
	 * Priority 2: Native FreeBSD OSS (`/dev/mixer*` ioctl via `BsdKernelBridge`)
	 */
	public class BsdAudioTelemetry : GLib.Object, IAudioProvider
	{
		static BsdAudioTelemetry? instance = null;
		static GLib.Mutex init_mutex;
		static string? cached_wpctl_path = null;
		static string? cached_pactl_path = null;
		static bool tools_probed = false;
		static string[]? c_locale_env = null;

		int last_nonzero_oss_vol = 70;

		public static BsdAudioTelemetry get_default ()
		{
			if (instance == null)
				instance = new BsdAudioTelemetry ();
			return instance;
		}

		private static void ensure_probed (out string? wpctl_path, out string? pactl_path, out string[]? locale_env)
		{
			init_mutex.lock ();
			if (!tools_probed) {
				cached_wpctl_path = Environment.find_program_in_path ("wpctl");
				cached_pactl_path = Environment.find_program_in_path ("pactl");
				c_locale_env = Environ.set_variable (Environ.get (), "LC_ALL", "C", true);
				tools_probed = true;
			}
			wpctl_path = cached_wpctl_path;
			pactl_path = cached_pactl_path;
			locale_env = c_locale_env;
			init_mutex.unlock ();
		}

		public AudioState probe_state_sync ()
		{
			string? wpctl_path;
			string? pactl_path;
			string[]? locale_env;
			ensure_probed (out wpctl_path, out pactl_path, out locale_env);

			string output;
			int exit_status;

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

			if (pactl_path != null) {
				try {
					if (Process.spawn_command_line_sync ("sh -c 'LC_ALL=C pactl get-sink-mute @DEFAULT_SINK@; LC_ALL=C pactl get-sink-volume @DEFAULT_SINK@'", out output, null, out exit_status) && exit_status == 0) {
						var idx = output.index_of ("%");
						if (idx > 0) {
							bool parsed_muted = output.contains ("Mute: yes");
							var sub = output.slice (0, idx);
							var last_space = sub.last_index_of (" ");
							if (last_space >= 0) {
								int v = int.parse (sub.slice (last_space + 1, sub.length).strip ());
								if (v >= 0)
									return AudioState () { ok = true, volume_percent = v, is_muted = parsed_muted };
							}
						}
					}
				} catch (Error e) { }
			}

			int oss_vol = 70;
			if (BsdKernelBridge.oss_get_volume (out oss_vol)) {
				if (oss_vol > 0)
					last_nonzero_oss_vol = oss_vol;
				return AudioState () {
					ok = true,
					volume_percent = oss_vol,
					is_muted = (oss_vol == 0)
				};
			}

			return AudioState () { ok = false, volume_percent = 70, is_muted = false };
		}

		public void set_muted (bool muted)
		{
			string? wpctl_path;
			string? pactl_path;
			string[]? locale_env;
			ensure_probed (out wpctl_path, out pactl_path, out locale_env);

			if (wpctl_path != null) {
				try {
					Process.spawn_command_line_async ("wpctl set-mute @DEFAULT_AUDIO_SINK@ %s".printf (muted ? "1" : "0"));
					return;
				} catch (Error e) { }
			}
			if (pactl_path != null) {
				try {
					Process.spawn_command_line_async ("pactl set-sink-mute @DEFAULT_SINK@ %s".printf (muted ? "1" : "0"));
					return;
				} catch (Error e) { }
			}

			if (muted) {
				int cur = 0;
				if (BsdKernelBridge.oss_get_volume (out cur) && cur > 0)
					last_nonzero_oss_vol = cur;
				BsdKernelBridge.oss_set_volume (0);
			} else {
				BsdKernelBridge.oss_set_volume (last_nonzero_oss_vol > 0 ? last_nonzero_oss_vol : 70);
			}
		}

		public void toggle_mute (bool target_muted_fallback)
		{
			string? wpctl_path;
			string? pactl_path;
			string[]? locale_env;
			ensure_probed (out wpctl_path, out pactl_path, out locale_env);

			if (wpctl_path != null) {
				try {
					Process.spawn_command_line_async ("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle");
					return;
				} catch (Error e) { }
			}
			if (pactl_path != null) {
				try {
					Process.spawn_command_line_async ("pactl set-sink-mute @DEFAULT_SINK@ %s".printf (target_muted_fallback ? "1" : "0"));
					return;
				} catch (Error e) { }
			}

			int cur = 0;
			if (BsdKernelBridge.oss_get_volume (out cur)) {
				if (cur > 0) {
					last_nonzero_oss_vol = cur;
					BsdKernelBridge.oss_set_volume (0);
				} else {
					BsdKernelBridge.oss_set_volume (last_nonzero_oss_vol > 0 ? last_nonzero_oss_vol : 70);
				}
			} else {
				set_muted (target_muted_fallback);
			}
		}

		public void set_volume_percent (int percent)
		{
			string? wpctl_path;
			string? pactl_path;
			string[]? locale_env;
			ensure_probed (out wpctl_path, out pactl_path, out locale_env);

			int clamped = percent.clamp (0, 150);
			if (wpctl_path != null) {
				try {
					Process.spawn_command_line_async ("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ %d%%".printf (clamped));
					return;
				} catch (Error e) { }
			}
			if (pactl_path != null) {
				try {
					Process.spawn_command_line_async ("pactl set-sink-volume @DEFAULT_SINK@ %d%%".printf (clamped));
					return;
				} catch (Error e) { }
			}

			int oss_clamped = percent.clamp (0, 100);
			if (oss_clamped > 0)
				last_nonzero_oss_vol = oss_clamped;
			BsdKernelBridge.oss_set_volume (oss_clamped);
		}
	}
}
