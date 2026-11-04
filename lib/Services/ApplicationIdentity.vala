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
		Gee.HashSet<string> dedicated_binaries = new Gee.HashSet<string> ();
		Gee.HashSet<string> startup_wm_classes = new Gee.HashSet<string> ();
		Gee.ArrayList<string> argument_tokens = new Gee.ArrayList<string> ();
		string app_name = "";
		string alnum_app_name = "";
		string base_id = "";
		string pwa_id = "";
		string web_app_host = "";
		string web_app_alt_host = "";
		string web_app_brand = "";
		bool has_startup_wm_class = false;
		bool is_non_app_desktop = false;
		bool is_browser_url_bookmark = false;
		bool is_chromium_webapp = false;
		bool has_browser_executable = false;

		public File desktop_file { get; private set; }
		public string desktop_uri { get; private set; default = ""; }
		public string normalized_id { get; private set; default = ""; }
		public bool has_exec { get; private set; default = false; }
		
		public ApplicationIdentity (File desktop_file)
		{
			this.desktop_file = desktop_file;
			this.desktop_uri = desktop_file.get_uri ();
			base_id = normalize (desktop_file.get_basename ());
			this.normalized_id = base_id;
			add_token (base_id);
			primary_tokens.add (base_id);
			var path = desktop_file.get_path ();
			if (path == null)
				return;
			if (GLib.FileUtils.test (path, GLib.FileTest.IS_SYMLINK)) {
				string? real_target = Posix.realpath (path);
				if (real_target != null && real_target != "") {
					var real_base = GLib.Path.get_basename (real_target);
					if (real_base.down ().has_suffix (".desktop")) {
						var norm_real = normalize (real_base);
						if (norm_real != "") {
							add_token (norm_real);
							primary_tokens.add (norm_real);
						}
					}
				}
			}
			try {
				var key_file = new KeyFile ();
				key_file.load_from_file (path, KeyFileFlags.NONE);
				if (key_file.has_key (KeyFileDesktop.GROUP, "Type")) {
					var dtype = key_file.get_string (KeyFileDesktop.GROUP, "Type").strip ();
					if (dtype == "Link") {
						string link_target = "";
						if (key_file.has_key (KeyFileDesktop.GROUP, "URL"))
							link_target = key_file.get_string (KeyFileDesktop.GROUP, "URL").strip ();
						else if (key_file.has_key (KeyFileDesktop.GROUP, "URL[$e]"))
							link_target = key_file.get_string (KeyFileDesktop.GROUP, "URL[$e]").strip ();
						string resolved_desktop = "";
						if (link_target.has_prefix ("file://")) {
							try { resolved_desktop = GLib.Filename.from_uri (link_target); } catch { }
						} else if (link_target.has_prefix ("/")) {
							resolved_desktop = link_target;
						}
						if (resolved_desktop != "" && resolved_desktop.down ().has_suffix (".desktop") && GLib.FileUtils.test (resolved_desktop, GLib.FileTest.EXISTS)) {
							var norm_linked = normalize (GLib.Path.get_basename (resolved_desktop));
							if (norm_linked != "") {
								add_token (norm_linked);
								primary_tokens.add (norm_linked);
							}
							key_file = new KeyFile ();
							key_file.load_from_file (resolved_desktop, KeyFileFlags.NONE);
						} else {
							is_non_app_desktop = true;
						}
					} else if (dtype != "" && dtype != "Application") {
						is_non_app_desktop = true;
					}
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, "StartupWMClass")) {
					var swmc = key_file.get_string (KeyFileDesktop.GROUP, "StartupWMClass");
					add_token (swmc);
					add_token_variants (swmc);
					var norm_swmc = normalize (swmc);
					if (norm_swmc != "") {
						has_startup_wm_class = true;
						primary_tokens.add (norm_swmc);
						if (norm_swmc.has_prefix ("crx_")) {
							var crx_id = norm_swmc.substring (4);
							if (crx_id.length >= 3) {
								pwa_id = crx_id;
								is_chromium_webapp = true;
								add_token (crx_id);
								primary_tokens.add (crx_id);
								argument_tokens.add (crx_id);
							}
						} else {
							startup_wm_classes.add (norm_swmc);
						}
					}
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, "X-GNOME-WMClass")) {
					var gmc = key_file.get_string (KeyFileDesktop.GROUP, "X-GNOME-WMClass");
					add_token (gmc);
					add_token_variants (gmc);
					var norm_gmc = normalize (gmc);
					if (norm_gmc != "") {
						primary_tokens.add (norm_gmc);
						startup_wm_classes.add (norm_gmc);
					}
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME)) {
					var raw_name = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME).strip ();
					if (raw_name != "") {
						app_name = raw_name.down ();
						alnum_app_name = to_alnum_lower (raw_name);
						add_token (app_name);
						add_token_variants (raw_name);
					}
				}
				bool has_desktop_url_key = false;
				string desktop_url_val = "";
				if (key_file.has_key (KeyFileDesktop.GROUP, "URL"))
					desktop_url_val = key_file.get_string (KeyFileDesktop.GROUP, "URL").strip ().down ();
				else if (key_file.has_key (KeyFileDesktop.GROUP, "URL[$e]"))
					desktop_url_val = key_file.get_string (KeyFileDesktop.GROUP, "URL[$e]").strip ().down ();
				if (desktop_url_val.has_prefix ("http://") || desktop_url_val.has_prefix ("https://"))
					has_desktop_url_key = true;

				if (key_file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
					var command = key_file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
					if (command != "") {
						has_exec = true;
						parse_exec_command (command, has_desktop_url_key);
					} else if (has_desktop_url_key && !has_startup_wm_class) {
						is_browser_url_bookmark = true;
					}
				} else if (has_desktop_url_key && !has_startup_wm_class) {
					is_browser_url_bookmark = true;
				}
			} catch (Error e) {
				debug ("Unable to read desktop identity '%s': %s", desktop_file.get_path (), e.message);
			}
		}

		private void parse_exec_command (string command, bool has_desktop_url_key = false)
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
			bool has_isolated_browser_flag = false;
			if (raw_exe.has_suffix (".sh")) {
				string? script_target = null;
				if (GLib.FileUtils.test (raw_exe, GLib.FileTest.IS_REGULAR)) {
					script_target = raw_exe;
				} else {
					script_target = GLib.Environment.find_program_in_path (raw_exe);
				}

				if (script_target != null) {
					inspect_script_file (script_target, ref has_isolated_browser_flag);
				}
			}

			bool is_browser = is_browser_binary (exe_name);
			bool is_generic_runtime = is_generic_runtime_binary (exe_name);
			bool has_positional_url = false;

			for (int i = 1; i < unwrap_tokens.size; i++) {
				var part = unwrap_tokens.get (i).strip ().replace ("\"", "").replace ("'", "");
				if (part == "" || part.has_prefix ("%") || part.has_prefix ("@"))
					continue;

				var part_down = part.down ();
				if (part_down.has_prefix ("http://") || part_down.has_prefix ("https://")) {
					has_positional_url = true;
					continue;
				}

				if ((part_down == "--app" || part_down == "-app") && i + 1 < unwrap_tokens.size) {
					var app_url = unwrap_tokens.get (i + 1).strip ().replace ("\"", "").replace ("'", "").down ();
					if (app_url != "" && !app_url.has_prefix ("-")) {
						is_chromium_webapp = true;
						if (!app_url.contains ("://") && app_url.contains (".") && !app_url.has_prefix ("/"))
							app_url = "https://" + app_url;
						if (app_url.has_prefix ("http://") || app_url.has_prefix ("https://"))
							extract_web_app_host (app_url);
						i++;
						continue;
					}
				}

				if (part_down == "--class" || part_down == "-class" || part_down == "--profile" || part_down == "-profile" || part_down == "--user-data-dir") {
					has_isolated_browser_flag = true;
					if (i + 1 < unwrap_tokens.size) {
						var cls_val = unwrap_tokens.get (i + 1).strip ().replace ("\"", "").replace ("'", "").down ();
						if (cls_val != "" && !cls_val.has_prefix ("-")) {
							argument_tokens.add (cls_val);
							i++;
						}
					}
					continue;
				}

				if (part == "-P" || part == "--ProfileManager") {
					has_isolated_browser_flag = true;
					if (i + 1 < unwrap_tokens.size) {
						var prof_val = unwrap_tokens.get (i + 1).strip ().replace ("\"", "").replace ("'", "").down ();
						if (prof_val != "" && !prof_val.has_prefix ("-")) {
							argument_tokens.add (prof_val);
							i++;
						}
					}
					continue;
				}

				// Parameter option with value like --profile-directory="Profile 14", --app-id=..., or --app=...
				if (part.contains ("=")) {
					var eq = part.index_of_char ('=');
					var opt_key = part.substring (0, eq).down ();
					if (opt_key == "--class" || opt_key == "-class"
						|| opt_key.contains ("user-data-dir")
						|| (opt_key.contains ("profile") && !opt_key.contains ("profile-directory")))
						has_isolated_browser_flag = true;
					if (opt_key.contains ("profile") || opt_key.contains ("user-data-dir") || opt_key.contains ("class") || opt_key.contains ("app")) {
						var val = part.substring (eq + 1).strip ().replace ("\"", "").replace ("'", "").down ();
						if (val != "" && val.length >= 3) {
							if (opt_key.contains ("app-id") && pwa_id == "") {
								pwa_id = val;
								is_chromium_webapp = true;
								add_token (val);
								primary_tokens.add (val);
							} else if (opt_key == "--app" || opt_key == "-app") {
								is_chromium_webapp = true;
								var norm_url = (!val.contains ("://") && val.contains (".") && !val.has_prefix ("/")) ? ("https://" + val) : val;
								if (norm_url.has_prefix ("http://") || norm_url.has_prefix ("https://")) {
									extract_web_app_host (norm_url);
									continue;
								}
							}
							argument_tokens.add (val);
							if (val.has_prefix ("http://") || val.has_prefix ("https://")) {
								var host_part = parse_url_host (val);
								if (host_part != "") {
									argument_tokens.add (host_part);
									var host_dot = host_part.last_index_of_char ('.');
									if (host_dot > 0) {
										var sld = host_part.substring (0, host_dot);
										var first_dot = sld.last_index_of_char ('.');
										if (first_dot >= 0)
											sld = sld.substring (first_dot + 1);
										if (sld.length >= 3 && !is_common_stopword (sld) && !is_browser_vendor_stopword (sld))
											argument_tokens.add (sld);
									}
								}
							}
						}
					}
					continue;
				}

				if (is_generic_runtime) {
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

			// If this launcher is a specific PWA (--app-id or StartupWMClass=crx_) or standalone URL web-app (--app=URL),
			// purge shared browser flags (e.g. --profile-directory) from argument_tokens
			// so multiple web-apps or normal browser windows in the same profile never cross-match.
			// Conversely, a browser shortcut opening an http(s):// URL in a regular browser tab (even with
			// --profile-directory=...) without --app-id, --app, StartupWMClass, or --class is a URL bookmark
			// and must never hijack the main browser's window identity.
			if (pwa_id != "") {
				argument_tokens.clear ();
				argument_tokens.add (pwa_id);
			} else if (web_app_host != "") {
				argument_tokens.clear ();
				argument_tokens.add (web_app_host);
				if (web_app_alt_host != "")
					argument_tokens.add (web_app_alt_host);
			} else if ((is_browser || has_browser_executable)
				&& (has_desktop_url_key || has_positional_url)
				&& !has_startup_wm_class
				&& !has_isolated_browser_flag) {
				is_browser_url_bookmark = true;
				argument_tokens.clear ();
			}
		}

		private static string parse_url_host (string url)
		{
			var slash_idx = url.index_of ("://");
			if (slash_idx < 0)
				return "";
			var host_part = url.substring (slash_idx + 3);
			var end_slash = host_part.index_of_char ('/');
			if (end_slash >= 0)
				host_part = host_part.substring (0, end_slash);
			var end_query = host_part.index_of_char ('?');
			if (end_query >= 0)
				host_part = host_part.substring (0, end_query);
			var end_hash = host_part.index_of_char ('#');
			if (end_hash >= 0)
				host_part = host_part.substring (0, end_hash);
			var at_idx = host_part.last_index_of_char ('@');
			if (at_idx >= 0)
				host_part = host_part.substring (at_idx + 1);
			var port_idx = host_part.index_of_char (':');
			if (port_idx > 0)
				host_part = host_part.substring (0, port_idx);
			return host_part.strip ();
		}

		private static string to_alnum_lower (string text)
		{
			var sb = new StringBuilder ();
			var down = text.down ();
			int idx = 0;
			unichar c;
			while (down.get_next_char (ref idx, out c)) {
				if (c.isalnum ())
					sb.append_unichar (c);
			}
			return sb.str;
		}

		private static string extract_url_brand (string host)
		{
			string h = host.down ().strip ();
			string[] prefixes = { "www.", "m.", "open.", "play.", "app.", "listen.", "watch.", "tv.", "web." };
			foreach (unowned string p in prefixes) {
				if (h.has_prefix (p) && h.length > p.length + 3) {
					h = h.substring (p.length);
					break;
				}
			}
			string[] multi_tlds = {
				".co.uk", ".org.uk", ".gov.uk", ".ac.uk",
				".com.au", ".net.au", ".org.au",
				".co.jp", ".co.nz", ".co.za", ".co.kr", ".co.in", ".co.il",
				".com.br", ".com.mx", ".com.ar", ".com.es", ".com.tr"
			};
			bool stripped_tld = false;
			foreach (unowned string tld in multi_tlds) {
				if (h.has_suffix (tld) && h.length > tld.length) {
					h = h.substring (0, h.length - tld.length);
					stripped_tld = true;
					break;
				}
			}
			if (!stripped_tld) {
				var last_dot = h.last_index_of_char ('.');
				if (last_dot > 0)
					h = h.substring (0, last_dot);
			}
			var sub_dot = h.last_index_of_char ('.');
			if (sub_dot >= 0)
				h = h.substring (sub_dot + 1);
			if (h.length < 3 || is_common_stopword (h) || is_browser_vendor_stopword (h))
				return "";
			return h;
		}

		private void extract_web_app_host (string url)
		{
			var host_part = parse_url_host (url);
			if (host_part == "")
				return;
			web_app_host = host_part;
			if (host_part.has_prefix ("www.")) {
				var stripped_www = host_part.substring (4);
				if (stripped_www.contains (".") && stripped_www.length >= 4)
					web_app_alt_host = stripped_www;
			} else if (host_part.contains (".")) {
				web_app_alt_host = "www." + host_part;
			}
			web_app_brand = extract_url_brand (host_part);
		}

		private void inspect_script_file (string script_path, ref bool has_isolated_browser_flag)
		{
			try {
				string content;
				if (!GLib.FileUtils.get_contents (script_path, out content))
					return;

				// Limit scanning to small launcher wrapper scripts (< 4KB)
				if (content.length > 4096)
					return;

				// Fast check: accept any #! shebang or .sh wrapper without binary NUL bytes
				int check_len = int.min (content.length, 512);
				for (int bi = 0; bi < check_len; bi++) {
					if (content.data[bi] == 0)
						return;
				}
				if (!content.has_prefix ("#!") && !script_path.down ().has_suffix (".sh"))
					return;

				string[] lines = content.split ("\n");
				foreach (var raw_line in lines) {
					var line = raw_line.strip ();
					if (line == "" || line.has_prefix ("#"))
						continue;
					// Skip shell builtins, control flow, and non-launcher utilities
					if (line.has_prefix ("echo ") || line.has_prefix ("printf ") || line.has_prefix ("export ") ||
					    line.has_prefix ("sleep ") || line.has_prefix ("killall ") || line.has_prefix ("kill ") ||
					    line.has_prefix ("pidof ") || line.has_prefix ("pgrep ") || line.has_prefix ("pkill ") ||
					    line.has_prefix ("cd ") || line.has_prefix ("mkdir ") || line.has_prefix ("wait") ||
					    line.has_prefix ("exit") || line.has_prefix ("trap ") || line.has_prefix ("source ") ||
					    line.has_prefix ("set ") || line.has_prefix ("if ") || line.has_prefix ("elif ") ||
					    line == "else" || line == "fi" || line.has_prefix ("case ") || line == "esac" ||
					    line == ";;" || line == "}" || line == "{" || line.has_prefix (". "))
						continue;

					var script_tokens = unwrap_command_string (line);
					if (script_tokens.size > 0) {
						var inner_exe = File.new_for_path (script_tokens.get (0)).get_basename ();
						if (inner_exe != "" && inner_exe != "sh" && inner_exe != "bash") {
							add_executable_token (inner_exe);
						}
						for (int i = 1; i < script_tokens.size; i++) {
							var s_arg = script_tokens.get (i).strip ().replace ("\"", "").replace ("'", "");
							var s_down = s_arg.down ();
							if (s_arg == "-P" || s_arg == "--ProfileManager"
								|| s_down == "--class" || s_down == "-class"
								|| s_down == "--profile" || s_down == "-profile"
								|| s_down == "--user-data-dir") {
								has_isolated_browser_flag = true;
								if (i + 1 < script_tokens.size) {
									var next_val = script_tokens.get (i + 1).strip ().replace ("\"", "").replace ("'", "").down ();
									if (next_val != "" && !next_val.has_prefix ("-")) {
										argument_tokens.add (next_val);
										i++;
									}
								}
								continue;
							}
							if (s_arg.contains ("=")) {
								var eq = s_arg.index_of_char ('=');
								var opt_key = s_arg.substring (0, eq).down ();
								if (opt_key == "--class" || opt_key == "-class"
									|| opt_key.contains ("user-data-dir")
									|| (opt_key.contains ("profile") && !opt_key.contains ("profile-directory")))
									has_isolated_browser_flag = true;
								if (opt_key.contains ("profile") || opt_key.contains ("user-data-dir") || opt_key.contains ("class") || opt_key.contains ("app")) {
									var val = s_arg.substring (eq + 1).strip ().replace ("\"", "").replace ("'", "").down ();
									if (val != "" && val.length >= 3) {
										if (opt_key.contains ("app-id") && pwa_id == "") {
											pwa_id = val;
											is_chromium_webapp = true;
											add_token (val);
											primary_tokens.add (val);
										} else if ((opt_key == "--app" || opt_key == "-app") && (val.has_prefix ("http://") || val.has_prefix ("https://"))) {
											is_chromium_webapp = true;
											extract_web_app_host (val);
											continue;
										}
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

				// 2. Skip env / exec shell wrappers
				if (base_p == "env" || base_p == "exec") {
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

				if (base_p == "flatpak" || base_p == "snap") {
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

				if (base_p == "gtk-launch") {
					idx++;
					while (idx < parts.length && parts[idx].has_prefix ("-"))
						idx++;
					if (idx < parts.length) {
						var launched_id = normalize (parts[idx]);
						if (launched_id != "") {
							add_token (launched_id);
							primary_tokens.add (launched_id);
							register_dedicated_binary (launched_id);
						}
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

		private void register_dedicated_binary (string bin_token)
		{
			if (bin_token == "" || bin_token.length < 2 || is_generic_runtime_binary (bin_token))
				return;
			dedicated_binaries.add (bin_token);
			primary_tokens.add (bin_token);
		}

		private void add_executable_token (string raw_name)
		{
			var norm = normalize (raw_name);
			if (norm == "" || norm == "sh" || norm == "bash" || norm == "env")
				return;
			executable_tokens.add (norm);
			tokens.add (norm);
			register_dedicated_binary (norm);
			if (is_chromium_browser_binary (norm))
				is_chromium_webapp = true;
			if (is_browser_binary (norm))
				has_browser_executable = true;

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
					register_dedicated_binary (base_name);
				}
			} else {
				executable_tokens.add (norm + "-bin");
				tokens.add (norm + "-bin");
				if (!is_generic_runtime_binary (norm)) {
					dedicated_binaries.add (norm + "-bin");
					primary_tokens.add (norm + "-bin");
				}
			}

			// Auto-register AppImage aliases by stripping .AppImage, architectures, and semantic version numbers
			if (norm.has_suffix (".appimage")) {
				var appimage_base = norm.substring (0, norm.length - 9);
				if (appimage_base.length >= 3) {
					executable_tokens.add (appimage_base);
					tokens.add (appimage_base);
					register_dedicated_binary (appimage_base);
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
							register_dedicated_binary (clean_name);
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
						register_dedicated_binary (clean_name);
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
				dedicated_binaries.add ("code");
				dedicated_binaries.add ("com.microsoft.vscode");
				primary_tokens.add ("code");
				primary_tokens.add ("com.microsoft.vscode");
			}
		}

		private void add_token_variants (string text)
		{
			// Split by whitespace and punctuation: "Google Chrome (Work Profile)" -> google, chrome, work, profile
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
		
		private static bool is_chromium_browser_binary (string exe_name)
		{
			var n = normalize (exe_name);
			return n == "google-chrome" || n == "google-chrome-stable" || n == "google-chrome-beta" || n == "google-chrome-unstable" ||
			       n == "chrome" || n == "chromium" || n == "chromium-browser" ||
			       n == "brave" || n == "brave-browser" || n == "brave-browser-stable" ||
			       n == "microsoft-edge" || n == "microsoft-edge-stable" || n == "msedge" ||
			       n == "vivaldi" || n == "vivaldi-stable" || n == "opera";
		}

		private static bool is_browser_binary (string exe_name)
		{
			var n = normalize (exe_name);
			return is_chromium_browser_binary (n) ||
			       n == "firefox" || n == "firefox-esr" || n == "firefox-bin" || n == "librewolf" || n == "zen" || n == "zen-bin";
		}

		private static bool is_generic_runtime_binary (string exe_name)
		{
			var n = normalize (exe_name);
			if (is_browser_binary (n) || n.has_prefix ("qemu-") || n.has_suffix (".sh"))
				return true;
			return n == "sh" || n == "bash" || n == "dash" || n == "zsh" || n == "fish" || n == "env" ||
			       n == "java" || n == "javaw" || n == "python" || n == "python2" || n == "python3" ||
			       n == "perl" || n == "ruby" || n == "node" || n == "nodejs" || n == "deno" || n == "bun" ||
			       n == "php" || n == "lua" || n == "wish" || n == "tclsh" ||
			       n == "mono" || n == "dotnet" || n == "electron" ||
			       n == "wine" || n == "wine64" || n == "wine-preloader" || n == "wine64-preloader" ||
			       n == "dosbox" || n == "scummvm" || n == "retroarch" ||
			       n == "flatpak" || n == "snap" || n == "xdg-open" || n == "gio" ||
			       n == "kde-open" || n == "kde-open5" || n == "kioclient" || n == "kioclient5" ||
			       n == "exo-open" || n == "gtk-launch" || n == "rundll32" ||
			       n == "qemu" || n == "steam" || n == "lutris" || n == "heroic";
		}

		private static bool has_browser_tab_suffix (string lower_caption)
		{
			return lower_caption.has_suffix (" - google chrome") ||
			       lower_caption.has_suffix (" — google chrome") ||
			       lower_caption.contains (" - google chrome - ") ||
			       lower_caption.contains (" - google chrome (") ||
			       lower_caption.has_suffix (" - chromium") ||
			       lower_caption.has_suffix (" — chromium") ||
			       lower_caption.contains (" - chromium - ") ||
			       lower_caption.contains (" - chromium (") ||
			       lower_caption.has_suffix (" - brave") ||
			       lower_caption.has_suffix (" — brave") ||
			       lower_caption.contains (" - brave - ") ||
			       lower_caption.contains (" - brave (") ||
			       lower_caption.has_suffix (" - microsoft\u200b edge") ||
			       lower_caption.has_suffix (" - microsoft edge") ||
			       lower_caption.contains (" - microsoft edge - ") ||
			       lower_caption.contains (" - microsoft edge (") ||
			       lower_caption.has_suffix (" - vivaldi") ||
			       lower_caption.has_suffix (" - opera") ||
			       lower_caption.has_suffix (" - mozilla firefox") ||
			       lower_caption.has_suffix (" — mozilla firefox") ||
			       lower_caption.contains (" - mozilla firefox (") ||
			       lower_caption.contains (" — mozilla firefox (") ||
			       lower_caption.has_suffix (" - firefox") ||
			       lower_caption.has_suffix (" - mullvad browser") ||
			       lower_caption.has_suffix (" — mullvad browser") ||
			       lower_caption.has_suffix (" — librewolf") ||
			       lower_caption.has_prefix ("devtools - ") ||
			       lower_caption == "devtools" ||
			       lower_caption == "google chrome" ||
			       lower_caption == "chromium" ||
			       lower_caption == "brave" ||
			       lower_caption == "microsoft edge" ||
			       lower_caption == "vivaldi" ||
			       lower_caption == "opera" ||
			       lower_caption == "mozilla firefox" ||
			       lower_caption == "firefox" ||
			       lower_caption == "mullvad browser" ||
			       lower_caption == "librewolf" ||
			       lower_caption == "new tab" ||
			       lower_caption == "untitled";
		}

		public static bool has_explicit_webapp_window_id (WindowInfo window)
		{
			var win_ids = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			foreach (var wid in win_ids) {
				if (wid == null || wid == "")
					continue;
				var norm = normalize (wid);
				if (norm == "" || is_browser_binary (norm))
					continue;
				if (norm.has_prefix ("crx_") || norm.contains ("__") ||
				    norm.has_prefix ("chrome-") || norm.has_prefix ("chromium-") ||
				    norm.has_prefix ("brave-") || norm.has_prefix ("msedge-") ||
				    norm.has_prefix ("vivaldi-"))
					return true;
			}
			return false;
		}

		public static bool is_plain_browser_window (WindowInfo window)
		{
			if (has_explicit_webapp_window_id (window))
				return false;
			if (window.Caption != "" && has_browser_tab_suffix (window.Caption.down ().strip ()))
				return true;
			bool has_any_browser_id = false;
			var win_ids = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			foreach (var wid in win_ids) {
				if (wid == null || wid == "")
					continue;
				var norm = normalize (wid);
				if (norm == "")
					continue;
				if (!is_browser_binary (norm))
					return false;
				has_any_browser_id = true;
			}
			return has_any_browser_id && window.Caption.strip () == "";
		}

		private static bool is_browser_vendor_stopword (string word)
		{
			return word == "google" || word == "chrome" || word == "chromium" ||
			       word == "mozilla" || word == "firefox" || word == "brave" ||
			       word == "microsoft" || word == "edge" || word == "msedge" ||
			       word == "vivaldi" || word == "opera";
		}

		public bool is_web_app ()
		{
			return pwa_id != "" || web_app_host != "";
		}

		public bool is_browser_launcher ()
		{
			return has_browser_executable && !is_web_app ();
		}

		public bool is_specialized ()
		{
			return pwa_id != "" || web_app_host != "" || is_browser_url_bookmark || is_non_app_desktop || argument_tokens.size > 0;
		}

		public bool shares_application_with (ApplicationIdentity other)
		{
			if (this == other)
				return true;
			if (this.is_specialized () || other.is_specialized ())
				return false;
			foreach (var bin in dedicated_binaries) {
				if (other.dedicated_binaries.contains (bin))
					return true;
			}
			foreach (var swmc in startup_wm_classes) {
				if (other.startup_wm_classes.contains (swmc))
					return true;
			}
			if (has_browser_executable && other.has_browser_executable) {
				foreach (var exe in executable_tokens) {
					if (is_browser_binary (exe) && other.executable_tokens.contains (exe))
						return true;
				}
			}
			return false;
		}

		public void inherit_sibling_wm_classes (ApplicationIdentity sibling)
		{
			if (!shares_application_with (sibling))
				return;
			foreach (var swmc in sibling.startup_wm_classes) {
				tokens.add (swmc);
				primary_tokens.add (swmc);
			}
		}

		private static bool web_brand_matches_identity (string brand, ApplicationIdentity target)
		{
			if (brand == "" || brand.length < 3)
				return false;
			if (target.web_app_brand != "" && brand == target.web_app_brand)
				return true;
			if (target.alnum_app_name != "" && brand == target.alnum_app_name)
				return true;
			if (target.alnum_app_name.length >= 5 && brand.has_prefix (target.alnum_app_name))
				return true;
			if (target.app_name != "" && contains_word (target.app_name, brand))
				return true;
			return false;
		}

		public bool matches_web_app_identity (ApplicationIdentity other)
		{
			if (this == other)
				return true;
			if (!this.is_web_app () || !other.is_web_app ())
				return false;
			if (pwa_id != "" && pwa_id == other.pwa_id)
				return true;
			if (web_app_host != "" && other.web_app_host != "") {
				if (web_app_host == other.web_app_host ||
				    (web_app_alt_host != "" && (web_app_alt_host == other.web_app_host || web_app_alt_host == other.web_app_alt_host)) ||
				    (other.web_app_alt_host != "" && web_app_host == other.web_app_alt_host))
					return true;
			}

			bool compatible_browser = (is_chromium_webapp && other.is_chromium_webapp);
			if (!compatible_browser) {
				foreach (var exe in executable_tokens) {
					if (other.executable_tokens.contains (exe)) {
						compatible_browser = true;
						break;
					}
				}
			}
			if (!compatible_browser && executable_tokens.size > 0 && other.executable_tokens.size > 0)
				return false;

			if (alnum_app_name != "" && alnum_app_name.length >= 3 &&
			    !is_common_stopword (alnum_app_name) && !is_browser_vendor_stopword (alnum_app_name) &&
			    alnum_app_name == other.alnum_app_name)
				return true;

			if (web_brand_matches_identity (web_app_brand, other) || web_brand_matches_identity (other.web_app_brand, this))
				return true;

			return false;
		}

		public bool matches (WindowInfo window)
		{
			return match_score (window) > 0;
		}

		public int match_score (WindowInfo window)
		{
			if (is_non_app_desktop || is_browser_url_bookmark)
				return 0;

			// Strict PWA Isolation: Single-process browsers (Chrome/Chromium/Brave/Edge) share a single
			// master PID and /proc/<pid>/cmdline across all open browser and PWA windows.
			// Therefore, a launcher with an explicit pwa_id (--app-id or StartupWMClass=crx_) MUST match
			// strictly against the window's own compositor identifiers, never via shared Cmdline or plain browser tabs.
			if (pwa_id != "") {
				if (is_plain_browser_window (window))
					return 0;
				bool pwa_matched = false;
				var win_ids = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
				foreach (var wid in win_ids) {
					if (wid != null && wid != "" && wid.down ().contains (pwa_id)) {
						pwa_matched = true;
						break;
					}
				}
				if (pwa_matched)
					return 120;
				if (web_app_host == "")
					return 0;
			}

			// Strict Standalone Web-App URL Isolation (--app=http(s)://...):
			// Match against compositor window identifiers (Wayland chrome-<host>__* or XWayland instance),
			// or chromeless standalone web-app windows (never plain browser tabs or shared /proc/<pid>/cmdline).
			if (web_app_host != "") {
				if (is_plain_browser_window (window))
					return 0;

				var win_ids = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
				foreach (var wid in win_ids) {
					if (wid == null || wid == "")
						continue;
					var wid_down = wid.down ();
					if (wid_down.contains (web_app_host) || (web_app_alt_host != "" && wid_down.contains (web_app_alt_host)))
						return 120;
				}

				foreach (var wid in win_ids) {
					if (wid == null || wid == "")
						continue;
					var norm_wid = normalize (wid);
					if (norm_wid.has_prefix ("chrome-") && norm_wid.contains ("__"))
						return 0;
				}

				if (window.Caption != "") {
					var cap_down = window.Caption.down ().strip ();
					bool browser_matches = false;
					foreach (var wid in win_ids) {
						if (wid == null || wid == "")
							continue;
						var norm_wid = normalize (wid);
						if (executable_tokens.contains (norm_wid) ||
						    (is_chromium_webapp && (norm_wid.has_prefix ("crx_") || norm_wid.has_prefix ("chrome-")))) {
							browser_matches = true;
							break;
						}
					}
					if (!browser_matches && window.Executable != "" && executable_tokens.contains (normalize (window.Executable)))
						browser_matches = true;

					if (browser_matches) {
						if (app_name != "" && app_name.length >= 3 && !is_common_stopword (app_name) && !is_browser_vendor_stopword (app_name)) {
							if (contains_word (cap_down, app_name))
								return 118;
							if (app_name.contains ("+")) {
								var compact_plus = app_name.replace (" ", "");
								if (compact_plus.length >= 4 && cap_down.contains (compact_plus))
									return 118;
							}
						}
						if (web_app_brand != "" && web_app_brand.length >= 3) {
							if (contains_word (cap_down, web_app_brand))
								return 118;
							if (web_app_brand.length >= 8 && to_alnum_lower (cap_down).contains (web_app_brand))
								return 118;
						}
					}
				}
				return 0;
			}

			// Check if the window directly matches this desktop entry's primary identity
			// (DesktopFileName, ApplicationId, ResourceClass, or ResourceName matching desktop basename or StartupWMClass)
			bool primary_identity_matched = false;
			var primary_values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
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

			// Plain browser & browser profile launchers (e.g. google-chrome.desktop, Chrome.sh, chrome-private.sh, winchrome-syensqo.sh)
			// must NEVER match standalone PWA / --app=URL windows sharing the master browser PID.
			if (has_browser_executable && !is_web_app () && has_explicit_webapp_window_id (window))
				return 0;

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
						    (window.ResourceClass != "" && window.ResourceClass.down ().contains (arg)) ||
						    (window.ResourceName != "" && window.ResourceName.down ().contains (arg))) {
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
			var desktop_id_values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceName };
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

			// Guard: Instance-named synthetic launchers (wayplank-app-* without StartupWMClass, e.g. multi-VM)
			// are strictly bound to their unique sanitized instance name so VM-Alpha never hijacks VM-Beta.
			// Class-bound synthetic launchers (with StartupWMClass, e.g. CLI/AppImage apps whose titles change
			// dynamically as documents/notes open) require primary_identity_matched instead.
			if (base_id.has_prefix ("wayplank-app-")) {
				if (has_startup_wm_class) {
					if (!primary_identity_matched)
						return 0;
				} else {
					var synth_key = base_id.substring ("wayplank-app-".length);
					var win_app_name = window.Caption != "" ? window.Caption : (window.ResourceName != "" ? window.ResourceName : window.ResourceClass);
					var win_clean_name = ApplicationDiscovery.sanitize_name_for_app (win_app_name, normalize (window.ResourceClass));
					if (win_clean_name != synth_key) {
						return 0;
					}
				}
			}

			var values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			var scores = new int[] { 100, 95, 85, 80 };
			var best = (args_matched && primary_identity_matched) ? 120 : (args_matched ? 116 : (primary_identity_matched ? 100 : 0));
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
