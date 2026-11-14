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

[CCode (cprefix = "wlr_toplevel_bridge_", lower_case_cprefix = "wlr_toplevel_bridge_", cheader_filename = "wlr-toplevel-bridge.h")]
namespace Plank.WlrBridge {
	[CCode (has_target = false)]
	public delegate void StateChangedCallback ();

	public static bool init (StateChangedCallback callback);
	public static void cleanup ();
	public static bool is_available ();
	public static string get_window_json ();
	public static bool queue_command (string target, string action);
	public static bool any_window_intersects (int x, int y, int width, int height);
	public static bool active_window_intersects (int x, int y, int width, int height);
	public static bool maximized_window_intersects (int x, int y, int width, int height);
	public static bool fullscreen_window_intersects (int x, int y, int width, int height);
}
