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
	 * Backend contract used by compositor-neutral window management code.
	 */
	public interface WindowBackend : GLib.Object
	{
		public signal void state_changed ();
		public signal void primary_monitor_changed ();
		public abstract bool start ();
		public abstract void cleanup ();
		public abstract bool has_state ();
		public abstract void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError;
		public abstract Gee.ArrayList<WindowInfo> get_windows ();
		public abstract bool queue_command (string target, string action);
		public abstract bool any_window_intersects (Gdk.Rectangle rect);
		public abstract bool active_window_intersects (Gdk.Rectangle rect);
		public abstract bool maximized_window_intersects (Gdk.Rectangle rect);
		public virtual void handle_system_resume () { }
		public virtual bool get_primary_monitor_geometry (out int x, out int y, out int width, out int height)
		{
			x = 0; y = 0; width = 0; height = 0;
			return false;
		}
		public virtual bool get_workarea_for_geometry (Gdk.Rectangle mon_geom, out Gdk.Rectangle workarea)
		{
			workarea = mon_geom;
			return false;
		}
		public virtual bool position_dock (int x, int y, int width, int height)
		{
			return false;
		}
		public virtual bool position_hover (int x, int y, int width, int height)
		{
			return false;
		}
		public virtual bool position_poof (int x, int y, int width, int height)
		{
			return false;
		}
	}
}
