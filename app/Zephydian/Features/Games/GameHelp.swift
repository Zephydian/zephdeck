import SwiftUI

/// A game's How to play card, over the board: the goal, the rules and the controls, with Got it.
/// Like the other game cards, a floating glass card in Liquid Glass mode and a frosted cover in Frosted.
struct HowToPlayCard: View {
    let name: String
    let howTo: HowToPlay
    let close: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if #available(macOS 26, *), settings.usesGlass {
            card
                .frame(maxWidth: 320)
                .glassSurface(in: RoundedRectangle(cornerRadius: Tokens.overlayRadius, style: .continuous))
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.18)))
                .transition(.opacity)
        } else {
            card
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to play \(name)").font(.system(size: 17, weight: .bold))
            ScrollView {
                HowToPlayText(howTo: howTo)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack {
                Spacer()
                Button("Got it", action: close)
                    .prominentButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How to play \(name)")
    }
}

/// The goal, rules and controls as text. Shared by the ⓘ card and a utility's Settings page.
struct HowToPlayText: View {
    let howTo: HowToPlay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(howTo.goal).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            if let rules = howTo.rules, !rules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(rule).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.system(size: 12.5))
            }
            if let controls = howTo.controls?.filter({ $0.count == 2 }), !controls.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(Array(controls.enumerated()), id: \.offset) { _, pair in
                        GridRow {
                            Text(pair[0]).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            Text(pair[1]).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// Hint, Give up and the like, as small capsules under the board (the same look as Five's).
/// An action with `confirm` asks first.
struct GameActionBar: View {
    let actions: [GameAction]
    let perform: (String) -> Void
    @State private var confirming: GameAction?

    var body: some View {
        HStack {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 { Spacer() }
                Button {
                    if action.confirm != nil { confirming = action } else { perform(action.id) }
                } label: {
                    Label(action.label, systemImage: action.symbol)
                }
                .disabled(!action.enabled)
                .help(action.help ?? action.label)
            }
        }
        .buttonStyle(GamePillStyle())
        .padding(.horizontal, 16)
        .frame(height: 26)
        .alert(confirming?.confirm?.title ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            if let action = confirming, let confirm = action.confirm {
                Button(confirm.button, role: .destructive) { perform(action.id) }
                Button("Keep Trying", role: .cancel) {}
            }
        } message: {
            Text(confirming?.confirm?.message ?? "")
        }
    }
}

/// Small capsule buttons for Hint / Give up.
struct GamePillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(configuration.isPressed ? Tokens.fillHover.opacity(2) : Tokens.fillHover))
            .foregroundStyle(.secondary)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}
