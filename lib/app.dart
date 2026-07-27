import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'models/product.dart';
import 'models/sale.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/pos/pos_screen.dart';
import 'screens/warehouse/warehouse_screen.dart';
import 'screens/warehouse/product_form_screen.dart';
import 'screens/warehouse/inventory_scanner_screen.dart';
import 'screens/pos/scanner_screen.dart';
import 'screens/pos/cart_screen.dart';
import 'screens/receipt/receipt_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/history/history_screen.dart';
import 'screens/baki/baki_screen.dart';
import 'screens/baki/customer_detail_screen.dart';
import 'db/database_helper.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/pos',
      builder: (context, state) => const PosScreen(),
    ),
    GoRoute(
      path: '/warehouse',
      builder: (context, state) => const WarehouseScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/baki',
      builder: (context, state) => const BakiScreen(),
    ),
    GoRoute(
      path: '/baki/customer',
      builder: (context, state) {
        final summary = state.extra as CustomerBakiSummary;
        return CustomerDetailScreen(summary: summary);
      },
    ),
    GoRoute(
      path: '/warehouse/scanner',
      builder: (context, state) => const InventoryScannerScreen(),
    ),
    GoRoute(
      path: '/warehouse/add',
      builder: (context, state) {
        // extra may be a String (barcode pre-fill from scan) or null (manual)
        final initialBarcode = state.extra as String?;
        return ProductFormScreen(
            product: null, initialBarcode: initialBarcode);
      },
    ),
    GoRoute(
      path: '/warehouse/edit',
      builder: (context, state) {
        final product = state.extra as Product;
        return ProductFormScreen(product: product);
      },
    ),
    GoRoute(
      path: '/pos/scanner',
      builder: (context, state) => const ScannerScreen(),
    ),
    GoRoute(
      path: '/cart',
      builder: (context, state) => const CartScreen(),
    ),
    GoRoute(
      path: '/receipt',
      builder: (context, state) {
        final sale = state.extra as Sale;
        return ReceiptScreen(sale: sale);
      },
    ),
  ],
);

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'mPOS',
      theme: appTheme,
      darkTheme: appDarkTheme,
      themeMode: settings.themeMode,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
