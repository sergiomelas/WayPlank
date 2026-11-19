#!/usr/bin/env python3
#
#  Copyright (C) 2026 Sergio Melas <sergiomelas@gmail.com>
#
#  This file is part of WayPlank.
#
#  WayPlank is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  WayPlank is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ==============================================================================
# WayPlank Fullscreen Inhibit & Edge Click Tester (FAT 3.9 / Issue #10)
# Author: Sergio Melas <sergiomelas@gmail.com>
# ==============================================================================
"""
WayPlank Fullscreen Inhibit & Edge Click Tester (FAT 3.9 / Issue #10)
=====================================================================
Simulates a normal unmaximized window (like Remmina, MPV, or a browser)
transitioning directly into Fullscreen mode (without being Maximized first),
and places interactive click-test buttons flush against all 4 screen edges
(0px margin) to verify that:
  1. The dock hides immediately when a fullscreen window is active on its monitor
     (across all HideModes, including 'Never' / HideType.NONE).
  2. Moving the mouse to the screen edge does NOT unhide the dock while fullscreen.
  3. 100% of clicks at the very edge (0px) reach the fullscreen application
     instead of being intercepted by the dock's hidden cursor reveal region.
"""

import sys
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango


class FullscreenTesterWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="WayPlank Fullscreen Inhibit Tester (FAT 3.9 / Issue #10)")
        self.set_default_size(850, 620)
        self.set_position(Gtk.WindowPosition.CENTER)

        self.is_fullscreen = False
        self.click_counts = {
            "TOP": 0,
            "BOTTOM": 0,
            "LEFT": 0,
            "RIGHT": 0,
        }

        self._apply_css()
        self._build_ui()

        self.connect("window-state-event", self._on_window_state_event)
        self.connect("key-press-event", self._on_key_press_event)
        self.connect("destroy", Gtk.main_quit)

    def _apply_css(self):
        css = b"""
        window {
            background-color: #1e222a;
            color: #eceff4;
        }
        .edge-btn {
            background-image: none;
            background-color: #2e3440;
            color: #88c0d0;
            font-weight: bold;
            font-size: 13px;
            border: 2px solid #4c566a;
            border-radius: 0px;
            margin: 0px;
            padding: 6px;
        }
        .edge-btn:hover {
            background-color: #3b4252;
            border-color: #88c0d0;
            color: #eceff4;
        }
        .edge-btn:active {
            background-color: #a3be8c;
            color: #2e3440;
        }
        .toggle-btn {
            background-image: none;
            background-color: #5e81ac;
            color: #eceff4;
            font-weight: bold;
            font-size: 16px;
            padding: 14px 28px;
            border-radius: 8px;
            border: 1px solid #81a1c1;
        }
        .toggle-btn:hover {
            background-color: #81a1c1;
        }
        .status-box {
            background-color: #2e3440;
            border: 1px solid #434c5e;
            border-radius: 10px;
            padding: 20px;
        }
        .status-title {
            font-size: 20px;
            font-weight: bold;
            color: #eceff4;
        }
        .state-badge-normal {
            background-color: #4c566a;
            color: #eceff4;
            font-weight: bold;
            font-size: 15px;
            padding: 6px 14px;
            border-radius: 6px;
        }
        .state-badge-fs {
            background-color: #a3be8c;
            color: #2e3440;
            font-weight: bold;
            font-size: 15px;
            padding: 6px 14px;
            border-radius: 6px;
        }
        .log-label {
            font-family: monospace;
            font-size: 14px;
            color: #ebcb8b;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    def _build_ui(self):
        # Root layout with 0px border/margin so edge buttons touch the exact screen edges
        root_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root_box.set_margin_top(0)
        root_box.set_margin_bottom(0)
        root_box.set_margin_start(0)
        root_box.set_margin_end(0)
        self.add(root_box)

        # TOP EDGE BUTTON (flush with y=0)
        self.top_btn = self._create_edge_button(
            "TOP", "▲ TOP EDGE CLICK TEST (y = 0px) — Click right against the top screen border ▲"
        )
        self.top_btn.set_size_request(-1, 42)
        root_box.pack_start(self.top_btn, False, False, 0)

        # Middle row: LEFT EDGE + CENTER DASHBOARD + RIGHT EDGE
        mid_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        root_box.pack_start(mid_box, True, True, 0)

        self.left_btn = self._create_edge_button(
            "LEFT", "◀ LEFT\nEDGE\n(x=0px)"
        )
        self.left_btn.set_size_request(80, -1)
        mid_box.pack_start(self.left_btn, False, False, 0)

        # Center Dashboard
        center_align = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        center_align.set_valign(Gtk.Align.CENTER)
        center_align.set_halign(Gtk.Align.CENTER)
        center_align.get_style_context().add_class("status-box")
        mid_box.pack_start(center_align, True, False, 24)

        title_lbl = Gtk.Label(label="WayPlank Fullscreen Inhibit Tester (FAT 3.9 / Issue #10)")
        title_lbl.get_style_context().add_class("status-title")
        center_align.pack_start(title_lbl, False, False, 0)

        self.state_lbl = Gtk.Label(label="WINDOW STATE: NORMAL (UNMAXIMIZED)")
        self.state_lbl.get_style_context().add_class("state-badge-normal")
        center_align.pack_start(self.state_lbl, False, False, 0)

        desc_lbl = Gtk.Label(
            label=(
                "The 4 outer border strips (TOP, BOTTOM, LEFT, RIGHT) sit directly over\n"
                "WayPlank's screen-edge trigger zone (10px/1px active reveal area).\n\n"
                "1. Press F11, Space, or the button below to enter FULLSCREEN directly\n"
                "   from an unmaximized window (simulating Remmina / MPV / QEMU).\n"
                "2. Verify that WayPlank disappears immediately — even when configured\n"
                "   as Always Visible (Hide Dock = OFF) or Dodge Maximized.\n"
                "3. Move the mouse into the 4 border zones and click them: even when\n"
                "   touching the very edge (0px), WayPlank MUST NOT appear and every\n"
                "   click MUST pass through and increment the counter below."
            )
        )
        desc_lbl.set_justify(Gtk.Justification.LEFT)
        center_align.pack_start(desc_lbl, False, False, 4)

        self.toggle_btn = Gtk.Button(label="⛶  Toggle Fullscreen (F11 / Space)")
        self.toggle_btn.get_style_context().add_class("toggle-btn")
        self.toggle_btn.connect("clicked", lambda *_: self.toggle_fullscreen())
        center_align.pack_start(self.toggle_btn, False, False, 6)

        self.log_lbl = Gtk.Label(
            label="Last Edge Click: None  |  Counts — BOTTOM: 0 | TOP: 0 | LEFT: 0 | RIGHT: 0"
        )
        self.log_lbl.get_style_context().add_class("log-label")
        center_align.pack_start(self.log_lbl, False, False, 4)

        hint_lbl = Gtk.Label(label="Shortcuts: [F11 / Space] Toggle Fullscreen   •   [Esc] Exit Fullscreen   •   [Q] Quit")
        center_align.pack_start(hint_lbl, False, False, 0)

        self.right_btn = self._create_edge_button(
            "RIGHT", "RIGHT ▶\nEDGE\n(x=max)"
        )
        self.right_btn.set_size_request(80, -1)
        mid_box.pack_end(self.right_btn, False, False, 0)

        # BOTTOM EDGE BUTTON (flush with y=max)
        self.bottom_btn = self._create_edge_button(
            "BOTTOM", "▼ BOTTOM EDGE CLICK TEST (y = max) — Click right against the bottom screen border ▼"
        )
        self.bottom_btn.set_size_request(-1, 42)
        root_box.pack_end(self.bottom_btn, False, False, 0)

    def _create_edge_button(self, edge_name: str, label_text: str) -> Gtk.Button:
        btn = Gtk.Button(label=label_text)
        btn.get_style_context().add_class("edge-btn")
        btn.connect("clicked", self._on_edge_clicked, edge_name)
        return btn

    def _on_edge_clicked(self, button: Gtk.Button, edge_name: str):
        self.click_counts[edge_name] += 1
        c = self.click_counts
        mode_str = "FULLSCREEN" if self.is_fullscreen else "WINDOWED"
        self.log_lbl.set_text(
            f"✅ {edge_name} EDGE CLICKED in {mode_str}!  |  "
            f"BOTTOM: {c['BOTTOM']} | TOP: {c['TOP']} | LEFT: {c['LEFT']} | RIGHT: {c['RIGHT']}"
        )

    def toggle_fullscreen(self):
        if self.is_fullscreen:
            self.unfullscreen()
        else:
            self.fullscreen()

    def _on_window_state_event(self, widget, event: Gdk.EventWindowState):
        self.is_fullscreen = bool(event.new_window_state & Gdk.WindowState.FULLSCREEN)
        is_max = bool(event.new_window_state & Gdk.WindowState.MAXIMIZED)
        ctx = self.state_lbl.get_style_context()
        if self.is_fullscreen:
            ctx.remove_class("state-badge-normal")
            ctx.add_class("state-badge-fs")
            self.state_lbl.set_text(
                f"WINDOW STATE: FULLSCREEN ACTIVE (GDK FULLSCREEN=True, MAXIMIZED={is_max})"
            )
            self.toggle_btn.set_label("🗗  Exit Fullscreen (F11 / Esc)")
        else:
            ctx.remove_class("state-badge-fs")
            ctx.add_class("state-badge-normal")
            self.state_lbl.set_text(
                f"WINDOW STATE: NORMAL WINDOWED (GDK FULLSCREEN=False, MAXIMIZED={is_max})"
            )
            self.toggle_btn.set_label("⛶  Enter Fullscreen (F11 / Space)")
        return False

    def _on_key_press_event(self, widget, event: Gdk.EventKey):
        keyval = event.keyval
        if keyval in (Gdk.KEY_F11, Gdk.KEY_space):
            self.toggle_fullscreen()
            return True
        if keyval == Gdk.KEY_Escape and self.is_fullscreen:
            self.unfullscreen()
            return True
        if keyval in (Gdk.KEY_q, Gdk.KEY_Q):
            Gtk.main_quit()
            return True
        return False


def main():
    win = FullscreenTesterWindow()
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    sys.exit(main())

