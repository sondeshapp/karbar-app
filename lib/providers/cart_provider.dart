import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_variant.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addItem(Product product, ProductVariant variant) {
    final index =
        state.indexWhere((item) => item.variant.id == variant.id);
    if (index >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index)
            state[i].copyWith(quantity: state[i].quantity + 1)
          else
            state[i],
      ];
    } else {
      state = [
        ...state,
        CartItem(product: product, variant: variant, quantity: 1)
      ];
    }
  }

  void removeItem(int variantId) {
    state = state.where((item) => item.variant.id != variantId).toList();
  }

  void incrementQty(int variantId) {
    state = state.map((item) {
      if (item.variant.id == variantId) {
        return item.copyWith(quantity: item.quantity + 1);
      }
      return item;
    }).toList();
  }

  void decrementQty(int variantId) {
    final item =
        state.firstWhere((item) => item.variant.id == variantId);
    if (item.quantity <= 1) {
      removeItem(variantId);
    } else {
      state = state.map((item) {
        if (item.variant.id == variantId) {
          return item.copyWith(quantity: item.quantity - 1);
        }
        return item;
      }).toList();
    }
  }

  void clearCart() => state = [];

  double get totalAmount =>
      state.fold(0, (sum, item) => sum + item.total);
  int get itemCount => state.fold(0, (sum, item) => sum + item.quantity);
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});
