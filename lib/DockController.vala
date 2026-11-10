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
	public const string G_RESOURCE_PATH = "/net/launchpad/plank";
	
	/**
	 * A controller class for managing a single dock.
	 *
	 * All needed controlling parts will be created and initialized.
	 */
	public class DockController : DockContainer
	{
		public string name { get; construct; }
		public File config_folder { get; construct; }
		public File launchers_folder { get; private set; }
		
		public DockPreferences prefs { get; construct; }
		
		public DragManager drag_manager { get; protected set; }
		public HideManager hide_manager { get; protected set; }
		public PositionManager position_manager { get; protected set; }
		public DockRenderer renderer { get; protected set; }
		public DockWindow window { get; protected set; }
		public HoverWindow hover { get; protected set; }
		public FolderMenuWindow folder_menu { get; protected set; }
		public WindowCardsWindow window_cards { get; protected set; }
		public string last_explicit_monitor { get; set; default = ""; }
		
		public DockItemProvider? default_provider { get; private set; }
		public unowned DefaultApplicationDockItemProvider? app_provider {
			get { return default_provider as DefaultApplicationDockItemProvider; }
		}
		
		DBusManager dbus_manager;
		Gee.ArrayList<unowned DockItem> visible_items;
		Gee.ArrayList<unowned DockItem> items;
		DockItem? dock_itself_item;
		uint serialize_item_positions_timer_id = 0U;
		bool is_initialized = false;

		public bool is_first_run_launch { get; private set; default = false; }
		public bool migrated_from_legacy_plank { get; private set; default = false; }
		
		/**
		 * List of all items on this dock
		 */
		public Gee.ArrayList<unowned DockItem> Items {
			get {
				return items;
			}
		}
		
		/**
		 * Ordered list of all visible items on this dock
		 */
		public Gee.ArrayList<unowned DockItem> VisibleItems {
			get {
				return visible_items;
			}
		}
		
		/**
		 * Create a new DockController which manages a single dock
		 *
		 * @param config_folder the base-folder to load settings from and save them to
		 */
		public DockController (string dock_name, File config_folder)
		{
			// Make sure our config-directory exists
			Paths.ensure_directory_exists (config_folder);
			
			debug ("Create dock '%s' (config_folder = %s)", dock_name, config_folder.get_path ());
			
			Object (name : dock_name, config_folder : config_folder, prefs : new DockPreferences (dock_name));
		}
		
		construct
		{
			launchers_folder = config_folder.get_child ("launchers");
			Factory.item_factory.launchers_dir = launchers_folder;
			
			items = new Gee.ArrayList<unowned DockItem> ();
			visible_items = new Gee.ArrayList<unowned DockItem> ();
			
			prefs.notify["Position"].connect (update_visible_elements);
			prefs.notify["ShowDockItem"].connect (update_show_dock_item);
			if (prefs.Monitor != "")
				last_explicit_monitor = prefs.Monitor;
			prefs.notify["Monitor"].connect (update_explicit_monitor);
			
			dbus_manager = new DBusManager (this);
			
			position_manager = new PositionManager (this);
			drag_manager = new DragManager (this);
			hide_manager = new HideManager (this);
			window = new DockWindow (this);
			hover = new HoverWindow ();
			folder_menu = new FolderMenuWindow (this);
			window_cards = new WindowCardsWindow (this);
			renderer = new DockRenderer (this, window);
		}
		
		void update_explicit_monitor ()
		{
			if (prefs.Monitor != "")
				last_explicit_monitor = prefs.Monitor;
		}

		~DockController ()
		{
			folder_menu.destroy ();
			window_cards.destroy ();
			prefs.notify["Monitor"].disconnect (update_explicit_monitor);
			prefs.notify["Position"].disconnect (update_visible_elements);
			prefs.notify["ShowDockItem"].disconnect (update_show_dock_item);
			
			if (is_initialized) {
				positions_changed.disconnect (handle_positions_changed);
				states_changed.disconnect (handle_states_changed);
				elements_changed.disconnect (handle_elements_changed);
			}
			
			if (serialize_item_positions_timer_id > 0U) {
				Source.remove (serialize_item_positions_timer_id);
				serialize_item_positions_timer_id = 0U;
			}
			serialize_item_positions ();

			items.clear ();
			visible_items.clear ();

			if (hover != null)
				hover.destroy ();
			if (window != null)
				window.destroy ();
		}
		
		/**
		 * Initialize this controller.
		 * Call this when added at least one DockItemProvider otherwise the
		 * {@link Plank.DefaultApplicationDockItemProvider} will be added by default.
		 */
		public void initialize ()
		{
			if (internal_elements.size <= 0)
				add_default_provider ();
			
			update_show_dock_item ();
			update_items ();
			
			AddTime = GLib.get_monotonic_time ();
			
			positions_changed.connect (handle_positions_changed);
			states_changed.connect (handle_states_changed);
			elements_changed.connect (handle_elements_changed);
			is_initialized = true;
			
			position_manager.initialize ();
			drag_manager.initialize ();
			hide_manager.initialize ();
			renderer.initialize ();
			hide_manager.refresh_visibility ();

			// Update the calculated dimensions and map the window on Wayland
			position_manager.update (renderer.theme);
			window.update_size_and_position ();
			window.show_all ();
			if (GtkLayerShell.is_supported ())
				window.present ();
			window.queue_draw ();

			// Geometry and theme are known now: let the Smart Pinned Accordion decide
			if (app_provider != null)
				app_provider.refresh_pinned_accordion ();
		}
		
		/**
		 * Add the default provider which is an instance of
		 * {@link Plank.DefaultApplicationDockItemProvider}
		 */
		public void add_default_provider ()
		{
			if (default_provider != null)
				return;
			
			Logger.verbose ("DockController.add_default_provider ()");
			default_provider = create_default_provider ();
			
			string[] target_items = prefs.DockItems;
			if (prefs.CategorizeItems && prefs.CategorizedDockItems != null && prefs.CategorizedDockItems.length > 0) {
				target_items = prefs.CategorizedDockItems;
			} else if (!prefs.CategorizeItems && prefs.FreeDockItems != null && prefs.FreeDockItems.length > 0) {
				target_items = prefs.FreeDockItems;
			}
			if (target_items.length == 0 && prefs.DockItems != null && prefs.DockItems.length > 0) {
				target_items = prefs.DockItems;
			}
			var elements = Factory.item_factory.load_elements (launchers_folder, target_items);
			if (Factory.item_factory.corrupted_dockitems.size > 0)
				prefs.report_corrupted_dockitems (Factory.item_factory.corrupted_dockitems);

			foreach (var element in elements)
				if (element is DockItem)
					default_provider.add (element);

			unowned DefaultApplicationDockItemProvider? def_prov = default_provider as DefaultApplicationDockItemProvider;
			if (def_prov != null) {
				def_prov.deduplicate_items ();
				def_prov.ensure_preferences_dockitem ();
				def_prov.deduplicate_items ();
				if (prefs.FreeDockItems == null || prefs.FreeDockItems.length == 0) {
					def_prov.reorder_free_items_by_category ();
				}
			}

			bool has_default_provider = false;
			foreach (var element in elements) {
				if (!has_default_provider && element is DockItem) {
					add (default_provider);
					has_default_provider = true;
				} else if (element is DockItemProvider) {
					add (element);
				}
			}
			if (!has_default_provider)
				add (default_provider);

			schedule_serialize_item_positions ();
		}
		
		static void ensure_default_autostart ()
		{
			var autostart_dir = Path.build_filename (Environment.get_user_config_dir (), "autostart");
			var autostart_path = Path.build_filename (autostart_dir, "wayplank.desktop");
			if (DirUtils.create_with_parents (autostart_dir, 0755) == 0) {
				try {
					FileUtils.set_contents (autostart_path,
						"[Desktop Entry]\n" +
						"Type=Application\n" +
						"Name=WayPlank\n" +
						"Comment=Stupidly simple dock for Wayland\n" +
						"Exec=wayplank\n" +
						"Icon=plank\n" +
						"Terminal=false\n" +
						"X-GNOME-Autostart-enabled=true\n" +
						"X-GNOME-Autostart-Delay=2\n" +
						"X-KDE-DBUS-Restricted-Interfaces=org.kde.kwin.Screenshot,org.kde.KWin.ScreenShot2\n");
					WindowControl.sync_autostart (true);
				} catch (FileError e) {
					warning ("Unable to create default autostart entry '%s': %s", autostart_path, e.message);
				}
			}
		}

		void apply_common_first_run_defaults ()
		{
			prefs.Theme = "Arian Theme Light";
			prefs.Position = Gtk.PositionType.BOTTOM;
			prefs.Monitor = "";
			prefs.Alignment = Gtk.Align.CENTER;
			prefs.ItemsAlignment = Gtk.Align.CENTER;
			prefs.Offset = 0;
			prefs.IconSize = 48;
			prefs.ScrollOverflow = false;
			prefs.TooltipsEnabled = true;
			prefs.HideMode = HideType.INTELLIGENT;
			prefs.HideDelay = 0U;
			prefs.UnhideDelay = 0U;
			prefs.PressureReveal = false;
			prefs.ReserveSpace = false;
			prefs.ZoomEnabled = true;
			prefs.ZoomPercent = 150U;
			prefs.AnticipateZoom = true;
			prefs.LockItems = false;
			prefs.LaunchAnimation = 0;
			prefs.ActiveHighlight = 0;
			prefs.UnpinAnimation = 0;
			prefs.EffectDuration = 600;
			prefs.WindowClickBehavior = 0;
			prefs.ShowWindowCards = true;
			prefs.RestoreMinimizedWindows = true;
			prefs.PinnedOnly = false;
			prefs.CurrentWorkspaceOnly = false;
			prefs.ShowRunningIndicators = true;
			prefs.ShowAttentionIndicators = true;
			prefs.DockletsOnRight = true;
			prefs.AccordionClickToExpand = true;
			prefs.PinnedAccordionCount = 6;
		}

		DockItemProvider create_default_provider ()
		{
			DockItemProvider provider;
			
			// If we made the default-launcher-directory or it is empty,
			// assume a first run and pre-populate with launchers
			bool is_first_run = Paths.ensure_directory_exists (launchers_folder);
			if (!is_first_run) {
				try {
					var enumerator = launchers_folder.enumerate_children (FileAttribute.STANDARD_NAME, 0);
					if (enumerator.next_file (null) == null)
						is_first_run = true;
				} catch { }
			}
			
			if (is_first_run) {
				if (Path.get_basename (Environment.get_prgname () ?? "wayplank") != "plank") {
					try {
						Process.spawn_command_line_sync ("killall -q plank");
					} catch { }
				}
				var onboarding_marker = config_folder.get_child ("onboarding-done");
				var legacy_launchers = Paths.ConfigHomeFolder.get_child ("plank").get_child (name).get_child ("launchers");
				bool headless = (Environment.get_variable ("WAYPLANK_NO_PROMPT") == "1"
					|| Environment.get_variable ("CI") == "1"
					|| Environment.get_variable ("NONINTERACTIVE") == "1");

				ensure_default_autostart ();

				if (Factory.item_factory.migrate_legacy_plank_items (legacy_launchers, launchers_folder)) {
					debug ("First run: migrated compatible launchers and folders from legacy ~/.config/plank/%s/launchers (read-only)...", name);
					migrated_from_legacy_plank = true;
					if (!prefs.has_profile_settings_on_disk ()) {
						prefs.reset_all ();
						prefs.DockItems = {};
						prefs.FreeDockItems = {};
						prefs.CategorizedDockItems = {};
						apply_common_first_run_defaults ();
					}
					prefs.CategorizeItems = false;
					prefs.AccordionDocklets = false;
					prefs.PinnedAccordionMode = DockPreferences.PINNED_ACCORDION_OFF;
					prefs.SystemMenuAccess = 3;
					prefs.AnchorAlwaysLeft = false;
					prefs.ShowDockItem = false;
					is_first_run_launch = !headless && !onboarding_marker.query_exists ();
				} else if (headless) {
					debug ("First run (headless): wiping residual settings and initializing modern Explorer defaults...");
					if (!prefs.has_profile_settings_on_disk ()) {
						prefs.reset_all ();
						prefs.DockItems = {};
						prefs.FreeDockItems = {};
						prefs.CategorizedDockItems = {};
						apply_common_first_run_defaults ();
						prefs.AccordionDocklets = true;
						prefs.PinnedAccordionMode = DockPreferences.PINNED_ACCORDION_TOP_N;
						prefs.SystemMenuAccess = 4;
						prefs.AnchorAlwaysLeft = true;
						prefs.ShowDockItem = false;
						prefs.CategorizeItems = true;
					}
					Factory.item_factory.make_default_items ();
					try {
						FileUtils.set_contents (onboarding_marker.get_path (), "explorer\n");
					} catch { }
				} else {
					debug ("First run: wiping residual settings, initializing classic baseline and scheduling onboarding choice...");
					if (!prefs.has_profile_settings_on_disk ()) {
						prefs.reset_all ();
						prefs.DockItems = {};
						prefs.FreeDockItems = {};
						prefs.CategorizedDockItems = {};
						apply_common_first_run_defaults ();
						prefs.AccordionDocklets = false;
						prefs.PinnedAccordionMode = DockPreferences.PINNED_ACCORDION_OFF;
						prefs.SystemMenuAccess = 3;
						prefs.AnchorAlwaysLeft = false;
						prefs.ShowDockItem = false;
						prefs.CategorizeItems = false;
					}
					Factory.item_factory.make_classic_items ();
					is_first_run_launch = !onboarding_marker.query_exists ();
				}
				prefs.flush_to_disk ();
				debug ("done.");
			} else if (!prefs.has_profile_settings_on_disk ()) {
				prefs.flush_to_disk ();
			}
			
			provider = new DefaultApplicationDockItemProvider (prefs, launchers_folder);
			
			return provider;
		}

		/**
		 * Applies the user's selected first-run onboarding profile (Classic vs Explorer)
		 * non-destructively without ever deleting existing user launchers or folders.
		 */
		public void apply_onboarding_profile (bool explorer_mode)
		{
			is_first_run_launch = false;
			ensure_default_autostart ();
			var onboarding_marker = config_folder.get_child ("onboarding-done");
			try {
				FileUtils.set_contents (onboarding_marker.get_path (), explorer_mode ? "explorer\n" : "classic\n");
			} catch { }

			unowned DefaultApplicationDockItemProvider? def_prov = default_provider as DefaultApplicationDockItemProvider;
			Factory.item_factory.launchers_dir = launchers_folder;

			if (!explorer_mode) {
				// WayPlank Classic: preserve 100% of existing/migrated launchers and folders (no left WayPlank icon, no forced Trash)
				prefs.delay ();
				if (!migrated_from_legacy_plank) {
					prefs.DockItems = {};
					prefs.FreeDockItems = {};
					prefs.CategorizedDockItems = {};
				}
				apply_common_first_run_defaults ();
				prefs.AccordionDocklets = false;
				prefs.PinnedAccordionMode = DockPreferences.PINNED_ACCORDION_OFF;
				prefs.SystemMenuAccess = 3;
				prefs.AnchorAlwaysLeft = false;
				prefs.ShowDockItem = false;
				prefs.CategorizeItems = false;
				prefs.apply ();
			} else {
				// WayPlank Explorer: keep all existing/migrated items and add modern folders + docklets
				if (def_prov != null)
					def_prov.delay_items_monitor ();
				if (migrated_from_legacy_plank)
					Factory.item_factory.make_default_docklets ();
				else
					Factory.item_factory.make_default_items ();
				if (default_provider != null) {
					var missing = Factory.item_factory.load_missing_items (launchers_folder, default_provider);
					foreach (var item in missing)
						default_provider.add (item);
				}
				if (def_prov != null)
					def_prov.resume_items_monitor ();
				prefs.delay ();
				if (!migrated_from_legacy_plank) {
					prefs.DockItems = {};
					prefs.FreeDockItems = {};
					prefs.CategorizedDockItems = {};
				}
				apply_common_first_run_defaults ();
				prefs.DockletsOnRight = true;
				prefs.AccordionDocklets = true;
				prefs.AccordionClickToExpand = true;
				prefs.PinnedAccordionMode = DockPreferences.PINNED_ACCORDION_TOP_N;
				prefs.PinnedAccordionCount = 6;
				prefs.ShowWindowCards = true;
				prefs.SystemMenuAccess = 4;
				prefs.AnchorAlwaysLeft = true;
				prefs.ShowDockItem = false;
				prefs.CategorizeItems = true;
				prefs.apply ();
			}

			if (def_prov != null) {
				def_prov.deduplicate_items ();
				def_prov.ensure_preferences_dockitem ();
				def_prov.deduplicate_items ();
				def_prov.refresh_separators ();
				def_prov.refresh_pinned_accordion ();
			}

			prefs.flush_to_disk ();
			if (hide_manager != null)
				hide_manager.refresh_visibility ();
			update_items ();
			position_manager.update (renderer.theme);
			window.update_size_and_position ();
			window.queue_draw ();
			renderer.animated_draw ();
			schedule_serialize_item_positions ();
		}
		
		void update_show_dock_item ()
		{
			if (prefs.ShowDockItem) {
				if (dock_itself_item == null)
					dock_itself_item = Factory.item_factory.get_item_for_dock ();
				if (!internal_elements.contains (dock_itself_item))
					prepend (dock_itself_item);
			} else if (dock_itself_item != null) {
				if (internal_elements.contains (dock_itself_item))
					remove (dock_itself_item);
				dock_itself_item = null;
			}
		}
		
		protected override void connect_element (DockElement element)
		{
			unowned DockItemProvider? provider = (element as DockItemProvider);
			if (provider == null)
				return;
			
			provider.positions_changed.connect (handle_positions_changed);
			provider.states_changed.connect (handle_states_changed);
			provider.elements_changed.connect (handle_elements_changed);
			
			unowned ApplicationDockItemProvider? app_provider = (provider as ApplicationDockItemProvider);
			if (app_provider != null) {
				Unity.get_default ().add_client (app_provider);
			}
		}
		
		protected override void disconnect_element (DockElement element)
		{
			unowned DockItemProvider? provider = (element as DockItemProvider);
			if (provider == null)
				return;
			
			provider.positions_changed.disconnect (handle_positions_changed);
			provider.states_changed.disconnect (handle_states_changed);
			provider.elements_changed.disconnect (handle_elements_changed);
			
			unowned ApplicationDockItemProvider? app_provider = (provider as ApplicationDockItemProvider);
			if (app_provider != null) {
				Unity.get_default ().remove_client (app_provider);
			}
		}
		
		protected override void update_visible_elements ()
		{
			base.update_visible_elements ();
			
			Logger.verbose ("DockController.update_visible_items ()");
			
			visible_items.clear ();
			
			var current_position = 0;
			update_visible_items_recursive (this, ref current_position);
		}
		
		void update_visible_items_recursive (DockContainer container, ref int current_position)
		{
			var iterator = container.VisibleElements.bidir_list_iterator ();
			
			// Reverse dock-item-order for RTL environments if dock is placed horizontally
			if (Gtk.Widget.get_default_direction () == Gtk.TextDirection.RTL && prefs.is_horizontal_dock ()) {
				iterator.last ();
				do {
					update_visible_items_add_from_iterator (iterator, ref current_position);
				} while (iterator.previous ());
			} else {
				iterator.first ();
				do {
					update_visible_items_add_from_iterator (iterator, ref current_position);
				} while (iterator.next ());
			}
		}
		
		inline void update_visible_items_add_from_iterator (Gee.Iterator<DockElement> iterator, ref int current_position)
		{
			DockElement? element = iterator.get ();
			unowned DockItem? item = null;
			unowned DockContainer? container = null;
			
			container = (element as DockContainer);
			if (container != null) {
				update_visible_items_recursive (container, ref current_position);
				return;
			}

			item = (element as DockItem);
			if (item == null)
				return;
			
			if (item.Position != current_position)
				item.Position = current_position;
			current_position++;
			
			visible_items.add (item);
		}
		
		public void update_items ()
		{
			Logger.verbose ("DockController.update_items ()");
			
			items.clear ();
			
			unowned DockItem? item = null;
			unowned DockContainer? container = null;
			int struct_pos = 0;
			
			foreach (var element in internal_elements) {
				item = (element as DockItem);
				if (item != null) {
					item.StructuralPosition = struct_pos++;
					items.add (item);
					continue;
				}
				
				container = (element as DockContainer);
				if (container == null)
					continue;
				
				foreach (var element2 in container.Elements) {
					item = (element2 as DockItem);
					if (item == null)
						continue;
					item.StructuralPosition = struct_pos++;
					items.add (item);
				}
			}
		}
		
		void handle_elements_changed (DockContainer container, Gee.List<DockElement> added, Gee.List<DockElement> removed)
		{
			update_visible_elements ();
			update_items ();

			if (window.HoveredItem != null && !visible_items.contains (window.HoveredItem))
				window.update_hovered (-1, -1);

			// Schedule added/removed items for special animations after visible_items is synchronized
			renderer.animate_items (added);
			renderer.animate_items (removed);
			
			if (added.size > 0 || removed.size > 0) {
				foreach (unowned DockItem it in visible_items)
					it.unset_move_state ();
				position_manager.update (renderer.theme);
			}
			
			window.update_icon_regions ();
			
			schedule_serialize_item_positions ();

			// FIXME Maybe add a dedicated signal
			if (container != this) {
				var empty = new Gee.ArrayList<DockElement> ();
				elements_changed (empty, empty);
			}
		}
		
		void handle_positions_changed (DockContainer container, Gee.List<unowned DockElement> moved_items)
		{
			update_visible_elements ();
			update_items ();
			
			foreach (unowned DockElement item in moved_items) {
				unowned ApplicationDockItem? app_item = (item as ApplicationDockItem);
				if (app_item != null)
					window.update_icon_region (app_item);
			}
			renderer.animated_draw ();

			schedule_serialize_item_positions ();
		}
		
		void handle_states_changed (DockContainer container)
		{
			renderer.animated_draw ();
		}

		public void refresh_visible_elements ()
		{
			update_visible_elements ();
			update_items ();
			window.update_icon_regions ();
			renderer.animated_draw ();
		}
		
		public void flush_pending_serialization ()
		{
			if (serialize_item_positions_timer_id > 0U) {
				Source.remove (serialize_item_positions_timer_id);
				serialize_item_positions_timer_id = 0U;
				serialize_item_positions ();
			}
		}

		public void schedule_serialize_item_positions ()
		{
			if (serialize_item_positions_timer_id > 0U)
				return;

			serialize_item_positions_timer_id = Gdk.threads_add_timeout (ITEM_SERIALIZATION_DELAY, (SourceFunc) serialize_item_positions);
		}

		bool serialize_item_positions ()
		{
			serialize_item_positions_timer_id = 0U;
			if (prefs == null || internal_elements == null)
				return false;

			var item_list = new Gee.ArrayList<string> ();

			foreach (var element in internal_elements) {
				unowned DockItem? item = (element as DockItem);
				if (item != null) {
					item_list.add (item.DockItemFilename);
					continue;
				}
				unowned DockItemProvider? provider = (element as DockItemProvider);
				if (provider != null) {
					var list = provider.get_dockitem_filenames ();
					foreach (unowned string s in list)
						item_list.add (s);
					continue;
				}
			}

			if (item_list.size == 0)
				return false;

			prefs.DockItems = item_list.to_array ();
			if (!prefs.CategorizeItems) {
				prefs.FreeDockItems = item_list.to_array ();
			} else {
				prefs.CategorizedDockItems = item_list.to_array ();
			}
			prefs.flush_to_disk ();

			return false;
		}

		public void handle_system_resume ()
		{
			message ("DockController '%s': handling system resume / wake-up", name);
			WindowControl.handle_system_resume ();
			window.update_layer_shell_monitor ();
			position_manager.update_dock_position ();
			window.update_size_and_position ();
			if (renderer != null)
				renderer.reset_buffers ();
			hide_manager.wake_up ();
			window.show_all ();
			if (GtkLayerShell.is_supported ())
				window.present ();
			if (renderer != null)
				renderer.animated_draw ();
		}

		public bool is_interaction_active (Gtk.Window? closing_win = null)
		{
			if (window != null && window.menu_is_visible ())
				return true;
			if (folder_menu != null && folder_menu.get_visible ())
				return true;
			if (window_cards != null && window_cards.get_visible ())
				return true;
			if (drag_manager != null && (drag_manager.InternalDragActive || drag_manager.ExternalDragActive))
				return true;

			if (IconChooserDialog.is_open && (closing_win == null || !(closing_win is IconChooserDialog)))
				return true;
			if (WeatherCityDialog.is_open && (closing_win == null || !(closing_win is WeatherCityDialog)))
				return true;
			if (CalendarWindow.is_open () && (closing_win == null || !(closing_win is CalendarWindow)))
				return true;
			if (WeatherWindow.is_open () && (closing_win == null || !(closing_win is WeatherWindow)))
				return true;
			if (SessionWindow.is_open () && (closing_win == null || !(closing_win is SessionWindow)))
				return true;
			if (AbstractMain.is_easter_egg_running)
				return true;

			return false;
		}

		public void check_collapse_after_interaction (Gtk.Window? closing_win = null)
		{
			if (app_provider != null && app_provider.is_accordion_enabled ()) {
				if (app_provider.has_drag_expansion ()) {
					if (!is_interaction_active (closing_win)) {
						app_provider.cancel_collapse_timer ();
						app_provider.schedule_collapse_docklets (uint.min (prefs.AccordionDelay, 800U));
					}
				} else if (prefs.AccordionClickToExpand) {
					if (!is_interaction_active (closing_win)) {
						app_provider.cancel_collapse_timer ();
						app_provider.restore_click_to_expand_latches ();
					}
				} else if (hide_manager.Hovered) {
					app_provider.cancel_collapse_timer ();
				} else if (!is_interaction_active (closing_win)) {
					app_provider.cancel_collapse_timer ();
					app_provider.schedule_collapse_docklets (prefs.AccordionDelay);
				}
			}
		}
	}
}
