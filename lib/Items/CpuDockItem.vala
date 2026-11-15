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
	public class CpuDockItem : DockItem
	{
		uint timer_id = 0;
		int cpu_pct = 0;
		int ram_pct = 0;
		int io_pct = 0;
		int system_pressure = 0;
		double ram_used_gb = 0.0;
		double ram_total_gb = 0.0;

		public CpuDockItem ()
		{
			GLib.Object (Prefs: new DockItemPreferences ());
		}

		public CpuDockItem.with_dockitem_file (GLib.File file)
		{
			GLib.Object (Prefs: new DockItemPreferences.with_file (file));
		}

		construct
		{
			Text = _("System Monitor");
			Icon = "utilities-system-monitor";
			Button = PopupButton.RIGHT;

			update_stats ();
			notify["IsAttached"].connect (on_attached_changed);
			start_timer ();
		}

		private bool cleaned_up = false;

		~CpuDockItem ()
		{
			if (!cleaned_up) {
				cleaned_up = true;
				notify["IsAttached"].disconnect (on_attached_changed);
			}
			stop_timer ();
		}

		public override void cleanup ()
		{
			if (!cleaned_up) {
				cleaned_up = true;
				notify["IsAttached"].disconnect (on_attached_changed);
			}
			stop_timer ();
			base.cleanup ();
		}

		void on_attached_changed ()
		{
			if (IsAttached)
				update_stats ();
		}

		void start_timer ()
		{
			if (timer_id != 0)
				return;

			timer_id = Timeout.add (1500, on_timer_tick);
		}

		void stop_timer ()
		{
			if (timer_id != 0) {
				Source.remove (timer_id);
				timer_id = 0;
			}
		}

		public override bool is_valid ()
		{
			return true;
		}

		public override void @delete ()
		{
			stop_timer ();
			base.@delete ();
		}

		void update_stats ()
		{
			var s = Hal.Telemetry.CpuMemory.sample ();
			cpu_pct = s.cpu_pct;
			ram_pct = s.ram_pct;
			io_pct = s.io_pct;
			system_pressure = s.system_pressure;
			ram_used_gb = s.ram_used_gb;
			ram_total_gb = s.ram_total_gb;

			Count = 1;
			BadgeText = "%d%%".printf (system_pressure);
			CountVisible = true;

			Text = _("System: %d%% | CPU: %d%% | RAM: %d%% (%.1f / %.1f GB) | Disk: %d%%").printf (
				system_pressure, cpu_pct, ram_pct, ram_used_gb, ram_total_gb, io_pct);
		}

		bool on_timer_tick ()
		{
			if (!IsAttached)
				return true;
			update_stats ();
			return true;
		}

		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			if (button == PopupButton.LEFT) {
				if (Hal.Runtime.open_system_utility (DesktopUtilityKind.SYSTEM_MONITOR))
					return AnimationType.BOUNCE;
			}

			return AnimationType.NONE;
		}

		public override Gee.ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new Gee.ArrayList<Gtk.MenuItem> ();

			var header_item = new Gtk.MenuItem.with_label (Text);
			header_item.sensitive = false;
			items.add (header_item);

			items.add (new Gtk.SeparatorMenuItem ());

			var mon_item = create_menu_item (_("_System Monitor..."), "utilities-system-monitor", true);
			mon_item.activate.connect (() => {
				on_clicked (PopupButton.LEFT, 0, 0);
			});
			items.add (mon_item);

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
