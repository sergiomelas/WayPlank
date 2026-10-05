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

		public void refresh_separators ()
		{
			update_visible_elements ();
		}
		
		/**
		 * Keeps a real SeparatorDockItem present exactly between the pinned and
		 * temporary items, so its layout/animation is handled by the normal
		 * per-item positioning instead of derived overlay coordinates.
		/**
		 * Maintains clean grouping and dynamic separators:
		 * - Pinned items (apps, folders, docklets) are grouped on the left.
		 * - Transient (running unpinned) items are grouped in the middle.
		 * - TrashDockItem is permanently anchored at the far right.
		 * - Dynamic separators:
		 *     * With Trash:
		 *         - If transient items exist: 2 separators [Pinned] | [Transient] | [Trash]
		 *         - If no transient items:    1 separator  [Pinned] | [Trash]
		 *     * Without Trash:
		 *         - If transient items exist: 1 separator  [Pinned] | [Transient]
		 *         - If no transient items:    0 separators [Pinned]
		 */
		void maintain_separator ()
		{
			unowned DockController? dock = get_dock ();
			unowned DockItem? dragging_item = (dock != null && dock.drag_manager.InternalDragActive)
				? dock.drag_manager.DragItem : null;

			// Step 1: Collect existing separators and identify Trash item
			var existing_separators = new Gee.ArrayList<SeparatorDockItem> ();
			TrashDockItem? trash_item = null;

			for (int i = 0; i < internal_elements.size; i++) {
				var el = internal_elements.get (i);
				if (el is SeparatorDockItem) {
					existing_separators.add ((SeparatorDockItem) el);
				} else if (el is TrashDockItem) {
					trash_item = (TrashDockItem) el;
				}
			}

			// Step 2: Remove existing separators temporarily so we work on clean item slots
			foreach (var sep in existing_separators) {
				disconnect_element (sep);
				internal_elements.remove (sep);
				sep.Container = null;
			}

			// Step 3: Anchor Trash permanently at the very end of internal_elements
			if (trash_item != null && dragging_item == null) {
				int trash_idx = internal_elements.index_of (trash_item);
				if (trash_idx >= 0 && trash_idx != internal_elements.size - 1) {
					move_element (internal_elements, trash_idx, internal_elements.size - 1);
				}
			}

			// Step 4: Ensure all pinned items precede transient items
			if (dragging_item == null) {
				int first_transient = -1;
				for (int i = 0; i < internal_elements.size; i++) {
					var el = internal_elements.get (i);
					if (el is TransientDockItem) {
						if (first_transient < 0)
							first_transient = i;
					} else if (first_transient >= 0 && !(el is TrashDockItem)) {
						move_element (internal_elements, i, first_transient);
						first_transient++;
					}
				}
			}

			// Step 5: Count items
			int pinned_count = 0;
			int transient_count = 0;
			int first_transient_idx = -1;
			int trash_idx = -1;

			for (int i = 0; i < internal_elements.size; i++) {
				var el = internal_elements.get (i);
				if (el is TrashDockItem) {
					trash_idx = i;
				} else if (el is TransientDockItem) {
					if (!Prefs.PinnedOnly) {
						transient_count++;
						if (first_transient_idx < 0)
							first_transient_idx = i;
					}
				} else {
					pinned_count++;
				}
			}

			// Step 6: Determine separator insertion positions
			// Insert from highest index to lowest so earlier target indices remain valid
			var insert_positions = new Gee.ArrayList<int> ();

			if (trash_item != null) {
				if (transient_count > 0 && pinned_count > 0) {
					// 2 separators: [Pinned] | [Transient] | [Trash]
					insert_positions.add (trash_idx);
					insert_positions.add (first_transient_idx);
				} else if (transient_count > 0 && pinned_count == 0) {
					// 1 separator: [Transient] | [Trash]
					insert_positions.add (trash_idx);
				} else if (pinned_count > 0) {
					// 1 separator: [Pinned] | [Trash]
					insert_positions.add (trash_idx);
				}
			} else {
				if (transient_count > 0 && pinned_count > 0) {
					// 1 separator: [Pinned] | [Transient]
					insert_positions.add (first_transient_idx);
				}
			}

			// Step 7: Insert separators at target positions (reusing pool or instantiating new)
			int sep_pool_idx = 0;
			foreach (int pos in insert_positions) {
				if (pos < 0 || pos > internal_elements.size)
					continue;
				SeparatorDockItem sep;
				if (sep_pool_idx < existing_separators.size) {
					sep = existing_separators.get (sep_pool_idx++);
				} else {
					sep = new SeparatorDockItem ();
				}
				sep.AddTime = 0;
				sep.RemoveTime = 0;
				internal_elements.insert (pos, sep);
				sep.Container = this;
				connect_element (sep);
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
