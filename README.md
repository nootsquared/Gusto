# Gusto — native iPhone demo

SwiftUI iPhone app for rescuing food, iOS 17+. Normal launches select the Maincloud database
`mhacks-pranav-dev-975fp`. Sign in through SpacetimeAuth using Google. First sign-in
creates a server-authorized profile; returning users retain the same account.
Scans save to private cloud inventory; **Sell this item → List on Gusto** publishes them for
other signed-in users. Foreground browsing refreshes all marketplace pages about every ten
seconds, and pulling down refreshes immediately. Nearby starts at 3 miles; filters and the map
viewport determine which published items appear. Both phones must use a normal cloud build,
not `--uitesting` fixtures or `--local-backend` accounts.
Debug launches with `--local-backend` use the local SpacetimeDB backend with separate
accounts, authorized reservations, persistent messaging, seller publishing,
pickup/payment simulation, and receipt-derived impact. Browsing survives temporary disconnection
through account-scoped caches. Camera, AI, cloud uploads, actual payments,
push remain future providers. Pickup routes use Apple Maps from your selected location, with
road directions available through Apple Maps. Plans choose an order automatically; you can move
stops before sending requests. Sellers confirm requests in Messages before buyers start pickups.
Seed sellers are sample accounts and cannot reply. Actual payment processing remains unconfigured.

Google account pictures appear in You and the tab bar when SpacetimeAuth provides a photo.
An expired session keeps the account and current screen. Token renewal clears reconnect prompts; transient failures never sign you out.

Gemini scanning, reviewed collection-to-sale publishing and sensor-linked quality estimates are
implemented; see [Gemini scan setup](docs/GEMINI_SCAN_SETUP.md) for server-key configuration and
the two-phone demo. The shared backend is deployed with Gemini configured; local core, backend, Simulator and iPhone build checks passed.

Start the four local development processes in [MHacksDB/README.md](MHacksDB/README.md),
then run the app in Simulator with the `--local-backend` launch argument.
`--fixture` selects the original bundled-photo offline demo;
`--uitesting` selects fixture mode unless `--backend` is also supplied. Backend failures show an
honest offline state and never silently substitute fixture records. Debug account switching is
in You → Settings and selects provisioned Keychain sessions.
## Run in Simulator

1. Open `Rescue.xcodeproj` in Xcode 16.4 or later.
2. Select the **Rescue** scheme and an iPhone Simulator.
3. Run (⌘R). If a runtime is missing, install an iOS runtime in Xcode Settings → Components.
4. Tap Find food nearby on first launch. Subsequent launches start on Discover.

## Run on a physical iPhone

1. Connect the iPhone and select it as the run destination.
2. In target Rescue → Signing & Capabilities, select your development team. Automatic signing is enabled; use a unique bundle ID if Xcode asks.
3. Enable Developer Mode on the iPhone if required, trust your development certificate when prompted, and run.

Physical-device signing/install requires your Apple account and connected hardware. An unsigned device build validates compilation, not a signed installation. The app contains no Apple Pay, push, camera, or location entitlement to configure.

## Fixture-mode hackathon demo

1. Discover → Organic Strawberries → Reserve. Close the sheet.
2. Add Greek Yogurt from Buy again, then use Search for Sourdough Loaf and Rigatoni. Reserve both. The default 3mi distance filter includes all four. Filters next to Search combines budget, pickup time, freshness and preferences in one sheet.
3. Cart shows **4 items, 4 sellers, $7.75 to pay, $14.63 saved, 6.1 lb**. These figures come from the source fixtures.
4. Plan My Pickups → choose a route preference → Coordinate All.
5. Accept Nina's later pickup time (or Alternative). Downstream stop times update.
6. Start pickups → tap the Next seller card → Simulate arrival → I'm Here → Looks good → Pay.
7. After Picked up, tap Next pickup. Repeat for the remaining sellers. At the last stop, tap See your impact.
8. Done enters You with updated impact. Purchases & Sales shows local demo receipts.

Payment buttons simulate payment and never charge money. Photos in pickup verification are clearly marked as reference photos. Report issue skips a seller without adding a receipt or impact. Fixture-mode reservations last for the demo session. Backend-mode reservations use an exclusive, server-controlled 30-minute hold; confirmed bookings last through the agreed pickup window plus 15 minutes.

Other flows: Map price pins and carousel, search and filters, Fresh Check, editable chat and quick replies, mock photo scan → safety confirmation → local listing, saved items, impact charts, alerts, and native invitation sharing.

**Offline demo:** all 26 source photos are bundled. The marketplace uses interactive Apple Maps with seller clustering, selected/GPS location centering, and cloud searches for the visible area. Map tiles need internet. Pickup route previews retain an offline demo map; You → Settings → Live maps for pickup routes enables Apple map tiles for those previews. In fixture mode, Settings → Reset demo restores fixtures. In backend mode, Clear device cache and refresh only clears this device and never resets shared server data.

## Tests and development

The TypeScript backend lives in `MHacksDB/`. Its isolated integration suite tests
sender authorization, privacy, reservation races/expiry, message retry deduplication, publishing,
seller handoff, trusted payment completion, immutable history, and non-destructive republishing.
See [API contracts](docs/backend/CONTRACT.md) and [testing](docs/TESTING.md).
```sh
swift test
python3 Scripts/generate_project.py  # after adding/moving Swift files
xcrun swift-format format -i -r Sources Rescue Tests Package.swift Scripts/generate_icon.swift
./Scripts/test.sh                   # core + iPhone Simulator tests
```

Xcode: ⌘U runs unit and UI tests. See `docs/TESTING.md` for precise commands, coverage, screenshots, and environment requirements. The `--uitesting` launch argument skips onboarding and shortens mock delays without pre-filling the cart or bypassing the product flow.

## Documentation index

- `AGENTS.md`: concise file map and constraints; start here for targeted changes.
- `DESIGN.md`: source typography, tokens, patterns, states, native adaptations.
- `ARCHITECTURE.md`: ownership, invariants, lifecycle, mock boundaries, extension paths.
- `docs/TESTING.md`: test and build verification.
- `docs/ASSETS.json`: exact photo URLs and local asset availability.

This repository is intentionally left uncommitted. The user handles Git commits and pushes.

The visible app name is Gusto. Existing Rescue target names, bundle ID, OAuth callback, and Keychain identifiers are retained for connection and session compatibility.

Tap the location below the Discover heading to use foreground GPS or search for a city, neighborhood, or address. Gusto requests When In Use permission on the first connected launch; manual choices persist on the device. Distances and nearby filters use the chosen coordinates. Sample seller locations remain fictional Ann Arbor locations.

Discover search is inline: type into the top field to show matching food on the same scrollable page. Empty search shows available categories, not seeded search history; Cancel returns to the discovery feed.

On Map, Choose location opens a dropdown for GPS or live Apple Maps address/place matches. Selecting a match centers the map and adds a green location pin; the choice is saved on this device. No additional address service or database setup is required.

Adding food to your cart saves it without reserving inventory or contacting sellers. In the cart, **Confirm & plan pickups** starts the inventory holds and creates a plan; contacting sellers is a separate next step. Saved items may become unavailable before confirmation.

## Scan and private food collection

The middle tab is **Scan**. Capture a camera photo or choose one through Apple's photo picker, review Gemini's food, variety, visible condition and quantity suggestions, and save a private inventory item. Confident food bounds offer a crop with a full-photo restore option. Analysis runs through the authenticated server; no Gemini key is bundled in the app. Manual entry remains available if analysis fails.

Items and compressed JPEGs persist in private Maincloud `food_inventory` records. This prototype limits each account to 50 items and each image to 65 KB; a production photo pipeline should use your Google Cloud Storage bucket. Only explicit **Sell this item** publishes its photo and creates a marketplace listing after price, allergens, a selected map address, pickup dates and four individual attestations. The app never calls AI output verified. Pickup location defaults to a recent precise location or your saved choice; use current location or select a live address match as you type. The pickup pin uses your selected coordinates. Tracked items attach recorded storage averages to their listing.

Scan → Storage sensor connects to the Nano `MHacks Climate` service using the exact UUIDs and 17-byte binary protocol in [Developer/BLE_PROTOCOL.md](Developer/BLE_PROTOCOL.md). Hold FREE-WILi blue for two seconds, tap Find a device, select MHacks Climate, and allow Bluetooth access. The app reads the current characteristic and subscribes to once-per-second notifications. Its live dashboard displays °F (with °C), % relative humidity, and raw APDS9960 clear-channel counts. Missing validity bits display dashes; after five seconds without a new sample all readings are hidden as stale. Disconnect stops monitoring; closing the panel leaves the foreground connection active. A physical iPhone is required for the radio check; the Simulator shows an explicit device requirement.

Tick **Track with sensor** on a collection item to record valid BLE history privately about once a minute. Temperature is converted to Celsius; raw light counts remain explicitly raw and are never mixed with lux. Recent temperature/humidity history supports a provisional remaining-quality estimate. Background recording depends on iOS notification delivery and a connected sensor. See [physical iPhone setup and other-phone installation](docs/IPHONE_SENSOR_SETUP.md).

The remaining-quality model is uncalibrated and does not establish a food-safety expiration date. See [Gemini scan setup](docs/GEMINI_SCAN_SETUP.md) for its assumptions. Without a sensor, scanning and selling still work, with no fabricated tracking values.
