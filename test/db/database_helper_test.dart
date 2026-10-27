import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/models/product.dart';
import 'package:m_pos/models/product_variant.dart';
import 'package:m_pos/models/cart_item.dart';
import 'package:m_pos/models/sale.dart';

Product _makeProduct(String name, {double price = 5.0, double stock = 20}) =>
    Product(
      name: name,
      variants: [
        ProductVariant(
          name: 'Default',
          barcode: '',
          price: price,
          stock: stock,
        ),
      ],
    );

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

  final db = DatabaseHelper();

  // ── Products ──────────────────────────────────────────────────────────────

  group('insertProduct / getAllProducts', () {
    test('inserts product and loads it back with variants', () async {
      final id = await db.insertProduct(
        _makeProduct('Apple Juice', price: 2.5, stock: 50),
      );
      expect(id, greaterThan(0));

      final products = await db.getAllProducts();
      expect(products.length, 1);
      expect(products.first.name, 'Apple Juice');
      expect(products.first.variants.length, 1);
      expect(products.first.variants.first.price, 2.5);
      expect(products.first.variants.first.stock, 50);
    });

    test('products are sorted by name', () async {
      await db.insertProduct(_makeProduct('Zebra'));
      await db.insertProduct(_makeProduct('Apple'));
      await db.insertProduct(_makeProduct('Mango'));

      final products = await db.getAllProducts();
      expect(products.map((p) => p.name).toList(), ['Apple', 'Mango', 'Zebra']);
    });

    test('inserts product with multiple variants', () async {
      final p = Product(
        name: 'Cola',
        variants: [
          const ProductVariant(
            name: '500ml',
            barcode: 'A1',
            price: 1.5,
            stock: 100,
          ),
          const ProductVariant(
            name: '1L',
            barcode: 'A2',
            price: 2.5,
            stock: 50,
          ),
        ],
      );
      await db.insertProduct(p);

      final loaded = await db.getAllProducts();
      expect(loaded.first.variants.length, 2);
      expect(
        loaded.first.variants.map((v) => v.name).toList(),
        containsAll(['500ml', '1L']),
      );
    });
  });

  group('updateProduct', () {
    test('updates product name and variant price', () async {
      await db.insertProduct(_makeProduct('Old Name', price: 1.0));
      final products = await db.getAllProducts();
      final updated = products.first.copyWith(
        name: 'New Name',
        variants: [products.first.variants.first.copyWith(price: 3.0)],
      );

      await db.updateProduct(updated);

      final result = await db.getAllProducts();
      expect(result.first.name, 'New Name');
      expect(result.first.variants.first.price, 3.0);
    });

    test('adding a new variant on update', () async {
      await db.insertProduct(_makeProduct('Water'));
      final products = await db.getAllProducts();
      final withNewVariant = products.first.copyWith(
        variants: [
          ...products.first.variants,
          const ProductVariant(name: '2L', barcode: '', price: 3.0, stock: 30),
        ],
      );

      await db.updateProduct(withNewVariant);

      final result = await db.getAllProducts();
      expect(result.first.variants.length, 2);
    });

    test('removing a variant on update', () async {
      final p = Product(
        name: 'Soda',
        variants: [
          const ProductVariant(
            name: 'Small',
            barcode: '',
            price: 1.0,
            stock: 10,
          ),
          const ProductVariant(
            name: 'Large',
            barcode: '',
            price: 2.0,
            stock: 10,
          ),
        ],
      );
      await db.insertProduct(p);
      final loaded = await db.getAllProducts();
      final withOneVariant = loaded.first.copyWith(
        variants: [loaded.first.variants.first],
      );

      await db.updateProduct(withOneVariant);

      final result = await db.getAllProducts();
      expect(result.first.variants.length, 1);
    });
  });

  group('deleteProduct', () {
    test('removes product and its variants', () async {
      final id = await db.insertProduct(_makeProduct('Delete Me'));
      await db.deleteProduct(id);

      final products = await db.getAllProducts();
      expect(products.isEmpty, true);
    });

    test('deleting one product does not affect others', () async {
      final id = await db.insertProduct(_makeProduct('Remove'));
      await db.insertProduct(_makeProduct('Keep'));

      await db.deleteProduct(id);

      final products = await db.getAllProducts();
      expect(products.length, 1);
      expect(products.first.name, 'Keep');
    });
  });

  // ── Sales ─────────────────────────────────────────────────────────────────

  group('insertSale / getAllSales', () {
    test('inserts sale and loads it back', () async {
      await db.insertProduct(_makeProduct('Item', price: 10.0, stock: 20));
      final products = await db.getAllProducts();
      final product = products.first;
      final variant = product.variants.first;

      final sale = Sale(
        items: [CartItem(product: product, variant: variant, quantity: 2)],
        totalAmount: 20.0,
        createdAt: DateTime(2024, 6, 1, 12, 0),
      );

      final saleId = await db.insertSale(sale);
      expect(saleId, greaterThan(0));

      final sales = await db.getAllSales();
      expect(sales.length, 1);
      expect(sales.first.totalAmount, 20.0);
      expect(sales.first.items.length, 1);
      expect(sales.first.items.first.quantity, 2);
    });

    test('insertSale decreases variant stock', () async {
      await db.insertProduct(_makeProduct('Milk', stock: 30));
      final products = await db.getAllProducts();
      final product = products.first;
      final variant = product.variants.first;

      final sale = Sale(
        items: [CartItem(product: product, variant: variant, quantity: 5)],
        totalAmount: 25.0,
        createdAt: DateTime.now(),
      );
      await db.insertSale(sale);

      final updated = await db.getAllProducts();
      expect(updated.first.variants.first.stock, 25);
    });

    test('stock does not go below 0', () async {
      await db.insertProduct(_makeProduct('Rare', stock: 2));
      final products = await db.getAllProducts();
      final product = products.first;
      final variant = product.variants.first;

      final sale = Sale(
        items: [CartItem(product: product, variant: variant, quantity: 10)],
        totalAmount: 50.0,
        createdAt: DateTime.now(),
      );
      await db.insertSale(sale);

      final updated = await db.getAllProducts();
      expect(updated.first.variants.first.stock, 0);
    });

    test('sales are ordered by created_at descending', () async {
      await db.insertProduct(_makeProduct('P', stock: 100));
      final products = await db.getAllProducts();
      final p = products.first;
      final v = p.variants.first;

      Future<void> addSale(DateTime dt, double amount) async {
        await db.insertSale(
          Sale(
            items: [CartItem(product: p, variant: v, quantity: 1)],
            totalAmount: amount,
            createdAt: dt,
          ),
        );
      }

      await addSale(DateTime(2024, 1, 1), 10.0);
      await addSale(DateTime(2024, 3, 1), 30.0);
      await addSale(DateTime(2024, 2, 1), 20.0);

      final sales = await db.getAllSales();
      expect(sales.map((s) => s.totalAmount).toList(), [30.0, 20.0, 10.0]);
    });
  });
}
