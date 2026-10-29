//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//  Copyright (C) 2026 史有虎 (IFtiger-hu)
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
	 * Desktop-entry identity and matching utilities shared by all backends.
	 */
	public class ApplicationIdentity : GLib.Object
	{
		Gee.HashSet<string> tokens = new Gee.HashSet<string> ();
		Gee.HashSet<string> primary_tokens = new Gee.HashSet<string> ();
		Gee.HashSet<string> word_tokens = new Gee.HashSet<string> ();
		Gee.HashSet<string> executable_tokens = new Gee.HashSet<string> ();
		Gee.ArrayList<string> argument_tokens = new Gee.ArrayList<string> ();
		string app_name = "";
		string base_id = "";
		
		public ApplicationIdentity (File desktop_file)
		{
			base_id = normalize (desktop_file.get_basename ());
			add_token (base_id);
			primary_tokens.add (base_id);
			var path = desktop_file.get_path ();
			if (path == null)
				return;
			try {
				var key_file = new KeyFile ();
				key_file.load_from_file (path, KeyFileFlags.NONE);
				if (key_file.has_key (KeyFileDesktop.GROUP, "StartupWMClass")) {
					var swmc = key_file.get_string (KeyFileDesktop.GROUP, "StartupWMClass");
					add_token (swmc);
					add_token_variants (swmc);
					var norm_swmc = normalize (swmc);
					if (norm_swmc != "") {
						primary_tokens.add (norm_swmc);
						if (norm_swmc.has_prefix ("crx_")) {
							var crx_id = norm_swmc.substring (4);
							if (crx_id.length >= 3) {
								add_token (crx_id);
								primary_tokens.add (crx_id);
								argument_tokens.add (crx_id);
							}
						}
					}
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, "X-GNOME-WMClass")) {
					var gmc = key_file.get_string (KeyFileDesktop.GROUP, "X-GNOME-WMClass");
					add_token (gmc);
					add_token_variants (gmc);
					var norm_gmc = normalize (gmc);
					if (norm_gmc != "")
						primary_tokens.add (norm_gmc);
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME)) {
					var raw_name = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME).strip ();
					if (raw_name != "") {
						app_name = raw_name.down ();
						add_token (app_name);
						add_token_variants (raw_name);
					}
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
					var command = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
					if (command != "") {
						parse_exec_command (command);
					}
				}
			} catch (Error e) {
				debug ("Unable to read desktop identity '%s': %s", desktop_file.get_path (), e.message);
			}
		}

		private void parse_exec_command (string command)
		{
			var unwrap_tokens = unwrap_command_string (command);
			if (unwrap_tokens.size == 0)
				return;

			var raw_exe = unwrap_tokens.get (0);
			var exe_name = File.new_for_path (raw_exe).get_basename ();
			if (exe_name != "") {
				add_executable_token (exe_name);
			}

			// If the target executable is a shell script (.sh), inspect it!
			if (raw_exe.has_suffix (".sh")) {
				string? script_target = null;
				if (GLib.FileUtils.test (raw_exe, GLib.FileTest.IS_REGULAR)) {
					script_target = raw_exe;
				} else {
					script_target = GLib.Environment.find_program_in_path (raw_exe);
				}

				if (script_target != null) {
					inspect_script_file (script_target);
				}
			}

			for (int i = 1; i < unwrap_tokens.size; i++) {
				var part = unwrap_tokens.get (i).strip ().replace ("\"", "").replace ("'", "");
				if (part == "" || part.has_prefix ("%") || part.has_prefix ("@"))
					continue;

				// Parameter option with value like --profile-directory="Profile 14", --app-id=..., or --app=...
				if (part.contains ("=")) {
					var eq = part.index_of_char ('=');
					var opt_key = part.substring (0, eq).down ();
					if (opt_key.contains ("profile") || opt_key.contains ("class") || opt_key.contains ("app")) {
						var val = part.substring (eq + 1).strip ().replace ("\"", "").replace ("'", "").down ();
						if (val != "" && val.length >= 3) {
							argument_tokens.add (val);
							if (val.has_prefix ("http://") || val.has_prefix ("https://")) {
								var slash_idx = val.index_of ("://");
								var host_part = val.substring (slash_idx + 3);
								var end_host = host_part.index_of_char ('/');
								if (end_host > 0)
									host_part = host_part.substring (0, end_host);
								var at_idx = host_part.last_index_of_char ('@');
								if (at_idx >= 0)
									host_part = host_part.substring (at_idx + 1);
								var port_idx = host_part.index_of_char (':');
								if (port_idx > 0)
									host_part = host_part.substring (0, port_idx);
								if (host_part != "") {
									argument_tokens.add (host_part);
									var host_dot = host_part.last_index_of_char ('.');
									if (host_dot > 0) {
										var sld = host_part.substring (0, host_dot);
										var first_dot = sld.last_index_of_char ('.');
										if (first_dot >= 0)
											sld = sld.substring (first_dot + 1);
										if (sld.length >= 3 && !is_common_stopword (sld))
											argument_tokens.add (sld);
									}
								}
							}
						}
					}
				}

				var target_name = File.new_for_path (part).get_basename ().down ();
				if (target_name != "" && target_name != "." && !target_name.has_prefix ("-") && !target_name.has_prefix ("@") && !is_generic_argument_stopword (target_name)) {
					argument_tokens.add (target_name);
					var dot = target_name.last_index_of_char ('.');
					if (dot > 0) {
						var sub_name = target_name.substring (0, dot);
						if (!is_generic_argument_stopword (sub_name))
							argument_tokens.add (sub_name);
					}
				}
			}
		}

		private void inspect_script_file (string script_path)
		{
			try {
				string content;
				if (!GLib.FileUtils.get_contents (script_path, out content))
					return;

				// Limit scanning to small launcher wrapper scripts (< 4KB)
				if (content.length > 4096)
					return;

				// Fast check: must start with a shell shebang
				if (!content.has_prefix ("#!/bin/") && !content.has_prefix ("#!/usr/bin/env") && !content.has_prefix ("#! /bin/"))
					return;

				string[] lines = content.split ("\n");
				foreach (var raw_line in lines) {
					var line = raw_line.strip ();
					if (line == "" || line.has_prefix ("#"))
						continue;
					// Skip shell builtins and non-launcher utilities
					if (line.has_prefix ("echo ") || line.has_prefix ("printf ") || line.has_prefix ("export ") ||
					    line.has_prefix ("sleep ") || line.has_prefix ("killall ") || line.has_prefix ("kill ") ||
					    line.has_prefix ("cd ") || line.has_prefix ("mkdir ") || line.has_prefix ("wait") ||
					    line.has_prefix ("exit") || line.has_prefix ("trap ") || line.has_prefix ("source ") ||
					    line.has_prefix (". "))
						continue;

					var script_tokens = unwrap_command_string (line);
					if (script_tokens.size > 0) {
						var inner_exe = File.new_for_path (script_tokens.get (0)).get_basename ();
						if (inner_exe != "" && inner_exe != "sh" && inner_exe != "bash") {
							add_executable_token (inner_exe);
						}
						for (int i = 1; i < script_tokens.size; i++) {
							var s_arg = script_tokens.get (i).strip ().replace ("\"", "").replace ("'", "");
							if (s_arg.contains ("=")) {
								var eq = s_arg.index_of_char ('=');
								var opt_key = s_arg.substring (0, eq).down ();
								if (opt_key.contains ("profile") || opt_key.contains ("class") || opt_key.contains ("app")) {
									var val = s_arg.substring (eq + 1).strip ().replace ("\"", "").replace ("'", "").down ();
									if (val != "" && val.length >= 3) {
										argument_tokens.add (val);
									}
								}
							}
						}
					}
				}
			} catch (Error e) { }
		}

		private Gee.ArrayList<string> unwrap_command_string (string command_line)
		{
			var result = new Gee.ArrayList<string> ();
			string[] parts;
			try {
				GLib.Shell.parse_argv (command_line.strip (), out parts);
			} catch (Error e) {
				parts = command_line.strip ().split (" ");
			}
			if (parts.length == 0)
				return result;

			int idx = 0;
			while (idx < parts.length) {
				var p = parts[idx].strip ().replace ("\"", "").replace ("'", "");
				var base_p = File.new_for_path (p).get_basename ().down ();

				// 1. Recursive unwrap for sh -c "..." or bash -c "..."
				if (base_p == "sh" || base_p == "bash") {
					if (idx + 1 < parts.length && parts[idx + 1] == "-c") {
						if (idx + 2 < parts.length) {
							return unwrap_command_string (parts[idx + 2]);
						}
					}
					idx++;
					continue;
				}

				// 2. Skip env or /usr/bin/env
				if (base_p == "env") {
					idx++;
					continue;
				}

				// 3. Skip environment variable assignments like TMPDIR=..., MESA_GL_VERSION_OVERRIDE=...
				if (p.contains ("=") && !p.has_prefix ("-")) {
					idx++;
					continue;
				}

				// 4. Skip common launcher / sandbox wrappers
				if (base_p == "firejail" || base_p == "flatpak-spawn" || base_p == "pkexec" ||
				    base_p == "sudo" || base_p == "prime-run" || base_p == "gamemoderun" ||
				    base_p == "optirun" || base_p == "systemd-inhibit" || base_p == "nohup") {
					idx++;
					while (idx < parts.length && parts[idx].has_prefix ("-")) {
						idx++;
					}
					continue;
				}

				if (base_p == "flatpak") {
					idx++;
					if (idx < parts.length && parts[idx] == "run")
						idx++;
					while (idx < parts.length && parts[idx].has_prefix ("-")) {
						if (parts[idx].has_prefix ("--command=")) {
							var cmd_target = parts[idx].substring ("--command=".length).strip ().replace ("\"", "").replace ("'", "");
							if (cmd_target != "") {
								add_executable_token (cmd_target);
							}
						}
						idx++;
					}
					continue;
				}

				// First real binary found! Add it and all remaining arguments
				for (int j = idx; j < parts.length; j++) {
					var tok = parts[j].strip ();
					if (tok != "")
						result.add (tok);
				}
				break;
			}

			return result;
		}

		private void add_executable_token (string raw_name)
		{
			var norm = normalize (raw_name);
			if (norm == "" || norm == "sh" || norm == "bash" || norm == "env")
				return;
			executable_tokens.add (norm);
			tokens.add (norm);

			// Prefix match for dashed binaries (e.g. qemu-system-x86_64 -> qemu)
			var first_dash = norm.index_of_char ('-');
			if (first_dash > 0) {
				var prefix = norm.substring (0, first_dash);
				if (prefix.length >= 3 && !is_common_stopword (prefix)) {
					executable_tokens.add (prefix);
					tokens.add (prefix);
				}
			}

			// Auto-register binary aliases (-bin variant, google-chrome vs chrome, etc.)
			if (norm.has_suffix ("-bin")) {
				var base_name = norm.substring (0, norm.length - 4);
				if (base_name.length >= 3) {
					executable_tokens.add (base_name);
					tokens.add (base_name);
				}
			} else {
				executable_tokens.add (norm + "-bin");
				tokens.add (norm + "-bin");
			}

			// Auto-register AppImage aliases by stripping .AppImage, architectures, and semantic version numbers
			if (norm.has_suffix (".appimage")) {
				var appimage_base = norm.substring (0, norm.length - 9);
				if (appimage_base.length >= 3) {
					executable_tokens.add (appimage_base);
					tokens.add (appimage_base);
					string[] arches = { "-x86_64", "_x86_64", "-x64", "_x64", "-amd64", "_amd64", "-linux", "_linux", "-i386", "_i386", "-arm64", "_arm64", "-aarch64", "_aarch64" };
					var arch_stripped = appimage_base;
					foreach (var arch in arches) {
						if (arch_stripped.has_suffix (arch)) {
							arch_stripped = arch_stripped.substring (0, arch_stripped.length - arch.length);
							break;
						}
					}
					try {
						var ver_regex = new GLib.Regex ("[-_vV]+[0-9]+(\\.[0-9]+)*.*$");
						var clean_name = ver_regex.replace_literal (arch_stripped, -1, 0, "");
						if (clean_name != "" && clean_name.length >= 3) {
							executable_tokens.add (clean_name);
							tokens.add (clean_name);
							tokens.add (clean_name.replace ("-", " "));
							tokens.add (clean_name.replace ("_", " "));
						}
					} catch (Error e) { }
				}
			} else {
				try {
					var ver_regex = new GLib.Regex ("[-_vV]+[0-9]+(\\.[0-9]+)+.*$");
					var clean_name = ver_regex.replace_literal (norm, -1, 0, "");
					if (clean_name != norm && clean_name != "" && clean_name.length >= 3) {
						executable_tokens.add (clean_name);
						tokens.add (clean_name);
						tokens.add (clean_name.replace ("-", " "));
						tokens.add (clean_name.replace ("_", " "));
					}
				} catch (Error e) { }
			}

			if (norm == "google-chrome" || norm == "google-chrome-stable") {
				executable_tokens.add ("chrome");
				tokens.add ("chrome");
			} else if (norm == "chrome") {
				executable_tokens.add ("google-chrome");
				tokens.add ("google-chrome");
			} else if (norm == "chromium" || norm == "chromium-browser") {
				executable_tokens.add ("chromium");
				executable_tokens.add ("chromium-browser");
				tokens.add ("chromium");
				tokens.add ("chromium-browser");
			} else if (norm == "brave" || norm == "brave-browser") {
				executable_tokens.add ("brave");
				executable_tokens.add ("brave-browser");
				tokens.add ("brave");
				tokens.add ("brave-browser");
			} else if (norm == "microsoft-edge" || norm == "msedge" || norm == "microsoft-edge-stable") {
				executable_tokens.add ("msedge");
				executable_tokens.add ("microsoft-edge");
				tokens.add ("msedge");
				tokens.add ("microsoft-edge");
			} else if (norm == "code" || norm == "visual-studio-code") {
				executable_tokens.add ("code");
				tokens.add ("com.microsoft.vscode");
			}
		}

		private void add_token_variants (string text)
		{
			// Split by whitespace and punctuation: "Google Chrome (Windows Syensqo)" -> google, chrome, windows, syensqo
			string clean = text.replace ("(", " ").replace (")", " ").replace ("[", " ").replace ("]", " ").replace ("-", " ").replace ("_", " ");
			string[] words = clean.split (" ");
			foreach (var w in words) {
				var norm = normalize (w);
				if (norm.length >= 3 && !is_common_stopword (norm)) {
					word_tokens.add (norm);
				}
			}
		}

		public static bool is_common_stopword (string word)
		{
			return word == "the" || word == "for" || word == "and" || word == "app" ||
			       word == "application" || word == "desktop" || word == "edition" ||
			       word == "version" || word == "pro" || word == "community" ||
			       word == "professional" || word == "release" || word == "tool" ||
			       word == "tools" || word == "viewer" || word == "editor" ||
			       word == "manager" || word == "client" || word == "web" ||
			       word == "open" || word == "new" || word == "home" ||
			       word == "page" || word == "tab" || word == "window" ||
			       word == "document" || word == "untitled" || word == "welcome" ||
			       word == "view" || word == "main" || word == "help";
		}

		public static bool contains_word (string text, string word)
		{
			if (word == "" || text == "" || word.length > text.length)
				return false;

			int start_pos = 0;
			while (start_pos <= text.length - word.length) {
				int idx = text.index_of (word, start_pos);
				if (idx < 0)
					return false;

				bool left_boundary = true;
				if (idx > 0) {
					int prev_idx = idx - 1;
					while (prev_idx > 0 && ((uint8) text[prev_idx] & 0xc0) == 0x80) {
						prev_idx--;
					}
					unichar left_c = text.get_char (prev_idx);
					if (left_c.isalnum ())
						left_boundary = false;
				}

				bool right_boundary = true;
				if (idx + word.length < text.length) {
					unichar right_c = text.get_char (idx + word.length);
					if (right_c.isalnum ())
						right_boundary = false;
				}

				if (left_boundary && right_boundary)
					return true;

				start_pos = idx + 1;
			}
			return false;
		}

		private static bool is_common_path_stopword (string word)
		{
			return word == "home" || word == "root" || word == "tmp" || word == "bin" ||
			       word == "usr" || word == "etc" || word == "var" || word == "opt" ||
			       word == "desktop" || word == "main" || word == "index" || word == "default" ||
			       word == "run" || word == "user" || word == "local" || word == "share";
		}

		private static bool is_generic_argument_stopword (string word)
		{
			if (is_common_path_stopword (word) || is_common_stopword (word))
				return true;
			if (word == "kvm" || word == "tcg" || word == "xen" || word == "hax" ||
			    word == "whpx" || word == "hvf" || word == "qemu" || word == "snapshot" ||
			    word == "qcow2" || word == "vmdk" || word == "vdi" || word == "raw" ||
			    word == "none" || word == "off" || word == "on" || word == "auto" ||
			    word == "true" || word == "false")
				return true;
			bool all_digits_or_unit = true;
			for (int i = 0; i < word.length; i++) {
				unichar c = word.get_char (word.index_of_nth_char (i));
				if (!c.isdigit () && c != 'm' && c != 'g' && c != 'k' && c != 'b') {
					all_digits_or_unit = false;
					break;
				}
			}
			if (all_digits_or_unit)
				return true;
			return false;
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
			// Check if the window directly matches this desktop entry's primary identity
			// (DesktopFileName, ApplicationId, or ResourceClass matching desktop basename or StartupWMClass)
			bool primary_identity_matched = false;
			var primary_values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass };
			foreach (var val in primary_values) {
				if (val != null && val != "") {
					var norm = normalize (val);
					if (norm != "" && primary_tokens.contains (norm)) {
						primary_identity_matched = true;
						break;
					}
				}
			}

			// If this launcher has specialized target arguments (e.g. Profile 14, specific VM/file, PWA app-id),
			// check if the window matches those arguments.
			bool specialized = (argument_tokens.size > 0);
			bool args_matched = false;

			// Guard 1: Argument matching can ONLY apply if the window's underlying application or binary
			// matches this launcher. Unrelated applications (e.g. Dolphin) must never match Chrome web apps or Steam shortcuts.
			if (specialized && !primary_identity_matched) {
				bool base_app_matches = false;
				var base_values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
				foreach (var val in base_values) {
					if (val != null && val != "") {
						var norm = normalize (val);
						if (tokens.contains (norm) || executable_tokens.contains (norm) || word_tokens.contains (norm)) {
							base_app_matches = true;
							break;
						}
					}
				}
				if (!base_app_matches && window.Executable != "" && executable_tokens.contains (normalize (window.Executable))) {
					base_app_matches = true;
				}

				if (!base_app_matches) {
					return 0;
				}
			}

			if (specialized && window.Cmdline != "") {
				var cmdline_down = window.Cmdline.down ();
				foreach (var arg in argument_tokens) {
					if (arg.length >= 3 && cmdline_down.contains (arg)) {
						args_matched = true;
						break;
					}
				}
			}

			// Check window identifiers for PWA hash / argument matches
			// (e.g. crx_mpkgflik... or chrome-mpkgflik... matching argument token mpkgflik...)
			if (specialized && !args_matched) {
				foreach (var arg in argument_tokens) {
					if (arg.length >= 5) {
						if ((window.ApplicationId != "" && window.ApplicationId.down ().contains (arg)) ||
						    (window.DesktopFileName != "" && window.DesktopFileName.down ().contains (arg)) ||
						    (window.ResourceClass != "" && window.ResourceClass.down ().contains (arg))) {
							args_matched = true;
							break;
						}
					}
				}
			}

			if (specialized && !args_matched && window.Caption != "") {
				var caption_down = window.Caption.down ();
				foreach (var arg in argument_tokens) {
					if (arg.length >= 3 && contains_word (caption_down, arg)) {
						args_matched = true;
						break;
					}
				}
			}

			// If this launcher requires specific arguments that were NOT found in the window,
			// it must NEVER hijack generic instances or different instances of the application
			// (unless the window specifically identified itself via exact desktop file id).
			bool exact_desktop_id_matched = false;
			var desktop_id_values = new string?[] { window.DesktopFileName, window.ApplicationId };
			foreach (var val in desktop_id_values) {
				if (val != null && val != "") {
					var norm = normalize (val);
					if (norm != "" && (norm == base_id || (base_id != "" && norm.has_prefix (base_id)))) {
						exact_desktop_id_matched = true;
						break;
					}
				}
			}

			if (specialized && !args_matched && !exact_desktop_id_matched) {
				return 0;
			}

			// Guard: Synthetic launchers (wayplank-app-*) are strictly bound to their unique sanitized instance name.
			// A synthetic launcher for VM-Alpha must NEVER hijack VM-Beta or other instances.
			if (base_id.has_prefix ("wayplank-app-")) {
				var synth_key = base_id.substring ("wayplank-app-".length);
				var win_app_name = window.Caption != "" ? window.Caption : (window.ResourceName != "" ? window.ResourceName : window.ResourceClass);
				var win_clean_name = ApplicationDiscovery.sanitize_name_for_app (win_app_name, normalize (window.ResourceClass));
				if (win_clean_name != synth_key) {
					return 0;
				}
			}

			var values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			var scores = new int[] { 100, 95, 85, 80 };
			var best = (args_matched && !primary_identity_matched) ? 110 : (primary_identity_matched ? 100 : 0);
			if (specialized && !args_matched && !exact_desktop_id_matched)
				best = 0;
			for (var i = 0; i < values.length; i++) {
				var value = values[i];
				if (value == null || value == "")
					continue;
				var normalized = normalize (value);
				if (normalized == "")
					continue;
				// Primary exact token match (exact .desktop basename, exact StartupWMClass, unwrapped binary)
				if (primary_tokens.contains (normalized))
					best = int.max (best, scores[i]);
				else if (tokens.contains (normalized))
					best = int.max (best, scores[i]);
				else if (tokens.contains (normalized.replace ("-", " ")) || tokens.contains (normalized.replace (" ", "-")) || tokens.contains (normalized.replace ("_", " ")))
					best = int.max (best, scores[i]);
				// Secondary word-variant match (strictly lower priority, exact matches always win)
				else if (word_tokens.contains (normalized))
					best = int.max (best, scores[i] - 25);

				// Check segments separated by '.', '-', '_' (e.g. org-scilab-modules-core-Scilab, scilab-bin)
				string[] seps = { ".", "-", "_" };
				foreach (var sep in seps) {
					var sep_idx = normalized.last_index_of (sep);
					if (sep_idx >= 0) {
						var suffix = normalized.substring (sep_idx + 1);
						if (suffix.length >= 3 && !is_common_stopword (suffix) && !is_common_path_stopword (suffix)) {
							if (tokens.contains (suffix))
								best = int.max (best, scores[i] - 15);
							else if (word_tokens.contains (suffix))
								best = int.max (best, scores[i] - 30);
						}
						var prefix = normalized.substring (0, sep_idx);
						if (prefix.length >= 3 && !is_common_stopword (prefix) && !is_common_path_stopword (prefix)) {
							if (tokens.contains (prefix))
								best = int.max (best, scores[i] - 20);
							else if (word_tokens.contains (prefix))
								best = int.max (best, scores[i] - 35);
						}
					}
				}

				// Prefix match for dashed binaries (e.g. qemu-system-x86_64 matching qemu)
				var first_dash = normalized.index_of_char ('-');
				if (first_dash > 0) {
					var first_part = normalized.substring (0, first_dash);
					if (primary_tokens.contains (first_part) || tokens.contains (first_part)) {
						best = int.max (best, scores[i] - 10);
					}
				}
			}

			// Check window.Cmdline against executables (strictly matching the invoked binary in argv[0] and non-switch tokens)
			if (window.Cmdline != "") {
				var cmdline = window.Cmdline.strip ();
				string first_arg = "";
				if (cmdline.has_prefix ("\"")) {
					var close_quote = cmdline.index_of_char ('"', 1);
					if (close_quote > 1)
						first_arg = cmdline.substring (1, close_quote - 1);
					else
						first_arg = cmdline.substring (1);
				} else {
					var first_space = cmdline.index_of_char (' ');
					if (first_space > 0)
						first_arg = cmdline.substring (0, first_space);
					else
						first_arg = cmdline;
				}
				if (first_arg != "") {
					var bin_name = File.new_for_path (first_arg).get_basename ().down ();
					if (bin_name != "") {
						if (executable_tokens.contains (bin_name)) {
							best = int.max (best, 85);
						} else {
							var first_dash = bin_name.index_of_char ('-');
							if (first_dash > 0) {
								var prefix = bin_name.substring (0, first_dash);
								if (executable_tokens.contains (prefix))
									best = int.max (best, 80);
							}
						}
					}
				}
				if (executable_tokens.size > 0 && best < 85) {
					var cmdline_down = cmdline.down ();
					string[] cmd_tokens = cmdline_down.split (" ");
					foreach (var token in cmd_tokens) {
						var tok = token.strip ().replace ("\"", "").replace ("'", "");
						if (tok == "" || tok.has_prefix ("-"))
							continue;
						var base_exe = File.new_for_path (tok).get_basename ();
						if (executable_tokens.contains (base_exe)) {
							best = int.max (best, 85);
							break;
						}
						if (base_exe.has_suffix ("-bin")) {
							var stripped = base_exe.substring (0, base_exe.length - 4);
							if (executable_tokens.contains (stripped)) {
								best = int.max (best, 85);
								break;
							}
						}
					}
				}
			}

			// Match window Caption (Title) against desktop Name or tokens with strict word-boundary matching
			if (window.Caption != "") {
				var caption_down = window.Caption.down ();
				if (app_name != "" && app_name.length >= 3 && !is_common_stopword (app_name) && contains_word (caption_down, app_name)) {
					if (window.Executable != "" && executable_tokens.contains (normalize (window.Executable)))
						best = int.max (best, 90);
					else if (executable_tokens.size == 0)
						best = int.max (best, 70);
					else
						best = int.max (best, 60);
				}
				foreach (var tok in primary_tokens) {
					if (tok.length >= 3 && !is_common_stopword (tok) && !is_common_path_stopword (tok) && contains_word (caption_down, tok)) {
						best = int.max (best, 70);
						break;
					}
				}
			}

			if (window.Executable != "") {
				var norm_exe = normalize (window.Executable);
				if (executable_tokens.contains (norm_exe)) {
					best = int.max (best, (argument_tokens.size == 0) ? 80 : 60);
				} else if (norm_exe.has_suffix ("-bin")) {
					var stripped = norm_exe.substring (0, norm_exe.length - 4);
					if (executable_tokens.contains (stripped))
						best = int.max (best, 75);
				} else if (norm_exe.length == 15) {
					foreach (var exe in executable_tokens) {
						if (exe.has_prefix (norm_exe)) {
							best = int.max (best, (argument_tokens.size == 0) ? 80 : 60);
							break;
						}
					}
				}
			}
			return best;
		}
	}
}
