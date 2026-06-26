class ProductVariant {
  final int? id;
  final int? productId;
  final String name;
  final String barcode;
  final double price;
  final int stock;

  const ProductVariant({
    this.id,
    this.productId,
    required this.name,
    required this.barcode,
    required this.price,
    required this.stock,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'product_id': productId,
    'name': name,
    'barcode': barcode,
    'price': price,
    'stock': stock,
  };

  factory ProductVariant.fromMap(Map<String, dynamic> map) => ProductVariant(
    id: map['id'] as int?,
    productId: map['product_id'] as int?,
    name: map['name'] as String,
    barcode: map['barcode'] as String? ?? '',
    price: (map['price'] as num).toDouble(),
    stock: map['stock'] as int,
  );

  ProductVariant copyWith({
    int? id,
    int? productId,
    String? name,
    String? barcode,
    double? price,
    int? stock,
  }) =>
      ProductVariant(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        price: price ?? this.price,
        stock: stock ?? this.stock,
      );
}
