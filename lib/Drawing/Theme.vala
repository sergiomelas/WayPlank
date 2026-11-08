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
	/**
	 * A themed renderer for windows.
	 */
	public abstract class Theme : Preferences
	{
		public const string DEFAULT_NAME = "Default";
		public const string GTK_THEME_NAME = "Gtk+";
		
		public static Gtk.StyleContext create_style_context (GLib.Type widget_type, Gtk.StyleContext? parent_style,
			Gtk.CssProvider provider, string? object_name, string first_class, ...)
		{
			Gtk.WidgetPath path;

			var style = new Gtk.StyleContext ();
			//FIXME
			//style.set_scale (get_window_scaling_factor ());
			style.set_parent (parent_style);

			if (parent_style != null)
				path = parent_style.get_path ().copy ();
			else
				path = new Gtk.WidgetPath ();

			path.append_type (widget_type);

			if (object_name != null)
				PlankCompat.gtk_widget_path_iter_set_object_name (path, -1, object_name);

			path.iter_add_class (-1, first_class);
			var name_list = va_list ();
			for (unowned string? name = name_list.arg<unowned string> (); name != null; name = name_list.arg<unowned string> ())
				path.iter_add_class (-1, name);

			style.set_path (path);
			style.add_provider (provider, Gtk.STYLE_PROVIDER_PRIORITY_SETTINGS);

			return style;
		}
		
		[Description(nick = "top-roundness", blurb = "The roundness of the top corners.")]
		public int TopRoundness { get; set; }
		
		[Description(nick = "bottom-roundness", blurb = "The roundness of the bottom corners.")]
		public int BottomRoundness { get; set; }
		
		[Description(nick = "reverse-roundness", blurb = "The concave flare roundness touching the screen bottom edge.")]
		public int ReverseRoundness { get; set; }
		
		[Description(nick = "line-width", blurb = "The thickness (in pixels) of lines drawn.")]
		public int LineWidth { get; set; }
		
		[Description(nick = "outer-stroke-color", blurb = "The color (RGBA) of the outer stroke.")]
		public Color OuterStrokeColor { get; set; }
		
		[Description(nick = "fill-start-color", blurb = "The starting color (RGBA) of the fill gradient.")]
		public Color FillStartColor { get; set; }
		
		[Description(nick = "fill-end-color", blurb = "The ending color (RGBA) of the fill gradient.")]
		public Color FillEndColor { get; set; }
		
		[Description(nick = "inner-stroke-color", blurb = "The color (RGBA) of the inner stroke.")]
		public Color InnerStrokeColor { get; set; }
		
		File? theme_folder;
		Gtk.StyleContext style_context;
		string theme_name;
		
		public string get_theme_name ()
		{
			return theme_name;
		}
		
		protected Theme ()
		{
			theme_name = DEFAULT_NAME;
			theme_folder = get_theme_folder (DEFAULT_NAME);
		}
		
		protected Theme.with_name (string name)
		{
			theme_name = name;
			theme_folder = get_theme_folder (name);
		}
		
		construct
		{
			unowned Gtk.Settings gtk_settings = Gtk.Settings.get_default ();
			
			var gtk_theme = gtk_settings.gtk_theme_name;
			update_style_context (gtk_theme);
			
			gtk_settings.notify["gtk-theme-name"].connect (gtk_theme_name_changed);
			gtk_settings.notify["gtk-application-prefer-dark-theme"].connect (gtk_theme_name_changed);
		}

		~Theme ()
		{
			unowned Gtk.Settings? gtk_settings = Gtk.Settings.get_default ();
			if (gtk_settings != null) {
				gtk_settings.notify["gtk-theme-name"].disconnect (gtk_theme_name_changed);
				gtk_settings.notify["gtk-application-prefer-dark-theme"].disconnect (gtk_theme_name_changed);
			}
		}
		
		void update_style_context (string? gtk_theme)
		{
			Gtk.CssProvider provider;
			if (gtk_theme != null)
				provider = Gtk.CssProvider.get_named (gtk_theme, null);
			else
				provider = Gtk.CssProvider.get_named (GTK_THEME_NAME, null);
			
			style_context = Theme.create_style_context (typeof (Gtk.IconView), null, provider,
				"iconview", Gtk.STYLE_CLASS_VIEW);
			
			style_context.set_state (Gtk.StateFlags.FOCUSED | Gtk.StateFlags.SELECTED);
		}
		
		void gtk_theme_name_changed (Object o, ParamSpec p)
		{
			var gtk_theme = ((Gtk.Settings) o).gtk_theme_name;
			update_style_context (gtk_theme);
			if (theme_name == GTK_THEME_NAME && theme_folder == null)
				apply_dynamic_gtk_theme ();
			
			notify (new ParamSpecBoolean ("theme-changed", "theme-changed", "theme-changed", true, ParamFlags.READABLE));
		}
		
		public unowned Gtk.StyleContext get_style_context ()
		{
			return style_context;
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override void reset_properties ()
		{
			TopRoundness     = 6;
			BottomRoundness  = 6;
			ReverseRoundness = 0;
			
			LineWidth = 1;
			
			OuterStrokeColor = { 0.1647, 0.1647, 0.1647, 1.0 };
			FillStartColor   = { 0.1647, 0.1647, 0.1647, 1.0 };
			FillEndColor     = { 0.3176, 0.3176, 0.3176, 1.0 };
			InnerStrokeColor = { 1.0, 1.0, 1.0, 1.0 };
		}

		/**
		 * Dynamically derives translucent dock styling and palette from the active GTK theme.
		 */
		protected virtual void apply_dynamic_gtk_theme ()
		{
			Gdk.RGBA bg_rgba = { 0.18, 0.18, 0.20, 1.0 };
			Gdk.RGBA fg_rgba = { 0.95, 0.95, 0.95, 1.0 };
			Gdk.RGBA border_rgba = { 0.30, 0.30, 0.30, 1.0 };
			
			bool has_bg = style_context.lookup_color ("theme_bg_color", out bg_rgba);
			if (!has_bg)
				has_bg = style_context.lookup_color ("window_bg_color", out bg_rgba);
			if (!has_bg)
				has_bg = style_context.lookup_color ("theme_base_color", out bg_rgba);
				
			style_context.lookup_color ("theme_fg_color", out fg_rgba);
			if (!style_context.lookup_color ("borders", out border_rgba))
				style_context.lookup_color ("theme_border_color", out border_rgba);

			// Determine dark vs light mode via FreeDesktop Settings Portal, falling back to luminance
			bool is_dark = SystemTheme.get_default ().is_dark;

			LineWidth = 1;
			TopRoundness = 6;
			BottomRoundness = 0;

			if (is_dark) {
				// Modern dark translucent theme harmonizing with GTK Dark Mode
				double r = bg_rgba.red < 0.5 ? bg_rgba.red : 0.18;
				double g = bg_rgba.green < 0.5 ? bg_rgba.green : 0.18;
				double b = bg_rgba.blue < 0.5 ? bg_rgba.blue : 0.20;
				
				FillStartColor = {
					(r + 0.05).clamp (0.0, 1.0),
					(g + 0.05).clamp (0.0, 1.0),
					(b + 0.05).clamp (0.0, 1.0),
					0.78
				};
				FillEndColor = {
					(r * 0.85).clamp (0.0, 1.0),
					(g * 0.85).clamp (0.0, 1.0),
					(b * 0.85).clamp (0.0, 1.0),
					0.85
				};
				OuterStrokeColor = { 0.05, 0.05, 0.05, 0.60 };
				InnerStrokeColor = { 1.0, 1.0, 1.0, 0.18 };
			} else {
				// Clean, elegant light translucent theme harmonizing with GTK Light Mode
				double r = bg_rgba.red > 0.5 ? bg_rgba.red : 0.94;
				double g = bg_rgba.green > 0.5 ? bg_rgba.green : 0.94;
				double b = bg_rgba.blue > 0.5 ? bg_rgba.blue : 0.96;
				
				FillStartColor = {
					(r + 0.02).clamp (0.0, 1.0),
					(g + 0.02).clamp (0.0, 1.0),
					(b + 0.02).clamp (0.0, 1.0),
					0.82
				};
				FillEndColor = {
					(r * 0.92).clamp (0.0, 1.0),
					(g * 0.92).clamp (0.0, 1.0),
					(b * 0.92).clamp (0.0, 1.0),
					0.88
				};
				OuterStrokeColor = {
					0.5, 0.5, 0.5, 0.45
				};
				InnerStrokeColor = { 1.0, 1.0, 1.0, 0.75 };
			}
		}
		
		/**
		 * Loads a theme for the renderer to use.
		 *
		 * @param type the type of theme to load
		 */
		public void load (string type)
		{
			if (theme_name == DEFAULT_NAME || theme_name == GTK_THEME_NAME) {
				reset_properties ();
				apply_dynamic_gtk_theme ();
				return;
			}

			// 1. User-installed or external filesystem theme overrides
			if (theme_folder != null) {
				var theme_file = theme_folder.get_child ("%s.theme".printf (type));
				if (theme_file.query_exists ()) {
					reset_properties ();
					init_from_file (theme_file);
					return;
				}
			}

			// 2. Monolithic built-in theme embedded in GResource RAM
			if (is_embedded_theme (theme_name, type)) {
				reset_properties ();
				if (init_from_resource ("/net/launchpad/plank/themes/%s/%s.theme".printf (theme_name, type)))
					return;
			}

			// 3. Fallback to internal dynamic adaptive GTK theme
			reset_properties ();
			apply_dynamic_gtk_theme ();
		}
		
		/**
		 * Returns the top offset.
		 *
		 * @return the top offset
		 */
		public int get_top_offset ()
		{
			return 2 * LineWidth;
		}
		
		/**
		 * Returns the bottom offset.
		 *
		 * @return the bottom offset
		 */
		public int get_bottom_offset ()
		{
			return BottomRoundness > 0 ? 2 * LineWidth : 0;
		}
		
		/**
		 * Draws a background onto the surface.
		 *
		 * @param surface the surface to draw on
		 */
		public void draw_background (Surface surface)
		{
			unowned Cairo.Context cr = surface.Context;
			Cairo.Pattern gradient;
			var width = surface.Width;
			var height = surface.Height;
			
			cr.save ();
			
			gradient = new Cairo.Pattern.linear (0, 0, 0, height);
			gradient.add_color_stop_rgba (0, FillStartColor.red, FillStartColor.green, FillStartColor.blue, FillStartColor.alpha);
			gradient.add_color_stop_rgba (1, FillEndColor.red, FillEndColor.green, FillEndColor.blue, FillEndColor.alpha);
			
			cr.set_source (gradient);

			if (ReverseRoundness > 0 && BottomRoundness == 0) {
				draw_reverse_fillet_dock (cr,
					LineWidth / 2.0,
					LineWidth / 2.0,
					width - LineWidth,
					height - LineWidth / 2.0,
					TopRoundness,
					ReverseRoundness,
					LineWidth);
				cr.fill_preserve ();
				
				cr.set_source_rgba (OuterStrokeColor.red, OuterStrokeColor.green, OuterStrokeColor.blue, OuterStrokeColor.alpha);
				cr.set_line_width (LineWidth);
				cr.stroke ();
				
				var bevel_gradient = new Cairo.Pattern.linear (0, 0, 0, height);
				bevel_gradient.add_color_stop_rgba (0.0, InnerStrokeColor.red, InnerStrokeColor.green, InnerStrokeColor.blue, 0.35);
				bevel_gradient.add_color_stop_rgba (0.4, InnerStrokeColor.red, InnerStrokeColor.green, InnerStrokeColor.blue, 0.10);
				bevel_gradient.add_color_stop_rgba (1.0, InnerStrokeColor.red, InnerStrokeColor.green, InnerStrokeColor.blue, 0.0);
				cr.set_source (bevel_gradient);
				draw_reverse_fillet_bevel (cr,
					LineWidth * 1.5,
					LineWidth * 1.5,
					width - LineWidth * 3.0,
					height - LineWidth * 1.5,
					TopRoundness - LineWidth,
					ReverseRoundness,
					LineWidth);
			} else {
				var bottom_offset = BottomRoundness > 0 ? LineWidth : -LineWidth;
				draw_rounded_rect (cr,
					LineWidth / 2.0,
					LineWidth / 2.0,
					width - LineWidth,
					height - LineWidth / 2.0 - bottom_offset / 2.0,
					TopRoundness,
					BottomRoundness,
					LineWidth);
				cr.fill_preserve ();
				
				cr.set_source_rgba (OuterStrokeColor.red, OuterStrokeColor.green, OuterStrokeColor.blue, OuterStrokeColor.alpha);
				cr.set_line_width (LineWidth);
				cr.stroke ();
				
				gradient = new Cairo.Pattern.linear (0, 2 * LineWidth, 0, height - 2 * LineWidth - bottom_offset);
				gradient.add_color_stop_rgba (0, InnerStrokeColor.red, InnerStrokeColor.green, InnerStrokeColor.blue, 0.5);
				gradient.add_color_stop_rgba ((TopRoundness > 0 ? TopRoundness : LineWidth) / (double) height, InnerStrokeColor.red, InnerStrokeColor.green, InnerStrokeColor.blue, 0.12);
				gradient.add_color_stop_rgba (1 - (BottomRoundness > 0 ? BottomRoundness : LineWidth) / (double) height, InnerStrokeColor.red, InnerStrokeColor.green, InnerStrokeColor.blue, 0.08);
				gradient.add_color_stop_rgba (1, InnerStrokeColor.red, InnerStrokeColor.green, InnerStrokeColor.blue, 0.19);
				
				cr.set_source (gradient);
				draw_inner_rect (cr, width, height);
				cr.stroke ();
			}
			
			cr.restore ();
		}

		public static void draw_reverse_fillet_dock (Cairo.Context cr, double x, double y, double width, double height, double top_radius = 19.0, double rev_radius = 26.0, double line_width = 1.0)
		{
			var min_size = double.min (width, height);
			top_radius = top_radius.clamp (0.0, min_size / 2.0);
			rev_radius = rev_radius.clamp (0.0, double.min (width / 3.0, double.max (0.0, height - top_radius)));

			if (!Gdk.Screen.get_default ().is_composited ()) {
				draw_rounded_rect (cr, x, y, width, height, 0.0, 0.0, line_width);
				return;
			}

			// 1. Bottom-left flared tip touching the screen bottom
			cr.move_to (x, y + height);

			// 2. Concave arc: from (x, y+height) flaring up-right to meet vertical wall at (x+rev_radius, y+height-rev_radius)
			if (rev_radius > 0.0) {
				cr.arc_negative (x, y + height - rev_radius, rev_radius, Math.PI_2, 0.0);
			} else {
				cr.line_to (x, y + height);
			}

			// 3. Vertical left wall up to top-left corner
			cr.line_to (x + rev_radius, y + top_radius);

			// 4. Convex top-left corner
			if (top_radius > 0.0) {
				cr.arc (x + rev_radius + top_radius, y + top_radius, top_radius, Math.PI, Math.PI + Math.PI_2);
			}

			// 5. Horizontal top wall across to top-right corner
			cr.line_to (x + width - rev_radius - top_radius, y);

			// 6. Convex top-right corner
			if (top_radius > 0.0) {
				cr.arc (x + width - rev_radius - top_radius, y + top_radius, top_radius, -Math.PI_2, 0.0);
			}

			// 7. Vertical right wall down to bottom-right flare
			cr.line_to (x + width - rev_radius, y + height - rev_radius);

			// 8. Concave arc: from (x+width-rev_radius, y+height-rev_radius) flaring down-right to (x+width, y+height)
			if (rev_radius > 0.0) {
				cr.arc_negative (x + width, y + height - rev_radius, rev_radius, Math.PI, Math.PI_2);
			} else {
				cr.line_to (x + width, y + height);
			}

			// 9. Close along bottom edge touching the screen
			cr.line_to (x, y + height);
			cr.close_path ();
		}

		public static void draw_reverse_fillet_bevel (Cairo.Context cr, double x, double y, double width, double height, double top_radius = 18.0, double rev_radius = 26.0, double line_width = 1.0)
		{
			var min_size = double.min (width, height);
			top_radius = top_radius.clamp (0.0, min_size / 2.0);
			rev_radius = rev_radius.clamp (0.0, double.min (width / 3.0, double.max (0.0, height - top_radius)));

			if (!Gdk.Screen.get_default ().is_composited ())
				return;

			cr.move_to (x, y + height);

			if (rev_radius > 0.0)
				cr.arc_negative (x, y + height - rev_radius, rev_radius, Math.PI_2, 0.0);

			cr.line_to (x + rev_radius, y + top_radius);

			if (top_radius > 0.0)
				cr.arc (x + rev_radius + top_radius, y + top_radius, top_radius, Math.PI, Math.PI + Math.PI_2);

			cr.line_to (x + width - rev_radius - top_radius, y);

			if (top_radius > 0.0)
				cr.arc (x + width - rev_radius - top_radius, y + top_radius, top_radius, -Math.PI_2, 0.0);

			cr.line_to (x + width - rev_radius, y + height - rev_radius);

			if (rev_radius > 0.0)
				cr.arc_negative (x + width, y + height - rev_radius, rev_radius, Math.PI, Math.PI_2);

			cr.set_line_width (line_width);
			cr.stroke ();
		}
		
		/**
		 * Similar to draw_rounded_rect, but moves in to avoid a containing rounded rect's lines.
		 *
		 * @param cr the context to draw with
		 * @param width the width of the rect
		 * @param height the height of the rect
		 */
		protected void draw_inner_rect (Cairo.Context cr, int width, int height)
		{
			var bottom_offset = BottomRoundness > 0 ? LineWidth : -LineWidth;
			
			draw_rounded_rect (cr,
				3 * LineWidth / 2.0,
				3 * LineWidth / 2.0,
				width - 3 * LineWidth,
				height - 3 * LineWidth / 2.0 - 3 * bottom_offset / 2.0,
				TopRoundness - LineWidth,
				BottomRoundness - LineWidth,
				LineWidth);
		}
		
		/**
		 * Draws a rounded rectangle.  If compositing is disabled, just draws a normal rectangle.
		 *
		 * @param cr the context to draw with
		 * @param x the x location of the rect
		 * @param y the y location of the rect
		 * @param width the width of the rect
		 * @param height the height of the rect
		 * @param top_radius the roundedness of the top edge
		 * @param bottom_radius the roundedness of the bottom edge
		 * @param line_width the line-width of the rect
		 */
		public static void draw_rounded_rect (Cairo.Context cr, double x, double y, double width, double height, double top_radius = 6.0, double bottom_radius = 6.0, double line_width = 1.0)
		{
			var min_size  = double.min (width, height);
			
			top_radius = top_radius.clamp (0.0, min_size);
			bottom_radius = bottom_radius.clamp (0.0, min_size - top_radius);
			
			if (!Gdk.Screen.get_default ().is_composited ())
				top_radius = bottom_radius = 0.0;
			
			// if the top isnt round, we have to adjust the starting point a bit
			if (top_radius == 0.0)
				cr.move_to (x - line_width / 2.0, y);
			else
				cr.move_to (x + top_radius, y);
			
			cr.arc (x + width - top_radius,    y + top_radius,             top_radius,    -Math.PI_2, 0);
			cr.arc (x + width - bottom_radius, y + height - bottom_radius, bottom_radius, 0,           Math.PI_2);
			cr.arc (x + bottom_radius,         y + height - bottom_radius, bottom_radius, Math.PI_2,   Math.PI);
			cr.arc (x + top_radius,            y + top_radius,             top_radius,    Math.PI,     -Math.PI_2);
			cr.close_path ();
		}
		
		/**
		 * Draws a rounded horizontal line.
		 *
		 * @param cr the context to draw with
		 * @param x the x location of the line
		 * @param y the y location of the line
		 * @param width the width of the line
		 * @param height the height of the line
		 * @param is_round_left weather the left is round or not
		 * @param is_round_right weather the right is round or not
		 * @param stroke filling style of the outline
		 * @param fill filling style of the inner area
		 */
		public static void draw_rounded_line (Cairo.Context cr, double x, double y, double width, double height, bool is_round_left, bool is_round_right, Cairo.Pattern? stroke = null, Cairo.Pattern? fill = null)
		{
			if (height > width) {
				y += Math.floor ((height - width) / 2.0);
				height = width;
			}
			
			height = 2.0 * Math.floor (height / 2.0);
			
			var left_radius = is_round_left ? height / 2.0 : 0.0;
			var right_radius = is_round_right ? height / 2.0 : 0.0;
			
			cr.move_to (x + width - right_radius, y);
			cr.line_to (x + left_radius, y);
			if (is_round_left)
				cr.arc_negative (x + left_radius, y + left_radius, left_radius, -Math.PI_2, Math.PI_2);
			else
				cr.line_to (x, y + height);
			cr.line_to (x + width - right_radius, y + height);
			if (is_round_right)
				cr.arc_negative (x + width - right_radius, y + right_radius, right_radius, Math.PI_2, -Math.PI_2);
			else
				cr.line_to (x + width, y);
			cr.close_path ();
			
			if (fill != null) {
				cr.set_source (fill);
				cr.fill_preserve ();
			}
			if (stroke != null)
				cr.set_source (stroke);
			cr.stroke ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override void verify (string prop)
		{
			base.verify (prop);
			
			switch (prop) {
			case "TopRoundness":
				if (TopRoundness < 0)
					TopRoundness = 0;
				break;
			
			case "BottomRoundness":
				if (BottomRoundness < 0)
					BottomRoundness = 0;
				break;
			
			case "ReverseRoundness":
				if (ReverseRoundness < 0)
					ReverseRoundness = 0;
				break;
			
			case "LineWidth":
				if (LineWidth < 0)
					LineWidth = 0;
				break;
			
			case "OuterStrokeColor":
				break;
			
			case "FillStartColor":
				break;
			
			case "FillEndColor":
				break;
			
			case "InnerStrokeColor":
				break;
			}
		}
		
		/**
		 * Enumerate valid dock theme directories inside a parent folder.
		 */
		static void enumerate_theme_folder (File? folder, Gee.HashSet<string> list)
		{
			if (folder == null || !folder.query_exists ())
				return;
			try {
				var enumerator = folder.enumerate_children ("standard::name,standard::type,standard::is-hidden",
					GLib.FileQueryInfoFlags.NONE);
				FileInfo info;
				while ((info = enumerator.next_file ()) != null) {
					if (info.get_is_hidden ()
						|| info.get_file_type () != GLib.FileType.DIRECTORY)
						continue;
					
					var child = folder.get_child (info.get_name ());
					if (child.get_child ("dock.theme").query_exists () || child.get_child ("hover.theme").query_exists ())
						list.add (info.get_name ());
				}
			} catch {}
		}

		static bool is_valid_theme_dir (File? folder)
		{
			return folder != null
				&& folder.query_exists ()
				&& folder.query_file_type (FileQueryInfoFlags.NONE, null) == FileType.DIRECTORY;
		}

		public static bool is_embedded_theme (string name, string type = "dock")
		{
			if (name == "" || name == DEFAULT_NAME || name == GTK_THEME_NAME)
				return false;
			try {
				resources_get_info ("/net/launchpad/plank/themes/%s/%s.theme".printf (name, type),
					ResourceLookupFlags.NONE, null, null);
				return true;
			} catch (Error e) {
				return false;
			}
		}

		/**
		 * Get a sorted array of all available theme-names (Wayplank and Plank legacy).
		 *
		 * @return array containing all available theme-names
		 */
		public static string[] get_theme_list ()
		{
			var list = new Gee.HashSet<string> ();
			
			list.add (DEFAULT_NAME);

			// 0. Monolithic built-in themes embedded in GResource RAM
			try {
				var children = resources_enumerate_children ("/net/launchpad/plank/themes", ResourceLookupFlags.NONE);
				foreach (unowned string child in children) {
					var clean_name = child.has_suffix ("/") ? child.substring (0, child.length - 1) : child;
					if (clean_name != "" && is_embedded_theme (clean_name))
						list.add (clean_name);
				}
			} catch (Error e) {}
			
			// 1. User's wayplank themes folder (~/.local/share/wayplank/themes)
			enumerate_theme_folder (Paths.AppThemeFolder, list);
			
			// 2. User's legacy plank themes folder (~/.local/share/plank/themes)
			enumerate_theme_folder (Paths.DataHomeFolder.get_child ("plank/themes"), list);
			
			// 3. User's ~/.themes folder
			enumerate_theme_folder (Paths.HomeFolder.get_child (".themes"), list);
			
			// 4. System wayplank themes folder (/usr/share/wayplank/themes)
			enumerate_theme_folder (Paths.ThemeFolder, list);
			
			// 5. System legacy plank themes folders (/usr/share/plank/themes)
			foreach (var datafolder in Paths.DataDirFolders) {
				enumerate_theme_folder (datafolder.get_child ("plank/themes"), list);
			}
			
			var others = new Gee.ArrayList<string> ();
			foreach (var theme_item in list) {
				if (theme_item != DEFAULT_NAME)
					others.add (theme_item);
			}
			others.sort ();
			
			var result = new Gee.ArrayList<string> ();
			result.add (DEFAULT_NAME);
			result.add_all (others);
			
			return result.to_array ();
		}
		
		/**
		 * Try to get an already existing folder located in the
		 * themes folder while prefering the user's themes folder.
		 * Checks Wayplank directories and legacy Plank directories for 100% theme compatibility.
		 *
		 * @param name the basename of the folder
		 * @return {@link GLib.File} the folder of the theme or NULL
		 */
		public static bool is_valid_name (string name)
		{
			if (name == DEFAULT_NAME || name == GTK_THEME_NAME)
				return true;

			if (is_embedded_theme (name))
				return true;

			if (is_valid_theme_dir (Paths.AppThemeFolder.get_child (name)))
				return true;
			if (is_valid_theme_dir (Paths.DataHomeFolder.get_child ("plank/themes/%s".printf (name))))
				return true;
			if (is_valid_theme_dir (Paths.HomeFolder.get_child (".themes/%s".printf (name))))
				return true;
			if (is_valid_theme_dir (Paths.ThemeFolder.get_child (name)))
				return true;
			foreach (var datafolder in Paths.DataDirFolders) {
				if (is_valid_theme_dir (datafolder.get_child ("plank/themes/%s".printf (name))))
					return true;
			}
			return false;
		}

		public static File? get_theme_folder (string name)
		{
			if (name == DEFAULT_NAME || name == GTK_THEME_NAME)
				return null;
			
			File folder;
			
			// 1. Look in user's wayplank themes folder
			folder = Paths.AppThemeFolder.get_child (name);
			if (is_valid_theme_dir (folder))
				return folder;
			
			// 2. Look in user's legacy plank themes folder (~/.local/share/plank/themes)
			folder = Paths.DataHomeFolder.get_child ("plank/themes/%s".printf (name));
			if (is_valid_theme_dir (folder))
				return folder;
			
			// 3. Look in user's ~/.themes folder
			folder = Paths.HomeFolder.get_child (".themes/%s".printf (name));
			if (is_valid_theme_dir (folder))
				return folder;

			// 4. Look in system's wayplank themes folder
			folder = Paths.ThemeFolder.get_child (name);
			if (is_valid_theme_dir (folder))
				return folder;
			
			// 5. Look in system's legacy plank themes folders
			foreach (var datafolder in Paths.DataDirFolders) {
				folder = datafolder.get_child ("plank/themes/%s".printf (name));
				if (is_valid_theme_dir (folder))
					return folder;
			}
			
			if (!is_embedded_theme (name))
				warning ("Theme '%s' not found, falling back to %s.", name, DEFAULT_NAME);
			
			return null;
		}
	}
}
