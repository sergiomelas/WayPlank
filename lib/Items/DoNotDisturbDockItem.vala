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
	public class DoNotDisturbDockItem : DockItem
	{
		const string ICON_ACTIVE = "preferences-desktop-notification-bell;;notifications;;preferences-system-notifications;;notification-symbolic";
		const string ICON_MUTED = "notifications-disabled;;notifications-disabled-symbolic;;notification-disabled";

		private bool is_dnd_active = false;
		private ulong dnd_signal_id = 0;
		private uint poll_timer_id = 0;
		private bool is_disposed = false;
		private bool poll_in_flight = false;
		private int state_generation = 0;

		public DoNotDisturbDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public DoNotDisturbDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("Do Not Disturb");
			Icon = ICON_ACTIVE;
			Button = PopupButton.RIGHT;

			dnd_signal_id = Hal.Bus.Notifications.dnd_state_changed.connect ((inhibited) => {
				if (!is_disposed)
					set_dnd_state (inhibited);
			});

			notify["IsAttached"].connect (on_attached_changed);
			schedule_dnd_poll ();
			if (!Hal.Bus.Notifications.has_instant_dnd_settings ()
				&& !Hal.Bus.Notifications.has_push_dnd_subscription ()) {
				start_timer ();
			}
		}

		void on_attached_changed ()
		{
			if (IsAttached && !Hal.Bus.Notifications.has_instant_dnd_settings ())
				schedule_dnd_poll ();
		}

		private bool cleaned_up = false;

		private void stop_dnd_resources ()
		{
			if (cleaned_up)
				return;
			cleaned_up = true;
			is_disposed = true;
			notify["IsAttached"].disconnect (on_attached_changed);
			stop_timer ();
			disconnect_dnd_signal ();
		}

		~DoNotDisturbDockItem ()
		{
			stop_dnd_resources ();
		}

		public override void cleanup ()
		{
			stop_dnd_resources ();
			base.cleanup ();
		}

		public override void @delete ()
		{
			stop_dnd_resources ();
			base.@delete ();
		}

		private void disconnect_dnd_signal ()
		{
			if (dnd_signal_id != 0) {
				Hal.Bus.Notifications.disconnect (dnd_signal_id);
				dnd_signal_id = 0;
			}
		}

		private void start_timer ()
		{
			if (poll_timer_id == 0) {
				poll_timer_id = Timeout.add_seconds (5, () => {
					if (!IsAttached)
						return true;
					schedule_dnd_poll ();
					return true;
				});
			}
		}

		private void stop_timer ()
		{
			if (poll_timer_id > 0) {
				Source.remove (poll_timer_id);
				poll_timer_id = 0;
			}
		}

		public override bool is_valid ()
		{
			return true;
		}

		private void set_dnd_state (bool active)
		{
			if (is_dnd_active != active || Icon == "") {
				is_dnd_active = active;
				Icon = is_dnd_active ? ICON_MUTED : ICON_ACTIVE;
				Text = is_dnd_active ? _("Notifications: Silenced (Do Not Disturb)") : _("Notifications: Active");
			}
		}

		private static void spawn_dnd_poll_worker (DoNotDisturbDockItem target, int gen_snap)
		{
			GLib.WeakRef self_ref = GLib.WeakRef (target);

			new Thread<void*> ("wayplank-dnd-poll", () => {
				bool active = Hal.Bus.Notifications.probe_dnd_inhibited_sync ();
				Idle.add (() => {
					var self = (DoNotDisturbDockItem?) self_ref.get ();
					if (self == null)
						return false;
					self.poll_in_flight = false;
					if (self.is_disposed || gen_snap != self.state_generation)
						return false;
					self.set_dnd_state (active);
					return false;
				});
				return null;
			});
		}

		private void schedule_dnd_poll ()
		{
			if (is_disposed)
				return;
			if (Hal.Bus.Notifications.has_instant_dnd_settings ()) {
				set_dnd_state (Hal.Bus.Notifications.get_instant_dnd_inhibited ());
				return;
			}
			if (poll_in_flight)
				return;
			poll_in_flight = true;
			int gen_snap = state_generation;

			spawn_dnd_poll_worker (this, gen_snap);
		}

		public void toggle_dnd ()
		{
			if (is_dnd_active)
				uninhibit ();
			else
				inhibit ();
		}

		public void inhibit ()
		{
			state_generation++;
			Hal.Bus.Notifications.inhibit_dnd ();
		}

		public void uninhibit ()
		{
			state_generation++;
			Hal.Bus.Notifications.uninhibit_dnd ();
		}

		public void open_settings ()
		{
			Hal.Runtime.open_system_utility (DesktopUtilityKind.NOTIFICATION_SETTINGS);
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				toggle_dnd ();
				return AnimationType.NONE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var header_item = new Gtk.MenuItem.with_label (_("Do Not Disturb"));
			header_item.sensitive = false;
			items.add (header_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var toggle_item = create_menu_item (
				is_dnd_active ? _("Resume Notifications") : _("Silence Notifications"),
				is_dnd_active ? "notifications" : "notifications-disabled",
				true
			);
			toggle_item.activate.connect (toggle_dnd);
			items.add (toggle_item);

			var settings_item = create_menu_item (_("_Notification Settings..."), "preferences-system-notifications", true);
			settings_item.activate.connect (open_settings);
			items.add (settings_item);

			if (!is_dock_locked ()) {
				items.add (new Gtk.SeparatorMenuItem ());

				var remove_item = create_menu_item (_("_Remove from Dock"), "edit-delete", true);
				remove_item.activate.connect (() => {
					this.@delete ();
				});
				items.add (remove_item);
			}

			return items;
		}
	}
}
