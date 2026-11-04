import AppKit
import ApplicationServices
import CoreGraphics

/// Synthesised keyboard and media-key events. Posting requires the Accessibility permission.
enum KeySender {
    /// When non-zero, stamped into every synthesised event (tests use it to recognise and swallow them).
    nonisolated(unsafe) static var eventMarker: Int64 = 0

    enum Key: CGKeyCode {
        case leftArrow = 123, rightArrow = 124, n = 45, v = 9, o = 31, e = 14
    }

    static func press(_ key: Key, flags: CGEventFlags) {
        var flags = flags
        if key == .leftArrow || key == .rightArrow { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: src, virtualKey: key.rawValue, keyDown: down) else { continue }
            ev.flags = flags
            if eventMarker != 0 { ev.setIntegerValueField(.eventSourceUserData, value: eventMarker) }
            ev.post(tap: .cghidEventTap)
        }
    }

    /// NX_KEYTYPE_* codes from IOKit's ev_keymap.h.
    enum MediaKey: Int { case volumeUp = 0, volumeDown = 1, mute = 7, play = 16, next = 17, previous = 18 }

    /// Media keys are NSSystemDefined events (subtype 8) carrying NX_KEYTYPE_* in data1.
    static func media(_ key: MediaKey) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                        timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                        data1: (key.rawValue << 16) | (state << 8), data2: -1)
            guard let cg = ev?.cgEvent else { continue }
            if eventMarker != 0 { cg.setIntegerValueField(.eventSourceUserData, value: eventMarker) }
            cg.post(tap: .cghidEventTap)
        }
    }
}

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    @MainActor private static var prompted = false

    /// Shows the system Accessibility prompt at most once per launch (later failures just report).
    @MainActor static func requestAccessibilityOnce() {
        guard !prompted else { return }
        prompted = true
        requestAccessibility()
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
enum ActionRunner {
    /// Runs a zone's action. Returns an error message for the UI if it could not run.
    @discardableResult
    static func perform(_ action: ZoneAction, guardController: PrivacyGuard) -> String? {
        if action.kind.needsAccessibility && !Permissions.accessibility {
            Permissions.requestAccessibilityOnce()
            return "LidTap needs Accessibility permission to do this."
        }
        switch action.kind {
        case .none:
            return nil
        case .desktopLeft:
            KeySender.press(.leftArrow, flags: .maskControl)
        case .desktopRight:
            KeySender.press(.rightArrow, flags: .maskControl)
        case .playPause:
            KeySender.media(.play)
        case .nextTrack:
            KeySender.media(.next)
        case .previousTrack:
            KeySender.media(.previous)
        case .volumeUp:
            KeySender.media(.volumeUp)
        case .volumeDown:
            KeySender.media(.volumeDown)
        case .mute:
            KeySender.media(.mute)
        case .newNote:
            openApp(bundleID: "com.apple.Notes") { app in
                waitUntilFrontmost(app.bundleIdentifier) { KeySender.press(.n, flags: .maskCommand) }
            }
        case .openApp:
            guard let id = action.appBundleID else { return "Choose an app for this zone in Settings." }
            openApp(bundleID: id, then: nil)
        case .runShortcut:
            guard let name = action.shortcutName else { return "Choose a shortcut for this zone in Settings." }
            Shortcuts.run(name)
        case .privacyGuard:
            guardController.toggle()
        }
        return nil
    }

    /// Launches the app, or brings it forward (and reopens a window) if it is already running.
    static func openApp(bundleID: String, then: ((NSRunningApplication) -> Void)?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.unhide()
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            guard let app, let then else { return }
            DispatchQueue.main.async { then(app) }
        }
    }

    /// Polls until the app is frontmost (up to ~3 s), then runs `body`.
    static func waitUntilFrontmost(_ bundleID: String?, attempts: Int = 30, _ body: @escaping @Sendable () -> Void) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: body)
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { waitUntilFrontmost(bundleID, attempts: attempts - 1, body) }
        }
    }
}

struct AppInfo: Identifiable, Hashable {
    let name: String
    let bundleID: String
    let url: URL
    var isRunning: Bool
    var id: String { bundleID }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

enum AppCatalog {
    /// Running regular apps first, then everything installed in the usual Applications folders.
    static func load() -> [AppInfo] {
        var seen = Set<String>()
        var out: [AppInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, let url = app.bundleURL, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { continue }
            out.append(AppInfo(name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, bundleID: id, url: url, isRunning: true))
        }
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        var installed: [AppInfo] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
                guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { continue }
                installed.append(AppInfo(name: fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                                         bundleID: id, url: url, isRunning: false))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            + installed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// The user's Shortcuts, through the `shortcuts` command-line tool that ships with macOS.
enum Shortcuts {
    static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// Starts the shortcut and returns at once; failures are logged (a shortcut can run for a long time).
    static func run(_ name: String) {
        let p = Process()
        p.executableURL = tool
        p.arguments = ["run", name]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        p.standardError = err
        p.terminationHandler = { proc in
            guard proc.terminationStatus != 0 else { return }
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Log.action.error("Shortcut \(name, privacy: .public) failed (\(proc.terminationStatus)): \(msg, privacy: .public)")
        }
        do { try p.run() } catch {
            Log.action.error("Could not run shortcut \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Names of every shortcut, in the order the Shortcuts app shows them. Blocks briefly: call off the main thread.
    static func list() -> [String] {
        let p = Process()
        p.executableURL = tool
        p.arguments = ["list"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }
}
