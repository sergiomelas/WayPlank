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
	public delegate void ThumbnailReadyCallback (Gdk.Pixbuf? pixbuf);

	public class KWinThumbnailService : GLib.Object
	{
		static KWinThumbnailService? instance = null;

		public static KWinThumbnailService get_default ()
		{
			if (instance == null)
				instance = new KWinThumbnailService ();
			return instance;
		}

		const int64 CACHE_TTL_USEC = 2500000;

		private class CallbackHolder
		{
			public ThumbnailReadyCallback cb;
			public CallbackHolder (owned ThumbnailReadyCallback c)
			{
				cb = (owned) c;
			}
		}

		Gee.HashMap<string, Gdk.Pixbuf> cache;
		Gee.HashMap<string, int64?> cache_time;
		Gee.HashMap<string, Gee.ArrayList<CallbackHolder>> pending_callbacks;

		construct
		{
			cache = new Gee.HashMap<string, Gdk.Pixbuf> ();
			cache_time = new Gee.HashMap<string, int64?> ();
			pending_callbacks = new Gee.HashMap<string, Gee.ArrayList<CallbackHolder>> ();
		}

		void prune_closed_windows ()
		{
			var windows = WindowControl.get_windows ();
			if (windows.size == 0)
				return;
			var live = new Gee.HashSet<string> ();
			foreach (var w in windows) {
				if (w.Id != null && w.Id != "")
					live.add (w.Id);
			}
			var stale = new Gee.ArrayList<string> ();
			foreach (var k in cache.keys) {
				if (k != "active" && !live.contains (k))
					stale.add (k);
			}
			foreach (var k in stale) {
				cache.unset (k);
				cache_time.unset (k);
			}
		}

		static int thumb_seq = 0;

		public Gdk.Pixbuf? get_cached (string win_id)
		{
			return cache.has_key (win_id) ? cache.get (win_id) : null;
		}

		public bool is_stale (string win_id)
		{
			if (!cache.has_key (win_id) || !cache_time.has_key (win_id))
				return true;
			int64? ts = cache_time.get (win_id);
			return ts == null || (GLib.get_monotonic_time () - ts) >= CACHE_TTL_USEC;
		}

		public void request_thumbnail (string win_id, int target_w, int target_h, owned ThumbnailReadyCallback cb)
		{
			if (!WindowControl.is_kwin () && !WindowControl.is_mutter ()) {
				cb (null);
				return;
			}

			prune_closed_windows ();
			debug ("[KWinThumbnailService] request_thumbnail for win_id='%s' (%dx%d)", win_id, target_w, target_h);
			if (cache.has_key (win_id)) {
				int64? ts = cache_time.get (win_id);
				if (ts != null && (GLib.get_monotonic_time () - ts) < CACHE_TTL_USEC) {
					debug ("[KWinThumbnailService] Cache HIT for '%s'", win_id);
					cb (cache.get (win_id));
					return;
				}
			}

			if (pending_callbacks.has_key (win_id)) {
				debug ("[KWinThumbnailService] Coalescing callback onto in-flight request for '%s'", win_id);
				pending_callbacks.get (win_id).add (new CallbackHolder ((owned) cb));
				return;
			}

			var waiters = new Gee.ArrayList<CallbackHolder> ();
			waiters.add (new CallbackHolder ((owned) cb));
			pending_callbacks.set (win_id, waiters);

			spawn_capture_worker (this, win_id, target_w, target_h);
		}

		private static void spawn_capture_worker (KWinThumbnailService svc, string win_id, int target_w, int target_h)
		{
			GLib.WeakRef svc_ref = GLib.WeakRef (svc);
			bool use_mutter = WindowControl.is_mutter ();
			bool use_kwin = WindowControl.is_kwin ();

			new Thread<void*> ("wayplank-thumb-" + win_id, () => {
				Gdk.Pixbuf? pix = null;
				if (use_mutter)
					pix = capture_window_mutter (win_id, target_w, target_h);
				else if (use_kwin)
					pix = capture_window_kwin (win_id, target_w, target_h);

				Idle.add (() => {
					var self = (KWinThumbnailService?) svc_ref.get ();
					if (self == null)
						return false;
					var list = self.pending_callbacks.get (win_id);
					self.pending_callbacks.unset (win_id);
					if (pix != null) {
						debug ("[KWinThumbnailService] SUCCESS: Got thumbnail for '%s'", win_id);
						self.cache.set (win_id, pix);
						self.cache_time.set (win_id, GLib.get_monotonic_time ());
					} else {
						debug ("[KWinThumbnailService] FAILED: capture returned null for '%s'", win_id);
					}
					if (list != null) {
						foreach (var holder in list)
							holder.cb (pix);
					}
					return false;
				});

				return null;
			});
		}

		static Gdk.Pixbuf? capture_window_mutter (string win_id, int target_w, int target_h)
		{
			int seq = GLib.AtomicInt.add (ref thumb_seq, 1);
			string runtime_dir = Environment.get_user_runtime_dir ();
			if (runtime_dir == null || runtime_dir == "" || !FileUtils.test (runtime_dir, FileTest.IS_DIR))
				runtime_dir = "/tmp";
			string safe_id = win_id.replace ("/", "_").replace ("..", "_");
			string tmp_path = Path.build_filename (runtime_dir, "wayplank_thumb_%d_%d_%s.png".printf ((int) Posix.getpid (), seq, safe_id));
			try {
				var conn = Bus.get_sync (BusType.SESSION, null);
				var reply = conn.call_sync (
					"org.wayplank.GnomeBridge",
					"/org/wayplank/GnomeBridge",
					"org.wayplank.GnomeBridge",
					"CaptureWindow",
					new Variant ("(ss)", win_id, tmp_path),
					new VariantType ("(b)"),
					DBusCallFlags.NO_AUTO_START,
					2500,
					null
				);
				bool ok = false;
				reply.get ("(b)", out ok);
				if (!ok || !FileUtils.test (tmp_path, FileTest.EXISTS))
					return null;

				return new Gdk.Pixbuf.from_file_at_scale (tmp_path, target_w, target_h, true);
			} catch (Error e) {
				debug ("[KWinThumbnailService] Mutter capture error: %s", e.message);
				return null;
			} finally {
				if (FileUtils.test (tmp_path, FileTest.EXISTS))
					FileUtils.unlink (tmp_path);
			}
		}

		static Gdk.Pixbuf? capture_window_kwin (string win_id, int target_w, int target_h)
		{
			int read_fd = -1;
			int write_fd = -1;
			try {
				int pipefd[2];
				if (Posix.pipe (pipefd) != 0) {
					debug ("[KWinThumbnailService] pipe() failed: %s", Posix.strerror (Posix.errno));
					return null;
				}
				read_fd = pipefd[0];
				write_fd = pipefd[1];

				var fd_list = new UnixFDList ();
				int fd_idx = fd_list.append (write_fd);
				Posix.close (write_fd);
				write_fd = -1;

				var conn = Bus.get_sync (BusType.SESSION);
				var builder = new VariantBuilder (new VariantType ("a{sv}"));

				string method = "CaptureWindow";
				Variant @params;
				if (win_id == "active") {
					method = "CaptureActiveWindow";
					@params = new Variant ("(@a{sv}h)", builder.end (), fd_idx);
				} else {
					@params = new Variant ("(s@a{sv}h)", win_id, builder.end (), fd_idx);
				}

				var msg = new DBusMessage.method_call (
					"org.kde.KWin",
					"/org/kde/KWin/ScreenShot2",
					"org.kde.KWin.ScreenShot2",
					method
				);
				msg.set_body (@params);
				msg.set_unix_fd_list (fd_list);

				var reply = conn.send_message_with_reply_sync (msg, DBusSendMessageFlags.NONE, 2500, null);
				if (reply == null) {
					debug ("[KWinThumbnailService] D-Bus reply is NULL for win_id='%s'", win_id);
					return null;
				}
				if (reply.get_message_type () == DBusMessageType.ERROR) {
					debug ("[KWinThumbnailService] D-Bus ERROR for win_id='%s': %s (%s)",
						win_id, reply.get_error_name (), reply.get_arg0 ());
					return null;
				}

				var body = reply.get_body ();
				Variant map = body.get_child_value (0);

				uint32 width = 0, height = 0, stride = 0;
				map.lookup ("width", "u", out width);
				map.lookup ("height", "u", out height);
				map.lookup ("stride", "u", out stride);

				debug ("[KWinThumbnailService] D-Bus reply map: width=%u height=%u stride=%u",
					width, height, stride);

				if (width == 0 || height == 0 || width > 16384 || height > 16384 || stride < width * 4 || stride > 65536)
					return null;

				size_t total_bytes = (size_t) height * stride;
				uint8[] buffer = new uint8[total_bytes];
				size_t read_bytes = 0;
				while (read_bytes < total_bytes) {
					ssize_t n = Posix.read (read_fd, (uint8*) buffer + read_bytes, total_bytes - read_bytes);
					if (n < 0) {
						if (Posix.errno == Posix.EINTR)
							continue;
						break;
					}
					if (n == 0)
						break;
					read_bytes += (size_t) n;
				}
				Posix.close (read_fd);
				read_fd = -1;

				debug ("[KWinThumbnailService] Read %zu / %zu bytes", read_bytes, total_bytes);

				if (read_bytes < total_bytes)
					return null;

				// KWin format 6 is BGRA. Swap B and R for standard RGBA Pixbuf
				// and guarantee full opacity (alpha = 255) for crisp rendering
				for (size_t i = 0; i + 3 < total_bytes; i += 4) {
					uint8 b = buffer[i];
					buffer[i] = buffer[i + 2];
					buffer[i + 2] = b;
					buffer[i + 3] = 255;
				}

				var raw_pixbuf = new Gdk.Pixbuf.from_data (
					buffer,
					Gdk.Colorspace.RGB,
					true,
					8,
					(int) width,
					(int) height,
					(int) stride,
					null
				);

				if (raw_pixbuf == null) {
					debug ("[KWinThumbnailService] Gdk.Pixbuf.from_data returned null");
					return null;
				}

				double scale = double.min ((double) target_w / width, (double) target_h / height);
				int scaled_w = int.max (1, (int) Math.round (width * scale));
				int scaled_h = int.max (1, (int) Math.round (height * scale));
				return raw_pixbuf.scale_simple (scaled_w, scaled_h, Gdk.InterpType.BILINEAR);
			} catch (Error e) {
				debug ("[KWinThumbnailService] Exception: %s", e.message);
				return null;
			} finally {
				if (write_fd >= 0)
					Posix.close (write_fd);
				if (read_fd >= 0)
					Posix.close (read_fd);
			}
		}
	}
}

