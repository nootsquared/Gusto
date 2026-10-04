# Architecture and maintenance

## Small, native, dependency-free

The app uses SwiftUI, Observation, MapKit, Charts, UIKit, Foundation URLSession and Keychain.
There are no third-party Swift dependencies. RescueCore stays free of SwiftUI/UIKit/MapKit;
it includes Codable contracts and the actor-backed HTTP repository. The Xcode target compiles
the same core sources as the Mac Swift package. Product data lives in private SpacetimeDB tables.
Detailed relationships, access rules and transitions are in [the backend contract](docs/backend/CONTRACT.md).
## Ownership and data flow

`RescueApp` creates one `AppStore` and one `AppRouter`, injecting both with SwiftUI's environment. `AppStore` is main-actor isolated and observable. Views read it; product changes go through guarded methods. View-local `@State` is for inputs and disclosure/selection state, never a second cart or receipt ledger.

`AppRouter` owns the selected `AppTab`, the current `AppSheet`, and a prior sheet for returning from chat. `RootView` owns system presentation. There is a single `.sheet` with `SheetHost`; replacing its destination swaps content without competing presentation calls. Listing→cart→plan stays in context. A chat remembers its originating sheet. A live pickup card is visible across tabs. Onboarding uses local AppStorage and a full-screen cover. Completion dismisses the run sheet, then shows the full-screen impact result; Done enters You.

Views compose reusable components from `Rescue/Components` and `Theme`. Colors are named catalog assets matching the Figma variables. The `rescueFont` modifier uses ScaledMetric. Standard navigation, tabs, forms, keyboard, safe areas, sheets and system sharing retain iPhone behaviors. Full-screen content does not draw a fake status bar or phone bezel.

`Theme.configureTabBar` supplies the opaque Paper system bar and Apricot unread badge at launch; both standard and scroll-edge appearances match. `BottomAction` extends its background through the home-indicator safe area. Map listing positions preserve the Make export's x/y values, projected into a fixed fictional MapKit region; route stops use the mock sellers' coordinates.

Filters are owned solely by `AppStore.filters`; the former `selectedPill` shortcut layer has been removed. Nearby is the default 0.8mi distance, and price/freshness/time/preferences use their existing model fields. Changing distance can expand results beyond the initial radius without a hidden shortcut cap.

## Product invariants

- A cart contains unique listing IDs; each listing represents one rescue package, not a quantity basket.
- Money is integer cents throughout; convert only for display with `Money.text`.
- `Totals` derives retail/pay/pounds/count from concrete listings.
- Planning groups all items once per seller. It uses deterministic order/preferences and fixed fictional coordinates.
- Cart mutation invalidates its draft plan and seller confirmations.
- During an active run, cart editing and re-planning are locked.
- Start requires nonempty, fully confirmed stops. Coordination is local and Nina requests a later time.
- Rescheduling shifts the requested stop and every later unpaid stop. The Alternative action uses a distinct later time.
- Payment is permitted only after arrival, seller handoff, and verification. Paying prevents repeated taps. A completed receipt makes those listings unavailable.
- Report issue skips the current seller without charging; skipped items never count toward impact.
- Impact is derived from receipts. Completion preserves purchase history and cumulative totals until app restart/reset.

## State transitions

Fixture mode: draft cart → `makePlan` → `coordinate` → seller confirmations / Nina counteroffer → `acceptCounter` → `startRun`.

For each stop:

Fixture mode: `enroute` → `arrive` → `arrived` → `announceArrival` → `waiting` → `verifying` → `verify` → `payment` → `pay` → `paying` → `rescued` → `continueRun` → next `enroute` or `finished`.

`reportIssue` from arrival/verification records skipped and advances. `finishRun` from finished clears the remaining cart and draft plan and returns to idle; receipts remain. State methods reject invalid transitions rather than relying solely on disabled UI controls. Explicit Next pickup / See your impact controls replace the web prototype's timed auto-advance, making the demo controllable and accessible.

## Async behavior

`DemoService.pause` provides a small asynchronous delay. Production demo defaults to 700ms; the UI-test launch argument reduces it to 50ms; core tests use zero. Coordination uses a generation token so stale responses from a discarded plan cannot confirm a new one. Reset changes the session generation so pending chat, freshness, arrival or payment responses cannot repopulate the reset session. Sending uses per-seller counters so overlapping messages keep typing status accurate. Async mutations remain main-actor isolated. Cancellation does not create a receipt. Receipt IDs are unique per transaction; payment deduplication uses the seller ID within the current run.

Fixture mode is intentionally session-local: catalog changes, carts, plans, messages and receipts live in memory. Onboarding, map preference and smart-alert preference persist through AppStorage. Relaunch/reset restores the fixture catalog. No personal location or camera permission is requested.

## Mock boundaries and future integration points

Normal launch connects the root AppStore to one account-scoped HTTPRepository. SessionController
imports provisioned local demo tokens into Keychain, and swaps accounts without carrying previous
private state across the first await. `--fixture` and ordinary `--uitesting` retain deterministic
local flows; backend errors never install MockCatalog data.

HTTPRepository deduplicates concurrent requests, persists protected Codable metadata and an outbox,
and limits metadata to 20 MB. Keys include server/database/user. Offline messages retain operation
IDs; favorites replay desired state. Exact pickup details are omitted from persisted snapshots and
cleared on offline refresh, which is stricter than retaining them for 15 minutes. Protected sell drafts
are account-scoped app files. Product writes require a successful server response; UI bodies perform
no requests. Cached listings are display snapshots, never proof of an inventory hold.

Bootstrap/cart/profile refresh at 30 seconds; feed at 60 seconds; chat polls every five seconds;
pickup/payment polls every three seconds. Root scene lifecycle cancels polling in the background.
Errors back off at 2/4/8/16/32/60 seconds with jitter. Search debounces 300 ms and rejects stale
responses. Feed, search, purchases and sales expose explicit Load more controls; automatic scroll
prefetch is not enabled.
Images share an actor cache with four network slots, 50 MB decoded memory and 200 MB disk LRU budgets.
Transport counters track calls, payload bytes, last response time and cache hits; server responses
include candidate-scan counts. Byte counters count decoded payload bytes, not protocol/header bytes.

The separate local simulator uses seller sessions for confirmations/handoff/freshness and distinct
service principals for payment/analysis. All successful payment impact comes from receipt snapshots.
Profile/monthly charts have no fabricated baselines. Seeded demo receipts are explicitly simulated.
Real authentication, camera, upload, analysis, provider payments, verification, push, referral
redemption and directions require future providers. Their typed interfaces are in Repository.swift;
unavailable database actions return service_unavailable. See MHacksDB/README.md for local startup.

Server scheduling cleans expired claims; each transition also checks expiry transactionally. The
server planner accepts arbitrary sellers/locations/windows with straight-line estimates. Swift's
pure arbitrary-seller planner is independently tested; the fixture planner retains source ordering
for deterministic screenshot/flow tests. One root sheet host continues to own all presentations.

## Common change paths

- **Change a color/type scale:** asset color sets and Theme, then check `DESIGN.md`.
- **Change feed content:** DiscoverView; fixtures only when product data changes.
- **Change filtering/search:** `Filters.accepts` and `AppStore.visibleListings`; map and search consume the same result function.
- **Change a pickup rule:** AppStore or PickupPlanner plus relevant core tests; do not encode it separately in the view.
- **Add a screen:** add its Feature view and route it through AppRouter/SheetHost; regenerate the Xcode project.
- **Add a photo:** named imageset, record original URL in `docs/ASSETS.json`, verify its geometry where used.
- **Investigate a test failure:** use `work/ios-tests.log` and Xcode's `.xcresult` attachments. Generated logs are ignored by Git.

## Source adaptation notes

The provided Make export is visual reference, not shipped web code. Its React/Tailwind/motion implementation has been recreated as native SwiftUI. Source issues intentionally corrected: inconsistent filter counts, static map filters, noneditable message composer, incorrect chat pinned-item fallback, duplicated payment risk, rescheduling downstream times, and report-issue payment blocking. Photos retain original source IDs, even where the original prototype chose a photo that does not depict the named food. See `DESIGN.md` for native tab, map, sheet, and verification adaptations.

Project files are generated by the small deterministic `Scripts/generate_project.py`. There is no XcodeGen dependency. The checked-in `.xcodeproj` opens directly. Regenerate after adding/removing/moving files; edits to build settings must also update the generator. `generate_icon.swift` creates the simple source-color leaf icon at exactly 1024px without Retina upscaling.

## Code formatting and reading strategy

`.swift-format` defines four-space indentation and a 100-column target. Run the bundled Xcode formatter with `xcrun swift-format format -i -r Sources Rescue Tests Package.swift Scripts/generate_icon.swift`. Types use UpperCamelCase, properties/methods lowerCamelCase. SwiftUI modifiers follow the view they style. Small private view builders sit near their screen; shared visual patterns belong in Components. Main-actor state mutations are in AppStore; pure arithmetic, filtering and route helpers remain in RescueCore. Comments explain mock boundaries, async guards and invariants.

For a focused change, start at the file map in `AGENTS.md`, read only the relevant screen and shared component, then follow calls into the store if behavior changes. Read `DESIGN.md` for visual changes and the matching core tests for state changes. The fixture catalog, asset manifest and generated project are reference material; avoid loading them for unrelated edits. No duplicate narrative or per-view README is necessary.
