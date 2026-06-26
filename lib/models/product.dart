import 'product_variant.dart';

class Product {
  final int? id;
  final String name;
  final String description;
  final String category;
  final String brand;
  final String sku;
  final String unit;
  final String imagePath;
  final double costPrice;
  final int lowStockAlert;
  final DateTime createdAt;
  final List<ProductVariant> variants;

  Product({
    this.id,
    required this.name,
    this.description = '',
    this.category = '',
    this.brand = '',
    this.sku = '',
    this.unit = 'pcs',
    this.imagePath = '',
    this.costPrice = 0,
    this.lowStockAlert = 5,
    DateTime? createdAt,
    this.variants = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  double get price => variants.isNotEmpty ? variants.first.price : 0;
  int get totalStock => variants.fold(0, (sum, v) => sum + v.stock);
  String get barcode => variants.isNotEmpty ? variants.first.barcode : '';
  bool get hasVariants => variants.length > 1;
  bool get isLowStock => totalStock > 0 && totalStock <= lowStockAlert;

  String get priceDisplay {
    if (variants.isEmpty) return '0';
    if (variants.length == 1) return variants.first.price.toString();
    final prices = variants.map((v) => v.price).toList()..sort();
    if (prices.first == prices.last) return prices.first.toString();
    return '${prices.first} – ${prices.last}';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'brand': brand,
    'sku': sku,
    'unit': unit,
    'image_path': imagePath,
    'cost_price': costPrice,
    'low_stock_alert': lowStockAlert,
    'created_at': createdAt.toIso8601String(),
  };

  factory Product.fromMap(
    Map<String, dynamic> map, {
    List<ProductVariant> variants = const [],
  }) =>
      Product(
        id: map['id'] as int?,
        name: map['name'] as String,
        description: map['description'] as String? ?? '',
        category: map['category'] as String? ?? '',
        brand: map['brand'] as String? ?? '',
        sku: map['sku'] as String? ?? '',
        unit: map['unit'] as String? ?? 'pcs',
        imagePath: map['image_path'] as String? ?? '',
        costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
        lowStockAlert: map['low_stock_alert'] as int? ?? 5,
        createdAt: map['created_at'] != null
            ? DateTime.parse(map['created_at'] as String)
            : DateTime.now(),
        variants: variants,
      );

  Product copyWith({
    int? id,
    String? name,
    String? description,
    String? category,
    String? brand,
    String? sku,
    String? unit,
    String? imagePath,
    double? costPrice,
    int? lowStockAlert,
    List<ProductVariant>? variants,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
        brand: brand ?? this.brand,
        sku: sku ?? this.sku,
        unit: unit ?? this.unit,
        imagePath: imagePath ?? this.imagePath,
        costPrice: costPrice ?? this.costPrice,
        lowStockAlert: lowStockAlert ?? this.lowStockAlert,
        createdAt: createdAt,
        variants: variants ?? this.variants,
      );
}
