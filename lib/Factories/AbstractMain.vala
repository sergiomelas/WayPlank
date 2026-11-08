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
	 * The main class for all dock applications.  All docks should extend this class.
	 * In the constructor, the string fields should be initialized to customize the dock.
	 */
	public abstract class AbstractMain : Gtk.Application
	{
		/**
		 * The default command-line options for the dock.
		 */
		const OptionEntry[] options = {
			{ "debug", 'd', 0, OptionArg.NONE, null, "Enable debug logging", null },
			{ "verbose", 'V', 0, OptionArg.NONE, null, "Enable verbose logging", null },
			{ "name", 'n', 0, OptionArg.STRING, null, "The name of this dock. Defaults to \"dock1\".", null },
			{ "preferences", 'p', 0, OptionArg.NONE, null, "Show preferences dialog of the just started or already running instance", null },
			{ "shortcuts", 's', 0, OptionArg.NONE, null, "Show shortcuts and gestures guide dialog", null },
			{ "reload", 'r', 0, OptionArg.NONE, null, "Reload and refresh running dock instance", null },
			{ "replace", 0, 0, OptionArg.NONE, null, "Restart and replace running dock instance", null },
			{ "version", 'v', 0, OptionArg.NONE, null, "Show the application's version", null },
			{ null }
		};

		static bool is_shutting_down = false;
		static uint sigint_source_id = 0U;
		static uint sigterm_source_id = 0U;
		static uint sighup_source_id = 0U;
		public static string? saved_gtk_use_portal = null;

		public static void perform_clean_shutdown ()
		{
			if (is_shutting_down)
				return;
			is_shutting_down = true;

			if (sigint_source_id > 0U) {
				GLib.Source.remove (sigint_source_id);
				sigint_source_id = 0U;
			}
			if (sigterm_source_id > 0U) {
				GLib.Source.remove (sigterm_source_id);
				sigterm_source_id = 0U;
			}
			if (sighup_source_id > 0U) {
				GLib.Source.remove (sighup_source_id);
				sighup_source_id = 0U;
			}

			if (app_instance != null) {
				if (app_instance.first_run_dlg != null) {
					app_instance.first_run_dlg.cancel_without_applying ();
					app_instance.first_run_dlg.destroy ();
					app_instance.first_run_dlg = null;
				}
				if (app_instance.env_error_dlg != null) {
					app_instance.env_error_dlg.destroy ();
					app_instance.env_error_dlg = null;
				}
				foreach (var dock in app_instance.docks) {
					dock.flush_pending_serialization ();
					if (dock.prefs != null)
						dock.prefs.flush_to_disk ();
				}

				if (app_instance.resume_timer_id > 0U) {
					GLib.Source.remove (app_instance.resume_timer_id);
					app_instance.resume_timer_id = 0U;
				}
				if (app_instance.upgrade_signal_source_id > 0U) {
					GLib.Source.remove (app_instance.upgrade_signal_source_id);
					app_instance.upgrade_signal_source_id = 0U;
				}
				app_instance.teardown_power_management_listener ();
			}

			SystemTheme.cleanup_if_active ();
			BrightnessControl.cleanup_if_active ();
			AppUsageService.shutdown_if_active ();
			WindowControl.cleanup ();
			GLib.Settings.sync ();
		}

		static bool handle_unix_termination_signal (int sig)
		{
			warning ("Caught signal (%d), exiting", sig);
			perform_clean_shutdown ();
			if (app_instance != null)
				app_instance.quit ();
			else
				Posix.exit (0);
			return false;
		}
		
		static construct
		{
			sigint_source_id = GLib.Unix.signal_add ((int) Posix.Signal.INT, () => {
				sigint_source_id = 0U;
				return handle_unix_termination_signal ((int) Posix.Signal.INT);
			});
			sigterm_source_id = GLib.Unix.signal_add ((int) Posix.Signal.TERM, () => {
				sigterm_source_id = 0U;
				return handle_unix_termination_signal ((int) Posix.Signal.TERM);
			});
			sighup_source_id = GLib.Unix.signal_add ((int) Posix.Signal.HUP, () => {
				sighup_source_id = 0U;
				return handle_unix_termination_signal ((int) Posix.Signal.HUP);
			});
		}
		
		/**
		 * Should be Build.DATADIR
		 */
		public string build_data_dir { get; construct; }
		/**
		 * Should be Build.PKGDATADIR
		 */
		public string build_pkg_data_dir { get; construct; }
		/**
		 * Should be Build.RELEASE_NAME
		 */
		public string build_release_name { get; construct; }
		/**
		 * Should be Build.VERSION
		 */
		public string build_version { get; construct; }
		/**
		 * Should be Build.VERSION_INFO
		 */
		public string build_version_info { get; construct; }
		
		/**
		 * The displayed name of the program.
		 */
		public string program_name { get; construct; }
		/**
		 * The executable name of the program.
		 */
		public string exec_name { get; construct; }
		
		/**
		 * The copyright year(s).
		 */
		public string app_copyright { get; construct; }
		/**
		 * The (unique) dbus path for this program.
		 */
		public string app_dbus { get; construct; }
		/**
		 * The name of this program's icon.
		 */
		public string app_icon { get; construct; }
		/**
		 * The name of the launcher (.desktop file) for this program.
		 */
		public string app_launcher { get; construct; }

		/**
		 * The URL for this program's website.
		 */
		public string main_url { get; construct set; }
		/**
		 * The URL for this program's help.
		 */
		public string help_url { get; construct set; }
		/**
		 * The URL for translating this program.
		 */
		public string translate_url { get; construct set; }
		
		/**
		 * The list of authors (to show in about dialog).
		 */
		public string[] about_authors { get; construct set; }
		/**
		 * The list of documenters (to show in about dialog).
		 */
		public string[] about_documenters { get; construct set; }
		/**
		 * The list of artists (to show in about dialog).
		 */
		public string[] about_artists { get; construct set; }
		/**
		 * The list of translators (to show in about dialog).
		 */
		public string about_translators { get; construct set; }
		/**
		 * The license of this program (to show in about dialog).
		 */
		public Gtk.License about_license_type { get; construct set; default = Gtk.License.UNKNOWN; }
		
		string dock_name = "";
		
		public static bool is_about_open { get; private set; default = false; }
		public static unowned AbstractMain? app_instance = null;

		public static void check_collapse_all_docks (Gtk.Window? closing_win = null)
		{
			if (app_instance != null) {
				foreach (var dock in app_instance.docks)
					dock.check_collapse_after_interaction (closing_win);
			}
		}

		Gtk.AboutDialog? about_dlg;
		PreferencesWindow? preferences_dlg;
		HelpWindow? help_dlg;
		FirstRunWindow? first_run_dlg;
		Gtk.MessageDialog? env_error_dlg;
		DockController? primary_dock;
		Gee.ArrayList<DockController> docks;
		
		construct
		{
			app_instance = this;
			flags = ApplicationFlags.HANDLES_COMMAND_LINE;
			docks = new Gee.ArrayList<DockController> ();
			
			// set program name
#if HAVE_SYS_PRCTL_H
			prctl (15, exec_name);
#else
			setproctitle (exec_name);
#endif
			Environment.set_prgname (exec_name);
			
			Intl.bindtextdomain (Build.GETTEXT_PACKAGE, Build.DATADIR + "/locale");
			Intl.bind_textdomain_codeset (Build.GETTEXT_PACKAGE, "UTF-8");
			
			add_main_option_entries (options);
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override void activate ()
		{
			refresh_docks ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override int handle_local_options (VariantDict options)
		{
			if (options.contains ("version")) {
				print ("%s\n", build_version);
				return 0;
			}
			
			Logger.initialize (program_name);
			
			if (options.contains ("verbose"))
				Logger.DisplayLevel = LogLevel.VERBOSE;
			else if (options.contains ("debug"))
				Logger.DisplayLevel = LogLevel.DEBUG;
			else
				Logger.DisplayLevel = LogLevel.WARN;
			
			if (options.lookup ("name", "&s", out dock_name)) {
				application_id = "%s.%s".printf (app_dbus, dock_name);
			} else {
				dock_name = "";
				application_id = app_dbus;
			}
			
			return -1;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override int command_line (ApplicationCommandLine command_line)
		{
			var options = command_line.get_options_dict ();
			
			if (options.contains ("preferences")) {
				activate_action ("preferences", null);
				return 0;
			}
			
			if (options.contains ("shortcuts")) {
				activate_action ("shortcuts", null);
				return 0;
			}
			
			if (command_line.is_remote) {
				refresh_docks ();
				command_line.print ("WayPlank is already running. Refreshing dock surface and position.\n");
			}

			return 0;
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override void startup ()
		{
			// Make sure important properties are set
			assert (build_data_dir != null);
			assert (build_pkg_data_dir != null);
			assert (build_release_name != null);
			assert (build_version != null);
			assert (build_version_info != null);
			assert (program_name != null);
			assert (exec_name != null);
			assert (app_dbus != null);
			
			base.startup ();

			if (saved_gtk_use_portal != null)
				Environment.set_variable ("GTK_USE_PORTAL", saved_gtk_use_portal, true);
			else
				Environment.unset_variable ("GTK_USE_PORTAL");
			
			if (!Thread.supported ())
				critical ("Problem initializing thread support.");
			
			message ("%s version: %s", program_name, build_version);
			message ("Kernel version: %s", Posix.utsname ().release);
			message ("GLib version: %u.%u.%u (%u.%u.%u)",
				GLib.Version.major, GLib.Version.minor, GLib.Version.micro,
				GLib.Version.MAJOR, GLib.Version.MINOR, GLib.Version.MICRO);
			message ("GTK+ version: %u.%u.%u (%i.%i.%i)",
				Gtk.get_major_version (), Gtk.get_minor_version () , Gtk.get_micro_version (),
				Gtk.MAJOR_VERSION, Gtk.MINOR_VERSION, Gtk.MICRO_VERSION);
			message ("Cairo version: %s", Cairo.version_string ());
			message ("Pango version: %s", Pango.version_string ());
			message ("+ Cairo/Gtk+ HiDPI support enabled");
#if HAVE_DBUSMENU
			message ("+ Dynamic Quicklists support enabled");
#endif
			if (Gtk.Widget.get_default_direction () == Gtk.TextDirection.RTL)
				message ("+ RTL support enabled");
			
			internal_quarks_initialize ();
			environment_initialize ();
			
			Paths.initialize (exec_name, build_pkg_data_dir);
			WindowControl.initialize ();
			
			initialize ();
			create_docks ();
			WindowControl.get_default ().bridge_reconnected.connect (() => {
				schedule_dock_refresh (150);
			});
			WindowControl.start ();
			create_actions ();
			setup_power_management_listener ();
			setup_binary_upgrade_watcher ();
		}
		
		/**
		 * Additional initializations before the dock is created.
		 */
		protected virtual void initialize ()
		{
		}
		
		/**
		 * Creates the docks.
		 */
		protected virtual void create_docks ()
		{
			if (dock_name != null && dock_name != "") {
				message ("Running with 1 dock ('%s')", dock_name);
				add_dock (create_dock (dock_name));
				if (primary_dock != null && primary_dock.prefs.load_environment_failed)
					show_load_environment_failed (primary_dock);
				else if (primary_dock != null && primary_dock.is_first_run_launch)
					show_first_run (primary_dock);
				return;
			}
			
			var settings = create_settings ("net.launchpad.plank");
			var enabled_docks = settings.get_strv ("enabled-docks");
			
			// Allow up to 8 docks
			if (enabled_docks.length <= 0) {
				enabled_docks = { "dock1" };
				settings.set_strv ("enabled-docks", enabled_docks);
			} else if (enabled_docks.length > 8) {
				enabled_docks = enabled_docks[0:8];
				settings.set_strv ("enabled-docks", enabled_docks);
			}
			
			message ("Running with %i docks ('%s')", enabled_docks.length, string.joinv ("', '", enabled_docks));
			foreach (unowned string dock_name in enabled_docks)
				add_dock (create_dock (dock_name));

			if (primary_dock != null && primary_dock.prefs.load_environment_failed)
				show_load_environment_failed (primary_dock);
			else if (primary_dock != null && primary_dock.is_first_run_launch)
				show_first_run (primary_dock);
		}
		
		DockController create_dock (string dock_name)
		{
			var config_folder = Paths.AppConfigFolder.get_child (dock_name);
			// Make sure our config-directory exists
			Paths.ensure_directory_exists (config_folder);
			
			var dock = new DockController (dock_name, config_folder);
			dock.initialize ();
			
			return dock;
		}
		
		void add_dock (DockController dock)
		{
			// Make sure to populate our primary-dock field
			if (primary_dock == null
				|| (primary_dock.prefs.PinnedOnly && !dock.prefs.PinnedOnly))
				primary_dock = dock;
			
			docks.add (dock);
			add_window (dock.window);
		}
		
		/**
		 * Creates the actions and adds them to this {@link GLib.Application}.
		 */
		protected virtual void create_actions ()
		{
			SimpleAction action;
			
			action = new SimpleAction ("help", null);
			action.activate.connect (() => {
				System.get_default ().open_uri (help_url);
			});
			add_action (action);
			
			action = new SimpleAction ("translate", null);
			action.activate.connect (() => {
				System.get_default ().open_uri (translate_url);
			});
			add_action (action);
			
			action = new SimpleAction ("preferences", null);
			action.activate.connect (() => {
				show_preferences (primary_dock);
			});
			add_action (action);

			action = new SimpleAction ("preferences-appearance", null);
			action.activate.connect (() => {
				show_preferences (primary_dock, "grid_appearance");
			});
			add_action (action);

			action = new SimpleAction ("preferences-behaviour", null);
			action.activate.connect (() => {
				show_preferences (primary_dock, "grid_behaviour");
			});
			add_action (action);

			action = new SimpleAction ("preferences-applications", null);
			action.activate.connect (() => {
				show_preferences (primary_dock, "grid_windows");
			});
			add_action (action);

			action = new SimpleAction ("preferences-docklets", null);
			action.activate.connect (() => {
				show_preferences (primary_dock, "grid_docklets");
			});
			add_action (action);

			action = new SimpleAction ("shortcuts", null);
			action.activate.connect (() => {
				show_help ();
			});
			add_action (action);

			action = new SimpleAction ("guide", null);
			action.activate.connect (() => {
				show_guide ();
			});
			add_action (action);
			
			action = new SimpleAction ("about", null);
			action.activate.connect (() => {
				show_about ();
			});
			add_action (action);
			
			action = new SimpleAction ("quit", null);
			action.activate.connect (() => {
				perform_clean_shutdown ();
				quit ();
			});
			add_action (action);
		}

		/**
		 * {@inheritDoc}
		 */
		public override void shutdown ()
		{
			perform_clean_shutdown ();
			base.shutdown ();
		}
		
		/**
		 * Is true if the launcher given is the launcher for this dock.
		 *
		 * @param launcher the launcher to test
		 */
		public bool is_launcher_for_dock (string launcher)
		{
			return launcher.has_suffix (app_launcher);
		}
		
		/**
		 * Displays the about dialog.
		 */
		void show_about ()
		{
			uint32 click_time = Gtk.get_current_event_time ();
			if (about_dlg != null) {
				raise_and_focus_window (about_dlg, click_time);
				return;
			}
			
			about_dlg = new Gtk.AboutDialog ();
			is_about_open = true;
			about_dlg.set_role ("help");
			about_dlg.set_title (_("About WayPlank"));
			about_dlg.set_decorated (true);
			about_dlg.set_destroy_with_parent (false);
			about_dlg.set_position (Gtk.WindowPosition.CENTER);
			about_dlg.window_position = Gtk.WindowPosition.CENTER;
			about_dlg.gravity = Gdk.Gravity.CENTER;
			about_dlg.set_type_hint (Gdk.WindowTypeHint.DIALOG);
			about_dlg.set_skip_taskbar_hint (true);
			about_dlg.set_skip_pager_hint (true);
			about_dlg.set_keep_above (true);
			about_dlg.set_focus_on_map (true);
			
			about_dlg.set_program_name (program_name);
			about_dlg.set_version ("%s\n%s".printf (build_version, build_version_info));
			try {
				var logo_buf = new Gdk.Pixbuf.from_resource_at_scale (
					"%s/img/wayplank.svg".printf (G_RESOURCE_PATH),
					128, 128, true
				);
				about_dlg.set_logo (logo_buf);
			} catch (Error e) {
				about_dlg.set_logo_icon_name (app_icon);
			}
			
			var fully_supported_compositors = WindowCapabilities.fully_supported_compositors ();
			var fully_supported = (fully_supported_compositors == ""
				? _("Fully supported compositors: none")
				: _("Fully supported compositors: %s").printf (fully_supported_compositors));
			var partially_supported_compositors = WindowCapabilities.partially_supported_compositors ();
			var partially_supported = (partially_supported_compositors == ""
				? _("Partially supported compositors: none")
				: _("Partially supported compositors: %s").printf (partially_supported_compositors));
			about_dlg.set_comments ("%s. %s\n%s\n%s".printf (program_name, build_release_name, fully_supported, partially_supported));
			about_dlg.set_copyright ("Copyright © %s %s Developers".printf (app_copyright, program_name));
			about_dlg.set_website (main_url);
			about_dlg.set_website_label (_("Website"));
			
			if (about_authors != null && about_authors.length > 0)
				about_dlg.set_authors (about_authors);
			if (about_documenters != null && about_documenters.length > 0)
				about_dlg.set_documenters (about_documenters);
			if (about_artists != null && about_artists.length > 0)
				about_dlg.set_artists (about_artists);
			if (about_translators != null && about_translators != "")
				about_dlg.set_translator_credits (about_translators);
			else
				about_dlg.set_translator_credits (_("translator-credits"));
			about_dlg.set_license_type (about_license_type);
			
			about_dlg.response.connect (() => {
				about_dlg.destroy ();
			});
			
			about_dlg.hide.connect (() => {
				is_about_open = false;
				if (about_dlg == null)
					return;
				Gtk.Window? old = about_dlg;
				about_dlg = null;
				old.destroy ();
				check_collapse_all_docks (old);
			});

			about_dlg.destroy.connect (() => {
				is_about_open = false;
				if (about_dlg != null) {
					Gtk.Window? old = about_dlg;
					about_dlg = null;
					check_collapse_all_docks (old);
				}
			});
			
			raise_and_focus_window (about_dlg, click_time);
		}
		
		void raise_and_focus_window (Gtk.Window window, uint32 event_time = 0)
		{
			window.show_all ();
			window.deiconify ();
			window.set_keep_above (true);
			uint32 time = event_time != 0 ? event_time : Gtk.get_current_event_time ();
			if (time != 0) {
				window.present_with_time (time);
			} else {
				window.present ();
			}
			var gdk_win = window.get_window ();
			if (gdk_win != null) {
				gdk_win.raise ();
				gdk_win.focus (time != 0 ? time : Gdk.CURRENT_TIME);
			}
			window.grab_focus ();

			if (!window.get_mapped ()) {
				ulong map_handler = 0;
				map_handler = window.map.connect (() => {
					if (window.get_visible ()) {
						uint32 t = event_time != 0 ? event_time : Gtk.get_current_event_time ();
						if (t != 0)
							window.present_with_time (t);
						else
							window.present ();
						window.grab_focus ();
					}
					if (map_handler != 0) {
						GLib.SignalHandler.disconnect (window, map_handler);
						map_handler = 0;
					}
				});
			}
		}

		/**
		 * Displays the preferences dialog.
		 *
		 * @param controller the dock to show preferences for
		 */
		void show_preferences (DockController controller, string? page_name = null)
		{
			uint32 click_time = Gtk.get_current_event_time ();
			if (preferences_dlg != null) {
				preferences_dlg.controller = controller;
				if (page_name != null)
					preferences_dlg.show_page (page_name);
				raise_and_focus_window (preferences_dlg, click_time);
				return;
			}
			
			preferences_dlg = new PreferencesWindow (controller);
			if (page_name != null)
				preferences_dlg.show_page (page_name);
			
			preferences_dlg.destroy.connect (() => {
				if (preferences_dlg == null)
					return;
				Gtk.Window? old = preferences_dlg;
				preferences_dlg = null;
				check_collapse_all_docks (old);
			});
			
			preferences_dlg.hide.connect (() => {
				if (preferences_dlg == null || preferences_dlg.suppress_destroy_on_hide)
					return;
				Gtk.Window? old = preferences_dlg;
				preferences_dlg = null;
				old.destroy ();
				check_collapse_all_docks (old);
			});
			
			raise_and_focus_window (preferences_dlg, click_time);
		}

		void show_help ()
		{
			uint32 click_time = Gtk.get_current_event_time ();
			if (help_dlg != null) {
				raise_and_focus_window (help_dlg, click_time);
				return;
			}

			help_dlg = new HelpWindow ();

			help_dlg.destroy.connect (() => {
				if (help_dlg == null)
					return;
				Gtk.Window? old = help_dlg;
				help_dlg = null;
				check_collapse_all_docks (old);
			});

			help_dlg.hide.connect (() => {
				if (help_dlg == null)
					return;
				Gtk.Window? old = help_dlg;
				help_dlg = null;
				old.destroy ();
				check_collapse_all_docks (old);
			});

			raise_and_focus_window (help_dlg, click_time);
		}

		void show_first_run (DockController controller)
		{
			uint32 click_time = Gtk.get_current_event_time ();
			if (first_run_dlg != null) {
				raise_and_focus_window (first_run_dlg, click_time);
				return;
			}

			first_run_dlg = new FirstRunWindow (controller);

			first_run_dlg.destroy.connect (() => {
				if (first_run_dlg == null)
					return;
				Gtk.Window? old = first_run_dlg;
				first_run_dlg = null;
				check_collapse_all_docks (old);
			});

			first_run_dlg.hide.connect (() => {
				if (first_run_dlg == null)
					return;
				Gtk.Window? old = first_run_dlg;
				first_run_dlg = null;
				old.destroy ();
				check_collapse_all_docks (old);
			});

			raise_and_focus_window (first_run_dlg, click_time);
		}

		void show_load_environment_failed (DockController controller)
		{
			string details = controller.prefs.load_environment_failed_details;
			string discarded = controller.prefs.discarded_dockitems_details;
			string secondary = "";
			if (details != "" && discarded != "") {
				secondary = "%s\n%s\n\n%s\n%s".printf (
					_("Defaulting partially to default config for:"),
					details,
					_("Discarded corrupted or invalid dockitem:"),
					discarded
				);
			} else if (discarded != "") {
				secondary = "%s\n%s".printf (_("Discarded corrupted or invalid dockitem:"), discarded);
			} else {
				if (details == "")
					details = _("All settings (corrupted latch-state.ini)");
				secondary = "%s\n%s".printf (_("Defaulting partially to default config for:"), details);
			}
			warning ("Load environment failed — %s", secondary.replace ("\n", " "));

			if (Environment.get_variable ("WAYPLANK_NO_PROMPT") == "1")
				return;

			uint32 click_time = Gtk.get_current_event_time ();
			if (env_error_dlg != null) {
				raise_and_focus_window (env_error_dlg, click_time);
				return;
			}

			env_error_dlg = new Gtk.MessageDialog (
				null,
				0,
				Gtk.MessageType.WARNING,
				Gtk.ButtonsType.OK,
				"%s",
				_("Load environment failed")
			);
			env_error_dlg.secondary_text = secondary;
			env_error_dlg.set_title (_("Load environment failed"));
			env_error_dlg.set_role ("help");
			env_error_dlg.set_position (Gtk.WindowPosition.CENTER);
			env_error_dlg.set_keep_above (true);

			env_error_dlg.response.connect (() => {
				if (env_error_dlg != null)
					env_error_dlg.hide ();
			});

			env_error_dlg.destroy.connect (() => {
				if (env_error_dlg == null)
					return;
				Gtk.Window? old = env_error_dlg;
				env_error_dlg = null;
				check_collapse_all_docks (old);
			});

			env_error_dlg.hide.connect (() => {
				if (env_error_dlg == null)
					return;
				Gtk.Window? old = env_error_dlg;
				env_error_dlg = null;
				old.destroy ();
				check_collapse_all_docks (old);
			});

			raise_and_focus_window (env_error_dlg, click_time);
		}

		void show_guide ()
		{
			string guide_b64 = "";
			try {
				var bytes = GLib.resources_lookup_data ("/net/launchpad/plank/doc/guide.md", GLib.ResourceLookupFlags.NONE);
				if (bytes != null) {
					unowned uint8[] data = bytes.get_data ();
					guide_b64 = GLib.Base64.encode (data);
				}
			} catch (GLib.Error e) {
				warning ("Failed to load guide resource: %s", e.message);
				return;
			}

			if (guide_b64 == "")
				return;

			string banner_b64 = "";
			try {
				var b_bytes = GLib.resources_lookup_data ("/net/launchpad/plank/doc/banner.png", GLib.ResourceLookupFlags.NONE);
				if (b_bytes != null) {
					unowned uint8[] b_data = b_bytes.get_data ();
					banner_b64 = GLib.Base64.encode (b_data);
				}
			} catch (GLib.Error e) { }

			string cache_dir = Path.build_filename (Environment.get_user_cache_dir (), "wayplank");
			DirUtils.create_with_parents (cache_dir, 0755);
			string html_path = Path.build_filename (cache_dir, "wayplank_user_guide.html");

			string?[] env_candidates = {
				Environment.get_variable ("LANGUAGE"),
				Environment.get_variable ("LC_ALL"),
				Environment.get_variable ("LC_MESSAGES"),
				Environment.get_variable ("LANG"),
				Intl.setlocale (LocaleCategory.MESSAGES, null)
			};
			string sys_lang = "en";
			foreach (unowned string? cand_raw in env_candidates) {
				if (cand_raw == null || cand_raw.strip () == "")
					continue;
				string first_tok = cand_raw.split (":")[0].strip ();
				int dot_idx = first_tok.index_of_char ('.');
				if (dot_idx >= 0)
					first_tok = first_tok.substring (0, dot_idx);
				int at_idx = first_tok.index_of_char ('@');
				if (at_idx >= 0)
					first_tok = first_tok.substring (0, at_idx);
				string norm_loc = first_tok.down ().replace ("-", "_");
				if (norm_loc == "" || norm_loc == "c" || norm_loc == "posix")
					continue;
				if (norm_loc == "en" || norm_loc.has_prefix ("en_")) {
					sys_lang = "en";
					break;
				}
				if (norm_loc == "zh_tw" || norm_loc == "zh_hk" || norm_loc == "zh_hant") {
					sys_lang = "zh-TW";
					break;
				}
				if (norm_loc.has_prefix ("zh")) {
					sys_lang = "zh-CN";
					break;
				}
				string base_lang = norm_loc.split ("_")[0];
				if (base_lang.length >= 2 && base_lang.length <= 3) {
					bool valid_iso = true;
					for (int ci = 0; ci < base_lang.length; ci++) {
						char ch = base_lang[ci];
						if (ch < 'a' || ch > 'z') {
							valid_iso = false;
							break;
						}
					}
					if (valid_iso) {
						sys_lang = base_lang;
						break;
					}
				}
			}

			var builder = new StringBuilder ();
			builder.append ("""<!DOCTYPE html>
<html lang="en" translate="yes">
<head>
  <meta charset="utf-8">
  <title>WayPlank - User Guide & Reference Manual</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/github-markdown-css@5/github-markdown.min.css">
  <style>
    body {
      box-sizing: border-box;
      min-width: 200px;
      max-width: 1060px;
      margin: 0 auto;
      padding: 40px 24px;
      background-color: #0d1117;
      color: #c9d1d9;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
      scroll-behavior: smooth;
    }
    @media (prefers-color-scheme: light) {
      body { background-color: #ffffff; color: #24292f; }
    }
    .markdown-body {
      background-color: transparent !important;
    }
    .mermaid {
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 8px;
      padding: 20px;
      text-align: center;
      margin: 24px 0;
      overflow-x: auto;
    }
    h1, h2, h3, h4, h5, h6 {
      scroll-margin-top: 24px;
    }
    #wp-lang-bar {
      display: flex;
      align-items: center;
      justify-content: flex-end;
      gap: 10px;
      margin-bottom: 16px;
      padding: 8px 14px;
      border-radius: 8px;
      background: rgba(128, 128, 128, 0.10);
      border: 1px solid rgba(128, 128, 128, 0.22);
      font-size: 13px;
    }
    #wp-lang-select {
      padding: 4px 10px;
      border-radius: 6px;
      border: 1px solid rgba(128, 128, 128, 0.35);
      background: inherit;
      color: inherit;
      font-weight: 600;
      cursor: pointer;
    }
    #wp-trans-status {
      opacity: 0.78;
      font-size: 12px;
    }
  </style>
  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <script src="https://res.zvo.cn/translate/translate.js" async onerror="this.remove()"></script>
</head>
<body class="markdown-body">
  <div id="wp-lang-bar" class="notranslate" translate="no">
    <span id="wp-trans-status">🌐 Language:</span>
    <select id="wp-lang-select" aria-label="Language">
      <option value="en">English (Original)</option>
      <option value="zh-CN">中文 (简体)</option>
      <option value="it">Italiano</option>
      <option value="es">Español</option>
      <option value="fr">Français</option>
      <option value="ca">Català</option>
      <option value="de">Deutsch</option>
      <option value="uk">Українська</option>
    </select>
  </div>
  <div id="content">Loading user guide...</div>
  <script>
    const INITIAL_LANG = '""");
			builder.append (sys_lang);
			builder.append ("""';
    const b64 = '""");
			builder.append (guide_b64);
			builder.append ("""';
    const bannerB64 = '""");
			builder.append (banner_b64);
			builder.append ("""';
    const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    const md = new TextDecoder().decode(bytes);

    function escapeHtml(str) {
      return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function slugify(text) {
      return text.toLowerCase()
        .replace(/<[^>]*>/g, '')
        .replace(/[^\w\s-]/g, '')
        .trim()
        .replace(/\s+/g, '-');
    }

    try {
      if (typeof marked !== 'undefined') {
        const isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        if (typeof mermaid !== 'undefined') {
          mermaid.initialize({ startOnLoad: false, theme: isDark ? 'dark' : 'default' });
        }

        const renderer = new marked.Renderer();
        const origCode = renderer.code.bind(renderer);
        renderer.code = function(token, lang, escaped) {
          let codeText = typeof token === 'object' && token !== null ? token.text : token;
          let codeLang = typeof token === 'object' && token !== null ? token.lang : lang;
          if (codeLang === 'mermaid') {
            return '<pre class="mermaid notranslate" translate="no">' + codeText + '</pre>';
          }
          return origCode(token, lang, escaped);
        };

        marked.setOptions({ renderer: renderer });
        const contentDiv = document.getElementById('content');
        contentDiv.innerHTML = marked.parse(md);

        contentDiv.querySelectorAll('pre, code, .mermaid, kbd, tt').forEach(el => {
          el.classList.add('notranslate');
          el.setAttribute('translate', 'no');
        });

        // Ensure every heading has matching slug IDs for navigation before any translation
        document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(h => {
          const raw = h.textContent.trim();
          const slug = slugify(raw);
          if (!h.id) {
            h.id = slug;
          }
          h.setAttribute('data-orig-slug', slug);
          const altSlug = slug.replace(/^[0-9]+-/, '');
          if (altSlug && altSlug !== slug) {
            const anchor = document.createElement('a');
            anchor.id = altSlug;
            h.parentNode.insertBefore(anchor, h);
          }
        });

        // Add banner image right under the main title if available
        if (bannerB64) {
          const bannerDiv = document.createElement('div');
          bannerDiv.style.textAlign = 'center';
          bannerDiv.style.margin = '20px 0 35px 0';
          bannerDiv.innerHTML = '<img src="data:image/png;base64,' + bannerB64 + '" alt="WayPlank Release Banner" style="max-width:100%; height:auto; border-radius:10px; box-shadow:0 6px 20px rgba(0,0,0,0.35); border:1px solid rgba(255,255,255,0.15);">';
          const firstH1 = contentDiv.querySelector('h1');
          if (firstH1 && firstH1.nextSibling) {
            firstH1.parentNode.insertBefore(bannerDiv, firstH1.nextSibling);
          } else {
            contentDiv.insertBefore(bannerDiv, contentDiv.firstChild);
          }
        }

        // Intercept TOC link clicks and perform robust navigation in Chrome/Firefox
        document.addEventListener('click', function(e) {
          const link = e.target.closest('a[href^="#"]');
          if (!link) return;

          const href = link.getAttribute('href');
          if (!href || href === '#') return;

          const targetId = href.substring(1);
          let target = document.getElementById(targetId);

          if (!target) {
            const normTarget = targetId.toLowerCase().replace(/[^a-z0-9]/g, '');
            for (const h of document.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
              const origSlug = (h.getAttribute('data-orig-slug') || h.textContent).toLowerCase().replace(/[^a-z0-9]/g, '');
              if (origSlug.includes(normTarget) || normTarget.includes(origSlug)) {
                target = h;
                break;
              }
            }
          }

          if (target) {
            e.preventDefault();
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
            history.pushState(null, null, href);
          }
        });

        if (typeof mermaid !== 'undefined') {
          mermaid.run({ querySelector: '.mermaid' });
        }

        // Multi-Provider Auto-Translator (Europe Fast-Path + China-Safe Fallback)
        const textNodes = [];
        const walker = document.createTreeWalker(contentDiv, NodeFilter.SHOW_TEXT, {
          acceptNode: function(node) {
            if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
            const p = node.parentElement;
            if (!p || p.closest('pre, code, .mermaid, .notranslate, script, style, kbd, tt')) {
              return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
        });
        let n;
        while ((n = walker.nextNode())) {
          textNodes.push({ node: n, orig: n.nodeValue });
        }

        async function fetchWithTimeout(url, ms) {
          const ctrl = new AbortController();
          const id = setTimeout(() => ctrl.abort(), ms);
          try {
            const res = await fetch(url, { signal: ctrl.signal });
            if (!res.ok) throw new Error('HTTP ' + res.status);
            return await res.json();
          } finally {
            clearTimeout(id);
          }
        }

        async function translateBatchGoogle(batchText, targetLang) {
          const url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl='
            + encodeURIComponent(targetLang) + '&dt=t&q=' + encodeURIComponent(batchText);
          const data = await fetchWithTimeout(url, 2800);
          if (!Array.isArray(data) || !Array.isArray(data[0])) throw new Error('Invalid GTX response');
          return data[0].map(part => part[0] || '').join('');
        }

        async function translateBatchMyMemory(batchText, targetLang) {
          const mmLang = targetLang === 'zh-CN' ? 'zh-CN' : targetLang;
          const url = 'https://api.mymemory.translated.net/get?q='
            + encodeURIComponent(batchText) + '&langpair=en|' + encodeURIComponent(mmLang);
          const data = await fetchWithTimeout(url, 4500);
          if (!data || !data.responseData || !data.responseData.translatedText) {
            throw new Error('Invalid MyMemory response');
          }
          return data.responseData.translatedText;
        }

        async function translateChunk(lines, targetLang) {
          const joined = lines.join('\n');
          try {
            const out = await Promise.any([
              translateBatchGoogle(joined, targetLang),
              translateBatchMyMemory(joined, targetLang)
            ]);
            const split = out.split('\n');
            if (split.length === lines.length) return split;
          } catch (_) {}
          return null;
        }

        let activeTranslateToken = 0;
        async function applyGuideLanguage(targetLang) {
          const myToken = ++activeTranslateToken;
          const statusEl = document.getElementById('wp-trans-status');
          if (!targetLang || targetLang === 'en') {
            textNodes.forEach(item => { item.node.nodeValue = item.orig; });
            if (statusEl) statusEl.textContent = '🌐 Language:';
            return;
          }

          if (statusEl) statusEl.textContent = '⏳ Translating (' + targetLang + ')...';

          // If China-native ZVO translate.js is loaded and user is in zh-CN, allow fallback if chunking fails
          const SEP_CHARS = 420;
          let batchIndices = [];
          let batchLines = [];
          let curLen = 0;

          async function flushBatch() {
            if (batchIndices.length === 0 || myToken !== activeTranslateToken) return;
            const idxs = batchIndices;
            const lns = batchLines;
            batchIndices = [];
            batchLines = [];
            curLen = 0;
            const translated = await translateChunk(lns, targetLang);
            if (myToken !== activeTranslateToken) return;
            if (translated) {
              for (let i = 0; i < idxs.length; i++) {
                const origVal = textNodes[idxs[i]].orig;
                const lead = origVal.match(/^\s*/)[0];
                const trail = origVal.match(/\s*$/)[0];
                textNodes[idxs[i]].node.nodeValue = lead + translated[i].trim() + trail;
              }
            } else if (window.translate && typeof window.translate.execute === 'function') {
              try {
                const zvoMap = {
                  'zh-CN': 'chinese_simplified',
                  'it': 'italian',
                  'es': 'spanish',
                  'fr': 'french',
                  'ca': 'catalan',
                  'de': 'german',
                  'uk': 'ukrainian'
                };
                if (zvoMap[targetLang]) {
                  window.translate.selectLanguageTag.show = false;
                  window.translate.changeLanguage(zvoMap[targetLang]);
                }
              } catch (_) {}
            }
          }

          for (let i = 0; i < textNodes.length; i++) {
            const clean = textNodes[i].orig.replace(/\s+/g, ' ').trim();
            if (!clean || /^[0-9.\-+/*=()[\]{}:;,\s]+$/.test(clean)) continue;
            if (curLen + clean.length > SEP_CHARS && batchLines.length > 0) {
              await flushBatch();
              if (myToken !== activeTranslateToken) return;
            }
            batchIndices.push(i);
            batchLines.push(clean);
            curLen += clean.length + 1;
          }
          await flushBatch();
          if (myToken === activeTranslateToken && statusEl) {
            statusEl.textContent = '🌐 Language (' + targetLang + '):';
          }
        }

        const langSel = document.getElementById('wp-lang-select');
        if (langSel) {
          if (INITIAL_LANG && !Array.from(langSel.options).some(o => o.value === INITIAL_LANG)) {
            const customOpt = document.createElement('option');
            customOpt.value = INITIAL_LANG;
            customOpt.textContent = INITIAL_LANG.toUpperCase();
            langSel.appendChild(customOpt);
          }
          langSel.value = INITIAL_LANG;
          langSel.addEventListener('change', function() {
            applyGuideLanguage(this.value);
          });
          if (INITIAL_LANG && INITIAL_LANG !== 'en') {
            applyGuideLanguage(INITIAL_LANG);
          }
        }
      } else {
        document.getElementById('content').innerHTML = '<div style="padding:15px; background:rgba(255,165,0,0.1); border:1px solid orange; border-radius:6px; margin-bottom:20px;"><strong>Notice:</strong> Offline mode active (CDN unreachable). Displaying raw documentation below.</div><pre style="white-space: pre-wrap; font-family: monospace;">' + escapeHtml(md) + '</pre>';
      }
    } catch (e) {
      document.getElementById('content').innerHTML = '<div style="color:red; padding:20px;">Error rendering guide: ' + e.message + '</div><pre style="white-space: pre-wrap; font-family: monospace;">' + escapeHtml(md) + '</pre>';
    }
  </script>
</body>
</html>
""");

			try {
				FileUtils.set_contents (html_path, builder.str);
				string uri = "file://" + html_path;
				try {
					AppInfo.launch_default_for_uri (uri, null);
				} catch (GLib.Error err) {
					System.get_default ().open_uri (uri);
				}
			} catch (GLib.Error e) {
				warning ("Failed to save/open guide HTML: %s", e.message);
			}
		}

		uint resume_timer_id = 0U;
		uint upgrade_signal_source_id = 0U;
		string startup_exe_path = "";
		bool is_reloading_for_upgrade = false;

		void setup_binary_upgrade_watcher ()
		{
			try {
				var resolved = FileUtils.read_link ("/proc/self/exe");
				if (resolved.has_suffix (" (deleted)"))
					resolved = resolved.substring (0, resolved.length - " (deleted)".length);
				startup_exe_path = resolved;
			} catch (Error e) {
				startup_exe_path = "";
			}

			upgrade_signal_source_id = GLib.Unix.signal_add ((int) Posix.Signal.WINCH, () => {
				if (is_shutting_down || is_reloading_for_upgrade || startup_exe_path == "")
					return true;
				try {
					var current_link = FileUtils.read_link ("/proc/self/exe");
					if (current_link.has_suffix (" (deleted)") && FileUtils.test (startup_exe_path, FileTest.IS_EXECUTABLE)) {
						is_reloading_for_upgrade = true;
						upgrade_signal_source_id = 0U;
						string saved_exe = startup_exe_path;
						string? saved_dock = dock_name;
						message ("Binary upgrade detected at '%s', hot-reloading WayPlank...", saved_exe);
						perform_clean_shutdown ();
						string[] spawn_argv = { saved_exe, "--replace" };
						if (saved_dock != null && saved_dock != "")
							spawn_argv = { saved_exe, "--replace", "-n", saved_dock };
						Process.spawn_async (null, spawn_argv, null, SpawnFlags.SEARCH_PATH, null, null);
						Posix.exit (0);
						return false;
					}
				} catch (Error e) {
					warning ("Failed to hot-reload upgraded WayPlank binary: %s", e.message);
				}
				return true;
			});
		}

		void schedule_dock_refresh (uint delay_ms)
		{
			if (resume_timer_id > 0U) {
				GLib.Source.remove (resume_timer_id);
				resume_timer_id = 0U;
			}

			resume_timer_id = GLib.Timeout.add (delay_ms, () => {
				resume_timer_id = 0U;
				refresh_docks ();
				return false;
			});
		}

		public void refresh_docks ()
		{
			message ("Refreshing all docks after resume / wake-up event...");
			foreach (var dock in docks) {
				dock.handle_system_resume ();
			}
		}

		uint login_sleep_sub_id = 0U;
		uint login_unlock_sub_id = 0U;
		Gee.ArrayList<uint>? screensaver_sub_ids = null;

		void teardown_power_management_listener ()
		{
			if (login_sleep_sub_id > 0U || login_unlock_sub_id > 0U) {
				try {
					var system_bus = Bus.get_sync (BusType.SYSTEM, null);
					if (login_sleep_sub_id > 0U) {
						system_bus.signal_unsubscribe (login_sleep_sub_id);
						login_sleep_sub_id = 0U;
					}
					if (login_unlock_sub_id > 0U) {
						system_bus.signal_unsubscribe (login_unlock_sub_id);
						login_unlock_sub_id = 0U;
					}
				} catch (Error e) { }
			}
			if (screensaver_sub_ids != null && screensaver_sub_ids.size > 0) {
				try {
					var session_bus = Bus.get_sync (BusType.SESSION, null);
					foreach (uint id in screensaver_sub_ids) {
						if (id > 0U)
							session_bus.signal_unsubscribe (id);
					}
				} catch (Error e) { }
				screensaver_sub_ids.clear ();
			}
		}

		void setup_power_management_listener ()
		{
			// 1. Listen for systemd-logind sleep/resume events (system bus)
			try {
				var system_bus = Bus.get_sync (BusType.SYSTEM, null);
				login_sleep_sub_id = system_bus.signal_subscribe (
					"org.freedesktop.login1",
					"org.freedesktop.login1.Manager",
					"PrepareForSleep",
					"/org/freedesktop/login1",
					null,
					DBusSignalFlags.NONE,
					(conn, sender, path, iface, signal_name, parameters) => {
						bool is_sleeping = false;
						parameters.get ("(b)", out is_sleeping);
						if (!is_sleeping) {
							message ("System resumed from suspend/hibernate! Scheduling dock refresh...");
							schedule_dock_refresh (800);
						}
					}
				);
				debug ("Subscribed to systemd-logind PrepareForSleep signal");

				login_unlock_sub_id = system_bus.signal_subscribe (
					"org.freedesktop.login1",
					"org.freedesktop.login1.Session",
					"Unlock",
					null,
					null,
					DBusSignalFlags.NONE,
					(conn, sender, path, iface, signal_name, parameters) => {
						message ("systemd-logind Session Unlock detected! Scheduling dock refresh...");
						schedule_dock_refresh (500);
					}
				);
				debug ("Subscribed to systemd-logind Session.Unlock signal");
			} catch (Error e) {
				debug ("Unable to subscribe to systemd-logind signals: %s", e.message);
			}

			// 2. Listen for ScreenSaver / Screen Lock unlock events (session bus: freedesktop + GNOME)
			try {
				var session_bus = Bus.get_sync (BusType.SESSION, null);
				screensaver_sub_ids = new Gee.ArrayList<uint> ();
				string[] screensaver_ifaces = {
					"org.freedesktop.ScreenSaver",
					"org.gnome.ScreenSaver"
				};
				foreach (unowned string ss_iface in screensaver_ifaces) {
					uint sub_id = session_bus.signal_subscribe (
						null,
						ss_iface,
						"ActiveChanged",
						null,
						null,
						DBusSignalFlags.NONE,
						(conn, sender, path, iface, signal_name, parameters) => {
							bool is_active = false;
							parameters.get ("(b)", out is_active);
							if (!is_active) {
								message ("Screen unlocked (%s)! Scheduling dock refresh...", iface);
								schedule_dock_refresh (500);
							}
						}
					);
					screensaver_sub_ids.add (sub_id);
				}
				debug ("Subscribed to ScreenSaver ActiveChanged signals");
			} catch (Error e) {
				debug ("Unable to subscribe to ScreenSaver ActiveChanged: %s", e.message);
			}
		}
	}
}
