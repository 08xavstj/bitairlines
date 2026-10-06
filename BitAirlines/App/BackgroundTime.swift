import UIKit

/// A little time from iOS to finish a write after the app goes to the background. The time is given back when the work is done,
/// or as soon as iOS asks for it back (if it is not given back then, iOS ends the app instead of suspending it).
final class BackgroundTime: @unchecked Sendable {
    /// Only read and changed on the main thread, after `init`.
    private var id = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.finish() }
    }

    /// Gives the time back. Can be called from any thread, and more than once.
    func end() {
        DispatchQueue.main.async { self.finish() }
    }

    private func finish() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
