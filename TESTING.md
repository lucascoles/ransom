# Running Ransom in Xcode

**None of this Swift has ever been compiled.** It was written on a Linux container
with no Swift toolchain, so treat the first build as a bug-fixing session, not a
run. Everything below is about getting to that first build with the fewest
surprises.

Open `ios/Ransom/Ransom.xcodeproj`. Ignore `project.yml` — it's an XcodeGen
fallback for regenerating the project if the `.pbxproj` ever gets mangled by a
merge. The checked-in project file is the real one.

---

## 1. What your Apple account allows

This is the part that decides how far you can get, so read it before changing
anything.

The app uses **Family Controls** (Apple's Screen Time API) and an **App Group**
shared between the app and three extensions. Both are paid-account capabilities.

| Account | What you can do |
|---|---|
| Free Apple ID (personal team) | Neither Family Controls nor App Groups are available. You cannot build this as-is. See §4. |
| Paid Developer Program | Enable both capabilities on your own bundle IDs and run on a real device. |

Family Controls has a second catch: the **development** entitlement is granted
when you add the capability in Xcode, but the **distribution** entitlement needs a
request form to Apple and takes days-to-weeks. That only matters for TestFlight
and the App Store, not for running on your own device.

## 2. Four targets, four bundle IDs

`com.ransom.app` is not registered to your team, so automatic signing will fail
on all four targets until you change the prefix. In **Signing & Capabilities**,
set your team and rename:

```
com.ransom.app              →  com.<you>.ransom
com.ransom.app.shield       →  com.<you>.ransom.shield
com.ransom.app.shieldaction →  com.<you>.ransom.shieldaction
com.ransom.app.monitor      →  com.<you>.ransom.monitor
```

Then update the App Group. It's referenced in four `.entitlements` files under
`Config/` and once in code:

- `RansomShared/RansomConstants.swift` → `RansomCore.appGroup`

All five must match exactly, or the app and its extensions will silently read
different state — the app will think you've earned time and the shield will
think you haven't.

## 3. What works where

| | Simulator | Real device |
|---|---|---|
| Intake flow, plan, paywall UI | yes | yes |
| Rex, stats, settings | yes | yes |
| StoreKit purchases | yes, via `Config/Ransom.storekit` | yes |
| Camera rep counting | **no** — no camera | yes |
| Motion rep counting | **no** — no sensors | yes |
| Blocking Instagram et al. | **no** — Screen Time is a stub | yes |

So: the simulator is for looking at the app, a device is for testing whether it
works. The `Ransom` scheme already points at `Config/Ransom.storekit`, so the
paywall runs against the local store with no App Store Connect setup — both
products carry a 3-day trial.

## 4. If you only have a free Apple ID

You can still see the whole intake funnel and the paid UI, which is most of what
there is to look at right now:

1. Select the **Ransom** target → Signing & Capabilities → remove **Family
   Controls** and **App Groups**.
2. Delete the three extension targets from the scheme's build phases (or from
   the project — they're independent of the app's UI).
3. Set `CODE_SIGN_ENTITLEMENTS` to empty for the app target.
4. Build to a simulator.

`ScreenTimeManager` will fail authorization and the shield will never appear, but
nothing else depends on it. Everything in §3's first two rows still runs.

## 5. Rep counting on a device

`Workout/PoseRepCounter.swift` counts reps with Vision's body-pose detection off
the front camera, entirely on-device — no video is recorded or uploaded. The
thresholds in it (`requiredRange = 0.45`, `minimumConfidence = 0.3`) are reasoned,
not measured. Expect to tune them against your own camera angle and lighting; a
rep that doesn't travel far enough is rejected on purpose, so if it feels
unresponsive, lower `requiredRange` first.

Prop the phone against something at floor level, roughly at your head. Manual
rep entry (`registerManualRep()`) always works as an escape hatch.

## 6. Known gaps

- `UserProfile.gender` and `GenderStep` are dead — the question was cut from the
  funnel but the field and its screen are still in the source.
- Promotional offers (the loyalty discount) need server-side signing that doesn't
  exist yet.
- Tariff copy and projections were verified against the HTML prototype, not
  against a running app.
