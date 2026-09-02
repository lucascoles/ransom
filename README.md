# Repp — *Earn your scroll.*

An iOS app that puts a price on Instagram, TikTok and whatever else eats your day.
The price is reps. Rex, a lime-green gecko with strong opinions, collects.

Built in SwiftUI for iOS 17+, on Apple's Screen Time frameworks (FamilyControls,
ManagedSettings, DeviceActivity). Everything stays on device — no account, no
server, no analytics.

---

## The idea

You pick the apps. Repp shields them. Opening one gets you Rex instead of your feed,
with a number on it: *12 push-ups and it's yours.* Do the set — the phone counts it —
and the shield lifts for the minutes you earned. When they're spent, Rex is back.

$5.99/month, gated behind a Cal-AI-style intake flow that turns a handful of answers
into a concrete deal ("10 push-ups → 15 minutes") before it ever asks for money.

## Opening it

```
open ios/Repp/Repp.xcodeproj
```

Requires **Xcode 16+**. Then, once:

1. Select the `Repp` target → Signing & Capabilities → set your **Team**.
   Do the same for `ReppShield`, `ReppShieldAction` and `ReppMonitor`.
2. Change the bundle IDs from `com.repp.app*` to something under your own prefix,
   and update the App Group (`group.com.repp.app`) in all four `.entitlements`
   files in `Config/` **and** in `ReppShared/ReppConstants.swift`.
3. **Family Controls needs a distribution entitlement from Apple.** Development
   builds work with the capability enabled; shipping to the App Store requires
   requesting the Family Controls entitlement at
   <https://developer.apple.com/contact/request/family-controls-distribution>.

### It has to run on a real device

Screen Time authorization, app shielding and the proximity sensor all no-op or fail
in the Simulator. The UI, onboarding flow and mascot are all previewable there; the
blocking is not.

### Testing the subscription

`Config/Repp.storekit` defines the $5.99/month product with a 3-day trial. The
`Repp` scheme references it, so purchases work locally without App Store Connect.
If Xcode doesn't pick it up: Product → Scheme → Edit Scheme → Run → Options →
StoreKit Configuration → `Repp.storekit`.

## How it's put together

```
ios/Repp/
├── Repp/                    App target
│   ├── ReppApp.swift        Entry point; owns the three environment objects
│   ├── RootView.swift       Onboarding gate, tabs, workout presentation
│   ├── Core/                Theme, models, AppModel store, StoreKit, notifications
│   ├── Components/          Buttons, choice cards, rings, bars, confetti
│   ├── Mascot/              Rex — the whole character, in vectors
│   ├── Onboarding/          18-step intake flow
│   ├── Home/ Stats/ Settings/ Paywall/
│   ├── Workout/             Rep detection engine + the set screen
│   └── Blocking/            Screen Time authorization and shield control
├── ReppShared/              Compiled into all four targets
├── ReppShield/              Shield UI extension — the block screen
├── ReppShieldAction/        Shield button handling
├── ReppMonitor/             DeviceActivityMonitor — puts the shield back
└── Config/                  Info.plists, entitlements, StoreKit config
```

`project.yml` is an XcodeGen spec that regenerates the project if the `.xcodeproj`
ever gets mangled by a merge. The checked-in project file is authoritative.

### Rex

`Repp/Mascot/Rex.swift` draws the character from SwiftUI shapes — no image assets.
A pose is a struct of ~15 numbers (limb angles, mouth curve, eye squint, tail droop),
so SwiftUI interpolates between any two poses and every expression change animates
for free. He idles, breathes, blinks on a random timer, and does push-ups in time
with your actual reps.

The shield extension can't host SwiftUI, so `ReppShared/RexBadge.swift` redraws his
face in Core Graphics. Same character, one source of truth, no bitmaps.

### Counting reps

`Workout/RepEngine.swift` reads a different sensor per movement:

| Movement | Sensor | Signal |
|---|---|---|
| Push-ups | Proximity | Phone face-up under your chest; your torso covers it at the bottom of each rep |
| Jumping jacks, high knees | Accelerometer | Impact peaks with a refractory window |
| Squats, sit-ups | Device attitude | Pitch sweeps, calibrated against the starting position |

Every mode also counts taps, so a bad reading never costs you a rep. Debounce
windows stop anyone shaking their way through a set.

### Enforcement

Earned time is enforced twice over, and whichever expires first wins:

1. A `DeviceActivityEvent` threshold on the shielded apps — the shield returns after
   the granted minutes of **actual use**, so time only burns while you're scrolling.
2. A wall-clock expiry in the shared `UnlockLedger`, re-checked by the app and by
   every extension each time one runs.

`ReppMonitor` does the re-shielding, so it works even if Repp has been force-quit.

### The shield handoff

iOS extensions can't launch their host app. So when you tap **Earn my time** on the
block screen, `ReppShieldAction` writes the request to the App Group, posts a Darwin
notification, and fires a local notification. Whether Repp is backgrounded or cold,
it picks the request up and drops you straight into a set for the app you were
reaching for. This is the one seam in the flow that Apple's frameworks don't let us
close — the block screen says so plainly rather than pretending otherwise.

## Onboarding

Eighteen steps, one question each, auto-advancing on single-select:

welcome → name → gender → age → height/weight → workout frequency → which apps →
how long → **reality check** → goals → movements → intensity → peak times →
notifications → referral → social proof → building your plan → the plan → paywall

The reality check is the turn: it converts "2–4 hours a day" into "45 days of your
year, gone" before offering the fix. Everything before it is data collection;
everything after it is the plan.

## Not built yet

- Localisation (all copy is English, inline)
- Unit tests around `ReppPlan.make` and `UnlockLedger` expiry maths
- Widget / Live Activity for the earned-time countdown
- A real Terms and Privacy page (the paywall links to placeholder URLs)
