/*
 *  Copyright (C) 2026 Sergio Melas
 *
 *  This file is part of WayPlank.
 *
 *  WayPlank is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  WayPlank is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef WAYPLANK_WIN32_MEDIA_BRIDGE_H
#define WAYPLANK_WIN32_MEDIA_BRIDGE_H

#include <stdint.h>
#include <glib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*Win32MediaPlayerCallback) (
	const char *player_id,
	const char *identity,
	const char *fallback_app_name,
	const char *status,
	const char *title,
	const char *artist,
	int can_pause,
	int is_browser,
	int owner_pid,
	void *user_data
);

/* Enumerates active Windows media sessions (WinRT GSMTC + CoreAudio/Win32 players like VLC) */
int win32_media_probe_players (Win32MediaPlayerCallback cb, void *user_data);

/* Sends a media command ("playpause", "play", "pause", "next", "previous", "stop") to player_id */
int win32_media_send_command (const char *player_id, const char *command);

#ifdef __cplusplus
}
#endif

#endif /* WAYPLANK_WIN32_MEDIA_BRIDGE_H */
