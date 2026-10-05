//
//  Copyright (C) 2026 Sergio Melas
//
//  This file is part of Wayplank.
//
//  Wayplank is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Wayplank is distributed in the hope that it will be useful,
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
	 * HAL Service for synchronizing Trash operations with KWin-based compositors
	 * and the KDE Plasma desktop shell via D-Bus (org.kde.KDirNotify) and KIO protocols.
	 */
	public class KWinTrashBridge : GLib.Object
	{
		static KWinTrashBridge? default_instance = null;
		uint signal_sub_id = 0U;

		public signal void trash_state_changed_externally ();

		public static KWinTrashBridge get_default ()
		{
			if (default_instance == null) {
				default_instance = new KWinTrashBridge ();
			}
			return default_instance;
		}

		construct
		{
			initialize_listener ();
		}

		~KWinTrashBridge ()
		{
			if (signal_sub_id > 0U) {
				var bus = get_session_bus ();
				if (bus != null)
					bus.signal_unsubscribe (signal_sub_id);
				signal_sub_id = 0U;
			}
		}

		static DBusConnection? get_session_bus ()
		{
			try {
				return Bus.get_sync (BusType.SESSION, null);
			} catch (Error e) {
				return null;
			}
		}

		public static bool is_kwin_or_kde ()
		{
			if (environment_is_session_desktop (XdgSessionDesktop.KDE))
				return true;
			
			unowned string? desktop = Environment.get_variable ("XDG_CURRENT_DESKTOP");
			if (desktop != null && (desktop.down ().contains ("kde") || desktop.down ().contains ("plasma")))
				return true;
			
			return WindowControl.is_kwin ();
		}

		void initialize_listener ()
		{
			if (signal_sub_id > 0U)
				return;

			var bus = get_session_bus ();
			if (bus == null)
				return;

			// Subscribe to org.kde.KDirNotify signals to synchronize in real-time when KDE changes trash
			signal_sub_id = bus.signal_subscribe (
				null, // any sender (KIO, Dolphin, Plasma)
				"org.kde.KDirNotify", // interface
				null, // any member (FilesAdded, FilesRemoved, FilesChanged)
				null, // any path
				null, // arg0
				DBusSignalFlags.NONE,
				(conn, sender, path, iface, member, parameters) => {
					string param_str = parameters.print (true);
					if ("trash:" in param_str || "Trash" in param_str) {
						trash_state_changed_externally ();
					}
				}
			);
		}

		public static void notify_items_added (string? specific_uri = null)
		{
			var bus = get_session_bus ();
			if (bus == null)
				return;

			// 1. Broadcast org.kde.KDirNotify.FilesAdded(directory: "trash:/")
			try {
				bus.emit_signal (null, "/", "org.kde.KDirNotify", "FilesAdded", new Variant ("(s)", "trash:/"));
				bus.emit_signal (null, "/org/kde/KDirNotify", "org.kde.KDirNotify", "FilesAdded", new Variant ("(s)", "trash:/"));
			} catch (Error e) {
				debug ("KDirNotify FilesAdded emit failed: %s", e.message);
			}

			// 2. Broadcast org.kde.KDirNotify.FilesChanged(["trash:/", "trash:///"])
			try {
				var builder = new VariantBuilder (new VariantType ("as"));
				builder.add ("s", "trash:/");
				builder.add ("s", "trash:///");
				if (specific_uri != null)
					builder.add ("s", specific_uri);
				var v = new Variant ("(as)", builder);
				bus.emit_signal (null, "/", "org.kde.KDirNotify", "FilesChanged", v);
				bus.emit_signal (null, "/org/kde/KDirNotify", "org.kde.KDirNotify", "FilesChanged", v);
			} catch (Error e) {
				debug ("KDirNotify FilesChanged emit failed: %s", e.message);
			}
		}

		public static void notify_items_removed ()
		{
			var bus = get_session_bus ();
			if (bus == null)
				return;

			// 1. Broadcast org.kde.KDirNotify.FilesRemoved(["trash:/", "trash:///"])
			try {
				var builder = new VariantBuilder (new VariantType ("as"));
				builder.add ("s", "trash:/");
				builder.add ("s", "trash:///");
				var v = new Variant ("(as)", builder);
				bus.emit_signal (null, "/", "org.kde.KDirNotify", "FilesRemoved", v);
				bus.emit_signal (null, "/org/kde/KDirNotify", "org.kde.KDirNotify", "FilesRemoved", v);
			} catch (Error e) {
				debug ("KDirNotify FilesRemoved emit failed: %s", e.message);
			}

			// 2. Broadcast org.kde.KDirNotify.FilesChanged(["trash:/", "trash:///"])
			try {
				var builder = new VariantBuilder (new VariantType ("as"));
				builder.add ("s", "trash:/");
				builder.add ("s", "trash:///");
				var v = new Variant ("(as)", builder);
				bus.emit_signal (null, "/", "org.kde.KDirNotify", "FilesChanged", v);
				bus.emit_signal (null, "/org/kde/KDirNotify", "org.kde.KDirNotify", "FilesChanged", v);
			} catch (Error e) {
				debug ("KDirNotify FilesChanged emit failed: %s", e.message);
			}
		}

		public static bool move_to_trash (string uri_or_path)
		{
			string target = uri_or_path;
			if (target.has_prefix ("file://")) {
				var f = File.new_for_uri (target);
				var p = f.get_path ();
				if (p != null)
					target = p;
			}

			string quoted = Shell.quote (target);
			int exit_status;

			// 1. Try kioclient
			try {
				if (Process.spawn_command_line_sync ("kioclient move " + quoted + " trash:/", null, null, out exit_status) && exit_status == 0) {
					notify_items_added (uri_or_path);
					return true;
				}
			} catch (Error e) {
			}

			// 2. Try kioclient5
			try {
				if (Process.spawn_command_line_sync ("kioclient5 move " + quoted + " trash:/", null, null, out exit_status) && exit_status == 0) {
					notify_items_added (uri_or_path);
					return true;
				}
			} catch (Error e) {
			}

			return false;
		}

		public static bool empty_trash ()
		{
			// Try running gio trash --empty if available
			int exit_status;
			try {
				if (Process.spawn_command_line_sync ("gio trash --empty", null, null, out exit_status) && exit_status == 0) {
					notify_items_removed ();
					return true;
				}
			} catch (Error e) {
			}

			return false;
		}
	}
}

