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
	[DBus (name = "org.wayplank.GnomeBridge")]
	public interface GnomeBridgeProxy : GLib.Object
	{
		public abstract string get_windows () throws GLib.Error;
		public abstract string get_primary_monitor () throws GLib.Error;
		[DBus (name = "GetMonitorWorkAreas")]
		public abstract string get_monitor_workareas () throws GLib.Error;
		public abstract bool activate_window (string uuid) throws GLib.Error;
		public abstract bool minimize_window (string uuid) throws GLib.Error;
		public abstract bool toggle_window (string uuid) throws GLib.Error;
		public abstract bool close_window (string uuid) throws GLib.Error;
		public abstract bool toggle_desktop () throws GLib.Error;
		public abstract bool position_dock (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_hover (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_poof (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool set_reserve_space (bool enabled, int thickness, int position) throws GLib.Error;
		public abstract string eval (string code) throws GLib.Error;
		public abstract bool capture_window (string uuid, string filename) throws GLib.Error;
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
		uint ext_enable_timer_id = 0U;
		uint bridge_reposition_timer_id = 0U;

		int last_x = -1;
		int last_y = -1;
		int last_width = -1;
		int last_height = -1;
		bool last_reserve_enabled = false;
		int last_reserve_thickness = 0;
		int last_reserve_position = -1;

		const string EXTENSION_UUID = "wayplank-bridge@wayplank.org";

		const string EXTENSION_METADATA = """{
  "name": "WayPlank Bridge",
  "description": "Native GNOME Shell bridge for WayPlank dock",
  "uuid": "wayplank-bridge@wayplank.org",
  "shell-version": ["45", "46", "47", "48", "49", "50", "51"],
  "url": "https://github.com/wayplank",
  "version": 3
}
""";

		// Stable loader deployed as extension.js. GNOME Shell (45+) caches ES modules by URL, so a
		// disable/enable cycle never reloads a modified extension.js. The loader instead imports the
		// real bridge from a content-hashed file (impl-<hash>.js) on every enable(): a new hash is a
		// new URL, so updated bridge code goes live on WayPlank restart without logout/login.
		const string EXTENSION_LOADER_JS = """//
//  Wayplank Bridge GNOME Shell Extension - versioned implementation loader
//  Copyright (C) 2026 Sergio Melas
//  Part of Wayplank - native Wayland dock
//

import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class WayplankBridgeLoader extends Extension {
    enable() {
        this._enabled = true;
        this._token = (this._token || 0) + 1;
        const token = this._token;

        let ver = null;
        try {
            const [ok, bytes] = GLib.file_get_contents(GLib.build_filenamev([this.path, 'impl-version']));
            if (ok)
                ver = new TextDecoder().decode(bytes).trim();
        } catch (e) {
            console.error('[WayplankBridge] loader: cannot read impl-version:', e);
            return;
        }
        if (!ver || !/^[0-9a-f]+$/.test(ver)) {
            console.error('[WayplankBridge] loader: invalid impl-version:', ver);
            return;
        }

        const uri = GLib.filename_to_uri(GLib.build_filenamev([this.path, `impl-${ver}.js`]), null);
        import(uri).then(mod => {
            // Ignore stale imports if disable() (or a newer enable()) happened meanwhile
            if (!this._enabled || token !== this._token)
                return;
            const impl = new mod.default();
            try {
                impl.enable();
                this._impl = impl;
            } catch (e) {
                console.error('[WayplankBridge] loader: implementation enable() failed:', e);
                try { impl.disable(); } catch (e2) { }
            }
        }).catch(e => {
            console.error('[WayplankBridge] loader: failed to import implementation:', e);
        });
    }

    disable() {
        this._enabled = false;
        this._token = (this._token || 0) + 1;
        if (this._impl) {
            try {
                this._impl.disable();
            } catch (e) {
                console.error('[WayplankBridge] loader: implementation disable() failed:', e);
            }
            this._impl = null;
        }
    }
}
""";

		// Bridge implementation, deployed as impl-<hash>.js and imported by EXTENSION_LOADER_JS.
		const string EXTENSION_JS = """//
//  Wayplank Bridge GNOME Shell Extension
//  Copyright (C) 2026 Sergio Melas
//  Part of Wayplank - native Wayland dock
//

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

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
    <method name="GetMonitorWorkareas">
      <arg type="s" name="json" direction="out"/>
    </method>
    <method name="Eval">
      <arg type="s" name="code" direction="in"/>
      <arg type="s" name="result" direction="out"/>
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
    <method name="CaptureWindow">
      <arg type="s" name="uuid" direction="in"/>
      <arg type="s" name="filename" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="SetReserveSpace">
      <arg type="b" name="enabled" direction="in"/>
      <arg type="i" name="thickness" direction="in"/>
      <arg type="i" name="position" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <signal name="WindowsChanged"/>
  </interface>
</node>`;

export default class WayplankBridgeImpl {
    enable() {
        this._signals = [];
        this._wsSignals = [];
        this._windowSignals = new Map();
        this._desktopRestoredWindows = [];

        // Suppress "Wayplank is ready" notifications safely via WindowAttentionHandler without altering native prototypes
        if (Main.windowAttentionHandler && !this._origAttentionHandler) {
            this._origAttentionHandler = Main.windowAttentionHandler._onWindowDemandsAttention;
            const ext = this;
            Main.windowAttentionHandler._onWindowDemandsAttention = function(display, window) {
                if (window && ext._classifyWindow(window) !== 'other') {
                    try { window.demands_attention = false; } catch (e) { }
                    return;
                }
                return ext._origAttentionHandler.call(this, display, window);
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
        if (this._strutActor) {
            try {
                Main.layoutManager.removeChrome(this._strutActor);
                this._strutActor.destroy();
            } catch (e) { }
            this._strutActor = null;
        }
        this._strutRect = null;
        this._lastReserveEnabled = false;
        this._lastReserveThickness = 0;
        this._lastReservePosition = -1;

        if (this._origAttentionHandler && Main.windowAttentionHandler) {
            Main.windowAttentionHandler._onWindowDemandsAttention = this._origAttentionHandler;
            this._origAttentionHandler = null;
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

        // 1. Tooltip / Hover / Folder Window (ensure poof is not mistaken for hover)
        if (lowerTitle.includes('hover') || lowerTitle.includes('folder') || lowerTitle.includes('cards') ||
            role === 'tooltip' ||
            (role === 'popup-menu' && (lowerTitle.includes('folder') || lowerTitle.includes('cards'))))
            return 'hover';

        // 2. Dialog Windows (Preferences, Shortcuts/Help, Weather, Session, Icon Chooser, About)
        if (lowerTitle.includes('prefer') || lowerTitle.includes('setting') ||
            lowerTitle.includes('short') || lowerTitle.includes('help') ||
            lowerTitle.includes('weather') || lowerTitle.includes('meteo') ||
            lowerTitle.includes('scorciatoie') || lowerTitle.includes('aiuto') ||
            lowerTitle.includes('session') || lowerTitle.includes('icon') ||
            role === 'preferences' || role === 'help' || role.includes('dialog') ||
            type === Meta.WindowType.DIALOG)
            return 'dialog';

        // 3. Dock Window: ONLY if title is exactly 'wayplank' or role is 'dock' or type is DOCK
        if (lowerTitle === 'wayplank' || role === 'dock' || type === Meta.WindowType.DOCK)
            return 'dock';

        return 'unknown';
    }

    _centerWindow(win) {
        if (!win || !win.mapped || win._wayplankCentered) return false;
        try {
            let monitor = win.get_monitor ? win.get_monitor() : -1;
            if (monitor === -1 || monitor === null || monitor === undefined) {
                monitor = (global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0;
            }
            const monGeo = global.display.get_monitor_geometry(monitor);
            if (!monGeo) return false;
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

    // Runs fn once on the window actor's first frame. Keeps at most ONE pending handler per
    // window (a 'first-frame' handler connected on an already-shown window never fires, so
    // connecting one per positioning call would accumulate handlers forever).
    _onFirstFrame(win, fn) {
        const act = win.get_compositor_private ? win.get_compositor_private() : null;
        if (!act || !act.connect)
            return;
        if (win._wpFirstFrameId) {
            try { act.disconnect(win._wpFirstFrameId); } catch (e) { }
            win._wpFirstFrameId = 0;
        }
        win._wpFirstFrameId = act.connect('first-frame', () => {
            try { act.disconnect(win._wpFirstFrameId); } catch (e) { }
            win._wpFirstFrameId = 0;
            fn();
        });
    }

    // Returns the Mutter work area of monitor i EXCLUDING WayPlank's own reserve-space strut.
    // Only native shell panels (e.g. GNOME top bar) are subtracted. The strut is added back only
    // if Mutter has actually applied it (work area edge coincides with the strut inner edge).
    _baseWorkArea(i) {
        const g = global.display.get_monitor_geometry(i);
        const ws = global.workspace_manager ? global.workspace_manager.get_active_workspace() : null;
        let wa = g;
        if (ws && ws.get_work_area_for_monitor) {
            try { wa = ws.get_work_area_for_monitor(i); } catch (e) { wa = g; }
        }
        const r = { x: wa.x, y: wa.y, width: wa.width, height: wa.height };
        const s = this._strutRect;
        const t = this._lastReserveThickness || 0;
        if (!this._strutActor || !s || t <= 0 || s.mon !== i)
            return r;

        const pos = this._lastReservePosition;
        if (pos === 2 && r.y === s.y + s.height) {            // TOP
            const ny = Math.max(g.y, r.y - t);
            r.height += (r.y - ny);
            r.y = ny;
        } else if (pos === 3 && r.y + r.height === s.y) {     // BOTTOM
            r.height = Math.min(g.y + g.height, r.y + r.height + t) - r.y;
        } else if (pos === 0 && r.x === s.x + s.width) {      // LEFT
            const nx = Math.max(g.x, r.x - t);
            r.width += (r.x - nx);
            r.x = nx;
        } else if (pos === 1 && r.x + r.width === s.x) {      // RIGHT
            r.width = Math.min(g.x + g.width, r.x + r.width + t) - r.x;
        }
        return r;
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

            // Rule 9 (Strut Purity): Anchor dock placement strictly to physical monitor geometry (monGeo).
            // Window coordinates must NEVER be calculated relative to dynamic work_area (wa), which shrinks
            // when reserving space and recalculates asynchronously in Mutter.
            const monGeo = global.display.get_monitor_geometry(targetMon);
            const isPrimary = (targetMon === ((global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0));
            const topPanelHeight = (isPrimary && Main.panel && Main.panel.height) ? Main.panel.height : 0;

            let targetX = x;
            let targetY = y;

            let isTop;
            if (this._lastReservePosition === 2)
                isTop = true;
            else if (this._lastReservePosition === 3)
                isTop = false;
            else
                isTop = (y <= monGeo.y + topPanelHeight + 100);

            let isLeft;
            if (this._lastReservePosition === 0)
                isLeft = true;
            else if (this._lastReservePosition === 1)
                isLeft = false;
            else
                isLeft = (x <= monGeo.x + 100);

            const isHorizontal = (width >= height);
            if (isHorizontal) {
                targetX = Math.max(monGeo.x, Math.min(x, monGeo.x + monGeo.width - width));
                targetY = isTop ? (monGeo.y + topPanelHeight) : (monGeo.y + monGeo.height - height);
            } else {
                targetX = isLeft ? monGeo.x : (monGeo.x + monGeo.width - width);
                targetY = Math.max(monGeo.y + topPanelHeight, Math.min(y, monGeo.y + monGeo.height - height));
            }
            this._lastDockGeo = { x: targetX, y: targetY, width, height };

            // user_op = true: on Wayland the dock is a NORMAL toplevel (never META_WINDOW_DOCK),
            // so Mutter's constrain_fully_onscreen would shove it out of its OWN reserve-space
            // strut (constraints.c). User-op moves skip that constraint and clear the window's
            // require_fully_onscreen flag, so later work-area re-constraints leave it in place.
            const move = () => {
                try {
                    if (!win || !win.mapped || this._classifyWindow(win) !== 'dock')
                        return;
                    const frameRect = win.get_frame_rect ? win.get_frame_rect() : null;
                    if (frameRect && frameRect.x === targetX && frameRect.y === targetY &&
                        frameRect.width === width && frameRect.height === height) {
                        return;
                    }
                    if (win.move_frame) {
                        win.move_frame(true, targetX, targetY);
                    }
                    if (win.move_resize_frame) {
                        win.move_resize_frame(true, targetX, targetY, width, height);
                    }
                } catch (e) {
                    console.error('[WayplankBridge] move dock error:', e);
                }
            };

            if (win.mapped) {
                move();
            } else {
                this._onFirstFrame(win, move);
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
                    if (!win || !win.mapped || this._classifyWindow(win) !== 'hover')
                        return;
                    if (win.move_resize_frame) {
                        const frameRect = win.get_frame_rect();
                        const w = (width && width > 0) ? width : frameRect.width;
                        const h = (height && height > 0) ? height : frameRect.height;
                        win.move_resize_frame(false, targetX, targetY, w, h);
                    } else if (win.move_frame) {
                        win.move_frame(false, targetX, targetY);
                    }
                } catch (e) {
                    console.error('[WayplankBridge] move hover error:', e);
                }
            };

            if (win.mapped) {
                move();
            } else {
                this._onFirstFrame(win, move);
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

            // user_op = true: the poof is drawn over the dock (inside the reserve-space strut);
            // a non-user move would be shoved out of the strut by constrain_fully_onscreen.
            const move = () => {
                try {
                    if (!win || !win.mapped)
                        return;
                    if (win.move_frame) {
                        win.move_frame(true, x, y);
                    }
                    if (win.move_resize_frame) {
                        win.move_resize_frame(true, x, y, width, height);
                    }
                } catch (e) {
                    console.error('[WayplankBridge] move poof error:', e);
                }
            };

            if (win.mapped) {
                move();
            } else {
                this._onFirstFrame(win, move);
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
                if (targetWin.mapped) {
                    this._centerWindow(targetWin);
                }
                const act = targetWin.get_compositor_private ? targetWin.get_compositor_private() : null;
                if (act && act.connect) {
                    const id = act.connect('first-frame', () => {
                        try { act.disconnect(id); } catch (e) { }
                        this._centerWindow(targetWin);
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
            const kind = this._classifyWindow(win);
            if (kind === 'dock' && this._lastDockGeo) {
                // Mutter may displace the dock (work-area re-constraint when our strut is applied):
                // restore it once; the frame-equality guard in _applyDockPosition prevents loops.
                const { x, y, width, height } = this._lastDockGeo;
                this._applyDockPosition(win, x, y, width, height);
            } else if (kind === 'other') {
                this._notifyWindowsChanged();
            }
        }));
        sigs.push(win.connect('size-changed', () => {
            const currentKind = this._classifyWindow(win);
            if (currentKind === 'dock' && this._lastDockGeo) {
                const { x, y, width, height } = this._lastDockGeo;
                this._applyDockPosition(win, x, y, width, height);
            } else if (currentKind === 'dialog') {
                this._centerWindow(win);
            } else if (currentKind === 'other') {
                this._notifyWindowsChanged();
            }
        }));
        sigs.push(win.connect('notify::title', () => {
            applyRole(win);
            if (this._classifyWindow(win) === 'other')
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
        const actors = global.get_window_actors();
        for (let i = actors.length - 1; i >= 0; i--) {
            const win = actors[i].meta_window;
            if (win && !win.minimized && this._classifyWindow(win) === 'hover')
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
                pid: (win.get_pid ? win.get_pid() : 0),
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
    // Work areas are reported WITHOUT WayPlank's own strut, so the dock never positions
    // itself inside the space it reserved (no workarea feedback loop / no jump on toggle).
    GetMonitorWorkAreas() {
        try {
            const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 1;
            const res = [];
            for (let i = 0; i < nMonitors; i++) {
                const g = global.display.get_monitor_geometry(i);
                const wa = this._baseWorkArea(i);
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

    // D-Bus Method: GetMonitorWorkareas alias
    GetMonitorWorkareas() {
        return this.GetMonitorWorkAreas();
    }

    // D-Bus Method: Eval
    Eval(code) {
        try {
            const res = eval(code);
            if (res === undefined || res === null)
                return "ok";
            return (typeof res === 'string') ? res : (JSON.stringify(res) || "ok");
        } catch (e) {
            return JSON.stringify({ error: e.toString() });
        }
    }

    // D-Bus Method: CaptureWindow
    CaptureWindow(uuid, filename) {
        try {
            const win = this._findWindowByUuid(uuid);
            if (!win)
                return false;
            const actor = win.get_compositor_private ? win.get_compositor_private() : null;
            if (!actor || !actor.get_image)
                return false;
            const surface = actor.get_image(null);
            if (!surface || !surface.writeToPNG)
                return false;
            surface.writeToPNG(filename);
            return true;
        } catch (e) {
            console.error('[WayplankBridge] CaptureWindow error:', e);
            return false;
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

    // D-Bus Method: SetReserveSpace
    SetReserveSpace(enabled, thickness, position) {
        if (this._lastReserveEnabled === enabled &&
            this._lastReserveThickness === thickness &&
            this._lastReservePosition === position) {
            return true;
        }

        // Resolve target monitor and its base work area (native panels only) BEFORE
        // touching the current strut state, so the old strut is correctly excluded.
        let targetMon = -1;
        let base = null;
        try {
            if (this._lastDockGeo) {
                const cx = this._lastDockGeo.x + Math.floor(this._lastDockGeo.width / 2);
                const cy = this._lastDockGeo.y + Math.floor(this._lastDockGeo.height / 2);
                const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 1;
                for (let i = 0; i < nMonitors; i++) {
                    const geo = global.display.get_monitor_geometry(i);
                    if (cx >= geo.x && cx < geo.x + geo.width &&
                        cy >= geo.y && cy < geo.y + geo.height) {
                        targetMon = i;
                        break;
                    }
                }
            }
            if (targetMon === -1) {
                targetMon = (global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0;
            }
            base = this._baseWorkArea(targetMon);
        } catch (e) {
            console.error('[WayplankBridge] SetReserveSpace base work area error:', e);
        }

        this._lastReserveEnabled = enabled;
        this._lastReserveThickness = thickness;
        this._lastReservePosition = position;

        if (this._strutActor) {
            try {
                Main.layoutManager.removeChrome(this._strutActor);
                this._strutActor.destroy();
            } catch (e) { }
            this._strutActor = null;
        }
        this._strutRect = null;

        if (enabled && thickness > 0 && base) {
            try {
                const monGeo = global.display.get_monitor_geometry(targetMon);
                const monRight = monGeo.x + monGeo.width;
                const monBottom = monGeo.y + monGeo.height;
                let sx = monGeo.x, sy = monGeo.y, sw = monGeo.width, sh = monGeo.height;

                // Position: 0=LEFT, 1=RIGHT, 2=TOP, 3=BOTTOM
                // Strut spans from the physical monitor edge to (native panel edge + thickness).
                if (position === 2) { // TOP
                    sh = (base.y - monGeo.y) + thickness;
                } else if (position === 3) { // BOTTOM
                    sy = base.y + base.height - thickness;
                    sh = monBottom - sy;
                } else if (position === 0) { // LEFT
                    sw = (base.x - monGeo.x) + thickness;
                } else if (position === 1) { // RIGHT
                    sx = base.x + base.width - thickness;
                    sw = monRight - sx;
                } else {
                    return true;
                }

                this._strutActor = new St.Widget({
                    name: 'wayplank-strut',
                    reactive: false,
                    can_focus: false,
                    opacity: 0,
                });
                this._strutActor.set_position(sx, sy);
                this._strutActor.set_size(sw, sh);
                this._strutRect = { mon: targetMon, x: sx, y: sy, width: sw, height: sh };
                Main.layoutManager.addChrome(this._strutActor, { affectsStruts: true, trackFullscreen: true });
            } catch (e) {
                console.error('[WayplankBridge] SetReserveSpace error:', e);
                this._strutRect = null;
                return false;
            }
        }

        if (this._lastDockGeo) {
            const win = this._findDockWindow();
            if (win) {
                this._applyDockPosition(win, this._lastDockGeo.x, this._lastDockGeo.y, this._lastDockGeo.width, this._lastDockGeo.height);
            }
        }
        return true;
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
			connect_bridge ();
			return true;
		}

		void ensure_extension_installed ()
		{
			// GNOME Safety Mode Self-Healing:
			// If GNOME Shell previously crashed and entered failsafe mode ('disable-user-extensions = true'),
			// reset the master switch and ensure our extension UUID is enrolled.
			var schema_source = SettingsSchemaSource.get_default ();
			if (schema_source != null && schema_source.lookup ("org.gnome.shell", true) != null) {
				var shell_settings = new GLib.Settings ("org.gnome.shell");
				if (shell_settings.get_boolean ("disable-user-extensions")) {
					message ("MutterBackend: GNOME Shell Safety Mode detected (disable-user-extensions=true), auto-recovering...");
					shell_settings.set_boolean ("disable-user-extensions", false);
				}

				var disabled = shell_settings.get_strv ("disabled-extensions");
				if (EXTENSION_UUID in disabled) {
					var updated_disabled = new Gee.ArrayList<string> ();
					foreach (var d in disabled) {
						if (d != EXTENSION_UUID)
							updated_disabled.add (d);
					}
					string[] new_arr = new string[updated_disabled.size];
					for (int i = 0; i < updated_disabled.size; i++)
						new_arr[i] = updated_disabled.get (i);
					shell_settings.set_strv ("disabled-extensions", new_arr);
				}

				var enabled = shell_settings.get_strv ("enabled-extensions");
				if (!(EXTENSION_UUID in enabled)) {
					var updated_enabled = new Gee.ArrayList<string> ();
					foreach (var e in enabled)
						updated_enabled.add (e);
					updated_enabled.add (EXTENSION_UUID);
					string[] new_arr = new string[updated_enabled.size];
					for (int i = 0; i < updated_enabled.size; i++)
						new_arr[i] = updated_enabled.get (i);
					shell_settings.set_strv ("enabled-extensions", new_arr);
				}
			}

			var ext_dir = Path.build_filename (Environment.get_user_data_dir (), "gnome-shell", "extensions", EXTENSION_UUID);
			var js_file = Path.build_filename (ext_dir, "extension.js");
			var meta_file = Path.build_filename (ext_dir, "metadata.json");
			var version_file = Path.build_filename (ext_dir, "impl-version");

			// Content hash of the bridge implementation: identical code -> identical file name,
			// changed code -> new file name (= new ES module URL, not cached by GNOME Shell).
			string impl_hash = GLib.Checksum.compute_for_string (ChecksumType.SHA256, EXTENSION_JS).substring (0, 12);
			string impl_name = "impl-" + impl_hash + ".js";
			var impl_file = Path.build_filename (ext_dir, impl_name);

			string? current_js = null;
			string? current_meta = null;
			string? current_version = null;
			if (FileUtils.test (js_file, FileTest.EXISTS)) {
				try {
					FileUtils.get_contents (js_file, out current_js);
				} catch (Error e) { }
			}
			if (FileUtils.test (meta_file, FileTest.EXISTS)) {
				try {
					FileUtils.get_contents (meta_file, out current_meta);
				} catch (Error e) { }
			}
			if (FileUtils.test (version_file, FileTest.EXISTS)) {
				try {
					FileUtils.get_contents (version_file, out current_version);
					if (current_version != null)
						current_version = current_version.strip ();
				} catch (Error e) { }
			}

			bool code_changed = (current_js == null || current_js != EXTENSION_LOADER_JS
				|| current_meta == null || current_meta != EXTENSION_METADATA
				|| current_version == null || current_version != impl_hash
				|| !FileUtils.test (impl_file, FileTest.EXISTS));

			try {
				DirUtils.create_with_parents (ext_dir, 0755);
				// Write the implementation first, then the version pointer, then the loader,
				// so the loader never points to a missing implementation file.
				FileUtils.set_contents (impl_file, EXTENSION_JS);
				FileUtils.set_contents (version_file, impl_hash);
				FileUtils.set_contents (meta_file, EXTENSION_METADATA);
				FileUtils.set_contents (js_file, EXTENSION_LOADER_JS);

				// Remove stale implementation files (already loaded modules stay in shell memory)
				try {
					var dir = Dir.open (ext_dir, 0);
					string? name = null;
					while ((name = dir.read_name ()) != null) {
						if (name.has_prefix ("impl-") && name.has_suffix (".js") && name != impl_name)
							FileUtils.unlink (Path.build_filename (ext_dir, name));
					}
				} catch (Error e) {
					warning ("MutterBackend: failed to clean stale bridge implementations: %s", e.message);
				}

				if (code_changed && current_js != null) {
					// Upgrade / code updated: reset error latch and cycle disable -> enable.
					// With the versioned loader, enable() imports impl-<new hash>.js -> new code goes live.
					// (A one-time logout/login is still needed when the loader itself changes.)
					Process.spawn_command_line_async ("sh -c 'gnome-extensions reset " + EXTENSION_UUID + " && gnome-extensions disable " + EXTENSION_UUID + "'");
					if (ext_enable_timer_id > 0U) {
						GLib.Source.remove (ext_enable_timer_id);
						ext_enable_timer_id = 0U;
					}
					ext_enable_timer_id = GLib.Timeout.add (300, () => {
						ext_enable_timer_id = 0U;
						try {
							Process.spawn_command_line_async ("gnome-extensions enable " + EXTENSION_UUID);
						} catch (Error e) { }
						return false;
					});
				} else {
					Process.spawn_command_line_async ("sh -c 'gnome-extensions reset " + EXTENSION_UUID + " && gnome-extensions enable " + EXTENSION_UUID + "'");
				}
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
				primary_monitor_changed ();
				state_changed ();
				if (last_width > 0 && last_height > 0) {
					try {
						proxy.position_dock (last_x, last_y, last_width, last_height);
					} catch (Error e) { }
				}
				if (last_reserve_enabled) {
					try {
						proxy.set_reserve_space (last_reserve_enabled, last_reserve_thickness, last_reserve_position);
					} catch (Error e) { }
				}
				if (bridge_reposition_timer_id > 0U) {
					GLib.Source.remove (bridge_reposition_timer_id);
					bridge_reposition_timer_id = 0U;
				}
				bridge_reposition_timer_id = GLib.Timeout.add (250, () => {
					bridge_reposition_timer_id = 0U;
					if (proxy != null && last_width > 0 && last_height > 0) {
						try {
							proxy.position_dock (last_x, last_y, last_width, last_height);
						} catch (Error e) { }
					}
					if (proxy != null && last_reserve_enabled) {
						try {
							proxy.set_reserve_space (last_reserve_enabled, last_reserve_thickness, last_reserve_position);
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
			if (bridge_reposition_timer_id > 0U) {
				GLib.Source.remove (bridge_reposition_timer_id);
				bridge_reposition_timer_id = 0U;
			}
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

					if (json.has_member ("pid")) {
						info.Pid = (int) json.get_int_member ("pid");
						if (info.Pid > 0) {
							info.Cmdline = ApplicationDiscovery.get_process_cmdline (info.Pid);
							string comm = "";
							if (GLib.FileUtils.get_contents ("/proc/%d/comm".printf (info.Pid), out comm)) {
								info.Executable = comm.strip ();
							}
						}
					}

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
			if (ext_enable_timer_id > 0U) {
				GLib.Source.remove (ext_enable_timer_id);
				ext_enable_timer_id = 0U;
			}
			if (bridge_reposition_timer_id > 0U) {
				GLib.Source.remove (bridge_reposition_timer_id);
				bridge_reposition_timer_id = 0U;
			}
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

		public override void set_reserve_space (bool enabled, int thickness, Gtk.PositionType position)
		{
			if (last_reserve_enabled == enabled &&
			    last_reserve_thickness == thickness &&
			    last_reserve_position == (int) position) {
				return;
			}
			last_reserve_enabled = enabled;
			last_reserve_thickness = thickness;
			last_reserve_position = (int) position;
			if (proxy != null) {
				try {
					proxy.set_reserve_space (enabled, thickness, (int) position);
				} catch (Error e) {
					debug ("MutterBackend: set_reserve_space D-Bus: %s", e.message);
				}
			}
		}

		public bool capture_window (string uuid, string filename)
		{
			if (proxy == null)
				return false;
			try {
				return proxy.capture_window (uuid, filename);
			} catch (Error e) {
				debug ("MutterBackend: capture_window D-Bus error: %s", e.message);
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
									const wa = (typeof this._baseWorkArea === 'function') ? this._baseWorkArea(i) : (ws ? ws.get_work_area_for_monitor(i) : g);
									res.push({ x: g.x, y: g.y, width: g.width, height: g.height, wa_x: wa.x, wa_y: wa.y, wa_width: wa.width, wa_height: wa.height });
								}
								return JSON.stringify(res);
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
