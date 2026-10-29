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

		public void handle_system_resume ()
		{
			KWinBridge.handle_system_resume ();
		}

		bool cached_top_floating = true;
		int last_floating_query_time = 0;
		int last_floating_mon_x = -1;
		int last_floating_mon_y = -1;
		int last_floating_mon_w = -1;

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
