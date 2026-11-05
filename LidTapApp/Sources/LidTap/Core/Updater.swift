import AppKit
import Foundation
import Security

// Updates come from the project's GitHub releases. LidTap asks GitHub for the latest release, and when it's newer
// and you confirm, downloads its zip, checks that the app inside is signed with LidTap's Developer ID, then swaps
// it in and relaunches. The signature check is what makes this safe: a tampered release can't pass it.

/// A release version such as 1.0.2. Tags may start with "v"; a suffix such as "-beta" is ignored.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let core = s.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.parts = parts.map { $0! }
    }

    /// The running app's version.
    static var current: AppVersion {
        AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? AppVersion("0")!
    }

    private static func padded(_ a: AppVersion, _ b: AppVersion) -> ([Int], [Int]) {
        let n = max(a.parts.count, b.parts.count)
        return (a.parts + Array(repeating: 0, count: n - a.parts.count), b.parts + Array(repeating: 0, count: n - b.parts.count))
    }
    static func == (a: AppVersion, b: AppVersion) -> Bool { let (x, y) = padded(a, b); return x == y }
    static func < (a: AppVersion, b: AppVersion) -> Bool { let (x, y) = padded(a, b); return x.lexicographicallyPrecedes(y) }
    var description: String { parts.map(String.init).joined(separator: ".") }
}

/// One GitHub release that carries the app.
struct Release: Equatable {
    let version: AppVersion
    let notes: String
    let page: URL
    let download: URL

    static let assetName = "LidTap-macOS.zip"

    /// Reads GitHub's "latest release" JSON. Drafts, pre-releases and releases without the app's zip are refused,
    /// and so is a download that isn't on github.com over HTTPS.
    static func parse(_ data: Data) throws -> Release {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        struct GitHubRelease: Decodable {
            let tag_name: String
            let body: String?
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        guard let r = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { throw UpdateError.unreadableFeed }
        guard r.draft != true, r.prerelease != true, let version = AppVersion(r.tag_name) else { throw UpdateError.unreadableFeed }
        guard let asset = r.assets.first(where: { $0.name == assetName }), let url = URL(string: asset.browser_download_url),
              url.scheme == "https", url.host == "github.com" else { throw UpdateError.noDownload }
        let page = URL(string: r.html_url).flatMap { $0.scheme == "https" && $0.host == "github.com" ? $0 : nil } ?? Updater.releasesPage
        return Release(version: version, notes: r.body ?? "", page: page, download: url)
    }
}

enum UpdateError: LocalizedError, Equatable {
    case unreadableFeed, noDownload, network(String), badArchive, notSigned(OSStatus), notNewer(String), cantReplace(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFeed: "GitHub's answer didn't describe a LidTap release."
        case .noDownload: "The latest release has no LidTap-macOS.zip to download."
        case .network(let m): "Couldn't reach GitHub: \(m)"
        case .badArchive: "The download didn't contain LidTap.app."
        case .notSigned: "The download isn't signed by LidTap's developer, so it wasn't installed."
        case .notNewer(let v): "The download is version \(v), which isn't newer than this one."
        case .cantReplace(let m): m
        }
    }
}

// MARK: - Installing

enum UpdateInstaller {
    static let bundleID = "dev.lidtap.LidTap"
    static let teamID = "23R7L2SQ34"

    /// Signed with a Developer ID certificate issued by Apple to LidTap's developer, for this app.
    static let requirement = """
        anchor apple generic and identifier "\(bundleID)" and certificate 1[field.1.2.840.113635.100.6.2.6] \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "\(teamID)"
        """

    /// Throws unless `app` is intact and signed by LidTap's Developer ID.
    static func verify(_ app: URL) throws {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw UpdateError.notSigned(status) }
        var req: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &req)
        guard status == errSecSuccess, let req else { throw UpdateError.notSigned(status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        status = SecStaticCodeCheckValidity(code, flags, req)
        guard status == errSecSuccess else { throw UpdateError.notSigned(status) }
    }

    /// The version in an app bundle's Info.plist (read directly: `Bundle` caches by path).
    static func version(of app: URL) -> AppVersion? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let v = plist["CFBundleShortVersionString"] as? String else { return nil }
        return AppVersion(v)
    }

    /// Unzips `zip` into `folder` and returns the LidTap.app inside.
    static func unpack(_ zip: URL, into folder: URL) throws -> URL {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, folder.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw UpdateError.badArchive }
        p.waitUntilExit()
        let app = folder.appendingPathComponent("LidTap.app")
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path)
        else { throw UpdateError.badArchive }
        return app
    }

    /// Where the update goes: the running app's bundle, if LidTap can replace it.
    static func destination(for bundle: URL = Bundle.main.bundleURL) throws -> URL {
        if bundle.path.contains("/AppTranslocation/") {
            throw UpdateError.cantReplace("Move LidTap to your Applications folder first, then update.")
        }
        let parent = bundle.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.cantReplace("LidTap can't write to \(parent.path). Download the update from GitHub instead.")
        }
        return bundle
    }

    /// Waits for process `pid` to quit, swaps `new` in at `dest` (putting the old app back if that fails), then
    /// optionally reopens it. Runs as its own process so it outlives LidTap.
    static let swapScript = #"""
        pid="$1"; new="$2"; dest="$3"; relaunch="$4"; old="$5"
        i=0
        while kill -0 "$pid" 2>/dev/null; do
          i=$((i + 1)); [ "$i" -gt 300 ] && exit 1
          sleep 0.1
        done
        rm -rf "$old"
        if mv "$dest" "$old"; then
          if mv "$new" "$dest"; then rm -rf "$old"; else mv "$old" "$dest"; fi
        fi
        [ "$relaunch" = 1 ] && open "$dest"
        exit 0
        """#

    /// Starts the swap; it begins once process `pid` (LidTap) has quit.
    @discardableResult
    static func launchSwap(new: URL, dest: URL, pid: Int32 = ProcessInfo.processInfo.processIdentifier, relaunch: Bool = true) throws -> Process {
        let old = new.deletingLastPathComponent().appendingPathComponent("LidTap-previous.app")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", swapScript, "lidtap-update", String(pid), new.path, dest.path, relaunch ? "1" : "0", old.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw UpdateError.cantReplace("Couldn't start the installer: \(error.localizedDescription)") }
        return p
    }
}

// MARK: - Checking

/// Checks GitHub for a newer LidTap and installs it when the user confirms.
@MainActor @Observable
final class Updater {
    enum State: Equatable { case idle, checking, upToDate, available, downloading, installing, failed(String) }

    nonisolated static let feed = URL(string: "https://api.github.com/repos/yemcube/lidtap/releases/latest")!
    nonisolated static let releasesPage = URL(string: "https://github.com/yemcube/lidtap/releases/latest")!
    /// Automatic checks happen at most this often.
    nonisolated static let interval: TimeInterval = 24 * 3600

    private(set) var state: State = .idle
    /// The newer release found by the last check, if any.
    private(set) var available: Release?
    let current: AppVersion

    /// Called when a check finds a release worth offering (`true` when the user asked for the check).
    @ObservationIgnored var onFound: ((Release, Bool) -> Void)?
    /// Quits the app once the swap is ready (tests replace it).
    @ObservationIgnored var quit: () -> Void = { NSApp.terminate(nil) }
    @ObservationIgnored private let feed: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.httpAdditionalHeaders = ["User-Agent": "LidTap-Updater", "Accept": "application/vnd.github+json"]
        return URLSession(configuration: c)
    }()

    init(current: AppVersion = .current, feed: URL = Updater.feed, defaults: UserDefaults = .standard) {
        self.current = current
        self.feed = feed
        self.defaults = defaults
    }

    var lastChecked: Date? { defaults.object(forKey: "updateLastChecked") as? Date }
    private var skipped: String? { defaults.string(forKey: "updateSkippedVersion") }
    private var snoozedUntil: Date? { defaults.object(forKey: "updateSnoozedUntil") as? Date }

    // MARK: Checking

    /// Asks GitHub for the latest release. A newer one that the user hasn't skipped or snoozed goes to `onFound`
    /// (always, when the user asked).
    func check(userInitiated: Bool) async {
        if state == .checking || state == .downloading || state == .installing { return }
        state = .checking
        do {
            let (data, response) = try await session.data(from: feed)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateError.network(http.statusCode == 404 ? "no release published yet" : "GitHub answered \(http.statusCode)")
            }
            let release = try Release.parse(data)
            defaults.set(Date(), forKey: "updateLastChecked")
            guard release.version > current else {
                available = nil
                state = .upToDate
                return
            }
            available = release
            state = .available
            let quiet = release.version.description == skipped || (snoozedUntil.map { $0 > Date() } ?? false)
            if userInitiated || !quiet { onFound?(release, userInitiated) }
        } catch {
            let e = (error as? UpdateError) ?? .network(error.localizedDescription)
            Log.app.error("Update check failed: \(e.localizedDescription, privacy: .public)")
            state = userInitiated ? .failed(e.localizedDescription) : .idle
        }
    }

    /// Checks shortly after launch and then about once a day while LidTap runs.
    func startAutomaticChecks() {
        stopAutomaticChecks()
        let due = { [weak self] in
            guard let self else { return }
            if let last = self.lastChecked, Date().timeIntervalSince(last) < Self.interval { return }
            Task { await self.check(userInitiated: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in MainActor.assumeIsolated { due() } }
        Task { try? await Task.sleep(for: .seconds(20)); if self.timer != nil { due() } }
    }

    func stopAutomaticChecks() {
        timer?.invalidate()
        timer = nil
    }

    func skip(_ release: Release) { defaults.set(release.version.description, forKey: "updateSkippedVersion") }
    func remindLater() { defaults.set(Date().addingTimeInterval(Self.interval), forKey: "updateSnoozedUntil") }

    // MARK: Installing

    /// Downloads, checks and unpacks `release`; returns the verified app, ready to swap in.
    func prepare(_ release: Release) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LidTap-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent(Release.assetName)
        if release.download.isFileURL {
            try FileManager.default.copyItem(at: release.download, to: zip)  // tests
        } else {
            let tmp: URL, response: URLResponse
            do { (tmp, response) = try await session.download(from: release.download) }
            catch { throw UpdateError.network(error.localizedDescription) }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.network("download answered \(http.statusCode)") }
            try FileManager.default.moveItem(at: tmp, to: zip)
        }
        let staged = folder.appendingPathComponent("staged", isDirectory: true)
        let app = try await Task.detached { try UpdateInstaller.unpack(zip, into: staged) }.value
        try await Task.detached { try UpdateInstaller.verify(app) }.value
        let version = UpdateInstaller.version(of: app)
        guard let version, version > current else { throw UpdateError.notNewer(version?.description ?? "unknown") }
        return app
    }

    /// Downloads and verifies `release`, then quits so it can be swapped in and relaunched.
    func install(_ release: Release, into dest: URL? = nil) async {
        guard state != .downloading, state != .installing else { return }
        state = .downloading
        do {
            let dest = try dest ?? UpdateInstaller.destination()
            let app = try await prepare(release)
            state = .installing
            try UpdateInstaller.launchSwap(new: app, dest: dest)
            Log.app.notice("Installing LidTap \(release.version.description, privacy: .public) and relaunching")
            quit()
        } catch {
            let e = (error as? UpdateError) ?? .cantReplace(error.localizedDescription)
            Log.app.error("Update failed: \(e.localizedDescription, privacy: .public)")
            state = .failed(e.localizedDescription)
        }
    }
}
