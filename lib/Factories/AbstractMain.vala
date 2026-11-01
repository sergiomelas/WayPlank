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
		public static string? saved_gtk_use_portal = null;

		public static void perform_clean_shutdown ()
		{
			if (is_shutting_down)
				return;
			is_shutting_down = true;

			if (app_instance != null && app_instance.resume_timer_id > 0U) {
				GLib.Source.remove (app_instance.resume_timer_id);
				app_instance.resume_timer_id = 0U;
			}

			SystemTheme.cleanup_if_active ();
			BrightnessControl.cleanup_if_active ();
			WindowControl.cleanup ();
		}

		static void sig_handler (int sig)
		{
			warning ("Caught signal (%d), exiting", sig);
			perform_clean_shutdown ();
			Posix.exit (0);
		}
		
		static construct
		{
			Posix.signal (Posix.Signal.INT, sig_handler);
			Posix.signal (Posix.Signal.TERM, sig_handler);
			Posix.signal (Posix.Signal.HUP, sig_handler);
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
			if (app_instance != null && app_instance.primary_dock != null) {
				app_instance.primary_dock.check_collapse_after_interaction (closing_win);
			}
		}

		Gtk.AboutDialog? about_dlg;
		PreferencesWindow? preferences_dlg;
		HelpWindow? help_dlg;
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
			WindowControl.start ();
			create_actions ();
			setup_power_management_listener ();
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

			action = new SimpleAction ("report", null);
			action.activate.connect (() => {
				show_report ();
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
				Gtk.Window? old = about_dlg;
				about_dlg.destroy ();
				about_dlg = null;
				if (primary_dock != null)
					primary_dock.check_collapse_after_interaction (old);
			});

			about_dlg.destroy.connect (() => {
				is_about_open = false;
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
				Gtk.Window? old = preferences_dlg;
				preferences_dlg = null;
				if (primary_dock != null)
					primary_dock.check_collapse_after_interaction (old);
			});
			
			preferences_dlg.hide.connect (() => {
				Gtk.Window? old = preferences_dlg;
				preferences_dlg.destroy ();
				preferences_dlg = null;
				if (primary_dock != null)
					primary_dock.check_collapse_after_interaction (old);
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
				Gtk.Window? old = help_dlg;
				help_dlg = null;
				if (primary_dock != null)
					primary_dock.check_collapse_after_interaction (old);
			});

			help_dlg.hide.connect (() => {
				Gtk.Window? old = help_dlg;
				help_dlg.destroy ();
				help_dlg = null;
				if (primary_dock != null)
					primary_dock.check_collapse_after_interaction (old);
			});

			raise_and_focus_window (help_dlg, click_time);
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

			var builder = new StringBuilder ();
			builder.append ("""<!DOCTYPE html>
<html lang="en">
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
  </style>
  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
</head>
<body class="markdown-body">
  <div id="content">Loading user guide...</div>
  <script>
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
            return '<pre class="mermaid">' + codeText + '</pre>';
          }
          return origCode(token, lang, escaped);
        };

        marked.setOptions({ renderer: renderer });
        const contentDiv = document.getElementById('content');
        contentDiv.innerHTML = marked.parse(md);

        // Ensure every heading has matching slug IDs for navigation
        document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(h => {
          const raw = h.textContent.trim();
          const slug = slugify(raw);
          if (!h.id) {
            h.id = slug;
          }
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
              const normH = h.textContent.toLowerCase().replace(/[^a-z0-9]/g, '');
              if (normH.includes(normTarget) || normTarget.includes(normH)) {
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

		void show_report ()
		{
			string report_b64 = "";
			try {
				var bytes = GLib.resources_lookup_data ("/net/launchpad/plank/doc/report.md", GLib.ResourceLookupFlags.NONE);
				if (bytes != null) {
					unowned uint8[] data = bytes.get_data ();
					report_b64 = GLib.Base64.encode (data);
				}
			} catch (GLib.Error e) {
				warning ("Failed to load report resource: %s", e.message);
				return;
			}

			if (report_b64 == "")
				return;

			string cache_dir = Path.build_filename (Environment.get_user_cache_dir (), "wayplank");
			DirUtils.create_with_parents (cache_dir, 0755);
			string html_path = Path.build_filename (cache_dir, "wayplank_migration_report.html");

			var builder = new StringBuilder ();
			builder.append ("""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>WayPlank - Wayland Migration & Architecture Report</title>
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
  </style>
  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
</head>
<body class="markdown-body">
  <div id="content">Loading documentation report...</div>
  <script>
    const b64 = '""");
			builder.append (report_b64);
			builder.append ("""';
    const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    const md = new TextDecoder().decode(bytes);

    function escapeHtml(str) {
      return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
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
            return '<pre class="mermaid">' + codeText + '</pre>';
          }
          return origCode(token, lang, escaped);
        };

        marked.setOptions({ renderer: renderer });
        document.getElementById('content').innerHTML = marked.parse(md);

        if (typeof mermaid !== 'undefined') {
          mermaid.run({ querySelector: '.mermaid' });
        }
      } else {
        document.getElementById('content').innerHTML = '<div style="padding:15px; background:rgba(255,165,0,0.1); border:1px solid orange; border-radius:6px; margin-bottom:20px;"><strong>Notice:</strong> Offline mode active (CDN unreachable). Displaying raw documentation below.</div><pre style="white-space: pre-wrap; font-family: monospace;">' + escapeHtml(md) + '</pre>';
      }
    } catch (e) {
      document.getElementById('content').innerHTML = '<div style="color:red; padding:20px;">Error rendering report: ' + e.message + '</div><pre style="white-space: pre-wrap; font-family: monospace;">' + escapeHtml(md) + '</pre>';
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
				warning ("Failed to save/open report HTML: %s", e.message);
			}
		}

		uint resume_timer_id = 0U;

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

		void setup_power_management_listener ()
		{
			// 1. Listen for systemd-logind sleep/resume events (system bus)
			try {
				var system_bus = Bus.get_sync (BusType.SYSTEM, null);
				system_bus.signal_subscribe (
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
			} catch (Error e) {
				debug ("Unable to subscribe to systemd-logind PrepareForSleep: %s", e.message);
			}

			// 2. Listen for ScreenSaver / Screen Lock unlock events (session bus)
			try {
				var session_bus = Bus.get_sync (BusType.SESSION, null);
				session_bus.signal_subscribe (
					null,
					"org.freedesktop.ScreenSaver",
					"ActiveChanged",
					null,
					null,
					DBusSignalFlags.NONE,
					(conn, sender, path, iface, signal_name, parameters) => {
						bool is_active = false;
						parameters.get ("(b)", out is_active);
						if (!is_active) {
							message ("Screen unlocked! Scheduling dock refresh...");
							schedule_dock_refresh (500);
						}
					}
				);
				debug ("Subscribed to ScreenSaver ActiveChanged signal");
			} catch (Error e) {
				debug ("Unable to subscribe to ScreenSaver ActiveChanged: %s", e.message);
			}
		}
	}
}
