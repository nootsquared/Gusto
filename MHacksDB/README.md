# Rescue local SpacetimeDB backend

SpacetimeDB CLI/SDK **2.10.2**, Node 22+, macOS `sips`. No external Swift package.
All product tables are private. See [API/security contract](../docs/backend/CONTRACT.md).

From this directory:

```sh
npm run setup
npm start                         # keep running; loopback :3000, persistent .spacetime/rescue-server
npm run publish                   # another terminal; --delete-data=never
npm run provision                 # owner-only, idempotent, local-only seed and identities
npm run media                     # third terminal; loopback :8081, immutable photos
npm run simulate                  # fourth terminal; separate sellers/payment/analysis identities
```

Normal app launch uses `mhacksdb`. Debug builds import the 12 already provisioned demo
sessions from loopback media tooling and keep their tokens in Keychain. `--fixture` opts
into the original offline demo; `--uitesting` chooses fixtures unless `--backend` is also
present. `--account riley` selects a provisioned debug session; it cannot attach an identity
to an arbitrary user. A physical iPhone's loopback address is its own device: these commands
are a Simulator development configuration, not a LAN or hosted deployment.

The versioned seed creates 200 packages, including the 20 familiar items, 12 users, private
fictional locations, related photos/tags/windows/attestations, separate conversations, saved
items/follows, one populated cart, a draft, unavailable packages and two immutable simulated
receipts with derived monthly totals. Timestamps are relative to installation. Startup never
reseeds. Old installed seeds remain intact when module code changes.

Credentials, persistent databases and media stay under ignored `.spacetime/`. Owner credentials
remain in the CLI's own Keychain/configuration. Never copy them into Xcode resources. Media
files use content-hash URLs and registered paths; draft media authorization is owner-only.
`/dev/accounts` deliberately supplies all local demo accounts for the debug switcher: never
host or forward this endpoint. Public fixture originals retain provenance in `docs/ASSETS.json`.

```sh
npm test                          # fresh isolated DB; security and product HTTP tests; republish
npm run load-test                 # 2,000 packages, bounded candidate scanning and paging
npm run typecheck
npm run build
npm run logs
```

Tests refuse remote servers, preserve their isolated `rescue-test-*` databases for inspection,
and never clear the development database. `RESCUE_DATABASE` and `RESCUE_SERVER` let tooling
target another explicitly local instance. A destructive local reset is intentionally absent
from the app; it needs an explicit developer database-management command.

Simulation starts disabled in every new database. Only local owner provisioning enables it.
Do not call `configure_local` or provision demo identities in cloud deployments. Real providers,
production authentication, HTTPS media hosting and cloud enrollment remain future work.

Official contracts: [procedures](https://spacetimedb.com/docs/functions/procedures/),
[HTTP API](https://spacetimedb.com/docs/http/database/),
[private tables](https://spacetimedb.com/docs/tables/access-permissions/).
