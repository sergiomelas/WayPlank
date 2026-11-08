//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
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
	 * On-demand FreeDesktop recent-files jump-list helper backed by Gtk.RecentManager.
	 * Queries `~/.local/share/recently-used.xbel` solely when a context menu is opened
	 * (zero background timers or polling).
	 */
	public class RecentFilesService : GLib.Object
	{
		public const int MAX_RECENT_ITEMS = 10;

		public delegate void ItemActivatedFunc ();

		class RecentCandidate : GLib.Object
		{
			public Gtk.RecentInfo info;
			public string uri;
			public string display_name;
			public GLib.Icon? gicon;
			public int64 modified_ts;
			public bool direct_app_match;

			public RecentCandidate (Gtk.RecentInfo info, string uri, string display_name, GLib.Icon? gicon, int64 modified_ts, bool direct_app_match)
			{
				this.info = info;
				this.uri = uri;
				this.display_name = display_name;
				this.gicon = gicon;
				this.modified_ts = modified_ts;
				this.direct_app_match = direct_app_match;
			}
		}

		static bool is_generic_wrapper_bin (string bin)
		{
			switch (bin) {
			case "flatpak":
			case "snap":
			case "env":
			case "sh":
			case "bash":
			case "dash":
			case "zsh":
			case "python":
			case "python2":
			case "python3":
			case "java":
			case "javaw":
			case "wine":
			case "wine64":
			case "electron":
			case "xdg-open":
			case "gio":
			case "nohup":
			case "firejail":
			case "bwrap":
				return true;
			default:
				return false;
			}
		}

		public static Gtk.MenuItem? build_submenu_item (string launcher_uri, owned ItemActivatedFunc? on_activated = null)
		{
			if (launcher_uri == null || launcher_uri == "" || launcher_uri.has_prefix ("docklet://"))
				return null;

			string? desktop_path = null;
			if (launcher_uri.has_prefix ("file://")) {
				try {
					desktop_path = Filename.from_uri (launcher_uri);
				} catch {
					desktop_path = File.new_for_uri (launcher_uri).get_path ();
				}
			} else if (launcher_uri.has_prefix ("/")) {
				desktop_path = launcher_uri;
			}

			if (desktop_path == null || !desktop_path.has_suffix (".desktop"))
				return null;

			DesktopAppInfo? desktop_info = new DesktopAppInfo.from_filename (desktop_path);
			if (desktop_info == null)
				return null;

			if (!desktop_info.supports_files () && !desktop_info.supports_uris ()) {
				unowned string[]? sup_check = desktop_info.get_supported_types ();
				if (sup_check == null || sup_check.length == 0)
					return null;
			}

			string exec_bin = "";
			string? raw_exe = desktop_info.get_executable ();
			if (raw_exe != null && raw_exe != "") {
				exec_bin = Path.get_basename (raw_exe).down ();
				if (is_generic_wrapper_bin (exec_bin))
					exec_bin = "";
			}

			string alt_app_token = "";
			if (exec_bin == "") {
				string? cmdline = desktop_info.get_commandline ();
				if (cmdline != null && cmdline != "") {
					try {
						string[] argv_tokens;
						if (Shell.parse_argv (cmdline, out argv_tokens) && argv_tokens.length > 0) {
							string first = Path.get_basename (argv_tokens[0]).down ();
							if (first == "env") {
								for (int i = 1; i < argv_tokens.length; i++) {
									string tok = argv_tokens[i];
									if (tok.has_prefix ("-") || tok.contains ("="))
										continue;
									string cand = Path.get_basename (tok).down ();
									if (!is_generic_wrapper_bin (cand))
										exec_bin = cand;
									break;
								}
							} else if (first == "flatpak") {
								for (int i = 1; i < argv_tokens.length; i++) {
									string tok = argv_tokens[i];
									if (tok.has_prefix ("--command=")) {
										string cand = Path.get_basename (tok.substring ("--command=".length)).down ();
										if (!is_generic_wrapper_bin (cand))
											exec_bin = cand;
									} else if (!tok.has_prefix ("-") && tok != "run" && tok.contains (".")) {
										int last_dot = tok.last_index_of_char ('.');
										if (last_dot >= 0 && last_dot + 1 < tok.length) {
											string tail = tok.substring (last_dot + 1).down ();
											if (tail.length >= 3 && !is_generic_wrapper_bin (tail))
												alt_app_token = tail;
										}
									}
								}
							}
						}
					} catch (Error e) { }
				}
			}

			string desktop_base = Path.get_basename (desktop_path).down ();
			if (desktop_base.has_suffix (".desktop"))
				desktop_base = desktop_base.substring (0, desktop_base.length - 8);
			if (alt_app_token == "" && desktop_base.contains ("_") && (desktop_path.contains ("/snapd/") || (raw_exe != null && Path.get_basename (raw_exe).down () == "snap"))) {
				int us = desktop_base.index_of_char ('_');
				if (us > 0 && us + 1 < desktop_base.length) {
					string snap_app = desktop_base.substring (us + 1);
					if (snap_app.length >= 3 && !is_generic_wrapper_bin (snap_app))
						alt_app_token = snap_app;
				}
			}

			var supported_mimes = new Gee.ArrayList<string> ();
			unowned string[]? raw_types = desktop_info.get_supported_types ();
			if (raw_types != null) {
				foreach (unowned string mt in raw_types) {
					if (mt != null && mt != "")
						supported_mimes.add (mt);
				}
			}

			if (exec_bin == "" && desktop_base == "" && supported_mimes.size == 0)
				return null;

			unowned Gtk.RecentManager? manager = Gtk.RecentManager.get_default ();
			if (manager == null)
				return null;

			GLib.List<Gtk.RecentInfo> all_items = manager.get_items ();
			if (all_items == null)
				return null;

			var candidates = new Gee.ArrayList<RecentCandidate> ();
			var seen_uris = new Gee.HashSet<string> ();

			foreach (Gtk.RecentInfo info in all_items) {
				unowned string u = info.get_uri ();
				if (u == null || !u.has_prefix ("file://") || seen_uris.contains (u))
					continue;

				bool app_matched = false;
				string[] apps = info.get_applications ();
				if (apps != null) {
					foreach (unowned string app_name in apps) {
						if (app_name == null || app_name == "")
							continue;
						string low = app_name.down ();
						if ((exec_bin != "" && (low == exec_bin || Path.get_basename (low) == exec_bin))
							|| (alt_app_token != "" && (low == alt_app_token || Path.get_basename (low) == alt_app_token))
							|| (desktop_base != "" && (low == desktop_base || low == desktop_base + ".desktop"))) {
							app_matched = true;
							break;
						}
					}
				}

				bool mime_matched = false;
				if (!app_matched && supported_mimes.size > 0) {
					unowned string item_mime = info.get_mime_type ();
					if (item_mime != null && item_mime != "") {
						foreach (var sup in supported_mimes) {
							if (item_mime == sup || ContentType.is_a (item_mime, sup)) {
								mime_matched = true;
								break;
							}
						}
					}
				}

				if (!app_matched && !mime_matched)
					continue;

				seen_uris.add (u);
				string label = info.get_display_name ();
				if (label == null || label == "")
					label = File.new_for_uri (u).get_basename () ?? u;

				candidates.add (new RecentCandidate (
					info,
					u,
					label,
					info.get_gicon (),
					(int64) info.get_modified (),
					app_matched
				));
			}

			if (candidates.size == 0)
				return null;

			candidates.sort ((a, b) => {
				if (a.direct_app_match != b.direct_app_match)
					return a.direct_app_match ? -1 : 1;
				if (b.modified_ts > a.modified_ts)
					return 1;
				if (b.modified_ts < a.modified_ts)
					return -1;
				return 0;
			});

			var valid_candidates = new Gee.ArrayList<RecentCandidate> ();
			foreach (var cand in candidates) {
				if (!cand.info.exists ())
					continue;
				valid_candidates.add (cand);
				if (valid_candidates.size >= MAX_RECENT_ITEMS)
					break;
			}

			if (valid_candidates.size == 0)
				return null;

			var root_item = DockElement.create_menu_item (_("Recent Files"), "document-open-recent", true);
			var submenu = new Gtk.Menu ();
			root_item.set_submenu (submenu);

			foreach (var c in valid_candidates) {
				string short_name = c.display_name;
				if (short_name.char_count () > 52)
					short_name = short_name.substring (0, short_name.index_of_nth_char (49)) + "…";

				string icon_str = (c.gicon != null) ? (DrawingService.get_icon_from_gicon (c.gicon) ?? "text-x-generic") : "text-x-generic";
				var sub_item = DockElement.create_literal_menu_item (short_name, icon_str, true);
				try {
					string tip_path = Filename.from_uri (c.uri);
					sub_item.set_tooltip_text (tip_path);
				} catch { }

				string target_uri = c.uri;
				string captured_desktop = desktop_path;
				sub_item.activate.connect (() => {
					var target_file = File.new_for_uri (target_uri);
					bool launched = false;
					var d_info = new DesktopAppInfo.from_filename (captured_desktop);
					if (d_info != null) {
						try {
							var files = new GLib.List<File> ();
							files.append (target_file);
							launched = d_info.launch (files, System.get_default ().context);
						} catch (Error e) {
							warning ("RecentFilesService: launch via '%s' failed: %s", captured_desktop, e.message);
						}
					}
					if (!launched)
						System.get_default ().open (target_file);
					if (on_activated != null)
						on_activated ();
				});
				submenu.append (sub_item);
			}

			submenu.show_all ();
			return root_item;
		}
	}
}

