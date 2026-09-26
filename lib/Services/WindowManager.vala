//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of Wayplank.
//
//  Wayplank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Wayplank is distributed in the hope that it will be useful,
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
	 * Compositor-neutral application window policy and grouping.
	 */
	public class WindowManager : GLib.Object
	{
		static WindowManager? instance;
		
		public static unowned WindowManager get_default ()
		{
			if (instance == null)
				instance = new WindowManager ();
			return instance;
		}
		
		WindowManager ()
		{
			cached_windows = new Gee.ArrayList<WindowInfo> ();
			matches_cache = new Gee.HashMap<string, Gee.ArrayList<WindowInfo>> ();
			WindowControl.get_default ().state_changed.connect (refresh_windows);
		}

		~WindowManager ()
		{
			WindowControl.get_default ().state_changed.disconnect (refresh_windows);
		}

		Gee.ArrayList<WindowInfo> cached_windows;
		Gee.HashMap<string, Gee.ArrayList<WindowInfo>> matches_cache;

		void refresh_windows ()
		{
			cached_windows = WindowControl.get_windows ();
			matches_cache.clear ();
		}
		
		static string normalize_id (string id)
		{
			var normalized = id.down ();
			if (normalized.has_suffix (".desktop"))
				normalized = normalized.substring (0, normalized.length - ".desktop".length);
			return normalized;
		}
		
		static bool matches_app (WindowInfo window, string app_id)
		{
			var normalized = normalize_id (app_id);
			if (window.ApplicationId == normalized)
				return true;
			var separator = window.ApplicationId.last_index_of_char ('.');
			return separator >= 0 && window.ApplicationId.substring (separator + 1) == normalized;
		}

		ApplicationIdentity? identity_for_launcher (string launcher_uri)
		{
			return ApplicationDiscovery.get_default ().identity_for_launcher (launcher_uri);
		}
		
		Gee.ArrayList<WindowInfo> matching_windows (string launcher_uri)
		{
			if (matches_cache.has_key (launcher_uri))
				return matches_cache.get (launcher_uri);

			var result = new Gee.ArrayList<WindowInfo> ();
			var app_id = File.new_for_uri (launcher_uri).get_basename ();
			var identity = identity_for_launcher (launcher_uri);
			foreach (var window in cached_windows)
				if ((identity != null && identity.matches (window)) || (identity == null && matches_app (window, app_id)))
					result.add (window);
			matches_cache.set (launcher_uri, result);
			return result;
		}
		
		public int window_count_for_app (string launcher_uri)
		{
			return matching_windows (launcher_uri).size;
		}
		
		public bool app_demands_attention (string launcher_uri)
		{
			foreach (var window in matching_windows (launcher_uri))
				if (window.DemandsAttention)
					return true;
			return false;
		}
		
		public bool resolve_click_command (string launcher_uri, int click_behavior, bool restore_minimized,
			out string? target, out string action)
		{
			target = null;
			action = "activate";
			var matches = matching_windows (launcher_uri);
			if (matches.size == 0)
				return false;
			
			if (matches.size == 1) {
				target = matches[0].Id;
				action = "toggle";
				return true;
			}
			
			var visible = new Gee.ArrayList<WindowInfo> ();
			foreach (var window in matches)
				if (!window.Minimized)
					visible.add (window);
			
			if (visible.size == 0) {
				if (!restore_minimized)
					return false;
				WindowInfo? newest = null;
				foreach (var window in matches)
					if (newest == null || window.MinimizedSequence > newest.MinimizedSequence)
						newest = window;
				if (newest != null) {
					target = newest.Id;
					return true;
				}
			}
			
			var active_index = -1;
			for (var i = 0; i < visible.size; i++)
				if (visible[i].Active) {
					active_index = i;
					break;
				}
			
			if (visible.size == 1 && active_index == 0 && restore_minimized) {
				foreach (var window in matches)
					if (window.Minimized) {
						target = window.Id;
						return true;
					}
			}
			
			if (click_behavior == 1) {
				target = visible[active_index >= 0 ? active_index : 0].Id;
				return true;
			}
			
			var next_index = (active_index + 1) % visible.size;
			target = visible[next_index].Id;
			return true;
		}
	}
}
