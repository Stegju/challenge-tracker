# Build plan

Claude Code works through this list top to bottom, one step per "go". It ticks a box only after the CI build is green and the step is merged to `main` (which ships it to TestFlight). Edit this file freely: reorder, add steps, or add notes under a step.

## v1 (on the phone before 1 January 2027)

- [ ] **0. Pipeline check.** Add a visible "build N" label to the default ContentView, confirm CI passes on `dev`, merge to `main`. Done when I see the label in TestFlight.
- [ ] **1. Core logic + tests.** `Core/`: catalogue loading (challenges.json), slot rules (choose, lock, baseline window, forfeit, exactly 2 redos, Murph fixed to December), scoring, year total, barbell plates incl. partial plate, momentum and mood (spec 5). Pure Swift. Unit tests for every rule and the momentum scenarios.
- [ ] **2. Data.** SwiftData models (spec 9), App Group container, JSON backup/restore, seed 12 slots for 2027.
- [ ] **3. Theme.** Colours, both fonts, NotchedRect, Panel, buttons, label style, ScoreMeter, Atmosphere background (motion off under Reduce Motion). Hidden Debug screen showing all components.
- [ ] **4. Mascot and barbell.** Mascot from Resources/mascot.json (Canvas, crisp pixels, 5 moods, slumped rotated); barbell per spec 4.
- [ ] **5. Home.** Match Main.dc.html, incl. the This week panel and the end-of-month card. "+ workout" action for other workouts.
- [ ] **6. Year + Choose.** Year.dc.html and Pick.dc.html (New / Redo tabs).
- [ ] **7. Challenge detail.** Challenge.dc.html: baseline/target until lock, entries (time, number, weight+reps for e1RM), two-tap finalize.
- [ ] **8. Stats.** Stats.dc.html.
- [ ] **9. Setup + notifications.** Settings.dc.html (test date, backup/restore, reset) and local notifications (spec 7).
- [ ] **10. Widget.** Widget.dc.html, App Group, reload on every save.
- [ ] **11. Pre-flight.** Compare the whole app against spec and artboards, list gaps, fix them.

## v1.1 (after 1 January)

- [ ] HealthKit read-only + suggested entries (needs one more session on the Mac to add the capability).
- [ ] Motra share extension (logging only) + paste import parser with tests against a real export.
- [ ] Exercises page + counted exercises.
