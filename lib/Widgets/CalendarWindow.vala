//
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
	public class CalendarWindow : Gtk.Window
	{
		static CalendarWindow? active_instance = null;

		public static void toggle_calendar ()
		{
			if (active_instance != null) {
				active_instance.destroy ();
				active_instance = null;
				return;
			}

			// 1. Try launching a full standalone calendar application if available
			string[] calendar_apps = { "merkuro-calendar", "kalendar", "korganizer", "gnome-calendar", "xfce4-calendar" };
			foreach (var app in calendar_apps) {
				if (Environment.find_program_in_path (app) != null) {
					try {
						Process.spawn_command_line_async (app);
						return;
					} catch (Error e) { }
				}
			}

			// 2. Fallback: Display native embedded GTK calendar popup
			var win = new CalendarWindow ();
			win.show_all ();
			win.present ();
			active_instance = win;
		}

		public CalendarWindow ()
		{
			Object (type: Gtk.WindowType.TOPLEVEL);
		}

		construct
		{
			title = _("Calendar");
			set_default_size (280, 220);
			window_position = Gtk.WindowPosition.MOUSE;
			skip_taskbar_hint = true;
			skip_pager_hint = true;
			set_keep_above (true);
			type_hint = Gdk.WindowTypeHint.DIALOG;
			decorated = true;

			var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
			box.margin = 10;

			var cal = new Gtk.Calendar ();
			cal.show_heading = true;
			cal.show_day_names = true;
			box.pack_start (cal, true, true, 0);

			add (box);

			key_press_event.connect ((w, e) => {
				if (e.keyval == Gdk.Key.Escape) {
					destroy ();
					return Gdk.EVENT_STOP;
				}
				return Gdk.EVENT_PROPAGATE;
			});

			destroy.connect (() => {
				if (active_instance == this)
					active_instance = null;
			});
		}
	}
}
