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
	class Win32DesktopThemeBus : GLib.Object, IDesktopThemeBus
	{
		bool last_prefer_dark = false;
		bool initialized = false;
		uint poll_timer_id = 0U;

		construct
		{
			bool dark = false;
			if (query_prefer_dark (out dark)) {
				last_prefer_dark = dark;
				initialized = true;
			}
			Win32Bridge.set_theme_callback (on_win32_theme_event);
			poll_timer_id = GLib.Timeout.add_seconds (30, on_theme_poll);
		}

		~Win32DesktopThemeBus ()
		{
			cleanup ();
		}

		void on_win32_theme_event ()
		{
			on_theme_poll ();
		}

		bool on_theme_poll ()
		{
			bool dark = false;
			if (query_prefer_dark (out dark)) {
				if (!initialized || dark != last_prefer_dark) {
					initialized = true;
					last_prefer_dark = dark;
					color_scheme_changed ();
				}
			}
			return Source.CONTINUE;
		}

		public bool query_prefer_dark (out bool prefer_dark)
		{
			int val = 0;
			int ok = Win32SysBridge.query_prefer_dark (out val);
			prefer_dark = (val != 0);
			return ok != 0;
		}

		public double get_font_scale_factor ()
		{
			return Win32SysBridge.query_font_scale_factor ();
		}

		public void cleanup ()
		{
			Win32Bridge.set_theme_callback (null);
			if (poll_timer_id != 0U) {
				Source.remove (poll_timer_id);
				poll_timer_id = 0U;
			}
		}
	}

	class Win32MediaController : GLib.Object, IMediaController
	{
		public bool has_event_subscription () { return false; }

		public bool probe_players_sync (out Gee.ArrayList<MediaPlayerInfo> players)
		{
			var list = new Gee.ArrayList<MediaPlayerInfo> ();
			int ok = Win32MediaBridge.probe_players ((player_id, identity, fallback_name, status, title, artist, can_pause, is_browser, owner_pid) => {
				var info = new MediaPlayerInfo ();
				info.player_id = player_id;
				info.identity = identity;
				info.fallback_app_name = fallback_name;
				info.status = status;
				info.title = title;
				info.artist = artist;
				info.can_pause = (can_pause != 0);
				info.is_browser = (is_browser != 0);
				info.owner_pid = owner_pid;
				list.add (info);
			});
			players = list;
			return (ok != 0);
		}

		public bool pause_player_sync (string player_id)
		{
			return Win32MediaBridge.send_command (player_id, "pause") != 0;
		}

		public bool send_player_command_sync (string player_id, string command)
		{
			return Win32MediaBridge.send_command (player_id, command) != 0;
		}

		public void cleanup () {}
	}

	class Win32NotificationBus : GLib.Object, INotificationBus
	{
		bool dnd_manual_override = false;
		bool dnd_manual_state = false;

		public bool show_launcher_badges { get { return true; } }
		public bool has_instant_dnd_settings () { return true; }
		public bool has_push_dnd_subscription () { return false; }

		public bool get_instant_dnd_inhibited ()
		{
			if (dnd_manual_override)
				return dnd_manual_state;
			return Win32SysBridge.query_dnd_inhibited () != 0;
		}

		public bool probe_dnd_inhibited_sync ()
		{
			bool os_dnd = (Win32SysBridge.query_dnd_inhibited () != 0);
			if (os_dnd) {
				dnd_manual_override = false;
				return true;
			}
			return dnd_manual_override ? dnd_manual_state : false;
		}

		public void inhibit_dnd ()
		{
			dnd_manual_override = true;
			dnd_manual_state = true;
			dnd_state_changed (true);
		}

		public void uninhibit_dnd ()
		{
			dnd_manual_override = true;
			dnd_manual_state = false;
			dnd_state_changed (false);
		}

		public void send_toast (string summary, string body, string icon_name)
		{
			Win32SysBridge.send_toast (summary, body);
		}

		public void cleanup () {}
	}

	class Win32AppMenuBus : GLib.Object, IAppMenuBus
	{
		static Gee.HashMap<string, string> load_profile_names_for_browser (BrowserFamily family)
		{
			var map = new Gee.HashMap<string, string> ();
			foreach (var ls_path in Hal.Apps.get_browser_local_state_paths (family)) {
				try {
					var parser = new Json.Parser ();
					parser.load_from_file (ls_path);
					var root = parser.get_root ();
					if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
						continue;
					var obj = root.get_object ();
					if (!obj.has_member ("profile"))
						continue;
					var prof_obj = obj.get_object_member ("profile");
					if (prof_obj == null || !prof_obj.has_member ("info_cache"))
						continue;
					var cache_obj = prof_obj.get_object_member ("info_cache");
					if (cache_obj == null)
						continue;
					foreach (var dir_key in cache_obj.get_members ()) {
						var entry = cache_obj.get_object_member (dir_key);
						if (entry != null && entry.has_member ("name")) {
							string? name = entry.get_string_member ("name");
							if (name != null && name.strip ().length > 0)
								map.set (dir_key.down (), name.strip ());
						}
					}
				} catch (Error e) {}
			}
			return map;
		}

		static string extract_profile_dir_from_cmdline (string cmdline)
		{
			if (cmdline.length == 0)
				return "";
			var argv = Hal.Runtime.parse_command_argv (cmdline);
			foreach (var arg in argv) {
				if (arg.down ().has_prefix ("--profile-directory="))
					return arg.substring (20).strip ();
			}
			return "";
		}

		static BrowserFamily? browser_family_for_app_id (string low_app)
		{
			switch (low_app) {
			case "chrome": return BrowserFamily.CHROME;
			case "msedge": return BrowserFamily.EDGE;
			case "brave": return BrowserFamily.BRAVE;
			case "vivaldi": return BrowserFamily.VIVALDI;
			case "opera": return BrowserFamily.OPERA;
			case "chromium": return BrowserFamily.CHROMIUM;
			default: return null;
			}
		}

		public Gee.ArrayList<string> query_ordered_window_profile_labels (int pid, string[]? known_profile_labels = null)
		{
			var labels = new Gee.ArrayList<string> ();
			if (pid <= 0)
				return labels;

			var family_cache = new Gee.HashMap<int, Gee.HashMap<string, string>> ();

			foreach (var w in Hal.Windows.get_windows ()) {
				if (w.Pid != pid)
					continue;
				string prof_dir = extract_profile_dir_from_cmdline (w.Cmdline);
				if (prof_dir.length == 0)
					continue;

				string low_app = w.ApplicationId.down ();
				string resolved = prof_dir;
				BrowserFamily? fam = browser_family_for_app_id (low_app);
				if (fam != null) {
					int fkey = (int) fam;
					if (!family_cache.has_key (fkey))
						family_cache.set (fkey, load_profile_names_for_browser (fam));
					var names = family_cache.get (fkey);
					if (names != null && names.has_key (prof_dir.down ()))
						resolved = names.get (prof_dir.down ());
				}

				if (known_profile_labels != null) {
					foreach (var known in known_profile_labels) {
						if (known.down () == resolved.down () || known.down () == prof_dir.down ()) {
							resolved = known;
							break;
						}
					}
				}
				labels.add (resolved);
			}
			return labels;
		}

		public string query_profile_label_at_token (int pid, string menu_token, string[]? known_profile_labels = null)
		{
			var list = query_ordered_window_profile_labels (pid, known_profile_labels);
			return list.size > 0 ? list[0] : "";
		}

		public void cleanup () {}
	}

	/**
	 * Native Windows implementation of `IBusBackend`.
	 */
	public class Win32BusBroker : GLib.Object, IBusBackend
	{
		IDockIpcClient ipc_client = new NullDockIpcClient ();
		Win32MediaController media = new Win32MediaController ();
		Win32NotificationBus notifications = new Win32NotificationBus ();
		Win32DesktopThemeBus theme = new Win32DesktopThemeBus ();
		ILauncherBadgeBus badges = new NullLauncherBadgeBus ();
		Win32AppMenuBus app_menu = new Win32AppMenuBus ();

		public IDockIpcServer create_dock_ipc_server (IDockIpcTarget target)
		{
			return new NullDockIpcServer ();
		}

		public IDockIpcClient DockIpcClient { get { return ipc_client; } }
		public IMediaController Media { get { return media; } }
		public INotificationBus Notifications { get { return notifications; } }
		public IDesktopThemeBus Theme { get { return theme; } }
		public ILauncherBadgeBus Badges { get { return badges; } }
		public IAppMenuBus AppMenu { get { return app_menu; } }

		public void cleanup ()
		{
			theme.cleanup ();
			media.cleanup ();
			notifications.cleanup ();
		}
	}
}
