import AppKit
import SwiftUI

/// Mines: clear the field without setting off a mine (Minesweeper-style gameplay, original name).
/// The first click is always safe and opens an area.
@Observable
final class MinesGame: GameSession {
    enum State { case ready, playing, paused, won, lost }

    enum Difficulty: String, CaseIterable, Identifiable {
        case easy, medium, hard
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var cols: Int { switch self { case .easy: 9; case .medium: 12; case .hard: 14 } }
        var rows: Int { switch self { case .easy: 9; case .medium: 14; case .hard: 16 } }
        var mines: Int { switch self { case .easy: 10; case .medium: 28; case .hard: 44 } }
        var bestKey: String { "mines.best.\(rawValue)" }
    }

    struct Cell: Hashable { var x: Int, y: Int }

    private(set) var state: State = .ready
    private(set) var mines: Set<Cell> = []
    private(set) var revealed: Set<Cell> = []
    private(set) var flagged: Set<Cell> = []
    /// The mine that went off.
    private(set) var exploded: Cell?
    private(set) var cursor = Cell(x: 4, y: 4)
    private(set) var seconds = 0
    private(set) var isNewBest = false
    @ObservationIgnored private let sounds = GameSoundBank("mines")
    var soundKey: String? { sounds.isAvailable ? sounds.key : nil }
    /// Safe squares opened (or wrong flags taken away) by Hint, and whether the mines were shown with Give up.
    private(set) var hintsUsed = 0
    private(set) var gaveUp = false
    var difficulty: Difficulty {
        didSet {
            UserDefaults.standard.set(difficulty.rawValue, forKey: "mines.difficulty")
            newGame()
        }
    }

    @ObservationIgnored private var loop: GameLoop!

    init() {
        difficulty = Difficulty(rawValue: UserDefaults.standard.string(forKey: "mines.difficulty") ?? "") ?? .easy
        loop = GameLoop(interval: .seconds(1)) { [weak self] in self?.seconds += 1 }
        newGame()
    }

    var cols: Int { difficulty.cols }
    var rows: Int { difficulty.rows }
    var minesLeft: Int { difficulty.mines - flagged.count }

    // MARK: GameSession

    var scoreText: String { "\(difficulty.title) · \(BestTime.format(seconds))" }
    var hint: String {
        switch state {
        case .won, .lost: "Enter: new game · Esc back"
        default: "Click reveal · right-click or F flag · arrows + Space · Esc back"
        }
    }
    var showsPauseButton: Bool { state == .playing || state == .paused }
    var isRunning: Bool { state == .playing }

    func pause() {
        sounds.stop()
        guard state == .playing else { return }
        state = .paused
        loop.stop()
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
        if state == .won || state == .lost {
            if event.keyCode == Key.enter || event.keyCode == Key.keypadEnter { newGame(); return true }
            return false
        }
        if state == .paused {
            if event.keyCode == Key.space { togglePause(); return true }
            return false
        }
        let moves: [UInt16: (Int, Int)] = [
            Key.left: (-1, 0), Key.a: (-1, 0), Key.right: (1, 0), Key.d: (1, 0),
            Key.up: (0, -1), Key.w: (0, -1), Key.down: (0, 1), Key.s: (0, 1),
        ]
        if let (dx, dy) = moves[event.keyCode] {
            cursor = Cell(x: min(max(cursor.x + dx, 0), cols - 1), y: min(max(cursor.y + dy, 0), rows - 1))
            return true
        }
        if [Key.space, Key.enter, Key.keypadEnter].contains(event.keyCode) { reveal(cursor); return true }
        if Key.letter(event) == "f" { toggleFlag(cursor); return true }
        return false
    }

    func makeView() -> AnyView { AnyView(MinesView(game: self)) }
    func makeHeaderAccessory() -> AnyView? { AnyView(MinesHeaderMenu(game: self)) }

    // The first click is always safe, so hints start once the field is open.
    var actions: [GameAction] {
        let open = state == .playing || state == .paused
        return [.hint(enabled: open, help: "Take away a wrong flag, or uncover a safe square"),
                .giveUp(enabled: open, daily: false, what: "where the mines are")]
    }

    func perform(_ action: String) {
        guard state == .playing || state == .paused else { return }
        if state == .paused { togglePause() }
        switch action {
        case "hint":
            if let wrong = flagged.first(where: { !mines.contains($0) }) {
                flagged.remove(wrong)
                cursor = wrong
            } else {
                // A safe square next to what's open; any safe square if none is.
                let all = (0..<rows).flatMap { y in (0..<cols).map { Cell(x: $0, y: y) } }
                let safe = all.filter { !mines.contains($0) && !revealed.contains($0) && !flagged.contains($0) }
                guard let cell = safe.first(where: { neighbors(of: $0).contains(where: revealed.contains) }) ?? safe.first else { return }
                cursor = cell
                open(cell)
                if revealed.count == cols * rows - mines.count { hintsUsed += 1; win(); return }
            }
            hintsUsed += 1
        case "giveUp":
            gaveUp = true
            flagged = flagged.filter(mines.contains)
            state = .lost
            loop.stop()
        default:
            break
        }
    }

    // MARK: Game logic

    func newGame() {
        loop.stop()
        mines = []
        revealed = []
        flagged = []
        exploded = nil
        seconds = 0
        isNewBest = false
        hintsUsed = 0
        gaveUp = false
        cursor = Cell(x: cols / 2, y: rows / 2)
        state = .ready
    }

    /// Reveals a cell. On an already-revealed number whose flags are all placed, reveals its other neighbors ("chording").
    func reveal(_ cell: Cell) {
        guard state == .ready || state == .playing, !flagged.contains(cell) else { return }
        cursor = cell
        if state == .ready {
            placeMines(avoiding: cell)
            state = .playing
            loop.start()
            GameStats.started("mines")   // the first click starts the game
        }
        if revealed.contains(cell) {
            let around = neighbors(of: cell)
            guard adjacentMines(cell) > 0, around.filter(flagged.contains).count == adjacentMines(cell) else { return }
            for n in around where !flagged.contains(n) && !revealed.contains(n) {
                open(n)
                if state == .lost { return }
            }
        } else {
            let before = revealed.count
            open(cell)
            if state == .playing { sounds.play(revealed.count - before > 1 ? "area" : "open", volume: 0.7) }
        }
        if state == .playing, revealed.count == cols * rows - mines.count { win() }
    }

    func toggleFlag(_ cell: Cell) {
        guard state == .ready || state == .playing, !revealed.contains(cell) else { return }
        cursor = cell
        if flagged.contains(cell) { flagged.remove(cell) } else { flagged.insert(cell) }
        sounds.play("flag", volume: 0.7)
    }

    func adjacentMines(_ cell: Cell) -> Int { neighbors(of: cell).filter(mines.contains).count }

    func neighbors(of cell: Cell) -> [Cell] {
        (-1...1).flatMap { dy in (-1...1).map { dx in Cell(x: cell.x + dx, y: cell.y + dy) } }
            .filter { $0 != cell && $0.x >= 0 && $0.y >= 0 && $0.x < cols && $0.y < rows }
    }

    /// Opens a cell, flood-filling outward from cells with no mines around them.
    private func open(_ cell: Cell) {
        if mines.contains(cell) {
            exploded = cell
            state = .lost
            loop.stop()
            sounds.play("boom")
            return
        }
        var stack = [cell]
        while let c = stack.popLast() {
            guard !revealed.contains(c), !flagged.contains(c) else { continue }
            revealed.insert(c)
            if adjacentMines(c) == 0 { stack.append(contentsOf: neighbors(of: c).filter { !revealed.contains($0) }) }
        }
    }

    /// Mines are placed on the first click, never on or next to it, so the game always opens with an area.
    private func placeMines(avoiding first: Cell) {
        let safe = Set(neighbors(of: first) + [first])
        let candidates = (0..<rows).flatMap { y in (0..<cols).map { Cell(x: $0, y: y) } }.filter { !safe.contains($0) }
        mines = Set(candidates.shuffled().prefix(difficulty.mines))
    }

    private func win() {
        state = .won
        loop.stop()
        sounds.play("win")
        flagged = mines
        isNewBest = BestTime.record(seconds, for: difficulty.bestKey)
        GameStats.won("mines")
    }

    static var tileStat: String {
        let difficulty = Difficulty(rawValue: UserDefaults.standard.string(forKey: "mines.difficulty") ?? "") ?? .easy
        let best = BestTime.get(difficulty.bestKey)
        return best > 0 ? "Best \(BestTime.format(best))" : "Not played"
    }
}
