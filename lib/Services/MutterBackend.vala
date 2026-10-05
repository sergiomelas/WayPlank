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
		public abstract bool activate_window (string uuid) throws GLib.Error;
		public abstract bool minimize_window (string uuid) throws GLib.Error;
		public abstract bool toggle_window (string uuid) throws GLib.Error;
		public abstract bool close_window (string uuid) throws GLib.Error;
		public abstract bool toggle_desktop () throws GLib.Error;
		public abstract bool position_dock (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_hover (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_poof (int x, int y, int width, int height) throws GLib.Error;
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
  "version": 4
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
        this._signals.push(display.connect('notify::focus-window', () => {
            this._notifyWindowsChanged();
        }));
        this._signals.push(display.connect('restacked', () => {
            this._notifyWindowsChanged();
        }));

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
    }

    _classifyWindow(win) {
        if (!win) return 'unknown';

        const title = (win.get_title ? win.get_title() : '') || '';
        const role = (win.get_role ? win.get_role() : '') || '';
        const wmClass = (win.get_wm_class ? win.get_wm_class() : '') || '';
        const gtkAppId = (win.get_gtk_application_id ? win.get_gtk_application_id() : '') || '';
        const tracker = Shell.WindowTracker.get_default();
        const app = tracker.get_window_app ? tracker.get_window_app(win) : null;
        const appId = app ? app.get_id() : '';
        const sandboxedId = (win.get_sandboxed_app_id ? win.get_sandboxed_app_id() : '') || '';

        const idStr = `${wmClass} ${appId} ${gtkAppId} ${title} ${sandboxedId}`.toLowerCase();
        if (!idStr.includes('wayplank') && !idStr.includes('plank'))
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

            const move = () => {
                try {
                    if (this._classifyWindow(win) !== 'dock')
                        return;
                    if (win.move_frame) {
                        win.move_frame(false, x, y);
                    } else if (win.move_resize_frame) {
                        const frameRect = win.get_frame_rect();
                        const w = (width && width > 0) ? width : frameRect.width;
                        const h = (height && height > 0) ? height : frameRect.height;
                        win.move_resize_frame(false, x, y, w, h);
                    }
                } catch (e) {
                    console.error('[WayplankBridge] move dock error:', e);
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
            if (dockWin) {
                const dockRect = dockWin.get_frame_rect();
                const monitor = dockWin.get_monitor ? dockWin.get_monitor() : global.display.get_primary_monitor();
                const monGeo = global.display.get_monitor_geometry(monitor);

                const isTop = dockRect.y < monGeo.y + 120;
                const isBottom = (dockRect.y + dockRect.height) > (monGeo.y + monGeo.height - 120);
                const isLeft = dockRect.x < monGeo.x + 120;
                const isRight = (dockRect.x + dockRect.width) > (monGeo.x + monGeo.width - 120);

                const tooltipH = (height && height > 0) ? height : 28;
                const tooltipW = (width && width > 0) ? width : 70;

                if (isTop && !isLeft && !isRight) {
                    targetY = Math.max(targetY, dockRect.y + dockRect.height + 6);
                } else if (isBottom && !isLeft && !isRight) {
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
                        const monitor = targetWin.get_monitor ? targetWin.get_monitor() : global.display.get_primary_monitor();
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
        sigs.push(win.connect('size-changed', () => {
            const currentKind = this._classifyWindow(win);
            if (currentKind === 'dialog') {
                this._centerWindow(win);
            }
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

        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
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
            const isActive = win.has_focus ? win.has_focus() : false;
            const isMinimized = win.minimized;
            const isMaximized = win.maximized_horizontally && win.maximized_vertically;
            const demandsAttention = win.demands_attention ? win.demands_attention : false;

            result.push({
                uuid: id,
                desktopFileName: desktopFileName || '',
                resourceClass: wmClass || '',
                resourceName: gtkAppId || '',
                caption: title || '',
                active: isActive,
                minimized: isMinimized,
                maximized: isMaximized,
                demandsAttention: demandsAttention
            });
        }

        return JSON.stringify(result);
    }

    _findWindowByUuid(uuid) {
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
            win.activate(global.get_current_time());
            return true;
        }
        return false;
    }

    // D-Bus Method: MinimizeWindow
    MinimizeWindow(uuid) {
        const win = this._findWindowByUuid(uuid);
        if (win) {
            win.minimize();
            return true;
        }
        return false;
    }

    // D-Bus Method: ToggleWindow
    ToggleWindow(uuid) {
        const win = this._findWindowByUuid(uuid);
        if (win) {
            if (win.has_focus() && !win.minimized) {
                win.minimize();
            } else {
                if (win.minimized)
                    win.unminimize();
                win.activate(global.get_current_time());
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

    // D-Bus Method: PositionDock
    PositionDock(x, y, width, height) {
        this._lastDockGeo = { x, y, width, height };
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
				refresh_window_infos ();
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
					info.CurrentDesktop = true;
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
			return false;
		}

		public bool active_window_intersects (Gdk.Rectangle rect)
		{
			return false;
		}

		public bool maximized_window_intersects (Gdk.Rectangle rect)
		{
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
	}
}
