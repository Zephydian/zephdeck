import Foundation

/// A game pack's sounds (SDK 10): short files from its `assets/`, played while it's on screen and
/// game sounds are on (`GameSounds`: the switch in Settings and the game's speaker).
final class PackSound {
    private let bundle: PackBundle
    private lazy var player = SoundPlayer { [bundle] name in bundle.assetURL(name) }

    init(bundle: PackBundle) { self.bundle = bundle }

    static func key(_ packID: String) -> String { "pack.\(packID).sound" }
    var key: String { Self.key(bundle.id) }
    var isOn: Bool { GameSounds.isOn(key) }

    func setOn(_ on: Bool) {
        GameSounds.set(key, on: on)
        if !on { stop() }
    }

    func play(_ name: String, volume: Double) {
        guard isOn else { return }
        player.play(name, volume: volume)
    }

    func preload(_ names: [String]) {
        guard isOn else { return }
        player.preload(names)
    }

    func stop() { player.stop() }
}
