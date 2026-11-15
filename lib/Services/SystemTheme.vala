//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//  Copyright (C) 2026 史有虎 (IFtiger-hu)
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
	 * Portable domain service tracking the desktop environment's Light/Dark mode
	 * through `Hal.Bus.Theme` with a GTK theme-name fallback.
	 */
	public class SystemTheme : GLib.Object
	{
		static SystemTheme? default_instance = null;

		public bool is_dark { get; private set; default = false; }
		public signal void theme_changed (bool is_dark);

		bool shutting_down = false;

		public static SystemTheme get_default ()
		{
			if (default_instance == null) {
				default_instance = new SystemTheme ();
			}
			return default_instance;
		}

		public static void cleanup_if_active ()
		{
			if (default_instance != null) {
				default_instance.cleanup ();
			}
		}

		construct
		{
			refresh_state ();
			Hal.Bus.Theme.color_scheme_changed.connect (refresh_state);

			// Fallback: observe GTK theme name changes
			unowned Gtk.Settings? gtk_settings = Gtk.Settings.get_default ();
			if (gtk_settings != null) {
				gtk_settings.notify["gtk-theme-name"].connect (() => {
					refresh_state ();
				});
				gtk_settings.notify["gtk-application-prefer-dark-theme"].connect (() => {
					refresh_state ();
				});
			}
		}

		~SystemTheme ()
		{
			cleanup ();
		}

		public void cleanup ()
		{
			if (!shutting_down) {
				shutting_down = true;
				Hal.Bus.Theme.color_scheme_changed.disconnect (refresh_state);
			}
		}

		public void refresh_state ()
		{
			if (shutting_down)
				return;

			bool detected_dark = false;
			if (!Hal.Bus.Theme.query_prefer_dark (out detected_dark)) {
				unowned Gtk.Settings? gtk_settings = Gtk.Settings.get_default ();
				var theme_name = gtk_settings != null ? (gtk_settings.gtk_theme_name ?? "") : "";
				detected_dark = (theme_name.down ().contains ("dark") || theme_name.down ().contains ("black"));
			}

			if (is_dark != detected_dark) {
				is_dark = detected_dark;
				theme_changed (is_dark);
			}
		}
	}
}
