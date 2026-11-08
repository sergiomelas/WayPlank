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
	 * Local, compositor-neutral application usage tracker ("frecency") used by the
	 * Smart Pinned Accordion.
	 *
	 * Modelled after GNOME Shell's shell-app-usage.c:
	 *  - 100% event-driven: there are NO timers. Points are only added when the user
	 *    launches an app from the dock, or when a focus session ends.
	 *  - Scores decay lazily (exponential, ~2 weeks half-life) whenever they are read
	 *    or updated, never in the background.
	 *  - Scores are kept below SCORE_MAX by proportional rescaling.
	 *  - Persisted in ~/.local/share/wayplank/app_usage.json: written on clean shutdown
	 *    and, at most once every SAVE_THROTTLE_SECONDS, right after a change.
	 *
	 * The only compositor data consumed is "which launcher is currently active", which
	 * is supplied by the dock item provider from the normalized WindowInfo.Active flag.
	 */
	public class AppUsageService : GLib.Object
	{
		/** Upper bound of any single score (proportional rescaling above this). */
		public const double SCORE_MAX = 100.0;
		/** Score half-life: ~2 weeks, like GNOME Shell. */
		public const double HALF_LIFE_SECONDS = 14.0 * 24.0 * 3600.0;
		/** Focus sessions shorter than this are ignored (filters Alt+Tab flicks). */
		public const double MIN_FOCUS_SECONDS = 5.0;
		/** Focus duration which earns the full duration bonus. */
		public const double FOCUS_FULL_SECONDS = 300.0;
		/** Points for an explicit launch/click from the dock. */
		public const double LAUNCH_POINTS = 1.0;
		/** Hard cap of points granted by one single focus session. */
		public const double FOCUS_MAX_POINTS = 3.0;
		/** Scores closer than this are considered a tie (manual dock order decides). */
		public const double TIE_EPSILON = 0.05;

		const int64 SAVE_THROTTLE_SECONDS = 300;
		const double PRUNE_BELOW = 0.01;
		const int MAX_ENTRIES = 1024;
		const int MAX_KEY_LENGTH = 256;
		const int64 MAX_FILE_BYTES = 1048576;
		const string STORE_FILE_NAME = "app_usage.json";

		class UsageEntry
		{
			public double score = 0.0;
			public int64 stamp = 0;
		}

		static AppUsageService? instance = null;

		public static unowned AppUsageService get_default ()
		{
			if (instance == null)
				instance = new AppUsageService ();
			return instance;
		}

		/**
		 * Flushes the running focus session and writes the scores, but only if the
		 * service was ever created (nothing to do for sessions which never used it).
		 */
		public static void shutdown_if_active ()
		{
			if (instance != null)
				instance.shutdown ();
		}

		public static void flush_if_active ()
		{
			if (instance != null)
				instance.flush ();
		}

		public void flush ()
		{
			if (is_shut_down)
				return;
			save ();
		}

		Gee.HashMap<string, UsageEntry> entries;
		File? store_file = null;
		bool dirty = false;
		bool is_shut_down = false;
		int64 last_save_s = 0;
		string? focus_key = null;
		int64 focus_start_us = 0;

		construct
		{
			entries = new Gee.HashMap<string, UsageEntry> ();
			if (Paths.AppDataFolder != null)
				store_file = Paths.AppDataFolder.get_child (STORE_FILE_NAME);
			last_save_s = now_seconds ();
			load ();
		}

		static inline int64 now_seconds ()
		{
			return GLib.get_real_time () / 1000000;
		}

		/**
		 * Stable usage key of a launcher: the basename of its .desktop file, so scores
		 * survive a launcher being moved or re-pinned.
		 */
		public static string key_for (string launcher)
		{
			if (launcher.has_prefix ("file://"))
				return File.new_for_uri (launcher).get_basename () ?? launcher;
			if (launcher.has_prefix ("/"))
				return Path.get_basename (launcher);
			return launcher;
		}

		static double decayed (UsageEntry entry, int64 now_s)
		{
			var dt = (double) (now_s - entry.stamp);
			if (dt <= 0.0)
				return entry.score;
			return entry.score * Math.pow (2.0, -dt / HALF_LIFE_SECONDS);
		}

		/**
		 * Current (lazily decayed) score of a launcher. 0.0 for apps never used.
		 */
		public double get_score (string launcher)
		{
			var entry = entries.get (key_for (launcher));
			if (entry == null)
				return 0.0;
			return decayed (entry, now_seconds ());
		}

		/**
		 * Registers an explicit launch/click of a launcher from the dock.
		 */
		public void note_launch (string launcher)
		{
			add_points (key_for (launcher), LAUNCH_POINTS);
		}

		/**
		 * Informs the service which launcher currently owns the focused window
		 * (null if none of the dock's apps is active). Idempotent: repeated calls with
		 * the same launcher do nothing, so it is safe to call on every window refresh.
		 */
		public void note_active_launcher (string? launcher)
		{
			if (is_shut_down)
				return;

			string? key = (launcher != null && launcher != "") ? key_for (launcher) : null;
			if (key == focus_key)
				return;

			end_focus_session ();
			focus_key = key;
			focus_start_us = (key != null) ? GLib.get_monotonic_time () : 0;
		}

		void end_focus_session ()
		{
			if (focus_key == null)
				return;

			var key = focus_key;
			var seconds = (double) (GLib.get_monotonic_time () - focus_start_us) / 1000000.0;
			focus_key = null;
			focus_start_us = 0;

			if (seconds < MIN_FOCUS_SECONDS)
				return;

			add_points (key, 1.0 + double.min (seconds / FOCUS_FULL_SECONDS, FOCUS_MAX_POINTS - 1.0));
		}

		void add_points (string key, double points)
		{
			if (is_shut_down || key == "" || key.length > MAX_KEY_LENGTH)
				return;

			var now_s = now_seconds ();
			var entry = entries.get (key);
			if (entry == null) {
				if (entries.size >= MAX_ENTRIES)
					return;
				entry = new UsageEntry ();
				entry.stamp = now_s;
				entries.set (key, entry);
			}

			entry.score = decayed (entry, now_s) + points;
			entry.stamp = now_s;

			if (entry.score > SCORE_MAX) {
				var factor = SCORE_MAX / entry.score;
				foreach (var other in entries.values) {
					other.score = decayed (other, now_s) * factor;
					other.stamp = now_s;
				}
			}

			dirty = true;
			debug ("AppUsageService: '%s' +%.2f -> %.2f", key, points, entry.score);

			if (now_s - last_save_s >= SAVE_THROTTLE_SECONDS)
				save ();
		}

		/**
		 * Closes the running focus session and writes the scores to disk.
		 * Called from the clean-shutdown path.
		 */
		public void shutdown ()
		{
			if (is_shut_down)
				return;
			end_focus_session ();
			save ();
			is_shut_down = true;
		}

		/**
		 * Human readable score of a single launcher (Developer Tools / debug log).
		 */
		public string describe (string launcher)
		{
			var key = key_for (launcher);
			var entry = entries.get (key);
			if (entry == null)
				return "%s: score 0.00 (never used)".printf (key);
			return "%s: score %.2f (raw %.2f)".printf (key, decayed (entry, now_seconds ()), entry.score);
		}

		/**
		 * Multi-line ranking of the most used apps (Developer Tools / debug log).
		 */
		public string describe_top (int limit = 15)
		{
			var now_s = now_seconds ();
			var keys = new Gee.ArrayList<string> ();
			keys.add_all (entries.keys);
			keys.sort ((a, b) => {
				var score_a = decayed (entries.get (a), now_s);
				var score_b = decayed (entries.get (b), now_s);
				return (score_a < score_b) ? 1 : ((score_a > score_b) ? -1 : 0);
			});

			var text = new StringBuilder ();
			int n = 0;
			foreach (var key in keys) {
				if (n++ >= limit)
					break;
				text.append ("  %2d. %s  %.2f\n".printf (n, key, decayed (entries.get (key), now_s)));
			}
			if (n == 0)
				text.append ("  (no usage data yet)\n");
			return text.str;
		}

		void load ()
		{
			if (store_file == null)
				return;
			var path = store_file.get_path ();
			if (path == null || !FileUtils.test (path, FileTest.IS_REGULAR))
				return;

			try {
				// The file is tiny (<= MAX_ENTRIES short lines): refuse anything absurdly large
				var info = store_file.query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
				if (info.get_size () > MAX_FILE_BYTES) {
					warning ("AppUsageService: ignoring oversized '%s'", path);
					return;
				}

				var parser = new Json.Parser ();
				parser.load_from_file (path);
				unowned Json.Node? root = parser.get_root ();
				if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
					return;
				unowned Json.Object obj = root.get_object ();
				if (!obj.has_member ("entries"))
					return;
				unowned Json.Node entries_node = obj.get_member ("entries");
				if (entries_node.get_node_type () != Json.NodeType.OBJECT)
					return;
				unowned Json.Object entries_obj = entries_node.get_object ();

				var now_s = now_seconds ();
				foreach (unowned string name in entries_obj.get_members ()) {
					if (entries.size >= MAX_ENTRIES)
						break;
					if (name == "" || name.length > MAX_KEY_LENGTH)
						continue;
					unowned Json.Node node = entries_obj.get_member (name);
					if (node.get_node_type () != Json.NodeType.OBJECT)
						continue;
					unowned Json.Object item = node.get_object ();
					if (!item.has_member ("score") || !item.has_member ("stamp"))
						continue;

					// json-glib raises a g_critical () on type mismatches: validate before reading
					unowned Json.Node score_node = item.get_member ("score");
					unowned Json.Node stamp_node = item.get_member ("stamp");
					if (score_node.get_node_type () != Json.NodeType.VALUE
						|| stamp_node.get_node_type () != Json.NodeType.VALUE)
						continue;
					var score_type = score_node.get_value_type ();
					var stamp_type = stamp_node.get_value_type ();
					if ((score_type != typeof (double) && score_type != typeof (int64))
						|| stamp_type != typeof (int64))
						continue;

					var score = score_node.get_double ();
					var stamp = stamp_node.get_int ();
					// Written as !(a && b) so that NaN is rejected as well
					if (!(score >= 0.0 && score <= SCORE_MAX))
						continue;
					if (stamp > now_s)
						stamp = now_s;

					var entry = new UsageEntry ();
					entry.score = score;
					entry.stamp = stamp;
					entries.set (name, entry);
				}
			} catch (GLib.Error e) {
				warning ("AppUsageService: unable to read '%s': %s", path, e.message);
				entries.clear ();
			}
		}

		void save ()
		{
			last_save_s = now_seconds ();
			if (!dirty || store_file == null)
				return;
			var path = store_file.get_path ();
			if (path == null)
				return;

			var now_s = last_save_s;
			var builder = new Json.Builder ();
			builder.begin_object ();
			builder.set_member_name ("version");
			builder.add_int_value (1);
			builder.set_member_name ("entries");
			builder.begin_object ();

			var stale = new Gee.ArrayList<string> ();
			foreach (var item in entries.entries) {
				var score = decayed (item.value, now_s);
				if (score < PRUNE_BELOW) {
					stale.add (item.key);
					continue;
				}
				builder.set_member_name (item.key);
				builder.begin_object ();
				builder.set_member_name ("score");
				builder.add_double_value (score);
				builder.set_member_name ("stamp");
				builder.add_int_value (now_s);
				builder.end_object ();
			}
			foreach (var key in stale)
				entries.unset (key);

			builder.end_object ();
			builder.end_object ();

			var generator = new Json.Generator ();
			generator.set_root (builder.get_root ());
			var data = generator.to_data (null);

			try {
				// g_file_set_contents () writes to a temporary file and renames it: atomic
				FileUtils.set_contents (path, data);
				dirty = false;
			} catch (GLib.FileError e) {
				warning ("AppUsageService: unable to write '%s': %s", path, e.message);
			}
		}
	}
}
