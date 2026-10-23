import SwiftUI

/// The Games tab: a row with Stats and Get more, then 3-column grids of game tiles under section
/// headings (Arcade, Puzzles, Words; empty sections are left out).
/// Reopening a paused game's tile resumes it where you left off.
struct HomeGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(PackLibrary.self) private var packs
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let games = GameRegistry.all
        VStack(spacing: 10) {
            if !settings.featuresIntroSeen, !Features.shared.all.isEmpty {
                FeaturesIntroCard()
                    .padding(.horizontal, 16)
            }
            GridToolbar(count: games.count, noun: "game") {
                GridToolbarButton(title: "Stats", symbol: "chart.bar.fill", help: "Games played, wins, best scores and streaks") {
                    model.openStats()
                }
                GridToolbarButton(title: "Get more", symbol: "plus", help: "Get more games from the Library") {
                    model.openLibrary(.game)
                }
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    let sections = GameCategory.allCases.filter { category in games.contains { $0.category == category } }
                    ForEach(sections, id: \.self) { category in
                        Section {
                            ForEach(games.filter { $0.category == category }) { info in
                                GameTile(info: info) { model.openGame(info.id) }
                            }
                        } header: {
                            GameSectionHeader(title: category.title)
                                .padding(.top, category == sections.first ? 0 : 6)
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .contentMargins(.bottom, 16, for: .scrollContent)
        }
        .onAppear { packs.refresh() }
        .onChange(of: model.panelOpenCount) { packs.refresh() }
    }
}

/// A section's heading above its tiles or Library rows, in the style of the Settings sections.
struct GameSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Shown once to people who updated from a version without Features (new people meet them in the welcome tour).
private struct FeaturesIntroCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("New: Features").font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: "switch.2").foregroundStyle(.tint)
            }
            Text("Zephdeck can now add features to macOS, like window previews in the Dock and a better ⌘Tab. Switch on the ones you want.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Not Now") { settings.featuresIntroSeen = true }
                    .panelButtonStyle()
                Button("Set Up") {
                    settings.featuresIntroSeen = true
                    model.openSettingsWindow(SettingsPage.features.rawValue)
                }
                .prominentButtonStyle()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous).fill(Tokens.fill))
    }
}
