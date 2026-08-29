# Adding a Usage Provider

Every provider lives behind one seam: `ProviderRegistry`. UI and services
never check `provider == .something` — they read **capability flags** from the
provider's `ProviderDescriptor`, and they fetch through the provider's
`UsageProviderService`. Adding a provider is therefore an additive checklist;
no core files (`MenuBarManager`, `ProfileManager`, `PopoverContentView`,
`SetupWizardView`) should need editing.

The reference implementation is Codex:
`Shared/Services/Providers/Codex/`.

## Data model contract

Usage maps onto `ClaudeUsage` (percentages + reset dates are the common
denominator every provider has):

- primary/short window → `sessionPercentage` / `sessionResetTime`
- secondary/long window → `weeklyPercentage` / `weeklyResetTime`
- no token counts? leave `*TokensUsed`/`*Limit` at **0** — the UI hides
  token-based rows, the icon falls back to percentages, and history/CSV
  suppress token columns via the `tokenCounts` capability
- plan / credits (if reported) → `planType`, `creditsBalance`, `creditsUnlimited`

## Checklist

1. **Enum case** — add to `Provider` (`Shared/Models/Provider.swift`).
   The raw value is persisted in `profiles_v3`; never rename it. Older app
   versions decode unknown values as `.anthropic` by design.

2. **Folder** — `Shared/Services/Providers/<Name>/` containing:
   - `<Name>AuthService.swift` — credential discovery (config file, keychain,
     env), refresh, and persistence. If tokens rotate, write refreshed tokens
     back to wherever the CLI/tool expects them (atomic temp-file + rename,
     preserve unknown JSON keys — see `CodexAuthService.writeBackToAuthFile`).
   - `<Name>APIService.swift` (+ `+Types.swift`) — fetch + **tolerant** DTOs
     (per-field `try?` decoding; a new server field must never fail the whole
     response) + mapping to `ClaudeUsage`.
   - `<Name>UsageProvider.swift` — conforms to `UsageProviderService`
     (`hasCredentials(for:)`, `fetchUsage(for:)`, optionally
     `fetchUsageForActiveProfile(_:)` if the active profile has a broader auth
     chain).

3. **Registry entry** — `ProviderRegistry.descriptors` (displayName, logo,
   status page URL if Statuspage-compatible, capability flags, credential
   sections) and `ProviderRegistry.service(for:)`.

4. **Capabilities** — set every `ProviderCapabilities` flag deliberately.
   `false` must cleanly hide/no-op the feature. Most new providers want
   everything `false` except maybe `credits`.

5. **Secrets** — if the provider stores a manual credential on the profile:
   add a field to `Profile` (mirroring `codexCredentialsJSON`: excluded from
   plist encoding, included under `includeSecretsKey`), a
   `KeychainService.ProfileSecretField` case, and the hydrate/persist lines in
   `ProfileStore`.

6. **Credentials UI** — a `SettingsSection` case (`isCredential: true`, title
   + icon + description) and a view modeled on `CodexAccountView` (detect →
   manual paste → test connection). Route it in `SettingsView`'s content
   switch and list it in the descriptor's `credentialSections`.

7. **Setup wizard** — a hint string for the provider card in
   `ProviderChoiceSetupView` and a setup view modeled on `CodexSetupView`.

8. **Logo** — asset named per the descriptor's `logoAssetName` in
   Assets.xcassets (template rendering); the SF Symbol fallback covers the
   interim.

9. **Localization** — add the new keys to all lproj dirs under `Resources/`
   (see the "Multi-Provider / OpenAI Codex" block for the pattern).

10. **Tests** — fixture-based decode tests (missing fields, malformed fields,
    unknown enum values), auth parsing variants, and a 0-token mapping test.
    See `CodexProviderTests`.

## What you should NOT need to touch

`MenuBarManager`, `ProfileManager`, `PopoverContentView`, `SetupWizardView`
(beyond the hint string), `UsageHistoryService`, `NotificationManager`,
`MenuBarIconRenderer`. If a change seems to require editing one of these,
the right fix is usually a new capability flag, not a provider check.
