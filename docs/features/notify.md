# Notify!

Claude Usage Tracker already knows every usage window worth knowing, and the phone is where the user actually looks. [Notify!](https://getnotifyapp.com) already exists, runs on Mac and iOS and reaches anything else through web push, and has a documented gateway API, so this app can put a usage window on a Lock Screen and a Home Screen without shipping an iOS app of its own.

---

## The problem

Every surface this app has is on the Mac, and every one of them needs the Mac awake and in front of you.

| Surface | Failure mode |
|---|---|
| **Menu bar icon** | One number, on a screen you have to be looking at. Gone the moment the lid closes. |
| **Popover** | A click on a target you have to aim for, on a machine you have to be sitting at. |
| **Notifications** | Transient, and delivered to the Mac. Focus modes swallow them. |
| **Notch HUD** | The best of the four and still the same machine, the same lid, the same desk. |

The question the app exists to answer is *"can I start another long run?"*, and it gets asked away from the desk as often as at it. A 95% notification firing into a sleeping Mac is a notification nobody reads.

`Views/Settings/App/MobileAppView.swift` is a painted door counting taps on a "Notify Me" button for exactly this. The real iPhone app behind that door is enormous out of proportion to the payload: an App Store presence and review queue, a push service to run, an account system to pair a Mac with a phone, a widget extension, a Live Activity extension, and a second release train alongside the Sparkle one. All of that to render one percentage.

Notify! has already built it. It is a published app covering Mac, iOS and web push, whose entire premise is that a script somewhere else pushes content to a device you carry: it owns the push certificates, the device pairing, and on iOS the extensions that draw a Lock Screen and a Home Screen. What it exposes is a plain HTTP gateway with no SDK and no bearer token, addressed by a device id and a per-device secret the user copies out of the app.

So the whole feature on this side is: turn the usage the app already holds into two small JSON bodies, and POST them to three routes.

## Behavior

Three surfaces, each switchable on its own once the feature itself is on, and two of them carry the identical thing.

That last part is the premise rather than a coincidence, and it is what makes the third surface nearly free. The gateway derives the Home Screen widget's content contract from the same module its Live Activity uses: same fields, same caps, same merge rules. `NotifyPayloadBuilder` builds the tile once, as one `NotifyTile` handed to both surfaces, and `NotifyGatewayClient` encodes it through the same `tileBody` for both routes. Building it twice would only produce two things that were meant to be identical and one day were not, which on a phone reads as two different pictures of one number.

**The metrics Live Activity** is the dense one. It carries the title `Claude Usage`, a progress bar, a compact reset countdown where a timer would sit, and a row of up to six windows, each with its own label, value, unit and color. Six is the gateway's ceiling and also about the point at which a Lock Screen row stops being readable, so the two limits agree.

**The Home Screen widget** carries that same tile, and differs in when the user meets it. A Live Activity appears while something is happening and goes away when it stops; a Home Screen widget stays where it was placed and always shows the latest thing stored for it. Neither is a substitute for the other, which is why both are on by default and either can be switched off alone.

The Home Screen widget is also the newest surface on Notify!'s side, and that shows in two places. It needs a recent Notify!, where it is turned on under Settings then Home Screen Widgets. And creating one over the gateway puts nothing on a screen by itself: it fills a slot the user still has to place through iOS's own widget picker.

**The Lock Screen widget** is the glanceable one, and the only surface with a shape of its own. Its gauge is a single chosen window: a headline value, a unit, a quieter second line naming the provider and the window, and a `progress` the gateway draws as a bar on the rectangular widget and as a ring on the circular one. It shows whichever window needs attention most until the user picks a specific one.

### Which usage reaches the phone

**The active profile's, and only the active profile's.** The phone shows what the menu bar shows. Merging every profile into one tile would need the six metric slots to cover several accounts, and a phone that disagreed with the Mac is worse than one that shows less. Switching profile on the Mac moves the phone with it, because the driver watches `ProfileManager.activeProfile`.

`NotifyUsageReadings` is the seam. `ClaudeUsage` is a wide struct of named windows, some of which a given provider never fills in; `NotifyQuotaReading` is a flat list of windows that are actually reporting something. Only windows the provider genuinely reports are included: a per-model weekly window a provider never fills in would otherwise sort as a healthy 100% and take one of the tile's six slots away from a number that matters.

| Window | Key | Included when |
|---|---|---|
| 5h session | `session` | always; an expired window reads as full rather than as its stale percentage |
| 7d weekly | `weekly` | always |
| Opus / Sonnet / Design / Fable 7d | `opus_weekly`, … | the provider reports per-model breakdowns **and** some of it has been used |
| Spend | `cost` | a cost limit exists to divide by |
| Extra usage | `overage` | an overage balance is reported |
| Credits | `credits` | the provider reports credits and the plan is not unlimited |

Four rules shape what all of that actually says, and all four live in `NotifyPayloadBuilder`:

- **Percentages are remaining, not used.** A 42% window publishes `progress: 42`. Every other surface in this app reads that way, and a full ring meaning a full window is the only intuitive mapping a gauge has.
- **The worst window leads.** Readings sort by status severity, then by how little is left. The headline is the first one, and the tile takes its tint, its bar and its countdown from it.
- **Labels drop the provider name when they can.** A tile covering one provider reads `5h 7d`, not `Anthropic 5h Anthropic 7d`. The name comes back as soon as a second provider is on show.
- **Ordering is fully deterministic**, down to a name and window-key tiebreak. Two payloads built from the same readings must compare equal, or the driver would republish forever.

Money-based windows have no percentage to draw. Their value is the formatted balance with no unit, and the tile's bar falls through to the worst window that *does* have a percentage, rather than vanishing whenever a credit balance happens to be the headline.

Colors are the menu bar's own, so a window that reads critical in the menu bar reads critical on the Lock Screen. `NotifyQuotaStatus` adds a fourth level the Mac does not have — `depleted` — because on a ring "you have run out" and "you are nearly out" are otherwise a quarter of a degree apart.

### Publish cadence

Usage moves on every refresh and the reset countdown moves every minute, so "publish whenever the payload differs" is a request per refresh, forever. `NotifyPublishGate` adds four rules on top of the difference:

| Rule | Value | Why |
|---|---|---|
| Minimum gap, tile | 60 s | The tile is a push, so it can afford to be prompt. |
| Minimum gap, gauge | 15 min | iOS decides when a widget redraws, roughly every quarter hour. Pushing faster buys nothing. |
| Minimum gap, Home Screen tile | 15 min | Also a poll, on the same quarter hour and for the same reason. |
| Keep alive, tile and Home Screen tile | 90 min | Two deadlines, both at **two hours**, both measured from the last write. The gateway ends a progress-only Live Activity that has gone that long without an update; and a Home Screen widget's `staleAt` lands there too, after which the phone dims the tile rather than presenting old numbers as current. Ninety minutes clears both with room to spare. |

The gauge is the one surface with no keep alive. The gateway documents neither a reaper nor a freshness deadline for `/widgets`, so there is nothing a heartbeat there would prevent.

The keep alive is the reason `NotifyPublishDriver` runs a one minute timer at all. Both time-based rules are unreachable from published state alone: a change the gate suppressed for arriving too soon has to be offered again once its interval has passed, and nothing in `@Published` state fires on the mere passage of time.

Saving credentials or pressing **Send Now** in the settings pane bypasses the gate entirely by clearing the record, because waiting a quarter of an hour to find out whether a token works is not an answer. The pane does that through `NotifyPublishDriver.publishNow()` rather than publishing for itself: the driver holds the stored handles and the single in-flight publish, and two publishers racing over one nil activity id is precisely how a phone ends up with two Live Activities.

### Recovery

Each failure mode below has a remedy of its own, and each one is a distinct case on `NotifyPublishError` for exactly that reason.

| What happened | HTTP | What the app does |
|---|---|---|
| The user swiped the tile away | 410 | Forget the stored activity id and start a fresh tile, once. A retry loop here is a retry loop against the gateway. |
| A stored handle is refused | 403 | Forget that one handle, so the next publish creates a replacement for it. The gateway answers a missing token, a wrong token, an unknown id and somebody else's id identically, so a 403 is not evidence the credentials are bad: far more often the user deleted that one tile or widget in the Notify! app. The other surfaces' handles are left alone, because clearing one would abandon something alive and put a duplicate beside it. |
| Push to start backoff | 429 | Suppress tile writes until the gateway's own wait has passed. Every attempt inside the wait lengthens it. Both widgets keep publishing. |
| The phone has never opened Notify! | 409 | Report it and stop. No Live Activity can start until the device has a push-to-start credential, which only opening the app once produces. |
| Apple never answered a start | 502 `unknown` | Keep the activity id the gateway returned and update it on the next tick. Starting again could leave two tiles. |
| Apple refused a start | 502 `not-delivered` | Wait. No tile exists, so starting again is safe, but every unanswered start counts toward the same ladder as a 429, so the gateway's own `retryAfterSeconds` is honored and 30 minutes assumed when it names none. |
| Home Screen widgets are not being served | 503 | Pause that one surface for six hours and say so at info level, not as an error. This is the gateway's own kill switch rather than anything wrong here, and nothing on this Mac moves it. The other two surfaces are untouched. |

Some failures are not worth discovering over the wire. A Live Activity aimed at a `GRP`, `MC` or `WB` id is refused locally, before a request exists, because the outcome is already known. Either widget aimed at a `GRP` id is refused for a different reason: a group is not a device and owns no widget list to write into. What the user reads in both cases is the id's own reason, which names the kind of device they linked and tells them what to paste instead, rather than a status code that reads as the app failing at something it should have managed.

The three surfaces are written independently, each addressed by its own stored handle and each failing for its own reasons. A tile the device refuses to start must not cost the user their widgets, which poll happily on a phone that cannot start a Live Activity at all.

### Privacy

Every other network call this app makes fetches usage from the provider that owns it. This one is the first that sends the app's own state outward, to a service that is neither the user's machine nor a provider they already have an account with, so it is worth being explicit.

- **What leaves the machine:** provider names, window labels, remaining percentages or balances, and reset countdowns. No prompts, no repository names, no file paths, no session content.
- **Where it goes:** `push.getnotifyapp.com`, a third party service, and from there to the user's own phone.
- **Off by default.** `NotifyConstants.defaultEnabled` is `false`, and the switch stays disabled until a device is linked. A feature that talks to someone else's server cannot ship enabled.
- **The token is a secret, and it lives in the Keychain or nowhere.** It goes through the same `saveItem`/`loadItem` helpers the per-profile secrets use, so it gets the data-protection keychain on entitled builds and the file-based login keychain on stably-signed ones. It is never logged, and neither is the device id above debug level.
- **A save is confirmed, not assumed.** `KeychainService.saveNotifyDeviceToken` reads the token back before reporting success, and `saveDeviceToken` and `saveDeviceLink` return that answer. A phantom write would otherwise leave the pane showing a linked device while every publish answered "not linked" — which is exactly what happened before this was checked.
- **There is no fallback store, deliberately.** The README's promise is that every credential in this app is kept in the Keychain and never in cleartext on disk (GHSA-mfxh-xpwm-23c7), and a push token is not the place to make an exception for convenience. So a build that cannot reach a Keychain cannot link, and the pane says so in as many words.

### The app has to be signed

This is the one requirement the feature adds, and it is worth stating plainly because the failure is otherwise puzzling.

An **ad-hoc signed build has no reachable Keychain at all**. The data-protection keychain wants an application-identifier entitlement such a build has no way to carry, and the file-based login keychain is deliberately gated off for ad-hoc identities, because their designated requirement changes on every rebuild and the next launch would throw a "wants to use your confidential information" password prompt (#292).

That covers every copy built locally in Xcode without a development team set. Linking will fail with a message naming the cause. Setting a team under **Signing & Capabilities**, or using a release download, resolves it. Nothing else about the feature depends on signing.

---

## The gateway

Read from its own OpenAPI document (`https://getnotifyapp.com/apidocs/openapi.json`). Host `https://push.getnotifyapp.com`; `NotifyGatewayClient`'s initializer takes another only so tests can point it at a stub. These routes declare `security: []`: there is no bearer token, and the per-device secret travels in `?token=`.

### The id namespaces, and which of them have a screen

| Id | What it names | Live Activity | Lock Screen widget | Home Screen widget |
|---|---|---|---|---|
| `GRP` + 5 | A notification group | no | no | no |
| `MC` + 14 | A push capable Mac listener | no | yes | yes |
| `WB` + 14 | A web push browser | no | yes | yes |
| `IO` + 14 | An iPhone or iPad | yes | yes | yes |
| 8 characters | The legacy format: an iPhone or iPad, or an older poll-only Mac listener | yes | yes | yes |
| anything else | A format newer than this document | yes | yes | yes |

Note which way round the Live Activity rule is written. The namespaces that cannot show one are named and everything else is allowed, rather than the reverse, because app device ids are not one fixed shape: the legacy format is 8 characters, `IO` is 16, and more will follow. A list of what *may* pass would refuse a real phone on the day Notify! mints a format this file has never heard of, and a refused phone reads as the app being broken.

Both widgets are the opposite, and identically so. The gateway is explicit that neither route carries a device-type gate. Only a group is refused, and only because a group is not a device. `NotifyDeviceKind.supportsScreenWidget` is therefore written as `supportsWidget` rather than as a second copy of the same switch, so the two can never drift into disagreeing about one id.

One thing cannot be decided locally at all. The legacy 8-character format is shared by iPhones and by older poll-only Mac listeners, and nothing in the id separates them, so such an id is allowed through and the gateway has the last word. Note too that `GRP` plus 5 is itself eight characters, so the two grammars genuinely overlap and the prefix is tested first, which is the gateway's own tie break.

### The fields are the type

**There is no tile type, and no widget display format.** No `activityType`, no `displayFormat`, nothing to select a layout with. Which fields are populated decides how the thing draws, and they compose. A title plus a progress bar plus a metrics row **is** the metrics tile. That is the single most surprising thing about this API, and it is what makes the feature cheap.

Saying nothing is load bearing in a second way, and it cuts both ways. Updates are JSON merge-patch: an absent field is left alone, a value replaces, an explicit `null` deletes. So `NotifyGatewayClient` deliberately never mentions `status`, `endsIn`, `steps`, `step` or `button`, and an update from here can share a tile with whatever else the user configured.

The same rule makes silence dangerous for the fields the app does drive. Omitting one it previously set does not clear it, it freezes it. A reset countdown would keep ticking beside a window that no longer reports one, and a gauge would keep the last percentage after the shown reading became a credit balance with no percentage at all. So every field the app owns is stated on every write, as an explicit `null` when it has no value. `title` is the one exception: the gateway treats it as an identity and refuses to clear it.

`POST /live-activity/{id}?token=`

| Field | Type | Limit | Notes |
|---|---|---|---|
| `title` | string | 120 | Required to start. The tile's identity. |
| `body` | string | 300 | Second line, shown only when there are no metrics in its place. |
| `symbol` | string | 64 | SF Symbol name. |
| `tint` | string | hex | `#RRGGBB` or `#AARRGGBB`, leading `#` optional. |
| `progress` | number | 0 to 100 | The bar. Clamped, not rejected. `null` removes it. |
| `trailing` | string | 40 | Static text where a timer would go. |
| `metrics` | array | 6 items | JSON body only, no query spelling. Replaces wholesale. |

`metrics[]` is `{label (1 to 24, required), value (1 to 16 or a number, required), unit (8), color (hex)}`. An absent color inherits the tile tint.

`POST /widgets/{id}?token=`

| Field | Type | Limit | Notes |
|---|---|---|---|
| `title` | string | 120 | Required to create. The identity in the phone's widget picker. Can be replaced, never cleared. |
| `value` | string | 40 | Headline text, pre-formatted by the caller. |
| `unit` | string | 12 | Small label beside the value. |
| `detail` | string | 120 | Quieter second line. |
| `symbol` | string | 64 | SF Symbol name. |
| `tint` | string | hex | Accent color. |
| `progress` | number | 0 to 100 | The gauge: a bar on the rectangular widget, a ring on the circular one. |

`POST /screenwidgets/{id}?token=`

No third table, because there is nothing new to put in one. This route's content contract is derived from the Live Activity's, field for field and cap for cap, so the tile table above describes it exactly and `NotifyGatewayClient` sends it through the same `tileBody`. What differs on the wire is the path and the id namespace: `SW` plus six characters, alongside `LA` and `WG`.

`NotifyLimits` enforces every length above at construction, shortening rather than failing, because a window label that happens to be long should shorten, never fail to reach the phone.

Two statuses mean something on `/screenwidgets` that they mean nowhere else, so `publishScreenTile` translates them where that difference is known rather than inside the shared mapping every other route would then have to reason about: a **503** is the server-side kill switch and becomes `surfaceSwitchedOff`, and a **409** here means the device dialect found several screen widgets and cannot say which was meant, so it becomes `invalidPayload` rather than the Live Activity's "open the Notify! app".

### Two dialects, and why only one of them is used

All three write routes take either a **device id** or a **handle**, and the handler decides by looking the id up rather than by its shape.

- Device id, the *upsert* dialect: the first call starts the device's single live tile and later calls update it in place.
- `LA######` / `WG######` / `SW######`, the *precise* dialect: always that exact tile or widget.

The upsert dialect is the shorter code and it is wrong here. A user who has a Notify! tile running from some other script of their own would find this app had taken it over, silently, with a percentage. So the app always creates its own: the first write carries `"new": true` against the device id, the returned handle is persisted, and every write after that addresses the handle. `new` never appears on an update, where it would leave the device with two tiles. It earns its keep twice over: it is also the gateway's documented override for the sticky-dismissal 410.

### The one call that is rate limited

`GET /link?id=&token=` validates a pair and describes the device it names, and the gateway allows **five calls a minute per IP**. It sits behind the pane's **Verify Device** button and nothing else. Nothing on a timer may call it. It answers **404**, not the 403 every other route uses, for a pair it does not recognise, giving that same 404 for a wrong token and for an id that does not exist so it cannot be used to enumerate ids.

---

## Architecture

Notify! is a **destination**, not a provider. Nothing in this feature reads usage from anywhere: it reads what the active profile already holds.

```
Claude Usage/Shared/Notify/
├── NotifyLimits.swift              # the gateway's field limits, enforced at construction
├── NotifyDeviceLink.swift          # device id + token; NotifyDeviceKind; NotifyDeviceInfo
├── NotifyQuota.swift               # NotifyQuotaStatus, NotifyQuota, NotifyQuotaReading
├── NotifyTile.swift                # NotifyMetric, NotifyTile: the content both tiles carry
├── NotifyGauge.swift               # the Lock Screen widget's content; progress is the gauge
├── NotifyPayload.swift             # NotifyGaugeSelection, NotifyPayload
├── NotifyPayloadBuilder.swift      # readings to one tile + a gauge; pure, the whole decision layer
├── NotifyPublishGate.swift         # whether a payload is worth a request; pure, clock free
├── NotifyPublishError.swift        # every way a publish fails, and the remedy each implies
├── NotifyPublishing.swift          # the protocol; the app's only view of the API
├── NotifyHTTPClient.swift          # the seam that lets the client be tested without a network
├── NotifyTint.swift                # NotifyQuotaStatus.notifyTintHex, NotifySymbol.quota
├── NotifySettingsStore.swift       # NotifyConstants + notify.* keys, token to the Keychain
├── NotifyUsageReadings.swift       # ClaudeUsage to readings; the one provider-aware file
├── NotifyGatewayClient.swift       # the only file that knows HTTP exists
└── NotifyPublishDriver.swift       # the Combine subscription, the tick, and the writes

Claude Usage/Views/Settings/App/
└── NotifySettingsView.swift        # link, verify, surface switches, gauge picker, send now
```

Settings keys, all under `notify.` in UserDefaults:

| Key | Holds |
|---|---|
| `notify.enabled` | Whether the app publishes at all. Default `false`. |
| `notify.deviceId` | The linked device id. |
| `notify.liveActivityEnabled` | Whether the tile is published. Default `true`. |
| `notify.widgetEnabled` | Whether the gauge is published. Default `true`. |
| `notify.screenWidgetEnabled` | Whether the Home Screen tile is published. Default `true`, because a 503 is handled as "not yet" rather than as an error, and shipping it off would mean nobody saw the surface on the day Notify! switched it on. |
| `notify.gauge.providerId`, `notify.gauge.quotaKey` | Which window the gauge shows. Both empty means automatic. |
| `notify.activityId`, `notify.widgetId`, `notify.screenWidgetId` | The handles of the three surfaces this app created. |

The device token never appears here. It goes to the Keychain through `KeychainService.saveNotifyDeviceToken`, or it is not stored at all.

### The testable core

Everything that decides anything is a pure value type with no clock, no network and no settings lookups of its own. `NotifyPayloadBuilder` takes readings and a selection and returns a payload; `NotifyPublishGate` takes a payload, the last record and a `now` and returns one boolean per surface; `NotifyDeviceLink` and `NotifyLimits` are parsers; `NotifyGatewayClient.failure(status:data:retryAfterHeader:)` is static and takes the raw body, so every status code can be driven through it without a network stub.

`NotifyPublishDriver` is deliberately free of judgement. It gathers state, asks the builder and the gate, and performs the writes the answer implies.

Rules under test, in `Claude UsageTests/Notify*Tests.swift`:

- the worst window leads, and the tile takes its tint, bar and countdown from that one
- ordering is deterministic to the last tiebreak, so two payloads from the same readings compare equal
- at most six metrics reach the tile, and a seventh reading is dropped rather than failing the whole tile
- labels omit the provider name when every reading is from the same provider, and regain it when a second appears
- a percentage is remaining: a 42% window publishes `progress: 42`, never 58
- a money window publishes its formatted balance with no unit, and the tile's bar falls through to the worst window that has a percentage
- a gauge selection naming a window that has stopped reporting falls back to the worst window rather than publishing nothing
- the Live Activity and the Home Screen tile are one built value, so the two can never disagree about the same number
- the gate holds a changed tile back inside its minimum interval, and releases it once the interval has passed
- the gate republishes an unchanged tile after the keep alive, and only then; the gauge takes the interval and no keep alive
- the record merges the three surfaces one at a time, so a surface the gate held back still remembers what it is actually showing
- the gate never writes a surface the payload left nil, because nil means the user switched that surface off
- a bare `id token` pair, a whole pasted notification URL, and the two fields all yield the same link
- an id outside 8 to 32 alphanumeric characters is refused locally, before any request exists
- `GRP` plus 5 reads as a group, `WB` plus 14 as a browser, `MC` plus 14 as a Mac, `IO` plus 14 and a bare 8 characters as an app device, with the group prefix winning the overlap at eight characters
- a Mac and a browser keep both widgets and cannot show a Live Activity, a group keeps none of the three, and an id from a namespace that does not exist yet can do everything
- the two widgets always answer alike for the same id, and each reason is present exactly when its own surface is unavailable
- a Live Activity aimed at a Mac, a browser or a group fails before a request exists, and so does either widget aimed at a group
- an over-long label shortens; an empty one is refused; a tint that is not 6 or 8 hex digits is dropped rather than failing the publish
- a percentage outside 0 to 100 clamps, because a window can legitimately report a negative remainder
- each status maps to the one error whose remedy differs, and a 429's wait comes from the body's own seconds first, the `Retry-After` header second, and 30 minutes when neither is present
- every field the app drives is present in the body on every write, as an explicit null when it has no value, while the fields it never drives stay unmentioned
- an expired session window reads as full rather than as its stale percentage, and an unused per-model window is left out entirely
- a saved token reads back again, and saving a link reports whether it actually landed
- a token never reaches UserDefaults, whichever way the save went
- a link naming a different device clears the three surface handles, while rotating the token for the same device keeps them

## Prior art

The design is a port of the same feature in [ClaudeBar](https://github.com/simplytoast1/ClaudeBar) (`feat/notify-lock-screen-publishing` and `feat/notify-home-screen-widget`), whose `docs/features/notify.md` read the gateway's OpenAPI document end to end. The decision layer, the gate, the error mapping and the client are ports of that work. What is new here is `NotifyUsageReadings`, because this app's `ClaudeUsage` is a fixed set of named windows rather than a generic list, and `NotifyPublishDriver`, which is rebuilt on Combine and a delegate-free singleton because this app does not use `@Observable`.

## Considered and rejected

**Send `endsIn` for a live countdown to the reset.** The gateway will happily tick a countdown locally on the device, which sounds strictly better than the static `trailing` text sent here. It was cut because the countdown claims the tile's progress rendering, and the percentage needs that bar: a tile cannot show both how much is left and how long until it refills, and the percentage is the thing the app exists for.

**Use the device-scoped upsert URL instead of storing handles.** One line shorter and needs nothing persisted. It also takes over whichever tile the device last had, which for a Notify! user is very likely one of their own scripts.

**Publish every profile at once.** The six metric slots get tight with two accounts, and a phone that disagreed with the Mac's menu bar is worse than one that shows less. Worth revisiting if somebody asks for it.

## Open questions

- **More than one gauge.** The gateway allows 10 widgets per device, so a widget per provider is possible. Unresolved: the widget title is its identity in the phone's picker, so several widgets need distinguishable titles that are still recognizably this app.
- **Should an exhausted window end the tile?** `endTile(link:activityId:keepFor:)` is implemented and the driver never calls it. Proposal: no. A depleted window is precisely when the number matters most, and a tile that vanishes at 0% is a tile that disappeared exactly when the user went looking for it.
- **Notify! groups.** `GET /link` already reports `type: "device"` or `"group"`, and the client rejects a group because a group carries none of the three surfaces. Publishing to a phone and an iPad at once therefore means a list of device links rather than one, with per-device handles and per-device backoff state.
