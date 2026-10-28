import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_strings.dart';
import '../../models/staff_user.dart';
import '../../providers/settings_provider.dart';
import '../../providers/staff_provider.dart';
import '../../widgets/recovery_code_dialog.dart';
import '../../widgets/onboarding_step_header.dart';

class StaffGateScreen extends ConsumerStatefulWidget {
  const StaffGateScreen({super.key});

  @override
  ConsumerState<StaffGateScreen> createState() => _StaffGateScreenState();
}

class _StaffGateScreenState extends ConsumerState<StaffGateScreen>
    with TickerProviderStateMixin {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _showPin = false;
  int _failedAttempts = 0;
  DateTime? _blockedUntil;
  Timer? _lockoutTimer;
  final _keyboardFocusNode = FocusNode(debugLabel: 'Staff PIN keypad');
  String? _error;
  int? _selectedId;
  int _pinLength = 4;
  int _legacyPinLength = 4;
  late final AnimationController _entranceController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    final curve = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _fade = curve;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(curve);
    _entranceController.forward();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _keyboardFocusNode.dispose();
    _entranceController.dispose();
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(hasStaffAccountsProvider);
    final settings = ref.watch(settingsProvider);
    final s = ref.watch(stringsProvider);
    final isOwnerSetup =
        accounts.whenOrNull(data: (hasAccounts) => !hasAccounts) ?? false;
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleLoginKey,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                if (isOwnerSetup)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: Theme.of(context).brightness == Brightness.dark
                            ? 0.035
                            : 0.065,
                        child: Image.asset(
                          'assets/onboarding_market_pattern.png',
                          scale: 2.4,
                          repeat: ImageRepeat.repeat,
                          fit: BoxFit.none,
                          alignment: Alignment.topLeft,
                        ),
                      ),
                    ),
                  ),
                SingleChildScrollView(
                  padding: isOwnerSetup
                      ? const EdgeInsets.fromLTRB(20, 16, 20, 28)
                      : const EdgeInsets.fromLTRB(22, 14, 22, 18),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0, constraints.maxHeight - 32),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isOwnerSetup ? 520 : 420,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FadeTransition(
                                opacity: _fade,
                                child: isOwnerSetup
                                    ? OnboardingStepHeader(
                                        step: 2,
                                        stepLabel: s.ownerSetupStep,
                                        title: s.ownerPinTitle,
                                        subtitle: s.ownerPinSubtitle,
                                        shopName: settings.shopName,
                                        trailing: _languageButton(
                                          context,
                                          settings.language,
                                          s,
                                        ),
                                      )
                                    : _brandRow(
                                        context,
                                        settings.shopName,
                                        settings.language,
                                        s,
                                      ),
                              ),
                              const SizedBox(height: 22),
                              FadeTransition(
                                opacity: _fade,
                                child: SlideTransition(
                                  position: _slide,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 320),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeIn,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0, 0.025),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                    child: accounts.when(
                                      loading: () => _form(
                                        key: const ValueKey('loading-accounts'),
                                        icon: Icons.storefront_outlined,
                                        title: s.enterStaffPinTitle,
                                        subtitle: s.pleaseWait,
                                        children: const [
                                          Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        ],
                                      ),
                                      error: (error, _) => _form(
                                        key: const ValueKey(
                                          'accounts-load-error',
                                        ),
                                        icon: Icons.error_outline_rounded,
                                        title: s.staffAccountsLoadFailed,
                                        subtitle: s.staffSignInSubtitle,
                                        children: const [],
                                      ),
                                      data: (hasAccounts) => hasAccounts
                                          ? _loginForm(s)
                                          : _firstOwnerForm(s),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandRow(
    BuildContext context,
    String shopName,
    String language,
    AppStrings s,
  ) => Row(
    children: [
      Container(
        width: 52,
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.asset('assets/karbar_logo.png'),
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Karbar',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                fontSize: 24,
              ),
            ),
            if (shopName.isNotEmpty)
              Text(
                shopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      _languageButton(context, language, s),
    ],
  );

  Widget _languageButton(BuildContext context, String language, AppStrings s) =>
      Tooltip(
        message: language == 'বাংলা' ? s.switchToEnglish : s.switchToBengali,
        child: OutlinedButton(
          onPressed: () => ref
              .read(settingsProvider.notifier)
              .setLanguage(language == 'বাংলা' ? 'English' : 'বাংলা'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(54, 38),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            shape: const StadiumBorder(),
          ),
          child: Text(language == 'বাংলা' ? 'EN' : 'বাং'),
        ),
      );

  Widget _firstOwnerForm(AppStrings s) => Padding(
    key: const ValueKey('create-owner'),
    padding: const EdgeInsets.all(20),
    child: _form(
      key: const ValueKey('create-owner-form'),
      icon: Icons.admin_panel_settings_outlined,
      title: s.ownerPinTitle,
      subtitle: s.ownerPinSubtitle,
      showHeading: false,
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: s.ownerNameLabel,
            prefixIcon: const Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 14),
        _pinLengthPicker(s),
        const SizedBox(height: 10),
        _pinField(s, maxLength: _pinLength),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _busy ? null : () => _createOwner(s),
          icon: _busy ? _buttonProgress() : const Icon(Icons.shield_outlined),
          label: Text(_busy ? s.pleaseWait : s.createOwnerButton),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => ref.read(settingsProvider.notifier).reopenShopSetup(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(s.previousStep),
        ),
      ],
      showCard: false,
    ),
  );

  Widget _loginForm(AppStrings s) {
    final staffAsync = ref.watch(activeStaffListProvider);
    return staffAsync.when(
      loading: () => _form(
        key: const ValueKey('loading-staff'),
        icon: Icons.lock_outline_rounded,
        title: s.enterStaffPinTitle,
        subtitle: s.pleaseWait,
        children: const [Center(child: CircularProgressIndicator())],
      ),
      error: (error, _) => _form(
        key: const ValueKey('staff-load-error'),
        icon: Icons.error_outline_rounded,
        title: s.staffLoadFailed,
        subtitle: s.staffSignInSubtitle,
        children: const [],
      ),
      data: (staff) {
        if (staff.isEmpty) {
          return _form(
            key: const ValueKey('no-staff'),
            icon: Icons.person_off_outlined,
            title: s.noActiveStaffTitle,
            subtitle: s.noActiveStaffSubtitle,
            children: const [],
          );
        }
        final selected = staff.any((user) => user.id == _selectedId)
            ? _selectedId
            : staff.first.id;
        final selectedUser = staff.firstWhere((user) => user.id == selected);
        final hasStoredPinLength = {4, 6}.contains(selectedUser.pinLength);
        final pinLength = hasStoredPinLength
            ? selectedUser.pinLength
            : _legacyPinLength;
        return _form(
          key: const ValueKey('staff-login'),
          icon: Icons.lock_outline_rounded,
          title: s.enterStaffPinTitle,
          subtitle: s.selectStaffSubtitle,
          showCard: false,
          showHeading: false,
          showFormError: false,
          children: [
            const SizedBox(height: 16),
            _staffSelector(staff, selectedUser, s),
            if (!hasStoredPinLength) ...[
              const SizedBox(height: 12),
              _legacyPinLengthPicker(s),
            ],
            const SizedBox(height: 10),
            _loginPinEntry(s, pinLength),
            const SizedBox(height: 8),
            _pinPad(s, pinLength),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _isLockedOut || _pin.text.length != pinLength
                  ? null
                  : () => _login(staff, selected, s),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: _busy ? _buttonProgress() : const Icon(Icons.lock_open),
              label: Text(_busy ? s.pleaseWait : s.unlockButton),
            ),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : selectedUser.isOwner && selectedUser.id != null
                    ? () => _recoverOwnerPin(
                        s,
                        selectedUser.id!,
                        selectedUser.pinLength == 6 ? 6 : 4,
                      )
                    : () => setState(() => _error = s.askOwnerToResetPin),
                icon: const Icon(Icons.key_rounded, size: 18),
                label: Text(
                  selectedUser.isOwner ? s.forgotPin : s.askOwnerToResetPin,
                ),
                style: TextButton.styleFrom(
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _staffSelector(
    List<StaffUser> staff,
    StaffUser selected,
    AppStrings s,
  ) {
    final colors = Theme.of(context).colorScheme;
    final roleColor = selected.isOwner ? colors.tertiary : colors.primary;
    return Column(
      children: [
        Semantics(
          button: true,
          label:
              '${selected.name}, ${s.staffRoleLabel(selected.role)}. ${s.changeStaffAccount}',
          child: InkWell(
            canRequestFocus: false,
            customBorder: const CircleBorder(),
            onTap: () => _chooseStaff(staff, selected, s),
            child: SizedBox.square(
              dimension: 96,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: roleColor.withAlpha(18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: roleColor.withAlpha(100),
                          width: 1.5,
                        ),
                      ),
                      child: CircleAvatar(
                        backgroundColor: roleColor,
                        child: Text(
                          selected.name.isEmpty
                              ? '?'
                              : selected.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 21,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: roleColor.withAlpha(22),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            s.staffRoleLabel(selected.role),
            style: TextStyle(
              color: roleColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseStaff(
    List<StaffUser> staff,
    StaffUser selected,
    AppStrings s,
  ) async {
    final colors = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<StaffUser>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          _StaffPickerSheet(staff: staff, selectedId: selected.id, strings: s),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedId = result.id;
      _legacyPinLength = result.pinLength == 6 ? 6 : 4;
      _pin.clear();
      _error = null;
    });
  }

  Widget _pinLengthPicker(AppStrings s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(s.pinLengthLabel, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 4, label: Text(s.pinDigitsLabel(4))),
          ButtonSegment(value: 6, label: Text(s.pinDigitsLabel(6))),
        ],
        selected: {_pinLength},
        onSelectionChanged: (selected) => setState(() {
          _pinLength = selected.first;
          _pin.clear();
        }),
      ),
    ],
  );

  Widget _legacyPinLengthPicker(AppStrings s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(s.pinLengthLabel, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 4, label: Text(s.pinDigitsLabel(4))),
            ButtonSegment(value: 6, label: Text(s.pinDigitsLabel(6))),
          ],
          selected: {_legacyPinLength},
          onSelectionChanged: (selection) => setState(() {
            _legacyPinLength = selection.first;
            _pin.clear();
            _error = null;
          }),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        s.legacyPinLengthHint,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _loginPinEntry(AppStrings s, int pinLength) {
    final colors = Theme.of(context).colorScheme;
    final hasLoginError = _error != null && _error != s.askOwnerToResetPin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: s.pinLabel,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final size = math.min(
                48.0,
                (constraints.maxWidth - (pinLength - 1) * gap) / pinLength,
              );
              return Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(pinLength, (index) {
                    final filled = index < _pin.text.length;
                    final active = index == _pin.text.length && !filled;
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == pinLength - 1 ? 0 : gap,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        width: size,
                        height: size,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          shape: BoxShape.circle,
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: colors.primary.withAlpha(35),
                                    blurRadius: 0,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                          border: Border.all(
                            color: hasLoginError
                                ? colors.error
                                : filled || active
                                ? colors.primary
                                : colors.outlineVariant,
                            width: filled || active ? 1.5 : 1,
                          ),
                        ),
                        child: filled
                            ? Text(
                                _showPin ? _pin.text[index] : '•',
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: _showPin ? 22 : 25,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _error ?? s.pinLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: !hasLoginError
                      ? colors.onSurfaceVariant
                      : colors.error,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _showPin ? s.hidePin : s.showPin,
              onPressed: () => setState(() => _showPin = !_showPin),
              icon: Icon(
                _showPin
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pinPad(AppStrings s, int pinLength) {
    final colors = Theme.of(context).colorScheme;
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'delete'],
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          children: [
            for (final row in keys)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final key in row)
                      SizedBox.square(
                        dimension: 68,
                        child: key.isEmpty
                            ? const SizedBox.shrink()
                            : Semantics(
                                button: true,
                                label: key == 'delete'
                                    ? s.deleteLastPinDigit
                                    : key,
                                child: Material(
                                  color: Colors.transparent,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    canRequestFocus: false,
                                    customBorder: const CircleBorder(),
                                    onTap: _busy || _isLockedOut
                                        ? null
                                        : () {
                                            if (key == 'delete') {
                                              _deletePinDigit();
                                            } else {
                                              _appendPinDigit(
                                                key,
                                                maxLength: pinLength,
                                              );
                                            }
                                          },
                                    child: Center(
                                      child: key == 'delete'
                                          ? Container(
                                              width: 48,
                                              height: 48,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: colors.primary,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.backspace_outlined,
                                                size: 21,
                                                color: colors.onPrimary,
                                              ),
                                            )
                                          : Text(
                                              key,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    color: colors.onSurface,
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _appendPinDigit(String digit, {required int maxLength}) {
    if (_pin.text.length >= maxLength) return;
    _setPin('${_pin.text}$digit');
  }

  void _deletePinDigit() {
    if (_pin.text.isEmpty) return;
    _setPin(_pin.text.substring(0, _pin.text.length - 1));
  }

  void _setPin(String value) {
    setState(() {
      _pin.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      _error = null;
    });
  }

  bool get _isLockedOut =>
      _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  void _startLockoutCountdown(AppStrings s) {
    _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
    _failedAttempts = 0;
    _lockoutTimer?.cancel();
    _refreshLockoutMessage(s);
    _lockoutTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshLockoutMessage(s),
    );
  }

  void _refreshLockoutMessage(AppStrings s) {
    if (!mounted) return;
    final remaining =
        _blockedUntil?.difference(DateTime.now()).inMilliseconds ?? 0;
    if (remaining <= 0) {
      _lockoutTimer?.cancel();
      _lockoutTimer = null;
      setState(() {
        _blockedUntil = null;
        _error = null;
      });
      return;
    }
    final seconds = (remaining / 1000).ceil();
    setState(() => _error = s.attemptsBlockedCountdown(seconds));
  }

  KeyEventResult _handleLoginKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final hasAccounts = ref
        .read(hasStaffAccountsProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    if (!hasAccounts) return KeyEventResult.ignored;
    final staff = ref
        .read(activeStaffListProvider)
        .maybeWhen(data: (value) => value, orElse: () => <StaffUser>[]);
    if (staff.isEmpty) return KeyEventResult.ignored;
    if (_busy || _isLockedOut) return KeyEventResult.handled;

    final user = staff.firstWhere(
      (account) => account.id == _selectedId,
      orElse: () => staff.first,
    );
    final length = {4, 6}.contains(user.pinLength)
        ? user.pinLength
        : _legacyPinLength;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _deletePinDigit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_pin.text.length == length) {
        _login(staff, user.id, ref.read(stringsProvider));
      }
      return KeyEventResult.handled;
    }
    final digit = event.character;
    if (digit != null && RegExp(r'^\d$').hasMatch(digit)) {
      if (_pin.text.length < length) {
        _appendPinDigit(digit, maxLength: length);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _form({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    bool showCard = true,
    bool showHeading = true,
    bool showFormError = true,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(22),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (showHeading) const SizedBox(height: 22),
        ...children,
        if (showFormError)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withAlpha(18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: Theme.of(context).colorScheme.error,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
      ],
    );
    if (showCard) {
      return Card(
        key: key,
        child: Padding(padding: const EdgeInsets.all(22), child: content),
      );
    }
    return Padding(key: key, padding: EdgeInsets.zero, child: content);
  }

  Widget _pinField(AppStrings s, {int maxLength = 8}) => TextField(
    controller: _pin,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.done,
    obscureText: !_showPin,
    maxLength: maxLength,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: s.pinLabel,
      prefixIcon: const Icon(Icons.password_rounded),
      suffixIcon: IconButton(
        tooltip: _showPin ? s.hidePin : s.showPin,
        onPressed: () => setState(() => _showPin = !_showPin),
        icon: Icon(
          _showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ),
  );

  Widget _buttonProgress() => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
    ),
  );

  Future<void> _createOwner(AppStrings s) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = ref.read(staffProvider);
      final ownerId = await access.create(
        name: _name.text,
        role: 'owner',
        pin: _pin.text,
        pinLength: _pinLength,
      );
      String? recoveryCode;
      try {
        recoveryCode = await access.createOwnerRecoveryCode(
          ownerStaffId: ownerId,
        );
      } catch (error) {
        debugPrint('Could not create owner recovery code: $error');
      }
      final owner = (await access.list(
        activeOnly: true,
      )).firstWhere((staff) => staff.id == ownerId);
      if (recoveryCode != null && mounted) {
        await showRecoveryCodeDialog(
          context: context,
          strings: s,
          code: recoveryCode,
        );
      }
      if (!mounted) return;
      ref.read(activeStaffProvider.notifier).state = owner;
      ref.invalidate(hasStaffAccountsProvider);
      ref.invalidate(activeStaffListProvider);
      if (recoveryCode == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.recoverySetupPending)));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error, s));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recoverOwnerPin(
    AppStrings s,
    int ownerStaffId,
    int currentPinLength,
  ) async {
    final access = ref.read(staffProvider);
    if (!await access.hasOwnerRecoveryCodeFor(ownerStaffId)) {
      if (mounted) setState(() => _error = s.recoveryCodeNotConfigured);
      return;
    }
    if (!mounted) return;

    final values = await showDialog<(String, String, int)>(
      context: context,
      builder: (_) => _OwnerPinRecoveryDialog(
        strings: s,
        initialPinLength: currentPinLength,
      ),
    );
    if (values == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final owner = await access.recoverOwnerPin(
        recoveryCode: values.$1,
        newPin: values.$2,
        newPinLength: values.$3,
      );
      if (!mounted) return;
      if (owner == null) {
        setState(() => _error = s.recoveryCodeInvalid);
      } else {
        ref.invalidate(activeStaffListProvider);
        ref.invalidate(staffListProvider);
        _pin.clear();
        setState(() {
          _selectedId = owner.id;
          _error = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.recoveryPinSuccess)));
      }
    } on OwnerRecoveryLocked {
      if (mounted) setState(() => _error = s.recoveryCodeLocked);
    } on OwnerRecoveryNotConfigured {
      if (mounted) setState(() => _error = s.recoveryCodeNotConfigured);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error, s));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login(List<StaffUser> staff, int? id, AppStrings s) async {
    if (id == null) return;
    final blockedUntil = _blockedUntil;
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
      _refreshLockoutMessage(s);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref.read(staffProvider).authenticate(id, _pin.text);
      if (user == null) {
        _failedAttempts++;
        if (_failedAttempts >= 5) {
          _startLockoutCountdown(s);
        } else {
          setState(() => _error = s.incorrectStaffPin);
        }
      } else {
        _failedAttempts = 0;
        _blockedUntil = null;
        _lockoutTimer?.cancel();
        _lockoutTimer = null;
        ref.invalidate(activeStaffListProvider);
        ref.read(activeStaffProvider.notifier).state = user;
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error, s));
    } finally {
      if (mounted) {
        _pin.clear();
        setState(() => _busy = false);
      }
    }
  }

  String _message(Object error, AppStrings s) {
    if (error is ArgumentError && error.message.toString().startsWith('PIN')) {
      return s.pinFormatInvalid;
    }
    return error is ArgumentError
        ? error.message.toString()
        : s.staffAccountSaveFailed;
  }
}

class _StaffPickerSheet extends StatefulWidget {
  final List<StaffUser> staff;
  final int? selectedId;
  final AppStrings strings;

  const _StaffPickerSheet({
    required this.staff,
    required this.selectedId,
    required this.strings,
  });

  @override
  State<_StaffPickerSheet> createState() => _StaffPickerSheetState();
}

class _StaffPickerSheetState extends State<_StaffPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final colors = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final filtered = widget.staff
        .where((user) => user.name.toLowerCase().contains(query))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '${strings.staffMemberLabel} · ${widget.staff.length}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: strings.searchStaff,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(strings.noStaffSearchResults))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: colors.outlineVariant.withAlpha(130),
                      ),
                      itemBuilder: (context, index) {
                        final user = filtered[index];
                        final roleColor = user.isOwner
                            ? colors.tertiary
                            : colors.primary;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          selected: user.id == widget.selectedId,
                          selectedTileColor: colors.primary.withAlpha(12),
                          leading: CircleAvatar(
                            backgroundColor: roleColor,
                            foregroundColor: Colors.white,
                            child: Text(
                              user.name.isEmpty
                                  ? '?'
                                  : user.name.substring(0, 1).toUpperCase(),
                            ),
                          ),
                          title: Text(user.name),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: roleColor.withAlpha(22),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              strings.staffRoleLabel(user.role),
                              style: TextStyle(
                                color: roleColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerPinRecoveryDialog extends StatefulWidget {
  final AppStrings strings;
  final int initialPinLength;

  const _OwnerPinRecoveryDialog({
    required this.strings,
    required this.initialPinLength,
  });

  @override
  State<_OwnerPinRecoveryDialog> createState() =>
      _OwnerPinRecoveryDialogState();
}

class _OwnerPinRecoveryDialogState extends State<_OwnerPinRecoveryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  late int _pinLength = widget.initialPinLength;

  @override
  void dispose() {
    _codeController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s.resetOwnerPin),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: s.recoveryCodeLabel,
                  prefixIcon: const Icon(Icons.key_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? s.recoveryCodeLabel
                    : null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 4, label: Text(s.pinDigitsLabel(4))),
                  ButtonSegment(value: 6, label: Text(s.pinDigitsLabel(6))),
                ],
                selected: {_pinLength},
                onSelectionChanged: (selection) => setState(() {
                  _pinLength = selection.first;
                  _newPinController.clear();
                  _confirmPinController.clear();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: _pinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: s.newPinLabel,
                  prefixIcon: const Icon(Icons.password_rounded),
                ),
                validator: (value) =>
                    value == null ||
                        value.length != _pinLength ||
                        !RegExp(r'^\d+$').hasMatch(value)
                    ? s.pinFormatInvalid
                    : null,
              ),
              TextFormField(
                controller: _confirmPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: _pinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: s.confirmNewPinLabel,
                  prefixIcon: const Icon(Icons.password_rounded),
                ),
                validator: (value) =>
                    value != _newPinController.text ? s.pinsDoNotMatch : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.historyCancel),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              _codeController.text,
              _newPinController.text,
              _pinLength,
            ));
          },
          child: Text(s.resetOwnerPin),
        ),
      ],
    );
  }
}
