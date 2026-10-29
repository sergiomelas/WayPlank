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
	 * WindowBackend implementation for Labwc and other wlroots compositors
	 * via the wlr-foreign-toplevel-management Wayland protocol.
	 */
	public class LabwcBackend : GLib.Object, WindowBackend
	{
		static LabwcBackend? instance;
		static Gee.HashMap<string, int>? toplevel_pid_cache;
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

		~LabwcBackend ()
		{
			cleanup ();
			if (instance == this)
				instance = null;
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

		public bool fullscreen_window_intersects (Gdk.Rectangle rect)
		{
			return WlrBridge.fullscreen_window_intersects (rect.x, rect.y, rect.width, rect.height);
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
					var res_class_chk = json.has_member ("resourceClass") ? json.get_string_member ("resourceClass").down () : "";
					var res_name_chk = json.has_member ("resourceName") ? json.get_string_member ("resourceName").down () : "";
					var capt_chk = json.has_member ("caption") ? json.get_string_member ("caption").down () : "";
					var dname_chk = json.has_member ("desktopFileName") ? json.get_string_member ("desktopFileName").down () : "";
					if (res_class_chk == "wayplank" || res_class_chk == "plank" ||
					    res_name_chk == "wayplank" || res_name_chk == "plank" ||
					    dname_chk == "wayplank" || dname_chk == "plank" || dname_chk == "wayplank.desktop" || dname_chk == "plank.desktop" ||
					    capt_chk == "wayplank" || capt_chk == "wayplank-hover")
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
					info.Fullscreen = json.has_member ("fullscreen") && json.get_boolean_member ("fullscreen");
					info.DemandsAttention = false;
					info.CurrentDesktop = true;
					info.MinimizedSequence = json.has_member ("minimizedSequence") ? json.get_int_member ("minimizedSequence") : 0;
					info.Caption = json.has_member ("caption") ? json.get_string_member ("caption") : "";
					resolve_toplevel_process (info);
					result.add (info);
				}
			} catch (Error e) {
				debug ("Unable to parse Labwc window state: %s", e.message);
			}
			return result;
		}

		static void resolve_toplevel_process (WindowInfo info)
		{
			var target_cls = info.ResourceClass != "" ? info.ResourceClass.down ().strip () : info.ApplicationId.down ().strip ();
			if (target_cls == "")
				return;

			if (toplevel_pid_cache == null)
				toplevel_pid_cache = new Gee.HashMap<string, int> ();

			var cache_key = "%s|%s|%s".printf (info.Id, target_cls, info.Caption);
			if (toplevel_pid_cache.has_key (cache_key)) {
				int cached_pid = toplevel_pid_cache.get (cache_key);
				if (cached_pid > 0 && FileUtils.test ("/proc/%d/cmdline".printf (cached_pid), FileTest.EXISTS)) {
					info.Pid = cached_pid;
					info.Cmdline = ApplicationDiscovery.get_process_cmdline (cached_pid);
					info.Executable = ApplicationDiscovery.get_process_comm (cached_pid);
					return;
				}
				toplevel_pid_cache.unset (cache_key);
			}

			var caption_tokens = new Gee.ArrayList<string> ();
			if (info.Caption != "") {
				var cleaned = info.Caption.down ()
					.replace ("(", " ")
					.replace (")", " ")
					.replace ("[", " ")
					.replace ("]", " ")
					.replace (":", " ")
					.replace (",", " ");
				foreach (var part in cleaned.split (" ")) {
					var tok = part.strip ();
					if (tok.length >= 2 && tok != target_cls && tok != "qemu")
						caption_tokens.add (tok);
				}
			}

			int best_pid = 0;
			int best_score = 0;
			var comm_prefix = target_cls.length > 15 ? target_cls.substring (0, 15) : target_cls;

			try {
				var proc_dir = Dir.open ("/proc", 0);
				unowned string? entry = null;
				while ((entry = proc_dir.read_name ()) != null) {
					int pid = int.parse (entry);
					if (pid <= 0)
						continue;

					var comm = ApplicationDiscovery.get_process_comm (pid).down ();
					if (comm == "")
						continue;

					var cmdline = ApplicationDiscovery.get_process_cmdline (pid);
					var cmd_lower = cmdline.down ();

					bool bin_match = (comm == target_cls || comm == comm_prefix || cmd_lower.contains (target_cls));
					if (!bin_match)
						continue;

					int score = 10;
					foreach (var tok in caption_tokens) {
						if (cmd_lower.contains (tok))
							score += 50;
					}

					if (score > best_score) {
						best_score = score;
						best_pid = pid;
					}
				}
			} catch { }

			if (best_pid > 0) {
				if (toplevel_pid_cache.size > 256)
					toplevel_pid_cache.clear ();
				toplevel_pid_cache.set (cache_key, best_pid);
				info.Pid = best_pid;
				info.Cmdline = ApplicationDiscovery.get_process_cmdline (best_pid);
				info.Executable = ApplicationDiscovery.get_process_comm (best_pid);
			}
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
