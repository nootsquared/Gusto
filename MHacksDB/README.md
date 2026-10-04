# Rescue local SpacetimeDB backend

## Cloud development database

The Rescue module is deployed to Maincloud as `mhacks-pranav-dev-975fp`.
Database identity: `c200e8f7ea8e27edd2c61fd13079ca926a5ed3497b066e94303a6e241310ec91`.
Host: `https://maincloud.spacetimedb.com`.
Dashboard: https://spacetimedb.com/mhacks-pranav-dev-975fp.

Run `npm run publish:cloud` to update without deleting data, and `npm run logs:cloud`
to inspect cloud logs. `spacetime.cloud.json` records the cloud environment; explicit
server/database arguments in these scripts prevent local overrides from choosing the target.
Local commands below still target the local database.

The cloud tables are deployed and the administrative owner is initialized. Product tables
start empty; local fixture records and demo credentials have not been transferred.
Because this database was created before the Rescue module was published, its new `init`
did not execute on update. The empty `database_owner` table was initialized through
owner-authorized SQL with the authenticated publishing identity; existing owners must
never be overwritten during deployment.

SpacetimeAuth is enabled with project `project_034Zwg7HzgCGNFHV6q3NX5` and default
client `client_034Zwg7ImCF86DX87V53K8`. These identifiers are public configuration,
not credentials. The default client is public and native, with callback `com.mhacks.rescue://oauth/callback`.
Google is enabled in the auth dashboard. The iPhone app uses Maincloud and performs
automatic authenticated profile registration through `register_profile`. Debug `--local-backend` selects local
sessions and the local endpoint. Keychain sessions are isolated between environments.
Uploaded photos also need hosted storage. Do not expose the local `/dev/accounts` endpoint
or enable local simulation on Maincloud.

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
Do not call `configure_local` or provision demo identities in cloud deployments. Real analysis/payment providers and HTTPS media hosting remain future work. Cloud
authentication uses SpacetimeAuth with the project/client restrictions described above.

Official contracts: [procedures](https://spacetimedb.com/docs/functions/procedures/),
[HTTP API](https://spacetimedb.com/docs/http/database/),
[private tables](https://spacetimedb.com/docs/tables/access-permissions/).

## Cloud sample catalog

`npm run seed:cloud` calls the owner-only, idempotent `seed_cloud_catalog` procedure
on `mhacks-pranav-dev-975fp`. It loads 200 sample listings and 12 fictional seller/demo
profiles without enabling local simulations, binding demo identities, or changing existing
Google accounts. No sample receipts, conversations, or purchases are assigned to cloud users.
Sample media references the photos bundled in the iPhone app; it needs no localhost media
server. Uploading real seller photos to HTTPS storage remains a separate integration.
