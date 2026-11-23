# One-time setup

About an hour on the Mac, 10 minutes on the laptop, 5 on the phone. After this you never need the Mac for v1.

## Before (laptop)

1. Download **Silkscreen** and **VT323** from fonts.google.com. You need `Silkscreen-Regular.ttf`, `Silkscreen-Bold.ttf`, `VT323-Regular.ttf`.
2. GitHub → Settings → Developer settings → Personal access tokens (classic) → new token with `repo` scope. Keep it for the Mac.
3. Put the fonts and this package zip on a USB stick or in iCloud Drive.

## Mac (once)

1. Install **Xcode** from the App Store (start the download the night before). Open it once.
2. Xcode → Settings → Accounts: **+** Apple ID (your developer account), and **+** GitHub (paste the token).
3. File → New → Project → iOS → **App**.
   Product Name `ChallengeTracker` · your Team · Organization Identifier `com.jpsdigital` · SwiftUI · Swift · Storage **SwiftData** · **Include Tests** ticked.
   Save to the **Desktop**, **"Create Git repository" unticked**. Close Xcode.
4. Terminal:
   ```bash
   mkdir -p ~/Developer && cd ~/Developer
   git clone https://github.com/<you>/<repo>.git challenge-tracker
   mv ~/Desktop/ChallengeTracker/* challenge-tracker/
   cd challenge-tracker
   ```
5. Unzip this package into `challenge-tracker` (merge folders). Copy the three fonts into `ChallengeTracker/Resources/Fonts/`.
6. Open `ChallengeTracker.xcodeproj`. Folders in the sidebar must be **blue**. (Yellow = stop and ask.)
7. File → New → Target → **Widget Extension**, name `ChallengeWidget`, untick Live Activity and Configuration App Intent → Finish → Activate.
8. Click the project (top of sidebar). For **both** targets:
   - General → Minimum Deployments → **iOS 26.0**
   - Signing & Capabilities → Automatically manage signing ✓, your Team
   - **+ Capability** → App Groups → `group.com.jpsdigital.challengetracker` (create on the app, tick the same one on the widget)
9. `ChallengeTracker` target → **Info** tab, add:
   - `App Uses Non-Exempt Encryption` = NO
   - `Fonts provided by application`: `Silkscreen-Regular.ttf`, `Silkscreen-Bold.ttf`, `VT323-Regular.ttf`
10. Product → Scheme → Manage Schemes: make sure `ChallengeTracker` has **Shared** ticked (CI needs this).
11. Choose **Any iOS Device**, press ⌘B. Must say *Build Succeeded*.
12. Terminal, in the repo:
    ```bash
    git add -A && git commit -m "Project setup" && git push
    git checkout -b dev && git push -u origin dev
    ```
13. Browser, appstoreconnect.apple.com → Apps → **+** → New App: iOS, any unique name (e.g. "JPS Challenge 2027"), bundle ID `com.jpsdigital.ChallengeTracker`, any SKU.
14. Xcode → Integrate → **Create Workflow…** (or Report navigator ⌘9 → Cloud). Edit the workflow:
    - Start Condition: Branch Changes → **main** only
    - Action: Archive – iOS → TestFlight (Internal Testing Only)
    - Post-Action: TestFlight Internal Testing → group "Me"
    - Grant access to the repo when the browser opens, then **Start Build**. Wait for green.

Done with the Mac.

## Phone (once)

15. App Store Connect → your app → TestFlight → Internal Testing → group "Me": add yourself, turn on automatic distribution.
16. Install **TestFlight**, accept the invite, install the app.

## Laptop (once)

17. Install the GitHub CLI and log in:
    ```powershell
    winget install GitHub.cli
    gh auth login
    ```
18. Clone the repo, then:
    ```bash
    git config core.autocrlf false
    ```

## Every day after that

```bash
cd <repo>
claude
```
Type **go**. Claude Code builds the next step in `docs/plan.md`, checks it compiles on GitHub's Mac, fixes its own errors, and ships it to `main`. About 20 minutes later the update is in TestFlight. Check it on your phone, then type **go** again, or describe a bug.

To change challenges or doses: edit `ChallengeTracker/Resources/challenges.json` (also possible in the GitHub app), commit to `main`, and the next build includes it.
