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
	/**
	 * Native Windows (Win32 / DWM) implementation of `IWindowBackend`.
	 * Uses out-of-context `SetWinEventHook` (zero polling) + `EnumWindows`
	 * with 50 ms burst coalescing to track top-level Windows applications.
	 */
	public class Win32Backend : GLib.Object, IWindowBackend
	{
		const uint EVENT_DEBOUNCE_MS = 150;

		bool started = false;
		bool state_valid = false;
		uint debounce_timer_id = 0U;
		int64 next_min_seq = 1;
		string last_active_thumb_id = "";

		Gee.ArrayList<WindowInfo> cached_windows;
		Gee.HashMap<string, int64?> minimized_seqs;
		Gee.HashSet<string> prev_live_ids;
		Gee.HashMap<string, string> aumid_profile_cache;

		construct
		{
			cached_windows = new Gee.ArrayList<WindowInfo> ();
			minimized_seqs = new Gee.HashMap<string, int64?> ();
			prev_live_ids = new Gee.HashSet<string> ();
			aumid_profile_cache = new Gee.HashMap<string, string> ();
		}

		~Win32Backend ()
		{
			cleanup ();
		}

		public static string format_hwnd (uint64 hwnd)
		{
			return "hwnd:0x%016llx".printf (hwnd);
		}

		public static bool parse_hwnd (string win_id, out uint64 hwnd)
		{
			hwnd = 0;
			if (!win_id.has_prefix ("hwnd:"))
				return false;
			string hex = win_id.substring (5);
			uint64 parsed = 0;
			if (uint64.try_parse (hex, out parsed, null, 16) && parsed != 0) {
				hwnd = parsed;
				return true;
			}
			return false;
		}

		static string extract_app_stem (string exe_path)
		{
			if (exe_path.length == 0)
				return "";
			int slash = exe_path.last_index_of_char ('\\');
			int fslash = exe_path.last_index_of_char ('/');
			int sep = int.max (slash, fslash);
			string base_name = (sep >= 0) ? exe_path.substring (sep + 1) : exe_path;
			if (base_name.down ().has_suffix (".exe") && base_name.length > 4)
				base_name = base_name.substring (0, base_name.length - 4);
			/* Preserve ++ distinctiveness (e.g. notepad++ != notepad) */
			if (base_name.contains ("++"))
				base_name = base_name.replace ("++", "plusplus");
			return base_name;
		}

		public bool start ()
		{
			if (started)
				return true;

			started = true;
			Win32Bridge.start_window_hooks (on_win32_event);
			refresh_windows ();
			return true;
		}

		public void cleanup ()
		{
			if (debounce_timer_id != 0U) {
				Source.remove (debounce_timer_id);
				debounce_timer_id = 0U;
			}
			if (started) {
				Win32Bridge.stop_window_hooks ();
				started = false;
			}
			cached_windows.clear ();
			minimized_seqs.clear ();
			prev_live_ids.clear ();
			aumid_profile_cache.clear ();
			state_valid = false;
		}

		void on_win32_event ()
		{
			if (!started)
				return;
			if (debounce_timer_id != 0U)
				return;
			debounce_timer_id = GLib.Timeout.add (EVENT_DEBOUNCE_MS, on_debounce_tick);
		}

		bool on_debounce_tick ()
		{
			debounce_timer_id = 0U;
			if (!started)
				return Source.REMOVE;
			if (refresh_windows ())
				state_changed ();
			return Source.REMOVE;
		}

		public static bool is_generic_win32_class (string cls)
		{
			if (cls.length == 0)
				return true;
			string low = cls.down ();
			return low.has_prefix ("chrome_widgetwin")
				|| low == "applicationframewindow"
				|| low == "consolewindowclass"
				|| low == "cascadia_hosting_window_class"
				|| low == "pseudoconsolewindow"
				|| low.has_prefix ("hwndwrapper[")
				|| low.has_prefix ("qt5qwindow")
				|| low.has_prefix ("qt6qwindow")
				|| low == "sunawtframe"
				|| low == "swt_window0"
				|| low == "cabinetwclass";
		}

		string extract_profile_dir_from_aumid (string aumid, string stem)
		{
			string clean = aumid.strip ();
			if (clean.length == 0)
				return "";
			string low = clean.down ();
			string low_stem = stem.down ();
			bool is_chromium = (low_stem == "chrome" || low_stem == "msedge" || low_stem == "brave" || low_stem == "vivaldi"
				|| low.has_prefix ("chrome") || low.has_prefix ("msedge") || low.has_prefix ("brave"));
			if (!is_chromium)
				return "";

			/* Bare AUMID without suffix (e.g. "Chrome" / "MSEdge") -> Default profile */
			int last_dot = clean.last_index_of_char ('.');
			if (last_dot < 0)
				return "Default";

			string tail = clean.substring (last_dot + 1).strip ();
			string low_tail = tail.down ();
			if (low_tail == "default")
				return "Default";
			if (low_tail.has_prefix ("profile")) {
				string rest = tail.substring (7).strip ();
				if (rest.length > 0)
					return "Profile " + rest;
			}

			if (aumid_profile_cache.has_key (low))
				return aumid_profile_cache.get (low);

			/* Hashed AUMID fallback: match once against installed .lnk PKEY_AppUserModel_ID and cache */
			string resolved = "";
			foreach (var app in Win32AppSystem.get_default ().discover_installed_apps (true)) {
				if (app.startup_wm_class_or_aumid.length > 0 && app.startup_wm_class_or_aumid.down () == low) {
					var argv = Hal.Runtime.parse_command_argv (app.exec_command);
					foreach (var arg in argv) {
						if (arg.down ().has_prefix ("--profile-directory=")) {
							resolved = arg.substring (20).strip ();
							break;
						}
					}
					if (resolved.length > 0)
						break;
				}
			}
			if (aumid_profile_cache.size > 256)
				aumid_profile_cache.clear ();
			aumid_profile_cache.set (low, resolved);
			return resolved;
		}

		static bool windows_snapshot_equal (Gee.ArrayList<WindowInfo> a, Gee.ArrayList<WindowInfo> b)
		{
			if (a.size != b.size)
				return false;
			for (int i = 0; i < a.size; i++) {
				var wa = a.get (i);
				var wb = b.get (i);
				if (wa.Id != wb.Id
					|| wa.Active != wb.Active
					|| wa.Minimized != wb.Minimized
					|| wa.Maximized != wb.Maximized
					|| wa.Fullscreen != wb.Fullscreen
					|| wa.DemandsAttention != wb.DemandsAttention
					|| wa.Geometry.x != wb.Geometry.x
					|| wa.Geometry.y != wb.Geometry.y
					|| wa.Geometry.width != wb.Geometry.width
					|| wa.Geometry.height != wb.Geometry.height
					|| wa.Caption != wb.Caption) {
					return false;
				}
			}
			return true;
		}

		bool refresh_windows ()
		{
			var next_list = new Gee.ArrayList<WindowInfo> ();
			var live_ids = new Gee.HashSet<string> ();

			Win32Bridge.enum_windows ((hwnd, pid, caption, class_name, exe_path, aumid,
				x, y, width, height, minimized, active, maximized, fullscreen, is_dialog, urgent) => {
				string id = "hwnd:0x%016llx".printf (hwnd);
				live_ids.add (id);

				string stem = extract_app_stem (exe_path);
				var info = new WindowInfo ();
				info.Id = id;
				info.Pid = pid;
				info.Caption = caption;
				info.Executable = exe_path;
				info.ApplicationId = stem.length > 0 ? stem : class_name;
				info.ResourceClass = (stem.length > 0 && is_generic_win32_class (class_name)) ? stem : (class_name.length > 0 ? class_name : stem);
				info.ResourceName = stem.down ();
				if (aumid.length > 0) {
					info.DesktopFileName = aumid;
					int crx_pos = aumid.index_of ("_crx_");
					if (crx_pos >= 0 && crx_pos + 5 < aumid.length) {
						string pwa_id = aumid.substring (crx_pos + 5).strip ();
						info.ResourceName = "crx_" + pwa_id;
						info.Cmdline = "\"%s\" --app-id=%s".printf (exe_path, pwa_id);
					} else {
						string prof_dir = extract_profile_dir_from_aumid (aumid, stem);
						if (prof_dir.length > 0) {
							info.Cmdline = "\"%s\" --profile-directory=\"%s\"".printf (exe_path, prof_dir);
						}
					}
				}
				info.Minimized = (minimized != 0);
				info.Active = (active != 0);
				info.Maximized = (maximized != 0);
				info.Fullscreen = (fullscreen != 0);
				info.IsDialog = (is_dialog != 0);
				info.DemandsAttention = (urgent != 0);
				info.CurrentDesktop = true;
				info.Geometry = { x, y, width, height };

				if (info.Minimized) {
					if (!minimized_seqs.has_key (id))
						minimized_seqs.set (id, next_min_seq++);
					info.MinimizedSequence = minimized_seqs.get (id) ?? 0;
				} else {
					minimized_seqs.unset (id);
					info.MinimizedSequence = 0;
				}

				next_list.add (info);
			});

			/* Prune minimized sequence entries & thumbnail cache for closed windows */
			var stale_keys = new Gee.ArrayList<string> ();
			foreach (var k in minimized_seqs.keys) {
				if (!live_ids.contains (k))
					stale_keys.add (k);
			}
			foreach (var k in stale_keys)
				minimized_seqs.unset (k);

			foreach (var old_id in prev_live_ids) {
				if (!live_ids.contains (old_id))
					Hal.Thumbnails.evict (old_id);
			}
			prev_live_ids = live_ids;

			bool changed = (!state_valid || !windows_snapshot_equal (cached_windows, next_list));
			cached_windows = next_list;
			state_valid = true;

			/* Proactively warm thumbnail cache off-thread only when the active window changes */
			foreach (var w in cached_windows) {
				if (!w.Minimized && w.Active && w.Id != last_active_thumb_id) {
					last_active_thumb_id = w.Id;
					if (Hal.Thumbnails.is_stale (w.Id))
						Hal.Thumbnails.request_thumbnail (w.Id, 240, 150, (pb) => {});
					break;
				}
			}
			return changed;
		}

		public bool has_state ()
		{
			return state_valid;
		}

		public Gee.ArrayList<WindowInfo> get_windows ()
		{
			var copy = new Gee.ArrayList<WindowInfo> ();
			copy.add_all (cached_windows);
			return copy;
		}

		public bool perform_window_action (string win_id, WindowAction action)
		{
			uint64 hwnd;
			if (!parse_hwnd (win_id, out hwnd))
				return false;

			int code = Win32Bridge.ACTION_ACTIVATE;
			switch (action) {
			case WindowAction.TOGGLE:
				code = Win32Bridge.ACTION_TOGGLE;
				break;
			case WindowAction.MINIMIZE:
				code = Win32Bridge.ACTION_MINIMIZE;
				break;
			case WindowAction.CLOSE:
				code = Win32Bridge.ACTION_CLOSE;
				break;
			default:
			case WindowAction.ACTIVATE:
				code = Win32Bridge.ACTION_ACTIVATE;
				break;
			}

			if (action == WindowAction.MINIMIZE || action == WindowAction.TOGGLE) {
				/* Snapshot thumbnail before minimizing so preview tiles remain populated */
				Hal.Thumbnails.request_thumbnail (win_id, 240, 150, (pb) => {});
			}

			bool ok = Win32Bridge.perform_window_action (hwnd, code) != 0;
			if (ok)
				on_win32_event ();
			return ok;
		}

		public bool toggle_show_desktop ()
		{
			bool ok = Win32Bridge.toggle_show_desktop () != 0;
			if (ok)
				on_win32_event ();
			return ok;
		}

		static bool rects_intersect (Gdk.Rectangle a, Gdk.Rectangle b)
		{
			if (a.width <= 0 || a.height <= 0 || b.width <= 0 || b.height <= 0)
				return false;
			return a.x < (b.x + b.width)
				&& (a.x + a.width) > b.x
				&& a.y < (b.y + b.height)
				&& (a.y + a.height) > b.y;
		}

		public bool any_window_intersects (Gdk.Rectangle rect)
		{
			foreach (var w in cached_windows) {
				if (w.Minimized || !w.CurrentDesktop)
					continue;
				if (rects_intersect (w.Geometry, rect))
					return true;
			}
			return false;
		}

		public bool active_window_intersects (Gdk.Rectangle rect)
		{
			foreach (var w in cached_windows) {
				if (!w.Active || w.Minimized || !w.CurrentDesktop)
					continue;
				if (rects_intersect (w.Geometry, rect))
					return true;
			}
			return false;
		}

		public bool maximized_window_intersects (Gdk.Rectangle rect)
		{
			foreach (var w in cached_windows) {
				if (!w.Maximized || w.Minimized || !w.CurrentDesktop)
					continue;
				if (rects_intersect (w.Geometry, rect))
					return true;
			}
			return false;
		}

		public bool fullscreen_window_intersects (Gdk.Rectangle rect)
		{
			foreach (var w in cached_windows) {
				if (!w.Fullscreen || w.Minimized || !w.CurrentDesktop)
					continue;
				if (rects_intersect (w.Geometry, rect))
					return true;
			}
			return false;
		}

		public void handle_system_resume ()
		{
			if (!started)
				return;
			refresh_windows ();
			state_changed ();
		}
	}
}
