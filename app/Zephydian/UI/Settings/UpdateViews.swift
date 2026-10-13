import SwiftUI

/// Settings → General: this version, a newer one when there is one, the daily check and Check Now.
struct UpdatesSection: View {
    @Environment(SettingsStore.self) private var settings
    @Bindable private var updater = AppUpdater.shared

    var body: some View {
        Section("Updates") {
            LabeledContent {
                if updater.available != nil {
                    Button("Update…") { updater.showsWhatsNew = true }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accentColor)
                } else {
                    Text(AppUpdater.currentVersion).foregroundStyle(.secondary)
                }
            } label: {
                HStack(spacing: 10) {
                    Image("MenuBarIcon").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(settings.accentColor)
                        .accessibilityHidden(true)
                    Text(headline)
                }
            }
            Toggle("Check for updates daily", isOn: $updater.autoCheck)
            LabeledContent {
                Button("Check Now") { Task { await updater.check() } }
                    .disabled(updater.state == .checking)
            } label: {
                Text(statusLine).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $updater.showsWhatsNew) {
            WhatsNewSheet().environment(settings)
        }
    }

    /// Never "up to date" unless a check said so (B-53: a refused check showed it).
    private var headline: String {
        if let release = updater.available { return "Zephydian \(release.version) is available" }
        switch updater.state {
        case .checking: return "Checking for updates…"
        case .failed: return "Couldn't check for updates"
        case .upToDate: return "Zephydian is up to date"
        case .idle: return updater.lastChecked == nil ? "Not checked yet" : "Zephydian is up to date"
        }
    }

    private var statusLine: String {
        switch updater.state {
        case .checking: return "Checking…"
        case .failed(let message):
            guard let retry = updater.retryAt, updater.autoCheck else { return message }
            return message + " Trying again at " + retry.formatted(date: .omitted, time: .shortened) + "."
        default:
            guard let date = updater.lastChecked else { return "Not checked yet" }
            return "Checked " + date.formatted(.relative(presentation: .named))
        }
    }
}

/// What's new in the available version, then Update and Restart (or Later).
struct WhatsNewSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    private var updater: AppUpdater { AppUpdater.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let release = updater.available {
                HStack(spacing: 10) {
                    Image("MenuBarIcon").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 24, height: 24).foregroundStyle(settings.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zephydian \(release.version)").font(.title3.bold())
                        Text("You have \(AppUpdater.currentVersion)").font(.callout).foregroundStyle(.secondary)
                    }
                }
                ScrollView {
                    Text(Self.notes(release.notes))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 220)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                Link("See it on GitHub", destination: release.pageURL).font(.callout)
                VStack(alignment: .leading, spacing: 4) {
                    if AppUpdater.homebrew != nil {
                        Text("Installed with Homebrew: this runs `brew upgrade zephydian` for you.")
                    }
                    Text("Until Zephydian is signed, macOS may ask for its permissions again after the update.")
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                progress
                HStack {
                    Spacer()
                    Button("Later") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(busy)
                    Button("Update and Restart") { Task { await updater.installUpdate() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy)
                }
            } else {
                Text("Zephydian is up to date.").font(.headline)
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var busy: Bool {
        switch updater.install {
        case .downloading, .installing: true
        default: false
        }
    }

    @ViewBuilder private var progress: some View {
        switch updater.install {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading…").font(.callout)
                ProgressView(value: fraction)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(AppUpdater.homebrew != nil ? "Homebrew is updating Zephydian…" : "Installing…").font(.callout)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .none:
            EmptyView()
        }
    }

    /// The notes as formatted text: the CHANGELOG's "### Added" headings in bold, "- " items as bullets,
    /// and its inline Markdown (bold, code, links).
    static func notes(_ text: String) -> AttributedString {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            if line.hasPrefix("### ") { return "**" + line.dropFirst(4) + "**" }
            if line.hasPrefix("- ") { return "•  " + line.dropFirst(2) }
            return String(line)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let joined = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: joined, options: options)) ?? AttributedString(joined)
    }
}

/// The panel's Settings tab: a small accent banner while an update is waiting.
struct UpdateBanner: View {
    @Environment(SettingsStore.self) private var settings
    private var updater: AppUpdater { AppUpdater.shared }

    var body: some View {
        if let release = updater.available {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(settings.accentColor)
                    .accessibilityHidden(true)
                Text("Zephydian \(release.version) is available")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 6)
                Button("Update…") { updater.requestWhatsNew() }
                    .prominentButtonStyle()
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(settings.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
