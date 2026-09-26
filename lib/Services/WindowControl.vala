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
	public enum Struts
	{
		LEFT,
		RIGHT,
		TOP,
		BOTTOM,
		LEFT_START,
		LEFT_END,
		RIGHT_START,
		RIGHT_END,
		TOP_START,
		TOP_END,
		BOTTOM_START,
		BOTTOM_END,
		N_VALUES
	}
	
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
		
		public static void initialize ()
		{
			unowned WindowControl self = get_default ();
			
			if (environment_is_session_desktop (XdgSessionDesktop.KDE)
				&& environment_is_session_type (XdgSessionType.WAYLAND)) {
				self.backend = new KWinBackend ();
				self.backend.state_changed.connect (() => self.state_changed ());
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

	}
}

