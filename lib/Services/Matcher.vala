//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of Wayplank.
//

namespace Plank
{
	/**
	 * Wayland-native Matcher wrapper (decoupled from Bamf/X11)
	 */
	public class Matcher : GLib.Object
	{
		public signal void active_window_changed (string? old_win_id, string? new_win_id);
		public signal void window_opened (string win_id);
		public signal void window_closed (string win_id);

		public signal void active_application_changed (string? old_app_id, string? new_app_id);
		public signal void application_opened (string app_id);
		public signal void application_closed (string app_id);

		static Matcher? matcher = null;

		public static Matcher get_default ()
		{
			if (matcher == null)
				matcher = new Matcher ();
			return matcher;
		}

		Gee.HashMap<string, Gee.HashSet<int>> app_pids;
		Gee.HashSet<string> active_apps;

		private Matcher ()
		{
			app_pids = new Gee.HashMap<string, Gee.HashSet<int>> ();
			active_apps = new Gee.HashSet<string> ();
		}

		construct
		{
			// Periodically scan running processes to populate the dock
			GLib.Timeout.add_seconds (2, () => {
				scan_running_applications ();
				return true;
			});
		}

		~Matcher ()
		{
			matcher = null;
		}

		private void scan_running_applications ()
		{
			try {
				var dir = GLib.Dir.open ("/proc", 0);
				string? name = null;
				Gee.HashSet<int> current_pids = new Gee.HashSet<int> ();

				while ((name = dir.read_name ()) != null) {
					int pid = int.parse (name);
					if (pid <= 0)
						continue;

					current_pids.add (pid);
					string comm_path = "/proc/%s/comm".printf (name);
					string comm = "";
					if (GLib.FileUtils.get_contents (comm_path, out comm)) {
						comm = comm.strip ();
						if (comm != "" && comm != "wayplank") {
							// Check common desktop file ID patterns generically
							string[] possible_ids = {
								comm + ".desktop",
								"org.kde." + comm + ".desktop",
								"org.gnome." + comm + ".desktop",
								comm.down () + ".desktop"
							};

							foreach (var id in possible_ids) {
								if (desktop_file_exists_in_system (id)) {
									register_process_for_app (id, pid);
									break;
								}
							}
						}
					}
				}

				// Remove PIDs that no longer exist in /proc
				foreach (var app_id in app_pids.keys.to_array ()) {
					var pids = app_pids.get (app_id);
					var dead_pids = new Gee.HashSet<int> ();
					foreach (var pid in pids) {
						if (!current_pids.contains (pid)) {
							dead_pids.add (pid);
						}
					}
					foreach (var dead in dead_pids) {
						unregister_process_for_app (app_id, dead);
					}
				}
			} catch (Error e) {
				warning ("Errors during Process Scan: %s", e.message);
			}
		}

		private bool desktop_file_exists_in_system (string app_id)
		{
			foreach (var folder in Paths.DataDirFolders) {
				var desktop_file = folder.get_child ("applications").get_child (app_id);
				if (desktop_file.query_exists ()) {
					// Filter system daemons, KDED/KWallet services, and hidden apps
					try {
						var key_file = new GLib.KeyFile ();
						key_file.load_from_file (desktop_file.get_path (), GLib.KeyFileFlags.NONE);
						
						if (key_file.has_key ("Desktop Entry", "NoDisplay") && key_file.get_boolean ("Desktop Entry", "NoDisplay"))
							return false;
						if (key_file.has_key ("Desktop Entry", "Hidden") && key_file.get_boolean ("Desktop Entry", "Hidden"))
							return false;
							
						string[] categories = {};
						if (key_file.has_key ("Desktop Entry", "Categories"))
							categories = key_file.get_string_list ("Desktop Entry", "Categories");
							
						// Discard system services or pure daemons without user categories
						bool is_service = false;
						foreach (var cat in categories) {
							if (cat == "Core" || cat == "System" || cat == "Settings") {
								// Check whether it is a valid settings app or a pure service
								if (app_id.contains ("kded") || app_id.contains ("kwallet") || app_id.contains ("at-spi")) {
									is_service = true;
								}
							}
						}
						if (is_service)
							return false;

						return true;
					} catch (Error e) {
						return true; // Fallback if parsing fails but the file exists
					}
				}
			}
			return false;
		}

		public Gee.ArrayList<string> active_launchers ()
		{
			var list = new Gee.ArrayList<string> ();
			foreach (var app in active_apps) {
				list.add (app);
			}
			return list;
		}

		public string? app_for_uri (string uri)
		{
			string launcher;
			try {
				launcher = Filename.from_uri (uri);
			} catch (ConvertError e) {
				warning (e.message);
				return null;
			}

			return launcher;
		}

		public void set_favorites (Gee.ArrayList<string> favs)
		{
		}

		public void register_process_for_app (string app_id, int pid)
		{
			if (!app_pids.has_key (app_id)) {
				app_pids.set (app_id, new Gee.HashSet<int> ());
			}
			app_pids.get (app_id).add (pid);

			if (active_apps.add (app_id)) {
				application_opened (app_id);
			}
		}

		public void unregister_process_for_app (string app_id, int pid)
		{
			if (app_pids.has_key (app_id)) {
				var pids = app_pids.get (app_id);
				pids.remove (pid);
				if (pids.size == 0) {
					app_pids.unset (app_id);
					if (active_apps.remove (app_id)) {
						application_closed (app_id);
					}
				}
			}
		}
	}
}
