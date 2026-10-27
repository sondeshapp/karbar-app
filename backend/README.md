# Karbar sync API

This service provides shop registration/login and an idempotent event inbox/feed. It is an additive cloud layer; the POS keeps writing to its local SQLite database when this service is unavailable.

## Run locally

1. Create a PostgreSQL database and apply every `migrations/*.sql` file in numeric order with a database role that can create tables and indexes.
2. Set `DATABASE_URL`, `JWT_SECRET`, and `REGISTRATION_SECRET` in your shell or deployment secret store. Generate the signing and registration secrets as random values of at least 32 characters.
3. Start the API with `go run ./cmd/api` from this directory.
4. Keep registration closed unless you are creating an owner account. `POST /v1/auth/register` requires the configured code in `X-Registration-Code`.

## Deploy with Docker Compose

For a new installation, copy `deploy.env.example` to `.env`, replace all placeholder secrets with long random values, then run `docker compose up --build -d`. Compose starts PostgreSQL, applies the SQL files in `migrations/` in numeric order, and starts the API after the migration service completes. The API binds to `127.0.0.1:8080` by default; set `PORT` in `.env` to change the host port. Check startup with `curl http://127.0.0.1:8080/v1/healthz` and inspect service output with `docker compose logs -f api`.

Put a TLS reverse proxy in front of the loopback API before connecting POS devices. Back up the `karbar-postgres` Docker volume regularly. `docker compose down` stops the services and keeps database data; `docker compose down -v` deletes it. Do not use the example credentials in a public deployment. The bundled migration service is intended for a fresh database; for an existing database, apply only migrations that have not already been applied.

The server listens on `PORT` (default `8080`). Put it behind a TLS reverse proxy before using it from a device. The API rejects bearer tokens over plain HTTP in the Flutter client; only localhost HTTP is allowed for development.

## API

- `GET /v1/healthz`
- `POST /v1/auth/register` (operator registration code required)
- `POST /v1/auth/login`
- `POST /v1/auth/refresh` (rotates refresh token)
- `POST /v1/auth/logout`
- `POST /v1/sync/events` (bearer token, idempotency key)
- `GET /v1/sync/events?after=<cursor>` (returns events from all devices in that shop)
- `PUT /v1/sync/catalog` (revision-checked product/customer/shop-settings/supplier upsert or tombstone)
- `GET /v1/sync/catalog?after=<cursor>` (shop-scoped catalog change feed)

Refresh tokens are stored only as SHA-256 hashes and rotate on use. Access tokens are shop-scoped HS256 JWTs that expire after 15 minutes. Event IDs are UUID idempotency keys; duplicate delivery returns the original cursor, while reusing a key with a different body returns `409`.

Catalog edits use optimistic concurrency. Each mutation includes a stable entity UUID, a unique mutation UUID, and the revision the client last read. The server accepts the update only when that revision is current, increments the revision, and records a cursor change in the same transaction. Replaying an identical mutation UUID returns the original result. A stale edit receives `409` with the current revision and payload; clients must resolve or rebase it instead of overwriting the server copy silently.

## Tests

Run `go test ./...` from this directory. Tests for database transaction behavior should use a disposable PostgreSQL database; never point test configuration at production data. The Compose setup can provide that disposable database for local manual API checks.
