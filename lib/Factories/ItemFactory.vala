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
	 * An item factory.  Creates {@link DockItem}s based on .dockitem files.
	 */
	public class ItemFactory : GLib.Object
	{
		const string[] FALLBACK_FILE_MANAGERS = {
			"org.gnome.Nautilus.desktop",
			"org.kde.dolphin.desktop",
			"nemo.desktop",
			"thunar.desktop",
			"pcmanfm.desktop",
			"org.xfce.FileManager.desktop"
		};

		const string[] FALLBACK_BROWSERS = {
			"google-chrome.desktop",
			"firefox.desktop",
			"chromium-browser.desktop",
			"chromium.desktop",
			"brave-browser.desktop",
			"microsoft-edge.desktop",
			"org.gnome.Epiphany.desktop"
		};

		const string[] FALLBACK_TERMINALS = {
			"org.gnome.Terminal.desktop",
			"org.gnome.Ptyxis.desktop",
			"ptyxis.desktop",
			"org.kde.konsole.desktop",
			"alacritty.desktop",
			"kitty.desktop",
			"xfce4-terminal.desktop",
			"foot.desktop",
			"terminator.desktop"
		};

		const string[] FALLBACK_EDITORS = {
			"org.gnome.TextEditor.desktop",
			"gedit.desktop",
			"org.kde.kate.desktop",
			"code.desktop",
			"com.microsoft.VSCode.desktop",
			"mousepad.desktop"
		};

		const string[] PRIORITY_INTERNET = {
			"google-chrome", "firefox", "chromium-browser", "brave-browser",
			"microsoft-edge", "thunderbird", "org.telegram.desktop", "discord", "signal-desktop"
		};

		const string[] PRIORITY_OFFICE = {
			"libreoffice-startcenter", "libreoffice-writer", "code", "com.microsoft.VSCode",
			"org.kde.kate", "org.gnome.TextEditor", "gedit", "org.kde.kcalc", "org.gnome.Calculator"
		};

		const string[] PRIORITY_MEDIA = {
			"vlc", "org.videolan.VLC", "org.gnome.Totem", "org.kde.dragonplayer",
			"spotify", "org.inkscape.Inkscape", "gimp", "org.gimp.GIMP", "rhythmbox", "org.pulseaudio.pavucontrol"
		};

		const string[] PRIORITY_GAMES = {
			"steam", "com.valvesoftware.Steam", "lutris", "net.lutris.Lutris", "heroic", "com.heroicgameslauncher.hgl"
		};
		
		/**
		 * The directory containing .dockitem files.
		 */
		public File launchers_dir;
		
		/**
		 * Creates a new {@link DockElement} from a .dockitem.
		 *
		 * @param file the {@link GLib.File} of .dockitem file to parse
		 * @return the new {@link DockElement} created
		 */
		public virtual DockElement? make_element (GLib.File file)
		{
			var launcher = get_launcher_from_dockitem (file);
			
			return default_make_element (file, launcher);
		}
		
		/**
		 * Creates a new {@link PlankDockItem} for the dock itself.
		 *
		 * @return the new {@link PlankDockItem} created
		 */
		public virtual DockItem get_item_for_dock ()
		{
			return PlankDockItem.get_instance ();
		}
		
		/**
		 * Creates a new {@link DockElement} for a launcher parsed from a .dockitem.
		 *
		 * @param file the {@link GLib.File} of .dockitem file that was parsed
		 * @param launcher the launcher name from the .dockitem
		 * @return the new {@link DockElement} created, or null if invalid/unsupported
		 */
		protected DockElement? default_make_element (GLib.File file, string launcher)
		{
			if (launcher == "docklet://trash")
				return new TrashDockItem.with_dockitem_file (file);
			if (launcher == "docklet://clock")
				return new ClockDockItem.with_dockitem_file (file);
			if (launcher == "docklet://digital-clock")
				return new DigitalClockDockItem.with_dockitem_file (file);
			if (launcher == "docklet://battery")
				return new BatteryDockItem.with_dockitem_file (file);
			if (launcher == "docklet://cpu")
				return new CpuDockItem.with_dockitem_file (file);
			if (launcher == "docklet://desktop")
				return new ShowDesktopDockItem.with_dockitem_file (file);
			if (launcher == "docklet://mpris")
				return new MprisDockItem.with_dockitem_file (file);
			if (launcher == "docklet://volume")
				return new VolumeDockItem.with_dockitem_file (file);
			if (launcher == "docklet://screenshot")
				return new ScreenshotDockItem.with_dockitem_file (file);
			if (launcher == "docklet://session")
				return new SessionDockItem.with_dockitem_file (file);
			if (launcher == "docklet://preferences")
				return new PreferencesDockItem.with_dockitem_file (file);
			if (launcher == "docklet://ejector")
				return new EjectorDockItem.with_dockitem_file (file);
			if (launcher == "docklet://brightness")
				return new BrightnessDockItem.with_dockitem_file (file);
			if (launcher == "docklet://weather")
				return new WeatherDockItem.with_dockitem_file (file);
			if (launcher == "docklet://network")
				return new NetworkDockItem.with_dockitem_file (file);
			if (launcher == "docklet://dnd" || launcher == "docklet://donotdisturb")
				return new DoNotDisturbDockItem.with_dockitem_file (file);
			if (launcher.has_prefix ("docklet://")) {
				warning ("Unknown or unsupported docklet '%s' in %s, skipping", launcher, file.get_basename ());
				return null;
			}
			if (launcher.has_suffix (".desktop"))
				return new ApplicationDockItem.with_dockitem_file (file);
			return new FileDockItem.with_dockitem_file (file);
		}
		
		/**
		 * Parses a .dockitem to get the launcher from it.
		 *
		 * @param file the {@link GLib.File} of .dockitem to parse
		 * @return the launcher from the .dockitem
		 */
		protected string get_launcher_from_dockitem (GLib.File file)
		{
			try {
				var keyfile = new KeyFile ();
				keyfile.load_from_file (file.get_path (), KeyFileFlags.NONE);
				
				unowned string group_name = typeof (DockItemPreferences).name ();
				if (keyfile.has_group (group_name))
					return keyfile.get_string (group_name, "Launcher");
				
				// 0.10.1 > 0.10.9/0.11.x
				if (keyfile.has_group ("PlankItemsDockItemPreferences"))
					return keyfile.get_string ("PlankItemsDockItemPreferences", "Launcher");
			} catch (Error e) {
				warning ("%s (%s)", e.message, file.get_basename ());
			}
			
			return "";
		}
			
		/**
		 * Creates a list of Dockitems based on .dockitem files found in the given source_dir.
		 *
		 * @param source_dir the folder where to load .dockitem from
		 * @param ordering a ";;"-separated string to be used to order the loaded DockItems
		 * @return the new List of DockItems
		 */
		public Gee.ArrayList<DockElement> load_elements (GLib.File source_dir, string[]? ordering = null)
		{
			var result = new Gee.ArrayList<DockElement> ();
			
			if (!source_dir.query_exists ()) {
				critical ("Given folder '%s' does not exist.", source_dir.get_path ());
				return result;
			}

			debug ("Loading dock elements from '%s'", source_dir.get_path ());
			
			var elements = new Gee.HashMap<string,DockElement> ();
			var count = 0U;
			
			try {
				var enumerator = source_dir.enumerate_children (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_IS_HIDDEN, 0);
				FileInfo info;
				while ((info = enumerator.next_file ()) != null) {
					var filename = info.get_name ();
					if (info.get_is_hidden () || !filename.has_suffix (".dockitem"))
						continue;
					
					if (count++ >= LAUNCHER_DIR_MAX_FILE_COUNT) {
						critical ("There are way too many files (%u+) in '%s'.", LAUNCHER_DIR_MAX_FILE_COUNT, source_dir.get_path ());
						break;
					}
					
					var file = source_dir.get_child (filename);
					var element = make_element (file);
					
					unowned DockItemProvider? provider = (element as DockItemProvider);
					if (provider != null) {
						elements.set (filename, element);
						continue;
					}
					
					unowned DockItem? item = (element as DockItem);
					if (item == null)
						continue;
					
					if (!item.is_valid ()) {
						warning ("The launcher '%s' in dock item '%s' does not exist. Removing '%s'.", item.Launcher, file.get_path (), item.DockItemFilename);
						item.delete ();
					} else {
						elements.set (filename, element);
					}
				}
			} catch (Error e) {
				critical ("Error loading dock elements from '%s'. (%s)", source_dir.get_path () ?? "", e.message);
			}
			
			// Downstream contribution by IFtiger-hu (史有虎): Clean launcher deduplication & duplicate disk pruning
			if (ordering != null) {
				foreach (unowned string dockitem in ordering) {
					DockElement? element;
					elements.unset (dockitem, out element);
					if (element == null)
						continue;

					unowned DockItem? item = (element as DockItem);
					if (item != null && item.Launcher != "") {
						unowned DockItem? dupe = find_item_for_uri (result, item.Launcher);
						if (dupe != null) {
							warning ("The launcher '%s' in dock item '%s' is already managed by dock item '%s'. Removing '%s'.",
								item.Launcher, item.DockItemFilename, dupe.DockItemFilename, item.DockItemFilename);
							item.delete ();
							continue;
						}
					}
					result.add (element);
				}
			}
			
			foreach (var element in elements.values) {
				unowned DockItem? item = (element as DockItem);
				if (item != null && item.Launcher != "") {
					unowned DockItem? dupe = find_item_for_uri (result, item.Launcher);
					if (dupe != null) {
						warning ("The launcher '%s' in dock item '%s' is already managed by dock item '%s'. Removing '%s'.",
							item.Launcher, item.DockItemFilename, dupe.DockItemFilename, item.DockItemFilename);
						item.delete ();
						continue;
					}
				}
				result.add (element);
			}
			elements.clear ();
			
			return result;
		}
		
		unowned DockItem? find_item_for_uri (Gee.ArrayList<DockElement> elements, string uri)
		{
			foreach (var element in elements) {
				unowned DockItem? item = (element as DockItem);
				if (item != null && DockItemProvider.uri_matches (item.Launcher, uri))
					return item;
			}
			
			return null;
		}

		bool make_dock_item_for_desktop_id (string id)
		{
			string desktop_id = id.has_suffix (".desktop") ? id : id + ".desktop";
			var app_info = new DesktopAppInfo (desktop_id);
			if (app_info == null)
				return false;
			
			unowned string filename = app_info.get_filename ();
			if (filename == null)
				return false;
			
			try {
				var uri = Filename.to_uri (filename);
				return (make_dock_item (uri) != null);
			} catch (ConvertError e) {
				return false;
			}
		}

		static bool categories_contain (string? categories, string[] search_tags)
		{
			if (categories == null || categories == "")
				return false;
			
			foreach (unowned string tag in search_tags) {
				if (categories.contains (tag))
					return true;
			}
			return false;
		}

		void populate_folder (File folder, string icon_name, string[] priority_ids, string[] category_tags, int max_items = 6)
		{
			Paths.ensure_directory_exists (folder);

			var dot_dir = folder.get_child (".directory");
			if (!dot_dir.query_exists ()) {
				try {
					FileUtils.set_contents (dot_dir.get_path (), "[Desktop Entry]\nType=Directory\nIcon=%s\n".printf (icon_name));
				} catch { }
			}

			try {
				folder.set_attribute_string ("metadata::custom-icon-name", icon_name, FileQueryInfoFlags.NONE, null);
			} catch { }

			var added_files = new Gee.HashSet<string> ();

			// 1. Check priority applications
			foreach (unowned string id in priority_ids) {
				if (added_files.size >= max_items)
					break;
				string desktop_id = id.has_suffix (".desktop") ? id : id + ".desktop";
				var app = new DesktopAppInfo (desktop_id);
				if (app != null && app.should_show ()) {
					unowned string fn = app.get_filename ();
					if (fn != null && !added_files.contains (fn)) {
						var src = File.new_for_path (fn);
						var dst = folder.get_child (src.get_basename ());
						try {
							src.copy (dst, FileCopyFlags.OVERWRITE, null, null);
							added_files.add (fn);
						} catch { }
					}
				}
			}

			// 2. Scan installed desktop apps for matching categories
			if (added_files.size < max_items) {
				var all = AppInfo.get_all ();
				foreach (var info in all) {
					if (added_files.size >= max_items)
						break;
					var d_info = info as DesktopAppInfo;
					if (d_info == null || !d_info.should_show ())
						continue;
					unowned string fn = d_info.get_filename ();
					if (fn == null || added_files.contains (fn))
						continue;
					unowned string cats = d_info.get_categories ();
					if (categories_contain (cats, category_tags)) {
						var src = File.new_for_path (fn);
						var dst = folder.get_child (src.get_basename ());
						try {
							src.copy (dst, FileCopyFlags.OVERWRITE, null, null);
							added_files.add (fn);
						} catch { }
					}
				}
			}
		}

		void make_default_folders ()
		{
			File folders_base = Paths.AppConfigFolder.get_child ("folders");
			Paths.ensure_directory_exists (folders_base);

			// 1. Internet Folder
			var internet_folder = folders_base.get_child ("Internet");
			populate_folder (internet_folder, "applications-internet", PRIORITY_INTERNET, {
				"WebBrowser", "Network", "Email", "Chat", "InstantMessaging", "IRCClient", "Feed"
			});
			make_dock_item (internet_folder.get_uri ());

			// 2. Office & Productivity Folder
			var office_folder = folders_base.get_child ("Office");
			populate_folder (office_folder, "applications-office", PRIORITY_OFFICE, {
				"Office", "Development", "IDE", "TextEditor", "WordProcessor", "Spreadsheet", "Calculator", "Viewer"
			});
			make_dock_item (office_folder.get_uri ());

			// 3. Media & Creative Folder
			var media_folder = folders_base.get_child ("Media");
			populate_folder (media_folder, "applications-multimedia", PRIORITY_MEDIA, {
				"AudioVideo", "Audio", "Video", "Graphics", "Player", "Recorder", "Music"
			});
			make_dock_item (media_folder.get_uri ());

			// 4. Games Folder (or Utilities fallback if no games exist)
			var games_folder = folders_base.get_child ("Games");
			populate_folder (games_folder, "applications-games", PRIORITY_GAMES, {
				"Game", "Emulator"
			});
			
			// Verify if Games folder received any app; if empty, create Utilities instead
			bool has_game = false;
			try {
				var enum_games = games_folder.enumerate_children (FileAttribute.STANDARD_NAME, 0);
				FileInfo? info;
				while ((info = enum_games.next_file (null)) != null) {
					if (info.get_name ().has_suffix (".desktop")) {
						has_game = true;
						break;
					}
				}
			} catch { }

			if (has_game) {
				make_dock_item (games_folder.get_uri ());
			} else {
				var utils_folder = folders_base.get_child ("Utilities");
				populate_folder (utils_folder, "applications-utilities", { "org.gnome.DiskUtility", "gnome-system-monitor", "org.kde.ark", "file-roller" }, {
					"System", "Utility", "Archiving", "Settings", "FileManager"
				});
				make_dock_item (utils_folder.get_uri ());
			}
		}

		void make_default_docklets ()
		{
			make_dock_item ("docklet://preferences");
			make_dock_item ("docklet://desktop");
			make_dock_item ("docklet://volume");
			make_dock_item ("docklet://trash");
		}

		void make_default_pinned_apps ()
		{
			// 1. File Manager
			bool fm_done = false;
			var fm = AppInfo.get_default_for_type ("inode/directory", false);
			if (fm != null && fm.get_id () != null)
				fm_done = make_dock_item_for_desktop_id (fm.get_id ());
			if (!fm_done) {
				foreach (unowned string fallback_id in FALLBACK_FILE_MANAGERS) {
					if (make_dock_item_for_desktop_id (fallback_id))
						break;
				}
			}

			// 2. Web Browser
			bool browser_done = false;
			var browser = AppInfo.get_default_for_type ("x-scheme-handler/http", false);
			if (browser != null && browser.get_id () != null)
				browser_done = make_dock_item_for_desktop_id (browser.get_id ());
			if (!browser_done) {
				foreach (unowned string fallback_id in FALLBACK_BROWSERS) {
					if (make_dock_item_for_desktop_id (fallback_id))
						break;
				}
			}

			// 3. System Terminal
			foreach (unowned string term_id in FALLBACK_TERMINALS) {
				if (make_dock_item_for_desktop_id (term_id))
					break;
			}

			// 4. Text Editor
			bool editor_done = false;
			var editor = AppInfo.get_default_for_type ("text/plain", false);
			if (editor != null && editor.get_id () != null)
				editor_done = make_dock_item_for_desktop_id (editor.get_id ());
			if (!editor_done) {
				foreach (unowned string fallback_id in FALLBACK_EDITORS) {
					if (make_dock_item_for_desktop_id (fallback_id))
						break;
				}
			}
		}

		/**
		 * Creates a bunch of default .dockitem's and category folders.
		 */
		public void make_default_items ()
		{
			debug ("ItemFactory: creating modern default folders, docklets and pinned applications...");
			make_default_folders ();
			make_default_docklets ();
			make_default_pinned_apps ();
			debug ("ItemFactory: default items successfully created.");
		}
		
		/**
		 * Creates a new .dockitem for a uri.
		 *
		 * @param uri the uri or path to create a .dockitem for
		 * @param target_dir the folder where to put the newly created .dockitem (defaults to launchers_dir)
		 * @return the new {@link GLib.File} of the new .dockitem created
		 */
		public GLib.File? make_dock_item (string uri, File? target_dir = null)
		{
			if (target_dir == null)
				target_dir = launchers_dir;
			
			if (target_dir != null && !target_dir.query_exists ()) {
				try {
					target_dir.make_directory_with_parents (null);
				} catch { }
			}
			
			string target_uri = uri.strip ();
			if (target_uri.has_prefix ("application://") || target_uri.has_prefix ("applications://") || target_uri.has_prefix ("applications:")) {
				string desktop_id = target_uri;
				if (desktop_id.has_prefix ("applications://"))
					desktop_id = desktop_id.replace ("applications://", "");
				else if (desktop_id.has_prefix ("application://"))
					desktop_id = desktop_id.replace ("application://", "");
				else if (desktop_id.has_prefix ("applications:"))
					desktop_id = desktop_id.replace ("applications:", "");
				desktop_id = desktop_id.strip ();
				while (desktop_id.has_suffix ("/"))
					desktop_id = desktop_id.slice (0, desktop_id.length - 1);
				var app_info = new DesktopAppInfo (desktop_id);
				if (app_info == null && !desktop_id.has_suffix (".desktop"))
					app_info = new DesktopAppInfo (desktop_id + ".desktop");
				if (app_info != null && app_info.get_filename () != null) {
					target_uri = File.new_for_path (app_info.get_filename ()).get_uri ();
				}
			} else if (target_uri.has_prefix ("/")) {
				target_uri = File.new_for_path (target_uri).get_uri ();
			} else if (!target_uri.has_prefix ("file://") && !target_uri.has_prefix ("docklet://")) {
				var f = File.new_for_commandline_arg (target_uri);
				if (f.query_exists ()) {
					target_uri = f.get_uri ();
				} else {
					var app_info = new DesktopAppInfo (target_uri);
					if (app_info == null && !target_uri.has_suffix (".desktop"))
						app_info = new DesktopAppInfo (target_uri + ".desktop");
					if (app_info != null && app_info.get_filename () != null)
						target_uri = File.new_for_path (app_info.get_filename ()).get_uri ();
				}
			}

			var launcher_file = File.new_for_uri (target_uri);
			bool is_docklet = target_uri.has_prefix ("docklet://");
			bool is_valid = is_docklet || launcher_file.query_exists ();
			string basename = is_docklet ? target_uri.replace ("docklet://", "") : (launcher_file.get_basename () ?? "unknown");
			
			if (is_valid && target_dir != null) {
				var file = new KeyFile ();
				
				file.set_string (typeof (DockItemPreferences).name (), "Launcher", target_uri);
				
				try {
					// find a unique file name, based on the name of the launcher
					var index_of_last_dot = basename.last_index_of (".");
					var launcher_base = (index_of_last_dot >= 0 ? basename.slice (0, index_of_last_dot) : basename);
					var dockitem = "%s.dockitem".printf (launcher_base);
					var dockitem_file = target_dir.get_child (dockitem);
					
					if (is_docklet && dockitem_file.query_exists ()) {
						try { dockitem_file.delete (null); } catch { }
					}
					
					// Reuse or update existing dock item to avoid duplicate files (KISS)
					if (dockitem_file.query_exists ()) {
						var existing_launcher = get_launcher_from_dockitem (dockitem_file);
						if (existing_launcher != null && DockItemProvider.uri_matches (existing_launcher, target_uri)) {
							debug ("Reusing existing dock item '%s' for launcher '%s'", dockitem_file.get_path (), uri);
							return dockitem_file;
						}
						debug ("Updating existing dock item '%s' for launcher '%s'", dockitem_file.get_path (), uri);
						var update_stream = new DataOutputStream (dockitem_file.replace (null, false, FileCreateFlags.NONE, null));
						update_stream.put_string (file.to_data ());
						update_stream.close ();
						return dockitem_file;
					}
					
					// save the key file
					var stream = new DataOutputStream (dockitem_file.replace (null, false, FileCreateFlags.NONE, null));
					stream.put_string (file.to_data ());
					stream.close ();
					
					debug ("Created dock item '%s' for launcher '%s'", dockitem_file.get_path (), uri);
					return dockitem_file;
				} catch { }
			}
			
			return null;
		}
	}
}
