# mPOS — Improvement Plan

> A living document for what's broken, what's missing, and what's next.

---

## Priority Matrix

```
IMPACT
  │
H │  ██ Currency Bug    ██ Tax Applied     ░░ Stock-In        ░░ Backup/Export
  │  ██ History Labels  ░░ Baki Aging      ░░ Discount        ░░ Profit Margin
  │                     ░░ Daily Close     ░░ Multi-Payment
  │
M │                                        ░░ DB Migration     ░░ User Accounts
  │                                        ░░ Barcode Print
  │
L │                                                            ░░ Cloud Sync
  └──────────────────────────────────────────────────────────────────────────
       QUICK FIX              MEDIUM                 LARGE
```

**Legend:** `██` = Bug / broken today  `░░` = Missing feature

---

## 🔴 Critical Bugs (fix immediately)

### 1. Currency Symbol Hardcoded

Every sale shows `$` regardless of what the shopkeeper set in Settings.

**Where it breaks:**

```
lib/screens/pos/cart_screen.dart      → NumberFormat.currency(symbol: '\$')
lib/screens/receipt/receipt_screen.dart → NumberFormat.currency(symbol: '\$')
lib/screens/home_screen.dart          → reads settings ✅ (correct)
```

**Fix:** Pass `settingsProvider.currencySymbol` into `NumberFormat` wherever currency is formatted. One-line change per file.

---

### 2. Tax Rate Exists But Does Nothing

`SettingsState` has `taxRate` and `showTax` — but `CartNotifier.totalAmount` ignores both.

**Current flow (broken):**

```
Settings screen
    └─ user sets taxRate = 15%
           │
           ▼
     SettingsState.taxRate = 0.15
           │
           ▼  ← ✗ never read
     CartNotifier.totalAmount = sum(items)   ← tax silently skipped
           │
           ▼
     Receipt shows no tax line
```

**Fixed flow:**

```
CartNotifier.totalAmount
    ├─ subtotal = sum(items)
    ├─ tax      = subtotal × taxRate   (if showTax)
    └─ total    = subtotal + tax

Receipt
    ├─ Subtotal:   ৳1,000
    ├─ VAT (15%):  ৳  150
    └─ Total:      ৳1,150
```

---

### 3. History Screen Doesn't Show Payment Type

`Sale.paymentType` is stored in the DB but history renders every sale identically. A shopkeeper can't tell which sales were baki at a glance.

**Expected:**

```
┌─────────────────────────────────────────┐
│  Sale #42        2:30 PM      ৳ 450     │
│  3 items                   [ Nagad ✓ ]  │
├─────────────────────────────────────────┤
│  Sale #41       11:15 AM      ৳ 800     │
│  5 items    Rahim       [ বাকি ⏳ ]     │
└─────────────────────────────────────────┘
```

---

## 🟡 Medium Priority — Feature Gaps

### 4. Stock-In / Purchase Recording

Right now stock **only goes down** (sales). There is no way to record receiving new inventory. The shopkeeper has to manually edit each product.

**Proposed flow:**

```
Warehouse Screen
      │
      ├── [+ Add Product]          ← exists today
      │
      └── [Stock In ↑]             ← NEW button
                │
                ▼
        Select Product
                │
                ▼
        Enter Quantity + Cost Price (optional)
                │
                ▼
        stock += quantity
        Record in stock_movements table (for audit trail)
```

**New table needed:**

| Column       | Type    | Notes                        |
|--------------|---------|------------------------------|
| id           | INT PK  |                              |
| variant_id   | INT FK  | which variant was stocked in |
| quantity     | INT     | units received               |
| cost_price   | REAL    | what was paid per unit       |
| supplier     | TEXT    | optional note                |
| created_at   | TEXT    |                              |

---

### 5. Discount System

No way to apply discounts — per-item or order-level. Very common in Bangladeshi retail.

**Two levels needed:**

```
Order Discount                    Item Discount
─────────────────                 ─────────────────
Cart total: ৳1,000                Rice 5kg    ৳ 500
                                  Discount:  -৳  50
[Discount: 10%]  →  -৳100        ──────────────────
─────────────────                 Net:        ৳ 450
Total:       ৳900
```

**Impact on models:**

```
CartItem
  + discountAmount: double   (flat discount on this item)

Sale
  + discountAmount: double   (order-level discount)
  + discountType: 'flat' | 'percent'
```

---

### 6. Baki Aging Indicator

All baki looks the same on the Baki Hiseb screen. A 1-week-old debt and a 3-month-old debt look identical.

**Proposed visual:**

```
┌─────────────────────────────────────────────┐
│  🟢  Karim          ৳800    today           │
│  🟡  Rahim         ৳1,200   8 days          │
│  🔴  Sumaiya       ৳3,400   42 days ⚠️      │
└─────────────────────────────────────────────┘

🟢 < 7 days     → green   (fresh)
🟡 7–30 days    → amber   (follow up)
🔴 > 30 days    → red     (overdue)
```

Implementation: purely computed from `lastActivity` — no new DB column needed.

---

### 7. Multiple Payment Methods

Currently payment is binary: Nagad (cash) or Baki. But real transactions are messier.

**Real scenarios:**

```
Scenario A: Split payment
  Customer owes ৳1,000
  Pays ৳500 cash + ৳500 bKash
  → Record as 2 partial payments, 0 baki

Scenario B: Partial upfront + rest baki
  Customer owes ৳1,000
  Pays ৳400 now, ৳600 baki
  → Record ৳400 received, baki = ৳600

Scenario C: bKash/Nagad app
  Customer pays via mobile banking
  → Should be tagged separately from cash
```

**Proposed payment types:**

| Code     | Label         | Icon                      |
|----------|---------------|---------------------------|
| `cash`   | Cash          | 💵                        |
| `bkash`  | bKash         | 📱                        |
| `nagad`  | Nagad App     | 📲                        |
| `baki`   | বাকি          | 📋                        |

---

### 8. Daily Close / Cash Register

End-of-day summary that answers: *how much money should be in the drawer?*

**Proposed screen:**

```
┌──────────────────────────────────────────┐
│         Day Close — 27 Jul 2026          │
│──────────────────────────────────────────│
│  Cash sales today:           ৳ 4,200     │
│  bKash / Nagad:              ৳   800     │
│  Baki given out:             ৳ 1,500     │
│  Baki collected:             ৳   900     │
│──────────────────────────────────────────│
│  Expected in drawer:         ৳ 5,000     │
│  Actual (enter):  [________]             │
│  Difference:                 ৳     0     │
│──────────────────────────────────────────│
│             [ Close Day ]                │
└──────────────────────────────────────────┘
```

---

### 9. Profit Tracking

`cost_price` exists on products but is never surfaced anywhere. The dashboard shows revenue but not **profit**.

**Dashboard additions:**

```
Current dashboard cards:
  [ Today Revenue ]  [ This Week ]  [ This Month ]  [ Avg Sale ]

Proposed additions:
  [ Today Profit ]   [ Margin % ]   [ Cost vs Revenue chart ]

Profit = SUM( (sale_price - cost_price) × quantity )  per sale_item
```

This requires no new DB columns — `cost_price` is already on `product_variants`, just unused.

---

## 🔵 Architecture / Technical Debt

### 10. DB Migration Destroys All Data

The current `_onUpgrade` drops every table and recreates from scratch. One app update = complete data loss.

**Current (dangerous):**

```dart
Future<void> _onUpgrade(db, oldVersion, newVersion) async {
  await db.execute('DROP TABLE IF EXISTS ...');  // 💀 all data gone
  await _createTables(db);
}
```

**Correct pattern:**

```dart
Future<void> _onUpgrade(db, oldVersion, newVersion) async {
  if (oldVersion < 3) {
    // additive only — never DROP
    await db.execute('ALTER TABLE sales ADD COLUMN payment_type TEXT DEFAULT "cash"');
    await db.execute('CREATE TABLE IF NOT EXISTS customers (...)');
  }
  if (oldVersion < 4) {
    await db.execute('ALTER TABLE sales ADD COLUMN discount_amount REAL DEFAULT 0');
  }
}
```

Each version bump adds columns or tables — never removes them.

---

### 11. No Data Backup

Everything lives in local SQLite. Phone stolen, app deleted, or factory reset → total loss.

**Options (cheapest to most complex):**

```
Option A: CSV Export (simplest)
  Export sales/products/baki to a .csv file
  User saves to Google Drive manually
  ✅ No backend needed   ❌ Manual, no auto-restore

Option B: JSON file backup
  Serialize entire DB to JSON
  Save to device Downloads folder
  User can import on new phone
  ✅ Full restore possible   ❌ Still manual

Option C: Firebase / Supabase sync (future)
  Real-time cloud sync
  Multi-device support
  ✅ Automatic   ❌ Needs backend, auth, cost
```

Start with **Option B** — low effort, high value for small shops.

---

### 12. `_SaleTile` Uses `dynamic` Type

In `customer_detail_screen.dart`, the `_SaleTile` receives `sale` as `dynamic` and casts inline. This will silently break if the type changes.

```dart
// Current — fragile
class _SaleTile extends StatelessWidget {
  final dynamic sale;   // ← should be Sale
  ...
  sale.createdAt as DateTime   // ← runtime cast
  sale.totalAmount as double   // ← runtime cast
}

// Fix — safe
class _SaleTile extends StatelessWidget {
  final Sale sale;   // ← typed
  ...
  sale.createdAt    // ← no cast needed
}
```

---

## 🗺️ Suggested Roadmap

```
Phase 1 — Stability (now)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✦ Fix currency symbol (30 min)
  ✦ Apply tax to cart total (1 hr)
  ✦ Baki chip in history screen (30 min)
  ✦ Fix _SaleTile dynamic type (15 min)
  ✦ Fix DB migration (1 hr)

Phase 2 — Core Retail Features
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✦ Stock-in / purchase recording
  ✦ Discount system (item + order level)
  ✦ Baki aging colours
  ✦ Profit tracking on dashboard

Phase 3 — Operations
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✦ Multiple payment methods (bKash, Nagad)
  ✦ Daily close / cash register
  ✦ JSON backup & restore

Phase 4 — Scale (future)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✦ Cloud sync (Firebase / Supabase)
  ✦ Multi-staff / PIN login
  ✦ Supplier management
  ✦ Barcode label printing
```

---

## Quick Reference — File Map

| Issue | File to change |
|-------|---------------|
| Currency bug | `cart_screen.dart`, `receipt_screen.dart` |
| Tax application | `cart_provider.dart`, `cart_screen.dart` |
| History baki label | `history/history_screen.dart` |
| Dynamic type fix | `baki/customer_detail_screen.dart` |
| DB migration | `db/database_helper.dart` → `_onUpgrade` |
| Stock-in | `warehouse/warehouse_screen.dart` + new `stock_movements` table |
| Discount | `cart_provider.dart`, `models/cart_item.dart`, `models/sale.dart` |
| Baki aging | `baki/baki_screen.dart` → `_CustomerCard._relativeDate` |
| Profit tracking | `dashboard/dashboard_screen.dart`, `db/database_helper.dart` |

---

*Last updated: July 2026*
