import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_helper.dart';
import '../models/receipt_design.dart';

final receiptDesignStoreProvider = Provider<ReceiptDesignStore>(
  (ref) => ReceiptDesignStore(),
);

final receiptDesignProvider = FutureProvider<ReceiptDesign>(
  (ref) => ref.watch(receiptDesignStoreProvider).load(),
);

class ReceiptDesignStore {
  static const _settingKey = 'receipt_design';
  final DatabaseHelper _db;

  ReceiptDesignStore({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  Future<ReceiptDesign> load() async {
    final settings = await _db.getAppSettings();
    final value = settings[_settingKey];
    if (value == null || value.isEmpty) return const ReceiptDesign();
    try {
      return ReceiptDesign.fromStorageJson(value);
    } on FormatException {
      return const ReceiptDesign();
    } on TypeError {
      return const ReceiptDesign();
    }
  }

  Future<void> save(ReceiptDesign design) async {
    final settings = await _db.getAppSettings();
    settings[_settingKey] = jsonEncode(design.toJson());
    await _db.saveAppSettings(settings);
  }
}
