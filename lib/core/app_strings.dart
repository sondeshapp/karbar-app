class AppStrings {
  final bool isBn;
  const AppStrings({required this.isBn});

  // ── Bottom nav ─────────────────────────────────────────────────────────
  String get navDashboard => isBn ? 'ড্যাশবোর্ড' : 'Dashboard';
  String get navWarehouse => isBn ? 'গুদামঘর' : 'Warehouse';
  String get navPos => isBn ? 'বিক্রয়' : 'POS';
  String get navSettings => isBn ? 'সেটিংস' : 'Settings';

  // ── Dashboard ──────────────────────────────────────────────────────────
  String get today => isBn ? 'আজ' : 'Today';
  String get thisWeek => isBn ? 'এই সপ্তাহ' : 'This Week';
  String get thisMonth => isBn ? 'এই মাস' : 'This Month';
  String get avgSale => isBn ? 'গড় বিক্রয়' : 'Avg Sale';
  String get productsLabel => isBn ? 'পণ্য' : 'Products';
  String get variantsLabel => isBn ? 'ভেরিয়েন্ট' : 'Variants';
  String get lowStockLabel => isBn ? 'কম স্টক' : 'Low Stock';
  String get bestSellers => isBn ? 'সেরা বিক্রেতা' : 'Best Sellers';
  String get revenueChart => isBn ? 'গত ৭ দিনের রাজস্ব' : 'Revenue — Last 7 Days';
  String get outOfStock => isBn ? 'স্টক শেষ' : 'Out of stock';
  String get noData => isBn ? 'এখনো কোনো ডেটা নেই' : 'No data yet';
  String lowStockTitle(int count) =>
      isBn ? '⚠  কম স্টক ($count)' : '⚠  Low Stock ($count)';
  String salesCountText(int count) =>
      isBn ? '$count বিক্রয়' : '$count sale${count == 1 ? '' : 's'}';
  String totalSalesText(int count) =>
      isBn ? 'মোট $count বিক্রয়' : '$count total sales';
  String soldText(int qty) => isBn ? '×$qty বিক্রিত' : '×$qty sold';
  String unitLeftText(int count, String unit) =>
      isBn ? '$count $unit বাকি' : '$count $unit left';

  // ── Warehouse ──────────────────────────────────────────────────────────
  String get warehouse => isBn ? 'গুদামঘর' : 'Warehouse';
  String get noProductsYet =>
      isBn ? 'এখনো কোনো পণ্য নেই। + চাপুন।' : 'No products yet. Tap + to add one.';

  // ── POS ────────────────────────────────────────────────────────────────
  String get searchProducts => isBn ? 'পণ্য খুঁজুন...' : 'Search products...';
  String get allCategories => isBn ? 'সব' : 'All';
  String get otherCategory => isBn ? 'অন্যান্য' : 'Other';
  String get viewCart => isBn ? 'কার্ট দেখুন' : 'View Cart';
  String get noProductsFound =>
      isBn
          ? 'কোনো পণ্য পাওয়া যায়নি।\nওয়্যারহাউসে পণ্য যোগ করুন।'
          : 'No products found.\nTry a different search or add products in Warehouse.';
  String inStockText(int count) =>
      isBn ? '$count স্টকে আছে' : '$count in stock';

  // ── History ────────────────────────────────────────────────────────────
  String get salesHistory => isBn ? 'বিক্রয় ইতিহাস' : 'Sales History';
  String get noSalesYet => isBn ? 'এখনো কোনো বিক্রয় নেই।' : 'No sales yet.';
  String itemsText(int count) =>
      isBn ? '$count টি পণ্য' : '$count item${count == 1 ? '' : 's'}';

  // ── Settings ───────────────────────────────────────────────────────────
  String get storeManagement => isBn ? 'স্টোর ম্যানেজমেন্ট' : 'Store Management';
  String get historyLabel => isBn ? 'ইতিহাস' : 'History';
  String get inventoryLabel => isBn ? 'ইনভেন্টরি' : 'Inventory';
  String get reportsLabel => isBn ? 'রিপোর্ট' : 'Reports';
  String get preferences => isBn ? 'পছন্দ' : 'Preferences';
  String get languageLabel => isBn ? 'ভাষা' : 'Language';
  String get darkMode => isBn ? 'ডার্ক মোড' : 'Dark Mode';
  String get currencyLabel => isBn ? 'মুদ্রা' : 'Currency';
  String get posSettingsLabel => isBn ? 'পিওএস সেটিংস' : 'POS Settings';
  String get taxRate => isBn ? 'করের হার' : 'Tax Rate';
  String get showTaxOnReceipt => isBn ? 'রসিদে কর দেখান' : 'Show Tax on Receipt';
  String get dataManagement => isBn ? 'ডেটা ব্যবস্থাপনা' : 'Data Management';
  String get viewTransactions =>
      isBn ? 'সকল লেনদেন দেখুন' : 'View all past transactions';
  String get clearSalesData => isBn ? 'বিক্রয় ডেটা মুছুন' : 'Clear Sales Data';
  String get clearSalesSubtitle =>
      isBn ? 'সকল বিক্রয় রেকর্ড মুছে ফেলুন' : 'Remove all sales records permanently';
  String get about => isBn ? 'সম্পর্কে' : 'About';
  String get appVersion => isBn ? 'অ্যাপ সংস্করণ' : 'App Version';
  String get helpSupport => isBn ? 'সাহায্য ও সহায়তা' : 'Help & Support';

  // ── Dialogs ────────────────────────────────────────────────────────────
  String get selectLanguage => isBn ? 'ভাষা বেছে নিন' : 'Select Language';
  String get selectCurrency => isBn ? 'মুদ্রা বেছে নিন' : 'Select Currency';
  String get setTaxRateTitle =>
      isBn ? 'করের হার নির্ধারণ করুন' : 'Set Tax Rate';
  String get clearDataTitle => isBn ? 'বিক্রয় ডেটা মুছবেন?' : 'Clear Sales Data?';
  String get clearDataBody =>
      isBn
          ? 'এটি সকল বিক্রয় রেকর্ড স্থায়ীভাবে মুছে ফেলবে। এই কাজটি পূর্বাবস্থায় ফেরানো যাবে না।'
          : 'This will permanently delete all sales records. This action cannot be undone.';
  String get cancel => isBn ? 'বাতিল' : 'Cancel';
  String get save => isBn ? 'সংরক্ষণ' : 'Save';
  String get clear => isBn ? 'মুছুন' : 'Clear';
  String get gotIt => isBn ? 'বুঝেছি' : 'Got it';
  String get helpTitle => isBn ? 'সাহায্য ও সহায়তা' : 'Help & Support';
  String get helpBody =>
      isBn
          ? 'সহায়তার জন্য যোগাযোগ করুন:\n\nmpos@betopialimited.com\n\nআমরা সাধারণত ২৪ ঘণ্টার মধ্যে উত্তর দিই।'
          : 'For support, please contact:\n\nmpos@betopialimited.com\n\nWe typically respond within 24 hours.';
  String get salesDataCleared =>
      isBn ? 'বিক্রয় ডেটা মুছে ফেলা হয়েছে।' : 'Sales data cleared.';
}
