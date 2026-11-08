import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../db/database_helper.dart';

class WarehouseNotifier extends StateNotifier<List<Product>> {
  final DatabaseHelper _db;

  WarehouseNotifier(this._db) : super([]);

  Future<void> loadProducts() async {
    state = await _db.getAllProducts();
  }

  Future<void> addProduct(Product product, {int? staffId}) async {
    final id = await _db.insertProduct(product, staffId: staffId);
    state = [...state, product.copyWith(id: id)];
  }

  Future<void> updateProduct(Product product, {int? staffId}) async {
    await _db.updateProduct(product, staffId: staffId);
    state = state.map((p) => p.id == product.id ? product : p).toList();
  }

  Future<void> deleteProduct(int id, {int? staffId}) async {
    await _db.deleteProduct(id, staffId: staffId);
    state = state.where((p) => p.id != id).toList();
  }

  Future<void> stockIn(
    int variantId,
    double quantity, {
    double costPrice = 0,
    int? staffId,
  }) async {
    await _db.stockIn(
      variantId,
      quantity,
      costPrice: costPrice,
      staffId: staffId,
    );
    await loadProducts();
  }
}

final warehouseProvider =
    StateNotifierProvider<WarehouseNotifier, List<Product>>((ref) {
      return WarehouseNotifier(DatabaseHelper());
    });
