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
	 * A dock item for applications backed by OS-blind HAL launcher descriptors.
	 */
	public class ApplicationDockItem : DockItem
	{
		/**
		 * Signal fired when the item's 'keep in dock' menu item is pressed.
		 */
		public signal void pin_launcher ();

		Gee.ArrayList<string> supported_mime_types;
		Gee.ArrayList<string> actions;
		Gee.HashMap<string, string> actions_map;
		Gee.HashMap<string, string> desktop_action_ids;
		public bool accepts_payload { get; private set; default = false; }

		public bool can_accept_any_drop ()
		{
			return (accepts_payload || is_web_browser () || (supported_mime_types != null && supported_mime_types.size > 0));
		}

		string? badge_sender_id = null;
		string base_launcher_text = "";
		bool is_standalone_webapp = false;
		bool has_web_category = false;
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
			update_indicator (!Hal.Windows.has_state ());
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
					get_dock ()?.position_manager?.ensure_item_visible (this);
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
			ApplicationIdentity.note_launcher_invocation (Prefs.Launcher);
			Hal.Apps.launch_app (Prefs.Launcher, {});
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
						Hal.Windows.perform_window_action (cycle_uuid, WindowAction.ACTIVATE);
						return AnimationType.NONE;
					}
				}
				var app_id = Hal.Apps.launcher_id_stem (Launcher);
				unowned DefaultApplicationDockItemProvider? provider = (Container as DefaultApplicationDockItemProvider);
				var click_behavior = (provider != null ? provider.Prefs.WindowClickBehavior : 0);
				var restore_minimized = (provider == null || provider.Prefs.RestoreMinimizedWindows);
				string? uuid;
				string action;
				if (WindowManager.get_default ().resolve_click_command (Launcher, click_behavior, restore_minimized, out uuid, out action)) {
					message ("Wayplank: click on '%s' (app_id=%s) -> uuid=%s action=%s", Text, app_id, uuid, action);
					Hal.Windows.perform_window_action (uuid, WindowAction.from_command_name (action));
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
				Hal.Windows.perform_window_action (uuid, WindowAction.ACTIVATE);
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
			var desc = Hal.Apps.load_launcher (Launcher);
			return (desc != null && desc.is_launchable);
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
							Hal.Windows.perform_window_action (target_id, WindowAction.ACTIVATE);
						});
						items.add (win_item);
					}
					var close_all_item = create_menu_item (_("Close _All"), "window-close", true);
					close_all_item.activate.connect (() => {
						foreach (var win in windows) {
							Hal.Windows.perform_window_action (win.Id, WindowAction.CLOSE);
						}
					});
					items.add (close_all_item);
				} else {
					var win = windows[0];
					var close_item = create_menu_item (_("_Close"), "window-close", true);
					string target_id = win.Id;
					close_item.activate.connect (() => {
						Hal.Windows.perform_window_action (target_id, WindowAction.CLOSE);
					});
					items.add (close_item);
				}
			}

			// Application Shortcuts & Quicklist Actions (e.g. "New Window", "New Incognito Window")
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
							string fallback_cmd = (values.length > 0) ? values[0] : "";
							if (action_id != null && action_id != "") {
								if (Hal.Apps.launch_action (Launcher, action_id, fallback_cmd))
									return;
							}
							if (fallback_cmd != "")
								Hal.Apps.launch_command (fallback_cmd);
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
			if (is_standalone_webapp)
				return false;

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

			return has_web_category;
		}

		static bool is_remote_web_uri (string uri)
		{
			string low = uri.ascii_down ();
			return (low.has_prefix ("http://") || low.has_prefix ("https://") || low.has_prefix ("ftp://"));
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
					if (!is_remote_web_uri (uri)) {
						if (Hal.Apps.extract_link_shortcut_url (uri) == null) {
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
					if (is_remote_web_uri (uri))
						return false;
					var f = Path.is_absolute (uri) ? File.new_for_path (uri) : File.new_for_uri (uri);
					if (f.query_file_type (FileQueryInfoFlags.NONE, null) != FileType.DIRECTORY)
						return false;
				}
				return true;
			}

			// If application explicitly declares supported MIME types, strictly enforce them!
			if (supported_mime_types != null && supported_mime_types.size > 0) {
				foreach (var uri in uris) {
					if (is_remote_web_uri (uri)) {
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
						var file = Path.is_absolute (uri) ? File.new_for_path (uri) : File.new_for_uri (uri);
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

			// Fallback: only if NO MIME types were specified in launcher metadata, allow if application declares payload support
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

			var effective_uris = new Gee.ArrayList<string> ();
			foreach (var u in uris) {
				var link_url = Hal.Apps.extract_link_shortcut_url (u);
				if (link_url != null)
					effective_uris.add (link_url);
				else
					effective_uris.add (u);
			}

			ApplicationIdentity.note_launcher_invocation (Prefs.Launcher);
			Hal.Apps.launch_app (Prefs.Launcher, effective_uris.to_array ());

			var windows = WindowManager.get_default ().matching_windows (Launcher);
			if (windows.size > 0) {
				Hal.Windows.perform_window_action (windows[0].Id, WindowAction.ACTIVATE);
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

			string icon = "";
			string text = "";
			is_standalone_webapp = false;
			has_web_category = false;
			accepts_payload = false;

			var desc = parse_launcher_descriptor (Prefs.Launcher, out icon, out text, actions, actions_map, supported_mime_types, desktop_action_ids);
			if (desc != null) {
				is_standalone_webapp = desc.exec_command.contains ("--app=") || desc.url_target != "";
				has_web_category = desc.categories.contains ("WebBrowser");
				accepts_payload = (desc.supports_files || desc.supports_uris);
			}

			string effective_icon = (Prefs.CustomIcon != "" && DrawingService.has_icon (Prefs.CustomIcon))
				? Prefs.CustomIcon
				: icon;
			if (effective_icon != null && effective_icon != "")
				Icon = effective_icon;
			ForcePixbuf = null;
			if (text != null && text != "") {
				base_launcher_text = text;
				Text = text;
			}

			browser_profile_reg_id = ApplicationDiscovery.get_default ().update_item_browser_profile (browser_profile_reg_id, Prefs.Launcher, Prefs.BrowserProfile);
			update_profile_tooltip_text ();
		}

		static AppDescriptor? parse_launcher_descriptor (string launcher, out string icon, out string text,
			Gee.ArrayList<string>? actions = null, Gee.Map<string, string>? actions_map = null,
			Gee.ArrayList<string>? mimes = null, Gee.Map<string, string>? desktop_action_ids = null)
		{
			icon = "";
			text = "";

			if (launcher == null || launcher == "")
				return null;

			var desc = Hal.Apps.load_launcher (launcher);
			if (desc == null)
				return null;

			text = desc.display_name;
			icon = desc.icon_token;

			if (mimes != null) {
				mimes.clear ();
				foreach (var mime in desc.mime_types)
					mimes.add (ContentType.from_mime_type (mime));
			}

			if (actions != null && actions_map != null) {
				actions.clear ();
				actions_map.clear ();
				if (desktop_action_ids != null)
					desktop_action_ids.clear ();

				foreach (var qa in desc.quicklist_actions) {
					if (qa.name == "")
						continue;
					actions.add (qa.name);
					actions_map.set (qa.name, "%s;;%s".printf (qa.exec, qa.icon_token));
					if (desktop_action_ids != null) {
						if (qa.is_native_action && qa.id != "")
							desktop_action_ids.set (qa.name, qa.id);
						else
							desktop_action_ids.unset (qa.name);
					}
				}
			}

			return desc;
		}

		/**
		 * Parses a launcher to get the text, icon and actions.
		 *
		 * @param launcher the launcher URI or path to parse
		 * @param icon the icon token from the launcher
		 * @param text the localized display name from the launcher
		 * @param actions a list of all actions by name
		 * @param actions_map a map of actions from name to exec;;icon
		 * @param mimes a list of all supported mime types
		 */
		public static void parse_launcher (string launcher, out string icon, out string text, Gee.ArrayList<string>? actions = null, Gee.Map<string, string>? actions_map = null, Gee.ArrayList<string>? mimes = null, Gee.Map<string, string>? desktop_action_ids = null)
		{
			parse_launcher_descriptor (launcher, out icon, out text, actions, actions_map, mimes, desktop_action_ids);
		}

		/**
		 * Get current remote badge/progress IPC sender identifier (`badge_sender_id`).
		 *
		 * @return the IPC sender identifier providing LauncherEntry state, or NULL
		 */
		public unowned string? get_unity_dbusname ()
		{
			return badge_sender_id;
		}

		/**
		 * Whether this item provides remote badge/progress information worth showing.
		 */
		public bool has_unity_info ()
		{
			return (ProgressVisible || CountVisible);
		}

		/**
		 * Update this item's remote badge/progress values based on normalized HAL state.
		 */
		public void unity_update (string sender_name, LauncherBadgeState state)
		{
			badge_sender_id = sender_name;

			if (state.has_count && Count != state.count)
				Count = state.count;
			if (state.has_count_visible && CountVisible != state.count_visible)
				CountVisible = state.count_visible;
			if (state.has_progress) {
				var val = nround (state.progress, 3U);
				if (Progress != val)
					Progress = val;
			}
			if (state.has_progress_visible && ProgressVisible != state.progress_visible)
				ProgressVisible = state.progress_visible;
			if (state.has_urgent)
				set_urgent (state.urgent);
		}

		/**
		 * Reset this item's remote badge/progress values (`badge_sender_id`).
		 */
		public void unity_reset ()
		{
			badge_sender_id = null;

			Count = 0;
			CountVisible = false;
			Progress = 0.0;
			ProgressVisible = false;
			set_urgent (false);
		}
	}
}
