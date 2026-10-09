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
	 * WindowBackend implementation for Labwc and other wlroots compositors
	 * via the wlr-foreign-toplevel-management Wayland protocol.
	 */
	public class LabwcBackend : GLib.Object, WindowBackend
	{
		static LabwcBackend? instance;
		Gee.ArrayList<WindowInfo> window_infos = new Gee.ArrayList<WindowInfo> ();
		bool started = false;

		public LabwcBackend ()
		{
			instance = this;
		}

		public static unowned LabwcBackend get_default ()
		{
			if (instance == null)
				instance = new LabwcBackend ();
			return instance;
		}

		public bool start ()
		{
			if (started)
				return true;

			started = WlrBridge.init (on_wlr_state_changed);
			if (started)
				refresh_window_infos ();
			return started;
		}

		uint debounce_timer_id = 0;

		public void cleanup ()
		{
			if (debounce_timer_id != 0) {
				Source.remove (debounce_timer_id);
				debounce_timer_id = 0;
			}
			if (started) {
				WlrBridge.cleanup ();
				started = false;
			}
		}

		public bool has_state ()
		{
			return started && WlrBridge.is_available ();
		}

		public void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError
		{
			// Native Wayland protocol; no extra D-Bus registration required.
		}

		public Gee.ArrayList<WindowInfo> get_windows ()
		{
			var result = new Gee.ArrayList<WindowInfo> ();
			result.add_all (window_infos);
			return result;
		}

		public bool queue_command (string target, string action)
		{
			return WlrBridge.queue_command (target, action);
		}

		public bool any_window_intersects (Gdk.Rectangle rect)
		{
			return WlrBridge.any_window_intersects (rect.x, rect.y, rect.width, rect.height);
		}

		public bool active_window_intersects (Gdk.Rectangle rect)
		{
			return WlrBridge.active_window_intersects (rect.x, rect.y, rect.width, rect.height);
		}

		public bool maximized_window_intersects (Gdk.Rectangle rect)
		{
			return WlrBridge.maximized_window_intersects (rect.x, rect.y, rect.width, rect.height);
		}

		void schedule_state_changed ()
		{
			if (debounce_timer_id != 0) {
				Source.remove (debounce_timer_id);
				debounce_timer_id = 0;
			}
			debounce_timer_id = Timeout.add (50, () => {
				debounce_timer_id = 0;
				refresh_window_infos ();
				state_changed ();
				return Source.REMOVE;
			});
		}

		static void on_wlr_state_changed ()
		{
			if (instance != null) {
				instance.schedule_state_changed ();
			}
		}

		void refresh_window_infos ()
		{
			string json_data = WlrBridge.get_window_json ();
			window_infos = parse_window_infos (json_data);
		}

		static Gee.ArrayList<WindowInfo> parse_window_infos (string state)
		{
			var result = new Gee.ArrayList<WindowInfo> ();
			try {
				var parser = new Json.Parser ();
				parser.load_from_data (state);
				var root = parser.get_root ();
				if (root == null || root.get_node_type () != Json.NodeType.ARRAY)
					return result;
				foreach (var node in root.get_array ().get_elements ()) {
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
					info.DemandsAttention = false;
					info.CurrentDesktop = true;
					info.MinimizedSequence = json.has_member ("minimizedSequence") ? json.get_int_member ("minimizedSequence") : 0;
					info.Caption = json.has_member ("caption") ? json.get_string_member ("caption") : "";
					result.add (info);
				}
			} catch (Error e) {
				debug ("Unable to parse Labwc window state: %s", e.message);
			}
			return result;
		}

		static string normalize_resource_id (string id)
		{
			var normalized = id.down ();
			if (normalized.has_suffix (".desktop"))
				normalized = normalized.substring (0, normalized.length - ".desktop".length);
			return normalized;
		}
	}
}
