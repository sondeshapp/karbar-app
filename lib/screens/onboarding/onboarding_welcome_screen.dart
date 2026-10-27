import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_strings.dart';
import '../../providers/settings_provider.dart';

class OnboardingWelcomeScreen extends ConsumerStatefulWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  ConsumerState<OnboardingWelcomeScreen> createState() =>
      _OnboardingWelcomeScreenState();
}

class _OnboardingWelcomeScreenState
    extends ConsumerState<OnboardingWelcomeScreen> {
  bool _busy = false;

  Future<void> _skip() async {
    setState(() => _busy = true);
    try {
      await ref.read(settingsProvider.notifier).completeSetup();
    } catch (error, stackTrace) {
      debugPrint('Could not continue onboarding: $error\n$stackTrace');
      if (mounted) {
        final s = ref.read(stringsProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.onboardingContinueFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: isDark ? 0.035 : 0.12,
              child: Image.asset(
                'assets/onboarding_market_pattern.png',
                scale: 2.4,
                repeat: ImageRepeat.repeat,
                fit: BoxFit.none,
                alignment: Alignment.topLeft,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 46,
                  ),
                  child: IntrinsicHeight(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _brandRow(context),
                            const Spacer(),
                            Text(
                              s.welcomeTitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6,
                                    height: 1.15,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              child: Text(
                                s.welcomeDescription,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      height: 1.45,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _featureCard(context, s),
                            const SizedBox(height: 26),
                            FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () =>
                                        context.push('/onboarding/setup-shop'),
                              icon: const Icon(Icons.storefront_rounded),
                              label: Text(s.setupShopButton),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _busy ? null : _skip,
                              child: _busy
                                  ? Text(s.pleaseWait)
                                  : Text(s.skipOnboarding),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandRow(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('assets/karbar_logo.png'),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'Karbar',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    ],
  );

  Widget _featureCard(BuildContext context, AppStrings s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: _featureItem(
            context,
            icon: Icons.point_of_sale_rounded,
            label: s.onboardingFeatureSales,
            color: const Color(0xFF2563EB),
          ),
        ),
        Expanded(
          child: _featureItem(
            context,
            icon: Icons.inventory_2_rounded,
            label: s.onboardingFeatureInventory,
            color: const Color(0xFF059669),
          ),
        ),
        Expanded(
          child: _featureItem(
            context,
            icon: Icons.bar_chart_rounded,
            label: s.onboardingFeatureReports,
            color: const Color(0xFF7C3AED),
          ),
        ),
      ],
    ),
  );

  Widget _featureItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      const SizedBox(height: 8),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}
