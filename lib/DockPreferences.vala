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
	 * Contains all preferences for docks.
	 */
	public class DockPreferences : Plank.Settings
	{
		public const int MIN_ICON_SIZE = 24;
		public const int MAX_ICON_SIZE = 128;
		
		public const int MIN_ICON_ZOOM = 100;
		public const int MAX_ICON_ZOOM = 200;

		public const uint MIN_ACCORDION_DELAY = 500U;
		public const uint MAX_ACCORDION_DELAY = 20000U;
		public const uint DEFAULT_ACCORDION_DELAY = 1000U;

		public const int PINNED_ACCORDION_OFF = 0;
		public const int PINNED_ACCORDION_AUTO_FIT = 1;
		public const int PINNED_ACCORDION_TOP_N = 2;
		public const int MIN_PINNED_ACCORDION_COUNT = 1;
		public const int MAX_PINNED_ACCORDION_COUNT = 20;
		public const int DEFAULT_PINNED_ACCORDION_COUNT = 6;

		public const int MAX_ACTIVE_HIGHLIGHT = 7;
		public const int MAX_LAUNCH_ANIMATION = 8;
		public const int MAX_UNPIN_ANIMATION = 8;

		public const int MIN_EFFECT_DURATION = 300;
		public const int MAX_EFFECT_DURATION = 1500;
		public const int DEFAULT_EFFECT_DURATION = 600;
		
		[Description(nick = "current-workspace-only", blurb = "Whether to show only windows of the current workspace.")]
		public bool CurrentWorkspaceOnly { get; set; }

		[Description(nick = "window-click-behavior", blurb = "How clicking a running application selects its windows: 0 smart, 1 focus, 2 cycle.")]
		public int WindowClickBehavior { get; set; }

		[Description(nick = "show-window-cards", blurb = "Whether to show floating visual preview cards for applications with multiple windows.")]
		public bool ShowWindowCards { get; set; }

		[Description(nick = "restore-minimized-windows", blurb = "Whether window cycling restores minimized windows when needed.")]
		public bool RestoreMinimizedWindows { get; set; }

		[Description(nick = "show-running-indicators", blurb = "Whether application icons show running-window indicators.")]
		public bool ShowRunningIndicators { get; set; }

		[Description(nick = "show-attention-indicators", blurb = "Whether application icons show attention indicators.")]
		public bool ShowAttentionIndicators { get; set; }
		
		[Description(nick = "icon-size", blurb = "The size of dock icons (in pixels).")]
		public int IconSize { get; set; }
		
		[Description(nick = "hide-mode", blurb = "If 0, the dock won't hide.  If 1, the dock intelligently hides.  If 2, the dock auto-hides. If 3, the dock dodges active maximized windows. If 4, the dock dodges every window.")]
		public HideType HideMode { get; set; }
		
		[Description(nick = "unhide-delay", blurb = "Time (in ms) to wait before unhiding the dock.")]
		public uint UnhideDelay { get; set; }
		
		[Description(nick = "hide-delay", blurb = "Time (in ms) to wait before hiding the dock.")]
		public uint HideDelay { get; set; }
		
		[Description(nick = "monitor", blurb = "The plug-name of the monitor for the dock to show on (e.g. DVI-I-1, HDMI1, LVDS1). Leave this empty to keep on the primary monitor.")]
		public string Monitor { get; set; }
		
		[Description(nick = "dock-items", blurb = "Array of the dockitem-files on this dock. DO NOT MODIFY")]
		public string[] DockItems { get; set; }
		
		[Description(nick = "free-dock-items", blurb = "Array of the dockitem-files in free mode. DO NOT MODIFY")]
		public string[] FreeDockItems { get; set; }
		
		[Description(nick = "categorized-dock-items", blurb = "Array of the dockitem-files in categorized mode. DO NOT MODIFY")]
		public string[] CategorizedDockItems { get; set; }
		
		[Description(nick = "position", blurb = "The position for the dock on the monitor.  If 0, left.  If 1, right.  If 2, top.  If 3, bottom.")]
		public Gtk.PositionType Position { get; set; }
		
		[Description(nick = "offset", blurb = "The dock's position offset from center (in percent).")]
		public int Offset { get; set; }
		
		[Description(nick = "theme", blurb = "The name of the dock's theme to use.")]
		public string Theme { get; set; }
		
		[Description(nick = "alignment", blurb = "The alignment for the dock on the monitor's edge.  If 0, panel-mode.  If 1, left-aligned.  If 2, right-aligned.  If 3, centered.")]
		public Gtk.Align Alignment { get; set; }
		
		[Description(nick = "items-alignment", blurb = "The alignment of the items in this dock if panel-mode is used.  If 1, left-aligned.  If 2, right-aligned.  If 3, centered.")]
		public Gtk.Align ItemsAlignment { get; set; }
		
		[Description(nick = "lock-items", blurb = "Whether to prevent drag'n'drop actions and lock items on the dock.")]
		public bool LockItems { get; set; }
		
		[Description(nick = "pressure-reveal", blurb = "Whether to use pressure-based revealing of the dock if the support is available.")]
		public bool PressureReveal { get; set; }
		
		[Description(nick = "reserve-space", blurb = "Whether to reserve screen space matching the dock thickness (Panel Mode). Enabling this automatically disables Hide Dock and Icon Zoom; enabling either automatically disables Reserve Screen Space.")]
		public bool ReserveSpace { get; set; default = false; }
		
		[Description(nick = "pinned-only", blurb = "Whether to show only pinned applications. Useful for running more then one dock.")]
		public bool PinnedOnly { get; set; }
		
		[Description(nick = "auto-pinning", blurb = "Whether to automatically pin an application if it seems useful to do.")]
		public bool AutoPinning { get; set; }
		
		[Description(nick = "show-dock-item", blurb = "Whether to show the item for the dock itself.")]
		public bool ShowDockItem { get; set; }
		
		[Description(nick = "zoom-enabled", blurb = "Whether the dock will zoom when hovered.")]
		public bool ZoomEnabled { get; set; default = true; }
		
		[Description(nick = "anticipate-zoom", blurb = "Whether to begin icon magnification as the cursor approaches the dock.")]
		public bool AnticipateZoom { get; set; default = true; }
		
		[Description(nick = "zoom-percent", blurb = "The dock's icon-zoom (in percent).")]
		public uint ZoomPercent { get; set; default = 150U; }
		
		[Description(nick = "tooltips-enabled", blurb = "Whether to show tooltips when items are hovered.")]
		public bool TooltipsEnabled { get; set; default = true; }
		
		[Description(nick = "categorize-items", blurb = "Whether to categorize dock items by type (Folders, Apps, Docklets, Running, Trash).")]
		public bool CategorizeItems { get; set; default = true; }
		
		[Description(nick = "anchor-always-left", blurb = "Whether to always anchor the WayPlank icon at the far left with its own separator.")]
		public bool AnchorAlwaysLeft { get; set; default = true; }
		
		[Description(nick = "docklets-on-right", blurb = "Whether to place the docklets category on the right after unpinned apps and before Trash.")]
		public bool DockletsOnRight { get; set; default = true; }
		
		[Description(nick = "accordion-docklets", blurb = "Whether to collapse docklets in-line showing only the first one at rest.")]
		public bool AccordionDocklets { get; set; default = true; }
		
		[Description(nick = "accordion-click-to-expand", blurb = "Whether to expand docklets accordion only on click instead of hover.")]
		public bool AccordionClickToExpand { get; set; default = true; }
		
		uint _accordion_delay = DEFAULT_ACCORDION_DELAY;
		[Description(nick = "accordion-delay", blurb = "Time (in ms) to wait before auto-collapsing docklets.")]
		public uint AccordionDelay {
			get {
				return (_accordion_delay >= MIN_ACCORDION_DELAY) ? _accordion_delay : DEFAULT_ACCORDION_DELAY;
			}
			set {
				_accordion_delay = value.clamp (MIN_ACCORDION_DELAY, MAX_ACCORDION_DELAY);
			}
		}

		[Description(nick = "pinned-accordion-mode", blurb = "Smart pinned apps accordion: 0 off, 1 auto-fit capacity, 2 top most used. Running, urgent and always-visible apps are never hidden.")]
		public int PinnedAccordionMode { get; set; default = PINNED_ACCORDION_TOP_N; }

		[Description(nick = "pinned-accordion-count", blurb = "Number of most used pinned apps kept visible in top most used mode.")]
		public int PinnedAccordionCount { get; set; default = DEFAULT_PINNED_ACCORDION_COUNT; }

		[Description(nick = "scroll-overflow", blurb = "Whether to smoothly scroll when items overflow the screen instead of shrinking.")]
		public bool ScrollOverflow { get; set; }

		[Description(nick = "system-menu-access", blurb = "System menu and preferences access mode (1: Docklets only, 2: Docklets only with fallback, 3: All icons, 4: Dedicated icon on dock).")]
		public int SystemMenuAccess { get; set; default = 4; }

		[Description(nick = "active-highlight", blurb = "Focused application highlight style (0: Classic Box, 1: Icon Glow, 2: Spotlight, 3: Rounded Card, 4: Accent Bar, 5: Rim Halo, 6: Floor Reflection, 7: None).")]
		public int ActiveHighlight { get; set; default = 0; }

		[Description(nick = "launch-animation", blurb = "Application launch and click animation (0: Bounce, 1: Elastic, 2: Pulse, 3: Spring, 4: Ripple, 5: Flip, 6: Swing, 7: Flash, 8: None).")]
		public int LaunchAnimation { get; set; default = 0; }

		[Description(nick = "unpin-animation", blurb = "Application unpin and removal animation (0: Poof Cloud, 1: Shrink & Fade, 2: Implode Spin, 3: Shatter Burst, 4: Vaporize, 5: 3D Tumble, 6: Shockwave, 7: Pixel Dissolve, 8: None).")]
		public int UnpinAnimation { get; set; default = 0; }

		[Description(nick = "effect-duration", blurb = "Duration in milliseconds (300 to 1500) for icon launch, focus highlight transition, and unpin animations.")]
		public int EffectDuration { get; set; default = DEFAULT_EFFECT_DURATION; }

		public string dock_name { get; construct; default = "dock1"; }
		public bool load_environment_failed { get; private set; default = false; }
		public string load_environment_failed_details { get; private set; default = ""; }
		public string discarded_dockitems_details { get; private set; default = ""; }
		public Gee.ArrayList<string> discarded_dockitems { get; private set; default = new Gee.ArrayList<string> (); }

		/**
		 * Converts a Gee.Collection<string> into a Vala string[] allocated via new string[n]
		 * (g_new0(gchar*, n + 1)), guaranteeing a trailing NULL sentinel for GLib GStrv APIs
		 * such as GLib.Settings.set_strv(), string.joinv(), and G_TYPE_STRV properties.
		 */
		public static string[] list_to_strv (Gee.Collection<string>? list)
		{
			if (list == null || list.size == 0)
				return new string[0];
			var arr = new string[list.size];
			int idx = 0;
			foreach (var s in list) {
				if (idx < arr.length)
					arr[idx++] = s ?? "";
			}
			return arr;
		}

		public void report_corrupted_dockitems (Gee.ArrayList<string> bad_items)
		{
			if (bad_items == null || bad_items.size == 0)
				return;
			load_environment_failed = true;
			preserve_disk_on_load_fault = true;
			discarded_dockitems.clear ();
			foreach (var item in bad_items) {
				if (item != null && item != "" && !discarded_dockitems.contains (item))
					discarded_dockitems.add (item);
			}
			discarded_dockitems_details = string.joinv (", ", list_to_strv (discarded_dockitems));
		}

		static string[] filter_out_dockitems (string[]? items, Gee.Collection<string> removed)
		{
			if (items == null || items.length == 0)
				return new string[0];
			var kept = new Gee.ArrayList<string> ();
			foreach (unowned string s in items) {
				if (s != null && s != "" && !removed.contains (s))
					kept.add (s);
			}
			return list_to_strv (kept);
		}

		public void purge_discarded_dockitems (File? launchers_folder)
		{
			if (discarded_dockitems.size > 0) {
				if (launchers_folder != null) {
					foreach (var fname in discarded_dockitems) {
						if (fname == "" || !fname.has_suffix (".dockitem")
							|| fname.contains ("/") || fname.contains ("\\") || fname.contains (".."))
							continue;
						var f = launchers_folder.get_child (fname);
						try {
							if (f.query_exists ())
								f.delete ();
						} catch (Error e) {
							warning ("Unable to remove invalid dockitem '%s': %s", fname, e.message);
						}
					}
				}
				DockItems = filter_out_dockitems (DockItems, discarded_dockitems);
				CategorizedDockItems = filter_out_dockitems (CategorizedDockItems, discarded_dockitems);
				FreeDockItems = filter_out_dockitems (FreeDockItems, discarded_dockitems);
				discarded_dockitems.clear ();
				discarded_dockitems_details = "";
			}
		}

		bool updating_sr_latch = false;
		bool loading_profile_settings = false;
		bool profile_settings_dirty = false;
		HideType saved_hide_mode_before_reserve = HideType.NONE;
		bool saved_zoom_before_reserve = false;
		bool has_saved_pre_reserve_state = false;
		int last_system_menu_access = 4;
		bool saved_anchor_always_left = false;
		bool has_saved_anchor_always_left = false;
		public bool docklets_expanded_latch { get; private set; default = false; }
		public bool pinned_expanded_latch { get; private set; default = false; }

		public void update_docklets_expanded_latch (bool expanded)
		{
			if (docklets_expanded_latch == expanded)
				return;
			docklets_expanded_latch = expanded;
			save_latch_state ();
		}

		public void update_pinned_expanded_latch (bool expanded)
		{
			if (pinned_expanded_latch == expanded)
				return;
			pinned_expanded_latch = expanded;
			save_latch_state ();
		}

		public const int MAX_DOCK_SLOTS = 4;

		// IMPORTANT: Zero static array/field initializers here — in Vala, non-zero static
		// initializers on a GLib.Object subclass run lazily inside class_init, which leaves
		// pointers NULL before first instantiation and overwrites pre-loaded state afterwards.
		static bool multidock_loaded;
		static bool preserve_disk_on_load_fault;
		static bool startup_phase_completed;
		static int[]? slot_enabled;
		static int[]? slot_positions;
		static int[]? slot_screens;
		static string[]? slot1_items;
		static string[]? slot1_free_items;
		static string[]? slot1_cat_items;
		static string[]? slot2_items;
		static string[]? slot2_free_items;
		static string[]? slot2_cat_items;
		static string[]? slot3_items;
		static string[]? slot3_free_items;
		static string[]? slot3_cat_items;
		static string[]? slot4_items;
		static string[]? slot4_free_items;
		static string[]? slot4_cat_items;

		public bool needs_startup_sync { get; private set; default = false; }

		static void ensure_slot_arrays_allocated ()
		{
			if (slot_enabled == null || slot_enabled.length < MAX_DOCK_SLOTS)
				slot_enabled = { 1, -1, -1, -1 };
			if (slot_positions == null || slot_positions.length < MAX_DOCK_SLOTS)
				slot_positions = { (int) Gtk.PositionType.BOTTOM, -1, -1, -1 };
			if (slot_screens == null || slot_screens.length < MAX_DOCK_SLOTS)
				slot_screens = { 0, -1, -1, -1 };
		}

		public static void finish_startup_phase ()
		{
			startup_phase_completed = true;
		}

		public static void allow_disk_writes_after_user_action ()
		{
			if (startup_phase_completed)
				preserve_disk_on_load_fault = false;
		}

		public static int slot_index_for_dock_name (string? name)
		{
			if (name == null || name == "" || name == "dock1")
				return 1;
			if (name == "dock2" || name == "dock-2")
				return 2;
			if (name == "dock3" || name == "dock-3")
				return 3;
			if (name == "dock4" || name == "dock-4")
				return 4;
			return 0;
		}

		public static string dock_name_for_slot (int slot)
		{
			int clamped = slot.clamp (1, MAX_DOCK_SLOTS);
			return "dock%d".printf (clamped);
		}

		static string resolve_global_latch_path ()
		{
			string root_dir = "";
			if (Paths.AppConfigFolder != null && Paths.AppConfigFolder.get_path () != null && Paths.AppConfigFolder.get_path () != "")
				root_dir = Paths.AppConfigFolder.get_path ();
			else
				root_dir = Path.build_filename (Environment.get_user_config_dir (), "wayplank");

			var global_path = Path.build_filename (root_dir, "latch-state.ini");
			var stale_docks_ini = Path.build_filename (root_dir, "docks.ini");
			if (FileUtils.test (stale_docks_ini, FileTest.EXISTS))
				FileUtils.unlink (stale_docks_ini);

			for (int s = 2; s <= MAX_DOCK_SLOTS; s++) {
				var old_hyphen = Path.build_filename (root_dir, "dock-%d".printf (s));
				var new_canonical = Path.build_filename (root_dir, "dock%d".printf (s));
				if (FileUtils.test (old_hyphen, FileTest.IS_DIR) && !FileUtils.test (new_canonical, FileTest.EXISTS))
					FileUtils.rename (old_hyphen, new_canonical);
			}

			var dock1_sub = Path.build_filename (root_dir, "dock1", "latch-state.ini");
			if (!FileUtils.test (global_path, FileTest.EXISTS) && FileUtils.test (dock1_sub, FileTest.IS_REGULAR)) {
				if (FileUtils.rename (dock1_sub, global_path) != 0) {
					try {
						string data = "";
						if (FileUtils.get_contents (dock1_sub, out data))
							FileUtils.set_contents (global_path, data);
					} catch { }
					FileUtils.unlink (dock1_sub);
				}
			}

			string[] sub_dirs = { "dock1", "dock2", "dock3", "dock4", "dock-2", "dock-3", "dock-4" };
			foreach (unowned string sd in sub_dirs) {
				var sp = Path.build_filename (root_dir, sd, "latch-state.ini");
				if (FileUtils.test (sp, FileTest.EXISTS))
					FileUtils.unlink (sp);
			}

			return global_path;
		}

		static int parse_multidock_position_token (string? raw_tok, out bool valid)
		{
			valid = true;
			if (raw_tok == null)
				return -1;
			string t = raw_tok.strip ().down ();
			if (t == "" || t == "null" || t == "none" || t == "-1")
				return -1;
			int64 parsed = 0;
			if (!int64.try_parse (t, out parsed)) {
				valid = false;
				return -1;
			}
			if (parsed < (int64) Gtk.PositionType.LEFT || parsed > (int64) Gtk.PositionType.BOTTOM) {
				valid = false;
				return -1;
			}
			return (int) parsed;
		}

		static string[] get_slot_item_array (int slot, string kind)
		{
			ensure_slot_arrays_allocated ();
			switch (slot) {
			case 1:
				if (kind == "FreeDockItems") return slot1_free_items ?? new string[0];
				if (kind == "CategorizedDockItems") return slot1_cat_items ?? new string[0];
				return slot1_items ?? new string[0];
			case 2:
				if (kind == "FreeDockItems") return slot2_free_items ?? new string[0];
				if (kind == "CategorizedDockItems") return slot2_cat_items ?? new string[0];
				return slot2_items ?? new string[0];
			case 3:
				if (kind == "FreeDockItems") return slot3_free_items ?? new string[0];
				if (kind == "CategorizedDockItems") return slot3_cat_items ?? new string[0];
				return slot3_items ?? new string[0];
			case 4:
				if (kind == "FreeDockItems") return slot4_free_items ?? new string[0];
				if (kind == "CategorizedDockItems") return slot4_cat_items ?? new string[0];
				return slot4_items ?? new string[0];
			default:
				return new string[0];
			}
		}

		static void set_slot_item_array (int slot, string kind, string[] arr)
		{
			ensure_slot_arrays_allocated ();
			switch (slot) {
			case 1:
				if (kind == "FreeDockItems") slot1_free_items = arr;
				else if (kind == "CategorizedDockItems") slot1_cat_items = arr;
				else slot1_items = arr;
				break;
			case 2:
				if (kind == "FreeDockItems") slot2_free_items = arr;
				else if (kind == "CategorizedDockItems") slot2_cat_items = arr;
				else slot2_items = arr;
				break;
			case 3:
				if (kind == "FreeDockItems") slot3_free_items = arr;
				else if (kind == "CategorizedDockItems") slot3_cat_items = arr;
				else slot3_items = arr;
				break;
			case 4:
				if (kind == "FreeDockItems") slot4_free_items = arr;
				else if (kind == "CategorizedDockItems") slot4_cat_items = arr;
				else slot4_items = arr;
				break;
			}
		}

		static int parse_multidock_screen_token (string? raw_tok, out bool valid)
		{
			valid = true;
			if (raw_tok == null)
				return -1;
			string t = raw_tok.strip ().down ();
			if (t == "" || t == "null" || t == "none" || t == "-1")
				return -1;
			int64 parsed = 0;
			if (!int64.try_parse (t, out parsed)) {
				valid = false;
				return -1;
			}
			if (parsed < 0 || parsed >= MAX_DOCK_SLOTS) {
				valid = false;
				return -1;
			}
			return (int) parsed;
		}

		static int parse_multidock_enabled_token (string? raw_tok, out bool valid)
		{
			valid = true;
			if (raw_tok == null)
				return -1;
			string t = raw_tok.strip ().down ();
			if (t == "" || t == "null" || t == "none" || t == "-1")
				return -1;
			if (t == "true" || t == "1")
				return 1;
			if (t == "false" || t == "0")
				return 0;
			valid = false;
			return -1;
		}

		static bool is_known_multidock_key (string key)
		{
			for (int s = 1; s <= MAX_DOCK_SLOTS; s++) {
				if (key == "Dock%dEnabled".printf (s)
					|| key == "Dock%dPosition".printf (s)
					|| key == "Dock%dScreen".printf (s))
					return true;
				if (s >= 2 && (key == "Dock%dItems".printf (s)
					|| key == "Dock%dFreeItems".printf (s)
					|| key == "Dock%dCategorizedItems".printf (s)))
					return true;
			}
			return false;
		}

		public static void ensure_multidock_table_loaded ()
		{
			ensure_slot_arrays_allocated ();
			if (multidock_loaded)
				return;
			var path = resolve_global_latch_path ();
			if (!FileUtils.test (path, FileTest.IS_REGULAR) || !Hal.Runtime.validate_keyfile_isolated (path)) {
				if (FileUtils.test (path, FileTest.IS_REGULAR))
					preserve_disk_on_load_fault = true;
				slot_enabled[0] = 1;
				slot_positions[0] = (int) Gtk.PositionType.BOTTOM;
				slot_screens[0] = 0;
				for (int i = 1; i < MAX_DOCK_SLOTS; i++) {
					slot_enabled[i] = -1;
					slot_positions[i] = -1;
					slot_screens[i] = -1;
				}
				multidock_loaded = true;
				return;
			}
			var kf = new KeyFile ();
			try {
				kf.load_from_file (path, KeyFileFlags.NONE);
				int fallback_p1 = (int) Gtk.PositionType.BOTTOM;
				int fallback_s1 = 0;
				if (kf.has_group ("DockPreferences")) {
					try {
						if (kf.has_key ("DockPreferences", "Position")) {
							int p = kf.get_integer ("DockPreferences", "Position");
							if (p >= (int) Gtk.PositionType.LEFT && p <= (int) Gtk.PositionType.BOTTOM)
								fallback_p1 = p;
						}
					} catch { }
					try {
						if (kf.has_key ("DockPreferences", "Monitor")) {
							string m_tok = kf.get_string ("DockPreferences", "Monitor");
							if (!m_tok.contains ("..") && !m_tok.contains ("/") && !m_tok.contains ("\\"))
								fallback_s1 = PositionManager.screen_index_for_monitor_token (Gdk.Display.get_default (), m_tok);
						}
					} catch { }
				}
				if (kf.has_group ("MultiDock")) {
					for (int s = 1; s <= MAX_DOCK_SLOTS; s++) {
						string ek = "Dock%dEnabled".printf (s);
						string pk = "Dock%dPosition".printf (s);
						string sk = "Dock%dScreen".printf (s);
						try {
							if (kf.has_key ("MultiDock", pk)) {
								bool ok_tok;
								int pv = parse_multidock_position_token (kf.get_string ("MultiDock", pk), out ok_tok);
								slot_positions[s - 1] = (ok_tok && !(s == 1 && pv < 0)) ? pv : (s == 1 ? fallback_p1 : -1);
							} else {
								slot_positions[s - 1] = (s == 1) ? fallback_p1 : -1;
							}
						} catch {
							slot_positions[s - 1] = (s == 1) ? fallback_p1 : -1;
						}

						if (slot_positions[s - 1] >= 0) {
							if (s == 1) {
								slot_enabled[0] = 1;
							} else {
								try {
									if (kf.has_key ("MultiDock", ek)) {
										bool ok_en;
										int ev = parse_multidock_enabled_token (kf.get_string ("MultiDock", ek), out ok_en);
										slot_enabled[s - 1] = (ok_en && ev >= 0) ? ev : 1;
									} else {
										slot_enabled[s - 1] = 1;
									}
								} catch {
									slot_enabled[s - 1] = 1;
								}
							}

							try {
								if (kf.has_key ("MultiDock", sk)) {
									bool ok_scr;
									int sv = parse_multidock_screen_token (kf.get_string ("MultiDock", sk), out ok_scr);
									slot_screens[s - 1] = (ok_scr && sv >= 0) ? sv : (s == 1 ? fallback_s1 : 0);
								} else {
									slot_screens[s - 1] = (s == 1) ? fallback_s1 : 0;
								}
							} catch {
								slot_screens[s - 1] = (s == 1) ? fallback_s1 : 0;
							}
						} else {
							slot_enabled[s - 1] = (s == 1) ? 1 : -1;
							slot_screens[s - 1] = -1;
						}
					}
					if (slot_positions[0] < 0) {
						slot_enabled[0] = 1;
						slot_positions[0] = fallback_p1;
						slot_screens[0] = fallback_s1;
					}
				} else {
					slot_enabled[0] = 1;
					slot_positions[0] = fallback_p1;
					slot_screens[0] = fallback_s1;
					for (int i = 1; i < MAX_DOCK_SLOTS; i++) {
						slot_enabled[i] = -1;
						slot_positions[i] = -1;
						slot_screens[i] = -1;
					}
				}
			} catch {
				preserve_disk_on_load_fault = true;
				slot_enabled[0] = 1;
				slot_positions[0] = (int) Gtk.PositionType.BOTTOM;
				slot_screens[0] = 0;
				for (int i = 1; i < MAX_DOCK_SLOTS; i++) {
					slot_enabled[i] = -1;
					slot_positions[i] = -1;
					slot_screens[i] = -1;
				}
			}
			multidock_loaded = true;
		}

		public static bool is_slot_enabled (int slot)
		{
			if (slot < 1 || slot > MAX_DOCK_SLOTS)
				return false;
			ensure_multidock_table_loaded ();
			if (slot == 1)
				return true;
			return slot_enabled[slot - 1] == 1 && slot_positions[slot - 1] >= 0;
		}

		public static bool has_slot_saved_config (int slot)
		{
			if (slot < 1 || slot > MAX_DOCK_SLOTS)
				return false;
			ensure_multidock_table_loaded ();
			return slot_enabled[slot - 1] >= 0 && slot_positions[slot - 1] >= 0;
		}

		public static int get_slot_position (int slot)
		{
			if (slot < 1 || slot > MAX_DOCK_SLOTS)
				return -1;
			ensure_multidock_table_loaded ();
			return slot_positions[slot - 1];
		}

		public static int get_slot_screen (int slot)
		{
			if (slot < 1 || slot > MAX_DOCK_SLOTS)
				return -1;
			ensure_multidock_table_loaded ();
			return slot_screens[slot - 1];
		}

		public static void set_slot_enabled (int slot, bool enabled)
		{
			if (slot < 2 || slot > MAX_DOCK_SLOTS)
				return;
			ensure_multidock_table_loaded ();
			if (startup_phase_completed)
				preserve_disk_on_load_fault = false;
			if (slot_positions[slot - 1] >= 0)
				slot_enabled[slot - 1] = enabled ? 1 : 0;
		}

		public static void set_slot_placement (int slot, int screen_idx, int pos)
		{
			if (slot < 1 || slot > MAX_DOCK_SLOTS)
				return;
			ensure_multidock_table_loaded ();
			if (startup_phase_completed)
				preserve_disk_on_load_fault = false;
			if (slot == 1 && pos < 0)
				pos = (int) Gtk.PositionType.BOTTOM;
			slot_positions[slot - 1] = pos;
			if (pos >= 0) {
				slot_enabled[slot - 1] = 1;
				slot_screens[slot - 1] = screen_idx.clamp (0, MAX_DOCK_SLOTS - 1);
			} else {
				slot_enabled[slot - 1] = -1;
				slot_screens[slot - 1] = -1;
				if (slot >= 2) {
					set_slot_item_array (slot, "DockItems", new string[0]);
					set_slot_item_array (slot, "FreeDockItems", new string[0]);
					set_slot_item_array (slot, "CategorizedDockItems", new string[0]);
				}
			}
		}

		public string get_latch_state_path ()
		{
			return resolve_global_latch_path ();
		}

		public bool has_profile_settings_on_disk ()
		{
			var path = get_latch_state_path ();
			if (!FileUtils.test (path, FileTest.EXISTS))
				return false;
			if (!Hal.Runtime.validate_keyfile_isolated (path))
				return false;
			var kf = new KeyFile ();
			try {
				kf.load_from_file (path, KeyFileFlags.NONE);
				return kf.has_group ("DockPreferences");
			} catch (Error e) {
				return false;
			}
		}

		public static bool is_slot_empty_after_onboarding (int slot)
		{
			if (slot < 1 || slot > MAX_DOCK_SLOTS)
				return false;
			string dname = dock_name_for_slot (slot);
			string dock_dir = "";
			if (Paths.AppConfigFolder != null && Paths.AppConfigFolder.get_path () != null && Paths.AppConfigFolder.get_path () != "")
				dock_dir = Path.build_filename (Paths.AppConfigFolder.get_path (), dname);
			else
				dock_dir = Path.build_filename (Environment.get_user_config_dir (), "wayplank", dname);

			string marker = Path.build_filename (dock_dir, "onboarding-done");
			if (!FileUtils.test (marker, FileTest.EXISTS))
				return false;

			string launchers_dir = Path.build_filename (dock_dir, "launchers");
			if (!FileUtils.test (launchers_dir, FileTest.IS_DIR))
				return true;

			try {
				var dir = Dir.open (launchers_dir, 0);
				unowned string? entry = null;
				while ((entry = dir.read_name ()) != null) {
					if (!entry.has_prefix (".") && entry.has_suffix (".dockitem"))
						return false;
				}
			} catch (Error e) {
			}
			return true;
		}

		bool has_existing_launchers_on_disk ()
		{
			var dname = (dock_name != null && dock_name != "") ? dock_name : "dock1";
			string launchers_dir = "";
			if (Paths.AppConfigFolder != null && Paths.AppConfigFolder.get_path () != null && Paths.AppConfigFolder.get_path () != "")
				launchers_dir = Path.build_filename (Paths.AppConfigFolder.get_path (), dname, "launchers");
			else
				launchers_dir = Path.build_filename (Environment.get_user_config_dir (), "wayplank", dname, "launchers");

			if (!FileUtils.test (launchers_dir, FileTest.IS_DIR))
				return false;

			try {
				var dir = Dir.open (launchers_dir, 0);
				unowned string? entry = null;
				while ((entry = dir.read_name ()) != null) {
					if (!entry.has_prefix (".") && entry.has_suffix (".dockitem"))
						return true;
				}
			} catch (Error e) {
			}
			return false;
		}

		void on_any_pref_changed (GLib.Object sender, ParamSpec pspec)
		{
			if (loading_profile_settings)
				return;
			if (startup_phase_completed && !updating_sr_latch && PreferencesWindow.is_open)
				preserve_disk_on_load_fault = false;
			if (settings.delay_apply) {
				profile_settings_dirty = true;
				return;
			}
			save_latch_state ();
		}

		public override void apply ()
		{
			if (startup_phase_completed && !loading_profile_settings && PreferencesWindow.is_open)
				preserve_disk_on_load_fault = false;
			base.apply ();
			save_latch_state ();
		}

		public void flush_to_disk ()
		{
			if (settings.delay_apply)
				base.apply ();
			if (!startup_phase_completed)
				needs_startup_sync = true;
			save_latch_state ();
			GLib.Settings.sync ();
		}

		void reset_property_to_default (ParamSpec prop, string schema_key_name)
		{
			settings.reset (schema_key_name);
			var schema_key = settings.settings_schema.get_key (schema_key_name);
			if (prop.value_type == typeof (uint) && schema_key.get_value_type ().equal (VariantType.INT32))
				@set (prop.get_name (), (uint) int.max (0, settings.get_int (schema_key_name)));
			verify (prop.get_name ());
		}

		bool is_valid_int_or_enum_value (string prop_name, int val)
		{
			switch (prop_name) {
			case "WindowClickBehavior":
				return (val >= 0 && val <= 2);
			case "IconSize":
				return (val >= MIN_ICON_SIZE && val <= MAX_ICON_SIZE && val % 2 == 0);
			case "HideMode":
				return (val >= (int) HideType.NONE && val <= (int) HideType.DODGE_ACTIVE);
			case "Position":
				return (val >= (int) Gtk.PositionType.LEFT && val <= (int) Gtk.PositionType.BOTTOM);
			case "Offset":
				return (val >= -100 && val <= 100);
			case "Alignment":
				return (val >= (int) Gtk.Align.FILL && val <= (int) Gtk.Align.CENTER);
			case "ItemsAlignment":
				return (val >= (int) Gtk.Align.START && val <= (int) Gtk.Align.CENTER);
			case "PinnedAccordionMode":
				return (val >= PINNED_ACCORDION_OFF && val <= PINNED_ACCORDION_TOP_N);
			case "PinnedAccordionCount":
				return (val >= MIN_PINNED_ACCORDION_COUNT && val <= MAX_PINNED_ACCORDION_COUNT);
			case "SystemMenuAccess":
				return (val >= 1 && val <= 4);
			case "ActiveHighlight":
				return (val >= 0 && val <= MAX_ACTIVE_HIGHLIGHT);
			case "LaunchAnimation":
				return (val >= 0 && val <= MAX_LAUNCH_ANIMATION);
			case "UnpinAnimation":
				return (val >= 0 && val <= MAX_UNPIN_ANIMATION);
			case "EffectDuration":
				return (val >= MIN_EFFECT_DURATION && val <= MAX_EFFECT_DURATION);
			default:
				return true;
			}
		}

		bool is_valid_uint_value (string prop_name, int64 raw)
		{
			if (raw < 0 || raw > (int64) int.MAX)
				return false;
			switch (prop_name) {
			case "HideDelay":
			case "UnhideDelay":
				return (raw >= 0 && raw <= 2500);
			case "ZoomPercent":
				return (raw >= (int64) MIN_ICON_ZOOM && raw <= (int64) MAX_ICON_ZOOM);
			case "AccordionDelay":
				return (raw >= (int64) MIN_ACCORDION_DELAY && raw <= (int64) MAX_ACCORDION_DELAY);
			default:
				return true;
			}
		}

		bool probe_latch_file_in_subprocess (string path)
		{
			// Validate syntax in an isolated child process; NEVER delete or overwrite the
			// faulty file on disk so the user/tester can inspect the broken file and re-run.
			return Hal.Runtime.validate_keyfile_isolated (path);
		}

		void reset_in_memory_defaults ()
		{
			ensure_slot_arrays_allocated ();
			loading_profile_settings = true;
			updating_sr_latch = true;
			profile_settings_dirty = false;
			has_saved_pre_reserve_state = false;
			saved_hide_mode_before_reserve = HideType.NONE;
			saved_zoom_before_reserve = false;
			has_saved_anchor_always_left = false;
			saved_anchor_always_left = false;
			docklets_expanded_latch = false;
			pinned_expanded_latch = false;
			slot_enabled[0] = 1;
			slot_positions[0] = (int) Gtk.PositionType.BOTTOM;
			slot_screens[0] = 0;
			for (int i = 1; i < MAX_DOCK_SLOTS; i++) {
				slot_enabled[i] = -1;
				slot_positions[i] = -1;
				slot_screens[i] = -1;
			}
			multidock_loaded = true;
			base.reset_all ();
			last_system_menu_access = SystemMenuAccess;
			updating_sr_latch = false;
			loading_profile_settings = false;
		}

		bool load_latch_state ()
		{
			ensure_slot_arrays_allocated ();
			load_environment_failed = false;
			load_environment_failed_details = "";
			var path = get_latch_state_path ();
			if (!FileUtils.test (path, FileTest.IS_REGULAR))
				return false;

			if (!probe_latch_file_in_subprocess (path)) {
				reset_in_memory_defaults ();
				load_environment_failed = true;
				preserve_disk_on_load_fault = true;
				load_environment_failed_details = _("All settings (corrupted latch-state.ini)");
				return false;
			}

			var kf = new KeyFile ();
			try {
				kf.load_from_file (path, KeyFileFlags.NONE);
			} catch (Error e) {
				reset_in_memory_defaults ();
				load_environment_failed = true;
				preserve_disk_on_load_fault = true;
				load_environment_failed_details = _("All settings (corrupted latch-state.ini)");
				return false;
			}

			var failed_keys = new Gee.ArrayList<string> ();

			foreach (unowned string grp in kf.get_groups ()) {
				if (grp != "LatchState" && grp != "DockPreferences" && grp != "MultiDock")
					failed_keys.add ("[%s]".printf (grp));
			}

			string[] latch_keys = {
				"HasSavedPreReserveState",
				"SavedHideModeBeforeReserve",
				"SavedZoomBeforeReserve",
				"HasSavedAnchorAlwaysLeft",
				"SavedAnchorAlwaysLeft",
				"DockletsExpanded",
				"PinnedExpanded"
			};
			if (kf.has_group ("LatchState")) {
				try {
					foreach (unowned string lk in kf.get_keys ("LatchState")) {
						bool known = false;
						foreach (unowned string valid_lk in latch_keys) {
							if (lk == valid_lk) {
								known = true;
								break;
							}
						}
						if (!known)
							failed_keys.add (lk);
					}
				} catch (Error e) {
				}

				try {
					if (!kf.has_key ("LatchState", "HasSavedPreReserveState"))
						throw new KeyFileError.KEY_NOT_FOUND ("Missing key");
					has_saved_pre_reserve_state = kf.get_boolean ("LatchState", "HasSavedPreReserveState");
				} catch (Error e) {
					has_saved_pre_reserve_state = false;
					failed_keys.add ("HasSavedPreReserveState");
				}
				try {
					if (!kf.has_key ("LatchState", "SavedHideModeBeforeReserve"))
						throw new KeyFileError.KEY_NOT_FOUND ("Missing key");
					int hm = kf.get_integer ("LatchState", "SavedHideModeBeforeReserve");
					if (hm < (int) HideType.NONE || hm > (int) HideType.DODGE_ACTIVE)
						throw new KeyFileError.INVALID_VALUE ("Out of range");
					saved_hide_mode_before_reserve = (HideType) hm;
				} catch (Error e) {
					saved_hide_mode_before_reserve = HideType.NONE;
					failed_keys.add ("SavedHideModeBeforeReserve");
				}
				try {
					if (!kf.has_key ("LatchState", "SavedZoomBeforeReserve"))
						throw new KeyFileError.KEY_NOT_FOUND ("Missing key");
					saved_zoom_before_reserve = kf.get_boolean ("LatchState", "SavedZoomBeforeReserve");
				} catch (Error e) {
					saved_zoom_before_reserve = false;
					failed_keys.add ("SavedZoomBeforeReserve");
				}
				try {
					if (!kf.has_key ("LatchState", "HasSavedAnchorAlwaysLeft"))
						throw new KeyFileError.KEY_NOT_FOUND ("Missing key");
					has_saved_anchor_always_left = kf.get_boolean ("LatchState", "HasSavedAnchorAlwaysLeft");
				} catch (Error e) {
					has_saved_anchor_always_left = false;
					failed_keys.add ("HasSavedAnchorAlwaysLeft");
				}
				try {
					if (!kf.has_key ("LatchState", "SavedAnchorAlwaysLeft"))
						throw new KeyFileError.KEY_NOT_FOUND ("Missing key");
					saved_anchor_always_left = kf.get_boolean ("LatchState", "SavedAnchorAlwaysLeft");
				} catch (Error e) {
					saved_anchor_always_left = false;
					failed_keys.add ("SavedAnchorAlwaysLeft");
				}
				try {
					if (kf.has_key ("LatchState", "DockletsExpanded"))
						docklets_expanded_latch = kf.get_boolean ("LatchState", "DockletsExpanded");
					else
						docklets_expanded_latch = false;
				} catch (Error e) {
					docklets_expanded_latch = false;
					failed_keys.add ("DockletsExpanded");
				}
				try {
					if (kf.has_key ("LatchState", "PinnedExpanded"))
						pinned_expanded_latch = kf.get_boolean ("LatchState", "PinnedExpanded");
					else
						pinned_expanded_latch = false;
				} catch (Error e) {
					pinned_expanded_latch = false;
					failed_keys.add ("PinnedExpanded");
				}
			}

			if (!kf.has_group ("DockPreferences")) {
				if (failed_keys.size > 0) {
					load_environment_failed = true;
					load_environment_failed_details = string.joinv (", ", list_to_strv (failed_keys));
				}
				return false;
			}

			loading_profile_settings = true;
			bool prev_latch = updating_sr_latch;
			updating_sr_latch = true;

			(unowned ParamSpec)[] properties = get_class ().list_properties ();
			try {
				foreach (unowned string dk in kf.get_keys ("DockPreferences")) {
					bool known = false;
					foreach (unowned ParamSpec p in properties) {
						if (p.get_name () == dk) {
							known = true;
							break;
						}
					}
					if (!known)
						failed_keys.add (dk);
				}
			} catch (Error e) {
			}

			foreach (unowned string key in settings.settings_schema.list_keys ()) {
				ParamSpec? prop = null;
				foreach (unowned ParamSpec p in properties) {
					if (p.get_nick () == key) {
						prop = p;
						break;
					}
				}
				if (prop == null)
					continue;

				unowned string prop_name = prop.get_name ();
				var type = prop.value_type;
				try {
					if (!kf.has_key ("DockPreferences", prop_name))
						throw new KeyFileError.KEY_NOT_FOUND ("Missing key");

					var schema_key = settings.settings_schema.get_key (key);
					if (type == typeof (bool)) {
						bool new_v = kf.get_boolean ("DockPreferences", prop_name);
						bool old_v = false;
						@get (prop_name, out old_v);
						if (old_v != new_v)
							@set (prop_name, new_v);
					} else if (type == typeof (int) || type.is_enum ()) {
						int new_v = kf.get_integer ("DockPreferences", prop_name);
						if ((schema_key.get_value_type ().equal (VariantType.INT32) && !schema_key.range_check (new Variant.int32 (new_v)))
							|| !is_valid_int_or_enum_value (prop_name, new_v))
							throw new KeyFileError.INVALID_VALUE ("Out of schema range");
						int old_v = 0;
						@get (prop_name, out old_v);
						if (old_v != new_v)
							@set (prop_name, new_v);
					} else if (type == typeof (uint)) {
						int64 raw = kf.get_int64 ("DockPreferences", prop_name);
						if (!is_valid_uint_value (prop_name, raw)
							|| (schema_key.get_value_type ().equal (VariantType.INT32) && !schema_key.range_check (new Variant.int32 ((int) raw))))
							throw new KeyFileError.INVALID_VALUE ("Out of schema range");
						uint new_v = (uint) raw;
						uint old_v = 0U;
						@get (prop_name, out old_v);
						if (old_v != new_v)
							@set (prop_name, new_v);
					} else if (type == typeof (string)) {
						string new_v = kf.get_string ("DockPreferences", prop_name);
						if (prop_name == "Theme" && (new_v == "" || new_v == "." || new_v == ".." || new_v.contains ("/") || new_v.contains ("\\")))
							throw new KeyFileError.INVALID_VALUE ("Invalid string");
						if (prop_name == "Monitor" && (new_v.contains ("..") || new_v.contains ("/") || new_v.contains ("\\")))
							throw new KeyFileError.INVALID_VALUE ("Invalid monitor token");
						string? old_v = null;
						@get (prop_name, out old_v);
						if ((old_v ?? "") != new_v)
							@set (prop_name, new_v);
					} else if (type == typeof (string[])) {
						string[] new_v = kf.get_string_list ("DockPreferences", prop_name);
						foreach (unowned string entry in new_v) {
							if (entry == "" || entry.contains ("..") || entry.contains ("/") || entry.contains ("\\") || !entry.has_suffix (".dockitem"))
								throw new KeyFileError.INVALID_VALUE ("Invalid dockitem entry");
						}
						string[] old_v = get_strv_property (prop_name);
						if (!string_arrays_equal (old_v, new_v))
							set_strv_property (prop_name, new_v);
					}
					verify (prop_name);
				} catch (Error e) {
					reset_property_to_default (prop, key);
					failed_keys.add (prop_name);
				}
			}

			int my_slot = slot_index_for_dock_name (dock_name);
			if (my_slot == 1 || !multidock_loaded) {
				if (my_slot == 1) {
					slot1_items = get_strv_property ("DockItems");
					slot1_free_items = get_strv_property ("FreeDockItems");
					slot1_cat_items = get_strv_property ("CategorizedDockItems");
				}

				int fallback_pos1 = (int) Position;
				int fallback_scr1 = PositionManager.screen_index_for_monitor_token (Gdk.Display.get_default (), Monitor);
				if (kf.has_group ("MultiDock")) {
					try {
						foreach (unowned string mk in kf.get_keys ("MultiDock")) {
							if (!is_known_multidock_key (mk))
								failed_keys.add (mk);
						}
					} catch { }

					for (int s = 1; s <= MAX_DOCK_SLOTS; s++) {
						string en_k = "Dock%dEnabled".printf (s);
						string pos_k = "Dock%dPosition".printf (s);
						string scr_k = "Dock%dScreen".printf (s);
						try {
							if (kf.has_key ("MultiDock", pos_k)) {
								bool ok_tok;
								int pv = parse_multidock_position_token (kf.get_string ("MultiDock", pos_k), out ok_tok);
								if (!ok_tok || (s == 1 && pv < 0)) {
									slot_positions[s - 1] = (s == 1) ? fallback_pos1 : -1;
									failed_keys.add (pos_k);
								} else {
									slot_positions[s - 1] = pv;
								}
							} else {
								slot_positions[s - 1] = (s == 1) ? fallback_pos1 : -1;
							}
						} catch {
							slot_positions[s - 1] = (s == 1) ? fallback_pos1 : -1;
							failed_keys.add (pos_k);
						}

						int parsed_en = (s == 1) ? 1 : -1;
						try {
							if (kf.has_key ("MultiDock", en_k)) {
								bool ok_en;
								int ev = parse_multidock_enabled_token (kf.get_string ("MultiDock", en_k), out ok_en);
								if (!ok_en || (s == 1 && ev != 1)) {
									failed_keys.add (en_k);
									parsed_en = 1;
								} else {
									parsed_en = ev;
								}
							} else {
								parsed_en = (slot_positions[s - 1] >= 0) ? 1 : -1;
							}
						} catch {
							failed_keys.add (en_k);
							parsed_en = (s == 1 || slot_positions[s - 1] >= 0) ? 1 : -1;
						}

						int parsed_scr = (s == 1) ? fallback_scr1 : -1;
						try {
							if (kf.has_key ("MultiDock", scr_k)) {
								bool ok_scr;
								int sv = parse_multidock_screen_token (kf.get_string ("MultiDock", scr_k), out ok_scr);
								if (!ok_scr || (s == 1 && sv < 0)) {
									failed_keys.add (scr_k);
									parsed_scr = (s == 1) ? fallback_scr1 : 0;
								} else {
									parsed_scr = sv;
								}
							} else {
								parsed_scr = (slot_positions[s - 1] >= 0) ? ((s == 1) ? fallback_scr1 : 0) : -1;
							}
						} catch {
							failed_keys.add (scr_k);
							parsed_scr = (s == 1) ? fallback_scr1 : 0;
						}

						if (slot_positions[s - 1] >= 0) {
							slot_enabled[s - 1] = (s == 1) ? 1 : ((parsed_en >= 0) ? parsed_en : 1);
							slot_screens[s - 1] = (parsed_scr >= 0) ? parsed_scr : ((s == 1) ? fallback_scr1 : 0);
						} else {
							slot_enabled[s - 1] = (s == 1) ? 1 : -1;
							slot_screens[s - 1] = -1;
						}

						if (s >= 2) {
							string[,] item_keys = {
								{ "Dock%dItems".printf (s), "DockItems" },
								{ "Dock%dFreeItems".printf (s), "FreeDockItems" },
								{ "Dock%dCategorizedItems".printf (s), "CategorizedDockItems" }
							};
							for (int ik = 0; ik < 3; ik++) {
								string kf_key = item_keys[ik, 0];
								string prop_kind = item_keys[ik, 1];
								try {
									if (kf.has_key ("MultiDock", kf_key)) {
										string[] arr = kf.get_string_list ("MultiDock", kf_key);
										bool valid_arr = true;
										foreach (unowned string entry in arr) {
											if (entry == "" || entry.contains ("..") || entry.contains ("/") || entry.contains ("\\") || !entry.has_suffix (".dockitem")) {
												valid_arr = false;
												break;
											}
										}
										if (valid_arr) {
											set_slot_item_array (s, prop_kind, arr);
										} else {
											failed_keys.add (kf_key);
											set_slot_item_array (s, prop_kind, new string[0]);
										}
									} else {
										set_slot_item_array (s, prop_kind, new string[0]);
									}
								} catch {
									failed_keys.add (kf_key);
									set_slot_item_array (s, prop_kind, new string[0]);
								}
							}

							// Configuration-loader armor: if a secondary dock (dock2..dock4) was emptied
							// after onboarding (0 .dockitem files on disk), clear it automatically to null.
							if ((slot_positions[s - 1] >= 0 || slot_enabled[s - 1] >= 0)
								&& is_slot_empty_after_onboarding (s)) {
								slot_enabled[s - 1] = -1;
								slot_positions[s - 1] = -1;
								slot_screens[s - 1] = -1;
								set_slot_item_array (s, "DockItems", new string[0]);
								set_slot_item_array (s, "FreeDockItems", new string[0]);
								set_slot_item_array (s, "CategorizedDockItems", new string[0]);
								needs_startup_sync = true;
							}
						}
					}
					multidock_loaded = true;
				} else {
					// v0.7.1 backward compatibility: migrate single global Position & Monitor onto dock1, slots 2..4 = null (-1)
					slot_enabled[0] = 1;
					slot_positions[0] = fallback_pos1;
					slot_screens[0] = fallback_scr1;
					for (int s = 2; s <= MAX_DOCK_SLOTS; s++) {
						slot_enabled[s - 1] = -1;
						slot_positions[s - 1] = -1;
						slot_screens[s - 1] = -1;
						set_slot_item_array (s, "DockItems", new string[0]);
						set_slot_item_array (s, "FreeDockItems", new string[0]);
						set_slot_item_array (s, "CategorizedDockItems", new string[0]);
					}
					multidock_loaded = true;
					needs_startup_sync = true;
				}
			}
			if (my_slot >= 1 && my_slot <= MAX_DOCK_SLOTS) {
				if (slot_positions[my_slot - 1] >= 0) {
					if (Position != (Gtk.PositionType) slot_positions[my_slot - 1])
						Position = (Gtk.PositionType) slot_positions[my_slot - 1];
					string target_mon_tok = PositionManager.monitor_token_for_screen_index (int.max (0, slot_screens[my_slot - 1]));
					if (Monitor != target_mon_tok)
						Monitor = target_mon_tok;
				}
				if (my_slot == 1 && is_slot_empty_after_onboarding (1) && SystemMenuAccess != 4) {
					SystemMenuAccess = 4;
					last_system_menu_access = 4;
					needs_startup_sync = true;
				}
				if (my_slot >= 2) {
					set_strv_property ("DockItems", get_slot_item_array (my_slot, "DockItems"));
					set_strv_property ("FreeDockItems", get_slot_item_array (my_slot, "FreeDockItems"));
					set_strv_property ("CategorizedDockItems", get_slot_item_array (my_slot, "CategorizedDockItems"));
				}
			}

			updating_sr_latch = prev_latch;
			loading_profile_settings = false;

			if (failed_keys.size > 0) {
				load_environment_failed = true;
				preserve_disk_on_load_fault = true;
				load_environment_failed_details = string.joinv (", ", list_to_strv (failed_keys));
			}
			return true;
		}

		string[] get_strv_property (string prop_name)
		{
			switch (prop_name) {
			case "DockItems":
				return DockItems ?? new string[0];
			case "FreeDockItems":
				return FreeDockItems ?? new string[0];
			case "CategorizedDockItems":
				return CategorizedDockItems ?? new string[0];
			default:
				return new string[0];
			}
		}

		void set_strv_property (string prop_name, string[] val)
		{
			switch (prop_name) {
			case "DockItems":
				DockItems = val;
				break;
			case "FreeDockItems":
				FreeDockItems = val;
				break;
			case "CategorizedDockItems":
				CategorizedDockItems = val;
				break;
			}
		}

		static bool string_arrays_equal (string[]? a, string[]? b)
		{
			int len_a = (a != null) ? a.length : 0;
			int len_b = (b != null) ? b.length : 0;
			if (len_a != len_b)
				return false;
			for (int i = 0; i < len_a; i++) {
				if (a[i] != b[i])
					return false;
			}
			return true;
		}

		public void save_latch_state ()
		{
			if (loading_profile_settings || preserve_disk_on_load_fault || !startup_phase_completed)
				return;

			ensure_multidock_table_loaded ();
			int my_slot = slot_index_for_dock_name (dock_name);
			if (my_slot == 1) {
				slot_positions[0] = (int) Position;
				slot_screens[0] = PositionManager.screen_index_for_monitor_token (Gdk.Display.get_default (), Monitor);
				slot1_items = get_strv_property ("DockItems");
				slot1_free_items = get_strv_property ("FreeDockItems");
				slot1_cat_items = get_strv_property ("CategorizedDockItems");
			} else if (my_slot >= 2 && my_slot <= MAX_DOCK_SLOTS && slot_positions[my_slot - 1] >= 0) {
				slot_positions[my_slot - 1] = (int) Position;
				slot_screens[my_slot - 1] = PositionManager.screen_index_for_monitor_token (Gdk.Display.get_default (), Monitor);
				set_slot_item_array (my_slot, "DockItems", get_strv_property ("DockItems"));
				set_slot_item_array (my_slot, "FreeDockItems", get_strv_property ("FreeDockItems"));
				set_slot_item_array (my_slot, "CategorizedDockItems", get_strv_property ("CategorizedDockItems"));
			}

			var path = get_latch_state_path ();
			var dir = Path.get_dirname (path);
			DirUtils.create_with_parents (dir, 0755);

			var kf = new KeyFile ();
			kf.set_boolean ("LatchState", "HasSavedPreReserveState", has_saved_pre_reserve_state);
			kf.set_integer ("LatchState", "SavedHideModeBeforeReserve", (int) saved_hide_mode_before_reserve);
			kf.set_boolean ("LatchState", "SavedZoomBeforeReserve", saved_zoom_before_reserve);
			kf.set_boolean ("LatchState", "HasSavedAnchorAlwaysLeft", has_saved_anchor_always_left);
			kf.set_boolean ("LatchState", "SavedAnchorAlwaysLeft", saved_anchor_always_left);
			kf.set_boolean ("LatchState", "DockletsExpanded", docklets_expanded_latch);
			kf.set_boolean ("LatchState", "PinnedExpanded", pinned_expanded_latch);

			(unowned ParamSpec)[] properties = get_class ().list_properties ();
			foreach (unowned string key in settings.settings_schema.list_keys ()) {
				ParamSpec? prop = null;
				foreach (unowned ParamSpec p in properties) {
					if (p.get_nick () == key) {
						prop = p;
						break;
					}
				}
				if (prop == null)
					continue;

				unowned string prop_name = prop.get_name ();
				var type = prop.value_type;

				if (type == typeof (bool)) {
					bool v = false;
					@get (prop_name, out v);
					kf.set_boolean ("DockPreferences", prop_name, v);
				} else if (type == typeof (int) || type.is_enum ()) {
					int v = 0;
					if (prop_name == "Position") {
						v = slot_positions[0];
					} else {
						@get (prop_name, out v);
					}
					if (prop_name == "IconSize" && v >= MIN_ICON_SIZE && v <= MAX_ICON_SIZE && (v % 2) != 0)
						v -= 1;
					kf.set_integer ("DockPreferences", prop_name, v);
				} else if (type == typeof (uint)) {
					uint v = 0U;
					@get (prop_name, out v);
					kf.set_int64 ("DockPreferences", prop_name, (int64) v);
				} else if (type == typeof (string)) {
					string? v = null;
					if (prop_name == "Monitor") {
						v = PositionManager.monitor_token_for_screen_index (int.max (0, slot_screens[0]));
					} else {
						@get (prop_name, out v);
					}
					kf.set_string ("DockPreferences", prop_name, v ?? "");
				} else if (type == typeof (string[])) {
					string[] v = (my_slot == 1)
						? get_strv_property (prop_name)
						: get_slot_item_array (1, prop_name);
					kf.set_string_list ("DockPreferences", prop_name, v);
				}
			}

			kf.set_string ("MultiDock", "Dock1Enabled", "true");
			kf.set_integer ("MultiDock", "Dock1Position", slot_positions[0] >= 0 ? slot_positions[0] : (int) Gtk.PositionType.BOTTOM);
			kf.set_integer ("MultiDock", "Dock1Screen", int.max (0, slot_screens[0]));
			for (int s = 2; s <= MAX_DOCK_SLOTS; s++) {
				int sp = slot_positions[s - 1];
				int se = slot_enabled[s - 1];
				if (sp >= 0 && se >= 0) {
					kf.set_string ("MultiDock", "Dock%dEnabled".printf (s), (se == 1) ? "true" : "false");
					kf.set_integer ("MultiDock", "Dock%dPosition".printf (s), sp);
					kf.set_integer ("MultiDock", "Dock%dScreen".printf (s), int.max (0, slot_screens[s - 1]));
					string[] s_items = get_slot_item_array (s, "DockItems");
					string[] s_free = get_slot_item_array (s, "FreeDockItems");
					string[] s_cat = get_slot_item_array (s, "CategorizedDockItems");
					if (s_items.length > 0)
						kf.set_string_list ("MultiDock", "Dock%dItems".printf (s), s_items);
					if (s_free.length > 0)
						kf.set_string_list ("MultiDock", "Dock%dFreeItems".printf (s), s_free);
					if (s_cat.length > 0)
						kf.set_string_list ("MultiDock", "Dock%dCategorizedItems".printf (s), s_cat);
				} else {
					kf.set_string ("MultiDock", "Dock%dEnabled".printf (s), "null");
					kf.set_string ("MultiDock", "Dock%dPosition".printf (s), "null");
					kf.set_string ("MultiDock", "Dock%dScreen".printf (s), "null");
				}
			}

			try {
				FileUtils.set_contents (path, kf.to_data ());
				profile_settings_dirty = false;
			} catch (FileError e) {
				warning ("Unable to save latch state '%s': %s", path, e.message);
			}
		}
		
		/**
		 * {@inheritDoc}
		 */
		public DockPreferences (string name)
		{
			Object (dock_name: name, settings: create_settings ("net.launchpad.plank.dock.settings", "/net/launchpad/plank/docks/%s/".printf (name)));
		}

		construct
		{
			bool loaded_from_disk = load_latch_state ();
			bool state_dirty = false;

			if (ReserveSpace && (HideMode != HideType.NONE || ZoomEnabled)) {
				saved_hide_mode_before_reserve = HideMode;
				saved_zoom_before_reserve = ZoomEnabled;
				has_saved_pre_reserve_state = true;
				state_dirty = true;
				updating_sr_latch = true;
				if (HideMode != HideType.NONE)
					HideMode = HideType.NONE;
				if (ZoomEnabled)
					ZoomEnabled = false;
				updating_sr_latch = false;
			}

			if (SystemMenuAccess != 4 && AnchorAlwaysLeft) {
				saved_anchor_always_left = true;
				has_saved_anchor_always_left = true;
				state_dirty = true;
				updating_sr_latch = true;
				AnchorAlwaysLeft = false;
				updating_sr_latch = false;
			}
			last_system_menu_access = SystemMenuAccess;

			if (!load_environment_failed && !preserve_disk_on_load_fault
				&& (state_dirty || (!loaded_from_disk && has_existing_launchers_on_disk ()))) {
				needs_startup_sync = true;
			}

			notify["ReserveSpace"].connect (on_sr_reserve_changed);
			notify["HideMode"].connect (on_sr_reset_changed);
			notify["ZoomEnabled"].connect (on_sr_reset_changed);
			notify["SystemMenuAccess"].connect (on_sr_system_menu_access_changed);
			notify["AnchorAlwaysLeft"].connect (on_sr_anchor_always_left_changed);
			notify.connect (on_any_pref_changed);
		}
		
		~DockPreferences ()
		{
			notify.disconnect (on_any_pref_changed);
			notify["ReserveSpace"].disconnect (on_sr_reserve_changed);
			notify["HideMode"].disconnect (on_sr_reset_changed);
			notify["ZoomEnabled"].disconnect (on_sr_reset_changed);
			notify["SystemMenuAccess"].disconnect (on_sr_system_menu_access_changed);
			notify["AnchorAlwaysLeft"].disconnect (on_sr_anchor_always_left_changed);
		}

		void on_sr_reserve_changed ()
		{
			if (updating_sr_latch)
				return;

			// S = rising edge of ReserveSpace: memorize pre-reserve state, then deactivate Hide Dock and Icon Zoom
			if (ReserveSpace) {
				saved_hide_mode_before_reserve = HideMode;
				saved_zoom_before_reserve = ZoomEnabled;
				has_saved_pre_reserve_state = true;
				save_latch_state ();
				updating_sr_latch = true;
				if (HideMode != HideType.NONE)
					HideMode = HideType.NONE;
				if (ZoomEnabled)
					ZoomEnabled = false;
				updating_sr_latch = false;
			} else if (has_saved_pre_reserve_state) {
				// Falling edge of ReserveSpace: restore the memorized HideMode and ZoomEnabled states
				has_saved_pre_reserve_state = false;
				save_latch_state ();
				updating_sr_latch = true;
				if (HideMode != saved_hide_mode_before_reserve)
					HideMode = saved_hide_mode_before_reserve;
				if (ZoomEnabled != saved_zoom_before_reserve)
					ZoomEnabled = saved_zoom_before_reserve;
				updating_sr_latch = false;
			}
		}

		void on_sr_reset_changed ()
		{
			if (updating_sr_latch)
				return;

			// R = rising edge of Hide Dock or Icon Zoom: deactivate ReserveSpace without locking
			if ((HideMode != HideType.NONE || ZoomEnabled) && ReserveSpace) {
				has_saved_pre_reserve_state = false;
				save_latch_state ();
				updating_sr_latch = true;
				ReserveSpace = false;
				updating_sr_latch = false;
			}
		}

		void on_sr_system_menu_access_changed ()
		{
			if (updating_sr_latch) {
				last_system_menu_access = SystemMenuAccess;
				return;
			}

			int prev = last_system_menu_access;
			last_system_menu_access = SystemMenuAccess;

			if (prev == 4 && SystemMenuAccess != 4) {
				saved_anchor_always_left = AnchorAlwaysLeft;
				has_saved_anchor_always_left = true;
				save_latch_state ();
				if (AnchorAlwaysLeft) {
					updating_sr_latch = true;
					AnchorAlwaysLeft = false;
					updating_sr_latch = false;
				}
			} else if (prev != 4 && SystemMenuAccess == 4 && has_saved_anchor_always_left) {
				has_saved_anchor_always_left = false;
				save_latch_state ();
				if (AnchorAlwaysLeft != saved_anchor_always_left) {
					updating_sr_latch = true;
					AnchorAlwaysLeft = saved_anchor_always_left;
					updating_sr_latch = false;
				}
			}
		}

		public override void reset_all ()
		{
			preserve_disk_on_load_fault = false;
			reset_in_memory_defaults ();
			var path = get_latch_state_path ();
			if (FileUtils.test (path, FileTest.EXISTS))
				FileUtils.unlink (path);
		}

		void on_sr_anchor_always_left_changed ()
		{
			if (updating_sr_latch)
				return;

			saved_anchor_always_left = AnchorAlwaysLeft;
			has_saved_anchor_always_left = false;
			if (AnchorAlwaysLeft && SystemMenuAccess != 4) {
				save_latch_state ();
				last_system_menu_access = 4;
				updating_sr_latch = true;
				SystemMenuAccess = 4;
				updating_sr_latch = false;
			}
		}
		
		/**
		 * Increases the IconSize, if it is not already at its max.
		 */
		public void increase_icon_size ()
		{
			if (IconSize < MAX_ICON_SIZE - 1)
				IconSize += 2;
		}
		
		/**
		 * Decreases the IconSize, if it is not already at its min.
		 */
		public void decrease_icon_size ()
		{
			if (IconSize > MIN_ICON_SIZE + 1)
				IconSize -= 2;
		}
		
		/**
		 * Return whether or not a dock is a horizontal dock.
		 *
		 * @return true if the dock's position indicates it is horizontal
		 */
		public bool is_horizontal_dock ()
		{
			return (Position == Gtk.PositionType.TOP || Position == Gtk.PositionType.BOTTOM);
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override void verify (string prop)
		{
			switch (prop) {
			case "IconSize":
				if (IconSize < MIN_ICON_SIZE)
					IconSize = MIN_ICON_SIZE;
				else if (IconSize > MAX_ICON_SIZE)
					IconSize = MAX_ICON_SIZE;
				else if (IconSize % 2 == 1)
					IconSize -= 1;
				break;
			case "ZoomPercent":
				if (ZoomPercent < (uint) MIN_ICON_ZOOM)
					ZoomPercent = (uint) MIN_ICON_ZOOM;
				else if (ZoomPercent > (uint) MAX_ICON_ZOOM)
					ZoomPercent = (uint) MAX_ICON_ZOOM;
				break;
			case "AccordionDelay":
				if (AccordionDelay < MIN_ACCORDION_DELAY)
					AccordionDelay = MIN_ACCORDION_DELAY;
				else if (AccordionDelay > MAX_ACCORDION_DELAY)
					AccordionDelay = MAX_ACCORDION_DELAY;
				break;
			
			case "Theme":
				if (Theme == "" || Theme == "." || Theme == "..") {
					Theme = Plank.Theme.DEFAULT_NAME;
				} else if (Theme.contains ("/") || Theme.contains ("\\")) {
					string sanitized = Theme.replace ("/", "").replace ("\\", "");
					Theme = (sanitized == "" || sanitized == "." || sanitized == "..") ? Plank.Theme.DEFAULT_NAME : sanitized;
				}
				break;
			case "ActiveHighlight":
				if (ActiveHighlight < 0 || ActiveHighlight > MAX_ACTIVE_HIGHLIGHT)
					ActiveHighlight = 0;
				break;
			case "LaunchAnimation":
				if (LaunchAnimation < 0 || LaunchAnimation > MAX_LAUNCH_ANIMATION)
					LaunchAnimation = 0;
				break;
			case "UnpinAnimation":
				if (UnpinAnimation < 0 || UnpinAnimation > MAX_UNPIN_ANIMATION)
					UnpinAnimation = 0;
				break;
			case "PinnedAccordionMode":
				if (PinnedAccordionMode < PINNED_ACCORDION_OFF || PinnedAccordionMode > PINNED_ACCORDION_TOP_N)
					PinnedAccordionMode = PINNED_ACCORDION_OFF;
				break;
			case "PinnedAccordionCount":
				if (PinnedAccordionCount < MIN_PINNED_ACCORDION_COUNT)
					PinnedAccordionCount = MIN_PINNED_ACCORDION_COUNT;
				else if (PinnedAccordionCount > MAX_PINNED_ACCORDION_COUNT)
					PinnedAccordionCount = MAX_PINNED_ACCORDION_COUNT;
				break;
			case "EffectDuration":
				if (EffectDuration < MIN_EFFECT_DURATION)
					EffectDuration = MIN_EFFECT_DURATION;
				else if (EffectDuration > MAX_EFFECT_DURATION)
					EffectDuration = MAX_EFFECT_DURATION;
				break;
			case "HideMode":
				if ((int) HideMode < (int) HideType.NONE || (int) HideMode > (int) HideType.DODGE_ACTIVE)
					HideMode = HideType.INTELLIGENT;
				break;
			case "Position":
				if ((int) Position < (int) Gtk.PositionType.LEFT || (int) Position > (int) Gtk.PositionType.BOTTOM)
					Position = Gtk.PositionType.BOTTOM;
				break;
			case "Alignment":
				if ((int) Alignment < (int) Gtk.Align.FILL || (int) Alignment > (int) Gtk.Align.CENTER)
					Alignment = Gtk.Align.CENTER;
				break;
			case "ItemsAlignment":
				if ((int) ItemsAlignment < (int) Gtk.Align.START || (int) ItemsAlignment > (int) Gtk.Align.CENTER)
					ItemsAlignment = Gtk.Align.CENTER;
				break;
			}
		}
	}
}
