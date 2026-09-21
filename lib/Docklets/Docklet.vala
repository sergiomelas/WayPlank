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
	 * The common interface for all docklets.
	 */
	public interface Docklet : Object
	{
		public abstract unowned string get_id ();
		
		public abstract unowned string get_name ();
		
		public abstract unowned string get_description ();
		
		public abstract unowned string get_icon ();
		
		public abstract bool is_supported ();
		
		public abstract Plank.DockElement make_element (string launcher, GLib.File file);
	}
}
