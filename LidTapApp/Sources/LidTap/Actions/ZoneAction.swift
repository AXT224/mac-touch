import AppKit
import SwiftUI

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, desktopLeft, desktopRight, newNote, playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute, openApp, runShortcut, privacyGuard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Nothing"
        case .desktopLeft: "Desktop Left"
        case .desktopRight: "Desktop Right"
        case .newNote: "New Note"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute Sound"
        case .openApp: "Open App"
        case .runShortcut: "Run Shortcut"
        case .privacyGuard: "Privacy Guard"
        }
    }

    var detail: String {
        switch self {
        case .none: "This zone does nothing"
        case .desktopLeft: "Switch to the Space on the left"
        case .desktopRight: "Switch to the Space on the right"
        case .newNote: "Open Notes with a fresh note"
        case .playPause: "Play or pause whatever is playing"
        case .nextTrack: "Skip to the next track"
        case .previousTrack: "Go back a track"
        case .volumeUp: "Turn the sound up one step"
        case .volumeDown: "Turn the sound down one step"
        case .mute: "Mute or unmute the sound"
        case .openApp: "Launch an app, or bring it to the front"
        case .runShortcut: "Run one of your Shortcuts"
        case .privacyGuard: "Mute, camera off and blur the screen"
        }
    }

    var symbol: String {
        switch self {
        case .none: "minus"
        case .desktopLeft: "rectangle.lefthalf.inset.filled.arrow.left"
        case .desktopRight: "rectangle.righthalf.inset.filled.arrow.right"
        case .newNote: "square.and.pencil"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.end.fill"
        case .previousTrack: "backward.end.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        case .openApp: "arrow.up.forward.app"
        case .runShortcut: "square.2.layers.3d.fill"
        case .privacyGuard: "eye.slash"
        }
    }

    /// Each action wears the hue of the Mac app or feature it belongs to (Spaces, Notes, Music, Privacy).
    var tint: Color {
        switch self {
        case .none: Color(nsColor: .tertiaryLabelColor)
        case .desktopLeft, .desktopRight: .blue
        case .newNote: .yellow
        case .playPause, .nextTrack, .previousTrack: .pink
        case .volumeUp, .volumeDown, .mute: .orange
        case .openApp: .teal
        case .runShortcut: .purple
        case .privacyGuard: .indigo
        }
    }

    /// Short group used to organise the action picker.
    var group: String {
        switch self {
        case .none: "None"
        case .desktopLeft, .desktopRight: "Desktop"
        case .playPause, .nextTrack, .previousTrack: "Music"
        case .volumeUp, .volumeDown, .mute: "Sound"
        case .newNote, .openApp, .runShortcut: "Apps"
        case .privacyGuard: "Privacy"
        }
    }

    /// Whether the action synthesises key events (needs Accessibility permission).
    var needsAccessibility: Bool {
        switch self {
        case .desktopLeft, .desktopRight, .newNote, .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute: true
        // Privacy Guard's blur and mic mute work without it; only the camera shortcut needs it (reported in the overlay).
        case .none, .openApp, .runShortcut, .privacyGuard: false
        }
    }

    /// Actions that need something chosen (an app, a shortcut) before they can run.
    var needsChoice: Bool { self == .openApp || self == .runShortcut }

    /// Volume keys bring up the system's own volume indicator (and its click), so LidTap adds no sound of its own.
    var hasSystemFeedback: Bool {
        switch self {
        case .volumeUp, .volumeDown, .mute: true
        default: false
        }
    }
}

struct ZoneAction: Codable, Equatable, Hashable {
    var kind: ActionKind = .none
    var appBundleID: String?
    var appName: String?
    var shortcutName: String?

    var title: String {
        if kind == .openApp, let appName { return appName }
        if kind == .runShortcut, let shortcutName { return shortcutName }
        return kind.title
    }

    /// False while an app or shortcut still has to be chosen.
    var isComplete: Bool {
        switch kind {
        case .openApp: appBundleID != nil
        case .runShortcut: shortcutName != nil
        default: true
        }
    }

    static func defaults(for grid: Grid) -> [String: ZoneAction] {
        let layout: [ActionKind]
        switch (grid.rows, grid.cols) {
        case (2, 2): layout = [.desktopLeft, .desktopRight, .playPause, .privacyGuard]
        case (2, 3): layout = [.desktopLeft, .newNote, .desktopRight, .previousTrack, .playPause, .privacyGuard]
        case (3, 3): layout = [.desktopLeft, .newNote, .desktopRight, .previousTrack, .playPause, .nextTrack, .openApp, .none, .privacyGuard]
        default: layout = []
        }
        var out: [String: ZoneAction] = [:]
        for i in 0..<grid.count { out[zoneLabel(i)] = ZoneAction(kind: i < layout.count ? layout[i] : .none) }
        return out
    }
}
