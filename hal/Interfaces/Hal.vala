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
	[CCode (cname = "wayplank_hal_platform_bootstrap")]
	extern void hal_platform_bootstrap ();

	[CCode (cname = "wayplank_hal_platform_sync_autostart")]
	extern void hal_platform_sync_autostart (bool enabled);

	/**
	 * Northbound OS- and protocol-blind Hardware, Compositor & Bus Meta-Object.
	 * Core (`src/` + `lib/`) interacts exclusively with `Hal` without knowing
	 * which underlying compositor, display protocol, or OS driver is linked.
	 */
	public class Hal : GLib.Object
	{
		static PlatformCapabilities? capabilities_instance;
		static IDockShell? shell_instance;
		static IWindowBackend? windows_instance;
		static IThumbnailProvider? thumbnails_instance;

		public static PlatformCapabilities Capabilities {
			get {
				if (capabilities_instance == null)
					capabilities_instance = new PlatformCapabilities ();
				return capabilities_instance;
			}
		}

		public static IDockShell Shell {
			get {
				if (shell_instance == null)
					shell_instance = new NullDockShell ();
				return shell_instance;
			}
		}

		public static IWindowBackend Windows {
			get {
				if (windows_instance == null)
					windows_instance = new NullWindowBackend ();
				return windows_instance;
			}
		}

		public static IThumbnailProvider Thumbnails {
			get {
				if (thumbnails_instance == null)
					thumbnails_instance = new NullThumbnailProvider ();
				return thumbnails_instance;
			}
		}

		public static void initialize ()
		{
			hal_platform_bootstrap ();
		}

		public static void bind_display_stack (PlatformCapabilities capabilities,
			IDockShell shell, IWindowBackend windows, IThumbnailProvider thumbnails)
		{
			capabilities_instance = capabilities;
			shell_instance = shell;
			windows_instance = windows;
			thumbnails_instance = thumbnails;
		}

		public static void start ()
		{
			Windows.start ();
		}

		public static void cleanup ()
		{
			Windows.cleanup ();
		}

		public static void sync_autostart (bool enabled)
		{
			hal_platform_sync_autostart (enabled);
		}
	}
}
