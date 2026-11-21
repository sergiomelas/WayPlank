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
	 * Southbound `GLib.VolumeMonitor` / UDisks2 removable drive provider (`IEjectorProvider`).
	 */
	public class FreedesktopEjectorProvider : GLib.Object, IEjectorProvider
	{
		static FreedesktopEjectorProvider? default_instance = null;

		public static FreedesktopEjectorProvider get_default ()
		{
			if (default_instance == null)
				default_instance = new FreedesktopEjectorProvider ();
			return default_instance;
		}

		private GLib.VolumeMonitor? volume_monitor = null;
		private ulong sig_mount_added = 0UL;
		private ulong sig_mount_removed = 0UL;
		private ulong sig_mount_changed = 0UL;
		private ulong sig_volume_added = 0UL;
		private ulong sig_volume_removed = 0UL;
		private ulong sig_drive_connected = 0UL;
		private ulong sig_drive_disconnected = 0UL;

		construct
		{
			volume_monitor = GLib.VolumeMonitor.get ();
			if (volume_monitor != null) {
				sig_mount_added = volume_monitor.mount_added.connect (on_storage_changed);
				sig_mount_removed = volume_monitor.mount_removed.connect (on_storage_changed);
				sig_mount_changed = volume_monitor.mount_changed.connect (on_storage_changed);
				sig_volume_added = volume_monitor.volume_added.connect (on_storage_changed);
				sig_volume_removed = volume_monitor.volume_removed.connect (on_storage_changed);
				sig_drive_connected = volume_monitor.drive_connected.connect (on_storage_changed);
				sig_drive_disconnected = volume_monitor.drive_disconnected.connect (on_storage_changed);
			}
		}

		~FreedesktopEjectorProvider ()
		{
			cleanup ();
		}

		private void on_storage_changed ()
		{
			drives_changed ();
		}

		public void cleanup ()
		{
			if (volume_monitor != null) {
				if (sig_mount_added != 0UL) { volume_monitor.disconnect (sig_mount_added); sig_mount_added = 0UL; }
				if (sig_mount_removed != 0UL) { volume_monitor.disconnect (sig_mount_removed); sig_mount_removed = 0UL; }
				if (sig_mount_changed != 0UL) { volume_monitor.disconnect (sig_mount_changed); sig_mount_changed = 0UL; }
				if (sig_volume_added != 0UL) { volume_monitor.disconnect (sig_volume_added); sig_volume_added = 0UL; }
				if (sig_volume_removed != 0UL) { volume_monitor.disconnect (sig_volume_removed); sig_volume_removed = 0UL; }
				if (sig_drive_connected != 0UL) { volume_monitor.disconnect (sig_drive_connected); sig_drive_connected = 0UL; }
				if (sig_drive_disconnected != 0UL) { volume_monitor.disconnect (sig_drive_disconnected); sig_drive_disconnected = 0UL; }
				volume_monitor = null;
			}
		}

		static string compute_mount_id (GLib.Mount mount)
		{
			string? uuid = mount.get_uuid ();
			if (uuid != null && uuid != "")
				return "uuid:" + uuid;
			var root = mount.get_default_location ();
			if (root != null)
				return root.get_uri ();
			return "name:" + mount.get_name ();
		}

		GLib.List<GLib.Mount> collect_removable_mounts ()
		{
			var list = new GLib.List<GLib.Mount> ();
			if (volume_monitor == null)
				volume_monitor = GLib.VolumeMonitor.get ();
			if (volume_monitor == null)
				return list;

			foreach (var mount in volume_monitor.get_mounts ()) {
				var volume = mount.get_volume ();
				var drive = (volume != null) ? volume.get_drive () : mount.get_drive ();
				bool is_removable = false;

				if (drive != null && (drive.is_removable () || drive.is_media_removable () || drive.can_eject () || drive.can_stop ())) {
					is_removable = true;
				} else if (volume != null && volume.can_eject ()) {
					is_removable = true;
				} else if (mount.can_eject () || mount.can_unmount ()) {
					var root = mount.get_default_location ();
					string? path = (root != null) ? root.get_path () : null;
					if (path != null && (path.has_prefix ("/media") || path.has_prefix ("/run/media") || path.has_prefix ("/mnt"))) {
						is_removable = true;
					}
				}

				if (is_removable)
					list.append (mount);
			}

			return list;
		}

		public Gee.ArrayList<RemovableDriveInfo> get_removable_drives ()
		{
			var drives = new Gee.ArrayList<RemovableDriveInfo> ();
			foreach (var mount in collect_removable_mounts ()) {
				var info = new RemovableDriveInfo ();
				info.id = compute_mount_id (mount);
				info.display_name = mount.get_name ();
				info.icon_name = "media-eject";
				drives.add (info);
			}
			return drives;
		}

		void unmount_single (GLib.Mount mount, owned DriveEjectCallback? callback)
		{
			string name = mount.get_name ();
			var op = new GLib.MountOperation ();

			mount.unmount_with_operation.begin (GLib.MountUnmountFlags.NONE, op, null, (obj, res) => {
				try {
					mount.unmount_with_operation.end (res);
					if (callback != null)
						callback (true, name, "");
					drives_changed ();
				} catch (GLib.Error e) {
					warning ("Ejector: failed to unmount '%s': %s", name, e.message);
					if (callback != null)
						callback (false, name, e.message);
				}
			});
		}

		public void eject_drive (string id, owned DriveEjectCallback? callback = null)
		{
			foreach (var mount in collect_removable_mounts ()) {
				if (compute_mount_id (mount) == id) {
					unmount_single (mount, (owned) callback);
					return;
				}
			}
			if (callback != null)
				callback (false, id, _("Drive is no longer mounted"));
		}

		public void eject_all (owned DriveEjectCallback? per_drive_callback = null)
		{
			var mounts = collect_removable_mounts ();
			foreach (var m in mounts) {
				string name = m.get_name ();
				var op = new GLib.MountOperation ();
				m.unmount_with_operation.begin (GLib.MountUnmountFlags.NONE, op, null, (obj, res) => {
					try {
						m.unmount_with_operation.end (res);
						if (per_drive_callback != null)
							per_drive_callback (true, name, "");
						drives_changed ();
					} catch (GLib.Error e) {
						warning ("Ejector: failed to unmount '%s': %s", name, e.message);
						if (per_drive_callback != null)
							per_drive_callback (false, name, e.message);
					}
				});
			}
		}
	}
}
