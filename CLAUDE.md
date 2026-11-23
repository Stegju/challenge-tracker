# Monthly Challenge Tracker

Personal iPhone app (one user, not on the App Store) that turns 2027 into twelve monthly fitness challenges. Full spec: `docs/spec.md`. Visual reference: `docs/design/README.md` and `docs/design/artboards/`. Read both before building any screen.

## Hard constraints

- **Deadline:** v1 on my phone through TestFlight before 1 January 2027. Scope is in spec section 10. Do not build v1.1 features until v1 is done.
- **No local Mac.** I develop on Windows (Surface) and build with Xcode Cloud on every push to `main`. The Mac was used once to create the project and connect Xcode Cloud. You cannot run `xcodebuild`, the simulator or tests here. So:
  - Write conservative Swift that compiles first time: no unreleased APIs, no guessing at signatures. If unsure about an API, say so and choose the boring option.
  - Keep logic in pure Swift types (no SwiftUI or SwiftData imports) inside `Core/`, so it can be unit-tested by Xcode Cloud and reasoned about without a device.
  - After each change, re-read the files you touched for compile errors: missing imports, optionals, `@MainActor`, exhaustive switches, the Swift 6 concurrency checks.
  - You *can* compile: push to `dev` and GitHub Actions builds and tests on a Mac (`.github/workflows/ci.yml`). Use `gh` to watch and read the result (see Workflow).
- **Xcode project file:** the `.xcodeproj` was created on a Mac. Never hand-edit `project.pbxproj`. Put new Swift files in folders the project already syncs (Xcode 16 folder references) or tell me exactly which files need adding.

## Stack

- SwiftUI, SwiftData, iOS 26+, Swift 6 language mode as set by the project.
- WidgetKit (systemMedium) sharing data through an App Group.
- Local notifications only (UNUserNotificationCenter). No server, no Firebase, no third-party packages in v1.
- Fonts: Silkscreen and VT323 (OFL), bundled in `ChallengeTracker/Resources/Fonts/` and registered in Info.plist.

## Architecture

```
ChallengeTracker/
  App/          entry point, tab bar, navigation
  Core/         pure logic, no UI imports: Scoring, Locking, Barbell, Momentum, Catalogue, DateProvider
  Data/         SwiftData models, persistence, JSON backup/restore
  UI/
    Theme/      colours, fonts, NotchedRect, Panel, buttons, ScoreMeter, Atmosphere
    Mascot/     sprite loader (mascot.json) + Canvas renderer
    Barbell/
    Screens/    Home, Year, Pick, ChallengeDetail, Stats, Settings, Debug
  Resources/    challenges.json, mascot.json, Fonts/
ChallengeWidget/
ChallengeTrackerTests/   unit tests for Core/
```

- Everything that reads "now" goes through `DateProvider` so the Settings test date works everywhere (locks, notifications, momentum).
- Scores, totals, plates, momentum and mood are always derived, never stored.
- All tunable numbers (momentum constants, thresholds, lock days) live in one config struct each.

## Design rules

- Match the artboards: exact hex colours, fonts, sizes and copy. No system blue, no rounded corners, no SF Symbols where the design uses pixel icons.
- The mascot is pixel art from `docs/design/mascot.json`. Render it, never redraw or "improve" it.
- Respect Reduce Motion (stop all animation) and Dynamic Type for body text where layout allows.

## Working style

- Small, reviewable steps. One feature per commit with a clear message.
- Unit tests for every Core rule: score formula both directions, clamping, forfeit, redo best-of, lock and baseline windows across month and year boundaries, partial plates, momentum scenarios from spec section 5.
- When the spec is ambiguous or one of its open questions blocks you, ask me. Don't invent rules.
- Keep `docs/spec.md` current when we change a rule.

## Workflow: what to do when I say "go" (or "continue", "next")

1. Read `docs/plan.md` and take the **first unticked step**. If my message names a different task, do that instead.
2. `git checkout dev` (create it from `main` if missing) and `git pull`. Make sure `dev` contains everything in `main`.
3. Implement the step. Small commits with clear messages.
4. `git push origin dev`, then wait for CI: `gh run watch --exit-status $(gh run list --branch dev --limit 1 --json databaseId -q '.[0].databaseId')`.
5. If CI fails: `gh run view --log-failed`, fix, push, wait again. Up to 5 attempts. If still red, stop and tell me what's blocking in plain words.
6. When CI is green: `git checkout main && git merge --ff-only dev && git push origin main`. That push makes Xcode Cloud build and send it to TestFlight (about 20 minutes).
7. Tick the step in `docs/plan.md` (commit that on `dev` and fast-forward `main` again), then stop.
8. Report in at most 4 lines: what changed, what to check on my phone, anything you need me to decide.

Never start the next step without me saying go. Never force-push. Never push directly to `main` except the fast-forward in step 6.

If I report a bug ("the This week panel is cut off", "crash when I finalize"): fix it with the same loop (steps 2 to 6) and don't tick anything.
