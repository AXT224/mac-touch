import AppKit
import SwiftUI

@MainActor
func profileTests() {
    T.suite = "Profiles"
    print("\n▶ Profiles")

    T.run("there are no profiles until one is added") {
        let h = AppHarness(name: "prof-none")
        T.expect(h.app.config.profiles.isEmpty, "profiles \(h.app.config.profiles.count)")
        T.expect(!h.app.config.hasProfiles, "hasProfiles")
        T.expect(h.app.config.activeProfileID == Profile.defaultID, "active \(h.app.config.activeProfileID)")
        T.expect(h.app.dataset.samples.count == 60, "samples \(h.app.dataset.samples.count)")
    }

    T.run("a new profile starts empty, keeps the old setup as Default and copies actions") {
        let h = AppHarness(name: "prof-add")
        guard h.train() else { return T.fail("no model") }
        h.app.setAction(ZoneAction(kind: .playPause), for: 0)
        h.app.config.detector.k = 9
        guard let lap = h.app.addProfile(name: "Lap", symbol: "figure.seated.side", copyTaps: false) else { return T.fail("not added") }
        let c = h.app.config
        T.expect(c.profiles.map(\.name) == ["Default", "Lap"], "names \(c.profiles.map(\.name))")
        T.expect(c.hasProfiles, "hasProfiles")
        T.expect(c.activeProfileID == lap.id, "active is \(c.activeProfileID)")
        T.expect(h.app.dataset.samples.isEmpty && h.app.grid == Grid(rows: 2, cols: 2), "lap dataset \(h.app.dataset.samples.count) \(h.app.grid.title)")
        T.expect(!h.app.isTrained, "trained with no taps")
        T.expect(h.app.action(for: 0).kind == .playPause, "actions not copied: \(h.app.action(for: 0).kind)")
        T.expect(c.detector.k == 9, "sensitivity not copied: \(c.detector.k)")
        T.expect(c.profiles[0].taps == 60 && (c.profiles[0].accuracy ?? 0) > 0.8, "default summary \(c.profiles[0].taps) \(c.profiles[0].accuracy ?? -1)")
        T.expect(h.app.store.loadDataset().samples.count == 60, "dataset.json changed")
        T.expect(FileManager.default.fileExists(atPath: h.app.store.datasetURL(profile: lap.id).path), "no file for the new profile")
        T.expect(h.app.summary(of: c.profiles[1]).needsCalibration, "new profile should need calibration")
    }

    T.run("copying taps makes a profile that works at once") {
        let h = AppHarness(name: "prof-copy")
        guard h.train() else { return T.fail("no model") }
        guard h.app.addProfile(name: "Sofa", symbol: "sofa", copyTaps: true) != nil else { return T.fail("not added") }
        T.expect(h.app.dataset.samples.count == 60, "copied \(h.app.dataset.samples.count)")
        T.expect(T.wait(30) { h.app.isTrained && !h.app.isTraining }, "copied profile didn't train")
        h.performed.removeAll()
        h.tap("z1")
        T.expect(h.performed.count == 1, "tap in copied profile did nothing")
    }

    T.run("each profile keeps its own settings, actions and taps") {
        let h = AppHarness(name: "prof-switch")
        guard h.train() else { return T.fail("no model") }
        let original = h.app.config.detector.k
        guard let sofa = h.app.addProfile(name: "Sofa", symbol: "sofa", copyTaps: true) else { return T.fail("not added") }
        _ = T.wait(30) { h.app.isTrained && !h.app.isTraining }
        h.app.config.detector.k = 12
        h.app.config.minConfidence = 0.8
        h.app.setAction(ZoneAction(kind: .nextTrack), for: 2)
        h.app.deleteSamples(label: "z3")
        T.expect(h.app.detector.settings.k == 12, "detector not updated")

        h.app.switchProfile(to: Profile.defaultID)
        T.expect(h.app.config.detector.k == original && h.app.detector.settings.k == original, "default k \(h.app.config.detector.k)")
        T.expect(h.app.config.minConfidence == 0.6, "default confidence \(h.app.config.minConfidence)")
        T.expect(h.app.action(for: 2).kind != .nextTrack, "sofa action leaked into Default")
        T.expect(h.app.count(for: "z3") == 15, "default z3 \(h.app.count(for: "z3"))")
        T.expect(!h.app.isTrained || h.app.isTraining, "old model kept across a switch")
        T.expect(T.wait(30) { h.app.isTrained && !h.app.isTraining }, "default didn't retrain")

        h.app.switchProfile(to: sofa.id)
        T.expect(h.app.config.detector.k == 12 && h.app.config.minConfidence == 0.8, "sofa settings lost: \(h.app.config.detector.k) \(h.app.config.minConfidence)")
        T.expect(h.app.action(for: 2).kind == .nextTrack, "sofa action lost")
        h.app.flushSave()
        T.expect(T.wait(2) { h.app.store.loadDataset(profile: sofa.id).count("z3") == 0 }, "sofa taps not saved to its own file")
        T.expect(h.app.store.loadDataset().count("z3") == 15, "Default's dataset.json was changed")
    }

    T.run("the profile in use and its settings survive a restart") {
        let h = AppHarness(name: "prof-restart")
        guard let lap = h.app.addProfile(name: "Lap", symbol: "figure.seated.side", copyTaps: true) else { return T.fail("not added") }
        h.app.config.detector.k = 11
        h.app.setAction(ZoneAction(kind: .mute), for: 1)
        h.app.flushSave()
        let again = AppModel(store: h.app.store, presentsUI: false)
        T.expect(again.config.activeProfileID == lap.id, "active after restart \(again.config.activeProfileID)")
        T.expect(again.config.detector.k == 11, "k after restart \(again.config.detector.k)")
        T.expect(again.action(for: 1).kind == .mute, "action after restart")
        T.expect(again.dataset.samples.count == 60, "taps after restart \(again.dataset.samples.count)")
        T.expect(again.config.profiles.first { $0.id == lap.id }?.settings.detector.k == 11, "saved copy out of date")
    }

    T.run("deleting the profile in use switches to another and removes its taps") {
        let h = AppHarness(name: "prof-delete")
        guard let lap = h.app.addProfile(name: "Lap", symbol: "figure.seated.side", copyTaps: false) else { return T.fail("not added") }
        guard let sofa = h.app.addProfile(name: "Sofa", symbol: "sofa", copyTaps: false) else { return T.fail("not added") }
        h.app.switchProfile(to: lap.id)
        h.app.deleteProfile(lap.id)
        T.expect(h.app.config.profiles.map(\.name) == ["Default", "Sofa"], "left \(h.app.config.profiles.map(\.name))")
        T.expect(h.app.config.activeProfileID == Profile.defaultID, "switched to \(h.app.config.activeProfileID)")
        T.expect(!FileManager.default.fileExists(atPath: h.app.store.datasetURL(profile: lap.id).path), "lap file still there")
        T.expect(h.app.dataset.samples.count == 60, "default taps \(h.app.dataset.samples.count)")
        h.app.deleteProfile(sofa.id)
        T.expect(h.app.config.profiles.count == 1 && !h.app.config.hasProfiles, "one left should hide profiles")
        h.app.deleteProfile(Profile.defaultID)
        T.expect(h.app.config.profiles.count == 1, "deleted the last profile")
    }

    T.run("names must be unique and not empty") {
        let h = AppHarness(name: "prof-names")
        guard let lap = h.app.addProfile(name: "Lap", symbol: "figure.seated.side", copyTaps: false) else { return T.fail("not added") }
        T.expect(h.app.addProfile(name: "  lap ", symbol: "sofa", copyTaps: false) == nil, "duplicate name accepted")
        T.expect(h.app.addProfile(name: "   ", symbol: "sofa", copyTaps: false) == nil, "empty name accepted")
        T.expect(h.app.addProfile(name: String(repeating: "x", count: 30), symbol: "sofa", copyTaps: false) == nil, "long name accepted")
        T.expect(Profile.problem(with: "Lap", among: h.app.config.profiles, excluding: lap.id) == nil, "renaming to own name refused")
        h.app.updateProfile(lap.id, name: " On my lap ", symbol: "chair.lounge")
        let p = h.app.config.profiles.first { $0.id == lap.id }
        T.expect(p?.name == "On my lap" && p?.symbol == "chair.lounge", "rename \(p?.name ?? "-") \(p?.symbol ?? "-")")
        h.app.updateProfile(lap.id, name: "default", symbol: "sofa")
        T.expect(h.app.config.profiles.first { $0.id == lap.id }?.name == "On my lap", "renamed onto another profile's name")
    }

    T.run("profiles can't change while calibrating") {
        let h = AppHarness(name: "prof-cal")
        guard let lap = h.app.addProfile(name: "Lap", symbol: "figure.seated.side", copyTaps: true) else { return T.fail("not added") }
        h.app.startCalibration()
        T.expect(!h.app.canChangeProfile, "canChangeProfile while calibrating")
        h.app.switchProfile(to: Profile.defaultID)
        T.expect(h.app.config.activeProfileID == lap.id, "switched during calibration")
        T.expect(h.app.addProfile(name: "Sofa", symbol: "sofa", copyTaps: false) == nil, "added during calibration")
        h.app.endCalibration()
        h.app.switchProfile(to: Profile.defaultID)
        T.expect(h.app.config.activeProfileID == Profile.defaultID, "couldn't switch after calibration")
    }

    T.run("a broken profile list in config.json falls back safely") {
        let json = """
        {"activeProfileID": "gone", "profiles": [
          {"id": "../../escape", "name": "Bad"},
          {"id": "default", "name": "Desk", "symbol": "table.furniture"},
          {"id": "default", "name": "Dupe"},
          {"id": "abc12345", "name": "Lap"}
        ]}
        """
        let c = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        T.expect(c.profiles.map(\.name) == ["Desk", "Lap"], "kept \(c.profiles.map(\.name))")
        T.expect(c.activeProfileID == "default", "active \(c.activeProfileID)")
        let store = Store(directory: T.tempDir("prof-paths"))
        T.expect(store.datasetURL(profile: "../x") == store.datasetURL, "unsafe id used as a path")
        T.expect(store.datasetURL(profile: "abc12345").lastPathComponent == "abc12345.json", "profile path")
        let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"enabled": true}"#.utf8))
        T.expect(old.profiles.isEmpty && old.activeProfileID == Profile.defaultID, "1.0.2 config didn't load cleanly")
    }

    // MARK: Snapshots

    func shot<V: View>(_ name: String, _ size: CGSize, dark: Bool = true, _ view: V) {
        T.run(name) {
            let url = snapshot(view, size: size, name: name.replacingOccurrences(of: " ", with: "_"), dark: dark)
            T.expect(hasContent(url), "\(name) rendered blank")
        }
    }

    let empty = AppHarness(name: "prof-ui-empty")
    UserDefaults.standard.set("profiles", forKey: "settingsPane")
    shot("profiles pane empty", CGSize(width: 980, height: 700), SettingsView().environment(empty.app))
    shot("profile editor new first", CGSize(width: 460, height: 560), dark: false, ProfileEditor(mode: .new).environment(empty.app))

    let h = AppHarness(name: "prof-ui")
    guard h.train() else { return T.fail("no model for profile snapshots") }
    h.app.addProfile(name: "Desk", symbol: "table.furniture", copyTaps: true)
    _ = T.wait(30) { h.app.isTrained && !h.app.isTraining }
    h.app.addProfile(name: "Sofa", symbol: "sofa", copyTaps: false)
    h.app.updateProfile(Profile.defaultID, name: "Lap", symbol: "figure.seated.side")
    shot("menu panel profiles untrained", CGSize(width: 300, height: 360), MenuPanel().environment(h.app))
    h.app.switchProfile(to: h.app.config.profiles[1].id)
    _ = T.wait(30) { h.app.isTrained && !h.app.isTraining }
    h.tap("z1")
    shot("menu panel profiles", CGSize(width: 300, height: 440), MenuPanel().environment(h.app))
    shot("menu panel profiles light", CGSize(width: 300, height: 440), dark: false, MenuPanel().environment(h.app))
    shot("profiles pane", CGSize(width: 980, height: 700), SettingsView().environment(h.app))
    shot("profiles pane light", CGSize(width: 980, height: 700), dark: false, SettingsView().environment(h.app))
    shot("profile editor new", CGSize(width: 460, height: 560), ProfileEditor(mode: .new).environment(h.app))
    if let p = h.app.config.profiles.last {
        shot("profile editor edit", CGSize(width: 460, height: 300), dark: false, ProfileEditor(mode: .edit(p)).environment(h.app))
    }
    for (name, symbol) in [("Bed", "bed.double"), ("Café", "cup.and.saucer"), ("Kitchen table", "fork.knife")] {
        h.app.addProfile(name: name, symbol: symbol, copyTaps: true)
    }
    h.app.switchProfile(to: h.app.config.profiles[1].id)
    _ = T.wait(30) { h.app.isTrained && !h.app.isTraining }
    shot("menu panel many profiles", CGSize(width: 300, height: 440), dark: false, MenuPanel().environment(h.app))
    UserDefaults.standard.set("zones", forKey: "settingsPane")
}
