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
	 * Milestone W1 bootstrap runtime for Windows (`hal/Windows/`).
	 * Extracts embedded `gschemas.compiled` from GResource into
	 * `%LOCALAPPDATA%\WayPlank\glib-2.0\schemas` and provides backslash-safe
	 * `CommandLineToArgvW` command parsing. Expanded into full Win32 runtime
	 * in Milestone W5 (`Win32PlatformRuntime`).
	 */
	class Win32BootstrapRuntime : GLib.Object, IPlatformRuntime
	{
		static Win32BootstrapRuntime? instance = null;
		string? cached_schema_dir = null;

		public static Win32BootstrapRuntime get_default ()
		{
			if (instance == null)
				instance = new Win32BootstrapRuntime ();
			return instance;
		}

		public string ensure_embedded_schemas_dir ()
		{
			if (cached_schema_dir != null && cached_schema_dir.length > 0)
				return cached_schema_dir;

			string? base_dir = Environment.get_variable ("LOCALAPPDATA");
			if (base_dir == null || base_dir.strip ().length == 0)
				base_dir = Environment.get_user_data_dir ();

			string schema_dir = Path.build_filename (base_dir, "WayPlank", "glib-2.0", "schemas");
			DirUtils.create_with_parents (schema_dir, 0755);

			string schema_file = Path.build_filename (schema_dir, "gschemas.compiled");
			try {
				var bytes = GLib.resources_lookup_data (
					"/net/launchpad/plank/glib-2.0/schemas/gschemas.compiled",
					GLib.ResourceLookupFlags.NONE
				);
				if (bytes != null) {
					unowned uint8[] data = bytes.get_data ();
					FileUtils.set_data (schema_file, data);
				}
			} catch (Error e) {
				warning ("Win32BootstrapRuntime: failed to extract embedded gschemas.compiled: %s", e.message);
			}

			cached_schema_dir = schema_dir;
			Environment.set_variable ("G_SETTINGS_SCHEMA_DIR", schema_dir, false);
			return schema_dir;
		}

		public bool open_system_utility (DesktopUtilityKind kind) { return false; }
		public bool open_uri (string uri, Gtk.Window? parent = null) { return false; }
		public bool http_get_sync (string url, int timeout_sec, out string response_body)
		{
			response_body = "";
			return false;
		}
		public bool extract_archive (string archive_path, string dest_dir) { return false; }
		public bool validate_keyfile_isolated (string path) { return true; }
		public bool is_autostart_enabled () { return false; }
		public bool set_autostart_enabled (bool enabled) { return false; }
		public void terminate_legacy_competing_docks () {}
		public void replace_running_instances (string target_dock_name) {}

		public void prepare_process_environment ()
		{
			ensure_embedded_schemas_dir ();
		}

		public void restore_process_environment () {}

		public bool verify_supported_display (Gdk.Display? display, out string error_message)
		{
			if (display == null) {
				error_message = "No Win32 display available.";
				return false;
			}
			error_message = "";
			return true;
		}

		public string get_self_launcher_id () { return "wayplank"; }
		public string get_system_data_dir () { return Build.DATADIR; }

		public string[] get_extra_schema_dirs ()
		{
			string dir = ensure_embedded_schemas_dir ();
			return dir.length > 0 ? new string[] { dir } : new string[] {};
		}

		public string canonicalize_path (string path)
		{
			return path.replace ("/", "\\");
		}

		public bool paths_equal (string path_a, string path_b)
		{
			return canonicalize_path (path_a).down () == canonicalize_path (path_b).down ();
		}

		public string expand_path_variables (string raw, Gee.HashMap<string, string>? extra_vars = null)
		{
			if (raw.length == 0)
				return raw;
			string result = raw;
			if (result.has_prefix ("~/") || result.has_prefix ("~\\"))
				result = Path.build_filename (Environment.get_home_dir (), result.substring (2));
			if (extra_vars != null) {
				foreach (var entry in extra_vars.entries) {
					result = result.replace ("%" + entry.key + "%", entry.value);
					result = result.replace ("$" + entry.key, entry.value);
				}
			}
			return result;
		}

		public int get_current_pid ()
		{
			return Win32Bridge.get_current_pid ();
		}

		public void set_process_title (string title) {}

		public string os_release_summary ()
		{
			return "Windows (Win32 HAL)";
		}

		public void install_lifecycle_signals () {}
		public void install_session_and_upgrade_watchers () {}
		public void reexec_self_on_upgrade (string executable_path, string? dock_name) {}

		public void exit_immediately (int status_code)
		{
			Win32Bridge.exit_immediately (status_code);
		}

		/**
		 * Backslash-preserving Windows `CommandLineToArgvW` tokenization grammar:
		 * backslashes are literal path separators unless immediately preceding `"`.
		 */
		public string[] parse_command_argv (string cmdline)
		{
			var args = new Gee.ArrayList<string> ();
			var cur = new StringBuilder ();
			bool in_quotes = false;
			bool has_token = false;
			int len = cmdline.length;
			int i = 0;

			while (i < len) {
				char c = cmdline[i];
				if (!in_quotes && (c == ' ' || c == '\t' || c == '\r' || c == '\n')) {
					if (has_token) {
						args.add (cur.str);
						cur.truncate (0);
						has_token = false;
					}
					i++;
					continue;
				}
				has_token = true;
				if (c == '\\') {
					int bs = 0;
					while (i < len && cmdline[i] == '\\') {
						bs++;
						i++;
					}
					if (i < len && cmdline[i] == '"') {
						for (int k = 0; k < bs / 2; k++)
							cur.append_c ('\\');
						if ((bs % 2) == 1) {
							cur.append_c ('"');
							i++;
						}
					} else {
						for (int k = 0; k < bs; k++)
							cur.append_c ('\\');
					}
					continue;
				}
				if (c == '"') {
					if (in_quotes && i + 1 < len && cmdline[i + 1] == '"') {
						cur.append_c ('"');
						i += 2;
					} else {
						in_quotes = !in_quotes;
						i++;
					}
					continue;
				}
				cur.append_c (c);
				i++;
			}

			if (has_token)
				args.add (cur.str);

			return args.to_array ();
		}

		public void cleanup () {}
	}

	/**
	 * Southbound Windows HAL bootstrapper linked exclusively into Windows builds
	 * (`BuildWin.sh` -> `build/wayplank.exe`) via `wayplank_hal_platform_*`.
	 */
	public class WindowsHalBootstrap : GLib.Object
	{
		[CCode (cname = "wayplank_hal_platform_early_runtime")]
		public static IPlatformRuntime early_runtime ()
		{
			var rt = Win32BootstrapRuntime.get_default ();
			rt.ensure_embedded_schemas_dir ();
			return rt;
		}

		[CCode (cname = "wayplank_hal_platform_early_apps")]
		public static IAppSystem early_apps ()
		{
			return new NullAppSystem ();
		}

		[CCode (cname = "wayplank_hal_platform_bootstrap")]
		public static void initialize ()
		{
			var rt = Win32BootstrapRuntime.get_default ();
			rt.ensure_embedded_schemas_dir ();

			var caps = new PlatformCapabilities ();
			caps.supports_intelligent_hide = true;
			caps.supports_dodge_maximized = true;
			caps.supports_dodge_all = true;
			caps.supports_dodge_active = true;
			caps.fallback_hide_mode = HideType.DODGE_MAXIMIZED;
			caps.supports_primary_display = true;
			caps.supports_live_thumbnails = true;
			caps.supports_panel_struts = true;
			caps.supports_poof_overlay = true;
			caps.supports_quit_action = true;
			caps.supports_pressure_reveal = false;
			caps.supports_hardware_brightness = true;
			caps.uses_shell_anchored_surfaces = false;
			caps.unsupported_hide_mode_suffix = "";
			caps.fully_supported_summary = "Windows (Win32/DWM)";
			caps.partially_supported_summary = "";

			Hal.bind_display_stack (
				caps,
				new NullDockShell (),
				new NullWindowBackend (),
				new NullThumbnailProvider ()
			);
			Hal.bind_system_stack (
				new NullBusBackend (),
				new NullSystemTelemetry (),
				rt,
				new NullAppSystem ()
			);
		}
	}
}
