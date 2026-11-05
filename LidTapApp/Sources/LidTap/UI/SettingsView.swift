import Charts
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case zones, profiles, training, detection, permissions, general
    var id: String { rawValue }
    /// Panes showing the active profile's settings.
    var isPerProfile: Bool { self == .zones || self == .training || self == .detection }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .zones: "rectangle.split.2x2"
        case .profiles: "rectangle.stack"
        case .training: "chart.bar.xaxis"
        case .detection: "waveform.path.ecg"
        case .permissions: "lock.shield"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("settingsPane") private var storedPane = SettingsPane.zones.rawValue

    private var pane: Binding<SettingsPane?> {
        Binding(get: { SettingsPane(rawValue: storedPane) ?? .zones }, set: { storedPane = ($0 ?? .zones).rawValue })
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            Group {
                switch pane.wrappedValue ?? .zones {
                case .zones: ZonesPane()
                case .profiles: ProfilesPane()
                case .training: TrainingPane()
                case .detection: DetectionPane()
                case .permissions: PermissionsPane()
                case .general: GeneralPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane.wrappedValue ?? .zones).title)
            .toolbar {
                if app.config.hasProfiles && (pane.wrappedValue ?? .zones).isPerProfile {
                    ToolbarItem(placement: .primaryAction) { ProfilePicker() }
                }
            }
        }
    }
}

// MARK: - Zones

private struct ZonesPane: View {
    @Environment(AppModel.self) private var app
    @State private var selected = 0
    @State private var pendingGrid: Grid?
    @State private var choosingApp = false
    @State private var choosingShortcut = false

    var body: some View {
        let current = app.action(for: selected)
        Form {
            Section {
                DisplayMap(grid: app.grid, action: app.action(for:), style: .large, selected: selected, ripple: app.ripple,
                           onSelect: { selected = $0 },
                           contextMenu: { zone in AnyView(ZoneActionMenu(zone: zone).environment(app)) })
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } footer: {
                Text("Click a zone to edit it. Zones are where you tap on your screen.")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Section("Zone \(selected + 1)") {
                Picker("Action", selection: Binding(
                    get: { current.kind },
                    set: { kind in
                        switch kind {
                        case .openApp: choosingApp = true
                        case .runShortcut: choosingShortcut = true
                        default: app.setAction(ZoneAction(kind: kind), for: selected)
                        }
                    })) {
                    ForEach(ActionKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                if current.kind == .openApp {
                    LabeledContent("App") {
                        HStack(spacing: 8) {
                            if current.appBundleID != nil { ActionGlyph(action: current, size: 14) }
                            Text(current.appName ?? "None chosen").foregroundStyle(current.appName == nil ? .secondary : .primary)
                            Button("Choose…") { choosingApp = true }
                        }
                    }
                }
                if current.kind == .runShortcut {
                    LabeledContent("Shortcut") {
                        HStack(spacing: 8) {
                            Text(current.shortcutName ?? "None chosen").foregroundStyle(current.shortcutName == nil ? .secondary : .primary)
                            Button("Choose…") { choosingShortcut = true }
                        }
                    }
                }
                LabeledContent {
                    Button("Try It") { app.testAction(zone: selected) }
                        .disabled(current.kind == .none || !current.isComplete)
                } label: {
                    Text(current.kind.detail).foregroundStyle(.secondary)
                }
                if current.kind.needsAccessibility && !app.status.accessibility {
                    Label("Needs Accessibility. Allow it in Permissions.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if current.kind == .privacyGuard { PrivacyGuardSection() }

            Section {
                Picker("Grid", selection: Binding(get: { app.grid }, set: { g in if g != app.grid { pendingGrid = g } })) {
                    ForEach(Grid.presets, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Layout")
            } footer: {
                Text("Fewer zones are more reliable. A new layout needs a new calibration.")
            }
        }
        .onAppear {
            if let z = app.settingsFocusZone, z < app.grid.count {
                selected = z
                app.settingsFocusZone = nil
                let choice = app.settingsFocusChoice ?? .openApp
                app.settingsFocusChoice = nil
                if app.action(for: z).kind != choice { choice == .runShortcut ? (choosingShortcut = true) : (choosingApp = true) }
            }
        }
        .onChange(of: app.grid) { selected = 0 }
        .alert("Switch to \(pendingGrid?.title ?? "")?", isPresented: Binding(get: { pendingGrid != nil }, set: { if !$0 { pendingGrid = nil } })) {
            Button("Cancel", role: .cancel) { pendingGrid = nil }
            Button("Switch and Calibrate") {
                if let g = pendingGrid { app.startCalibration(grid: g) }
                pendingGrid = nil
            }
        } message: {
            Text("The \(app.dataset.zoneTapCount) taps recorded for \(app.grid.title) will be replaced. Your bump examples are kept.")
        }
        .sheet(isPresented: $choosingApp) {
            AppPicker { info in
                app.setAction(ZoneAction(kind: .openApp, appBundleID: info.bundleID, appName: info.name), for: selected)
                choosingApp = false
            } cancel: { choosingApp = false }
        }
        .sheet(isPresented: $choosingShortcut) {
            ShortcutPicker { name in
                app.setAction(ZoneAction(kind: .runShortcut, shortcutName: name), for: selected)
                choosingShortcut = false
            } cancel: { choosingShortcut = false }
        }
    }
}

private struct PrivacyGuardSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            Toggle("Mute every microphone", isOn: $app.config.guardMutesMic)
            Toggle("Turn the camera off in meetings", isOn: $app.config.guardStopsCamera)
        } header: {
            Text("Privacy Guard")
        } footer: {
            Text("Hides every screen until you tap this zone again or click. Turns the camera off in Zoom, Microsoft Teams, Webex and Google Meet (Chrome, Edge, Brave or Safari), and turns it back on afterwards.")
        }
    }
}

struct AppPicker: View {
    let choose: (AppInfo) -> Void
    let cancel: () -> Void
    @State private var apps: [AppInfo] = []
    @State private var query = ""
    @State private var selection: String?

    var body: some View {
        let filtered = apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 0) {
            List(selection: $selection) {
                let running = filtered.filter(\.isRunning), other = filtered.filter { !$0.isRunning }
                if !running.isEmpty { Section("Running") { ForEach(running) { row($0) } } }
                if !other.isEmpty { Section("Applications") { ForEach(other) { row($0) } } }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search apps")
            .overlay { if !apps.isEmpty && filtered.isEmpty { ContentUnavailableView.search(text: query) } }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Choose") { if let s = selection, let info = apps.first(where: { $0.id == s }) { choose(info) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
        .navigationTitle("Choose an App")
        .task { apps = AppCatalog.load() }
    }

    private func row(_ info: AppInfo) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: info.icon).resizable().frame(width: 22, height: 22)
            Text(info.name)
        }
        .tag(info.id)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { choose(info) }
    }
}

struct ShortcutPicker: View {
    let choose: (String) -> Void
    let cancel: () -> Void
    @State private var names: [String]?
    @State private var query = ""
    @State private var selection: String?

    var body: some View {
        let filtered = (names ?? []).filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 0) {
            List(filtered, id: \.self, selection: $selection) { name in
                Label(name, systemImage: ActionKind.runShortcut.symbol)
                    .tag(name)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { choose(name) }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search shortcuts")
            .overlay {
                if names == nil {
                    ProgressView()
                } else if names?.isEmpty == true {
                    ContentUnavailableView("No Shortcuts", systemImage: ActionKind.runShortcut.symbol,
                                           description: Text("Make one in the Shortcuts app, then choose it here."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            Divider()
            HStack {
                Button("Open Shortcuts") { ActionRunner.openApp(bundleID: "com.apple.shortcuts", then: nil) }
                Button("Refresh") { load() }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Choose") { if let s = selection { choose(s) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
        .navigationTitle("Choose a Shortcut")
        .task { load() }
    }

    private func load() {
        Task.detached(priority: .userInitiated) {
            let list = Shortcuts.list()
            await MainActor.run { names = list }
        }
    }
}

// MARK: - Training

private struct TrainingPane: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                LabeledContent("Accuracy") {
                    Text(app.accuracy.map { "\(Int(($0 * 100).rounded()))% of taps land in the right zone" } ?? "Not trained yet")
                        .foregroundStyle(app.accuracy == nil ? .secondary : .primary)
                }
                LabeledContent("Recorded") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(app.dataset.zoneTapCount - app.softTapCount) taps, \(app.count(for: noiseLabel)) bumps")
                        if app.softTapCount > 0 {
                            Text(String(format: "%d softer than %.1f °/s, not used", app.softTapCount, app.minTapStrength))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Picker("Recogniser", selection: $app.config.modelChoice) {
                    Text("Automatic").tag("auto")
                    Divider()
                    ForEach(ModelKind.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent {
                    HStack {
                        Slider(value: snapped($app.config.minConfidence, 0.05), in: 0.3...0.95)
                        Text("\(Int((app.config.minConfidence * 100).rounded()))%").monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                } label: {
                    Text("Act only when this sure")
                    Text("Below this, LidTap shows \"Not sure which zone\" instead of guessing.")
                }
                LabeledContent {
                    HStack {
                        Slider(value: snapped($app.config.rejectFactor, 0.1), in: 1...5)
                        Text(String(format: "%.1f×", app.config.rejectFactor)).monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                } label: {
                    Text("Ignore unfamiliar taps")
                    Text("Lower is stricter: fewer wrong actions, more \"tap again\".")
                }
            } header: {
                Text("Recognition")
            } footer: {
                HStack {
                    if app.isTraining { ProgressView().controlSize(.small); Text("Learning your taps…") }
                    Spacer()
                    Button("Retrain") { app.retrain() }.disabled(app.isTraining)
                    Button("Calibrate…") { app.startCalibration() }
                }
            }

            if let report = app.report {
                Section {
                    DisplayMap(grid: app.grid, action: app.action(for:), style: .large, reliability: report.zoneReliability)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } header: {
                    Text("Reliability by zone")
                } footer: {
                    Text("How often a tap in each zone was recognised as that zone, scored on taps the recogniser never saw. Add taps to a weak zone, or use fewer zones.")
                }

                Section("Reliability by layout") { layoutTable(report) }
                if report.confusion != nil { Section("Where taps go") { confusion(report) } }
                if !report.learning.isEmpty {
                    Section {
                        learning(report)
                    } header: {
                        Text("Taps needed")
                    } footer: {
                        Text("Accuracy against the number of taps per zone used for learning. A flat curve means more taps won't help much.")
                    }
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Nothing learned yet", systemImage: "hand.tap")
                    } description: {
                        Text("Calibrate to record a few taps in each zone. Results appear here.")
                    } actions: {
                        Button("Calibrate…") { app.startCalibration() }.buttonStyle(.borderedProminent)
                    }
                }
            }

            Section {
                ForEach((0..<app.grid.count).map(zoneLabel) + [noiseLabel], id: \.self) { label in
                    let n = app.usableCount(for: label)
                    LabeledContent {
                        HStack(spacing: 10) {
                            Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                            Button(role: .destructive) { app.deleteSamples(label: label) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .disabled(n == 0)
                                .help("Delete these taps")
                        }
                    } label: {
                        if label == noiseLabel {
                            Label("Bumps", systemImage: "waveform.badge.minus")
                        } else {
                            Label { Text("Zone \((zoneIndex(label) ?? 0) + 1)") } icon: { ActionGlyph(action: app.action(for: zoneIndex(label) ?? 0), size: 12) }
                        }
                    }
                }
            } header: {
                Text("Recorded taps")
            } footer: {
                HStack { Spacer(); Button("Delete All…", role: .destructive) { confirmDeleteAll = true }.disabled(app.dataset.samples.isEmpty) }
            }
        }
        .confirmationDialog("Delete all \(app.dataset.samples.count) recorded taps?", isPresented: $confirmDeleteAll) {
            Button("Delete All Taps", role: .destructive) { app.clearData() }
        } message: {
            Text("LidTap will stop recognising zones until you calibrate again.")
        }
    }

    private func layoutTable(_ report: ModelReport) -> some View {
        SwiftUI.Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow {
                Text("Recogniser").foregroundStyle(.secondary)
                ForEach(report.layouts, id: \.self) { Text($0).foregroundStyle(.secondary).gridColumnAlignment(.trailing) }
            }
            .font(.caption)
            Divider()
            ForEach(report.scores) { score in
                GridRow {
                    HStack(spacing: 4) {
                        Text(score.kind.title)
                        if score.kind == app.activeKind { Text("in use").font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(report.layouts, id: \.self) { layout in
                        let v = score.accuracy[layout]
                        Text(v.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                            .monospacedDigit()
                            .foregroundStyle(v.map { $0 < 0.75 ? Color.red : $0 < 0.9 ? Color.orange : Color.primary } ?? .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func confusion(_ report: ModelReport) -> some View {
        let cm = report.confusion ?? []
        let short = report.labels.map { $0 == noiseLabel ? "Bump" : "\((zoneIndex($0) ?? 0) + 1)" }
        return VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("Tapped ↓  Read as →").font(.caption2).foregroundStyle(.secondary).gridCellColumns(1)
                    ForEach(short.indices, id: \.self) { Text(short[$0]).font(.caption).foregroundStyle(.secondary).frame(width: 34) }
                }
                ForEach(cm.indices, id: \.self) { i in
                    let total = max(cm[i].reduce(0, +), 1)
                    GridRow {
                        Text(i < short.count ? (short[i] == "Bump" ? "Bump" : "Zone \(short[i])") : "").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        ForEach(cm[i].indices, id: \.self) { j in
                            let v = cm[i][j], share = Double(v) / Double(total)
                            Text(v == 0 ? "" : "\(v)")
                                .font(.caption.weight(.medium)).monospacedDigit()
                                .frame(width: 34, height: 26)
                                .background((i == j ? Color.accentColor : Color.red).opacity(v == 0 ? 0.05 : 0.15 + share * 0.6),
                                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .foregroundStyle(share > 0.5 ? Color.white : Color.primary)
                        }
                    }
                }
            }
            Text("The diagonal is correct. Anything off it is a tap read as another zone.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func learning(_ report: ModelReport) -> some View {
        Chart(report.learning, id: \.n) { p in
            LineMark(x: .value("Taps per zone", p.n), y: .value("Accuracy", p.accuracy))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Taps per zone", p.n), y: .value("Accuracy", p.accuracy))
        }
        .foregroundStyle(Color.accentColor)
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(values: [0, 0.5, 0.75, 0.9, 1]) { v in
            AxisGridLine()
            AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) * 100))%") }
        } }
        .chartXAxisLabel("Taps per zone")
        .frame(height: 160)
        .padding(.vertical, 6)
    }
}

/// Snaps a slider's value to `step` without asking macOS to draw a tick per step.
func snapped(_ b: Binding<Double>, _ step: Double) -> Binding<Double> {
    Binding(get: { b.wrappedValue }, set: { b.wrappedValue = ($0 / step).rounded() * step })
}

// MARK: - Detection

private struct DetectionPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                MotionTrace(detector: app.detector, seconds: 5, showsAxes: true)
                    .frame(height: 170)
                    .padding(.vertical, 4)
            } header: {
                Text("Live motion")
            } footer: {
                HStack(spacing: 14) {
                    Text(String(format: "%.0f Hz", app.status.rate))
                    Text(String(format: "Noise %.2f °/s", app.status.noise))
                    Text(String(format: "Trigger %.2f °/s", app.status.threshold))
                    if let lid = app.status.lid { Text("Lid \(lid)°") }
                    Spacer()
                    Text("A tap fires when the line crosses the dashed trigger.")
                }
                .monospacedDigit()
            }

            Section("Sensitivity") {
                Toggle(isOn: $app.config.autoTapStrength) {
                    Text("Learn tap strength from my taps")
                    Text(String(format: "Softer taps than %.1f °/s are not recorded or acted on. A screen tap moves a larger, heavier MacBook less, so LidTap sets this from your own calibration taps", app.minTapStrength))
                }
                if !app.config.autoTapStrength {
                    slider("Minimum tap strength", "Lower it if crisp taps are refused as too soft", $app.config.minTapStrength, 0.5...10, 0.1) { String(format: "%.1f °/s", $0) }
                }
                slider("Trigger", "How far above the resting noise a tap must rise", $app.config.detector.k, 2...15, 0.5) { String(format: "%.1f× noise", $0) }
                slider("Minimum", "Raise if bumps register as taps. Lower if gentle taps are missed", $app.config.detector.minThreshold, 0.2...20, 0.1) { String(format: "%.1f °/s", $0) }
                slider("Gap between taps", "Shorter allows quicker repeat taps", $app.config.detector.refractory, 0.15...1, 0.05) { String(format: "%.2f s", $0) }
                slider("Pause after typing", "Taps this soon after a key, click or scroll are ignored", $app.config.detector.gateSeconds, 0...1, 0.05) { String(format: "%.2f s", $0) }
                Toggle(isOn: $app.config.detector.gating) {
                    Text("Ignore taps while typing or moving the lid")
                    Text("Keeps keystrokes, clicks and lid adjustments from counting as taps.")
                }
            }

            Section("Recent taps") {
                if let last = app.lastRecord {
                    TapWaveform(gyro: last.gyro).frame(height: 56)
                    ForEach(app.recent.prefix(8)) { r in
                        LabeledContent {
                            HStack(spacing: 10) {
                                if let c = r.confidence { Text("\(Int((c * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary) }
                                Text(r.date, format: .dateTime.hour().minute().second()).monospacedDigit().foregroundStyle(.tertiary)
                            }
                        } label: {
                            Text(r.label.flatMap(zoneIndex).map { "Zone \($0 + 1) · \(r.detail)" } ?? r.detail).lineLimit(1)
                        }
                    }
                } else {
                    Text("No taps yet. Tap your screen gently and watch the trace above.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func slider(_ title: String, _ help: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double,
                        _ format: @escaping (Double) -> String) -> some View {
        LabeledContent {
            HStack {
                Slider(value: snapped(value, step), in: range)
                Text(format(value.wrappedValue)).monospacedDigit().frame(width: 82, alignment: .trailing)
            }
        } label: {
            Text(title)
            Text(help)
        }
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                row("Motion sensor", "gyroscope",
                    ok: app.status.rate > 500,
                    detail: app.status.error ?? (app.status.rate > 500 ? String(format: "Streaming at %.0f Hz", app.status.rate) : "Not streaming yet. If it stays this way, allow Input Monitoring."),
                    button: nil)
                row("Accessibility", "accessibility",
                    ok: app.status.accessibility,
                    detail: "To switch desktops, control music, start a note and turn meeting cameras off.",
                    button: ("Allow…", { Permissions.requestAccessibility(); Permissions.openPrivacyPane("Privacy_Accessibility") }))
                row("Input Monitoring", "keyboard",
                    ok: app.status.rate > 500,
                    detail: "Some Macs need it before the motion sensor streams.",
                    button: ("Open…", { Permissions.openPrivacyPane("Privacy_ListenEvent") }))
                row("Automation", "safari",
                    ok: nil,
                    detail: "Asked the first time Privacy Guard looks for a Google Meet tab in your browser.",
                    button: ("Open…", { Permissions.openPrivacyPane("Privacy_Automation") }))
            } footer: {
                Text("LidTap runs entirely on this Mac. After installing a new build, macOS may ask you to switch Accessibility off and on again.")
            }
        }
    }

    private func row(_ title: String, _ symbol: String, ok: Bool?, detail: String, button: (String, () -> Void)?) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                if let ok {
                    Label(ok ? "On" : "Off", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(ok ? .green : .orange)
                        .labelStyle(.titleAndIcon)
                }
                if let (label, action) = button { Button(label, action: action) }
            }
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: symbol)
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Toggle("LidTap is on", isOn: $app.config.enabled)
                Toggle("Open at login", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
            }
            Section {
                Toggle(isOn: $app.config.showTapFeedback) {
                    Text("Show each tap on screen")
                    Text("A ripple in the zone you tapped, with the action's name.")
                }
                Toggle("Play sounds", isOn: $app.config.playSounds)
            } header: {
                Text("Feedback")
            }
            Section {
                LabeledContent("Version") {
                    HStack(spacing: 10) {
                        Text(app.updater.current.description).monospacedDigit()
                        Button(app.updater.available != nil ? "Update…" : "Check Now") {
                            app.updater.available != nil ? app.showUpdate() : app.checkForUpdates()
                        }
                    }
                }
                Toggle(isOn: $app.config.checkForUpdates) {
                    Text("Check for updates automatically")
                    Text("About once a day LidTap asks GitHub for its latest release. Nothing is installed until you confirm, and only an update signed by LidTap's developer.")
                }
            } header: {
                Text("Updates")
            }
            Section {
                LabeledContent("Data") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.dataDirectory]) }
                }
            } footer: {
                Text("Tap gently with a fingertip. LidTap feels the whole laptop move, so there's never a need to press: pressing hard on a display can leave marks.")
            }
        }
    }
}
