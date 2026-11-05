import AppKit

// Swift note: this file is the program's entry point, like `index.ts`.
// We deliberately don't use SwiftUI's `@main struct App`. That would keep SwiftUI's
// scene machinery alive for the app's whole lifetime. With a plain AppKit entry point,
// no SwiftUI object exists at all while the popover is closed.
//
// Top-level code in main.swift runs on the main actor (the main thread).

let app = NSApplication.shared
// `NSApplication.delegate` is a weak reference, so this global keeps the delegate alive.
let delegate = AppDelegate()
app.delegate = delegate
app.run()
