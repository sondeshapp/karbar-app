import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/karbar_brand_header.dart';

class ShopSetupScreen extends ConsumerStatefulWidget {
  final bool firstRun;

  const ShopSetupScreen({super.key, this.firstRun = false});

  @override
  ConsumerState<ShopSetupScreen> createState() => _ShopSetupScreenState();
}

class _ShopSetupScreenState extends ConsumerState<ShopSetupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late String _currencyLocale;
  bool _saving = false;
  late final AnimationController _entranceController;
  late final Animation<double> _headerFade;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;

  static const _currencies =
      <({String shortLabel, String symbol, String locale})>[
        (shortLabel: 'BDT · ৳', symbol: '৳', locale: 'bn_BD'),
        (shortLabel: 'USD · \$', symbol: r'$', locale: 'en_US'),
        (shortLabel: 'EUR · €', symbol: '€', locale: 'en_EU'),
        (shortLabel: 'GBP · £', symbol: '£', locale: 'en_GB'),
      ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _headerFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, 0.72, curve: Curves.easeOut),
    );
    final formCurve = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.18, 1, curve: Curves.easeOutCubic),
    );
    _formFade = formCurve;
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.045),
      end: Offset.zero,
    ).animate(formCurve);
    _entranceController.forward();
    final settings = ref.read(settingsProvider);
    _nameController = TextEditingController(text: settings.shopName);
    _phoneController = TextEditingController(text: settings.shopPhone);
    _addressController = TextEditingController(text: settings.shopAddress);
    _currencyLocale = settings.currencyLocale;
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final currency = _currencies.firstWhere(
        (item) => item.locale == _currencyLocale,
      );
      final notifier = ref.read(settingsProvider.notifier);
      await notifier.setCurrency(currency.symbol, currency.locale);
      await notifier.setShopProfile(
        name: _nameController.text,
        phone: _phoneController.text,
        address: _addressController.text,
        completeSetup: widget.firstRun,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Failed to save shop details: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(stringsProvider).setupSaveFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skipSetup() async {
    await ref.read(settingsProvider.notifier).completeSetup();
    if (mounted && widget.firstRun) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final isFirstRun = widget.firstRun;

    return Scaffold(
      appBar: widget.firstRun ? null : AppBar(title: Text(s.storeProfile)),
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isFirstRun) ...[
                    FadeTransition(
                      opacity: _headerFade,
                      child: KarbarBrandHeader(subtitle: s.setupShopTitle),
                    ),
                    const SizedBox(height: 18),
                  ],
                  FadeTransition(
                    opacity: _formFade,
                    child: SlideTransition(
                      position: _formSlide,
                      child: Card(
                        color: cardColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isFirstRun) ...[
                                  Row(
                                    children: [
                                      Text(
                                        s.setupStep,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: 0.5,
                                            minHeight: 4,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.primary.withAlpha(24),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withAlpha(22),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Icon(
                                        Icons.storefront_rounded,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isFirstRun
                                                ? s.shopDetailsTitle
                                                : s.storeProfile,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            s.setupShopDescription,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                TextFormField(
                                  key: const Key('shop-name-field'),
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: s.shopName,
                                    prefixIcon: const Icon(
                                      Icons.store_mall_directory_outlined,
                                    ),
                                  ),
                                  validator: (value) =>
                                      isFirstRun &&
                                          (value == null ||
                                              value.trim().isEmpty)
                                      ? s.shopNameRequired
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: s.shopPhoneOptional,
                                    prefixIcon: const Icon(
                                      Icons.phone_outlined,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _addressController,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  textInputAction: TextInputAction.done,
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    labelText: s.shopAddressOptional,
                                    prefixIcon: const Icon(
                                      Icons.location_on_outlined,
                                    ),
                                    alignLabelWithHint: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  key: const Key('shop-currency-dropdown'),
                                  initialValue:
                                      _currencies.any(
                                        (item) =>
                                            item.locale == _currencyLocale,
                                      )
                                      ? _currencyLocale
                                      : 'bn_BD',
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: s.currencyLabel,
                                    prefixIcon: const Icon(
                                      Icons.currency_exchange_rounded,
                                    ),
                                  ),
                                  selectedItemBuilder: (context) => _currencies
                                      .map(
                                        (item) => Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            item.shortLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  items: _currencies
                                      .map(
                                        (item) => DropdownMenuItem(
                                          value: item.locale,
                                          child: Text(
                                            switch (item.locale) {
                                              'bn_BD' => s.currencyBdt,
                                              'en_US' => s.currencyUsd,
                                              'en_EU' => s.currencyEur,
                                              'en_GB' => s.currencyGbp,
                                              _ => item.shortLabel,
                                            },
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _currencyLocale = value);
                                    }
                                  },
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  key: const Key('save-shop-profile-button'),
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          isFirstRun
                                              ? Icons.arrow_forward_rounded
                                              : Icons.check_rounded,
                                        ),
                                  label: Text(
                                    _saving
                                        ? s.saving
                                        : isFirstRun
                                        ? s.continueSetup
                                        : s.save,
                                  ),
                                ),
                                if (isFirstRun) ...[
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _saving ? null : _skipSetup,
                                    child: Text(s.skipForNow),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
