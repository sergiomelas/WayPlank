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
	public delegate void ThumbnailReadyCallback (Gdk.Pixbuf? pixbuf);

	/**
	 * OS- and transport-blind asynchronous live window thumbnail capture contract.
	 */
	public interface IThumbnailProvider : GLib.Object
	{
		public abstract Gdk.Pixbuf? get_cached (string win_id);
		public abstract bool is_stale (string win_id);
		public abstract void request_thumbnail (string win_id, int target_w, int target_h, owned ThumbnailReadyCallback cb);
		public abstract void evict (string win_id);
		public virtual void cleanup () {}
	}

	/**
	 * Safe fallback thumbnail provider when live window capture is unavailable.
	 */
	public class NullThumbnailProvider : GLib.Object, IThumbnailProvider
	{
		public Gdk.Pixbuf? get_cached (string win_id)
		{
			return null;
		}

		public bool is_stale (string win_id)
		{
			return false;
		}

		public void request_thumbnail (string win_id, int target_w, int target_h, owned ThumbnailReadyCallback cb)
		{
			cb (null);
		}

		public void evict (string win_id)
		{
		}
	}
}
