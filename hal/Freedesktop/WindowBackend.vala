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
	 * Backend contract used by compositor-neutral window management code.
	 */
	public interface WindowBackend : GLib.Object
	{
		public signal void state_changed ();
		public signal void primary_monitor_changed ();
		public signal void bridge_reconnected ();
		public abstract bool start ();
		public abstract void cleanup ();
		public abstract bool has_state ();
		public abstract void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError;
		public abstract Gee.ArrayList<WindowInfo> get_windows ();
		public abstract bool queue_command (string target, string action);
		public abstract bool any_window_intersects (Gdk.Rectangle rect);
		public abstract bool active_window_intersects (Gdk.Rectangle rect);
		public abstract bool maximized_window_intersects (Gdk.Rectangle rect);
		public virtual bool fullscreen_window_intersects (Gdk.Rectangle rect)
		{
			return false;
		}
		public virtual void handle_system_resume () { }
		public virtual void invalidate_panel_cache () { }
		public virtual int get_top_panel_floating_offset (Gdk.Rectangle mon_geom = Gdk.Rectangle ())
		{
			return 0;
		}
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
		public virtual bool position_dock_for (string dock_key, int x, int y, int width, int height)
		{
			return position_dock (x, y, width, height);
		}
		public virtual bool position_hover (int x, int y, int width, int height)
		{
			return false;
		}
		public virtual bool position_hover_for (int pid, int x, int y, int width, int height)
		{
			return position_hover (x, y, width, height);
		}
		public virtual bool position_poof (int x, int y, int width, int height)
		{
			return false;
		}
		public virtual bool position_poof_for (int pid, int x, int y, int width, int height)
		{
			return position_poof (x, y, width, height);
		}
		public virtual void set_reserve_space (bool enabled, int thickness, Gtk.PositionType position) { }
		public virtual void set_reserve_space_for (string dock_key, bool enabled, int thickness, Gtk.PositionType position)
		{
			set_reserve_space (enabled, thickness, position);
		}
		public virtual void release_dock_surface (string dock_key) { }
	}
}
