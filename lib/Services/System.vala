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
	 * OS-blind Core facade for launching applications and opening files or URIs via HAL.
	 */
	public class System : GLib.Object
	{
		static System? instance = null;

		public static unowned System get_default ()
		{
			if (instance == null) {
				var display = Gdk.Display.get_default ();
				instance = new System (display != null ? display.get_app_launch_context () : new AppLaunchContext ());
			}

			return instance;
		}

		public AppLaunchContext context { get; construct; }

		public System (AppLaunchContext context)
		{
			Object (context: context);
		}

		/**
		 * Opens a file or remote resource based on a URI.
		 *
		 * @param uri the URI to open
		 */
		public void open_uri (string uri)
		{
			if (uri == "")
				return;
			if (!Hal.Runtime.open_uri (uri, null))
				warning ("Failed to open URI '%s'", uri);
		}

		/**
		 * Opens a file based on a {@link GLib.File}.
		 *
		 * @param file the {@link GLib.File} to open
		 */
		public void open (File? file)
		{
			if (file == null)
				return;
			open_uri (file.get_uri ());
		}

		/**
		 * Opens multiple files based on {@link GLib.File}.
		 *
		 * @param files the {@link GLib.File}s to open
		 */
		public void open_files (File[] files)
		{
			foreach (var f in files)
				open (f);
		}

		/**
		 * Launches an application.
		 *
		 * @param app the application launcher to launch
		 */
		public void launch (File app)
		{
			launch_with_files (app, new File[] {});
		}

		/**
		 * Launches an application and opens URIs (files or web/remote URLs).
		 *
		 * @param app the application launcher file
		 * @param uris the URIs to open with the application
		 */
		public void launch_with_uris (File? app, string[] uris)
		{
			if (app == null) {
				foreach (var uri in uris)
					open_uri (uri);
				return;
			}

			string launcher_uri = app.get_uri ();
			if (!Hal.Apps.launch_app (launcher_uri, uris, context))
				warning ("Failed to launch '%s'", launcher_uri);
		}

		/**
		 * Launches an application and opens files.
		 *
		 * @param app the application to launch
		 * @param files the files to open with the application
		 */
		public void launch_with_files (File? app, File[] files)
		{
			if (app == null) {
				open_files (files);
				return;
			}

			string[] uris = new string[files.length];
			for (int i = 0; i < files.length; i++)
				uris[i] = files[i].get_uri ();

			launch_with_uris (app, uris);
		}

		/**
		 * Safely loads a KeyFile from a file path, sanitizing expanded keys such as
		 * URL[$e]= to URL= if strict keyfile parsing fails.
		 */
		public static bool load_keyfile_safe (KeyFile kf, string file_path, KeyFileFlags flags = KeyFileFlags.NONE)
		{
			try {
				if (kf.load_from_file (file_path, flags))
					return true;
			} catch (Error e) {
				try {
					var gfile = File.new_for_path (file_path);
					uint8[] raw_bytes;
					if (gfile.load_contents (null, out raw_bytes, null)) {
						string content = (string) raw_bytes;
						content = content.replace ("[$e]=", "=");
						content = content.replace ("[$i]=", "=");
						content = content.replace ("[$d]=", "=");
						return kf.load_from_data (content, content.length, flags);
					}
				} catch {}
			}
			return false;
		}

		/**
		 * Extracts the destination URL from an internet shortcut launcher or .url file.
		 */
		public static string? extract_link_shortcut_url (string uri_or_path)
		{
			return Hal.Apps.extract_link_shortcut_url (uri_or_path);
		}
	}
}
