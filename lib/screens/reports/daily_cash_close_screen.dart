import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_strings.dart';
import '../../db/database_helper.dart';
import '../../models/daily_cash_close.dart';
import '../../models/sales_report.dart';
import '../../providers/settings_provider.dart';
import '../../providers/staff_provider.dart';

class DailyCashCloseScreen extends ConsumerStatefulWidget {
  const DailyCashCloseScreen({super.key});

  @override
  ConsumerState<DailyCashCloseScreen> createState() =>
      _DailyCashCloseScreenState();
}

class _DailyCashCloseScreenState extends ConsumerState<DailyCashCloseScreen> {
  final _db = DatabaseHelper();
  final _counted = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  SalesReportData? _report;
  List<DailyCashClose> _closes = [];
  bool _loading = true;
  bool _saving = false;

  double get _cashReceipts => _report?.paymentTotals['cash'] ?? 0;
  double get _expectedCash => _cashReceipts + (_report?.bakiCollected ?? 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final day = DateTime(_date.year, _date.month, _date.day);
    final results = await Future.wait([
      _db.getSalesReportData(ReportRange(from: day, through: day)),
      _db.getDailyCloses(businessDate: day),
    ]);
    if (!mounted) return;
    setState(() {
      _report = results[0] as SalesReportData;
      _closes = results[1] as List<DailyCashClose>;
      _loading = false;
    });
  }

  Future<void> _chooseDate(bool isBn) async {
    final selected = await showDatePicker(
      context: context,
      locale: isBn ? const Locale('bn') : const Locale('en', 'US'),
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null) return;
    setState(() => _date = selected);
    await _load();
  }

  Future<void> _saveClose(AppStrings s) async {
    final counted = double.tryParse(_counted.text.trim());
    if (counted == null ||
        !counted.isFinite ||
        counted < 0 ||
        _report == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.enterValidCountedCash)));
      return;
    }
    setState(() => _saving = true);
    try {
      await _db.recordDailyClose(
        DailyCashClose(
          businessDate: _date,
          expectedCash: _expectedCash,
          countedCash: counted,
          cashReceipts: _cashReceipts,
          bakiIssued: _report!.bakiIssued,
          bakiCollected: _report!.bakiCollected,
          refundsTotal: _report!.returns,
          paymentTotals: Map<String, double>.from(_report!.paymentTotals),
          note: _note.text,
          closedAt: DateTime.now(),
          staffId: ref.read(activeStaffProvider)?.id,
        ),
      );
      _counted.clear();
      _note.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.cashCloseSaved)));
      }
    } catch (error) {
      debugPrint('Could not save daily cash close: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.cashCloseSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final s = ref.watch(stringsProvider);
    final isBn = settings.language == 'বাংলা';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currency = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );
    String money(num value) => _localizeDigits(currency.format(value), isBn);

    final counted = double.tryParse(_counted.text.trim());
    final variance = counted == null ? null : counted - _expectedCash;
    final colors = [
      const Color(0xFF2563EB),
      const Color(0xFF059669),
      const Color(0xFF7C3AED),
      const Color(0xFFF59E0B),
    ];

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(title: Text(s.dailyCashClose)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).padding.bottom + 24,
                ),
                children: [
                  _dateSelector(
                    context,
                    s,
                    _formatDate(_date, isBn),
                    () => _chooseDate(isBn),
                    isDark,
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 350 ? 2 : 1;
                      final gap = 12.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      final issuedAndRefunds =
                          '${s.bakiIssued}: ${money(_report!.bakiIssued)}';
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          _metricCard(
                            width: width,
                            title: s.expectedDrawerCash,
                            value: money(_expectedCash),
                            icon: Icons.account_balance_wallet_outlined,
                            color: colors[0],
                          ),
                          _metricCard(
                            width: width,
                            title: s.cashSalesAfterRefunds,
                            value: money(_cashReceipts),
                            icon: Icons.payments_outlined,
                            color: colors[1],
                          ),
                          _metricCard(
                            width: width,
                            title: s.bakiCollected,
                            value: money(_report!.bakiCollected),
                            icon: Icons.call_received_rounded,
                            color: colors[2],
                          ),
                          _metricCard(
                            width: width,
                            title: s.bakiIssued,
                            value: money(_report!.bakiIssued),
                            detail: s.refundsAmount(money(_report!.returns)),
                            icon: Icons.swap_horiz_rounded,
                            color: colors[3],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _sectionPanel(
                    context,
                    title: s.countedDrawerCash,
                    icon: Icons.point_of_sale_rounded,
                    accent: colors[0],
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _counted,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: s.countedDrawerCash,
                            prefixText: '${settings.currencySymbol} ',
                          ),
                        ),
                        if (variance != null) ...[
                          const SizedBox(height: 12),
                          _differenceBanner(
                            context,
                            s.differenceAmount(money(variance)),
                            variance < 0
                                ? Theme.of(context).colorScheme.error
                                : const Color(0xFF059669),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _note,
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: s.noteOptional,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _saving ? null : () => _saveClose(s),
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? s.saving : s.saveThisClose),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionPanel(
                    context,
                    title: s.paymentTotals,
                    icon: Icons.payments_outlined,
                    accent: colors[1],
                    isDark: isDark,
                    child: _report!.paymentTotals.isEmpty
                        ? _emptyState(context, s.noPaymentsForDate, colors[1])
                        : Column(
                            children: _report!.paymentTotals.entries.map((
                              entry,
                            ) {
                              return _dataRow(
                                context,
                                icon: _paymentIcon(entry.key),
                                label: s.paymentMethodLabel(entry.key),
                                value: money(entry.value),
                                accent: colors[1],
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 16),
                  _sectionPanel(
                    context,
                    title: s.savedCloses,
                    icon: Icons.fact_check_outlined,
                    accent: colors[2],
                    isDark: isDark,
                    child: _closes.isEmpty
                        ? _emptyState(context, s.noClosesForDate, colors[2])
                        : Column(
                            children: _closes.map((close) {
                              final time = _localizeDigits(
                                DateFormat.Hm().format(close.closedAt),
                                isBn,
                              );
                              return _savedCloseRow(
                                context,
                                s.closeSummary(
                                  money(close.countedCash),
                                  money(close.difference),
                                ),
                                [
                                  time,
                                  if (close.note.isNotEmpty) close.note,
                                ].join(' · '),
                                colors[2],
                                isDark,
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _dateSelector(
    BuildContext context,
    AppStrings s,
    String date,
    VoidCallback onTap,
    bool isDark,
  ) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withAlpha(24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.businessDate,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _metricCard({
    required double width,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? detail,
  }) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 124),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color, color.withAlpha(210)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: color.withAlpha(55),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, color: Colors.white.withAlpha(220), size: 19),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withAlpha(225),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _sectionPanel(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color accent,
    required bool isDark,
    required Widget child,
  }) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: accent.withAlpha(isDark ? 38 : 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _differenceBanner(BuildContext context, String text, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.compare_arrows_rounded, color: color, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  Widget _dataRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: accent, size: 19),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _emptyState(BuildContext context, String text, Color accent) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withAlpha(16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: accent, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _savedCloseRow(
    BuildContext context,
    String title,
    String subtitle,
    Color accent,
    bool isDark,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: accent.withAlpha(isDark ? 18 : 12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withAlpha(48)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, color: accent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  IconData _paymentIcon(String method) => switch (method.toLowerCase()) {
    'cash' => Icons.payments_outlined,
    'bkash' || 'nagad' => Icons.phone_android_rounded,
    'card' => Icons.credit_card_rounded,
    _ => Icons.account_balance_wallet_outlined,
  };

  String _formatDate(DateTime date, bool isBn) {
    if (!isBn) return DateFormat.yMMMMd('en_US').format(date);
    const months = [
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর',
    ];
    return '${_localizeDigits('${date.day}', true)} ${months[date.month - 1]} ${_localizeDigits('${date.year}', true)}';
  }

  String _localizeDigits(String value, bool isBn) {
    if (!isBn) return value;
    const bengaliDigits = '০১২৩৪৫৬৭৮৯';
    return value.replaceAllMapped(RegExp(r'[0-9]'), (match) {
      final digit = int.parse(match.group(0)!);
      return bengaliDigits[digit];
    });
  }
}
