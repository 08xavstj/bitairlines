import SwiftUI

/// Animation that respects the iPhone's Reduce Motion setting: with it on, changes happen at once and nothing slides, dissolves or flickers.
enum Motion {
    static var reduced: Bool { Platform.reduceMotion }

    /// `withAnimation`, skipped when Reduce Motion is on.
    @discardableResult
    static func animate<R>(_ animation: Animation? = .default, _ body: () throws -> R) rethrows -> R {
        try withAnimation(reduced ? nil : animation, body)
    }

    /// An animation to attach with `.animation(_:value:)`, or nil when Reduce Motion is on.
    static func animation(_ animation: Animation) -> Animation? { reduced ? nil : animation }
}
