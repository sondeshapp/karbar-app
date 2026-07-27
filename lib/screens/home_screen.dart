import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import '../providers/sales_provider.dart';
import '../providers/settings_provider.dart';
import '../core/app_strings.dart';
import '../models/sale.dart';
import 'pos/pos_screen.dart';
import 'settings/settings_screen.dart';

final selectedTabProvider = StateProvider<int>((ref) => 0);

// ── Shell ─────────────────────────────────────────────────────────────────────

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
          _HomeHub(),
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
                icon: const Icon(Icons.home_outlined),
                activeIcon: const Icon(Icons.home_rounded),
                label: 'Home',
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

// ── Hub ───────────────────────────────────────────────────────────────────────

class _HomeHub extends ConsumerStatefulWidget {
  const _HomeHub();

  @override
  ConsumerState<_HomeHub> createState() => _HomeHubState();
}

class _HomeHubState extends ConsumerState<_HomeHub> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(salesProvider.notifier).loadSales());
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final s = ref.watch(stringsProvider);
    final dashAsync = ref.watch(dashboardProvider);
    final sales = ref.watch(salesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final fmt = NumberFormat.currency(
      symbol: settings.currencySymbol,
      decimalDigits: 2,
    );
    final revenueToday = dashAsync.valueOrNull?.revenueToday ?? 0.0;

    final recentSales = [...sales]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              revenueToday: revenueToday,
              fmt: fmt,
              s: s,
            ),
          ),
          SliverToBoxAdapter(
            child: _ServicesSection(s: s, isDark: isDark),
          ),
          SliverToBoxAdapter(
            child: _RecentSalesSection(
              sales: recentSales.take(5).toList(),
              fmt: fmt,
              isDark: isDark,
              s: s,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final double revenueToday;
  final NumberFormat fmt;
  final AppStrings s;

  const _Header({
    required this.revenueToday,
    required this.fmt,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting =
        hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.store_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                greeting,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_outlined,
                    color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Revenue + New Sale
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fmt.format(revenueToday),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${s.today} revenue',
                      style: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 13),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => context.push('/pos'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'New Sale',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Quick actions
          Row(
            children: [
              _QuickAction(
                icon: Icons.point_of_sale_rounded,
                label: s.navPos,
                onTap: () => context.push('/pos'),
              ),
              const SizedBox(width: 10),
              _QuickAction(
                icon: Icons.inventory_2_rounded,
                label: s.navWarehouse,
                onTap: () => context.push('/warehouse'),
              ),
              const SizedBox(width: 10),
              _QuickAction(
                icon: Icons.receipt_long_rounded,
                label: 'History',
                onTap: () => context.push('/history'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withAlpha(18), width: 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Services Grid ─────────────────────────────────────────────────────────────

class _ServicesSection extends StatelessWidget {
  final AppStrings s;
  final bool isDark;

  const _ServicesSection({required this.s, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final services = [
      _Svc(Icons.point_of_sale_rounded, s.navPos,
          const Color(0xFF2563EB), '/pos'),
      _Svc(Icons.inventory_2_rounded, s.navWarehouse,
          const Color(0xFF059669), '/warehouse'),
      _Svc(Icons.receipt_long_rounded, 'History',
          const Color(0xFFF59E0B), '/history'),
      _Svc(Icons.dashboard_rounded, s.navDashboard,
          const Color(0xFF7C3AED), '/dashboard'),
      _Svc(Icons.settings_rounded, s.navSettings,
          const Color(0xFF64748B), '/settings'),
      _Svc(Icons.pending_actions_rounded, 'বাকি হিসেব',
          const Color(0xFFF59E0B), '/baki'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Services',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: services
                .map((svc) => _ServiceTile(svc: svc, isDark: isDark))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _Svc {
  final IconData icon;
  final String label;
  final Color color;
  final String? route;
  const _Svc(this.icon, this.label, this.color, this.route);
}

class _ServiceTile extends StatelessWidget {
  final _Svc svc;
  final bool isDark;

  const _ServiceTile({required this.svc, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final active = svc.route != null;
    return GestureDetector(
      onTap: active ? () => context.push(svc.route!) : null,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 25 : 8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: active
                    ? svc.color.withAlpha(28)
                    : Colors.grey.withAlpha(18),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                svc.icon,
                color: active ? svc.color : Colors.grey,
                size: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              svc.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent Sales ──────────────────────────────────────────────────────────────

class _RecentSalesSection extends StatelessWidget {
  final List<Sale> sales;
  final NumberFormat fmt;
  final bool isDark;
  final AppStrings s;

  const _RecentSalesSection({
    required this.sales,
    required this.fmt,
    required this.isDark,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recent Transactions',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/history'),
                child: const Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sales.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                s.noData,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8)),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 25 : 8),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sales.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.black.withAlpha(8),
                  indent: 64,
                ),
                itemBuilder: (context, i) {
                  final sale = sales[i];
                  final timeStr =
                      DateFormat('h:mm a').format(sale.createdAt);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF059669).withAlpha(22),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.receipt_rounded,
                              color: Color(0xFF059669), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sale #${sale.id ?? (i + 1)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                '${sale.items.length} item${sale.items.length == 1 ? '' : 's'} · $timeStr',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          fmt.format(sale.totalAmount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
