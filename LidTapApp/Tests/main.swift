import AppKit

// LidTap test runner.  build/LidTapTests [suite ...]
// Suites: ml detector logic update ui hardware actions guard e2e updatelive   (default: ml detector logic update ui)
// "updatelive" asks the real GitHub for the latest release and verifies its download.
// "hardware", "actions", "guard" and "e2e" touch the real system (sensors, desktops, apps, microphone, screen).
let wanted = Set(CommandLine.arguments.dropFirst())
let suites = wanted.isEmpty ? ["ml", "detector", "logic", "update", "ui"] : Array(wanted)

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
    let all: [(String, () -> Void)] = [
        ("ml", mlTests), ("detector", detectorTests), ("logic", appLogicTests), ("update", updaterTests), ("updatelive", updaterLiveTests), ("ui", uiTests),
        ("hardware", hardwareTests), ("actions", actionTests), ("guard", guardTests), ("e2e", endToEndTests), ("diag", diagnosticTests), ("sweep", rejectSweep), ("augment", augmentDiag),
    ]
    for (name, run) in all where suites.contains(name) { run() }
    exit(T.summary())
}
