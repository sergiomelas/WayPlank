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
	/**
	 * If/How the dock should hide itself.
	 */
	public enum HideType
	{
		/**
		 * The dock remains visible and reserves space through the layer-shell exclusive zone.
		 */
		NONE,
		/**
		 * The dock hides if a window in the active window group overlaps it.
		 */
		INTELLIGENT,
		/**
		 * The dock hides if the mouse is not over it.
		 */
		AUTO,
		/**
		 * The dock hides if there is an active maximized window.
		 */
		DODGE_MAXIMIZED,
		/**
		 * The dock hides if there is any window overlapping it.
		 */
		WINDOW_DODGE,
		/**
		 * The dock hides if there is the active window overlapping it.
		 */
		DODGE_ACTIVE,
	}
	
	/**
	 * Handles checking if a dock should hide or not.
	 */
	public class HideManager : GLib.Object
	{
		// a delay between window changes and updating our data
		// this allows window animations to occur, which might change
		// the results of our update
		const uint UPDATE_TIMEOUT = 200U;
		const uint PRESSURE_REVEAL_TIMEOUT = 50U;
		const int PRESSURE_REVEAL_SIZE = 8;
		
		
		static int plank_pid;
		
		static construct
		{
			plank_pid = getpid ();
		}
		
		public DockController controller { private get; construct; }
		
		/**
		 * If the dock is currently hidden.
		 */
		public bool Hidden { get; private set; default = true; }
		
		/**
		 * If hiding the dock is currently disabled
		 */
		public bool Disabled { get; private set; default = false; }
		
		/**
		 * If the dock is currently hovered by the mouse cursor.
		 */
		public bool Hovered { get; private set; default = false; }
		
		uint hide_timer_id = 0U;
		uint unhide_timer_id = 0U;
		uint prefs_changed_timer_id = 0U;
		uint pressure_reveal_timer_id = 0U;
		bool pressure_reveal_active = false;
		
		bool pointer_update = true;
		bool window_intersect = false;
		bool active_window_intersect = false;
		bool active_application_intersect = false;
		bool active_maximized_window_intersect = false;
		bool dialog_windows_intersect = false;
		
		/**
		 * Creates a new instance of a HideManager, which handles
		 * checking if a dock should hide or not.
		 *
		 * @param controller the {@link DockController} to manage hiding for
		 */
		public HideManager (DockController controller)
		{
			GLib.Object (controller : controller);
		}
		
		construct
		{
			controller.prefs.notify.connect (prefs_changed);
		}
		
		/**
		 * Initializes the hide manager. Call after the DockWindow is constructed.
		 */
		public void initialize ()
			requires (controller.window != null)
		{
			unowned DockWindow window = controller.window;

			window.enter_notify_event.connect (handle_enter_notify_event);
			window.leave_notify_event.connect (handle_leave_notify_event);
			WindowControl.get_default ().state_changed.connect (window_state_changed);
			pressure_reveal_timer_id = Gdk.threads_add_timeout (PRESSURE_REVEAL_TIMEOUT, pressure_reveal_tick);
			update_window_intersect ();
		}

		public void refresh_visibility ()
		{
			update_window_intersect ();
		}
		
		~HideManager ()
		{
			unowned DockWindow window = controller.window;
			
			controller.prefs.notify.disconnect (prefs_changed);
			
			window.enter_notify_event.disconnect (handle_enter_notify_event);
			window.leave_notify_event.disconnect (handle_leave_notify_event);
			WindowControl.get_default ().state_changed.disconnect (window_state_changed);
			if (pressure_reveal_timer_id > 0U) {
				Source.remove (pressure_reveal_timer_id);
				pressure_reveal_timer_id = 0U;
			}
			
			stop_timers ();
		}
		
		/**
		 * Checks to see if the dock is being hovered by the mouse cursor.
		 */
		public void update_hovered ()
		{
			unowned PositionManager position_manager = controller.position_manager;
			unowned DockWindow window = controller.window;
			
			// get current mouse pointer location
			int x = 0, y = 0;
			var seat = window.get_display ().get_default_seat ();
			var pointer = seat != null ? seat.get_pointer () : null;
			if (pointer != null)
				pointer.get_position (null, out x, out y);
			
			// get window location
			var win_rect = position_manager.get_dock_window_region ();
			x -= win_rect.x;
			y -= win_rect.y;
			
			update_hovered_with_coords (x, y);
		}
		
		/**
		 * Checks to see if the dock is being hovered by the mouse cursor.
		 *
		 * @param x the x coordinate of the pointer relative to the dock window
		 * @param y the y coordinate of the pointer relative to the dock window
		 */
		public void update_hovered_with_coords (int x, int y)
		{
			unowned PositionManager position_manager = controller.position_manager;
			unowned DockWindow window = controller.window;
			unowned DragManager drag_manager = controller.drag_manager;
			
			freeze_notify ();
			
			bool update_needed = false;
			
			var dock_rect = position_manager.get_cursor_region ();
			var window_rect = position_manager.get_dock_window_region ();
			var composited = (window.get_screen () != null && window.get_screen ().is_composited ());
			
			// On Wayland/layer-shell the dock can receive pointer events over the full shell window
			// even when the reduced hover region is smaller or translated at the edge. Using the
			// full dock rect here keeps the hover state stable at the bottom edge and while zooming.
			var hovered = (composited)
				? (x >= 0 && x < window_rect.width && y >= 0 && y < window_rect.height)
				: (x >= dock_rect.x && x < dock_rect.x + dock_rect.width
					&& y >= dock_rect.y && y < dock_rect.y + dock_rect.height);
			
			if (Hovered != hovered) {
				Hovered = hovered;
				update_needed = true;
			}
			
			// disable hiding if menu is visible or drags are active
			var disabled = (window.menu_is_visible () || drag_manager.InternalDragActive || drag_manager.ExternalDragActive);
			if (Disabled != disabled) {
				Disabled = disabled;
				update_needed = true;
			}
			
			if (update_needed)
				update_hidden ();
			
			thaw_notify ();
		}
		
		void prefs_changed (Object prefs, ParamSpec prop)
		{
			switch (prop.name) {
			case "HideMode":
			case "Position":
				if (prefs_changed_timer_id > 0U) {
					GLib.Source.remove (prefs_changed_timer_id);
					prefs_changed_timer_id = 0U;
				}
				
				prefs_changed_timer_id = Gdk.threads_add_timeout (UPDATE_TIMEOUT, () => {
					update_window_intersect ();
					prefs_changed_timer_id = 0U;
					return false;
				});
				break;
			case "PressureReveal":
				update_hidden ();
				break;
			default:
				// Nothing important for us changed
				break;
			}
		}
		
		bool pressure_reveal_tick ()
		{
			if (!controller.prefs.PressureReveal || controller.prefs.HideMode == HideType.NONE || !Hidden) {
				if (pressure_reveal_active) {
					pressure_reveal_active = false;
					update_hidden ();
				}
				return true;
			}

			var display = controller.window.get_display ();
			var seat = display != null ? display.get_default_seat () : null;
			var device = seat != null ? seat.get_pointer () : null;
			if (device == null)
				return true;

			int pointer_x, pointer_y;
			device.get_position (null, out pointer_x, out pointer_y);
			var monitor = display.get_monitor_at_point (pointer_x, pointer_y);
			if (monitor == null)
				return true;

			var geometry = monitor.get_geometry ();
			bool at_edge;
			switch (controller.prefs.Position) {
			case Gtk.PositionType.TOP:
				at_edge = pointer_y <= geometry.y + PRESSURE_REVEAL_SIZE;
				break;
			case Gtk.PositionType.LEFT:
				at_edge = pointer_x <= geometry.x + PRESSURE_REVEAL_SIZE;
				break;
			case Gtk.PositionType.RIGHT:
				at_edge = pointer_x >= geometry.x + geometry.width - PRESSURE_REVEAL_SIZE;
				break;
			default:
				at_edge = pointer_y >= geometry.y + geometry.height - PRESSURE_REVEAL_SIZE;
				break;
			}

			if (at_edge != pressure_reveal_active) {
				pressure_reveal_active = at_edge;
				update_hidden ();
			}
			return true;
		}

		void update_hidden ()
		{
			if (Disabled) {
				if (Hidden)
					Hidden = false;
				return;
			}
			
			switch (controller.prefs.HideMode) {
			default:
			case HideType.NONE:
				show ();
				break;
			
			case HideType.INTELLIGENT:
				if (Hovered || pressure_reveal_active || !active_application_intersect)
					show ();
				else
					hide ();
				break;
			
			case HideType.AUTO:
				if (Hovered || pressure_reveal_active)
					show ();
				else
					hide ();
				break;
			
			case HideType.DODGE_MAXIMIZED:
				if (Hovered || pressure_reveal_active || !(active_maximized_window_intersect || dialog_windows_intersect))
					show ();
				else
					hide ();
				break;
			
			case HideType.WINDOW_DODGE:
				if (Hovered || pressure_reveal_active || !window_intersect)
					show ();
				else
					hide ();
				break;
			
			case HideType.DODGE_ACTIVE:
				if (Hovered || pressure_reveal_active || !active_window_intersect)
					show ();
				else
					hide ();
				break;
			}
			pointer_update = true;
		}
		
		void hide ()
		{
			if (unhide_timer_id > 0U) {
				GLib.Source.remove (unhide_timer_id);
				unhide_timer_id = 0U;
			}
			
			if (Hidden)
				return;
			
			if (controller.prefs.HideDelay == 0U) {
				if (!Hidden)
					Hidden = true;
				return;
			}
			
			if (hide_timer_id > 0U)
				return;
			
			hide_timer_id = Gdk.threads_add_timeout (controller.prefs.HideDelay, () => {
				if (!Hidden)
					Hidden = true;
				hide_timer_id = 0U;
				return false;
			});
		}

		void show ()
		{
			if (hide_timer_id > 0U) {
				GLib.Source.remove (hide_timer_id);
				hide_timer_id = 0U;
			}
			
			if (!Hidden)
				return;
			
			if (!pointer_update || controller.prefs.UnhideDelay == 0U) {
				if (Hidden)
					Hidden = false;
				return;
			}
			
			if (unhide_timer_id > 0U)
				return;
			
			unhide_timer_id = Gdk.threads_add_timeout (controller.prefs.UnhideDelay, () => {
				if (Hidden)
					Hidden = false;
				unhide_timer_id = 0U;
				return false;
			});
		}
		
		[CCode (instance_pos = -1)]
		bool handle_enter_notify_event (Gtk.Widget widget, Gdk.EventCrossing event)
		{
			if (event.detail == Gdk.NotifyType.INFERIOR)
				return Hidden;
			
			
			if (!Hovered)
				update_hovered_with_coords ((int) event.x, (int) event.y);
			
			return Hidden;
		}
		
		[CCode (instance_pos = -1)]
		bool handle_leave_notify_event (Gtk.Widget widget, Gdk.EventCrossing event)
		{
			if (event.detail == Gdk.NotifyType.INFERIOR)
				return Gdk.EVENT_PROPAGATE;
			
			// ignore this event if it was sent explicitly
			if ((bool) event.send_event)
				return Gdk.EVENT_PROPAGATE;
			
			if (Hovered)
				update_hovered_with_coords (-1, -1);
			
			return Gdk.EVENT_PROPAGATE;
		}
		
		//
		// intelligent hiding code
		//
		
		void update_window_intersect ()
		{
			var dock_rect = controller.position_manager.get_static_dock_region ();
			window_intersect = WindowControl.any_window_intersects (dock_rect);
			active_application_intersect = WindowControl.active_window_intersects (dock_rect);
			active_window_intersect = active_application_intersect;
			active_maximized_window_intersect = WindowControl.maximized_window_intersects (dock_rect);
			dialog_windows_intersect = false;
			pointer_update = false;
			update_hidden ();
		}

		void window_state_changed ()
		{
			update_window_intersect ();
		}
		
		void stop_timers ()
		{
			if (prefs_changed_timer_id > 0U) {
				GLib.Source.remove (prefs_changed_timer_id);
				prefs_changed_timer_id = 0U;
			}
			
			if (hide_timer_id > 0U) {
				GLib.Source.remove (hide_timer_id);
				hide_timer_id = 0U;
			}
			
			if (unhide_timer_id > 0U) {
				GLib.Source.remove (unhide_timer_id);
				unhide_timer_id = 0U;
			}
		}
		
	}
}
