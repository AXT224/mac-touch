import AppKit
import SwiftUI

/// The "Software Update" window. Nothing is downloaded until the user clicks Install and Relaunch.
@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
    static let shared = UpdateWindow()
    private var window: NSWindow?

    func show(_ updater: Updater) {
        if window == nil {
            let host = NSHostingController(rootView: UpdateView(updater: updater, close: { [weak self] in self?.close() }))
            host.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: host)
            w.title = "Software Update"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }
}

struct UpdateView: View {
    let updater: Updater
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .idle, .checking:
            Text("Checking for updates…").font(.headline)
            ProgressView().progressViewStyle(.linear)
            buttons { Button("Cancel", action: close).keyboardShortcut(.cancelAction) }

        case .upToDate:
            Text("LidTap is up to date").font(.headline)
            Text("You have the latest version, \(updater.current.description).").foregroundStyle(.secondary)
            buttons { Button("OK", action: close).keyboardShortcut(.defaultAction) }

        case .available:
            if let release = updater.available { available(release) }

        case .downloading, .installing:
            Text(updater.state == .downloading ? "Downloading LidTap \(updater.available?.version.description ?? "")…"
                                               : "Installing… LidTap will reopen in a moment.")
                .font(.headline)
            ProgressView().progressViewStyle(.linear)

        case .failed(let message):
            Text("Couldn't update LidTap").font(.headline)
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                Button("Download from GitHub") {
                    NSWorkspace.shared.open(updater.available?.page ?? Updater.releasesPage)
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private func available(_ release: Release) -> some View {
        Text("A new version of LidTap is available").font(.headline)
        Text("LidTap \(release.version.description) is available. You have \(updater.current.description). Would you like to install it now?")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if !release.notes.isEmpty {
            Text("Release notes").font(.subheadline.weight(.semibold)).padding(.top, 4)
            ScrollView {
                Text(notes(release.notes))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 160)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        Text("The update comes from LidTap's GitHub releases and is installed only if it's signed by LidTap's developer. Your calibration and settings are kept.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Button("Skip This Version") { updater.skip(release); close() }
            Spacer()
            Button("Remind Me Later") { updater.remindLater(); close() }
                .keyboardShortcut(.cancelAction)
            Button("Install Update") { Task { await updater.install(release) } }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 6)
    }

    private func buttons<B: View>(@ViewBuilder _ content: () -> B) -> some View {
        HStack {
            Spacer()
            content()
        }
        .padding(.top, 6)
    }

    /// GitHub release notes are Markdown: headings become bold lines, list items bullets, and inline styles
    /// (bold, code, links) are kept.
    private func notes(_ markdown: String) -> AttributedString {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { return "**" + line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) + "**" }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { return "•  " + line.dropFirst(2) }
            return String(raw)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
