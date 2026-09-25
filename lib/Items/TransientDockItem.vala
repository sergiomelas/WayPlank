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
	 * A dock item for applications which aren't pinned or doesn't have a matched desktop-files.
	 *
	 * Usually this represents a running application while it is possible it is a virtual item
	 * added through e.g. libunity-support to show specific application information.
	 */
	public class TransientDockItem : ApplicationDockItem
	{
		public TransientDockItem.with_launcher (string launcher_uri)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_launcher (launcher_uri));
		}
		
		construct
		{
			if (Prefs.Launcher != "")
				load_from_launcher ();
			else
				critical ("No source of information for this item available");
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override bool can_be_removed ()
		{
			return false;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override bool is_valid ()
		{
			return true;
		}
	}
}
