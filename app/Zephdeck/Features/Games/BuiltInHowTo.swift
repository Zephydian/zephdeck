import Foundation

/// How to play the games built into the app (packs bring theirs in manifest.json).
extension HowToPlay {
    static let builtIn: [String: HowToPlay] = [
        "snake": HowToPlay(
            goal: "Steer the snake to eat the food. Each bite makes it longer.",
            rules: ["Running into a wall or your own tail ends the game.", "The longer you get, the faster it goes."],
            controls: [["←↑↓→ or WASD", "Turn"], ["Space", "Pause"], ["R", "Restart"]]),
        "stackr": HowToPlay(
            goal: "Fit the falling blocks together to fill whole rows.",
            rules: ["A full row clears and scores points; clearing several at once scores more.",
                    "The blocks fall faster as you level up.", "The game ends when the blocks reach the top."],
            controls: [["← →", "Move"], ["↑", "Rotate"], ["↓", "Drop faster"], ["Space", "Drop now"], ["C", "Hold a block for later"], ["P", "Pause"]]),
        "five": HowToPlay(
            goal: "Guess the five-letter word in six tries.",
            rules: ["Green: the letter is in the right spot.", "Yellow: it's in the word, in another spot.",
                    "Grey: it isn't in the word.", "The daily word is the same for everyone; practice words are endless."],
            controls: [["Type", "Letters"], ["Enter", "Guess"], ["⌫", "Delete"], ["?", "Hint: one letter in its spot"]]),
        "wheel": HowToPlay(
            goal: "Make words from the letters around the wheel to fill the crossword.",
            rules: ["Words use each letter once and need at least three letters.",
                    "Extra real words count as bonus words.", "Fill every word to finish the level."],
            controls: [["Type or drag", "Spell a word"], ["Enter", "Submit"], ["Space", "Shuffle the wheel"], ["?", "Hint: one letter"]]),
        "fleet": HowToPlay(
            goal: "Sink the computer's hidden ships before it sinks yours.",
            rules: ["First place your ships, then take turns firing at a square.",
                    "A hit lets you keep looking nearby; a ship sinks when every square of it is hit."],
            controls: [["Drag", "Move a ship (while placing)"], ["Click", "Rotate (while placing) or fire"], ["Space", "Shuffle ships, or fire"], ["Enter", "Start the battle"]]),
        "airship": HowToPlay(
            goal: "Fly through an endless sky, dodging and shooting what comes at you.",
            rules: ["Getting hit costs a life.", "Shoot enemies for points; it gets busier as you go."],
            controls: [["←↑↓→ or WASD", "Fly"], ["Hold Space", "Fire"], ["Mouse", "Fly and fire"], ["P", "Pause"]]),
        "2048": HowToPlay(
            goal: "Slide the tiles so equal numbers merge, and reach 2048.",
            rules: ["Every slide moves all tiles as far as they go, and a new tile appears.",
                    "Two equal tiles that touch merge into their sum.", "The game ends when no move is left."],
            controls: [["←↑↓→ or WASD", "Slide"], ["Drag", "Slide"]]),
        "mines": HowToPlay(
            goal: "Uncover every safe square without setting off a mine.",
            rules: ["A number tells how many mines touch that square, diagonals included.",
                    "Flag the squares you're sure hide a mine.", "Your first click is always safe."],
            controls: [["Click", "Uncover"], ["Right-click or F", "Flag"], ["Arrows + Space", "Move and uncover"]]),
        "nines": HowToPlay(
            goal: "Fill the grid so every row, column and 3×3 box has 1 to 9 once.",
            rules: ["The starting numbers can't change.", "Notes help you keep track of what a square could be."],
            controls: [["Click or arrows", "Pick a square"], ["1–9", "Fill in"], ["N", "Notes on or off"], ["⌫", "Erase"], ["⌘Z", "Undo"]]),
    ]
}
