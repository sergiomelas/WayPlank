//
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
		public abstract bool position_dock_for (string dock_key, int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_hover (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_hover_for (int pid, int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_poof (int x, int y, int width, int height) throws GLib.Error;
		public abstract bool position_poof_for (int pid, int x, int y, int width, int height) throws GLib.Error;
		public abstract bool set_reserve_space (bool enabled, int thickness, int position) throws GLib.Error;
		public abstract bool set_reserve_space_for (string dock_key, bool enabled, int thickness, int position) throws GLib.Error;
		public abstract bool release_dock (string dock_key) throws GLib.Error;
		public abstract string eval (string code) throws GLib.Error;
		public abstract bool capture_window (string uuid, string filename) throws GLib.Error;
		public abstract bool take_screenshot (string mode, string filename) throws GLib.Error;
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
		string? last_windows_json = null;
		bool started = false;
		GnomeBridgeProxy? proxy = null;
		DBusConnection? session_bus = null;
		uint display_config_sub_id = 0U;
		bool pending_monitor_sync = false;
		uint name_watch_id = 0U;
		uint ext_enable_timer_id = 0U;
		uint bridge_reposition_timer_id = 0U;

		class MutterDockState
		{
			public string dock_key;
			public int x = -1;
			public int y = -1;
			public int width = -1;
			public int height = -1;
			public bool has_reserve = false;
			public bool reserve_enabled = false;
			public int reserve_thickness = 0;
			public int reserve_position = -1;

			public MutterDockState (string key)
			{
				this.dock_key = key;
			}
		}

		Gee.HashMap<string, MutterDockState> dock_states = new Gee.HashMap<string, MutterDockState> ();
		bool reload_attempted = false;

		const string EXTENSION_UUID = "wayplank-bridge@wayplank.org";
		const string BRIDGE_GEN = "v072_bridge_5";

		const string EXTENSION_METADATA = """{
  "name": "WayPlank Bridge",
  "description": "Native GNOME Shell bridge for WayPlank dock",
  "uuid": "wayplank-bridge@wayplank.org",
  "shell-version": ["45", "46", "47", "48", "49", "50", "51"],
  "url": "https://github.com/wayplank",
  "version": 5
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

try {
    if (Shell.Screenshot && Shell.Screenshot.composite_to_stream && !Shell.Screenshot._original_composite_to_stream)
        Gio._promisify(Shell.Screenshot, 'composite_to_stream', 'composite_to_stream_finish');
    if (Shell.Screenshot && Shell.Screenshot.prototype) {
        if (Shell.Screenshot.prototype.screenshot && !Shell.Screenshot.prototype._original_screenshot)
            Gio._promisify(Shell.Screenshot.prototype, 'screenshot', 'screenshot_finish');
        if (Shell.Screenshot.prototype.screenshot_window && !Shell.Screenshot.prototype._original_screenshot_window)
            Gio._promisify(Shell.Screenshot.prototype, 'screenshot_window', 'screenshot_window_finish');
    }
} catch (e) { }

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
    <method name="PositionDockFor">
      <arg type="s" name="dockKey" direction="in"/>
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
    <method name="PositionHoverFor">
      <arg type="i" name="pid" direction="in"/>
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
    <method name="PositionPoofFor">
      <arg type="i" name="pid" direction="in"/>
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
    <method name="TakeScreenshot">
      <arg type="s" name="mode" direction="in"/>
      <arg type="s" name="filename" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="SetReserveSpace">
      <arg type="b" name="enabled" direction="in"/>
      <arg type="i" name="thickness" direction="in"/>
      <arg type="i" name="position" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="SetReserveSpaceFor">
      <arg type="s" name="dockKey" direction="in"/>
      <arg type="b" name="enabled" direction="in"/>
      <arg type="i" name="thickness" direction="in"/>
      <arg type="i" name="position" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <method name="ReleaseDock">
      <arg type="s" name="dockKey" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
    <signal name="WindowsChanged"/>
  </interface>
</node>`;

export default class WayplankBridgeImpl {
    enable() {
        this._bridgeGen = 'v072_bridge_4';
        this._docks = new Map();
        this._hoverByPid = new Map();
        this._poofByPid = new Map();
        this._signals = [];
        this._wsSignals = [];
        this._lmSignals = [];
        this._windowSignals = new Map();
        this._minSeq = 0;
        this._minMap = new Map();
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
            if (!win) return;
            if (this._classifyWindow(win) !== 'other') {
                try { win.demands_attention = false; } catch (e) { }
            } else {
                this._notifyWindowsChanged();
            }
        }));
        this._signals.push(display.connect('window-marked-urgent', (d, win) => {
            if (!win) return;
            if (this._classifyWindow(win) !== 'other') {
                try { win.demands_attention = false; } catch (e) { }
            } else {
                this._notifyWindowsChanged();
            }
        }));
        this._signals.push(display.connect('window-created', (d, win) => {
            this._connectWindow(win);
            if (this._classifyWindow(win) === 'other') {
                this._clampWindowToReserve(win);
                this._notifyWindowsChanged();
            }
        }));
        this._signals.push(display.connect('grab-op-end', (d, arg1, arg2) => {
            const win = (arg1 && arg1.get_frame_rect) ? arg1 : arg2;
            if (win && this._classifyWindow(win) === 'other')
                this._clampWindowToReserve(win);
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
            this._wsSignals.push(global.workspace_manager.connect('showing-desktop-changed', () => {
                if (!this._handlingShowDesktop) {
                    const ws = global.workspace_manager.get_active_workspace ? global.workspace_manager.get_active_workspace() : null;
                    const showing = ws ? !!ws.showing_desktop : false;
                    const inOverview = !!(Main.overview && Main.overview.visible);
                    if (showing && !inOverview && typeof global.workspace_manager.unshow_desktop === 'function') {
                        this._handlingShowDesktop = true;
                        try {
                            global.workspace_manager.unshow_desktop();
                            this.ToggleDesktop();
                        } catch (e) { }
                        this._handlingShowDesktop = false;
                        return;
                    }
                }
                this._notifyWindowsChanged();
            }));
        }
        this._signals.push(display.connect('workareas-changed', () => {
            const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 0;
            for (const entry of this._docks.values()) {
                if (entry.reserveEnabled && entry.reserveThickness > 0 && entry.strutActor && entry.strutRect) {
                    try {
                        const sr = entry.strutRect;
                        if (sr.mon >= 0 && sr.mon < nMonitors && global.workspace_manager) {
                            const ws = global.workspace_manager.get_active_workspace();
                            const wa = ws ? ws.get_work_area_for_monitor(sr.mon) : null;
                            if (wa) {
                                const pos = entry.reservePosition;
                                let reserved = true;
                                if (pos === 3)
                                    reserved = (wa.y + wa.height <= sr.y + 1);
                                else if (pos === 2)
                                    reserved = (wa.y >= sr.y + sr.height - 1);
                                else if (pos === 0)
                                    reserved = (wa.x >= sr.x + sr.width - 1);
                                else if (pos === 1)
                                    reserved = (wa.x + wa.width <= sr.x + 1);

                                if (!reserved && !entry.strutHealAttempted) {
                                    entry.strutHealAttempted = true;
                                    entry.strutActor.visible = true;
                                    entry.strutActor.set_position(sr.x, sr.y);
                                    entry.strutActor.set_size(sr.width, sr.height);
                                    try { entry.strutActor.queue_relayout(); } catch (e) { }
                                    if (Main.layoutManager && Main.layoutManager._queueUpdateRegions)
                                        Main.layoutManager._queueUpdateRegions();
                                } else if (reserved) {
                                    entry.strutHealAttempted = false;
                                }
                            }
                        }
                    } catch (e) { }
                }
                if (entry.geo) {
                    const dockWin = this._findDockWindowForEntry(entry);
                    if (dockWin) {
                        const { x, y, width, height } = entry.geo;
                        this._applyDockPosition(dockWin, entry, x, y, width, height);
                    }
                }
            }
        }));
        if (Main.layoutManager) {
            this._lmSignals.push(Main.layoutManager.connect('monitors-changed', () => {
                const nMonitors = global.display.get_n_monitors ? global.display.get_n_monitors() : 0;
                if (nMonitors > 0) {
                    const pMon = this._getSafePrimaryMonitor(nMonitors);
                    for (const entry of this._docks.values()) {
                        if (entry.geo) {
                            let targetMon = -1;
                            if (entry.onPrimary !== false) {
                                targetMon = pMon;
                            } else {
                                const cx = entry.geo.x + Math.floor(entry.geo.width / 2);
                                const cy = entry.geo.y + Math.floor(entry.geo.height / 2);
                                for (let i = 0; i < nMonitors; i++) {
                                    const geo = global.display.get_monitor_geometry(i);
                                    if (cx >= geo.x && cx < geo.x + geo.width &&
                                        cy >= geo.y && cy < geo.y + geo.height) {
                                        targetMon = i;
                                        break;
                                    }
                                }
                                if (targetMon < 0 || targetMon >= nMonitors)
                                    targetMon = pMon;
                            }
                            if (targetMon >= 0 && targetMon < nMonitors) {
                                const monGeo = global.display.get_monitor_geometry(targetMon);
                                const topPanel = (targetMon === pMon && Main.panel && Main.panel.height) ? Main.panel.height : 0;
                                const w = entry.geo.width;
                                const h = entry.geo.height;
                                let nx = monGeo.x + Math.max(0, Math.floor((monGeo.width - w) / 2));
                                let ny = monGeo.y + monGeo.height - h;
                                if (w >= h) {
                                    const wasTop = (entry.reserveEnabled && entry.reservePosition === 2) ||
                                                   (entry.geo.y <= monGeo.y + topPanel + 100);
                                    if (wasTop)
                                        ny = monGeo.y + topPanel;
                                } else {
                                    const wasRight = (entry.reserveEnabled && entry.reservePosition === 1) ||
                                                     (entry.geo.x > monGeo.x + 100);
                                    nx = wasRight ? (monGeo.x + monGeo.width - w) : monGeo.x;
                                    ny = monGeo.y + topPanel + Math.max(0, Math.floor((monGeo.height - topPanel - h) / 2));
                                }
                                entry.geo = { x: nx, y: ny, width: w, height: h };
                            }
                            const dockWin = this._findDockWindowForEntry(entry);
                            if (dockWin) {
                                const { x, y, width, height } = entry.geo;
                                this._applyDockPosition(dockWin, entry, x, y, width, height);
                            }
                        }
                        if (entry.reserveEnabled && entry.reserveThickness > 0 && entry.reservePosition >= 0) {
                            this._syncReserveStrutForEntry(entry, true, entry.reserveThickness, entry.reservePosition);
                        }
                    }
                }
                this._notifyWindowsChanged();
            }));
        }

        // Connect existing windows and restore any normal windows that may have been stuck/above/hidden
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (win) {
                if (this._classifyWindow(win) === 'other') {
                    if (win.get_window_type && win.get_window_type() === Meta.WindowType.NORMAL) {
                        try { if (win.show_in_window_list) win.show_in_window_list(); } catch (e) { }
                        try { if (win.is_above && win.is_above()) win.unmake_above(); } catch (e) { }
                        try { if (win.is_on_all_workspaces && win.is_on_all_workspaces()) win.unstick(); } catch (e) { }
                    }
                    if (win.minimized) {
                        const initId = win.get_stable_sequence ? win.get_stable_sequence().toString() : (win.get_id ? win.get_id().toString() : '');
                        if (initId)
                            this._minMap.set(initId, ++this._minSeq);
                    }
                }
                this._connectWindow(win);
            }
        }
    }

    disable() {
        if (this._docks) {
            for (const entry of this._docks.values()) {
                this._destroyEntryStrut(entry);
            }
            this._docks.clear();
        }
        if (this._hoverByPid)
            this._hoverByPid.clear();
        if (this._poofByPid)
            this._poofByPid.clear();
        if (Main.layoutManager && Main.layoutManager._queueUpdateRegions) {
            try { Main.layoutManager._queueUpdateRegions(); } catch (e) { }
        }

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

        if (this._lmSignals && Main.layoutManager) {
            for (const id of this._lmSignals) {
                try { Main.layoutManager.disconnect(id); } catch (e) { }
            }
            this._lmSignals = [];
        }

        if (this._notifyTimeout) {
            GLib.Source.remove(this._notifyTimeout);
            this._notifyTimeout = 0;
        }

        for (const [win, sigs] of this._windowSignals.entries()) {
            this._cancelPendingFirstFrame(win);
            for (const id of sigs) {
                try { win.disconnect(id); } catch (e) { }
            }
        }
        this._windowSignals.clear();
        if (this._minMap)
            this._minMap.clear();
        this._minSeq = 0;
        this._desktopRestoredWindows = [];
        this._lastActiveUuid = null;
    }

    _parseDockKey(dockKey) {
        const raw = (dockKey && typeof dockKey === 'string') ? dockKey.trim() : '';
        if (raw) {
            const parts = raw.split(':');
            if (parts.length === 2) {
                const pid = parseInt(parts[0], 10) || 0;
                const slot = Math.max(1, parseInt(parts[1], 10) || 1);
                return { key: `${pid}:${slot}`, pid, slot };
            }
        }
        return { key: '0:1', pid: 0, slot: 1 };
    }

    _getOrCreateDockEntry(dockKey) {
        const parsed = this._parseDockKey(dockKey);
        let entry = this._docks.get(parsed.key);
        if (!entry) {
            entry = {
                key: parsed.key,
                pid: parsed.pid,
                slot: parsed.slot,
                geo: null,
                onPrimary: true,
                reserveEnabled: false,
                reserveThickness: 0,
                reservePosition: -1,
                strutActor: null,
                strutRect: null,
                strutHealAttempted: false,
            };
            this._docks.set(parsed.key, entry);
        }
        return entry;
    }

    _destroyEntryStrut(entry) {
        if (!entry)
            return;
        if (entry.strutActor) {
            try {
                Main.layoutManager.removeChrome(entry.strutActor);
                entry.strutActor.destroy();
            } catch (e) { }
            entry.strutActor = null;
        }
        entry.strutRect = null;
        entry.strutHealAttempted = false;
    }

    _dockSlotForWindow(win) {
        const title = ((win && win.get_title ? win.get_title() : '') || '').toLowerCase();
        if (title === 'wayplank')
            return 1;
        const m = /^wayplank-([2-9]|[1-9][0-9]+)$/.exec(title);
        if (m)
            return parseInt(m[1], 10);
        return 1;
    }

    _hasActivePoofForWindow(win) {
        if (!this._poofByPid || this._poofByPid.size === 0)
            return null;
        const now = Date.now();
        const winPid = (win && win.get_pid ? win.get_pid() : 0) || 0;
        if (winPid > 0 && this._poofByPid.has(winPid)) {
            const st = this._poofByPid.get(winPid);
            if (st && (now - (st.time || 0) < 3000))
                return st;
        }
        if (this._poofByPid.has(0)) {
            const st0 = this._poofByPid.get(0);
            if (st0 && (now - (st0.time || 0) < 3000))
                return st0;
        }
        return null;
    }

    _isExactDockTitle(lowerTitle) {
        return (lowerTitle === 'wayplank' || /^wayplank-([2-9]|[1-9][0-9]+)$/.test(lowerTitle));
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

        const lowerTitle = title.toLowerCase();
        const exactDockTitle = this._isExactDockTitle(lowerTitle);
        const isExactInternalTitle = (exactDockTitle ||
                                      lowerTitle === 'wayplank-hover' ||
                                      lowerTitle === 'wayplank-folder-menu' ||
                                      lowerTitle === 'wayplank-hover-cards' ||
                                      lowerTitle === 'wayplank-poof');
        const isWayplankApp = (wmClass === 'wayplank' ||
                               wmClass === 'plank' ||
                               wmClass === 'net.launchpad.plank' ||
                               wmClass.startsWith('net.launchpad.plank.') ||
                               appId === 'wayplank.desktop' ||
                               appId === 'net.launchpad.plank.desktop' ||
                               appId.startsWith('net.launchpad.plank.') ||
                               gtkAppId === 'net.launchpad.plank' ||
                               gtkAppId.startsWith('net.launchpad.plank.') ||
                               sandboxedId === 'net.launchpad.plank' ||
                               sandboxedId.startsWith('net.launchpad.plank.') ||
                               role === 'dock' ||
                               (wmClass === '' && isExactInternalTitle));

        if (!isWayplankApp)
            return 'other';

        const type = win.get_window_type ? win.get_window_type() : -1;

        // 0. Poof Window: match exact title, role, or active poof placement request for this PID
        if (lowerTitle === 'wayplank-poof' || role === 'poof' ||
            (this._hasActivePoofForWindow(win) && !isExactInternalTitle && !lowerTitle.includes('prefer') && !lowerTitle.includes('help')))
            return 'poof';

        // 1. Tooltip / Hover / Folder / Cards Window (exact internal titles or popup roles on WayPlank surfaces)
        if (lowerTitle === 'wayplank-hover' || lowerTitle === 'wayplank-folder-menu' || lowerTitle === 'wayplank-hover-cards' ||
            role === 'tooltip' || role === 'popup-menu')
            return 'hover';

        // 2. Dock Window: ONLY if title is exact dock title ('wayplank' / 'wayplank-2'..'wayplank-8') or role is 'dock' or type is DOCK
        if (exactDockTitle || role === 'dock' || type === Meta.WindowType.DOCK)
            return 'dock';

        if (!win.mapped && lowerTitle === '' && role === '')
            return 'unknown';

        // 3. Dialog Windows: Any remaining WayPlank-owned window (Preferences, FirstRunWindow,
        //    About WayPlank, Shortcuts/Help, Weather, Calendar, Session, Icon Chooser, Confirmations)
        return 'dialog';
    }

    _isWindowAlive(win) {
        if (!win || win._wpUnmanaging || !win.mapped)
            return false;
        const act = win.get_compositor_private ? win.get_compositor_private() : null;
        if (!act || (act.is_destroyed && act.is_destroyed()))
            return false;
        return true;
    }

    _getSafePrimaryMonitor(nMonitors) {
        if (nMonitors <= 0)
            return -1;
        const pMon = (global.display && global.display.get_primary_monitor)
            ? global.display.get_primary_monitor() : 0;
        return (pMon >= 0 && pMon < nMonitors) ? pMon : 0;
    }

    _ensureWindowStickyAbove(win) {
        if (!win || win._wpUnmanaging)
            return;
        const isAbove = Boolean(win.above || (win.is_above && win.is_above()));
        if (!isAbove && win.make_above)
            win.make_above();
        const isAllWs = Boolean(win.on_all_workspaces || (win.is_on_all_workspaces && win.is_on_all_workspaces()));
        if (!isAllWs && win.stick)
            win.stick();
    }

    _cancelPendingFirstFrame(win) {
        if (!win)
            return;
        if (win._wpFirstFrameId) {
            const act = win.get_compositor_private ? win.get_compositor_private() : null;
            if (act) {
                try { act.disconnect(win._wpFirstFrameId); } catch (e) { }
            }
            win._wpFirstFrameId = 0;
        }
        if (win._wpLaterId) {
            const laterId = win._wpLaterId;
            win._wpLaterId = 0;
            try {
                if (global.compositor && typeof global.compositor.get_laters === 'function')
                    global.compositor.get_laters().remove(laterId);
                else if (Meta.later_remove)
                    Meta.later_remove(laterId);
            } catch (e) { }
        }
        if (win._wpIdleId) {
            const idleId = win._wpIdleId;
            win._wpIdleId = 0;
            try { GLib.Source.remove(idleId); } catch (e) { }
        }
    }

    _centerWindow(win) {
        if (!this._isWindowAlive(win) || win._wayplankCentered) return false;
        try {
            const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
            if (nMonitors <= 0) return false;
            let monitor = win.get_monitor ? win.get_monitor() : -1;
            if (monitor === null || monitor === undefined || monitor < 0 || monitor >= nMonitors) {
                monitor = this._getSafePrimaryMonitor(nMonitors);
            }
            const monGeo = global.display.get_monitor_geometry(monitor);
            if (!monGeo) return false;
            const frameRect = win.get_frame_rect();
            if (!frameRect || frameRect.width < 100 || frameRect.height < 100)
                return false;
            const x = monGeo.x + Math.max(0, Math.round((monGeo.width - frameRect.width) / 2));
            const y = monGeo.y + Math.max(0, Math.round((monGeo.height - frameRect.height) / 2));
            win._wpApplyingGeometry = true;
            try {
                if (win.move_frame) {
                    win.move_frame(false, x, y);
                } else if (win.move_resize_frame) {
                    win.move_resize_frame(false, x, y, frameRect.width, frameRect.height);
                }
            } finally {
                win._wpApplyingGeometry = false;
            }
            win._wayplankCentered = true;
            return true;
        } catch (e) {
            console.error('[WayplankBridge] _centerWindow error:', e);
            return false;
        }
    }

    // Runs fn once after the window actor's first frame, deferred to Mutter's BEFORE_REDRAW
    // (before-update) phase so fn NEVER executes while compositor->priv->frame_in_progress == TRUE
    // inside meta_window_actor_after_paint() (Mutter 51 assertion in compositor.c:498).
    _onFirstFrame(win, fn) {
        this._cancelPendingFirstFrame(win);
        const act = win.get_compositor_private ? win.get_compositor_private() : null;
        if (!act || !act.connect)
            return;
        win._wpFirstFrameId = act.connect('first-frame', () => {
            if (win._wpFirstFrameId) {
                try { act.disconnect(win._wpFirstFrameId); } catch (e) { }
                win._wpFirstFrameId = 0;
            }
            if (!win || win._wpUnmanaging)
                return;
            const runDeferred = () => {
                win._wpLaterId = 0;
                win._wpIdleId = 0;
                if (!win || win._wpUnmanaging)
                    return GLib.SOURCE_REMOVE;
                fn();
                return GLib.SOURCE_REMOVE;
            };
            try {
                if (global.compositor && typeof global.compositor.get_laters === 'function') {
                    win._wpLaterId = global.compositor.get_laters().add(
                        Meta.LaterType.BEFORE_REDRAW, runDeferred);
                    return;
                }
                if (Meta.later_add) {
                    win._wpLaterId = Meta.later_add(
                        Meta.LaterType.BEFORE_REDRAW, runDeferred);
                    return;
                }
            } catch (e) { }
            win._wpIdleId = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, runDeferred);
        });
    }

    // Rule 9 (Strut Purity): Base work area is anchored strictly to physical monitor geometry (monGeo)
    // with an offset applied solely for GNOME Shell's fixed native top panel on the primary monitor.
    // Never read ws.get_work_area_for_monitor(i), which recalculates asynchronously on BEFORE_REDRAW
    // and includes WayPlank's own strut or third-party docks (e.g. ubuntu-dock).
    _baseWorkArea(i) {
        const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
        if (nMonitors <= 0)
            return { x: 0, y: 0, width: 1920, height: 1080 };
        const pMon = this._getSafePrimaryMonitor(nMonitors);
        const monIdx = (i >= 0 && i < nMonitors) ? i : pMon;
        const g = global.display.get_monitor_geometry(monIdx);
        const topPanelHeight = (monIdx === pMon && Main.panel && Main.panel.height && Main.panel.visible !== false)
            ? Main.panel.height : 0;
        return {
            x: g.x,
            y: g.y + topPanelHeight,
            width: g.width,
            height: Math.max(0, g.height - topPanelHeight)
        };
    }

    _applyDockPosition(win, entry, x, y, width, height) {
        if (!win || win._wpUnmanaging || this._classifyWindow(win) !== 'dock')
            return false;
        try {
            if (win.hide_from_window_list)
                win.hide_from_window_list();

            const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
            if (nMonitors <= 0)
                return false;

            let targetMon = -1;
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
            const pMon = this._getSafePrimaryMonitor(nMonitors);
            if (targetMon < 0 || targetMon >= nMonitors) {
                targetMon = pMon;
            }

            // Rule 9 (Strut Purity): Anchor dock placement strictly to physical monitor geometry (monGeo).
            // Window coordinates must NEVER be calculated relative to dynamic work_area (wa), which shrinks
            // when reserving space and recalculates asynchronously in Mutter.
            const monGeo = global.display.get_monitor_geometry(targetMon);
            const isPrimary = (targetMon === pMon);
            if (entry)
                entry.onPrimary = isPrimary;
            const topPanelHeight = (isPrimary && Main.panel && Main.panel.height) ? Main.panel.height : 0;

            let targetX = x;
            let targetY = y;

            const rPos = (entry && entry.reserveEnabled) ? entry.reservePosition : -1;
            let isTop;
            if (rPos === 2)
                isTop = true;
            else if (rPos === 3)
                isTop = false;
            else
                isTop = (y <= monGeo.y + topPanelHeight + 100);

            let isLeft;
            if (rPos === 0)
                isLeft = true;
            else if (rPos === 1)
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
            if (entry)
                entry.geo = { x: targetX, y: targetY, width, height };

            // user_op = true: on Wayland the dock is a NORMAL toplevel (never META_WINDOW_DOCK),
            // so Mutter's constrain_fully_onscreen would shove it out of its OWN reserve-space
            // strut (constraints.c). User-op moves skip that constraint and clear the window's
            // require_fully_onscreen flag, so later work-area re-constraints leave it in place.
            const move = () => {
                try {
                    if (!this._isWindowAlive(win) || this._classifyWindow(win) !== 'dock')
                        return;
                    this._ensureWindowStickyAbove(win);
                    if (win.hide_from_window_list)
                        win.hide_from_window_list();
                    const frameRect = win.get_frame_rect ? win.get_frame_rect() : null;
                    if (frameRect && frameRect.x === targetX && frameRect.y === targetY &&
                        frameRect.width === width && frameRect.height === height) {
                        return;
                    }
                    win._wpApplyingGeometry = true;
                    try {
                        if (win.move_frame) {
                            win.move_frame(true, targetX, targetY);
                        }
                        if (win.move_resize_frame) {
                            win.move_resize_frame(true, targetX, targetY, width, height);
                        }
                    } finally {
                        win._wpApplyingGeometry = false;
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

    _applyHoverPosition(win, pid, x, y, width, height) {
        if (!win || win._wpUnmanaging || this._classifyWindow(win) !== 'hover')
            return false;
        try {
            if (win.hide_from_window_list)
                win.hide_from_window_list();
            if (win.demands_attention)
                win.demands_attention = false;

            const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
            if (nMonitors <= 0)
                return false;

            let targetX = x;
            let targetY = y;
            const effPid = pid > 0 ? pid : ((win.get_pid ? win.get_pid() : 0) || 0);

            let targetMon = -1;
            const cx = x + Math.floor((width > 0 ? width : 60) / 2);
            const cy = y + Math.floor((height > 0 ? height : 28) / 2);
            const dockEntry = this._findNearestDockEntryForPid(effPid, cx, cy);
            const dockWin = dockEntry ? this._findDockWindowForEntry(dockEntry) : null;
            const dockRect = (dockEntry && dockEntry.geo) ? dockEntry.geo : (dockWin ? dockWin.get_frame_rect() : null);

            for (let i = 0; i < nMonitors; i++) {
                const geo = global.display.get_monitor_geometry(i);
                if (cx >= geo.x && cx < geo.x + geo.width &&
                    cy >= geo.y && cy < geo.y + geo.height) {
                    targetMon = i;
                    break;
                }
            }
            if (targetMon === -1 && dockWin && dockWin.get_monitor) {
                const dm = dockWin.get_monitor();
                if (dm >= 0 && dm < nMonitors)
                    targetMon = dm;
            }

            if (dockRect) {
                const pMon = this._getSafePrimaryMonitor(nMonitors);
                const monIdx = (targetMon >= 0 && targetMon < nMonitors) ? targetMon : pMon;
                const monGeo = global.display.get_monitor_geometry(monIdx);
                const topPanelHeight = (monIdx === pMon && Main.panel && Main.panel.height && Main.panel.visible !== false)
                    ? Main.panel.height : 0;
                const isHorizontal = dockRect.width >= dockRect.height;
                const isTop = (dockEntry && dockEntry.reserveEnabled && dockEntry.reservePosition === 2) ||
                              (isHorizontal && dockRect.y <= monGeo.y + topPanelHeight + 12);
                if (isTop && topPanelHeight > 0)
                    targetY = y + topPanelHeight;
            }

            win._wpHoverGeo = { pid: effPid, x: targetX, y: targetY, width, height };

            const move = () => {
                try {
                    if (!this._isWindowAlive(win) || this._classifyWindow(win) !== 'hover')
                        return;
                    this._ensureWindowStickyAbove(win);
                    if (win.hide_from_window_list)
                        win.hide_from_window_list();
                    if (win.demands_attention)
                        win.demands_attention = false;
                    const frameRect = win.get_frame_rect ? win.get_frame_rect() : null;
                    if (frameRect && frameRect.x === targetX && frameRect.y === targetY)
                        return;
                    win._wpApplyingGeometry = true;
                    try {
                        if (win.move_frame) {
                            win.move_frame(true, targetX, targetY);
                        } else if (win.move_resize_frame && frameRect) {
                            win.move_resize_frame(true, targetX, targetY, frameRect.width, frameRect.height);
                        }
                    } finally {
                        win._wpApplyingGeometry = false;
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

    _applyPoofPosition(win, pid, x, y, width, height) {
        if (!win || win._wpUnmanaging)
            return false;
        try {
            if (win.hide_from_window_list)
                win.hide_from_window_list();
            if (win.demands_attention)
                win.demands_attention = false;
            win._wayplankCentered = true;

            const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
            if (nMonitors <= 0)
                return false;

            const effPid = pid > 0 ? pid : ((win.get_pid ? win.get_pid() : 0) || 0);
            let targetMon = -1;
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

            let targetX = x;
            let targetY = y;
            const dockEntry = this._findNearestDockEntryForPid(effPid, cx, cy);
            const dockWin = dockEntry ? this._findDockWindowForEntry(dockEntry) : null;
            const dockRect = (dockEntry && dockEntry.geo) ? dockEntry.geo : (dockWin && dockWin.get_frame_rect ? dockWin.get_frame_rect() : null);
            if (dockRect && targetMon >= 0 && targetMon < nMonitors) {
                const monGeo = global.display.get_monitor_geometry(targetMon);
                const isHorizontal = dockRect.width >= dockRect.height;
                const isTop = isHorizontal && dockRect.y < monGeo.y + 120;
                if (isTop && y <= monGeo.y + 120) {
                    targetY = dockRect.y;
                }
            }

            // user_op = true: the poof is drawn over the dock (inside the reserve-space strut);
            // a non-user move would be shoved out of the strut by constrain_fully_onscreen.
            const move = () => {
                try {
                    if (!this._isWindowAlive(win))
                        return;
                    this._ensureWindowStickyAbove(win);
                    if (win.hide_from_window_list)
                        win.hide_from_window_list();
                    if (win.demands_attention)
                        win.demands_attention = false;
                    win._wpApplyingGeometry = true;
                    try {
                        if (win.move_frame) {
                            win.move_frame(true, targetX, targetY);
                        }
                        if (win.move_resize_frame) {
                            win.move_resize_frame(true, targetX, targetY, width, height);
                        }
                    } finally {
                        win._wpApplyingGeometry = false;
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
            const activePoof = this._hasActivePoofForWindow(targetWin);
            if (kind === 'unknown' && activePoof) {
                const title = (targetWin.get_title ? targetWin.get_title() : '') || '';
                const lowerTitle = title.toLowerCase();
                if (!this._isExactDockTitle(lowerTitle) && !lowerTitle.includes('hover') && !lowerTitle.includes('prefer') && !lowerTitle.includes('help')) {
                    kind = 'poof';
                }
            }
            if (kind === 'dock') {
                try {
                    if (targetWin.hide_from_window_list)
                        targetWin.hide_from_window_list();
                } catch (e) { }
                const entry = this._findEntryForDockWindow(targetWin);
                if (entry && entry.geo) {
                    const { x, y, width, height } = entry.geo;
                    this._applyDockPosition(targetWin, entry, x, y, width, height);
                } else if (targetWin.mapped) {
                    try { this._ensureWindowStickyAbove(targetWin); } catch (e) { }
                } else {
                    this._onFirstFrame(targetWin, () => {
                        if (this._isWindowAlive(targetWin) && this._classifyWindow(targetWin) === 'dock') {
                            try { this._ensureWindowStickyAbove(targetWin); } catch (e) { }
                        }
                    });
                }
            } else if (kind === 'hover') {
                try {
                    targetWin.demands_attention = false;
                    if (targetWin.hide_from_window_list)
                        targetWin.hide_from_window_list();
                } catch (e) { }
                const wPid = (targetWin.get_pid ? targetWin.get_pid() : 0) || 0;
                const hoverGeo = targetWin._wpHoverGeo || this._hoverByPid.get(wPid) || this._hoverByPid.get(0);
                if (hoverGeo) {
                    const { x, y, width, height } = hoverGeo;
                    this._applyHoverPosition(targetWin, wPid, x, y, width, height);
                }
            } else if (kind === 'poof') {
                try {
                    targetWin.demands_attention = false;
                    if (targetWin.hide_from_window_list)
                        targetWin.hide_from_window_list();
                } catch (e) { }
                targetWin._wayplankCentered = true;
                const wPid = (targetWin.get_pid ? targetWin.get_pid() : 0) || 0;
                const poofGeo = this._poofByPid.get(wPid) || this._poofByPid.get(0);
                if (poofGeo) {
                    const { x, y, width, height } = poofGeo;
                    this._applyPoofPosition(targetWin, wPid, x, y, width, height);
                }
            } else if (kind === 'dialog') {
                try {
                    targetWin.demands_attention = false;
                } catch (e) { }
                if (targetWin.mapped) {
                    try { targetWin.activate(global.get_current_time()); } catch (e) { }
                    this._centerWindow(targetWin);
                } else {
                    this._onFirstFrame(targetWin, () => {
                        if (this._isWindowAlive(targetWin)) {
                            try { targetWin.activate(global.get_current_time()); } catch (e) { }
                            this._centerWindow(targetWin);
                        }
                    });
                }
            }
        };

        applyRole(win);

        const winId = win.get_stable_sequence ? win.get_stable_sequence().toString() : (win.get_id ? win.get_id().toString() : '');
        const sigs = [];
        sigs.push(win.connect('unmanaged', () => {
            const cls = this._classifyWindow(win);
            const entry = (cls === 'dock') ? this._findEntryForDockWindow(win) : null;
            win._wpUnmanaging = true;
            this._cancelPendingFirstFrame(win);
            if (this._minMap && winId)
                this._minMap.delete(winId);
            if (this._desktopRestoredWindows && winId)
                this._desktopRestoredWindows = this._desktopRestoredWindows.filter(id => id !== winId);
            this._windowSignals.delete(win);
            if (entry && !this._findDockWindowForEntry(entry)) {
                this.ReleaseDock(entry.key);
            }
            if (cls === 'other')
                this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('notify::minimized', () => {
            if (this._minMap && winId) {
                if (win.minimized)
                    this._minMap.set(winId, ++this._minSeq);
                else
                    this._minMap.delete(winId);
            }
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('notify::demands-attention', () => {
            if (this._classifyWindow(win) === 'other')
                this._notifyWindowsChanged();
        }));
        try {
            sigs.push(win.connect('notify::urgent', () => {
                if (this._classifyWindow(win) === 'other')
                    this._notifyWindowsChanged();
            }));
        } catch (e) { }
        sigs.push(win.connect('notify::maximized-horizontally', () => {
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('notify::maximized-vertically', () => {
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('notify::fullscreen', () => {
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('workspace-changed', () => {
            this._notifyWindowsChanged();
        }));
        sigs.push(win.connect('position-changed', () => {
            if (win._wpApplyingGeometry || win._wpUnmanaging)
                return;
            const kind = this._classifyWindow(win);
            if (kind === 'dock') {
                const entry = this._findEntryForDockWindow(win);
                if (entry && entry.geo) {
                    const { x, y, width, height } = entry.geo;
                    this._applyDockPosition(win, entry, x, y, width, height);
                }
            } else if (kind === 'hover' && win._wpHoverGeo) {
                const { pid, x, y, width, height } = win._wpHoverGeo;
                this._applyHoverPosition(win, pid || 0, x, y, width, height);
            } else if (kind === 'other') {
                this._notifyWindowsChanged();
            }
        }));
        sigs.push(win.connect('size-changed', () => {
            if (win._wpApplyingGeometry || win._wpUnmanaging)
                return;
            const currentKind = this._classifyWindow(win);
            if (currentKind === 'dock') {
                const entry = this._findEntryForDockWindow(win);
                if (entry && entry.geo) {
                    const { x, y, width, height } = entry.geo;
                    this._applyDockPosition(win, entry, x, y, width, height);
                }
            } else if (currentKind === 'hover') {
                const wPid = (win.get_pid ? win.get_pid() : 0) || 0;
                const hoverGeo = win._wpHoverGeo || this._hoverByPid.get(wPid) || this._hoverByPid.get(0);
                if (hoverGeo) {
                    const { x, y, width, height } = hoverGeo;
                    this._applyHoverPosition(win, wPid, x, y, width, height);
                }
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
        sigs.push(win.connect('notify::wm-class', () => {
            applyRole(win);
            if (this._classifyWindow(win) === 'other')
                this._notifyWindowsChanged();
        }));

        this._windowSignals.set(win, sigs);
    }

    _findPoofWindow(pid = 0) {
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (!win || win._wpUnmanaging) continue;
            const wPid = (win.get_pid ? win.get_pid() : 0) || 0;
            if (pid > 0 && wPid > 0 && wPid !== pid) continue;
            if (this._classifyWindow(win) === 'poof')
                return win;
        }
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (!win || win._wpUnmanaging) continue;
            const wPid = (win.get_pid ? win.get_pid() : 0) || 0;
            if (pid > 0 && wPid > 0 && wPid !== pid) continue;
            const role = ((win.get_role ? win.get_role() : '') || '').toLowerCase();
            if (role === 'dock') continue;
            const kind = this._classifyWindow(win);
            if (kind === 'poof') return win;
            if (kind === 'unknown') {
                const title = (win.get_title ? win.get_title() : '') || '';
                const lowerTitle = title.toLowerCase();
                if (lowerTitle === 'wayplank-poof')
                    return win;
            }
        }
        return null;
    }

    _findHoverWindow(pid = 0) {
        const actors = global.get_window_actors();
        let unmappedMatch = null;
        for (let i = actors.length - 1; i >= 0; i--) {
            const actor = actors[i];
            if (!actor || (actor.is_destroyed && actor.is_destroyed()))
                continue;
            const win = actor.meta_window;
            if (!win || win._wpUnmanaging || win.minimized || this._classifyWindow(win) !== 'hover')
                continue;
            const wPid = (win.get_pid ? win.get_pid() : 0) || 0;
            if (pid > 0 && wPid > 0 && wPid !== pid)
                continue;
            if (win.mapped)
                return win;
            if (!unmappedMatch)
                unmappedMatch = win;
        }
        return unmappedMatch;
    }

    _findDockWindowForEntry(entry) {
        if (!entry)
            return null;
        for (const actor of global.get_window_actors()) {
            if (!actor || (actor.is_destroyed && actor.is_destroyed()))
                continue;
            const win = actor.meta_window;
            if (!win || win._wpUnmanaging || this._classifyWindow(win) !== 'dock')
                continue;
            const wPid = (win.get_pid ? win.get_pid() : 0) || 0;
            const wSlot = this._dockSlotForWindow(win);
            if ((entry.pid <= 0 || wPid === entry.pid) && wSlot === entry.slot)
                return win;
        }
        return null;
    }

    _findEntryForDockWindow(win) {
        if (!win)
            return null;
        const wPid = (win.get_pid ? win.get_pid() : 0) || 0;
        const wSlot = this._dockSlotForWindow(win);
        if (wPid > 0) {
            const exact = this._docks.get(`${wPid}:${wSlot}`);
            if (exact)
                return exact;
        }
        return this._docks.get(`0:${wSlot}`) || null;
    }

    _findNearestDockEntryForPid(pid, cx, cy) {
        let best = null;
        let bestDist = Infinity;
        for (const entry of this._docks.values()) {
            if (pid > 0 && entry.pid > 0 && entry.pid !== pid)
                continue;
            if (!entry.geo) {
                if (!best)
                    best = entry;
                continue;
            }
            const dx = (entry.geo.x + entry.geo.width / 2) - cx;
            const dy = (entry.geo.y + entry.geo.height / 2) - cy;
            const d2 = dx * dx + dy * dy;
            if (d2 < bestDist) {
                bestDist = d2;
                best = entry;
            }
        }
        return best;
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
            const wmClassInstance = win.get_wm_class_instance ? win.get_wm_class_instance() : '';
            const gtkAppId = win.get_gtk_application_id ? win.get_gtk_application_id() : '';
            const title = win.get_title ? win.get_title() : '';
            const isMinimized = win.minimized;
            const isTop = (win === topWin) || (win === focusWin) || (focusId === id) || (this._lastActiveUuid === id) || (win.has_focus ? win.has_focus() : false);
            const isActive = !isMinimized && isTop;
            const isFullscreen = win.is_fullscreen ? win.is_fullscreen() : false;
            const isDialog = (windowType === Meta.WindowType.DIALOG) || (win.get_transient_for ? win.get_transient_for() !== null : false);
            const isMaximized = (win.maximized_horizontally && win.maximized_vertically) || isFullscreen;
            const demandsAttention = Boolean((win.demands_attention || win.urgent) && win !== focusWin);
            const minimizedSequence = isMinimized ? (this._minMap ? (this._minMap.get(id) || 0) : 0) : 0;
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
                resourceName: gtkAppId || wmClassInstance || '',
                caption: title || '',
                active: isActive,
                minimized: isMinimized,
                maximized: isMaximized,
                fullscreen: isFullscreen,
                isDialog: isDialog,
                demandsAttention: demandsAttention,
                minimizedSequence: minimizedSequence,
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
                    const id = win.get_stable_sequence ? win.get_stable_sequence().toString() : (win.get_id ? win.get_id().toString() : '');
                    if (id)
                        this._desktopRestoredWindows.push(id);
                    win.minimize();
                }
            }
        } else {
            if (this._desktopRestoredWindows && this._desktopRestoredWindows.length > 0) {
                for (const uuid of this._desktopRestoredWindows) {
                    const win = this._findWindowByUuid(uuid);
                    if (win) {
                        try { win.unminimize(); } catch (e) {}
                    }
                }
                this._desktopRestoredWindows = [];
            } else {
                for (const win of windows) {
                    try { win.unminimize(); } catch (e) {}
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
            const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
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

    // D-Bus Method: CaptureWindow (GNOME 45-47 get_image + GNOME 48-51 paint_to_content)
    async CaptureWindow(uuid, filename) {
        try {
            const win = this._findWindowByUuid(uuid);
            if (!win)
                return false;
            const actor = win.get_compositor_private ? win.get_compositor_private() : null;
            if (!actor)
                return false;
            if (typeof actor.get_image === 'function') {
                const surface = actor.get_image(null);
                if (!surface || !surface.writeToPNG)
                    return false;
                surface.writeToPNG(filename);
                return true;
            }
            if (typeof actor.paint_to_content === 'function' &&
                Shell.Screenshot && typeof Shell.Screenshot.composite_to_stream === 'function') {
                const content = actor.paint_to_content(null);
                const texture = (content && typeof content.get_texture === 'function') ? content.get_texture() : null;
                if (!texture)
                    return false;
                const file = Gio.File.new_for_path(filename);
                const stream = file.replace(null, false, Gio.FileCreateFlags.PRIVATE, null);
                try {
                    await Shell.Screenshot.composite_to_stream(
                        texture, 0, 0, -1, -1, 1, null, 0, 0, 1, stream
                    );
                } finally {
                    try { stream.close(null); } catch (e2) { }
                }
                return true;
            }
            return false;
        } catch (e) {
            console.error('[WayplankBridge] CaptureWindow error:', e);
            return false;
        }
    }

    // D-Bus Method: TakeScreenshot (native GNOME Shell Main.screenshotUI & Shell.Screenshot)
    async TakeScreenshot(mode, filename) {
        try {
            if (mode === 'interactive') {
                if (!Main.screenshotUI || typeof Main.screenshotUI.open !== 'function')
                    return false;
                await Main.screenshotUI.open();
                if (Main.screenshotUI._selectionButton)
                    Main.screenshotUI._selectionButton.checked = true;
                return true;
            }
            if (mode === 'fullscreen') {
                if (filename && Shell.Screenshot) {
                    const dir = GLib.path_get_dirname(filename);
                    if (dir)
                        GLib.mkdir_with_parents(dir, 0o755);
                    const file = Gio.File.new_for_path(filename);
                    const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null);
                    try {
                        const shooter = new Shell.Screenshot();
                        await shooter.screenshot(false, stream);
                    } finally {
                        try { stream.close(null); } catch (e2) { }
                    }
                    return true;
                }
                if (Main.screenshotUI && typeof Main.screenshotUI.open === 'function') {
                    await Main.screenshotUI.open();
                    if (Main.screenshotUI._screenButton)
                        Main.screenshotUI._screenButton.checked = true;
                    return true;
                }
                return false;
            }
            if (mode === 'window') {
                const focusWin = global.display && global.display.get_focus_window
                    ? global.display.get_focus_window()
                    : (global.display ? global.display.focus_window : null);
                const hasNormalFocus = focusWin && this._classifyWindow(focusWin) === 'other';
                if (hasNormalFocus && filename && Shell.Screenshot) {
                    const dir = GLib.path_get_dirname(filename);
                    if (dir)
                        GLib.mkdir_with_parents(dir, 0o755);
                    const file = Gio.File.new_for_path(filename);
                    const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null);
                    try {
                        const shooter = new Shell.Screenshot();
                        await shooter.screenshot_window(true, false, stream);
                    } finally {
                        try { stream.close(null); } catch (e2) { }
                    }
                    return true;
                }
                if (Main.screenshotUI && typeof Main.screenshotUI.open === 'function') {
                    await Main.screenshotUI.open();
                    if (Main.screenshotUI._windowButton)
                        Main.screenshotUI._windowButton.checked = true;
                    return true;
                }
                return false;
            }
            return false;
        } catch (e) {
            console.error('[WayplankBridge] TakeScreenshot error:', e);
            return false;
        }
    }

    // D-Bus Method: GetPrimaryMonitor
    GetPrimaryMonitor() {
        const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
        const pMon = this._getSafePrimaryMonitor(nMonitors);
        const geo = (pMon >= 0 && global.display && global.display.get_monitor_geometry)
            ? global.display.get_monitor_geometry(pMon)
            : { x: 0, y: 0, width: 1920, height: 1080 };
        return JSON.stringify({ x: geo.x, y: geo.y, width: geo.width, height: geo.height });
    }

    // D-Bus Method: PositionDock (legacy compatibility wrapper)
    PositionDock(x, y, width, height) {
        return this.PositionDockFor('0:1', x, y, width, height);
    }

    // D-Bus Method: PositionDockFor
    PositionDockFor(dockKey, x, y, width, height) {
        const entry = this._getOrCreateDockEntry(dockKey);
        entry.geo = { x, y, width, height };
        try {
            const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
            if (nMonitors > 0) {
                const pMon = this._getSafePrimaryMonitor(nMonitors);
                const cx = x + Math.floor(width / 2);
                const cy = y + Math.floor(height / 2);
                let mon = -1;
                for (let i = 0; i < nMonitors; i++) {
                    const geo = global.display.get_monitor_geometry(i);
                    if (cx >= geo.x && cx < geo.x + geo.width &&
                        cy >= geo.y && cy < geo.y + geo.height) {
                        mon = i;
                        break;
                    }
                }
                if (mon !== -1)
                    entry.onPrimary = (mon === pMon);
            }
        } catch (e) { }

        const win = this._findDockWindowForEntry(entry);
        let ok = true;
        if (win) {
            ok = this._applyDockPosition(win, entry, x, y, width, height);
        }
        // Keep this dock's reserve-space strut strictly bound to its active monitor whenever
        // PositionDockFor moves the dock across monitors or re-anchors after cable hotplug/unplug.
        if (entry.reserveEnabled && entry.reserveThickness > 0 && entry.reservePosition >= 0) {
            this._syncReserveStrutForEntry(entry, true, entry.reserveThickness, entry.reservePosition);
        }
        return ok;
    }

    // D-Bus Method: PositionHover
    PositionHover(x, y, width, height) {
        return this.PositionHoverFor(0, x, y, width, height);
    }

    // D-Bus Method: PositionHoverFor
    PositionHoverFor(pid, x, y, width, height) {
        const effPid = pid > 0 ? pid : 0;
        this._hoverByPid.set(effPid, { x, y, width, height });
        const win = this._findHoverWindow(effPid);
        if (win) {
            return this._applyHoverPosition(win, effPid, x, y, width, height);
        }
        return false;
    }

    // D-Bus Method: PositionPoof
    PositionPoof(x, y, width, height) {
        return this.PositionPoofFor(0, x, y, width, height);
    }

    // D-Bus Method: PositionPoofFor
    PositionPoofFor(pid, x, y, width, height) {
        const effPid = pid > 0 ? pid : 0;
        this._poofByPid.set(effPid, { x, y, width, height, time: Date.now() });
        const win = this._findPoofWindow(effPid);
        if (win) {
            return this._applyPoofPosition(win, effPid, x, y, width, height);
        }
        return false;
    }

    _syncReserveStrutForEntry(entry, enabled, thickness, position) {
        if (!entry)
            return false;
        const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
        if (!enabled || thickness <= 0 || position < 0 || position > 3 || nMonitors <= 0) {
            this._destroyEntryStrut(entry);
            if (Main.layoutManager && Main.layoutManager._queueUpdateRegions) {
                try { Main.layoutManager._queueUpdateRegions(); } catch (e) { }
            }
            return true;
        }

        let targetMon = -1;
        try {
            if (entry.geo) {
                const cx = entry.geo.x + Math.floor(entry.geo.width / 2);
                const cy = entry.geo.y + Math.floor(entry.geo.height / 2);
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
                const dockWin = this._findDockWindowForEntry(entry);
                if (dockWin && dockWin.get_monitor) {
                    const wm = dockWin.get_monitor();
                    if (wm >= 0 && wm < nMonitors)
                        targetMon = wm;
                }
            }
            if (targetMon === -1) {
                targetMon = (global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0;
            }
        } catch (e) {
            targetMon = 0;
        }
        if (targetMon < 0 || targetMon >= nMonitors)
            targetMon = 0;

        try {
            const monGeo = global.display.get_monitor_geometry(targetMon);
            const base = this._baseWorkArea(targetMon);
            let sx = monGeo.x, sy = monGeo.y, sw = monGeo.width, sh = monGeo.height;

            // Position: 0=LEFT, 1=RIGHT, 2=TOP, 3=BOTTOM — anchored strictly to targetMon's monGeo + primary top panel (Rule 5.9)
            if (position === 2) { // TOP
                sh = (base.y - monGeo.y) + thickness;
            } else if (position === 3) { // BOTTOM
                sy = monGeo.y + monGeo.height - thickness;
                sh = thickness;
            } else if (position === 0) { // LEFT
                sw = thickness;
            } else if (position === 1) { // RIGHT
                sx = monGeo.x + monGeo.width - thickness;
                sw = thickness;
            }

            if (entry.strutActor && entry.strutActor.get_parent() && entry.strutActor.visible &&
                entry.strutRect &&
                entry.strutRect.mon === targetMon &&
                entry.strutRect.x === sx && entry.strutRect.y === sy &&
                entry.strutRect.width === sw && entry.strutRect.height === sh) {
                return true;
            }

            entry.strutHealAttempted = false;
            entry.strutRect = { mon: targetMon, x: sx, y: sy, width: sw, height: sh };

            if (entry.strutActor && !entry.strutActor.get_parent()) {
                try { entry.strutActor.destroy(); } catch (e) { }
                entry.strutActor = null;
            }

            if (!entry.strutActor) {
                entry.strutActor = new St.Widget({
                    name: `wayplank-strut-${entry.key}`,
                    reactive: false,
                    can_focus: false,
                    opacity: 0,
                    visible: true,
                });
                entry.strutActor.set_position(sx, sy);
                entry.strutActor.set_size(sw, sh);
                Main.layoutManager.addChrome(entry.strutActor, { affectsStruts: true, trackFullscreen: false });
            } else {
                entry.strutActor.visible = true;
                entry.strutActor.set_position(sx, sy);
                entry.strutActor.set_size(sw, sh);
                try { entry.strutActor.queue_relayout(); } catch (e) { }
            }
            if (Main.layoutManager && Main.layoutManager._queueUpdateRegions)
                Main.layoutManager._queueUpdateRegions();
            return true;
        } catch (e) {
            console.error('[WayplankBridge] _syncReserveStrutForEntry error:', e);
            entry.strutRect = null;
            return false;
        }
    }

    _clampWindowToReserve(win) {
        try {
            if (!this._docks || this._docks.size === 0)
                return;
            if (!win || win._wpUnmanaging || this._classifyWindow(win) !== 'other')
                return;
            const t = win.get_window_type ? win.get_window_type() : Meta.WindowType.NORMAL;
            if ((t !== Meta.WindowType.NORMAL && t !== Meta.WindowType.DIALOG) ||
                (win.is_skip_taskbar && win.is_skip_taskbar()) ||
                win.minimized ||
                (win.is_fullscreen && win.is_fullscreen()) ||
                (win.get_maximized && win.get_maximized() !== 0))
                return;
            const nMonitors = (global.display && global.display.get_n_monitors) ? global.display.get_n_monitors() : 0;
            if (nMonitors <= 0 || !win.get_monitor)
                return;
            const winMon = win.get_monitor();
            if (winMon < 0 || winMon >= nMonitors)
                return;

            const monGeo = global.display.get_monitor_geometry(winMon);
            const base = this._baseWorkArea(winMon);
            let minX = monGeo.x, minY = base.y;
            let maxRight = monGeo.x + monGeo.width, maxBottom = monGeo.y + monGeo.height;
            let anyActive = false;

            for (const entry of this._docks.values()) {
                if (!entry.reserveEnabled || !(entry.reserveThickness > 0) || !entry.strutRect)
                    continue;
                if (entry.strutRect.mon !== winMon)
                    continue;
                anyActive = true;
                const pos = entry.reservePosition;
                const thick = entry.reserveThickness;
                if (pos === 3) maxBottom = Math.min(maxBottom, monGeo.y + monGeo.height - thick);
                else if (pos === 2) minY = Math.max(minY, base.y + thick);
                else if (pos === 0) minX = Math.max(minX, monGeo.x + thick);
                else if (pos === 1) maxRight = Math.min(maxRight, monGeo.x + monGeo.width - thick);
            }
            if (!anyActive)
                return;

            const fr = win.get_frame_rect ? win.get_frame_rect() : null;
            if (!fr || fr.width <= 0 || fr.height <= 0 || !win.move_resize_frame)
                return;
            let nx = fr.x, ny = fr.y, nw = fr.width, nh = fr.height;
            if (ny + nh > maxBottom) {
                ny = Math.max(minY, maxBottom - nh);
                if (ny + nh > maxBottom) nh = Math.max(120, maxBottom - ny);
            }
            if (ny < minY) {
                ny = minY;
                if (ny + nh > maxBottom) nh = Math.max(120, maxBottom - ny);
            }
            if (nx + nw > maxRight) {
                nx = Math.max(minX, maxRight - nw);
                if (nx + nw > maxRight) nw = Math.max(160, maxRight - nx);
            }
            if (nx < minX) {
                nx = minX;
                if (nx + nw > maxRight) nw = Math.max(160, maxRight - nx);
            }
            if (Math.abs(nx - fr.x) >= 1 || Math.abs(ny - fr.y) >= 1 ||
                Math.abs(nw - fr.width) >= 1 || Math.abs(nh - fr.height) >= 1) {
                win.move_resize_frame(false, Math.round(nx), Math.round(ny), Math.round(nw), Math.round(nh));
            }
        } catch (e) { }
    }

    _clampAllWindowsToReserve() {
        if (!this._docks || this._docks.size === 0)
            return;
        try {
            const actors = global.get_window_actors ? global.get_window_actors() : [];
            for (const actor of actors) {
                const w = actor && actor.get_meta_window ? actor.get_meta_window() : null;
                if (w) this._clampWindowToReserve(w);
            }
        } catch (e) { }
    }

    // D-Bus Method: SetReserveSpace (legacy compatibility wrapper)
    SetReserveSpace(enabled, thickness, position) {
        return this.SetReserveSpaceFor('0:1', enabled, thickness, position);
    }

    // D-Bus Method: SetReserveSpaceFor
    SetReserveSpaceFor(dockKey, enabled, thickness, position) {
        const entry = this._getOrCreateDockEntry(dockKey);
        if (entry.reserveEnabled === enabled &&
            entry.reserveThickness === thickness &&
            entry.reservePosition === position) {
            return true;
        }

        entry.reserveEnabled = enabled;
        entry.reserveThickness = thickness;
        entry.reservePosition = position;

        const ok = this._syncReserveStrutForEntry(entry, enabled, thickness, position);
        if (entry.geo) {
            const win = this._findDockWindowForEntry(entry);
            if (win) {
                this._applyDockPosition(win, entry, entry.geo.x, entry.geo.y, entry.geo.width, entry.geo.height);
            }
        }
        if (enabled && thickness > 0)
            this._clampAllWindowsToReserve();
        return ok;
    }

    // D-Bus Method: ReleaseDock
    ReleaseDock(dockKey) {
        const parsed = this._parseDockKey(dockKey);
        const entry = this._docks.get(parsed.key);
        if (!entry)
            return false;
        this._destroyEntryStrut(entry);
        this._docks.delete(parsed.key);
        if (parsed.pid > 0) {
            let hasOtherDockForPid = false;
            for (const other of this._docks.values()) {
                if (other.pid === parsed.pid) {
                    hasOtherDockForPid = true;
                    break;
                }
            }
            if (!hasOtherDockForPid) {
                this._hoverByPid.delete(parsed.pid);
                this._poofByPid.delete(parsed.pid);
            }
        }
        if (Main.layoutManager && Main.layoutManager._queueUpdateRegions) {
            try { Main.layoutManager._queueUpdateRegions(); } catch (e) { }
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
			session_bus = DbusBroker.get_default ().get_session_bus ();
			if (session_bus != null) {
				display_config_sub_id = session_bus.signal_subscribe (
					null,
					"org.gnome.Mutter.DisplayConfig",
					"MonitorsChanged",
					"/org/gnome/Mutter/DisplayConfig",
					null,
					DBusSignalFlags.NONE,
					on_display_config_monitors_changed
				);
			}
			ensure_extension_installed ();
			connect_bridge ();
			return true;
		}

		void on_display_config_monitors_changed (DBusConnection conn, string? sender, string object_path, string interface_name, string signal_name, Variant parameters)
		{
			pending_monitor_sync = true;
			notify_monitor_layout_changed ();
		}

		void notify_monitor_layout_changed ()
		{
			primary_monitor_changed ();
		}

		void ensure_extension_installed ()
		{
			// GNOME Safety Mode Self-Healing:
			// If GNOME Shell previously crashed and entered failsafe mode ('disable-user-extensions = true'),
			// reset the master switch and ensure our extension UUID is enrolled.
			var schema_source = SettingsSchemaSource.get_default ();
			var shell_schema = schema_source != null ? schema_source.lookup ("org.gnome.shell", true) : null;
			if (shell_schema != null) {
				var shell_settings = new GLib.Settings ("org.gnome.shell");
				if (shell_schema.has_key ("disable-user-extensions")
					&& shell_settings.get_boolean ("disable-user-extensions")) {
					message ("MutterBackend: GNOME Shell Safety Mode detected (disable-user-extensions=true), auto-recovering...");
					shell_settings.set_boolean ("disable-user-extensions", false);
				}

				if (shell_schema.has_key ("disabled-extensions")) {
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
				}

				if (shell_schema.has_key ("enabled-extensions")) {
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

				if (ext_enable_timer_id > 0U) {
					GLib.Source.remove (ext_enable_timer_id);
					ext_enable_timer_id = 0U;
				}
				activate_extension_in_shell (code_changed && current_js != null);
			} catch (Error e) {
				warning ("MutterBackend: failed to deploy extension: %s", e.message);
			}
		}

		void activate_extension_in_shell (bool cycle_reload)
		{
			if (session_bus != null) {
				try {
					if (cycle_reload) {
						session_bus.call_sync (
							"org.gnome.Shell",
							"/org/gnome/Shell",
							"org.gnome.Shell.Extensions",
							"DisableExtension",
							new Variant ("(s)", EXTENSION_UUID),
							null,
							DBusCallFlags.NO_AUTO_START,
							1500,
							null
						);
					}
					var res = session_bus.call_sync (
						"org.gnome.Shell",
						"/org/gnome/Shell",
						"org.gnome.Shell.Extensions",
						"EnableExtension",
						new Variant ("(s)", EXTENSION_UUID),
						new VariantType ("(b)"),
						DBusCallFlags.NO_AUTO_START,
						1500,
						null
					);
					bool enabled_ok = false;
					res.get ("(b)", out enabled_ok);
					if (!enabled_ok && ext_enable_timer_id == 0U) {
						ext_enable_timer_id = GLib.Timeout.add (150, () => {
							ext_enable_timer_id = 0U;
							if (session_bus != null && proxy == null) {
								try {
									session_bus.call_sync (
										"org.gnome.Shell",
										"/org/gnome/Shell",
										"org.gnome.Shell.Extensions",
										"EnableExtension",
										new Variant ("(s)", EXTENSION_UUID),
										null,
										DBusCallFlags.NO_AUTO_START,
										1500,
										null
									);
								} catch (Error e) { }
							}
							return false;
						});
					}
					return;
				} catch (Error e) {
					debug ("MutterBackend: direct Shell.Extensions D-Bus activation failed (%s), falling back to CLI", e.message);
				}
			}

			try {
				if (cycle_reload) {
					Process.spawn_command_line_async ("sh -c 'gnome-extensions reset " + EXTENSION_UUID + " >/dev/null 2>&1; gnome-extensions disable " + EXTENSION_UUID + " >/dev/null 2>&1; sleep 0.2; gnome-extensions enable " + EXTENSION_UUID + " >/dev/null 2>&1'");
				} else {
					Process.spawn_command_line_async ("sh -c 'gnome-extensions reset " + EXTENSION_UUID + " >/dev/null 2>&1; gnome-extensions enable " + EXTENSION_UUID + " >/dev/null 2>&1'");
				}
			} catch (Error e) { }
		}

		void connect_bridge ()
		{
			name_watch_id = DbusBroker.get_default ().watch_session_name (
				"org.wayplank.GnomeBridge",
				BusNameWatcherFlags.NONE,
				on_bridge_appeared,
				on_bridge_vanished
			);
		}

		void clear_proxy ()
		{
			if (proxy != null) {
				proxy.windows_changed.disconnect (on_windows_changed);
				proxy = null;
			}
		}

		void on_bridge_appeared (DBusConnection connection, string name, string name_owner)
		{
			clear_proxy ();
			try {
				proxy = connection.get_proxy_sync (
					"org.wayplank.GnomeBridge",
					"/org/wayplank/GnomeBridge"
				);
				string active_gen = "";
				try {
					active_gen = proxy.eval ("this._bridgeGen || ''").replace ("\"", "").strip ();
				} catch (Error e) { }
				if (active_gen != BRIDGE_GEN && !reload_attempted) {
					reload_attempted = true;
					clear_proxy ();
					message ("MutterBackend: Stale GnomeBridge detected in RAM ('%s' != '%s'), forcing live reload...", active_gen, BRIDGE_GEN);
					if (ext_enable_timer_id > 0U) {
						GLib.Source.remove (ext_enable_timer_id);
						ext_enable_timer_id = 0U;
					}
					activate_extension_in_shell (true);
					return;
				}
				message ("MutterBackend: GnomeBridge verified live in GNOME Shell (gen=%s)", active_gen);
				proxy.windows_changed.connect (on_windows_changed);
				refresh_window_infos (true);
				primary_monitor_changed ();
				state_changed ();
				bridge_reconnected ();
				replay_all_dock_states ();
				if (bridge_reposition_timer_id > 0U) {
					GLib.Source.remove (bridge_reposition_timer_id);
					bridge_reposition_timer_id = 0U;
				}
				bridge_reposition_timer_id = GLib.Timeout.add (250, on_bridge_reposition_timeout);
			} catch (Error e) {
				clear_proxy ();
				debug ("MutterBackend: unable to connect to GnomeBridge: %s", e.message);
			}
		}

		void on_bridge_vanished (DBusConnection? connection, string name)
		{
			if (bridge_reposition_timer_id > 0U) {
				GLib.Source.remove (bridge_reposition_timer_id);
				bridge_reposition_timer_id = 0U;
			}
			clear_proxy ();
			last_windows_json = null;
			window_infos.clear ();
			state_changed ();
		}

		void on_windows_changed ()
		{
			if (pending_monitor_sync) {
				pending_monitor_sync = false;
				notify_monitor_layout_changed ();
			}
			if (refresh_window_infos ())
				state_changed ();
		}

		bool refresh_window_infos (bool force = false)
		{
			if (proxy == null)
				return false;
			try {
				var json = proxy.get_windows ();
				if (!force && last_windows_json != null && last_windows_json == json)
					return false;
				last_windows_json = json;
				window_infos = parse_window_infos (json);
				return true;
			} catch (Error e) {
				debug ("MutterBackend: get_windows failed: %s", e.message);
				return false;
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
							var snap = Hal.Apps.inspect_process (info.Pid, false);
							info.Cmdline = snap.full_cmdline;
							info.Executable = snap.executable_comm;
						}
					}

					var desktop_val = (json.has_member ("desktopFileName") && !json.get_null_member ("desktopFileName")) ? json.get_string_member ("desktopFileName") : "";
					var class_val = (json.has_member ("resourceClass") && !json.get_null_member ("resourceClass")) ? json.get_string_member ("resourceClass") : "";
					var name_val = (json.has_member ("resourceName") && !json.get_null_member ("resourceName")) ? json.get_string_member ("resourceName") : "";
					var caption_val = (json.has_member ("caption") && !json.get_null_member ("caption")) ? json.get_string_member ("caption") : "";

					info.DesktopFileName = (desktop_val != null && !desktop_val.has_prefix ("window:")) ? desktop_val : "";
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
					info.Fullscreen = json.has_member ("fullscreen") && json.get_boolean_member ("fullscreen");
					info.IsDialog = json.has_member ("isDialog") && json.get_boolean_member ("isDialog");
					info.DemandsAttention = json.has_member ("demandsAttention") && json.get_boolean_member ("demandsAttention");
					info.MinimizedSequence = json.has_member ("minimizedSequence") ? json.get_int_member ("minimizedSequence") : 0;
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
			if (display_config_sub_id > 0U && session_bus != null) {
				session_bus.signal_unsubscribe (display_config_sub_id);
				display_config_sub_id = 0U;
			}
			session_bus = null;
			pending_monitor_sync = false;
			if (name_watch_id > 0U) {
				DbusBroker.get_default ().unwatch_name (name_watch_id);
				name_watch_id = 0U;
			}
			if (proxy != null && dock_states.size > 0) {
				foreach (var st in dock_states.values) {
					try {
						proxy.release_dock (st.dock_key);
					} catch (Error e) { }
				}
			}
			dock_states.clear ();
			clear_proxy ();
			last_windows_json = null;
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

		static bool is_wayplank_self_window (WindowInfo window)
		{
			string rc_low = window.ResourceClass.down ();
			string df_low = window.DesktopFileName.down ();
			return (rc_low == "wayplank" || rc_low == "plank" || rc_low == "net.launchpad.plank" || rc_low.has_prefix ("net.launchpad.plank.")
				|| df_low == "wayplank" || df_low == "plank" || df_low == "net.launchpad.plank" || df_low.has_prefix ("net.launchpad.plank."));
		}

		public bool fullscreen_window_intersects (Gdk.Rectangle rect)
		{
			foreach (var window in window_infos) {
				if (window.Minimized)
					continue;
				if (!window.CurrentDesktop)
					continue;
				if (is_wayplank_self_window (window))
					continue;
				if (!window.Active || !window.Fullscreen)
					continue;
				if (window.Geometry.width <= 0 || window.Geometry.height <= 0)
					continue;
				if (window.Geometry.intersect (rect, null))
					return true;
			}
			return false;
		}

		bool window_intersects (Gdk.Rectangle dock_rect, bool active_only, bool maximized_only)
		{
			foreach (var window in window_infos) {
				if (window.Minimized)
					continue;
				if (!window.CurrentDesktop)
					continue;
				if (is_wayplank_self_window (window))
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

		MutterDockState ensure_dock_state (string dock_key)
		{
			string norm = (dock_key != null && dock_key != "") ? dock_key : "%d:1".printf (Hal.Runtime.get_current_pid ());
			var st = dock_states.get (norm);
			if (st == null) {
				st = new MutterDockState (norm);
				dock_states.set (norm, st);
			}
			return st;
		}

		void replay_all_dock_states ()
		{
			if (proxy == null)
				return;
			foreach (var st in dock_states.values) {
				if (st.width > 0 && st.height > 0) {
					try {
						proxy.position_dock_for (st.dock_key, st.x, st.y, st.width, st.height);
					} catch (Error e) { }
				}
				if (st.has_reserve && st.reserve_enabled) {
					try {
						proxy.set_reserve_space_for (st.dock_key, st.reserve_enabled, st.reserve_thickness, st.reserve_position);
					} catch (Error e) { }
				}
			}
		}

		bool on_bridge_reposition_timeout ()
		{
			bridge_reposition_timer_id = 0U;
			replay_all_dock_states ();
			return false;
		}

		public bool position_dock (int x, int y, int width, int height)
		{
			return position_dock_for ("%d:1".printf (Hal.Runtime.get_current_pid ()), x, y, width, height);
		}

		public override bool position_dock_for (string dock_key, int x, int y, int width, int height)
		{
			var st = ensure_dock_state (dock_key);
			st.x = x;
			st.y = y;
			st.width = width;
			st.height = height;
			if (proxy == null)
				return false;
			try {
				return proxy.position_dock_for (st.dock_key, x, y, width, height);
			} catch (Error e) {
				return false;
			}
		}

		public bool position_hover (int x, int y, int width, int height)
		{
			return position_hover_for (Hal.Runtime.get_current_pid (), x, y, width, height);
		}

		public override bool position_hover_for (int pid, int x, int y, int width, int height)
		{
			if (proxy == null)
				return false;
			try {
				return proxy.position_hover_for (pid, x, y, width, height);
			} catch (Error e) {
				debug ("MutterBackend: position_hover_for D-Bus: %s", e.message);
				return false;
			}
		}

		public bool position_poof (int x, int y, int width, int height)
		{
			return position_poof_for (Hal.Runtime.get_current_pid (), x, y, width, height);
		}

		public override bool position_poof_for (int pid, int x, int y, int width, int height)
		{
			if (proxy == null)
				return false;
			try {
				return proxy.position_poof_for (pid, x, y, width, height);
			} catch (Error e) {
				debug ("MutterBackend: position_poof_for D-Bus: %s", e.message);
				return false;
			}
		}

		public override void set_reserve_space (bool enabled, int thickness, Gtk.PositionType position)
		{
			set_reserve_space_for ("%d:1".printf (Hal.Runtime.get_current_pid ()), enabled, thickness, position);
		}

		public override void set_reserve_space_for (string dock_key, bool enabled, int thickness, Gtk.PositionType position)
		{
			var st = ensure_dock_state (dock_key);
			if (st.has_reserve &&
			    st.reserve_enabled == enabled &&
			    st.reserve_thickness == thickness &&
			    st.reserve_position == (int) position) {
				return;
			}
			st.has_reserve = true;
			st.reserve_enabled = enabled;
			st.reserve_thickness = thickness;
			st.reserve_position = (int) position;
			if (proxy != null) {
				try {
					proxy.set_reserve_space_for (st.dock_key, enabled, thickness, (int) position);
				} catch (Error e) {
					debug ("MutterBackend: set_reserve_space_for D-Bus: %s", e.message);
				}
			}
		}

		public override void release_dock_surface (string dock_key)
		{
			if (dock_key == null || dock_key == "")
				return;
			dock_states.unset (dock_key);
			if (proxy != null) {
				try {
					proxy.release_dock (dock_key);
				} catch (Error e) {
					debug ("MutterBackend: release_dock D-Bus: %s", e.message);
				}
			}
		}

		public bool capture_window (string uuid, string filename)
		{
			GnomeBridgeProxy? p = proxy;
			if (p == null)
				return false;
			try {
				return p.capture_window (uuid, filename);
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
					var root = parser.get_root ();
					if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
						var obj = root.get_object ();
						x = (int) obj.get_int_member ("x");
						y = (int) obj.get_int_member ("y");
						width = (int) obj.get_int_member ("width");
						height = (int) obj.get_int_member ("height");
						return true;
					}
				} catch (Error e) {
					// Fallback to Mutter DisplayConfig below
				}
			}

			try {
				var bus = DbusBroker.get_default ().get_session_bus ();
				if (bus == null)
					return false;
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
			debug ("MutterBackend.get_workarea_for_geometry for %d,%d %dx%d (proxy=%s)",
				mon_geom.x, mon_geom.y, mon_geom.width, mon_geom.height, proxy != null ? "connected" : "null");
			if (proxy != null) {
				try {
					string json_str;
					try {
						json_str = proxy.get_monitor_workareas ();
					} catch (Error e) {
						debug ("MutterBackend: get_monitor_workareas failed (%s), trying eval fallback", e.message);
						json_str = proxy.eval ("""
							(() => {
								const n = global.display.get_n_monitors();
								const ws = global.workspace_manager.get_active_workspace();
								const res = [];
								for (let i = 0; i < n; i++) {
									const g = global.display.get_monitor_geometry(i);
									const pMon = (global.display && global.display.get_primary_monitor) ? global.display.get_primary_monitor() : 0; const topH = (i === pMon && Main.panel && Main.panel.height && Main.panel.visible !== false) ? Main.panel.height : 0; const wa = (typeof this._baseWorkArea === 'function') ? this._baseWorkArea(i) : { x: g.x, y: g.y + topH, width: g.width, height: Math.max(0, g.height - topH) };
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
							debug ("MutterBackend: matched workarea for %d,%d: wa=%d,%d %dx%d",
								gx, gy, workarea.x, workarea.y, workarea.width, workarea.height);
							return true;
						}
					}
					debug ("MutterBackend: NO match for %d,%d in %u monitor workareas",
						mon_geom.x, mon_geom.y, array.get_length ());
				} catch (Error e) {
					warning ("MutterBackend: failed to get monitor workareas: %s", e.message);
				}
			}
			return false;
		}
	}
}
