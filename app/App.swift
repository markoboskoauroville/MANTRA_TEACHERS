// App.swift: the Teachers as one Swift app (Marko, 13.11.2026: "convert anything that is still on Hammer Spoon
// to Swift right now"). One source, two bundles: Ableton Teacher (Mantra) and DaVinci Teacher (Mantra); the
// bundle's Info.plist key TeacherKey (or --teacher <key>) says which. teacher.lua is in old/.
import AppKit
import ApplicationServices
import AVFoundation

let VERSION = 1

struct Cfg {
    let key: String
    let name: String
    let app: String
    let bundle: String
    let what: String
    let dir: String
    let portName: String
    let usualPort: Int
}

let HOME = NSHomeDirectory()

func makeCfg(_ key: String) -> Cfg {
    switch key {
    case "davinci":
        return Cfg(key: "davinci", name: "DaVinci Teacher (Mantra)", app: "DaVinci Resolve",
                   bundle: "com.blackmagic-design.DaVinciResolve", what: "Resolve",
                   dir: HOME + "/.davinci_teacher", portName: "davinci-teacher", usualPort: 8971)
    case "universal":
        return Cfg(key: "universal", name: "Universal Teacher (Mantra)", app: "Google Chrome",
                   bundle: "com.google.Chrome", what: "the browser",
                   dir: HOME + "/.universal_teacher", portName: "universal-teacher", usualPort: 8972)
    default:
        return Cfg(key: "ableton", name: "Ableton Teacher (Mantra)", app: "Live",
                   bundle: "com.ableton.live", what: "Live",
                   dir: HOME + "/.ableton_teacher", portName: "ableton-teacher", usualPort: 8970)
    }
}

func chooseKey() -> String {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: "--teacher"), i + 1 < a.count { return a[i + 1] }
    if let k = Bundle.main.object(forInfoDictionaryKey: "TeacherKey") as? String { return k }
    return "ableton"
}

func jsonData(_ o: Any) -> Data {
    return (try? JSONSerialization.data(withJSONObject: o, options: [.fragmentsAllowed, .sortedKeys])) ?? Data("{}".utf8)
}
func jsonString(_ o: Any) -> String { return String(data: jsonData(o), encoding: .utf8) ?? "{}" }
func readJSON(_ path: String) -> [String: Any]? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}
func writeJSON(_ o: Any, _ path: String) {
    try? jsonData(o).write(to: URL(fileURLWithPath: path), options: .atomic)
}
func num(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}

enum Permissions {
    static let needed = ["Accessibility", "ScreenCapture", "Microphone"]
    static func allowed(_ p: String) -> Bool {
        switch p {
        case "Accessibility": return AXIsProcessTrusted()
        case "ScreenCapture": return CGPreflightScreenCaptureAccess()
        case "Microphone": return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        default: return true
        }
    }
    static var missing: [String] { return needed.filter { !allowed($0) } }
    static func openMissing() {
        guard let p = missing.first else { return }
        switch p {
        case "Accessibility": _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        case "ScreenCapture": _ = CGRequestScreenCaptureAccess()
        case "Microphone": AVCaptureDevice.requestAccess(for: .audio) { _ in }
        default: break
        }
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + p) { NSWorkspace.shared.open(u) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var teacher: Teacher!
    var door: Door!
    let login = CommandLine.arguments.contains("--login")

    func applicationDidFinishLaunching(_ n: Notification) {
        let cfg = makeCfg(chooseKey())
        teacher = Teacher(cfg: cfg)
        door = Door(teacher: teacher)
        door.start()
        teacher.begin()
        if !login { teacher.start() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { return false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool {
        teacher.start()
        return true
    }
    func applicationWillTerminate(_ n: Notification) {
        teacher.shutdown()
        door.stop()
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
