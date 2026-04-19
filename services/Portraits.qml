pragma Singleton

// Portraits — portrait image collections for the collage background.
//
// Scans `basePath` (from config) for collection subdirs, lazily enumerates
// images per collection, and exposes random/indexed lookup helpers.
//
// State:
//   collections       [{name, path, imageCount}] — updated twice: once
//                     after the directory listing (imageCount=0), once
//                     after per-collection image counts are resolved.
//   defaultCollection string — name of the user's chosen default,
//                     read from ~/.config/somewm/.default_portrait
//                     (plain-text, one line, written by the Lua menu
//                     fishlive.services.portraits:set_default).
//   loading           bool — true while the initial directory scan is
//                     in flight; independent of per-collection scans.
//
// Signals:
//   collectionScanned(name) — per-collection image list is available
//                             in the cache (first time after load).
//
// IPC:
//   somewm-shell:portraits { refresh } — clear caches and rescan.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core" as Core

Singleton {
	id: root

	// Base directory for portrait collections
	readonly property string basePath: {
		var cfg = Core.Config._data
		var p = cfg && cfg.collage && cfg.collage.portraitBasePath
			? cfg.collage.portraitBasePath : ""
		return p || (Quickshell.env("HOME") +
			"/Pictures/wallpapers/public-wallpapers/portrait")
	}

	// Available collections: [{name, path, imageCount}]
	property var collections: []

	// Per-collection image cache: { "joy": ["/path/img1.jpg", ...], ... }
	property var _imageCache: ({})

	// Loading flag
	property bool loading: false

	// User-selected default collection (shared with the Lua-side notifications
	// random-portrait fallback). Plain-text file written by
	// fishlive.services.portraits:set_default(). Empty string when the file
	// does not exist or the value does not match any scanned collection.
	property string defaultCollection: ""

	// Emitted when a specific collection's image list becomes available
	signal collectionScanned(string name)

	// === Public API ===

	// Return cached image list for `name`, or `[]` while the scan is in
	// flight. The per-collection scan is async — callers should listen
	// for `collectionScanned(name)` (or poll `isScanned(name)`) to pick
	// up the populated list on a subsequent call.
	function getImagesForCollection(name) {
		if (_imageCache[name]) return _imageCache[name]
		_scanCollection(name)
		return []
	}

	function getImage(collection, index) {
		var imgs = getImagesForCollection(collection)
		if (imgs.length === 0) return ""
		var idx = ((index % imgs.length) + imgs.length) % imgs.length
		return imgs[idx]
	}

	function randomImage(collection) {
		var imgs = getImagesForCollection(collection)
		if (imgs.length === 0) return ""
		return imgs[Math.floor(Math.random() * imgs.length)]
	}

	function imageCount(collection) {
		var imgs = _imageCache[collection]
		return imgs ? imgs.length : 0
	}

	// True once the image list for `collection` has been resolved (even
	// if the collection turned out to be empty). Callers use this to
	// distinguish "scan still running" from "scan done, zero images".
	function isScanned(collection) {
		return _imageCache.hasOwnProperty(collection)
	}

	function refresh() {
		_imageCache = ({})
		_scanCollections()
	}

	// === Collection directory scanning ===

	function _scanCollections() {
		root.loading = true
		collectionsProc.command = ["find", "-L", root.basePath,
			"-mindepth", "1", "-maxdepth", "1", "-type", "d"]
		collectionsProc.running = true
	}

	Process {
		id: collectionsProc
		stdout: StdioCollector {
			onStreamFinished: {
				var lines = text.trim().split("\n")
				var result = []
				lines.sort()
				lines.forEach(function(line) {
					if (!line) return
					var name = line.split("/").pop()
					result.push({ name: name, path: line, imageCount: 0 })
				})
				root.collections = result
				root.loading = false
				// Kick off per-collection image counts so the UI can
				// show badges and pick a non-empty collection as the
				// auto-select fallback.
				if (result.length > 0) _startCountProc()
			}
		}
	}

	// Count images per collection via a single `find` invocation.
	function _startCountProc() {
		countProc.command = ["bash", "-c",
			"for d in \"$1\"/*/; do " +
			"n=$(find -L \"$d\" -maxdepth 1 -type f " +
			"\\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \\) " +
			"| wc -l); echo \"$(basename \"$d\") $n\"; done",
			"--", root.basePath]
		countProc.running = true
	}

	Process {
		id: countProc
		stdout: StdioCollector {
			onStreamFinished: {
				var lines = text.trim().split("\n")
				var counts = {}
				lines.forEach(function(line) {
					if (!line) return
					var parts = line.split(" ")
					var count = parseInt(parts[parts.length - 1]) || 0
					var name = parts.slice(0, parts.length - 1).join(" ")
					counts[name] = count
				})
				// Update collection imageCount
				var updated = root.collections.map(function(c) {
					return {
						name: c.name,
						path: c.path,
						imageCount: counts[c.name] || 0
					}
				})
				root.collections = updated
			}
		}
	}

	// === Per-collection image scanning ===
	// Queue to handle one scan at a time (Process is not reentrant)
	property var _scanQueue: []
	property string _pendingScanCollection: ""

	function _scanCollection(name) {
		// Already cached or already queued
		if (_imageCache[name]) return
		if (_pendingScanCollection === name) return
		if (_scanQueue.indexOf(name) >= 0) return

		if (imageScanProc.running) {
			_scanQueue.push(name)
			return
		}
		_startScan(name)
	}

	function _startScan(name) {
		var colPath = root.basePath + "/" + name
		root._pendingScanCollection = name
		imageScanProc.command = ["find", "-L", colPath,
			"-maxdepth", "1", "-type", "f",
			"(", "-name", "*.jpg", "-o", "-name", "*.jpeg",
			"-o", "-name", "*.png", "-o", "-name", "*.webp", ")"]
		imageScanProc.running = true
	}

	Process {
		id: imageScanProc
		stdout: StdioCollector {
			onStreamFinished: {
				var lines = text.trim().split("\n")
				var result = []
				lines.sort()
				lines.forEach(function(line) {
					if (line) result.push(line)
				})
				var cache = Object.assign({}, root._imageCache)
				cache[root._pendingScanCollection] = result
				root._imageCache = cache
				var scannedName = root._pendingScanCollection
				root._pendingScanCollection = ""
				root.collectionScanned(scannedName)

				// Process next in queue
				if (root._scanQueue.length > 0) {
					var next = root._scanQueue.shift()
					root._startScan(next)
				}
			}
		}
	}

	// === Default collection (shared with Lua notifications) ===
	//
	// The default is a single line of plain text at
	//   ~/.config/somewm/.default_portrait
	// and is written by the Lua menu (Super+Shift+P →
	// fishlive.services.portraits:set_default). We read it via a Process
	// (`cat`) because FileView.text() on a hidden dot-file returned empty
	// synchronously on first access and `onFileChanged` never fired for
	// the initial load, leading to a misdetected "no default" on startup.
	// FileView is kept solely as a change watcher so that flipping the
	// default via the Lua menu updates the Qt side live.

	readonly property string _defaultFilePath:
		Quickshell.env("HOME") + "/.config/somewm/.default_portrait"

	Process {
		id: defaultProc
		stdout: StdioCollector {
			onStreamFinished: {
				root.defaultCollection = text ? text.trim() : ""
			}
		}
	}

	function _loadDefault() {
		defaultProc.command = ["cat", root._defaultFilePath]
		defaultProc.running = true
	}

	FileView {
		id: defaultWatch
		path: root._defaultFilePath
		watchChanges: true
		onFileChanged: root._loadDefault()
		// Both "file missing" and "FileView couldn't decode this
		// hidden dot-file" flow through here. Re-run `cat` rather
		// than clearing directly — if the file genuinely exists,
		// the Process will succeed and set the value; if not, cat
		// returns empty and the StdioCollector assigns "".
		onLoadFailed: root._loadDefault()
	}

	// === IPC ===

	IpcHandler {
		target: "somewm-shell:portraits"
		function refresh(): void { root.refresh() }
	}

	// Initial scan on startup
	Component.onCompleted: {
		_scanCollections()
		_loadDefault()
	}
}
