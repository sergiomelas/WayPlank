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
		Gee.ArrayList<string> required_browser_args = new Gee.ArrayList<string> ();
		Gee.ArrayList<string> required_mod_tokens = new Gee.ArrayList<string> ();
		static Gee.HashMap<int, string>? pid_cwd_cache;
		static Gee.HashMap<string, string>? window_browser_profiles;
		static Gee.HashMap<string, string>? window_locked_launcher_uris;
		static Gee.HashMap<string, string>? window_locked_display_names;
		static Gee.HashMap<string, int64?>? window_open_time_us;
		static Gee.HashMap<int, string>? newest_window_for_pid;
		static Gee.HashMap<int, string>? pid_to_dbus_sender;
		static Gee.HashMap<string, int>? dbus_sender_to_pid;
		static Gee.HashMap<string, int>? unresolved_browser_windows;
		static Gee.ArrayList<string>? open_browser_window_order;
		static Gee.HashMap<string, int>? open_browser_window_pids;
		static Gee.HashSet<int>? ever_seen_browser_pids;
		static Gee.HashSet<int>? multi_window_browser_pids;
		static Gee.HashMap<int, string>? terminal_cmdline_owner_wid;
		static Gee.HashSet<int>? terminal_cmdline_consumed_pids;
		static Gee.HashMap<int, string>? terminal_child_pid_owner_wid;
		static Gee.HashMap<string, int>? open_terminal_window_pids;
		static Gee.HashMap<string, string>? profile_dir_to_name;
		static Gee.HashMap<string, string>? profile_label_to_dir;
		static string last_used_profile_dir = "";
		static string first_known_profile_dir = "";
		static int64 local_state_last_load_us = 0;
		static uint dbusmenu_signal_sub_id = 0;
		string app_name = "";
		string alnum_app_name = "";
		string base_id = "";
		string pwa_id = "";
		string web_app_host = "";
		string web_app_alt_host = "";
		string web_app_brand = "";
		string raw_path_dir = "";
		string wine_lnk_token = "";
		string wine_path_token = "";
		string wine_prefix_token = "";
		bool has_startup_wm_class = false;
		bool is_non_app_desktop = false;
		bool is_browser_url_bookmark = false;
		bool is_chromium_webapp = false;
		bool has_browser_executable = false;
		bool has_wine_executable = false;
		bool is_multi_component_suite = false;
		bool requires_incognito = false;

		public File desktop_file { get; private set; }
		public string desktop_uri { get; private set; default = ""; }
		public string normalized_id { get; private set; default = ""; }
		public bool has_exec { get; private set; default = false; }
		public bool is_terminal_app { get; private set; default = false; }
		public bool is_nodisplay_desktop { get; private set; default = false; }
		public string detected_browser_profile { get; private set; default = ""; }
		public string pwa_app_id { get { return pwa_id; } }

		public Gee.HashSet<string> get_primary_tokens ()
		{
			return primary_tokens;
		}
		
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
				if (key_file.has_key (KeyFileDesktop.GROUP, "NoDisplay")) {
					try { is_nodisplay_desktop = key_file.get_boolean (KeyFileDesktop.GROUP, "NoDisplay"); } catch { }
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, "Terminal")) {
					try { is_terminal_app = key_file.get_boolean (KeyFileDesktop.GROUP, "Terminal"); } catch { }
				}
				if (key_file.has_key (KeyFileDesktop.GROUP, "Path")) {
					raw_path_dir = expand_shell_path (key_file.get_string (KeyFileDesktop.GROUP, "Path").strip ());
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
				if (has_wine_executable && raw_path_dir != "") {
					var clean_path = raw_path_dir.replace ("\\", "/");
					while (clean_path.length > 1 && clean_path.has_suffix ("/"))
						clean_path = clean_path.substring (0, clean_path.length - 1);
					var path_leaf = File.new_for_path (clean_path).get_basename ().down ();
					if (path_leaf.length >= 3 && !is_generic_argument_stopword (path_leaf) && !is_wine_path_stopword (path_leaf)) {
						if (wine_path_token == "")
							wine_path_token = path_leaf;
						if (!argument_tokens.contains (path_leaf))
							argument_tokens.add (path_leaf);
					}
				}
			} catch (Error e) {
				debug ("Unable to read desktop identity '%s': %s", desktop_file.get_path (), e.message);
			}
		}

		private static string expand_shell_path (string raw, Gee.HashMap<string, string>? vars = null)
		{
			string s = raw.strip ();
			if (vars != null && vars.size > 0 && s.contains ("$")) {
				var sorted_keys = new Gee.ArrayList<string> ();
				sorted_keys.add_all (vars.keys);
				sorted_keys.sort ((a, b) => {
					if (a.length != b.length)
						return b.length - a.length;
					return strcmp (a, b);
				});
				foreach (var k in sorted_keys) {
					var val = vars.get (k) ?? "";
					s = s.replace ("${" + k + "}", val);
					s = s.replace ("$" + k, val);
				}
			}
			string home = GLib.Environment.get_home_dir ();
			string user = GLib.Environment.get_user_name ();
			string cfg = GLib.Environment.get_user_config_dir ();
			string data = GLib.Environment.get_user_data_dir ();
			if (cfg != "") {
				if (home != "")
					s = s.replace ("${XDG_CONFIG_HOME:-$HOME/.config}", cfg).replace ("${XDG_CONFIG_HOME:-${HOME}/.config}", cfg);
				s = s.replace ("${XDG_CONFIG_HOME}", cfg).replace ("$XDG_CONFIG_HOME", cfg);
			}
			if (data != "") {
				if (home != "")
					s = s.replace ("${XDG_DATA_HOME:-$HOME/.local/share}", data).replace ("${XDG_DATA_HOME:-${HOME}/.local/share}", data);
				s = s.replace ("${XDG_DATA_HOME}", data).replace ("$XDG_DATA_HOME", data);
			}
			if (home != "") {
				s = s.replace ("${HOME}", home).replace ("$HOME", home);
				if (s == "~")
					s = home;
				else if (s.has_prefix ("~/"))
					s = home + s.substring (1);
			}
			if (user != "")
				s = s.replace ("${USER}", user).replace ("$USER", user);
			return s;
		}

		private static bool is_incognito_switch (string flag_down)
		{
			return flag_down == "--incognito" || flag_down == "-incognito" ||
			       flag_down == "--inprivate" || flag_down == "-inprivate" ||
			       flag_down == "--private-window" || flag_down == "-private-window" ||
			       flag_down == "--private" || flag_down == "--tor" || flag_down == "--guest";
		}

		private void add_required_browser_arg (string kind, string raw_val, Gee.HashMap<string, string>? vars = null)
		{
			string clean = expand_shell_path (raw_val, vars).strip ().replace ("\"", "").replace ("'", "");
			if (clean == "" || clean == "$@" || clean == "$*" || clean == "$1")
				return;
			if (kind == "user-data-dir" || kind == "profile-arg") {
				while (clean.length > 1 && clean.has_suffix ("/"))
					clean = clean.substring (0, clean.length - 1);
			}
			if ((kind == "profile-dir" || kind == "user-data-dir" || kind == "profile-arg") && detected_browser_profile == "")
				detected_browser_profile = clean;
			string spec = kind + "=" + clean.down ();
			if (!required_browser_args.contains (spec))
				required_browser_args.add (spec);
		}

		private static bool is_wine_path_stopword (string word)
		{
			return word == "drive_c" || word == "dosdevices" || word == "program files" ||
			       word == "program files (x86)" || word == "programmi" || word == "windows" ||
			       word == "system32" || word == "syswow64" || word == "users" ||
			       word == "public" || word == "start menu" || word == "programs" ||
			       word == "wine" || word == ".wine" || word == "c:" || word == "z:";
		}

		private static bool is_wine_helper_exe (string exe_down)
		{
			return exe_down == "start.exe" || exe_down == "explorer.exe" || exe_down == "rundll32.exe" ||
			       exe_down == "cmd.exe" || exe_down == "winebrowser.exe" || exe_down == "winedbg.exe" ||
			       exe_down == "winecfg.exe" || exe_down == "msiexec.exe" || exe_down == "regedit.exe" ||
			       exe_down == "services.exe" || exe_down == "plugplay.exe" || exe_down == "winedevice.exe" ||
			       exe_down == "start" || exe_down == "explorer" || exe_down == "rundll32" ||
			       exe_down == "cmd" || exe_down == "winebrowser";
		}

		private void parse_exec_command (string command, bool has_desktop_url_key = false)
		{
			var unwrap_tokens = unwrap_command_string (command);
			if (unwrap_tokens.size == 0)
				return;

			var raw_exe = unwrap_tokens.get (0);
			var exe_name = File.new_for_path (raw_exe).get_basename ();
			var norm_exe = normalize (exe_name);

			if (norm_exe == "exo-open" && command.down ().contains ("terminalemulator")) {
				add_executable_token ("xfce4-terminal");
				return;
			}

			bool direct_term_hosted = false;
			if (exe_name != "" && is_terminal_emulator_binary (exe_name)) {
				string[] unwrap_arr = unwrap_tokens.to_array ();
				var term_hosted = new Gee.HashSet<string> ();
				for (int ti = 1; ti < unwrap_arr.length; ti++) {
					var t_tok = unwrap_arr[ti].strip ();
					var t_down = t_tok.down ();
					if ((t_down == "-class" || t_down == "--class") && ti + 1 < unwrap_arr.length) {
						var wm_cls = normalize (unwrap_arr[ti + 1].strip ().replace ("\"", "").replace ("'", ""));
						if (wm_cls != "") {
							has_startup_wm_class = true;
							startup_wm_classes.add (wm_cls);
							primary_tokens.add (wm_cls);
							tokens.add (wm_cls);
						}
						ti++;
						continue;
					}
					if (t_down.has_prefix ("--class=")) {
						var wm_cls = normalize (t_tok.substring ("--class=".length).strip ().replace ("\"", "").replace ("'", ""));
						if (wm_cls != "") {
							has_startup_wm_class = true;
							startup_wm_classes.add (wm_cls);
							primary_tokens.add (wm_cls);
							tokens.add (wm_cls);
						}
						continue;
					}
					if (t_tok == "-e" || t_tok == "--command" || t_tok == "-x" || t_tok == "--") {
						if (ti + 1 < unwrap_arr.length)
							collect_unwrapped_cmd_tokens (unwrap_arr, ti + 1, term_hosted);
						break;
					}
					if (t_tok.has_prefix ("--command=")) {
						var sub_argv = parse_cmdline_argv (t_tok.substring ("--command=".length));
						collect_unwrapped_cmd_tokens (sub_argv, 0, term_hosted);
						break;
					}
				}
				if (term_hosted.size > 0) {
					direct_term_hosted = true;
					is_terminal_app = true;
					foreach (var htok in term_hosted)
						add_executable_token (htok);
				}
			}

			if (exe_name != "" && !direct_term_hosted) {
				add_executable_token (exe_name);
			}

			if (norm_exe == "wine" || norm_exe == "wine64" || norm_exe == "wine-preloader" ||
			    norm_exe == "wine64-preloader" || norm_exe == "umu-run" || norm_exe == "proton")
				has_wine_executable = true;
			if (norm_exe == "libreoffice" || norm_exe == "soffice" || norm_exe == "soffice.bin" || norm_exe == "loffice")
				is_multi_component_suite = true;

			// Inspect wrapper scripts (< 16KB with #! shebang or .sh suffix, e.g. chrome-private.sh, winchrome-syensqo.sh, updatesys, uxterm)
			bool has_isolated_browser_flag = false;
			bool has_positional_url = false;
			if (!is_browser_binary (exe_name) &&
			    (raw_exe.down ().has_suffix (".sh") || !is_generic_runtime_binary (exe_name)) &&
			    (!is_terminal_emulator_binary (exe_name) || norm_exe == "uxterm")) {
				string? script_target = null;
				if (GLib.FileUtils.test (raw_exe, GLib.FileTest.IS_REGULAR)) {
					script_target = raw_exe;
				} else if (exe_name != "") {
					script_target = GLib.Environment.find_program_in_path (raw_exe);
				}
				if (script_target != null) {
					inspect_script_file (script_target, ref has_isolated_browser_flag, ref has_positional_url);
				}
			}

			bool is_browser = is_browser_binary (exe_name) || has_browser_executable;
			bool is_generic_runtime = is_generic_runtime_binary (exe_name) || has_wine_executable;

			for (int i = 1; i < unwrap_tokens.size; i++) {
				var part = unwrap_tokens.get (i).strip ().replace ("\"", "").replace ("'", "");
				if (part == "" || part.has_prefix ("%") || part.has_prefix ("@"))
					continue;

				var part_down = part.down ();
				if (part_down.has_prefix ("http://") || part_down.has_prefix ("https://")) {
					has_positional_url = true;
					continue;
				}

				if (is_multi_component_suite && (part_down == "--writer" || part_down == "--calc" ||
				    part_down == "--impress" || part_down == "--draw" || part_down == "--math" || part_down == "--base")) {
					var comp_wm = "libreoffice-" + part_down.substring (2);
					has_startup_wm_class = true;
					startup_wm_classes.add (comp_wm);
					primary_tokens.add (comp_wm);
					tokens.add (comp_wm);
					continue;
				}

				if ((part_down == "+set" || part_down == "-set") && i + 2 < unwrap_tokens.size) {
					var cvar = unwrap_tokens.get (i + 1).strip ().down ();
					var cval = unwrap_tokens.get (i + 2).strip ().replace ("\"", "").replace ("'", "").down ();
					if ((cvar == "game" || cvar == "fs_game") && cval != "" && !is_generic_argument_stopword (cval)) {
						if (!required_mod_tokens.contains (cval))
							required_mod_tokens.add (cval);
						if (!argument_tokens.contains (cval))
							argument_tokens.add (cval);
						i += 2;
						continue;
					}
				}

				if (is_browser && is_incognito_switch (part_down)) {
					requires_incognito = true;
					has_isolated_browser_flag = true;
					continue;
				}

				if ((part_down == "--app" || part_down == "-app") && i + 1 < unwrap_tokens.size) {
					var app_url = unwrap_tokens.get (i + 1).strip ().replace ("\"", "").replace ("'", "").down ();
					if (app_url != "" && !app_url.has_prefix ("-")) {
						is_chromium_webapp = true;
						if (app_url.has_prefix ("chrome-extension://") || app_url.has_prefix ("extension://") || app_url.has_prefix ("moz-extension://")) {
							var ext_id = parse_url_host (app_url);
							if (ext_id != "" && pwa_id == "") {
								pwa_id = ext_id;
								add_token (ext_id);
								primary_tokens.add (ext_id);
							}
						} else {
							if (!app_url.contains ("://") && app_url.contains (".") && !app_url.has_prefix ("/"))
								app_url = "https://" + app_url;
							if (app_url.has_prefix ("http://") || app_url.has_prefix ("https://"))
								extract_web_app_host (app_url);
						}
						i++;
						continue;
					}
				}

				if (part_down == "--class" || part_down == "-class" || part_down == "--profile" || part_down == "-profile" || part_down == "--user-data-dir" || part_down == "--profile-directory" || part_down == "--user-agent") {
					if (part_down != "--profile-directory")
						has_isolated_browser_flag = true;
					if (i + 1 < unwrap_tokens.size) {
						var raw_next = unwrap_tokens.get (i + 1).strip ().replace ("\"", "").replace ("'", "");
						if (raw_next != "" && !raw_next.has_prefix ("-")) {
							if (is_browser) {
								string kind = part_down.contains ("class") ? "class"
									: (part_down.contains ("user-data-dir") ? "user-data-dir"
									: (part_down.contains ("profile-directory") ? "profile-dir"
									: (part_down.contains ("user-agent") ? "user-agent" : "profile-arg")));
								add_required_browser_arg (kind, raw_next);
							} else {
								argument_tokens.add (expand_shell_path (raw_next).down ());
							}
							i++;
						}
					}
					continue;
				}

				if (part == "-P" || part == "--ProfileManager") {
					has_isolated_browser_flag = true;
					if (i + 1 < unwrap_tokens.size) {
						var raw_prof = unwrap_tokens.get (i + 1).strip ().replace ("\"", "").replace ("'", "");
						if (raw_prof != "" && !raw_prof.has_prefix ("-")) {
							if (is_browser)
								add_required_browser_arg ("profile-arg", raw_prof);
							else
								argument_tokens.add (expand_shell_path (raw_prof).down ());
							i++;
						}
					}
					continue;
				}

				// Parameter option with value like --profile-directory="Profile 14", --app-id=..., or --app=...
				if (part.contains ("=")) {
					var eq = part.index_of_char ('=');
					var opt_key = part.substring (0, eq).down ();
					var raw_val = part.substring (eq + 1).strip ().replace ("\"", "").replace ("'", "");
					if (opt_key == "--class" || opt_key == "-class"
						|| opt_key.contains ("user-data-dir")
						|| opt_key == "--user-agent"
						|| (opt_key.contains ("profile") && !opt_key.contains ("profile-directory")))
						has_isolated_browser_flag = true;
					if (is_browser && (opt_key.contains ("profile") || opt_key.contains ("user-data-dir") || opt_key == "--class" || opt_key == "-class" || opt_key == "--user-agent")) {
						string kind = opt_key.contains ("class") ? "class"
							: (opt_key.contains ("user-data-dir") ? "user-data-dir"
							: (opt_key.contains ("profile-directory") ? "profile-dir"
							: (opt_key == "--user-agent" ? "user-agent" : "profile-arg")));
						add_required_browser_arg (kind, raw_val);
						continue;
					}
					if (opt_key.contains ("profile") || opt_key.contains ("user-data-dir")
						|| opt_key == "--class" || opt_key == "-class"
						|| opt_key == "--name" || opt_key == "-name"
						|| opt_key == "--app" || opt_key == "-app"
						|| opt_key == "--app-id" || opt_key == "-app-id") {
						var val = expand_shell_path (raw_val).down ();
						if (val != "" && val.length >= 3) {
							if (opt_key.contains ("app-id") && pwa_id == "") {
								pwa_id = val;
								is_chromium_webapp = true;
								add_token (val);
								primary_tokens.add (val);
							} else if (opt_key == "--app" || opt_key == "-app") {
								is_chromium_webapp = true;
								if (val.has_prefix ("chrome-extension://") || val.has_prefix ("extension://") || val.has_prefix ("moz-extension://")) {
									var ext_id = parse_url_host (val);
									if (ext_id != "" && pwa_id == "") {
										pwa_id = ext_id;
										add_token (ext_id);
										primary_tokens.add (ext_id);
										continue;
									}
								}
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

				if (is_generic_runtime && !is_browser) {
					var slash_part = part.replace ("\\", "/");
					while (slash_part.contains ("//"))
						slash_part = slash_part.replace ("//", "/");
					var target_name = File.new_for_path (slash_part).get_basename ().down ();
					if (has_wine_executable && slash_part.contains ("/")) {
						string[] segs = slash_part.split ("/");
						for (int si = 0; si < segs.length - 1; si++) {
							var seg = segs[si].strip ().down ();
							if (seg.length >= 3 && !seg.has_suffix (":") && !is_generic_argument_stopword (seg) && !is_wine_path_stopword (seg)) {
								if (wine_path_token == "")
									wine_path_token = seg;
								if (!argument_tokens.contains (seg))
									argument_tokens.add (seg);
							}
						}
					}
					if (target_name != "" && target_name != "." && !target_name.has_prefix ("-") && !target_name.has_prefix ("@") && !is_generic_argument_stopword (target_name)) {
						if (has_wine_executable && is_wine_helper_exe (target_name))
							continue;
						var dot = target_name.last_index_of_char ('.');
						var sub_name = (dot > 0) ? target_name.substring (0, dot) : "";
						if (target_name.has_suffix (".lnk")) {
							if (sub_name.length >= 3 && !is_generic_argument_stopword (sub_name)) {
								wine_lnk_token = sub_name;
								if (!argument_tokens.contains (sub_name))
									argument_tokens.add (sub_name);
							}
							if (!argument_tokens.contains (target_name))
								argument_tokens.add (target_name);
						} else {
							if (!argument_tokens.contains (target_name))
								argument_tokens.add (target_name);
							if (sub_name.length >= 3 && !is_generic_argument_stopword (sub_name) && !argument_tokens.contains (sub_name))
								argument_tokens.add (sub_name);
						}
					}
				}
			}

			// Fallback profile extraction from Chromium PWA desktop basename (e.g. chrome-<pwa_id>-Profile_5.desktop)
			if (pwa_id != "" && detected_browser_profile == "" && base_id != "") {
				var pwa_marker = pwa_id + "-";
				var marker_idx = base_id.index_of (pwa_marker);
				if (marker_idx >= 0 && marker_idx + pwa_marker.length < base_id.length) {
					detected_browser_profile = base_id.substring (marker_idx + pwa_marker.length);
				}
			}

			// If this launcher is a specific PWA (--app-id or StartupWMClass=crx_) or standalone URL web-app (--app=URL),
			// purge shared browser flags (e.g. --profile-directory) from argument_tokens / required_browser_args
			// so multiple web-apps or normal browser windows in the same profile never cross-match via Cmdline.
			// Conversely, a browser shortcut opening an http(s):// URL in a regular browser tab (even with
			// --profile-directory=...) without --app-id, --app, StartupWMClass, or isolated wrapper flags is a URL bookmark
			// and must never hijack the main browser's window identity.
			if (pwa_id != "") {
				argument_tokens.clear ();
				required_browser_args.clear ();
				requires_incognito = false;
				argument_tokens.add (pwa_id);
			} else if (web_app_host != "") {
				argument_tokens.clear ();
				required_browser_args.clear ();
				requires_incognito = false;
				argument_tokens.add (web_app_host);
				if (web_app_alt_host != "")
					argument_tokens.add (web_app_alt_host);
			} else if ((is_browser || has_browser_executable)
				&& (has_desktop_url_key || has_positional_url)
				&& !has_startup_wm_class
				&& !has_isolated_browser_flag) {
				is_browser_url_bookmark = true;
				argument_tokens.clear ();
				required_browser_args.clear ();
				requires_incognito = false;
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

		private void inspect_script_file (string script_path, ref bool has_isolated_browser_flag, ref bool has_positional_url)
		{
			try {
				// Fast stat check: never read ELF binaries or files > 16KB into memory
				Posix.Stat st;
				if (Posix.stat (script_path, out st) != 0 || st.st_size <= 2 || st.st_size > 16384)
					return;

				string content;
				if (!GLib.FileUtils.get_contents (script_path, out content))
					return;

				// Limit scanning to launcher wrapper scripts (< 16KB, e.g. devecostudio.sh / idea.sh / /usr/games/quake2)
				if (content.length > 16384)
					return;

				// Fast check: accept any #! shebang or .sh wrapper without binary NUL bytes
				int check_len = int.min (content.length, 512);
				for (int bi = 0; bi < check_len; bi++) {
					if (content.data[bi] == 0)
						return;
				}
				if (!content.has_prefix ("#!") && !script_path.down ().has_suffix (".sh"))
					return;

				var script_vars = new Gee.HashMap<string, string> ();
				string[] raw_lines = content.split ("\n");
				var lines = new Gee.ArrayList<string> ();
				string pending_line = "";
				foreach (var rl in raw_lines) {
					var trimmed = rl.strip ();
					if (trimmed == "" || trimmed.has_prefix ("#")) {
						if (pending_line != "") {
							lines.add (pending_line);
							pending_line = "";
						}
						continue;
					}
					if (trimmed.has_suffix ("\\") && !trimmed.has_suffix ("\\\\")) {
						var piece = trimmed.substring (0, trimmed.length - 1).strip ();
						pending_line = (pending_line == "") ? piece : (pending_line + " " + piece);
					} else {
						var full_line = (pending_line == "") ? trimmed : (pending_line + " " + trimmed);
						lines.add (full_line);
						pending_line = "";
					}
				}
				if (pending_line != "")
					lines.add (pending_line);

				foreach (var raw_line in lines) {
					var line = raw_line.strip ();
					if (line == "" || line.has_prefix ("#") || line.contains ("()"))
						continue;

					// Capture simple shell variable assignments (e.g. DIR="$HOME/.config/chrome-work" or export UA="...")
					var var_line = line.has_prefix ("export ") ? line.substring (7).strip () : line;
					int eq_pos = var_line.index_of_char ('=');
					if (eq_pos > 0 && !var_line.has_prefix ("-")) {
						string lhs = var_line.substring (0, eq_pos);
						bool valid_ident = true;
						for (int ci = 0; ci < lhs.length; ci++) {
							char ch = lhs[ci];
							if (!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_' || (ci > 0 && ch >= '0' && ch <= '9'))) {
								valid_ident = false;
								break;
							}
						}
						if (valid_ident && !lhs.contains (" ")) {
							string rhs = var_line.substring (eq_pos + 1).strip ();
							if ((rhs.has_prefix ("\"") && rhs.has_suffix ("\"") && rhs.length >= 2) ||
							    (rhs.has_prefix ("'") && rhs.has_suffix ("'") && rhs.length >= 2)) {
								rhs = rhs.substring (1, rhs.length - 2);
							}
							if (lhs == "WINEPREFIX" && rhs != "") {
								var exp_wp = expand_shell_path (rhs, script_vars).replace ("\\", "/");
								while (exp_wp.length > 1 && exp_wp.has_suffix ("/"))
									exp_wp = exp_wp.substring (0, exp_wp.length - 1);
								var wp_leaf = File.new_for_path (exp_wp).get_basename ().down ();
								if (wp_leaf != "" && wp_leaf != ".wine" && wp_leaf.length >= 3 && !is_generic_argument_stopword (wp_leaf)) {
									has_wine_executable = true;
									if (wine_prefix_token == "")
										wine_prefix_token = wp_leaf;
									if (!argument_tokens.contains (wp_leaf))
										argument_tokens.add (wp_leaf);
								}
							}
							if (!rhs.contains (" ")) {
								script_vars.set (lhs, expand_shell_path (rhs, script_vars));
								continue;
							} else if (var_line.substring (eq_pos + 1).strip ().has_prefix ("\"") || var_line.substring (eq_pos + 1).strip ().has_prefix ("'")) {
								script_vars.set (lhs, expand_shell_path (rhs, script_vars));
								continue;
							}
						}
					}

					// Skip shell builtins, control flow, and non-launcher utilities
					if (line.has_prefix ("echo ") || line.has_prefix ("printf ") || line.has_prefix ("export ") ||
					    line.has_prefix ("sleep ") || line.has_prefix ("killall ") || line.has_prefix ("kill ") ||
					    line.has_prefix ("pidof ") || line.has_prefix ("pgrep ") || line.has_prefix ("pkill ") ||
					    line.has_prefix ("cd ") || line.has_prefix ("mkdir ") || line.has_prefix ("wait") ||
					    line.has_prefix ("exit") || line.has_prefix ("trap ") || line.has_prefix ("source ") ||
					    line.has_prefix ("set ") || line.has_prefix ("unset ") || line.has_prefix ("local ") ||
					    line.has_prefix ("readonly ") || line.has_prefix ("declare ") || line.has_prefix ("typeset ") ||
					    line.has_prefix ("return") || line.has_prefix ("shift") || line.has_prefix ("break") ||
					    line.has_prefix ("continue") || line.has_prefix ("if ") || line.has_prefix ("elif ") ||
					    line.has_prefix ("then") || line == "else" || line == "fi" ||
					    line.has_prefix ("for ") || line.has_prefix ("while ") || line.has_prefix ("until ") ||
					    line.has_prefix ("do") || line == "done" || line.has_prefix ("case ") || line == "esac" ||
					    line.has_prefix ("function ") || line.has_prefix ("test ") || line.has_prefix ("[ ") ||
					    line.has_prefix ("[[ ") || line == ";;" || line == "}" || line == "{" || line.has_prefix (". "))
						continue;

					bool line_has_exec = line.has_prefix ("exec ") || line.contains (" exec ");
					var script_tokens = unwrap_command_string (line);
					if (script_tokens.size > 0) {
						var raw_first = expand_shell_path (script_tokens.get (0), script_vars).strip ();
						var inner_exe = File.new_for_path (raw_first).get_basename ();
						if (is_terminal_emulator_binary (inner_exe)) {
							var norm_term = normalize (inner_exe);
							bool found_e_flag = false;
							for (int ti = 1; ti < script_tokens.size; ti++) {
								var t_tok = expand_shell_path (script_tokens.get (ti), script_vars).strip ();
								var t_down = t_tok.down ();
								if ((t_down == "-class" || t_down == "--class") && ti + 1 < script_tokens.size) {
									var wm_cls = normalize (expand_shell_path (script_tokens.get (ti + 1), script_vars).strip ().replace ("\"", "").replace ("'", ""));
									if (wm_cls != "" && !wm_cls.contains ("$")) {
										has_startup_wm_class = true;
										startup_wm_classes.add (wm_cls);
										primary_tokens.add (wm_cls);
										tokens.add (wm_cls);
									}
									ti++;
									continue;
								}
								if (t_down.has_prefix ("--class=")) {
									var wm_cls = normalize (t_tok.substring ("--class=".length).strip ().replace ("\"", "").replace ("'", ""));
									if (wm_cls != "" && !wm_cls.contains ("$")) {
										has_startup_wm_class = true;
										startup_wm_classes.add (wm_cls);
										primary_tokens.add (wm_cls);
										tokens.add (wm_cls);
									}
									continue;
								}
								if (t_tok == "-e" || t_tok == "--command" || t_tok == "-x" || t_tok == "--") {
									found_e_flag = true;
									for (int tj = ti + 1; tj < script_tokens.size; tj++) {
										var exp_cmd = expand_shell_path (script_tokens.get (tj), script_vars).strip ().replace ("\"", "").replace ("'", "");
										if (exp_cmd == "" || exp_cmd.has_prefix ("-") || exp_cmd == "$@" || exp_cmd == "$*")
											continue;
										if (exp_cmd.contains (" ")) {
											var sub_parts = parse_cmdline_argv (exp_cmd);
											var sub_hosted = new Gee.HashSet<string> ();
											collect_unwrapped_cmd_tokens (sub_parts, 0, sub_hosted);
											foreach (var sh_tok in sub_hosted) {
												if (!sh_tok.contains ("$") && !is_shell_script_utility (sh_tok)) {
													is_terminal_app = true;
													add_executable_token (sh_tok);
												}
											}
											if (sub_hosted.size > 0)
												break;
										}
										var cmd_base = File.new_for_path (exp_cmd).get_basename ();
										if (is_interactive_shell_binary (cmd_base) || cmd_base == "env" || cmd_base == "exec" || cmd_base == "sudo")
											continue;
										if (!cmd_base.contains ("$") && !is_shell_script_utility (cmd_base)) {
											is_terminal_app = true;
											add_executable_token (cmd_base);
										}
										break;
									}
									break;
								}
								if (t_down.has_prefix ("--command=")) {
									found_e_flag = true;
									var sub_cmd = t_tok.substring ("--command=".length).strip ().replace ("\"", "").replace ("'", "");
									var sub_parts = parse_cmdline_argv (sub_cmd);
									var sub_hosted = new Gee.HashSet<string> ();
									collect_unwrapped_cmd_tokens (sub_parts, 0, sub_hosted);
									foreach (var sh_tok in sub_hosted) {
										if (!sh_tok.contains ("$") && !is_shell_script_utility (sh_tok)) {
											is_terminal_app = true;
											add_executable_token (sh_tok);
										}
									}
									break;
								}
							}
							if (!found_e_flag && (norm_term == "foot" || norm_term == "footclient" || norm_term == "kitty" ||
							    norm_term == "alacritty" || norm_term == "wezterm" || norm_term == "ghostty")) {
								int ti = 1;
								while (ti < script_tokens.size) {
									var t_tok = expand_shell_path (script_tokens.get (ti), script_vars).strip ().replace ("\"", "").replace ("'", "");
									if (t_tok == "" || t_tok == "$@" || t_tok == "$*") {
										ti++;
										continue;
									}
									if (t_tok == "-T" || t_tok == "--title" || t_tok == "-a" || t_tok == "--app-id" ||
									    t_tok == "-w" || t_tok == "--working-directory" || t_tok == "-c" || t_tok == "--config" ||
									    t_tok == "-o" || t_tok == "--override" || t_tok == "--option" || t_tok == "-f" || t_tok == "--font" ||
									    t_tok == "--class" || t_tok == "--name" || t_tok == "--session" || t_tok == "-d" || t_tok == "--directory") {
										ti += 2;
										continue;
									}
									if (t_tok.has_prefix ("-")) {
										ti++;
										continue;
									}
									var cmd_base = File.new_for_path (t_tok).get_basename ();
									if (is_interactive_shell_binary (cmd_base) || cmd_base == "env" || cmd_base == "exec" || cmd_base == "sudo") {
										ti++;
										continue;
									}
									if (!cmd_base.contains ("$") && !is_shell_script_utility (cmd_base)) {
										is_terminal_app = true;
										add_executable_token (cmd_base);
									}
									break;
								}
							}
							continue;
						}
						if (inner_exe != "" && !inner_exe.has_prefix ("-") && !inner_exe.contains ("(") &&
						    !inner_exe.contains ("=") && !inner_exe.contains ("$") && !is_shell_script_utility (inner_exe)) {
							var norm_inner = normalize (inner_exe);
							bool is_wine_or_runtime = (norm_inner == "wine" || norm_inner == "wine64" || norm_inner == "wine-preloader" ||
							    norm_inner == "wine64-preloader" || norm_inner == "umu-run" || norm_inner == "proton" ||
							    norm_inner == "java" || norm_inner == "javaw" || norm_inner == "python" || norm_inner == "python3");
							string script_dir = GLib.Path.get_dirname (script_path);
							bool same_dir_target = (raw_first.has_prefix ("/") && GLib.Path.get_dirname (raw_first) == script_dir);
							if (line_has_exec || is_browser_binary (inner_exe) || is_wine_or_runtime || same_dir_target ||
							    (base_id != "" && norm_inner.length >= 3 && (base_id.contains (norm_inner) || norm_inner.contains (base_id)))) {
								add_executable_token (inner_exe);
							}
							if (norm_inner == "wine" || norm_inner == "wine64" || norm_inner == "wine-preloader" ||
							    norm_inner == "wine64-preloader" || norm_inner == "umu-run" || norm_inner == "proton")
								has_wine_executable = true;
						}
						bool inner_is_browser = is_browser_binary (inner_exe) || has_browser_executable;
						for (int i = 1; i < script_tokens.size; i++) {
							var s_arg = expand_shell_path (script_tokens.get (i), script_vars).strip ().replace ("\"", "").replace ("'", "");
							if (s_arg == "" || s_arg == "$@" || s_arg == "$*" || s_arg == "$1")
								continue;
							var s_down = s_arg.down ();
							if (s_down.has_prefix ("http://") || s_down.has_prefix ("https://")) {
								has_positional_url = true;
								continue;
							}
							if ((s_down == "+set" || s_down == "-set") && i + 2 < script_tokens.size) {
								var cvar = expand_shell_path (script_tokens.get (i + 1), script_vars).strip ().down ();
								var cval = expand_shell_path (script_tokens.get (i + 2), script_vars).strip ().replace ("\"", "").replace ("'", "").down ();
								if ((cvar == "game" || cvar == "fs_game") && cval != "" && !cval.contains ("$") && !is_generic_argument_stopword (cval)) {
									if (!required_mod_tokens.contains (cval))
										required_mod_tokens.add (cval);
									if (!argument_tokens.contains (cval))
										argument_tokens.add (cval);
									i += 2;
									continue;
								}
							}
							if (inner_is_browser && is_incognito_switch (s_down)) {
								requires_incognito = true;
								has_isolated_browser_flag = true;
								continue;
							}
							if ((s_down == "--app" || s_down == "-app") && i + 1 < script_tokens.size) {
								var next_url = expand_shell_path (script_tokens.get (i + 1), script_vars).strip ().replace ("\"", "").replace ("'", "").down ();
								if (next_url != "" && !next_url.has_prefix ("-")) {
									is_chromium_webapp = true;
									if (!next_url.contains ("://") && next_url.contains (".") && !next_url.has_prefix ("/"))
										next_url = "https://" + next_url;
									if (next_url.has_prefix ("http://") || next_url.has_prefix ("https://"))
										extract_web_app_host (next_url);
									i++;
									continue;
								}
							}
							if (s_arg == "-P" || s_arg == "--ProfileManager"
								|| s_down == "--class" || s_down == "-class"
								|| s_down == "--profile" || s_down == "-profile"
								|| s_down == "--user-data-dir"
								|| s_down == "--profile-directory"
								|| s_down == "--user-agent") {
								if (s_down != "--profile-directory")
									has_isolated_browser_flag = true;
								if (i + 1 < script_tokens.size) {
									var raw_next = expand_shell_path (script_tokens.get (i + 1), script_vars).strip ().replace ("\"", "").replace ("'", "");
									if (raw_next != "" && !raw_next.has_prefix ("-")) {
										if (inner_is_browser) {
											string kind = s_down.contains ("class") ? "class"
												: (s_down.contains ("user-data-dir") ? "user-data-dir"
												: (s_down.contains ("profile-directory") ? "profile-dir"
												: (s_down.contains ("user-agent") ? "user-agent" : "profile-arg")));
											add_required_browser_arg (kind, raw_next, script_vars);
										} else {
											argument_tokens.add (raw_next.down ());
										}
										i++;
									}
								}
								continue;
							}
							if (s_arg.contains ("=")) {
								var eq = s_arg.index_of_char ('=');
								var opt_key = s_arg.substring (0, eq).down ();
								var raw_val = s_arg.substring (eq + 1).strip ().replace ("\"", "").replace ("'", "");
								if (opt_key == "--class" || opt_key == "-class"
									|| opt_key.contains ("user-data-dir")
									|| opt_key == "--user-agent"
									|| (opt_key.contains ("profile") && !opt_key.contains ("profile-directory")))
									has_isolated_browser_flag = true;
								if (inner_is_browser && (opt_key.contains ("profile") || opt_key.contains ("user-data-dir") || opt_key == "--class" || opt_key == "-class" || opt_key == "--user-agent")) {
									string kind = opt_key.contains ("class") ? "class"
										: (opt_key.contains ("user-data-dir") ? "user-data-dir"
										: (opt_key.contains ("profile-directory") ? "profile-dir"
										: (opt_key == "--user-agent" ? "user-agent" : "profile-arg")));
									add_required_browser_arg (kind, raw_val, script_vars);
									continue;
								}
								if (opt_key == "-didea.platform.prefix" || opt_key == "-didea.paths.selector") {
									var val = normalize (expand_shell_path (raw_val, script_vars));
									if (val != "" && val.length >= 3 && !is_common_stopword (val) && !is_generic_script_stem (val)) {
										tokens.add (val);
										primary_tokens.add (val);
										try {
											var ver_regex = new GLib.Regex ("[-_vV]*[0-9]+(\\.[0-9]+)*.*$");
											var clean_val = ver_regex.replace_literal (val, -1, 0, "");
											if (clean_val != "" && clean_val.length >= 3 && !is_common_stopword (clean_val) && !is_generic_script_stem (clean_val)) {
												tokens.add (clean_val);
												primary_tokens.add (clean_val);
											}
										} catch (Error e) { }
									}
									continue;
								}
								if (opt_key.contains ("profile") || opt_key.contains ("user-data-dir")
						|| opt_key == "--class" || opt_key == "-class"
						|| opt_key == "--name" || opt_key == "-name"
						|| opt_key == "--app" || opt_key == "-app"
						|| opt_key == "--app-id" || opt_key == "-app-id") {
									var val = expand_shell_path (raw_val, script_vars).down ();
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
				while (p.length > 1 && (p.has_suffix (";") || p.has_suffix ("&") || p.has_suffix ("|")))
					p = p.substring (0, p.length - 1).strip ();
				if (p == "") {
					idx++;
					continue;
				}
				var base_p = File.new_for_path (p).get_basename ().down ();

				// 1. Recursive unwrap for sh -c "..." or bash -c "..." (supporting ; / && / || compound commands)
				if (base_p == "sh" || base_p == "bash" || base_p == "dash" || base_p == "zsh") {
					if (idx + 1 < parts.length && (parts[idx + 1] == "-c" || parts[idx + 1] == "-lc")) {
						if (idx + 2 < parts.length) {
							var inner_script = parts[idx + 2];
							if (inner_script.contains (";") || inner_script.contains ("&&") || inner_script.contains ("||")) {
								var normalized_sep = inner_script.replace ("&&", ";").replace ("||", ";");
								foreach (var stmt in normalized_sep.split (";")) {
									var sub_stmt = stmt.strip ();
									if (sub_stmt == "")
										continue;
									var sub_unwrapped = unwrap_command_string (sub_stmt);
									if (sub_unwrapped.size > 0) {
										var cand_exe = File.new_for_path (sub_unwrapped.get (0)).get_basename ().down ();
										if (cand_exe != "" && !is_shell_script_utility (cand_exe))
											return sub_unwrapped;
									}
								}
							}
							return unwrap_command_string (inner_script);
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

				// 3. Skip environment variable assignments like TMPDIR=..., MESA_GL_VERSION_OVERRIDE=..., and extract WINEPREFIX=...
				if (p.contains ("=") && !p.has_prefix ("-")) {
					if (p.down ().has_prefix ("wineprefix=")) {
						var wp_val = expand_shell_path (p.substring ("wineprefix=".length).strip ().replace ("\"", "").replace ("'", "")).replace ("\\", "/");
						while (wp_val.length > 1 && wp_val.has_suffix ("/"))
							wp_val = wp_val.substring (0, wp_val.length - 1);
						var wp_leaf = File.new_for_path (wp_val).get_basename ().down ();
						if (wp_leaf != "" && wp_leaf != ".wine" && wp_leaf.length >= 3 && !is_generic_argument_stopword (wp_leaf)) {
							has_wine_executable = true;
							if (wine_prefix_token == "")
								wine_prefix_token = wp_leaf;
							if (!argument_tokens.contains (wp_leaf))
								argument_tokens.add (wp_leaf);
						}
					}
					idx++;
					continue;
				}

				// 4. Skip common launcher / sandbox wrappers (handling flags with arguments like sudo -u root / pkexec --user root)
				if (base_p == "firejail" || base_p == "flatpak-spawn" || base_p == "pkexec" ||
				    base_p == "sudo" || base_p == "prime-run" || base_p == "gamemoderun" ||
				    base_p == "optirun" || base_p == "systemd-inhibit" || base_p == "nohup") {
					idx++;
					while (idx < parts.length && parts[idx].has_prefix ("-")) {
						var flag_tok = parts[idx];
						if ((flag_tok == "-u" || flag_tok == "--user" || flag_tok == "-g" || flag_tok == "--group") && idx + 1 < parts.length) {
							idx += 2;
							continue;
						}
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

				// First real binary found! Add it and all remaining arguments up to any shell statement separator
				for (int j = idx; j < parts.length; j++) {
					var tok = parts[j].strip ();
					if (tok == ";" || tok == "&&" || tok == "||" || tok == "&" || tok == "|")
						break;
					bool stop_after = false;
					if (tok.length > 1 && tok.has_suffix (";")) {
						tok = tok.substring (0, tok.length - 1).strip ();
						stop_after = true;
					}
					if (tok != "")
						result.add (tok);
					if (stop_after)
						break;
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
			if (norm == "" || norm == "sh" || norm == "bash" || norm == "env" || is_shell_script_utility (norm))
				return;

			// Strip wrapper script extensions (.sh, .py, .run, .bin) so e.g. devecostudio.sh -> devecostudio
			string script_stem = "";
			string[] script_exts = { ".sh", ".py", ".run", ".bin" };
			foreach (unowned string ext in script_exts) {
				if (norm.has_suffix (ext)) {
					var candidate = norm.substring (0, norm.length - ext.length);
					if (candidate.length < 3 || is_common_stopword (candidate) || is_generic_script_stem (candidate)) {
						if (norm.length >= 4) {
							executable_tokens.add (norm);
							tokens.add (norm);
							dedicated_binaries.add (norm);
							primary_tokens.add (norm);
						}
						return;
					}
					script_stem = candidate;
					break;
				}
			}

			executable_tokens.add (norm);
			tokens.add (norm);
			register_dedicated_binary (norm);

			var effective_norm = (script_stem != "") ? script_stem : norm;
			if (script_stem != "") {
				executable_tokens.add (script_stem);
				tokens.add (script_stem);
				register_dedicated_binary (script_stem);
			}
			if (is_chromium_browser_binary (effective_norm))
				is_chromium_webapp = true;
			if (is_browser_binary (effective_norm))
				has_browser_executable = true;

			// Prefix match for dashed binaries (e.g. qemu-system-x86_64 -> qemu)
			var first_dash = effective_norm.index_of_char ('-');
			if (first_dash > 0) {
				var prefix = effective_norm.substring (0, first_dash);
				if (prefix.length >= 3 && !is_common_stopword (prefix) && !is_generic_script_stem (prefix)) {
					executable_tokens.add (prefix);
					tokens.add (prefix);
				}
			}

			// Auto-register binary aliases (-bin variant, google-chrome vs chrome, etc.)
			if (effective_norm.has_suffix ("-bin")) {
				var base_name = effective_norm.substring (0, effective_norm.length - 4);
				if (base_name.length >= 3 && !is_common_stopword (base_name) && !is_generic_script_stem (base_name)) {
					executable_tokens.add (base_name);
					tokens.add (base_name);
					register_dedicated_binary (base_name);
				}
			} else {
				executable_tokens.add (effective_norm + "-bin");
				tokens.add (effective_norm + "-bin");
				if (!is_generic_runtime_binary (effective_norm)) {
					dedicated_binaries.add (effective_norm + "-bin");
					primary_tokens.add (effective_norm + "-bin");
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
					var clean_name = ver_regex.replace_literal (effective_norm, -1, 0, "");
					if (clean_name != effective_norm && clean_name != "" && clean_name.length >= 3 && !is_common_stopword (clean_name) && !is_generic_script_stem (clean_name)) {
						executable_tokens.add (clean_name);
						tokens.add (clean_name);
						tokens.add (clean_name.replace ("-", " "));
						tokens.add (clean_name.replace ("_", " "));
						register_dedicated_binary (clean_name);
					}
				} catch (Error e) { }
			}

			if (effective_norm == "google-chrome" || effective_norm == "google-chrome-stable") {
				executable_tokens.add ("chrome");
				tokens.add ("chrome");
			} else if (effective_norm == "chrome") {
				executable_tokens.add ("google-chrome");
				tokens.add ("google-chrome");
			} else if (effective_norm == "chromium" || effective_norm == "chromium-browser") {
				executable_tokens.add ("chromium");
				executable_tokens.add ("chromium-browser");
				tokens.add ("chromium");
				tokens.add ("chromium-browser");
			} else if (effective_norm == "brave" || effective_norm == "brave-browser") {
				executable_tokens.add ("brave");
				executable_tokens.add ("brave-browser");
				tokens.add ("brave");
				tokens.add ("brave-browser");
			} else if (effective_norm == "microsoft-edge" || effective_norm == "msedge" || effective_norm == "microsoft-edge-stable") {
				executable_tokens.add ("msedge");
				executable_tokens.add ("microsoft-edge");
				tokens.add ("msedge");
				tokens.add ("microsoft-edge");
			} else if (effective_norm == "code" || effective_norm == "visual-studio-code") {
				executable_tokens.add ("code");
				tokens.add ("com.microsoft.vscode");
				dedicated_binaries.add ("code");
				dedicated_binaries.add ("com.microsoft.vscode");
				primary_tokens.add ("code");
				primary_tokens.add ("com.microsoft.vscode");
			} else if (effective_norm == "quake2" || effective_norm == "yamagi-quake2") {
				executable_tokens.add ("quake2");
				executable_tokens.add ("yamagi-quake2");
				tokens.add ("quake2");
				tokens.add ("yamagi-quake2");
				dedicated_binaries.add ("quake2");
				dedicated_binaries.add ("yamagi-quake2");
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
			       word == "view" || word == "main" || word == "help" ||
			       word == "studio" || word == "ide" || word == "browser" || word == "player";
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
			int idx = 0;
			unichar c;
			while (word.get_next_char (ref idx, out c)) {
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
			if (is_browser_binary (n) || n.has_prefix ("qemu-") ||
			    n.has_suffix (".sh") || n.has_suffix (".py") || n.has_suffix (".run") || n.has_suffix (".bin"))
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

		private static bool is_generic_script_stem (string stem)
		{
			var n = normalize (stem);
			if (is_common_stopword (n) || is_common_path_stopword (n) || is_shell_script_utility (n))
				return true;
			return n == "sh" || n == "bash" || n == "dash" || n == "zsh" || n == "fish" || n == "env" ||
			       n == "java" || n == "javaw" || n == "python" || n == "python2" || n == "python3" ||
			       n == "perl" || n == "ruby" || n == "node" || n == "nodejs" || n == "deno" || n == "bun" ||
			       n == "php" || n == "lua" || n == "wish" || n == "tclsh" || n == "mono" || n == "dotnet" ||
			       n == "electron" || n == "wine" || n == "wine64" || n == "flatpak" || n == "snap" ||
			       n == "xdg-open" || n == "gio" || n == "start" || n == "starter" || n == "startup" ||
			       n == "launch" || n == "launcher" || n == "wrapper" || n == "setup" || n == "init" ||
			       n == "install" || n == "installer" || n == "uninstall" || n == "update" ||
			       n == "updater" || n == "bootstrap" || n == "entry" || n == "entrypoint" ||
			       n == "script" || n == "runner" || n == "exec" || n == "cli" || n == "gui";
		}

		private static bool is_shell_script_utility (string exe_name)
		{
			var n = normalize (exe_name);
			return n == "uname" || n == "dirname" || n == "basename" || n == "readlink" ||
			       n == "realpath" || n == "grep" || n == "egrep" || n == "fgrep" ||
			       n == "sed" || n == "awk" || n == "gawk" || n == "mawk" || n == "cat" ||
			       n == "cut" || n == "tr" || n == "head" || n == "tail" || n == "wc" ||
			       n == "sort" || n == "uniq" || n == "find" || n == "xargs" || n == "which" ||
			       n == "command" || n == "type" || n == "rm" || n == "cp" || n == "mv" ||
			       n == "ln" || n == "chmod" || n == "chown" || n == "mkdir" || n == "rmdir" ||
			       n == "touch" || n == "expr" || n == "mktemp" || n == "zenity" ||
			       n == "kdialog" || n == "xmessage" || n == "notify-send" || n == "message" ||
			       n == "true" || n == "false" || n == "test" || n == "eval" || n == "exec" ||
			       n == "xprop" || n == "xdpyinfo" || n == "xrandr" || n == "wmctrl" ||
			       n == "xdotool" || n == "ldconfig" || n == "ldd" || n == "file" ||
			       n == "stat" || n == "id" || n == "whoami" || n == "hostname" || n == "date" ||
			       n == "tput" || n == "stty" || n == "ulimit" || n == "nohup" || n == "setsid" ||
			       n == "nice" || n == "ionice" || n == "chrt" || n == "taskset" || n == "timeout" ||
			       n == "com.intellij.idea.main";
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

		public static bool is_terminal_emulator_binary (string exe_name)
		{
			var n = normalize (exe_name);
			if (n.has_suffix ("-bin"))
				n = n.substring (0, n.length - 4);
			return n == "konsole" || n == "gnome-terminal" || n == "gnome-terminal-server" ||
			       n == "kgx" || n == "ptyxis" || n == "xfce4-terminal" || n == "mate-terminal" ||
			       n == "tilix" || n == "terminator" || n == "alacritty" || n == "kitty" ||
			       n == "foot" || n == "footclient" || n == "wezterm" || n == "wezterm-gui" ||
			       n == "xterm" || n == "uxterm" || n == "urxvt" || n == "rxvt" ||
			       n == "sakura" || n == "guake" || n == "yakuake" || n == "qterminal" ||
			       n == "lxterminal" || n == "terminology" || n == "st" || n == "hyper" ||
			       n == "tabby" || n == "ghostty" || n == "rio" || n == "warp-terminal";
		}

		public bool is_terminal_emulator_launcher ()
		{
			if (is_terminal_app || is_specialized ())
				return false;
			foreach (var exe in executable_tokens) {
				if (is_terminal_emulator_binary (exe))
					return true;
			}
			foreach (var pt in primary_tokens) {
				if (is_terminal_emulator_binary (pt))
					return true;
				var last_dot = pt.last_index_of_char ('.');
				if (last_dot >= 0 && is_terminal_emulator_binary (pt.substring (last_dot + 1)))
					return true;
			}
			return false;
		}

		public static bool is_terminal_window (WindowInfo window)
		{
			if (window.Executable != "" && is_terminal_emulator_binary (window.Executable))
				return true;
			var win_ids = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			foreach (var wid in win_ids) {
				if (wid == null || wid == "")
					continue;
				var norm = normalize (wid);
				if (is_terminal_emulator_binary (norm))
					return true;
				var last_dot = norm.last_index_of_char ('.');
				if (last_dot >= 0 && is_terminal_emulator_binary (norm.substring (last_dot + 1)))
					return true;
			}
			return false;
		}

		private static bool is_interactive_shell_binary (string exe_name)
		{
			var n = normalize (exe_name);
			if (n.has_prefix ("-"))
				n = n.substring (1);
			return n == "sh" || n == "bash" || n == "zsh" || n == "fish" || n == "dash" || n == "csh" || n == "tcsh" || n == "ksh";
		}

		private static bool is_bare_interactive_shell_argv (string[] c_argv)
		{
			if (c_argv.length == 0)
				return false;
			var c_bin = File.new_for_path (c_argv[0]).get_basename ().down ();
			if (!is_interactive_shell_binary (c_bin))
				return false;
			for (int i = 1; i < c_argv.length; i++) {
				var arg = c_argv[i].strip ();
				if (arg == "")
					continue;
				if (arg == "-c" || arg == "-lc" || arg == "-ic" || arg.has_prefix ("-c"))
					return false;
				if (!arg.has_prefix ("-"))
					return false;
			}
			return true;
		}

		private static string read_proc_children_raw (int pid)
		{
			if (pid <= 0)
				return "";
			string children_raw = "";
			try {
				if (GLib.FileUtils.get_contents ("/proc/%d/task/%d/children".printf (pid, pid), out children_raw) && children_raw.strip () != "")
					return children_raw.strip ();
			} catch { }
			try {
				if (GLib.FileUtils.get_contents ("/proc/%d/children".printf (pid), out children_raw) && children_raw.strip () != "")
					return children_raw.strip ();
			} catch { }
			return "";
		}

		private static void collect_unwrapped_cmd_tokens (string[] argv, int start_idx, Gee.HashSet<string> out_tokens)
		{
			int idx = start_idx;
			while (idx < argv.length) {
				var p = argv[idx].strip ().replace ("\"", "").replace ("'", "");
				while (p.length > 1 && (p.has_suffix (";") || p.has_suffix ("&") || p.has_suffix ("|")))
					p = p.substring (0, p.length - 1).strip ();
				if (p == "") {
					idx++;
					continue;
				}
				var base_p = File.new_for_path (p).get_basename ().down ();
				if (base_p == "sh" || base_p == "bash" || base_p == "dash" || base_p == "zsh") {
					if (idx + 1 < argv.length && (argv[idx + 1] == "-c" || argv[idx + 1] == "-lc")) {
						if (idx + 2 < argv.length) {
							var sub_argv = parse_cmdline_argv (argv[idx + 2]);
							collect_unwrapped_cmd_tokens (sub_argv, 0, out_tokens);
							return;
						}
					}
					idx++;
					continue;
				}
				if (base_p == "env" || base_p == "exec" || (p.contains ("=") && !p.has_prefix ("-"))) {
					idx++;
					continue;
				}
				if (base_p == "sudo" || base_p == "pkexec" || base_p == "firejail" || base_p == "nohup") {
					idx++;
					while (idx < argv.length && argv[idx].has_prefix ("-")) {
						if ((argv[idx] == "-u" || argv[idx] == "--user") && idx + 1 < argv.length) {
							idx += 2;
							continue;
						}
						idx++;
					}
					continue;
				}
				if (base_p != "" && !base_p.has_prefix ("-") && !is_interactive_shell_binary (base_p) && !is_terminal_emulator_binary (base_p)) {
					out_tokens.add (base_p);
					var dot = base_p.last_index_of_char ('.');
					if (dot > 0)
						out_tokens.add (base_p.substring (0, dot));
					if (is_generic_runtime_binary (base_p)) {
						for (int j = idx + 1; j < argv.length; j++) {
							var arg_p = argv[j].strip ().replace ("\"", "").replace ("'", "");
							if (arg_p == "" || arg_p.has_prefix ("-"))
								continue;
							var arg_base = File.new_for_path (arg_p).get_basename ().down ();
							if (arg_base.length >= 3 && !is_generic_argument_stopword (arg_base)) {
								out_tokens.add (arg_base);
								var adot = arg_base.last_index_of_char ('.');
								if (adot > 0)
									out_tokens.add (arg_base.substring (0, adot));
								break;
							}
						}
					}
				}
				return;
			}
		}

		public static Gee.HashSet<string> extract_terminal_hosted_tokens (WindowInfo window)
		{
			var hosted = new Gee.HashSet<string> ();
			if (!is_terminal_window (window))
				return hosted;
			ensure_browser_tracking_maps ();

			if (window.Id != "" && window.Pid > 0)
				open_terminal_window_pids.set (window.Id, window.Pid);

			if (window.Cmdline != "") {
				var argv = parse_cmdline_argv (window.Cmdline);
				if (argv.length > 0) {
					var term_bin = normalize (File.new_for_path (argv[0]).get_basename ());
					bool can_use_cmdline = (window.Pid <= 0 || window.Id == "" ||
						(terminal_cmdline_owner_wid.has_key (window.Pid) && terminal_cmdline_owner_wid.get (window.Pid) == window.Id) ||
						(!terminal_cmdline_owner_wid.has_key (window.Pid) && !terminal_cmdline_consumed_pids.contains (window.Pid)));

					if (can_use_cmdline) {
						for (int i = 1; i < argv.length; i++) {
							var tok = argv[i].strip ();
							if (tok == "-e" || tok == "--command" || tok == "-x" || tok == "--") {
								if (i + 1 < argv.length)
									collect_unwrapped_cmd_tokens (argv, i + 1, hosted);
								break;
							}
							if (tok.has_prefix ("--command=")) {
								var sub_argv = parse_cmdline_argv (tok.substring ("--command=".length));
								collect_unwrapped_cmd_tokens (sub_argv, 0, hosted);
								break;
							}
						}
						// Positional command support for foot, kitty, alacritty, wezterm, ghostty (e.g. "foot updatesys")
						if (hosted.size == 0 && (term_bin == "foot" || term_bin == "footclient" || term_bin == "kitty" ||
						    term_bin == "alacritty" || term_bin == "wezterm" || term_bin == "wezterm-gui" || term_bin == "ghostty")) {
							int idx = 1;
							while (idx < argv.length) {
								var tok = argv[idx].strip ();
								if (tok == "") {
									idx++;
									continue;
								}
								if (tok == "-T" || tok == "--title" || tok == "-a" || tok == "--app-id" ||
								    tok == "-w" || tok == "--working-directory" || tok == "-c" || tok == "--config" ||
								    tok == "-o" || tok == "--override" || tok == "--option" || tok == "-f" || tok == "--font" ||
								    tok == "--class" || tok == "--name" || tok == "--session" || tok == "-d" || tok == "--directory") {
									idx += 2;
									continue;
								}
								if (tok.has_prefix ("-")) {
									idx++;
									continue;
								}
								collect_unwrapped_cmd_tokens (argv, idx, hosted);
								break;
							}
						}
						if (hosted.size > 0 && window.Pid > 0 && window.Id != "") {
							terminal_cmdline_owner_wid.set (window.Pid, window.Id);
							terminal_cmdline_consumed_pids.add (window.Pid);
						}
					}
				}
			}

			// Multi-window / single-process & child process ownership inspection
			// ALWAYS run child PID ownership binding even when Step 1 matched hosted tokens for W1,
			// so W1 claims its own child PID in terminal_child_pid_owner_wid and a subsequent plain terminal W2 never steals it!
			if (window.Pid > 0) {
				int owned_cpid = 0;
				if (window.Id != "") {
					var stale_cpids = new Gee.ArrayList<int> ();
					foreach (var entry in terminal_child_pid_owner_wid.entries) {
						if (entry.value == window.Id) {
							if (GLib.FileUtils.test ("/proc/%d".printf (entry.key), GLib.FileTest.EXISTS)) {
								owned_cpid = entry.key;
								break;
							} else {
								stale_cpids.add (entry.key);
							}
						}
					}
					foreach (int sc in stale_cpids)
						terminal_child_pid_owner_wid.unset (sc);
				}

				if (owned_cpid <= 0) {
					string children_raw = read_proc_children_raw (window.Pid);
					if (children_raw != "") {
						foreach (var cpid_str in children_raw.split (" ")) {
							int cpid = int.parse (cpid_str.strip ());
							if (cpid <= 0)
								continue;
							if (window.Id != "" && terminal_child_pid_owner_wid.has_key (cpid) &&
							    terminal_child_pid_owner_wid.get (cpid) != window.Id)
								continue;
							var c_cmd = ApplicationDiscovery.get_process_cmdline (cpid);
							if (c_cmd == "")
								continue;
							var c_argv = parse_cmdline_argv (c_cmd);
							if (c_argv.length == 0)
								continue;
							var c_bin = File.new_for_path (c_argv[0]).get_basename ().down ();
							// Skip pre-execve forked child that still reports the terminal emulator binary
							if (is_terminal_emulator_binary (c_bin)) {
								ApplicationDiscovery.invalidate_process_cmdline (cpid);
								continue;
							}
							if (window.Id != "")
								terminal_child_pid_owner_wid.set (cpid, window.Id);
							owned_cpid = cpid;
							break;
						}
					}
				}

				if (hosted.size == 0 && owned_cpid > 0) {
					var c_cmd = ApplicationDiscovery.get_process_cmdline (owned_cpid);
					if (c_cmd != "") {
						var c_argv = parse_cmdline_argv (c_cmd);
						if (c_argv.length > 0 && !is_bare_interactive_shell_argv (c_argv)) {
							collect_unwrapped_cmd_tokens (c_argv, 0, hosted);
							if (hosted.size == 0) {
								string sub_children = read_proc_children_raw (owned_cpid);
								if (sub_children != "") {
									foreach (var gpid_str in sub_children.split (" ")) {
										int gpid = int.parse (gpid_str.strip ());
										if (gpid <= 0)
											continue;
										var g_cmd = ApplicationDiscovery.get_process_cmdline (gpid);
										if (g_cmd == "")
											continue;
										var g_argv = parse_cmdline_argv (g_cmd);
										if (g_argv.length > 0 && !is_bare_interactive_shell_argv (g_argv)) {
											collect_unwrapped_cmd_tokens (g_argv, 0, hosted);
											if (hosted.size > 0)
												break;
										}
									}
								}
							}
						}
					}
				}
			}
			return hosted;
		}

		public static bool is_terminal_window_child_ready (WindowInfo window)
		{
			if (!is_terminal_window (window))
				return true;
			ensure_browser_tracking_maps ();
			var hosted = extract_terminal_hosted_tokens (window);
			if (hosted.size > 0)
				return true;
			if (window.Id != "" && terminal_child_pid_owner_wid.values.contains (window.Id))
				return true;
			if (window.Pid > 0 && window.Id != "" && terminal_cmdline_owner_wid.has_key (window.Pid) &&
			    terminal_cmdline_owner_wid.get (window.Pid) == window.Id)
				return true;
			return false;
		}

		public static bool window_has_terminal_command (WindowInfo window)
		{
			return extract_terminal_hosted_tokens (window).size > 0;
		}

		private static string get_process_cwd (int pid)
		{
			if (pid <= 0)
				return "";
			if (pid_cwd_cache == null)
				pid_cwd_cache = new Gee.HashMap<int, string> ();
			if (pid_cwd_cache.has_key (pid))
				return pid_cwd_cache.get (pid);
			try {
				string? cwd = GLib.FileUtils.read_link ("/proc/%d/cwd".printf (pid));
				if (cwd != null && cwd != "") {
					var res = cwd.replace ("\\", "/").down ();
					if (pid_cwd_cache.size > 512)
						pid_cwd_cache.clear ();
					pid_cwd_cache.set (pid, res);
					return res;
				}
			} catch { }
			return "";
		}

		private static bool is_wine_window (WindowInfo window)
		{
			if (window.Executable != "") {
				var ne = normalize (window.Executable);
				if (ne == "wine" || ne == "wine64" || ne == "wine-preloader" || ne == "wine64-preloader" || ne == "wineserver" || ne.has_suffix (".exe") || ne.has_suffix (".lnk"))
					return true;
			}
			var win_ids = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			foreach (var wid in win_ids) {
				if (wid == null || wid == "")
					continue;
				var nw = wid.down ().strip ();
				if (nw == "wine" || nw.has_suffix (".exe") || nw.has_suffix (".lnk"))
					return true;
			}
			if (window.Cmdline != "") {
				var cl = window.Cmdline.down ();
				if (cl.contains (":\\") || cl.contains (":/") || cl.contains (".exe") || cl.contains (".lnk") || cl.contains ("wine"))
					return true;
			}
			return false;
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
			return pwa_id != "" || web_app_host != "" || is_browser_url_bookmark || is_non_app_desktop ||
			       argument_tokens.size > 0 || required_browser_args.size > 0 || required_mod_tokens.size > 0 || requires_incognito;
		}

		public bool shares_application_with (ApplicationIdentity other)
		{
			if (this == other)
				return true;
			if (this.is_specialized () || other.is_specialized ())
				return false;
			if (this.startup_wm_classes.size > 0 && other.startup_wm_classes.size > 0) {
				bool wm_compat = false;
				foreach (var sw in this.startup_wm_classes) {
					if (other.startup_wm_classes.contains (sw) || other.primary_tokens.contains (sw)) {
						wm_compat = true;
						break;
					}
				}
				if (!wm_compat) {
					foreach (var sw in other.startup_wm_classes) {
						if (this.startup_wm_classes.contains (sw) || this.primary_tokens.contains (sw)) {
							wm_compat = true;
							break;
						}
					}
				}
				if (!wm_compat)
					return false;
			}
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

		public static string normalize_profile_token (string raw)
		{
			string s = expand_shell_path (raw).strip ().replace ("\"", "").replace ("'", "").down ();
			while (s.length > 1 && s.has_suffix ("/"))
				s = s.substring (0, s.length - 1);
			return s.replace (" ", "_");
		}

		private static string? extract_json_string_field (string obj_text, string field_name)
		{
			string needle = "\"" + field_name + "\"";
			int idx = obj_text.index_of (needle);
			if (idx < 0)
				return null;
			int colon = obj_text.index_of_char (':', idx + needle.length);
			if (colon < 0)
				return null;
			int q1 = obj_text.index_of_char ('"', colon + 1);
			if (q1 < 0)
				return null;
			var sb = new GLib.StringBuilder ();
			bool esc = false;
			for (int i = q1 + 1; i < obj_text.length; i++) {
				char c = obj_text[i];
				if (esc) {
					sb.append_c (c);
					esc = false;
				} else if (c == '\\') {
					esc = true;
				} else if (c == '"') {
					return sb.str;
				} else {
					sb.append_c (c);
				}
			}
			return null;
		}

		private static void parse_local_state_file (string path)
		{
			try {
				if (!GLib.FileUtils.test (path, GLib.FileTest.IS_REGULAR))
					return;
				string content;
				if (!GLib.FileUtils.get_contents (path, out content) || content == "")
					return;
				int ic_pos = content.index_of ("\"info_cache\"");
				if (ic_pos < 0)
					return;
				int prof_pos = content.index_of ("\"profile\"");
				if (prof_pos >= 0 && last_used_profile_dir == "") {
					string? lu = extract_json_string_field (content.substring (prof_pos), "last_used");
					if (lu != null && lu.strip () != "")
						last_used_profile_dir = lu.strip ();
				}
				int open_brace = content.index_of_char ('{', ic_pos + 12);
				if (open_brace < 0)
					return;

				int depth = 0;
				bool in_str = false;
				bool esc = false;
				string current_key = "";
				int entry_start = -1;

				for (int i = open_brace; i < content.length; i++) {
					char c = content[i];
					if (in_str) {
						if (esc) {
							esc = false;
						} else if (c == '\\') {
							esc = true;
						} else if (c == '"') {
							in_str = false;
						}
						continue;
					}
					if (c == '"') {
						if (depth == 1 && entry_start < 0) {
							int q_end = i + 1;
							bool q_esc = false;
							while (q_end < content.length) {
								char qc = content[q_end];
								if (q_esc) {
									q_esc = false;
								} else if (qc == '\\') {
									q_esc = true;
								} else if (qc == '"') {
									break;
								}
								q_end++;
							}
							if (q_end < content.length) {
								current_key = content.substring (i + 1, q_end - i - 1);
								i = q_end;
								continue;
							}
						}
						in_str = true;
						continue;
					}
					if (c == '{') {
						depth++;
						if (depth == 2)
							entry_start = i;
					} else if (c == '}') {
						if (depth == 2 && entry_start >= 0 && current_key != "") {
							string entry_json = content.substring (entry_start, i - entry_start + 1);
							string? name = extract_json_string_field (entry_json, "name");
							string? gaia_given = extract_json_string_field (entry_json, "gaia_given_name");
							string norm_dir = normalize_profile_token (current_key);
							string disp = (name != null && name.strip () != "") ? name.strip () : current_key;
							if (first_known_profile_dir == "")
								first_known_profile_dir = current_key;
							profile_dir_to_name.set (norm_dir, disp);
							profile_label_to_dir.set (norm_dir, current_key);
							profile_label_to_dir.set (current_key.down (), current_key);
							if (name != null && name.strip () != "") {
								string clean_name = name.strip ();
								profile_label_to_dir.set (clean_name.down (), current_key);
								profile_label_to_dir.set (normalize_profile_token (clean_name), current_key);
								if (gaia_given != null && gaia_given.strip () != "" && gaia_given.strip ().down () != clean_name.down ()) {
									string combo = "%s (%s)".printf (gaia_given.strip (), clean_name);
									profile_label_to_dir.set (combo.down (), current_key);
									profile_label_to_dir.set (normalize_profile_token (combo), current_key);
								}
							}
							entry_start = -1;
							current_key = "";
						}
						depth--;
						if (depth == 0)
							break;
					}
				}
			} catch (Error e) { }
		}

		private static void ensure_chrome_local_state_loaded ()
		{
			int64 now = GLib.get_monotonic_time ();
			if (profile_dir_to_name != null && (now - local_state_last_load_us) < 10000000LL)
				return;
			local_state_last_load_us = now;
			if (profile_dir_to_name == null)
				profile_dir_to_name = new Gee.HashMap<string, string> ();
			else
				profile_dir_to_name.clear ();
			if (profile_label_to_dir == null)
				profile_label_to_dir = new Gee.HashMap<string, string> ();
			else
				profile_label_to_dir.clear ();
			last_used_profile_dir = "";
			first_known_profile_dir = "";

			string cfg = GLib.Environment.get_user_config_dir ();
			if (cfg == "")
				return;
			string[] rel_paths = {
				"google-chrome/Local State",
				"chromium/Local State",
				"BraveSoftware/Brave-Browser/Local State",
				"microsoft-edge/Local State"
			};
			foreach (unowned string rel in rel_paths)
				parse_local_state_file (GLib.Path.build_filename (cfg, rel));
		}

		private static string get_fallback_default_profile ()
		{
			ensure_chrome_local_state_loaded ();
			if (last_used_profile_dir != "")
				return last_used_profile_dir;
			if (profile_dir_to_name != null && profile_dir_to_name.has_key ("default") && profile_label_to_dir != null && profile_label_to_dir.has_key ("default"))
				return profile_label_to_dir.get ("default");
			if (first_known_profile_dir != "")
				return first_known_profile_dir;
			return "Default";
		}

		public static string canonical_profile_token (string raw)
		{
			string norm = normalize_profile_token (raw);
			if (norm == "")
				return "";
			ensure_chrome_local_state_loaded ();
			if (profile_label_to_dir != null) {
				string raw_down = raw.strip ().replace ("\"", "").replace ("'", "").down ();
				if (profile_label_to_dir.has_key (raw_down))
					return normalize_profile_token (profile_label_to_dir.get (raw_down));
				if (profile_label_to_dir.has_key (norm))
					return normalize_profile_token (profile_label_to_dir.get (norm));
			}
			return norm;
		}

		public static string get_browser_profile_display_name (string raw_profile)
		{
			string clean = raw_profile.strip ().replace ("\"", "").replace ("'", "");
			if (clean == "")
				return "";
			ensure_chrome_local_state_loaded ();
			string canon = canonical_profile_token (clean);
			if (profile_dir_to_name != null && profile_dir_to_name.has_key (canon))
				return profile_dir_to_name.get (canon);
			return clean;
		}

		public static string format_chrome_profile_identity_name (string raw_profile)
		{
			string disp = get_browser_profile_display_name (raw_profile);
			if (disp == "")
				return "";
			return "Chrome:" + disp;
		}

		public static bool profiles_match (string prof_a, string prof_b)
		{
			var na = canonical_profile_token (prof_a);
			var nb = canonical_profile_token (prof_b);
			return na != "" && na == nb;
		}

		private static string extract_cmdline_profile_dir (string cmdline)
		{
			if (cmdline.strip () == "")
				return "";
			var argv = parse_cmdline_argv (cmdline);
			for (int i = 0; i < argv.length; i++) {
				string tok = argv[i].strip ().replace ("\"", "").replace ("'", "");
				string tok_down = tok.down ();
				if (tok_down.has_prefix ("--profile-directory=")) {
					string val = tok.substring ("--profile-directory=".length).strip ();
					if (val.down () == "profile" && i + 1 < argv.length) {
						string next_tok = argv[i + 1].strip ().replace ("\"", "").replace ("'", "");
						if (next_tok != "" && !next_tok.has_prefix ("-"))
							val = val + " " + next_tok;
					}
					return val;
				}
				if (tok_down == "--profile-directory" && i + 1 < argv.length) {
					string val = argv[i + 1].strip ().replace ("\"", "").replace ("'", "");
					if (val.down () == "profile" && i + 2 < argv.length) {
						string next_tok = argv[i + 2].strip ().replace ("\"", "").replace ("'", "");
						if (next_tok != "" && !next_tok.has_prefix ("-"))
							val = val + " " + next_tok;
					}
					return val;
				}
			}
			return "";
		}

		static Gee.HashSet<string>? dead_dbus_senders;

		private static void ensure_browser_tracking_maps ()
		{
			if (window_browser_profiles == null)
				window_browser_profiles = new Gee.HashMap<string, string> ();
			if (window_locked_launcher_uris == null)
				window_locked_launcher_uris = new Gee.HashMap<string, string> ();
			if (window_locked_display_names == null)
				window_locked_display_names = new Gee.HashMap<string, string> ();
			if (window_open_time_us == null)
				window_open_time_us = new Gee.HashMap<string, int64?> ();
			if (newest_window_for_pid == null)
				newest_window_for_pid = new Gee.HashMap<int, string> ();
			if (pid_to_dbus_sender == null)
				pid_to_dbus_sender = new Gee.HashMap<int, string> ();
			if (dbus_sender_to_pid == null)
				dbus_sender_to_pid = new Gee.HashMap<string, int> ();
			if (dead_dbus_senders == null)
				dead_dbus_senders = new Gee.HashSet<string> ();
			if (unresolved_browser_windows == null)
				unresolved_browser_windows = new Gee.HashMap<string, int> ();
			if (open_browser_window_order == null)
				open_browser_window_order = new Gee.ArrayList<string> ();
			if (open_browser_window_pids == null)
				open_browser_window_pids = new Gee.HashMap<string, int> ();
			if (ever_seen_browser_pids == null)
				ever_seen_browser_pids = new Gee.HashSet<int> ();
			if (multi_window_browser_pids == null)
				multi_window_browser_pids = new Gee.HashSet<int> ();
			if (terminal_cmdline_owner_wid == null)
				terminal_cmdline_owner_wid = new Gee.HashMap<int, string> ();
			if (terminal_cmdline_consumed_pids == null)
				terminal_cmdline_consumed_pids = new Gee.HashSet<int> ();
			if (terminal_child_pid_owner_wid == null)
				terminal_child_pid_owner_wid = new Gee.HashMap<int, string> ();
			if (open_terminal_window_pids == null)
				open_terminal_window_pids = new Gee.HashMap<string, int> ();
		}

		public static void invalidate_locked_launcher_uris ()
		{
			if (window_locked_launcher_uris != null)
				window_locked_launcher_uris.clear ();
			if (window_locked_display_names != null)
				window_locked_display_names.clear ();
		}

		public static void prune_locked_launcher_uris (Gee.Collection<string> valid_uris)
		{
			if (window_locked_launcher_uris == null || window_locked_launcher_uris.size == 0)
				return;
			var to_remove = new Gee.ArrayList<string> ();
			foreach (var entry in window_locked_launcher_uris.entries) {
				if (!valid_uris.contains (entry.value))
					to_remove.add (entry.key);
			}
			foreach (var wid in to_remove) {
				window_locked_launcher_uris.unset (wid);
				if (window_locked_display_names != null)
					window_locked_display_names.unset (wid);
			}
		}

		public static void init_browser_profile_tracking ()
		{
			ensure_browser_tracking_maps ();
			ensure_dbusmenu_listener ();
		}

		private static int resolve_pid_for_dbus_sender (string sender_name)
		{
			if (sender_name == "")
				return 0;
			ensure_browser_tracking_maps ();
			if (dbus_sender_to_pid.has_key (sender_name)) {
				int cached = dbus_sender_to_pid.get (sender_name);
				return cached > 0 ? cached : 0;
			}
			if (dbus_sender_to_pid.size > 4096)
				dbus_sender_to_pid.clear ();
			try {
				var bus = GLib.Bus.get_sync (GLib.BusType.SESSION);
				var res = bus.call_sync (
					"org.freedesktop.DBus",
					"/org/freedesktop/DBus",
					"org.freedesktop.DBus",
					"GetConnectionUnixProcessID",
					new GLib.Variant ("(s)", sender_name),
					new GLib.VariantType ("(u)"),
					GLib.DBusCallFlags.NONE,
					50,
					null
				);
				uint upid = 0;
				res.get ("(u)", out upid);
				if (upid > 0) {
					int pid = (int) upid;
					dbus_sender_to_pid.set (sender_name, pid);
					return pid;
				}
			} catch (Error e) { }
			dbus_sender_to_pid.set (sender_name, -1);
			return 0;
		}

		private static int parse_dbus_unique_conn_serial (string name)
		{
			if (!name.has_prefix (":1."))
				return int.MAX;
			return int.parse (name.substring (3));
		}

		private static string resolve_dbus_dest_for_pid (int pid)
		{
			if (pid <= 0)
				return "";
			ensure_browser_tracking_maps ();
			if (pid_to_dbus_sender.has_key (pid)) {
				string cached_dest = pid_to_dbus_sender.get (pid);
				if (cached_dest != null && cached_dest != "" && !dead_dbus_senders.contains (cached_dest))
					return cached_dest;
				pid_to_dbus_sender.unset (pid);
			}

			try {
				var bus = GLib.Bus.get_sync (GLib.BusType.SESSION);
				var names_res = bus.call_sync (
					"org.freedesktop.DBus",
					"/org/freedesktop/DBus",
					"org.freedesktop.DBus",
					"ListNames",
					null,
					new GLib.VariantType ("(as)"),
					GLib.DBusCallFlags.NONE,
					100,
					null
				);
				string[] names = names_res.get_child_value (0).get_strv ();
				var matching_conns = new Gee.ArrayList<string> ();
				for (int i = 0; i < names.length; i++) {
					unowned string n = names[i];
					if (!n.has_prefix (":1.") || dead_dbus_senders.contains (n))
						continue;
					int npid = resolve_pid_for_dbus_sender (n);
					if (npid == pid)
						matching_conns.add (n);
				}
				// Sort in ASCENDING connection serial order (:1.699 before :1.701..:1.705):
				// Chromium creates its main UI thread D-Bus connection FIRST at startup, whereas higher-numbered
				// connections belong to worker/portal/audio threads that may not dispatch D-Bus calls.
				matching_conns.sort ((a, b) => {
					int sa = parse_dbus_unique_conn_serial (a);
					int sb = parse_dbus_unique_conn_serial (b);
					return (sa < sb) ? -1 : ((sa > sb) ? 1 : 0);
				});
				int max_probe = int.min (matching_conns.size, 2);
				for (int idx = 0; idx < max_probe; idx++) {
					string n = matching_conns[idx];
					try {
						var intro = bus.call_sync (
							n,
							"/com/canonical/menu",
							"org.freedesktop.DBus.Introspectable",
							"Introspect",
							null,
							new GLib.VariantType ("(s)"),
							GLib.DBusCallFlags.NONE,
							60,
							null
						);
						string xml;
						intro.get ("(s)", out xml);
						if (xml.contains ("<node name=")) {
							pid_to_dbus_sender.set (pid, n);
							return n;
						}
					} catch (Error e) {
						if (idx > 0)
							dead_dbus_senders.add (n);
					}
				}
			} catch (Error e) { }
			return "";
		}

		private static void ensure_dbusmenu_listener ()
		{
			if (dbusmenu_signal_sub_id > 0)
				return;
			try {
				var bus = GLib.Bus.get_sync (GLib.BusType.SESSION);
				dbusmenu_signal_sub_id = bus.signal_subscribe (
					null,
					"com.canonical.dbusmenu",
					"LayoutUpdated",
					null,
					null,
					GLib.DBusSignalFlags.NONE,
					on_dbusmenu_layout_updated
				);
			} catch (Error e) { }
		}

		private static Gee.ArrayList<string> list_all_chrome_menu_paths (int pid, string? explicit_dest = null)
		{
			var result = new Gee.ArrayList<string> ();
			if (pid <= 0)
				return result;
			string dest = (explicit_dest != null && explicit_dest != "") ? explicit_dest : resolve_dbus_dest_for_pid (pid);
			if (dest == "")
				return result;
			try {
				var bus = GLib.Bus.get_sync (GLib.BusType.SESSION);
				var intro_res = bus.call_sync (
					dest,
					"/com/canonical/menu",
					"org.freedesktop.DBus.Introspectable",
					"Introspect",
					null,
					new GLib.VariantType ("(s)"),
					GLib.DBusCallFlags.NONE,
					80,
					null
				);
				string xml;
				intro_res.get ("(s)", out xml);

				int search_pos = 0;
				while (search_pos < xml.length) {
					int node_idx = xml.index_of ("<node name=\"", search_pos);
					if (node_idx < 0)
						break;
					int q_start = node_idx + 12;
					int q_end = xml.index_of_char ('"', q_start);
					if (q_end <= q_start)
						break;
					string node_name = xml.substring (q_start, q_end - q_start);
					search_pos = q_end + 1;
					if (node_name == "")
						continue;
					uint64 node_num = 0;
					if (!uint64.try_parse (node_name, out node_num, null, 16) || node_num == 0)
						continue;
					string path = "/com/canonical/menu/" + node_name;
					if (!result.contains (path))
						result.add (path);
				}

				result.sort ((a, b) => {
					uint64 na = 0;
					uint64 nb = 0;
					uint64.try_parse (a.substring ("/com/canonical/menu/".length), out na, null, 16);
					uint64.try_parse (b.substring ("/com/canonical/menu/".length), out nb, null, 16);
					if (na < nb) return -1;
					if (na > nb) return 1;
					return 0;
				});
			} catch (Error e) {
				if (pid_to_dbus_sender != null && pid_to_dbus_sender.has_key (pid) && pid_to_dbus_sender.get (pid) == dest)
					pid_to_dbus_sender.unset (pid);
			}
			return result;
		}

		private static string query_chrome_current_dbus_profile (int pid, string? explicit_dest = null)
		{
			var all_menus = list_all_chrome_menu_paths (pid, explicit_dest);
			for (int i = all_menus.size - 1; i >= 0; i--) {
				string? menu_path = all_menus[i];
				if (menu_path == null || menu_path == "")
					continue;
				string? prof = query_chrome_dbus_profile_at_path (pid, menu_path, explicit_dest);
				if (prof != null && prof != "")
					return prof;
			}
			return "";
		}

		private static string find_unassigned_fd_profile_for_pid (int pid, string exclude_wid)
		{
			if (pid <= 0)
				return "";
			ensure_browser_tracking_maps ();
			var fd_profs = extract_open_chrome_profiles_from_proc_fds (pid, "");
			if (fd_profs.size == 0)
				return "";

			var assigned = new Gee.ArrayList<string> ();
			foreach (var wid in open_browser_window_order) {
				if (wid == exclude_wid)
					continue;
				if (open_browser_window_pids.has_key (wid) && open_browser_window_pids.get (wid) == pid) {
					if (window_browser_profiles.has_key (wid)) {
						string p = window_browser_profiles.get (wid);
						if (p != "" && p != "__webapp__")
							assigned.add (p);
					}
				}
			}

			foreach (var fp in fd_profs) {
				bool used = false;
				foreach (var ap in assigned) {
					if (profiles_match (fp, ap)) {
						used = true;
						break;
					}
				}
				if (!used)
					return fp;
			}
			return "";
		}

		private static bool is_profile_assigned_to_other_window (int pid, string exclude_wid, string prof)
		{
			if (pid <= 0 || prof == "")
				return false;
			ensure_browser_tracking_maps ();
			foreach (var wid in open_browser_window_order) {
				if (wid == exclude_wid)
					continue;
				if (open_browser_window_pids.has_key (wid) && open_browser_window_pids.get (wid) == pid) {
					if (window_browser_profiles.has_key (wid)) {
						string p = window_browser_profiles.get (wid);
						if (p != "" && p != "__webapp__" && profiles_match (p, prof))
							return true;
					}
				}
			}
			return false;
		}

		private static string resolve_profile_for_window (string wid, int pid, string cmdline, bool allow_cmdline_fallback,
			string? explicit_dest = null, string? signal_menu_path = null, out bool is_authoritative = null)
		{
			is_authoritative = false;
			if (pid <= 0)
				return "";
			ensure_browser_tracking_maps ();

			int other_open_count = 0;
			foreach (var owid in open_browser_window_order) {
				if (owid == wid)
					continue;
				if (open_browser_window_pids.has_key (owid) && open_browser_window_pids.get (owid) == pid) {
					if (!window_browser_profiles.has_key (owid) || window_browser_profiles.get (owid) != "__webapp__")
						other_open_count++;
				}
			}

			// 1. First window of a brand-new browser process: explicit --profile-directory on its command line
			// is 100% authoritative for this first window and must never be overridden by background FDs.
			if (other_open_count == 0 && allow_cmdline_fallback) {
				string cmd_prof = extract_cmdline_profile_dir (cmdline);
				if (cmd_prof != "") {
					is_authoritative = true;
					return cmd_prof;
				}
			}

			string unassigned_fd = find_unassigned_fd_profile_for_pid (pid, wid);
			string dbus_prof = "";
			if (signal_menu_path != null && signal_menu_path != "")
				dbus_prof = query_chrome_dbus_profile_at_path (pid, signal_menu_path, explicit_dest);
			if (dbus_prof == "")
				dbus_prof = query_chrome_current_dbus_profile (pid, explicit_dest);

			if (other_open_count > 0) {
				if (unassigned_fd != "") {
					is_authoritative = true;
					return unassigned_fd;
				}
				if (dbus_prof != "" && !is_profile_assigned_to_other_window (pid, wid, dbus_prof)) {
					is_authoritative = true;
					return dbus_prof;
				}
				return "";
			}

			if (dbus_prof != "") {
				is_authoritative = true;
				return dbus_prof;
			}
			if (unassigned_fd != "") {
				is_authoritative = true;
				return unassigned_fd;
			}
			return "";
		}

		private static bool refresh_recent_window_for_pid (int pid, string? explicit_dest = null, string? signal_menu_path = null)
		{
			if (pid <= 0)
				return false;
			ensure_browser_tracking_maps ();

			string? wid = newest_window_for_pid.has_key (pid) ? newest_window_for_pid.get (pid) : null;
			if (wid == null || wid == "" || !open_browser_window_pids.has_key (wid))
				return false;

			if (!unresolved_browser_windows.has_key (wid))
				return false;

			bool is_auth = false;
			string resolved = resolve_profile_for_window (wid, pid, "", false, explicit_dest, signal_menu_path, out is_auth);
			if (resolved == "")
				return false;

			string prev = window_browser_profiles.has_key (wid) ? window_browser_profiles.get (wid) : "";
			if (is_auth)
				unresolved_browser_windows.unset (wid);

			if (prev == "" || !profiles_match (prev, resolved)) {
				window_browser_profiles.set (wid, resolved);
				window_locked_launcher_uris.unset (wid);
				window_locked_display_names.unset (wid);
				return true;
			}
			return false;
		}

		private static void schedule_browser_profile_followup (int pid)
		{
			if (pid <= 0)
				return;
			GLib.Timeout.add (120, () => {
				if (refresh_recent_window_for_pid (pid))
					WindowManager.get_default ().on_browser_profile_resolved ();
				return false;
			});
			GLib.Timeout.add (300, () => {
				if (refresh_recent_window_for_pid (pid))
					WindowManager.get_default ().on_browser_profile_resolved ();
				return false;
			});
			GLib.Timeout.add (650, () => {
				bool changed = refresh_recent_window_for_pid (pid);
				if (newest_window_for_pid != null && newest_window_for_pid.has_key (pid)) {
					string wid = newest_window_for_pid.get (pid);
					if (open_browser_window_pids != null && open_browser_window_pids.has_key (wid)) {
						if (window_browser_profiles == null || !window_browser_profiles.has_key (wid) || window_browser_profiles.get (wid) == "") {
							string fb = find_unassigned_fd_profile_for_pid (pid, wid);
							if (fb == "")
								fb = query_chrome_current_dbus_profile (pid);
							if (fb == "")
								fb = get_fallback_default_profile ();
							if (fb != "") {
								window_browser_profiles.set (wid, fb);
								window_locked_launcher_uris.unset (wid);
								window_locked_display_names.unset (wid);
								changed = true;
							}
						}
						if (unresolved_browser_windows != null)
							unresolved_browser_windows.unset (wid);
					}
				}
				if (changed)
					WindowManager.get_default ().on_browser_profile_resolved ();
				return false;
			});
		}

		private static void on_dbusmenu_layout_updated (GLib.DBusConnection conn, string? sender_name,
			string object_path, string interface_name, string signal_name, GLib.Variant parameters)
		{
			if (sender_name == null || sender_name == "" || !object_path.has_prefix ("/com/canonical/menu/"))
				return;
			ensure_browser_tracking_maps ();

			int sender_pid = resolve_pid_for_dbus_sender (sender_name);
			if (sender_pid <= 0)
				return;
			pid_to_dbus_sender.set (sender_pid, sender_name);

			if (!open_browser_window_pids.values.contains (sender_pid) && !ever_seen_browser_pids.contains (sender_pid))
				return;

			if (refresh_recent_window_for_pid (sender_pid, sender_name, object_path))
				WindowManager.get_default ().on_browser_profile_resolved ();
		}

		private static string query_chrome_dbus_profile_at_path (int pid, string menu_path, string? explicit_dest = null)
		{
			if (pid <= 0 || menu_path == "")
				return "";
			string dest = (explicit_dest != null && explicit_dest != "") ? explicit_dest : resolve_dbus_dest_for_pid (pid);
			if (dest == "")
				return "";
			try {
				var bus = GLib.Bus.get_sync (GLib.BusType.SESSION);
				string[] prop_names = { "label", "toggle-type", "toggle-state" };
				var res = bus.call_sync (
					dest,
					menu_path,
					"com.canonical.dbusmenu",
					"GetLayout",
					new GLib.Variant ("(ii^as)", 0, -1, prop_names),
					new GLib.VariantType ("(u(ia{sv}av))"),
					GLib.DBusCallFlags.NONE,
					80,
					null
				);
				uint rev;
				GLib.Variant root_item;
				res.get ("(u@(ia{sv}av))", out rev, out root_item);

				int root_id;
				GLib.Variant root_props;
				GLib.VariantIter top_children;
				root_item.get ("(i@a{sv}av)", out root_id, out root_props, out top_children);

				ensure_chrome_local_state_loaded ();
				GLib.Variant? sub_var = null;
				while (top_children.next ("v", out sub_var)) {
					if (sub_var == null)
						continue;
					int sub_id;
					GLib.Variant sub_props;
					GLib.VariantIter item_iter;
					sub_var.get ("(i@a{sv}av)", out sub_id, out sub_props, out item_iter);

					bool has_profile_checkmarks = (sub_id == 61);
					string checked_label = "";
					GLib.Variant? child_var = null;
					while (item_iter.next ("v", out child_var)) {
						if (child_var == null)
							continue;
						int cid;
						GLib.Variant cprops;
						GLib.VariantIter dummy_iter;
						child_var.get ("(i@a{sv}av)", out cid, out cprops, out dummy_iter);
						string? ttype = null;
						cprops.lookup ("toggle-type", "s", out ttype);
						if (ttype == "checkmark") {
							string? lbl = null;
							cprops.lookup ("label", "s", out lbl);
							string clean_lbl = (lbl != null) ? lbl.strip ().replace ("_", "") : "";
							if (clean_lbl != "" && profile_label_to_dir != null) {
								string ldown = clean_lbl.down ();
								string lnorm = normalize_profile_token (clean_lbl);
								if (profile_label_to_dir.has_key (ldown) || profile_label_to_dir.has_key (lnorm))
									has_profile_checkmarks = true;
							}
							int tstate = 0;
							cprops.lookup ("toggle-state", "i", out tstate);
							if (tstate == 1 && clean_lbl != "")
								checked_label = clean_lbl;
						}
					}
					if (has_profile_checkmarks && checked_label != "") {
						if (profile_label_to_dir != null) {
							string ldown = checked_label.down ();
							if (profile_label_to_dir.has_key (ldown))
								return profile_label_to_dir.get (ldown);
							string lnorm = normalize_profile_token (checked_label);
							if (profile_label_to_dir.has_key (lnorm))
								return profile_label_to_dir.get (lnorm);
						}
						return checked_label;
					}
				}
			} catch (Error e) { }
			return "";
		}

		private static int64 extract_session_file_timestamp (string rest)
		{
			int idx = rest.index_of ("/Sessions/Session_");
			int prefix_len = "/Sessions/Session_".length;
			if (idx < 0) {
				idx = rest.index_of ("/Sessions/Tabs_");
				prefix_len = "/Sessions/Tabs_".length;
			}
			if (idx < 0)
				return -1;
			string tail = rest.substring (idx + prefix_len);
			var sb = new GLib.StringBuilder ();
			for (int i = 0; i < tail.length; i++) {
				char c = tail[i];
				if (c >= '0' && c <= '9')
					sb.append_c (c);
				else
					break;
			}
			if (sb.len == 0)
				return 0;
			return int64.parse (sb.str);
		}

		private static Gee.ArrayList<string> extract_open_chrome_profiles_from_proc_fds (int pid, string first_cmd_prof)
		{
			var result = new Gee.ArrayList<string> ();
			if (first_cmd_prof != "")
				result.add (first_cmd_prof);
			if (pid <= 0)
				return result;

			try {
				ensure_chrome_local_state_loaded ();
				string fd_dir_path = "/proc/%d/fd".printf (pid);
				var dir = GLib.Dir.open (fd_dir_path, 0);
				var session_prof_ts = new Gee.HashMap<string, int64?> ();
				string? name = null;
				while ((name = dir.read_name ()) != null) {
					int fd_num = int.parse (name);
					if (fd_num <= 0)
						continue;
					string link_target = GLib.FileUtils.read_link (GLib.Path.build_filename (fd_dir_path, name));
					int marker_idx = link_target.index_of ("/google-chrome/");
					int marker_len = "/google-chrome/".length;
					if (marker_idx < 0) {
						marker_idx = link_target.index_of ("/chromium/");
						marker_len = "/chromium/".length;
					}
					if (marker_idx < 0)
						continue;
					string rest = link_target.substring (marker_idx + marker_len);
					int slash = rest.index_of_char ('/');
					if (slash <= 0)
						continue;
					string sub = rest.substring (0, slash);
					if (sub == "Default" || sub.has_prefix ("Profile ")) {
						int64 ts = extract_session_file_timestamp (rest);
						if (ts >= 0) {
							int64 prev_ts = session_prof_ts.has_key (sub) ? session_prof_ts.get (sub) : -1;
							if (prev_ts < 0 || (ts > 0 && ts < prev_ts))
								session_prof_ts.set (sub, ts);
						}
					}
				}

				var sorted_profs = new Gee.ArrayList<string> ();
				foreach (var k in session_prof_ts.keys)
					sorted_profs.add (k);
				sorted_profs.sort ((a, b) => {
					int64 ta = session_prof_ts.get (a);
					int64 tb = session_prof_ts.get (b);
					return (ta < tb) ? -1 : ((ta > tb) ? 1 : 0);
				});

				foreach (var p in sorted_profs) {
					bool already = false;
					foreach (var existing in result) {
						if (profiles_match (existing, p)) {
							already = true;
							break;
						}
					}
					if (!already)
						result.add (p);
				}
			} catch (Error e) { }
			return result;
		}

		public static void scan_initial_windows (Gee.ArrayList<WindowInfo> windows)
		{
			init_browser_profile_tracking ();

			var pid_windows = new Gee.HashMap<int, Gee.ArrayList<WindowInfo>> ();
			foreach (var w in windows) {
				if (w.Id == "" || w.Pid <= 0)
					continue;
				if (has_explicit_webapp_window_id (w)) {
					ever_seen_browser_pids.add (w.Pid);
					if (!open_browser_window_order.contains (w.Id))
						open_browser_window_order.add (w.Id);
					open_browser_window_pids.set (w.Id, w.Pid);
					window_browser_profiles.set (w.Id, "__webapp__");
					continue;
				}
				if (!is_plain_browser_window (w))
					continue;
				ever_seen_browser_pids.add (w.Pid);
				if (!open_browser_window_order.contains (w.Id))
					open_browser_window_order.add (w.Id);
				open_browser_window_pids.set (w.Id, w.Pid);

				Gee.ArrayList<WindowInfo>? list = pid_windows.get (w.Pid);
				if (list == null) {
					list = new Gee.ArrayList<WindowInfo> ();
					pid_windows.set (w.Pid, list);
				}
				list.add (w);
			}

			foreach (var entry in pid_windows.entries) {
				int pid = entry.key;
				var group = entry.value;
				if (group.size >= 2)
					multi_window_browser_pids.add (pid);

				string dbus_prof = query_chrome_current_dbus_profile (pid);
				string cmd_prof = extract_cmdline_profile_dir (group[0].Cmdline);
				var fd_profs = extract_open_chrome_profiles_from_proc_fds (pid, cmd_prof);

				if (group.size == 1) {
					var w0 = group[0];
					string resolved = dbus_prof;
					if (resolved == "" && fd_profs.size > 0)
						resolved = fd_profs[0];
					if (resolved == "")
						resolved = cmd_prof != "" ? cmd_prof : get_fallback_default_profile ();
					window_browser_profiles.set (w0.Id, resolved);
				} else if (group.size >= 2) {
					string active_wid = "";
					if (dbus_prof != "") {
						foreach (var wi in group) {
							if (wi.Active) {
								window_browser_profiles.set (wi.Id, dbus_prof);
								active_wid = wi.Id;
								break;
							}
						}
					}
					int fd_idx = 0;
					for (int i = 0; i < group.size; i++) {
						var wi = group[i];
						if (wi.Id == active_wid)
							continue;
						while (fd_idx < fd_profs.size && active_wid != "" && profiles_match (fd_profs[fd_idx], dbus_prof))
							fd_idx++;
						string assigned_prof = (fd_idx < fd_profs.size)
							? fd_profs[fd_idx++]
							: (fd_profs.size > 0 ? fd_profs[fd_profs.size - 1] : (dbus_prof != "" ? dbus_prof : get_fallback_default_profile ()));
						window_browser_profiles.set (wi.Id, assigned_prof);
					}
				}
			}

			// Identify and lock every initial window ONCE
			foreach (var w in windows) {
				if (w.Id != "")
					get_locked_window_launcher_uri (w);
			}
		}

		public static void on_window_opened (WindowInfo window, bool is_initial_batch = false, int same_pid_browser_count = 1, int same_pid_browser_index = 0)
		{
			init_browser_profile_tracking ();

			if (window.Id == "" || window.Pid <= 0)
				return;
			if (has_explicit_webapp_window_id (window)) {
				ever_seen_browser_pids.add (window.Pid);
				if (!open_browser_window_pids.has_key (window.Id)) {
					open_browser_window_order.add (window.Id);
					open_browser_window_pids.set (window.Id, window.Pid);
					window_browser_profiles.set (window.Id, "__webapp__");
				}
				get_locked_window_launcher_uri (window);
				return;
			}
			if (!is_plain_browser_window (window)) {
				get_locked_window_launcher_uri (window);
				return;
			}
			if (open_browser_window_pids.has_key (window.Id))
				return;

			bool is_brand_new_browser_pid = !ever_seen_browser_pids.contains (window.Pid);
			ever_seen_browser_pids.add (window.Pid);

			int existing_for_pid = 0;
			foreach (var wid in open_browser_window_order) {
				if (open_browser_window_pids.has_key (wid) && open_browser_window_pids.get (wid) == window.Pid) {
					if (!window_browser_profiles.has_key (wid) || window_browser_profiles.get (wid) != "__webapp__")
						existing_for_pid++;
				}
			}
			if (!is_brand_new_browser_pid || existing_for_pid > 0 || same_pid_browser_count > 1)
				multi_window_browser_pids.add (window.Pid);

			open_browser_window_order.add (window.Id);
			open_browser_window_pids.set (window.Id, window.Pid);
			unresolved_browser_windows.set (window.Id, window.Pid);
			window_open_time_us.set (window.Id, GLib.get_monotonic_time ());
			newest_window_for_pid.set (window.Pid, window.Id);

			bool allow_cmdline = is_brand_new_browser_pid && existing_for_pid == 0 && same_pid_browser_count <= 1;
			bool is_auth = false;
			string prof = resolve_profile_for_window (window.Id, window.Pid, window.Cmdline, allow_cmdline, null, null, out is_auth);
			if (prof != "") {
				window_browser_profiles.set (window.Id, prof);
				if (is_auth)
					unresolved_browser_windows.unset (window.Id);
			}

			get_locked_window_launcher_uri (window);
			if (unresolved_browser_windows.has_key (window.Id))
				schedule_browser_profile_followup (window.Pid);
		}

		public static void resolve_unresolved_browser_windows ()
		{
			if (unresolved_browser_windows == null || unresolved_browser_windows.size == 0)
				return;
			var pending_pids = new Gee.HashSet<int> ();
			foreach (int p in unresolved_browser_windows.values) {
				if (p > 0)
					pending_pids.add (p);
			}
			foreach (int p in pending_pids)
				refresh_recent_window_for_pid (p);
		}

		public static void on_window_closed (string window_id)
		{
			int closed_pid = 0;
			if (open_browser_window_pids != null && open_browser_window_pids.has_key (window_id))
				closed_pid = open_browser_window_pids.get (window_id);
			int closed_term_pid = 0;
			if (open_terminal_window_pids != null && open_terminal_window_pids.has_key (window_id)) {
				closed_term_pid = open_terminal_window_pids.get (window_id);
				open_terminal_window_pids.unset (window_id);
			}
			if (window_browser_profiles != null)
				window_browser_profiles.unset (window_id);
			if (window_locked_launcher_uris != null)
				window_locked_launcher_uris.unset (window_id);
			if (window_locked_display_names != null)
				window_locked_display_names.unset (window_id);
			if (window_open_time_us != null)
				window_open_time_us.unset (window_id);
			if (newest_window_for_pid != null && closed_pid > 0 && newest_window_for_pid.get (closed_pid) == window_id)
				newest_window_for_pid.unset (closed_pid);
			if (unresolved_browser_windows != null)
				unresolved_browser_windows.unset (window_id);
			if (open_browser_window_order != null)
				open_browser_window_order.remove (window_id);
			if (open_browser_window_pids != null)
				open_browser_window_pids.unset (window_id);
			if (closed_pid > 0 && open_browser_window_pids != null) {
				bool has_remaining_plain_browser = false;
				foreach (var rem_wid in open_browser_window_order) {
					if (open_browser_window_pids.has_key (rem_wid) && open_browser_window_pids.get (rem_wid) == closed_pid) {
						if (!window_browser_profiles.has_key (rem_wid) || window_browser_profiles.get (rem_wid) != "__webapp__") {
							has_remaining_plain_browser = true;
							break;
						}
					}
				}
				if (!has_remaining_plain_browser) {
					if (multi_window_browser_pids != null)
						multi_window_browser_pids.remove (closed_pid);
					if (ever_seen_browser_pids != null)
						ever_seen_browser_pids.remove (closed_pid);
					if (pid_to_dbus_sender != null)
						pid_to_dbus_sender.unset (closed_pid);
				}
			}
			if (terminal_cmdline_owner_wid != null) {
				var cmd_pids_to_remove = new Gee.ArrayList<int> ();
				foreach (var entry in terminal_cmdline_owner_wid.entries) {
					if (entry.value == window_id)
						cmd_pids_to_remove.add (entry.key);
				}
				foreach (int p in cmd_pids_to_remove)
					terminal_cmdline_owner_wid.unset (p);
			}
			if (closed_term_pid > 0 && open_terminal_window_pids != null && !open_terminal_window_pids.values.contains (closed_term_pid)) {
				if (!GLib.FileUtils.test ("/proc/%d".printf (closed_term_pid), GLib.FileTest.EXISTS) && terminal_cmdline_consumed_pids != null)
					terminal_cmdline_consumed_pids.remove (closed_term_pid);
			}
			if (terminal_child_pid_owner_wid != null) {
				var child_pids_to_remove = new Gee.ArrayList<int> ();
				foreach (var entry in terminal_child_pid_owner_wid.entries) {
					if (entry.value == window_id)
						child_pids_to_remove.add (entry.key);
				}
				foreach (int cp in child_pids_to_remove)
					terminal_child_pid_owner_wid.unset (cp);
			}
		}

		public static string get_window_browser_profile (WindowInfo window)
		{
			if (window_browser_profiles != null && window.Id != "" && window_browser_profiles.has_key (window.Id)) {
				string? p = window_browser_profiles.get (window.Id);
				if (p == null || p == "" || p == "__webapp__")
					return "";
				return p;
			}
			return "";
		}

		public static bool is_window_profile_pending (WindowInfo window)
		{
			if (window.Id == "")
				return false;
			return unresolved_browser_windows != null && unresolved_browser_windows.has_key (window.Id);
		}

		public static bool is_uri_locked_by_any_window (string uri)
		{
			if (uri == null || uri == "" || window_locked_launcher_uris == null)
				return false;
			return window_locked_launcher_uris.values.contains (uri);
		}

		/**
		 * GLOBAL SINGLE SOURCE OF TRUTH: Identifies a window ONCE and locks its canonical .desktop URI
		 * for the entire lifetime of window.Id until on_window_closed(window.Id).
		 */
		public static string get_locked_window_launcher_uri (WindowInfo window)
		{
			ensure_browser_tracking_maps ();
			if (window.Id == "")
				return "";
			bool is_plain_browser = is_plain_browser_window (window) && !has_explicit_webapp_window_id (window);
			bool is_term = is_terminal_window (window);
			if (!is_plain_browser && !is_term)
				return "";
			if (window_locked_launcher_uris.has_key (window.Id)) {
				string? cached_uri = window_locked_launcher_uris.get (window.Id);
				if (cached_uri != null && cached_uri != "")
					return cached_uri;
			}

			var desktop_file = ApplicationDiscovery.get_default ().compute_best_desktop_file_for_window (window);
			if (desktop_file == null)
				return "";
			string? uri = desktop_file.get_uri ();
			if (uri != null && uri != "") {
				bool can_lock = true;
				if (is_plain_browser && is_window_profile_pending (window))
					can_lock = false;
				else if (is_term && !is_terminal_window_child_ready (window))
					can_lock = false;

				if (can_lock)
					window_locked_launcher_uris.set (window.Id, uri);

				string? prof = get_window_browser_profile (window);
				if (prof != null && prof != "") {
					string? disp = format_chrome_profile_identity_name (prof);
					if (disp != null && disp != "")
						window_locked_display_names.set (window.Id, disp);
				}
				return uri;
			}
			return "";
		}

		public static string get_locked_window_display_name (WindowInfo window)
		{
			ensure_browser_tracking_maps ();
			if (window.Id != "" && window_locked_display_names.has_key (window.Id)) {
				string? cached_disp = window_locked_display_names.get (window.Id);
				if (cached_disp != null && cached_disp != "")
					return cached_disp;
			}
			string? prof = get_window_browser_profile (window);
			if (prof != null && prof != "") {
				string? disp = format_chrome_profile_identity_name (prof);
				if (disp != null && disp != "" && window.Id != "") {
					window_locked_display_names.set (window.Id, disp);
					return disp;
				}
			}
			return "";
		}

		/**
		 * Central identity provider for external consumers (e.g. MprisDockItem) so docklets
		 * receive the resolved identity from ApplicationIdentity instead of searching on their own.
		 */
		public static string get_identity_for_pid_or_bus (int pid, string bus_name, string raw_identity)
		{
			ensure_browser_tracking_maps ();
			int target_pid = pid;
			if (target_pid <= 0 && bus_name != "") {
				int inst_idx = bus_name.index_of (".instance");
				if (inst_idx > 0 && inst_idx + 9 < bus_name.length) {
					target_pid = int.parse (bus_name.substring (inst_idx + 9));
				}
			}
			if (target_pid > 0) {
				var prof_labels = new Gee.ArrayList<string> ();
				foreach (var wid in open_browser_window_order) {
					if (open_browser_window_pids.has_key (wid) && open_browser_window_pids.get (wid) == target_pid) {
						if (window_browser_profiles.has_key (wid)) {
							string fmt = format_chrome_profile_identity_name (window_browser_profiles.get (wid));
							if (fmt != "" && !prof_labels.contains (fmt))
								prof_labels.add (fmt);
						}
					}
				}
				if (prof_labels.size == 1)
					return prof_labels[0];
			}
			if (raw_identity.strip () != "")
				return raw_identity.strip ();
			string clean = bus_name.has_prefix ("org.mpris.MediaPlayer2.")
				? bus_name.substring ("org.mpris.MediaPlayer2.".length)
				: bus_name;
			int idx = clean.index_of (".instance");
			if (idx > 0)
				clean = clean.substring (0, idx);
			if (clean.length > 0)
				return clean.substring (0, 1).ascii_up () + clean.substring (1);
			return _("Media Player");
		}

		private static string extract_window_pwa_profile (WindowInfo window, string pwa_id)
		{
			string marker = pwa_id + "-";
			var win_ids = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
			foreach (var wid in win_ids) {
				if (wid == null || wid == "")
					continue;
				var norm = normalize (wid);
				int idx = norm.index_of (marker);
				if (idx >= 0 && idx + marker.length < norm.length) {
					return norm.substring (idx + marker.length);
				}
			}
			return "";
		}

		private static string[] parse_cmdline_argv (string cmdline)
		{
			if (cmdline.strip () == "")
				return {};
			string[] argv;
			try {
				if (GLib.Shell.parse_argv (cmdline.strip (), out argv))
					return argv;
			} catch (Error e) { }
			return cmdline.strip ().split (" ");
		}

		private static bool window_is_incognito (WindowInfo window)
		{
			if (window.Caption == "")
				return cmdline_has_incognito_flag (window.Cmdline);
			var cap = window.Caption.down ();
			return cap.contains ("(incognito)") ||
			       cap.contains ("(navigazione in incognito)") ||
			       cap.contains ("(navigazione privata)") ||
			       cap.contains ("(inprivate)") ||
			       cap.contains ("(private browsing)") ||
			       cap.contains ("(private)") ||
			       cap.contains ("(incógnito)") ||
			       cap.contains ("(navegación privada)") ||
			       cap.contains ("(navigation privée)") ||
			       cap.contains ("(inkognito)") ||
			       cap.contains ("(privater modus)") ||
			       cap.contains ("(incògnit)") ||
			       cap.contains ("(navegació privada)") ||
			       cap.contains ("(анонімного перегляду)") ||
			       cap.contains ("(режим анонімного перегляду)") ||
			       cap.contains ("(приватний перегляд)") ||
			       cap.contains ("(无痕模式)") ||
			       cap.contains ("(隐私浏览)");
		}

		private static bool cmdline_has_incognito_flag (string cmdline)
		{
			if (cmdline == "")
				return false;
			foreach (var raw_tok in parse_cmdline_argv (cmdline)) {
				var tok = raw_tok.strip ().replace ("\"", "").replace ("'", "").down ();
				if (is_incognito_switch (tok))
					return true;
			}
			return false;
		}

		private static bool window_matches_browser_arg (WindowInfo window, string[] win_argv, string spec)
		{
			int eq = spec.index_of_char ('=');
			if (eq <= 0)
				return false;
			string kind = spec.substring (0, eq);
			string target = spec.substring (eq + 1);
			if (target == "")
				return false;

			string win_dbus_prof = get_window_browser_profile (window);
			if (win_dbus_prof != "") {
				if (kind == "profile-dir")
					return profiles_match (win_dbus_prof, target);
				if (kind == "user-agent") {
					string cmd_prof = extract_cmdline_profile_dir (window.Cmdline);
					if (cmd_prof != "" && !profiles_match (win_dbus_prof, cmd_prof))
						return false;
				}
			}

			if (kind == "class") {
				var norm_cls = normalize (target);
				var win_ids = new string?[] { window.ApplicationId, window.ResourceClass, window.ResourceName, window.DesktopFileName };
				foreach (var wid in win_ids) {
					if (wid != null && wid != "" && (wid.down () == target || normalize (wid) == norm_cls))
						return true;
				}
			}

			bool saw_explicit_profile_flag = false;
			for (int i = 0; i < win_argv.length; i++) {
				string tok = win_argv[i].strip ().replace ("\"", "").replace ("'", "");
				if (tok == "")
					continue;
				string tok_down = tok.down ();

				if (tok_down.contains ("=")) {
					int teq = tok_down.index_of_char ('=');
					string k = tok_down.substring (0, teq);
					string v = tok_down.substring (teq + 1).strip ();
					if (v == "profile" && i + 1 < win_argv.length) {
						string next_tok = win_argv[i + 1].strip ().replace ("\"", "").replace ("'", "").down ();
						if (next_tok != "" && !next_tok.has_prefix ("-"))
							v = v + " " + next_tok;
					}
					while (v.length > 1 && v.has_suffix ("/"))
						v = v.substring (0, v.length - 1);
					if (k.contains ("user-data-dir") || k.contains ("profile-directory") || k == "--profile" || k == "-profile")
						saw_explicit_profile_flag = true;
					if (kind == "user-data-dir" && k.contains ("user-data-dir") && v == target)
						return true;
					if (kind == "profile-dir" && k.contains ("profile-directory") && profiles_match (v, target))
						return true;
					if (kind == "profile-arg" && k.contains ("profile") && !k.contains ("profile-directory") && v == target)
						return true;
					if (kind == "class" && (k == "--class" || k == "-class") && v == target)
						return true;
					if (kind == "user-agent" && k == "--user-agent" && v == target)
						return true;
					continue;
				}

				if (i + 1 < win_argv.length) {
					string nv = win_argv[i + 1].strip ().replace ("\"", "").replace ("'", "").down ();
					while (nv.length > 1 && nv.has_suffix ("/"))
						nv = nv.substring (0, nv.length - 1);
					if (tok_down == "--user-data-dir" || tok_down == "--profile-directory" || tok == "-P" || tok == "--ProfileManager" || tok_down == "--profile" || tok_down == "-profile")
						saw_explicit_profile_flag = true;
					if (kind == "user-data-dir" && tok_down == "--user-data-dir" && nv == target)
						return true;
					if (kind == "profile-dir" && tok_down == "--profile-directory" && profiles_match (nv, target))
						return true;
					if (kind == "profile-arg" && (tok == "-P" || tok == "--ProfileManager" || tok_down == "--profile" || tok_down == "-profile") && nv == target)
						return true;
					if (kind == "class" && (tok_down == "--class" || tok_down == "-class") && nv == target)
						return true;
					if (kind == "user-agent" && tok_down == "--user-agent" && nv == target)
						return true;
				}
			}

			if (kind == "profile-dir" && target == "default" && win_argv.length > 0 && !saw_explicit_profile_flag)
				return true;

			return false;
		}

		private static bool window_matches_profile_hint (WindowInfo window, string[] win_argv, string profile_hint)
		{
			string clean = expand_shell_path (profile_hint).strip ().replace ("\"", "").replace ("'", "").down ();
			while (clean.length > 1 && clean.has_suffix ("/"))
				clean = clean.substring (0, clean.length - 1);
			if (clean == "")
				return false;
			string win_dbus_prof = get_window_browser_profile (window);
			if (win_dbus_prof != "")
				return profiles_match (win_dbus_prof, clean);
			if (window_matches_browser_arg (window, win_argv, "profile-dir=" + clean) ||
			    window_matches_browser_arg (window, win_argv, "user-data-dir=" + clean) ||
			    window_matches_browser_arg (window, win_argv, "profile-arg=" + clean) ||
			    window_matches_browser_arg (window, win_argv, "class=" + clean))
				return true;
			return false;
		}

		public bool matches_web_app_identity (ApplicationIdentity other)
		{
			if (this == other)
				return true;
			if (!this.is_web_app () || !other.is_web_app ())
				return false;
			if (detected_browser_profile != "" && other.detected_browser_profile != "" &&
			    !profiles_match (detected_browser_profile, other.detected_browser_profile))
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

		public string get_effective_browser_profile (string? browser_profile_hint = null)
		{
			return (browser_profile_hint != null && browser_profile_hint.strip () != "")
				? browser_profile_hint.strip ()
				: detected_browser_profile;
		}

		public int match_score (WindowInfo window, string? browser_profile_hint = null)
		{
			if (is_non_app_desktop || is_browser_url_bookmark)
				return 0;

			string eff_profile = get_effective_browser_profile (browser_profile_hint);

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
				if (pwa_matched) {
					if (eff_profile != "") {
						string win_prof = extract_window_pwa_profile (window, pwa_id);
						if (win_prof != "")
							return profiles_match (eff_profile, win_prof) ? 124 : 119;
					}
					return 120;
				}
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

			// Multi-Component Suite Disjointness Guard (e.g. LibreOffice Writer vs Calc vs Impress sharing soffice.bin):
			// Prevent shared suite binaries from cross-illuminating sibling suite components when the window reports
			// a different component's StartupWMClass / ApplicationId.
			if (is_multi_component_suite && startup_wm_classes.size > 0 && !primary_identity_matched) {
				foreach (var val in primary_values) {
					if (val == null || val == "")
						continue;
					var norm = normalize (val);
					if (norm != "" && (norm.has_prefix ("libreoffice-") || norm.has_prefix ("soffice")))
						return 0;
				}
			}

			// Terminal-Hosted CLI / TUI Application Disambiguation (§3.2.2):
			// When a terminal emulator window executes a child CLI/TUI command (via -e, --command, positional arg,
			// or gnome-terminal-server child process), match the dedicated CLI/TUI launcher at Score 118.
			// Conversely, a non-terminal launcher must NEVER match a terminal window when hosted_tokens does not match!
			if (!is_terminal_emulator_launcher () && is_terminal_window (window)) {
				var hosted_tokens = extract_terminal_hosted_tokens (window);
				if (hosted_tokens.size > 0) {
					bool cmd_matched = false;
					foreach (var dbin in dedicated_binaries) {
						if (hosted_tokens.contains (dbin)) {
							cmd_matched = true;
							break;
						}
					}
					if (!cmd_matched && argument_tokens.size > 0) {
						bool runtime_ok = false;
						foreach (var exe in executable_tokens) {
							if (hosted_tokens.contains (exe)) {
								runtime_ok = true;
								break;
							}
						}
						if (runtime_ok) {
							foreach (var arg in argument_tokens) {
								if (hosted_tokens.contains (arg)) {
									cmd_matched = true;
									break;
								}
							}
						}
					}
					if (cmd_matched)
						return 118;
				}
				return 0;
			}

			// Plain browser & browser profile launchers (e.g. google-chrome.desktop, Chrome.sh, chrome-private.sh, winchrome-syensqo.sh)
			// must NEVER match standalone PWA / --app=URL windows sharing the master browser PID.
			if (has_browser_executable && !is_web_app ()) {
				if (has_explicit_webapp_window_id (window))
					return 0;

				bool has_manual_profile = (browser_profile_hint != null && browser_profile_hint.strip () != "");
				if (required_browser_args.size > 0 || requires_incognito || has_manual_profile) {
					bool browser_base_matches = primary_identity_matched;
					if (!browser_base_matches) {
						var base_values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
						foreach (var val in base_values) {
							if (val != null && val != "") {
								var norm = normalize (val);
								if (tokens.contains (norm) || executable_tokens.contains (norm)) {
									browser_base_matches = true;
									break;
								}
							}
						}
						if (!browser_base_matches && window.Executable != "" && executable_tokens.contains (normalize (window.Executable)))
							browser_base_matches = true;
					}
					if (!browser_base_matches)
						return 0;

					if (requires_incognito) {
						if (required_browser_args.size == 0 && !has_manual_profile) {
							if (!window_is_incognito (window))
								return 0;
						} else if (!window_is_incognito (window) && !cmdline_has_incognito_flag (window.Cmdline)) {
							return 0;
						}
					} else if (window_is_incognito (window)) {
						return 0;
					}

					string win_dbus_prof = get_window_browser_profile (window);
					if (win_dbus_prof != "" && eff_profile != "")
						return profiles_match (eff_profile, win_dbus_prof) ? (primary_identity_matched ? 120 : 118) : 0;

					// Never fall back to shared /proc/<pid>/cmdline on a multi-window browser PID while profile is still pending
					if (window.Pid > 0 && multi_window_browser_pids != null && multi_window_browser_pids.contains (window.Pid))
						return 0;

					if (required_browser_args.size > 0 || has_manual_profile) {
						var win_argv = parse_cmdline_argv (window.Cmdline);
						foreach (var req in required_browser_args) {
							if (has_manual_profile && (req.has_prefix ("profile-dir=") || req.has_prefix ("user-data-dir=") || req.has_prefix ("profile-arg=")))
								continue;
							if (!window_matches_browser_arg (window, win_argv, req))
								return 0;
						}
						if (has_manual_profile && !window_matches_profile_hint (window, win_argv, browser_profile_hint))
							return 0;
					}

					return primary_identity_matched ? 120 : 118;
				}
			}

			// If this launcher has specialized target arguments (e.g. specific VM/file, Wine game, Quake mod),
			// check if the window matches those arguments.
			bool specialized = (argument_tokens.size > 0 || required_mod_tokens.size > 0);
			bool args_matched = false;

			// Guard 1: Argument matching can ONLY apply if the window's underlying application or binary
			// matches this launcher (strictly primary/executable tokens or Wine signature; never word_tokens).
			if (specialized && !primary_identity_matched) {
				bool base_app_matches = false;
				var base_values = new string?[] { window.DesktopFileName, window.ApplicationId, window.ResourceClass, window.ResourceName };
				foreach (var val in base_values) {
					if (val != null && val != "") {
						var norm = normalize (val);
						if (tokens.contains (norm) || executable_tokens.contains (norm)) {
							base_app_matches = true;
							break;
						}
					}
				}
				if (!base_app_matches && window.Executable != "" && executable_tokens.contains (normalize (window.Executable))) {
					base_app_matches = true;
				}
				if (!base_app_matches && has_wine_executable && is_wine_window (window)) {
					base_app_matches = true;
				}

				if (!base_app_matches) {
					return 0;
				}
			}

			var cmdline_norm = window.Cmdline.replace ("\\", "/").down ();
			var cwd_norm = has_wine_executable ? get_process_cwd (window.Pid) : "";

			// Conjunctive Engine Mod Check (e.g. Quake II +set game rogue / xatrix / zaero)
			if (required_mod_tokens.size > 0) {
				if (cmdline_norm == "")
					return 0;
				foreach (var mtok in required_mod_tokens) {
					if (!contains_word (cmdline_norm, mtok) && !cmdline_norm.contains (mtok))
						return 0;
				}
				args_matched = true;
			}

			// Disjunctive Wine .lnk vs Path= Directory & WINEPREFIX Check (§3.2.1)
			if (has_wine_executable && specialized && !args_matched) {
				if (wine_prefix_token != "" && (cmdline_norm != "" || cwd_norm != "")) {
					if (!cmdline_norm.contains (wine_prefix_token) && !cwd_norm.contains (wine_prefix_token))
						return 0;
				}
				if (wine_path_token != "" || wine_lnk_token != "") {
					bool wine_target_ok = false;
					if (wine_path_token != "" && (cmdline_norm.contains (wine_path_token) || cwd_norm.contains (wine_path_token)))
						wine_target_ok = true;
					if (!wine_target_ok && wine_lnk_token != "" && cmdline_norm.contains (wine_lnk_token))
						wine_target_ok = true;
					if (!wine_target_ok) {
						foreach (var val in primary_values) {
							if (val == null || val == "")
								continue;
							var vd = val.down ();
							if ((wine_path_token != "" && vd.contains (wine_path_token)) ||
							    (wine_lnk_token != "" && vd.contains (wine_lnk_token))) {
								wine_target_ok = true;
								break;
							}
						}
					}
					if (wine_target_ok)
						args_matched = true;
				}
			}

			if (specialized && !args_matched && cmdline_norm != "") {
				foreach (var arg in argument_tokens) {
					if (arg.length >= 3 && cmdline_norm.contains (arg)) {
						args_matched = true;
						break;
					}
				}
			}

			if (specialized && !args_matched && cwd_norm != "") {
				foreach (var arg in argument_tokens) {
					if (arg.length >= 3 && cwd_norm.contains (arg)) {
						args_matched = true;
						break;
					}
				}
			}

			// Check window identifiers for PWA hash / argument matches
			// (e.g. crx_mpkgflik... or chrome-mpkgflik... matching argument token mpkgflik...)
			if (specialized && !args_matched) {
				foreach (var arg in argument_tokens) {
					if (arg.length >= 4) {
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

			if (specialized && !args_matched && !has_browser_executable && window.Caption != "") {
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
			var best = (args_matched && primary_identity_matched) ? 120 : (args_matched ? 118 : 0);
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
			if (window.Cmdline != "" && (!is_terminal_window (window) || is_terminal_emulator_launcher ())) {
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
				if (!specialized && required_mod_tokens.size == 0 && best > 85 &&
				    (cmdline_norm.contains ("+set game ") || cmdline_norm.contains ("-set game "))) {
					best = 85;
				}
			}

			// Enforce StartupWMClass disjointness when a terminal emulator wrapper sets a distinct ResourceClass
			// (e.g. UXTerm sets ResourceClass="UXTerm" and ResourceName="xterm", so debian-xterm.desktop with StartupWMClass=XTerm
			// must not tie with debian-uxterm.desktop with StartupWMClass=UXTerm).
			if (is_terminal_emulator_launcher () && startup_wm_classes.size > 0 && window.ResourceClass != "") {
				var norm_rc = normalize (window.ResourceClass);
				if (norm_rc != "" && !startup_wm_classes.contains (norm_rc) && best > 75)
					best = 75;
			}

			// Match window Caption (Title) against desktop Name or tokens with strict word-boundary matching
			if (window.Caption != "") {
				var caption_down = window.Caption.down ();
				if (app_name != "" && app_name.length >= 3 && !is_common_stopword (app_name) && contains_word (caption_down, app_name)) {
					if (window.Executable != "" && executable_tokens.contains (normalize (window.Executable)))
						best = int.max (best, 90);
					else if (executable_tokens.size == 0)
						best = int.max (best, 70);
					else if (window.Executable == "")
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
