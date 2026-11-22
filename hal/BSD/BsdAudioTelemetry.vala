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
	 * Southbound FreeBSD audio volume & mute provider.
	 * Milestone B1 skeleton; full `wpctl`/`pactl` + native OSS `/dev/mixer` implementation arrives in Milestone B3.
	 */
	public class BsdAudioTelemetry : GLib.Object, IAudioProvider
	{
		static BsdAudioTelemetry? instance = null;

		public static BsdAudioTelemetry get_default ()
		{
			if (instance == null)
				instance = new BsdAudioTelemetry ();
			return instance;
		}

		public AudioState probe_state_sync ()
		{
			return AudioState () {
				ok = false,
				volume_percent = 70,
				is_muted = false
			};
		}

		public void set_muted (bool muted)
		{
		}

		public void toggle_mute (bool target_muted_fallback)
		{
		}

		public void set_volume_percent (int percent)
		{
		}
	}
}
