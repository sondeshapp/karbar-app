import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_strings.dart';
import '../providers/settings_provider.dart';
import 'dashboard/dashboard_screen.dart';
import 'warehouse/warehouse_screen.dart';
import 'pos/pos_screen.dart';
import 'settings/settings_screen.dart';

final selectedTabProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(selectedTabProvider);
    final s = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: selectedTab,
        children: const [
          DashboardScreen(),
          WarehouseScreen(),
          PosScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _GlassNavBar(
        selectedTab: selectedTab,
        isDark: isDark,
        strings: s,
        onTap: (i) => ref.read(selectedTabProvider.notifier).state = i,
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final int selectedTab;
  final bool isDark;
  final AppStrings strings;
  final ValueChanged<int> onTap;

  const _GlassNavBar({
    required this.selectedTab,
    required this.isDark,
    required this.strings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F172A).withAlpha(102)
                : Colors.white.withAlpha(102),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withAlpha(18)
                    : const Color(0xFF2563EB).withAlpha(25),
                width: 0.8,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 50 : 15),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              currentIndex: selectedTab,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: primary,
              unselectedItemColor: isDark
                  ? Colors.white.withAlpha(100)
                  : const Color(0xFFADB5BD),
              selectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              onTap: onTap,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.dashboard_outlined),
                  activeIcon: const Icon(Icons.dashboard_rounded),
                  label: strings.navDashboard,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.inventory_2_outlined),
                  activeIcon: const Icon(Icons.inventory_2_rounded),
                  label: strings.navWarehouse,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.point_of_sale_outlined),
                  activeIcon: const Icon(Icons.point_of_sale_rounded),
                  label: strings.navPos,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.settings_outlined),
                  activeIcon: const Icon(Icons.settings_rounded),
                  label: strings.navSettings,
                ),
              ],
            ),
          ),
        ),
      );
  }
}
