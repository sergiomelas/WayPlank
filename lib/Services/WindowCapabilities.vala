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
	 * Core capability matrix maintained as compositor support evolves.
	 */
	public class WindowCapabilities : GLib.Object
	{
		const string MATRIX = "KDE=11111;LABWC=11111;WLROOTS=11100";
		
		static string display_name (string desktop)
		{
			switch (desktop) {
			case "KDE": return "KWin (KDE Plasma)";
			case "LABWC": return "Labwc";
			case "WLROOTS": return "wlroots-compatible compositors";
			default: return desktop;
			}
		}
		
		static string supported_compositors (bool fully)
		{
			var result = new StringBuilder ("");
			foreach (unowned string entry in MATRIX.split (";")) {
				var pair = entry.split ("=", 2);
				if (pair.length != 2)
					continue;
				var any = pair[1].contains ("1");
				var all = pair[1].replace ("1", "") == "";
				if (fully ? !all : !any || all)
					continue;
				if (result.len > 0)
					result.append (", ");
				result.append (display_name (pair[0]));
			}
			return result.str;
		}
		
		public static string fully_supported_compositors ()
		{
			return supported_compositors (true);
		}
		
		public static string partially_supported_compositors ()
		{
			return supported_compositors (false);
		}
		
		public static bool hide_mode_supported (HideType mode)
		{
			if (mode == HideType.NONE || mode == HideType.AUTO)
				return true;
			
			if (WindowControl.is_kwin ()) {
				return mode == HideType.INTELLIGENT
					|| mode == HideType.DODGE_MAXIMIZED
					|| mode == HideType.WINDOW_DODGE
					|| mode == HideType.DODGE_ACTIVE;
			}
			
			if (WindowControl.is_labwc ()) {
				return mode == HideType.DODGE_MAXIMIZED;
			}

			if (environment_is_session_desktop (XdgSessionDesktop.KDE)
				&& environment_is_session_type (XdgSessionType.WAYLAND)) {
				return mode == HideType.INTELLIGENT
					|| mode == HideType.DODGE_MAXIMIZED
					|| mode == HideType.WINDOW_DODGE
					|| mode == HideType.DODGE_ACTIVE;
			}
			
			return mode == HideType.DODGE_MAXIMIZED;
		}
	}
}
