import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var clock: MenuBarClock?
    private let settings = AppSettings.shared

    // These exist only while the popover is open. Closing it sets them back to nil, which releases
    // the SwiftUI views, the zone list and all converter state.
    private var popover: NSPopover?
    private var popoverModel: PopoverModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When unit tests run, they're injected into this app. Don't put an item in the menu bar.
        guard !AppDelegate.isRunningTests else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        clock = MenuBarClock(button: item.button!, place: settings.menuBarPlace)

        installMainMenu()
        if UserDefaults.standard.bool(forKey: "WCDebugHooks") { installDebugHooks() }
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: Popover lifecycle

    // Swift note: `@objc` exposes the method to the Objective-C runtime, which AppKit's
    // target/action mechanism (and #selector) needs.
    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(lastPopoverClose) > 0.3 {
            openPopover()
        }
        // Otherwise this click on the menu bar item already closed the popover: a transient popover
        // closes on the mouse-down of any click outside it, before the button's action fires on mouse-up.
        // Opening it again here would make the item impossible to close by clicking it.
    }

    private var lastPopoverClose = Date.distantPast

    func popoverWillClose(_ notification: Notification) {
        lastPopoverClose = Date()
    }

    private func openPopover() {
        guard let button = statusItem?.button, let clock else { return }

        let start = Date()
        let entries = ZoneCatalog.build(from: ZoneCatalog.bundledRows())
        let built = Date()
        let model = PopoverModel(
            entries: entries,
            now: start,
            menuBarPlace: clock.place,
            converterTarget: settings.converterTarget,
            onChooseMenuBarPlace: { [weak self] place in
                self?.settings.menuBarPlace = place
                self?.clock?.show(place)
            },
            close: { [weak self] in self?.popover?.performClose(nil) }
        )

        let hosting = NSHostingController(rootView: PopoverView(model: model))
        hosting.sizingOptions = []  // the popover size is fixed below; SwiftUI doesn't change it

        let popover = NSPopover()
        popover.behavior = .transient  // closes on a click outside
        // No open/close animation. A popover's close only completes when its animation does, and
        // animations don't run while the display is asleep. In testing, a close requested with the
        // display off left the SwiftUI content alive for 3.5 minutes, until the screen woke.
        popover.animates = false
        popover.contentSize = PopoverView.size
        popover.contentViewController = hosting
        popover.delegate = self

        self.popover = popover
        self.popoverModel = model
        // While open, the menu bar's minute tick also refreshes the row times. No extra timer.
        clock.onRefresh = { [weak model] now in model?.now = now }

        NSApp.activate()  // an accessory app must be active for the search field to take typing
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        log.debug("popover opened: \(entries.count) rows built in \(Int(built.timeIntervalSince(start) * 1000)) ms, shown after \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }

    func popoverDidClose(_ notification: Notification) {
        clock?.onRefresh = nil
        popover?.contentViewController = nil
        popover = nil
        popoverModel = nil
        statusItem?.button?.highlight(false)
        // We activated the app so the search field could take typing. Hand focus back to whatever app
        // was in use, so keystrokes after Esc don't go to an app with no windows.
        if NSApp.isActive { NSApp.deactivate() }
        log.debug("popover closed; views and model released")
    }

    // MARK: Menus

    /// A menu bar-only app has no visible menus, but key shortcuts are still routed through the main
    /// menu. Without an Edit menu, ⌘C/⌘V/⌘A wouldn't work in the search field.
    private func installMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit World Clock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    // MARK: Debug hooks

    /// Off unless the app is launched with `--args -WCDebugHooks YES`; when off, nothing is registered.
    /// Lets a script open and close the popover and fake a wake, so CPU can be measured without clicking.
    /// Debug builds can also snapshot the popover and set its state, for checking the UI.
    private func installDebugHooks() {
        let center = DistributedNotificationCenter.default()
        // `@MainActor` on the closure type tells the compiler it only ever runs on the main thread,
        // which makes it safe to hand to NotificationCenter's thread-agnostic callback.
        func on(_ name: String, _ action: @escaping @MainActor (String?) -> Void) {
            center.addObserver(forName: .init("com.viralthaker.WorldClock.debug." + name), object: nil, queue: .main) { note in
                let argument = note.object as? String
                MainActor.assumeIsolated { action(argument) }
            }
        }
        on("wake") { [weak self] _ in self?.clock?.refresh(.debugWake) }
        on("toggle") { [weak self] _ in self?.togglePopover() }
        #if DEBUG
        on("snapshot") { [weak self] path in if let path { self?.snapshotPopover(to: path) } }
        on("set") { [weak self] command in if let command { self?.applyDebugCommand(command) } }
        #endif
        log.notice("debug hooks installed")
    }

    #if DEBUG
    /// Renders the popover's layer tree to a PNG. No screen-recording permission is needed because it's
    /// the app's own content. The translucent background isn't captured, so it's filled with the window colour.
    private func snapshotPopover(to path: String) {
        guard let view = popover?.contentViewController?.view, let layer = view.layer else { return }
        let scale = view.window?.backingScaleFactor ?? 2
        let size = view.bounds.size
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        }
        context.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        // Core Graphics puts the origin at the bottom left; the hosting view's layers draw top-down.
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)
        guard let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }

    /// "tab=converter", "query=EST", "source=US|America/New_York", "input=2026-03-08 02:30", "second=1", "pick=GB|Europe/London"
    private func applyDebugCommand(_ command: String) {
        guard let model = popoverModel else { return }
        let parts = command.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let place = parts[1].split(separator: "|").map(String.init)
        switch parts[0] {
        case "tab": model.tab = parts[1] == "converter" ? .converter : .clock
        case "query": model.clockQuery = parts[1]
        case "source" where place.count == 2: model.converter.source = Place(countryCode: place[0], zoneID: place[1])
        case "pick" where place.count == 2:
            if let entry = model.entry(for: Place(countryCode: place[0], zoneID: place[1])) { model.chooseForMenuBar(entry) }
        case "input":
            let f = DateFormatter()
            f.timeZone = .gmt
            f.dateFormat = "yyyy-MM-dd HH:mm"
            if let date = f.date(from: parts[1]) { model.converter.input = date }
        case "second": model.converter.useSecondOccurrence = parts[1] == "1"
        case "key": sendKeys(parts[1])
        default: break
        }
    }

    /// Sends key presses through AppKit's normal event path, as if typed: "escape", "return", or literal text.
    private func sendKeys(_ keys: String) {
        guard let window = popover?.contentViewController?.view.window else { return }
        let presses: [(String, UInt16)] = switch keys {
        case "escape": [("\u{1b}", 53)]
        case "return": [("\r", 36)]
        default: keys.map { (String($0), 0) }
        }
        log.debug("debug keys -> window key=\(window.isKeyWindow), app active=\(NSApp.isActive)")
        for (characters, code) in presses {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
                ) {
                    NSApp.sendEvent(event)
                }
            }
        }
    }
    #endif
}
