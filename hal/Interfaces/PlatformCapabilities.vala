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
	 * OS- and compositor-neutral capability descriptor populated at bootstrap
	 * by the active platform driver. Core and UI layers query these flags
	 * purely to present honest UI controls, never to branch driver logic.
	 */
	public class PlatformCapabilities : GLib.Object
	{
		public HideType fallback_hide_mode { get; set; default = HideType.DODGE_MAXIMIZED; }
		public bool supports_intelligent_hide { get; set; default = true; }
		public bool supports_dodge_all { get; set; default = true; }
		public bool supports_dodge_active { get; set; default = true; }
		public bool supports_dodge_maximized { get; set; default = true; }
		public bool supports_primary_display { get; set; default = true; }
		public bool supports_live_thumbnails { get; set; default = false; }
		public bool supports_panel_struts { get; set; default = true; }
		public bool supports_poof_overlay { get; set; default = true; }
		public bool supports_quit_action { get; set; default = true; }
		public bool supports_pressure_reveal { get; set; default = false; }
		public bool supports_hardware_brightness { get; set; default = true; }
		public string unsupported_hide_mode_suffix { get; set; default = ""; }
		public string fully_supported_summary { get; set; default = ""; }
		public string partially_supported_summary { get; set; default = ""; }

		public bool supports_hide_mode (HideType mode)
		{
			switch (mode) {
			case HideType.NONE:
			case HideType.AUTO:
				return true;
			case HideType.INTELLIGENT:
				return supports_intelligent_hide;
			case HideType.DODGE_MAXIMIZED:
				return supports_dodge_maximized;
			case HideType.WINDOW_DODGE:
				return supports_dodge_all;
			case HideType.DODGE_ACTIVE:
				return supports_dodge_active;
			default:
				return false;
			}
		}

		public string get_unsupported_hide_mode_hint (HideType mode)
		{
			return supports_hide_mode (mode) ? "" : unsupported_hide_mode_suffix;
		}
	}
}
