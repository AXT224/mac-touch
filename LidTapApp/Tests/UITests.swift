import AppKit
import SwiftUI

/// True if the PNG has real content (not a single flat colour).
func hasContent(_ url: URL?) -> Bool {
    guard let url, let img = NSImage(contentsOf: url), let rep = img.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: img.tiffRepresentation ?? Data()) else { return false }
    var seen = Set<UInt32>()
    let stepX = max(rep.pixelsWide / 40, 1), stepY = max(rep.pixelsHigh / 40, 1)
    for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            seen.insert(UInt32(c.redComponent * 31) << 10 | UInt32(c.greenComponent * 31) << 5 | UInt32(c.blueComponent * 31))
        }
    }
    return seen.count > 3
}

@MainActor
func uiTests() {
    T.suite = "UI"
    print("\n▶ UI snapshots (rendered offscreen into test-artifacts/)")
    let h = AppHarness(name: "ui")
    guard h.train() else { return T.fail("no model for UI tests") }
    h.tap("z1")
    h.tap("z2", gated: "typing")

    func shot<V: View>(_ name: String, _ size: CGSize, dark: Bool = true, _ view: V) {
        T.run(name) {
            let url = snapshot(view, size: size, name: name.replacingOccurrences(of: " ", with: "_"), dark: dark)
            T.expect(url != nil && (name.contains("secondary") || hasContent(url)), "\(name) rendered blank")
        }
    }

    shot("menu panel trained", CGSize(width: 300, height: 400), MenuPanel().environment(h.app))
    shot("menu panel light mode", CGSize(width: 300, height: 400), dark: false, MenuPanel().environment(h.app))
    let fresh = AppHarness(name: "ui-untrained", dataset: nil)
    shot("menu panel untrained", CGSize(width: 300, height: 400), MenuPanel().environment(fresh.app))

    for pane in SettingsPane.allCases {
        UserDefaults.standard.set(pane.rawValue, forKey: "settingsPane")
        shot("settings \(pane.rawValue)", CGSize(width: 980, height: 700), SettingsView().environment(h.app))
    }
    UserDefaults.standard.set("zones", forKey: "settingsPane")
    shot("settings zones light mode", CGSize(width: 980, height: 700), dark: false, SettingsView().environment(h.app))

    let grid33 = Grid(rows: 3, cols: 3)
    var actions33 = ZoneAction.defaults(for: grid33)
    actions33["z6"] = ZoneAction(kind: .openApp, appBundleID: "com.apple.calculator", appName: "Calculator")
    shot("display map 3x3", CGSize(width: 620, height: 420),
         DisplayMap(grid: grid33, action: { actions33[zoneLabel($0)] ?? ZoneAction() }, style: .large, selected: 6).padding())
    shot("display map reliability", CGSize(width: 620, height: 420),
         DisplayMap(grid: h.app.grid, action: h.app.action(for:), style: .large, reliability: h.app.report?.zoneReliability ?? [:]).padding())
    shot("display map compact", CGSize(width: 300, height: 220),
         DisplayMap(grid: grid33, action: { actions33[zoneLabel($0)] ?? ZoneAction() }, style: .compact).padding())

    let screen = NSScreen.builtIn?.frame.size ?? CGSize(width: 1470, height: 956)
    let size = CGSize(width: screen.width / 2, height: screen.height / 2)
    h.app.calibration = CalibrationState(grid: h.app.grid, perZone: 15, sequence: ["z2", "z2", "z0", "z1", "z3"], position: 0)
    shot("calibration taps", size, CalibrationView().environment(h.app))
    h.app.calibration?.phase = .noisePrompt
    shot("calibration noise prompt", size, CalibrationView().environment(h.app))
    h.app.calibration?.phase = .noise(until: Date().addingTimeInterval(9))
    shot("calibration noise countdown", size, CalibrationView().environment(h.app))
    h.app.calibration?.phase = .training
    shot("calibration training", size, CalibrationView().environment(h.app))
    h.app.calibration?.phase = .done
    shot("calibration done", size, CalibrationView().environment(h.app))
    h.app.calibration = CalibrationState(grid: grid33, perZone: 15, sequence: ["z4"], position: 0)
    shot("calibration 3x3 target centre", size, CalibrationView().environment(h.app))
    h.app.calibration = nil

    let g = PrivacyGuard(presentsOverlay: false)
    g.muteMic = false
    g.stopCamera = false
    g.engage()
    shot("privacy overlay", size, PrivacyOverlayView(guardState: g, isPrimary: true))
    shot("privacy overlay secondary screen", CGSize(width: 600, height: 380), PrivacyOverlayView(guardState: g, isPrimary: false))
    g.release()

    T.run("app catalog lists running and installed apps") {
        let apps = AppCatalog.load()
        T.note("\(apps.filter(\.isRunning).count) running, \(apps.filter { !$0.isRunning }.count) installed")
        T.expect(apps.contains { $0.bundleID == "com.apple.calculator" }, "Calculator missing")
        T.expect(apps.contains(where: \.isRunning), "no running apps listed")
        T.expect(Set(apps.map(\.bundleID)).count == apps.count, "duplicate apps in catalog")
        T.expect(!apps.contains { $0.bundleID == Bundle.main.bundleIdentifier }, "lists itself")
        shot("app picker", CGSize(width: 420, height: 520), AppPicker(choose: { _ in }, cancel: {}))
    }
}
