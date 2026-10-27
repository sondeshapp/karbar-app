class ProductVariant {
  final int? id;
  final String? syncId;
  final int? productId;
  final String name;
  final String barcode;
  final double price;
  final double stock;

  const ProductVariant({
    this.id,
    this.syncId,
    this.productId,
    required this.name,
    required this.barcode,
    required this.price,
    required this.stock,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'sync_id': syncId,
    'product_id': productId,
    'name': name,
    'barcode': barcode,
    'price': price,
    'stock': stock,
  };

  factory ProductVariant.fromMap(Map<String, dynamic> map) => ProductVariant(
    id: map['id'] as int?,
    syncId: map['sync_id'] as String?,
    productId: map['product_id'] as int?,
    name: map['name'] as String,
    barcode: map['barcode'] as String? ?? '',
    price: (map['price'] as num).toDouble(),
    stock: (map['stock'] as num).toDouble(),
  );

  ProductVariant copyWith({
    int? id,
    String? syncId,
    int? productId,
    String? name,
    String? barcode,
    double? price,
    double? stock,
  }) => ProductVariant(
    id: id ?? this.id,
    syncId: syncId ?? this.syncId,
    productId: productId ?? this.productId,
    name: name ?? this.name,
    barcode: barcode ?? this.barcode,
    price: price ?? this.price,
    stock: stock ?? this.stock,
  );
}
