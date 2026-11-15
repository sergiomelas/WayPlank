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
		bool signals_connected = false;

		public FreedesktopWindowBackendAdapter ()
		{
			WindowControl.get_default ().state_changed.connect (on_state_changed);
			WindowControl.get_default ().bridge_reconnected.connect (on_bridge_reconnected);
			signals_connected = true;
		}

		~FreedesktopWindowBackendAdapter ()
		{
			disconnect_signals ();
		}

		void disconnect_signals ()
		{
			if (!signals_connected)
				return;
			signals_connected = false;
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
			disconnect_signals ();
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
	 * Aggregate Freedesktop D-Bus stack adapter implementing `IBusBackend` (`Hal.Bus`).
	 * Instantiates individual bus services lazily so unused docklets incur zero D-Bus traffic.
	 */
	class FreedesktopBusBackend : GLib.Object, IBusBackend
	{
		IDockIpcClient? _dock_ipc_client = null;
		IMediaController? _media = null;
		INotificationBus? _notifications = null;
		IDesktopThemeBus? _theme = null;
		ILauncherBadgeBus? _badges = null;
		IAppMenuBus? _app_menu = null;

		public IDockIpcServer create_dock_ipc_server (IDockIpcTarget target)
		{
			return new DockIpcServer (target);
		}

		public IDockIpcClient DockIpcClient {
			get {
				if (_dock_ipc_client == null)
					_dock_ipc_client = FreedesktopDockIpcClient.get_instance ();
				return _dock_ipc_client;
			}
		}

		public IMediaController Media {
			get {
				if (_media == null)
					_media = MprisDbusService.get_default ();
				return _media;
			}
		}

		public INotificationBus Notifications {
			get {
				if (_notifications == null)
					_notifications = NotificationDbusService.get_default ();
				return _notifications;
			}
		}

		public IDesktopThemeBus Theme {
			get {
				if (_theme == null)
					_theme = DesktopThemeDbusService.get_default ();
				return _theme;
			}
		}

		public ILauncherBadgeBus Badges {
			get {
				if (_badges == null)
					_badges = LauncherEntryDbusService.get_default ();
				return _badges;
			}
		}

		public IAppMenuBus AppMenu {
			get {
				if (_app_menu == null)
					_app_menu = AppMenuDbusService.get_default ();
				return _app_menu;
			}
		}

		public void cleanup ()
		{
			if (_dock_ipc_client != null)
				_dock_ipc_client.cleanup ();
			if (_media != null)
				_media.cleanup ();
			if (_notifications != null)
				_notifications.cleanup ();
			if (_theme != null)
				_theme.cleanup ();
			if (_badges != null)
				_badges.cleanup ();
			if (_app_menu != null)
				_app_menu.cleanup ();
			DbusBroker.get_default ().cleanup ();
		}
	}

	/**
	 * Aggregate Linux/Freedesktop hardware & session telemetry adapter (`Hal.Telemetry`).
	 * Instantiates individual providers lazily so unused docklets incur zero polling or I/O.
	 */
	class FreedesktopSystemTelemetry : GLib.Object, ISystemTelemetry
	{
		ISessionPowerProvider? _session_power = null;
		IBatteryProvider? _battery = null;
		IBrightnessProvider? _brightness = null;
		ICpuMemoryProvider? _cpu_memory = null;
		INetworkProvider? _network = null;
		IAudioProvider? _audio = null;
		IEjectorProvider? _ejector = null;
		IScreenshotProvider? _screenshot = null;
		ITrashProvider? _trash = null;

		public ISessionPowerProvider SessionPower {
			get {
				if (_session_power == null)
					_session_power = LinuxSessionPower.get_default ();
				return _session_power;
			}
		}

		public IBatteryProvider Battery {
			get {
				if (_battery == null)
					_battery = LinuxBatteryProvider.get_default ();
				return _battery;
			}
		}

		public IBrightnessProvider Brightness {
			get {
				if (_brightness == null)
					_brightness = BrightnessControl.get_default ();
				return _brightness;
			}
		}

		public ICpuMemoryProvider CpuMemory {
			get {
				if (_cpu_memory == null)
					_cpu_memory = LinuxCpuMemDiskTelemetry.get_default ();
				return _cpu_memory;
			}
		}

		public INetworkProvider Network {
			get {
				if (_network == null)
					_network = NetworkManagerDbusService.get_default ();
				return _network;
			}
		}

		public IAudioProvider Audio {
			get {
				if (_audio == null)
					_audio = LinuxAudioTelemetry.get_default ();
				return _audio;
			}
		}

		public IEjectorProvider Ejector {
			get {
				if (_ejector == null)
					_ejector = FreedesktopEjectorProvider.get_default ();
				return _ejector;
			}
		}

		public IScreenshotProvider Screenshot {
			get {
				if (_screenshot == null)
					_screenshot = FreedesktopScreenshotProvider.get_default ();
				return _screenshot;
			}
		}

		public ITrashProvider Trash {
			get {
				if (_trash == null)
					_trash = FreedesktopTrashProvider.get_default ();
				return _trash;
			}
		}

		public void cleanup ()
		{
			BrightnessControl.cleanup_if_active ();
			if (_network != null)
				_network.cleanup ();
			if (_ejector != null)
				_ejector.cleanup ();
			if (_trash != null)
				_trash.cleanup ();
			KWinTrashBridge.cleanup_if_active ();
		}
	}

	/**
	 * Southbound Freedesktop/Linux HAL bootstrapper linked exclusively into
	 * Linux/BSD builds via the `wayplank_hal_platform_*` link symbols.
	 */
	public class FreedesktopHalBootstrap : GLib.Object
	{
		[CCode (cname = "wayplank_hal_platform_early_runtime")]
		public static IPlatformRuntime early_runtime ()
		{
			return LinuxPlatformRuntime.get_default ();
		}

		[CCode (cname = "wayplank_hal_platform_early_apps")]
		public static IAppSystem early_apps ()
		{
			return XdgAppSystem.get_default ();
		}

		[CCode (cname = "wayplank_hal_platform_bootstrap")]
		public static void initialize ()
		{
			environment_initialize ();
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
			caps.uses_shell_anchored_surfaces = environment_is_session_type (XdgSessionType.WAYLAND) || GtkLayerShell.is_supported ();
			caps.unsupported_hide_mode_suffix = WindowControl.is_labwc () ? _(" (Requires KWin)") : "";
			caps.fully_supported_summary = WindowCapabilities.fully_supported_compositors ();
			caps.partially_supported_summary = WindowCapabilities.partially_supported_compositors ();

			var shell = new LayerShellDockShell ();
			IWindowBackend windows = new FreedesktopWindowBackendAdapter ();
			IThumbnailProvider thumbnails = caps.supports_live_thumbnails
				? (IThumbnailProvider) KWinThumbnailService.get_default ()
				: (IThumbnailProvider) new NullThumbnailProvider ();

			Hal.bind_display_stack (caps, shell, windows, thumbnails);
			Hal.bind_system_stack (
				new FreedesktopBusBackend (),
				new FreedesktopSystemTelemetry (),
				LinuxPlatformRuntime.get_default (),
				XdgAppSystem.get_default ()
			);
		}
	}
}
