import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sale.dart';
import '../db/database_helper.dart';

class SalesNotifier extends StateNotifier<List<Sale>> {
  final DatabaseHelper _db;

  SalesNotifier(this._db) : super([]);

  Future<void> loadSales() async {
    state = await _db.getAllSales();
  }

  Future<void> completeSale(Sale sale) async {
    await _db.insertSale(sale);
    await loadSales();
  }

  Future<void> clearSales() async {
    await _db.clearAllSales();
    state = [];
  }
}

final salesProvider =
    StateNotifierProvider<SalesNotifier, List<Sale>>((ref) {
  return SalesNotifier(DatabaseHelper());
});
