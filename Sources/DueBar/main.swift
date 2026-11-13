import AppKit

// Plain AppKit entry point: DueBar is one status item, a dropdown panel and
// a few ordinary windows, so there's no SwiftUI App scene to host.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
