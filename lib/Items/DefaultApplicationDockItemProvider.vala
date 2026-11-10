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
	public class DefaultApplicationDockItemProvider : ApplicationDockItemProvider
	{
		public DockPreferences Prefs { get; construct; }
		public bool docklets_expanded { get; protected set; default = false; }
		public bool docklets_drag_expanded { get; private set; default = false; }
		uint docklets_collapse_timer_id = 0U;

		/**
		 * Whether the Smart Pinned Accordion is currently expanded (all pinned apps shown).
		 * Independent from docklets_expanded, but both share the collapse timer and delay.
		 */
		public bool pinned_expanded { get; protected set; default = false; }
		public bool pinned_drag_expanded { get; private set; default = false; }

		public bool has_drag_expansion ()
		{
			return docklets_drag_expanded || pinned_drag_expanded;
		}

		/**
		 * How many pinned apps the Smart Pinned Accordion is currently hiding.
		 */
		public int pinned_hidden_count { get; private set; default = 0; }

		bool refreshing_pinned = false;

		/**
		 * Pinned apps are the regular launcher items: not transient (unpinned running)
		 * apps, folders, docklets, separators or the trash.
		 */
		public static bool is_pinned_app_element (DockElement el)
		{
			return (el is ApplicationDockItem) && !(el is TransientDockItem);
		}

		/**
		 * Whether the Smart Pinned Accordion is active. Like the docklet accordion it
		 * only exists in categorized mode, where pinned apps form their own group.
		 */
		public bool is_pinned_accordion_enabled ()
		{
			return Prefs.CategorizeItems && Prefs.PinnedAccordionMode != DockPreferences.PINNED_ACCORDION_OFF;
		}

		/**
		 * Whether any accordion (docklets or pinned apps) is active: they share the
		 * Click to Expand and Collapse Delay preferences.
		 */
		public bool is_accordion_enabled ()
		{
			return Prefs.CategorizeItems && (Prefs.AccordionDocklets || is_pinned_accordion_enabled ());
		}

		/**
		 * Whether any accordion is currently expanded.
		 */
		public bool is_any_expanded ()
		{
			return docklets_expanded || pinned_expanded;
		}

		public static bool is_docklet_element (DockElement el)
		{
			if (el is TrashDockItem || el is SeparatorDockItem || el is PlankDockItem)
				return false;
			var item = el as DockItem;
			if (item != null && item.Prefs != null && item.Prefs.Launcher != null)
				return item.Prefs.Launcher.has_prefix ("docklet://");
			return false;
		}

		public bool is_accordion_docklet (DockElement el)
		{
			if (!is_docklet_element (el))
				return false;
			if (Prefs != null && Prefs.AnchorAlwaysLeft) {
				unowned DockItem? item = el as DockItem;
				if (el is PreferencesDockItem || (item != null && item.Prefs != null && item.Prefs.Launcher == "docklet://preferences"))
					return false;
			}
			return true;
		}

		public DefaultApplicationDockItemProvider (DockPreferences prefs, File launchers_dir)
		{
			Object (Prefs : prefs, LaunchersDir : launchers_dir);
		}

		construct
		{
			if (Prefs != null && Prefs.CategorizeItems && Prefs.AccordionClickToExpand) {
				docklets_expanded = Prefs.AccordionDocklets && Prefs.docklets_expanded_latch;
				pinned_expanded = is_pinned_accordion_enabled () && Prefs.pinned_expanded_latch;
			}
			Prefs.notify["CurrentWorkspaceOnly"].connect (handle_setting_changed);
			Prefs.notify["PinnedOnly"].connect (handle_pinned_only_changed);
			Prefs.notify["CategorizeItems"].connect (handle_categorize_items_changed);
			Prefs.notify["AnchorAlwaysLeft"].connect (handle_category_layout_changed);
			Prefs.notify["DockletsOnRight"].connect (handle_category_layout_changed);
			Prefs.notify["AccordionDocklets"].connect (handle_accordion_docklets_changed);
			Prefs.notify["SystemMenuAccess"].connect (handle_system_menu_access_changed);
			Prefs.notify["ShowRunningIndicators"].connect (handle_running_indicators_changed);
			Prefs.notify["ShowAttentionIndicators"].connect (handle_running_indicators_changed);
			Prefs.notify["PinnedAccordionMode"].connect (handle_pinned_accordion_changed);
			Prefs.notify["PinnedAccordionCount"].connect (handle_pinned_accordion_changed);
			Prefs.notify["AccordionClickToExpand"].connect (handle_click_to_expand_changed);
			Prefs.notify["IconSize"].connect (handle_icon_size_changed);
			WindowManager.get_default ().windows_refreshed.connect (on_windows_refreshed);
		}

		public void ensure_preferences_dockitem ()
		{
			if (Prefs.SystemMenuAccess == 4) {
				if (item_for_uri ("docklet://preferences") == null) {
					add_item_with_uri ("docklet://preferences");
				}
			} else {
				DockItem? di = item_for_uri ("docklet://preferences");
				if (di != null) {
					disconnect_element (di);
					internal_elements.remove (di);
					di.Container = null;
					di.delete ();
				}
			}
		}

		void handle_system_menu_access_changed ()
		{
			ensure_preferences_dockitem ();
			refresh_separators ();
			update_visible_elements ();
			unowned DockController? dock = get_dock ();
			if (dock != null && dock.renderer != null && dock.renderer.theme != null) {
				dock.refresh_visible_elements ();
				dock.position_manager.update (dock.renderer.theme);
				dock.renderer.reset_buffers ();
				dock.schedule_serialize_item_positions ();
				if (dock.window != null) {
					dock.window.set_input_mask ();
				}
				dock.renderer.animated_draw ();
			}
		}

		public void deduplicate_items ()
		{
			var seen_uris = new Gee.HashSet<string> ();
			var duplicates = new Gee.ArrayList<DockElement> ();
			
			for (int i = 0; i < internal_elements.size; i++) {
				var el = internal_elements.get (i);
				if (el is SeparatorDockItem)
					continue;
				unowned DockItem? item = el as DockItem;
				if (item != null && item.Launcher != null && item.Launcher != "") {
					if (seen_uris.contains (item.Launcher)) {
						duplicates.add (el);
					} else {
						seen_uris.add (item.Launcher);
					}
				}
			}
			
			foreach (var dup in duplicates) {
				warning ("DefaultApplicationDockItemProvider: Removing duplicate element '%s'", dup.Text);
				disconnect_element (dup);
				internal_elements.remove (dup);
				dup.Container = null;
				if (dup is DockItem)
					((DockItem) dup).cleanup ();
			}
		}

		~DefaultApplicationDockItemProvider ()
		{
			cancel_collapse_timer ();
			Prefs.notify["CurrentWorkspaceOnly"].disconnect (handle_setting_changed);
			Prefs.notify["PinnedOnly"].disconnect (handle_pinned_only_changed);
			Prefs.notify["CategorizeItems"].disconnect (handle_categorize_items_changed);
			Prefs.notify["AnchorAlwaysLeft"].disconnect (handle_category_layout_changed);
			Prefs.notify["DockletsOnRight"].disconnect (handle_category_layout_changed);
			Prefs.notify["AccordionDocklets"].disconnect (handle_accordion_docklets_changed);
			Prefs.notify["SystemMenuAccess"].disconnect (handle_system_menu_access_changed);
			Prefs.notify["ShowRunningIndicators"].disconnect (handle_running_indicators_changed);
			Prefs.notify["ShowAttentionIndicators"].disconnect (handle_running_indicators_changed);
			Prefs.notify["PinnedAccordionMode"].disconnect (handle_pinned_accordion_changed);
			Prefs.notify["PinnedAccordionCount"].disconnect (handle_pinned_accordion_changed);
			Prefs.notify["AccordionClickToExpand"].disconnect (handle_click_to_expand_changed);
			Prefs.notify["IconSize"].disconnect (handle_icon_size_changed);
			WindowManager.get_default ().windows_refreshed.disconnect (on_windows_refreshed);
			if (pinned_expander != null) {
				disconnect_element (pinned_expander);
				internal_elements.remove (pinned_expander);
				pinned_expander.Container = null;
				pinned_expander.cleanup ();
				pinned_expander = null;
			}
			if (docklets_expander != null) {
				disconnect_element (docklets_expander);
				internal_elements.remove (docklets_expander);
				docklets_expander.Container = null;
				docklets_expander.cleanup ();
				docklets_expander = null;
			}
		}

		void handle_running_indicators_changed ()
		{
			foreach (var element in internal_elements) {
				unowned ApplicationDockItem? app_item = (element as ApplicationDockItem);
				if (app_item != null) {
					app_item.refresh_indicator ();
					continue;
				}
				unowned FileDockItem? file_item = (element as FileDockItem);
				if (file_item != null)
					file_item.update_indicator ();
			}
			unowned DockController? dock = get_dock ();
			if (dock != null) {
				if (dock.folder_menu != null)
					dock.folder_menu.refresh_if_visible ();
				if (dock.renderer != null)
					dock.renderer.animated_draw ();
			}
			refresh_pinned_accordion ();
		}

		void handle_category_layout_changed ()
		{
			cancel_collapse_timer ();
			docklets_drag_expanded = false;
			pinned_drag_expanded = false;
			if (Prefs.CategorizeItems && Prefs.AccordionClickToExpand) {
				docklets_expanded = Prefs.AccordionDocklets && Prefs.docklets_expanded_latch;
				pinned_expanded = is_pinned_accordion_enabled () && Prefs.pinned_expanded_latch;
			} else {
				docklets_expanded = false;
				pinned_expanded = false;
			}
			foreach (var element in internal_elements) {
				element.IsAttached = true;
				element.AddTime = 0;
				element.RemoveTime = 0;
			}
			refresh_separators ();

			unowned DockController? dock = get_dock ();
			if (dock != null && dock.renderer != null && dock.renderer.theme != null) {
				dock.update_items ();
				dock.position_manager.update (dock.renderer.theme);
				dock.renderer.reset_buffers ();
				dock.renderer.animated_draw ();
				dock.schedule_serialize_item_positions ();
				if (dock.window != null) {
					dock.window.set_input_mask ();
				}
			}
		}

		void handle_accordion_docklets_changed ()
		{
			cancel_collapse_timer ();
			docklets_drag_expanded = false;
			docklets_expanded = (Prefs.CategorizeItems && Prefs.AccordionDocklets && Prefs.AccordionClickToExpand)
				? Prefs.docklets_expanded_latch
				: false;
			foreach (var element in internal_elements) {
				element.IsAttached = true;
				element.AddTime = 0;
				element.RemoveTime = 0;
			}
			refresh_separators ();

			unowned DockController? dock = get_dock ();
			if (dock != null && dock.renderer != null && dock.renderer.theme != null) {
				dock.update_items ();
				dock.position_manager.update (dock.renderer.theme);
				dock.renderer.reset_buffers ();
				dock.renderer.animated_draw ();
				dock.schedule_serialize_item_positions ();
				if (dock.window != null) {
					dock.window.set_input_mask ();
				}
			}
		}

		public void expand_docklets (bool save_latch = false, bool for_drag = false)
		{
			cancel_collapse_timer ();
			if (!Prefs.CategorizeItems || !Prefs.AccordionDocklets)
				return;
			if (!for_drag)
				docklets_drag_expanded = false;
			if (save_latch && Prefs.AccordionClickToExpand)
				Prefs.update_docklets_expanded_latch (true);
			if (docklets_expanded)
				return;
			if (for_drag)
				docklets_drag_expanded = true;
			docklets_expanded = true;
			refresh_separators ();
			refresh_dock_layout ();
		}

		public void collapse_docklets (bool save_latch = false)
		{
			cancel_collapse_timer ();
			docklets_drag_expanded = false;
			if (save_latch && Prefs.AccordionClickToExpand)
				Prefs.update_docklets_expanded_latch (false);
			if (!docklets_expanded)
				return;
			docklets_expanded = false;
			refresh_separators ();
			refresh_dock_layout ();
		}

		public void restore_click_to_expand_latches ()
		{
			docklets_drag_expanded = false;
			pinned_drag_expanded = false;
			if (Prefs == null || !Prefs.CategorizeItems || !Prefs.AccordionClickToExpand)
				return;
			bool target_docklets = Prefs.AccordionDocklets && Prefs.docklets_expanded_latch;
			bool target_pinned = is_pinned_accordion_enabled () && Prefs.pinned_expanded_latch;
			if (docklets_expanded == target_docklets && pinned_expanded == target_pinned)
				return;
			docklets_expanded = target_docklets;
			pinned_expanded = target_pinned;
			refresh_separators ();
			refresh_dock_layout ();
		}

		public void cancel_collapse_timer ()
		{
			if (docklets_collapse_timer_id != 0U) {
				Source.remove (docklets_collapse_timer_id);
				docklets_collapse_timer_id = 0U;
			}
		}

		public void schedule_collapse_docklets (uint delay_ms = 0U)
		{
			if (!is_accordion_enabled () || (Prefs != null && Prefs.AccordionClickToExpand && !has_drag_expansion ())) {
				cancel_collapse_timer ();
				return;
			}
			unowned DockController? dock = get_dock ();
			if (dock != null && (dock.drag_manager.InternalDragActive || dock.drag_manager.ExternalDragActive))
				return;
			if (dock != null && dock.is_interaction_active ())
				return;
			if (!docklets_expanded && !pinned_expanded)
				return;
			if (docklets_collapse_timer_id != 0U)
				return;
			uint timeout_ms = delay_ms;
			if (timeout_ms == 0U) {
				timeout_ms = (Prefs != null && Prefs.AccordionDelay >= DockPreferences.MIN_ACCORDION_DELAY) ? Prefs.AccordionDelay : DockPreferences.DEFAULT_ACCORDION_DELAY;
			}
			docklets_collapse_timer_id = Timeout.add (timeout_ms, () => {
				docklets_collapse_timer_id = 0U;
				if (!is_accordion_enabled ()) {
					docklets_drag_expanded = false;
					pinned_drag_expanded = false;
					foreach (var element in internal_elements) {
						element.IsAttached = true;
						element.AddTime = 0;
						element.RemoveTime = 0;
					}
					return Source.REMOVE;
				}
				unowned DockController? d = get_dock ();
				if (d != null && (d.drag_manager.InternalDragActive || d.drag_manager.ExternalDragActive))
					return Source.REMOVE;
				if (d != null && d.is_interaction_active ())
					return Source.REMOVE;

				if (has_drag_expansion ()) {
					bool click_mode = (Prefs != null && Prefs.AccordionClickToExpand);
					bool changed = false;
					if (docklets_drag_expanded) {
						docklets_drag_expanded = false;
						bool target_d = click_mode ? (Prefs.AccordionDocklets && Prefs.docklets_expanded_latch) : false;
						if (docklets_expanded != target_d) {
							docklets_expanded = target_d;
							changed = true;
						}
					}
					if (pinned_drag_expanded) {
						pinned_drag_expanded = false;
						bool target_p = click_mode ? (is_pinned_accordion_enabled () && Prefs.pinned_expanded_latch) : false;
						if (pinned_expanded != target_p) {
							pinned_expanded = target_p;
							changed = true;
						}
					}
					if (!click_mode && (d == null || !d.hide_manager.Hovered)) {
						if (docklets_expanded || pinned_expanded) {
							docklets_expanded = false;
							pinned_expanded = false;
							changed = true;
						}
					}
					if (changed) {
						refresh_separators ();
						refresh_dock_layout ();
					}
					return Source.REMOVE;
				}

				if (Prefs != null && Prefs.AccordionClickToExpand)
					return Source.REMOVE;
				if (d != null && d.hide_manager.Hovered)
					return Source.REMOVE;
				if (docklets_expanded || pinned_expanded) {
					docklets_expanded = false;
					pinned_expanded = false;
					refresh_separators ();
					refresh_dock_layout ();
				}
				return Source.REMOVE;
			});
		}

		void refresh_dock_layout ()
		{
			unowned DockController? dock = get_dock ();
			if (dock != null && dock.renderer != null && dock.renderer.theme != null) {
				dock.update_items ();
				dock.position_manager.update (dock.renderer.theme);
				dock.renderer.animated_draw ();
				if (dock.window != null) {
					dock.window.set_input_mask ();
				}
			}
		}

		/**
		 * Expands the Smart Pinned Accordion: all pinned apps become visible until the
		 * shared collapse timer (or an explicit collapse) hides the unused ones again.
		 */
		public void expand_pinned (bool save_latch = false, bool for_drag = false)
		{
			cancel_collapse_timer ();
			if (!is_pinned_accordion_enabled ())
				return;
			if (!for_drag)
				pinned_drag_expanded = false;
			if (save_latch && Prefs.AccordionClickToExpand)
				Prefs.update_pinned_expanded_latch (true);
			if (pinned_expanded)
				return;
			if (for_drag)
				pinned_drag_expanded = true;
			pinned_expanded = true;
			refresh_separators ();
			refresh_dock_layout ();
		}

		/**
		 * An app is never hidden by the accordion while it is running, demands attention,
		 * or was marked "Keep Always Visible" by the user.
		 */
		bool is_pinned_app_always_visible (ApplicationDockItem app)
		{
			if (app.Prefs.KeepVisible)
				return true;
			var window_manager = WindowManager.get_default ();
			if (window_manager.window_count_for_app (app.Launcher) > 0)
				return true;
			if (!WindowControl.has_state () && app.running_for_accordion)
				return true;
			if (Prefs.ShowAttentionIndicators && window_manager.app_demands_attention (app.Launcher))
				return true;
			return false;
		}

		/**
		 * Decides which pinned apps the Smart Pinned Accordion hides right now.
		 *
		 * - Running / urgent / Keep Always Visible apps always stay (additively).
		 * - The remaining apps are ranked by usage score; ties (and cold start, all 0.0)
		 *   are broken by the manual left-to-right dock order.
		 * - The N best stay: N is the user's count (Top Most Used) or what still fits on
		 *   screen at the preferred icon size (Auto-Fit Capacity).
		 * - Visible apps keep their manual order: nothing is ever reshuffled.
		 *
		 * Pure computation: no IPC, no layout mutation, no timers.
		 *
		 * @param as_collapsed evaluate as if the accordion were collapsed (ignores the
		 *        expanded state and running drags): tells how many apps a collapse would hide
		 */
		Gee.HashSet<DockElement> compute_hidden_pinned_apps (bool as_collapsed = false)
		{
			var hidden = new Gee.HashSet<DockElement> ();
			if (!is_pinned_accordion_enabled () || (pinned_expanded && !as_collapsed))
				return hidden;

			unowned DockController? dock = get_dock ();
			if (!as_collapsed && dock != null
				&& (dock.drag_manager.ExternalDragActive
					|| (dock.drag_manager.InternalDragActive && dock.drag_manager.InternalReorderIntent)))
				return hidden;

			var pinned = new Gee.ArrayList<ApplicationDockItem> ();
			foreach (var element in internal_elements) {
				if (is_pinned_app_element (element))
					pinned.add ((ApplicationDockItem) element);
			}
			if (pinned.size == 0)
				return hidden;

			var candidates = new Gee.ArrayList<ApplicationDockItem> ();
			int always_visible = 0;
			foreach (var app in pinned) {
				if (is_pinned_app_always_visible (app))
					always_visible++;
				else
					candidates.add (app);
			}

			int habitual;
			if (Prefs.PinnedAccordionMode == DockPreferences.PINNED_ACCORDION_TOP_N) {
				habitual = Prefs.PinnedAccordionCount;
			} else {
				if (dock == null)
					return hidden;
				double capacity = dock.position_manager.get_preferred_slot_capacity ();
				// Geometry not ready yet (startup): show everything, we are re-run afterwards
				if (capacity < 0.0)
					return hidden;

				// Slots taken by everything which is not a pinned app (+0.5 for the expander).
				// Separators are counted structurally so that the result does not depend on
				// the separator clean-up pass.
				double used = 0.5 + always_visible;
				foreach (var element in internal_elements) {
					if (is_pinned_app_element (element) || element is PinnedExpanderDockItem)
						continue;
					if (element is SeparatorDockItem)
						used += 0.5;
					else if (element.IsAttached)
						used += 1.0;
				}
				habitual = int.max (1, (int) Math.floor (capacity - used));
			}

			if (candidates.size <= habitual)
				return hidden;

			var usage = AppUsageService.get_default ();
			candidates.sort ((a, b) => {
				var score_a = usage.get_score (a.Launcher);
				var score_b = usage.get_score (b.Launcher);
				int64 bucket_a = (int64) Math.round (score_a / AppUsageService.TIE_EPSILON);
				int64 bucket_b = (int64) Math.round (score_b / AppUsageService.TIE_EPSILON);
				if (bucket_a != bucket_b)
					return (bucket_a > bucket_b) ? -1 : 1;
				return pinned.index_of (a) - pinned.index_of (b);
			});

			for (int i = habitual; i < candidates.size; i++)
				hidden.add (candidates.get (i));
			return hidden;
		}

		/**
		 * Applies the accordion decision to the IsAttached flags. Called from
		 * update_visible_elements () which has just reset every flag.
		 */
		void apply_pinned_accordion ()
		{
			var hidden = compute_hidden_pinned_apps ();
			// How many apps a collapse hides: drives the expander (also while expanded or during drag)
			var collapsed_hidden = compute_hidden_pinned_apps (true);

			if (collapsed_hidden.size != pinned_hidden_count) {
				var names = new StringBuilder ();
				foreach (var element in collapsed_hidden) {
					if (names.len > 0)
						names.append (", ");
					names.append (element.Text);
				}
				debug ("PinnedAccordion: %d pinned app(s) hideable%s%s", collapsed_hidden.size,
					collapsed_hidden.size > 0 ? ": " : "", names.str);
				pinned_hidden_count = collapsed_hidden.size;
			}

			if (pinned_hidden_count == 0 && pinned_expanded && !Prefs.AccordionClickToExpand)
				pinned_expanded = false;

			foreach (var element in internal_elements) {
				if (!is_pinned_app_element (element) || !hidden.contains (element))
					continue;
				element.IsAttached = false;
			}

			sync_pinned_expander ();
		}

		PinnedExpanderDockItem? pinned_expander = null;
		PinnedExpanderDockItem? docklets_expander = null;

		void update_expander_text ()
		{
			if (pinned_expander != null) {
				string new_pinned_text;
				if (pinned_expanded) {
					new_pinned_text = _("Collapse pinned apps");
				} else {
					var hidden_text = _("Hidden pinned apps: %d").printf (pinned_hidden_count);
					new_pinned_text = Prefs.AccordionClickToExpand
						? "%s (%s)".printf (hidden_text, _("Click to expand"))
						: hidden_text;
				}
				if (pinned_expander.Text != new_pinned_text)
					pinned_expander.Text = new_pinned_text;
			}
			if (docklets_expander != null) {
				string new_docklets_text;
				if (docklets_expanded) {
					new_docklets_text = _("Docklets");
				} else {
					new_docklets_text = Prefs.AccordionClickToExpand
						? "%s (%s)".printf (_("Docklets"), _("Click to expand"))
						: _("Docklets");
				}
				if (docklets_expander.Text != new_docklets_text)
					docklets_expander.Text = new_docklets_text;
			}
		}

		void handle_click_to_expand_changed ()
		{
			cancel_collapse_timer ();
			if (!Prefs.AccordionClickToExpand) {
				unowned DockController? dock = get_dock ();
				if (dock != null && dock.hide_manager != null && dock.hide_manager.Hovered) {
					// Pointer is on the dock: keep current state until pointer leaves
				} else {
					docklets_expanded = false;
					pinned_expanded = false;
				}
			} else if (Prefs.CategorizeItems) {
				docklets_expanded = Prefs.AccordionDocklets && Prefs.docklets_expanded_latch;
				pinned_expanded = is_pinned_accordion_enabled () && Prefs.pinned_expanded_latch;
			}
			update_expander_text ();
			refresh_separators ();
			refresh_dock_layout ();
		}

		void sync_docklets_expander ()
		{
			if (docklets_expander != null) {
				var old_index = internal_elements.index_of (docklets_expander);
				if (old_index >= 0)
					internal_elements.remove_at (old_index);
				docklets_expander.IsAttached = false;
			}

			if (!Prefs.CategorizeItems || !Prefs.AccordionDocklets || get_docklet_count () <= 1)
				return;

			int last_docklet = -1;
			for (int i = 0; i < internal_elements.size; i++) {
				if (is_accordion_docklet (internal_elements.get (i)))
					last_docklet = i;
			}
			if (last_docklet < 0)
				return;

			if (docklets_expander == null) {
				docklets_expander = new PinnedExpanderDockItem ();
				docklets_expander.IsDockletExpander = true;
				docklets_expander.Container = this;
				connect_element (docklets_expander);
			}

			docklets_expander.IsAttached = true;
			docklets_expander.AddTime = 0;
			docklets_expander.RemoveTime = 0;
			internal_elements.insert (last_docklet + 1, docklets_expander);

			if (docklets_expander.Expanded != docklets_expanded)
				docklets_expander.Expanded = docklets_expanded;
			update_expander_text ();
		}

		/**
		 * Keeps the expander item right after the last pinned app while the accordion has
		 * something to expand, and removes it otherwise. The item instance is kept alive
		 * (and connected) across rebuilds so that it never flickers or re-animates.
		 */
		void sync_pinned_expander ()
		{
			if (pinned_expander != null) {
				var old_index = internal_elements.index_of (pinned_expander);
				if (old_index >= 0)
					internal_elements.remove_at (old_index);
				pinned_expander.IsAttached = false;
			}

			if (!is_pinned_accordion_enabled () || pinned_hidden_count <= 0)
				return;

			int last_pinned = -1;
			for (int i = 0; i < internal_elements.size; i++) {
				if (is_pinned_app_element (internal_elements.get (i)))
					last_pinned = i;
			}
			if (last_pinned < 0)
				return;

			if (pinned_expander == null) {
				pinned_expander = new PinnedExpanderDockItem ();
				pinned_expander.Container = this;
				connect_element (pinned_expander);
			}

			pinned_expander.IsAttached = true;
			pinned_expander.AddTime = 0;
			pinned_expander.RemoveTime = 0;
			internal_elements.insert (last_pinned + 1, pinned_expander);

			if (pinned_expander.Expanded != pinned_expanded)
				pinned_expander.Expanded = pinned_expanded;
			update_expander_text ();
		}

		/**
		 * Collapses the Smart Pinned Accordion right away (click on the expander).
		 */
		public void collapse_pinned (bool save_latch = false)
		{
			cancel_collapse_timer ();
			pinned_drag_expanded = false;
			if (save_latch && Prefs.AccordionClickToExpand)
				Prefs.update_pinned_expanded_latch (false);
			if (!pinned_expanded)
				return;
			pinned_expanded = false;
			refresh_separators ();
			refresh_dock_layout ();
		}

		/**
		 * Re-evaluates the accordion and, only if the set of hidden apps changed, rebuilds
		 * the dock layout. Cheap enough to call on every window refresh.
		 */
		public void refresh_pinned_accordion ()
		{
			if (refreshing_pinned)
				return;

			unowned DockController? dock = get_dock ();
			if (dock == null || dock.renderer == null || dock.renderer.theme == null)
				return;

			var hidden = compute_hidden_pinned_apps ();
			bool changed = false;
			foreach (var element in internal_elements) {
				if (!is_pinned_app_element (element))
					continue;
				// An element must be attached exactly when it is not hidden
				if (element.IsAttached == hidden.contains (element)) {
					changed = true;
					break;
				}
			}
			// The expander follows the number of apps a collapse would hide
			var collapsed_count = pinned_expanded ? compute_hidden_pinned_apps (true).size : hidden.size;
			if (collapsed_count != pinned_hidden_count)
				changed = true;
			if (!changed)
				return;

			refreshing_pinned = true;
			refresh_separators ();
			refresh_dock_layout ();
			refreshing_pinned = false;
		}

		void handle_pinned_accordion_changed ()
		{
			cancel_collapse_timer ();
			pinned_drag_expanded = false;
			pinned_expanded = (is_pinned_accordion_enabled () && Prefs.AccordionClickToExpand)
				? Prefs.pinned_expanded_latch
				: false;
			refreshing_pinned = true;
			refresh_separators ();
			refresh_dock_layout ();
			refreshing_pinned = false;
		}

		void handle_icon_size_changed ()
		{
			refresh_pinned_accordion ();
		}

		void handle_keep_visible_changed ()
		{
			refresh_pinned_accordion ();
		}

		/**
		 * Feeds the usage tracker with the app owning the focused window and re-evaluates
		 * the accordion (an app which just started running must not stay hidden).
		 */
		void on_windows_refreshed ()
		{
			string? active_launcher = null;
			var window_manager = WindowManager.get_default ();
			foreach (var element in internal_elements) {
				unowned ApplicationDockItem? app = (element as ApplicationDockItem);
				if (app != null && app.Launcher != "" && window_manager.app_is_active (app.Launcher)) {
					active_launcher = app.Launcher;
					break;
				}
			}
			AppUsageService.get_default ().note_active_launcher (active_launcher);

			refresh_pinned_accordion ();
		}

		void handle_categorize_items_changed ()
		{
			cancel_collapse_timer ();
			if (Prefs.CategorizeItems && Prefs.AccordionClickToExpand) {
				docklets_expanded = Prefs.AccordionDocklets && Prefs.docklets_expanded_latch;
				pinned_expanded = is_pinned_accordion_enabled () && Prefs.pinned_expanded_latch;
			} else {
				docklets_expanded = false;
				pinned_expanded = false;
			}
			deduplicate_items ();
			foreach (var element in internal_elements) {
				element.IsAttached = true;
				element.AddTime = 0;
				element.RemoveTime = 0;
			}
			if (!Prefs.CategorizeItems) {
				save_current_order_to (false);
				restore_order_from (Prefs.FreeDockItems);
			} else {
				save_current_order_to (true);
				if (Prefs.CategorizedDockItems.length > 0) {
					restore_order_from (Prefs.CategorizedDockItems);
				}
			}
			update_visible_elements ();

			unowned DockController? dock = get_dock ();
			// CRITICAL RENDERER READY GUARD:
			// During initial startup, add_default_provider () runs before renderer.initialize ().
			// If a category setting triggers this callback early, dock.renderer or its theme may be null.
			// Guarding against null prevents assertion failures (plank_dock_renderer_reset_buffers: assertion 'self != NULL').
			if (dock != null && dock.renderer != null && dock.renderer.theme != null) {
				dock.refresh_visible_elements ();
				dock.position_manager.update (dock.renderer.theme);
				dock.renderer.reset_buffers ();
				dock.schedule_serialize_item_positions ();
				if (dock.window != null) {
					dock.window.set_input_mask ();
				}
				dock.renderer.animated_draw ();
			}
		}

		void save_current_order_to (bool is_free)
		{
			var item_list = new Gee.ArrayList<string> ();
			var seen = new Gee.HashSet<string> ();
			foreach (var element in internal_elements) {
				unowned DockItem? item = (element as DockItem);
				if (item != null && !(item is TransientDockItem) && !(item is SeparatorDockItem) && item.DockItemFilename.length > 0) {
					if (!seen.contains (item.DockItemFilename)) {
						seen.add (item.DockItemFilename);
						item_list.add (item.DockItemFilename);
					}
				}
			}
			if (item_list.size == 0)
				return;
			if (is_free)
				Prefs.FreeDockItems = item_list.to_array ();
			else
				Prefs.CategorizedDockItems = item_list.to_array ();
		}

		void restore_order_from (string[] target_items)
		{
			if (target_items == null || target_items.length == 0)
				return;

			var ordered_elements = new Gee.ArrayList<DockElement> ();
			var remaining_elements = new Gee.ArrayList<DockElement> ();
			TrashDockItem? trash_item = null;
			var transient_items = new Gee.ArrayList<DockElement> ();

			for (int i = 0; i < internal_elements.size; i++) {
				var el = internal_elements.get (i);
				if (el is SeparatorDockItem || el is PinnedExpanderDockItem) {
					continue;
				} else if (el is TrashDockItem) {
					trash_item = (TrashDockItem) el;
				} else if (el is TransientDockItem) {
					transient_items.add (el);
				} else {
					remaining_elements.add (el);
				}
			}

			var seen_targets = new Gee.HashSet<string> ();
			foreach (var fn in target_items) {
				if (seen_targets.contains (fn))
					continue;
				seen_targets.add (fn);
				for (int i = 0; i < remaining_elements.size; i++) {
					var el = remaining_elements.get (i);
					unowned DockItem? item = el as DockItem;
					if (item != null && item.DockItemFilename == fn) {
						ordered_elements.add (el);
						remaining_elements.remove_at (i);
						break;
					}
				}
			}

			var rem_folders = new Gee.ArrayList<DockElement> ();
			var rem_docklets = new Gee.ArrayList<DockElement> ();
			var rem_apps = new Gee.ArrayList<DockElement> ();
			foreach (var el in remaining_elements) {
				if (el is FileDockItem)
					rem_folders.add (el);
				else if (is_docklet_element (el))
					rem_docklets.add (el);
				else
					rem_apps.add (el);
			}
			foreach (var el in rem_folders) ordered_elements.add (el);
			if (!Prefs.DockletsOnRight) {
				foreach (var el in rem_docklets) ordered_elements.add (el);
			}
			foreach (var el in rem_apps) ordered_elements.add (el);

			foreach (var el in transient_items) {
				ordered_elements.add (el);
			}

			if (Prefs.DockletsOnRight) {
				foreach (var el in rem_docklets) ordered_elements.add (el);
			}

			if (trash_item != null) {
				ordered_elements.add (trash_item);
			}

			internal_elements.clear ();
			foreach (var el in ordered_elements) {
				internal_elements.add (el);
			}
		}

		Gee.ArrayList<DockElement> sort_bucket_by_target (Gee.ArrayList<DockElement> bucket, string[] targets)
		{
			var result = new Gee.ArrayList<DockElement> ();
			foreach (var fn in targets) {
				for (int i = 0; i < bucket.size; i++) {
					var el = bucket.get (i);
					unowned DockItem? item = el as DockItem;
					if (item != null && item.DockItemFilename == fn) {
						result.add (el);
						bucket.remove_at (i);
						break;
					}
				}
			}
			foreach (var el in bucket) {
				result.add (el);
			}
			return result;
		}

		public void reorder_free_items_by_category ()
		{
			cancel_collapse_timer ();
			if (Prefs != null && Prefs.CategorizeItems && Prefs.AccordionClickToExpand) {
				docklets_expanded = Prefs.AccordionDocklets && Prefs.docklets_expanded_latch;
				pinned_expanded = is_pinned_accordion_enabled () && Prefs.pinned_expanded_latch;
			} else {
				docklets_expanded = false;
				pinned_expanded = false;
			}
			deduplicate_items ();

			var folders = new Gee.ArrayList<DockElement> ();
			var docklets = new Gee.ArrayList<DockElement> ();
			DockElement? preferences_docklet = null;
			var pinned_apps = new Gee.ArrayList<DockElement> ();
			var transients = new Gee.ArrayList<DockElement> ();
			TrashDockItem? trash_item = null;

			for (int i = 0; i < internal_elements.size; i++) {
				var el = internal_elements.get (i);
				if (el is SeparatorDockItem || el is PinnedExpanderDockItem)
					continue;
				if (el is TrashDockItem) {
					trash_item = (TrashDockItem) el;
				} else if (el is TransientDockItem) {
					transients.add (el);
				} else if (el is FileDockItem) {
					folders.add (el);
				} else if (is_docklet_element (el)) {
					unowned DockItem? item = el as DockItem;
					if (el is PreferencesDockItem || (item != null && item.Prefs != null && item.Prefs.Launcher == "docklet://preferences")) {
						preferences_docklet = el;
					} else {
						docklets.add (el);
					}
				} else {
					pinned_apps.add (el);
				}
			}

			// Preserve user's relative order within each category if CategorizedDockItems exists
			if (Prefs.CategorizedDockItems != null && Prefs.CategorizedDockItems.length > 0) {
				folders = sort_bucket_by_target (folders, Prefs.CategorizedDockItems);
				docklets = sort_bucket_by_target (docklets, Prefs.CategorizedDockItems);
				pinned_apps = sort_bucket_by_target (pinned_apps, Prefs.CategorizedDockItems);
			}

			// Ordered according to user layout preferences
			var new_order = new Gee.ArrayList<DockElement> ();
			if (Prefs.AnchorAlwaysLeft && preferences_docklet != null)
				new_order.add (preferences_docklet);
			foreach (var f in folders) new_order.add (f);
			if (!Prefs.DockletsOnRight) {
				if (!Prefs.AnchorAlwaysLeft && preferences_docklet != null)
					new_order.add (preferences_docklet);
				foreach (var d in docklets) new_order.add (d);
			}
			foreach (var p in pinned_apps) new_order.add (p);
			foreach (var t in transients) new_order.add (t);
			if (Prefs.DockletsOnRight) {
				foreach (var d in docklets) new_order.add (d);
				if (!Prefs.AnchorAlwaysLeft && preferences_docklet != null)
					new_order.add (preferences_docklet);
			}
			if (trash_item != null) new_order.add (trash_item);

			internal_elements.clear ();
			foreach (var el in new_order) {
				internal_elements.add (el);
			}

			// Persist the clean sequence into FreeDockItems
			save_current_order_to (true);

			refresh_separators ();

			unowned DockController? dock = get_dock ();
			if (dock != null && dock.renderer != null && dock.renderer.theme != null) {
				dock.update_items ();
				dock.position_manager.update (dock.renderer.theme);
				dock.renderer.reset_buffers ();
				dock.renderer.animated_draw ();
				dock.schedule_serialize_item_positions ();
				if (dock.window != null) {
					dock.window.set_input_mask ();
				}
			}
		}

		public int get_docklet_count ()
		{
			int count = 0;
			foreach (var element in internal_elements) {
				if (is_accordion_docklet (element)) {
					count++;
				}
			}
			return count;
		}

		public DockElement? get_anchor_docklet ()
		{
			// Always anchor to the outer edge of the docklets group:
			// - Rightmost docklet when DockletsOnRight is true (so docklets expand Right -> Left)
			// - Leftmost docklet when DockletsOnRight is false (so docklets expand Left -> Right)
			if (Prefs != null && Prefs.DockletsOnRight) {
				for (int i = internal_elements.size - 1; i >= 0; i--) {
					var element = internal_elements.get (i);
					if (is_accordion_docklet (element)) {
						return element;
					}
				}
			} else {
				foreach (var element in internal_elements) {
					if (is_accordion_docklet (element)) {
						return element;
					}
				}
			}
			return null;
		}

		bool updating_visible_elements = false;

		protected override void update_visible_elements ()
		{
			unowned DockController? dock = get_dock ();
			bool can_animate_accordion = (dock != null && dock.renderer != null && dock.renderer.theme != null && visible_elements.size > 0);
			var prev_attached = new Gee.HashSet<DockElement> ();
			if (can_animate_accordion) {
				foreach (var item in visible_elements)
					prev_attached.add (item);
			}

			foreach (var item in internal_elements) {
				item.IsAttached = !(Prefs.PinnedOnly && item is TransientDockItem);
			}
			
			if (!updating_visible_elements) {
				updating_visible_elements = true;
				maintain_separator ();
				updating_visible_elements = false;
			}

			bool drag_active = (dock != null && (dock.drag_manager.ExternalDragActive
				|| (dock.drag_manager.InternalDragActive && dock.drag_manager.InternalReorderIntent)));
			if (drag_active && !Prefs.AccordionClickToExpand) {
				docklets_expanded = true;
				if (is_pinned_accordion_enabled ())
					pinned_expanded = true;
			}

			if (Prefs.CategorizeItems && Prefs.AccordionDocklets && !docklets_expanded && !drag_active) {
				int docklet_count = get_docklet_count ();
				if (docklet_count > 1) {
					DockElement? anchor = get_anchor_docklet ();
					foreach (var element in internal_elements) {
						if (is_accordion_docklet (element)) {
							element.IsAttached = (element == anchor);
						}
					}
				}
			}
			sync_docklets_expander ();

			// Smart Pinned Accordion: hide the least used pinned apps (before separator clean-up,
			// so that separators next to hidden apps are collapsed correctly)
			apply_pinned_accordion ();

			// Clean up consecutive, leading, and trailing separators
			bool prev_was_sep = true; // Start true so any leading separator is suppressed
			SeparatorDockItem? last_sep = null;
			foreach (var element in internal_elements) {
				if (!element.IsAttached)
					continue;
				if (element is SeparatorDockItem) {
					var sep = (SeparatorDockItem) element;
					if (prev_was_sep) {
						sep.IsAttached = false;
					} else {
						prev_was_sep = true;
						last_sep = sep;
					}
				} else if (element is PinnedExpanderDockItem) {
					// PinnedExpanderDockItem draws its own trailing bar (›| / «|), so it acts as
					// the separator after the group: drop any separator right before or right
					// after it.
					if (prev_was_sep && last_sep != null) {
						last_sep.IsAttached = false;
					}
					prev_was_sep = true;
					last_sep = null;
				} else {
					prev_was_sep = false;
				}
			}
			if (prev_was_sep && last_sep != null) {
				last_sep.IsAttached = false;
			}

			if (can_animate_accordion) {
				var now = GLib.get_monotonic_time ();
				foreach (var item in internal_elements) {
					if (item is SeparatorDockItem || item is PinnedExpanderDockItem)
						continue;
					bool was_att = prev_attached.contains (item);
					if (item.IsAttached && !was_att) {
						item.AddTime = now;
						item.RemoveTime = 0;
					} else if (!item.IsAttached && was_att) {
						item.RemoveTime = now;
						item.AddTime = 0;
					}
				}
			} else {
				foreach (var item in internal_elements) {
					if (item.IsAttached)
						item.RemoveTime = 0;
				}
			}

			base.update_visible_elements ();
		}

		public void refresh_separators ()
		{
			update_visible_elements ();
			unowned DockController? dock = get_dock ();
			if (dock != null) {
				dock.refresh_visible_elements ();
			}
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
			if (dragging_item != null)
				return;

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

			// Step 2: Keep existing separators connected so they remain stable and flicker-free

			// Step 3: Anchor Trash permanently at the very end of internal_elements
			if (trash_item != null && dragging_item == null) {
				int trash_idx = internal_elements.index_of (trash_item);
				if (trash_idx >= 0 && trash_idx != internal_elements.size - 1) {
					move_element (internal_elements, trash_idx, internal_elements.size - 1);
				}
			}

			// Step 4: Categorized Grouping or Classic Plank Arrangement
			if (Prefs.CategorizeItems) {
				var orphan_transients = new Gee.ArrayList<TransientDockItem> ();
				var folders = new Gee.ArrayList<DockElement> ();
				var pinned_apps = new Gee.ArrayList<DockElement> ();
				var docklets = new Gee.ArrayList<DockElement> ();
				DockElement? preferences_docklet = null;
				var other_docklets = new Gee.ArrayList<DockElement> ();
				var transients = new Gee.ArrayList<DockElement> ();

				for (int i = 0; i < internal_elements.size; i++) {
					var el = internal_elements.get (i);
					if (el is TrashDockItem || el is SeparatorDockItem || el is PinnedExpanderDockItem)
						continue;
					if (el is TransientDockItem) {
						var trans = (TransientDockItem) el;
						var win_count = WindowManager.get_default ().window_count_for_app (trans.Launcher);
						if (win_count <= 0 && !trans.is_running ()) {
							orphan_transients.add (trans);
							continue;
						}
						if (!Prefs.PinnedOnly)
							transients.add (el);
					} else if (el is FileDockItem) {
						folders.add (el);
					} else if (is_docklet_element (el)) {
						unowned DockItem? item = el as DockItem;
						if (el is PreferencesDockItem || (item != null && item.Prefs != null && item.Prefs.Launcher == "docklet://preferences")) {
							preferences_docklet = el;
						} else {
							other_docklets.add (el);
						}
					} else {
						pinned_apps.add (el);
					}
				}

				if (Prefs.SystemMenuAccess == 4 && preferences_docklet == null && dragging_item == null) {
					ensure_preferences_dockitem ();
					preferences_docklet = item_for_uri ("docklet://preferences");
				}

				if (!Prefs.DockletsOnRight && !Prefs.AnchorAlwaysLeft && preferences_docklet != null)
					docklets.add (preferences_docklet);
				foreach (var od in other_docklets)
					docklets.add (od);
				if (Prefs.DockletsOnRight && !Prefs.AnchorAlwaysLeft && preferences_docklet != null)
					docklets.add (preferences_docklet);

				foreach (var orphan in orphan_transients) {
					disconnect_element (orphan);
					internal_elements.remove (orphan);
					orphan.Container = null;
					orphan.delete ();
				}

				// Build ordered non-empty category groups:
				// - AnchorAlwaysLeft: [WayPlank] | at index 0
				// - DockletsOnRight = false: Folders -> Docklets -> Pinned Apps -> Unpinned Transients -> Trash
				// - DockletsOnRight = true:  Folders -> Pinned Apps -> Unpinned Transients -> Docklets -> Trash
				var groups = new Gee.ArrayList<Gee.ArrayList<DockElement>> ();

				if (Prefs.AnchorAlwaysLeft && preferences_docklet != null) {
					var anchor_group = new Gee.ArrayList<DockElement> ();
					anchor_group.add (preferences_docklet);
					groups.add (anchor_group);
				}

				if (folders.size > 0)
					groups.add (folders);

				if (!Prefs.DockletsOnRight && docklets.size > 0)
					groups.add (docklets);

				if (pinned_apps.size > 0)
					groups.add (pinned_apps);

				if (transients.size > 0)
					groups.add (transients);

				if (Prefs.DockletsOnRight && docklets.size > 0)
					groups.add (docklets);

				if (trash_item != null) {
					var trash_group = new Gee.ArrayList<DockElement> ();
					trash_group.add (trash_item);
					groups.add (trash_group);
				}

				// Rebuild internal_elements with dynamic separators between adjacent non-empty groups
				internal_elements.clear ();
				int sep_pool_idx = 0;
				for (int g = 0; g < groups.size; g++) {
					if (g > 0) {
						SeparatorDockItem sep;
						if (sep_pool_idx < existing_separators.size) {
							sep = existing_separators.get (sep_pool_idx++);
						} else {
							sep = new SeparatorDockItem ();
							sep.Container = this;
							connect_element (sep);
						}
						sep.AddTime = 0;
						sep.RemoveTime = 0;
						sep.IsAttached = true;
						internal_elements.add (sep);
					}
					foreach (var item in groups.get (g)) {
						internal_elements.add (item);
					}
				}

				// Clean up any remaining unused separators in the pool to prevent leaks
				while (sep_pool_idx < existing_separators.size) {
					var unused_sep = existing_separators.get (sep_pool_idx++);
					disconnect_element (unused_sep);
					unused_sep.Container = null;
					unused_sep.cleanup ();
				}
				return;
			}

			// Step 4b (Classic / Free Mode): Deterministic grouping of [Preferences] | Pinned | [Transient] | [Trash]
			DockElement? preferences_item = null;
			var pinned = new Gee.ArrayList<DockElement> ();
			var transients = new Gee.ArrayList<DockElement> ();
			var orphan_transients = new Gee.ArrayList<TransientDockItem> ();

			for (int i = 0; i < internal_elements.size; i++) {
				var el = internal_elements.get (i);
				if (el is SeparatorDockItem || el is TrashDockItem || el is PinnedExpanderDockItem)
					continue;
				if (el is TransientDockItem) {
					var trans = (TransientDockItem) el;
					var win_count = WindowManager.get_default ().window_count_for_app (trans.Launcher);
					if (win_count <= 0 && !trans.is_running () && dragging_item == null) {
						orphan_transients.add (trans);
						continue;
					}
					if (!Prefs.PinnedOnly)
						transients.add (el);
				} else {
					unowned DockItem? item = el as DockItem;
					if (el is PreferencesDockItem || (item != null && item.Prefs != null && item.Prefs.Launcher == "docklet://preferences")) {
						if (preferences_item == null) {
							preferences_item = el;
							if (!Prefs.AnchorAlwaysLeft)
								pinned.add (el);
						}
					} else {
						pinned.add (el);
					}
				}
			}

			if (Prefs.SystemMenuAccess == 4 && preferences_item == null && dragging_item == null) {
				ensure_preferences_dockitem ();
				preferences_item = item_for_uri ("docklet://preferences");
				if (preferences_item != null && !Prefs.AnchorAlwaysLeft)
					pinned.insert (0, preferences_item);
			}

			foreach (var orphan in orphan_transients) {
				disconnect_element (orphan);
				internal_elements.remove (orphan);
				orphan.Container = null;
				orphan.delete ();
			}

			internal_elements.clear ();
			int sep_pool_idx = 0;

			// 1. Anchor Preferences strictly at index 0 when AnchorAlwaysLeft is enabled
			if (Prefs.AnchorAlwaysLeft && preferences_item != null)
				internal_elements.add (preferences_item);

			// 2. Add separator after Preferences anchor only if there are other items following it
			if (Prefs.AnchorAlwaysLeft && preferences_item != null && (pinned.size > 0 || transients.size > 0)) {
				SeparatorDockItem sep;
				if (sep_pool_idx < existing_separators.size) {
					sep = existing_separators.get (sep_pool_idx++);
				} else {
					sep = new SeparatorDockItem ();
					sep.Container = this;
					connect_element (sep);
				}
				sep.AddTime = 0;
				sep.RemoveTime = 0;
				sep.IsAttached = true;
				internal_elements.add (sep);
			}

			// 3. Add all user pinned items (preserving free-placement sequence)
			foreach (var p in pinned)
				internal_elements.add (p);

			// 4. Core separator between Pinned and Transients (unpinned running apps)
			if (pinned.size > 0 && transients.size > 0) {
				SeparatorDockItem sep;
				if (sep_pool_idx < existing_separators.size) {
					sep = existing_separators.get (sep_pool_idx++);
				} else {
					sep = new SeparatorDockItem ();
					sep.Container = this;
					connect_element (sep);
				}
				sep.AddTime = 0;
				sep.RemoveTime = 0;
				sep.IsAttached = true;
				internal_elements.add (sep);
			}

			// 5. Add unpinned running apps
			foreach (var t in transients)
				internal_elements.add (t);

			// 6. Core separator before Trash
			if (trash_item != null && (pinned.size > 0 || transients.size > 0 || preferences_item != null)) {
				SeparatorDockItem sep;
				if (sep_pool_idx < existing_separators.size) {
					sep = existing_separators.get (sep_pool_idx++);
				} else {
					sep = new SeparatorDockItem ();
					sep.Container = this;
					connect_element (sep);
				}
				sep.AddTime = 0;
				sep.RemoveTime = 0;
				sep.IsAttached = true;
				internal_elements.add (sep);
			}

			// 7. Add Trash at the end
			if (trash_item != null)
				internal_elements.add (trash_item);

			// Clean up any remaining unused separators in the pool to prevent leaks
			while (sep_pool_idx < existing_separators.size) {
				var unused_sep = existing_separators.get (sep_pool_idx++);
				disconnect_element (unused_sep);
				unused_sep.Container = null;
				unused_sep.cleanup ();
			}
		}

		public override void prepare ()
		{
			base.prepare ();

			var favs = new Gee.ArrayList<string> ();

			foreach (var element in internal_elements) {
				unowned ApplicationDockItem? item = (element as ApplicationDockItem);
				if (item != null)
					favs.add (item.Launcher);
			}

			Matcher.get_default ().set_favorites (favs);
		}

		protected override bool is_pinned_only ()
		{
			return Prefs.PinnedOnly;
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
			sync_compositor_windows ();
			update_visible_elements ();

			unowned DockController? dock = get_dock ();
			if (dock != null && dock.renderer != null && dock.renderer.theme != null) {
				dock.refresh_visible_elements ();
				dock.position_manager.update (dock.renderer.theme);
				dock.renderer.reset_buffers ();
				dock.schedule_serialize_item_positions ();
				if (dock.window != null) {
					dock.window.set_input_mask ();
				}
				dock.renderer.animated_draw ();
			}
		}

		protected override void connect_element (DockElement element)
		{
			base.connect_element (element);

			unowned ApplicationDockItem? appitem = (element as ApplicationDockItem);
			if (appitem != null) {
				appitem.pin_launcher.connect (pin_item);
				appitem.Prefs.notify["KeepVisible"].connect (handle_keep_visible_changed);
			}
		}

		protected override void disconnect_element (DockElement element)
		{
			base.disconnect_element (element);

			unowned ApplicationDockItem? appitem = (element as ApplicationDockItem);
			if (appitem != null) {
				appitem.pin_launcher.disconnect (pin_item);
				appitem.Prefs.notify["KeepVisible"].disconnect (handle_keep_visible_changed);
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
					if (item.Prefs.CustomIcon != "")
						new_item.Prefs.CustomIcon = item.Prefs.CustomIcon;
					if (item.Prefs.BrowserProfile != "")
						new_item.Prefs.BrowserProfile = item.Prefs.BrowserProfile;
					replace (new_item, item);
				}
			} else {
				unowned DockController? dock_ctrl = get_dock ();
				if (dock_ctrl != null && dock_ctrl.drag_manager != null && !dock_ctrl.drag_manager.InternalDragActive) {
					resume_items_monitor ();
					dock_ctrl.drag_manager.remove_item_with_effect (item, false, dock_ctrl.position_manager.IconSize);
					return;
				}

				var launcher_uri = item.Launcher;
				var win_count = WindowManager.get_default ().window_count_for_app (item.Launcher);
				bool still_running = (win_count > 0);
				if (internal_elements.contains (item))
					remove (item);
				item.delete ();
				
				// Re-add as a temporary item only if the app has active open windows or running process
				if (still_running) {
					DockElement? trash_target = null;
					foreach (var el in internal_elements) {
						if (el is TrashDockItem) {
							trash_target = el;
							break;
						}
					}
					var new_item = new TransientDockItem.with_launcher (launcher_uri);
					add (new_item, trash_target);
				}
			}

			resume_items_monitor ();
			refresh_separators ();
			unowned DockController? dock = get_dock ();
			if (dock != null)
				dock.schedule_serialize_item_positions ();
		}
	}
}
