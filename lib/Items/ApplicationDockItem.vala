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
	 * A dock item for applications (with .desktop launchers).
	 */
	public class ApplicationDockItem : DockItem
	{
		// for FDO Desktop Actions
		// see http://standards.freedesktop.org/desktop-entry-spec/desktop-entry-spec-latest.html#extra-actions
		private const string DESKTOP_ACTION_KEY = "Actions";
		private const string DESKTOP_ACTION_GROUP_NAME = "Desktop Action %s";
		
		// for the Unity static quicklists
		// see https://wiki.edubuntu.org/Unity/LauncherAPI#Static_Quicklist_entries
		private const string UNITY_QUICKLISTS_KEY = "X-Ayatana-Desktop-Shortcuts";
		private const string UNITY_QUICKLISTS_SHORTCUT_GROUP_NAME = "%s Shortcut Group";
		private const string UNITY_QUICKLISTS_TARGET_KEY = "TargetEnvironment";
		private const string UNITY_QUICKLISTS_TARGET_VALUE = "Unity";
		
		private const string[] SUPPORTED_GETTEXT_DOMAINS_KEYS = {"X-Ubuntu-Gettext-Domain", "X-GNOME-Gettext-Domain"};
		
		/**
		 * Signal fired when the item's 'keep in dock' menu item is pressed.
		 */
		public signal void pin_launcher ();
		
#if HAVE_DBUSMENU
		/**
		 * The dock item's quicklist-dbusmenu.
		 */
		DbusmenuGtk.Client? Quicklist { get; set; default = null; }
#endif
		
		Gee.ArrayList<string> supported_mime_types;
		Gee.ArrayList<string> actions;
		Gee.HashMap<string, string> actions_map;
		Gee.HashMap<string, string> desktop_action_ids;
		public bool accepts_payload { get; private set; default = false; }
		
		public bool can_accept_any_drop ()
		{
			return (accepts_payload || is_web_browser () || (supported_mime_types != null && supported_mime_types.size > 0));
		}
		
		string? unity_dbusname = null;
		string base_launcher_text = "";
		int prev_window_count = 0;
		int browser_profile_reg_id = 0;
		bool scanned_running = false;

		/**
		 * Whether this app counts as running for the Smart Pinned Accordion: it has windows,
		 * or the last process scan found it. Kept apart from Indicator so that it does not
		 * depend on the "Show Running" preference.
		 */
		public bool running_for_accordion { get; private set; default = false; }
		
		/**
		 * {@inheritDoc}
		 */
		public ApplicationDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}
		
		/**
		 * {@inheritDoc}
		 */
		public ApplicationDockItem.with_dockitem_filename (string filename)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_filename (filename));
		}
		
		construct
		{
			supported_mime_types = new Gee.ArrayList<string> ();
			actions = new Gee.ArrayList<string> ();
			actions_map = new Gee.HashMap<string, string> ();
			desktop_action_ids = new Gee.HashMap<string, string> ();
			Matcher.get_default ().processes_changed.connect (handle_processes_changed);
			WindowManager.get_default ().windows_refreshed.connect (handle_window_state_changed);
			Prefs.notify["BrowserProfile"].connect (handle_browser_profile_changed);
			
			load_from_launcher ();
			prev_window_count = WindowManager.get_default ().window_count_for_app (Launcher);
			update_indicator (!WindowControl.has_state ());
		}
		
		bool is_app_cleaned_up = false;

		public override void cleanup ()
		{
			if (is_app_cleaned_up)
				return;
			is_app_cleaned_up = true;

			Matcher.get_default ().processes_changed.disconnect (handle_processes_changed);
			WindowManager.get_default ().windows_refreshed.disconnect (handle_window_state_changed);
			Prefs.notify["BrowserProfile"].disconnect (handle_browser_profile_changed);

			if (browser_profile_reg_id > 0) {
				ApplicationDiscovery.get_default ().update_item_browser_profile (browser_profile_reg_id, "", "");
				browser_profile_reg_id = 0;
			}

			supported_mime_types = null;
			actions = null;
			actions_map = null;
			desktop_action_ids = null;
#if HAVE_DBUSMENU
			Quicklist = null;
#endif
			base.cleanup ();
		}

		~ApplicationDockItem ()
		{
			cleanup ();
		}
		
		public bool is_running ()
		{
			return Matcher.get_default ().is_launcher_running (Launcher);
		}
		
		public bool is_window ()
		{
			return false;
		}

		void handle_processes_changed ()
		{
			update_indicator (true);
		}

		void handle_window_state_changed ()
		{
			update_indicator (false);
		}

		public void set_urgent (bool is_urgent)
		{
			var was_urgent = (State & ItemState.URGENT) != 0;
			if (is_urgent) {
				if (!was_urgent) {
					LastUrgent = GLib.get_monotonic_time ();
					get_dock ()?.position_manager.ensure_item_visible (this);
				}
				State |= ItemState.URGENT;
			} else {
				State &= ~ItemState.URGENT;
			}
		}
		
		public void refresh_indicator ()
		{
			update_indicator (false);
		}

		protected void update_indicator (bool scan_process)
		{
			unowned DefaultApplicationDockItemProvider? provider = (Container as DefaultApplicationDockItemProvider);
			var show_running = (provider == null || provider.Prefs.ShowRunningIndicators);
			var show_attention = (provider == null || provider.Prefs.ShowAttentionIndicators);
			var window_manager = WindowManager.get_default ();
			var window_count = window_manager.window_count_for_app (Launcher);
			var running = (window_count > 0 || (scan_process && is_running ()));
			if (scan_process)
				scanned_running = (window_count == 0 && running);
			else if (window_count > 0)
				scanned_running = false;
			var prev_running_for_accordion = running_for_accordion;
			running_for_accordion = (window_count > 0 || scanned_running);
			if (scan_process && prev_running_for_accordion != running_for_accordion && provider != null)
				provider.refresh_pinned_accordion ();
			
			var had_open_windows = (prev_window_count > 0);
			prev_window_count = window_count;
			
			if (!show_running || !running)
				Indicator = IndicatorState.NONE;
			else
				Indicator = (window_count > 1 ? IndicatorState.SINGLE_PLUS : IndicatorState.SINGLE);
			
			if (show_attention && window_manager.app_demands_attention (Launcher))
				set_urgent (true);
			else if ((State & ItemState.URGENT) != 0)
				set_urgent (false);
			
			// CRITICAL ACTIVE STATE & GLOW TRACKING (DO NOT REMOVE):
			// Keeps ItemState.ACTIVE, LastActive, and needs_redraw () synchronized with the compositor's
			// active window state. This feeds DockRenderer.theme.draw_active_glow (), restoring the
			// original Plank active app highlight glow effect.
			var is_active = window_manager.app_is_active (Launcher);
			var was_active = (State & ItemState.ACTIVE) != 0;
			if (is_active != was_active) {
				LastActive = GLib.get_monotonic_time ();
				if (is_active)
					State |= ItemState.ACTIVE;
				else
					State &= ~ItemState.ACTIVE;
				needs_redraw ();
			}

			// Only bounce if THIS specific app had open windows and its last window was closed
			if (had_open_windows && window_count == 0) {
				ClickedAnimation = AnimationType.BOUNCE;
				LastClicked = GLib.get_monotonic_time ();
			}

			update_profile_tooltip_text ();
		}
		
		void launch ()
		{
			// Explicit launch from the dock: feeds the Smart Pinned Accordion usage score
			AppUsageService.get_default ().note_launch (Launcher);
			System.get_default ().launch (File.new_for_uri (Prefs.Launcher));
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.MIDDLE
				|| (button == PopupButton.LEFT && (mod & Gdk.ModifierType.CONTROL_MASK) != 0)) {
					message ("Wayplank: click on '%s' -> launching new instance (is_running=%s)", Text, is_running ().to_string ());
					launch ();
					return AnimationType.BOUNCE;
				}
			
			if (button == PopupButton.LEFT) {
				if ((mod & Gdk.ModifierType.SHIFT_MASK) != 0) {
					string? cycle_uuid;
					if (WindowManager.get_default ().cycle_window (Launcher, true, out cycle_uuid)) {
						message ("Wayplank: shift-click on '%s' -> cycle window uuid=%s", Text, cycle_uuid);
						WindowControl.queue_command (cycle_uuid, "activate");
						return AnimationType.NONE;
					}
				}
				var app_id = File.new_for_uri (Launcher).get_basename ();
				unowned DefaultApplicationDockItemProvider? provider = (Container as DefaultApplicationDockItemProvider);
				var click_behavior = (provider != null ? provider.Prefs.WindowClickBehavior : 0);
				var restore_minimized = (provider == null || provider.Prefs.RestoreMinimizedWindows);
				string? uuid;
				string action;
				if (WindowManager.get_default ().resolve_click_command (Launcher, click_behavior, restore_minimized, out uuid, out action)) {
					message ("Wayplank: click on '%s' (app_id=%s) -> uuid=%s action=%s", Text, app_id, uuid, action);
					WindowControl.queue_command (uuid, action);
					return AnimationType.BOUNCE;
				}
				message ("Wayplank: click on '%s' -> no matching window, launching new instance", Text);
				launch ();
				return AnimationType.BOUNCE;
			}
			
			return AnimationType.NONE;
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override AnimationType on_scrolled (Gdk.ScrollDirection direction, Gdk.ModifierType mod, uint32 event_time)
		{
			base.on_scrolled (direction, mod, event_time);
			bool forward = (direction == Gdk.ScrollDirection.UP || direction == Gdk.ScrollDirection.RIGHT);
			string? uuid;
			if (WindowManager.get_default ().cycle_window (Launcher, forward, out uuid)) {
				message ("Wayplank: scroll on '%s' -> cycle window uuid=%s (forward=%s)", Text, uuid, forward.to_string ());
				WindowControl.queue_command (uuid, "activate");
			}
			return AnimationType.NONE;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public bool has_executable_launcher ()
		{
			if (Launcher == "")
				return false;
			try {
				string file_path = Launcher;
				if (file_path.has_prefix ("file://"))
					file_path = Filename.from_uri (file_path);
				var kf = new KeyFile ();
				if (System.load_keyfile_safe (kf, file_path, 0)) {
					if (!kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC))
						return false;
					var exec_str = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC).strip ();
					return exec_str != "";
				}
			} catch { }
			return false;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();
			
			var windows = WindowManager.get_default ().matching_windows (Launcher);
			if (windows.size > 0) {
				if (windows.size > 1) {
					foreach (var win in windows) {
						var cap = (win.Caption != null && win.Caption != "") ? win.Caption : Text;
						var win_item = create_literal_menu_item (cap, null, false);
						string target_id = win.Id;
						win_item.activate.connect (() => {
							WindowControl.queue_command (target_id, "activate");
						});
						items.add (win_item);
					}
					var close_all_item = create_menu_item (_("Close _All"), "window-close", true);
					close_all_item.activate.connect (() => {
						foreach (var win in windows) {
							WindowControl.queue_command (win.Id, "close");
						}
					});
					items.add (close_all_item);
				} else {
					var win = windows[0];
					var close_item = create_menu_item (_("_Close"), "window-close", true);
					string target_id = win.Id;
					close_item.activate.connect (() => {
						WindowControl.queue_command (target_id, "close");
					});
					items.add (close_item);
				}
			}
			
			// Application Shortcuts & Desktop Actions (e.g. "New Window", "New Incognito Window")
			if (!is_window ()) {
				if (actions.size == 0 && Launcher != "") {
					load_from_launcher ();
				}
				
				if (actions.size > 0) {
					if (items.size > 0)
						items.add (new Gtk.SeparatorMenuItem ());
					
					foreach (var s in actions) {
						var values = actions_map.get (s).split (";;");
						var action_id = desktop_action_ids.get (s);
						
						var item = create_menu_item (s, values.length > 1 ? values[1] : "", true);
						item.activate.connect (() => {
							AppUsageService.get_default ().note_launch (Launcher);
							if (action_id != null) {
								string? path = null;
								if (Launcher.has_prefix ("file://"))
									path = File.new_for_uri (Launcher).get_path ();
								else
									path = Launcher;
								if (path != null) {
									var desktop_info = new DesktopAppInfo.from_filename (path);
									if (desktop_info != null) {
										desktop_info.launch_action (action_id, System.get_default ().context);
										return;
									}
								}
							}
							if (values.length > 0 && values[0] != "") {
								try {
									AppInfo.create_from_commandline (values[0], null, AppInfoCreateFlags.NONE).launch (null, null);
								} catch { }
							}
						});
						items.add (item);
					}
				}

				if (Launcher != "") {
					var recent_item = RecentFilesService.build_submenu_item (Launcher);
					if (recent_item != null) {
						if (items.size > 0)
							items.add (new Gtk.SeparatorMenuItem ());
						items.add (recent_item);
					}
				}
			}
			
#if HAVE_DBUSMENU
			if (Quicklist != null) {
				if (items.size > 0)
					items.add (new Gtk.SeparatorMenuItem ());
				
				var dm_root = Quicklist.get_root ();
				if (dm_root != null) {
					Logger.verbose ("%i quicklist menuitems for %s", dm_root.get_children ().length (), Text);
					foreach (var menuitem in dm_root.get_children ())
						items.add (Quicklist.menuitem_get (menuitem));
				}
			}
#endif
			
			if (items.size > 0)
				items.add (new Gtk.SeparatorMenuItem ());

			unowned DefaultApplicationDockItemProvider? default_provider = (Container as DefaultApplicationDockItemProvider);
			if (default_provider != null
				&& !default_provider.Prefs.LockItems
				&& !is_window ()
				&& has_executable_launcher ()) {
				var item = new Gtk.CheckMenuItem.with_mnemonic (_("_Keep in Dock"));
				item.active = !(this is TransientDockItem);
				item.activate.connect (() => pin_launcher ());
				items.add (item);

				if (!(this is TransientDockItem) && default_provider.is_pinned_accordion_enabled ()) {
					var keep_item = new Gtk.CheckMenuItem.with_mnemonic (_("Keep Always _Visible"));
					keep_item.active = Prefs.KeepVisible;
					keep_item.activate.connect (() => {
						Prefs.KeepVisible = !Prefs.KeepVisible;
					});
					items.add (keep_item);
				}
			}
			
			if (!is_window () && Launcher != "" && has_executable_launcher ()) {
				var icon_item = create_menu_item (_("Change _Icon..."), "preferences-desktop-theme", true);
				icon_item.activate.connect (() => {
					IconChooserDialog.show_for_launcher (this);
				});
				items.add (icon_item);
			}
			
			return items;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override string get_drop_text ()
		{
			return _("Drop to open with %s").printf (Text);
		}
		
		/**
		 * Whether this application explicitly supports opening directories.
		 */
		public bool can_accept_directory ()
		{
			if (supported_mime_types != null) {
				foreach (var ct in supported_mime_types) {
					if (ct == "inode/directory")
						return true;
				}
			}
			return false;
		}

		/**
		 * Whether this application is a web browser.
		 */
		public bool is_web_browser ()
		{
			// Web App shortcuts (e.g. Chrome Apps with --app=...) are standalone web apps, not general web browsers
			try {
				string launcher_path = Prefs.Launcher;
				if (launcher_path.has_prefix ("file://"))
					launcher_path = Filename.from_uri (launcher_path);
				var app_info = new DesktopAppInfo.from_filename (launcher_path);
				if (app_info != null) {
					string cmd = app_info.get_commandline () ?? "";
					if (cmd.contains ("--app="))
						return false;
				}
			} catch {}

			if (supported_mime_types != null) {
				foreach (var ct in supported_mime_types) {
					if (ct == "text/html" || ct == "application/xhtml+xml"
						|| ct.contains ("x-scheme-handler/http") || ct.contains ("x-scheme-handler/https"))
						return true;
				}
			}

			string l_launcher = (Prefs != null && Prefs.Launcher != null) ? Prefs.Launcher.down () : "";
			string l_icon = (Icon != null) ? Icon.down () : "";
			string l_text = (Text != null) ? Text.down () : "";

			string[] keywords = {
				"chrome", "chromium", "firefox", "browser", "edge", "brave",
				"opera", "vivaldi", "epiphany", "zen", "waterfox", "librewolf",
				"tor-browser", "floorp", "falkon", "midori", "qutebrowser"
			};

			foreach (var kw in keywords) {
				if (l_launcher.contains (kw) || l_icon.contains (kw) || l_text.contains (kw))
					return true;
			}

			try {
				string launcher_path = Prefs.Launcher;
				if (launcher_path.has_prefix ("file://"))
					launcher_path = Filename.from_uri (launcher_path);
				var app_info = new DesktopAppInfo.from_filename (launcher_path);
				if (app_info != null) {
					var cats = app_info.get_categories ();
					if (cats != null && cats.contains ("WebBrowser"))
						return true;
				}
			} catch {}

			return false;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool can_accept_drop (Gee.ArrayList<string> uris)
		{
			if (uris == null || uris.size == 0 || is_window ())
				return false;
			
			// Web browsers always accept web URLs and internet shortcuts
			bool is_browser = is_web_browser ();
			if (is_browser) {
				bool all_web = true;
				foreach (var uri in uris) {
					if (!uri.has_prefix ("http://") && !uri.has_prefix ("https://") && !uri.has_prefix ("ftp://")) {
						if (System.extract_link_shortcut_url (uri) == null) {
							all_web = false;
							break;
						}
					}
				}
				if (all_web)
					return true;
			}

			// If application only accepts directories (like file managers: Dolphin, Nautilus, etc.),
			// require that every dropped item is a directory
			if (supported_mime_types != null && supported_mime_types.size == 1 && supported_mime_types.contains ("inode/directory")) {
				foreach (var uri in uris) {
					if (uri.has_prefix ("http://") || uri.has_prefix ("https://") || uri.has_prefix ("ftp://"))
						return false;
					var f = uri.has_prefix ("/") ? File.new_for_path (uri) : File.new_for_uri (uri);
					if (f.query_file_type (FileQueryInfoFlags.NONE, null) != FileType.DIRECTORY)
						return false;
				}
				return true;
			}

			// If application explicitly declares supported MIME types, strictly enforce them!
			if (supported_mime_types != null && supported_mime_types.size > 0) {
				foreach (var uri in uris) {
					if (uri.has_prefix ("http://") || uri.has_prefix ("https://") || uri.has_prefix ("ftp://")) {
						bool match_web = false;
						foreach (var content_type in supported_mime_types) {
							if (content_type.contains ("html") || content_type.contains ("http") || content_type.contains ("url")) {
								match_web = true;
								break;
							}
						}
						if (!match_web)
							return false;
					} else {
						var file = uri.has_prefix ("/") ? File.new_for_path (uri) : File.new_for_uri (uri);
						string? uri_content_type = null;
						try {
							var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
							uri_content_type = info.get_content_type ();
						} catch {}
						
						// If empty 0-byte file (application/x-zerosize) or query failed, guess MIME from filename
						if (uri_content_type == null || uri_content_type == "application/x-zerosize") {
							bool uncertain;
							uri_content_type = ContentType.guess (uri, null, out uncertain);
						}
						
						if (uri_content_type == null)
							return false;

						bool matched = false;
						foreach (var content_type in supported_mime_types) {
							if (ContentType.is_a (uri_content_type, content_type) || ContentType.equals (uri_content_type, content_type)) {
								matched = true;
								break;
							}
						}
						if (!matched)
							return false;
					}
				}
				return true;
			}

			// Fallback: only if NO MIME types were specified in .desktop, allow if application declares payload support (%f, %F, %u, %U)
			if (accepts_payload)
				return true;
			
			return false;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override bool accept_drop (Gee.ArrayList<string> uris)
		{
			if (uris == null || uris.size == 0)
				return false;
			
			trigger_bounce ();
			
			File? app_file = null;
			if (Prefs.Launcher.has_prefix ("file://"))
				app_file = File.new_for_uri (Prefs.Launcher);
			else
				app_file = File.new_for_path (Prefs.Launcher);
			
			var effective_uris = new Gee.ArrayList<string> ();
			foreach (var u in uris) {
				var link_url = System.extract_link_shortcut_url (u);
				if (link_url != null)
					effective_uris.add (link_url);
				else
					effective_uris.add (u);
			}

			System.get_default ().launch_with_uris (app_file, effective_uris.to_array ());
			
			var windows = WindowManager.get_default ().matching_windows (Launcher);
			if (windows.size > 0) {
				WindowControl.queue_command (windows[0].Id, "activate");
			}
			
			return true;
		}
		
		void update_profile_tooltip_text ()
		{
			if (Prefs.Launcher == "")
				return;
			var identity = ApplicationDiscovery.get_default ().identity_for_launcher (Prefs.Launcher);
			if (identity == null || !identity.is_browser_launcher ())
				return;

			var wins = WindowManager.get_default ().matching_windows (Prefs.Launcher);
			foreach (var w in wins) {
				string? locked_disp = ApplicationIdentity.get_locked_window_display_name (w);
				if (locked_disp != null && locked_disp != "") {
					if (Text != locked_disp)
						Text = locked_disp;
					return;
				}
			}

			string? prof = (Prefs.BrowserProfile != null && Prefs.BrowserProfile.strip () != "")
				? Prefs.BrowserProfile.strip ()
				: identity.detected_browser_profile;

			if (prof != null && prof != "") {
				string? formatted = ApplicationIdentity.format_chrome_profile_identity_name (prof);
				if (formatted != null && formatted != "" && Text != formatted)
					Text = formatted;
			} else if (base_launcher_text != null && base_launcher_text != "" && Text != base_launcher_text) {
				Text = base_launcher_text;
			}
		}

		void handle_browser_profile_changed ()
		{
			if (Prefs.Launcher != "")
				browser_profile_reg_id = ApplicationDiscovery.get_default ().update_item_browser_profile (browser_profile_reg_id, Prefs.Launcher, Prefs.BrowserProfile);
			update_profile_tooltip_text ();
			update_indicator (false);
		}

		/**
		 * {@inheritDoc}
		 */
		protected override void load_from_launcher ()
		{
			if (Prefs.Launcher == "")
				return;
			
			string icon, text;
			parse_launcher (Prefs.Launcher, out icon, out text, actions, actions_map, supported_mime_types, desktop_action_ids);
			if (icon != null && icon != "")
				Icon = icon;
			ForcePixbuf = null;
			if (text != null && text != "") {
				base_launcher_text = text;
				Text = text;
			}

			browser_profile_reg_id = ApplicationDiscovery.get_default ().update_item_browser_profile (browser_profile_reg_id, Prefs.Launcher, Prefs.BrowserProfile);
			update_profile_tooltip_text ();

			accepts_payload = false;
			try {
				string launcher_path = Prefs.Launcher;
				if (launcher_path.has_prefix ("file://")) {
					try {
						launcher_path = Filename.from_uri (launcher_path);
					} catch (Error e) {
						var gfile = File.new_for_uri (launcher_path);
						var p = gfile.get_path ();
						if (p != null)
							launcher_path = p;
					}
				}
				var app_info = new DesktopAppInfo.from_filename (launcher_path);
				if (app_info != null && (app_info.supports_files () || app_info.supports_uris ())) {
					accepts_payload = true;
				} else {
					var kf = new KeyFile ();
					if (System.load_keyfile_safe (kf, launcher_path, KeyFileFlags.NONE)) {
						if (kf.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC)) {
							var exec_str = kf.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_EXEC);
							if (exec_str.contains ("%f") || exec_str.contains ("%F") || 
							    exec_str.contains ("%u") || exec_str.contains ("%U")) {
								accepts_payload = true;
							}
						}
					}
				}
			} catch {}
		}
		
		/**
		 * Parses a launcher to get the text, icon and actions.
		 *
		 * @param launcher the launcher file (.desktop file) to parse
		 * @param icon the icon key from the launcher
		 * @param text the text key from the launcher
		 * @param actions a list of all actions by name
		 * @param actions_map a map of actions from name to exec;;icon
		 * @param mimes a list of all supported mime types
		 */
		public static void parse_launcher (string launcher, out string icon, out string text, Gee.ArrayList<string>? actions = null, Gee.Map<string, string>? actions_map = null, Gee.ArrayList<string>? mimes = null, Gee.Map<string, string>? desktop_action_ids = null)
		{
			icon = "";
			text = "";
			
			if (launcher == null || launcher == "")
				return;
			
			string file_path = launcher;
			if (launcher.has_prefix ("file://")) {
				try {
					file_path = Filename.from_uri (launcher);
				} catch (Error e) {
					var gfile = File.new_for_uri (launcher);
					var p = gfile.get_path ();
					if (p != null)
						file_path = p;
				}
			}
			
			KeyFile file = new KeyFile ();
			if (!System.load_keyfile_safe (file, file_path, 0)) {
				critical ("%s: unable to parse desktop launcher", launcher);
				return;
			}
			
			try {
				text = file.get_locale_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME);
				
				if (file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON))
					icon = file.get_locale_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
				
				var type = file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE);
				switch (type) {
				default:
				case KeyFileDesktop.TYPE_APPLICATION:
					break;
				case KeyFileDesktop.TYPE_DIRECTORY:
					if (icon == "")
						icon = "inode-directory";
					return;
				case KeyFileDesktop.TYPE_LINK:
					if (icon == "")
						icon = "text-html";
					return;	
				}
			} catch (KeyFileError e) {
				critical ("%s: %s", launcher, e.message);
				return;
			}
			
			try {
				if (mimes != null && file.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_MIME_TYPE)) {
					var mimestrings = file.get_string_list (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_MIME_TYPE);
					foreach (unowned string mime in mimestrings)
						mimes.add (ContentType.from_mime_type (mime));
				}
				
				string? textdomain = null;
				foreach (unowned string domain_key in SUPPORTED_GETTEXT_DOMAINS_KEYS)
					if (file.has_key (KeyFileDesktop.GROUP, domain_key)) {
						textdomain = file.get_string (KeyFileDesktop.GROUP, domain_key);
						break;
					}
				
				// get FDO Desktop Actions
				// see http://standards.freedesktop.org/desktop-entry-spec/desktop-entry-spec-latest.html#extra-actions
				// get the Unity static quicklists
				// see https://wiki.edubuntu.org/Unity/LauncherAPI#Static Quicklist entries
				if (actions != null && actions_map != null) {
					actions.clear ();
					actions_map.clear ();
					if (desktop_action_ids != null)
						desktop_action_ids.clear ();
					
					string[] keys = {DESKTOP_ACTION_KEY, UNITY_QUICKLISTS_KEY};
					
					foreach (unowned string key in keys) {
						if (!file.has_key (KeyFileDesktop.GROUP, key))
							continue;
						
						foreach (unowned string action in file.get_string_list (KeyFileDesktop.GROUP, key)) {
							var group = DESKTOP_ACTION_GROUP_NAME.printf (action);
							if (!file.has_group (group)) {
								group = UNITY_QUICKLISTS_SHORTCUT_GROUP_NAME.printf (action);
								if (!file.has_group (group))
									continue;
							}
							
							// check for TargetEnvironment
							if (file.has_key (group, UNITY_QUICKLISTS_TARGET_KEY)) {
								var target = file.get_string (group, UNITY_QUICKLISTS_TARGET_KEY);
								if (target != UNITY_QUICKLISTS_TARGET_VALUE && target != "Plank")
									continue;
							}
							
							// check for NotShowIn
							if (file.has_key (group, KeyFileDesktop.KEY_NOT_SHOW_IN)) {
								var found = false;
								
								foreach (unowned string s in file.get_string_list (group, KeyFileDesktop.KEY_NOT_SHOW_IN))
									if (s == "Plank") {
										found = true;
										break;
									}
								
								if (found)
									continue;
							}
							
							// check for OnlyShowIn
							if (file.has_key (group, KeyFileDesktop.KEY_ONLY_SHOW_IN)) {
								var found = false;
								
								foreach (unowned string s in file.get_string_list (group, KeyFileDesktop.KEY_ONLY_SHOW_IN))
									if (s == UNITY_QUICKLISTS_TARGET_VALUE || s == "Plank") {
										found = true;
										break;
									}
								
								if (!found)
									continue;
							}
							
							var action_name = file.get_locale_string (group, KeyFileDesktop.KEY_NAME);
							
							var action_icon = "";
							if (file.has_key (group, KeyFileDesktop.KEY_ICON))
								action_icon = file.get_locale_string (group, KeyFileDesktop.KEY_ICON);
							
							var action_exec = "";
							if (file.has_key (group, KeyFileDesktop.KEY_EXEC))
								action_exec = file.get_string (group, KeyFileDesktop.KEY_EXEC);
							
							// apply given gettext-domain if available
							if (textdomain != null)
								action_name = GLib.dgettext (textdomain, action_name).dup ();
							
							actions.add (action_name);
							actions_map.set (action_name, "%s;;%s".printf (action_exec, action_icon));
							if (desktop_action_ids != null) {
								if (key == DESKTOP_ACTION_KEY && group == DESKTOP_ACTION_GROUP_NAME.printf (action))
									desktop_action_ids.set (action_name, action);
								else
									desktop_action_ids.unset (action_name);
							}
						}
					}
					
					if (actions.size == 0 && file_path != "") {
						var desktop_info = new DesktopAppInfo.from_filename (file_path);
						if (desktop_info != null) {
							foreach (unowned string act in desktop_info.list_actions ()) {
								var act_name = desktop_info.get_action_name (act);
								if (act_name != null && act_name != "") {
									actions.add (act_name);
									actions_map.set (act_name, ";;");
									if (desktop_action_ids != null)
										desktop_action_ids.set (act_name, act);
								}
							}
						}
					}
				}
			} catch (KeyFileError e) {
				critical ("%s: %s", launcher, e.message);
				return;
			}
		}
		
		
		/**
		 * Get current libunity dbusname
		 *
		 * @return the dbusname which provides the LauncherEntry interface, or NULL
		 */
		public unowned string? get_unity_dbusname ()
		{
			return unity_dbusname;
		}
		
		/**
		 * Whether this item provides information worth showing
		 */
		public bool has_unity_info ()
		{
			return (ProgressVisible || CountVisible);
		}
		
		/**
		 * Update this item's remote libunity value based on the given data
		 *
		 * @param sender_name the corressponding dbusname
		 * @param prop_iter the data in a standardize format from libunity
		 */
		public void unity_update (string sender_name, VariantIter prop_iter)
		{
			unity_dbusname = sender_name;
			
			string prop_key;
			Variant prop_value;
			
			while (prop_iter.next ("{sv}", out prop_key, out prop_value)) {
				if (prop_key == "count") {
					var val = prop_value.get_int64 ();
					if (Count != val)
						Count = val;
				} else if (prop_key == "count-visible") {
					var val = prop_value.get_boolean ();
					if (CountVisible != val)
						CountVisible = val;
				} else if (prop_key == "progress") {
					var val = nround (prop_value.get_double (), 3U);
					if (Progress != val)
						Progress = val;
				} else if (prop_key == "progress-visible") {
					var val = prop_value.get_boolean ();
					if (ProgressVisible != val)
						ProgressVisible = val;
				} else if (prop_key == "urgent") {
					set_urgent (prop_value.get_boolean ());
#if HAVE_DBUSMENU
				} else if (prop_key == "quicklist") {
					/* The value is the object path of the dbusmenu */
					unowned string dbus_path = prop_value.get_string ();
					// Make sure we don't update our Quicklist instance if isn't necessary
					if (Quicklist == null || Quicklist.dbus_object != dbus_path)
						if (dbus_path != "") {
							Logger.verbose ("Loading dynamic quicklists for %s (%s)", Text, sender_name);
							Quicklist = new DbusmenuGtk.Client (sender_name, dbus_path);
						} else {
							Quicklist = null;
						}
#endif
				}
			}
		}
		
		/**
		 * Reset this item's remote libunity values
		 */
		public void unity_reset ()
		{
			unity_dbusname = null;
			
			Count = 0;
			CountVisible = false;
			Progress = 0.0;
			ProgressVisible = false;
			set_urgent (false);
#if HAVE_DBUSMENU
			Quicklist = null;
#endif
		}

	}
}
