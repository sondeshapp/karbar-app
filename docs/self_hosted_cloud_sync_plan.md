# Karbar — Self-Hosted Cloud Sync Plan

**Status:** Proposed direction

**Scope:** Optional multi-device synchronization for the free Karbar POS app.

## 1. Product direction

Karbar should remain a complete local-first POS application. A shop must be able to install and use it without creating an online account, running a server, or depending on an internet connection.

Cloud sync is an optional add-on for users who want to connect multiple devices or keep a copy of their shop data on infrastructure they control. The user, not Karbar, owns the hosting decision, server, database, backups, and associated costs.

The sync service should therefore be:

- **Optional:** local-only use remains fully supported.
- **Self-hosted:** users can run the server on a VPS, home server, office computer, or private network.
- **Easy to deploy:** the supported path should be a small number of documented commands.
- **Offline-safe:** checkout, inventory, and staff workflows must continue when the server is unavailable.
- **Transparent:** the app must show what is pending, synchronized, failed, or in conflict.
- **Reversible:** disconnecting from a server must not delete the device's local data.
- **Portable:** users can use local backup and restore independently of cloud sync.
- **Privacy-preserving:** no mandatory hosted Karbar account or telemetry service is required.

## 2. Goals and non-goals

### Goals

1. Allow an owner to connect two or more Karbar installations belonging to the same shop.
2. Synchronize the shared catalog, customers, suppliers, staff, shop settings, and transaction history.
3. Make retries safe when devices lose connectivity or repeat a request.
4. Make conflicts explicit and reviewable instead of silently overwriting business data.
5. Provide a reliable deployment path that does not require the user to understand Go or PostgreSQL.
6. Keep the server useful without requiring a separate Karbar-managed cloud service.
7. Provide clear backup, update, restore, and troubleshooting instructions.

### Non-goals for the first self-hosted release

- A hosted multi-tenant service operated by Karbar.
- Real-time collaborative editing or instant dashboard updates.
- Arbitrary third-party integrations.
- Automatic server administration or remote access to a user's infrastructure.
- Treating the sync server as the only backup of a shop's data.

## 3. Supported user journeys

### Journey A: local-only shop

1. Install Karbar.
2. Complete shop setup and create local staff accounts.
3. Use POS, inventory, reports, backups, and receipts without configuring sync.

No cloud-related screen should block this path.

### Journey B: owner enables self-hosted sync

1. The owner installs the Karbar sync server using the deployment guide.
2. The owner creates a server URL and configures the required secrets.
3. In Karbar, the owner opens **Settings → Cloud Sync**.
4. The owner enters the server URL and tests connectivity.
5. The owner registers or signs in to the shop account.
6. Karbar uploads the local catalog and queued transaction history using stable IDs and idempotent requests.
7. The app shows an initial sync summary and the current sync status.

The setup flow must explain that the server is user-managed and that HTTPS, database backups, and server updates are the owner's responsibility.

### Journey C: connect another device

1. Install Karbar on the second device.
2. Complete the local app setup.
3. Open Cloud Sync and sign in to the existing shop account.
4. Pull the shared catalog and transaction history.
5. Keep device-local preferences, such as language and theme, independent unless explicitly marked as shared.
6. Require local staff authentication before the device can be used for shop operations.

### Journey D: server unavailable

1. The device continues operating against SQLite.
2. Local changes are committed normally and added to durable outboxes in the same transaction.
3. The app retries later using the same event or mutation IDs.
4. The UI reports the outage without blocking checkout.

### Journey E: disconnect or migrate

1. The owner can sign out or disconnect the server from Settings.
2. Local data remains on the device.
3. The owner can export a normal Karbar backup before changing servers.
4. A new server can be connected later, subject to an explicit initial-sync decision.

## 4. Proposed architecture

```text
┌───────────────────────────────┐
│ Karbar Flutter app             │
│                               │
│ SQLite                         │
│ - catalog and shop data        │
│ - sales, returns, purchases    │
│ - staff and settings           │
│                               │
│ Durable outboxes               │
│ - transaction events           │
│ - catalog mutations            │
│                               │
│ Sync coordinator               │
│ - upload                       │
│ - cursor-based pull            │
│ - conflict inbox               │
└───────────────┬───────────────┘
                │ HTTPS / REST
                ▼
┌───────────────────────────────┐
│ User-hosted Karbar sync API    │
│                               │
│ Go net/http                    │
│ - authentication               │
│ - shop isolation               │
│ - event inbox and feed         │
│ - revisioned catalog API       │
│ - health endpoint              │
└───────────────┬───────────────┘
                ▼
┌───────────────────────────────┐
│ PostgreSQL                     │
│ - shops and users              │
│ - catalog snapshots             │
│ - immutable event records      │
│ - cursors and mutations        │
└───────────────────────────────┘
```

The existing `backend/` service is the foundation for this architecture. It already provides shop-scoped authentication, rotating refresh tokens, an idempotent event inbox/feed, revisioned catalog writes, and Docker Compose deployment.

## 5. Data synchronization model

Different data types need different synchronization rules. A single last-write-wins rule is unsafe for a POS system.

| Data | Direction | Rule |
|---|---|---|
| Sales and sale items | Device → server | Append-only transaction event; never silently replace another sale |
| Sale returns | Device → server | Append-only event; enforce return limits during application |
| Baki collections | Device → server | Append-only payment event; apply idempotently |
| Purchases | Device → server | Append-only event; import history without applying stock twice |
| Products and variants | Bidirectional | Stable UUID plus optimistic revision and conflict review |
| Customers | Bidirectional | Stable UUID plus optimistic revision and conflict review |
| Suppliers | Bidirectional | Stable UUID plus optimistic revision and conflict review |
| Staff accounts | Bidirectional | Stable UUID, role/active-state revisions, protected credentials |
| Shop profile, currency, tax | Bidirectional | Shared revisioned settings |
| Language and theme | Device-local | Do not sync by default |
| Product images | Device → server → devices | Size-limited, validated image payload or future object storage |

### Stable identity

Local SQLite integer IDs are device-scoped and must never be treated as global IDs. Shared entities need stable UUIDs generated locally and preserved across retries, backup restore, and synchronization.

Every transaction event and catalog mutation must have an immutable idempotency key. Retrying the same request must produce the original result rather than a duplicate sale, payment, purchase, or catalog mutation.

### Transaction events

Transaction events are immutable facts. The server stores and deduplicates them, and other devices consume them through a cursor-based feed.

The client must:

1. Commit the local business transaction and outbox event atomically.
2. Send pending events in creation order.
3. Stop or back off after a failure while retaining the event for retry.
4. Reuse the same event ID on every retry.
5. Apply incoming events idempotently using their origin identifiers.
6. Preserve the original transaction's staff, customer, product, price, discount, tax, and cost snapshots.

### Catalog mutations

Catalog records are editable snapshots rather than append-only sales. Each mutation includes:

- Stable entity UUID.
- Mutation UUID.
- Device's last-known server revision.
- Complete canonical payload or tombstone.

The server accepts the mutation only when the base revision is current. A stale mutation returns the current server copy and creates a reviewable conflict. The client must never silently overwrite a newer server record or a newer local edit.

### Stock ownership

Stock is business-critical and must not be incremented twice when transaction history is imported. The implementation should keep one clearly documented rule for how current stock is reconciled:

- Catalog snapshots carry the server's current shared stock state.
- Imported historical purchases and sales are applied to local history idempotently.
- Applying a historical event must not re-run a stock mutation that has already been represented by the catalog snapshot.
- Any unresolved stock discrepancy must be visible to the owner rather than hidden by a last-write-wins update.

## 6. Self-hosting and deployment experience

### Supported deployment shape

The first supported deployment should be a Docker Compose stack containing:

1. PostgreSQL.
2. A migration job that runs versioned SQL migrations.
3. The Go API.
4. A persistent PostgreSQL volume.

TLS should normally be provided by a reverse proxy such as Caddy, Nginx, or a managed VPS proxy. Local HTTP may be allowed for localhost development only; device connections to a remote server must use HTTPS.

### Required configuration

The deployment guide should clearly document:

- `DATABASE_URL`.
- `JWT_SECRET`.
- `REGISTRATION_SECRET`.
- API port and reverse-proxy configuration.
- PostgreSQL volume location.
- Domain name or LAN address.
- Firewall rules and exposed ports.
- Backup destination and retention policy.

Secrets must be long, random, and supplied through environment or secret-management facilities. Example credentials must never be suitable for production.

### Easy-install target

The self-hosting documentation should provide:

```text
1. Install Docker and Docker Compose.
2. Download the Karbar server release files.
3. Copy the example environment file.
4. Generate or enter secrets.
5. Start the stack.
6. Open the health URL.
7. Connect the Karbar app using the server URL.
```

Future improvements may include a setup script, a guided web setup page, or packaged releases, but the underlying deployment should remain inspectable and reproducible.

### Updates

Every server release needs:

- A visible version number.
- Migration instructions.
- Compatibility notes for supported app versions.
- A backup reminder before upgrading.
- A rollback warning when a migration is irreversible.

Database migrations must be additive or have an explicitly documented recovery path. Users must not be told to delete the PostgreSQL volume during a normal update.

## 7. App connection and sync UX

The Cloud Sync screen should be understandable to a shop owner who did not build the server.

### Connection states

Show one of these states prominently:

- Not configured.
- Testing connection.
- Connected and synchronized.
- Syncing.
- Offline; local changes are safe and queued.
- Authentication expired; sign in required.
- Sync failed; retry available.
- Conflict needs owner review.
- Server version incompatible.

### Required actions

- Enter or edit server URL.
- Test connection.
- Register or sign in.
- Start initial sync.
- Sync now.
- View pending events.
- View failed events and error details.
- Review catalog conflicts.
- Sign out.
- Disconnect without deleting local data.

### User-facing language

The app should use precise language:

- “Saved on this device” means the local SQLite transaction committed.
- “Synced” means the server accepted the event or mutation.
- “Pending” means it is stored locally and will be retried.
- “Conflict” means two valid edits need an owner decision.
- “Backup” means an exported or server-side database copy, not merely a queued event.

## 8. Security and privacy requirements

### Client security

- Store access and refresh tokens only in platform secure storage.
- Use HTTPS for non-localhost servers.
- Do not log passwords, tokens, PIN hashes, or full customer records.
- Clear or rotate local sync credentials on sign-out.
- Require local staff authentication independently of server connectivity.

### Server security

- Resolve `shop_id` only from authenticated token claims.
- Apply shop scoping to every database query.
- Hash passwords and refresh tokens appropriately.
- Rotate refresh tokens and expire access tokens.
- Require an operator-controlled registration secret for account creation.
- Rate-limit authentication and registration endpoints.
- Validate event sizes, image sizes, timestamps, and payload schemas.
- Keep staff PIN hashes and salts protected from ordinary API responses.
- Use PostgreSQL access controls and encrypted backups where available.
- Provide a security response path for self-hosting users.

Self-hosted deployment means Karbar cannot guarantee the user's server security. Documentation must state which protections are provided by the application and which protections remain the hoster's responsibility.

## 9. Backups and disaster recovery

Sync and backup are separate features.

The user should be encouraged to maintain both:

1. **Local application backups** made through Karbar's backup/restore feature.
2. **Server backups** of the PostgreSQL database and any external image storage.

The deployment guide should document:

- Scheduled PostgreSQL dumps or volume snapshots.
- Backup encryption and access control.
- Retention periods.
- Restore testing on a separate instance.
- What happens to clients while the server is being restored.
- Reconnecting a device after a catastrophic server replacement.

The app must not claim that a transaction is backed up merely because it is queued for sync or accepted by the API. A server event log is not a substitute for tested database backups.

## 10. Compatibility and API evolution

The API should continue using a versioned path such as `/v1`.

The server should expose a small unauthenticated health/capability response containing:

- Server version.
- API version.
- Database migration level.
- Supported sync features.
- Minimum and maximum compatible app versions, where needed.

The app should test compatibility before beginning an initial sync. If a server is too old or too new, the app should explain the upgrade path and preserve local operation.

Backward compatibility requirements:

- New app versions should tolerate missing optional server capabilities.
- New server versions should preserve existing `/v1` behavior when possible.
- Event payloads should be versioned or forwards-compatible.
- Unknown optional fields should be ignored safely.
- Destructive schema changes require a migration and release note.

## 11. Observability without central telemetry

Because the service is self-hosted, diagnostics must work without sending data to Karbar.

The server should provide:

- `/v1/healthz` for liveness checks.
- Structured local logs with request IDs.
- Sync counters and migration status in logs.
- Safe error messages that do not expose secrets.
- Documentation for inspecting API and database container logs.

The app should provide a copyable diagnostic summary containing server URL host, API version, connection state, pending count, last successful sync time, and last error category—without tokens or business records.

## 12. Implementation roadmap

### Phase 1 — Stabilize the sync contract

- Document the event and catalog payload formats.
- Finalize stable UUID and origin-ID rules.
- Add explicit server/app capability negotiation.
- Verify idempotent replay for sales, returns, purchases, baki payments, and catalog mutations.
- Verify dependency ordering for products, variants, suppliers, staff, and transaction history.

### Phase 2 — Make the server easy to host

- Maintain a production Docker Compose example.
- Add pinned image and dependency versions.
- Provide migration-on-start or migration-job guidance.
- Add health checks and clear startup failures.
- Document TLS reverse-proxy setups.
- Add backup, restore, upgrade, and rollback guides.

### Phase 3 — Finish the app connection flow

- Improve Cloud Sync onboarding for non-technical users.
- Add connection testing and capability checks.
- Add clear pending/error/conflict states.
- Preserve local operation during every connection failure.
- Make sign-out, disconnect, and re-pairing safe.

### Phase 4 — Validate real deployments

- Test on a fresh VPS with a real domain and TLS.
- Test two or more Android/iOS devices on one shop.
- Test offline sales followed by reconnect and retry.
- Test duplicate requests and interrupted uploads.
- Test concurrent catalog edits and conflict resolution.
- Test PostgreSQL backup and restore.
- Test server upgrade across supported migration versions.

### Phase 5 — Publish the self-hosting package

- Publish a versioned server release bundle.
- Publish the deployment guide and troubleshooting guide.
- Publish an app/server compatibility matrix.
- Add a clear “self-hosted sync is optional” explanation to the app and README.
- Mark deployment verification complete only after the real deployment tests pass.

## 13. Acceptance criteria

The self-hosted sync feature is ready for general use when:

- A new user can deploy the server by following the written guide without modifying application source code.
- A local-only user can ignore sync completely.
- A shop can connect two devices and see shared catalog and transaction history without duplicate records.
- A server outage never prevents a local sale from being recorded.
- Retried requests never duplicate a sale, return, purchase, payment, or catalog mutation.
- Concurrent catalog edits produce an understandable conflict instead of silent data loss.
- Staff permissions and local authentication remain safe offline.
- The owner can see pending and failed work and retry it.
- A PostgreSQL backup can be restored and clients can reconnect safely.
- Server upgrades have documented migrations and compatibility behavior.
- The app never describes an unsynchronized or unbacked-up record as safely backed up.

## 14. Decisions still required

1. Whether the first release supports one shop per server installation or multiple shops per installation.
2. Whether product images remain in PostgreSQL payloads or move to local/object storage.
3. Whether the server exposes a minimal admin/status page or remains API plus documentation only.
4. Whether registration is performed from the app, a one-time server setup command, or both.
5. The minimum supported server hardware and PostgreSQL version.
6. The supported reverse-proxy examples for the first release.
7. The conflict-resolution policy for stock and other numeric catalog fields.
8. The retention policy for immutable event records and tombstones.
9. The release channel and compatibility policy for app/server version combinations.

## Related documentation

- [Backend architecture](backend.md)
- [Backend deployment and API README](../backend/README.md)
- [User feature roadmap](user_feature_roadmap.md)
- [Android release notes](android_release.md)
