import SwiftUI

/// Applying a preset: what it changes, one confirmation, then the utilities it adds, downloaded
/// one after another from the Library. Nothing is ever removed.
@Observable
final class PresetRun: Identifiable {
    enum Phase: Equatable {
        case loading
        case ready
        case installing(done: Int, total: Int)
        case finished(failed: [String])
    }

    let preset: FeaturePreset
    private(set) var phase: Phase = .loading
    /// Utilities it adds (not installed yet).
    private(set) var additions: [PackCatalog.Entry] = []
    /// The Library couldn't be reached, so no utilities can be added now.
    private(set) var libraryUnavailable = false

    private var features: Features { Features.shared }
    private var packs: PackManager { PackManager.shared }

    init(_ preset: FeaturePreset) { self.preset = preset }

    var featuresOn: [Feature] {
        let ids = preset.featureIDs(in: features.all)
        return features.all.filter { ids.contains($0.id) && !features.isOn($0.id) }
    }

    var featuresOff: [Feature] {
        let ids = preset.featureIDs(in: features.all)
        return features.all.filter { !ids.contains($0.id) && features.isOn($0.id) }
    }

    /// Reads the Library (or its last copy) for the utilities still missing.
    func prepare() async {
        if packs.catalog == nil { await packs.loadCatalog() }
        guard let catalog = packs.catalog else {
            libraryUnavailable = true
            phase = .ready
            return
        }
        let wanted = preset.utilityIDs.map(Set.init)
        additions = catalog.packs.filter { entry in
            entry.kind == "utility" && (wanted?.contains(entry.id) ?? true)
                && packs.installed[entry.id] == nil && entry.sdkVersion <= PackBundle.sdkVersion
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        phase = .ready
    }

    /// Switches the features (unless the caller does it later) and installs the utilities.
    func run(applyFeatures: Bool = true) async {
        if applyFeatures { features.apply(preset) }
        var failed: [String] = []
        for (index, entry) in additions.enumerated() {
            phase = .installing(done: index, total: additions.count)
            await packs.install(entry)
            if packs.installed[entry.id] == nil { failed.append(entry.name) }
        }
        phase = .finished(failed: failed)
    }
}

/// The three preset cards at the top of the Features page (Vorssaint-style tiles), and Turn All Off.
struct PresetCards: View {
    @State private var run: PresetRun?
    @Environment(SettingsStore.self) private var settings
    private var features: Features { Features.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(FeaturePreset.allCases) { preset in
                    card(preset)
                }
            }
            HStack {
                Spacer()
                Button("Turn All Off") { features.turnAllOff() }
                    .disabled(features.enabled.isEmpty)
            }
        }
        .sheet(item: $run) { run in
            PresetConfirmView(run: run, onClose: { self.run = nil })
                .frame(width: 420)
        }
    }

    private func card(_ preset: FeaturePreset) -> some View {
        let current = features.matchingPreset == preset
        return Button { run = PresetRun(preset) } label: {
            VStack(spacing: 6) {
                Image(systemName: preset.symbol).font(.system(size: 20, weight: .medium))
                Text(preset.title).font(.system(size: 12, weight: .semibold))
                Text(preset.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(10)
            .foregroundStyle(current ? settings.accentColor : .primary)
            .background(current ? settings.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(current ? settings.accentColor.opacity(0.7) : .clear, lineWidth: 1) }
            .overlay(alignment: .topTrailing) {
                if current {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(settings.accentColor)
                        .padding(7)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(preset.summary)
        .accessibilityLabel("\(preset.title) preset")
        .accessibilityValue(current ? "Current" : "")
        .accessibilityHint(preset.summary)
    }
}

/// "Use Essential?": what it switches on and off and the utilities it adds (with what each can do),
/// then the downloads' progress and anything that failed.
struct PresetConfirmView: View {
    let run: PresetRun
    /// The welcome tour switches the features itself once its panel has closed.
    var appliesFeatures = true
    /// Called when Use is pressed (the welcome tour notes that the tour is done).
    var onConfirmed: () -> Void = {}
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Use \(run.preset.title)?", systemImage: run.preset.symbol)
                .font(.headline)
            switch run.phase {
            case .loading:
                ProgressView("Reading the Library…").controlSize(.small)
            case .ready:
                details
            case .installing(let done, let total):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Adding utilities… \(done + 1) of \(total)").font(.callout)
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                }
            case .finished(let failed):
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(run.preset.title) is on.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if !failed.isEmpty {
                        Text("Couldn't add \(failed.formatted(.list(type: .and))). Try again from the Library.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                switch run.phase {
                case .loading, .ready:
                    Button("Cancel", role: .cancel, action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Button("Use \(run.preset.title)") {
                        onConfirmed()
                        Task { await run.run(applyFeatures: appliesFeatures) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(run.phase == .loading)
                case .installing:
                    EmptyView()
                case .finished:
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .task { if run.phase == .loading { await run.prepare() } }
    }

    @ViewBuilder private var details: some View {
        let on = run.featuresOn.count, off = run.featuresOff.count
        VStack(alignment: .leading, spacing: 10) {
            Text(featureLine(on: on, off: off)).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if run.libraryUnavailable {
                Text("The Library can't be reached right now, so no utilities are added. Add them later from the Library.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if run.additions.isEmpty {
                Text("Its utilities are already installed.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Adds \(run.additions.count) \(run.additions.count == 1 ? "utility" : "utilities") from the Library:")
                    .font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        let withAccess = run.additions.filter { !PackCapability.list($0.capabilities).isEmpty }
                        let plain = run.additions.filter { PackCapability.list($0.capabilities).isEmpty }
                        ForEach(withAccess) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.name).font(.callout.weight(.medium)).frame(width: 110, alignment: .leading)
                                Text(PackCapability.list(entry.capabilities).map(\.short).joined(separator: ", "))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        if !plain.isEmpty {
                            Text(plain.map(\.name).joined(separator: ", ") + " (no access needed)")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            Text("Nothing is removed: features it doesn't include switch off and keep their settings, and your utilities and games stay.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureLine(on: Int, off: Int) -> String {
        switch (on, off) {
        case (0, 0): "Its features are already set."
        case (_, 0): "Switches on \(on) \(on == 1 ? "feature" : "features")."
        case (0, _): "Switches off \(off) \(off == 1 ? "feature" : "features")."
        default: "Switches on \(on) \(on == 1 ? "feature" : "features") and off \(off)."
        }
    }
}
