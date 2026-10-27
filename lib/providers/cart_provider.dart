import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import 'settings_provider.dart';
import '../core/quantity_format.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  final Ref _ref;
  CartNotifier(this._ref) : super([]);

  double _orderDiscount = 0;
  String _orderDiscountType = 'flat'; // 'flat' | 'percent'

  double get orderDiscount => _orderDiscount;
  String get orderDiscountType => _orderDiscountType;

  void addItem(Product product, ProductVariant variant) {
    final index = state.indexWhere((item) => item.variant.id == variant.id);
    if (index >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index)
            state[i].copyWith(
              quantity:
                  state[i].quantity +
                  quantityStep(state[i].product.quantityPrecision),
            )
          else
            state[i],
      ];
    } else {
      state = [
        ...state,
        CartItem(product: product, variant: variant, quantity: 1),
      ];
    }
  }

  void setScannedQuantity(
    Product product,
    ProductVariant variant,
    double quantity,
  ) {
    if (!quantity.isFinite || quantity <= 0) return;
    if (product.quantityPrecision == 0 && quantity % 1 != 0) return;
    final index = state.indexWhere((item) => item.variant.id == variant.id);
    if (index < 0) {
      state = [
        ...state,
        CartItem(product: product, variant: variant, quantity: quantity),
      ];
      return;
    }
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index)
          state[i].copyWith(quantity: state[i].quantity + quantity)
        else
          state[i],
    ];
  }

  void removeItem(int variantId) {
    state = state.where((item) => item.variant.id != variantId).toList();
  }

  void incrementQty(int variantId) {
    state = state.map((item) {
      if (item.variant.id == variantId) {
        return item.copyWith(
          quantity:
              item.quantity + quantityStep(item.product.quantityPrecision),
        );
      }
      return item;
    }).toList();
  }

  void decrementQty(int variantId) {
    final item = state.firstWhere((item) => item.variant.id == variantId);
    final step = quantityStep(item.product.quantityPrecision);
    if (item.quantity <= step) {
      removeItem(variantId);
    } else {
      state = state.map((item) {
        if (item.variant.id == variantId) {
          return item.copyWith(quantity: item.quantity - step);
        }
        return item;
      }).toList();
    }
  }

  void setItemQuantity(int variantId, double quantity) {
    if (!quantity.isFinite || quantity <= 0) return;
    state = state.map((item) {
      if (item.variant.id == variantId) {
        return item.copyWith(quantity: quantity);
      }
      return item;
    }).toList();
  }

  void setItemDiscount(int variantId, double amount) {
    state = state.map((item) {
      if (item.variant.id == variantId) {
        return item.copyWith(discountAmount: amount);
      }
      return item;
    }).toList();
  }

  void setOrderDiscount(double amount, String type) {
    _orderDiscount = amount;
    _orderDiscountType = type;
    state = [...state]; // trigger rebuild
  }

  void clearCart() {
    _orderDiscount = 0;
    _orderDiscountType = 'flat';
    state = [];
  }

  double get subtotal => state.fold(0, (sum, item) => sum + item.total);

  double get orderDiscountFlat {
    if (_orderDiscountType == 'percent') {
      return (subtotal * _orderDiscount / 100).clamp(0, subtotal);
    }
    return _orderDiscount.clamp(0, subtotal);
  }

  double get taxAmount {
    final s = _ref.read(settingsProvider);
    final taxable = subtotal - orderDiscountFlat;
    return s.showTax ? taxable * s.taxRate : 0;
  }

  double get totalAmount =>
      (subtotal - orderDiscountFlat).clamp(0, double.infinity) + taxAmount;

  double get itemCount => state.fold(0.0, (sum, item) => sum + item.quantity);
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier(ref);
});
