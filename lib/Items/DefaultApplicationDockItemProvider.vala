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
	public class DefaultApplicationDockItemProvider : ApplicationDockItemProvider
	{
		public DockPreferences Prefs { get; construct; }

		public DefaultApplicationDockItemProvider (DockPreferences prefs, File launchers_dir)
		{
			Object (Prefs : prefs, LaunchersDir : launchers_dir);
		}

		construct
		{
			Prefs.notify["CurrentWorkspaceOnly"].connect (handle_setting_changed);
			Prefs.notify["PinnedOnly"].connect (handle_pinned_only_changed);
		}

		~DefaultApplicationDockItemProvider ()
		{
			Prefs.notify["CurrentWorkspaceOnly"].disconnect (handle_setting_changed);
			Prefs.notify["PinnedOnly"].disconnect (handle_pinned_only_changed);
		}

		bool updating_visible_elements = false;

		protected override void update_visible_elements ()
		{
			foreach (var item in internal_elements) {
				item.IsAttached = !(Prefs.PinnedOnly && item is TransientDockItem);
			}
			
			if (!updating_visible_elements) {
				updating_visible_elements = true;
				maintain_separator ();
				updating_visible_elements = false;
			}

			base.update_visible_elements ();
		}
		
		/**
		 * Keeps a real SeparatorDockItem present exactly between the pinned and
		 * temporary items, so its layout/animation is handled by the normal
		 * per-item positioning instead of derived overlay coordinates.
		 */
		void maintain_separator ()
		{
			SeparatorDockItem? existing = null;
			int first_transient_idx = -1;
			int pinned_count = 0;
			int transient_count = 0;
			
			// If an internal drag is in progress, exclude the dragged item from
			// deciding where the separator should be anchored so it doesn't jump during drag.
			unowned DockController? dock = get_dock ();
			unowned DockItem? dragging_item = (dock != null && dock.drag_manager.InternalDragActive)
				? dock.drag_manager.DragItem : null;
			
			var all_separators = new Gee.ArrayList<SeparatorDockItem> ();
			for (int i = 0; i < internal_elements.size; i++) {
				var element = internal_elements.get (i);
				if (element is SeparatorDockItem) {
					all_separators.add ((SeparatorDockItem) element);
					continue;
				}
				if (element == dragging_item)
					continue;
				
				if (element is TransientDockItem) {
					transient_count++;
					if (first_transient_idx < 0)
						first_transient_idx = i;
				} else if (!(element is TransientDockItem)) {
					pinned_count++;
				}
			}
			
			// Clean up any extraneous separators if more than one ever slipped in
			if (all_separators.size > 1) {
				for (int i = 1; i < all_separators.size; i++) {
					var extra = all_separators.get (i);
					disconnect_element (extra);
					internal_elements.remove (extra);
					extra.Container = null;
				}
			}
			
			if (all_separators.size > 0)
				existing = all_separators.get (0);
			
			bool need_separator = (!Prefs.PinnedOnly && pinned_count > 0 && transient_count > 0);
			
			if (!need_separator) {
				if (existing != null) {
					disconnect_element (existing);
					internal_elements.remove (existing);
					existing.Container = null;
				}
				return;
			}
			
			if (existing != null) {
				int current_sep_idx = internal_elements.index_of (existing);
				if (current_sep_idx == first_transient_idx - 1)
					return;
				
				disconnect_element (existing);
				internal_elements.remove (existing);
				existing.Container = null;
			}
			
			int target_idx = -1;
			for (int i = 0; i < internal_elements.size; i++) {
				var el = internal_elements.get (i);
				if (el == dragging_item)
					continue;
				if (el is TransientDockItem) {
					target_idx = i;
					break;
				}
			}
			
			if (target_idx >= 0) {
				if (existing == null) {
					existing = new SeparatorDockItem ();
				}
				existing.AddTime = 0;
				existing.RemoveTime = 0;
				internal_elements.insert (target_idx, existing);
				existing.Container = this;
				connect_element (existing);
			}
		}

		public override void prepare ()
		{
			var favs = new Gee.ArrayList<string> ();

			foreach (var element in internal_elements) {
				unowned ApplicationDockItem? item = (element as ApplicationDockItem);
				if (item != null)
					favs.add (item.Launcher);
			}

			Matcher.get_default ().set_favorites (favs);
		}

		protected override void app_opened (string app_id)
		{
			if (WindowControl.has_state ())
				return;

			unowned ApplicationDockItem? found = item_for_application_id (app_id);
			if (found != null) {
				return;
			}

			// Find the corresponding .desktop file in the system to create the icon on the fly
			var desktop_file = desktop_file_for_application_id (app_id);
			if (desktop_file != null) {
				var new_item = new TransientDockItem.with_launcher (desktop_file.get_uri ());
				add (new_item);
			}
		}

		private File? desktop_file_for_application_id (string app_id)
		{
			foreach (var folder in Paths.DataDirFolders) {
				var applications_folder = folder.get_child ("applications");
				if (!applications_folder.query_exists ())
					continue;

				var desktop_file = applications_folder.get_child (app_id);
				if (desktop_file.query_exists ())
					return desktop_file;
			}
			return null;
		}

		void handle_setting_changed ()
		{
			update_visible_elements ();
		}

		void handle_pinned_only_changed ()
		{
			update_visible_elements ();
		}

		protected override void connect_element (DockElement element)
		{
			base.connect_element (element);

			unowned ApplicationDockItem? appitem = (element as ApplicationDockItem);
			if (appitem != null) {
				appitem.pin_launcher.connect (pin_item);
			}
		}

		protected override void disconnect_element (DockElement element)
		{
			base.disconnect_element (element);

			unowned ApplicationDockItem? appitem = (element as ApplicationDockItem);
			if (appitem != null) {
				appitem.pin_launcher.disconnect (pin_item);
			}
		}

		public void pin_item (DockItem item)
		{
			if (!internal_elements.contains (item))
				return;

			unowned ApplicationDockItem? app_item = (item as ApplicationDockItem);
			if (app_item == null)
				return;

			delay_items_monitor ();

			if (item is TransientDockItem) {
				var dockitem_file = Factory.item_factory.make_dock_item (item.Launcher, LaunchersDir);
				if (dockitem_file != null) {
					var new_item = new ApplicationDockItem.with_dockitem_file (dockitem_file);
					item.copy_values_to (new_item);
					replace (new_item, item);
				}
			} else {
				var launcher_uri = item.Launcher;
				var still_running = app_item.is_running ();
				item.delete ();
				
				// Re-add as a temporary item if the app is still running after unpinning
				if (still_running) {
					var new_item = new TransientDockItem.with_launcher (launcher_uri);
					add (new_item);
				}
			}

			resume_items_monitor ();
		}
	}
}
