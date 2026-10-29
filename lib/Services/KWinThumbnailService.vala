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

		Gee.HashMap<string, Gdk.Pixbuf> cache;
		Gee.HashSet<string> pending;

		construct
		{
			cache = new Gee.HashMap<string, Gdk.Pixbuf> ();
			pending = new Gee.HashSet<string> ();
		}

		public Gdk.Pixbuf? get_cached (string win_id)
		{
			return cache.has_key (win_id) ? cache.get (win_id) : null;
		}

		public void request_thumbnail (string win_id, int target_w, int target_h, owned ThumbnailReadyCallback cb)
		{
			stderr.printf ("[KWinThumbnailService] request_thumbnail for win_id='%s' (%dx%d)\n", win_id, target_w, target_h);
			if (cache.has_key (win_id)) {
				stderr.printf ("[KWinThumbnailService] Cache HIT for '%s'\n", win_id);
				cb (cache.get (win_id));
				return;
			}

			if (pending.contains (win_id)) {
				stderr.printf ("[KWinThumbnailService] Pending request for '%s' already in flight\n", win_id);
				return;
			}

			pending.add (win_id);

			new Thread<void*> ("wayplank-thumb-" + win_id, () => {
				Gdk.Pixbuf? pix = capture_window_raw (win_id, target_w, target_h);

				Idle.add (() => {
					pending.remove (win_id);
					if (pix != null) {
						stderr.printf ("[KWinThumbnailService] SUCCESS: Got thumbnail for '%s'\n", win_id);
						cache.set (win_id, pix);
						cb (pix);
					} else {
						stderr.printf ("[KWinThumbnailService] FAILED: capture_window_raw returned null for '%s'\n", win_id);
						cb (null);
					}
					return false;
				});

				return null;
			});
		}

		static Gdk.Pixbuf? capture_window_raw (string win_id, int target_w, int target_h)
		{
			if (WindowControl.is_mutter ()) {
				return capture_window_mutter (win_id, target_w, target_h);
			} else {
				return capture_window_kwin (win_id, target_w, target_h);
			}
		}

		static Gdk.Pixbuf? capture_window_mutter (string win_id, int target_w, int target_h)
		{
			string tmp_path = "/dev/shm/wayplank_thumb_%s.png".printf (win_id);
			try {
				bool ok = MutterBackend.get_default ().capture_window (win_id, tmp_path);
				if (!ok || !FileUtils.test (tmp_path, FileTest.EXISTS))
					return null;

				var pix = new Gdk.Pixbuf.from_file_at_scale (tmp_path, target_w, target_h, false);
				FileUtils.unlink (tmp_path);
				return pix;
			} catch (Error e) {
				if (FileUtils.test (tmp_path, FileTest.EXISTS))
					FileUtils.unlink (tmp_path);
				stderr.printf ("[KWinThumbnailService] Mutter capture error: %s\n", e.message);
				return null;
			}
		}

		static Gdk.Pixbuf? capture_window_kwin (string win_id, int target_w, int target_h)
		{
			try {
				int pipefd[2];
				if (Posix.pipe (pipefd) != 0) {
					stderr.printf ("[KWinThumbnailService] pipe() failed: %s\n", Posix.strerror (Posix.errno));
					return null;
				}

				var fd_list = new UnixFDList ();
				int fd_idx = fd_list.append (pipefd[1]);
				Posix.close (pipefd[1]);

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
					stderr.printf ("[KWinThumbnailService] D-Bus reply is NULL for win_id='%s'\n", win_id);
					Posix.close (pipefd[0]);
					return null;
				}
				if (reply.get_message_type () == DBusMessageType.ERROR) {
					stderr.printf ("[KWinThumbnailService] D-Bus ERROR for win_id='%s': %s (%s)\n",
						win_id, reply.get_error_name (), reply.get_arg0 ());
					Posix.close (pipefd[0]);
					return null;
				}

				var body = reply.get_body ();
				Variant map = body.get_child_value (0);

				uint32 width = 0, height = 0, stride = 0;
				map.lookup ("width", "u", out width);
				map.lookup ("height", "u", out height);
				map.lookup ("stride", "u", out stride);

				stderr.printf ("[KWinThumbnailService] D-Bus reply map: width=%u height=%u stride=%u\n",
					width, height, stride);

				if (width == 0 || height == 0 || stride == 0) {
					Posix.close (pipefd[0]);
					return null;
				}

				size_t total_bytes = (size_t) height * stride;
				uint8[] buffer = new uint8[total_bytes];
				size_t read_bytes = 0;
				while (read_bytes < total_bytes) {
					ssize_t n = Posix.read (pipefd[0], (uint8*) buffer + read_bytes, total_bytes - read_bytes);
					if (n <= 0) break;
					read_bytes += n;
				}
				Posix.close (pipefd[0]);

				stderr.printf ("[KWinThumbnailService] Read %zu / %zu bytes\n", read_bytes, total_bytes);

				if (read_bytes < total_bytes)
					return null;

				// KWin format 6 is BGRA. Swap B and R for standard RGBA Pixbuf
				// and guarantee full opacity (alpha = 255) for crisp rendering
				for (size_t i = 0; i < total_bytes; i += 4) {
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
					stderr.printf ("[KWinThumbnailService] Gdk.Pixbuf.from_data returned null\n");
					return null;
				}

				return raw_pixbuf.scale_simple (target_w, target_h, Gdk.InterpType.BILINEAR);
			} catch (Error e) {
				stderr.printf ("[KWinThumbnailService] Exception: %s\n", e.message);
				return null;
			}
		}
	}
}

