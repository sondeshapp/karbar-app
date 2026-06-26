import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_strings.dart';

class SettingsState {
  final ThemeMode themeMode;
  final String language;
  final String currencySymbol;
  final String currencyLocale;
  final double taxRate;
  final bool showTax;

  const SettingsState({
    this.themeMode = ThemeMode.light,
    this.language = 'English',
    this.currencySymbol = r'$',
    this.currencyLocale = 'en_US',
    this.taxRate = 0.0,
    this.showTax = false,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? language,
    String? currencySymbol,
    String? currencyLocale,
    double? taxRate,
    bool? showTax,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyLocale: currencyLocale ?? this.currencyLocale,
      taxRate: taxRate ?? this.taxRate,
      showTax: showTax ?? this.showTax,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  void toggleTheme() {
    state = state.copyWith(
      themeMode:
          state.themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
    );
  }

  void setLanguage(String language) =>
      state = state.copyWith(language: language);

  void setCurrency(String symbol, String locale) =>
      state = state.copyWith(currencySymbol: symbol, currencyLocale: locale);

  void setTaxRate(double rate) => state = state.copyWith(taxRate: rate);

  void setShowTax(bool show) => state = state.copyWith(showTax: show);
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);

final stringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(settingsProvider).language;
  return AppStrings(isBn: lang == 'বাংলা');
});
