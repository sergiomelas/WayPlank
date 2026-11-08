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
	 * A utility class for launching applications and opening files/URIs.
	 */
	public class System : GLib.Object
	{
		static System? instance = null;
		
		public static unowned System get_default ()
		{
			if (instance == null)
				instance = new System (Gdk.Display.get_default ().get_app_launch_context ());
			
			return instance;
		}
		
		public AppLaunchContext context { get; construct; }
		
		public System (AppLaunchContext context)
		{
			Object (context: context);
		}
		
		construct
		{
			context.launch_failed.connect (on_launch_failed);
			context.launched.connect (on_launched);
		}
		
		~System ()
		{
			context.launch_failed.disconnect (on_launch_failed);
			context.launched.disconnect (on_launched);
		}
		
		void on_launch_failed (string startup_notify_id) 
		{
			warning ("Failed to launch '%s'", startup_notify_id);
		}
		
		void on_launched (AppInfo info, Variant platform_data)
		{
			Logger.verbose ("Launched '%s' ('%s')", info.get_name (), info.get_executable ());
		}
		
		/**
		 * Opens a file based on a URI according to its MIME type.
		 *
		 * @param uri the URI to open
		 */
		public void open_uri (string uri)
		{
			try {
				if (!AppInfo.launch_default_for_uri (uri, null)) {
					AppInfo.launch_default_for_uri (uri, context);
				}
			} catch (Error e) {
				try {
					AppInfo.launch_default_for_uri (uri, context);
				} catch (Error e2) {
					try {
						Process.spawn_async (null, { "xdg-open", uri }, null, SpawnFlags.SEARCH_PATH, null, null);
					} catch (Error e3) {
						critical ("Failed to open URI '%s': %s", uri, e3.message);
					}
				}
			}
		}
		
		/**
		 * Opens a file based on a {@link GLib.File} according to its MIME type.
		 *
		 * @param file the {@link GLib.File} to open
		 */
		public void open (File? file)
		{
			if (file == null)
				return;
			var uri = file.get_uri ();
			try {
				if (!AppInfo.launch_default_for_uri (uri, null)) {
					AppInfo.launch_default_for_uri (uri, context);
				}
			} catch (Error e) {
				try {
					AppInfo.launch_default_for_uri (uri, context);
				} catch (Error e2) {
					try {
						var path = file.get_path ();
						Process.spawn_async (null, { "xdg-open", path != null ? path : uri }, null, SpawnFlags.SEARCH_PATH, null, null);
					} catch (Error e3) {
						critical ("Failed to open file '%s': %s", uri, e3.message);
					}
				}
			}
		}
		
		/**
		 * Opens multiple files based on {@link GLib.File}.
		 *
		 * @param files the {@link GLib.File}s to open
		 */
		public void open_files (File[] files)
		{
			foreach (var f in files) {
				open (f);
			}
		}
		
		/**
		 * Launches an application.
		 *
		 * @param app the application to launch
		 */
		public void launch (File app)
		{
			launch_with_files (app, new File[] {});
		}
		
		/**
		 * Launches an application and opens URIs (files or web/remote URLs).
		 *
		 * @param app the application launcher file (.desktop)
		 * @param uris the URIs to open with the application
		 */
		public void launch_with_uris (File? app, string[] uris)
		{
			if (app != null && !app.query_exists ()) {
				warning ("Application '%s' doesn't exist", app.get_path () ?? "");
				return;
			}
			
			if (app == null) {
				foreach (var uri in uris) {
					try {
						AppInfo.launch_default_for_uri (uri, context);
					} catch (Error e) {
						warning ("%s", e.message);
					}
				}
				return;
			}

			var launcher_path = app.get_path ();
			if (launcher_path == null)
				return;

			try {
				var info = new DesktopAppInfo.from_filename (launcher_path);
				if (info == null) {
					critical ("Unable to use application '%s' for execution.", launcher_path);
					return;
				}

				if (uris.length == 0) {
					info.launch (null, context);
					return;
				}

				var uri_list = new GLib.List<string> ();
				var file_list = new GLib.List<File> ();
				bool has_remote_uri = false;

				foreach (var u in uris) {
					uri_list.append (u);
					file_list.append (File.new_for_uri (u));
					if (!u.has_prefix ("file://")) {
						has_remote_uri = true;
					}
				}

				Logger.verbose ("Launch '%s' with %d URIs", info.get_name (), (int) uris.length);

				// 1. If remote URIs exist (e.g. http://, https://), launch with launch_uris
				if (has_remote_uri) {
					try {
						info.launch_uris (uri_list, context);
						return;
					} catch (Error e) {
						warning ("Failed to launch '%s' with remote URIs: %s", info.get_name (), e.message);
					}
				}

				// 2. If app supports files:
				if (info.supports_files ()) {
					try {
						info.launch (file_list, context);
						return;
					} catch (Error e) {
						warning ("Failed to launch '%s' with files: %s", info.get_name (), e.message);
					}
				}

				// 3. Fallback: try launch_uris, then basic launch
				try {
					info.launch_uris (uri_list, context);
					return;
				} catch (Error e) {
					warning ("launch_uris failed for '%s', falling back to basic launch: %s", info.get_name (), e.message);
					try {
						info.launch (null, context);
					} catch (Error err) {
						warning ("Failed basic launch for '%s': %s", info.get_name (), err.message);
					}
				}
			} catch (Error e) {
				critical ("%s: %s", launcher_path, e.message);
			}
		}

		/**
		 * Launches an application and opens files.
		 *
		 * @param app the application to launch
		 * @param files the files to open with the application
		 */
		public void launch_with_files (File? app, File[] files)
		{
			if (app != null && !app.query_exists ()) {
				warning ("Application '%s' doesn't exist", app.get_path () ?? "");
				return;
			}
			
			var mounted_files = new GLib.List<File> ();
			
			// make sure all files are mounted
			foreach (var f in files) {
				var path = f.get_path ();
				if (path != null && path != "" && (f.is_native () || path_is_mounted (path))) {
					mounted_files.append (f);
					continue;
				}
				
				try {
					AppInfo.launch_default_for_uri (f.get_uri (), context);
				} catch {
					f.mount_enclosing_volume.begin (0, null);
					mounted_files.append (f);
				}
			}
			
			if (mounted_files.length () > 0 || files.length == 0)
				internal_launch (app, mounted_files);
		}
		
		static bool path_is_mounted (string path)
		{
			foreach (var m in VolumeMonitor.get ().get_mounts ()) {
				var m_root = m.get_root ();
				if (m_root == null)
					continue;
				
				var m_path = m_root.get_path ();
				if (m_path != null && path.contains (m_path))
					return true;
			}
			
			return false;
		}
		
		/**
		 * Safely loads a KeyFile from a file path, automatically sanitizing KDE expanded
		 * keys such as URL[$e]= to URL= if standard strict desktop entry parsing fails.
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
		 * Extracts the destination URL from an internet shortcut file (.desktop of Type=Link or .url file).
		 * Supports standard URL= as well as KDE URL[$e]= expanded keys.
		 */
		public static string? extract_link_shortcut_url (string uri_or_path)
		{
			string path = uri_or_path.strip ();
			if (path.has_prefix ("file://")) {
				try {
					path = Filename.from_uri (path);
				} catch {
					var gfile = File.new_for_uri (path);
					path = gfile.get_path () ?? path;
				}
			}

			if (!path.has_suffix (".desktop") && !path.has_suffix (".url"))
				return null;

			try {
				var file = File.new_for_path (path);
				if (!file.query_exists ())
					return null;

				uint8[] contents;
				if (!file.load_contents (null, out contents, null))
					return null;

				string raw = (string) contents;
				var lines = raw.split ("\n");
				string? found_url = null;

				foreach (unowned string line in lines) {
					string s = line.strip ();
					if (path.has_suffix (".url") && (s.has_prefix ("URL=") || s.has_prefix ("URL[$e]=") || s.has_prefix ("URL["))) {
						int eq = s.index_of ("=");
						if (eq >= 0)
							found_url = s.slice (eq + 1, s.length).strip ();
					} else if (s.has_prefix ("Exec=")) {
						int app_idx = s.index_of ("--app=");
						if (app_idx >= 0) {
							string candidate = s.slice (app_idx + 6, s.length).strip ();
							if (candidate.has_prefix ("http://") || candidate.has_prefix ("https://")) {
								int space_idx = candidate.index_of (" ");
								if (space_idx >= 0)
									candidate = candidate.slice (0, space_idx).strip ();
								found_url = candidate;
							}
						} else {
							int http_idx = s.index_of ("http://");
							if (http_idx < 0)
								http_idx = s.index_of ("https://");
							if (http_idx >= 0) {
								string candidate = s.slice (http_idx, s.length).strip ();
								int space_idx = candidate.index_of (" ");
								if (space_idx >= 0)
									candidate = candidate.slice (0, space_idx).strip ();
								found_url = candidate;
							}
						}
					}
				}

				if (found_url != null && (found_url.has_prefix ("http://") || found_url.has_prefix ("https://") || found_url.has_prefix ("ftp://")))
					return found_url;
			} catch {}

			return null;
		}

		/**
		 * Launches a desktop settings / utility command prioritizing tools native to
		 * the currently active XDG session desktop before falling back to generic or
		 * cross-desktop alternatives.
		 */
		public static bool launch_desktop_utility (string[] kde_cmds, string[] gnome_cmds, string[] generic_cmds)
		{
			var ordered = new Gee.ArrayList<string> ();
			if (environment_is_session_desktop (XdgSessionDesktop.KDE)) {
				foreach (unowned string c in kde_cmds) ordered.add (c);
				foreach (unowned string c in generic_cmds) ordered.add (c);
				foreach (unowned string c in gnome_cmds) ordered.add (c);
			} else if (environment_is_session_desktop (XdgSessionDesktop.GNOME | XdgSessionDesktop.UBUNTU)) {
				foreach (unowned string c in gnome_cmds) ordered.add (c);
				foreach (unowned string c in generic_cmds) ordered.add (c);
				foreach (unowned string c in kde_cmds) ordered.add (c);
			} else {
				foreach (unowned string c in generic_cmds) ordered.add (c);
				foreach (unowned string c in gnome_cmds) ordered.add (c);
				foreach (unowned string c in kde_cmds) ordered.add (c);
			}

			foreach (var cmd in ordered) {
				var trimmed = cmd.strip ();
				if (trimmed == "")
					continue;
				var prog = trimmed.split (" ")[0];
				if (GLib.Environment.find_program_in_path (prog) != null) {
					try {
						GLib.Process.spawn_command_line_async (trimmed);
						return true;
					} catch (GLib.Error e) { }
				}
			}

			return false;
		}
		
		void internal_launch (File? app, GLib.List<File> files)
		{
			if (app == null && files.length () == 0)
				return;
			
			AppInfo? info = null;
			
			if (app != null) {
				KeyFile keyfile = new KeyFile ();
				var launcher = app.get_path ();
				
				if (!load_keyfile_safe (keyfile, launcher, KeyFileFlags.NONE)) {
					critical ("%s: unable to parse desktop launcher", launcher);
					return;
				}
				
				try {
					var type = keyfile.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_TYPE);
					switch (type) {
					default:
					case KeyFileDesktop.TYPE_APPLICATION:
					case KeyFileDesktop.TYPE_DIRECTORY:
						break;
					case KeyFileDesktop.TYPE_LINK:
						try {
							string? url = null;
							if (keyfile.has_key (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_URL))
								url = keyfile.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_URL);
							else if (keyfile.has_key (KeyFileDesktop.GROUP, "URL"))
								url = keyfile.get_string (KeyFileDesktop.GROUP, "URL");
							if (url == null || url == "")
								url = extract_link_shortcut_url (launcher);
							if (url != null && url.length > 0)
								AppInfo.launch_default_for_uri (url, context);
						} catch (Error e) {
							critical ("%s: %s", launcher, e.message);
						}
						return;
					}
				} catch (KeyFileError e) {
					critical ("%s: %s", launcher, e.message);
					return;
				}
				
				info = new DesktopAppInfo.from_filename (launcher);
			} else {
				try {
					info = files.first ().data.query_default_handler ();
				} catch (Error e) {
					critical (e.message);
				}
			}
			
			if (info == null) {
				critical ("Unable to use application/file '%s' for execution.",
					(app != null ? app.get_path () : files.first ().data.get_path ()));
				return;
			}
			
			try {
				Logger.verbose ("Launch '%s' ('%s')", info.get_name (), info.get_executable ());
				
				if (files.length () == 0) {
					info.launch (null, context);
					return;
				}
				
				if (info.supports_files ()) {
					info.launch (files, context);
					return;
				}
				
				if (info.supports_uris ()) {
					var uris = new GLib.List<string> ();
					foreach (var f in files)
						uris.append (f.get_uri ());
					info.launch_uris (uris, context);
					return;
				}
				
				warning ("The application '%s' doesn't support files/URIs or wasn't found.", info.get_name ());
			} catch (Error e) {
				critical (e.message);
			}
		}
	}
}
