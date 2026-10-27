# Karbar — User Feature Roadmap

This document lists the most useful next features for a small-shop user and gives implementation guidance based on the current Flutter and SQLite app. It is intended to help turn the roadmap into small, reviewable changes.

## Current feature baseline

The app already includes:

- Product and variant management, product images, barcode scanning, and low-stock indicators.
- Stock receiving with quantity and optional cost price. Stock movements are recorded, but the receiving flow does not yet provide a supplier workflow.
- POS cart, item and order discounts, tax calculation, and cash or baki checkout.
- Customer records, customer baki balances, payment recording, and a basic age indicator.
- Sales history, PDF receipt sharing/printing, and dashboard revenue, best sellers, low-stock, and basic profit figures.
- English and Bangla labels, theme selection, and currency/tax settings.

Avoid rebuilding these features. Improve their gaps and connect incomplete shortcuts. In particular, the Settings screen shows Inventory and Reports shortcuts that currently have no action. Settings and shop details now persist in SQLite; first-run setup asks the owner to configure the shop and currency. The default currency before setup is `$`.

## Implementation progress

- [x] Persist settings and add shop setup/profile.
- [x] Backup and restore.
- [x] Reports and connected Settings shortcuts.
- [x] Additional payment methods and split payments.
- [x] Sale returns and corrections.
- [x] Supplier and purchase tracking.
- [x] Sales history search and receipt reprint.
- [x] Fractional quantities.
- [x] Daily cash close.
- [x] Historical cost snapshots for profit.
- [x] Staff PIN access, roles, and sale/close attribution.
- [ ] Optional multi-device cloud sync.

## Priority 1 — Make daily use reliable

### 1. Persist settings and add shop setup

**User outcome:** Currency, language, tax, and theme remain as selected. Receipts identify the shop.

**Implementation guidance:**

1. Persist the current `SettingsState` fields using a small local settings store. Shared Preferences is suitable for simple values; SQLite is also reasonable if shop profile and settings are stored together. **Implemented:** app settings and shop profile now use the SQLite settings table.
2. Load saved settings before the first screen uses them. Provide a loading/default state so the app does not briefly display the wrong currency or theme.
3. Add a shop profile with shop name, phone, address, and optional logo. Keep it local and include it in backups.
4. Add a first-run setup path, while keeping the profile editable later in Settings. Let the owner choose currency rather than assuming a country.
5. Apply the saved currency and shop profile consistently to POS, baki, dashboard, history, and receipts.

**Done when:** changing a setting, closing and reopening the app, and generating a receipt all show the saved values.

**Relevant code:** `lib/providers/settings_provider.dart`, `lib/screens/settings/settings_screen.dart`, `lib/screens/receipt/receipt_screen.dart`.

### 2. Add backup and restore — implemented

**User outcome:** A shop can move to a new phone or recover after losing the old one.

**Implementation guidance:**

1. Define a versioned JSON backup format. Include products, variants, customers, sales and sale items, baki payments, stock movements, shop profile, and settings.
2. Export through the platform share/save sheet so the owner can put the file in a safe location. Android and iOS use the system share sheet; desktop platforms use the native save dialog.
3. On restore, validate the format and version before changing local data. Show a clear summary and require an explicit choice to replace or merge data.
4. Restore all related records in one database transaction. If validation or insertion fails, roll back without leaving partial data.
5. Keep primary keys and relationships consistent. For merge mode, define duplicate handling explicitly; do not silently overwrite records based only on names.
6. Show the backup date and a success/failure message. Do not claim a cloud backup unless the file was actually uploaded.

**Done when:** a backup made on one app install restores products, stock, sales, and customer balances on a clean install, and invalid files leave existing data untouched.

**Relevant code:** `lib/services/backup_service.dart`, `lib/screens/settings/backup_restore_screen.dart`, `lib/db/database_helper.dart`. The version 1 JSON backup includes all SQLite tables, settings, and available product image files. Restore replaces local data only after confirmation and performs database writes in a transaction.

### 3. Complete Reports and Settings shortcuts — implemented

**User outcome:** Owners can answer “How much did I sell?”, “What made profit?”, and “What should I restock?” for a chosen period.

**Implementation guidance:**

1. Make the Reports shortcut navigate to a Reports screen. Connect the Inventory shortcut to Warehouse, or remove it until it is connected. **Implemented:** both Settings shortcuts now navigate to their screens.
2. Start with date range selection and report cards for gross sales, discounts, tax, sales count, average sale, estimated profit, and baki issued/collected. **Implemented:** Today, last 7 days, this month, and custom date ranges are available.
3. Add product and payment-method breakdowns, plus a low-stock/reorder list.
4. Put report calculations in database/provider methods instead of calculating them inside widgets. Use start-inclusive/end-exclusive date ranges to avoid missing records at day boundaries.
5. Offer CSV export first for spreadsheet use; add a printable PDF summary if it fits the existing receipt/export approach. **Implemented:** CSV uses the platform share sheet on mobile and a save dialog on desktop.
6. Clearly label estimated profit and any sales whose historical cost is unknown.

**Done when:** changing the report period changes all totals and breakdowns together, and the export matches the on-screen values.

**Relevant code:** `lib/screens/reports/reports_screen.dart`, `lib/providers/reports_provider.dart`, `lib/db/database_helper.dart`, `lib/models/sales_report.dart`. A v7 additive migration stores tax per sale. Existing sales have no stored tax breakdown, so the report explains that limitation and only totals recorded tax amounts.

### 10. Preserve historical cost for profit reports — implemented

**User outcome:** Editing a product's current cost does not rewrite profit for sales that happened earlier.

**Implementation guidance:**

1. Add a nullable cost snapshot to each sale item and capture the product cost during checkout.
2. Use the saved snapshot for dashboard profit, period reports, and return adjustments. Never join historical sales to the current product cost for these calculations.
3. Leave the snapshot null for older sales and sales made without a known cost. Reports count and explain lines whose cost is unknown rather than presenting them as known profit.
4. Add an additive SQLite migration and keep older backup formats readable. Old sale rows restored from a backup remain unknown-cost rows.

**Done when:** changing a product's current cost after a sale leaves that sale's profit unchanged, and restoring an older backup does not fabricate a historical cost.

**Relevant code:** `lib/db/database_helper.dart`, `lib/services/backup_service.dart`, `lib/models/sales_report.dart`. Database version 13 adds `sale_items.cost_price_snapshot`; backup format version 7 accepts versions 1–6 with the snapshot left unknown.

### 4. Add payment methods and split payments — implemented

**User outcome:** A sale can accurately record cash, bKash, Nagad, card, or a combination, including an amount left on baki.

**Implementation guidance:**

1. Replace the checkout binary choice with a payment allocation screen. Allow one or more methods and an amount for each.
2. Add a `sale_payments` table with sale ID, method, amount, and optional reference/note. Keep existing `sales.payment_type` readable during migration or derive it for older screens until all consumers move to allocations.
3. Validate that received amounts plus any baki amount equal the final sale total. Prevent negative values and overpayment unless change-making is explicitly supported.
4. Require/select a customer when any amount is recorded as baki. Record the outstanding amount in a way that keeps customer balances and payment history consistent.
5. Update sales history, reports, and daily close to show allocations by method.
6. Add the table with an additive database migration. Preserve old sales as their existing cash/baki type.

**Done when:** full cash, full digital payment, split tender, and partial-payment-plus-baki sales all produce correct totals and customer balances.

**Relevant code:** `lib/screens/pos/cart_screen.dart`, `lib/models/sale.dart`, `lib/db/database_helper.dart`, `lib/screens/history/history_screen.dart`.

## Priority 2 — Handle mistakes and stock purchasing

### 5. Add returns, refunds, and sale correction — implemented

**User outcome:** Staff can correct a mistaken sale or record a partial return without losing the audit trail.

**Implementation guidance:**

1. Add a sale detail action for return/correction. Support partial quantity returns and a reason.
2. Record returns in `sale_returns` and `sale_return_items`, preserving the original sale and its history. **Implemented.**
3. In one transaction, record the return, restore stock, and record the refund method or baki reduction. **Implemented.**
4. Cap returns by sold quantity minus earlier returns. Show returned quantity and value beside the original sale. **Implemented.**
5. Subtract returns from period net sales, receivables, payment totals, baki, and estimated profit. Record stock movement for each restocked return. **Implemented.**

**Done when:** a partial return updates stock and net sales correctly, repeated returns cannot exceed sold quantity, and the original sale remains auditable.

### 6. Complete supplier and purchase tracking — implemented

**User outcome:** The owner can see what was bought, from whom, at what cost, and what remains payable.

**Implementation guidance:**

1. Add supplier records with name and optional phone/address/notes. **Implemented.**
2. Record multiple product variants, quantities, unit costs, supplier, date, and note in one purchase. **Implemented.**
3. Save purchase headers and lines, and link each stock movement to its supplier. **Implemented.**
4. Update stock and the latest product cost in the same transaction as the purchase. A failed line rolls back the purchase and earlier stock changes.
5. Keep the quick Stock In action; both receiving flows use the same stock movement helper.
6. Show purchase history and period purchase totals by supplier in Reports.

**Done when:** purchase history explains stock changes, supplier totals reconcile to purchases, and receiving does not update stock twice. Verified by multi-line and rollback tests.

### 7. Improve sales history — implemented

**User outcome:** A shopkeeper can find a past sale quickly and re-share its receipt.

**Implementation guidance:**

1. Search by receipt/sale number and customer name/phone. **Implemented.**
2. Filter by date range and payment method; reset search, method, or date filters directly.
3. Expand each sale to review items, discounts and return details, then reprint/share the original receipt.
4. Keep the current expansion list as a quick view if useful, but avoid loading a very large history all at once; paginate or query by date as volume grows.

**Done when:** a sale can be found by customer and date, and the re-shared receipt reflects the original sale data. Implemented with local history filtering and a history return path from receipt preview.

## Priority 3 — Fit more shop types and daily operations

### 8. Support measured and fractional quantities — implemented

**User outcome:** Shops can sell rice, oil, fabric, and other goods by weight or volume.

**Implementation guidance:**

1. Store stock, sale, return, purchase, and movement quantities as numeric values. **Implemented.**
2. Keep the product unit and configure whole units or up to three decimal places. Show the unit in product, cart, stock, and receipt views.
3. Convert SQLite-backed models and report calculations to doubles. SQLite keeps existing whole values; the v11 migration adds the per-product precision setting with a default of zero.
4. Validate quantities against each product's precision for sales, receiving, purchases, and returns. Reject whole-unit fractions and return overruns.
5. Format quantities without unnecessary trailing zeros. **Implemented.**

**Done when:** a fractional sale reduces stock by the same amount and the receipt displays the quantity and unit clearly. Verified with fractional sale, return, report, and whole-unit rejection tests. Backup v4 files remain restorable with whole-unit precision by default.

### 9. Add daily cash close — implemented

**User outcome:** At shift end, the owner can reconcile expected cash with the drawer and see payment totals.

**Implementation guidance:**

1. Show payment totals, baki issued/collected, refunds, and expected drawer cash for a selected date.
2. Let the owner enter counted cash and see the variance.
3. Save a dated snapshot with all payment totals and note; preserve earlier closes for that date.
4. If the app later supports staff accounts, attach each close to the cashier/shift.

**Done when:** the close summary reconciles to recorded transactions for the selected day and remains available afterward. Verified with cash, baki, refund, repeated-close, and backup tests.

### 10. Make profit history stable

**User outcome:** Past profit remains meaningful when product costs change.

**Implementation guidance:**

1. Store a cost-price snapshot on each sale item at checkout, alongside the sale price and discount.
2. Calculate future profit reports from the snapshot, not the product's current cost.
3. For old sales without a stored cost, display “cost unavailable” or mark estimates. Do not silently apply today's cost to past sales.
4. Add the new column with a safe additive migration and update backup/export formats.

**Done when:** editing a product's cost later does not change profit for sales already recorded.

### 11. Add staff access — implemented

**User outcome:** Multiple staff can use the app with appropriate access, and owners can use more than one device.

**Implementation guidance:**

- Require the owner to create the first staff account with a 4–8 digit PIN; store PINs as salted, iterated hashes.
- Let owners add owner/cashier accounts, reset PINs, and disable accounts. Keep at least one active owner.
- Require staff selection and PIN entry at app start. Cashiers stay in POS; owners can use settings, reports, inventory, and data management.
- Record the active staff ID on each new sale and cash close. Existing records remain unattributed.
- Include staff accounts in backups, accept older backup versions, and require sign-in again after restoring a backup.
- Keep staff login and checkout fully local and available offline.

**Done when:** owner and cashier accounts have different access, invalid PINs are rejected, new sales/closes retain the signed-in staff ID, and legacy backups/database records restore without fabricated attribution.

**Relevant code:** `lib/models/staff_user.dart`, `lib/providers/staff_provider.dart`, `lib/screens/settings/staff_gate_screen.dart`, `lib/screens/settings/staff_management_screen.dart`, `lib/db/database_helper.dart`, `lib/services/backup_service.dart`.

### 12. Add optional multi-device cloud sync — in progress

- [x] Define account ownership, offline edits, conflict handling, and catalog deletion behavior.
- [x] Use stable IDs and idempotent sync operations so retries cannot duplicate sales.
- [x] Keep local checkout available offline and show queued, staged, conflict, and error states.
- [x] Include authentication and shop-scoped data access in the sync service.
- [x] Sync shared shop settings and supplier records with revision conflict handling.
- [x] Sync purchase history without reapplying stock; [x] sync staff accounts and PIN credentials; [x] sync product images.
- [x] Schedule OS background sync retries; [ ] verify the deployed service.

Core sync now covers catalog records, transaction history, staff, product images, and OS-scheduled retries. Only verification against the deployed service remains on this checklist.

**Implementation progress:** SQLite v17 records sale, return, and baki collection events in a durable outbox. Purchase headers and lines use `purchase.recorded` events, stable supplier/product/variant IDs, and source event IDs for idempotent import. Incoming purchase history waits for its catalog dependencies; importing history and audit stock movements does not change current stock or product cost. SQLite v23 adds purchase origin IDs. SQLite v24 adds stable staff UUIDs and syncs account profiles, roles, active state, and salted PIN hashes through the revisioned catalog inbox/outbox. Product snapshots carry compressed JPEG image data capped at 280 KiB; the server validates the image and remote devices store it as a local file. Incoming staff records retain local row IDs, enable offline PIN authentication, and cannot remove the last active owner. Backup v13 accepts versions 1–12 and backfills staff/catalog IDs on restore. Events have UUID idempotency keys, keep retry counts/errors, survive backup/restore, and are sent sequentially by an HTTPS-only sync runner. The Go/PostgreSQL service provides operator-gated shop registration, phone/password login, rotating refresh tokens, idempotent event acceptance, and a shop-scoped event feed. The owner-only Settings screen supports account creation/sign-in, platform secure token storage, sign-out, pending counts, and manual sync. SQLite v16 stages incoming transaction event pages in an account-scoped inbox with a durable cursor; restore resets device-specific pull state. SQLite v17 adds stable UUID sync IDs to products, variants, and customers; SQLite v22 adds supplier sync IDs and backfills existing rows. SQLite v21 adds durable origin IDs to imported sales, returns, and baki payments and retryable apply errors to staged events. Sync retries after expired credentials. The Go API exposes revision-checked catalog writes and a cursor feed; mutation IDs make retries idempotent, and stale revisions return the latest server copy for explicit conflict resolution. The Flutter client durably queues product, customer, supplier, staff, and shared shop-settings snapshots, including compressed product images per account, retries with stable mutation IDs, and sends product tombstones. Language and theme remain device-local. Sync runs automatically at app launch and resume, every five minutes while the app stays in the foreground, and through a 12-hour OS periodic task on Android and iOS; the Settings button uses the same single-flight runner. OS background timing remains system-controlled, especially on iOS. It uploads local changes, pulls and applies safe catalog updates before transaction history, and stages unresolved catalog conflicts or transaction dependency errors for retry. **Deployment verification remains pending.** Queued data is not a cloud backup until accepted by the server.

These are larger features and should follow reliable backup/restore and database migrations.

## Shared implementation rules

- Add database changes as additive migrations. Never drop user data during an app upgrade.
- Update models, database mapping, providers, screens, receipts, backup/export, and reports together when adding a field.
- Keep money calculations in one shared layer and use the configured currency consistently.
- Preserve offline POS use; network-dependent features should show their state and provide a safe local path.
- Keep English and Bangla labels aligned as screens and settings are added.
- For every feature, define what happens to existing records and verify totals, stock, customer balances, and receipts remain consistent.

## Suggested delivery order

1. Persist settings and add shop profile/setup.
2. Backup and restore.
3. Reports screen and connect existing shortcuts.
4. Payment methods and split payments.
5. Sale returns and corrections.
6. Supplier and purchase tracking.
7. Sales history search and receipt reprint.
8. Fractional quantities, daily close, and historical cost snapshots.
9. Staff access.
10. Optional cloud sync after selecting a provider and account model.
