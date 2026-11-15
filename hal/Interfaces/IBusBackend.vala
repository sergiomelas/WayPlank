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
	 * Pure domain callback interface implemented by `DockController` so external
	 * automation RPC drivers can inspect or mutate dock items without exposing
	 * wire protocols to `lib/`.
	 */
	public interface IDockIpcTarget : GLib.Object
	{
		public signal void ipc_elements_changed ();
		public abstract string get_ipc_dock_name ();
		public abstract GLib.File get_ipc_config_folder ();
		public abstract bool ipc_add_item (string uri);
		public abstract bool ipc_remove_item (string uri);
		public abstract int ipc_get_item_count ();
		public abstract string[] ipc_get_persistent_applications ();
		public abstract string[] ipc_get_transient_applications ();
		public abstract bool ipc_get_hover_position (string uri, out int x, out int y, out Gtk.PositionType dock_position);
	}

	/**
	 * OS-agnostic RPC endpoint exported for a single `DockController` instance.
	 */
	public interface IDockIpcServer : GLib.Object
	{
		public abstract void dispose_ipc ();
	}

	/**
	 * OS-agnostic client proxy for external automation consumers.
	 */
	public interface IDockIpcClient : GLib.Object
	{
		public signal void proxy_changed ();
		public abstract bool is_connected { get; }
		public abstract bool add_item (string uri);
		public abstract bool remove_item (string uri);
		public abstract int get_count ();
		public abstract string[]? get_persistent_applications ();
		public abstract string[]? get_transient_applications ();
		public abstract bool get_hover_position (string uri, out int x, out int y, out Gtk.PositionType dock_position);
	}

	/**
	 * Normalized media player snapshot unpacked south of `hal/Interfaces/`.
	 */
	public class MediaPlayerInfo : GLib.Object
	{
		public string player_id = "";
		public string identity = "";
		public string status = "Stopped";
		public string title = "";
		public string artist = "";
		public bool is_browser = false;
		public bool can_pause = true;
	}

	/**
	 * Agnostic media transport controller translator.
	 */
	public interface IMediaController : GLib.Object
	{
		public signal void players_changed ();
		public abstract bool has_event_subscription ();
		public abstract bool probe_players_sync (out Gee.ArrayList<MediaPlayerInfo> players);
		public abstract bool pause_player_sync (string player_id);
		public abstract bool send_player_command_sync (string player_id, string command);
		public abstract void cleanup ();
	}

	/**
	 * Agnostic desktop notification, Do-Not-Disturb, and badge-visibility translator.
	 */
	public interface INotificationBus : GLib.Object
	{
		public signal void show_launcher_badges_changed ();
		public signal void dnd_state_changed (bool inhibited);

		public abstract bool show_launcher_badges { get; }
		public abstract bool has_instant_dnd_settings ();
		public abstract bool has_push_dnd_subscription ();
		public abstract bool get_instant_dnd_inhibited ();
		public abstract bool probe_dnd_inhibited_sync ();
		public abstract void inhibit_dnd ();
		public abstract void uninhibit_dnd ();
		public abstract void send_toast (string summary, string body, string icon_name);
		public abstract void cleanup ();
	}

	/**
	 * Agnostic desktop dark/light color-scheme translator.
	 */
	public interface IDesktopThemeBus : GLib.Object
	{
		public signal void color_scheme_changed ();
		public signal void gtk_theme_changed ();

		public abstract bool query_prefer_dark (out bool prefer_dark);
		public abstract double get_font_scale_factor ();
		public abstract void cleanup ();
	}

	/**
	 * Normalized launcher badge/progress payload unpacked south of `hal/Interfaces/`.
	 */
	public struct LauncherBadgeState
	{
		public string app_uri;
		public bool has_count;
		public int64 count;
		public bool has_count_visible;
		public bool count_visible;
		public bool has_progress;
		public double progress;
		public bool has_progress_visible;
		public bool progress_visible;
		public bool has_urgent;
		public bool urgent;
	}

	/**
	 * Pure domain badge receiver implemented by `ApplicationDockItemProvider`.
	 */
	public interface ILauncherBadgeClient : GLib.Object
	{
		public abstract void update_launcher_entry (string sender_id, LauncherBadgeState state, bool is_retry = false);
		public abstract void remove_launcher_entry (string sender_id);
	}

	/**
	 * Agnostic application badge & progress bus translator.
	 */
	public interface ILauncherBadgeBus : GLib.Object
	{
		public abstract void add_client (ILauncherBadgeClient client);
		public abstract void remove_client (ILauncherBadgeClient client);
		public abstract void cleanup ();
	}

	/**
	 * Aggregate northbound IPC & desktop event bus contract (`Hal.Bus`).
	 */
	public interface IBusBackend : GLib.Object
	{
		public abstract IDockIpcServer create_dock_ipc_server (IDockIpcTarget target);
		public abstract IDockIpcClient DockIpcClient { get; }
		public abstract IMediaController Media { get; }
		public abstract INotificationBus Notifications { get; }
		public abstract IDesktopThemeBus Theme { get; }
		public abstract ILauncherBadgeBus Badges { get; }
		public abstract void cleanup ();
	}

	internal class NullDockIpcServer : GLib.Object, IDockIpcServer
	{
		public void dispose_ipc () {}
	}

	internal class NullDockIpcClient : GLib.Object, IDockIpcClient
	{
		public bool is_connected { get { return false; } }
		public bool add_item (string uri) { return false; }
		public bool remove_item (string uri) { return false; }
		public int get_count () { return -1; }
		public string[]? get_persistent_applications () { return null; }
		public string[]? get_transient_applications () { return null; }
		public bool get_hover_position (string uri, out int x, out int y, out Gtk.PositionType dock_position)
		{
			x = -1;
			y = -1;
			dock_position = Gtk.PositionType.BOTTOM;
			return false;
		}
	}

	internal class NullMediaController : GLib.Object, IMediaController
	{
		public bool has_event_subscription () { return false; }
		public bool probe_players_sync (out Gee.ArrayList<MediaPlayerInfo> players)
		{
			players = new Gee.ArrayList<MediaPlayerInfo> ();
			return false;
		}
		public bool pause_player_sync (string player_id) { return false; }
		public bool send_player_command_sync (string player_id, string command) { return false; }
		public void cleanup () {}
	}

	internal class NullNotificationBus : GLib.Object, INotificationBus
	{
		public bool show_launcher_badges { get { return true; } }
		public bool has_instant_dnd_settings () { return false; }
		public bool has_push_dnd_subscription () { return false; }
		public bool get_instant_dnd_inhibited () { return false; }
		public bool probe_dnd_inhibited_sync () { return false; }
		public void inhibit_dnd () {}
		public void uninhibit_dnd () {}
		public void send_toast (string summary, string body, string icon_name) {}
		public void cleanup () {}
	}

	internal class NullDesktopThemeBus : GLib.Object, IDesktopThemeBus
	{
		public bool query_prefer_dark (out bool prefer_dark)
		{
			prefer_dark = false;
			return false;
		}
		public double get_font_scale_factor () { return 1.0; }
		public void cleanup () {}
	}

	internal class NullLauncherBadgeBus : GLib.Object, ILauncherBadgeBus
	{
		public void add_client (ILauncherBadgeClient client) {}
		public void remove_client (ILauncherBadgeClient client) {}
		public void cleanup () {}
	}

	internal class NullBusBackend : GLib.Object, IBusBackend
	{
		IDockIpcClient ipc_client = new NullDockIpcClient ();
		IMediaController media = new NullMediaController ();
		INotificationBus notifications = new NullNotificationBus ();
		IDesktopThemeBus theme = new NullDesktopThemeBus ();
		ILauncherBadgeBus badges = new NullLauncherBadgeBus ();

		public IDockIpcServer create_dock_ipc_server (IDockIpcTarget target)
		{
			return new NullDockIpcServer ();
		}

		public IDockIpcClient DockIpcClient { get { return ipc_client; } }
		public IMediaController Media { get { return media; } }
		public INotificationBus Notifications { get { return notifications; } }
		public IDesktopThemeBus Theme { get { return theme; } }
		public ILauncherBadgeBus Badges { get { return badges; } }
		public void cleanup () {}
	}
}
