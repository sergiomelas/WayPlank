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
	 * Compositor-agnostic facade for window control. Detects the active
	 * compositor once and forwards neutral operations to the matching backend.
	 */
	public class WindowControl : GLib.Object
	{
		/**
		 * Fired whenever the active backend's window state changes.
		 */
		public signal void state_changed ();
		public signal void primary_monitor_changed ();
		
		static WindowControl? instance;
		WindowBackend? backend;
		
		public static unowned WindowControl get_default ()
		{
			if (instance == null)
				instance = new WindowControl ();
			return instance;
		}
		
		WindowControl ()
		{
		}

		void bind_backend (WindowBackend b)
		{
			backend = b;
			backend.state_changed.connect (() => state_changed ());
			backend.primary_monitor_changed.connect (() => primary_monitor_changed ());
		}
		
		public static void initialize ()
		{
			unowned WindowControl self = get_default ();
			
			if (!environment_is_session_type (XdgSessionType.WAYLAND))
				return;

			// 1. Explicit override via WAYPLANK_BACKEND environment variable
			var backend_env = (Environment.get_variable ("WAYPLANK_BACKEND") ?? "").down ();
			if (backend_env == "mutter") {
				var mutter = new MutterBackend ();
				if (mutter.start ()) {
					self.bind_backend (mutter);
					message ("Wayplank: activated Mutter window backend (explicit override)");
					return;
				}
				mutter.cleanup ();
			}

			// 2. Probe for native wlroots/Labwc foreign toplevel protocol on current Wayland display
			var labwc = new LabwcBackend ();
			if (labwc.start ()) {
				self.bind_backend (labwc);
				message ("Wayplank: activated Labwc/wlroots window backend (wlr-foreign-toplevel)");
				return;
			}
			labwc.cleanup ();

			// 3. If under KDE Plasma AND Layer Shell is supported on this display, use KWin backend
			if (environment_is_session_desktop (XdgSessionDesktop.KDE) && GtkLayerShell.is_supported ()) {
				var kwin = new KWinBackend ();
				self.bind_backend (kwin);
				message ("Wayplank: activated KWin window backend (KDE Plasma)");
				return;
			}

			// 4. GNOME / Mutter fallback (if Layer Shell is not supported or GNOME session)
			if (backend_env == "mutter" || environment_is_session_desktop (XdgSessionDesktop.GNOME) || !GtkLayerShell.is_supported ()) {
				var mutter = new MutterBackend ();
				if (mutter.start ()) {
					self.bind_backend (mutter);
					message ("Wayplank: activated Mutter window backend (GNOME / non-layer-shell)");
					return;
				}
				mutter.cleanup ();
			}
		}

		public static void start ()
		{
			if (get_default ().backend != null)
				get_default ().backend.start ();
		}
		
		public static void cleanup ()
		{
			if (get_default ().backend != null)
				get_default ().backend.cleanup ();
		}

		public static bool has_state ()
		{
			return get_default ().backend != null && get_default ().backend.has_state ();
		}
		
		/**
		 * Whether any window intersects the given dock region.
		 */
		public static bool any_window_intersects (Gdk.Rectangle dock_rect)
		{
			return get_default ().backend != null && get_default ().backend.any_window_intersects (dock_rect);
		}
		
		/**
		 * Whether the active window intersects the given dock region.
		 */
		public static bool active_window_intersects (Gdk.Rectangle dock_rect)
		{
			return get_default ().backend != null && get_default ().backend.active_window_intersects (dock_rect);
		}
		
		/**
		 * Whether a maximized window intersects the given dock region.
		 */
		public static bool maximized_window_intersects (Gdk.Rectangle dock_rect)
		{
			return get_default ().backend != null && get_default ().backend.maximized_window_intersects (dock_rect);
		}

		public static Gee.ArrayList<WindowInfo> get_windows ()
		{
			return get_default ().backend != null
				? get_default ().backend.get_windows ()
				: new Gee.ArrayList<WindowInfo> ();
		}

		public static void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError
		{
			if (get_default ().backend != null)
				get_default ().backend.register_dbus (connection, object_path);
		}
		
		/**
		 * Decides which window/action a dock-icon click should trigger for the
		 * given desktop-file based app id. See the concrete backend for the
		 * exact single/multi-window/all-minimized rules.
		 *
		 * @param app_id the desktop-file based app id to search windows for
		 * @param target an opaque backend-specific handle for the resolved window
		 * @param action the action to apply ("toggle" or "activate")
		 * @return whether a matching window was found
		 */
		/**
		 * Queues an action for an opaque backend-provided window target.
		 */
		public static void queue_command (string target, string action)
		{
			if (get_default ().backend != null)
				get_default ().backend.queue_command (target, action);
		}

		public static void handle_system_resume ()
		{
			if (get_default ().backend != null)
				get_default ().backend.handle_system_resume ();
		}

		public static bool get_primary_monitor_geometry (out int x, out int y, out int width, out int height)
		{
			if (get_default ().backend != null) {
				return get_default ().backend.get_primary_monitor_geometry (out x, out y, out width, out height);
			}
			x = 0; y = 0; width = 0; height = 0;
			return false;
		}

		public static bool get_workarea_for_geometry (Gdk.Rectangle mon_geom, out Gdk.Rectangle workarea)
		{
			if (get_default ().backend != null) {
				return get_default ().backend.get_workarea_for_geometry (mon_geom, out workarea);
			}
			workarea = mon_geom;
			return false;
		}

		public static bool position_dock (int x, int y, int width, int height)
		{
			return get_default ().backend != null && get_default ().backend.position_dock (x, y, width, height);
		}

		public static bool position_hover (int x, int y, int width, int height)
		{
			return get_default ().backend != null && get_default ().backend.position_hover (x, y, width, height);
		}

		public static bool position_poof (int x, int y, int width, int height)
		{
			return get_default ().backend != null && get_default ().backend.position_poof (x, y, width, height);
		}

		public static bool is_kwin ()
		{
			return get_default ().backend is KWinBackend;
		}

		public static bool is_labwc ()
		{
			return get_default ().backend is LabwcBackend;
		}

		public static bool is_mutter ()
		{
			return get_default ().backend is MutterBackend;
		}
	}
}

