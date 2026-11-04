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
	 * An animated compositor-agnostic overlay window that renders icon removal
	 * animations anchored accurately to the icon's canonical dock slot via
	 * SurfaceCoordinateService, reporting deterministic frame completion via
	 * the poof_completed(tx_id) handshake signal.
	 */
	public class PoofWindow : CompositedWindow
	{
		const int DEFAULT_RUN_LENGTH = 600 * 1000;

		public signal void poof_completed (uint64 tx_id);

		static PoofWindow? instance = null;

		public static unowned PoofWindow get_default ()
		{
			if (instance == null)
				instance = new PoofWindow ();

			return instance;
		}

		Gdk.Pixbuf? poof_image = null;
		int poof_size = 128;
		int canvas_size = 192;
		int poof_frames = 0;

		int64 start_time = 0LL;
		int64 frame_time = 0LL;
		int active_run_length = DEFAULT_RUN_LENGTH;
		int active_effect_mode = 0;

		Cairo.Surface? icon_surface = null;
		double accent_r = 0.35;
		double accent_g = 0.68;
		double accent_b = 1.00;

		uint tick_cb_id = 0U;
		uint64 active_tx_id = 0ULL;
		double canvas_cx = 96.0;
		double canvas_cy = 96.0;
		int target_icon_size = 48;

		public PoofWindow ()
		{
			GLib.Object (type: Gtk.WindowType.TOPLEVEL);
		}

		construct
		{
			SurfaceCoordinateService.init_overlay_surface (this, "wayplank-poof", "poof");

			try {
				poof_image = new Gdk.Pixbuf.from_resource ("%s/img/poof.svg".printf (Plank.G_RESOURCE_PATH));
				poof_size = poof_image.width;
				poof_frames = (int) Math.floor (poof_image.height / poof_size);
				debug ("Loaded animation: size = %ipx, frame-count = %i, duration = %ims", poof_size, poof_frames, DEFAULT_RUN_LENGTH / 1000);
			} catch (Error e) {
				poof_image = null;
				poof_size = 128;
				poof_frames = 0;
				critical ("Unable to load poof animation image: %s", e.message);
			}

			canvas_size = int.max (poof_size, 192);
			set_size_request (canvas_size, canvas_size);

			unmap.connect (() => {
				if (active_tx_id != 0ULL) {
					if (tick_cb_id > 0U) {
						remove_tick_callback (tick_cb_id);
						tick_cb_id = 0U;
					}
					icon_surface = null;
					uint64 done_tx = active_tx_id;
					active_tx_id = 0ULL;
					poof_completed (done_tx);
				}
			});
		}

		~PoofWindow ()
		{
			if (tick_cb_id > 0U) {
				remove_tick_callback (tick_cb_id);
				tick_cb_id = 0U;
			}
			icon_surface = null;
			active_tx_id = 0ULL;
		}

		/**
		 * Aborts any in-flight animation without emitting a completion signal
		 * (used when DragManager synchronously flushes a preempted removal).
		 */
		public void cancel_active ()
		{
			if (tick_cb_id > 0U) {
				remove_tick_callback (tick_cb_id);
				tick_cb_id = 0U;
			}
			icon_surface = null;
			active_tx_id = 0ULL;
			if (get_visible ())
				hide ();
		}

		/**
		 * Starts the selected destruction animation (0..8) at the item's canonical
		 * dock coordinate and emits poof_completed(tx_id) deterministically upon VSync completion.
		 */
		public void show_for_icon_anchor (uint64 tx_id, int along_coord, int perp_from_dock_base,
			int icon_size, Gtk.PositionType dock_edge, bool reserve_space_active,
			int dock_exclusive_thickness, Gdk.Monitor? monitor,
			int effect_mode = 0, Cairo.Surface? icon_snapshot = null, Color? accent = null,
			int duration_ms = 600)
		{
			if (tick_cb_id > 0U) {
				remove_tick_callback (tick_cb_id);
				tick_cb_id = 0U;
			}
			active_tx_id = 0ULL;
			icon_surface = null;

			int mode = effect_mode.clamp (0, 8);
			if (mode == 8) {
				if (get_visible ())
					hide ();
				poof_completed (tx_id);
				return;
			}

			if (mode >= 1 && mode <= 7 && icon_snapshot == null)
				mode = 0;

			if (mode == 0 && (poof_image == null || poof_frames <= 0)) {
				poof_completed (tx_id);
				return;
			}

			active_effect_mode = mode;
			active_run_length = (duration_ms >= 100) ? (duration_ms.clamp (100, 1000) * 1000) : DEFAULT_RUN_LENGTH;
			icon_surface = icon_snapshot;

			if (accent != null && (accent.red > 0.05 || accent.green > 0.05 || accent.blue > 0.05)) {
				accent_r = accent.red;
				accent_g = accent.green;
				accent_b = accent.blue;
				double max_c = double.max (accent_r, double.max (accent_g, accent_b));
				if (max_c < 0.68 && max_c > 0.01) {
					double boost = 0.82 / max_c;
					accent_r = (accent_r * boost).clamp (0.0, 1.0);
					accent_g = (accent_g * boost).clamp (0.0, 1.0);
					accent_b = (accent_b * boost).clamp (0.0, 1.0);
				}
			} else {
				accent_r = 0.35;
				accent_g = 0.68;
				accent_b = 1.00;
			}

			active_tx_id = tx_id;
			target_icon_size = (icon_size > 0) ? icon_size : 48;
			start_time = GLib.get_monotonic_time ();
			frame_time = start_time;

			SurfaceCoordinateService.place_dock_overlay (
				this, monitor, dock_edge, along_coord, perp_from_dock_base,
				canvas_size, canvas_size, reserve_space_active, dock_exclusive_thickness,
				out canvas_cx, out canvas_cy
			);

			queue_draw ();

			tick_cb_id = add_tick_callback ((widget, clock) => {
				if (active_tx_id != tx_id) {
					tick_cb_id = 0U;
					return GLib.Source.REMOVE;
				}

				frame_time = GLib.get_monotonic_time ();
				if (frame_time - start_time < active_run_length) {
					queue_draw ();
					return GLib.Source.CONTINUE;
				}

				tick_cb_id = 0U;
				icon_surface = null;
				uint64 done_tx = active_tx_id;
				active_tx_id = 0ULL;
				hide ();
				poof_completed (done_tx);
				return GLib.Source.REMOVE;
			});
		}

		public override bool draw (Cairo.Context cr)
		{
			cr.save ();
			cr.set_operator (Cairo.Operator.CLEAR);
			cr.paint ();
			cr.restore ();

			double p = ((frame_time - start_time) / (double) active_run_length).clamp (0.0, 0.9999);
			double sz = (double) target_icon_size;
			double half = sz / 2.0;

			if (active_effect_mode == 0 || icon_surface == null) {
				if (poof_image == null || poof_frames <= 0)
					return Gdk.EVENT_STOP;

				int frame_idx = int.min (poof_frames - 1, (int) Math.floor (poof_frames * p));
				double cloud_size = double.min ((double) canvas_size, double.max (56.0, sz * 1.65));
				double s = cloud_size / (double) poof_size;

				cr.save ();
				cr.set_operator (Cairo.Operator.OVER);
				cr.translate (canvas_cx, canvas_cy);
				cr.scale (s, s);
				cr.rectangle (-poof_size / 2.0, -poof_size / 2.0, poof_size, poof_size);
				cr.clip ();
				Gdk.cairo_set_source_pixbuf (cr, poof_image, -poof_size / 2.0, -poof_size / 2.0 - frame_idx * poof_size);
				cr.paint ();
				cr.restore ();
				return Gdk.EVENT_STOP;
			}

			cr.set_operator (Cairo.Operator.OVER);

			switch (active_effect_mode) {
			case 1: // Shrink & Fade
				double scale;
				double alpha;
				if (p < 0.22) {
					double t = p / 0.22;
					scale = 1.0 + 0.14 * Math.sin (t * Math.PI_2);
					alpha = 1.0;
				} else {
					double t = (p - 0.22) / 0.78;
					scale = 1.14 * (1.0 - t * t * (3.0 - 2.0 * t));
					alpha = (1.0 - t * t).clamp (0.0, 1.0);
				}
				if (scale > 0.01 && alpha > 0.005) {
					cr.save ();
					cr.translate (canvas_cx, canvas_cy);
					cr.scale (scale, scale);
					cr.set_source_surface (icon_surface, -half, -half);
					cr.paint_with_alpha (alpha);
					cr.restore ();
				}
				break;

			case 2: // Implode Spin (540-degree vortex collapse + pinpoint spark)
				double angle = 3.0 * Math.PI * p * p;
				double scale = (1.0 - p) * (1.0 - 0.35 * p);
				double alpha = (1.0 - p * p * p).clamp (0.0, 1.0);
				if (scale > 0.01 && alpha > 0.005) {
					cr.save ();
					cr.translate (canvas_cx, canvas_cy);
					cr.rotate (angle);
					cr.scale (scale, scale);
					cr.set_source_surface (icon_surface, -half, -half);
					cr.paint_with_alpha (alpha);
					cr.restore ();
				}
				if (p > 0.50) {
					double sp = (p - 0.50) / 0.50;
					double spark_a = 0.85 * Math.sin (sp * Math.PI);
					double spark_r = double.max (2.0, half * 0.42 * (1.0 - 0.65 * sp));
					if (spark_a > 0.01) {
						var grad = new Cairo.Pattern.radial (canvas_cx, canvas_cy, 0.0, canvas_cx, canvas_cy, spark_r);
						grad.add_color_stop_rgba (0.0, 1.0, 1.0, 1.0, spark_a);
						grad.add_color_stop_rgba (0.45, accent_r, accent_g, accent_b, spark_a * 0.75);
						grad.add_color_stop_rgba (1.0, accent_r, accent_g, accent_b, 0.0);
						cr.save ();
						cr.arc (canvas_cx, canvas_cy, spark_r, 0, 2.0 * Math.PI);
						cr.set_source (grad);
						cr.fill ();
						cr.restore ();
					}
				}
				break;

			case 3: // Shatter Burst (4x4 textured shards with radial impulse, spin & gravity)
				double sw = sz / 4.0;
				double sh = sz / 4.0;
				double ease_out = 1.0 - (1.0 - p) * (1.0 - p);
				double shard_scale = (1.0 - 0.32 * p).clamp (0.12, 1.0);
				double alpha = (1.0 - p * p).clamp (0.0, 1.0);

				for (int row = 0; row < 4; row++) {
					for (int col = 0; col < 4; col++) {
						int idx = row * 4 + col;
						double sx0 = col * sw;
						double sy0 = row * sh;
						double ox = (col - 1.5) * sw;
						double oy = (row - 1.5) * sh;
						double base_ang = Math.atan2 (oy, ox) + 0.28 * Math.sin (idx * 2.39996);
						double speed = sz * (0.48 + 0.34 * ((idx * 7 % 5) / 4.0));
						double dx = ox + Math.cos (base_ang) * speed * ease_out;
						double dy = oy + Math.sin (base_ang) * speed * ease_out + (sz * 0.40) * p * p;
						double rot = ((idx % 2 == 0) ? 1.0 : -1.0) * (1.05 + 0.26 * (idx % 4)) * p;

						cr.save ();
						cr.translate (canvas_cx + dx, canvas_cy + dy);
						cr.rotate (rot);
						cr.scale (shard_scale, shard_scale);
						cr.rectangle (-sw / 2.0, -sh / 2.0, sw, sh);
						cr.clip ();
						cr.set_source_surface (icon_surface, -sx0 - sw / 2.0, -sy0 - sh / 2.0);
						cr.paint_with_alpha (alpha);
						cr.restore ();
					}
				}
				break;

			case 4: // Vaporize (upward thermal drift + rising glowing embers)
				double icon_alpha = Math.pow (1.0 - p, 1.65);
				if (icon_alpha > 0.008) {
					double sx = (1.0 - 0.24 * p).clamp (0.1, 1.0);
					double sy = 1.0 + 0.20 * p;
					double lift = -sz * 0.34 * p;
					cr.save ();
					cr.translate (canvas_cx, canvas_cy + lift);
					cr.scale (sx, sy);
					cr.set_source_surface (icon_surface, -half, -half);
					cr.paint_with_alpha (icon_alpha);
					cr.restore ();
				}

				for (int i = 0; i < 18; i++) {
					double t_start = (i % 6) * 0.055;
					if (p <= t_start)
						continue;
					double lp = ((p - t_start) / (1.0 - t_start)).clamp (0.0, 1.0);
					double x_spread = ((i * 37 % 19) / 9.0 - 1.0) * half * 0.82 + Math.sin (lp * 5.2 + i) * 4.0;
					double y_rise = ((i % 3) - 1.0) * half * 0.30 - sz * (0.52 + 0.44 * ((i * 5 % 7) / 6.0)) * lp;
					double r = double.max (0.8, (2.9 - 1.9 * lp) * (0.8 + 0.35 * (i % 3)));
					double ember_a = (0.90 * Math.sin (lp * Math.PI) * (1.0 - 0.25 * p)).clamp (0.0, 1.0);
					if (ember_a <= 0.01)
						continue;

					cr.save ();
					cr.arc (canvas_cx + x_spread, canvas_cy + y_rise, r, 0, 2.0 * Math.PI);
					if (i % 3 == 0)
						cr.set_source_rgba (1.0, 0.96, 0.88, ember_a);
					else
						cr.set_source_rgba (accent_r, accent_g, accent_b, ember_a);
					cr.fill ();
					cr.restore ();
				}
				break;

			case 5: // 3D Tumble (perspective card flip receding into depth)
				double ease = 1.0 - (1.0 - p) * (1.0 - p);
				double spin_cos = Math.cos (2.5 * Math.PI * ease);
				if (Math.fabs (spin_cos) < 0.03)
					spin_cos = (spin_cos >= 0.0) ? 0.03 : -0.03;
				double depth = (1.0 - 0.82 * p * p).clamp (0.08, 1.0);
				double drop = sz * 0.16 * p * p;
				double tilt = 0.22 * p;
				double alpha = (1.0 - p * p).clamp (0.0, 1.0);

				if (alpha > 0.005) {
					cr.save ();
					cr.translate (canvas_cx, canvas_cy + drop);
					cr.rotate (tilt);
					cr.scale (spin_cos * depth, depth);
					cr.set_source_surface (icon_surface, -half, -half);
					cr.paint_with_alpha (alpha);
					cr.restore ();
				}
				break;

			case 6: // Shockwave (core flash collapse + dual concentric ripple rings)
				if (p < 0.48) {
					double tp = p / 0.48;
					double core_scale = 1.08 * (1.0 - tp * tp);
					double core_alpha = (1.0 - tp).clamp (0.0, 1.0);
					if (core_scale > 0.02 && core_alpha > 0.005) {
						cr.save ();
						cr.translate (canvas_cx, canvas_cy);
						cr.scale (core_scale, core_scale);
						cr.set_source_surface (icon_surface, -half, -half);
						cr.paint_with_alpha (core_alpha);
						cr.restore ();
					}
				}

				double ease1 = 1.0 - Math.pow (1.0 - p, 3.0);
				double r1 = half * 0.22 + sz * 0.86 * ease1;
				double a1 = 0.88 * (1.0 - p) * (1.0 - p);
				if (a1 > 0.005) {
					cr.save ();
					cr.arc (canvas_cx, canvas_cy, r1, 0, 2.0 * Math.PI);
					cr.set_line_width (3.4 * (1.0 - p) + 0.9);
					cr.set_source_rgba (accent_r, accent_g, accent_b, a1);
					cr.stroke ();
					cr.restore ();
				}

				if (p > 0.10) {
					double p2 = (p - 0.10) / 0.90;
					double ease2 = 1.0 - (1.0 - p2) * (1.0 - p2);
					double r2 = half * 0.16 + sz * 0.58 * ease2;
					double a2 = 0.72 * (1.0 - p2) * (1.0 - p2);
					if (a2 > 0.005) {
						cr.save ();
						cr.arc (canvas_cx, canvas_cy, r2, 0, 2.0 * Math.PI);
						cr.set_line_width (2.2 * (1.0 - p2) + 0.7);
						cr.set_source_rgba (
							0.5 * (1.0 + accent_r),
							0.5 * (1.0 + accent_g),
							0.5 * (1.0 + accent_b),
							a2
						);
						cr.stroke ();
						cr.restore ();
					}
				}
				break;

			default:
			case 7: // Pixel Dissolve (6x6 micro-tile grid with staggered organic drift)
				double tw = sz / 6.0;
				double th = sz / 6.0;
				for (int row = 0; row < 6; row++) {
					for (int col = 0; col < 6; col++) {
						int idx = row * 6 + col;
						double delay = ((idx * 17 + row * 7) % 12) * 0.036;
						double lp = ((p - delay) / (1.0 - delay)).clamp (0.0, 1.0);
						double alpha = (1.0 - lp * lp).clamp (0.0, 1.0);
						if (alpha <= 0.005)
							continue;

						double tx0 = col * tw;
						double ty0 = row * th;
						double ox = (col - 2.5) * tw;
						double oy = (row - 2.5) * th;
						double dx = ox * (1.0 + 0.75 * lp * lp);
						double dy = oy * (1.0 + 0.50 * lp * lp) - sz * 0.22 * lp;
						double t_scale = (1.0 - 0.82 * lp).clamp (0.08, 1.0);

						cr.save ();
						cr.translate (canvas_cx + dx, canvas_cy + dy);
						cr.scale (t_scale, t_scale);
						cr.rectangle (-tw / 2.0, -th / 2.0, tw, th);
						cr.clip ();
						cr.set_source_surface (icon_surface, -tx0 - tw / 2.0, -ty0 - th / 2.0);
						cr.paint_with_alpha (alpha);
						cr.restore ();
					}
				}
				break;
			}

			return Gdk.EVENT_STOP;
		}
	}
}
