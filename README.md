# Rescue — native iPhone demo

SwiftUI iPhone app for rescuing food, iOS 17+. Normal launches use the local SpacetimeDB
backend with separate accounts, authorized reservations, persistent messaging, seller publishing,
pickup/payment simulation, and receipt-derived impact. Browsing survives temporary disconnection
through account-scoped caches. External authentication, camera, AI, cloud uploads, actual payments,
push and directions remain future providers.

Start the four local development processes in [MHacksDB/README.md](MHacksDB/README.md),
then run the app in Simulator. `--fixture` selects the original bundled-photo offline demo;
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
2. Add Greek Yogurt from Buy again, then use Search for Sourdough Loaf and Rigatoni. Reserve both. The default Near Me filter includes all four.
3. Cart shows **4 items, 4 sellers, $7.75 to pay, $14.63 saved, 6.1 lb**. These figures come from the source fixtures.
4. Plan My Pickups → choose a route preference → Coordinate All.
5. Accept Nina's later pickup time (or Alternative). Downstream stop times update.
6. Start rescue run → tap the Next seller card → Simulate arrival → I'm Here → Looks good → Pay.
7. After Rescued, tap Next pickup. Repeat for the remaining sellers. At the last stop, tap See your impact.
8. Done enters You with updated impact. Purchases & Sales shows local demo receipts.

Payment buttons simulate payment and never charge money. Photos in pickup verification are clearly marked as reference photos. Report issue skips a seller without adding a receipt or impact. Fixture-mode reservations last for the demo session. Backend-mode reservations use an exclusive, server-controlled 30-minute hold; confirmed bookings last through the agreed pickup window plus 15 minutes.

Other flows: Map price pins and carousel, search and filters, Fresh Check, editable chat and quick replies, mock photo scan → safety confirmation → local listing, saved items, impact charts, alerts, and native invitation sharing.

**Offline demo:** all 26 source photos are bundled. The default map recreates the Figma MapArt locally. You → Settings → Use live MapKit basemap enables Apple map tiles; coordinates remain fixed demo locations. In fixture mode, Settings → Reset demo restores fixtures. In backend mode, Clear device cache and refresh only clears this device and never resets shared server data.

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
