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
	 * Adapter between the neutral WindowBackend contract and KWinBridge.
	 */
	public class KWinBackend : GLib.Object, WindowBackend
	{
		public KWinBackend ()
		{
			KWinBridge.get_default ().state_changed.connect (forward_state_changed);
		}
		
		~KWinBackend ()
		{
			KWinBridge.get_default ().state_changed.disconnect (forward_state_changed);
		}
		
		void forward_state_changed ()
		{
			int nx, ny;
			if (KWinBridge.get_primary_panel_monitor (out nx, out ny)) {
				bool changed = !has_cached_primary || nx != cached_primary_x || ny != cached_primary_y;
				cached_primary_x = nx;
				cached_primary_y = ny;
				has_cached_primary = true;
				if (changed) {
					primary_monitor_changed ();
				}
			}
			state_changed ();
		}
		
		public bool start ()
		{
			KWinBridge.start ();
			return true;
		}
		
		public void cleanup ()
		{
			KWinBridge.cleanup ();
		}

		public bool has_state ()
		{
			return KWinBridge.has_window_state ();
		}

		public void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError
		{
			KWinBridge.register_dbus (connection, object_path);
		}
		
		public Gee.ArrayList<WindowInfo> get_windows ()
		{
			return KWinBridge.get_window_infos ();
		}
		
		public bool queue_command (string target, string action)
		{
			KWinBridge.queue_command (target, action);
			return true;
		}
		
		public bool any_window_intersects (Gdk.Rectangle rect)
		{
			return KWinBridge.any_window_intersects (rect);
		}
		
		public bool active_window_intersects (Gdk.Rectangle rect)
		{
			return KWinBridge.active_window_intersects (rect);
		}
		
		public bool maximized_window_intersects (Gdk.Rectangle rect)
		{
			return KWinBridge.maximized_window_intersects (rect);
		}

		public bool fullscreen_window_intersects (Gdk.Rectangle rect)
		{
			return KWinBridge.fullscreen_window_intersects (rect);
		}

		public void handle_system_resume ()
		{
			KWinBridge.handle_system_resume ();
		}

		bool cached_top_floating = true;
		int last_floating_query_time = 0;
		int last_floating_mon_x = -1;
		int last_floating_mon_y = -1;
		int last_floating_mon_w = -1;

		int last_primary_query_time = 0;
		bool has_cached_primary = false;
		int cached_primary_x = 0;
		int cached_primary_y = 0;

		public override bool get_primary_monitor_geometry (out int x, out int y, out int width, out int height)
		{
			x = 0; y = 0; width = 0; height = 0;
			int kx, ky;
			if (KWinBridge.get_primary_panel_monitor (out kx, out ky)) {
				cached_primary_x = kx;
				cached_primary_y = ky;
				has_cached_primary = true;
				x = kx;
				y = ky;
				return true;
			}

			int now = (int) (GLib.get_monotonic_time () / 1000000);
			if (has_cached_primary && last_primary_query_time > 0 && (now - last_primary_query_time) < 1) {
				x = cached_primary_x;
				y = cached_primary_y;
				return true;
			}

			last_primary_query_time = now;
			try {
				var script = """
					var res = "";
					if (typeof screenGeometry === "function") {
						var sg = null;
						if (panels().length > 0 && panels()[0].screen !== undefined && panels()[0].screen >= 0) {
							sg = screenGeometry(panels()[0].screen);
						}
						if (!sg || sg.width <= 0) {
							sg = screenGeometry(0);
						}
						if (sg && sg.width > 0) {
							res = Math.round(sg.x) + "," + Math.round(sg.y);
						}
					}
					print(res);
				""";
				var bus = Bus.get_sync (BusType.SESSION, null);
				var res = bus.call_sync (
					"org.kde.plasmashell",
					"/PlasmaShell",
					"org.kde.PlasmaShell",
					"evaluateScript",
					new Variant ("(s)", script),
					new VariantType ("(s)"),
					DBusCallFlags.NO_AUTO_START,
					150,
					null
				);
				string val;
				res.get ("(s)", out val);
				if (val != null) {
					var parts = val.strip ().split (",");
					if (parts.length == 2) {
						cached_primary_x = int.parse (parts[0]);
						cached_primary_y = int.parse (parts[1]);
						has_cached_primary = true;
						x = cached_primary_x;
						y = cached_primary_y;
						return true;
					}
				}
			} catch (Error e) { }

			if (has_cached_primary) {
				x = cached_primary_x;
				y = cached_primary_y;
				return true;
			}
			return false;
		}

		public bool is_top_panel_floating_configured (Gdk.Rectangle mon_geom = Gdk.Rectangle ())
		{
			int now = (int) (GLib.get_monotonic_time () / 1000000);
			if (last_floating_query_time > 0 && (now - last_floating_query_time) < 1
				&& mon_geom.x == last_floating_mon_x
				&& mon_geom.y == last_floating_mon_y
				&& mon_geom.width == last_floating_mon_w)
				return cached_top_floating;

			last_floating_query_time = now;
			last_floating_mon_x = mon_geom.x;
			last_floating_mon_y = mon_geom.y;
			last_floating_mon_w = mon_geom.width;
			try {
				var script = """
					var res = false;
					for (var i = 0; i < panels().length; i++) {
						var p = panels()[i];
						if (p.location === "top") {
							if (%d > 0 && typeof screenGeometry === "function" && p.screen !== undefined) {
								var sg = screenGeometry(p.screen);
								if (sg && (sg.x !== %d || sg.y !== %d))
									continue;
							}
							res = (p.floating === true);
							break;
						}
					}
					print(res);
				""".printf (mon_geom.width, mon_geom.x, mon_geom.y);
				var bus = Bus.get_sync (BusType.SESSION, null);
				var res = bus.call_sync (
					"org.kde.plasmashell",
					"/PlasmaShell",
					"org.kde.PlasmaShell",
					"evaluateScript",
					new Variant ("(s)", script),
					new VariantType ("(s)"),
					DBusCallFlags.NONE,
					150,
					null
				);
				string val;
				res.get ("(s)", out val);
				if (val != null) {
					cached_top_floating = (val.strip () == "true");
				}
			} catch (Error e) { }

			return cached_top_floating;
		}

		public override void invalidate_panel_cache ()
		{
			last_floating_query_time = 0;
			last_primary_query_time = 0;
		}

		public override int get_top_panel_floating_offset (Gdk.Rectangle mon_geom = Gdk.Rectangle ())
		{
			if (is_top_panel_floating_configured (mon_geom)) {
				if (!KWinBridge.has_maximized_window_on_current_desktop (mon_geom)) {
					return 8;
				}
			}
			return 0;
		}
	}
}
