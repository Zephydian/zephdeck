import SwiftUI

/// The shared game chrome: back · name · score · pause, the game, and a hint line.
struct GameScreen: View {
    /// False in a game or utility tab, which has nothing to go back to.
    var showsBack = true
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    /// Redraws the speaker after it's used (a game's own switch isn't observable).
    @State private var soundTick = 0

    var body: some View {
        if let session = model.gameSession, let info = GameRegistry.info(for: model.gameID) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    if showsBack {
                        Button { model.closeGame() } label: {
                            Image(systemName: "chevron.left")
                        }
                        .glassIconButtonStyle()
                        .help("Back to \(model.backDestination) (Esc)")
                        .accessibilityLabel("Back to \(model.backDestination)")
                    } else {
                        Spacer().frame(width: 6)
                    }

                    Text(info.name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    // The menu and pause button are both glass controls, so they share one glass group.
                    GlassGroup(spacing: 6) {
                        HStack(spacing: 6) {
                            if let accessory = session.makeHeaderAccessory() {
                                accessory
                            } else {
                                Text(session.scoreText)
                                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Score: \(session.scoreText)")
                            }

                            // A game with sounds: the speaker shows whether it will play (Game sounds in
                            // Settings and the game's own switch), and switches it.
                            if let key = session.soundKey {
                                // Reading these redraws the button when they change (a pack's own Sound
                                // switch, or the speaker itself).
                                let _ = (session as? PackSession)?.isSoundOn
                                let _ = soundTick
                                let on = settings.gameSounds && GameSounds.gameOn(key)
                                Button {
                                    session.setSound(!on)
                                    soundTick += 1
                                } label: {
                                    Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                }
                                .glassIconButtonStyle()
                                .help(on ? "Turn sound off" : "Turn sound on")
                                .accessibilityLabel(on ? "Sound on" : "Sound off")
                            }

                            // A utility with a settings page (SDK 5): the gear opens it in the Settings window.
                            if let pack = (session as? PackSession)?.bundle, pack.hasSettings {
                                Button { model.openSettingsWindow(SettingsSelection.utility(pack.id).rawValue) } label: {
                                    Image(systemName: "gearshape")
                                }
                                .glassIconButtonStyle()
                                .help("\(pack.manifest.name) settings")
                                .accessibilityLabel("\(pack.manifest.name) settings")
                            }

                            // How to play (games only; a utility's is on its Settings page).
                            if info.howTo != nil {
                                Button { showHowTo(session) } label: {
                                    Image(systemName: "info.circle")
                                }
                                .glassIconButtonStyle()
                                .help("How to play \(info.name)")
                                .accessibilityLabel("How to play \(info.name)")
                            }

                            if session.showsPauseButton {
                                Button { session.togglePause() } label: {
                                    Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                                }
                                .glassIconButtonStyle()
                                .accessibilityLabel(session.isRunning ? "Pause" : "Resume")
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 44)

                session.makeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A new session for the same game (a reloaded pack, opened again by its shortcut
                    // while still on screen) gets a new view, so it appears and starts.
                    .id(ObjectIdentifier(session))
                    .overlay {
                        if model.isShowingHowTo, let howTo = info.howTo {
                            HowToPlayCard(name: info.name, howTo: howTo) { model.isShowingHowTo = false }
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: model.isShowingHowTo)

                let actions = session.actions
                if !actions.isEmpty {
                    GameActionBar(actions: actions, perform: session.perform)
                        .padding(.top, 6)
                }

                if !session.hint.isEmpty {
                    Text(session.hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                }
            }
            // The first time a game opens, its How to play card comes up by itself.
            .task(id: model.gameID) {
                guard info.howTo != nil, let id = model.gameID else { return }
                let key = "howto.seen.\(id)"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    showHowTo(session)
                }
            }
        }
    }

    private func showHowTo(_ session: any GameSession) {
        session.pause()
        model.isShowingHowTo = true
    }
}
