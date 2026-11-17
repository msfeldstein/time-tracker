# Time Tracker

A voice-first iPhone app for logging how long everyday tasks take. Tap the mic (or the Lock Screen widget, a Control Center button, Back Tap, or Siri), say **"starting dishes"**, and a timer starts. Later say **"done with dishes"** or tap **Stop** on the Lock Screen. There are no categories to manage and no forms to fill in.

- SwiftUI, Swift 6 (strict concurrency), iOS 26. Runs on an iPhone 13 mini.
- Speech is recognized **on the iPhone**. Audio never leaves the phone.
- Everything is stored offline with SwiftData. Each transcript is saved before it is interpreted, so nothing she says is lost.
- Designed to install with a **free Apple ID** (Personal Team). See [Free Apple ID limitations](#free-apple-id-limitations).

---

## Contents

1. [What's in milestone 1](#whats-in-milestone-1)
2. [Install on Alexa's iPhone (free Apple ID)](#install-on-alexas-iphone-free-apple-id)
3. [Every 7 days: re-sign the app](#every-7-days-re-sign-the-app)
4. [Set up the Lock Screen widget, Control, Back Tap and Siri](#set-up-the-lock-screen-widget-control-back-tap-and-siri)
5. [Free Apple ID limitations](#free-apple-id-limitations)
6. [How it works](#how-it-works)
7. [Development](#development)
8. [Troubleshooting](#troubleshooting)

---

## What's in milestone 1

| Piece | Where |
| --- | --- |
| Big mic button with live transcript. Listening ends by itself after about 1.6 s of silence. | `App/Views/HomeView.swift`, `App/Speech/VoiceCaptureController.swift` |
| On-device speech: `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26), falling back to `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` | `App/Speech/` |
| Deterministic parser for start, stop, stop-all and note phrases, with fuzzy matching against running activities | `Packages/TimeTrackerCore/` |
| SwiftData store in the shared App Group container. Raw transcripts are saved first and re-processed on launch if interpretation didn't finish. | `Shared/SharedStore.swift`, `Shared/EntryService.swift` |
| Live Activity / Dynamic Island with the name, a live elapsed timer, "+N more", and a **Stop** button (a `LiveActivityIntent`, so the app doesn't open) | `Widgets/TimerLiveActivity.swift`, `Shared/SharedIntents.swift` |
| Lock Screen widgets (circular, rectangular, inline). Tapping one opens the app already listening. | `Widgets/RunningActivityWidget.swift` |
| Control Center / Lock Screen control "Log Time" that opens the app already listening | `Widgets/LogTimeControl.swift` |
| App Intents: Start Activity (Siri asks "What are you starting?"), Stop Activity, Log by Voice, plus Siri phrases | `App/Intents/`, `Shared/SharedIntents.swift` |
| Today view with durations (running ones update live), a daily total, and fixes: rename, change start and end times, mark as stopped, delete, add a forgotten entry. Anything over 3 hours is flagged "Forgot to stop?". | `App/Views/TodayView.swift`, `App/Views/EditEntryView.swift` |
| Milestone 2 hook: an `LLMService` protocol, a `ClaudeHaikuService` stub, and an Anthropic API key field in Settings (stored in the Keychain) | `Packages/TimeTrackerCore/Sources/TimeTrackerCore/LLMService.swift`, `App/LLM/` |
| Parser, matcher and resolver unit tests (46 tests), run with `swift test` or ⌘U | `Packages/TimeTrackerCore/Tests/` |

### Things she can say

| She says | What happens |
| --- | --- |
| "Starting dishes", "Start laundry", "I'm doing homework", "Time for a walk" | Starts a timer ("Dishes", "Laundry", ...) |
| "Done with the dishes", "Finished laundry", "Stop dishes", "The dishes are done" | Stops the best fuzzy match among running timers |
| "Stop", "Done", "I'm done", "All done" | Stops the most recently started timer |
| "Stop everything", "I'm done for the day" | Stops all timers |
| "Done with dishes and starting laundry" | Both, in order |
| "Starting dishes" while Dishes is already running | Nothing new starts; she's told it's already running |
| Anything else ("remember to buy soap") | Saved as a note in Today. Never dropped. |

Several timers can run at the same time.

---

## Install on Alexa's iPhone (free Apple ID)

You need: a Mac with **Xcode 26** or later, a USB cable, Alexa's iPhone on **iOS 26**, and any Apple ID (yours is fine; the Personal Team belongs to whoever signs the app).

### 1. Get the code

```bash
git clone https://github.com/msfeldstein/time-tracker.git
cd time-tracker
```

The Xcode project (`TimeTracker.xcodeproj`) is committed, so you don't need XcodeGen to build: open it in Xcode 26 or later.

If you change `project.yml`, regenerate the project. No Homebrew is needed:

```bash
./scripts/generate-project.sh
```

The script downloads a pinned XcodeGen release (2.47.0) from GitHub into `.build/` (git-ignored) the first time, runs `xcodegen generate`, then runs `scripts/check_xcodeproj.py`. That check catches project problems Xcode refuses to open, such as a file that belongs to more than one group. Other ways to get XcodeGen: download `xcodegen.zip` from the [releases page](https://github.com/yonaskolb/XcodeGen/releases) and run `xcodegen/bin/xcodegen generate`, or build it from source with `git clone https://github.com/yonaskolb/XcodeGen && cd XcodeGen && swift run xcodegen --spec /path/to/time-tracker/project.yml`.

To confirm the project is readable, run `xcodebuild -list -project TimeTracker.xcodeproj`. It should list the targets `TimeTracker` and `TimeTrackerWidgets` and the scheme `TimeTracker`.

### 2. Change the bundle ID and team (one file)

Bundle IDs and App Group IDs are **globally unique across all Apple accounts**, so the placeholder `com.example.timetracker` will probably be rejected. Everything is derived from one setting:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig   # git-ignored
```

Edit `Config/Local.xcconfig`:

```
BUNDLE_ID_PREFIX = com.michaelfeldstein.timetracker   // anything unique to you
DEVELOPMENT_TEAM = ABCDE12345                         // your Personal Team ID, or leave blank (see below)
```

This produces:

- App: `com.michaelfeldstein.timetracker`
- Widget extension: `com.michaelfeldstein.timetracker.widgets`
- App Group: `group.com.michaelfeldstein.timetracker`

You can also edit `Config/Base.xcconfig` directly. `Local.xcconfig` just keeps your personal values out of git.

**Finding the team ID:** in Xcode, go to **Settings › Accounts**, click **+**, and sign in with your Apple ID. A "(Personal Team)" entry appears. The easiest way to set the team is to leave `DEVELOPMENT_TEAM` blank and, in Xcode, select the **TimeTracker** target, then **Signing & Capabilities**, then **Team: <Your Name> (Personal Team)**. Do the same for the **TimeTrackerWidgets** target. Selections made in the UI are lost if you later regenerate the project. To make it stick, copy the 10-character ID from **Build Settings › Development Team** into `Local.xcconfig`.

Leave **Automatically manage signing** on. Don't add capabilities by hand: both targets already declare the App Group in `Config/*.entitlements`, and Xcode registers it for you.

### 3. Turn on Developer Mode on the iPhone

1. Plug the iPhone into the Mac, unlock it, and tap **Trust This Computer**.
2. On the iPhone, open **Settings › Privacy & Security › Developer Mode** and turn it **On**. This option only appears after the phone has been connected to Xcode at least once. If it's missing, do step 4 once and then come back.
3. The phone restarts. After unlocking, tap **Turn On** and enter the passcode.

### 4. Build and run

1. In Xcode's toolbar, choose the **TimeTracker** scheme and Alexa's iPhone as the destination.
2. Press **⌘R**. The first time, Xcode registers the device, creates the App IDs and the App Group, and installs the app.
3. If the app installs but won't open ("Untrusted Developer"), do step 5 and press ⌘R again.

### 5. Trust the developer profile on the iPhone

**Settings › General › VPN & Device Management**, then under **Developer App** tap **Apple Development: <your Apple ID>**, then **Trust "Apple Development: ..."**, then **Trust**.

### 6. First launch

- Allow the **Microphone**. If asked, also allow **Speech Recognition** (only the fallback engine asks).
- The first time she talks, iOS may download its on-device speech model (Wi-Fi helps). The screen shows "Getting ready..." while this happens. This is a language-model download only; no audio is uploaded.
- When the first timer starts, a Live Activity appears on the Lock Screen. If iOS asks, choose **Allow**.

### 7. (Optional) Wireless re-installs

With the phone plugged in, open **Window › Devices and Simulators**, select the phone, and tick **Connect via network**. After that, the 7-day re-sign works over Wi-Fi whenever the phone is unlocked and on the same network as the Mac.

---

## Every 7 days: re-sign the app

Free-account provisioning profiles **expire 7 days after install**. When that happens the app stops launching (iOS says it's no longer available). **Her data is kept**: it's in the App Group container, which survives re-installs as long as the app isn't deleted and the bundle ID doesn't change.

To renew: connect the phone (USB or wireless), open the project, and press **⌘R**. That's all. A weekly calendar reminder helps.

Don't change `BUNDLE_ID_PREFIX` once she has data. A new ID installs a separate, empty app.

---

## Set up the Lock Screen widget, Control, Back Tap and Siri

### Lock Screen widget

1. On the Lock Screen, touch and hold, then tap **Customize › Lock Screen**.
2. Tap the widget row under the clock and choose **Time Tracker**.
3. Add the **rectangular** widget (shows what's running and its timer, "+N more") and/or the **circular** one (mic icon and a count).
4. Tap **Done**. Tapping the widget opens the app already listening.

### Control Center / Lock Screen button ("Log Time")

- **Control Center:** swipe down from the top-right, tap **+** (top-left), choose **Add a Control**, search for **Time Tracker**, and pick **Log Time**.
- **Lock Screen bottom buttons:** go to **Customize › Lock Screen**, tap the flashlight or camera button, remove it, tap **+**, and choose **Log Time**.

### Back Tap (double-tap the back of the phone)

Back Tap can only run Shortcuts, so this takes two steps:

1. Open the **Shortcuts** app, tap **+**, then **Add Action**, search for **Time Tracker**, and choose **Log by Voice**. Name the shortcut **Log Time** and tap **Done**.
2. Go to **Settings › Accessibility › Touch › Back Tap › Double Tap** and choose **Log Time**.

Double-tapping the back of the phone now opens Time Tracker listening. The iPhone 13 mini supports Back Tap. It works best when the phone is unlocked, because opening an app from a locked phone asks for Face ID first.

### Siri

These work once the app has been opened at least once. Siri can take a minute or two to learn the phrases.

- "Hey Siri, **log time in Time Tracker**": opens the app, already listening.
- "Hey Siri, **start timing in Time Tracker**". Siri asks "What are you starting?"; she answers "dishes".
- "Hey Siri, **stop timing in Time Tracker**": stops the most recent timer.

The same three actions appear in the Shortcuts app under Time Tracker. "Log Time" is also an option for the Action button on newer iPhones (the 13 mini doesn't have one).

---

## Free Apple ID limitations

Researched against Apple's [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios) table (the "Apple Developer" column means a free account) and the [Personal Team rules](https://developer.apple.com/help/account/basics/about-your-developer-account/).

| Feature | Free account? | What this app does |
| --- | --- | --- |
| App Groups | ✅ Supported | Used to share the SwiftData store with the widget. If signing ever drops the App Group, the app falls back to private storage (no data loss, but widgets go blank) and shows a warning in Settings. |
| Widgets / Lock Screen widgets / Controls | ✅ No capability needed | Used. |
| Live Activities | ✅ No entitlement needed (`NSSupportsLiveActivities`) | Started and updated **locally only** with `pushType: nil`. Requesting a push token makes `Activity.request` fail on Personal Team builds. The timer uses `Text(date, style: .timer)`, which updates itself, so no pushes are needed. |
| App Intents / App Shortcuts / Siri phrases | ✅ No entitlement needed | Used. The **Siri capability (SiriKit) is *not* available to free accounts**, and it isn't needed: Apple only requires it for Intents extensions handling non-shortcut Siri requests. The project deliberately doesn't add it, because adding it would break free signing. |
| Keychain | ✅ | Stores the optional Anthropic key (device-only, not synced). |
| Push notifications | ❌ | Not used. As a result, Live Activities can't be started or updated remotely, and a Live Activity can't refresh while the app is idle. That isn't needed here. |
| iCloud / CloudKit | ❌ | Not used. Data lives only on this phone, with no sync between devices. The phone's normal backup should include it, but that hasn't been verified. |
| TestFlight / App Store | ❌ | Install from Xcode only. |

Other Personal Team limits:

- **Apps expire after 7 days** and must be re-run from Xcode (see above).
- **Up to 3 free-signed apps per device** at a time.
- **10 App IDs per 7 days** per Apple ID. This project uses 2 (app and widget), so avoid changing the bundle prefix repeatedly.
- **Live Activities last at most about 8 hours** (then up to 4 more on the Lock Screen). Something left running overnight drops off the Lock Screen but is still running in the app and flagged "Forgot to stop?". Opening the app brings the Live Activity back.
- **No Dynamic Island on the iPhone 13 mini.** The Live Activity shows on the Lock Screen and as a banner. The Dynamic Island layout is there for newer phones.

---

## How it works

```
mic / widget / control / Siri / Back Tap
        │
        ▼
VoiceCaptureController ──► TranscriptionEngine (SpeechAnalyzer → SFSpeechRecognizer, both on-device)
        │  final transcript
        ▼
EntryService.capture(text)
   1. insert CaptureRecord(text) and save   ← raw words are persisted first
   2. CommandParser.parse(text)             ← deterministic, TimeTrackerCore
   3. CommandResolver.resolve(..., running) ← fuzzy-matches stops to running timers
   4. insert/stop TimeEntry rows, mark the CaptureRecord interpreted, save
   5. reload widgets and sync the Live Activity
```

- **Storage.** `TimeTracker.store` lives in the App Group container and both the app and widget open it. Every transcript becomes a `CaptureRecord` before parsing. If the app dies between steps 1 and 4, `reprocessPendingCaptures()` finishes the job on next launch using the original timestamp. Text the parser can't understand becomes a note `TimeEntry`, so nothing is discarded.
- **One Live Activity** shows the most recently started timer plus "+N more". Its Stop button runs `StopEntryIntent` (a `LiveActivityIntent`) in the app process without opening the app, then the activity switches to the next timer or ends.
- **"Open and listen" entry points** use `LogByVoiceIntent` (`openAppWhenRun`) or the `timetracker://listen` URL (widgets). `ListenRequest` hands the request to the UI on both cold and warm launches.
- **Milestone 2 seam.** `LLMService` (in `TimeTrackerCore`) defines `interpret`, `categorize` and `summarize`. `ClaudeHaikuService` (model `claude-haiku-4-5`) reads its key from the Keychain and currently throws `notImplemented`. `LLMServices.current()` picks it when a key exists. **Never commit an API key: this repository is public.** The key is only ever entered in the app's Settings screen.

### Project layout

```
project.yml                 XcodeGen spec (source of truth for the project)
TimeTracker.xcodeproj       Generated from project.yml, committed for convenience
Config/                     xcconfig (bundle ID prefix, team), Info.plists, entitlements
App/                        App target: SwiftUI views, speech, Siri intents, Keychain, LLM stub
Shared/                     Compiled into app + widget: SwiftData models, store, EntryService,
                            Live Activity attributes/manager, widget-facing intents
Widgets/                    Widget extension: Lock Screen widget, Live Activity, Control
Packages/TimeTrackerCore/   Platform-independent parser, matcher, resolver, formatting, LLM protocol + tests
```

---

## Development

- **Parser tests (any Mac, or Linux):** `cd Packages/TimeTrackerCore && swift test`
- **In Xcode:** **⌘U** on the `TimeTracker` scheme runs the package's own `TimeTrackerCoreTests` target in an iOS Simulator. You can also open `Packages/TimeTrackerCore/Package.swift` on its own and test the `TimeTrackerCore` scheme. The test files belong only to the package. Don't add them to an app-project target too: Xcode 27 refuses to open a project where a file is in more than one group.
- **CI:** `.github/workflows/ios.yml` runs the package tests and builds the app and widget for the iOS Simulator with Xcode 26 on GitHub's macOS runners, unsigned.
- The scheme builds both the app and the widget extension. To debug the widget or Live Activity, run the app, then use **Debug › Attach to Process by PID or Name › TimeTrackerWidgets**.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "Failed to register bundle identifier" / "App Group is not available" | The ID is taken. Change `BUNDLE_ID_PREFIX` to something more unique. |
| "Communication with Apple failed" / no devices | Plug the phone in and unlock it so Xcode can register it with your Personal Team. |
| App won't open after a week | The 7-day expiry. Re-run from Xcode. |
| Widget always says "Tap to log" while timers are running | The App Group isn't active. Check Settings › Storage in the app, and that both targets use the same team and the same `APP_GROUP_ID`. |
| "On-device speech recognition isn't available" | Go to **Settings › General › Keyboard** and make sure Dictation is on for her language, then let the phone download the language on Wi-Fi. |
| No Live Activity | **Settings › Time Tracker › Live Activities** must be on. It appears when a timer starts or when the app is opened. |
| Siri doesn't know the phrases | Open the app once, wait a minute, and use the exact phrases above (they must include "Time Tracker"). |
