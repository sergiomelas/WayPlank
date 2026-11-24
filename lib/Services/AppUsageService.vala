//
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
		/** Per-rank damping factor for folder damped-Euclidean app aggregation (bound <= 1.155 * s_max). */
		public const double FOLDER_DAMPING = 0.5;

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

		struct GlobalKeyBucket
		{
			public string key;
			public int64 bucket;
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
		Gee.HashMap<string, Gee.ArrayList<string>> folder_apps;
		GlobalKeyBucket[] global_key_vector = new GlobalKeyBucket[0];
		bool vector_dirty = true;
		int64 vector_built_s = 0;
		File? store_file = null;
		bool dirty = false;
		bool is_shut_down = false;
		int64 last_save_s = 0;
		string? focus_key = null;
		int64 focus_start_us = 0;

		construct
		{
			entries = new Gee.HashMap<string, UsageEntry> ();
			folder_apps = new Gee.HashMap<string, Gee.ArrayList<string>> ();
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
		 * Stable usage key of a launcher: the basename or stem of its launcher URI, so scores
		 * survive a launcher being moved or re-pinned.
		 */
		public static string key_for (string launcher)
		{
			if (launcher.has_prefix ("file://"))
				return File.new_for_uri (launcher).get_basename () ?? launcher;
			if (Path.is_absolute (launcher))
				return Path.get_basename (launcher);
			return launcher;
		}

		/**
		 * Collision-free usage key for a dock folder or file item ("folder:<path>").
		 */
		public static string folder_key_for (string launcher)
		{
			if (launcher == "")
				return "";
			if (launcher.has_prefix ("file://")) {
				string? p = File.new_for_uri (launcher).get_path ();
				return "folder:" + (p ?? launcher);
			}
			return "folder:" + launcher;
		}

		/**
		 * Typed usage key for any dock item: folder_key_for() for FileDockItem,
		 * key_for() for apps and docklets (100% pure Zone 1, zero I/O, zero HAL calls).
		 */
		public static string key_for_item (DockItem item)
		{
			if (item.Launcher == null || item.Launcher == "")
				return "";
			if (item is FileDockItem)
				return folder_key_for (item.Launcher);
			return key_for (item.Launcher);
		}

		/**
		 * Registers the app launchers contained inside a dock folder so its priority in the
		 * expanded global vector is computed as the damped Euclidean norm of its apps' scores.
		 */
		public void register_folder_apps (string folder_launcher, Gee.Collection<string> app_launchers)
		{
			if (folder_launcher == "")
				return;
			var fkey = folder_key_for (folder_launcher);
			var seen = new Gee.HashSet<string> ();
			var list = new Gee.ArrayList<string> ();
			foreach (var app_uri in app_launchers) {
				var akey = key_for (app_uri);
				if (akey != "" && seen.add (akey))
					list.add (akey);
			}
			folder_apps.set (fkey, list);
			vector_dirty = true;
		}

		public void unregister_folder_apps (string folder_launcher)
		{
			if (folder_launcher == "")
				return;
			if (folder_apps.unset (folder_key_for (folder_launcher)))
				vector_dirty = true;
		}

		static double decayed (UsageEntry entry, int64 now_s)
		{
			var dt = (double) (now_s - entry.stamp);
			if (dt <= 0.0)
				return entry.score;
			return entry.score * Math.pow (2.0, -dt / HALF_LIFE_SECONDS);
		}

		double compute_folder_aggregated_score (Gee.ArrayList<string> app_keys, int64 now_s)
		{
			if (app_keys.size == 0)
				return 0.0;
			var scores = new Gee.ArrayList<double?> ();
			foreach (var app_key in app_keys) {
				var e = entries.get (app_key);
				if (e == null)
					continue;
				double s = decayed (e, now_s);
				if (s > 0.0)
					scores.add (s);
			}
			if (scores.size == 0)
				return 0.0;
			scores.sort ((a, b) => (a < b) ? 1 : ((a > b) ? -1 : 0));

			double sum_sq = 0.0;
			double w = 1.0;
			foreach (var s in scores) {
				double ws = w * s;
				sum_sq += ws * ws;
				w *= FOLDER_DAMPING;
			}
			return double.min (SCORE_MAX, Math.sqrt (sum_sq));
		}

		double effective_score_for_key (string key, int64 now_s)
		{
			var entry = entries.get (key);
			double direct = (entry != null) ? decayed (entry, now_s) : 0.0;
			var fapps = folder_apps.get (key);
			if (fapps != null && fapps.size > 0) {
				double agg = compute_folder_aggregated_score (fapps, now_s);
				return double.min (SCORE_MAX, double.max (direct, agg));
			}
			return direct;
		}

		/**
		 * Current (lazily decayed) score of a launcher (or damped-Euclidean aggregated
		 * score for a registered folder). 0.0 for items never used.
		 */
		public double get_score (string launcher)
		{
			return effective_score_for_key (key_for (launcher), now_seconds ());
		}

		void ensure_global_vector (int64 now_s)
		{
			if (!vector_dirty && (now_s - vector_built_s) < 60 && (now_s >= vector_built_s))
				return;

			var combined = new Gee.HashMap<string, double?> ();
			foreach (var kv in entries.entries) {
				double s = decayed (kv.value, now_s);
				if (s > 0.0)
					combined.set (kv.key, s);
			}
			foreach (var fkv in folder_apps.entries) {
				double agg = compute_folder_aggregated_score (fkv.value, now_s);
				double direct = combined.has_key (fkv.key) ? combined.get (fkv.key) : 0.0;
				double eff = double.min (SCORE_MAX, double.max (direct, agg));
				if (eff > 0.0)
					combined.set (fkv.key, eff);
			}

			var sorted_keys = new Gee.ArrayList<string> ();
			sorted_keys.add_all (combined.keys);
			sorted_keys.sort ((a, b) => strcmp (a, b));

			global_key_vector = new GlobalKeyBucket[sorted_keys.size];
			for (int i = 0; i < sorted_keys.size; i++) {
				string k = sorted_keys.get (i);
				double sc = combined.get (k);
				int64 b = (int64) Math.round (sc / TIE_EPSILON);
				global_key_vector[i] = GlobalKeyBucket () { key = k, bucket = b };
			}
			vector_built_s = now_s;
			vector_dirty = false;
		}

		int64 lookup_rank_bucket_for_key (string target)
		{
			if (target == "" || entries.size == 0)
				return 0;
			ensure_global_vector (now_seconds ());
			int lo = 0;
			int hi = global_key_vector.length - 1;
			while (lo <= hi) {
				int mid = lo + ((hi - lo) >> 1);
				int cmp = strcmp (global_key_vector[mid].key, target);
				if (cmp == 0)
					return global_key_vector[mid].bucket;
				if (cmp < 0)
					lo = mid + 1;
				else
					hi = mid - 1;
			}
			return 0;
		}

		/**
		 * Global dichotomic (O(log N) binary-search) rank-bucket lookup across the single
		 * global usage statistics vector shared by all docks.
		 */
		public int64 get_global_rank_bucket (string launcher)
		{
			if (launcher == "")
				return 0;
			return lookup_rank_bucket_for_key (key_for (launcher));
		}

		public int64 get_global_rank_bucket_for_item (DockItem item)
		{
			return lookup_rank_bucket_for_key (key_for_item (item));
		}

		/**
		 * Registers an explicit launch/click of a launcher from the dock.
		 */
		public void note_launch (string launcher)
		{
			add_points (key_for (launcher), LAUNCH_POINTS);
		}

		public void note_item_launch (DockItem item)
		{
			add_points (key_for_item (item), LAUNCH_POINTS);
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
			vector_dirty = true;
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
		string describe_key (string key)
		{
			var now_s = now_seconds ();
			var fapps = folder_apps.get (key);
			if (fapps != null && fapps.size > 0) {
				var agg = compute_folder_aggregated_score (fapps, now_s);
				var entry = entries.get (key);
				var direct = (entry != null) ? decayed (entry, now_s) : 0.0;
				var eff = double.min (SCORE_MAX, double.max (direct, agg));
				return "%s: score %.2f (damped L2 over %d apps = %.2f, direct clicks = %.2f)".printf (
					key, eff, fapps.size, agg, direct
				);
			}
			var entry = entries.get (key);
			if (entry == null)
				return "%s: score 0.00 (never used)".printf (key);
			return "%s: score %.2f (raw %.2f)".printf (key, decayed (entry, now_s), entry.score);
		}

		public string describe (string launcher)
		{
			return describe_key (key_for (launcher));
		}

		public string describe_item (DockItem item)
		{
			return describe_key (key_for_item (item));
		}

		/**
		 * Multi-line ranking of the most used items (Developer Tools / debug log).
		 */
		public string describe_top (int limit = 15)
		{
			var now_s = now_seconds ();
			var combined = new Gee.HashMap<string, double?> ();
			foreach (var kv in entries.entries)
				combined.set (kv.key, decayed (kv.value, now_s));
			foreach (var fkv in folder_apps.entries) {
				double agg = compute_folder_aggregated_score (fkv.value, now_s);
				double direct = combined.has_key (fkv.key) ? combined.get (fkv.key) : 0.0;
				double eff = double.min (SCORE_MAX, double.max (direct, agg));
				if (eff > 0.0)
					combined.set (fkv.key, eff);
			}
			var keys = new Gee.ArrayList<string> ();
			keys.add_all (combined.keys);
			keys.sort ((a, b) => {
				var score_a = combined.get (a);
				var score_b = combined.get (b);
				return (score_a < score_b) ? 1 : ((score_a > score_b) ? -1 : 0);
			});

			var text = new StringBuilder ();
			int n = 0;
			foreach (var key in keys) {
				if (n++ >= limit)
					break;
				text.append ("  %2d. %s  %.2f\n".printf (n, key, combined.get (key)));
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
			vector_dirty = true;
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
