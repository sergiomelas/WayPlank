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
	public class ApplicationDockItemProvider : DockItemProvider, UnityClient
	{
		public File LaunchersDir { get; construct; }

		FileMonitor? items_monitor = null;
		bool delay_items_monitor_handle = false;
		Gee.ArrayList<GLib.File> queued_files;

		public ApplicationDockItemProvider (File launchers_dir)
		{
			Object (LaunchersDir : launchers_dir);
		}

		construct
		{
			queued_files = new Gee.ArrayList<GLib.File> ();
			Paths.ensure_directory_exists (LaunchersDir);

			Matcher.get_default ().application_opened.connect (app_opened);
			Matcher.get_default ().application_closed.connect (app_closed);
			ApplicationDiscovery.get_default ().changed.connect (sync_compositor_windows);
			WindowManager.get_default ().windows_refreshed.connect (sync_compositor_windows);

			try {
				items_monitor = LaunchersDir.monitor_directory (0);
				items_monitor.changed.connect (handle_items_dir_changed);
			} catch (Error e) {
				critical ("Unable to watch the launchers directory. (%s)", e.message);
			}
		}

		~ApplicationDockItemProvider ()
		{
			queued_files = null;
			Matcher.get_default ().application_opened.disconnect (app_opened);
			Matcher.get_default ().application_closed.disconnect (app_closed);
			ApplicationDiscovery.get_default ().changed.disconnect (sync_compositor_windows);
			WindowManager.get_default ().windows_refreshed.disconnect (sync_compositor_windows);

			if (items_monitor != null) {
				items_monitor.changed.disconnect (handle_items_dir_changed);
				items_monitor.cancel ();
				items_monitor = null;
			}
		}

		protected unowned ApplicationDockItem? item_for_application_id (string app_id)
		{
			foreach (var item in internal_elements) {
				unowned ApplicationDockItem? appitem = (item as ApplicationDockItem);
				if (appitem == null)
					continue;

				unowned string launcher = appitem.Launcher;
				// Check for both exact match and binary name matching within the launcher path
				if (launcher != "" && (launcher.contains (app_id) || launcher.down ().contains (app_id.replace (".desktop", "").down ())))
					return appitem;
			}

			return null;
		}


		unowned DockItem? find_default_target_for_item (string uri)
		{
			bool is_docklet = uri.has_prefix ("docklet://");
			if (is_docklet) {
				// DEFENSIVE GUARD: When adding a docklet, always position it at the far right
				// (the end) of the docklets category, never to the left.
				// This preserves the user's primary/default docklet (e.g. Preferences or Clock)
				// as the first item on the left, keeping it always-visible at rest in Accordion mode.
				bool in_docklets = false;
				foreach (var el in internal_elements) {
					if (DefaultApplicationDockItemProvider.is_docklet_element (el)) {
						in_docklets = true;
					} else if (in_docklets) {
						return el as DockItem;
					}
				}

				if (in_docklets)
					return null;

				// No existing docklet; place before pinned apps if any, or before transient/trash
				foreach (var el in internal_elements) {
					if (el is ApplicationDockItem && !(el is TransientDockItem)) {
						return el as DockItem;
					}
				}
			}

			foreach (var el in internal_elements) {
				if (el is SeparatorDockItem || el is PinnedExpanderDockItem || el is TransientDockItem) {
					return el as DockItem;
				}
			}

			return null;
		}

		public override bool add_item_with_uri (string uri, DockItem? target = null)
		{
			if (uri == null || uri == "")
				return false;

			if (target != null && target != placeholder_item && !internal_elements.contains (target))
				target = null;

			if (target == null) {
				target = find_default_target_for_item (uri);
			}

			unowned DockItem? existing = item_for_uri (uri);
			if (existing != null) {
				if (existing is TransientDockItem) {
					unowned DefaultApplicationDockItemProvider? default_provider = this as DefaultApplicationDockItemProvider;
					if (default_provider != null) {
						default_provider.pin_item (existing);
						unowned DockItem? pinned = item_for_uri (uri);
						if (target != null && pinned != null && target != pinned && internal_elements.contains (target))
							move_to (pinned, target);
						return true;
					}
				}
				return false;
			}

			delay_items_monitor ();

			var dockitem_file = Factory.item_factory.make_dock_item (uri, LaunchersDir);
			if (dockitem_file == null) {
				resume_items_monitor ();
				return false;
			}

			var element = Factory.item_factory.make_element (dockitem_file);
			unowned DockItem? item = (element as DockItem);
			if (item == null) {
				resume_items_monitor ();
				return false;
			}

			add (item, target);
			resume_items_monitor ();
			return true;
		}

		bool window_has_pinned_item (WindowInfo window)
		{
			var discovery = ApplicationDiscovery.get_default ();
			unowned DockController? dock = get_dock ();
			if (dock != null && dock.drag_manager.RemovalActive && dock.drag_manager.PendingRemovalLauncher.length > 0) {
				if (discovery.is_best_launcher_for_window (dock.drag_manager.PendingRemovalLauncher, window))
					return true;
			}

			foreach (var element in internal_elements) {
				unowned ApplicationDockItem? appitem = (element as ApplicationDockItem);
				if (appitem == null || (appitem is TransientDockItem))
					continue;

				if (discovery.is_best_launcher_for_window (appitem.Launcher, window))
					return true;
			}
			return false;
		}

		public override void prepare ()
		{
			sync_compositor_windows ();
		}

		protected virtual bool is_pinned_only ()
		{
			return false;
		}

		public void sync_compositor_windows ()
		{
			var windows = WindowControl.get_windows ();
			var discovery = ApplicationDiscovery.get_default ();
			var my_pid = Posix.getpid ();
			var active_transient_launchers = new Gee.HashSet<string> ();

			foreach (var window in windows) {
				// Ignore windows belonging to Wayplank itself
				if (window.Pid > 0 && window.Pid == my_pid)
					continue;

				var app_id = window.ApplicationId.down ();
				var res_class = window.ResourceClass.down ();
				var res_name = window.ResourceName.down ();
				var desk_name = window.DesktopFileName.down ();
				var caption = window.Caption.down ();
				if (app_id == "wayplank" || app_id == "plank" ||
				    res_class == "wayplank" || res_class == "plank" ||
				    res_name == "wayplank" || res_name == "plank" ||
				    desk_name == "wayplank.desktop" || desk_name == "plank.desktop" || desk_name == "wayplank" || desk_name == "plank" ||
				    caption == "wayplank" || caption == "wayplank-hover" || caption == "wayplank-poof" ||
				    caption == "wayplank-folder-menu" || caption == "wayplank-hover-cards")
					continue;

				// Wait for pending cold-start browser profile resolution (120ms) before spawning a transient dock item
				if (ApplicationIdentity.is_plain_browser_window (window) &&
				    !ApplicationIdentity.has_explicit_webapp_window_id (window) &&
				    ApplicationIdentity.is_window_profile_pending (window) &&
				    ApplicationIdentity.get_window_browser_profile (window) == "")
					continue;

				// If a window is already handled by a pinned dock item, don't create a transient item
				if (window_has_pinned_item (window))
					continue;

				var desktop_file = discovery.best_desktop_file_for_window (window);
				if (desktop_file == null)
					continue;

				// Never add Wayplank or Plank as a transient dock item
				var base_name = desktop_file.get_basename ().down ();
				if (base_name == "wayplank.desktop" || base_name == "plank.desktop")
					continue;

				var uri = desktop_file.get_uri ();
				active_transient_launchers.add (uri);

				bool already_exists = false;
				foreach (var element in internal_elements) {
					unowned ApplicationDockItem? appitem = (element as ApplicationDockItem);
					if (appitem != null && appitem.Launcher == uri) {
						already_exists = true;
						break;
					}
				}

				if (!already_exists && !is_pinned_only ()) {
					DockElement? trash_target = null;
					foreach (var element in internal_elements) {
						if (element is TrashDockItem) {
							trash_target = element;
							break;
						}
					}
					add (new TransientDockItem.with_launcher (uri), trash_target);
				}
			}

			var seen_transient_launchers = new Gee.HashSet<string> ();
			foreach (var element in internal_elements.to_array ()) {
				unowned TransientDockItem? transient = (element as TransientDockItem);
				if (transient == null)
					continue;

				if (is_pinned_only () || !active_transient_launchers.contains (transient.Launcher) || seen_transient_launchers.contains (transient.Launcher))
					remove (transient);
				else
					seen_transient_launchers.add (transient.Launcher);
			}
		}

		public override string[] get_dockitem_filenames ()
		{
			var item_list = new Gee.ArrayList<string> ();

			foreach (var element in internal_elements) {
				unowned DockItem? item = (element as DockItem);
				if (item == null || (item is TransientDockItem) || (item is SeparatorDockItem) || (item is PinnedExpanderDockItem))
					continue;

				var dock_item_filename = item.DockItemFilename;
				if (dock_item_filename.length > 0) {
					item_list.add ((owned) dock_item_filename);
				}
			}

			return item_list.to_array ();
		}

		protected virtual void app_opened (string app_id)
		{
		}

		protected virtual void app_closed (string app_id)
		{
			foreach (var element in internal_elements) {
				unowned TransientDockItem? transient = (element as TransientDockItem);
				if (transient != null && transient.Launcher.contains (app_id)) {
					remove (transient);
					break;
				}
			}
		}

		public void delay_items_monitor ()
		{
			delay_items_monitor_handle = true;
		}

		public void resume_items_monitor ()
		{
			delay_items_monitor_handle = false;
			process_queued_files ();
		}

		void process_queued_files ()
		{
			foreach (var file in queued_files) {
				var basename = file.get_basename ();
				bool skip = false;
				foreach (var element in internal_elements) {
					unowned DockItem? item = (element as DockItem);
					if (item != null && basename == item.DockItemFilename) {
						skip = true;
						break;
					}
				}

				if (skip)
					continue;

				var element = Factory.item_factory.make_element (file);
				unowned DockItem? item = (element as DockItem);
				if (item == null)
					continue;
				DockItem? target = null;
				if (item != null && item.Prefs != null && item.Prefs.Launcher != null) {
					target = find_default_target_for_item (item.Prefs.Launcher);
				} else {
					foreach (var el in internal_elements) {
						if (el is SeparatorDockItem || el is PinnedExpanderDockItem || el is TransientDockItem) {
							target = el as DockItem;
							break;
						}
					}
				}

				add (item, target);
			}
			queued_files.clear ();
		}

		[CCode (instance_pos = -1)]
		void handle_items_dir_changed (File f, File? other, FileMonitorEvent event)
		{
			if (event != FileMonitorEvent.CREATED)
				return;

			if (!file_is_dockitem (f))
				return;

			foreach (var element in internal_elements) {
				unowned DockItem? item = (element as DockItem);
				if (item != null && f.get_basename () == item.DockItemFilename)
					return;
			}

			queued_files.add (f);
			if (!delay_items_monitor_handle)
				process_queued_files ();
		}

		// Unity.Client interface stubs
		public void remove_launcher_entry (string sender_name) {}
		public void update_launcher_entry (string sender_name, Variant parameters, bool is_retry = false) {}
	}
}

