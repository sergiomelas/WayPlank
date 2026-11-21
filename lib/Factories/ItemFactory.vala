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
		const string[] PRIORITY_INTERNET = {
			"google-chrome", "firefox", "chromium-browser", "brave-browser",
			"microsoft-edge", "thunderbird", "org.telegram", "discord", "signal-desktop"
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
		public Gee.ArrayList<string> corrupted_dockitems = new Gee.ArrayList<string> ();
		
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
			return new PlankDockItem ();
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
			if (Hal.Apps.is_launcher_uri (launcher))
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
				if (keyfile.has_group (group_name)) {
					var val = keyfile.get_string (group_name, "Launcher");
					return val.contains ("..") ? "" : val;
				}
				
				// 0.10.1 > 0.10.9/0.11.x
				if (keyfile.has_group ("PlankItemsDockItemPreferences")) {
					var val = keyfile.get_string ("PlankItemsDockItemPreferences", "Launcher");
					return val.contains ("..") ? "" : val;
				}
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
			corrupted_dockitems.clear ();
			var result = new Gee.ArrayList<DockElement> ();
			
			if (!source_dir.query_exists ()) {
				critical ("Given folder '%s' does not exist.", source_dir.get_path ());
				return result;
			}

			debug ("Loading dock elements from '%s'", source_dir.get_path ());
			
			var elements = new Gee.HashMap<string,DockElement> ();
			var filenames = new Gee.ArrayList<string> ();
			var count = 0U;
			
			try {
				var enumerator = source_dir.enumerate_children (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_IS_HIDDEN, 0);
				FileInfo? info;
				while ((info = enumerator.next_file ()) != null) {
					var filename = info.get_name ();
					if (info.get_is_hidden () || !filename.has_suffix (".dockitem"))
						continue;
					
					if (count++ >= LAUNCHER_DIR_MAX_FILE_COUNT) {
						critical ("There are way too many files (%u+) in '%s'.", LAUNCHER_DIR_MAX_FILE_COUNT, source_dir.get_path ());
						break;
					}
					
					filenames.add (filename);
				}
				try { enumerator.close (null); } catch { }
			} catch (Error e) {
				critical ("Error loading dock elements from '%s'. (%s)", source_dir.get_path () ?? "", e.message);
			}
			
			foreach (var filename in filenames) {
				var file = source_dir.get_child (filename);
				var launcher_check = get_launcher_from_dockitem (file);
				if (launcher_check == "") {
					if (!corrupted_dockitems.contains (filename))
						corrupted_dockitems.add (filename);
					continue;
				}
				var element = make_element (file);
				
				unowned DockItemProvider? provider = (element as DockItemProvider);
				if (provider != null) {
					elements.set (filename, element);
					continue;
				}
				
				unowned DockItem? item = (element as DockItem);
				if (item == null) {
					if (!corrupted_dockitems.contains (filename))
						corrupted_dockitems.add (filename);
					continue;
				}
				
				if (!item.is_valid ()) {
					if (item is BrightnessDockItem) {
						message ("Hardware brightness control is unavailable on this display. Skipping '%s' in memory without marking it corrupted.", item.DockItemFilename);
					} else {
						warning ("The launcher '%s' in dock item '%s' does not exist. Skipping '%s' in memory without deleting disk file.", item.Launcher, file.get_path (), item.DockItemFilename);
						if (!corrupted_dockitems.contains (filename))
							corrupted_dockitems.add (filename);
					}
				} else {
					elements.set (filename, element);
				}
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

		void make_default_folders ()
		{
			File folders_base = Paths.AppConfigFolder.get_child ("folders");
			Paths.ensure_directory_exists (folders_base);

			// 1. Internet Folder
			var internet_folder = folders_base.get_child ("Internet");
			Hal.Apps.populate_category_folder (internet_folder, "applications-internet", PRIORITY_INTERNET, {
				"WebBrowser", "Network", "Email", "Chat", "InstantMessaging", "IRCClient", "Feed"
			});
			make_dock_item (internet_folder.get_uri ());

			// 2. Office & Productivity Folder
			var office_folder = folders_base.get_child ("Office");
			Hal.Apps.populate_category_folder (office_folder, "applications-office", PRIORITY_OFFICE, {
				"Office", "Development", "IDE", "TextEditor", "WordProcessor", "Spreadsheet", "Calculator", "Viewer"
			});
			make_dock_item (office_folder.get_uri ());

			// 3. Media & Creative Folder
			var media_folder = folders_base.get_child ("Media");
			Hal.Apps.populate_category_folder (media_folder, "applications-multimedia", PRIORITY_MEDIA, {
				"AudioVideo", "Audio", "Video", "Graphics", "Player", "Recorder", "Music"
			});
			make_dock_item (media_folder.get_uri ());

			// 4. Games Folder (or Utilities fallback if no games exist)
			var games_folder = folders_base.get_child ("Games");
			int game_count = Hal.Apps.populate_category_folder (games_folder, "applications-games", PRIORITY_GAMES, {
				"Game", "Emulator"
			});

			if (game_count > 0) {
				make_dock_item (games_folder.get_uri ());
			} else {
				var utils_folder = folders_base.get_child ("Utilities");
				Hal.Apps.populate_category_folder (utils_folder, "applications-utilities", { "org.gnome.DiskUtility", "gnome-system-monitor", "org.kde.ark", "file-roller" }, {
					"System", "Utility", "Archiving", "Settings", "FileManager"
				});
				make_dock_item (utils_folder.get_uri ());
			}
		}

		public void make_default_docklets ()
		{
			make_dock_item ("docklet://preferences");
			make_dock_item ("docklet://clock");
			make_dock_item ("docklet://brightness");
			make_dock_item ("docklet://desktop");
			make_dock_item ("docklet://volume");
			make_dock_item ("docklet://trash");
		}

		void make_default_pinned_apps ()
		{
			foreach (var seed_uri in Hal.Apps.discover_default_seed_apps ())
				make_dock_item (seed_uri);
		}

		static bool is_supported_docklet_uri (string launcher)
		{
			return (launcher == "docklet://trash"
				|| launcher == "docklet://cpu"
				|| launcher == "docklet://clock"
				|| launcher == "docklet://desktop"
				|| launcher == "docklet://digital-clock"
				|| launcher == "docklet://mpris"
				|| launcher == "docklet://battery"
				|| launcher == "docklet://volume"
				|| launcher == "docklet://screenshot"
				|| launcher == "docklet://session"
				|| launcher == "docklet://preferences"
				|| launcher == "docklet://ejector"
				|| launcher == "docklet://brightness"
				|| launcher == "docklet://weather"
				|| launcher == "docklet://network"
				|| launcher == "docklet://dnd"
				|| launcher == "docklet://donotdisturb");
		}

		/**
		 * Copies compatible .dockitem files (apps, user folders, and supported docklets)
		 * from legacy ~/.config/plank/<dock>/launchers into ~/.config/wayplank/<dock>/launchers
		 * in 100% read-only mode so X11 Plank sessions remain completely untouched.
		 */
		public bool migrate_legacy_plank_items (GLib.File legacy_launchers_dir, GLib.File? target_dir = null)
		{
			if (!legacy_launchers_dir.query_exists ())
				return false;

			if (target_dir == null)
				target_dir = launchers_dir;
			if (target_dir == null)
				return false;

			Paths.ensure_directory_exists (target_dir);
			int migrated_count = 0;

			try {
				var enumerator = legacy_launchers_dir.enumerate_children (
					FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_IS_HIDDEN, 0);
				FileInfo? info;
				while ((info = enumerator.next_file (null)) != null) {
					var filename = info.get_name ();
					if (info.get_is_hidden () || !filename.has_suffix (".dockitem"))
						continue;

					var src_file = legacy_launchers_dir.get_child (filename);
					var launcher = get_launcher_from_dockitem (src_file);
					if (launcher == "")
						continue;

					if (launcher.has_prefix ("docklet://")) {
						if (!is_supported_docklet_uri (launcher)) {
							debug ("Skipping unsupported legacy Plank docklet '%s' (%s)", launcher, filename);
							continue;
						}
					} else {
						if (!Hal.Apps.launcher_exists (launcher) && !File.new_for_uri (launcher).query_exists ())
							continue;
					}

					var dst_file = target_dir.get_child (filename);
					if (!dst_file.query_exists ()) {
						try {
							src_file.copy (dst_file, FileCopyFlags.NONE, null, null);
							migrated_count++;
						} catch (Error e) {
							warning ("Unable to copy legacy Plank dockitem '%s': %s", filename, e.message);
						}
					} else {
						migrated_count++;
					}
				}
				try { enumerator.close (null); } catch { }
			} catch (Error e) {
				warning ("Error scanning legacy Plank launchers '%s': %s", legacy_launchers_dir.get_path () ?? "", e.message);
			}

			return (migrated_count > 0);
		}

		/**
		 * Creates classic Plank-style default .dockitem's (core pinned apps + Preferences + Trash,
		 * without auto-generated category folders or extra docklets).
		 */
		public void make_classic_items ()
		{
			debug ("ItemFactory: creating classic default pinned applications...");
			make_default_pinned_apps ();
			debug ("ItemFactory: classic items successfully created.");
		}

		/**
		 * Instantiates only .dockitem files from source_dir whose Launcher URI is not yet present in provider.
		 */
		public Gee.ArrayList<DockItem> load_missing_items (GLib.File source_dir, DockItemProvider provider)
		{
			var result = new Gee.ArrayList<DockItem> ();
			if (!source_dir.query_exists ())
				return result;

			var filenames = new Gee.ArrayList<string> ();
			try {
				var enumerator = source_dir.enumerate_children (
					FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_IS_HIDDEN, 0);
				FileInfo? info;
				while ((info = enumerator.next_file (null)) != null) {
					var filename = info.get_name ();
					if (info.get_is_hidden () || !filename.has_suffix (".dockitem"))
						continue;
					filenames.add (filename);
				}
				try { enumerator.close (null); } catch { }
			} catch (Error e) {
				warning ("Error loading missing dock items from '%s': %s", source_dir.get_path () ?? "", e.message);
			}

			foreach (var filename in filenames) {
				var file = source_dir.get_child (filename);
				var launcher = get_launcher_from_dockitem (file);
				if (launcher == "" || provider.item_for_uri (launcher) != null)
					continue;

				var element = make_element (file);
				unowned DockItem? item = element as DockItem;
				if (item != null && item.is_valid ())
					result.add (item);
				else if (item != null)
					item.cleanup ();
			}

			return result;
		}

		/**
		 * Creates a bunch of default .dockitem's and category folders (WayPlank Explorer mode).
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
			bool is_docklet = target_uri.has_prefix ("docklet://");
			if (!is_docklet) {
				string resolved = Hal.Apps.resolve_launcher_uri (target_uri);
				if (resolved != "")
					target_uri = resolved;
			}

			bool is_valid = is_docklet || Hal.Apps.launcher_exists (target_uri) || File.new_for_uri (target_uri).query_exists ();
			string launcher_base = is_docklet
				? Hal.Apps.launcher_id_stem (target_uri.substring ("docklet://".length))
				: Hal.Apps.launcher_id_stem (target_uri);

			if (is_valid && target_dir != null) {
				var file = new KeyFile ();
				var group_name = typeof (DockItemPreferences).name ();

				file.set_string (group_name, "Launcher", target_uri);
				file.set_string (group_name, "CustomIcon", "");
				file.set_string (group_name, "BrowserProfile", "");
				file.set_boolean (group_name, "KeepVisible", false);

				try {
					var dockitem_file = target_dir.get_child ("%s.dockitem".printf (launcher_base));

					if (dockitem_file.query_exists ()) {
						var existing_launcher = get_launcher_from_dockitem (dockitem_file);
						if (existing_launcher != null && DockItemProvider.uri_matches (existing_launcher, target_uri)) {
							debug ("Reusing existing dock item '%s' for launcher '%s'", dockitem_file.get_path (), uri);
							return dockitem_file;
						}
						if (existing_launcher != null && existing_launcher != "") {
							for (int suffix = 2; suffix < 1000; suffix++) {
								var candidate_file = target_dir.get_child ("%s-%d.dockitem".printf (launcher_base, suffix));
								if (!candidate_file.query_exists ()) {
									dockitem_file = candidate_file;
									break;
								}
								var cand_launcher = get_launcher_from_dockitem (candidate_file);
								if (cand_launcher != null && DockItemProvider.uri_matches (cand_launcher, target_uri)) {
									debug ("Reusing existing dock item '%s' for launcher '%s'", candidate_file.get_path (), uri);
									return candidate_file;
								}
							}
						}
					}

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
