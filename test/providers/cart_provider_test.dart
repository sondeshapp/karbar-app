import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/providers/cart_provider.dart';

void main() {
  late ProviderContainer container;
  late CartNotifier notifier;
  late Product product;
  late ProductVariant v1, v2;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(cartProvider.notifier);
    v1 = const ProductVariant(
        id: 1, name: '500ml', barcode: '111', price: 10.0, stock: 20);
    v2 = const ProductVariant(
        id: 2, name: '1L', barcode: '222', price: 18.0, stock: 10);
    product = Product(id: 1, name: 'Juice', variants: [v1, v2]);
  });

  tearDown(() => container.dispose());

  group('CartNotifier — addItem', () {
    test('adds a new item', () {
      notifier.addItem(product, v1);
      expect(container.read(cartProvider).length, 1);
      expect(container.read(cartProvider).first.quantity, 1);
    });

    test('increments quantity for existing variant', () {
      notifier.addItem(product, v1);
      notifier.addItem(product, v1);
      expect(container.read(cartProvider).length, 1);
      expect(container.read(cartProvider).first.quantity, 2);
    });

    test('treats different variants as separate cart lines', () {
      notifier.addItem(product, v1);
      notifier.addItem(product, v2);
      expect(container.read(cartProvider).length, 2);
    });
  });

  group('CartNotifier — removeItem', () {
    test('removes item by variant id', () {
      notifier.addItem(product, v1);
      notifier.addItem(product, v2);
      notifier.removeItem(v1.id!);
      final cart = container.read(cartProvider);
      expect(cart.length, 1);
      expect(cart.first.variant.id, 2);
    });
  });

  group('CartNotifier — incrementQty / decrementQty', () {
    test('incrementQty adds 1', () {
      notifier.addItem(product, v1);
      notifier.incrementQty(v1.id!);
      expect(container.read(cartProvider).first.quantity, 2);
    });

    test('decrementQty subtracts 1', () {
      notifier.addItem(product, v1);
      notifier.incrementQty(v1.id!);
      notifier.decrementQty(v1.id!);
      expect(container.read(cartProvider).first.quantity, 1);
    });

    test('decrementQty removes item when quantity reaches 0', () {
      notifier.addItem(product, v1);
      notifier.decrementQty(v1.id!);
      expect(container.read(cartProvider).isEmpty, true);
    });
  });

  group('CartNotifier — clearCart', () {
    test('empties all items', () {
      notifier.addItem(product, v1);
      notifier.addItem(product, v2);
      notifier.clearCart();
      expect(container.read(cartProvider).isEmpty, true);
    });
  });

  group('CartNotifier — computed values', () {
    test('totalAmount sums variant prices × quantities', () {
      notifier.addItem(product, v1); // 10.0 × 1
      notifier.addItem(product, v1); // 10.0 × 2 = 20.0
      notifier.addItem(product, v2); // 18.0 × 1
      expect(notifier.totalAmount, closeTo(38.0, 0.001));
    });

    test('totalAmount is 0 for empty cart', () {
      expect(notifier.totalAmount, 0.0);
    });

    test('itemCount sums all quantities', () {
      notifier.addItem(product, v1);
      notifier.addItem(product, v1);
      notifier.addItem(product, v2);
      expect(notifier.itemCount, 3);
    });

    test('itemCount is 0 for empty cart', () {
      expect(notifier.itemCount, 0);
    });
  });

  group('CartItem', () {
    test('total = variant.price × quantity', () {
      notifier.addItem(product, v1);
      notifier.incrementQty(v1.id!);
      final item = container.read(cartProvider).first;
      expect(item.total, closeTo(20.0, 0.001));
    });
  });
}
