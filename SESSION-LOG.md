# Session log, 2 to 3 September 2026

Everything done in one working session, and everything left open. Written so the
next person (or the next session) can pick up cold.

The raw conversation transcript is at `.session-archive/transcript-2026-09-03.jsonl`.
It is **gitignored on purpose**: it is 13 MB, and it contains a Higgsfield account
ID and signed asset URLs that should not go into a public repo.

---

## How the session started

The repo was not on this machine at all. There was a stray `CLAUDE.md` sitting
alone in `~/Downloads` with no project around it. Cloned from GitHub to `~/ransom`.

## Getting it to run at all

Four things were in the way, in this order:

1. **No GitHub credentials.** Installed `gh`. Became moot once the repo was made
   public.
2. **No iOS platform in Xcode.** Xcode 26.6 was installed but `xcrun simctl list
   runtimes` was empty. `-showsdks` listed an iOS Simulator SDK, which is
   misleading: the platform itself was not downloaded, so there was no build
   destination at all.
3. **Disk full.** The platform download stalled silently at 98% disk (13.6 GB
   free, needs roughly 18 GB to download and unpack). It reported no error and
   held zero network connections. Cleared a 46 GB After Effects cache, which took
   free space to 63 GB.
4. **Download cancelled at 62%** (`MobileAssetError.Download Code=48`), most
   likely Xcode.app and `xcodebuild` competing for the same asset. A plain retry
   completed it.

Then: `BUILD SUCCEEDED`, all four targets, and the app launched in the simulator.

**Signing is a non-issue for the simulator.** Xcode uses "Sign to Run Locally";
no team, no provisioning profile, no paid account. A full signing-enabled build
succeeds. The `TESTING.md` §4 strip-down is only needed for a *real device*.

---

## Changes made

### 1. Palette: green no longer does the brand's work

`CLAUDE.md` listed this as open. 52 of 56 `Palette.green` call sites moved to
`Palette.brand`. The rule applied, taken from the palette's own doc comments:

- **Tangerine (`brand`)**: interactive chrome, selection states, identity
  moments, cost and effort figures, progress.
- **Green**: reserved strictly for *earned / unlocked / win*.

Four deliberate survivors:

| File | Why it stayed green |
|---|---|
| `HomeView.swift:224` | the unlock countdown, literally "the door is open" |
| `WorkoutCompleteView.swift:83` | minutes **earned** |
| `StatsView.swift:166` | "Now" vs "Before Ransom", an improvement |
| `Confetti.swift:61` | one hue inside a multi-colour mix |

**`CLAUDE.md` was wrong about the scope.** It called this "a `Palette` change, not
a structural one". That is true only of the app target. The extensions cannot see
`Theme.swift`, and they were still drawing the **green gecko**: `RexBadge.swift`
rendered Rex with green skin (`0.42, 0.82, 0.35`) and the shield's primary button
was bright green. That is the block screen, the most-seen surface of the core
feature. Fixed by adding `RansomShared/RansomPalette.swift`, which all four
targets compile, and pointing `RexBadge` and `ShieldConfigurationExtension` at it.

### 2. Copy rewrite across all 16 intake steps

Done by a subagent. Full before/after with rationale per step is in
`COPY-NOTES.md`. Summary:

- Zero em dashes left in any user-facing string anywhere in the app.
- Apps step: "What's taking up most of your time?", nine-word subtitle, plus an
  **Other** tile that requests Screen Time access and opens `FamilyActivityPicker`.
- Bedtime question: the chip row became "Do you scroll in bed?" with the price
  consequence shown, derived from `Tariff.nightSurcharge`. Still writes only
  `.lateNight` into `peakTimes`, so `AppModel.swift:231` is untouched.
- Identity screen rewritten from "Finish the sentence" to "What do you want back?".
  Both later echoes (plan screen, paywall) still read correctly.
- Plan screen uses green only on win figures. Reps stay tangerine as the cost.

**Two real bugs found and fixed in passing:**

1. `FirstRepStep` hardcoded push-ups, so anyone who picked squats was told to get
   on the floor and do push-ups. Now reads `profile.primaryExercise`.
2. The plan chart carried its own copy of the 35% / 4-week constant instead of
   reading `reduction(onDay:)`. Same values today, one edit from contradicting the
   chart beside it, which is the exact failure `CLAUDE.md` warns about.

### 3. Camera state honesty (not a camera fix)

`configureSession()` now returns whether an input was actually attached, and
`start()` reports it:

```swift
guard configureSession() else {
    state = .blocked("No camera on this device, so Rex can't watch your form. Tap to count each rep.")
    return
}
```

Previously, with no camera, the session ran with no input at all and the user got
a live-looking counter that silently never counted.

### 4. Rex intro animation on the welcome screen

`Mascot/RexIntroVideo.swift` plus `Resources/RexIntro.mp4` (6s, 1080x1080,
generated on Seedance 2.5 from an existing Higgsfield job). Replaces the static
`RexImage` on `WelcomeStep`.

No video codec on iOS carries alpha reliably, so the clip is rendered on white and
keyed with `.blendMode(.multiply)`: white multiplied against the canvas leaves the
canvas untouched. Works only because the canvas is lighter than every colour in
the artwork. Loops via `AVPlayerLooper`, muted, and falls back to the static
`RexImage` if the asset fails to load.

### 5. Debug flags

Both `#if DEBUG`, following the existing `-RansomStartStep` convention.

- `-RansomPreviewUnlocked 1` starts past onboarding with the seeded `AppModel.preview`
  profile, so the tabs behind the paywall can be inspected without a purchase.
- `-RansomTab <0|1|2>` opens straight onto Home / Progress / Settings. Note: it
  lands reliably on Home and Progress; Settings did not take in testing and is
  worth a look.

---

## Two things that are not bugs, and cannot be fixed in code

**Camera rep counting does not work in the simulator, and never will.** There is
no camera device, so `AVCaptureDevice.default(.builtInWideAngleCamera, ...)`
returns nil and Vision gets no frames. The Mac's built-in webcam does not pass
through to iOS apps. `TESTING.md` §3 says the same. It needs a physical iPhone.

**The paywall cannot complete under `simctl launch`.** The StoreKit configuration
is a *scheme* setting (`Ransom.xcscheme:53`, `StoreKitConfigurationFileReference`
to `Config/Ransom.storekit`), and `simctl` ignores the scheme. With no products
loaded, `SubscriptionManager.purchase()` hits its `guard` and fails with "That
plan isn't available right now." Running from Xcode with ⌘R fixes it. `simctl` has
no way to attach a StoreKit config.

---

## Open, and needing a decision

1. **Device deployment.** Blocks camera rep counting entirely. Two paths: free
   Apple ID with Family Controls and App Groups stripped (camera works, blocking
   does not), or a paid account with bundle IDs repointed to your team (both
   work). Unanswered.
2. **App icons on the apps step.** `ApplicationToken` only exists for apps already
   chosen in the system picker, so no API maps "Instagram" to an icon. Showing
   real logos before selection means bundling Meta's and ByteDance's marks
   yourself. That is a trademark call, not a technical one. Opal almost certainly
   ships bundled logos. See §1 of `COPY-NOTES.md`.
3. **Dead screens.** `GenderStep`, `ReferralStep`, `SocialProofStep` are
   unreferenced. `SocialProofStep` contains **fake testimonials**. Recommend
   cutting all three before this goes near review.
4. **Rex animation is off-model at the end.** He finishes genuinely
   bodybuilder-proportioned, much larger than the in-app mascot. Intended per the
   brief, but may not sit right next to the static Rex. A green-screen version is
   also archived if a different composite is wanted.
5. **Nothing has been committed.** Still on `main`, all work in the working tree.
6. **`CLAUDE.md` is now stale** in two places: the "Green is doing the brand's
   work" open item is done, and the claim that it is app-target-only was wrong.

## Untouched from the original open list

- Swift 6 landmine at `SubscriptionManager.swift:149`.
- Two `AVCaptureSession` Sendable warnings in `PoseRepCounter`.
- `PoseRepCounter` thresholds (`requiredRange = 0.45`, `minimumConfidence = 0.3`)
  are still unmeasured guesses. Expect to tune on a real camera. `TESTING.md` §5
  says lower `requiredRange` first if it feels unresponsive.
- `UserProfile.gender` still dead.
- Promotional offers still need server-side signing.
- Still no tests of any kind.
