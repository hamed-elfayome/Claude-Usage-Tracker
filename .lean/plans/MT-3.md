### MT-3 — Current-pair detection, saved-window projection, group-move event, Teams rows (pure)

Size: M
Risk: normal
Importance: high
After: MT-1

**Goal:** The cross-account pure logic: decide the current pair from a probe round (spec
`docs/specs/multi-team-tracking.md` §4), project saved windows after their reset (§5), build the one grouped
event for a group move (§6 "Grouped move"), and build the sorted rows the Teams list shows (§11). No network,
no singletons, `now` always injected.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/CurrentPairDetector.swift`
- NEW `Claude Usage/Shared/MultiTeam/PairView.swift`
- NEW `Claude Usage/Shared/MultiTeam/GroupMoveAggregator.swift`
- NEW `Claude Usage/Shared/MultiTeam/TeamRows.swift`
- NEW tests `Claude UsageTests/CurrentPairDetectorTests.swift`, `PairViewTests.swift`, `GroupMoveAggregatorTests.swift`, `TeamRowsTests.swift`
- Read only: `MultiTeam/TeamTrackingModels.swift`, `Claude UsageTests/Fixtures/TeamFixtures.swift`, `Shared/Models/ClaudeUsage.swift`.

Do not edit `AccountRules.swift`, `CredentialOrgParser.swift` (MT-2) or any Localizable file.

**Steps**
1. `CurrentPairDetector`:
   ```swift
   struct RoundCandidate { let pair: PairRef; let previous: RoundReading?; let latest: ClaudeUsage?; let latestAt: Date? }
   struct RoundInput { let now: Date; let current: PairRef?; let manualPickAt: Date?; let lastRoundAt: Date?; let candidates: [RoundCandidate] }  // candidates in (profile order, org order)
   struct RoundOutput: Equatable { let current: PairRef?; let switched: Bool; let readings: [PairRef: RoundReading]; let rises: [PairRef: Double]; let clearManualPick: Bool }
   enum CurrentPairDetector { static let minRise = 1.0; static let tieEpsilon = 0.05; static let staleAfter: TimeInterval = 450
     static func metric(_ u: ClaudeUsage) -> (percent: Double, reset: Date)
     static func rise(previous: RoundReading?, latest: RoundReading) -> Double?   // nil = re-baseline only
     static func evaluate(_ input: RoundInput) -> RoundOutput }
   ```
   Rules exactly as spec §4 (metric, rise, decision, manual pick: if `manualPickAt != nil` and
   (`lastRoundAt == nil` or `manualPickAt > lastRoundAt`) → readings only, no switch, `clearManualPick = true`).
   A candidate with `latest == nil` gets no reading and no rise. Same-window tolerance = `ResetDetection.tolerance`.
2. `PairView` (struct) with `static func make(usage: ClaudeUsage?, sampledAt: Date?, now: Date) -> PairView`:
   fields `sessionPercent: Double?` (nil without a 5-hour window), `weeklyPercent: Double?`, `sessionProjected`,
   `weeklyProjected`, `sessionLeft`, `weeklyLeft`, `headroom: Double?` — rules spec §5; clamp 0…100.
3. `GroupMoveAggregator.event(from orgId: String, trigger: UUID, triggerTarget: String?, peers: [UUID: PeerOutcome], names: [String: String], now: Date) -> TeamEvent`,
   `enum PeerOutcome: Equatable { case moved(to: String?), notMoved, unchecked }`. Builds `.groupMove(from:to:moves:notMoved:unchecked:)`
   with the trigger in `moves` and `to = mostCommonTarget(moves, trigger:)`;
   `static func mostCommonTarget(_ moves: [UUID: String?], trigger: UUID) -> String?` (ties → trigger's target).
4. `TeamRows`:
   ```swift
   struct TeamRow: Identifiable, Equatable { let id: String; let pair: PairRef; let profileName: String; let orgName: String
     let isCurrent: Bool; let view: PairView; let lastSampleAt: Date?; let state: State; let deleteAfterDays: Int?
     enum State: Equatable { case ok, needsLogin, notSignedIn, old, unreachable } }
   static func build(profiles: [Profile], global: TeamTrackingGlobalState, hasCredential: (Profile) -> Bool, now: Date) -> [TeamRow]
   ```
   Only anthropic profiles with `orgTracking`. Order (spec §11): current row; then `.ok` rows by headroom desc,
   weekly left desc, "profile · org" asc (nil headroom last); then `.needsLogin`/`.notSignedIn` by name; then
   `.old`/`.unreachable` by name. `deleteAfterDays` for `.old` = ceil((lastSeenInListAt + 15 d − now) / 1 d), min 0.
   `id` = `"\(profileId)_\(orgId)"`. `static func recentEvents(_ global:, limit: Int = 5) -> [TeamEvent]`.
5. Tests, then Validate.

**Acceptance criteria**
1. Current A (rise 0), B rises 3 → current B, `switched`.
2. B rises 3, C rises 5 → C. B rises 4, C rises 4 → current A kept. A rises 4, B rises 4 → A kept.
3. No rises (all < 1.0) → unchanged, `switched == false`; current nil and no rises → nil.
4. B previous reading 600 s old → B re-baselined, no rise, current unchanged.
5. B previous session reset differs from latest by 2 h, latest 7 % → rise 7.
6. Same window, latest lower than previous (early reset) → rise 0.
7. `manualPickAt` after `lastRoundAt` → no switch even if B rises 10; readings updated; `clearManualPick`.
8. Weekly-only usage (`hasSessionLimit false`) → metric uses weekly percent.
9. Candidate with `latest == nil` → keeps no reading; not chosen.
10. `PairView`: session 80 % with reset 1 min ago, sampled before it → session 0, projected, sessionLeft 100; sampled after the reset time → not projected.
11. `PairView`: weekly reset passed → weekly 0, projected, opus 0; headroom = min(left).
12. Group: trigger P → B, peers Q moved B, R notMoved, S unchecked → `moves` has P and Q, `notMoved [R]`, `unchecked [S]`; title "2 accounts moved: A → B".
13. Group: all moved with no target → title "N accounts removed from A".
14. Rows: current first even with less headroom; then headroom 50 before 30; equal headroom → higher weekly left first.
15. Rows: `needsLogin` account rows after all `.ok`; `old` rows last with `deleteAfterDays` 3 when last seen 12 days ago.
16. Rows: codex profile and profile without `orgTracking` → no rows.
17. `recentEvents` returns at most 5, newest first.
18. Full suite passes.

**Tests:** one test per line 1–17 with `TeamFixtures.usage(...)` and a fixed `now`. Edge cases: empty
candidates; current pair not among candidates; three-way tie with no current (first in order); usage > 100 %
(left clamped to 0); `lastSeenInListAt` nil on an `old` pair (use `firstSeenAt`).

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
