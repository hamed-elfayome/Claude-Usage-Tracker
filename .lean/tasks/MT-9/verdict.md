## Verdict        PASS — docs-only; all 7 criteria met in the three named files; gates green.
## How it's going A
Plain, short sentences matching the spec; all 8 events, Google fallbacks, limits and troubleshooting entries present.
No code touched; Unreleased block correctly above 3.4.0.
## Done well
- Each event gets one plain sentence; limits list covers every spec §15 bullet plus the capture request.
- Troubleshooting links back to profiles.md (relative link valid).
## Must fix
none
## Tests to add
none (docs only)
## Hunter
not run; reviewer checks: git diff (3 .md files only, 0 non-md), git diff --check clean, grep for TBD (owner) and "Two changes between checks show as one" both found. Gate: validate-clt.sh 598 ok, 0 failed.
## Improve later
- The TBD line reads awkwardly ("TBD (owner) (works / is blocked)"); owner will replace it.
