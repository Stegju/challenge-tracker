# Monthly Challenge Tracker: spec (v2, 22 Nov 2026)

Personal iPhone app, one user (Julian), not for the App Store. 2027 becomes twelve monthly fitness challenges. Each month has one locked target, a scored result, and a barbell that gains plates as points add up. Hypertrophy training runs underneath and is not a challenge.

**Deadline: v1 installed and usable via TestFlight before 1 January 2027.**

Visual reference: `docs/design/` (read `docs/design/README.md` first).

---

## 1. Core loop

1. Before the 1st, pick next month's challenge from the catalogue (or pick a redo).
2. Set baseline (optional until day 3) and target.
3. At 00:00 on the 1st the challenge locks. Baseline and target stay editable through day 7 (a test week), or until locked in by hand, then freeze.
4. Log entries during the month. The best entry is the result.
5. Finalize (two taps). Score 0 to 120.
6. Points add to the year total, which drives the barbell. The mascot reacts to *momentum* (training consistency and recent progress), not to the score.

## 2. Challenge catalogue (hard-coded, not user-editable in the app)

- Lives in `ChallengeTracker/Resources/challenges.json`, bundled in the app. Julian edits it in the repo and pushes; the next build ships it.
- Each entry defines: `id`, `name`, `domain` (strength | speed | endurance | physique | hybrid), `metric` (number | time | e1rm), `unit`, `direction` (higher | lower), `weeklyDose` (`{ "unit": "sessions", "amount": 3 }`), `countedExercises` (normalized exercise names that feed this challenge from imports), optional `fixedMonth`, optional `notes`.
- Metric input: `time` is typed as h:mm:ss or mm:ss and stored in seconds. `e1rm` is typed as weight + reps; the entry stores e1RM in kg, $w(1 + r/30)$, rounded to 0.5 kg, and keeps the raw weight and reps. `number` is stored as typed (decimal comma accepted).

**The 2027 catalogue (final):**

| Challenge | Domain | Metric | Better |
|---|---|---|---|
| HYROX race | hybrid | time | lower |
| Max push-ups | strength | reps | higher |
| Bench press | strength | e1RM, kg | higher |
| 2K row | speed | time | lower |
| The cut | physique | estimated body fat % | lower |
| 5K run | speed | time | lower |
| Long bike ride | endurance | km, single ride | higher |
| Long run | endurance | km, single run | higher |
| Max pull-ups | strength | reps | higher |
| Murph | hybrid | time | lower, **boss, fixed to December** |

10 challenges + 2 redos = exactly 12 slots, so every challenge gets used once and both redos get used.
- The user never types name, domain, metric, unit, direction or weekly dose. The user only enters **baseline, target, entries, and finalizes the result**.
- Slots reference catalogue entries by `id`. Keep a snapshot of the catalogue entry on the slot at lock time, so later edits to the JSON never change a locked or finished month.
- Optional later: fetch an override JSON from a URL on launch, cache it, fall back to the bundled file. Not in v1.

## 3. Rules and scoring

1. 12 slots, Jan to Dec 2027. Each is a new challenge or a redo. Exactly 2 redos per year (10 challenges fill the other 10). Murph is pre-assigned to December and cannot be picked or redone. January cannot be a redo. If the remaining open months equal the remaining required picks, the picker says so (e.g. "3 months left: 1 challenge + 2 redos").
2. **Choosing:** any time before the 1st, from the picker (see screens). Redos are chosen exactly like new challenges, typically the month before. Nothing is pre-assigned.
3. **New tab** lists catalogue challenges not yet used this year. **Redo tab** lists challenges already finished this year with their score. A challenge already at 120 is shown but disabled (cannot improve).
4. **Lock:** at 00:00 local on the 1st the challenge freezes. Baseline and target can be entered or changed until the end of day 7 (`LockConfig.setupDays`), then freeze. A two-tap LOCK IN freezes them earlier. Entries can be logged from the 1st.
5. **Forfeit:** no challenge on the 1st, or no baseline or no target at the end of day 7, scores 0.
6. **Result:** best entry. Best = highest if direction is higher, lowest if lower. Finalize = two taps (arm, confirm), then permanent.
7. **Redo:** reuses the earlier slot's baseline and target. The better score of the two attempts counts toward the total, once. The redo month adds no points of its own.
8. December is the boss month: Murph, scored like any other, shown in red throughout the UI.

Score for one challenge (works for both directions because of the sign of target minus baseline):

$$\text{score} = \text{clamp}_{[0,120]}\left(100 \cdot \frac{\text{result} - \text{baseline}}{\text{target} - \text{baseline}}\right)$$

Validation: refuse to lock a slot where target equals baseline, or where the target is on the wrong side of the baseline for the challenge's direction.

Year total = sum over finished challenges, redo pairs counted once with the better score. Max is 1200; 1000 is "a full bar" (10 plates per side), not a cap.

## 4. Barbell (exact, with partial plates)

- One full plate per side per 100 points, max 10.
- The remainder is drawn as a **partial plate**: same tier colour and thickness as the next plate, height = 120 × (remainder / 100), vertically centred, min 4 units if remainder > 0, with a faint dashed outline of the full-size plate around it.
- Tiers step every 2 plates: white `#F2F2F2`, green `#3ECF6A`, yellow `#F5D33B`, blue `#3D8BFF`, red `#FF4D4D`. Thickness by tier: 7, 9, 11, 13, 15. Heavier plates sit closer to the centre.
- Geometry and logic: `docs/design/artboards/Barbell.dc.html` (see its script block).

## 5. Mascot: 5 moods driven by momentum

Pixel sprites: `docs/design/mascot.json` (40×40 grids with palettes). Render with a SwiftUI `Canvas`, nearest-neighbour, no smoothing.

| Mood | Plate colour | Pose | Momentum m |
|---|---|---|---|
| onfire | red | flames on top, flexing both arms, gritted grin | ≥ 1.15 |
| pumped | lime | both arms up, ^^ eyes, open grin, sparkles | 0.85 to 1.15 |
| steady | blue | waving, smile | 0.60 to 0.85 |
| tired | yellow | arms hanging, half-closed eyes, sweat drops | 0.30 to 0.60 |
| slumped | grey | tilted, closed eyes, frown, Z's | < 0.30 |

Daily update (run on app open and from a background refresh; compute for every missed day in order):

$$a_t = \min\left(1.1,\ \frac{\text{challengeSessions}_{7d} + 0.5 \cdot \text{otherWorkouts}_{7d}}{\text{weeklyDose}}\right)$$

$$g_t = \max\big(0.8\, g_{t-1},\ \mathbb{1}[\text{new best entry on day } t]\big)$$

$$x_t = a_t + 0.25\, g_t, \qquad m_t = 0.3\, x_t + 0.7\, m_{t-1}, \qquad m_0 = 0.6$$

- Hysteresis: only change mood when m crosses a threshold by at least 0.05, and hold any mood at least 1 day.
- A finished month overrides: target hit → pumped for the rest of that month's display; under 50 points → tired.
- **Tap the mascot** to show one line of explanation, e.g. "3/3 sessions this week · new best 4 days ago". This matters more than the exact constants.
- All constants (0.5, 1.1, 0.8, 0.25, 0.3, thresholds) live in one `MomentumConfig` struct so they can be tuned.
- Simulated behaviour (dose 3): 3/wk no PR → pumped; 2/wk → steady; stop training → steady after ~1 day, tired ~4 days, slumped ~7 days; 4/wk + PR → on fire for about a week, then pumped.

## 6. Screens

All screens: dark pixel-arcade gym look (see design README). Tab bar: Home, Year, Stats, Import, Setup. Challenge detail, Pick and Exercises are pushed screens.

**Countdown (Home before 1 Jan 2027)**: neon 2027 sign, live countdown (days : hours : min : sec), mascot, a January card (CHOOSE / EDIT JANUARY, with baseline and target tiles) so January is set before it locks, the December boss card, "+ LOG WORKOUT", and ENTER TEST MODE.

**Test mode**: a separate demo year (sandbox store) at a pretend date, default 14 Mar 2027, pre-filled like the artboards (Jan 5K 81, Feb bench 120, Mar pull-ups live at 50). Everything can be tapped, logged and finalized; the real year is never touched. A yellow banner on every screen shows the pretend date and EXIT. Setup has the switch, the date and REFILL DEMO DATA. Widget and notifications always use the real year.

**Home** (`Main.dc.html`)
- Top row: total (`201/1000`), flickering neon "2027" sign (placeholder text; app has no name yet), redo count `0/2` with two outline pips.
- Month strip: 12 cells. Done = lime fill, current = lime outline pulsing, open = dim outline, December = red outline with glow. No legend.
- Mascot (hops/bobs) with a speech bubble: mood label + one-line status.
- Current challenge card: month + domain, days left, name, big `best / target`, "from baseline", score meter (plate colours, white tick at 100, scale 0 to 120), buttons LOG ENTRY and DETAILS.
- **This week** panel: 7 day columns M to S. Every workout is a block: lime = challenge session, blue = any other workout. One workout = one block; blocks only stack when 2+ workouts happen that day, so the panel height grows only then. Rest day = thin grey line. Today: letter highlighted (white background, dark letter); if no workout yet today, an empty block with a white 2 px outline, same size as a workout block. Summary "2/3 CHALLENGE · 4 OTHER". Momentum number with trend arrow. Key underneath: CHALLENGE, OTHER WORKOUT, TODAY.
- Next-month card appears **only in the last 3 days before the next lock** (or always if the next slot is empty and lock is within 3 days): "APRIL LOCKS IN 2 DAYS" + CHOOSE → Pick.

**Year** (`Year.dc.html`): 12 rows: month, challenge name, right side = points (finished/current), CHOOSE chip (next open month), OPEN (later months, dimmed), BOSS (December, red). No redo banner. Tapping an open month → Pick; tapping a chosen month → Challenge detail.

**Pick** (`Pick.dc.html`): header "CHOOSE APRIL", "LOCKS 1 APR 00:00". Tabs NEW (n left) / REDO (n left of 2). NEW lists unused catalogue entries with domain, metric and direction. REDO lists finished challenges with their score; maxed ones disabled. Selecting one enables the bottom button "SET X FOR APRIL". Then go to Challenge detail to enter baseline and target.

**Challenge detail** (`Challenge.dc.html`): read-only card from the catalogue (name, domain, metric, weekly dose), baseline and target tiles (editable until lock; baseline until day 3), lock status line, entries list (date, value, source MANUAL/HEALTHKIT/MOTRA; best highlighted), add entry row, result, score preview, two-tap finalize.

**Stats** (`Stats.dc.html`): barbell with partial plate and "2.01 PLATES / SIDE", next plate countdown, radar by domain (average improvement over baseline per domain, live months included; outer ring = next 10 % step above the best domain), score per month bars, start → end table.

**Import** (`Import.dc.html`, v1.1): paste from clipboard (share extension later), parsed summary (name, date, duration, volume, kcal), matched Watch workout, a row "6 exercises · 1 counts for March" that opens **Exercises**, suggested entry, ADD ENTRY / SETS ONLY.

**Exercises** (`Exercises.dc.html`, v1.1): every parsed exercise as a card with all sets; warm-up and drop sets shown dimmed and never counted; best set or e1RM; toggle "COUNTS · MAR" per exercise (writes to the slot's counted exercises).

**Setup** (`Settings.dc.html`): short rules, notification toggles, HealthKit (v1.1), widget help, test date (simulate a date to check locks; never mutates data), JSON export/restore, reset year (two-tap, red).

**Widget** (`Widget.dc.html`, systemMedium): before 1 Jan 2027 it shows "2027 STARTS IN n DAYS" and January's pick. During the year: left = mascot + mood label; right = "MAR · PULL-UPS", big `15 / 18`, score meter, "17D LEFT" and "201 PTS". No barbell. Shares data through an App Group; reload timeline whenever an entry is saved.

## 7. Notifications (local only)

- 7 and 2 days before a lock if the next slot is empty.
- Day 1 and day 6 if baseline or target is blank.
- 3 days before month end if no entries.
- Day after month end if not finalized.
- Optional: mascot drops to tired or slumped.

## 8. Imports

**Automatic tracking per challenge (24 Nov):**

| Challenge | Entry | Sessions (momentum) |
|---|---|---|
| Long run / long ride | longest outdoor run / ride in Health (indoor flag excluded) | runs / rides |
| 5K run | fastest 5 km stretch inside any run (distance samples), else a 5 km run scaled | runs |
| 2K row | a 1.98–2.2 km row, time scaled (Concept2 app → Health) | rows |
| Bench / push-ups / pull-ups | Motra: best set of the month's chosen exercise (one entry per workout) | Motra sessions with that exercise |
| HYROX | typed in by hand | every Health workout except strength training and boxing |
| Murph | typed in by hand | runs, strength (incl. Motra) and HIIT |
| The cut | typed in by hand (eye test) | none |

Motra share extension: saves text, links and images to the App Group inbox; the app reads the text, then text recognized in images, then the shared web page.

### Original notes

- HealthKit read-only: workouts, distance, duration, heart rate, energy. Used to suggest entries and to count "other workouts" for momentum. Never auto-finalizes.
- Motra text import. First ship a tiny share extension that only logs what Motra sends (text, link, or both). Paste is the fallback.
- Parsing: header (name, then a date like "16 Nov 2026 at 6:15"), summary lines (duration, volume like "6,3K kg", calories, exercise count), exercise name lines followed by set lines like "1: 9 reps x 80 kg". "Warm Up" and "Drop Set" labels kept but excluded from best-set logic. Decimal commas. "BW" = bodyweight, rep-only. Footer and link ignored. Unit tests against a real export.
- Match a Watch workout whose start is within ~15 min and duration is close; else keep sets and ask.
- e1RM = w (1 + r/30), flagged unreliable above 10 reps.

Until HealthKit exists (v1), "other workouts" for the This week panel and momentum are logged manually with a quick "+ workout" action (type optional).

## 9. Data model (iOS 26+)

Stored as Codable JSON files in the App Group container (`year2027.json`, `sandbox2027.json`, `settings.json`, `widget.json`) rather than SwiftData: one small document a year, tolerant decoding instead of schema migrations, and the backup file is the same format. Types live in `Core/Model.swift`.

Derived, never stored: scores, totals, plates, momentum, mood.

- `Slot`: month 1–12, type (new | redo), challengeId, catalogue snapshot (JSON), sourceSlot (redo), baseline?, target?, finalResult?, isFinal, lockedAt?
- `Entry`: slot, date, value (time values in seconds), source (manual | healthkit | motra), workoutRef?
- `Workout`: date, kind (challenge | other), source, healthKitId?, duration?, notes?
- `ParsedSet` (v1.1): workout, exercise (normalized), setType (normal | warmup | drop), reps, weightKg? (nil = bodyweight)
- `MomentumState`: date, m, g (one row per day, so the history can be inspected and tuned)
- `Settings`: notification toggles, testDate?, onboarding flags
- App Group container shared with the widget.

## 10. Build order

**v1 (by 1 Jan):** catalogue loading, 12 slots, picker (new/redo), lock rules with test date, entries + finalize + scoring, Home incl. This week (manual other-workout logging), Year, Challenge detail, Stats with barbell, mascot (5 moods + momentum + tap to explain), local notifications, medium widget, JSON backup/restore, hidden debug screen (log viewer, state dump).

**v1.1:** HealthKit read + suggestions, Motra import + share extension, Exercises page, counted exercises.

**Later:** iCloud sync, lock screen widgets, Watch complication, Live Activity for race day.

## 11. Open questions

- [x] Baseline/target timing: settled 24 Nov as a 7-day test week plus manual lock-in (rules 4 and 5).
- [x] Momentum calibration: a = (challenge + 0.5 · other) / (dose + 0.5 · normal other per week), with "other workouts in a normal week" set in Setup (default 4). A normal week sits at m ≈ 1.0 (pumped); a new best gives about a week of on fire (progress weight raised from 0.25 to 0.5).
- [ ] Logging an entry also logs a challenge session for that day (if none yet). Confirm that's wanted.
- [x] Motra parser tested against a real export (ParserTests.realExport). Imports add the matching entry automatically.

- [ ] Weekly dose per challenge (all placeholders at 3 sessions). The cut needs a different dose unit, e.g. days on plan or weigh-ins.
- [ ] Murph standard: vest or not, partitioned or not.
- [ ] Bodyweight sets: add body weight to e1RM or keep rep-only?
- [ ] What does Motra's share button send?
- [ ] Is forfeit (empty at lock = 0) too harsh?
- [ ] Bench: barbell only, or machine presses too?
- [ ] Stats month bars: does a redo month show its own attempt, or move the improvement onto the original month?
