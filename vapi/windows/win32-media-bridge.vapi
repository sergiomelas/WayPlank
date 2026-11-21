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

[CCode (cheader_filename = "win32-media-bridge.h")]
namespace Win32MediaBridge
{
	[CCode (cname = "Win32MediaPlayerCallback", has_target = true)]
	public delegate void MediaPlayerCallback (
		string player_id,
		string identity,
		string fallback_app_name,
		string status,
		string title,
		string artist,
		int can_pause,
		int is_browser,
		int owner_pid
	);

	[CCode (cname = "win32_media_probe_players")]
	public static int probe_players (MediaPlayerCallback cb);

	[CCode (cname = "win32_media_send_command")]
	public static int send_command (string player_id, string command);
}
