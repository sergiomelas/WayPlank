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
	public class KWinBridge : GLib.Object
	{
		const string KWIN_SCRIPT =
			"var wayplankService = \"net.launchpad.plank\";\n"
			+ "var wayplankPath = \"/net/launchpad/plank/KWin\";\n"
			+ "var wayplankInterface = \"net.launchpad.plank.KWin\";\n"
			+ "var wayplankMinimizeSequence = 0;\n"
			+ "var wayplankMinimizedWindows = {};\n"
			+ "\n"
			+ "function sendWindowState () {\n"
			+ "    var windows = [];\n"
			+ "    workspace.stackingOrder.forEach(function (client) {\n"
			+ "        var uuid = String(client.internalId);\n"
			+ "        if (client.minimized === true && !wayplankMinimizedWindows[uuid])\n"
			+ "            wayplankMinimizedWindows[uuid] = ++wayplankMinimizeSequence;\n"
			+ "        else if (client.minimized !== true)\n"
			+ "            delete wayplankMinimizedWindows[uuid];\n"
			+ "        windows.push({\n"
			+ "            uuid: uuid,\n"
			+ "            caption: client.caption,\n"
			+ "            resourceClass: client.resourceClass,\n"
			+ "            resourceName: client.resourceName,\n"
			+ "            desktopFileName: client.desktopFileName,\n"
			+ "            pid: client.pid,\n"
			+ "            x: client.frameGeometry.x,\n"
			+ "            y: client.frameGeometry.y,\n"
			+ "            width: client.frameGeometry.width,\n"
			+ "            height: client.frameGeometry.height,\n"
			+ "            minimized: client.minimized === true,\n"
			+ "            minimizedSequence: wayplankMinimizedWindows[uuid] || 0,\n"
			+ "            demandsAttention: client.demandsAttention === true,\n"
			+ "            maximized: (typeof client.maximizeMode === \"number\" && client.maximizeMode !== 0),\n"
			+ "            active: client === workspace.activeWindow,\n"
			+ "            normal: client.normalWindow !== false,\n"
			+ "            visible: client.visible !== false,\n"
			+ "            currentDesktop: client.onCurrentDesktop !== false\n"
			+ "        });\n"
			+ "    });\n"
			+ "    callDBus(wayplankService, wayplankPath, wayplankInterface,\n"
			+ "        \"UpdateWindowState\", JSON.stringify(windows));\n"
			+ "}\n"
			+ "\n"
			+ "function connectWindow (window) {\n"
			+ "    window.frameGeometryChanged.connect(sendWindowState);\n"
			+ "    window.minimizedChanged.connect(sendWindowState);\n"
			+ "    window.maximizedChanged.connect(sendWindowState);\n"
			+ "    window.activeChanged.connect(sendWindowState);\n"
			+ "}\n"
			+ "\n"
			+ "workspace.windowAdded.connect(function (window) {\n"
			+ "    connectWindow(window);\n"
			+ "    sendWindowState();\n"
			+ "});\n"
			+ "workspace.windowRemoved.connect(sendWindowState);\n"
			+ "workspace.windowActivated.connect(sendWindowState);\n"
			+ "workspace.stackingOrder.forEach(connectWindow);\n"
			+ "sendWindowState();\n"
			+ "\n"
			+ "function normalizeApplicationIdentity (value) {\n"
			+ "    return String(value || \"\").toLowerCase().replace(/\\.desktop$/, \"\");\n"
			+ "}\n"
			+ "\n"
			+ "function applicationIdentityMatches (client, appId) {\n"
			+ "    var identities = [client.desktopFileName, client.resourceClass, client.resourceName];\n"
			+ "    for (var i = 0; i < identities.length; i++) {\n"
			+ "        var identity = normalizeApplicationIdentity(identities[i]);\n"
			+ "        if (identity === appId)\n"
			+ "            return true;\n"
			+ "        var separator = identity.lastIndexOf(\".\");\n"
			+ "        if (separator >= 0 && identity.substring(separator + 1) === appId)\n"
			+ "            return true;\n"
			+ "    }\n"
			+ "    return false;\n"
			+ "}\n"
			+ "\n"
			+ "function applyWindowCommand (uuid, action) {\n"
			+ "    var target = null;\n"
			+ "    workspace.stackingOrder.forEach(function (client) {\n"
			+ "        if (String(client.internalId) === uuid)\n"
			+ "            target = client;\n"
			+ "    });\n"
			+ "    if (!target)\n"
			+ "        return;\n"
			+ "\n"
			+ "    if (action === \"activate\") {\n"
			+ "        if (target.minimized)\n"
			+ "            target.minimized = false;\n"
			+ "        workspace.activeWindow = target;\n"
			+ "    } else if (action === \"toggle\") {\n"
			+ "        if (target.minimized) {\n"
			+ "            target.minimized = false;\n"
			+ "            workspace.activeWindow = target;\n"
			+ "        } else if (target === workspace.activeWindow) {\n"
			+ "            target.minimized = true;\n"
			+ "        } else {\n"
			+ "            workspace.activeWindow = target;\n"
			+ "        }\n"
			+ "    }\n"
			+ "}\n"
			+ "\n"
			+ "function pollWayplankCommand () {\n"
			+ "    callDBus(wayplankService, wayplankPath, wayplankInterface, \"FetchPendingCommand\",\n"
			+ "        function (reply) {\n"
			+ "            if (!reply)\n"
			+ "                return;\n"
			+ "            print(\"Wayplank: received pending command: \" + reply);\n"
			+ "            try {\n"
			+ "                var cmd = JSON.parse(reply);\n"
			+ "                if (cmd && cmd.uuid)\n"
			+ "                    applyWindowCommand(cmd.uuid, cmd.action);\n"
			+ "            } catch (e) {\n"
			+ "                print(\"Wayplank: invalid pending command: \" + e);\n"
			+ "            }\n"
			+ "        });\n"
			+ "}\n"
			+ "\n"
			+ "print(\"Wayplank: KWin bridge script loaded, command channel ready\");\n"
			+ "\n"
			+ "var wayplankShortcutRegistered = registerShortcut(\n"
			+ "    \"WayplankApplyCommand\", \"Wayplank: Apply pending window command\", \"\",\n"
			+ "    pollWayplankCommand);\n"
			+ "print(\"Wayplank: command shortcut registered: \" + wayplankShortcutRegistered);\n";

		static KWinBridge? instance;
		static string? window_state;
		static Gee.ArrayList<WindowInfo> window_infos = new Gee.ArrayList<WindowInfo> ();
		static string? script_path;
		static DBusConnection? dbus_connection;
		static uint dbus_registration_id = 0U;
		public signal void state_changed ();

		public static unowned KWinBridge get_default ()
		{
			if (instance == null)
				instance = new KWinBridge ();
			return instance;
		}

		public static void update_window_state (string state)
		{
			window_state = state;
			window_infos = parse_window_infos (state);
			get_default ().state_changed ();
		}

		public static bool has_window_state ()
		{
			return window_state != null;
		}

		public static void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError
		{
			if (dbus_registration_id > 0U && dbus_connection != null) {
				dbus_connection.unregister_object (dbus_registration_id);
				dbus_registration_id = 0U;
			}
			dbus_connection = connection;
		var kwin_path = "%s/KWin".printf (object_path.substring (0, object_path.last_index_of ("/")));
			dbus_registration_id = connection.register_object<Plank.DBusKWinIface> (kwin_path, new KWinDbus ());
		}

		public static Gee.ArrayList<WindowInfo> get_window_infos ()
		{
			var result = new Gee.ArrayList<WindowInfo> ();
			result.add_all (window_infos);
			return result;
		}

		static Gee.ArrayList<WindowInfo> parse_window_infos (string state)
		{
			var result = new Gee.ArrayList<WindowInfo> ();
			try {
				var parser = new Json.Parser ();
				parser.load_from_data (state);
				foreach (var node in parser.get_root ().get_array ().get_elements ()) {
					var json = node.get_object ();
					if (!json.has_member ("uuid"))
						continue;
					var info = new WindowInfo ();
					info.Id = json.get_string_member ("uuid");
					info.DesktopFileName = json.has_member ("desktopFileName") ? json.get_string_member ("desktopFileName") : "";
					info.ResourceClass = json.has_member ("resourceClass") ? json.get_string_member ("resourceClass") : "";
					info.ResourceName = json.has_member ("resourceName") ? json.get_string_member ("resourceName") : "";
					if (info.DesktopFileName != "")
						info.ApplicationId = normalize_resource_id (json.get_string_member ("desktopFileName"));
					else if (info.ResourceClass != "")
						info.ApplicationId = normalize_resource_id (info.ResourceClass);
					else
						info.ApplicationId = normalize_resource_id (info.ResourceName);
					info.Minimized = json.has_member ("minimized") && json.get_boolean_member ("minimized");
					info.Active = json.has_member ("active") && json.get_boolean_member ("active");
					info.Maximized = json.has_member ("maximized") && json.get_boolean_member ("maximized");
					info.DemandsAttention = json.has_member ("demandsAttention") && json.get_boolean_member ("demandsAttention");
					info.CurrentDesktop = !json.has_member ("currentDesktop") || json.get_boolean_member ("currentDesktop");
					info.MinimizedSequence = json.has_member ("minimizedSequence") ? json.get_int_member ("minimizedSequence") : 0;
					if (json.has_member ("x") && json.has_member ("y") && json.has_member ("width") && json.has_member ("height"))
						info.Geometry = { (int) json.get_double_member ("x"), (int) json.get_double_member ("y"),
							(int) json.get_double_member ("width"), (int) json.get_double_member ("height") };
					result.add (info);
				}
			} catch (Error e) {
				debug ("Unable to convert KWin window state: %s", e.message);
			}
			return result;
		}

		static string? pending_command_uuid;
		static string? pending_command_action;

		/**
		 * Queues a window command (e.g. "activate" or "toggle") to be applied
		 * the next time the KWin script polls for pending commands.
		 */
		public static void queue_command (string uuid, string action)
		{
			message ("Wayplank: queued KWin command uuid=%s action=%s", uuid, action);
			pending_command_uuid = uuid;
			pending_command_action = action;
			invoke_apply_shortcut ();
		}
		
		/**
		 * Triggers the KWin script's registered global shortcut via KGlobalAccel's
		 * D-Bus interface, which runs its callback immediately without requiring
		 * an actual key combination to be pressed.
		 */
		static void invoke_apply_shortcut ()
		{
			try {
				var connection = Bus.get_sync (BusType.SESSION, null);
				connection.call_sync ("org.kde.kglobalaccel", "/component/kwin",
					"org.kde.kglobalaccel.Component", "invokeShortcut",
					new Variant ("(s)", "WayplankApplyCommand"),
					null, DBusCallFlags.NONE, -1, null);
				message ("Wayplank: invoked KWin shortcut to apply pending command");
			} catch (Error e) {
				warning ("Wayplank: unable to invoke KWin shortcut (%s)", e.message);
			}
		}

		/**
		 * Returns and clears the currently queued command as a JSON string,
		 * or an empty string if none is pending. Called by the KWin script.
		 */
		public static string fetch_pending_command ()
		{
			if (pending_command_uuid == null)
				return "";
			
			message ("Wayplank: KWin script fetched pending command uuid=%s action=%s", pending_command_uuid, pending_command_action);

			var builder = new Json.Builder ();
			builder.begin_object ();
			builder.set_member_name ("uuid");
			builder.add_string_value (pending_command_uuid);
			builder.set_member_name ("action");
			builder.add_string_value (pending_command_action);
			builder.end_object ();

			pending_command_uuid = null;
			pending_command_action = null;

			var generator = new Json.Generator ();
			generator.set_root (builder.get_root ());
			return generator.to_data (null);
		}

		static string normalize_resource_id (string id)
		{
			var normalized = id.down ();
			if (normalized.has_suffix (".desktop"))
				normalized = normalized.substring (0, normalized.length - ".desktop".length);
			return normalized;
		}

		public static void cleanup ()
		{
			if (dbus_registration_id > 0U && dbus_connection != null) {
				dbus_connection.unregister_object (dbus_registration_id);
				dbus_registration_id = 0U;
			}
			dbus_connection = null;
			if (script_path == null)
				return;

			try {
				FileUtils.remove (script_path);
			} catch (Error e) {
				debug ("Unable to remove temporary KWin script: %s", e.message);
			}
			script_path = null;
		}

		public static bool any_window_intersects (Gdk.Rectangle dock_rect)
		{
			return window_intersects (dock_rect, false, false);
		}

		public static bool active_window_intersects (Gdk.Rectangle dock_rect)
		{
			return window_intersects (dock_rect, true, false);
		}

		public static bool maximized_window_intersects (Gdk.Rectangle dock_rect)
		{
			return window_intersects (dock_rect, false, true);
		}

		static bool window_intersects (Gdk.Rectangle dock_rect, bool active_only, bool maximized_only)
		{
			if (window_state == null)
				return false;

			try {
				var parser = new Json.Parser ();
				parser.load_from_data (window_state);
				var root = parser.get_root ().get_array ();
				foreach (var node in root.get_elements ()) {
					var window = node.get_object ();
					if (window.has_member ("resourceClass")
						&& window.get_string_member ("resourceClass").down () == "wayplank")
						continue;
					if (window.has_member ("minimized") && window.get_boolean_member ("minimized"))
						continue;
					if (window.has_member ("normal") && !window.get_boolean_member ("normal"))
						continue;
					if (window.has_member ("visible") && !window.get_boolean_member ("visible"))
						continue;
					if (window.has_member ("currentDesktop") && !window.get_boolean_member ("currentDesktop"))
						continue;
					if (active_only && (!window.has_member ("active") || !window.get_boolean_member ("active")))
						continue;
					if (maximized_only && (!window.has_member ("maximized") || !window.get_boolean_member ("maximized")))
						continue;

					Gdk.Rectangle window_rect = {
						(int) window.get_double_member ("x"),
						(int) window.get_double_member ("y"),
						(int) window.get_double_member ("width"),
						(int) window.get_double_member ("height")
					};
					if (window_rect.intersect (dock_rect, null))
						return true;
				}
			} catch (Error e) {
				debug ("Unable to parse KWin window state: %s", e.message);
			}

			return false;
		}

		public static void start ()
		{
			if (!environment_is_session_desktop (XdgSessionDesktop.KDE)
				|| !environment_is_session_type (XdgSessionType.WAYLAND))
				return;

			try {
			script_path = "/tmp/wayplank-kwin-%i.js".printf (Posix.getpid ());
			FileUtils.set_contents (script_path, KWIN_SCRIPT);
				var connection = Bus.get_sync (BusType.SESSION, null);
				var result = connection.call_sync ("org.kde.KWin", "/Scripting",
					"org.kde.kwin.Scripting", "loadScript",
					new Variant ("(s)", script_path),
					new VariantType ("(i)"), DBusCallFlags.NONE, -1, null);
				connection.call_sync ("org.kde.KWin", "/Scripting",
					"org.kde.kwin.Scripting", "start", null, null,
					DBusCallFlags.NONE, -1, null);
				debug ("KWin bridge script loaded (id %d)", result.get_child_value (0).get_int32 ());
			} catch (Error e) {
				warning ("Unable to start KWin bridge: %s", e.message);
			}
		}
	}
}
