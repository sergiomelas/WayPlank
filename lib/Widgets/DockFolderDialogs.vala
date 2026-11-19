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
	public class DockFolderDialogs : GLib.Object
	{
		static Gtk.Dialog? active_folder_dialog = null;
		static Gtk.Dialog? active_new_dock_dialog = null;
		static Gtk.Dialog? active_delete_dock_dialog = null;

		static string sanitize_folder_leaf (string raw)
		{
			string s = raw.strip ();
			s = s.replace ("/", "-").replace ("\\", "-");
			while (s.has_prefix ("."))
				s = s.substring (1).strip ();
			return s;
		}

		static GLib.File? resolve_folder_target (string raw_name, string raw_path, out string resolved_display_name)
		{
			string clean_name = raw_name.strip ();
			string leaf = sanitize_folder_leaf (clean_name);
			string clean_path = raw_path.strip ();
			resolved_display_name = clean_name;

			if (clean_path == "") {
				if (leaf == "")
					return null;
				return Paths.AppConfigFolder.get_child ("folders").get_child (leaf);
			}

			string expanded = Hal.Runtime.expand_path_variables (clean_path).strip ();
			if (expanded == "")
				return null;

			GLib.File base_dir;
			if (expanded.has_prefix ("file://"))
				base_dir = File.new_for_uri (expanded);
			else if (Path.is_absolute (expanded))
				base_dir = File.new_for_path (expanded);
			else
				base_dir = Paths.AppConfigFolder.get_child ("folders").get_child (expanded);

			if (leaf == "") {
				string? bn = base_dir.get_basename ();
				resolved_display_name = (bn != null && bn != "") ? bn : _("Folder");
				return base_dir;
			}

			string? base_leaf = base_dir.get_basename ();
			if (base_leaf != null && base_leaf.down () == leaf.down ())
				return base_dir;

			return base_dir.get_child (leaf);
		}

		static void configure_independent_dialog (Gtk.Dialog dlg, string role)
		{
			dlg.set_role (role);
			dlg.set_decorated (true);
			dlg.set_destroy_with_parent (false);
			dlg.set_position (Gtk.WindowPosition.CENTER);
			dlg.window_position = Gtk.WindowPosition.CENTER;
			dlg.set_type_hint (Gdk.WindowTypeHint.DIALOG);
			dlg.set_keep_above (true);
			dlg.set_focus_on_map (true);
		}

		static void restore_preferences_keep_above_if_idle ()
		{
			if (active_folder_dialog == null
				&& active_new_dock_dialog == null
				&& active_delete_dock_dialog == null
				&& PreferencesWindow.active_instance != null) {
				PreferencesWindow.active_instance.set_keep_above (true);
			}
		}

		static void present_dialog_above_preferences (Gtk.Dialog dlg, uint32 event_time = 0)
		{
			if (PreferencesWindow.active_instance != null)
				PreferencesWindow.active_instance.set_keep_above (false);

			dlg.show_all ();
			dlg.deiconify ();
			dlg.set_keep_above (true);

			uint32 time = (event_time != 0) ? event_time : Gtk.get_current_event_time ();
			if (time != 0)
				dlg.present_with_time (time);
			else
				dlg.present ();

			var gdk_win = dlg.get_window ();
			if (gdk_win != null) {
				gdk_win.raise ();
				gdk_win.focus (time != 0 ? time : Gdk.CURRENT_TIME);
			}

			if (!dlg.get_mapped ()) {
				ulong map_handler = 0;
				map_handler = dlg.map.connect (() => {
					if (dlg.get_visible ()) {
						dlg.set_keep_above (true);
						uint32 t = (event_time != 0) ? event_time : Gtk.get_current_event_time ();
						if (t != 0)
							dlg.present_with_time (t);
						else
							dlg.present ();
						var gw = dlg.get_window ();
						if (gw != null) {
							gw.raise ();
							gw.focus (t != 0 ? t : Gdk.CURRENT_TIME);
						}
					}
					if (map_handler != 0) {
						GLib.SignalHandler.disconnect (dlg, map_handler);
						map_handler = 0;
					}
				});
			}
		}

		public static void show_add_folder_dialog (DockController? controller)
		{
			if (controller == null || controller.prefs.LockItems)
				return;

			uint32 click_time = Gtk.get_current_event_time ();
			if (active_folder_dialog != null) {
				present_dialog_above_preferences (active_folder_dialog, click_time);
				return;
			}

			var ctrl_ref = GLib.WeakRef (controller);
			var dlg = new Gtk.Dialog ();
			active_folder_dialog = dlg;
			configure_independent_dialog (dlg, "preferences");
			dlg.set_title ("%s — %s".printf (_("Add Folder"), controller.name));
			dlg.set_default_size (460, -1);

			var cancel_btn = dlg.add_button (_("_Cancel"), Gtk.ResponseType.CANCEL);
			var add_btn = dlg.add_button (_("_Add Folder"), Gtk.ResponseType.ACCEPT) as Gtk.Button;
			if (add_btn != null) {
				add_btn.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				add_btn.set_can_default (true);
				dlg.set_default (add_btn);
			}
			cancel_btn.set_can_focus (true);

			var content = dlg.get_content_area ();
			content.set_spacing (10);
			content.set_margin_start (16);
			content.set_margin_end (16);
			content.set_margin_top (14);
			content.set_margin_bottom (10);

			var grid = new Gtk.Grid ();
			grid.set_row_spacing (10);
			grid.set_column_spacing (10);

			var lbl_name = new Gtk.Label.with_mnemonic (_("Folder _Name:"));
			lbl_name.set_xalign (0.0f);
			var entry_name = new Gtk.Entry ();
			entry_name.set_hexpand (true);
			entry_name.set_activates_default (true);
			entry_name.set_placeholder_text (_("e.g. Work, Tools, Projects"));
			lbl_name.set_mnemonic_widget (entry_name);

			var lbl_path = new Gtk.Label.with_mnemonic (_("Folder _Path:"));
			lbl_path.set_xalign (0.0f);
			var path_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			var entry_path = new Gtk.Entry ();
			entry_path.set_hexpand (true);
			entry_path.set_activates_default (true);
			entry_path.set_placeholder_text (_("Leave empty to create inside WayPlank config"));
			lbl_path.set_mnemonic_widget (entry_path);

			var browse_btn = new Gtk.Button.with_mnemonic (_("_Browse..."));
			path_box.pack_start (entry_path, true, true, 0);
			path_box.pack_end (browse_btn, false, false, 0);

			var lbl_preview = new Gtk.Label ("");
			lbl_preview.set_xalign (0.0f);
			lbl_preview.set_ellipsize (Pango.EllipsizeMode.MIDDLE);
			lbl_preview.set_opacity (0.75);

			grid.attach (lbl_name, 0, 0, 1, 1);
			grid.attach (entry_name, 1, 0, 1, 1);
			grid.attach (lbl_path, 0, 1, 1, 1);
			grid.attach (path_box, 1, 1, 1, 1);
			grid.attach (lbl_preview, 0, 2, 2, 1);
			content.pack_start (grid, true, true, 0);

			entry_name.changed.connect (() => {
				string disp;
				var resolved = resolve_folder_target (entry_name.text, entry_path.text, out disp);
				if (add_btn != null)
					add_btn.sensitive = (resolved != null);
				lbl_preview.set_text (resolved != null
					? "%s %s".printf (_("Target:"), resolved.get_path () ?? resolved.get_uri ())
					: _("Enter a folder name (or select a folder path)."));
			});
			entry_path.changed.connect (() => {
				string disp;
				var resolved = resolve_folder_target (entry_name.text, entry_path.text, out disp);
				if (add_btn != null)
					add_btn.sensitive = (resolved != null);
				lbl_preview.set_text (resolved != null
					? "%s %s".printf (_("Target:"), resolved.get_path () ?? resolved.get_uri ())
					: _("Enter a folder name (or select a folder path)."));
			});

			browse_btn.clicked.connect (() => {
				var chooser = new Gtk.FileChooserDialog (
					_("Select Folder Location"),
					null,
					Gtk.FileChooserAction.SELECT_FOLDER,
					_("_Cancel"), Gtk.ResponseType.CANCEL,
					_("_Select"), Gtk.ResponseType.ACCEPT
				);
				if (chooser.run () == Gtk.ResponseType.ACCEPT) {
					var picked = chooser.get_file ();
					if (picked != null) {
						entry_path.text = picked.get_path () ?? picked.get_uri ();
						if (entry_name.text.strip () == "") {
							string? bn = picked.get_basename ();
							if (bn != null && bn != "")
								entry_name.text = bn;
						}
					}
				}
				chooser.destroy ();
			});

			if (add_btn != null)
				add_btn.sensitive = false;
			lbl_preview.set_text (_("Enter a folder name (or select a folder path)."));

			dlg.response.connect ((resp) => {
				if (resp == Gtk.ResponseType.ACCEPT) {
					var ctrl = ctrl_ref.get () as DockController;
					string disp_name;
					var target = resolve_folder_target (entry_name.text, entry_path.text, out disp_name);
					if (ctrl != null && target != null) {
						unowned DefaultApplicationDockItemProvider? def_prov = ctrl.default_provider as DefaultApplicationDockItemProvider;
						if (def_prov != null)
							def_prov.pin_folder_directory (target, disp_name);
					}
				}
				dlg.destroy ();
			});

			dlg.destroy.connect (() => {
				if (active_folder_dialog == dlg)
					active_folder_dialog = null;
				restore_preferences_keep_above_if_idle ();
			});

			present_dialog_above_preferences (dlg, click_time);
		}

		public static void show_new_dock_dialog (DockController? source_controller)
		{
			if (AbstractMain.app_instance == null || AbstractMain.app_instance.get_dock_count () >= DockPreferences.MAX_DOCK_SLOTS)
				return;

			uint32 click_time = Gtk.get_current_event_time ();
			if (active_new_dock_dialog != null) {
				present_dialog_above_preferences (active_new_dock_dialog, click_time);
				return;
			}

			var dlg = new Gtk.Dialog ();
			active_new_dock_dialog = dlg;
			configure_independent_dialog (dlg, "preferences");
			dlg.set_title (_("Open Dock"));
			dlg.set_default_size (440, -1);

			dlg.add_button (_("_Cancel"), Gtk.ResponseType.CANCEL);
			var create_btn = dlg.add_button (_("_Open Dock"), Gtk.ResponseType.ACCEPT) as Gtk.Button;
			if (create_btn != null) {
				create_btn.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				create_btn.set_can_default (true);
				dlg.set_default (create_btn);
			}

			var content = dlg.get_content_area ();
			content.set_spacing (10);
			content.set_margin_start (16);
			content.set_margin_end (16);
			content.set_margin_top (14);
			content.set_margin_bottom (10);

			var grid = new Gtk.Grid ();
			grid.set_row_spacing (10);
			grid.set_column_spacing (10);

			var lbl_name = new Gtk.Label.with_mnemonic (_("_Dock Slot:"));
			lbl_name.set_xalign (0.0f);
			var cb_dock = new Gtk.ComboBoxText ();
			cb_dock.set_hexpand (true);
			string suggested_name = AbstractMain.app_instance.suggest_next_dock_name ();
			for (int s = 2; s <= DockPreferences.MAX_DOCK_SLOTS; s++) {
				string dname = DockPreferences.dock_name_for_slot (s);
				if (AbstractMain.app_instance.is_dock_running (dname))
					continue;
				bool saved = AbstractMain.app_instance.has_existing_dock_config (dname);
				string label = saved
					? _("Dock %d (%s — saved config)").printf (s, dname)
					: _("Dock %d (%s)").printf (s, dname);
				cb_dock.append (dname, label);
			}
			cb_dock.active_id = suggested_name;
			if (cb_dock.active_id == null)
				cb_dock.set_active (0);
			lbl_name.set_mnemonic_widget (cb_dock);

			var lbl_scr = new Gtk.Label.with_mnemonic (_("_Screen:"));
			lbl_scr.set_xalign (0.0f);
			var cb_scr = new Gtk.ComboBoxText ();
			cb_scr.set_hexpand (true);
			var display = dlg.get_display () ?? Gdk.Display.get_default ();
			string[] scr_labels = (display != null) ? PositionManager.get_logical_screen_labels (display) : new string[0];
			for (int i = 0; i < DockPreferences.MAX_DOCK_SLOTS; i++) {
				string slbl = (i < scr_labels.length)
					? scr_labels[i]
					: _("Screen %d (Multi-seat / Offline)").printf (i + 1);
				cb_scr.append (i.to_string (), slbl);
			}
			lbl_scr.set_mnemonic_widget (cb_scr);

			var lbl_pos = new Gtk.Label.with_mnemonic (_("_Position:"));
			lbl_pos.set_xalign (0.0f);
			var cb_pos = new Gtk.ComboBoxText ();
			cb_pos.set_hexpand (true);
			cb_pos.append (((int) Gtk.PositionType.BOTTOM).to_string (), _("Bottom"));
			cb_pos.append (((int) Gtk.PositionType.TOP).to_string (), _("Top"));
			cb_pos.append (((int) Gtk.PositionType.LEFT).to_string (), _("Left"));
			cb_pos.append (((int) Gtk.PositionType.RIGHT).to_string (), _("Right"));
			lbl_pos.set_mnemonic_widget (cb_pos);

			var lbl_status = new Gtk.Label ("");
			lbl_status.set_xalign (0.0f);
			lbl_status.set_line_wrap (true);
			lbl_status.set_max_width_chars (52);
			lbl_status.set_opacity (0.80);

			grid.attach (lbl_name, 0, 0, 1, 1);
			grid.attach (cb_dock, 1, 0, 1, 1);
			grid.attach (lbl_scr, 0, 1, 1, 1);
			grid.attach (cb_scr, 1, 1, 1, 1);
			grid.attach (lbl_pos, 0, 2, 1, 1);
			grid.attach (cb_pos, 1, 2, 1, 1);
			grid.attach (lbl_status, 0, 3, 2, 1);
			content.pack_start (grid, true, true, 0);

			apply_slot_defaults_to_dialog (cb_dock, cb_scr, cb_pos);

			var scr_ref = GLib.WeakRef (cb_scr);
			var pos_ref = GLib.WeakRef (cb_pos);
			foreach (unowned Gtk.CellRenderer renderer in cb_pos.get_cells ()) {
				cb_pos.set_cell_data_func (renderer, (layout, cell, model, iter) => {
					var scr_w = scr_ref.get () as Gtk.ComboBoxText;
					string? base_text = null;
					string? id = null;
					model.get (iter, 0, out base_text, 1, out id);
					if (scr_w == null || id == null || id == "" || AbstractMain.app_instance == null) {
						cell.sensitive = true;
						if (cell is Gtk.CellRendererText && base_text != null)
							((Gtk.CellRendererText) cell).text = base_text;
						return;
					}
					int cur_s = (scr_w.active_id != null) ? int.parse (scr_w.active_id) : 0;
					var cand_p = (Gtk.PositionType) int.parse (id);
					var occupier = AbstractMain.app_instance.find_dock_at_placement (cur_s, cand_p);
					cell.sensitive = (occupier == null);
					if (cell is Gtk.CellRendererText) {
						string clean = base_text ?? "";
						string dname = (occupier != null && occupier.name != null && occupier.name.length > 0)
							? (occupier.name.substring (0, 1).up () + occupier.name.substring (1))
							: "";
						((Gtk.CellRendererText) cell).text = (occupier != null)
							? "%s (%s)".printf (clean, dname)
							: clean;
					}
				});
			}
			foreach (unowned Gtk.CellRenderer renderer in cb_scr.get_cells ()) {
				cb_scr.set_cell_data_func (renderer, (layout, cell, model, iter) => {
					var pos_w = pos_ref.get () as Gtk.ComboBoxText;
					string? base_text = null;
					string? id = null;
					model.get (iter, 0, out base_text, 1, out id);
					if (pos_w == null || id == null || id == "" || AbstractMain.app_instance == null) {
						cell.sensitive = true;
						if (cell is Gtk.CellRendererText && base_text != null)
							((Gtk.CellRendererText) cell).text = base_text;
						return;
					}
					int cand_s = int.parse (id);
					var cur_p = (Gtk.PositionType) ((pos_w.active_id != null) ? int.parse (pos_w.active_id) : (int) Gtk.PositionType.TOP);
					var occupier = AbstractMain.app_instance.find_dock_at_placement (cand_s, cur_p);
					cell.sensitive = (occupier == null);
					if (cell is Gtk.CellRendererText) {
						string clean = base_text ?? "";
						string dname = (occupier != null && occupier.name != null && occupier.name.length > 0)
							? (occupier.name.substring (0, 1).up () + occupier.name.substring (1))
							: "";
						((Gtk.CellRendererText) cell).text = (occupier != null)
							? "%s (%s)".printf (clean, dname)
							: clean;
					}
				});
			}

			update_new_dock_dialog_state (cb_dock, cb_scr, cb_pos, lbl_status, create_btn);

			cb_dock.changed.connect (() => {
				apply_slot_defaults_to_dialog (cb_dock, cb_scr, cb_pos);
				update_new_dock_dialog_state (cb_dock, cb_scr, cb_pos, lbl_status, create_btn);
				cb_scr.queue_draw ();
				cb_pos.queue_draw ();
			});
			cb_scr.changed.connect (() => {
				update_new_dock_dialog_state (cb_dock, cb_scr, cb_pos, lbl_status, create_btn);
				cb_pos.queue_draw ();
			});
			cb_pos.changed.connect (() => {
				update_new_dock_dialog_state (cb_dock, cb_scr, cb_pos, lbl_status, create_btn);
				cb_scr.queue_draw ();
			});

			dlg.response.connect ((resp) => {
				if (resp == Gtk.ResponseType.ACCEPT && AbstractMain.app_instance != null) {
					string sel_dock = cb_dock.active_id ?? "dock2";
					int scr_id = (cb_scr.active_id != null) ? int.parse (cb_scr.active_id) : 0;
					int pos_id = (cb_pos.active_id != null) ? int.parse (cb_pos.active_id) : (int) Gtk.PositionType.TOP;
					AbstractMain.app_instance.create_or_launch_dock (sel_dock, (Gtk.PositionType) pos_id, scr_id);
				}
				dlg.destroy ();
			});

			dlg.destroy.connect (() => {
				if (active_new_dock_dialog == dlg)
					active_new_dock_dialog = null;
				restore_preferences_keep_above_if_idle ();
			});

			present_dialog_above_preferences (dlg, click_time);
		}

		static void apply_slot_defaults_to_dialog (Gtk.ComboBoxText cb_dock, Gtk.ComboBoxText cb_scr, Gtk.ComboBoxText cb_pos)
		{
			if (AbstractMain.app_instance == null)
				return;
			string sel_dock = cb_dock.active_id ?? "dock2";
			int slot = DockPreferences.slot_index_for_dock_name (sel_dock);
			if (slot >= 2 && DockPreferences.has_slot_saved_config (slot)) {
				int saved_scr = int.max (0, DockPreferences.get_slot_screen (slot));
				int saved_pos = DockPreferences.get_slot_position (slot);
				cb_scr.active_id = saved_scr.to_string ();
				cb_pos.active_id = saved_pos.to_string ();
				return;
			}
			int free_scr;
			Gtk.PositionType free_pos;
			AbstractMain.app_instance.suggest_free_placement (out free_scr, out free_pos);
			cb_scr.active_id = free_scr.to_string ();
			cb_pos.active_id = ((int) free_pos).to_string ();
		}

		static void update_new_dock_dialog_state (Gtk.ComboBoxText cb_dock, Gtk.ComboBoxText cb_scr, Gtk.ComboBoxText cb_pos, Gtk.Label lbl_status, Gtk.Button? create_btn)
		{
			if (AbstractMain.app_instance == null)
				return;

			string sel_dock = cb_dock.active_id ?? "";
			if (sel_dock == "") {
				if (create_btn != null)
					create_btn.sensitive = false;
				lbl_status.set_text (_("Maximum number of docks (4) already active."));
				return;
			}

			int scr_id = (cb_scr.active_id != null) ? int.parse (cb_scr.active_id) : 0;
			int pos_id = (cb_pos.active_id != null) ? int.parse (cb_pos.active_id) : (int) Gtk.PositionType.TOP;
			if (AbstractMain.app_instance.is_placement_used (scr_id, (Gtk.PositionType) pos_id)) {
				if (create_btn != null)
					create_btn.sensitive = false;
				lbl_status.set_text (_("Another active dock already uses this Screen and Position."));
				return;
			}

			if (create_btn != null)
				create_btn.sensitive = true;

			bool has_cfg = AbstractMain.app_instance.has_existing_dock_config (sel_dock);
			if (has_cfg)
				lbl_status.set_text (_("Saved configuration found for '%s' — will re-open with all pinned items intact.").printf (sel_dock));
			else
				lbl_status.set_text (_("Will launch '%s' immediately without repeating onboarding.").printf (sel_dock));
		}

		public static void confirm_and_delete_dock (DockController? controller)
		{
			if (controller == null || controller.name == "dock1" || AbstractMain.app_instance == null || AbstractMain.app_instance.get_dock_count () <= 1)
				return;

			uint32 click_time = Gtk.get_current_event_time ();
			if (active_delete_dock_dialog != null) {
				present_dialog_above_preferences (active_delete_dock_dialog, click_time);
				return;
			}

			var ctrl_ref = GLib.WeakRef (controller);
			var dlg = new Gtk.MessageDialog (
				null,
				0,
				Gtk.MessageType.WARNING,
				Gtk.ButtonsType.NONE,
				"%s",
				_("Delete dock '%s'?").printf (controller.name)
			);
			active_delete_dock_dialog = dlg;
			configure_independent_dialog (dlg, "help");
			dlg.set_title (_("Delete Dock"));
			dlg.secondary_text = _("This will close '%s' and permanently remove its configuration and pinned item list.").printf (controller.name);

			dlg.add_button (_("_Cancel"), Gtk.ResponseType.CANCEL);
			var del_btn = dlg.add_button (_("_Delete Dock"), Gtk.ResponseType.ACCEPT) as Gtk.Button;
			if (del_btn != null)
				del_btn.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);

			dlg.response.connect ((resp) => {
				if (resp == Gtk.ResponseType.ACCEPT && AbstractMain.app_instance != null) {
					var target = ctrl_ref.get () as DockController;
					if (target != null)
						AbstractMain.app_instance.delete_dock (target);
				}
				dlg.destroy ();
			});

			dlg.destroy.connect (() => {
				if (active_delete_dock_dialog == dlg)
					active_delete_dock_dialog = null;
				restore_preferences_keep_above_if_idle ();
			});

			present_dialog_above_preferences (dlg, click_time);
		}
	}
}
