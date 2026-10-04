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
- `addToCart` saves a package without an inventory hold, expiry timer, or seller contact. Cloud cart rows have an empty reservation ID until checkout. `confirmCartAndPlan` reserves the cart atomically and builds a draft pickup plan; unavailable inventory rolls back the entire confirmation. Seller contact begins only through the separate coordinate action. Existing confirmed holds keep their original expiry.
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

Fixture mode is intentionally session-local: catalog changes, carts, plans, messages and receipts live in memory. Onboarding, map preference and smart-alert preference persist through AppStorage. Relaunch/reset restores the fixture catalog. Fixture tests do not trigger location prompts. Camera permission is not requested.

## Mock boundaries and future integration points

Normal launch selects Maincloud (`mhacks-pranav-dev-975fp`). OAuthSignIn uses Apple
ASWebAuthenticationSession with authorization code, S256 PKCE, state and nonce. The public
native SpacetimeAuth client permits only `com.mhacks.rescue://oauth/callback`. Google is
the only enabled login method in SpacetimeAuth: email and anonymous login are disabled,
so a fresh authorization redirects directly to Google. No provider/client secret is bundled in the app.
An empty backend catalog shows a single listing invitation; it does not imply a failed login.
Registration verifies the token/sender pair through Maincloud, then checks issuer, audience,
project and expiry before creating the user, identity mapping and initial account rows
in one transaction. Retries return the existing active account without overwriting its profile.
SessionController stores tokens, refresh token, expiry and subject in Keychain. HTTPRepository
obtains the current session before each request, allowing refresh without switching accounts.
Sign-out clears the active store synchronously and invalidates pending account work. Debug `--local-backend`
selects the local database. SessionController uses separate Keychain services for local and
cloud sessions and only imports provisioned local demo tokens in local mode. Account switching
clears previous private state before the first await. `--fixture` and ordinary `--uitesting` retain deterministic
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
Camera, upload, analysis, provider payments, verification, push, referral
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

The owner-only cloud catalog seed uses the existing 200-record fixture generator with
`rescue-cloud-catalog-v1` as its installation marker. It preserves authenticated accounts,
leaves simulation disabled, and omits local account activity. Catalog rows and related seller,
pickup, tag, and media-reference records live in Maincloud; sample image bytes remain bundled
in the app. The API resolves `bundle:` media keys to native asset names.

`Rescue/Features/WelcomeView.swift` owns welcome presentation; RootView supplies the
existing OAuth action and session state. Debug `--welcome-preview` shows it without
clearing Keychain; Get started dismisses that preview to the existing session.

LocationController is a root-injected observable platform adapter for Core Location and
MapKit place search. It requests When In Use access, updates at approximately 250m movement,
reverse-geocodes the Discover label, and pauses GPS when the app leaves the foreground.
Manual location selection stops GPS and persists on device; users can switch back at any time.
AppStore recalculates listing distances with pure Haversine math whenever coordinates or
seller data changes. Search sends the chosen coordinates to the existing backend contract.
The cloud discovery index still covers the seeded Linden Park market; this change does not
create national inventory or move the fictional seller locations.

MarketplaceMapView owns viewport/search and card selection state. Its native MKMapView coordinator clusters seller annotations, retains camera position during updates, and follows LocationController selections. AppStore.loadMapArea pages cloud searches using viewport coordinates without changing Discover location or text-search state. Map filters use the viewport for distance; remaining marketplace filters still apply.

DiscoverView owns transient search text, focus, and loading presentation. Its query/filter/location task cancels superseded searches and uses AppStore.searchBackend plus paginated searchResults. Listing details still use the single root sheet; search is no longer an AppSheet destination.

Map dropdown search owns its query/focus and debounces LocationController.find. MKLocalSearch supplies the address/place matches; selected coordinates use the existing device persistence and browse-location propagation, without introducing a separate address database. A non-clustered BrowseMapAnnotation marks manual selections.

The Messages tab uses a scrollable inbox with actual seller conversations and a bundled, read-only Gusto welcome note. The note is always available, including before a new account has conversations; opening it does not create a seller chat or send a backend message. Empty inboxes offer a direct link back to Discover. The tab does not show a fabricated unread count.

Gusto consumer copy refers to pickup plans, pickup trips, and purchases. The existing internal `rescued` phase and Rescue module names remain stable for stored data and authentication compatibility; completion is presented as “Picked up” or “Pickups complete.”

## Scan ownership and hardware boundary

`FoodScanController` owns transient image review and on-device Vision classification. Camera and scan sheets use the root modal host. `AppStore.inventory` and `storageReadings` own product state, clear on account changes, and load through the authenticated repository. Private photos remain private until the atomic `inventory_publish` action creates the listing, pickup location/window, public media reference and seller attestations. `inventory_unlist` archives the linked listing and returns the item to the private collection; claimed/sold listings cannot be removed. Inventory reads and edits are scoped to `ctx.sender`'s registered account.

`StorageSensorConnection` is a native CoreBluetooth adapter for discovery and pairing. No arbitrary BLE bytes become measurements; firmware decoding remains pending. `StorageSummary` rejects other items/devices, future timestamps, invalid units/ranges, samples before the scan and history older than three days. This is a simple sample mean, not an expiry predictor. No connected sensor means no active tracking; if recent recorded samples exist, they are labeled historical averages.

Private cloud photo storage is a bounded prototype (50 items/account, JPEG <=65 KB). Inventory is fetched separately from bootstrap. Full-size object storage, Gemini variety/condition extraction, calibrated expiry forecasting and BLE characteristic ingestion remain unconfigured. Database table/index additions are deployed without deleting existing data.

Browse-location headers show “Current location” for GPS and a compact area label for manual selections; the picker retains the full place name. Switching to GPS removes the persisted manual selection. A one-time migration removes the museum selection written by older Simulator address tests; current tests use isolated preferences.
