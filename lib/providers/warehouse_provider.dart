import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../db/database_helper.dart';

class WarehouseNotifier extends StateNotifier<List<Product>> {
  final DatabaseHelper _db;

  WarehouseNotifier(this._db) : super([]);

  Future<void> loadProducts() async {
    state = await _db.getAllProducts();
  }

  Future<void> addProduct(Product product) async {
    final id = await _db.insertProduct(product);
    state = [...state, product.copyWith(id: id)];
  }

  Future<void> updateProduct(Product product) async {
    await _db.updateProduct(product);
    state = state.map((p) => p.id == product.id ? product : p).toList();
  }

  Future<void> deleteProduct(int id) async {
    await _db.deleteProduct(id);
    state = state.where((p) => p.id != id).toList();
  }
}

final warehouseProvider =
    StateNotifierProvider<WarehouseNotifier, List<Product>>((ref) {
  return WarehouseNotifier(DatabaseHelper());
});
