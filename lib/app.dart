import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'screens/purchases/supplier_purchase_screen.dart';
import 'screens/pos/scanner_screen.dart';
import 'screens/pos/cart_screen.dart';
import 'screens/receipt/receipt_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/reports/daily_cash_close_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/shop_setup_screen.dart';
import 'screens/history/history_screen.dart';
import 'screens/baki/baki_screen.dart';
import 'screens/baki/customer_detail_screen.dart';
import 'db/database_helper.dart';
import 'providers/staff_provider.dart';
import 'screens/settings/staff_gate_screen.dart';
import 'screens/settings/staff_management_screen.dart';
import 'screens/settings/cloud_sync_screen.dart';
import 'screens/settings/staff_roles_screen.dart';
import 'screens/settings/receipt_design_screen.dart';
import 'screens/settings/staff_activity_screen.dart';
import 'models/staff_role.dart';
import 'widgets/staff_permission_gate.dart';

Widget _guarded(String permission, Widget child) =>
    StaffPermissionGate(anyOf: [permission], child: child);

Widget _guardedAny(List<String> permissions, Widget child) =>
    StaffPermissionGate(anyOf: permissions, child: child);

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AppEntryScreen()),
    GoRoute(
      path: '/pos',
      builder: (context, state) =>
          _guarded(StaffPermission.pos, const PosScreen()),
    ),
    GoRoute(
      path: '/warehouse',
      builder: (context, state) =>
          _guarded(StaffPermission.inventory, const WarehouseScreen()),
    ),
    GoRoute(
      path: '/purchases',
      builder: (context, state) =>
          _guarded(StaffPermission.purchases, const SupplierPurchaseScreen()),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) =>
          _guarded(StaffPermission.dashboard, const DashboardScreen()),
    ),
    GoRoute(
      path: '/reports',
      builder: (context, state) =>
          _guarded(StaffPermission.reports, const ReportsScreen()),
    ),
    GoRoute(
      path: '/cash-close',
      builder: (context, state) =>
          _guarded(StaffPermission.cashClose, const DailyCashCloseScreen()),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(showBackButton: true),
    ),
    GoRoute(
      path: '/settings/shop-profile',
      builder: (context, state) =>
          _guarded('owner_admin', const ShopSetupScreen()),
    ),
    GoRoute(
      path: '/onboarding/setup-shop',
      builder: (context, state) => const ShopSetupScreen(firstRun: true),
    ),
    GoRoute(
      path: '/settings/staff',
      builder: (context, state) =>
          _guarded('owner_admin', const StaffManagementScreen()),
    ),
    GoRoute(
      path: '/settings/staff/roles',
      builder: (context, state) =>
          _guarded('owner_admin', const StaffRolesScreen()),
    ),
    GoRoute(
      path: '/settings/activity',
      builder: (context, state) =>
          _guarded('owner_admin', const StaffActivityScreen()),
    ),
    GoRoute(
      path: '/settings/receipt-design',
      builder: (context, state) =>
          _guarded('owner_admin', const ReceiptDesignScreen()),
    ),
    GoRoute(
      path: '/settings/cloud-sync',
      builder: (context, state) =>
          _guarded('owner_admin', const CloudSyncScreen()),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) =>
          _guarded(StaffPermission.history, const HistoryScreen()),
    ),
    GoRoute(
      path: '/baki',
      builder: (context, state) =>
          _guarded(StaffPermission.customerCredit, const BakiScreen()),
    ),
    GoRoute(
      path: '/baki/customer',
      builder: (context, state) {
        final summary = state.extra as CustomerBakiSummary;
        return _guarded(
          StaffPermission.customerCredit,
          CustomerDetailScreen(summary: summary),
        );
      },
    ),
    GoRoute(
      path: '/warehouse/scanner',
      builder: (context, state) =>
          _guarded(StaffPermission.inventory, const InventoryScannerScreen()),
    ),
    GoRoute(
      path: '/warehouse/add',
      builder: (context, state) {
        // extra may be a String (barcode pre-fill from scan) or null (manual)
        final initialBarcode = state.extra as String?;
        return _guarded(
          StaffPermission.inventory,
          ProductFormScreen(product: null, initialBarcode: initialBarcode),
        );
      },
    ),
    GoRoute(
      path: '/warehouse/edit',
      builder: (context, state) {
        final product = state.extra as Product;
        return _guarded(
          StaffPermission.inventory,
          ProductFormScreen(product: product),
        );
      },
    ),
    GoRoute(
      path: '/pos/scanner',
      builder: (context, state) =>
          _guarded(StaffPermission.pos, const ScannerScreen()),
    ),
    GoRoute(
      path: '/cart',
      builder: (context, state) =>
          _guarded(StaffPermission.pos, const CartScreen()),
    ),
    GoRoute(
      path: '/receipt',
      builder: (context, state) {
        final sale = state.extra as Sale;
        return _guardedAny(
          [StaffPermission.pos, StaffPermission.history],
          ReceiptScreen(
            sale: sale,
            returnToHistory: state.uri.queryParameters['history'] == '1',
          ),
        );
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
      title: 'Karbar',
      locale: settings.language == 'বাংলা'
          ? const Locale('bn')
          : const Locale('en', 'US'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en', 'US'), Locale('bn')],
      theme: appTheme,
      darkTheme: appDarkTheme,
      themeMode: settings.themeMode,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppEntryScreen extends ConsumerWidget {
  const AppEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final staff = ref.watch(activeStaffProvider);
    if (!settings.setupComplete) {
      return const ShopSetupScreen(firstRun: true);
    }
    if (staff == null) return const StaffGateScreen();
    return const HomeScreen();
  }
}
