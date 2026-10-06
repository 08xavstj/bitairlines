import Foundation

/// Every sound effect the game makes. They are all synthesised on the device (see `ChipSynth`): the game ships no audio files.
enum SoundEffect: String, CaseIterable, Sendable {
    /// A button pressed.
    case tap
    /// Money changing hands: buying, selling, a loan.
    case coin
    /// The game refused something.
    case denied
    /// A quiet heads-up: a delivery is ready, weather has closed a strip.
    case notice
    /// A problem that stops the game.
    case alarm
    /// A new aircraft arrives.
    case arrival
    case routeOpened
    /// A new certificate level.
    case levelUp
    case gameOver

    /// How loud it is next to the others (0...1).
    var gain: Float {
        switch self {
        case .tap: 0.5
        case .coin: 0.7
        case .denied: 0.7
        case .notice: 0.6
        case .alarm: 0.8
        case .arrival: 0.7
        case .routeOpened: 0.7
        case .levelUp: 0.85
        case .gameOver: 0.85
        }
    }

    /// When two cues land together only the more important one plays (higher first).
    var priority: Int {
        switch self {
        case .gameOver: 9
        case .alarm: 8
        case .levelUp: 7
        case .routeOpened: 6
        case .arrival: 5
        case .coin: 4
        case .denied: 3
        case .notice: 2
        case .tap: 1
        }
    }
}

enum MusicTheme: String, CaseIterable, Sendable {
    /// Title screen and the new-airline screens.
    case title
    /// Running an airline.
    case flying

    /// Music sits under the sound effects.
    var gain: Float {
        switch self { case .title: 0.5; case .flying: 0.35 }
    }
}
