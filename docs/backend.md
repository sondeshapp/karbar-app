# mPOS — Backend Documentation

> **Status:** Planning phase. Frontend is being finalized. This document will evolve.
> **Stack:** Go · Gin · PostgreSQL
> **Last updated:** July 2026

---

## Table of Contents

1. [Overview](#overview)
2. [Tech Stack & Rationale](#tech-stack--rationale)
3. [System Architecture](#system-architecture)
4. [Multi-Tenancy Strategy](#multi-tenancy-strategy)
5. [Database Schema](#database-schema)
6. [API Design](#api-design)
7. [Authentication & Authorization](#authentication--authorization)
8. [Key Business Logic Rules](#key-business-logic-rules)
9. [Real-time & Sync Strategy](#real-time--sync-strategy)
10. [Open Questions](#open-questions)

---

## Overview

The mPOS backend serves as the cloud layer for the Flutter mobile app. Right now the app runs fully on-device with SQLite. The backend's job is to:

- Be the source of truth for all shop data
- Enable sync across multiple devices (owner's phone + staff phone + tablet)
- Store data safely so a broken/lost phone doesn't mean lost business records
- Eventually support multiple shops (SaaS path)

The Flutter app should remain **fully functional offline**. The backend is additive — sync happens when connection is available, not as a hard dependency.

---

## Tech Stack & Rationale

| Layer | Choice | Why |
|-------|--------|-----|
| Language | Go | Developer expertise, fast, lightweight binaries |
| HTTP Framework | Gin | Minimal, well-documented, good middleware ecosystem |
| Database | PostgreSQL | Relational integrity, complex aggregation queries for dashboard, mature |
| Auth | JWT (access + refresh tokens) | Stateless, works well with mobile clients |
| Migrations | `golang-migrate` | SQL-first, version-controlled schema changes |
| Config | Environment variables | 12-factor app, easy Docker/VPS deployment |
| Deployment | Single VPS (initially) | Low ops overhead, cheap for early stage |

### What we are NOT using (and why)

| Skipped | Reason |
|---------|--------|
| GraphQL | Overkill for a known, stable API surface |
| gRPC | Mobile clients are simpler with REST |
| Redis | Add only when dashboard query latency is a proven problem |
| Microservices | One team, one app — monolith first |

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter App                          │
│                                                             │
│   ┌────────────┐    ┌────────────┐    ┌────────────────┐   │
│   │  SQLite    │    │  Sync      │    │  UI Screens    │   │
│   │  (local)   │◄──►│  Service   │◄──►│  Riverpod      │   │
│   └────────────┘    └─────┬──────┘    └────────────────┘   │
│                           │                                 │
└───────────────────────────┼─────────────────────────────────┘
                            │ HTTPS / REST
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      Go + Gin API                           │
│                                                             │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│   │  Auth    │  │  Sales   │  │  Baki    │  │  Stock   │  │
│   │  Handler │  │  Handler │  │  Handler │  │  Handler │  │
│   └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │              Middleware Chain                        │  │
│   │   Rate Limit → JWT Auth → Shop Scope → Logger       │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      PostgreSQL                             │
│                                                             │
│   shops · users · products · variants · customers          │
│   sales · sale_items · baki_payments · stock_movements     │
└─────────────────────────────────────────────────────────────┘
```

---

## Multi-Tenancy Strategy

Every shop is a **tenant**. All tables share a single PostgreSQL database with a `shop_id` column. This is the simplest path that still allows the system to scale to hundreds of shops.

```
shops
  └── users          (staff belonging to a shop)
  └── products       (shop's product catalog)
  └── customers      (shop's credit customers)
  └── sales          (shop's transaction history)
  └── baki_payments  (shop's credit collections)
```

### Isolation guarantee

Every API endpoint resolves `shop_id` from the authenticated JWT token. No endpoint accepts `shop_id` as a user-supplied parameter — it is always injected by the auth middleware.

```
Request comes in
      │
      ▼
JWT middleware extracts shop_id from token claims
      │
      ▼
shop_id is set in Gin context: c.Set("shop_id", shopID)
      │
      ▼
Handler reads: shopID := c.GetString("shop_id")
      │
      ▼
Every DB query: WHERE shop_id = $1   ← never skipped
```

This means a bug in one shop's request can never read or write another shop's data.

---

## Database Schema

### Entity Relationship Overview

```
shops ──< users
  │
  ├──< products ──< product_variants
  │
  ├──< customers ──< baki_payments
  │
  └──< sales ──< sale_items
         │
         └── (references product_variants)
```

---

### Table: `shops`

The root tenant table. One row per shop.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| name | TEXT | Shop display name |
| phone | TEXT | Owner contact |
| address | TEXT | |
| currency_symbol | TEXT | Default `৳` |
| currency_locale | TEXT | Default `bn_BD` |
| tax_rate | NUMERIC | Default `0.00` |
| show_tax | BOOLEAN | Default `false` |
| created_at | TIMESTAMPTZ | |

---

### Table: `users`

Shop staff. One shop has one owner and optionally multiple staff members.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| shop_id | UUID FK → shops | |
| name | TEXT | |
| phone | TEXT | Used as login identifier |
| password_hash | TEXT | bcrypt |
| role | TEXT | `owner` \| `staff` |
| is_active | BOOLEAN | Soft disable without deleting |
| created_at | TIMESTAMPTZ | |

---

### Table: `products`

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| shop_id | UUID FK | |
| name | TEXT | |
| description | TEXT | |
| category | TEXT | |
| brand | TEXT | |
| sku | TEXT | |
| unit | TEXT | `pcs`, `kg`, `litre`, etc. |
| image_url | TEXT | Cloud storage path |
| cost_price | NUMERIC | For profit tracking |
| low_stock_alert | INT | Default `5` |
| is_active | BOOLEAN | Soft delete |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

---

### Table: `product_variants`

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| product_id | UUID FK | |
| shop_id | UUID FK | Denormalized for faster queries |
| name | TEXT | e.g. `500g`, `Red`, `XL` |
| barcode | TEXT | Nullable |
| price | NUMERIC | Selling price |
| stock | INT | Current stock level |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

---

### Table: `customers`

Baki customers. Only shops that use the credit feature will have rows here.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| shop_id | UUID FK | |
| name | TEXT | |
| phone | TEXT | Nullable |
| notes | TEXT | Any extra info about this customer |
| created_at | TIMESTAMPTZ | |

---

### Table: `sales`

One row per completed transaction.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| shop_id | UUID FK | |
| user_id | UUID FK | Which staff member made the sale |
| customer_id | UUID FK | Nullable — only for baki sales |
| customer_name | TEXT | Denormalized snapshot at time of sale |
| subtotal | NUMERIC | Before tax/discount |
| discount_amount | NUMERIC | Default `0` |
| tax_amount | NUMERIC | Default `0` |
| total_amount | NUMERIC | Final amount |
| payment_type | TEXT | `cash` \| `bkash` \| `nagad` \| `baki` |
| amount_paid | NUMERIC | For partial payments |
| notes | TEXT | Optional |
| created_at | TIMESTAMPTZ | |

---

### Table: `sale_items`

Line items for each sale.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| sale_id | UUID FK | |
| shop_id | UUID FK | Denormalized |
| product_id | UUID FK | Snapshot reference |
| variant_id | UUID FK | Snapshot reference |
| product_name | TEXT | Snapshot at time of sale |
| variant_name | TEXT | Snapshot at time of sale |
| unit_price | NUMERIC | Price at time of sale |
| cost_price | NUMERIC | Cost at time of sale (for profit) |
| quantity | INT | |
| discount_amount | NUMERIC | Item-level discount |
| total | NUMERIC | (unit_price - discount) × quantity |

> **Why snapshot names?** Product names change over time. Storing them on the sale item means historical receipts always show what was actually sold, not the current product name.

---

### Table: `baki_payments`

Records of customers paying back their credit.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| shop_id | UUID FK | |
| customer_id | UUID FK | |
| amount | NUMERIC | |
| payment_method | TEXT | `cash` \| `bkash` \| `nagad` |
| note | TEXT | Optional |
| recorded_by | UUID FK → users | Which staff recorded it |
| paid_at | TIMESTAMPTZ | |

---

### Table: `stock_movements`

Audit trail for every stock change — sales, stock-ins, adjustments.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| shop_id | UUID FK | |
| variant_id | UUID FK | |
| type | TEXT | `sale` \| `stock_in` \| `adjustment` \| `return` |
| quantity_delta | INT | Negative for stock-out, positive for stock-in |
| reference_id | UUID | sale_id or purchase_id depending on type |
| note | TEXT | |
| created_by | UUID FK → users | |
| created_at | TIMESTAMPTZ | |

---

## API Design

Base URL: `https://api.mpos.app/v1`

All authenticated routes require header: `Authorization: Bearer <access_token>`

---

### Auth

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/auth/register` | Register new shop + owner account |
| `POST` | `/auth/login` | Login, returns access + refresh tokens |
| `POST` | `/auth/refresh` | Exchange refresh token for new access token |
| `POST` | `/auth/logout` | Invalidate refresh token |

---

### Shop

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/shop` | Get current shop settings |
| `PUT` | `/shop` | Update shop settings (name, currency, tax) |

---

### Products

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/products` | List all products (with variants) |
| `POST` | `/products` | Create product + variants |
| `GET` | `/products/:id` | Get single product |
| `PUT` | `/products/:id` | Update product |
| `DELETE` | `/products/:id` | Soft delete product |
| `POST` | `/products/:id/stock-in` | Add stock to a variant |
| `GET` | `/products/:id/movements` | Stock movement history for a product |

---

### Sales

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/sales` | List sales (paginated, filterable by date/type) |
| `POST` | `/sales` | Record a completed sale |
| `GET` | `/sales/:id` | Get single sale with all items |
| `GET` | `/sales/summary` | Dashboard aggregates (today/week/month) |

---

### Customers & Baki

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/customers` | List all customers |
| `POST` | `/customers` | Create customer |
| `GET` | `/customers/:id` | Customer detail |
| `PUT` | `/customers/:id` | Update customer |
| `GET` | `/customers/:id/baki` | Baki sales + payments + outstanding total |
| `POST` | `/customers/:id/payments` | Record a baki payment |
| `GET` | `/baki/summary` | All customers with outstanding > 0, sorted by amount |

---

### Staff / Users

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/users` | List staff (owner only) |
| `POST` | `/users` | Add staff member |
| `PUT` | `/users/:id` | Update staff (role, active status) |
| `DELETE` | `/users/:id` | Deactivate staff |

---

## Authentication & Authorization

### Token Flow

```
Mobile App                          API Server
    │                                   │
    │── POST /auth/login ──────────────►│
    │   { phone, password, shop_id }    │
    │                                   │  verify credentials
    │                                   │  generate tokens
    │◄── 200 OK ─────────────────────── │
    │   { access_token  (15min)  }      │
    │   { refresh_token (30days) }      │
    │                                   │
    │── GET /sales (with access_token)─►│
    │                                   │  decode JWT
    │                                   │  extract shop_id, user_id, role
    │◄── 200 OK ─────────────────────── │
    │                                   │
    │  (15 min later, token expires)    │
    │                                   │
    │── POST /auth/refresh ────────────►│
    │   { refresh_token }               │
    │◄── 200 OK (new access_token) ─────│
```

### JWT Claims

```json
{
  "sub":      "user-uuid",
  "shop_id":  "shop-uuid",
  "role":     "owner",
  "exp":      1722038400
}
```

### Role Permissions

| Action | Owner | Staff |
|--------|-------|-------|
| View sales | ✅ | ✅ |
| Create sale | ✅ | ✅ |
| View products | ✅ | ✅ |
| Add / edit products | ✅ | ✅ |
| Delete products | ✅ | ❌ |
| View baki | ✅ | ✅ |
| Record baki payment | ✅ | ✅ |
| View dashboard | ✅ | ❌ |
| Add / remove staff | ✅ | ❌ |
| Edit shop settings | ✅ | ❌ |
| Clear all sales | ✅ | ❌ |

---

## Key Business Logic Rules

These rules must be enforced at the API layer, not just the app.

### Outstanding Baki Calculation

```
outstanding(customer_id) =
    SUM(sales.total_amount WHERE customer_id AND payment_type = 'baki')
  - SUM(baki_payments.amount WHERE customer_id)
```

This is always computed, never stored. Storing it would risk drift from the ledger.

---

### Stock Update on Sale

When a sale is recorded, for each line item:

```
UPDATE product_variants
   SET stock = GREATEST(0, stock - quantity)
 WHERE id = variant_id AND shop_id = shop_id

INSERT INTO stock_movements (type='sale', quantity_delta = -quantity, ...)
```

Both happen inside a single DB transaction. If anything fails, neither commits.

---

### Profit Calculation

```
profit_per_item = (unit_price - cost_price) × quantity
profit_per_sale = SUM(profit_per_item) - sale.discount_amount
```

`cost_price` is snapshotted on `sale_items` at the time of sale. This means if the cost price changes later, old sale profit figures remain accurate.

---

### Soft Deletes

Products are never hard-deleted. Setting `is_active = false` hides them from the POS screen but preserves them in historical sale records.

```
DELETE /products/:id
  → UPDATE products SET is_active = false   (not a real DELETE)

GET /products
  → WHERE is_active = true AND shop_id = $1
```

---

## Real-time & Sync Strategy

The Flutter app works offline-first using SQLite. Sync to the backend is additive.

### Approach: Last-Write-Wins with `updated_at`

```
App goes offline
    │
    ├── Creates sale locally (SQLite)
    ├── Marks it: sync_status = 'pending'
    │
App comes back online
    │
    ├── Reads all rows WHERE sync_status = 'pending'
    ├── POSTs each to the API
    ├── On 201 Created → sync_status = 'synced', server_id = uuid
    └── On conflict → server wins (server timestamp is newer)
```

### What needs a `sync_status` column locally

| Local Table | Sync direction |
|-------------|---------------|
| products | bidirectional |
| sales | app → server only |
| customers | bidirectional |
| baki_payments | app → server only |

### Real-time (future)

For multi-device live updates (e.g. one staff makes a sale and it appears on owner's dashboard immediately), the options are:

- **Server-Sent Events (SSE)** — Go supports this natively, lightweight, one-directional push from server to client. Good fit.
- **WebSockets** — bidirectional but more complex. Only needed if devices need to send real-time data to each other, which isn't the case here.

**Decision deferred** until multi-device sync is confirmed as a needed feature.

---

## Open Questions

Things to decide before backend development starts.

| # | Question | Options | Notes |
|---|----------|---------|-------|
| 1 | UUIDs or integer IDs? | UUID v4 vs BIGSERIAL | UUIDs safer for distributed sync, integers simpler |
| 2 | Image storage? | Local disk vs S3-compatible (Cloudflare R2) | R2 has free tier, no egress cost |
| 3 | Phone number as login or email? | Phone (OTP) vs email/password | Target users are more comfortable with phone |
| 4 | OTP verification on register? | Yes / No / Later | Prevents fake accounts if SaaS |
| 5 | Rate limiting strategy? | Per-IP vs per-shop vs per-user | Per-shop is safest |
| 6 | Pagination style? | Offset vs cursor-based | Cursor better for large sales history |
| 7 | API versioning? | URL prefix `/v1` vs header | URL prefix simpler for mobile clients |
| 8 | Soft-delete customers? | Yes / No | If shop deletes a customer who has baki history, what happens? |
| 9 | Multi-branch support? | One shop = one branch vs shops have branches | Affects schema significantly |

---

*This document is a living draft. Update it as frontend features are finalized.*
