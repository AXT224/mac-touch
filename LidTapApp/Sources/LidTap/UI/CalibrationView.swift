import AppKit
import SwiftUI

private final class CalibrationPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen window on the laptop display so the zones sit exactly where you tap.
@MainActor
final class CalibrationWindow {
    static let shared = CalibrationWindow()
    private var window: NSWindow?
    private var keyMonitor: Any?

    func show() {
        guard let screen = NSScreen.builtIn else { return }
        if window == nil {
            let w = CalibrationPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isOpaque = true
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)  // a dark full-screen surface whatever the system appearance
            w.contentView = NSHostingView(rootView: CalibrationView().environment(AppModel.shared))
            window = w
        }
        window?.setFrame(screen.frame, display: true)
        window?.alphaValue = 0
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; window?.animator().alphaValue = 1 }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { AppModel.shared.endCalibration(); return nil }  // Esc
                return event
            }
        }
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) })
    }
}

struct CalibrationView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            DS.screen.ignoresSafeArea()
            if let cal = app.calibration {
                switch cal.phase {
                case .taps: TapStage(cal: cal)
                case .noisePrompt: NoisePromptStage(cal: cal).transition(.opacity)
                case .noise(let until): NoiseStage(until: until).transition(.opacity)
                case .training: TrainingStage().transition(.opacity)
                case .done: DoneStage().transition(.opacity)
                }
            }
        }
        .animation(DS.Motion.overlayIn, value: phaseKey)
        .environment(\.colorScheme, .dark)
    }

    private var phaseKey: String {
        switch app.calibration?.phase {
        case .taps: "taps"
        case .noisePrompt: "prompt"
        case .noise: "noise"
        case .training: "training"
        case .done: "done"
        case nil: "none"
        }
    }
}

// MARK: - Taps

private struct TapStage: View {
    @Environment(AppModel.self) private var app
    let cal: CalibrationState
    @State private var ignoredText: String?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(cal.grid.cols), h = geo.size.height / CGFloat(cal.grid.rows)
            ZStack(alignment: .topLeading) {
                ForEach(0..<cal.grid.count, id: \.self) { i in
                    zone(i)
                        .frame(width: w, height: h)
                        .offset(x: CGFloat(i % cal.grid.cols) * w, y: CGFloat(i / cal.grid.cols) * h)
                }
                if let t = cal.target, let i = zoneIndex(t) {
                    TapTarget()
                        .position(tapPoint(zone: i, w: w, h: h))
                        .id(i)
                        .transition(.opacity)
                }
                Path { p in
                    for c in 1..<max(cal.grid.cols, 1) { p.move(to: CGPoint(x: CGFloat(c) * w, y: 0)); p.addLine(to: CGPoint(x: CGFloat(c) * w, y: geo.size.height)) }
                    for r in 1..<max(cal.grid.rows, 1) { p.move(to: CGPoint(x: 0, y: CGFloat(r) * h)); p.addLine(to: CGPoint(x: geo.size.width, y: CGFloat(r) * h)) }
                }
                .stroke(DS.hairline, lineWidth: 1)
            }
        }
        .overlay(alignment: .top) { hud.padding(.top, 14) }
        .onChange(of: cal.flashID) {
            if case .ignored(let reason) = cal.flash {
                withAnimation(DS.Motion.state) {
                    ignoredText = reason == "too soft" ? "Not recorded: a little crisper, please"
                        : reason == "still moving" ? "Wait for the screen to settle, then tap"
                        : "Ignored (\(reason)). Tap again"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(DS.Motion.state) { ignoredText = nil } }
            }
        }
    }

    private var hud: some View {
        HStack(spacing: 14) {
            Image(systemName: "scope").font(.headline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(ignoredText ?? "Calibrating \(cal.grid.title)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ignoredText == nil ? Color.primary : Color.orange)
                    .contentTransition(.opacity)
                ProgressView(value: Double(cal.position), total: Double(max(cal.sequence.count, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }
            Text("\(cal.position) of \(cal.sequence.count)")
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(DS.Motion.feedback, value: cal.position)
            Divider().frame(height: 24)
            StrengthMeter(strength: cal.lastStrength, minimum: app.minTapStrength, id: cal.strengthID)
            Divider().frame(height: 24)
            Button { app.undoLastCalibrationTap() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(cal.position == 0)
            Button { app.endCalibration() } label: { Label("Stop", systemImage: "xmark") }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .padding(.horizontal, 18).padding(.vertical, 10)
        .floatingGlassCapsule()
    }

    /// Where to tap in a zone: toward the screen's outer edge, where a tap twists the laptop most (a longer lever
    /// about the hinge and the screen's centre), so zones are easiest to tell apart. Centre zones keep their centre.
    private func tapPoint(zone i: Int, w: CGFloat, h: CGFloat) -> CGPoint {
        let r = i / cal.grid.cols, c = i % cal.grid.cols
        let inset: CGFloat = 0.2
        let x = c == 0 ? w * inset : c == cal.grid.cols - 1 ? (CGFloat(c) + 1 - inset) * w : (CGFloat(c) + 0.5) * w
        let y = r == 0 ? h * inset + 30 : r == cal.grid.rows - 1 ? (CGFloat(r) + 1 - inset) * h : (CGFloat(r) + 0.36) * h
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func zone(_ i: Int) -> some View {
        let label = zoneLabel(i)
        let isTarget = cal.target == label
        let done = min(app.usableCount(for: label), cal.perZone)
        ZStack {
            Rectangle().fill(isTarget ? Color.accentColor.opacity(0.28) : Color.clear)
            if isTarget {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 3).padding(1.5)
            }
            if let r = app.ripple, r.zone == i { Ripple(color: .accentColor, trigger: r.id).padding(40) }
            VStack(spacing: 8) {
                if isTarget {
                    Text("Zone \(i + 1)")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(cal.remainingInBlock > 1 ? "Tap the dot \(cal.remainingInBlock) times" : "Tap the dot once")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("A quick, light flick. Wait for the screen to settle between taps")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("\(i + 1)")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.22))
                    Text("\(done) of \(cal.perZone)")
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(.white.opacity(done >= cal.perZone ? 0.55 : 0.35))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 16)
            .padding(.vertical, isTarget ? 28 : 16)
            // Keep the instructions on the side of the zone away from the tap dot, so the dot is never covered.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isTarget ? (i / cal.grid.cols == cal.grid.rows - 1 ? .top : .bottom) : .center)
        }
        .animation(DS.Motion.state, value: isTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isTarget ? "Zone \(i + 1). Tap here" : "Zone \(i + 1), \(done) of \(cal.perZone) taps")
    }
}

/// The spot to tap: a quiet target that breathes, so the eye finds it without it shouting.
private struct TapTarget: View {
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2).frame(width: 46, height: 46)
                .scaleEffect(breathe && !reduceMotion ? 1.12 : 1)
                .opacity(breathe ? 0.55 : 0.95)
            Circle().fill(Color.white).frame(width: 10, height: 10)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathe = true } }
        .accessibilityLabel("Tap here")
        .allowsHitTesting(false)
    }
}

/// How crisp the last calibration tap was, against the minimum LidTap records.
private struct StrengthMeter: View {
    let strength: Double?
    let minimum: Double
    let id: Int

    private var scaleMax: Double { minimum * 4 }

    private var verdict: (String, Color) {
        guard let s = strength else { return ("Tap strength", .secondary) }
        if s < minimum { return ("A little crisper", .orange) }
        if s > AppModel.gentlerAbove { return ("Gentler is fine", .yellow) }
        return ("Good tap", .green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verdict.0)
                .font(.callout.weight(.semibold))
                .foregroundStyle(verdict.1)
                .contentTransition(.opacity)
            GeometryReader { geo in
                let frac = min((strength ?? 0) / scaleMax, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(verdict.1).frame(width: max(geo.size.width * frac, strength == nil ? 0 : 6))
                    Rectangle().fill(Color.white.opacity(0.7)).frame(width: 1.5, height: 10)
                        .offset(x: geo.size.width * (minimum / scaleMax) - 0.75)
                }
            }
            .frame(width: 130, height: 6)
        }
        .animation(DS.Motion.feedback, value: id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strength.map { String(format: "%@, %.1f degrees per second", verdict.0, $0) } ?? "Tap strength")
    }
}

// MARK: - Panels

private struct StagePanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 18) { content }
            .multilineTextAlignment(.center)
            .padding(36)
            .frame(width: 500)
            .floatingGlass(cornerRadius: 26)
    }
}

private struct NoisePromptStage: View {
    @Environment(AppModel.self) private var app
    let cal: CalibrationState

    var body: some View {
        StagePanel {
            Image(systemName: "checkmark.circle").font(.system(size: 40, weight: .light)).foregroundStyle(.green)
                .symbolEffect(.bounce, value: true)
            Text("All \(cal.grid.count) zones recorded").font(.title.weight(.semibold))
            Text("Recommended: show LidTap what isn't a tap, so it learns to ignore it. For 20 seconds, type a sentence, click the trackpad, knock the desk and nudge the lid. Just don't tap the screen.")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Skip") { app.finishCalibration() }
                    .controlSize(.large)
                Button("Record 20 Seconds") { app.startNoiseRecording(seconds: 20) }
                    .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
    }
}

private struct NoiseStage: View {
    @Environment(AppModel.self) private var app
    let until: Date

    var body: some View {
        StagePanel {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let left = max(0, until.timeIntervalSince(ctx.date))
                VStack(spacing: 14) {
                    Text("\(Int(left.rounded(.up)))")
                        .font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(DS.Motion.feedback, value: Int(left.rounded(.up)))
                    ProgressView(value: 20 - left, total: 20).progressViewStyle(.linear).frame(width: 260)
                }
            }
            Text("Recording what isn't a tap").font(.title2.weight(.semibold))
            Text("Type, click the trackpad, knock the desk, adjust the lid. Anything except tapping the screen.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("\(app.count(for: noiseLabel)) bumps so far").font(.callout).monospacedDigit().foregroundStyle(.tertiary)
        }
    }
}

private struct TrainingStage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        StagePanel {
            ProgressView().controlSize(.large)
            Text("Learning your taps").font(.title2.weight(.semibold))
            Text("Checking \(app.dataset.samples.count) recorded taps against each other, so the accuracy you see is honest.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DoneStage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 22) {
            if let report = app.report, let kind = app.activeKind {
                let acc = report.accuracy(kind) ?? 0
                VStack(spacing: 6) {
                    Text("\(Int((acc * 100).rounded()))% of taps land in the right zone")
                        .font(.largeTitle.weight(.semibold))
                    Text(summary(report, kind))
                        .font(.title3).foregroundStyle(.secondary)
                }
                DisplayMap(grid: report.grid, action: app.action(for:), style: .large, reliability: report.zoneReliability)
                    .frame(width: 520)
                Text(advice(report))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not enough taps to learn from yet").font(.title.weight(.semibold))
            }
            HStack(spacing: 10) {
                Button("Add More Taps") { app.startCalibration(perZone: app.usableCount(for: zoneLabel(0)) + 5) }
                    .controlSize(.large)
                Button("Done") { app.endCalibration() }
                    .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .floatingGlass(cornerRadius: 28)
    }

    private func summary(_ r: ModelReport, _ kind: ModelKind) -> String {
        let parts = r.layouts.filter { $0 != Layouts.full }.compactMap { l in r.accuracy(kind, l).map { "\(l.lowercased()) \(Int(($0 * 100).rounded()))%" } }
        return "\(r.sampleCount) taps on \(r.grid.title)" + (parts.isEmpty ? "" : " · " + parts.joined(separator: " · "))
    }

    private func advice(_ r: ModelReport) -> String {
        let weak = r.zoneReliability.filter { $0.value < 0.85 }.keys.sorted().map { "\($0 + 1)" }
        if weak.isEmpty { return "Every zone is reliable. Tap gently, the way you just did." }
        return "Zone \(weak.joined(separator: ", ")) " + (weak.count == 1 ? "gets" : "get") + " mixed up more often. Add a few more taps there, or switch to fewer zones."
    }
}
