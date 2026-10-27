import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../providers/cart_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../core/constants.dart';
import '../../core/quantity_format.dart';

// ── Session item ──────────────────────────────────────────────────────────────

class _ScanItem {
  final Product product;
  final ProductVariant variant;
  final double quantity;

  const _ScanItem({
    required this.product,
    required this.variant,
    this.quantity = 1,
  });

  _ScanItem copyWith({double? quantity}) => _ScanItem(
    product: product,
    variant: variant,
    quantity: quantity ?? this.quantity,
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  List<_ScanItem> _items = [];
  bool _cooldown = false;
  bool _scanSuccess = false;
  String _toastMsg = '';
  bool _toastIsSuccess = true;

  Timer? _cooldownTimer;
  Timer? _flashTimer;
  Timer? _toastTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _flashTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_cooldown) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    _cooldown = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _cooldown = false);
    });

    _processBarcode(raw);
  }

  void _processBarcode(String barcode) {
    final products = ref.read(warehouseProvider);

    for (final product in products) {
      for (final variant in product.variants) {
        if (variant.barcode.isNotEmpty && variant.barcode == barcode) {
          HapticFeedback.mediumImpact();
          setState(() {
            _scanSuccess = true;
            final idx = _items.indexWhere((i) => i.variant.id == variant.id);
            if (idx >= 0) {
              _items = [
                ..._items.take(idx),
                _items[idx].copyWith(
                  quantity:
                      _items[idx].quantity +
                      quantityStep(_items[idx].product.quantityPrecision),
                ),
                ..._items.skip(idx + 1),
              ];
            } else {
              _items = [
                ..._items,
                _ScanItem(product: product, variant: variant),
              ];
            }
          });
          _flashTimer?.cancel();
          _flashTimer = Timer(const Duration(milliseconds: 1000), () {
            if (mounted) setState(() => _scanSuccess = false);
          });
          _showToast(product.name, success: true);
          return;
        }
      }
    }

    HapticFeedback.heavyImpact();
    _showToast('Not found: $barcode', success: false);
  }

  void _showToast(String msg, {required bool success}) {
    setState(() {
      _toastMsg = msg;
      _toastIsSuccess = success;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastMsg = '');
    });
  }

  void _incrementItem(int idx) {
    setState(() {
      _items = [
        ..._items.take(idx),
        _items[idx].copyWith(quantity: _items[idx].quantity + 1),
        ..._items.skip(idx + 1),
      ];
    });
  }

  void _decrementItem(int idx) {
    final step = quantityStep(_items[idx].product.quantityPrecision);
    if (_items[idx].quantity <= step) {
      _removeItem(idx);
      return;
    }
    setState(() {
      _items = [
        ..._items.take(idx),
        _items[idx].copyWith(quantity: _items[idx].quantity - step),
        ..._items.skip(idx + 1),
      ];
    });
  }

  void _removeItem(int idx) {
    setState(() {
      _items = [..._items.take(idx), ..._items.skip(idx + 1)];
    });
  }

  void _clearAll() => setState(() => _items = []);

  void _addToCart() {
    for (final item in _items) {
      ref
          .read(cartProvider.notifier)
          .setScannedQuantity(item.product, item.variant, item.quantity);
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final totalQty = _items.fold(0.0, (s, i) => s + i.quantity);
    final totalAmt = _items.fold(
      0.0,
      (s, i) => s + i.variant.price * i.quantity,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera ────────────────────────────────────────────────
          MobileScanner(onDetect: _onDetect),

          // ── Top gradient (readability) ──────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 130,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Scan frame ────────────────────────────────────────────
          Align(
            alignment: const Alignment(0, -0.25),
            child: _ScanFrame(success: _scanSuccess),
          ),

          // ── Hint label ────────────────────────────────────────────
          Align(
            alignment: const Alignment(0, 0.06),
            child: AnimatedOpacity(
              opacity: _scanSuccess ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _cooldown
                      ? 'Ready in a moment…'
                      : 'Align barcode inside the frame',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // ── Toast ──────────────────────────────────────────────────
          if (_toastMsg.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 62,
              left: 20,
              right: 20,
              child: Center(
                child: _Toast(message: _toastMsg, success: _toastIsSuccess),
              ),
            ),

          // ── Top bar ───────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => context.pop(),
                    ),
                    const Text(
                      'Barcode Scanner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
                      ),
                    ),
                    const Spacer(),
                    if (_items.isNotEmpty) _CartBadge(count: totalQty),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom panel ──────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              items: _items,
              totalQty: totalQty,
              totalAmt: totalAmt,
              cf: cf,
              onIncrement: _incrementItem,
              onDecrement: _decrementItem,

              onClear: _clearAll,
              onAddToCart: _items.isEmpty ? null : _addToCart,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan frame ─────────────────────────────────────────────────────────────────

class _ScanFrame extends StatelessWidget {
  final bool success;

  const _ScanFrame({required this.success});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 270,
      height: 115,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: success ? Colors.greenAccent : Colors.white.withAlpha(200),
          width: 2.5,
        ),
      ),
      child: AnimatedOpacity(
        opacity: success ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.greenAccent.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.greenAccent,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Toast ─────────────────────────────────────────────────────────────────────

class _Toast extends StatelessWidget {
  final String message;
  final bool success;

  const _Toast({required this.message, required this.success});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: success
            ? Colors.green.shade800.withAlpha(230)
            : Colors.red.shade800.withAlpha(230),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: Colors.white,
            size: 17,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              success ? '$message added' : message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cart badge ────────────────────────────────────────────────────────────────

class _CartBadge extends StatelessWidget {
  final double count;

  const _CartBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shopping_cart_outlined,
            color: Colors.white,
            size: 15,
          ),
          const SizedBox(width: 4),
          Text(
            formatQuantity(count, 3),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom panel ──────────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final List<_ScanItem> items;
  final double totalQty;
  final double totalAmt;
  final NumberFormat cf;
  final void Function(int) onIncrement;
  final void Function(int) onDecrement;

  final VoidCallback onClear;
  final VoidCallback? onAddToCart;

  const _BottomPanel({
    required this.items,
    required this.totalQty,
    required this.totalAmt,
    required this.cf,
    required this.onIncrement,
    required this.onDecrement,

    required this.onClear,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.52;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 2),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(kPadding, 8, 10, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    items.isEmpty
                        ? 'No items scanned yet'
                        : 'Scanned  ·  ${items.length} product${items.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: kText,
                    ),
                  ),
                ),
                if (items.isNotEmpty)
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Clear All',
                      style: TextStyle(color: kError, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),

          // Items or empty hint
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.grey.shade400,
                    size: 30,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Point camera at a barcode to scan',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: kPadding,
                  endIndent: kPadding,
                ),
                itemBuilder: (ctx, i) => _ItemRow(
                  item: items[i],
                  cf: cf,
                  onDec: () => onDecrement(i),
                  onInc: () => onIncrement(i),
                ),
              ),
            ),

          // Add to Cart button
          Padding(
            padding: EdgeInsets.fromLTRB(kPadding, 8, kPadding, bottom + 12),
            child: ElevatedButton(
              onPressed: onAddToCart,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: kBorder,
                disabledForegroundColor: Colors.grey,
              ),
              child: items.isEmpty
                  ? const Text(
                      'Scan items to add to cart',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add ${formatQuantity(totalQty, 3)} items to cart',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          cf.format(totalAmt),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Item row ──────────────────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  final _ScanItem item;
  final NumberFormat cf;
  final VoidCallback onDec;
  final VoidCallback onInc;

  const _ItemRow({
    required this.item,
    required this.cf,
    required this.onDec,
    required this.onInc,
  });

  static const _avatarColors = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF0EA5E9),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    final showVariant =
        item.variant.name.isNotEmpty && item.variant.name != 'Default';

    final avatarColor = item.product.name.isEmpty
        ? _avatarColors[0]
        : _avatarColors[item.product.name.codeUnitAt(0) % _avatarColors.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPadding, vertical: 8),
      child: Row(
        children: [
          // Colored avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: avatarColor.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                item.product.name.isNotEmpty
                    ? item.product.name[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: avatarColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Name + variant + price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showVariant)
                  Text(
                    item.variant.name,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                Text(
                  cf.format(item.variant.price * item.quantity),
                  style: const TextStyle(
                    fontSize: 12,
                    color: kPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Qty controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CtrlBtn(
                icon:
                    item.quantity <=
                        quantityStep(item.product.quantityPrecision)
                    ? Icons.delete_outline_rounded
                    : Icons.remove_rounded,
                iconColor:
                    item.quantity <=
                        quantityStep(item.product.quantityPrecision)
                    ? kError
                    : kText,
                bgColor:
                    item.quantity <=
                        quantityStep(item.product.quantityPrecision)
                    ? kError.withAlpha(20)
                    : kSurface,
                onTap: onDec,
              ),
              SizedBox(
                width: 32,
                child: Text(
                  formatQuantity(item.quantity, item.product.quantityPrecision),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              _CtrlBtn(
                icon: Icons.add_rounded,
                iconColor: Colors.white,
                bgColor: kPrimary,
                onTap: onInc,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;

  const _CtrlBtn({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: iconColor),
      ),
    );
  }
}
