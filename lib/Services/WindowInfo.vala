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
	 * Compositor-neutral state for one application window.
	 */
	public class WindowInfo : GLib.Object
	{
		public string Id { get; set; default = ""; }
		public string ApplicationId { get; set; default = ""; }
		public string DesktopFileName { get; set; default = ""; }
		public string ResourceClass { get; set; default = ""; }
		public string ResourceName { get; set; default = ""; }
		public string Executable { get; set; default = ""; }
		public bool Minimized { get; set; default = false; }
		public bool Active { get; set; default = false; }
		public bool Maximized { get; set; default = false; }
		public bool DemandsAttention { get; set; default = false; }
		public bool CurrentDesktop { get; set; default = true; }
		public int64 MinimizedSequence { get; set; default = 0; }
		public Gdk.Rectangle Geometry { get; set; default = {}; }
	}
}
