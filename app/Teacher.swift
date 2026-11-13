// Teacher.swift: the state machine of teacher.lua. Claude proposes ONE step (through the door, teacher.py);
// the panel shows it with NEXT; nothing happens until Marko presses NEXT; then the step is performed at human
// speed on the real window and the app is photographed for Claude. Same state files and inbox as before.
import AppKit
import AVFoundation
import ImageIO

final class Teacher {
    let cfg: Cfg
    var on = false
    var n = 0
    var step: [String: Any]? = nil
    var status = "idle"          // idle | proposed | doing | done | stopped
    var error: String? = nil
    var voice: String? = nil
    var view: [String: Any] = ["say": "", "status": "", "count": "", "nextOn": false, "hint": ""]
    var gen = 0
    var glideTimers: [Timer] = []
    var mic = "idle"             // idle | listening | thinking
    var rec: Process? = nil
    lazy var panel: Panel = Panel(teacher: self)

    var dir: String { return cfg.dir }
    var stateFile: String { return dir + "/state.json" }
    var stepFile: String { return dir + "/step.json" }
    var logFile: String { return dir + "/steps.jsonl" }
    var panelFile: String { return dir + "/panel.json" }
    var inbox: String { return dir + "/inbox" }
    var wav: String { return dir + "/mic.wav" }
    var snapDir: String { return dir + "/snaps" }
    var lastSnapFile: String { return dir + "/lastsnap.json" }
    let maxSec = 90

    init(cfg: Cfg) { self.cfg = cfg }

    var python: String {
        let p = HOME + "/.pyenv/versions/3.10.14/bin/python3"
        return FileManager.default.isExecutableFile(atPath: p) ? p : "/usr/bin/python3"
    }
    var teacherPy: String {
        let a = HOME + "/Developer/ABLETON_TEACHER/teacher.py"
        return FileManager.default.fileExists(atPath: a) ? a : HOME + "/Developer/teacher/teacher.py"
    }

    // MARK: small helpers

    func mkdirs() {
        let fm = FileManager.default
        for d in [dir, inbox, snapDir] { try? fm.createDirectory(atPath: d, withIntermediateDirectories: true) }
    }

    func after(_ secs: Double, _ fn: @escaping () -> Void) {
        let g = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in
            guard let self = self, self.gen == g else { return }
            fn()
        }
    }

    func cancelTimers() {
        gen += 1
        for t in glideTimers { t.invalidate() }
        glideTimers = []
    }

    func runningApp() -> NSRunningApplication? { return AX.runningApp(cfg.bundle, cfg.app) }
    func appWindow() -> AXUIElement? { guard let a = runningApp() else { return nil }; return AX.window(a) }
    func windowFrame() -> CGRect? { guard let w = appWindow() else { return nil }; return AX.frame(w) }

    func stateDict() -> [String: Any] {
        var d: [String: Any] = ["n": n, "status": status, "at": Int(Date().timeIntervalSince1970), "on": on,
                                "voiceAt": ProcessInfo.processInfo.systemUptime]
        if let s = step { d["step"] = s }
        if let e = error { d["error"] = e }
        if let v = voice { d["voice"] = v }
        return d
    }

    func writeState() {
        mkdirs()
        writeJSON(stateDict(), stateFile)
    }

    func log(_ st: String) {
        mkdirs()
        var d: [String: Any] = ["n": n, "status": st, "at": Int(Date().timeIntervalSince1970)]
        if let s = step { d["step"] = s }
        guard let line = String(data: jsonData(d), encoding: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: logFile) {
            h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
        } else {
            try? (line + "\n").write(toFile: logFile, atomically: true, encoding: .utf8)
        }
    }

    func paint(_ o: [String: Any]) { panel.paint(o) }

    // MARK: the switch

    /// at launch: remember the last step, so a closed and reopened window continues
    func begin() {
        mkdirs()
        if let last = readJSON(stateFile), let ln = last["n"] {
            n = Int(num(ln) ?? 0)
            step = last["step"] as? [String: Any]
            let st = last["status"] as? String ?? "idle"
            status = (st == "proposed" || st == "doing") ? "stopped" : st
        }
        on = false
        writeState()
    }

    func start() {
        if on && panel.visible { return }
        mkdirs()
        if let saved = readJSON(panelFile), let sp = num(saved["speed"]) { view["speed"] = sp; panel.speed = sp }
        on = true
        if let s = step {
            let say = (s["say"] as? String) ?? (s["kind"] as? String) ?? ""
            view = ["say": "Last step \(n) (\(status)): \(say)", "status": "waiting for Claude", "nextOn": false,
                    "count": "step \(n)", "hint": "Press MIC and tell me what to do.", "mic": "idle", "stopped": false]
        } else {
            view = ["say": "Press MIC and tell me what you want to do in \(cfg.what).", "status": "", "nextOn": false,
                    "count": "", "hint": "", "mic": "idle", "stopped": false]
        }
        panel.show()
        writeState()
    }

    /// the red button or ✕: the window goes, the app stays ON
    func panelClosed() { goOff() }

    func goOff() {
        cancelTimers()
        stopRecorder()
        mic = "idle"
        on = false
        if status == "proposed" || status == "doing" { status = "stopped" }
        writeState()
    }

    func closePanel() {
        panel.hide()
        goOff()
    }

    func shutdown() {
        panel.hide()
        goOff()
    }

    func panelReady() {}

    // MARK: propose / go / stop

    func propose(_ st: [String: Any]) -> Int {
        if !on || !panel.visible { start() }
        cancelTimers()
        n += 1
        step = st
        error = nil
        status = "proposed"
        let say = (st["say"] as? String) ?? (st["kind"] as? String) ?? "?"
        paint(["say": "NEXT: " + say, "status": "click NEXT when ready", "nextOn": true, "count": "step \(n)",
               "hint": "", "stopped": false, "reply": false])
        panel.clearSpoken()
        writeState()
        log("proposed")
        return n
    }

    func proposeFile() -> (Int?, String?) {
        guard let s = readJSON(stepFile) else { return (nil, "no step.json") }
        return (propose(s), nil)
    }

    func go() {
        guard status == "proposed", let s = step else { return }
        status = "doing"
        paint(["status": "doing …", "nextOn": false])
        writeState()
        let kind = (s["kind"] as? String) ?? "none"
        let known = ["none", "claude", "wait", "keys", "type", "menu", "point", "click", "drag", "scroll", "window"]
        if !known.contains(kind) {
            status = "done"; error = "unknown kind \(kind)"
            paint(["status": "unknown step kind"]); writeState(); log("error"); return
        }
        let finish: (String?) -> Void = { [weak self] err in
            guard let self = self else { return }
            if self.status == "stopped" { return }
            self.status = "done"
            self.error = err
            self.paint(["status": err != nil ? "problem: \(err!)" : "done · photographing \(self.cfg.what) for Claude …"])
            self.writeState()
            self.log(err != nil ? "error" : "done")
            let n0 = self.n
            self.after(0.8) {
                var note: [String: Any] = ["kind": "step", "n": n0, "status": err != nil ? "error" : "done"]
                if let say = s["say"] { note["say"] = say }
                if let e = err { note["error"] = e }
                self.autoSnap("step\(n0)", note) { _ in
                    if self.n == n0 && self.status == "done" {
                        self.paint(["status": err != nil ? "problem: \(err!)" : "done · Claude has the picture"])
                    }
                }
            }
        }
        let run: () -> Void = { [weak self] in self?.perform(kind, s, finish) }
        // the app in front for anything that presses or clicks
        if kind != "none" && kind != "wait" && kind != "claude" && (s["app"] as? Bool) != false {
            if let a = runningApp() { a.activate(options: [.activateIgnoringOtherApps]) }
            after(0.5, run)
        } else {
            run()
        }
    }

    func stop() {
        cancelTimers()
        panel.hush()
        status = "stopped"
        paint(["say": "STOPPED. Tell me what to do instead, with MIC.", "status": "stopped", "nextOn": false, "stopped": true])
        writeState()
        log("stopped")
    }

    func reply(_ text: String) {
        if !on || !panel.visible { start() }
        if status == "proposed" { paint(["hint": text]); return }
        paint(["say": text, "status": "", "nextOn": false, "stopped": false, "reply": true])
    }

    func hint(_ text: String) { paint(["hint": text]) }

    func speak(_ text: String, _ where_: String) -> Bool {
        if !panel.visible { return false }
        voice = "asked"
        writeState()
        return panel.speak(text, where_)
    }

    // MARK: mouse at human speed

    func glide(_ to: CGPoint, secs: Double? = nil, dragging: Bool = false, _ cb: @escaping () -> Void) {
        let from = Mouse.location()
        let dist = hypot(to.x - from.x, to.y - from.y)
        let dur = secs ?? max(0.6, min(1.8, dist / 700))
        let t0 = Date()
        let g = gen
        let tm = Timer(timeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self, self.gen == g else { timer.invalidate(); return }
            let p = min(1.0, Date().timeIntervalSince(t0) / dur)
            let e = p < 0.5 ? 2 * p * p : -1 + (4 - 2 * p) * p
            Mouse.move(CGPoint(x: from.x + (to.x - from.x) * CGFloat(e), y: from.y + (to.y - from.y) * CGFloat(e)), dragging: dragging)
            if p >= 1 { timer.invalidate(); cb() }
        }
        RunLoop.main.add(tm, forMode: .common)
        glideTimers.append(tm)
    }

    /// where a step points: absolute {x,y} or window-relative {wx,wy}
    func target(_ s: [String: Any], _ key: String? = nil) -> CGPoint? {
        let t: [String: Any]
        if let k = key { guard let sub = s[k] as? [String: Any] else { return nil }; t = sub } else { t = s }
        if let x = num(t["x"]), let y = num(t["y"]) { return CGPoint(x: x, y: y) }
        if t["wx"] == nil && t["wy"] == nil { return nil }
        guard let f = windowFrame() else { return nil }
        return CGPoint(x: f.minX + CGFloat(num(t["wx"]) ?? 0), y: f.minY + CGFloat(num(t["wy"]) ?? 0))
    }

    // MARK: the actions (ACT in teacher.lua)

    func perform(_ kind: String, _ s: [String: Any], _ done: @escaping (String?) -> Void) {
        switch kind {
        case "none": done(nil)
        case "claude": after(0.2) { done(nil) }
        case "wait": after(num(s["secs"]) ?? 1) { done(nil) }
        case "keys":
            var list: [String] = []
            if let l = s["keys"] as? [String] { list = l } else if let k = s["keys"] as? String { list = [k] }
            let gap = num(s["gap"]) ?? 0.7
            var i = 0
            func nextKey() {
                if i >= list.count { after(0.3) { done(nil) }; return }
                Keys.post(list[i])
                i += 1
                after(gap) { nextKey() }
            }
            after(0.3) { nextKey() }
        case "type":
            let chars = Array(String((s["text"] as? String) ?? ""))
            let gap = num(s["gap"]) ?? 0.08
            let enter = (s["enter"] as? Bool) ?? false
            var i = 0
            func nextChar() {
                if i >= chars.count {
                    if enter {
                        after(0.4) { Keys.post("return", hold: 0.1); self.after(0.3) { done(nil) } }
                    } else { after(0.3) { done(nil) } }
                    return
                }
                Keys.typeChar(chars[i])
                i += 1
                after(gap) { nextChar() }
            }
            after(0.3) { nextChar() }
        case "menu":
            guard let a = runningApp() else { return done("\(cfg.what) is not running") }
            let path = (s["path"] as? [String]) ?? []
            let ok = AX.pressMenu(a, path)
            after(0.8) { done(ok ? nil : "menu item not found: " + path.joined(separator: " > ")) }
        case "point":
            guard let p = target(s) else { return done("no target") }
            glide(p) { Ring.show(at: p); self.after(num(s["hold"]) ?? 1.5) { done(nil) } }
        case "click":
            guard let p = target(s) else { return done("no target") }
            let right = (s["button"] as? String) == "right"
            let count = ((s["double"] as? Bool) ?? false) ? 2 : 1
            let mods = (s["mods"] as? [String]) ?? []
            glide(p) {
                Ring.show(at: p)
                self.after(0.4) {
                    Mouse.click(p, right: right, count: count, mods: mods)
                    self.after(0.5) { done(nil) }
                }
            }
        case "drag":
            guard let a = target(s, "from"), let b = target(s, "to") else { return done("no target") }
            glide(a) {
                Ring.show(at: a)
                self.after(0.35) {
                    Mouse.button(a, down: true)
                    self.after(0.3) {
                        let dist = hypot(b.x - a.x, b.y - a.y)
                        self.glide(b, secs: max(1.0, min(2.5, Double(dist) / 400)), dragging: true) {
                            self.after(0.2) {
                                Mouse.button(b, down: false)
                                Ring.show(at: b)
                                self.after(0.5) { done(nil) }
                            }
                        }
                    }
                }
            }
        case "scroll":
            let dx = Int(num(s["dx"]) ?? 0), dy = Int(num(s["dy"]) ?? 0)
            let go: () -> Void = { Mouse.scroll(dx: dx, dy: dy); self.after(0.5) { done(nil) } }
            if let p = target(s) { glide(p, go) } else { go() }
        case "window":
            performWindow(s, done)
        default:
            done("unknown kind \(kind)")
        }
    }

    /// move the app to a screen and/or maximize it, exact, through Accessibility (no mouse)
    func performWindow(_ s: [String: Any], _ done: @escaping (String?) -> Void) {
        guard let a = runningApp(), let w = AX.window(a), let f = AX.frame(w) else { return done("\(cfg.what) window not found") }
        let ph = primaryHeight()
        var scr: NSScreen? = nil
        if let name = s["screen"] as? String {
            scr = NSScreen.screens.first { $0.localizedName.lowercased().contains(name.lowercased()) }
            if scr == nil { return done("no screen called \(name)") }
        }
        let maximize = (s["maximize"] as? Bool) ?? ((num(s["maximize"]) ?? 0) != 0)
        if scr != nil || maximize {
            let sc = scr ?? AX.screen(of: f) ?? NSScreen.main!
            let v = sc.visibleFrame
            let topY = ph - v.maxY
            var r = f
            if maximize {
                r = CGRect(x: v.minX, y: topY, width: v.width, height: v.height)
            } else {
                r.size.width = min(f.width, v.width); r.size.height = min(f.height, v.height)
                r.origin.x = v.minX + (v.width - r.width) / 2
                r.origin.y = topY + (v.height - r.height) / 2
            }
            AX.setFrame(w, r)
        }
        after(0.8) {
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            a.activate(options: [.activateIgnoringOtherApps])
            self.after(0.9) { done(nil) }
        }
    }

    // MARK: the inbox and the eyes

    func inboxWrite(_ note: [String: Any]) {
        mkdirs()
        var nn = note
        nn["at"] = Int(Date().timeIntervalSince1970)
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        writeJSON(nn, "\(inbox)/\(ms).json")
    }

    static func run(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
    }

    /// the taught app's window as a PNG (screencapture -l, no shadow) and its frame; callable off the main thread
    func capture(_ path: String) -> [String: Any]? {
        guard let a = runningApp(), let w = AX.window(a), let f = AX.frame(w), let id = AX.windowID(w) else { return nil }
        _ = Teacher.run("/usr/sbin/screencapture", ["-x", "-o", "-l", String(id), path])
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return ["x": Double(f.minX), "y": Double(f.minY), "w": Double(f.width), "h": Double(f.height),
                "screen": AX.screen(of: f)?.localizedName ?? "?", "path": path]
    }

    static func pixels(_ path: String) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (0, 0) }
        return (Int(num(p[kCGImagePropertyPixelWidth]) ?? 0), Int(num(p[kCGImagePropertyPixelHeight]) ?? 0))
    }

    /// photograph the app, shrink to 1600 px, record lastsnap.json exactly as teacher.py does, put the note in the inbox
    func autoSnap(_ label: String, _ note: [String: Any], _ cb: ((String?) -> Void)?) {
        mkdirs()
        let stamp = Int(Date().timeIntervalSince1970)
        let full = "\(snapDir)/\(stamp)_\(label)_full.png"
        let small = "\(snapDir)/\(stamp)_\(label).png"
        DispatchQueue.global().async {
            guard let frame = self.capture(full) else {
                DispatchQueue.main.async { self.inboxWrite(note); cb?(nil) }
                return
            }
            _ = Teacher.run("/usr/bin/sips", ["-Z", "1600", full, "--out", small])
            let (iw, ih) = Teacher.pixels(small)
            try? FileManager.default.removeItem(atPath: full)
            let fw = num(frame["w"]) ?? 1
            let meta: [String: Any] = ["frame": frame, "img_w": iw, "img_h": ih, "small": small, "full": full,
                                       "scale": iw > 0 ? fw / Double(iw) : 1.0]
            DispatchQueue.main.async {
                writeJSON(meta, self.lastSnapFile)
                var nn = note
                nn["snap"] = small
                nn["window"] = "\(Int(fw))x\(Int(num(frame["h"]) ?? 0)) on \(frame["screen"] as? String ?? "?"), image \(iw)x\(ih)"
                self.inboxWrite(nn)
                cb?(small)
            }
        }
    }

    // MARK: the microphone

    func heard(_ text: String?, _ err: String?) {
        mic = "idle"
        if let e = err { paint(["mic": "idle", "status": "mic: " + e]); return }
        let t = text ?? ""
        paint(["mic": "idle", "hint": "You said: " + t, "status": "sent to Claude, with a picture of \(cfg.what) …"])
        autoSnap("mic", ["kind": "mic", "text": t], nil)
    }

    func stopRecorder() {
        if let r = rec, r.isRunning { r.interrupt() }   // SIGINT: ffmpeg closes the wav
        rec = nil
    }

    func stopListening() {
        let r = rec
        rec = nil
        mic = "thinking"
        paint(["mic": "thinking", "status": "listening done, writing it down …"])
        if let r = r, r.isRunning { r.interrupt() }
        after(0.4) {
            let wavPath = self.wav
            DispatchQueue.global().async {
                let (rc, out0) = Teacher.run(self.python, [self.teacherPy, "transcribe", wavPath])
                let out = out0.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    if rc != 0 || out.isEmpty || out.hasPrefix("ERROR") {
                        self.heard(nil, String((out.isEmpty ? "transcription failed" : out).prefix(120)))
                    } else { self.heard(out, nil) }
                }
            }
        }
    }

    func levelFrom(_ chunk: String) {
        var last: Double? = nil
        for part in chunk.components(separatedBy: "RMS_level=").dropFirst() {
            let tok = part.prefix { "-0123456789.inf".contains($0) }
            if tok.hasPrefix("-inf") { last = -120 } else if let d = Double(tok) { last = d }
        }
        guard let db = last else { return }
        let v = max(0, min(1, (db + 60) / 50))
        DispatchQueue.main.async { self.panel.level(v) }
    }

    func startListening() {
        try? FileManager.default.removeItem(atPath: wav)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        p.arguments = ["-hide_banner", "-loglevel", "error",
                       "-f", "avfoundation", "-i", ":default", "-t", String(maxSec),
                       "-filter_complex",
                       "[0:a]aformat=channel_layouts=mono:sample_rates=16000,asplit=2[a][b];"
                       + "[b]asetnsamples=1600,astats=metadata=1:reset=1:measure_perchannel=none:measure_overall=RMS_level,"
                       + "ametadata=mode=print:key=lavfi.astats.Overall.RMS_level:file=-:direct=1[m]",
                       "-map", "[a]", "-y", wav,
                       "-map", "[m]", "-f", "null", "/dev/null"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            if let s = String(data: d, encoding: .utf8) { self?.levelFrom(s) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { if self?.mic == "listening" { self?.stopListening() } }   // the time cap
        }
        do {
            try p.run()
            rec = p
            mic = "listening"
            paint(["mic": "listening", "status": "listening … press MIC again when you are done"])
        } catch {
            rec = nil
            paint(["status": "the microphone did not open"])
        }
    }

    func micPress() {
        if mic == "listening" { stopListening() } else if mic == "idle" { startListening() }
    }

    /// throw the recording away: nothing written down, nothing sent (the CANCEL button, C, or Escape)
    func micCancel() {
        if mic != "listening" { return }
        let r = rec
        rec = nil
        mic = "idle"
        if let r = r, r.isRunning { r.terminate() }
        try? FileManager.default.removeItem(atPath: wav)
        paint(["mic": "idle", "status": "cancelled, nothing sent"])
    }
}
