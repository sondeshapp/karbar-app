import 'quantity_format.dart';

class AppStrings {
  final bool isBn;
  const AppStrings({required this.isBn});

  // ── Bottom nav ─────────────────────────────────────────────────────────
  String get navDashboard => isBn ? 'ড্যাশবোর্ড' : 'Dashboard';
  String get navWarehouse => isBn ? 'ইনভেন্টরি' : 'Inventory';
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
  String get revenueChart =>
      isBn ? 'গত ৭ দিনের রাজস্ব' : 'Revenue — Last 7 Days';
  String get outOfStock => isBn ? 'স্টক শেষ' : 'Out of stock';
  String get noData => isBn ? 'এখনো কোনো ডেটা নেই' : 'No data yet';
  String lowStockTitle(int count) =>
      isBn ? '⚠  কম স্টক ($count)' : '⚠  Low Stock ($count)';
  String salesCountText(int count) =>
      isBn ? '$count বিক্রয়' : '$count sale${count == 1 ? '' : 's'}';
  String totalSalesText(int count) =>
      isBn ? 'মোট $count বিক্রয়' : '$count total sales';
  String soldText(double qty) => isBn
      ? '×${formatQuantity(qty, 3)} বিক্রিত'
      : '×${formatQuantity(qty, 3)} sold';
  String unitLeftText(double count, String unit) => isBn
      ? '${formatQuantity(count, 3)} $unit বাকি'
      : '${formatQuantity(count, 3)} $unit left';

  // ── Inventory ──────────────────────────────────────────────────────────
  String get warehouse => isBn ? 'ইনভেন্টরি' : 'Inventory';
  String get noProductsYet => isBn
      ? 'এখনো কোনো পণ্য নেই। + চাপুন।'
      : 'No products yet. Tap + to add one.';

  // ── POS ────────────────────────────────────────────────────────────────
  String get searchProducts => isBn ? 'পণ্য খুঁজুন...' : 'Search products...';
  String get allCategories => isBn ? 'সব' : 'All';
  String get otherCategory => isBn ? 'অন্যান্য' : 'Other';
  String get viewCart => isBn ? 'কার্ট দেখুন' : 'View Cart';
  String get noProductsFound => isBn
      ? 'কোনো পণ্য পাওয়া যায়নি।\nইনভেন্টরিতে পণ্য যোগ করুন।'
      : 'No products found.\nTry a different search or add products in Inventory.';
  String inStockText(double count) => isBn
      ? '${formatQuantity(count, 3)} স্টকে আছে'
      : '${formatQuantity(count, 3)} in stock';

  // ── History ────────────────────────────────────────────────────────────
  String get salesHistory => isBn ? 'বিক্রয় ইতিহাস' : 'Sales History';
  String get noSalesYet => isBn ? 'এখনো কোনো বিক্রয় নেই।' : 'No sales yet.';
  String get noSalesYetDescription => isBn
      ? 'আপনার বিক্রয়গুলো এখানে দেখা যাবে। প্রথম বিক্রয় শুরু করুন।'
      : 'Your completed sales will appear here. Start a sale to see it listed.';
  String get searchHistoryHint => isBn
      ? 'রসিদ নম্বর, গ্রাহক বা ফোন খুঁজুন'
      : 'Search receipt, customer, or phone';
  String get historyPaymentMethod =>
      isBn ? 'পেমেন্টের মাধ্যম' : 'Payment method';
  String get allPaymentMethods => isBn ? 'সব মাধ্যম' : 'All methods';
  String get historyDates => isBn ? 'তারিখ' : 'Dates';
  String get clearDateFilter =>
      isBn ? 'তারিখের ফিল্টার মুছুন' : 'Clear date filter';
  String get noSalesMatchFilters => isBn
      ? 'এই ফিল্টারে কোনো বিক্রয় পাওয়া যায়নি।'
      : 'No sales match these filters.';
  String get adjustHistoryFilters => isBn
      ? 'খোঁজার শব্দ বা ফিল্টার বদলে আবার চেষ্টা করুন।'
      : 'Try changing your search or filters.';
  String get clearFilters => isBn ? 'ফিল্টার মুছুন' : 'Clear filters';
  String get startSale => isBn ? 'বিক্রয় শুরু করুন' : 'Start a sale';
  String get recordReturn => isBn ? 'পণ্য ফেরত নথিভুক্ত করুন' : 'Record return';
  String get returnQuantity => isBn ? 'ফেরতের পরিমাণ' : 'Return qty';
  String quantityRemaining(String quantity) =>
      isBn ? '$quantity টি বাকি' : '$quantity left';
  String get returnReason => isBn ? 'ফেরতের কারণ' : 'Reason for return';
  String get refundMethod => isBn ? 'ফেরতের পেমেন্ট মাধ্যম' : 'Refund method';
  String get reduceBaki => isBn ? 'বাকি কমান' : 'Reduce baki';
  String get historyCancel => isBn ? 'বাতিল' : 'Cancel';
  String get saveReturn => isBn ? 'ফেরত সংরক্ষণ করুন' : 'Save return';
  String returnRecorded(String amount) =>
      isBn ? 'ফেরত নথিভুক্ত হয়েছে: $amount' : 'Return recorded: $amount';
  String returnFailed(String error) =>
      isBn ? 'ফেরত ব্যর্থ হয়েছে: $error' : 'Return failed: $error';
  String get reprintShareReceipt =>
      isBn ? 'রসিদ আবার প্রিন্ট / শেয়ার করুন' : 'Reprint / share receipt';
  String get returnItems => isBn ? 'পণ্য ফেরত দিন' : 'Return items';
  String get returned => isBn ? 'ফেরত দেওয়া হয়েছে' : 'Returned';
  String saleNumber(String number) =>
      isBn ? 'বিক্রয় #$number' : 'Sale #$number';
  String itemsText(double count) => isBn
      ? '${formatQuantity(count, 3)} টি পণ্য'
      : '${formatQuantity(count, 3)} items';

  // ── Settings ───────────────────────────────────────────────────────────
  String get storeManagement =>
      isBn ? 'স্টোর ম্যানেজমেন্ট' : 'Store Management';
  String get storeProfile => isBn ? 'দোকানের তথ্য' : 'Shop profile';
  String get shopName => isBn ? 'দোকানের নাম' : 'Shop name';
  String get shopPhone => isBn ? 'ফোন নম্বর' : 'Phone number';
  String get shopAddress => isBn ? 'ঠিকানা' : 'Address';
  String get shopPhoneOptional =>
      isBn ? 'ফোন নম্বর (ঐচ্ছিক)' : 'Phone number (optional)';
  String get shopAddressOptional =>
      isBn ? 'ঠিকানা (ঐচ্ছিক)' : 'Address (optional)';
  String get setupShopTitle =>
      isBn ? 'আপনার দোকান সেট আপ করুন' : 'Set up your shop';
  String get shopDetailsTitle => isBn ? 'দোকানের তথ্য' : 'Shop details';
  String get setupStep => isBn ? 'ধাপ ১ / ২' : 'Step 1 of 2';
  String get ownerSetupStep => isBn ? 'ধাপ ২ / ২' : 'Step 2 of 2';
  String get currencyBdt =>
      isBn ? 'BDT — বাংলাদেশি টাকা (৳)' : 'BDT — Bangladeshi Taka (৳)';
  String get currencyUsd =>
      isBn ? 'USD — মার্কিন ডলার (\$)' : 'USD — US Dollar (\$)';
  String get currencyEur => isBn ? 'EUR — ইউরো (€)' : 'EUR — Euro (€)';
  String get currencyGbp =>
      isBn ? 'GBP — ব্রিটিশ পাউন্ড (£)' : 'GBP — British Pound (£)';
  String get continueSetup => isBn ? 'চালিয়ে যান' : 'Continue';
  String get setupShopDescription => isBn
      ? 'রসিদে দেখানোর জন্য দোকানের তথ্য ও মুদ্রা দিন।'
      : 'Add the details and currency to show on your receipts.';
  String get shopNameRequired =>
      isBn ? 'দোকানের নাম লিখুন' : 'Enter a shop name';
  String get setupSaveFailed => isBn
      ? 'দোকানের তথ্য সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'
      : 'Could not save shop details. Please try again.';
  String get skipForNow => isBn ? 'এখন এড়িয়ে যান' : 'Skip for now';
  String get previousStep => isBn ? 'আগের ধাপে যান' : 'Previous';
  String get welcomeTitle => isBn ? 'কারবারে স্বাগতম' : 'Welcome to Karbar';
  String get welcomeDescription => isBn
      ? 'বিক্রি, পণ্য আর দোকানের হিসাব—সবকিছু গুছিয়ে রাখুন।'
      : 'Keep sales, stock, and shop records together in one place.';
  String get onboardingFeatureSales => isBn ? 'বিক্রয়' : 'Sales';
  String get onboardingFeatureInventory => isBn ? 'ইনভেন্টরি' : 'Inventory';
  String get onboardingFeatureReports => isBn ? 'রিপোর্ট' : 'Reports';
  String get setupShopButton => isBn ? 'দোকান সেট আপ করুন' : 'Set up shop';
  String get skipOnboarding => isBn ? 'এড়িয়ে যান' : 'Skip';
  String get onboardingContinueFailed => isBn
      ? 'এগিয়ে যাওয়া যায়নি। আবার চেষ্টা করুন।'
      : 'Could not continue. Please try again.';
  String get ownerPinTitle =>
      isBn ? 'মালিকের পিন তৈরি করুন' : 'Create owner PIN';
  String get ownerPinSubtitle => isBn
      ? 'দোকানের নিরাপত্তার জন্য মালিকের অ্যাকাউন্ট তৈরি করুন।'
      : 'Create an owner account to protect this shop.';
  String get ownerNameLabel => isBn ? 'মালিকের নাম' : 'Owner name';
  String get noActiveStaffTitle =>
      isBn ? 'সক্রিয় কর্মী অ্যাকাউন্ট নেই' : 'No active staff account';
  String get noActiveStaffSubtitle => isBn
      ? 'অ্যাকাউন্ট চালু করতে মালিকের সঙ্গে যোগাযোগ করুন।'
      : 'Ask an owner to reactivate an account.';
  String get enterStaffPinTitle => isBn ? 'আপনার পিন লিখুন' : 'Enter your PIN';
  String get selectStaffSubtitle => isBn
      ? 'চালিয়ে যেতে আপনার কর্মী অ্যাকাউন্ট বেছে নিন।'
      : 'Choose your staff account to continue.';
  String get staffMemberLabel => isBn ? 'কর্মী' : 'Staff member';
  String get pinLabel => isBn ? 'পিন (৪ বা ৬ সংখ্যা)' : 'PIN (4 or 6 digits)';
  String get pinLengthLabel => isBn ? 'পিনের দৈর্ঘ্য' : 'PIN length';
  String get legacyPinLengthHint => isBn
      ? 'আপনার বর্তমান পিনের দৈর্ঘ্য বেছে নিন।'
      : 'Choose the length of your current PIN.';
  String pinDigitsLabel(int count) {
    final digits = isBn ? (count == 4 ? '৪' : '৬') : '$count';
    return isBn ? '$digits সংখ্যা' : '$digits digits';
  }

  String get searchStaff => isBn ? 'কর্মী খুঁজুন' : 'Search staff';
  String get noStaffSearchResults =>
      isBn ? 'কোনো কর্মী পাওয়া যায়নি' : 'No staff found';
  String get changeStaffAccount =>
      isBn ? 'কর্মী অ্যাকাউন্ট বদলান' : 'Change staff account';
  String get deleteLastPinDigit =>
      isBn ? 'শেষ সংখ্যা মুছুন' : 'Delete last PIN digit';
  String get switchToEnglish => isBn ? 'ইংরেজি ভাষা' : 'Switch to English';
  String get switchToBengali => isBn ? 'বাংলা ভাষা' : 'Switch to Bengali';
  String get showPin => isBn ? 'পিন দেখান' : 'Show PIN';
  String get hidePin => isBn ? 'পিন লুকান' : 'Hide PIN';
  String get createOwnerButton =>
      isBn ? 'মালিকের অ্যাকাউন্ট তৈরি করুন' : 'Create owner account';
  String get unlockButton => isBn ? 'প্রবেশ করুন' : 'Unlock';
  String get pleaseWait => isBn ? 'অপেক্ষা করুন…' : 'Please wait…';
  String get attemptsBlocked => isBn
      ? 'অনেকবার চেষ্টা হয়েছে। ৩০ সেকেন্ড পরে আবার চেষ্টা করুন।'
      : 'Too many attempts. Wait 30 seconds and try again.';
  String attemptsBlockedCountdown(int seconds) {
    final digits = seconds.toString().split('').map((digit) {
      const bengaliDigits = '০১২৩৪৫৬৭৮৯';
      return isBn ? bengaliDigits[int.parse(digit)] : digit;
    }).join();
    return isBn
        ? 'অনেকবার চেষ্টা হয়েছে। $digits সেকেন্ড অপেক্ষা করুন।'
        : 'Too many attempts. Try again in $digits seconds.';
  }

  String get incorrectStaffPin =>
      isBn ? 'পিনটি সঠিক নয়। আবার চেষ্টা করুন।' : 'Incorrect PIN. Try again.';
  String get staffSignInSubtitle =>
      isBn ? 'চালিয়ে যেতে কর্মী হিসেবে প্রবেশ করুন।' : 'Sign in to continue.';
  String get staffAccountsLoadFailed => isBn
      ? 'কর্মী অ্যাকাউন্ট লোড করা যায়নি।'
      : 'Could not load staff accounts.';
  String get staffLoadFailed =>
      isBn ? 'কর্মীর তথ্য লোড করা যায়নি।' : 'Could not load staff.';
  String get staffAccountSaveFailed => isBn
      ? 'কর্মী অ্যাকাউন্ট সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'
      : 'Could not save staff account. Please try again.';
  String get changeMyPin => isBn ? 'আমার পিন পরিবর্তন' : 'Change my PIN';
  String get currentPinLabel => isBn ? 'বর্তমান পিন' : 'Current PIN';
  String get newPinLabel =>
      isBn ? 'নতুন পিন (৪ বা ৬ সংখ্যা)' : 'New PIN (4 or 6 digits)';
  String get confirmNewPinLabel =>
      isBn ? 'নতুন পিন নিশ্চিত করুন' : 'Confirm new PIN';
  String get pinChanged => isBn ? 'পিন পরিবর্তন হয়েছে।' : 'PIN changed.';
  String get currentPinIncorrect =>
      isBn ? 'বর্তমান পিনটি সঠিক নয়।' : 'Current PIN is incorrect.';
  String get pinFormatInvalid => isBn
      ? 'পিনে ঠিক ৪ অথবা ৬টি সংখ্যা থাকতে হবে।'
      : 'PIN must contain exactly 4 or 6 digits.';
  String get pinsDoNotMatch =>
      isBn ? 'নতুন পিন দুটি মিলছে না।' : 'The new PINs do not match.';
  String get forgotPin => isBn ? 'পিন ভুলে গেছেন?' : 'Forgot PIN?';
  String get askOwnerToResetPin => isBn
      ? 'পিন রিসেট করতে মালিকের সঙ্গে যোগাযোগ করুন।'
      : 'Ask the owner to reset your PIN.';
  String get recoveryCodeTitle =>
      isBn ? 'আপনার রিকভারি কোড' : 'Your recovery code';
  String get recoveryCodeDescription => isBn
      ? 'এই কোডটি একবারই দেখানো হবে। এটি নিরাপদ স্থানে লিখে রাখুন। এই ডিভাইসে কোডটি দিয়ে মালিকের পিন একবার রিসেট করা যাবে।'
      : 'This code is shown once. Save it somewhere safe. It can reset the owner PIN once on this device.';
  String get copyRecoveryCode => isBn ? 'কোড কপি করুন' : 'Copy code';
  String get recoveryCodeCopied =>
      isBn ? 'রিকভারি কোড কপি হয়েছে।' : 'Recovery code copied.';
  String get recoveryCodeSaved =>
      isBn ? 'আমি কোডটি নিরাপদে সংরক্ষণ করেছি' : 'I saved the code';
  String get manageRecoveryCode =>
      isBn ? 'রিকভারি কোড তৈরি / বদলান' : 'Set up / replace recovery code';
  String get recoveryCodeSetupDescription => isBn
      ? 'নতুন কোড তৈরি করলে আগের কোডটি আর কাজ করবে না।'
      : 'Creating a new code will invalidate the previous one.';
  String get verifyPinToCreateRecovery => isBn
      ? 'রিকভারি কোড তৈরি করতে আপনার বর্তমান পিন দিন।'
      : 'Enter your current PIN to create a recovery code.';
  String get recoveryCodeNotConfigured => isBn
      ? 'রিকভারি কোড সেট করা নেই। আগে প্রবেশ করে স্টাফ অ্যাক্সেস থেকে একটি তৈরি করুন।'
      : 'No recovery code is set. Sign in and create one from Staff access first.';
  String get recoveryCodeLabel => isBn ? 'রিকভারি কোড' : 'Recovery code';
  String get resetOwnerPin =>
      isBn ? 'মালিকের পিন রিসেট করুন' : 'Reset owner PIN';
  String get recoveryCodeInvalid =>
      isBn ? 'রিকভারি কোডটি সঠিক নয়।' : 'Recovery code is incorrect.';
  String get recoveryCodeLocked => isBn
      ? 'অনেকবার ভুল কোড দেওয়া হয়েছে। ৫ মিনিট পরে আবার চেষ্টা করুন।'
      : 'Too many incorrect codes. Try again in 5 minutes.';
  String get recoveryPinSuccess => isBn
      ? 'পিন রিসেট হয়েছে। নতুন পিন দিয়ে প্রবেশ করে স্টাফ অ্যাক্সেস থেকে নতুন রিকভারি কোড তৈরি করুন।'
      : 'PIN reset. Sign in with the new PIN, then create a new recovery code in Staff access.';
  String get recoveryCodeSaveFailed => isBn
      ? 'রিকভারি কোড সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'
      : 'Could not save the recovery code. Please try again.';
  String get recoverySetupPending => isBn
      ? 'রিকভারি কোড তৈরি হয়নি। প্রবেশের পর স্টাফ অ্যাক্সেস থেকে সেট আপ করুন।'
      : 'Recovery code was not created. Set one up from Staff access after signing in.';
  String staffRoleLabel(String role) {
    if (!isBn) return role;
    return switch (role.toLowerCase()) {
      'owner' => 'মালিক',
      'cashier' => 'ক্যাশিয়ার',
      _ => role,
    };
  }

  String get dailyCashClose => isBn ? 'দৈনিক ক্যাশ ক্লোজ' : 'Daily cash close';
  String get businessDate => isBn ? 'ব্যবসার তারিখ' : 'Business date';
  String get expectedDrawerCash =>
      isBn ? 'ড্রয়ারে প্রত্যাশিত নগদ' : 'Expected drawer cash';
  String get cashSalesAfterRefunds =>
      isBn ? 'ফেরত বাদে নগদ বিক্রয়' : 'Cash sales after refunds';
  String get refunds => isBn ? 'ফেরত' : 'Refunds';
  String get countedDrawerCash =>
      isBn ? 'গণনা করা ড্রয়ারের নগদ' : 'Counted drawer cash';
  String get noteOptional => isBn ? 'নোট (ঐচ্ছিক)' : 'Note (optional)';
  String get difference => isBn ? 'পার্থক্য' : 'Difference';
  String differenceAmount(String amount) => '$difference: $amount';
  String get paymentTotals => isBn ? 'পেমেন্টের মোট' : 'Payment totals';
  String get savedCloses => isBn ? 'সংরক্ষিত ক্লোজ' : 'Saved closes';
  String get noPaymentsForDate =>
      isBn ? 'এই তারিখে কোনো পেমেন্ট নেই' : 'No payments for this date';
  String get noClosesForDate => isBn
      ? 'এই তারিখে কোনো ক্লোজ সংরক্ষিত নেই'
      : 'No close saved for this date';
  String get saveThisClose => isBn ? 'ক্লোজ সংরক্ষণ করুন' : 'Save this close';
  String get saving => isBn ? 'সংরক্ষণ হচ্ছে…' : 'Saving…';
  String get cashCloseSaved =>
      isBn ? 'ক্যাশ ক্লোজ সংরক্ষিত হয়েছে' : 'Cash close saved';
  String get enterValidCountedCash => isBn
      ? 'গণনা করা নগদের সঠিক পরিমাণ লিখুন।'
      : 'Enter a valid counted cash amount.';
  String closeSummary(String counted, String difference) => isBn
      ? 'গণনা: $counted · পার্থক্য: $difference'
      : 'Counted: $counted · Difference: $difference';
  String refundsAmount(String amount) => '$refunds: $amount';
  String get cashCloseSaveFailed => isBn
      ? 'ক্যাশ ক্লোজ সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।'
      : 'Could not save the cash close. Please try again.';
  String paymentMethodLabel(String method) {
    if (!isBn) {
      return switch (method.toLowerCase()) {
        'cash' => 'Cash',
        'bkash' => 'bKash',
        'nagad' => 'Nagad',
        'card' => 'Card',
        'baki' => 'Baki',
        'split' => 'Split',
        _ => method,
      };
    }
    return switch (method.toLowerCase()) {
      'cash' => 'নগদ',
      'bkash' => 'বিকাশ',
      'nagad' => 'নগদ',
      'card' => 'কার্ড',
      'bank' => 'ব্যাংক',
      'baki' => 'বাকি',
      'split' => 'বিভক্ত পেমেন্ট',
      _ => method,
    };
  }

  String get historyLabel => isBn ? 'ইতিহাস' : 'History';
  String get inventoryLabel => isBn ? 'ইনভেন্টরি' : 'Inventory';
  String get reportsLabel => isBn ? 'রিপোর্ট' : 'Reports';
  String get todayRange => isBn ? 'আজ' : 'Today';
  String get lastSevenDays => isBn ? 'শেষ ৭ দিন' : 'Last 7 days';
  String get thisMonthRange => isBn ? 'এই মাস' : 'This month';
  String get customRange => isBn ? 'তারিখ বেছে নিন' : 'Custom dates';
  String get grossSales => isBn ? 'মোট বিক্রয়' : 'Gross sales';
  String get discountTotal => isBn ? 'মোট ছাড়' : 'Discounts';
  String get netSales => isBn ? 'ছাড়ের পর বিক্রয়' : 'Net sales';
  String get taxCollected => isBn ? 'সংগৃহীত কর' : 'Tax recorded';
  String get totalReceivable =>
      isBn ? 'মোট পাওনা/প্রাপ্তি' : 'Total due / received';
  String get returnsMetric => isBn ? 'ফেরত' : 'Returns';
  String get purchaseCostsMetric => isBn ? 'ক্রয় খরচ' : 'Purchase costs';
  String get supplierPurchases =>
      isBn ? 'সরবরাহকারী অনুযায়ী ক্রয়' : 'Purchases by supplier';
  String get transactions => isBn ? 'লেনদেন' : 'Transactions';
  String get payment => isBn ? 'পেমেন্ট' : 'Payment';
  String get cash => isBn ? 'নগদ' : 'Cash';
  String get bkash => isBn ? 'বিকাশ' : 'bKash';
  String get nagad => isBn ? 'নগদ' : 'Nagad';
  String get card => isBn ? 'কার্ড' : 'Card';
  String get received => isBn ? 'পরিশোধ হয়েছে' : 'Received';
  String get remainingBaki => isBn ? 'বাকি থাকবে' : 'Remaining (baki)';
  String get continuePayment => isBn ? 'চালিয়ে যান' : 'Continue';
  String get enterValidPayment => isBn
      ? 'বিক্রয়ের মোট টাকার সমান সঠিক পেমেন্ট দিন।'
      : 'Enter valid amounts that add up to the sale total.';
  String get averageSale => isBn ? 'গড় বিক্রয়' : 'Average sale';
  String get estimatedProfit => isBn ? 'আনুমানিক লাভ' : 'Estimated profit';
  String get bakiIssued => isBn ? 'নতুন বাকি' : 'Baki issued';
  String get bakiCollected => isBn ? 'বাকি আদায়' : 'Baki collected';
  String get paymentBreakdown => isBn ? 'পেমেন্ট অনুযায়ী' : 'By payment type';
  String get topProductsReport => isBn ? 'শীর্ষ পণ্য' : 'Top products';
  String get lowStockProducts => isBn ? 'কম স্টকের পণ্য' : 'Low stock';
  String get exportCsv => isBn ? 'CSV রপ্তানি' : 'Export CSV';
  String get csvShareReady => isBn
      ? 'রিপোর্ট CSV শেয়ার করার জন্য প্রস্তুত।'
      : 'Report CSV is ready to share.';
  String get csvSaved =>
      isBn ? 'রিপোর্ট CSV সংরক্ষিত হয়েছে।' : 'Report CSV saved.';
  String get noReportSales =>
      isBn ? 'এই সময়ে কোনো বিক্রয় নেই।' : 'No sales in this period.';
  String get taxHistoryNote => isBn
      ? 'আগের বিক্রয়ে কর আলাদা করে সংরক্ষিত ছিল না; করের মোট নতুন রেকর্ড থেকে এসেছে।'
      : 'Older sales did not store tax separately. Tax totals include only sales recorded with a tax amount.';
  String missingCostNote(int count) => isBn
      ? '$count বিক্রয় লাইনে পণ্যের ক্রয়মূল্য নেই; লাভের হিসাব থেকে বাদ।'
      : '$count sale lines have no recorded cost and are excluded from estimated profit.';
  String reportPeriod(String start, String end) => '$start – $end';
  String get preferences => isBn ? 'পছন্দ' : 'Preferences';
  String get languageLabel => isBn ? 'ভাষা' : 'Language';
  String get darkMode => isBn ? 'ডার্ক মোড' : 'Dark Mode';
  String get currencyLabel => isBn ? 'মুদ্রা' : 'Currency';
  String get posSettingsLabel => isBn ? 'পিওএস সেটিংস' : 'POS Settings';
  String get taxRate => isBn ? 'করের হার' : 'Tax Rate';
  String get showTaxOnReceipt =>
      isBn ? 'রসিদে কর দেখান' : 'Show Tax on Receipt';
  String get dataManagement => isBn ? 'ডেটা ব্যবস্থাপনা' : 'Data Management';
  String get viewTransactions =>
      isBn ? 'সকল লেনদেন দেখুন' : 'View all past transactions';
  String get clearSalesData => isBn ? 'বিক্রয় ডেটা মুছুন' : 'Clear Sales Data';
  String get clearSalesSubtitle => isBn
      ? 'সকল বিক্রয় রেকর্ড মুছে ফেলুন'
      : 'Remove all sales records permanently';
  String get backupAndRestore =>
      isBn ? 'ব্যাকআপ ও পুনরুদ্ধার' : 'Backup & restore';
  String get createBackup => isBn ? 'ব্যাকআপ তৈরি করুন' : 'Create backup';
  String get createBackupDescription => isBn
      ? 'পণ্য, বিক্রয়, স্টক ও সেটিংস ফাইলে সংরক্ষণ করুন।'
      : 'Save products, sales, stock, and settings to a file.';
  String get restoreBackup => isBn ? 'ব্যাকআপ পুনরুদ্ধার' : 'Restore backup';
  String get restoreBackupDescription => isBn
      ? 'আগে তৈরি করা Karbar ব্যাকআপ ফাইল খুলুন।'
      : 'Choose a Karbar backup file to restore.';
  String get backupFileTitle => isBn ? 'Karbar ব্যাকআপ' : 'Karbar backup';
  String get backupShareOpened => isBn
      ? 'ব্যাকআপ শেয়ার করার জন্য প্রস্তুত। নিরাপদ স্থানে সংরক্ষণ করুন।'
      : 'Backup is ready to share. Save it somewhere safe.';
  String get backupSaved =>
      isBn ? 'ব্যাকআপ ফাইল সংরক্ষিত হয়েছে।' : 'Backup file saved.';
  String get backupFailed =>
      isBn ? 'ব্যাকআপ তৈরি করা যায়নি।' : 'Could not create the backup.';
  String get restoreBackupTitle =>
      isBn ? 'ব্যাকআপ পুনরুদ্ধার করবেন?' : 'Restore this backup?';
  String restoreBackupBody(
    String date,
    int products,
    int sales,
    int customers,
  ) => isBn
      ? '$date তারিখের ব্যাকআপে $products পণ্য, $sales বিক্রয় এবং $customers গ্রাহক আছে। বর্তমান তথ্য প্রতিস্থাপিত হবে।'
      : 'Backup from $date contains $products products, $sales sales, and $customers customers. It will replace the current data.';
  String get restoreAndReplace =>
      isBn ? 'প্রতিস্থাপন করে পুনরুদ্ধার' : 'Restore and replace';
  String get restoreReplacesDataNote => isBn
      ? 'পুনরুদ্ধার করলে এই ডিভাইসের বর্তমান পণ্য, বিক্রয়, গ্রাহক ও সেটিংস প্রতিস্থাপিত হবে।'
      : 'Restoring replaces the products, sales, customers, and settings currently on this device.';
  String get restoreBackupSuccess =>
      isBn ? 'ব্যাকআপ পুনরুদ্ধার হয়েছে।' : 'Backup restored.';
  String get restoreBackupFailed =>
      isBn ? 'ব্যাকআপ পুনরুদ্ধার করা যায়নি।' : 'Could not restore the backup.';
  String get about => isBn ? 'সম্পর্কে' : 'About';
  String get appVersion => isBn ? 'অ্যাপ সংস্করণ' : 'App Version';
  String get helpSupport => isBn ? 'সাহায্য ও সহায়তা' : 'Help & Support';

  // ── Dialogs ────────────────────────────────────────────────────────────
  String get selectLanguage => isBn ? 'ভাষা বেছে নিন' : 'Select Language';
  String get selectCurrency => isBn ? 'মুদ্রা বেছে নিন' : 'Select Currency';
  String get setTaxRateTitle =>
      isBn ? 'করের হার নির্ধারণ করুন' : 'Set Tax Rate';
  String get clearDataTitle =>
      isBn ? 'বিক্রয় ডেটা মুছবেন?' : 'Clear Sales Data?';
  String get clearDataBody => isBn
      ? 'এটি সকল বিক্রয় রেকর্ড স্থায়ীভাবে মুছে ফেলবে। এই কাজটি পূর্বাবস্থায় ফেরানো যাবে না।'
      : 'This will permanently delete all sales records. This action cannot be undone.';
  String get cancel => isBn ? 'বাতিল' : 'Cancel';
  String get save => isBn ? 'সংরক্ষণ' : 'Save';
  String get clear => isBn ? 'মুছুন' : 'Clear';
  String get gotIt => isBn ? 'বুঝেছি' : 'Got it';
  String get helpTitle => isBn ? 'সাহায্য ও সহায়তা' : 'Help & Support';
  String get helpBody => isBn
      ? 'সহায়তার জন্য যোগাযোগ করুন:\n\nmpos@betopialimited.com\n\nআমরা সাধারণত ২৪ ঘণ্টার মধ্যে উত্তর দিই।'
      : 'For support, please contact:\n\nmpos@betopialimited.com\n\nWe typically respond within 24 hours.';
  String get salesDataCleared =>
      isBn ? 'বিক্রয় ডেটা মুছে ফেলা হয়েছে।' : 'Sales data cleared.';
}
