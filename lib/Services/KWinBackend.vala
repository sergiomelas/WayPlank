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
	 * Adapter between the neutral WindowBackend contract and KWinBridge.
	 */
	public class KWinBackend : GLib.Object, WindowBackend
	{
		public KWinBackend ()
		{
			KWinBridge.get_default ().state_changed.connect (forward_state_changed);
		}
		
		~KWinBackend ()
		{
			KWinBridge.get_default ().state_changed.disconnect (forward_state_changed);
		}
		
		void forward_state_changed ()
		{
			state_changed ();
		}
		
		public bool start ()
		{
			KWinBridge.start ();
			return true;
		}
		
		public void cleanup ()
		{
			KWinBridge.cleanup ();
		}

		public bool has_state ()
		{
			return KWinBridge.has_window_state ();
		}

		public void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError
		{
			KWinBridge.register_dbus (connection, object_path);
		}
		
		public Gee.ArrayList<WindowInfo> get_windows ()
		{
			return KWinBridge.get_window_infos ();
		}
		
		public bool queue_command (string target, string action)
		{
			KWinBridge.queue_command (target, action);
			return true;
		}
		
		public bool any_window_intersects (Gdk.Rectangle rect)
		{
			return KWinBridge.any_window_intersects (rect);
		}
		
		public bool active_window_intersects (Gdk.Rectangle rect)
		{
			return KWinBridge.active_window_intersects (rect);
		}
		
		public bool maximized_window_intersects (Gdk.Rectangle rect)
		{
			return KWinBridge.maximized_window_intersects (rect);
		}
	}
}
