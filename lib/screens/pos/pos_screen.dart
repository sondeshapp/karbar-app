import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../providers/cart_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/product_grid_card.dart';
import '../../widgets/empty_state.dart';
import '../../core/constants.dart';
import '../../core/quantity_format.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _selectedCategory = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(warehouseProvider.notifier).loadProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    await context.push<void>('/pos/scanner');
  }

  void _showVariantPicker(Product product, ProductVariant initialVariant) {
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final s = ref.read(stringsProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPadding, 8, kPadding, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...product.variants.map(
            (variant) => ListTile(
              title: Text(
                variant.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(s.inStockText(variant.stock)),
              trailing: Text(
                cf.format(variant.price),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kPrimary,
                  fontSize: 15,
                ),
              ),
              onTap: () {
                ref.read(cartProvider.notifier).addItem(product, variant);
                Navigator.pop(ctx);
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + kPadding),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allProducts = ref.watch(warehouseProvider);
    final cartItems = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final s = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Unique sorted categories
    final categories =
        allProducts
            .map((p) => p.category)
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    // Filtered products
    final filtered = allProducts.where((p) {
      final q = _query.toLowerCase();
      final matchesQuery =
          _query.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
      final matchesCat =
          _selectedCategory.isEmpty || p.category == _selectedCategory;
      return matchesQuery && matchesCat;
    }).toList();

    // Group by category
    final grouped = <String, List<Product>>{};
    for (final p in filtered) {
      final cat = p.category.isEmpty ? s.otherCategory : p.category;
      grouped.putIfAbsent(cat, () => []).add(p);
    }

    final headerBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final inputBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF3F4F6);
    final hintColor = isDark ? Colors.white38 : Colors.grey;
    final chipUnselectedBg = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF3F4F6);
    final chipUnselectedText = isDark ? Colors.white70 : kText;
    final dividerColor = isDark ? const Color(0xFF334155) : kBorder;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF5F5F5),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // ── Search bar ──────────────────────────────────────────
                Container(
                  color: headerBg,
                  padding: const EdgeInsets.fromLTRB(kPadding, 10, 8, 10),
                  child: Row(
                    children: [
                      if (Navigator.canPop(context))
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 18,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 44,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(12),
                            border: isDark
                                ? Border.all(
                                    color: Colors.white.withAlpha(10),
                                    width: 0.5,
                                  )
                                : null,
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: s.searchProducts,
                              hintStyle: TextStyle(
                                color: hintColor,
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: hintColor,
                                size: 20,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: kPrimary,
                        ),
                        onPressed: _scanBarcode,
                        tooltip: 'Scan barcode',
                      ),
                    ],
                  ),
                ),
                // ── Category chips ──────────────────────────────────────
                if (categories.isNotEmpty)
                  Container(
                    color: headerBg,
                    height: 46,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: kPadding,
                        vertical: 6,
                      ),
                      itemCount: categories.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final cat = i == 0 ? '' : categories[i - 1];
                        final label = i == 0 ? s.allCategories : cat;
                        final selected = _selectedCategory == cat;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? kPrimary : chipUnselectedBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: selected
                                    ? Colors.white
                                    : chipUnselectedText,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                // ── Divider ─────────────────────────────────────────────
                if (categories.isNotEmpty)
                  Divider(height: 1, color: dividerColor),
                // ── Product grid ────────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyState(message: s.noProductsFound)
                      : ListView.builder(
                          padding: EdgeInsets.only(
                            top: 8,
                            bottom: cartItems.isNotEmpty
                                ? MediaQuery.of(context).padding.bottom + 80
                                : MediaQuery.of(context).padding.bottom + 8,
                          ),
                          itemCount: grouped.length,
                          itemBuilder: (ctx, sectionIdx) {
                            final cat = grouped.keys.elementAt(sectionIdx);
                            final products = grouped[cat]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (grouped.length > 1 ||
                                    _selectedCategory.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      6,
                                    ),
                                    child: Text(
                                      cat,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : kText,
                                      ),
                                    ),
                                  ),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        childAspectRatio: 0.68,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                      ),
                                  itemCount: products.length,
                                  itemBuilder: (ctx, j) => ProductGridCard(
                                    product: products[j],
                                    onVariantPick: _showVariantPicker,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),

            // ── View Cart floating bar ────────────────────────────────
            if (cartItems.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(context).padding.bottom + 8,
                child: _ViewCartBar(
                  itemCount: cartNotifier.itemCount,
                  total: cartNotifier.totalAmount,
                  cf: cf,
                  label: s.viewCart,
                  bottomOffset: MediaQuery.of(context).padding.bottom,
                  onTap: () => context.push('/cart'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── View Cart floating button ──────────────────────────────────────────────

class _ViewCartBar extends StatelessWidget {
  final double itemCount;
  final double total;
  final NumberFormat cf;
  final String label;
  final double bottomOffset;
  final VoidCallback onTap;

  const _ViewCartBar({
    required this.itemCount,
    required this.total,
    required this.cf,
    required this.label,
    required this.bottomOffset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: kPrimary.withAlpha(230),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withAlpha(40), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withAlpha(90),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(50),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          formatQuantity(itemCount, 3),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      cf.format(total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
