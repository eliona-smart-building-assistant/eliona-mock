# BuildingPro Suites mock

A local BuildingPro Suites environment to develop and test apps against API v2: the real API v2 server, a
database generated from the platform, a Kafka broker, a calculator that writes data, and change data capture
for the API listeners.

## Versions

Each tag of this repository matches one platform version: tag `v26.4.3` runs `eliona/api-v2:v26.4.3` on the
database of platform `v26.4.3` (see `init/VERSION`). Pin the tag of the platform version your app targets.

Tags `v2.x` are the earlier hand-written mock for apps with their own database schema; they are no longer updated.

## Start

```sh
docker compose up -d
```

| Setting | Value |
|---|---|
| `API_ENDPOINT` | `http://localhost:3000/v2` |
| `API_TOKEN` | `secret` (full access), `secret-read-only` (read only) |
| `BROKERS` | `localhost:19092` |
| `CONNECTION_STRING` | `postgres://postgres:secret@localhost:5432/postgres` (for inspection only; apps use API v2) |

API v2 is published for `linux/amd64` only; on Apple Silicon Docker runs it through emulation.

The mock starts with one tenant and no project. Create a project and use its ID in your app:

```sh
curl -X PUT localhost:3000/v2/projects -H 'X-API-Key: secret' -H 'Content-Type: application/json' \
  -d '{"title":"Mock project"}'
```

## What is mocked

| Service | Image | Role |
|---|---|---|
| database | `timescale/timescaledb-ha` | PostgreSQL 16 with TimescaleDB, schema and master data from `init/` |
| kafka | `redpanda` | Kafka API |
| init-topics | `redpanda` | creates the topics API v2 uses |
| api-v2 | `eliona/api-v2` | the real API v2 server |
| calculator | `insolare/mockprocessor` | writes data from `eliona.calculator.raw.v1` into `heap` |
| debezium | `debezium/connect` | change data capture of `heap`, `asset`, `alarm` for the API v2 listeners |

The database contains only the tables, views and functions API v2 uses. Platform rules are left out on
purpose: no license checks, no audit, no notifications, no row level security. Triggers that shape the data
API v2 returns (column defaults, heap rows of new assets and attributes) are kept.

## Update to a new platform version

Maintainers with access to the platform images regenerate the database:

```sh
az acr login -n mybuildingsmeu1
scripts/generate.sh v26.4.4
```

The script deploys the real database image of that version, keeps what API v2 of the same version needs
(`scripts/subset.py`), replaces generated keys and secrets with the mock values (`scripts/mock-seed.sql`) and
writes `init/00-roles.sql`, `init/10-schema.sql`, `init/20-data.sql` and `init/VERSION`. Then set the same
version for `eliona/api-v2` in `docker-compose.yml`, start the mock, check an app against it and tag the commit
with the version.
