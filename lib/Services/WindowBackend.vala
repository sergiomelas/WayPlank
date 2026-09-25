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
		public abstract bool start ();
		public abstract void cleanup ();
		public abstract bool has_state ();
		public abstract void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError;
		public abstract Gee.ArrayList<WindowInfo> get_windows ();
		public abstract bool queue_command (string target, string action);
		public abstract bool any_window_intersects (Gdk.Rectangle rect);
		public abstract bool active_window_intersects (Gdk.Rectangle rect);
		public abstract bool maximized_window_intersects (Gdk.Rectangle rect);
	}
}
