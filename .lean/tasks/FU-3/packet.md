<!-- source: .lean/plans/multi-team-followups.md lines 102-146 -->
### FU-3 — Teams UI correctness: stale history key, format specifiers, empty detail

Size: S
Risk: normal
Importance: normal

Repo `/Users/kuke/Coding/Claude-Usage-Tracker`, branch `feat/multi-team-tracking`.

**Goal:** fix three user-visible MT-8 defects and widen the locale test from 3 to all 17 `multiteam.ui.*` keys.

**Files:**
- `Claude Usage/Views/Settings/Profile/UsageHistoryView.swift` (over 300 lines: only `selectedHistoryKey`, the picker binding near line 108 and the key resolver near line 123)
- `Claude Usage/MenuBar/TeamsSectionView.swift` (static helpers `historyChoices`, `defaultHistoryKey`, `detail`, and the row body that shows the detail line)
- `Claude Usage/Resources/*.lproj/Localizable.strings` (all 15; only `multiteam.ui.*` values that take an integer)
- `Claude UsageTests/TeamsSectionViewTests.swift`, `Claude UsageTests/UsageHistoryKeyTests.swift`

(If the `.lproj` folders live elsewhere, `git ls-files '*Localizable.strings'` finds them; edit those.)

**Steps:**
1. Add `static func effectiveHistoryKey(selected: String?, profile: Profile) -> String?` to
   `TeamsSectionView`: return `selected` when it is one of `historyChoices(for: profile)` keys, else
   `defaultHistoryKey(for: profile)`. Use it in both the picker getter and the loader in
   `UsageHistoryView` so a deleted pair's key is never shown or loaded.
2. When the resolved key differs from a non-nil `selectedHistoryKey`, reset `selectedHistoryKey = nil`
   (in the existing `.onChangeCompat` path or `onAppear`; no new state).
3. In every `multiteam.ui.*` value that formats a Swift `Int`, replace `%d` with `%ld` in all 15 locales.
   Check each call site: only change specifiers whose argument is `Int`.
4. `detail(for:)` returning an empty string for an `.ok` row with no usage: the row must not render an
   empty line. Decision: hide the detail `Text` when the string is empty. No new string keys.
5. Extend the existing locale test to assert all 17 `multiteam.ui.*` keys exist in all 15 locales and that
   no `multiteam.ui.*` value contains a bare `%d`.

**Acceptance criteria:**
1. Profile with pairs {A, B}, selected key = B's key, B deleted -> `effectiveHistoryKey` returns the default key (A's).
2. Selected key valid -> returned unchanged.
3. Profile with one pair -> `effectiveHistoryKey` returns nil (picker hidden, as today).
4. No `multiteam.ui.*` value in any locale contains `%d`; Int-formatted values use `%ld`.
5. `.ok` row with nil usage -> the row renders without an empty detail line (NSHostingView layout test does not crash and `detail` is empty).
6. Locale test covers 17 keys x 15 locales.
7. Full CLT suite green.

**Tests:** unit tests for AC1-3 in `UsageHistoryKeyTests.swift`; AC4 and AC6 in the locale test in
`TeamsSectionViewTests.swift`; AC5 with the existing NSHostingView pattern there.

**Validate:** `bash scripts/validate-clt.sh` `git diff --check`
