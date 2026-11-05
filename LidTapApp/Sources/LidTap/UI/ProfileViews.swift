import SwiftUI

// MARK: - Icon

/// A profile's symbol on a rounded tile: filled with the accent colour for the profile in use, tinted otherwise.
struct ProfileIcon: View {
    let symbol: String
    var size: CGFloat = 28
    var active = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .frame(width: size, height: size)
            .foregroundStyle(active ? Color.white : Color.accentColor)
            .background {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(active ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.accentColor.opacity(0.14)))
            }
            .accessibilityHidden(true)
    }
}

extension AppModel {
    /// One line describing how a profile is calibrated: live for the profile in use, remembered for the rest.
    func summary(of p: Profile) -> (text: String, needsCalibration: Bool) {
        let active = p.id == config.activeProfileID
        if active && isTraining { return ("Learning your taps…", false) }
        let grid = active ? self.grid : (p.grid ?? self.grid)
        let taps = active ? dataset.zoneTapCount - softTapCount : p.taps
        let acc = active ? (isTrained ? accuracy : nil) : p.accuracy
        guard taps > 0 else { return ("Not calibrated yet", true) }
        var parts = [grid.title, "\(taps) taps"]
        if let acc { parts.append("\(Int((acc * 100).rounded()))% accurate") }
        return (parts.joined(separator: " · "), acc == nil)
    }
}

// MARK: - Menu bar switcher

/// Segmented switcher at the top of the menu panel. Up to four profiles share the width; more scroll sideways.
/// ⌘1…⌘9 switch while the panel is open.
struct ProfileSwitcher: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Namespace private var selection

    var body: some View {
        let profiles = app.config.profiles
        Group {
            if profiles.count <= 4 {
                track(profiles, fill: true)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { track(profiles, fill: false) }
                        // Fade the trailing edge so a cut-off profile reads as "scroll for more".
                        .mask {
                            HStack(spacing: 0) {
                                Color.black
                                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18)
                            }
                        }
                        .onAppear { proxy.scrollTo(app.config.activeProfileID, anchor: .center) }
                }
            }
        }
        .disabled(!app.canChangeProfile)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile")
    }

    private func track(_ profiles: [Profile], fill: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { i, p in
                segment(p, index: i, fill: fill).id(p.id)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func segment(_ p: Profile, index: Int, fill: Bool) -> some View {
        let on = p.id == app.config.activeProfileID
        let needs = app.summary(of: p).needsCalibration && !(on && app.isTraining)
        return Button {
            withAnimation(DS.Motion.state) { app.switchProfile(to: p.id) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: p.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                Text(p.name)
                    .font(.callout.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? .primary : .secondary)
                    .lineLimit(1)
                if needs {
                    Circle().fill(.orange).frame(width: 5, height: 5).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: fill ? .infinity : nil)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.12), radius: 1.5, y: 0.5)
                        .matchedGeometryEffect(id: "selected", in: selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(NumberShortcut(index: index))
        .help(index < 9 ? "\(p.name)  ⌘\(index + 1)" : p.name)
        .accessibilityLabel(p.name + (needs ? ", not calibrated" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct NumberShortcut: ViewModifier {
    let index: Int
    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        } else {
            content
        }
    }
}

/// Toolbar menu in Settings for the panes whose settings belong to a profile.
struct ProfilePicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Picker("Profile", selection: Binding(get: { app.config.activeProfileID }, set: { app.switchProfile(to: $0) })) {
            ForEach(app.config.profiles) { p in
                Label(p.name, systemImage: p.symbol).tag(p.id)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(!app.canChangeProfile)
        .help("Zones, training and detection settings belong to this profile")
    }
}

// MARK: - Settings pane

struct ProfilesPane: View {
    @Environment(AppModel.self) private var app
    @State private var editing: ProfileEditor.Mode?
    @State private var deleting: Profile?

    var body: some View {
        Form {
            if app.config.hasProfiles {
                Section {
                    ForEach(Array(app.config.profiles.enumerated()), id: \.element.id) { i, p in
                        row(p, index: i)
                    }
                } header: {
                    Text("Profiles")
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Switch from the LidTap menu, or with ⌘1–⌘\(min(app.config.profiles.count, 9)) while it's open.")
                        Spacer()
                        Button("Add Profile…") { editing = .new }.disabled(!app.canChangeProfile)
                    }
                }
                Section {
                    LabeledContent("Each profile has its own") { Text("Calibration, zone actions and sensitivity") }
                    LabeledContent("Shared by all profiles") { Text("Privacy Guard, feedback, sounds and updates") }
                }
            } else {
                Section { intro }
            }
        }
        .sheet(item: $editing) { mode in ProfileEditor(mode: mode).environment(app) }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Profile", role: .destructive) {
                if let p = deleting { withAnimation(DS.Motion.state) { app.deleteProfile(p.id) } }
                deleting = nil
            }
        } message: {
            Text("Its recorded taps are moved to the Trash. Other profiles aren't affected.")
        }
    }

    private var intro: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ProfileIcon(symbol: "table.furniture", size: 44)
                ProfileIcon(symbol: "figure.seated.side", size: 54, active: true)
                ProfileIcon(symbol: "sofa", size: 44)
            }
            .padding(.bottom, 4)
            Text("A setup for every place").font(.title3.weight(.semibold))
            Text("Taps feel different on a desk, on your lap or on a sofa. A profile gives each place its own calibration, zone actions and sensitivity. Switch between them from the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            Button("Add Profile…") { editing = .new }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!app.canChangeProfile)
            Text("What you've set up so far is kept as your “\(app.config.activeProfile?.name ?? Profile.defaultName)” profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private func row(_ p: Profile, index: Int) -> some View {
        let active = p.id == app.config.activeProfileID
        let summary = app.summary(of: p)
        return HStack(spacing: 12) {
            ProfileIcon(symbol: p.symbol, size: 32, active: active)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.name).font(.body.weight(.medium))
                    if active {
                        Text("In Use")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .foregroundStyle(Color.accentColor)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }
                Label {
                    Text(summary.text)
                } icon: {
                    if summary.needsCalibration && !app.isTraining { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                }
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if index < 9 { Text("⌘\(index + 1)").font(.caption).monospacedDigit().foregroundStyle(.tertiary) }
            if !active {
                Button("Switch") { withAnimation(DS.Motion.state) { app.switchProfile(to: p.id) } }
                    .disabled(!app.canChangeProfile)
            }
            Menu {
                actions(p, summary.needsCalibration)
            } label: {
                Image(systemName: "ellipsis.circle").font(.body)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu { actions(p, summary.needsCalibration) }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ p: Profile, _ needsCalibration: Bool) -> some View {
        Button("Edit…") { editing = .edit(p) }
        Button(needsCalibration ? "Calibrate…" : "Calibrate Again…") { app.calibrateProfile(p.id) }
            .disabled(!app.canChangeProfile)
        Divider()
        Button("Delete…", role: .destructive) { deleting = p }
            .disabled(!app.canChangeProfile)
    }
}

// MARK: - New / edit sheet

struct ProfileEditor: View {
    enum Mode: Identifiable {
        case new
        case edit(Profile)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let p): p.id
            }
        }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var name = ""
    @State private var symbol = "figure.seated.side"
    @State private var copyTaps = false
    @State private var edited = false
    @FocusState private var nameFocused: Bool

    init(mode: Mode) {
        self.mode = mode
        if case .edit(let p) = mode {
            _name = State(initialValue: p.name)
            _symbol = State(initialValue: p.symbol)
        }
    }

    private var isNew: Bool { if case .new = mode { true } else { false } }
    private var editingID: String? { if case .edit(let p) = mode { p.id } else { nil } }
    private var problem: String? { Profile.problem(with: name, among: app.config.profiles, excluding: editingID) }
    private var currentName: String { app.config.activeProfile?.name ?? Profile.defaultName }
    private var canCopy: Bool { app.dataset.zoneTapCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ProfileIcon(symbol: symbol, size: 52, active: true)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(DS.Motion.state, value: symbol)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isNew ? "New Profile" : "Edit Profile").font(.title3.weight(.semibold))
                    Text(isNew ? "A setup for one place you use your Mac." : "Rename it or pick another icon.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: $name, prompt: Text("Lap, Sofa, Kitchen table…"))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($nameFocused)
                    .onChange(of: name) { edited = true }
                    .onSubmit(commit)
                if isNew { suggestions }
                if edited, let problem { Text(problem).font(.caption).foregroundStyle(.red) }
            }

            VStack(alignment: .leading, spacing: 8) {
                caption("Icon")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 10), alignment: .leading, spacing: 8) {
                    ForEach(Profile.symbols, id: \.self) { s in symbolButton(s) }
                }
            }

            if isNew {
                VStack(alignment: .leading, spacing: 8) {
                    caption("Start with")
                    option(selected: !copyTaps, symbol: "scope", title: "Calibrate on the new surface",
                           detail: "Recommended: taps feel different on each surface. About two minutes.") { copyTaps = false }
                    option(selected: copyTaps, symbol: "doc.on.doc", title: "A copy of “\(currentName)”",
                           detail: canCopy ? "Ready right away. Calibrate later if taps are misread." : "“\(currentName)” isn't calibrated yet.") { copyTaps = true }
                        .disabled(!canCopy)
                    Text(app.config.hasProfiles
                         ? "Zone actions and sensitivity start as a copy of “\(currentName)”. Change them any time."
                         : "Zone actions and sensitivity start as a copy of your current setup, which is kept as “\(currentName)”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? (copyTaps ? "Create Profile" : "Create and Calibrate") : "Save", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear { nameFocused = true }
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
    }

    private var suggestions: some View {
        FlowLayout(spacing: 6) {
            ForEach(Profile.suggestions.filter { s in !app.config.profiles.contains { $0.name.caseInsensitiveCompare(s.name) == .orderedSame } },
                    id: \.name) { s in
                let picked = name == s.name
                Button {
                    name = s.name
                    symbol = s.symbol
                } label: {
                    Label(s.name, systemImage: s.symbol)
                        .font(.callout)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(picked ? Color.white : .primary)
                        .background(picked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func symbolButton(_ s: String) -> some View {
        let on = s == symbol
        return Button { symbol = s } label: {
            Image(systemName: s)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(on ? Color.white : .primary)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func option(selected: Bool, symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: symbol).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func commit() {
        edited = true
        guard problem == nil else { return }
        switch mode {
        case .new:
            let calibrate = !copyTaps
            dismiss()
            guard app.addProfile(name: name, symbol: symbol, copyTaps: copyTaps) != nil else { return }
            if calibrate { app.startCalibration() }
        case .edit(let p):
            app.updateProfile(p.id, name: name, symbol: symbol)
            dismiss()
        }
    }
}

/// Lays children out left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width && !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += row.items.isEmpty ? size.width : size.width + spacing
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
