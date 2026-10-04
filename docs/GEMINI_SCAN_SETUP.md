# Gemini scanning and a two-phone demo

The app calls the authenticated SpacetimeDB `scan_analyze` procedure. Only that server calls
Gemini. The API key lives in the private `gemini_configuration` table and an ignored, permission
restricted local `MHacksDB/.gemini-key` file; it is never compiled into the app or returned to users.
The supplied replacement key has been verified against a real photo on the isolated local server.
The default is `gemini-3.1-flash-lite`, which successfully identified ripe bananas and their bounds.
The model can be changed with `GEMINI_MODEL` when configuring the server.

## Configure the shared backend

The shared backend was deployed on October 4, 2026, with Gemini configured and existing listings
reindexed. Future deployments use:

```sh
cd /Users/pranavmaringanti/Dev/MHacks/MHacksDB
npm run publish:cloud -- --yes=remote,migrate,break-clients
RESCUE_SERVER=https://maincloud.spacetimedb.com RESCUE_DATABASE=mhacks-pranav-dev-975fp node scripts/configure-gemini.mjs
spacetime call mhacks-pranav-dev-975fp rebuild_search_index --server https://maincloud.spacetimedb.com --no-config --yes
```

Use the database-owner CLI account. Publishing uses `--delete-data=never`. Reindexing adds singular
food aliases to existing listings without modifying their contents. Added inventory/reading columns
have migration defaults. Do not clear the database. Build and install the updated iPhone app after
publishing. The key file must contain only the key; replacing it and rerunning configuration rotates
the server key without rebuilding the app.

## Scan and sell

1. Open Scan and take or choose a photo.
2. Gemini suggests the food, variety, category, visible condition, quantity, description and handling
   information. Review the editable fields. Photo text is treated as input, never as instructions.
3. A confident, sufficiently large bounding box crops around the food with padding. “Use full photo”
   restores the original. This is a rectangular crop, not a transparent background removal.
4. Save to your private collection. Nothing is published or reserved.
5. Open the item → Sell this item. Check allergens, set a price, select a pickup address and times,
   and explicitly confirm the listing information. The photo and reviewed metadata are reused.
6. Publishing creates a shared marketplace row; the private item moves to For sale. Unlisting puts
   it back in your collection when no reservation prevents withdrawal.

Gemini failures show a readable message and let you enter details manually or retry. Google can
return quota, billing or temporary availability errors even for a valid key. Scan analysis is limited
to six requests per account per minute; requests time out rather than blocking indefinitely.

## Sensor-linked estimates

Connect the actual Nano under Storage sensor, then tick **Track with sensor** on an item. Multiple
items can use the same sensor. Valid BLE readings are converted from Fahrenheit to Celsius and
recorded privately about once a minute. Light remains labeled **raw**, distinct from legacy lux.
The live dashboard still refreshes every second. Unchecking tracking stops new records for the item,
including when it is listed for sale.

The estimate uses Gemini's broad remaining-quality range at a reference temperature, recent
observed temperature/humidity averages and elapsed time since scanning. The prototype assumes a
Q10 factor of 2 for warmer conditions and a small drying adjustment below the suggested humidity;
cooling never promises additional shelf life. It is **not calibrated**, not a food-safety expiration
date, and raw light does not affect it. No valid linked history means no estimate. Changing the
food, variety, condition or storage invalidates the old suggestion rather than applying it to a
different item. Recent history is bounded to the latest 500 account samples within three days.

Bluetooth central background mode is enabled. iOS may deliver notifications while the app is in
the background, but recording requires the connection and valid packets. Force-quitting the app,
disconnecting the device or OS suspension does not produce readings. Historical averages remain
history; the app does not pretend they are current conditions.

## Another phone

Connect the second phone to Xcode, enable Developer Mode and install the same updated Rescue/Gusto
scheme with your signing team. Use a normal launch with no `--fixture`, `--uitesting` or
`--local-backend` arguments. Sign into Google separately on each phone. Both normal builds use
`https://maincloud.spacetimedb.com`, database `mhacks-pranav-dev-975fp`.

Phone A saves a scan privately and publishes it with an available pickup window. Phone B selects
the same area, pulls to refresh Discover or searches for the food, opens the listing and messages
the seller. Feed polling runs about every ten seconds while foregrounded; active chat refreshes
about every five seconds. Refresh also reruns an active search. Private scans and sensor history
remain account-scoped. Real payments are not configured.

Google avatars now use original-color tab artwork. Profile synchronization runs on login, including
logging into the same account again. If the provider omits its picture claim, the app shows initials;
it does not substitute another person's fixture photo. A physical Google-photo check remains.
