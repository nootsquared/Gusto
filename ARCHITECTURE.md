# Architecture and maintenance

## Small, native, dependency-free

The app uses SwiftUI, Observation, MapKit, Charts, UIKit haptics, and Core Image for QR generation. There are no third-party Swift dependencies, cloud services, credentials, migrations or API clients. The Xcode target compiles the `Sources/RescueCore` files directly; `Package.swift` exposes those same files as a Mac-testable library. There is one implementation of the business logic and one test suite for it.

## Ownership and data flow

`RescueApp` creates one `AppStore` and one `AppRouter`, injecting both with SwiftUI's environment. `AppStore` is main-actor isolated and observable. Views read it; product changes go through guarded methods. View-local `@State` is for inputs and disclosure/selection state, never a second cart or receipt ledger.

`AppRouter` owns the selected `AppTab`, the current `AppSheet`, and a prior sheet for returning from chat. `RootView` owns system presentation. There is a single `.sheet` with `SheetHost`; replacing its destination swaps content without competing presentation calls. Listing→cart→plan stays in context. A chat remembers its originating sheet. A live pickup card is visible across tabs. Onboarding uses local AppStorage and a full-screen cover. Completion dismisses the run sheet, then shows the full-screen impact result; Done enters You.

Views compose reusable components from `Rescue/Components` and `Theme`. Colors are named catalog assets matching the Figma variables. The `rescueFont` modifier uses ScaledMetric. Standard navigation, tabs, forms, keyboard, safe areas, sheets and system sharing retain iPhone behaviors. Full-screen content does not draw a fake status bar or phone bezel.

`Theme.configureTabBar` supplies the opaque Paper system bar and Apricot unread badge at launch; both standard and scroll-edge appearances match. `BottomAction` extends its background through the home-indicator safe area. Map listing positions preserve the Make export's x/y values, projected into a fixed fictional MapKit region; route stops use the mock sellers' coordinates.

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

Draft cart → `makePlan` → `coordinate` → seller confirmations / Nina counteroffer → `acceptCounter` → `startRun`.

For each stop:

`enroute` → `arrive` → `arrived` → `announceArrival` → `waiting` → `verifying` → `verify` → `payment` → `pay` → `paying` → `rescued` → `continueRun` → next `enroute` or `finished`.

`reportIssue` from arrival/verification records skipped and advances. `finishRun` from finished clears the remaining cart and draft plan and returns to idle; receipts remain. State methods reject invalid transitions rather than relying solely on disabled UI controls. Explicit Next pickup / See your impact controls replace the web prototype's timed auto-advance, making the demo controllable and accessible.

## Async behavior

`DemoService.pause` provides a small asynchronous delay. Production demo defaults to 700ms; the UI-test launch argument reduces it to 50ms; core tests use zero. Coordination uses a generation token so stale responses from a discarded plan cannot confirm a new one. Reset changes the session generation so pending chat, freshness, arrival or payment responses cannot repopulate the reset session. Sending uses per-seller counters so overlapping messages keep typing status accurate. Async mutations remain main-actor isolated. Cancellation does not create a receipt. Receipt IDs are unique per transaction; payment deduplication uses the seller ID within the current run.

The demo is intentionally session-local: catalog changes, carts, plans, messages and receipts live in memory. Onboarding, map preference and smart-alert preference persist through AppStorage. Relaunch/reset restores the fixture catalog. No personal location or camera permission is requested.

## Mock boundaries and future integration points

| Capability | Demo implementation | Replace later |
| --- | --- | --- |
| Listings/sellers | `MockCatalog`, mutable `AppStore.catalog` | repository-backed feed with stable IDs |
| Reservations | unique ID cart, no actual timer | backend reservation expiry and inventory locks |
| Fresh Check | local seller condition/timestamp update, same reference image | seller photo workflow and timestamped media |
| Smart route | `PickupPlanner` estimates, fixed fictional coordinates | directions/pickup availability service; preserve grouping/shift invariants |
| Messaging | seeded/local messages, deterministic replies | conversation service; keep pinned listing selection |
| Arrival | explicit Simulate arrival action | opt-in location or seller/QR confirmation |
| Payment | guarded delay plus local receipt, no money moved | payment processor; use server idempotency keys and authoritative receipts |
| Sell | fixed reference photo, mock scan, safety-confirmed local listing | camera/photos, recognition service, server validation/publishing |
| Impact | paid-item weights and prices plus source profile baseline | authoritative ledger; retain estimated-weight labeling |
| Alerts/referral | local preference, demo URL/QR, native ShareLink | push preferences / actual referral redemption |

Avoid introducing service protocols, dependency containers, databases or coordinator hierarchies until a concrete integration needs them. `DemoService` is a single explicit seam, not a pretend backend.

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
