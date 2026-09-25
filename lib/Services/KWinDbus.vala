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
	[DBus (name = "net.launchpad.plank.KWin")]
	interface DBusKWinIface : GLib.Object
	{
		public abstract void update_window_state (string state) throws GLib.DBusError, GLib.IOError;
		public abstract string fetch_pending_command () throws GLib.DBusError, GLib.IOError;
	}

	/**
	 * KWin-specific D-Bus endpoint used by the injected KWin script.
	 */
	class KWinDbus : GLib.Object, Plank.DBusKWinIface
	{
		public void update_window_state (string state)
		{
			KWinBridge.update_window_state (state);
		}
		
		public string fetch_pending_command ()
		{
			return KWinBridge.fetch_pending_command ();
		}
	}
}
