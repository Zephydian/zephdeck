import AppKit
import SwiftUI

/// Nines: fill the grid so every row, column and 3×3 box has 1–9 once (Sudoku-style gameplay, original name).
/// Every puzzle is freshly generated with exactly one solution. The game in progress is saved, so it survives relaunches.
@Observable
final class NinesGame: GameSession {
    enum State { case loading, playing, paused, won }

    nonisolated enum Difficulty: String, CaseIterable, Identifiable, Codable, Sendable {
        case easy, medium, hard
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var bestKey: String { "nines.best.\(rawValue)" }
    }

    private(set) var state: State = .loading
    private(set) var difficulty: Difficulty
    private(set) var puzzle: NinesPuzzle?
    /// The player's numbers (0 = empty). Givens live in `puzzle`.
    private(set) var entries = Array(repeating: 0, count: 81)
    /// Pencil marks: bit `d` set = note for digit d.
    private(set) var notes = Array(repeating: 0, count: 81)
    private(set) var selected = 40
    private(set) var seconds = 0
    private(set) var isNewBest = false
    /// Numbers filled in by Hint, and whether the solution was shown with Give up.
    private(set) var hintsUsed = 0
    private(set) var gaveUp = false
    var notesMode = false

    private static let saveKey = "nines.saved"
    @ObservationIgnored private var loop: GameLoop!
    @ObservationIgnored private var undoStack: [(entries: [Int], notes: [Int])] = []
    @ObservationIgnored private var generateTask: Task<Void, Never>?
    @ObservationIgnored private let sounds = GameSoundBank("nines")
    var soundKey: String? { sounds.isAvailable ? sounds.key : nil }

    init() {
        difficulty = Difficulty(rawValue: UserDefaults.standard.string(forKey: "nines.difficulty") ?? "") ?? .easy
        loop = GameLoop(interval: .seconds(1)) { [weak self] in self?.tick() }
        if !restore() { newGame() }
    }

    // MARK: GameSession

    var scoreText: String { "\(difficulty.title) · \(BestTime.format(seconds))" }
    var hint: String {
        switch state {
        case .won: "Enter: new game · Esc back"
        default: "1–9 fill · N notes · ⌫ erase · ⌘Z undo · Space pause · Esc back"
        }
    }
    var showsPauseButton: Bool { state == .playing || state == .paused }
    var isRunning: Bool { state == .playing }

    func pause() {
        sounds.stop()
        guard state == .playing else { return }
        state = .paused
        loop.stop()
        save()
    }

    func togglePause() {
        if state == .playing {
            pause()
        } else if state == .paused {
            state = .playing
            loop.start()
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        switch state {
        case .won:
            if event.keyCode == Key.enter || event.keyCode == Key.keypadEnter { newGame(); return true }
            return false
        case .paused:
            if event.keyCode == Key.space { togglePause(); return true }
            return false
        case .loading:
            return false
        case .playing:
            break
        }
        let moves: [UInt16: (Int, Int)] = [
            Key.left: (-1, 0), Key.a: (-1, 0), Key.right: (1, 0), Key.d: (1, 0),
            Key.up: (0, -1), Key.w: (0, -1), Key.down: (0, 1), Key.s: (0, 1),
        ]
        if let (dx, dy) = moves[event.keyCode] {
            let row = (selected / 9 + dy + 9) % 9, col = (selected % 9 + dx + 9) % 9
            selected = row * 9 + col
            return true
        }
        switch event.keyCode {
        case Key.space: togglePause(); return true
        case Key.delete, Key.forwardDelete: erase(); return true
        default: break
        }
        guard let key = Key.letter(event) else { return false }
        if key == "n" { notesMode.toggle(); return true }
        if key == "0" { erase(); return true }
        if let digit = Int(key), (1...9).contains(digit) { enter(digit); return true }
        return false
    }

    func undo() -> Bool {
        guard state == .playing, let last = undoStack.popLast() else { return false }
        entries = last.entries
        notes = last.notes
        save()
        return true
    }

    var actions: [GameAction] {
        let open = state == .playing || state == .paused
        return [.hint(enabled: open, help: "Fill in one right number: the selected square if it's empty or wrong"),
                .giveUp(enabled: open, daily: false)]
    }

    func perform(_ action: String) {
        guard let puzzle, state == .playing || state == .paused else { return }
        if state == .paused { togglePause() }
        switch action {
        case "hint":
            // The selected square if it isn't right yet; otherwise the first wrong one, then the first empty one.
            let open = { (cell: Int) in !self.isGiven(cell) && self.entries[cell] != puzzle.solution[cell] }
            let cell = open(selected) ? selected
                : (0..<81).first { open($0) && self.entries[$0] != 0 } ?? (0..<81).first(where: open)
            guard let cell else { return }
            pushUndo()
            selected = cell
            entries[cell] = puzzle.solution[cell]
            notes[cell] = 0
            for peer in NinesGenerator.peers[cell] { notes[peer] &= ~(1 << puzzle.solution[cell]) }
            hintsUsed += 1
            if (0..<81).allSatisfy({ value(at: $0) == puzzle.solution[$0] }) { win() } else { save() }
        case "giveUp":
            for cell in 0..<81 where !isGiven(cell) { entries[cell] = puzzle.solution[cell] }
            notes = Array(repeating: 0, count: 81)
            gaveUp = true
            state = .won
            loop.stop()
            UserDefaults.standard.removeObject(forKey: Self.saveKey)
        default:
            break
        }
    }

    func makeView() -> AnyView { AnyView(NinesView(game: self)) }
    func makeHeaderAccessory() -> AnyView? { AnyView(NinesHeaderMenu(game: self)) }

    // MARK: Board

    func value(at cell: Int) -> Int {
        guard let puzzle else { return 0 }
        return puzzle.givens[cell] != 0 ? puzzle.givens[cell] : entries[cell]
    }

    func isGiven(_ cell: Int) -> Bool { puzzle?.givens[cell] ?? 0 != 0 }

    /// Cells whose number repeats in their row, column or box.
    var conflicts: Set<Int> {
        var result = Set<Int>()
        for cell in 0..<81 {
            let v = value(at: cell)
            guard v != 0 else { continue }
            if NinesGenerator.peers[cell].contains(where: { value(at: $0) == v }) { result.insert(cell) }
        }
        return result
    }

    /// How many of each digit are on the board (index 1–9).
    var digitCounts: [Int] {
        var counts = Array(repeating: 0, count: 10)
        for cell in 0..<81 { counts[value(at: cell)] += 1 }
        return counts
    }

    // MARK: Actions

    func select(_ cell: Int) {
        guard state == .playing else { return }
        selected = cell
    }

    /// Places a digit, or toggles a pencil mark in notes mode.
    func enter(_ digit: Int) {
        guard state == .playing, !isGiven(selected) else { return }
        pushUndo()
        if notesMode {
            guard entries[selected] == 0 else { undoStack.removeLast(); return }
            notes[selected] ^= 1 << digit
            sounds.play("note", volume: 0.6)
        } else if entries[selected] == digit {
            entries[selected] = 0
            sounds.play("erase", volume: 0.7)
        } else {
            entries[selected] = digit
            notes[selected] = 0
            // The digit can't go anywhere else in this row, column or box any more.
            for peer in NinesGenerator.peers[selected] { notes[peer] &= ~(1 << digit) }
            // A number that repeats in its row, column or box gets the clash sound.
            sounds.play(conflicts.contains(selected) ? "clash" : "place", volume: 0.8)
        }
        if let puzzle, (0..<81).allSatisfy({ value(at: $0) == puzzle.solution[$0] }) {
            win()
        } else {
            save()
        }
    }

    func erase() {
        guard state == .playing, !isGiven(selected), entries[selected] != 0 || notes[selected] != 0 else { return }
        pushUndo()
        entries[selected] = 0
        notes[selected] = 0
        sounds.play("erase", volume: 0.7)
        save()
    }

    func newGame(_ newDifficulty: Difficulty? = nil) {
        if let newDifficulty {
            difficulty = newDifficulty
            UserDefaults.standard.set(newDifficulty.rawValue, forKey: "nines.difficulty")
        }
        loop.stop()
        generateTask?.cancel()
        state = .loading
        puzzle = nil
        entries = Array(repeating: 0, count: 81)
        notes = Array(repeating: 0, count: 81)
        undoStack = []
        seconds = 0
        isNewBest = false
        hintsUsed = 0
        gaveUp = false
        notesMode = false
        let difficulty = difficulty
        // Generating takes a moment, so it runs off the main thread.
        generateTask = Task { [weak self] in
            let puzzle = await Task.detached(priority: .userInitiated) { NinesGenerator.make(difficulty) }.value
            guard let self, !Task.isCancelled else { return }
            self.puzzle = puzzle
            self.selected = (0..<81).first { puzzle.givens[$0] == 0 } ?? 40
            self.state = .playing
            self.loop.start()
            self.save()
            GameStats.started("nines")
        }
    }

    private func pushUndo() {
        undoStack.append((entries, notes))
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    private func tick() {
        seconds += 1
        if seconds % 10 == 0 { save() }
    }

    private func win() {
        state = .won
        loop.stop()
        sounds.play("win")
        isNewBest = BestTime.record(seconds, for: difficulty.bestKey)
        UserDefaults.standard.removeObject(forKey: Self.saveKey)
        GameStats.won("nines")
    }

    // MARK: Saving

    private struct Saved: Codable {
        var difficulty: Difficulty
        var puzzle: NinesPuzzle
        var entries: [Int]
        var notes: [Int]
        var seconds: Int
        var hints: Int?
    }

    private func save() {
        guard let puzzle, state != .won else { return }
        let saved = Saved(difficulty: difficulty, puzzle: puzzle, entries: entries, notes: notes, seconds: seconds, hints: hintsUsed)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.saveKey)
    }

    /// Restores a saved game, paused, so the clock doesn't run until you're back.
    private func restore() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.puzzle.givens.count == 81, saved.entries.count == 81, saved.notes.count == 81 else { return false }
        difficulty = saved.difficulty
        puzzle = saved.puzzle
        entries = saved.entries
        notes = saved.notes
        seconds = saved.seconds
        hintsUsed = saved.hints ?? 0
        selected = (0..<81).first { value(at: $0) == 0 } ?? 40
        state = .paused
        return true
    }

    static var tileStat: String {
        let difficulty = Difficulty(rawValue: UserDefaults.standard.string(forKey: "nines.difficulty") ?? "") ?? .easy
        let best = BestTime.get(difficulty.bestKey)
        return best > 0 ? "Best \(BestTime.format(best))" : "Not played"
    }
}
