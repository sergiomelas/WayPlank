//
//  Copyright (C) 2011-2012 Robert Dyer, Michal Hruby, Rico Tzschichholz
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
			ApplicationDiscovery.get_default ().changed.disconnect (sync_compositor_windows);

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

		static File? desktop_file_for_application_uri (string app_uri)
		{
			foreach (var folder in Paths.DataDirFolders) {
				var applications_folder = folder.get_child ("applications");
				if (!applications_folder.query_exists ())
					continue;

				var desktop_file = applications_folder.get_child (app_uri.replace ("application://", ""));
				if (!desktop_file.query_exists ())
					continue;

				return desktop_file;
			}
			return null;
		}

		public override bool add_item_with_uri (string uri, DockItem? target = null)
		{
			if (uri == null || uri == "")
				return false;

			if (target != null && target != placeholder_item && !internal_elements.contains (target))
				return false;

			if (item_exists_for_uri (uri))
				return false;

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

		public override void prepare ()
		{
			sync_compositor_windows ();
			foreach (var app_id in Matcher.get_default ().active_launchers ()) {
				unowned ApplicationDockItem? found = item_for_application_id (app_id);
				if (found == null) {
					// If the app is active but not pinned, add it as a transient item
					var desktop_file = desktop_file_for_application_uri ("application://" + app_id);
					if (desktop_file != null) {
						var new_item = new TransientDockItem.with_launcher (desktop_file.get_uri ());
						add (new_item);
					}
				}
			}
		}

		void sync_compositor_windows ()
		{
			var active_ids = ApplicationDiscovery.get_default ().active_launcher_ids ();
			if (active_ids.length == 0)
				return;
			var active = new Gee.HashSet<string> ();
			foreach (var app_id in active_ids)
				active.add (ApplicationIdentity.normalize (app_id));

			foreach (var app_id in active) {
				if (item_for_application_id (app_id) != null)
					continue;
				var desktop_file = ApplicationDiscovery.get_default ().desktop_file_for_id (app_id);
				if (desktop_file != null)
					add (new TransientDockItem.with_launcher (desktop_file.get_uri ())); 
			}

			foreach (var element in internal_elements.to_array ()) {
				unowned TransientDockItem? transient = (element as TransientDockItem);
				if (transient == null)
					continue;
				var launcher_id = ApplicationIdentity.normalize (File.new_for_uri (transient.Launcher).get_basename ());
				if (!active.contains (launcher_id))
					remove (transient);
			}
		}

		public override string[] get_dockitem_filenames ()
		{
			var item_list = new Gee.ArrayList<string> ();

			foreach (var element in internal_elements) {
				unowned DockItem? item = (element as DockItem);
				if (item == null || (item is TransientDockItem))
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
			unowned ApplicationDockItem? found = item_for_application_id (app_id);
			if (found != null) {
				// Gestione apertura app
			}
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

		protected void delay_items_monitor ()
		{
			delay_items_monitor_handle = true;
		}

		protected void resume_items_monitor ()
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

				add (item);
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

		protected override void connect_element (DockElement element)
		{
			base.connect_element (element);
		}

		protected override void disconnect_element (DockElement element)
		{
			base.disconnect_element (element);
		}

		public void remove_launcher_entry (string sender_name) {}
		public void update_launcher_entry (string sender_name, Variant parameters, bool is_retry = false) {}
	}
}

