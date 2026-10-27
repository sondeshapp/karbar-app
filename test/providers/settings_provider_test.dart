import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/providers/settings_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.setTestPath(inMemoryDatabasePath);
    await DatabaseHelper.resetForTesting();
  });

  tearDown(() async => DatabaseHelper.resetForTesting());

  test('settings and shop profile survive notifier recreation', () async {
    final first = SettingsNotifier();
    await first.load();
    await first.setLanguage('বাংলা');
    await first.toggleTheme();
    await first.setCurrency('৳', 'bn_BD');
    await first.setTaxRate(7.5);
    await first.setShowTax(true);
    await first.setShopProfile(
      name: 'Karbar Store',
      phone: '01700000000',
      address: 'Dhaka',
      completeSetup: true,
    );

    final restored = SettingsNotifier();
    await restored.load();

    expect(restored.state.language, 'বাংলা');
    expect(restored.state.themeMode, ThemeMode.dark);
    expect(restored.state.currencySymbol, '৳');
    expect(restored.state.currencyLocale, 'bn_BD');
    expect(restored.state.taxRate, 7.5);
    expect(restored.state.showTax, isTrue);
    expect(restored.state.shopName, 'Karbar Store');
    expect(restored.state.shopPhone, '01700000000');
    expect(restored.state.shopAddress, 'Dhaka');
    expect(restored.state.setupComplete, isTrue);
  });

  test(
    'missing or invalid saved values fall back to usable defaults',
    () async {
      final notifier = SettingsNotifier();
      await notifier.load();

      expect(notifier.state.themeMode, ThemeMode.light);
      expect(notifier.state.currencySymbol, r'$');
      expect(notifier.state.taxRate, 0);
      expect(notifier.state.setupComplete, isFalse);
    },
  );
}
