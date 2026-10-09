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
	[DBus (name = "org.wayplank.GnomeBridge")]
	public interface GnomeBridgeProxy : GLib.Object
	{
		public abstract string get_windows () throws GLib.Error;
		public abstract string get_primary_monitor () throws GLib.Error;
		public abstract string get_monitor_workareas () throws GLib.Error;
		public abstract bool activate_window (string uuid) throws GLib.Error;
		public abstract bool minimize_window (string uuid) throws GLib.Error;
		public abstract bool toggle_window (string uuid) throws GLib.Error;
		public abstract bool close_window (string uuid) throws GLib.Error;
		public abstract bool toggle_desktop () throws GLib.Error;
		public abstract bool position_dock (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_hover (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_poof (int x, int y, int width, int height) throws GLib.Error;
		public abstract string eval (string code) throws GLib.Error;
		public signal void windows_changed ();
	}

	/**
	 * WindowBackend implementation for GNOME / Mutter.
	 * Connects via D-Bus to the Wayplank GNOME Shell Extension (org.wayplank.GnomeBridge).
	 * Embeds the extension monolithically and installs/enables it if absent.
	 * Falls back gracefully to process-matching via Matcher if the extension is not active.
	 */
	public class MutterBackend : GLib.Object, WindowBackend
	{
		static MutterBackend? instance;
		Gee.ArrayList<WindowInfo> window_infos = new Gee.ArrayList<WindowInfo> ();
		bool started = false;
		GnomeBridgeProxy? proxy = null;
		uint name_watch_id = 0U;

		int last_x = -1;
		int last_y = -1;
		int last_width = -1;
		int last_height = -1;

		const string EXTENSION_UUID = "wayplank-bridge@wayplank.org";

		const string EXTENSION_METADATA = """{
  "name": "Wayplank Bridge",
  "description": "Native GNOME Shell bridge for Wayplank dock",
  "uuid": "wayplank-bridge@wayplank.org",
  "shell-version": ["45", "46", "47", "48", "49", "50"],
  "url": "https://github.com/wayplank",
  "version": 7
}
""";

		const string EXTENSION_JS = """//
//  Wayplank Bridge GNOME Shell Extension
//  Copyright (C) 2026 Sergio Melas
//  Part of Wayplank - native Wayland dock
//

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE_XML = `
<node>
  <interface name="org.wayplank.GnomeBridge">
    <method name="GetWindows">
      <arg type="s" name="json" direction="out"/>
    </method>
    <method name="GetPrimaryMonitor">
      <arg type="s" name="json" direction="out"/>
    </method>
    <method name="GetMonitorWorkAreas">
      <arg type="s" name="json" direction="out"/>
    </method>
    <method name="ActivateWindow">
      <arg type="s" name="uuid" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="MinimizeWindow">
      <arg type="s" name="uuid" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="ToggleWindow">
      <arg type="s" name="uuid" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="CloseWindow">
      <arg type="s" name="uuid" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="ToggleDesktop">
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="PositionDock">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
      <arg type="i" name="width" direction="in"/>
      <arg type="i" name="height" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="PositionHover">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
      <arg type="i" name="width" direction="in"/>
      <arg type="i" name="height" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="PositionPoof">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
      <arg type="i" name="width" direction="in"/>
      <arg type="i" name="height" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <signal name="WindowsChanged"/>
  </interface>
</node>`;

export default class WayplankBridgeExtension extends Extension {
    enable() {
        this._signals = [];
        this._wsSignals = [];
        this._windowSignals = new Map();
        this._desktopRestoredWindows = [];

        // Ensure all Wayplank windows (hover, dock, dialog, poof) are treated as skip_taskbar for WindowAttentionHandler so no notifications are ever created
        if (!this._origIsSkipTaskbar) {
            this._origIsSkipTaskbar = Meta.Window.prototype.is_skip_taskbar;
            const ext = this;
            Meta.Window.prototype.is_skip_taskbar = function() {
                try {
                    const kind = ext._classifyWindow(this);
                    if (kind === 'hover' || kind === 'dock' || kind === 'dialog' || kind === 'poof' || kind === 'unknown') {
                        return true;
                    }
                } catch (e) { }
                return ext._origIsSkipTaskbar.call(this);
            };
        }

        // Export D-Bus service using Gio.DBusExportedObject.wrapJSObject
        this._dbusImpl = Gio.DBusExportedObject.wrapJSObject(IFACE_XML, this);
        this._dbusImpl.export(Gio.DBus.session, '/org/wayplank/GnomeBridge');

        this._ownerId = Gio.bus_own_name(
            Gio.BusType.SESSION,
            'org.wayplank.GnomeBridge',
            Gio.BusNameOwnerFlags.NONE,
            null,
            null,
            null
        );

        // Hook GNOME display events to notify Wayplank and suppress attention
        const display = global.display;
        this._signals.push(display.connect('window-demands-attention', (d, win) => {
            if (win && this._classifyWindow(win) !== 'other') {
                try { win.demands_attention = false; } catch (e) { }
            }
        }));
        this._signals.push(display.connect('window-marked-urgent', (d, win) => {
            if (win && this._classifyWindow(win) !== 'other') {
                try { win.demands_attention = false; } catch (e) { }
            }
        }));
        this._signals.push(display.connect('window-created', (d, win) => {
            this._connectWindow(win);
            this._notifyWindowsChanged();
        }));
        const handleFocus = (fw) => {
            if (!fw) {
                fw = display.get_focus_window ? display.get_focus_window() : display.focus_window;
            }
            if (fw && this._classifyWindow(fw) === 'other') {
                this._lastActiveUuid = fw.get_stable_sequence ? fw.get_stable_sequence().toString() : fw.get_id().toString();
            }
            this._notifyWindowsChanged();
        };
        try {
            this._signals.push(display.connect('focus-window', (d, win) => handleFocus(win)));
        } catch (e) { }
        this._signals.push(display.connect('notify::focus-window', () => handleFocus(null)));
        const initFw = display.get_focus_window ? display.get_focus_window() : display.focus_window;
        if (initFw && this._classifyWindow(initFw) === 'other') {
            this._lastActiveUuid = initFw.get_stable_sequence ? initFw.get_stable_sequence().toString() : initFw.get_id().toString();
        }
        this._signals.push(display.connect('restacked', () => {
            this._notifyWindowsChanged();
        }));
        if (global.workspace_manager) {
            this._wsSignals.push(global.workspace_manager.connect('active-workspace-changed', () => {
                this._notifyWindowsChanged();
            }));
        }

        // Connect existing windows
        for (const actor of global.get_window_actors()) {
            if (actor.meta_window) {
                this._connectWindow(actor.meta_window);
            }
        }
    }

    disable() {
        if (this._origIsSkipTaskbar) {
            Meta.Window.prototype.is_skip_taskbar = this._origIsSkipTaskbar;
            this._origIsSkipTaskbar = null;
        }

        if (this._dbusImpl) {
            this._dbusImpl.unexport();
            this._dbusImpl = null;
        }

        if (this._ownerId) {
            Gio.bus_unown_name(this._ownerId);
            this._ownerId = 0;
        }

        const display = global.display;
        for (const id of this._signals) {
            display.disconnect(id);
        }
        this._signals = [];

        if (this._wsSignals && global.workspace_manager) {
            for (const id of this._wsSignals) {
                try { global.workspace_manager.disconnect(id); } catch (e) { }
            }
            this._wsSignals = [];
        }

        if (this._notifyTimeout) {
            GLib.Source.remove(this._notifyTimeout);
            this._notifyTimeout = 0;
        }

        for (const [win, sigs] of this._windowSignals.entries()) {
            for (const id of sigs) {
                try { win.disconnect(id); } catch (e) { }
            }
        }
        this._windowSignals.clear();
        this._lastActiveUuid = null;
    }

    _classifyWindow(win) {
        if (!win) return 'unknown';

        const title = (win.get_title ? win.get_title() : '') || '';
        const role = (win.get_role ? win.get_role() : '') || '';
        const wmClass = ((win.get_wm_class ? win.get_wm_class() : '') || '').toLowerCase();
        const gtkAppId = ((win.get_gtk_application_id ? win.get_gtk_application_id() : '') || '').toLowerCase();
        const tracker = Shell.WindowTracker.get_default();
        const app = tracker.get_window_app ? tracker.get_window_app(win) : null;
        const appId = ((app ? app.get_id() : '') || '').toLowerCase();
        const sandboxedId = ((win.get_sandboxed_app_id ? win.get_sandboxed_app_id() : '') || '').toLowerCase();

        const isWayplankApp = (wmClass === 'wayplank' ||
                               wmClass === 'plank' ||
                               appId.includes('wayplank') ||
                               appId.includes('net.launchpad.plank') ||
                               gtkAppId.includes('wayplank') ||
                               sandboxedId.includes('wayplank') ||
                               role === 'dock' ||
                               (title.toLowerCase() === 'wayplank' && wmClass === ''));

        if (!isWayplankApp)
            return 'other';

        const type = win.get_window_type ? win.get_window_type() : -1;
        const lowerTitle = title.toLowerCase();

        // 0. Poof Window: match title, role, or active poof placement request
        if (lowerTitle.includes('poof') || role === 'poof' ||
            (this._lastPoofGeo && (Date.now() - (this._lastPoofTime || 0) < 3000) && lowerTitle !== 'wayplank' && !lowerTitle.includes('hover') && !lowerTitle.includes('prefer') && !lowerTitle.includes('help')))
            return 'poof';

        // 1. Tooltip / Hover Window (ensure poof is not mistaken for hover)
        if (lowerTitle.includes('hover') || role === 'tooltip' || (type === Meta.WindowType.TOOLTIP && !lowerTitle.includes('poof') && role !== 'poof'))
            return 'hover';

        // 2. Dialog Windows (Preferences, Shortcuts/Help)
        if (lowerTitle.includes('prefer') || lowerTitle.includes('setting') ||
            lowerTitle.includes('short') || lowerTitle.includes('help') ||
            lowerTitle.includes('scorciatoie') || lowerTitle.includes('aiuto') ||
            role === 'preferences' || role === 'help' || type === Meta.WindowType.DIALOG)
            return 'dialog';

        // 3. Dock Window: ONLY if title is exactly 'wayplank' or role is 'dock' or type is DOCK
        if (lowerTitle === 'wayplank' || role === 'dock' || type === Meta.WindowType.DOCK)
            return 'dock';

        return 'unknown';
    }

    _centerWindow(win) {
        if (!win || win._wayplankCentered) return false;
        try {
            const monitor = win.get_monitor ? win.get_monitor() : global.display.get_primary_monitor();
            const monGeo = global.display.get_monitor_geometry(monitor);
            const frameRect = win.get_frame_rect();
            if (!frameRect || frameRect.width < 100 || frameRect.height < 100)
                return false;
            const x = monGeo.x + Math.max(0, Math.round((monGeo.width - frameRect.width) / 2));
            const y = monGeo.y + Math.max(0, Math.round((monGeo.height - frameRect.height) / 2));
            if (win.move_frame) {
                win.move_frame(false, x, y);
            } else if (win.move_resize_frame) {
                win.move_resize_frame(false, x, y, frameRect.width, frameRect.height);
            }
            win._wayplankCentered = true;
            return true;
        } catch (e) {
            console.error('[WayplankBridge] _centerWindow error:', e);
            return false;
        }
    }

    _applyDockPosition(win, x, y, width, height) {
        if (!win || this._classifyWindow(win) !== 'dock')
            return false;
        try {
            win.make_above();
            win.stick();

            let targetMon = -1;
            const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 1;
            const cx = x + Math.floor(width / 2);
            const cy = y + Math.floor(height / 2);

            for (let i = 0; i < nMonitors; i++) {
                const geo = global.display.get_monitor_geometry(i);
                if (cx >= geo.x && cx < geo.x + geo.width &&
                    cy >= geo.y && cy < geo.y + geo.height) {
                    targetMon = i;
                    break;
                }
            }
            if (targetMon === -1) {
                targetMon = (global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0;
            }

            const monGeo = global.display.get_monitor_geometry(targetMon);
            const ws = global.workspace_manager ? global.workspace_manager.get_active_workspace() : null;
            const wa = (ws && ws.get_work_area_for_monitor) ? ws.get_work_area_for_monitor(targetMon) : monGeo;

            let targetX = x;
            let targetY = y;

            const isHorizontal = (width >= height);
            if (isHorizontal) {
                const isTop = (y <= wa.y + 100);
                targetX = Math.max(wa.x, Math.min(x, wa.x + wa.width - width));
                targetY = isTop ? wa.y : (wa.y + wa.height - height);
            } else {
                const isLeft = (x <= wa.x + 100);
                targetX = isLeft ? wa.x : (wa.x + wa.width - width);
                targetY = Math.max(wa.y, Math.min(y, wa.y + wa.height - height));
            }
            this._lastDockGeo = { x: targetX, y: targetY, width, height };

            const move = () => {
                try {
                    if (this._classifyWindow(win) !== 'dock')
                        return;
                    if (win.move_frame) {
                        win.move_frame(false, targetX, targetY);
                    } else if (win.move_resize_frame) {
                        win.move_resize_frame(false, targetX, targetY, width, height);
                    }
                } catch (e) {
                    console.error('[WayplankBridge] move dock error:', e);
                }
            };

            move();
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                move();
                return GLib.SOURCE_REMOVE;
            });
            const act = win.get_compositor_private ? win.get_compositor_private() : null;
            if (act && act.connect) {
                const id = act.connect('first-frame', () => {
                    move();
                    try { act.disconnect(id); } catch (e) { }
                });
            }
            return true;
        } catch (e) {
            console.error('[WayplankBridge] _applyDockPosition error:', e);
            return false;
        }
    }

    _applyHoverPosition(win, x, y, width, height) {
        if (!win || this._classifyWindow(win) !== 'hover')
            return false;
        try {
            win.make_above();
            win.stick();
            if (win.demands_attention)
                win.demands_attention = false;

            let targetX = x;
            let targetY = y;
            const dockWin = this._findDockWindow();
            const dockRect = this._lastDockGeo || (dockWin ? dockWin.get_frame_rect() : null);

            let targetMon = -1;
            const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 1;
            const cx = x + Math.floor((width > 0 ? width : 60) / 2);
            const cy = y + Math.floor((height > 0 ? height : 28) / 2);

            for (let i = 0; i < nMonitors; i++) {
                const geo = global.display.get_monitor_geometry(i);
                if (cx >= geo.x && cx < geo.x + geo.width &&
                    cy >= geo.y && cy < geo.y + geo.height) {
                    targetMon = i;
                    break;
                }
            }
            if (targetMon === -1 && dockWin && dockWin.get_monitor) {
                targetMon = dockWin.get_monitor();
            }

            if (dockRect) {
                const monGeo = (targetMon !== -1) ? global.display.get_monitor_geometry(targetMon) : global.display.get_monitor_geometry(global.display.get_primary_monitor());

                const isHorizontal = dockRect.width >= dockRect.height;
                const isVertical = dockRect.height > dockRect.width;

                const isTop = isHorizontal && dockRect.y < monGeo.y + 120;
                const isBottom = isHorizontal && (dockRect.y + dockRect.height) > (monGeo.y + monGeo.height - 120);
                const isLeft = isVertical && dockRect.x < monGeo.x + 120;
                const isRight = isVertical && (dockRect.x + dockRect.width) > (monGeo.x + monGeo.width - 120);

                const tooltipH = (height && height > 0) ? height : 28;
                const tooltipW = (width && width > 0) ? width : 70;

                if (isTop) {
                    targetY = Math.max(targetY, dockRect.y + dockRect.height + 6);
                } else if (isBottom) {
                    targetY = Math.min(targetY, dockRect.y - tooltipH - 6);
                } else if (isLeft) {
                    targetX = Math.max(targetX, dockRect.x + dockRect.width + 6);
                } else if (isRight) {
                    targetX = Math.min(targetX, dockRect.x - tooltipW - 6);
                }
            }

            const move = () => {
                try {
                    if (this._classifyWindow(win) !== 'hover')
                        return;
                    if (win.move_frame) {
                        win.move_frame(false, targetX, targetY);
                    } else if (win.move_resize_frame) {
                        const frameRect = win.get_frame_rect();
                        const w = (width && width > 0) ? width : frameRect.width;
                        const h = (height && height > 0) ? height : frameRect.height;
                        win.move_resize_frame(false, targetX, targetY, w, h);
                    }
                } catch (e) {
                    console.error('[WayplankBridge] move hover error:', e);
                }
            };

            move();
            const act = win.get_compositor_private ? win.get_compositor_private() : null;
            if (act && act.connect) {
                const id = act.connect('first-frame', () => {
                    move();
                    try { act.disconnect(id); } catch (e) { }
                });
            }
            return true;
        } catch (e) {
            console.error('[WayplankBridge] _applyHoverPosition error:', e);
            return false;
        }
    }

    _applyPoofPosition(win, x, y, width, height) {
        if (!win)
            return false;
        try {
            win.make_above();
            win.stick();
            if (win.demands_attention)
                win.demands_attention = false;
            win._wayplankCentered = true;

            let targetMon = -1;
            const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 1;
            const cx = x + Math.floor((width > 0 ? width : 64) / 2);
            const cy = y + Math.floor((height > 0 ? height : 64) / 2);

            for (let i = 0; i < nMonitors; i++) {
                const geo = global.display.get_monitor_geometry(i);
                if (cx >= geo.x && cx < geo.x + geo.width &&
                    cy >= geo.y && cy < geo.y + geo.height) {
                    targetMon = i;
                    break;
                }
            }
            if (targetMon !== -1 && win.get_monitor && win.get_monitor() !== targetMon && win.move_to_monitor) {
                try { win.move_to_monitor(targetMon); } catch (e) { }
            }

            const move = () => {
                try {
                    if (win.move_frame) {
                        win.move_frame(false, x, y);
                    }
                    if (win.move_resize_frame) {
                        win.move_resize_frame(false, x, y, width, height);
                    }
                } catch (e) {
                    console.error('[WayplankBridge] move poof error:', e);
                }
            };

            move();
            const act = win.get_compositor_private ? win.get_compositor_private() : null;
            if (act && act.connect) {
                const id = act.connect('first-frame', () => {
                    move();
                    try { act.disconnect(id); } catch (e) { }
                });
            }
            return true;
        } catch (e) {
            console.error('[WayplankBridge] _applyPoofPosition error:', e);
            return false;
        }
    }

    _connectWindow(win) {
        if (!win || this._windowSignals.has(win))
            return;

        const applyRole = (targetWin) => {
            let kind = this._classifyWindow(targetWin);
            if (kind === 'unknown' && this._lastPoofGeo && (Date.now() - (this._lastPoofTime || 0) < 3000)) {
                const title = (targetWin.get_title ? targetWin.get_title() : '') || '';
                const lowerTitle = title.toLowerCase();
                if (lowerTitle !== 'wayplank' && !lowerTitle.includes('hover') && !lowerTitle.includes('prefer') && !lowerTitle.includes('help')) {
                    kind = 'poof';
                }
            }
            if (kind === 'dock') {
                if (this._lastDockGeo) {
                    const { x, y, width, height } = this._lastDockGeo;
                    this._applyDockPosition(targetWin, x, y, width, height);
                } else {
                    try {
                        const monitor = (global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0;
                        const monGeo = global.display.get_monitor_geometry(monitor);
                        const frameRect = targetWin.get_frame_rect();
                        const dockH = frameRect.height > 0 ? frameRect.height : 64;
                        this._applyDockPosition(targetWin, monGeo.x, monGeo.y + monGeo.height - dockH, monGeo.width, dockH);
                    } catch (e) { }
                }
            } else if (kind === 'hover') {
                try { targetWin.demands_attention = false; } catch (e) { }
                if (this._lastHoverGeo) {
                    const { x, y, width, height } = this._lastHoverGeo;
                    this._applyHoverPosition(targetWin, x, y, width, height);
                }
            } else if (kind === 'poof') {
                try { targetWin.demands_attention = false; } catch (e) { }
                targetWin._wayplankCentered = true;
                if (this._lastPoofGeo) {
                    const { x, y, width, height } = this._lastPoofGeo;
                    this._applyPoofPosition(targetWin, x, y, width, height);
                }
            } else if (kind === 'dialog') {
                try {
                    targetWin.demands_attention = false;
                    targetWin.activate(global.get_current_time());
                } catch (e) { }
                this._centerWindow(targetWin);
                const act = targetWin.get_compositor_private ? targetWin.get_compositor_private() : null;
                if (act && act.connect) {
                    const id = act.connect('first-frame', () => {
                        this._centerWindow(targetWin);
                        try { act.disconnect(id); } catch (e) { }
                    });
                }
            }
        };

        applyRole(win);

        const sigs = [];
        sigs.push(win.connect('unmanaged', () => {
            this._windowSignals.delete(win);
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('notify::minimized', () => {
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('notify::maximized-horizontally', () => {
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('notify::maximized-vertically', () => {
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('position-changed', () => {
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('size-changed', () => {
            const currentKind = this._classifyWindow(win);
            if (currentKind === 'dialog') {
                this._centerWindow(win);
            } else if (currentKind === 'dock' && this._lastDockGeo) {
                const { x, y, width, height } = this._lastDockGeo;
                this._applyDockPosition(win, x, y, width, height);
            }
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('notify::title', () => {
            applyRole(win);
            this._notifyWindowsChanged();
        }));

        this._windowSignals.set(win, sigs);
    }

    _findPoofWindow() {
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (win && this._classifyWindow(win) === 'poof')
                return win;
        }
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (!win) continue;
            const kind = this._classifyWindow(win);
            if (kind === 'poof') return win;
            if (kind === 'unknown') {
                const title = (win.get_title ? win.get_title() : '') || '';
                const lowerTitle = title.toLowerCase();
                if (lowerTitle !== 'wayplank' && !lowerTitle.includes('hover') && !lowerTitle.includes('prefer') && !lowerTitle.includes('help'))
                    return win;
            }
        }
        return null;
    }

    _findHoverWindow() {
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (win && this._classifyWindow(win) === 'hover')
                return win;
        }
        return null;
    }

    _findDockWindow() {
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (win && this._classifyWindow(win) === 'dock')
                return win;
        }
        return null;
    }

    _notifyWindowsChanged() {
        if (this._notifyTimeout) {
            GLib.Source.remove(this._notifyTimeout);
            this._notifyTimeout = 0;
        }
        this._notifyTimeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
            this._notifyTimeout = 0;
            if (this._dbusImpl) {
                try {
                    this._dbusImpl.emit_signal('WindowsChanged', null);
                } catch (e) { }
            }
            return GLib.SOURCE_REMOVE;
        });
    }

    // D-Bus Method: GetWindows
    GetWindows() {
        const tracker = Shell.WindowTracker.get_default();
        const result = [];
        const winList = (global.display && global.display.list_all_windows)
            ? global.display.list_all_windows()
            : global.get_window_actors().map(a => a.meta_window).filter(Boolean);

        const ws = global.workspace_manager ? global.workspace_manager.get_active_workspace() : null;
        const tabList = (global.display && global.display.get_tab_list)
            ? global.display.get_tab_list(Meta.TabList.NORMAL, ws)
            : [];
        const topWin = (tabList && tabList.length > 0) ? tabList[0] : null;
        const focusWin = global.display.get_focus_window ? global.display.get_focus_window() : global.display.focus_window;
        const focusId = focusWin ? (focusWin.get_stable_sequence ? focusWin.get_stable_sequence().toString() : (focusWin.get_id ? focusWin.get_id().toString() : null)) : null;

        for (const win of winList) {
            if (!win)
                continue;

            if (this._classifyWindow(win) !== 'other')
                continue;

            const windowType = win.get_window_type();
            if (windowType !== Meta.WindowType.NORMAL && windowType !== Meta.WindowType.DIALOG)
                continue;

            if (win.is_skip_taskbar())
                continue;

            const id = win.get_stable_sequence ? win.get_stable_sequence().toString() : win.get_id().toString();
            const app = tracker.get_window_app(win);
            const desktopFileName = app ? app.get_id() : '';
            const wmClass = win.get_wm_class ? win.get_wm_class() : '';
            const gtkAppId = win.get_gtk_application_id ? win.get_gtk_application_id() : '';
            const title = win.get_title ? win.get_title() : '';
            const isMinimized = win.minimized;
            const isTop = (win === topWin) || (win === focusWin) || (focusId === id) || (this._lastActiveUuid === id) || (win.has_focus ? win.has_focus() : false);
            const isActive = !isMinimized && isTop;
            const isMaximized = win.maximized_horizontally && win.maximized_vertically;
            const demandsAttention = win.demands_attention ? win.demands_attention : false;
            const frameRect = win.get_frame_rect ? win.get_frame_rect() : null;
            const x = frameRect ? frameRect.x : 0;
            const y = frameRect ? frameRect.y : 0;
            const width = frameRect ? frameRect.width : 0;
            const height = frameRect ? frameRect.height : 0;

            let onCurrentWorkspace = false;
            if (!ws || (win.is_on_all_workspaces && win.is_on_all_workspaces())) {
                onCurrentWorkspace = true;
            } else if (win.located_on_workspace && win.located_on_workspace(ws)) {
                onCurrentWorkspace = true;
            } else {
                const winWs = win.get_workspace ? win.get_workspace() : null;
                if (winWs) {
                    if (typeof winWs.index === 'function' && typeof ws.index === 'function') {
                        onCurrentWorkspace = (winWs.index() === ws.index());
                    } else {
                        onCurrentWorkspace = (winWs === ws);
                    }
                }
            }

            result.push({
                uuid: id,
                desktopFileName: desktopFileName || '',
                resourceClass: wmClass || '',
                resourceName: gtkAppId || '',
                caption: title || '',
                active: isActive,
                minimized: isMinimized,
                maximized: isMaximized,
                demandsAttention: demandsAttention,
                x: x,
                y: y,
                width: width,
                height: height,
                currentDesktop: onCurrentWorkspace
            });
        }

        return JSON.stringify(result);
    }

    _findWindowByUuid(uuid) {
        if (global.display && global.display.list_all_windows) {
            for (const win of global.display.list_all_windows()) {
                if (!win) continue;
                const id = win.get_stable_sequence ? win.get_stable_sequence().toString() : win.get_id().toString();
                if (id === uuid)
                    return win;
            }
        }
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (!win)
                continue;
            const id = win.get_stable_sequence ? win.get_stable_sequence().toString() : win.get_id().toString();
            if (id === uuid)
                return win;
        }
        return null;
    }

    // D-Bus Method: ActivateWindow
    ActivateWindow(uuid) {
        const win = this._findWindowByUuid(uuid);
        if (win) {
            if (win.minimized)
                win.unminimize();
            if (Main.activateWindow)
                Main.activateWindow(win);
            else
                win.activate(global.get_current_time());
            this._lastActiveUuid = uuid;
            return true;
        }
        return false;
    }

    // D-Bus Method: MinimizeWindow
    MinimizeWindow(uuid) {
        const win = this._findWindowByUuid(uuid);
        if (win) {
            win.minimize();
            if (this._lastActiveUuid === uuid)
                this._lastActiveUuid = null;
            return true;
        }
        return false;
    }

    // D-Bus Method: ToggleWindow
    ToggleWindow(uuid) {
        const win = this._findWindowByUuid(uuid);
        if (win) {
            if (win.minimized) {
                win.unminimize();
                if (Main.activateWindow)
                    Main.activateWindow(win);
                else
                    win.activate(global.get_current_time());
                this._lastActiveUuid = uuid;
                return true;
            }

            const ws = global.workspace_manager ? global.workspace_manager.get_active_workspace() : null;
            const tabList = (global.display && global.display.get_tab_list)
                ? global.display.get_tab_list(Meta.TabList.NORMAL, ws)
                : [];
            const topWin = (tabList && tabList.length > 0) ? tabList[0] : null;
            const focusWin = global.display.get_focus_window ? global.display.get_focus_window() : global.display.focus_window;
            const focusId = focusWin ? (focusWin.get_stable_sequence ? focusWin.get_stable_sequence().toString() : (focusWin.get_id ? focusWin.get_id().toString() : null)) : null;
            const isCurrent = (win === topWin) || (win === focusWin) || (focusId === uuid) || (this._lastActiveUuid === uuid) || (tabList.length <= 1);

            if (isCurrent) {
                win.minimize();
                if (this._lastActiveUuid === uuid)
                    this._lastActiveUuid = null;
            } else {
                if (Main.activateWindow)
                    Main.activateWindow(win);
                else
                    win.activate(global.get_current_time());
                this._lastActiveUuid = uuid;
            }
            return true;
        }
        return false;
    }

    // D-Bus Method: CloseWindow
    CloseWindow(uuid) {
        const win = this._findWindowByUuid(uuid);
        if (win) {
            win.delete(global.get_current_time());
            return true;
        }
        return false;
    }

    // D-Bus Method: ToggleDesktop
    ToggleDesktop() {
        const ws = global.workspace_manager.get_active_workspace();
        const windows = ws.list_windows().filter(w => {
            const t = w.get_window_type();
            return (t === Meta.WindowType.NORMAL || t === Meta.WindowType.DIALOG) && !w.is_skip_taskbar() && this._classifyWindow(w) === 'other';
        });

        const anyVisible = windows.some(w => !w.minimized);
        if (anyVisible) {
            this._desktopRestoredWindows = [];
            for (const win of windows) {
                if (!win.minimized) {
                    this._desktopRestoredWindows.push(win);
                    win.minimize();
                }
            }
        } else {
            if (this._desktopRestoredWindows && this._desktopRestoredWindows.length > 0) {
                for (const win of this._desktopRestoredWindows) {
                    try { win.unminimize(); } catch (e) {}
                }
                this._desktopRestoredWindows = [];
            } else {
                for (const win of windows) {
                    win.unminimize();
                }
            }
        }
        return true;
    }

    // D-Bus Method: GetMonitorWorkAreas
    GetMonitorWorkAreas() {
        try {
            const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 1;
            const ws = global.workspace_manager ? global.workspace_manager.get_active_workspace() : null;
            const res = [];
            for (let i = 0; i < nMonitors; i++) {
                const g = global.display.get_monitor_geometry(i);
                let wa = g;
                if (ws && ws.get_work_area_for_monitor) {
                    try { wa = ws.get_work_area_for_monitor(i); } catch (e) { }
                }
                res.push({
                    x: g.x,
                    y: g.y,
                    width: g.width,
                    height: g.height,
                    wa_x: wa.x,
                    wa_y: wa.y,
                    wa_width: wa.width,
                    wa_height: wa.height
                });
            }
            return JSON.stringify(res);
        } catch (e) {
            return JSON.stringify([]);
        }
    }

    // D-Bus Method: GetPrimaryMonitor
    GetPrimaryMonitor() {
        const pMon = (global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0;
        const geo = (global.display && global.display.get_monitor_geometry) ? global.display.get_monitor_geometry(pMon) : { x: 0, y: 0, width: 1920, height: 1080 };
        return JSON.stringify({ x: geo.x, y: geo.y, width: geo.width, height: geo.height });
    }

    // D-Bus Method: PositionDock
    PositionDock(x, y, width, height) {
        this._lastDockGeo = { x, y, width, height };
        this._lastHoverGeo = null;
        const win = this._findDockWindow();
        if (win) {
            return this._applyDockPosition(win, x, y, width, height);
        }
        return false;
    }

    // D-Bus Method: PositionHover
    PositionHover(x, y, width, height) {
        this._lastHoverGeo = { x, y, width, height };
        const win = this._findHoverWindow();
        if (win) {
            return this._applyHoverPosition(win, x, y, width, height);
        }
        return false;
    }

    // D-Bus Method: PositionPoof
    PositionPoof(x, y, width, height) {
        this._lastPoofGeo = { x, y, width, height };
        this._lastPoofTime = Date.now();
        const win = this._findPoofWindow();
        if (win) {
            return this._applyPoofPosition(win, x, y, width, height);
        }
        return false;
    }
}
""";

		public MutterBackend ()
		{
			instance = this;
		}

		public static unowned MutterBackend get_default ()
		{
			if (instance == null)
				instance = new MutterBackend ();
			return instance;
		}

		public bool start ()
		{
			if (started)
				return true;

			started = true;
			ensure_extension_installed ();
			try {
				Process.spawn_command_line_async ("gnome-extensions enable " + EXTENSION_UUID);
			} catch (Error e) { }
			connect_bridge ();
			return true;
		}

		void ensure_extension_installed ()
		{
			var ext_dir = Path.build_filename (Environment.get_user_data_dir (), "gnome-shell", "extensions", EXTENSION_UUID);
			var js_file = Path.build_filename (ext_dir, "extension.js");
			var meta_file = Path.build_filename (ext_dir, "metadata.json");

			string? current_js = null;
			if (FileUtils.test (js_file, FileTest.EXISTS)) {
				try {
					FileUtils.get_contents (js_file, out current_js);
				} catch (Error e) { }
			}

			if (current_js == EXTENSION_JS && FileUtils.test (meta_file, FileTest.EXISTS))
				return;

			try {
				DirUtils.create_with_parents (ext_dir, 0755);
				FileUtils.set_contents (meta_file, EXTENSION_METADATA);
				FileUtils.set_contents (js_file, EXTENSION_JS);
				// Reload extension in GNOME Shell
				Process.spawn_command_line_async ("gnome-extensions disable " + EXTENSION_UUID);
				GLib.Timeout.add (300, () => {
					try {
						Process.spawn_command_line_async ("gnome-extensions enable " + EXTENSION_UUID);
					} catch (Error e) { }
					return false;
				});
			} catch (Error e) {
				warning ("MutterBackend: failed to deploy extension: %s", e.message);
			}
		}

		void connect_bridge ()
		{
			name_watch_id = Bus.watch_name (
				BusType.SESSION,
				"org.wayplank.GnomeBridge",
				BusNameWatcherFlags.NONE,
				on_bridge_appeared,
				on_bridge_vanished
			);
		}

		void on_bridge_appeared (DBusConnection connection, string name, string name_owner)
		{
			try {
				proxy = Bus.get_proxy_sync (
					BusType.SESSION,
					"org.wayplank.GnomeBridge",
					"/org/wayplank/GnomeBridge"
				);
				proxy.windows_changed.connect (on_windows_changed);
				try {
					proxy.eval ("""
						this._applyDockPosition = function(win, x, y, width, height) {
							if (!win || this._classifyWindow(win) !== "dock") return false;
							try {
								win.make_above();
								win.stick();
								let targetMon = -1;
								const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 1;
								const cx = x + Math.floor(width / 2);
								const cy = y + Math.floor(height / 2);
								for (let i = 0; i < nMonitors; i++) {
									const geo = global.display.get_monitor_geometry(i);
									if (cx >= geo.x && cx < geo.x + geo.width && cy >= geo.y && cy < geo.y + geo.height) {
										targetMon = i;
										break;
									}
								}
								if (targetMon === -1) targetMon = (global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0;
								const monGeo = global.display.get_monitor_geometry(targetMon);
								const ws = global.workspace_manager ? global.workspace_manager.get_active_workspace() : null;
								const wa = (ws && ws.get_work_area_for_monitor) ? ws.get_work_area_for_monitor(targetMon) : monGeo;
								let targetX = x;
								let targetY = y;
								const isHorizontal = (width >= height);
								if (isHorizontal) {
									const isTop = (y <= wa.y + 100);
									targetX = Math.max(wa.x, Math.min(x, wa.x + wa.width - width));
									targetY = isTop ? wa.y : (wa.y + wa.height - height);
								} else {
									const isLeft = (x <= wa.x + 100);
									targetX = isLeft ? wa.x : (wa.x + wa.width - width);
									targetY = Math.max(wa.y, Math.min(y, wa.y + wa.height - height));
								}
								this._lastDockGeo = { x: targetX, y: targetY, width, height };
								const move = () => {
									try {
										if (this._classifyWindow(win) !== "dock") return;
										if (win.move_frame) win.move_frame(false, targetX, targetY);
										else if (win.move_resize_frame) win.move_resize_frame(false, targetX, targetY, width, height);
									} catch (e) { }
								};
								move();
								GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => { move(); return GLib.SOURCE_REMOVE; });
								return true;
							} catch (e) { return false; }
						};
					""");
				} catch (Error e) { }
				refresh_window_infos ();
				primary_monitor_changed ();
				state_changed ();
				if (last_width > 0 && last_height > 0) {
					try {
						proxy.position_dock (last_x, last_y, last_width, last_height);
					} catch (Error e) { }
				}
				GLib.Timeout.add (250, () => {
					if (proxy != null && last_width > 0 && last_height > 0) {
						try {
							proxy.position_dock (last_x, last_y, last_width, last_height);
						} catch (Error e) { }
					}
					return false;
				});
			} catch (Error e) {
				debug ("MutterBackend: unable to connect to GnomeBridge: %s", e.message);
			}
		}

		void on_bridge_vanished (DBusConnection connection, string name)
		{
			proxy = null;
			window_infos.clear ();
			state_changed ();
		}

		void on_windows_changed ()
		{
			refresh_window_infos ();
			state_changed ();
		}

		void refresh_window_infos ()
		{
			if (proxy == null)
				return;
			try {
				var json = proxy.get_windows ();
				window_infos = parse_window_infos (json);
			} catch (Error e) {
				debug ("MutterBackend: get_windows failed: %s", e.message);
			}
		}

		static Gee.ArrayList<WindowInfo> parse_window_infos (string state)
		{
			var result = new Gee.ArrayList<WindowInfo> ();
			try {
				var parser = new Json.Parser ();
				parser.load_from_data (state);
				var root = parser.get_root ();
				if (root == null || root.get_node_type () != Json.NodeType.ARRAY)
					return result;
				foreach (var node in root.get_array ().get_elements ()) {
					var json = node.get_object ();
					if (!json.has_member ("uuid"))
						continue;
					var info = new WindowInfo ();
					info.Id = json.get_string_member ("uuid");

					var desktop_val = (json.has_member ("desktopFileName") && !json.get_null_member ("desktopFileName")) ? json.get_string_member ("desktopFileName") : "";
					var class_val = (json.has_member ("resourceClass") && !json.get_null_member ("resourceClass")) ? json.get_string_member ("resourceClass") : "";
					var name_val = (json.has_member ("resourceName") && !json.get_null_member ("resourceName")) ? json.get_string_member ("resourceName") : "";
					var caption_val = (json.has_member ("caption") && !json.get_null_member ("caption")) ? json.get_string_member ("caption") : "";

					info.DesktopFileName = desktop_val != null ? desktop_val : "";
					info.ResourceClass = class_val != null ? class_val : "";
					info.ResourceName = name_val != null ? name_val : "";
					info.Caption = caption_val != null ? caption_val : "";

					if (info.DesktopFileName != "")
						info.ApplicationId = normalize_resource_id (info.DesktopFileName);
					else if (info.ResourceClass != "")
						info.ApplicationId = normalize_resource_id (info.ResourceClass);
					else if (info.ResourceName != "")
						info.ApplicationId = normalize_resource_id (info.ResourceName);
					else
						info.ApplicationId = "";

					info.Minimized = json.has_member ("minimized") && json.get_boolean_member ("minimized");
					info.Active = json.has_member ("active") && json.get_boolean_member ("active");
					info.Maximized = json.has_member ("maximized") && json.get_boolean_member ("maximized");
					info.DemandsAttention = json.has_member ("demandsAttention") && json.get_boolean_member ("demandsAttention");
					info.CurrentDesktop = !json.has_member ("currentDesktop") || json.get_boolean_member ("currentDesktop");
					if (json.has_member ("x") && json.has_member ("y") && json.has_member ("width") && json.has_member ("height")) {
						info.Geometry = {
							(int) json.get_double_member ("x"),
							(int) json.get_double_member ("y"),
							(int) json.get_double_member ("width"),
							(int) json.get_double_member ("height")
						};
					}
					result.add (info);
				}
			} catch (Error e) {
				debug ("Unable to parse GNOME window state: %s", e.message);
			}
			return result;
		}

		static string normalize_resource_id (string id)
		{
			var normalized = id.down ();
			if (normalized.has_suffix (".desktop"))
				normalized = normalized.substring (0, normalized.length - ".desktop".length);
			return normalized;
		}

		public void cleanup ()
		{
			if (name_watch_id > 0U) {
				Bus.unwatch_name (name_watch_id);
				name_watch_id = 0U;
			}
			proxy = null;
			started = false;
		}

		~MutterBackend ()
		{
			cleanup ();
			if (instance == this)
				instance = null;
		}

		public bool has_state ()
		{
			return started && proxy != null;
		}

		public void register_dbus (DBusConnection connection, string object_path) throws GLib.IOError
		{
		}

		public Gee.ArrayList<WindowInfo> get_windows ()
		{
			var result = new Gee.ArrayList<WindowInfo> ();
			result.add_all (window_infos);
			return result;
		}

		public bool queue_command (string target, string action)
		{
			if (proxy == null)
				return false;
			try {
				switch (action) {
				case "activate":
					return proxy.activate_window (target);
				case "minimize":
					return proxy.minimize_window (target);
				case "toggle":
					return proxy.toggle_window (target);
				case "close":
					return proxy.close_window (target);
				case "toggle_desktop":
					return proxy.toggle_desktop ();
				default:
					return proxy.activate_window (target);
				}
			} catch (Error e) {
				warning ("MutterBackend queue_command failed: %s", e.message);
				return false;
			}
		}

		public bool any_window_intersects (Gdk.Rectangle rect)
		{
			return window_intersects (rect, false, false);
		}

		public bool active_window_intersects (Gdk.Rectangle rect)
		{
			return window_intersects (rect, true, false);
		}

		public bool maximized_window_intersects (Gdk.Rectangle rect)
		{
			return window_intersects (rect, false, true);
		}

		bool window_intersects (Gdk.Rectangle dock_rect, bool active_only, bool maximized_only)
		{
			foreach (var window in window_infos) {
				if (window.Minimized)
					continue;
				if (!window.CurrentDesktop)
					continue;
				if (window.ResourceClass.down () == "wayplank" || window.DesktopFileName.down () == "wayplank")
					continue;
				if (active_only && !window.Active)
					continue;
				if (maximized_only && !window.Maximized)
					continue;

				if (window.Geometry.width <= 0 || window.Geometry.height <= 0)
					continue;

				if (window.Geometry.intersect (dock_rect, null))
					return true;
			}
			return false;
		}

		public void handle_system_resume ()
		{
			refresh_window_infos ();
			state_changed ();
		}

		public bool position_dock (int x, int y, int width, int height)
		{
			last_x = x;
			last_y = y;
			last_width = width;
			last_height = height;
			if (proxy == null)
				return false;
			try {
				return proxy.position_dock (x, y, width, height);
			} catch (Error e) {
				return false;
			}
		}

		public bool position_hover (int x, int y, int width, int height)
		{
			if (proxy == null)
				return false;
			try {
				return proxy.position_hover (x, y, width, height);
			} catch (Error e) {
				debug ("MutterBackend: position_hover D-Bus: %s", e.message);
				return false;
			}
		}

		public bool position_poof (int x, int y, int width, int height)
		{
			if (proxy == null)
				return false;
			try {
				return proxy.position_poof (x, y, width, height);
			} catch (Error e) {
				debug ("MutterBackend: position_poof D-Bus: %s", e.message);
				return false;
			}
		}

		public bool get_primary_monitor_geometry (out int x, out int y, out int width, out int height)
		{
			x = 0; y = 0; width = 0; height = 0;
			if (proxy != null) {
				try {
					var json_str = proxy.get_primary_monitor ();
					var parser = new Json.Parser ();
					parser.load_from_data (json_str);
					var obj = parser.get_root ().get_object ();
					x = (int) obj.get_int_member ("x");
					y = (int) obj.get_int_member ("y");
					width = (int) obj.get_int_member ("width");
					height = (int) obj.get_int_member ("height");
					return true;
				} catch (Error e) {
					// Fallback to Mutter DisplayConfig below
				}
			}

			try {
				var bus = Bus.get_sync (BusType.SESSION);
				var reply = bus.call_sync (
					"org.gnome.Mutter.DisplayConfig",
					"/org/gnome/Mutter/DisplayConfig",
					"org.gnome.Mutter.DisplayConfig",
					"GetCurrentState",
					null,
					new VariantType ("(ua((ssss)a(siiddada{sv})a{sv})a(iiduba(ssss)a{sv})a{sv})"),
					DBusCallFlags.NONE,
					1000
				);
				var lms = reply.get_child_value (2);
				for (size_t i = 0; i < lms.n_children (); i++) {
					var lm = lms.get_child_value (i);
					bool is_primary = lm.get_child_value (4).get_boolean ();
					if (is_primary) {
						x = lm.get_child_value (0).get_int32 ();
						y = lm.get_child_value (1).get_int32 ();
						return true;
					}
				}
			} catch (Error e) { }

			return false;
		}

		public bool get_workarea_for_geometry (Gdk.Rectangle mon_geom, out Gdk.Rectangle workarea)
		{
			workarea = mon_geom;
			message ("MutterBackend.get_workarea_for_geometry for %d,%d %dx%d (proxy=%s)",
				mon_geom.x, mon_geom.y, mon_geom.width, mon_geom.height, proxy != null ? "connected" : "null");
			if (proxy != null) {
				try {
					string json_str;
					try {
						json_str = proxy.get_monitor_workareas ();
					} catch (Error e) {
						message ("MutterBackend: get_monitor_workareas failed (%s), trying eval fallback", e.message);
						json_str = proxy.eval ("""
							(() => {
								const n = global.display.get_n_monitors();
								const ws = global.workspace_manager.get_active_workspace();
								const res = [];
								for (let i = 0; i < n; i++) {
									const g = global.display.get_monitor_geometry(i);
									const wa = ws ? ws.get_work_area_for_monitor(i) : g;
									res.push({ x: g.x, y: g.y, width: g.width, height: g.height, wa_x: wa.x, wa_y: wa.y, wa_width: wa.width, wa_height: wa.height });
								}
								return res;
							})()
						""");
					}
					var parser = new Json.Parser ();
					parser.load_from_data (json_str);
					var root = parser.get_root ();
					if (root == null)
						return false;
					if (root.get_node_type () == Json.NodeType.VALUE && root.get_value_type () == typeof (string)) {
						var inner_parser = new Json.Parser ();
						inner_parser.load_from_data (root.get_string ());
						root = inner_parser.get_root ();
					}
					if (root == null || root.get_node_type () != Json.NodeType.ARRAY)
						return false;
					var array = root.get_array ();
					for (uint i = 0; i < array.get_length (); i++) {
						var obj = array.get_object_element (i);
						int gx = (int) obj.get_int_member ("x");
						int gy = (int) obj.get_int_member ("y");
						if (gx == mon_geom.x && gy == mon_geom.y) {
							workarea = Gdk.Rectangle () {
								x = (int) obj.get_int_member ("wa_x"),
								y = (int) obj.get_int_member ("wa_y"),
								width = (int) obj.get_int_member ("wa_width"),
								height = (int) obj.get_int_member ("wa_height")
							};
							message ("MutterBackend: matched workarea for %d,%d: wa=%d,%d %dx%d",
								gx, gy, workarea.x, workarea.y, workarea.width, workarea.height);
							return true;
						}
					}
					message ("MutterBackend: NO match for %d,%d in %u monitor workareas",
						mon_geom.x, mon_geom.y, array.get_length ());
				} catch (Error e) {
					warning ("MutterBackend: failed to get monitor workareas: %s", e.message);
				}
			}
			return false;
		}
	}
}
