> **Superseded, 3 September 2026.** The copy below was replaced by a warmer,
> Duolingo-style pass that drops the pay/price/guard-the-door framing entirely.
> The current strings live in `Ransom/Ransom/Onboarding/` and `Paywall/`; the
> voice rules are in `CLAUDE.md` under "Rex's voice". Kept for the history.

# Intake copy rewrite

Every user-facing string in the 16-step funnel, before and after. Rules applied
throughout: no em dashes, short sentences, one idea per screen, problem and
solution both visible, all quantities computed from the user's own answers.

**Rex's voice, fixed:** a supportive gym-bro dinosaur. Warm, plain, never sarcastic,
never lets you off the hook. He says what a thing costs and then says you can do it.
Removed every line where he was nagging, judging or showing "no mercy".

---

## 1. Welcome (`IntakeSteps.swift` → `WelcomeStep`)

| | |
|---|---|
| Old | "Instagram, TikTok and the rest stay locked until you move. Rex is the doorman." / "Takes about 60 seconds." |
| New | "You open the apps without thinking. Now they cost push-ups." / "About 60 seconds." |

**Why:** the old line was all mechanism and no problem. The new one names the
problem in sentence one and the solution in sentence two, in eleven words. "Rex is
the doorman" was a metaphor the user hasn't earned yet on screen one.

## 2. Name (`NameStep`)

| | |
|---|---|
| Old | subtitle "Optional. It makes the nagging personal." / Rex: "Or stay anonymous. I'll still block Instagram." / "Nice to meet you, X." |
| New | subtitle "Optional. It just makes him louder." / Rex: "No name? Fine. I still guard the door." / "Good to meet you, X." |

**Why:** "nagging" is the wrong promise for a coach. "Stay anonymous" is a privacy
word on a screen that isn't about privacy. Both new lines are shorter and in voice.

## 3. Apps (`HabitSteps.swift` → `AppsStep`) — rebuilt

| | |
|---|---|
| Old | "What's eating your day?" / "Pick everything that pulls you in. You'll choose the exact apps later." |
| New | "What's taking up most of your time?" / "Tap what pulls you in. You can pick the exact apps later." / footnote: "Nothing gets deleted. Rex just makes you pay to open it." |

**Why:** "eating your day" is idiom, not plain English; the owner asked for the
literal version. Subtitle cut to nine words. The footnote is the screen's
problem/solution pair and pre-empts the single biggest objection ("am I losing my
apps?").

**Structural changes on this screen:**
- Added an **Other** tile that requests Screen Time authorization and presents
  `AppPickerView` (the system `FamilyActivityPicker`). This is the only path that
  can block anything on the phone, and the only surface that shows real app icons.
- Continue now unlocks on either a quick-pick or a system-picker selection.
- A live count ("N picked from your phone.") confirms the picker took. It is
  computed from `screenTime.selection`, not `ScreenTimeManager.hasSelection`, because
  only the mirrored `selection` property is `@Observable`; reading the store would
  have left the tile stuck unchecked after the sheet closed.
- `DistractingApp.x` emoji changed from 🐦 to ✖️ (X has not been a bird for years).

See **Open questions** for the app-icon trademark tradeoff.

## 4. How long (`ScrollLoadStep`) — bedtime question rebuilt

| | |
|---|---|
| Old | "How long, honestly?" / "Screen Time already knows. Say it out loud." Then a chip row: "And when does it get you?" with four multi-select chips (Mornings / Lunch / After work / Late night). |
| New | "How long, honestly?" / "Your phone already knows. Say it out loud." Then, after they answer: **"Do you scroll in bed?"** with the price stated above two cards: "After 10pm, unlocks cost 1.5x the reps. That is the hour Rex charges most for." → "Yes. Most nights." / "No. Phone's down by then." |

**Why:** the chip row was the least important-looking element on the screen and the
most consequential in the codebase — `AppModel.swift:231` reads
`peakTimes.contains(.lateNight)` and nothing else, and that is the only switch for
the 1.5x night tariff. A user could set a surcharge on themselves by tapping a
decorative chip. It is now a named question with the consequence printed before the
answer. The title kept its bluntness because it already worked.

- The multiplier ("1.5") and the window ("10pm") are read from `Tariff.nightSurcharge`
  and `Tariff.nightWindow.start`. Retuning the tariff retunes this sentence.
- The answer is three-state (`Bool?`): "unanswered" and "no" both leave `peakTimes`
  empty, and Continue has to tell them apart. It is held in `OnboardingFlow`, not in
  the step, so stepping back and forward doesn't wipe a "no" and re-ask.
- Only `.lateNight` is written. The other three `TimeOfDay` cases were never read.

## 5. Reality check (`RealityCheckStep`)

| | |
|---|---|
| Old | bullets: "Ransom doesn't delete the apps. / It puts a price on them." · "The price is reps. / Push-ups, jacks, squats — your call." · "You still scroll. / You just arrive slightly stronger." |
| New | "Rex doesn't delete your apps. / He puts a price on them." · "The price is reps. / You pick the move. Rex counts them." · "You still scroll. / You just get stronger first." |

**Why:** the owner is right that this screen is the best one in the funnel, so the
headline, the counting number and "Show me the fix" are untouched. Only three edits:
the em dash in bullet two is gone, the list of three exercises (which contradicts the
exercise step two screens later) became "you pick the move", and "Ransom" became
"Rex" so the character does the talking on the screen that carries the emotion.
"Slightly stronger" undersold it.

## 6. Identity (`CommitmentSteps.swift` → `IdentityStep`) — rewritten

| | |
|---|---|
| Old | "Finish the sentence" / "Pick the one that's most true. Rex will hold you to it." Options: "I'm someone who gets stronger without going to a gym." · "I'm someone who takes their evenings back." · "I'm someone who moves every day." · "I'm someone who finishes what they start." |
| New | "What do you want back?" / "Pick one. Rex holds you to it." Options: "Get strong without a gym." · "Take my evenings back." · "Move every day." · "Finish what I start." |

**Why:** the owner's read is right — it was a personality quiz dropped into a fitness
funnel. "Finish the sentence" is an instruction about the UI, not a question. The
options were 7–9 words each of grammatical scaffolding wrapped around a 3-word idea.
Cutting to the idea makes the screen scannable in about two seconds, which is the
Opal bar.

**The two echoes still work** (`Identity.statement` and `Identity.shortForm` in
`RansomShared/Exercise.swift` were reshaped to keep them working):
- Plan screen: `"You picked: Take my evenings back."`
- Paywall: `"This is how you take your evenings back."` (`shortForm` is now second
  person, verb first, so it drops straight into a sentence).

## 7. Age (`AgeStep`)

| | |
|---|---|
| Old | subtitle "Rex adjusts how hard he pushes." Quips: "Young joints. No excuses." · "Prime rep-earning years." · "Perfect age to start banking reps." · "Consistency beats intensity. Always." |
| New | subtitle "Rex uses this to set how hard he pushes." Quips: "Young joints. This will be easy work." · "Best years to build the habit." · "Great age to start. I mean it." · "Steady beats hard. Every time." |

**Why:** "No excuses" is the drill-sergeant register we're not using. "Prime
rep-earning" and "banking reps" are jargon the user hasn't been taught yet.
"Consistency beats intensity" is a fitness-influencer aphorism; "steady beats hard"
says the same thing at a sixth-grade reading level.

## 8. Height and weight (`BodyStep`)

| | |
|---|---|
| Old | "Used to estimate the calories you burn earning your scroll." |
| New | "So Rex can count the calories you burn earning your scroll." |

**Why:** "used to estimate" is passive and bureaucratic. Rex does it, and he counts.

## 9. Fitness (`FitnessStep`)

| | |
|---|---|
| Old | "How often do you work out right now?" / "Be honest. Rex doesn't judge, he calibrates." Options: "We'll start you gently." · "You've got a base to build on." · "Rex will make it count." |
| New | "How often do you work out now?" / "Be honest. Rex sets your reps from this, not his opinion of you." Options: "Rex will start you easy." · "You have a base to build on." · "Rex can ask for more." |

**Why:** "calibrates" fails the reading-level test. The new subtitle says the same
reassurance in words a twelve-year-old uses, and says *why* honesty pays: the number
you get is built from this answer. "Rex will make it count" sounded like a threat.

## 10. Exercises (`PlanSteps.swift` → `ExercisesStep`)

| | |
|---|---|
| Old | "Pick your currency" / "What you'll do to buy scroll time. Choose at least one — you can swap any time." |
| New | "Pick your moves" / "This is what you'll do to unlock an app. Pick at least one. You can swap them later." |

**Why:** "currency" is a metaphor asking to be decoded on the one screen where the
user needs to just pick a thing. Em dash removed by splitting into two sentences.

**Verified the choice actually flows** (owner asked): `Exercise` already covers
push-ups, jumping jacks, squats, sit-ups and high knees; the step is multi-select and
cannot be emptied; `UserProfile.primaryExercise` picks the hardest selected movement;
`RansomPlan.make` scales the rep target by `effortWeight`; `HomeView` offers every
selected movement with a re-scaled target and `RootView` passes the chosen one into
`WorkoutView`; `AppModel.syncPlanToExtensions` mirrors it to the shield. **One real
gap, now fixed** — see step 12.

## 11. Intensity (`IntensityStep`)

| | |
|---|---|
| Old | subtitle "You can change this whenever. Most people start on Standard." Tariff paragraph: "That's the **first** unlock. The fourth costs double, the sixth triple, and anything after 10pm carries a surcharge. Walk away for three hours and the price resets." |
| New | subtitle "Most people start on Standard. Change it any time." Tariff line, fully computed: "That's your first unlock of the day. Keep going back and the price climbs. By your 6th it's 30 push-ups. After 10pm it costs 1.5x more, because you told Rex you scroll in bed. Stay off the apps for 3 hours and the price drops back down." |
| Also | `Intensity` blurbs: "Easing in. Short sets, generous scroll time." → "Short sets. Plenty of scroll time."; "Rex shows no mercy. Earn every single minute." → "Big sets. You earn every minute." |

**Why:** the old paragraph hardcoded *four*, *double*, *sixth*, *triple*, *10pm* and
*three hours* — six written numbers describing a ladder that lives in
`Tariff.ladder`, `Tariff.nightWindow` and `Tariff.coolDown`. Any tariff change would
have made the screen lie. The new line derives all of them, and quotes the top of the
ladder **in the user's own reps and their own movement** rather than as a multiplier,
which is the reality-check trick applied to pricing: "30 push-ups" lands, "triple"
doesn't. The night clause only appears if they said yes on step 4, so it reads as a
consequence of their own answer.

"No mercy" was the last of Rex's mean register.

## 12. First rep (`FirstRepStep`) — bug fixed

| | |
|---|---|
| Old | "Five. Right now." / "Not for scroll time. Just so we both know you can." / counter hint "Phone on the floor. We'll wait." / button "I'm on the floor" / "Not here" / payoff "There's about N more in your first month." |
| New | "5 squats. Right now." (movement and count both computed) / same second line / counter hint is `exercise.coachingCue` / button "I'm on the floor" or "I'm up. Let's go" / "Not right now" / payoff "About N more in your first month. You just did the hard part." |

**Why (this was a real defect, not a copy issue):** the screen hardcoded push-ups.
Someone who picked squats two screens earlier was told to get on the floor and shown
Rex doing push-ups. The step now reads `profile.primaryExercise` for its headline,
its coaching cue and its button, and Rex only mimes push-ups when push-ups were
chosen (he has no other animation, so he coaches instead of performing the wrong
movement). "Not here" was ambiguous; "Not right now" is the actual meaning and keeps
the no-scolding skip path intact.

The target of five stays literal: it is a fixed product rule, not a projection, and
it is interpolated from the constant so the copy can't drift from the counter.

## 13. Notifications (`NotificationsStep`)

| | |
|---|---|
| Old | Rex: "One nudge a day if you go quiet. That's the whole deal — I'm not going to blow up your phone." / "Let Rex check in?" / "A reminder when your earned time runs out, and one evening nudge if you haven't moved." |
| New | Rex: "One nudge a day if you go quiet. That's the whole deal. I'm not going to blow up your phone." / "Can Rex check in?" / "You get a ping when your earned time runs out. And one at night if you haven't moved." |

**Why:** em dash out. "Let Rex" is permission-granting phrasing that makes the user
the gatekeeper of a favour; "Can Rex" makes him ask. The old subtitle was one 19-word
sentence with a comma splice; it is now two short ones, and "you get" puts the
benefit on the user's side of the sentence.

## 14. Building the plan (`BuildingPlanStep`)

| | |
|---|---|
| Old | "Reading your answers" · "Calibrating rep targets" · "Setting your unlock price" · "Briefing Rex" |
| New | "Reading your answers" · "Setting your rep target" · "Pricing your unlocks" · "Waking up Rex" |

**Why:** "calibrating" and "briefing" are both above the reading level and both
slightly corporate. The new list is four verbs anyone knows, and "waking up Rex" is
the only joke on a screen that is otherwise theatre.

## 15. Plan reveal (`PlanRevealStep`)

| | |
|---|---|
| Old | subtitle "You said: I'm someone who takes their evenings back." · metrics "daily goal" (brand) / "saved per day" (flame) · "Nh not scrolled" (brand) · caption "Two lines that move at once. Hours down, reps up." · chart "Projected screen time" (brand) · Rex: "That's about N jacks in week one, if you scroll like you say you do. See you on the floor." |
| New | subtitle "You picked: Take my evenings back." · metrics "daily goal" (brand) / "back in your day" (**green**) · "Nh you get back" (**green**) · caption "Hours down. Reps up." · chart "Your screen time from here" (**green** line, fill and week-4 label) · Rex: "About N jacks in week one. That's the whole plan. See you tomorrow." |

**Why:** the screen is the payoff and was painted entirely in the cost colour. Under
the retuned palette rule — brand for chrome, selection, identity and cost; green
strictly for earned/unlocked/win — the two win figures (minutes back, hours back) and
the falling projection line are exactly what green is for. The reps stay tangerine
because reps are the price. No chrome was changed and `Core/Theme.swift` was not
touched.

"Not scrolled" is a negative; "you get back" is the same number as a gain. "Two lines
that move at once" describes the chart instead of the outcome. "If you scroll like
you say you do" hedged the promise at the exact moment it needed to land.

**Projection fix (rule 6).** `projectionCard` carried its own copy of the
35%-over-four-weeks constant: `baseline * (1 - 0.35 * (week / 4))`. It happened to
agree with `RansomPlan.reduction(onDay:)` today, but retuning the curve would have
left the picture contradicting the numbers stacked directly above it — the exact
failure CLAUDE.md records. The chart now reads the curve through the existing public
API:

```swift
let savedThatDay = plan.projectedHoursSaved(overDays: day + 1)
                 - plan.projectedHoursSaved(overDays: day)
return max(0, plan.hoursPerDay - savedThatDay)
```

Identical values today, single source of truth from now on, and no change to
`Core/Models.swift` logic.

## 16. Paywall (`Paywall/PaywallView.swift`)

| | |
|---|---|
| Old | subtitle "Keep being evenings back." / fallback "The whole point of the app." · "Block any app you choose" / "Instagram, TikTok, games — as many as you like." · "The price rises the more you come back." · "Lifetime totals, streaks and hours saved." |
| New | subtitle "This is how you take your evenings back." / fallback "Earn your scroll." · "Lock any app you want" / "Instagram, TikTok, games. As many as you want." · "Come back too often and the price goes up." · "See your streak and the hours you got back." |

**Why:** the identity echo was grammatically broken for two of the four options
("Keep being evanings back", "Keep being finishing what you start") — reshaping
`shortForm` fixes all four. Em dash removed. "The price rises" is passive and
formal; "come back too often and the price goes up" states the rule as cause and
effect. "Lifetime totals" is accounting language on a consumer paywall.

---

## Outside the funnel

Em-dash sweep across every user-facing string in the app. Copy-only, no logic:

- `Home/HomeView.swift:93` — "Go enjoy it — I'll be here" → "Go enjoy it. I'll be here"
- `Workout/WorkoutCompleteView.swift:78` — "count toward today — the time doesn't" → "count toward today. The time doesn't."
- `Workout/RepEngine.swift` ×3 — "No proximity sensor here — tap the screen" → "No proximity sensor here. Tap the screen"; "Motion unavailable — tap the screen" → "No motion sensor here. Tap the screen" (also fixes "unavailable", which is above the reading level)
- `RansomShared/Tariff.swift:75` — "3rd today — the break earned you a tier back." → "3rd today. The break earned you a tier back."

A string-literal scan of the whole repo now returns em dashes in exactly one file:
see below.

---

## Open questions and things not done

### 1. Real app icons: a trademark decision, not an engineering one

**The constraint is real.** Apple's FamilyControls framework deliberately prevents an
app from displaying arbitrary third-party app icons. The only supported way to render
one is `Label(ApplicationToken)`, and an `ApplicationToken` is an opaque, per-install
value that exists *only* for apps the user has already selected inside the system
`FamilyActivityPicker`. There is no API that maps "Instagram" to an icon. This is a
privacy design, not an oversight: it stops apps from enumerating what you have
installed.

So showing Instagram's real icon **before** the user picks anything requires bundling
our own copy of Meta's logo in `Assets.xcassets`. (The asset catalog currently
contains only Rex and the app icon — no third-party marks. Verified.)

**What I implemented — the technically clean version:**
- The quick-pick grid keeps emoji stand-ins and plain names ("Instagram", "TikTok").
  Nominative use of a name to identify the real thing is the low-risk end of this;
  reproducing a logo is not.
- An **Other** tile requests Screen Time access and opens `FamilyActivityPicker`,
  which renders the real icons *and* covers every app on the phone, including ones
  the grid will never list.

**Recommendation:** ship as built and put the logo question in front of a lawyer
before bundling any marks. If the owner decides to bundle them, the mechanics are a
one-line change per tile (swap `Text(app.emoji)` for `Image(app.assetName)`), but
three things need answering first: (a) each platform's brand-asset terms — several
forbid use that implies partnership or endorsement, and "here are the apps we help
you block" is arguably adversarial use; (b) App Review, which rejects apps
misrepresenting a relationship with another brand; (c) maintenance, since logos are
refreshed and a stale one looks worse than an emoji. A middle path worth considering:
monochrome glyphs in Rex's tangerine that suggest the app without reproducing the
mark.

### 2. Two em dashes I could not remove

`Workout/PoseRepCounter.swift:161` and `:177` — "Get lower — chest toward the floor."
and "Deeper — hips to knee height." Both are user-facing form hints. The file is
owned by another in-flight change, so I left them. **They need the same fix:** "Get
lower. Chest toward the floor." and "Go deeper. Hips to knee height."

### 3. Files I edited outside the strict list

`RansomShared/Exercise.swift` (Identity statements and `shortForm`, Intensity blurbs,
FitnessLevel subtitles) and `RansomShared/Tariff.swift` (one quote explanation). These
are display strings for enums the funnel renders; the identity rewrite is impossible
without them. No logic, no cases added or removed, no signatures changed. Flagging
because `RansomShared` compiles into all four targets, so the shield sees the Tariff
string too — which is the point, since the shield is where that line is read.

### 4. Screens not in the 16

`GenderStep`, `ReferralStep` and `SocialProofStep` are all unreferenced by
`OnboardingFlow`. I tidied their copy (a few words each) rather than delete them,
since deletion is a product call. `UserProfile.gender` and `GenderStep` are already
flagged as dead in CLAUDE.md and TESTING.md — they should probably go.

`SocialProofStep` carries two invented testimonials with names and a specific rep
count ("I've done 1,400 push-ups this month"). If that screen is ever put back in the
funnel, those need to be real or removed. I left the text alone apart from replacing
the attribution em dash with an en dash, because rewriting fake testimonials to sound
better is the wrong direction.

### 5. `FlowChips` is now unused

The bedtime rework was the only caller. The component still compiles and is generally
useful, so I left it in `Components/`. Delete it if nothing else claims it.

### 6. Not verified at runtime

Per CLAUDE.md, nothing here has been exercised. The build passes; the funnel has not
been walked. Two things specifically want a device pass:
- The **Other** tile calls `requestAuthorization()` and only presents the sheet on
  success. On a simulator this always fails (Screen Time is a stub), so the tile will
  appear inert. That is correct behaviour but looks like a bug during a simulator demo.
- The bedtime question adds height to the hours screen. It scrolls, but the two cards
  plus the price line should be checked on the smallest supported device.

---

**Build:** `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**. Not installed or launched.
