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
	 * Native Windows live window thumbnail provider backed by off-thread
	 * `PrintWindow` (`PW_RENDERFULLCONTENT` with Win 7 `BitBlt` fallback)
	 * so GTK/Cairo UI rendering stays locked at 60 FPS with zero main-thread stalls.
	 */
	public class Win32ThumbnailProvider : GLib.Object, IThumbnailProvider
	{
		const int64 CACHE_TTL_USEC = 2500000;
		const int MAX_CONCURRENT_WORKERS = 4;

		class CallbackHolder
		{
			public ThumbnailReadyCallback cb;
			public CallbackHolder (owned ThumbnailReadyCallback c)
			{
				cb = (owned) c;
			}
		}

		Gee.HashMap<string, Gdk.Pixbuf> cache;
		Gee.HashMap<string, int64?> cache_time;
		Gee.HashMap<string, Gee.ArrayList<CallbackHolder>> pending;
		int active_workers = 0;
		bool is_cleaned_up = false;

		construct
		{
			cache = new Gee.HashMap<string, Gdk.Pixbuf> ();
			cache_time = new Gee.HashMap<string, int64?> ();
			pending = new Gee.HashMap<string, Gee.ArrayList<CallbackHolder>> ();
		}

		public Gdk.Pixbuf? get_cached (string win_id)
		{
			return cache.has_key (win_id) ? cache.get (win_id) : null;
		}

		public bool is_stale (string win_id)
		{
			if (!cache.has_key (win_id) || !cache_time.has_key (win_id))
				return true;
			int64 ts = cache_time.get (win_id) ?? 0;
			return (GLib.get_monotonic_time () - ts) > CACHE_TTL_USEC;
		}

		public void request_thumbnail (string win_id, int target_w, int target_h, owned ThumbnailReadyCallback cb)
		{
			if (is_cleaned_up) {
				cb (null);
				return;
			}

			uint64 hwnd;
			if (!Win32Backend.parse_hwnd (win_id, out hwnd)) {
				cb (null);
				return;
			}

			if (pending.has_key (win_id)) {
				pending.get (win_id).add (new CallbackHolder ((owned) cb));
				return;
			}

			if (active_workers >= MAX_CONCURRENT_WORKERS) {
				cb (get_cached (win_id));
				return;
			}

			var waiters = new Gee.ArrayList<CallbackHolder> ();
			waiters.add (new CallbackHolder ((owned) cb));
			pending.set (win_id, waiters);
			active_workers++;

			int req_w = (target_w > 0) ? target_w : 240;
			int req_h = (target_h > 0) ? target_h : 150;
			string id_copy = win_id;

			new GLib.Thread<void*> ("win32-thumb", () => {
				uint8* rgba_ptr = null;
				int out_w = 0;
				int out_h = 0;
				int ok = Win32Bridge.capture_window_rgba (hwnd, req_w, req_h, out rgba_ptr, out out_w, out out_h);

				GLib.Idle.add (() => {
					if (active_workers > 0)
						active_workers--;

					if (is_cleaned_up) {
						if (rgba_ptr != null)
							Win32Bridge.free_buffer (rgba_ptr);
						return Source.REMOVE;
					}

					Gdk.Pixbuf? result = null;
					if (ok != 0 && rgba_ptr != null && out_w > 0 && out_h > 0) {
						int rowstride = out_w * 4;
						int total_bytes = rowstride * out_h;
						uint8[] pixels = new uint8[total_bytes];
						Memory.copy (pixels, rgba_ptr, total_bytes);
						Win32Bridge.free_buffer (rgba_ptr);

						result = new Gdk.Pixbuf.from_data (
							(owned) pixels,
							Gdk.Colorspace.RGB,
							true,
							8,
							out_w,
							out_h,
							rowstride
						);
						if (cache.size > 64) {
							cache.clear ();
							cache_time.clear ();
						}
						cache.set (id_copy, result);
						cache_time.set (id_copy, GLib.get_monotonic_time ());
					} else {
						if (rgba_ptr != null)
							Win32Bridge.free_buffer (rgba_ptr);
						result = get_cached (id_copy);
					}

					var list = pending.get (id_copy);
					pending.unset (id_copy);
					if (list != null) {
						foreach (var h in list)
							h.cb (result);
					}
					return Source.REMOVE;
				});
				return null;
			});
		}

		public void evict (string win_id)
		{
			cache.unset (win_id);
			cache_time.unset (win_id);
		}

		public void cleanup ()
		{
			is_cleaned_up = true;
			cache.clear ();
			cache_time.clear ();
			pending.clear ();
		}
	}
}
