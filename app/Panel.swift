// Panel.swift: the floating window. First row native (ON OFF ... TOP PERMISSIONS ✕, Accessibility buttons,
// MANTRA_MANIFEST swift-apps.md), under it the page of teacher.lua (NEXT / STOP / MIC, the VU bar, the voice).
import AppKit
import WebKit

final class TPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
}

let GREEN = NSColor(srgbRed: 0.247, green: 0.722, blue: 0.384, alpha: 1)
let GREY = NSColor(srgbRed: 0.6, green: 0.62, blue: 0.66, alpha: 1)
let AMBER = NSColor(srgbRed: 0.91, green: 0.64, blue: 0.24, alpha: 1)
let ROWH: CGFloat = 34

final class TopRow: NSView {
    let onB: NSButton, offB: NSButton, topB: NSButton, permB: NSButton, closeB: NSButton
    let label = NSTextField(labelWithString: "")

    static func word(_ title: String, id: String, label: String, color: NSColor, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: color])
        b.setAccessibilityIdentifier(id)
        b.setAccessibilityLabel(label)
        b.setAccessibilityRole(.button)
        b.focusRingType = .none
        return b
    }

    init(panel: Panel, name: String) {
        onB = TopRow.word("ON", id: "on", label: "On", color: GREEN, target: panel, action: #selector(Panel.pressOn))
        offB = TopRow.word("OFF", id: "off", label: "Off", color: GREY, target: panel, action: #selector(Panel.pressOff))
        topB = TopRow.word("TOP", id: "top", label: "Top", color: GREEN, target: panel, action: #selector(Panel.pressTop))
        permB = TopRow.word("PERMISSIONS", id: "permissions", label: "Permissions", color: AMBER, target: panel, action: #selector(Panel.pressPerm))
        closeB = TopRow.word("✕", id: "close", label: "Close", color: GREY, target: panel, action: #selector(Panel.pressClose))
        super.init(frame: .zero)
        label.stringValue = name.uppercased()
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        label.textColor = GREY
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let left = NSStackView(views: [onB, offB])
        left.spacing = 12
        let right = NSStackView(views: [topB, permB, closeB])
        right.spacing = 12
        for v in [left, right, label] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        closeB.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 72),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeB.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            closeB.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
        ])
        let cx = label.centerXAnchor.constraint(equalTo: centerXAnchor)
        cx.priority = .defaultLow
        cx.isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func paintTop(_ on: Bool) {
        topB.attributedTitle = NSAttributedString(string: "TOP", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: on ? GREEN : GREY])
        topB.setAccessibilityValue(on ? "on" : "off")
    }
    func paintPerm(_ missing: Bool) { permB.isHidden = !missing }
}

final class Panel: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    unowned let t: Teacher
    var win: TPanel?
    var web: WKWebView?
    var row: TopRow?
    var ready = false
    var pending: [String: Any] = [:]
    var permTimer: Timer?
    let W: CGFloat = 480
    let H: CGFloat = 240
    var onTop: Bool {
        get { return UserDefaults.standard.object(forKey: "onTop") == nil ? true : UserDefaults.standard.bool(forKey: "onTop") }
        set { UserDefaults.standard.set(newValue, forKey: "onTop") }
    }
    var speed: Double = 1.0

    init(teacher: Teacher) { t = teacher; super.init() }

    var visible: Bool { return win?.isVisible ?? false }

    // MARK: frames. panel.json keeps x,y of the top-left corner, as teacher.lua did.

    func defaultFrame() -> NSRect {
        var scr = NSScreen.main ?? NSScreen.screens[0]
        if let a = AX.runningApp(t.cfg.bundle, t.cfg.app), let w = AX.window(a), let f = AX.frame(w), let s = AX.screen(of: f) { scr = s }
        let v = scr.visibleFrame
        return NSRect(x: v.maxX - W - 14, y: v.minY + 14, width: W, height: H)
    }

    func savedFrame() -> NSRect? {
        guard let p = readJSON(t.panelFile), let x = num(p["x"]), let y = num(p["y"]), let w = num(p["w"]) else { return nil }
        if let sp = num(p["speed"]) { speed = sp }
        let h = CGFloat(num(p["h"]) ?? Double(H))
        let ph = primaryHeight()
        let r = NSRect(x: CGFloat(x), y: ph - CGFloat(y) - h, width: CGFloat(w), height: h)
        for s in NSScreen.screens where s.frame.intersects(r) { return r }
        return nil
    }

    func saveFrame() {
        guard let w = win else { return }
        let f = w.frame
        let top = primaryHeight() - f.maxY
        writeJSON(["x": Double(f.minX), "y": Double(top), "w": Double(f.width), "h": Double(f.height), "speed": speed], t.panelFile)
    }

    // MARK: build

    func build() {
        if win != nil { return }
        let frame = savedFrame() ?? defaultFrame()
        let w = TPanel(contentRect: frame,
                       styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                       backing: .buffered, defer: false)
        w.title = t.cfg.name
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isFloatingPanel = false
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = false
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(srgbRed: 0.059, green: 0.071, blue: 0.09, alpha: 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.minSize = NSSize(width: 440, height: 200)
        w.delegate = self
        w.appearance = NSAppearance(named: .darkAqua)

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "teacher")
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground")

        let r = TopRow(panel: self, name: t.cfg.name)
        let c = NSView()
        r.translatesAutoresizingMaskIntoConstraints = false
        wv.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(r); c.addSubview(wv)
        NSLayoutConstraint.activate([
            r.topAnchor.constraint(equalTo: c.topAnchor),
            r.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            r.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            r.heightAnchor.constraint(equalToConstant: ROWH),
            wv.topAnchor.constraint(equalTo: r.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: c.bottomAnchor),
        ])
        w.contentView = c
        win = w; web = wv; row = r
        r.paintTop(onTop)
        applyLevel()
        refreshPermissions()
        ready = false
        wv.loadHTMLString(PAGE_HTML.replacingOccurrences(of: "@@HEAD@@", with: ""), baseURL: nil)
        permTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermissions() }
    }

    func show() {
        build()
        win?.orderFrontRegardless()
        win?.makeKey()
    }

    func hide() {
        saveFrame()
        win?.orderOut(nil)
        ready = false
        web?.stopLoading()
        permTimer?.invalidate(); permTimer = nil
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "teacher")
        win?.delegate = nil
        win?.close()
        win = nil; web = nil; row = nil
    }

    func applyLevel() { win?.level = onTop ? .screenSaver : .normal }
    func refreshPermissions() { row?.paintPerm(!Permissions.missing.isEmpty) }

    // MARK: first-row buttons

    @objc func pressOn() {}
    @objc func pressOff() { DispatchQueue.main.async { NSApp.terminate(nil) } }
    @objc func pressTop() { onTop.toggle(); row?.paintTop(onTop); applyLevel() }
    @objc func pressPerm() { Permissions.openMissing(); refreshPermissions() }
    @objc func pressClose() { DispatchQueue.main.async { [weak self] in self?.closeByUser() } }

    func closeByUser() {
        hide()
        t.panelClosed()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        DispatchQueue.main.async { [weak self] in self?.closeByUser() }
        return false
    }
    func windowDidMove(_ n: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ n: Notification) { saveFrame() }

    // MARK: the page

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {}

    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let b = m.body as? String else { return }
        if b == "ready" {
            ready = true
            paint([:])
            t.panelReady()
        } else if b == "next" { t.go() }
        else if b == "stop" { t.stop() }
        else if b == "mic" { t.micPress() }
        else if b == "cancel" { t.micCancel() }
        else if b.hasPrefix("voice:") { t.voice = String(b.dropFirst(6)); t.writeState() }
        else if b.hasPrefix("size:") { if let n = Double(b.dropFirst(5)) { fit(CGFloat(n)) } }
        else if b.hasPrefix("speed:") { speed = Double(b.dropFirst(6)) ?? 1.0; saveFrame() }
    }

    func js(_ code: String) {
        if ready { web?.evaluateJavaScript(code, completionHandler: nil) }
    }

    func paint(_ o: [String: Any]) {
        for (k, v) in o { t.view[k] = v }
        var v = t.view
        v["speed"] = speed
        js("set(" + jsonString(v) + ")")
    }

    func level(_ v: Double) { js(String(format: "lvl(%.3f)", v)) }
    func hush() { js("hush()") }
    func clearSpoken() { js("document.getElementById('spoken').textContent = ''") }

    func speak(_ text: String, _ where_: String) -> Bool {
        guard win != nil, ready else { return false }
        js("speak(" + jsonString(text) + ", " + jsonString(where_) + ")")
        return true
    }

    /// grow or shrink to the height the page asks for, the top edge staying where it is, never taller than the screen
    func fit(_ need: CGFloat) {
        guard let w = win else { return }
        let f = w.frame
        let scr = (w.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let h = max(200, min(need + ROWH + 4, scr.height - 40))
        if abs(h - f.height) < 4 { return }
        var y = f.maxY - h
        if y < scr.minY + 10 { y = scr.minY + 10 }
        w.setFrame(NSRect(x: f.minX, y: y, width: f.width, height: h), display: true)
    }
}
