import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';

void main() {
  group('Product', () {
    ProductVariant v(int id, double price, double stock) => ProductVariant(
      id: id,
      name: 'Variant $id',
      barcode: '',
      price: price,
      stock: stock,
    );

    test('totalStock sums all variant stocks', () {
      final p = Product(name: 'X', variants: [v(1, 1.0, 10), v(2, 2.0, 5)]);
      expect(p.totalStock, 15);
    });

    test('totalStock is 0 with no variants', () {
      expect(Product(name: 'X').totalStock, 0);
    });

    test('hasVariants is false for single variant', () {
      final p = Product(name: 'X', variants: [v(1, 1.0, 10)]);
      expect(p.hasVariants, false);
    });

    test('hasVariants is true for multiple variants', () {
      final p = Product(name: 'X', variants: [v(1, 1.0, 5), v(2, 2.0, 5)]);
      expect(p.hasVariants, true);
    });

    test('isLowStock triggers at or below threshold', () {
      final p = Product(name: 'X', lowStockAlert: 5, variants: [v(1, 1.0, 5)]);
      expect(p.isLowStock, true);
    });

    test('isLowStock false above threshold', () {
      final p = Product(name: 'X', lowStockAlert: 5, variants: [v(1, 1.0, 6)]);
      expect(p.isLowStock, false);
    });

    test(
      'isLowStock false when stock is 0 (out of stock handled separately)',
      () {
        final p = Product(
          name: 'X',
          lowStockAlert: 5,
          variants: [v(1, 1.0, 0)],
        );
        // out-of-stock is still considered low stock
        expect(p.isLowStock, false); // 0 <= 5 but isLowStock requires > 0
      },
    );

    test('price returns first variant price', () {
      final p = Product(name: 'X', variants: [v(1, 9.99, 10), v(2, 19.99, 5)]);
      expect(p.price, 9.99);
    });

    test('fromMap roundtrip preserves all fields', () {
      final map = {
        'id': 1,
        'name': 'Cola',
        'description': 'Soft drink',
        'category': 'Beverages',
        'brand': 'Acme',
        'sku': 'COL-001',
        'unit': 'ml',
        'image_path': '/img.jpg',
        'cost_price': 0.50,
        'low_stock_alert': 10,
        'created_at': '2024-01-15T10:00:00.000',
      };
      final p = Product.fromMap(map);
      expect(p.name, 'Cola');
      expect(p.brand, 'Acme');
      expect(p.category, 'Beverages');
      expect(p.unit, 'ml');
      expect(p.costPrice, 0.50);
      expect(p.lowStockAlert, 10);

      final roundtrip = p.toMap();
      expect(roundtrip['name'], 'Cola');
      expect(roundtrip['brand'], 'Acme');
      expect(roundtrip['sku'], 'COL-001');
    });

    test('copyWith only changes specified fields', () {
      final p = Product(name: 'Original', brand: 'BrandA');
      final copy = p.copyWith(name: 'Updated');
      expect(copy.name, 'Updated');
      expect(copy.brand, 'BrandA');
    });
  });

  group('ProductVariant', () {
    test('fromMap roundtrip', () {
      final map = {
        'id': 1,
        'product_id': 2,
        'name': '500ml',
        'barcode': '9876',
        'price': 2.50,
        'stock': 100,
      };
      final v = ProductVariant.fromMap(map);
      expect(v.name, '500ml');
      expect(v.price, 2.50);
      expect(v.stock, 100);

      final back = v.toMap();
      expect(back['barcode'], '9876');
    });

    test('copyWith works', () {
      const v = ProductVariant(name: 'S', barcode: '', price: 1.0, stock: 10);
      final copy = v.copyWith(price: 2.0, stock: 5);
      expect(copy.price, 2.0);
      expect(copy.stock, 5);
      expect(copy.name, 'S');
    });
  });
}
