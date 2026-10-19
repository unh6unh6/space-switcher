import AppKit
import os

/// Text fields in our non-activating panels need the app to be active. This borrows the keyboard
/// and later hands it back to whichever app the user was in (#7: not `NSApp.hide`, which would also
/// hide the panel). Shared by the switcher's inline editors and the memo overlay.
final class FocusReturner {
    private var borrowed = false
    private var previous: NSRunningApplication?

    /// Between `take` and `release`/`giveBack`: the user clicked in to type.
    var isBorrowing: Bool { borrowed }

    func take(for window: NSWindow) {
        if !borrowed {
            let front = NSWorkspace.shared.frontmostApplication
            previous = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        }
        borrowed = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        // macOS 14+ may refuse the activation; typing still reaches a non-activating panel. Note it so
        // a missing caret can be traced (the editor draws its caret anyway).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !NSApp.isActive { Self.log.notice("activation refused; keyboard borrowed without activating") }
        }
    }

    private static let log = Logger(subsystem: "io.github.unh6unh6.SpaceSwitcher", category: "Focus")

    /// Lets go without reactivating the previous app: used when the user already moved to another
    /// desktop, where activating an app from the old one would pull them back.
    func release() {
        guard borrowed else { return }
        borrowed = false
        previous = nil
        NSApp.deactivate()
    }

    func giveBack() {
        guard borrowed else { return }
        borrowed = false
        if let app = previous, !app.isTerminated {
            app.activate()
        } else {
            NSApp.deactivate()
        }
        previous = nil
    }
}
