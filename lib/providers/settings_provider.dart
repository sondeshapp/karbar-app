import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_strings.dart';
import '../db/database_helper.dart';

class SettingsState {
  final ThemeMode themeMode;
  final String language;
  final String currencySymbol;
  final String currencyLocale;
  final double taxRate;
  final bool showTax;
  final String shopName;
  final String shopPhone;
  final String shopAddress;
  final bool setupComplete;

  const SettingsState({
    this.themeMode = ThemeMode.light,
    this.language = 'English',
    this.currencySymbol = '৳',
    this.currencyLocale = 'bn_BD',
    this.taxRate = 0.0,
    this.showTax = false,
    this.shopName = '',
    this.shopPhone = '',
    this.shopAddress = '',
    this.setupComplete = false,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? language,
    String? currencySymbol,
    String? currencyLocale,
    double? taxRate,
    bool? showTax,
    String? shopName,
    String? shopPhone,
    String? shopAddress,
    bool? setupComplete,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyLocale: currencyLocale ?? this.currencyLocale,
      taxRate: taxRate ?? this.taxRate,
      showTax: showTax ?? this.showTax,
      shopName: shopName ?? this.shopName,
      shopPhone: shopPhone ?? this.shopPhone,
      shopAddress: shopAddress ?? this.shopAddress,
      setupComplete: setupComplete ?? this.setupComplete,
    );
  }

  Map<String, String> toStorageMap() => {
    'theme_mode': themeMode.name,
    'language': language,
    'currency_symbol': currencySymbol,
    'currency_locale': currencyLocale,
    'tax_rate': taxRate.toString(),
    'show_tax': showTax.toString(),
    'shop_name': shopName,
    'shop_phone': shopPhone,
    'shop_address': shopAddress,
    'setup_complete': setupComplete.toString(),
  };

  factory SettingsState.fromStorageMap(Map<String, String> values) {
    final themeMode = ThemeMode.values.where(
      (mode) => mode.name == values['theme_mode'],
    );
    return SettingsState(
      themeMode: themeMode.isEmpty ? ThemeMode.light : themeMode.first,
      language: values['language'] ?? 'English',
      currencySymbol: values['currency_symbol'] ?? '৳',
      currencyLocale: values['currency_locale'] ?? 'bn_BD',
      taxRate: double.tryParse(values['tax_rate'] ?? '') ?? 0,
      showTax: values['show_tax'] == 'true',
      shopName: values['shop_name'] ?? '',
      shopPhone: values['shop_phone'] ?? '',
      shopAddress: values['shop_address'] ?? '',
      setupComplete: values['setup_complete'] == 'true',
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final DatabaseHelper _db;
  Future<void> _pendingSave = Future.value();

  SettingsNotifier({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper(),
      super(const SettingsState());

  Future<void> load() async {
    try {
      state = SettingsState.fromStorageMap(await _db.getAppSettings());
    } catch (_) {
      // Keep usable defaults if local settings cannot be read.
    }
  }

  Future<void> _save() {
    final values = state.toStorageMap();
    _pendingSave = _pendingSave
        .catchError((_) {})
        .then((_) => _db.saveAppSettings(values));
    return _pendingSave;
  }

  Future<void> toggleTheme() async {
    state = state.copyWith(
      themeMode: state.themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light,
    );
    await _save();
  }

  Future<void> setLanguage(String language) async {
    state = state.copyWith(language: language);
    await _save();
  }

  Future<void> setCurrency(String symbol, String locale) async {
    state = state.copyWith(currencySymbol: symbol, currencyLocale: locale);
    await _save();
  }

  Future<void> setTaxRate(double rate) async {
    state = state.copyWith(taxRate: rate);
    await _save();
  }

  Future<void> setShowTax(bool show) async {
    state = state.copyWith(showTax: show);
    await _save();
  }

  Future<void> setShopProfile({
    required String name,
    required String phone,
    required String address,
    bool completeSetup = false,
  }) async {
    state = state.copyWith(
      shopName: name.trim(),
      shopPhone: phone.trim(),
      shopAddress: address.trim(),
      setupComplete: completeSetup || state.setupComplete,
    );
    await _save();
  }

  Future<void> completeSetup() async {
    state = state.copyWith(setupComplete: true);
    await _save();
  }

  Future<void> reopenShopSetup() async {
    state = state.copyWith(setupComplete: false);
    await _save();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);

final stringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(settingsProvider).language;
  return AppStrings(isBn: lang == 'বাংলা');
});
