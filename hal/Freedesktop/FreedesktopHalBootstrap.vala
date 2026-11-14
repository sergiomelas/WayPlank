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
	 * Pure 1-to-1 pass-through adapter bridging the northbound OS-blind
	 * `IWindowBackend` translator contract directly to the untouched
	 * `WindowControl` Freedesktop facade.
	 */
	class FreedesktopWindowBackendAdapter : GLib.Object, IWindowBackend
	{
		public FreedesktopWindowBackendAdapter ()
		{
			WindowControl.get_default ().state_changed.connect (on_state_changed);
			WindowControl.get_default ().bridge_reconnected.connect (on_bridge_reconnected);
		}

		~FreedesktopWindowBackendAdapter ()
		{
			WindowControl.get_default ().state_changed.disconnect (on_state_changed);
			WindowControl.get_default ().bridge_reconnected.disconnect (on_bridge_reconnected);
		}

		void on_state_changed ()
		{
			state_changed ();
		}

		void on_bridge_reconnected ()
		{
			bridge_reconnected ();
		}

		public bool start ()
		{
			WindowControl.start ();
			return WindowControl.has_state ();
		}

		public void cleanup ()
		{
			WindowControl.cleanup ();
		}

		public bool has_state ()
		{
			return WindowControl.has_state ();
		}

		public Gee.ArrayList<WindowInfo> get_windows ()
		{
			return WindowControl.get_windows ();
		}

		public bool perform_window_action (string win_id, WindowAction action)
		{
			WindowControl.queue_command (win_id, action.to_command_name ());
			return true;
		}

		public bool toggle_show_desktop ()
		{
			WindowControl.queue_command ("desktop", "toggle_desktop");
			return true;
		}

		public bool any_window_intersects (Gdk.Rectangle rect)
		{
			return WindowControl.any_window_intersects (rect);
		}

		public bool active_window_intersects (Gdk.Rectangle rect)
		{
			return WindowControl.active_window_intersects (rect);
		}

		public bool maximized_window_intersects (Gdk.Rectangle rect)
		{
			return WindowControl.maximized_window_intersects (rect);
		}

		public bool fullscreen_window_intersects (Gdk.Rectangle rect)
		{
			return WindowControl.fullscreen_window_intersects (rect);
		}

		public void handle_system_resume ()
		{
			WindowControl.handle_system_resume ();
		}
	}

	/**
	 * Southbound Freedesktop/Wayland HAL bootstrapper linked exclusively into
	 * Linux/BSD builds via the `wayplank_hal_platform_*` link symbols.
	 */
	public class FreedesktopHalBootstrap : GLib.Object
	{
		[CCode (cname = "wayplank_hal_platform_bootstrap")]
		public static void initialize ()
		{
			WindowControl.initialize ();

			var caps = new PlatformCapabilities ();
			caps.supports_intelligent_hide = WindowCapabilities.hide_mode_supported (HideType.INTELLIGENT);
			caps.supports_dodge_maximized = WindowCapabilities.hide_mode_supported (HideType.DODGE_MAXIMIZED);
			caps.supports_dodge_all = WindowCapabilities.hide_mode_supported (HideType.WINDOW_DODGE);
			caps.supports_dodge_active = WindowCapabilities.hide_mode_supported (HideType.DODGE_ACTIVE);
			caps.fallback_hide_mode = WindowControl.is_mutter () ? HideType.AUTO : HideType.DODGE_MAXIMIZED;
			caps.supports_primary_display = WindowCapabilities.primary_display_supported ();
			caps.supports_live_thumbnails = WindowControl.is_kwin () || WindowControl.is_mutter ();
			caps.supports_panel_struts = true;
			caps.supports_poof_overlay = !WindowControl.is_labwc ();
			caps.supports_quit_action = !environment_is_session_desktop (XdgSessionDesktop.PANTHEON);
			caps.supports_pressure_reveal = !environment_is_session_type (XdgSessionType.WAYLAND);
			caps.supports_hardware_brightness = true;
			caps.unsupported_hide_mode_suffix = WindowControl.is_labwc () ? _(" (Requires KWin)") : "";
			caps.fully_supported_summary = WindowCapabilities.fully_supported_compositors ();
			caps.partially_supported_summary = WindowCapabilities.partially_supported_compositors ();

			var shell = new LayerShellDockShell ();
			IWindowBackend windows = new FreedesktopWindowBackendAdapter ();
			IThumbnailProvider thumbnails = caps.supports_live_thumbnails
				? (IThumbnailProvider) KWinThumbnailService.get_default ()
				: (IThumbnailProvider) new NullThumbnailProvider ();

			Hal.bind_display_stack (caps, shell, windows, thumbnails);
		}

		[CCode (cname = "wayplank_hal_platform_register_dbus")]
		public static void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError
		{
			WindowControl.register_dbus (connection, object_path);
		}

		[CCode (cname = "wayplank_hal_platform_sync_autostart")]
		public static void sync_autostart (bool enabled)
		{
			WindowControl.sync_autostart (enabled);
		}
	}
}
