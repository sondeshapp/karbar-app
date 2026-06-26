import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Minimal barcode scanner used only by the warehouse/inventory side.
/// Scans one barcode then immediately pops with the raw string value.
/// Never touches the cart or product lookup — that's the caller's job.
class InventoryScannerScreen extends StatefulWidget {
  const InventoryScannerScreen({super.key});

  @override
  State<InventoryScannerScreen> createState() =>
      _InventoryScannerScreenState();
}

class _InventoryScannerScreenState extends State<InventoryScannerScreen> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _done = true;
    HapticFeedback.mediumImpact();
    context.pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera ─────────────────────────────────────────────────
          MobileScanner(onDetect: _onDetect),

          // ── Top fade ───────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0, height: 130,
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

          // ── Scan frame ─────────────────────────────────────────────
          const Align(
            alignment: Alignment(0, -0.2),
            child: _ScanFrame(),
          ),

          // ── Hint ───────────────────────────────────────────────────
          const Align(
            alignment: Alignment(0, 0.12),
            child: Text(
              'Point at a barcode to scan',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
          ),

          // ── Top bar ────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: () => context.pop(),
                    ),
                    const Text(
                      'Scan Barcode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 8, color: Colors.black87)
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      height: 115,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withAlpha(200),
          width: 2.5,
        ),
      ),
    );
  }
}
