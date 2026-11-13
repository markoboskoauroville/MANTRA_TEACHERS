// Door.swift: the tiny localhost HTTP door teacher.py talks to, instead of `hs -c`. 127.0.0.1 only, one port per
// teacher, claimed in ~/.config/mantra-ports.json like the other Mantra apps (usual 8970 Ableton, 8971 DaVinci,
// the next sixteen if taken). There is NO verb that presses NEXT: only Marko's click approves a step.
//
//   GET  /health   GET /state
//   POST /up  /down  /quit
//   POST /propose  (body: the step as JSON; empty body reads step.json)   -> {"n":N}
//   POST /reply {"text"}   POST /hint {"text"}   POST /speak {"text","where"}   -> {"ok":bool}
//   POST /snap {"path"}    -> the window's frame, and the PNG saved there
import Foundation
import Darwin
import AppKit

final class Door {
    unowned let t: Teacher
    var fd: Int32 = -1
    var port = 0

    init(teacher: Teacher) { t = teacher }

    func start() {
        let usual = t.cfg.usualPort
        for p in usual...(usual + 15) {
            let s = socket(AF_INET, SOCK_STREAM, 0)
            if s < 0 { continue }
            var yes: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(p).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            let r = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if r == 0 && listen(s, 16) == 0 { fd = s; port = p; break }
            close(s)
        }
        if fd < 0 { return }
        claim()
        let listener = fd
        DispatchQueue.global().async { [weak self] in
            while true {
                let c = accept(listener, nil, nil)
                if c < 0 { return }
                DispatchQueue.global().async { self?.serve(c) }
            }
        }
    }

    func stop() {
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); fd = -1 }
        unclaim()
    }

    // MARK: the registry ~/.config/mantra-ports.json

    var registry: String { return HOME + "/.config/mantra-ports.json" }

    func claim() {
        var d = readJSON(registry) ?? [:]
        d[t.cfg.portName] = ["at": Int(Date().timeIntervalSince1970), "health": "/health", "pid": Int(getpid()),
                             "port": port, "proto": "tcp", "url": "http://127.0.0.1:\(port)", "wanted": t.cfg.usualPort]
        writeJSON(d, registry)
    }

    func unclaim() {
        guard var d = readJSON(registry) else { return }
        if let me = d[t.cfg.portName] as? [String: Any], (me["pid"] as? Int) == Int(getpid()) {
            d.removeValue(forKey: t.cfg.portName)
            writeJSON(d, registry)
        }
    }

    // MARK: serving

    func serve(_ c: Int32) {
        defer { close(c) }
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        var headEnd: Range<Data.Index>? = nil
        var want = 0
        while true {
            let n = recv(c, &chunk, chunk.count, 0)
            if n <= 0 { break }
            buf.append(contentsOf: chunk[0..<n])
            if headEnd == nil, let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                headEnd = r
                let head = String(data: buf[0..<r.lowerBound], encoding: .utf8) ?? ""
                for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
                    want = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
            if let r = headEnd, buf.count - r.upperBound >= want { break }
            if buf.count > 4_000_000 { break }
        }
        guard let he = headEnd else { return }
        let head = String(data: buf[0..<he.lowerBound], encoding: .utf8) ?? ""
        let first = head.components(separatedBy: "\r\n").first ?? ""
        let parts = first.split(separator: " ")
        if parts.count < 2 { return }
        let method = String(parts[0])
        let path = String(parts[1]).components(separatedBy: "?")[0]
        let body = Data(buf[he.upperBound...])
        let (code, out) = handle(method, path, body)
        let payload = jsonData(out)
        let resp = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var data = Data(resp.utf8)
        data.append(payload)
        data.withUnsafeBytes { raw in
            var off = 0
            while off < data.count {
                let w = send(c, raw.baseAddress!.advanced(by: off), data.count - off, 0)
                if w <= 0 { break }
                off += w
            }
        }
    }

    func onMain<T>(_ f: () -> T) -> T {
        if Thread.isMainThread { return f() }
        return DispatchQueue.main.sync { f() }
    }

    func handle(_ method: String, _ path: String, _ body: Data) -> (Int, Any) {
        let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        switch (method, path) {
        case ("GET", "/health"):
            return (200, ["ok": true, "teacher": t.cfg.key, "version": VERSION, "port": port])
        case ("GET", "/state"):
            return (200, onMain { t.stateDict() })
        case ("POST", "/up"):
            onMain { t.start() }
            return (200, ["ok": true])
        case ("POST", "/down"):
            onMain { t.closePanel() }
            return (200, ["ok": true])
        case ("POST", "/quit"):
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return (200, ["ok": true])
        case ("POST", "/propose"):
            let r: (Int?, String?) = onMain {
                if j.isEmpty { return t.proposeFile() }
                return (t.propose(j), nil)
            }
            if let n = r.0 { return (200, ["n": n]) }
            return (400, ["error": r.1 ?? "failed"])
        case ("POST", "/reply"):
            let text = (j["text"] as? String) ?? ""
            onMain { t.reply(text) }
            return (200, ["ok": true])
        case ("POST", "/hint"):
            let text = (j["text"] as? String) ?? ""
            onMain { t.hint(text) }
            return (200, ["ok": true])
        case ("POST", "/speak"):
            let text = (j["text"] as? String) ?? ""
            let where_ = (j["where"] as? String) ?? "spoken"
            let ok = onMain { t.speak(text, where_) }
            return (200, ["ok": ok])
        case ("POST", "/snap"):
            guard let p = j["path"] as? String else { return (400, ["error": "no path"]) }
            if let f = t.capture(p) { return (200, f) }
            return (200, ["error": "\(t.cfg.what) window not found, or no Screen Recording permission"])
        default:
            return (404, ["error": "no such door"])
        }
    }
}
