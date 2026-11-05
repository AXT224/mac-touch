import Foundation

/// Updater: version parsing, GitHub's release JSON, the signature gate, download-and-verify, and the swap.
/// No network: the feed and the download are local files. The signature tests use the Developer ID–signed
/// LidTap in ~/Applications when it's there.
@MainActor
func updaterTests() {
    T.suite = "Updater"

    func releaseJSON(tag: String, asset: String = Release.assetName, url: String? = nil,
                     draft: Bool = false, prerelease: Bool = false) -> Data {
        let dl = url ?? "https://github.com/yemcube/lidtap/releases/download/\(tag)/\(asset)"
        let obj: [String: Any] = [
            "tag_name": tag, "body": "## What's new\n- **Faster** taps", "html_url": "https://github.com/yemcube/lidtap/releases/tag/\(tag)",
            "draft": draft, "prerelease": prerelease,
            "assets": [["name": asset, "browser_download_url": dl], ["name": "Source.zip", "browser_download_url": "https://github.com/x"]],
        ]
        return try! JSONSerialization.data(withJSONObject: obj)
    }
    func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "lidtap-tests-\(UUID().uuidString)")! }
    func run(_ work: @escaping () async -> Void) {
        var done = false
        Task { await work(); done = true }
        T.expect(T.wait(30) { done }, "timed out")
    }
    func shell(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try! p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    T.run("versions compare numerically, with or without a leading v") {
        let v = { AppVersion($0)! }
        T.expect(v("v1.0.2") > v("1.0.1"), "1.0.2 > 1.0.1")
        T.expect(v("1.0.10") > v("1.0.9"), "1.0.10 > 1.0.9 (not string order)")
        T.expect(v("1.1") > v("1.0.5"), "1.1 > 1.0.5")
        T.expect(v("1.0") == v("1.0.0"), "1.0 == 1.0.0")
        T.expect(!(v("1.0.1") > v("1.0.1")), "same version isn't newer")
        T.expect(v("2.0.0-beta") == v("2.0.0"), "suffix ignored")
        T.expect(AppVersion("latest") == nil && AppVersion("1..2") == nil && AppVersion("") == nil, "garbage refused")
    }

    T.run("reads GitHub's latest-release answer") {
        let r = try Release.parse(releaseJSON(tag: "v1.2.0"))
        T.expect(r.version == AppVersion("1.2.0")!, "version \(r.version)")
        T.expect(r.download.absoluteString.hasSuffix("/v1.2.0/LidTap-macOS.zip"), "download \(r.download)")
        T.expect(r.notes.contains("Faster"), "notes")
    }

    T.run("refuses drafts, pre-releases, missing zips and downloads off github.com") {
        func refused(_ d: Data) -> Bool { (try? Release.parse(d)) == nil }
        T.expect(refused(releaseJSON(tag: "v2.0.0", draft: true)), "draft")
        T.expect(refused(releaseJSON(tag: "v2.0.0", prerelease: true)), "pre-release")
        T.expect(refused(releaseJSON(tag: "v2.0.0", asset: "Other.zip")), "no LidTap zip")
        T.expect(refused(releaseJSON(tag: "v2.0.0", url: "https://evil.example/LidTap-macOS.zip")), "other host")
        T.expect(refused(releaseJSON(tag: "v2.0.0", url: "http://github.com/x/LidTap-macOS.zip")), "plain http")
        T.expect(refused(Data("{\"message\":\"Not Found\"}".utf8)), "error answer")
    }

    T.run("a check offers a newer release once, and respects Skip and Remind Me Later") {
        let dir = T.tempDir("feed")
        let feed = dir.appendingPathComponent("latest.json")
        try releaseJSON(tag: "v1.0.2").write(to: feed)
        var offers: [(String, Bool)] = []
        let u = Updater(current: AppVersion("1.0.1")!, feed: feed, defaults: freshDefaults())
        u.onFound = { r, asked in offers.append((r.version.description, asked)) }

        run { await u.check(userInitiated: false) }
        T.expect(u.state == .available && u.available?.version.description == "1.0.2", "state \(u.state)")
        T.expect(offers.count == 1 && offers[0] == ("1.0.2", false), "offers \(offers)")
        T.expect(u.lastChecked != nil, "last check recorded")

        u.skip(u.available!)
        run { await u.check(userInitiated: false) }
        T.expect(offers.count == 1, "skipped version offered again automatically")
        run { await u.check(userInitiated: true) }
        T.expect(offers.count == 2 && offers[1].1, "asking always shows it")

        let u2 = Updater(current: AppVersion("1.0.1")!, feed: feed, defaults: freshDefaults())
        var n = 0
        u2.onFound = { _, _ in n += 1 }
        u2.remindLater()
        run { await u2.check(userInitiated: false) }
        T.expect(n == 0 && u2.state == .available, "snoozed: no pop-up, but the menu still knows (\(u2.state))")
    }

    T.run("up to date, and a failed check only reports when the user asked") {
        let dir = T.tempDir("feed2")
        let feed = dir.appendingPathComponent("latest.json")
        try releaseJSON(tag: "v1.0.1").write(to: feed)
        let u = Updater(current: AppVersion("1.0.1")!, feed: feed, defaults: freshDefaults())
        var offered = false
        u.onFound = { _, _ in offered = true }
        run { await u.check(userInitiated: true) }
        T.expect(u.state == .upToDate && !offered && u.available == nil, "state \(u.state)")

        let missing = Updater(current: AppVersion("1.0.1")!, feed: dir.appendingPathComponent("nope.json"), defaults: freshDefaults())
        run { await missing.check(userInitiated: false) }
        T.expect(missing.state == .idle, "automatic failure should stay quiet: \(missing.state)")
        run { await missing.check(userInitiated: true) }
        if case .failed = missing.state {} else { T.fail("asked: should report failure, got \(missing.state)") }
    }

    T.run("won't replace an app it can't write to or that runs from a translocated copy") {
        T.expect((try? UpdateInstaller.destination(for: URL(fileURLWithPath: "/System/Applications/Calculator.app"))) == nil, "read-only folder")
        let trans = URL(fileURLWithPath: "/private/var/folders/xx/AppTranslocation/ABC/d/LidTap.app")
        T.expect((try? UpdateInstaller.destination(for: trans)) == nil, "translocated")
        let ok = T.tempDir("dest").appendingPathComponent("LidTap.app")
        T.expect((try? UpdateInstaller.destination(for: ok)) == ok, "writable folder")
    }

    T.run("swaps the new app in after LidTap quits") {
        let dir = T.tempDir("swap")
        let dest = dir.appendingPathComponent("Applications/LidTap.app")
        let new = dir.appendingPathComponent("staged/LidTap.app")
        for (app, mark) in [(dest, "old"), (new, "new")] {
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try mark.write(to: app.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
        }
        let gone = Process()
        gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try gone.run()
        gone.waitUntilExit()  // stands in for LidTap, already quit
        let swap = try UpdateInstaller.launchSwap(new: new, dest: dest, pid: gone.processIdentifier, relaunch: false)
        swap.waitUntilExit()
        let mark = try? String(contentsOf: dest.appendingPathComponent("marker"), encoding: .utf8)
        T.expect(mark == "new", "installed app is \(mark ?? "missing")")
        T.expect(!FileManager.default.fileExists(atPath: new.path), "staged copy left behind")
        T.expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("staged/LidTap-previous.app").path), "old app left behind")
    }

    T.run("a failed swap puts the old app back") {
        let dir = T.tempDir("swapfail")
        let dest = dir.appendingPathComponent("LidTap.app")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "old".write(to: dest.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
        let missing = dir.appendingPathComponent("staged/LidTap.app")  // nothing to install
        try FileManager.default.createDirectory(at: missing.deletingLastPathComponent(), withIntermediateDirectories: true)
        let swap = try UpdateInstaller.launchSwap(new: missing, dest: dest, pid: 999_999, relaunch: false)
        swap.waitUntilExit()
        let mark = try? String(contentsOf: dest.appendingPathComponent("marker"), encoding: .utf8)
        T.expect(mark == "old", "old app not restored: \(mark ?? "missing")")
    }

    T.run("update window renders each state") {
        let dir = T.tempDir("feed-ui")
        let feed = dir.appendingPathComponent("latest.json")
        let notes = "## What's new\n- **Check for Updates** in the menu: LidTap updates itself from GitHub when you say so.\n- Privacy Guard keeps your camera and mic settings safe if LidTap quits unexpectedly.\n- Taps saved on quit during calibration."
        let obj: [String: Any] = ["tag_name": "v1.0.2", "body": notes, "html_url": "https://github.com/yemcube/lidtap/releases/tag/v1.0.2",
                                  "assets": [["name": Release.assetName, "browser_download_url": "https://github.com/yemcube/lidtap/releases/download/v1.0.2/LidTap-macOS.zip"]]]
        try JSONSerialization.data(withJSONObject: obj).write(to: feed)
        let u = Updater(current: AppVersion("1.0.1")!, feed: feed, defaults: freshDefaults())
        run { await u.check(userInitiated: true) }
        for dark in [true, false] {
            let url = snapshot(UpdateView(updater: u, close: {}), size: CGSize(width: 560, height: 400), name: "update_available_\(dark ? "dark" : "light")", dark: dark)
            T.expect(url != nil, "snapshot")
        }
        try releaseJSON(tag: "v1.0.1").write(to: feed)
        run { await u.check(userInitiated: true) }
        snapshot(UpdateView(updater: u, close: {}), size: CGSize(width: 560, height: 130), name: "update_uptodate", dark: false)
    }

    // The signature gate, against the real Developer ID build.
    let installed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LidTap.app")
    let signed: URL? = {
        guard (try? UpdateInstaller.verify(installed)) != nil else { return nil }
        let copy = T.tempDir("signed").appendingPathComponent("LidTap.app")
        return shell(["/usr/bin/ditto", installed.path, copy.path]) == 0 ? copy : nil
    }()
    func needSigned() throws -> URL {
        guard let signed else { throw T.Skip(reason: "no Developer ID–signed LidTap in ~/Applications") }
        return signed
    }
    func zipped(_ app: URL, _ name: String) -> URL {
        let zip = T.tempDir(name).appendingPathComponent(Release.assetName)
        _ = shell(["/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, zip.path])
        return zip
    }
    func localRelease(_ zip: URL, _ version: String) -> Release {
        Release(version: AppVersion(version)!, notes: "", page: Updater.releasesPage, download: zip)
    }

    T.run("only an app signed with LidTap's Developer ID passes") {
        let app = try needSigned()
        T.expect((try? UpdateInstaller.verify(app)) != nil, "the real signed build was refused")

        let adhoc = T.tempDir("adhoc").appendingPathComponent("LidTap.app")
        _ = shell(["/usr/bin/ditto", app.path, adhoc.path])
        _ = shell(["/usr/bin/codesign", "--force", "--sign", "-", adhoc.path])
        T.expect((try? UpdateInstaller.verify(adhoc)) == nil, "ad hoc signature accepted")

        let tampered = T.tempDir("tampered").appendingPathComponent("LidTap.app")
        _ = shell(["/usr/bin/ditto", app.path, tampered.path])
        try "x".write(to: tampered.appendingPathComponent("Contents/Resources/extra.txt"), atomically: true, encoding: .utf8)
        T.expect((try? UpdateInstaller.verify(tampered)) == nil, "modified bundle accepted")

        let notApp = T.tempDir("plain")
        T.expect((try? UpdateInstaller.verify(notApp)) == nil, "unsigned folder accepted")
    }

    T.run("downloads, unpacks and verifies a release; refuses unsigned and same-version zips") {
        let app = try needSigned()
        let v = UpdateInstaller.version(of: app)!
        let older = AppVersion(v.parts.dropLast().map(String.init).joined(separator: ".") + ".\(max(0, v.parts.last! - 1))")!
        let zip = zipped(app, "zip-signed")

        var result: Result<URL, Error>?
        let u = Updater(current: older, defaults: freshDefaults())
        run { do { result = .success(try await u.prepare(localRelease(zip, v.description))) } catch { result = .failure(error) } }
        if case .success(let staged) = result {
            T.expect(UpdateInstaller.version(of: staged) == v, "staged version")
        } else { T.fail("signed newer release refused: \(String(describing: result))") }

        let same = Updater(current: v, defaults: freshDefaults())
        result = nil
        run { do { result = .success(try await same.prepare(localRelease(zip, v.description))) } catch { result = .failure(error) } }
        if case .failure(let e) = result, case .notNewer = e as? UpdateError {} else { T.fail("same version accepted: \(String(describing: result))") }

        let adhoc = T.tempDir("adhoc2").appendingPathComponent("LidTap.app")
        _ = shell(["/usr/bin/ditto", app.path, adhoc.path])
        _ = shell(["/usr/bin/codesign", "--force", "--sign", "-", adhoc.path])
        let badZip = zipped(adhoc, "zip-adhoc")
        result = nil
        run { do { result = .success(try await u.prepare(localRelease(badZip, v.description))) } catch { result = .failure(error) } }
        if case .failure(let e) = result, case .notSigned = e as? UpdateError {} else { T.fail("ad hoc build accepted: \(String(describing: result))") }

        let junk = T.tempDir("junk").appendingPathComponent(Release.assetName)
        try "not a zip".write(to: junk, atomically: true, encoding: .utf8)
        result = nil
        run { do { result = .success(try await u.prepare(localRelease(junk, v.description))) } catch { result = .failure(error) } }
        if case .failure(let e) = result, (e as? UpdateError) == .badArchive {} else { T.fail("junk zip: \(String(describing: result))") }
    }

    T.run("a failed install reports why and leaves the app alone") {
        let app = try needSigned()
        let v = UpdateInstaller.version(of: app)!
        let dest = T.tempDir("dest-fail").appendingPathComponent("LidTap.app")
        let u = Updater(current: v, defaults: freshDefaults())
        var quit = false
        u.quit = { quit = true }
        run { await u.install(localRelease(zipped(app, "zip-same"), v.description), into: dest) }
        if case .failed(let m) = u.state { T.expect(m.contains("isn't newer"), "message: \(m)") } else { T.fail("state \(u.state)") }
        T.expect(!quit, "quit although nothing was installed")
    }
}

/// Live: asks the real GitHub for the latest release and verifies its download. Network, no other side effects.
@MainActor
func updaterLiveTests() {
    T.suite = "Updater (live GitHub)"
    T.run("the published release is found, downloads and passes the signature check") {
        let u = Updater(current: AppVersion("0.0.1")!, defaults: UserDefaults(suiteName: "lidtap-tests-live")!)
        var done = false
        Task { await u.check(userInitiated: true); done = true }
        T.expect(T.wait(30) { done }, "check timed out")
        guard let r = u.available else { return T.fail("no release: \(u.state)") }
        T.note("latest: \(r.version) \(r.download.absoluteString)")
        var staged: URL?
        var err: Error?
        done = false
        Task { do { staged = try await u.prepare(r) } catch { err = error }; done = true }
        T.expect(T.wait(120) { done }, "download timed out")
        T.expect(staged != nil, "release refused: \(String(describing: err))")
    }
}
