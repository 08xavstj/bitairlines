import Foundation

/// Money that just came in from flights and jobs, shown as "+$1.2K" next to the bank total.
struct Payout: Equatable {
    /// A new id starts a new tag; the same id with a bigger amount updates the one on screen.
    let id: Int
    let amount: Int
    let shownAt: Date

    /// Payments closer together than this are added to the tag already showing.
    static let mergeSeconds = 1.0
    /// How long the tag stays before it fades.
    static let showSeconds = 1.6
}
