<div align="center">

# 🛒 mPOS — Mobile Point of Sale

### A modern, offline-first POS system built with Flutter

<br/>

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Riverpod](https://img.shields.io/badge/Riverpod-2.x-00BCD4?style=for-the-badge&logo=data:image/png;base64,)](https://riverpod.dev)
[![SQLite](https://img.shields.io/badge/SQLite-Offline-003B57?style=for-the-badge&logo=sqlite&logoColor=white)](https://www.sqlite.org)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green?style=for-the-badge&logo=android&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-purple?style=for-the-badge)](LICENSE)

<br/>

> **A fully offline, feature-rich Point of Sale application** for small and medium businesses.  
> Manage inventory, ring up sales, scan barcodes, generate PDF receipts — all without internet.

<br/>

---

</div>

## ✨ Features

<table>
<tr>
<td width="50%">

### 📊 Dashboard
- Real-time revenue overview (Today / Week / Month)
- Animated 7-day revenue bar chart
- Best-selling products with progress bars
- Low-stock alerts with colour-coded badges
- Inventory summary (products, variants, low stock count)

</td>
<td width="50%">

### 🏪 Point of Sale
- Chaldal-style product grid for fast browsing
- Category filter chips for quick navigation
- Live search across name, brand & category
- Multi-variant product picker (size, colour, etc.)
- Floating glassmorphic "View Cart" bar
- Barcode scanner via device camera

</td>
</tr>
<tr>
<td width="50%">

### 📦 Warehouse / Inventory
- Add, edit & delete products
- Multiple variants per product (price + stock each)
- Product images via camera or gallery
- Brand, category & unit tracking
- Live stock count synced with sales

</td>
<td width="50%">

### 🧾 Sales & Receipts
- Complete sales history with expandable detail
- Per-item breakdown (variant, qty, subtotal)
- PDF receipt generation & printing/sharing
- Tax calculation with configurable rate
- Currency symbol customisation

</td>
</tr>
<tr>
<td width="50%">

### ⚙️ Settings
- 🌙 Dark / Light mode toggle
- 🌐 English / বাংলা language switching
- 💱 Currency configuration
- 🧮 Tax rate & show/hide toggle
- 🗑️ Clear all sales data

</td>
<td width="50%">

### 🎨 Design
- Material 3 design system
- Glassmorphic bottom navigation bar (acrylic blur)
- Glassmorphic floating cart button
- Glassmorphic AppBar on Dashboard
- Colourful gradient stat cards with glass shimmer
- Full dark mode across every screen

</td>
</tr>
</table>

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Framework** | Flutter 3.x |
| **Language** | Dart 3.x |
| **State Management** | Flutter Riverpod 2.x (`StateNotifier`, `Provider`) |
| **Navigation** | GoRouter 14.x |
| **Database** | SQLite via `sqflite` + `sqflite_common_ffi` |
| **PDF** | `pdf` + `printing` packages |
| **Barcode Scanner** | `mobile_scanner` 5.x |
| **Image Picker** | `image_picker` |
| **Localisation** | Custom `AppStrings` class (EN / বাংলা) |
| **Theming** | Material 3 `ThemeData` + custom `appDarkTheme` |

---

## 📁 Project Structure

```
lib/
├── app.dart                    # MaterialApp.router + theme wiring
├── main.dart                   # Entry point
│
├── core/
│   ├── constants.dart          # App-wide colours, padding
│   ├── theme.dart              # appTheme (light) + appDarkTheme (dark)
│   └── app_strings.dart        # EN / বাংলা string definitions
│
├── db/
│   └── database_helper.dart    # SQLite singleton, migrations
│
├── models/
│   ├── product.dart
│   ├── product_variant.dart
│   ├── cart_item.dart
│   ├── sale.dart
│   └── dashboard_data.dart
│
├── providers/
│   ├── settings_provider.dart  # Theme, language, currency, tax
│   ├── warehouse_provider.dart # Product CRUD state
│   ├── cart_provider.dart      # Active cart state
│   ├── sales_provider.dart     # Sales history state
│   └── dashboard_provider.dart # Aggregated analytics
│
├── screens/
│   ├── home_screen.dart        # IndexedStack + glass nav bar
│   ├── dashboard/
│   ├── warehouse/
│   ├── pos/
│   │   ├── pos_screen.dart
│   │   ├── cart_screen.dart
│   │   └── scanner_screen.dart
│   ├── history/
│   ├── receipt/
│   └── settings/
│
└── widgets/
    ├── product_grid_card.dart
    ├── product_tile.dart
    ├── cart_item_tile.dart
    └── empty_state.dart
```

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `^3.12.2`
- Dart SDK `^3.12.2`
- Android Studio / VS Code
- A connected Android / iOS device or emulator

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/your-username/m_pos.git
cd m_pos

# 2. Install dependencies
flutter pub get

# 3. Run on a connected device
flutter run

# 4. Build a release APK
flutter build apk --release
```

### First Launch

1. Open the app — the SQLite database is created automatically on first run.
2. Go to **Warehouse** → tap **＋** to add your first product and variants.
3. Switch to **POS** → browse or search for products → add to cart → checkout.
4. View your sales in **Settings → History**, or check analytics on the **Dashboard**.

---

## 📱 Screens at a Glance

| Screen | Description |
|---|---|
| **Dashboard** | Revenue cards, 7-day chart, best sellers, low-stock list |
| **Warehouse** | Product list with stock levels; tap to edit |
| **POS** | Grid browsing, category filter, barcode scan, cart |
| **Cart** | Review items, adjust qty, apply tax, checkout |
| **Receipt** | PDF preview with share / print |
| **History** | Expandable sales log (accessible from Settings) |
| **Settings** | Theme, language, currency, tax, data management |

---

## 🌐 Localisation

The app ships with two languages, switchable at runtime from Settings:

| Key | English | বাংলা |
|---|---|---|
| Dashboard | Dashboard | ড্যাশবোর্ড |
| Today | Today | আজ |
| Warehouse | Warehouse | গুদাম |
| Point of Sale | Point of Sale | বিক্রয় কেন্দ্র |
| Settings | Settings | সেটিংস |
| Low Stock | Low Stock | কম স্টক |

Adding a new language requires extending the `AppStrings` class in `lib/core/app_strings.dart`.

---

## 🗄️ Database Schema

```sql
-- Products
CREATE TABLE products (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  name      TEXT NOT NULL,
  brand     TEXT,
  category  TEXT,
  unit      TEXT,
  image     TEXT
);

-- Variants (price + stock per SKU)
CREATE TABLE product_variants (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL REFERENCES products(id),
  name       TEXT NOT NULL,
  price      REAL NOT NULL,
  stock      INTEGER NOT NULL DEFAULT 0
);

-- Sales header
CREATE TABLE sales (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  total_amount REAL NOT NULL,
  tax_amount   REAL,
  created_at   TEXT NOT NULL
);

-- Sale line items
CREATE TABLE sale_items (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  sale_id    INTEGER NOT NULL REFERENCES sales(id),
  product_id INTEGER NOT NULL,
  variant_id INTEGER NOT NULL,
  quantity   INTEGER NOT NULL,
  unit_price REAL NOT NULL
);
```

---

## 🤝 Contributing

Contributions, issues and feature requests are welcome!

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

Built with ❤️ using **Flutter** & **Dart**

[![Flutter](https://img.shields.io/badge/Made%20with-Flutter-02569B?style=flat-square&logo=flutter)](https://flutter.dev)

</div>
