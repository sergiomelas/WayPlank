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
	 * Normalized window management action requested by Core UI policies.
	 */
	public enum WindowAction
	{
		ACTIVATE,
		TOGGLE,
		MINIMIZE,
		CLOSE;

		public static WindowAction from_command_name (string action)
		{
			switch (action) {
			case "toggle":
				return WindowAction.TOGGLE;
			case "minimize":
				return WindowAction.MINIMIZE;
			case "close":
				return WindowAction.CLOSE;
			default:
			case "activate":
				return WindowAction.ACTIVATE;
			}
		}

		public unowned string to_command_name ()
		{
			switch (this) {
			case WindowAction.TOGGLE:
				return "toggle";
			case WindowAction.MINIMIZE:
				return "minimize";
			case WindowAction.CLOSE:
				return "close";
			default:
			case WindowAction.ACTIVATE:
				return "activate";
			}
		}
	}

	/**
	 * OS- and transport-blind contract for enumerating, intersecting, and
	 * controlling desktop application windows.
	 */
	public interface IWindowBackend : GLib.Object
	{
		public signal void state_changed ();
		public signal void bridge_reconnected ();

		public abstract bool start ();
		public abstract void cleanup ();
		public abstract bool has_state ();
		public abstract Gee.ArrayList<WindowInfo> get_windows ();
		public abstract bool perform_window_action (string win_id, WindowAction action);
		public abstract bool toggle_show_desktop ();
		public abstract bool any_window_intersects (Gdk.Rectangle rect);
		public abstract bool active_window_intersects (Gdk.Rectangle rect);
		public abstract bool maximized_window_intersects (Gdk.Rectangle rect);

		public virtual bool fullscreen_window_intersects (Gdk.Rectangle rect)
		{
			return false;
		}

		public virtual void handle_system_resume ()
		{
		}
	}

	/**
	 * Safe no-op window backend used when no compositor window driver is bound.
	 */
	public class NullWindowBackend : GLib.Object, IWindowBackend
	{
		public bool start ()
		{
			return false;
		}

		public void cleanup ()
		{
		}

		public bool has_state ()
		{
			return false;
		}

		public Gee.ArrayList<WindowInfo> get_windows ()
		{
			return new Gee.ArrayList<WindowInfo> ();
		}

		public bool perform_window_action (string win_id, WindowAction action)
		{
			return false;
		}

		public bool toggle_show_desktop ()
		{
			return false;
		}

		public bool any_window_intersects (Gdk.Rectangle rect)
		{
			return false;
		}

		public bool active_window_intersects (Gdk.Rectangle rect)
		{
			return false;
		}

		public bool maximized_window_intersects (Gdk.Rectangle rect)
		{
			return false;
		}
	}
}
