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
		Gee.ArrayList<string> argument_tokens = new Gee.ArrayList<string> ();
		string app_name = "";
		
		public ApplicationIdentity (File desktop_file)
		{
			add_token (desktop_file.get_basename ());
			var path = desktop_file.get_path ();
			if (path == null)
				return;
			try {
				var key_file = new KeyFile ();
				key_file.load_from_file (path, KeyFileFlags.NONE);
				if (key_file.has_key (KeyFileDesktop.GROUP, "StartupWMClass"))
					add_token (key_file.get_string (KeyFileDesktop.GROUP, "StartupWMClass"));
				if (key_file.has_key (KeyFileDesktop.GROUP, "X-GNOME-WMClass"))
					add_token (key_file.get_string (KeyFileDesktop.GROUP, "X-GNOME-WMClass"));
				if (key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME)) {
					var raw_name = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME).strip ();
					if (raw_name != "") {
						app_name = raw_name.down ();
						add_token (app_name);
					}
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
					var command = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
					if (command != "") {
						string[] parts;
						try {
							GLib.Shell.parse_argv (command, out parts);
						} catch (Error e) {
							parts = command.split (" ");
						}
						if (parts.length > 0) {
							var executable = File.new_for_path (parts[0].replace ("\"", "").replace ("'", "")).get_basename ();
							if (executable != null && executable != "")
								executable_tokens.add (normalize (executable));

							for (int i = 1; i < parts.length; i++) {
								var part = parts[i].strip ().replace ("\"", "").replace ("'", "");
								if (part == "" || part.has_prefix ("-") || part.has_prefix ("%"))
									continue;
								var target_name = File.new_for_path (part).get_basename ().down ();
								if (target_name != "" && target_name != ".") {
									argument_tokens.add (target_name);
									var dot = target_name.last_index_of_char ('.');
									if (dot > 0)
										argument_tokens.add (target_name.substring (0, dot));
								}
							}
						}
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
		
		public static string normalize (string? value)
		{
			if (value == null || value == "")
				return "";
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
			var values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			var scores = new int[] { 100, 95, 85, 80 };
			var best = 0;
			for (var i = 0; i < values.length; i++) {
				var value = values[i];
				if (value == null || value == "")
					continue;
				var normalized = normalize (value);
				if (normalized == "")
					continue;
				if (tokens.contains (normalized))
					best = int.max (best, scores[i]);
				var separator = normalized.last_index_of_char ('.');
				if (separator >= 0 && tokens.contains (normalized.substring (separator + 1)))
					best = int.max (best, scores[i] - 20);
			}

			// If launcher has specific target arguments (e.g. Windows 10 x64.vmx), check window cmdline
			if (window.Cmdline != "" && argument_tokens.size > 0) {
				var cmdline_down = window.Cmdline.down ();
				foreach (var arg in argument_tokens) {
					if (arg.length >= 3 && cmdline_down.contains (arg)) {
						best = int.max (best, 95);
						break;
					}
				}
			}

			// Match window Caption (Title) against desktop Name or argument tokens
			if (window.Caption != "") {
				var caption_down = window.Caption.down ();
				if (app_name != "" && app_name.length >= 3 && caption_down.contains (app_name)) {
					if (window.Executable != "" && executable_tokens.contains (normalize (window.Executable)))
						best = int.max (best, 90);
					else if (executable_tokens.size == 0)
						best = int.max (best, 75);
					else
						best = int.max (best, 70);
				}
				foreach (var arg in argument_tokens) {
					if (arg.length >= 3 && caption_down.contains (arg)) {
						best = int.max (best, 90);
						break;
					}
				}
			}

			if (window.Executable != "" && executable_tokens.contains (normalize (window.Executable))) {
				if (argument_tokens.size == 0)
					best = int.max (best, 60);
			}
			return best;
		}
	}
}
