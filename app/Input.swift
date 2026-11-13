// Input.swift: what teacher.lua did with hs.eventtap, hs.mouse, hs.canvas and hs.application, natively:
// CGEvent for the mouse and keys, AXUIElement for windows and menus, an NSWindow for the ring.
import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

let primaryHeight: () -> CGFloat = { NSScreen.screens.first?.frame.height ?? 0 }

enum Keys {
    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111,
    ]
    static let aliases: [String: String] = [
        "enter": "return", "esc": "escape", "del": "delete", "bksp": "delete", "backspace": "delete",
        "plus": "=", "minus": "-", "comma": ",", "period": ".", "dot": ".", "slash": "/", "backslash": "\\",
        "semicolon": ";", "quote": "'", "bracketleft": "[", "bracketright": "]", "grave": "`",
        "arrowleft": "left", "arrowright": "right", "arrowup": "up", "arrowdown": "down",
    ]
    // modifier name -> (flag, key code of the modifier key)
    static let mods: [String: (CGEventFlags, CGKeyCode)] = [
        "cmd": (.maskCommand, 55), "command": (.maskCommand, 55),
        "ctrl": (.maskControl, 59), "control": (.maskControl, 59),
        "alt": (.maskAlternate, 58), "option": (.maskAlternate, 58), "opt": (.maskAlternate, 58),
        "shift": (.maskShift, 56), "fn": (.maskSecondaryFn, 63),
    ]

    /// "cmd+shift+t" -> modifiers and the key's code (a "+" at the end is the plus key: shift and =)
    static func parse(_ str: String) -> (mods: [(CGEventFlags, CGKeyCode)], key: CGKeyCode?)? {
        var ms: [(CGEventFlags, CGKeyCode)] = []
        var key: CGKeyCode? = nil
        var parts = str.split(separator: "+", omittingEmptySubsequences: true).map { String($0) }
        if str.hasSuffix("+") { parts.append("+") }
        for part in parts {
            let p = part.lowercased()
            if let m = mods[p] { ms.append(m); continue }
            if part == "+" {
                key = codes["="]
                if let s = mods["shift"] { ms.append(s) }
                continue
            }
            let name = aliases[p] ?? p
            if let c = codes[name] { key = c }
        }
        return (ms, key)
    }

    static func post(_ chord: String, hold: TimeInterval = 0.12) {
        guard let parsed = parse(chord), let key = parsed.key else { return }
        var flags = CGEventFlags()
        for m in parsed.mods {
            flags.insert(m.0)
            if let e = CGEvent(keyboardEventSource: nil, virtualKey: m.1, keyDown: true) {
                e.type = .flagsChanged; e.flags = flags; e.post(tap: .cghidEventTap)
            }
        }
        if let d = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true) {
            d.flags = flags; d.post(tap: .cghidEventTap)
        }
        usleep(UInt32(hold * 1_000_000))
        if let u = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) {
            u.flags = flags; u.post(tap: .cghidEventTap)
        }
        for m in parsed.mods.reversed() {
            flags.remove(m.0)
            if let e = CGEvent(keyboardEventSource: nil, virtualKey: m.1, keyDown: false) {
                e.type = .flagsChanged; e.flags = flags; e.post(tap: .cghidEventTap)
            }
        }
    }

    /// one character typed, whatever the layout (hs.eventtap.keyStrokes)
    static func typeChar(_ ch: Character) {
        let utf16 = Array(String(ch).utf16)
        for down in [true, false] {
            if let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) {
                e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                e.post(tap: .cghidEventTap)
            }
        }
    }
}

enum Mouse {
    static func location() -> CGPoint { return CGEvent(source: nil)?.location ?? .zero }

    static func move(_ p: CGPoint, dragging: Bool) {
        let t: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        if let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
    }

    static func flags(_ names: [String]) -> CGEventFlags {
        var f = CGEventFlags()
        for n in names { if let m = Keys.mods[n.lowercased()] { f.insert(m.0) } }
        return f
    }

    static func click(_ p: CGPoint, right: Bool, count: Int, mods: [String]) {
        let down: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = right ? .rightMouseUp : .leftMouseUp
        let b: CGMouseButton = right ? .right : .left
        for i in 1...max(1, count) {
            for t in [down, up] {
                if let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: b) {
                    e.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                    e.flags = flags(mods)
                    e.post(tap: .cghidEventTap)
                }
            }
        }
    }

    static func button(_ p: CGPoint, down: Bool) {
        let t: CGEventType = down ? .leftMouseDown : .leftMouseUp
        if let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
    }

    static func scroll(dx: Int, dy: Int) {
        if let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                           wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) {
            e.post(tap: .cghidEventTap)
        }
    }
}

/// a ring of light around a point, so the eye finds the target (hs.canvas circle, 22 pt, amber)
final class RingView: NSView {
    override func draw(_ r: NSRect) {
        NSColor(srgbRed: 1, green: 0.75, blue: 0.2, alpha: 0.95).setStroke()
        let p = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        p.lineWidth = 3
        p.stroke()
    }
}

enum Ring {
    static func show(at p: CGPoint, seconds: TimeInterval = 1.4) {
        let r: CGFloat = 22
        let frame = NSRect(x: p.x - r, y: primaryHeight() - p.y - r, width: 2 * r, height: 2 * r)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.contentView = RingView(frame: NSRect(x: 0, y: 0, width: 2 * r, height: 2 * r))
        w.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { w.orderOut(nil) }
    }
}

// MARK: Accessibility: the taught app's window and menu bar (hs.application / hs.window)

enum AX {
    static func runningApp(_ bundle: String, _ name: String) -> NSRunningApplication? {
        if let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { return a }
        return NSWorkspace.shared.runningApplications.first { $0.localizedName == name }
    }

    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success { return v as AnyObject? }
        return nil
    }

    static func window(_ app: NSRunningApplication) -> AXUIElement? {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        if let w = attr(el, kAXMainWindowAttribute as String) { return (w as! AXUIElement) }
        if let w = attr(el, kAXFocusedWindowAttribute as String) { return (w as! AXUIElement) }
        if let ws = attr(el, kAXWindowsAttribute as String) as? [AXUIElement] { return ws.first }
        return nil
    }

    static func frame(_ w: AXUIElement) -> CGRect? {
        guard let pv = attr(w, kAXPositionAttribute as String), let sv = attr(w, kAXSizeAttribute as String) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
        // size first then position again: a window moved to a smaller screen keeps its size otherwise
        if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
    }

    static func windowID(_ w: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(w, &id) == .success && id != 0 ? id : nil
    }

    /// the screen a rectangle (top-left coordinates) is mostly on
    static func screen(of r: CGRect) -> NSScreen? {
        let h = primaryHeight()
        let c = CGPoint(x: r.midX, y: r.midY)
        for s in NSScreen.screens {
            let f = s.frame
            let top = CGRect(x: f.origin.x, y: h - f.origin.y - f.height, width: f.width, height: f.height)
            if top.contains(c) { return s }
        }
        return NSScreen.main
    }

    /// the menu item by its path, exact, through the menu bar: no mouse (hs.application:selectMenuItem)
    static func pressMenu(_ app: NSRunningApplication, _ path: [String]) -> Bool {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = attr(el, kAXMenuBarAttribute as String) else { return false }
        var node = bar as! AXUIElement
        for (i, title) in path.enumerated() {
            guard let kids = attr(node, kAXChildrenAttribute as String) as? [AXUIElement] else { return false }
            var found: AXUIElement? = nil
            for k in kids {
                if let t = attr(k, kAXTitleAttribute as String) as? String, matches(t, title) { found = k; break }
            }
            guard let item = found else { return false }
            if i == path.count - 1 {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            guard let sub = attr(item, kAXChildrenAttribute as String) as? [AXUIElement], let menu = sub.first else { return false }
            node = menu
        }
        return false
    }

    static func matches(_ have: String, _ want: String) -> Bool {
        if have == want { return true }
        let h = have.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespaces)
        let w = want.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespaces)
        return h == w
    }
}
