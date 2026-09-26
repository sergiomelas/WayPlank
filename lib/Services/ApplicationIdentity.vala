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
	 * Desktop-entry identity and matching utilities shared by all backends.
	 */
	public class ApplicationIdentity : GLib.Object
	{
		Gee.HashSet<string> tokens = new Gee.HashSet<string> ();
		Gee.HashSet<string> executable_tokens = new Gee.HashSet<string> ();
		
		public ApplicationIdentity (File desktop_file)
		{
			add_token (desktop_file.get_basename ());
			try {
				var key_file = new KeyFile ();
				key_file.load_from_file (desktop_file.get_path (), KeyFileFlags.NONE);
				if (key_file.has_key (KeyFileDesktop.GROUP, "StartupWMClass"))
					add_token (key_file.get_string (KeyFileDesktop.GROUP, "StartupWMClass"));
				if (key_file.has_key (KeyFileDesktop.GROUP, "X-GNOME-WMClass"))
					add_token (key_file.get_string (KeyFileDesktop.GROUP, "X-GNOME-WMClass"));
				if (key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
					var command = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
					if (command != "") {
						var executable = File.new_for_path (command.split (" ")[0].replace ("\"", "").replace ("'", "")).get_basename ();
						if (executable != null && executable != "")
							executable_tokens.add (normalize (executable));
					}
				}
			} catch (Error e) {
				debug ("Unable to read desktop identity '%s': %s", desktop_file.get_path (), e.message);
			}
		}
		
		void add_token (string? value)
		{
			if (value == null || value.strip () == "")
				return;
			tokens.add (normalize (value));
		}
		
		public static string normalize (string value)
		{
			var normalized = value.strip ().down ();
			if (normalized.has_suffix (".desktop"))
				normalized = normalized.substring (0, normalized.length - ".desktop".length);
			var slash = normalized.last_index_of_char ('/');
			if (slash >= 0)
				normalized = normalized.substring (slash + 1);
			return normalized;
		}
		
		public bool matches (WindowInfo window)
		{
			return match_score (window) > 0;
		}

		public int match_score (WindowInfo window)
		{
			var values = new string[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			var scores = new int[] { 100, 95, 85, 80 };
			var best = 0;
			for (var i = 0; i < values.length; i++) {
				var value = values[i];
				var normalized = normalize (value);
				if (tokens.contains (normalized))
					best = int.max (best, scores[i]);
				var separator = normalized.last_index_of_char ('.');
				if (separator >= 0 && tokens.contains (normalized.substring (separator + 1)))
					best = int.max (best, scores[i] - 20);
			}
			if (window.Executable != "" && executable_tokens.contains (normalize (window.Executable)))
				best = int.max (best, 60);
			return best;
		}
	}
}
