import AppKit
import os

/// Unified logging (view it in Console.app or with `log stream`). `.debug` messages cost almost
/// nothing unless someone is streaming them. `.notice` messages are saved to disk, so they're used
/// only for rare events such as waking from sleep.
/// `nonisolated` because Logger is thread-safe and it's also used from deinits, which don't run on the main actor.
nonisolated let log = Logger(subsystem: "com.viralthaker.WorldClock", category: "clock")

/// Keeps the menu bar title current.
///
/// While the popover is closed, this is the app's only work: one timer firing per minute, plus a
/// refresh when the Mac wakes or the clock, timezone or locale changes. It's plain AppKit, with no
/// SwiftUI view in the menu bar to lay out.
final class MenuBarClock {
    enum Reason: String {
        case launch, tick, wake, clockChanged, timeZoneChanged, localeChanged, placeChanged, debugWake
    }

    private let button: NSStatusBarButton
    private(set) var place: Place
    private var formatter: DateFormatter
    private let timer: DispatchSourceTimer
    private var scheduledFire: Date?
    private var observers: [NSObjectProtocol] = []

    /// Called after every refresh. The open popover uses it to update its row times, so the open
    /// popover needs no timer of its own.
    var onRefresh: ((Date) -> Void)?

    init(button: NSStatusBarButton, place: Place) {
        self.button = button
        self.place = place
        self.formatter = Self.makeFormatter(for: place.timeZone)

        // All digits the same width, so "1:11" and "10:00" don't make the menu bar item jiggle.
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

        // Swift note: GCD (Grand Central Dispatch) is the OS's task-queue library. This timer runs its
        // handler on the main queue (the UI thread). `[weak self]` is like holding a WeakRef: the
        // closure doesn't keep this object alive. `assumeIsolated` tells the compiler the main-queue
        // callback really is on the main actor, and checks that at runtime.
        timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refresh(.tick) }
        }
        timer.resume()

        observeSystemChanges()
        refresh(.launch)
        // There's no deinit: this object lives as long as the app does.
    }

    func show(_ place: Place) {
        self.place = place
        formatter = Self.makeFormatter(for: place.timeZone)
        refresh(.placeChanged)
    }

    /// Updates the title from the current time and re-arms the timer for the next minute boundary.
    /// Calling it more than once is harmless, which is what makes the wake and clock-change handling safe.
    func refresh(_ reason: Reason) {
        let now = Date()
        let title = "\(place.flag) \(formatter.string(from: now))"
        if button.title != title { button.title = title }  // AppKit relayouts only on a real change

        let next = MinuteBoundary.next(after: now)
        // A wall-clock deadline keeps counting while the Mac sleeps, so a deadline missed during sleep
        // fires straight after wake. The leeway (tolerance) lets macOS batch this wakeup with others.
        // macOS tends to use the whole leeway (a 1 s leeway fired ~0.95 s late), so 250 ms keeps the
        // flip within a third of a second of the real minute at no measurable energy cost.
        timer.schedule(wallDeadline: DispatchWallTime(date: next), repeating: .never, leeway: .milliseconds(250))

        if reason == .tick, let scheduled = scheduledFire {
            log.debug("tick \(title, privacy: .public), \(Int(now.timeIntervalSince(scheduled) * 1000)) ms after target")
        } else {
            log.notice("refresh(\(reason.rawValue, privacy: .public)) -> \(title, privacy: .public); next at \(next.formatted(.iso8601), privacy: .public)")
        }
        scheduledFire = next
        onRefresh?(now)
    }

    private func observeSystemChanges() {
        // Sleep and wake are reported on NSWorkspace's own notification center, not the default one.
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification, .wake)
        observe(.default, .NSSystemClockDidChange, .clockChanged)
        observe(.default, .NSSystemTimeZoneDidChange, .timeZoneChanged)
        observe(.default, NSLocale.currentLocaleDidChangeNotification, .localeChanged)  // e.g. 12/24-hour switch
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ reason: Reason) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if reason == .localeChanged || reason == .timeZoneChanged {
                    self.formatter = Self.makeFormatter(for: self.place.timeZone)
                }
                self.refresh(reason)
            }
        })
    }

    private static func makeFormatter(for zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent  // follows System Settings, including 12/24-hour
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

extension DispatchWallTime {
    init(date: Date) {
        let seconds = date.timeIntervalSince1970
        let whole = seconds.rounded(.down)
        self.init(timespec: timespec(tv_sec: Int(whole), tv_nsec: Int((seconds - whole) * 1_000_000_000)))
    }
}
