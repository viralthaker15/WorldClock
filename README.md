# World Clock

A macOS menu bar clock for personal use. It shows one flag and time (`🇬🇧 1:44 PM`). Click it to pick
another country or timezone, or to convert a time in any zone to India time (IST).

- Swift 6 + SwiftUI, with AppKit for the menu bar item and popover. No dependencies, no network, no accounts.
- Menu bar only: no Dock icon (`LSUIElement`).
- Designed to sit at about 0% CPU when idle (numbers [below](#measured-idle-cpu)).

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later. Built and tested with Xcode 27.2 on macOS 27.0.1. The project uses Xcode 16's
  synchronized folders, so new files dropped into `WorldClock/` are picked up without editing the project.

## Build and test

```bash
make test      # unit tests (Swift Testing), Debug
make build     # Release build -> build/DerivedData/Build/Products/Release/WorldClock.app
make run       # build and launch from the build folder
```

Without `make`:

```bash
xcodebuild -project WorldClock.xcodeproj -scheme WorldClock -derivedDataPath build/DerivedData -configuration Debug test
xcodebuild -project WorldClock.xcodeproj -scheme WorldClock -derivedDataPath build/DerivedData -configuration Release build
```

Or open `WorldClock.xcodeproj` in Xcode and press ⌘R (run) or ⌘U (test).

The app is signed ad hoc ("Sign to Run Locally"), so no Apple developer account is needed. That's fine
for your own Mac; giving it to other people would need a Developer ID and notarisation.

## Install to /Applications

```bash
make install
```

This builds Release, quits any running copy, copies the app to `/Applications/WorldClock.app` with
`ditto`, and launches it. By hand:

```bash
pkill -x WorldClock
ditto build/DerivedData/Build/Products/Release/WorldClock.app /Applications/WorldClock.app
open /Applications/WorldClock.app
```

To remove it: `make uninstall`. Settings stay in `~/Library/Preferences/com.viralthaker.WorldClock.plist`;
`defaults delete com.viralthaker.WorldClock` clears them.

## Launch at login

Open **System Settings → General → Login Items** (called *Login Items & Extensions* on newer macOS).
Under **Open at Login**, click **+** and choose `/Applications/WorldClock.app`.

Or from Terminal (macOS asks once for permission to control System Events):

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/WorldClock.app", hidden:false}'
```

Install to `/Applications` first, so the login item doesn't point into the `build` folder.

## Using it

- **Clock tab**: search by country ("india", "united k"), city ("los ang", "Detroit") or abbreviation
  ("EST", "IST", "BST", "utc+5:30"). Click a row, or press Return for the top hit, to show that zone in
  the menu bar. The choice is saved.
- **Converter tab**: choose the source (it defaults to the menu bar zone), a date and a time. The result
  is the time in India. The date is shown only when it differs from the source date.
  - **A time that doesn't exist** (clocks spring forward, e.g. New York 02:30 on 8 March 2026): you get a
    warning saying which times were skipped, and no result. The input is never moved for you.
  - **A time that occurs twice** (clocks go back, e.g. London 01:30 on 25 October 2026): the first
    occurrence (BST) is shown and labelled, with a button to switch to the second (GMT).
- Esc closes the popover. ⌘Q or the Quit button quits.

## How it stays idle

This replaces Dato, which got stuck at ~94% CPU re-running a SwiftUI layout pass
(`NSHostingView.layout`, lazy stacks, scroll views) while its popup was closed, after a long sleep.
This app is built so that can't happen here:

| Decision | Why |
|---|---|
| `NSStatusItem` + `NSPopover` rather than SwiftUI's `MenuBarExtra` | `MenuBarExtra` has no API to tell you when its window opens or closes, and you can't tear its content down. Its label is a SwiftUI hosting view in the menu bar, the same component Dato was spinning in. Here the menu bar text is a plain AppKit `button.title`. |
| SwiftUI exists only while the popover is open | The `NSHostingController`, the view model and the zone list are created on open. In `popoverDidClose` they're set to `nil`, which frees them. With the popover closed, there are no SwiftUI views to lay out. |
| AppKit entry point (`main.swift`) rather than `@main App` | SwiftUI's app lifecycle keeps scene machinery running for the life of the app. |
| One timer, aligned to the minute | A one-shot GCD timer with a wall-clock deadline at the next minute boundary plus 50 ms, and 250 ms leeway (tolerance). It re-arms itself from the current time on every firing, so it can't drift. |
| Wall-clock deadline (`DispatchWallTime`) | `Timer` counts in system uptime, which stops during sleep. A wall-clock deadline that passed during sleep fires immediately on wake. |
| Explicit refresh on wake, clock change, timezone change and locale change | Belt and braces. Each refresh updates the title and re-arms the same timer. Running it twice is harmless, and nothing observes layout, so it can't cause a feedback loop. |
| Title set only when the text changes, using equal-width digits | The status item resizes at most once a minute, and its width doesn't change as digits change. |
| Fixed-size popover | `sizingOptions = []`, so SwiftUI content never resizes the popover. |
| No popover animation | A popover's close only completes when its animation does, and animations don't run while the display is asleep. In testing, a close requested with the display off left the SwiftUI content alive for 3.5 minutes, until the screen woke. With `animates = false`, closing frees everything at once (measured: model freed 13 ms after close). |
| While open, row times update from the same minute tick | No second timer. |

### Measured idle CPU

Measured on 5 Nov 2026 on this Mac (Apple silicon, macOS 27.0.1) with the Release build. CPU time and
wakeup counts come from `proc_pid_rusage`. They were cross-checked with `top` (the numbers Activity
Monitor shows) and `sample` (Activity Monitor's "Sample Process").

| Scenario | Window | CPU time | Average CPU | Wakeups | Memory |
|---|---|---|---|---|---|
| Idle, popover never opened | 10 min | 122 ms | **0.020%** | 0.11/s | 14 MB, flat |
| Same, second run | 5 min | 75 ms | **0.025%** | 0.14/s | 14.5 MB |
| Idle after the popover was opened and closed (minutes 2–5) | 4 min | 61 ms | **0.025%** | 0.45/s | 40 MB |
| First minute after closing (one-off cleanup) | 1 min | 200 ms | | | |
| Popover open and untouched | 60 s | 128 ms | 0.21% | 0.75/s | 43 MB |
| Opening the popover | | ~200 ms | | | |
| Refresh on (simulated) wake | | 0.85 ms | | | |

`top` (and so Activity Monitor) shows **0.0%** in every idle case.

- **The whole idle cost is the minute tick, about 15 ms each.** Formatting the time takes microseconds.
  The rest is AppKit redrawing the menu bar item and sending it to the menu bar, as a `sample` profile
  showed.
- **Ticks land 130–250 ms after the minute**, inside the 250 ms leeway. With a 1 s leeway they landed
  about 950 ms late, which is why the leeway is 250 ms.
- **After the popover has been shown once**, AppKit keeps receiving window-server messages, such as
  display-brightness (EDR) changes, so wakeups rise from about 0.14/s to 0.45/s. Each one is too short
  to show up in a 1 ms sampling profile: the main thread was idle in 100% of 32,665 samples over 40 s.
  CPU doesn't change. These are AppKit's wakeups, not this app's code.
- **Memory stays around 40 MB after the first open** because the SwiftUI frameworks stay loaded. The
  app's own objects are freed: the log shows `PopoverModel freed` within 13 ms of closing.
- **Opening the popover takes about 0.1–0.25 s.** The zone list takes 30–55 ms; SwiftUI setup is the rest.
- **If you re-measure**, two things inflate the numbers. Streaming debug logs (`log stream --level debug`)
  makes the target process format AppKit's debug messages, and an open popover's blinking text cursor
  costs about 0.2%. A simple check:
  `ps -o time= -p $(pgrep -x WorldClock)` now and again in 10 minutes. CPU % = difference ÷ 600 s × 100.

## Timezone data

- **Offsets and DST rules** come only from Foundation's `TimeZone`/`Calendar` (the macOS tz database,
  updated with the OS). Nothing is hard-coded. For example, on this Mac the 2026c data already has
  British Columbia on permanent UTC−7, and the app shows that.
- **The country ↔ zone mapping** comes from a copy of tzdata's
  [`zone.tab`](WorldClock/Resources/zone.tab) bundled in the app (public domain, from
  `/usr/share/zoneinfo/zone.tab`, tzdata 2026c).
  - **Why `zone.tab` and not `zone1970.tab`**: `zone1970.tab` merges zones across borders (Norway,
    Sweden and Denmark all map to `Europe/Berlin`), so Norway would appear as "Berlin". `zone.tab` gives
    every country its own zones and its own city names.
  - **Why bundled rather than read from `/usr/share/zoneinfo` at runtime**: the build doesn't depend
    on an OS file path, and tests are deterministic. Only the list of rows comes from the file; the times
    themselves always come from the live OS data. macOS doesn't ship `zone1970.tab` anyway.
- **Merged zones.** Within a country, zones whose clocks behave the same over the next year (same
  offsets, same DST transition dates) become one row. The US goes from 29 rows to 8 (New York, Chicago,
  Denver, Phoenix, Los Angeles, Anchorage, Adak, Honolulu); 418 rows become 314 overall. Merged cities
  stay searchable ("Detroit" finds the New York row) and appear in the row's tooltip. The trade-off: for
  converter dates years in the past, the main city's historical rules apply (e.g. New York's rather
  than Indianapolis's pre-2006 rules).
- **Abbreviations** come from Foundation's localised short names, preferring the zone's own country's
  English locale (`en_IN` → IST, `en_GB` → BST, `en_AU` → AEST). If no common abbreviation exists, they
  fall back to `GMT+3` style.
- **Refreshing the data:** `cp /usr/share/zoneinfo/zone.tab WorldClock/Resources/zone.tab`, then rebuild.

## Settings

Stored in UserDefaults (domain `com.viralthaker.WorldClock`):

| Key | Default | UI |
|---|---|---|
| `menuBarPlace` | `{countryCode = GB; zoneID = "Europe/London"}` | Clock tab |
| `converterTarget` | `{countryCode = IN; zoneID = "Asia/Kolkata"}` | None yet (phase 2). The converter reads its target only from this setting. |

To try another converter target before phase 2 adds a picker:

```bash
defaults write com.viralthaker.WorldClock converterTarget -dict countryCode GB zoneID Europe/London
```

## Logs and debugging

```bash
# Rare events (launch, wake, clock/timezone change), which are kept on disk:
log show --last 1d --style compact --predicate 'subsystem == "com.viralthaker.WorldClock"'
# Everything, including each minute tick and how late it fired, live:
log stream --level debug --style compact --predicate 'subsystem == "com.viralthaker.WorldClock"'
```

After a sleep, `log show` should include a `refresh(wake)` line with the correct time.

Launching with `open WorldClock.app --args -WCDebugHooks YES` enables debug hooks: distributed
notifications that open and close the popover (`com.viralthaker.WorldClock.debug.toggle`) or fake a
wake (`…debug.wake`). Debug builds also have `…debug.snapshot` and `…debug.set`. These were used to
measure CPU and check the UI from scripts. Without the flag, nothing is registered.

## Project layout

```
WorldClock/
  main.swift            entry point (AppKit, no SwiftUI App)
  AppDelegate.swift     status item, popover create/teardown, menus, debug hooks
  MenuBarClock.swift    title, minute timer, wake/clock/timezone/locale refresh
  Core/                 pure logic, no UI, unit-tested
    TimeMath.swift      wall-clock <-> instant conversion, gap/overlap detection
    ZoneCatalog.swift   zone.tab parsing, merging, labels, search
    Place.swift         persisted country+zone, flags, AppSettings
    MinuteBoundary.swift, Display.swift
  Popover/              SwiftUI views and the view model (alive only while open)
  Resources/zone.tab
WorldClockTests/        Swift Testing suites
```

## Swift notes (for a TypeScript developer)

- **`struct` vs `class`**: structs are values, copied on assignment like immutable objects
  (`LocalDateTime`, `ZoneEntry`). Classes are shared references, used for things with a lifetime
  (`AppDelegate`, `MenuBarClock`, the view models).
- **`enum` with associated values** is a discriminated union. `ConversionOutcome` is
  `exact | occursTwice(first, second) | doesNotExist(gap)`, and `switch` must handle every case.
- **Concurrency**: the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so code runs on the
  main thread unless marked otherwise, like JS's single event loop. Pure logic in `Core/` is marked
  `nonisolated` so tests can call it from any thread. Swift 6 checks for data races at compile time.
- **`@Observable`** is roughly MobX: SwiftUI tracks which properties each view reads and re-renders
  only those views.
- **Memory**: Swift uses reference counting, not a garbage collector. `[weak self]` in a closure is like
  holding a `WeakRef`, and it prevents reference cycles that would keep objects alive.
- **Optionals**: `T?` is `T | undefined`. `guard let x else { return }` unwraps it or exits early.
- **Tests**: Swift Testing's `@Test(arguments:)` is Jest's `test.each`, and `#expect` is `expect`.
