import Foundation

/// What each profile keeps for itself. Taps feel different on a desk, on a lap or on a sofa, so the calibration
/// (stored per profile in its own dataset file), the sensitivity and the zone actions belong to the place.
/// Everything else in `AppConfig` (on/off, feedback, Privacy Guard, updates) is shared.
struct ProfileSettings: Codable, Equatable {
    var detector = DetectorSettings()
    var rejectFactor = 2.0
    var minConfidence = 0.6
    var autoTapStrength = true
    var minTapStrength = 3.5
    var modelChoice = "auto"
    var actions: [String: ZoneAction] = [:]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProfileSettings()
        detector = try c.decodeIfPresent(DetectorSettings.self, forKey: .detector) ?? d.detector
        rejectFactor = try c.decodeIfPresent(Double.self, forKey: .rejectFactor) ?? d.rejectFactor
        minConfidence = try c.decodeIfPresent(Double.self, forKey: .minConfidence) ?? d.minConfidence
        autoTapStrength = try c.decodeIfPresent(Bool.self, forKey: .autoTapStrength) ?? d.autoTapStrength
        minTapStrength = try c.decodeIfPresent(Double.self, forKey: .minTapStrength) ?? d.minTapStrength
        modelChoice = try c.decodeIfPresent(String.self, forKey: .modelChoice) ?? d.modelChoice
        actions = try c.decodeIfPresent([String: ZoneAction].self, forKey: .actions) ?? d.actions
    }
}

/// A named place the Mac is used: "Desk", "Lap", "Sofa".
struct Profile: Codable, Equatable, Identifiable {
    /// The setup everyone starts with. Its taps stay in dataset.json, where they always were.
    static let defaultID = "default"
    static let defaultName = "Default"
    static let defaultSymbol = "laptopcomputer"
    static let maxNameLength = 24

    var id: String
    var name: String
    var symbol: String
    var settings: ProfileSettings
    /// Last known calibration, so profiles that aren't loaded can still be described.
    var grid: Grid?
    var taps = 0
    var accuracy: Double?

    init(id: String = Profile.newID(), name: String, symbol: String, settings: ProfileSettings) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? Profile.defaultName
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? Profile.defaultSymbol
        settings = try c.decodeIfPresent(ProfileSettings.self, forKey: .settings) ?? ProfileSettings()
        grid = try c.decodeIfPresent(Grid.self, forKey: .grid)
        taps = try c.decodeIfPresent(Int.self, forKey: .taps) ?? 0
        accuracy = try c.decodeIfPresent(Double.self, forKey: .accuracy)
    }

    static func newID() -> String { String(UUID().uuidString.lowercased().prefix(8)) }

    /// Safe as a file name: an id read from a hand-edited config can't point outside the profiles folder.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 36 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// Why `name` can't be used, or nil if it can. `excluding` is the profile being renamed.
    static func problem(with name: String, among profiles: [Profile], excluding: String? = nil) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return "Give the profile a name." }
        if n.count > maxNameLength { return "Use \(maxNameLength) characters or fewer." }
        if profiles.contains(where: { $0.id != excluding && $0.name.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return "There's already a profile called “\(n)”."
        }
        return nil
    }

    /// Places people tap their Mac, offered when making a profile.
    static let suggestions: [(name: String, symbol: String)] = [
        ("Desk", "table.furniture"), ("Lap", "figure.seated.side"), ("Sofa", "sofa"),
        ("Bed", "bed.double"), ("Café", "cup.and.saucer"), ("Travel", "airplane"),
    ]

    static let symbols = [
        "laptopcomputer", "table.furniture", "lamp.desk", "studentdesk", "figure.seated.side", "sofa", "chair.lounge", "bed.double",
        "house", "building.2", "briefcase", "books.vertical", "cup.and.saucer", "fork.knife", "airplane", "tram",
        "car", "tree", "beach.umbrella", "moon",
    ]
}

extension AppConfig {
    /// The active profile's settings, read from and written to the live fields everything else binds to.
    var profileSettings: ProfileSettings {
        get {
            var s = ProfileSettings()
            s.detector = detector
            s.rejectFactor = rejectFactor
            s.minConfidence = minConfidence
            s.autoTapStrength = autoTapStrength
            s.minTapStrength = minTapStrength
            s.modelChoice = modelChoice
            s.actions = actions
            return s
        }
        set {
            detector = newValue.detector
            rejectFactor = newValue.rejectFactor
            minConfidence = newValue.minConfidence
            autoTapStrength = newValue.autoTapStrength
            minTapStrength = newValue.minTapStrength
            modelChoice = newValue.modelChoice
            actions = newValue.actions
        }
    }

    /// Profiles appear in the menu and settings once there are two to choose between.
    var hasProfiles: Bool { profiles.count >= 2 }
    var activeProfile: Profile? { profiles.first { $0.id == activeProfileID } }
    var activeProfileIndex: Int? { profiles.firstIndex { $0.id == activeProfileID } }
}
