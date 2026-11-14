## Verdict
PASS: all three must-fix items from review 1 are corrected structurally, and the pure per-rule design can meet AC1-21.

## Must fix
(none)

## Notes
- L3 lockout is fixed (`AccountRules.swift` ruleL, about lines 163-198). L3 now needs `obs.oauthUnauthorized` in the current call. The counter resets on a fingerprint change or on samples. The restore signal is `fingerprintChanged || listSucceeded || !samples.isEmpty`, as the packet requires. A blocked account with a stale count of 2 can now recover.
- The stale `pending` wedge is fixed. ruleS sweeps every pending older than 30 min first and marks the pair `resolved`, so R cannot create a new candidate in the same run. S1 clears a `.seatInferred` pending. In R, the age and `present` checks run together and discard before any other evaluation. `markIdentity` clears `pending` on every identity event.
- The followed-org fallback in M now excludes `goneIds`.
- The order is still sound: U, L, fingerprint store, then M, T, S, R and recordSamples (skipped while blocked), then credentialOrgId store and X. The result contract is unchanged for MT-3.
- Carry-over for MT-3: the first sighting of an OAuth-only credential org on an empty state is left to MT-3. MT-3's packet must state it.
