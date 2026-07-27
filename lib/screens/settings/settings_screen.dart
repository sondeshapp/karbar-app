import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_strings.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sales_provider.dart';
import '../history/history_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final s = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F4F8);

    return Scaffold(
      backgroundColor: bg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(context, s),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuickAccess(context, ref, s),
                const SizedBox(height: 24),
                _sectionLabel(s.preferences, isDark),
                const SizedBox(height: 10),
                _buildPreferencesCard(context, ref, settings, s, isDark),
                const SizedBox(height: 20),
                _sectionLabel(s.posSettingsLabel, isDark),
                const SizedBox(height: 10),
                _buildPosCard(context, ref, settings, s, isDark),
                const SizedBox(height: 20),
                _sectionLabel(s.dataManagement, isDark),
                const SizedBox(height: 10),
                _buildDataCard(context, ref, s, isDark),
                const SizedBox(height: 20),
                _sectionLabel(s.about, isDark),
                const SizedBox(height: 10),
                _buildAboutCard(context, s, isDark),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, AppStrings s) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 24,
        left: 20,
        right: 20,
        bottom: 32,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF5B21B6)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Navigator.canPop(context))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          Row(
          children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(38),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withAlpha(77), width: 1),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'mPOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.storeManagement,
                  style: TextStyle(
                    color: Colors.white.withAlpha(204),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(38),
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded,
                  color: Colors.white),
            ),
          ),
        ],
          ),
        ],
      ),
    );
  }

  // ── Quick access cards ────────────────────────────────────────────────────

  Widget _buildQuickAccess(BuildContext context, WidgetRef ref, AppStrings s) {
    return Row(
      children: [
        Expanded(
          child: _quickCard(
            context,
            icon: Icons.receipt_long_rounded,
            label: s.historyLabel,
            color: const Color(0xFF7C3AED),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _quickCard(
            context,
            icon: Icons.inventory_2_rounded,
            label: s.inventoryLabel,
            color: const Color(0xFF059669),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _quickCard(
            context,
            icon: Icons.bar_chart_rounded,
            label: s.reportsLabel,
            color: const Color(0xFF2563EB),
          ),
        ),
      ],
    );
  }

  Widget _quickCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderCol =
        isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderCol),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 30 : 8),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFFF1F5F9)
                    : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section helpers ───────────────────────────────────────────────────────

  Widget _sectionLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF9CA3AF),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildCard(
      BuildContext context, List<Widget> children, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderCol =
        isDark ? const Color(0xFF334155) : const Color(0xFFEEF0F4);
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderCol),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 6),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(children: children),
      ),
    );
  }

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isLast = false,
    bool isDanger = false,
    required bool isDark,
  }) {
    final dividerCol =
        isDark ? const Color(0xFF273040) : const Color(0xFFF3F4F6);
    final titleCol = isDanger
        ? const Color(0xFFEF4444)
        : isDark
            ? const Color(0xFFF1F5F9)
            : const Color(0xFF111827);
    final subtitleCol =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    final effectiveIconColor =
        isDanger ? const Color(0xFFEF4444) : iconColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: effectiveIconColor.withAlpha(28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: effectiveIconColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: titleCol)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle,
                              style: TextStyle(
                                  fontSize: 12, color: subtitleCol)),
                        ],
                      ],
                    ),
                  ),
                  trailing ??
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark
                            ? const Color(0xFF475569)
                            : const Color(0xFFD1D5DB),
                        size: 20,
                      ),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 1, indent: 70, endIndent: 0, color: dividerCol),
      ],
    );
  }

  // ── Preferences card ──────────────────────────────────────────────────────

  Widget _buildPreferencesCard(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
    AppStrings s,
    bool isDark,
  ) {
    return _buildCard(context, [
      _tile(
        context: context,
        icon: Icons.language_rounded,
        iconColor: const Color(0xFF2563EB),
        title: s.languageLabel,
        subtitle: settings.language,
        isDark: isDark,
        onTap: () => _showLanguageDialog(context, ref, settings.language, s),
      ),
      _tile(
        context: context,
        icon: Icons.dark_mode_rounded,
        iconColor: const Color(0xFF7C3AED),
        title: s.darkMode,
        isDark: isDark,
        trailing: Transform.scale(
          scale: 0.85,
          child: Switch(
            value: settings.themeMode == ThemeMode.dark,
            onChanged: (_) =>
                ref.read(settingsProvider.notifier).toggleTheme(),
            activeThumbColor: const Color(0xFF7C3AED),
          ),
        ),
        onTap: () => ref.read(settingsProvider.notifier).toggleTheme(),
      ),
      _tile(
        context: context,
        icon: Icons.currency_exchange_rounded,
        iconColor: const Color(0xFF059669),
        title: s.currencyLabel,
        subtitle: _currencyLabel(settings.currencySymbol),
        isDark: isDark,
        isLast: true,
        onTap: () =>
            _showCurrencyDialog(context, ref, settings.currencySymbol, s),
      ),
    ], isDark);
  }

  // ── POS Settings card ─────────────────────────────────────────────────────

  Widget _buildPosCard(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
    AppStrings s,
    bool isDark,
  ) {
    return _buildCard(context, [
      _tile(
        context: context,
        icon: Icons.percent_rounded,
        iconColor: const Color(0xFFF59E0B),
        title: s.taxRate,
        subtitle: '${settings.taxRate.toStringAsFixed(1)}%',
        isDark: isDark,
        onTap: () => _showTaxRateDialog(context, ref, settings.taxRate, s),
      ),
      _tile(
        context: context,
        icon: Icons.receipt_rounded,
        iconColor: const Color(0xFF0EA5E9),
        title: s.showTaxOnReceipt,
        isDark: isDark,
        isLast: true,
        trailing: Transform.scale(
          scale: 0.85,
          child: Switch(
            value: settings.showTax,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setShowTax(v),
            activeThumbColor: const Color(0xFF0EA5E9),
          ),
        ),
        onTap: () => ref
            .read(settingsProvider.notifier)
            .setShowTax(!settings.showTax),
      ),
    ], isDark);
  }

  // ── Data Management card ──────────────────────────────────────────────────

  Widget _buildDataCard(
      BuildContext context, WidgetRef ref, AppStrings s, bool isDark) {
    return _buildCard(context, [
      _tile(
        context: context,
        icon: Icons.history_rounded,
        iconColor: const Color(0xFFEC4899),
        title: s.salesHistory,
        subtitle: s.viewTransactions,
        isDark: isDark,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        ),
      ),
      _tile(
        context: context,
        icon: Icons.delete_outline_rounded,
        iconColor: const Color(0xFFEF4444),
        title: s.clearSalesData,
        subtitle: s.clearSalesSubtitle,
        isDark: isDark,
        isLast: true,
        isDanger: true,
        onTap: () => _showClearDataDialog(context, ref, s),
      ),
    ], isDark);
  }

  // ── About card ────────────────────────────────────────────────────────────

  Widget _buildAboutCard(BuildContext context, AppStrings s, bool isDark) {
    return _buildCard(context, [
      _tile(
        context: context,
        icon: Icons.info_outline_rounded,
        iconColor: const Color(0xFF6B7280),
        title: s.appVersion,
        subtitle: '1.0.0',
        isDark: isDark,
        trailing: const SizedBox.shrink(),
      ),
      _tile(
        context: context,
        icon: Icons.help_outline_rounded,
        iconColor: const Color(0xFF2563EB),
        title: s.helpSupport,
        isDark: isDark,
        isLast: true,
        onTap: () => _showHelpDialog(context, s),
      ),
    ], isDark);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _currencyLabel(String symbol) {
    if (symbol == r'$') return 'USD — US Dollar';
    if (symbol == '৳') return 'BDT — Bangladeshi Taka';
    if (symbol == '€') return 'EUR — Euro';
    if (symbol == '£') return 'GBP — British Pound';
    return symbol;
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showLanguageDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
    AppStrings s,
  ) {
    // English label always in English; Bengali label always in Bengali so
    // the user can recognise and switch even when the UI is in the other language.
    const options = [
      ('English', 'English'),
      ('বাংলা', 'বাংলা'),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.selectLanguage),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((opt) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Radio<String>(
                      value: opt.$1,
                      groupValue: current,
                      onChanged: (v) {
                        if (v != null) {
                          ref
                              .read(settingsProvider.notifier)
                              .setLanguage(v);
                          Navigator.pop(ctx);
                        }
                      },
                      activeColor: const Color(0xFF2563EB),
                    ),
                    title: Text(opt.$2,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    onTap: () {
                      ref
                          .read(settingsProvider.notifier)
                          .setLanguage(opt.$1);
                      Navigator.pop(ctx);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showCurrencyDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
    AppStrings s,
  ) {
    final currencies = [
      {'label': 'USD — US Dollar (\$)', 'symbol': r'$', 'locale': 'en_US'},
      {'label': 'BDT — Bangladeshi Taka (৳)', 'symbol': '৳', 'locale': 'bn_BD'},
      {'label': 'EUR — Euro (€)', 'symbol': '€', 'locale': 'en_EU'},
      {'label': 'GBP — British Pound (£)', 'symbol': '£', 'locale': 'en_GB'},
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.selectCurrency),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: currencies
              .map((c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Radio<String>(
                      value: c['symbol']!,
                      groupValue: current,
                      onChanged: (v) {
                        if (v != null) {
                          ref
                              .read(settingsProvider.notifier)
                              .setCurrency(c['symbol']!, c['locale']!);
                          Navigator.pop(ctx);
                        }
                      },
                      activeColor: const Color(0xFF2563EB),
                    ),
                    title: Text(c['label']!),
                    onTap: () {
                      ref
                          .read(settingsProvider.notifier)
                          .setCurrency(c['symbol']!, c['locale']!);
                      Navigator.pop(ctx);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showTaxRateDialog(
    BuildContext context,
    WidgetRef ref,
    double current,
    AppStrings s,
  ) {
    final controller = TextEditingController(
        text: current > 0 ? current.toStringAsFixed(1) : '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.setTaxRateTitle),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            suffixText: '%',
            hintText: '0.0',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(minimumSize: const Size(80, 44)),
            onPressed: () {
              final val = double.tryParse(controller.text) ?? 0.0;
              ref
                  .read(settingsProvider.notifier)
                  .setTaxRate(val.clamp(0, 100));
              Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog(
      BuildContext context, WidgetRef ref, AppStrings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.clearDataTitle),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Text(s.clearDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              minimumSize: const Size(80, 44),
            ),
            onPressed: () {
              ref.read(salesProvider.notifier).clearSales();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.salesDataCleared)),
              );
            },
            child: Text(s.clear),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.helpTitle),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Text(s.helpBody),
        actions: [
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(minimumSize: const Size(80, 44)),
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.gotIt),
          ),
        ],
      ),
    );
  }
}
