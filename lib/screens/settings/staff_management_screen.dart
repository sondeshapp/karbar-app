import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_strings.dart';
import '../../db/database_helper.dart';
import '../../models/staff_user.dart';
import '../../providers/settings_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/staff_roles_provider.dart';
import '../../models/staff_role.dart';
import '../../widgets/recovery_code_dialog.dart';

class StaffManagementScreen extends ConsumerWidget {
  const StaffManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(activeStaffProvider);
    final s = ref.watch(stringsProvider);
    final roleDefinitions =
        ref.watch(staffRolesProvider).valueOrNull ?? const [];
    if (current?.isOwner != true) {
      return const Scaffold(
        body: Center(child: Text('Owner access is required.')),
      );
    }
    final staff = ref.watch(staffListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff access'),
        actions: [
          IconButton(
            tooltip: s.manageRoles,
            onPressed: () => context.push('/settings/staff/roles'),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: s.manageRecoveryCode,
            onPressed: () => _manageRecoveryCode(context, ref, current!, s),
            icon: const Icon(Icons.key_rounded),
          ),
          IconButton(
            tooltip: s.changeMyPin,
            onPressed: () => _changeMyPin(context, ref, current!, s),
            icon: const Icon(Icons.password_rounded),
          ),
          IconButton(
            tooltip: 'Lock and switch user',
            onPressed: () async {
              if (current?.id != null) {
                await DatabaseHelper().recordStaffActivity(
                  staffId: current!.id!,
                  action: 'signed_out',
                  entityType: 'session',
                  summary: 'Signed out',
                );
              }
              if (!context.mounted) return;
              ref.read(activeStaffProvider.notifier).state = null;
              context.go('/');
            },
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addStaff(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add staff'),
      ),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load staff: $error')),
        data: (users) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('PINs are stored as salted hashes on this device.'),
            ),
            for (final user in users)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer,
                    child: Icon(
                      user.isOwner
                          ? Icons.admin_panel_settings
                          : Icons.point_of_sale,
                    ),
                  ),
                  title: Text(user.name),
                  subtitle: Text(
                    '${_roleName(user.role, roleDefinitions, s)} · ${user.active ? 'Active' : 'Disabled'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: s.roleManagement,
                        icon: const Icon(Icons.manage_accounts_outlined),
                        onPressed: user.isOwner
                            ? null
                            : () => _changeRole(context, ref, user, s),
                      ),
                      IconButton(
                        tooltip: 'Reset PIN',
                        icon: const Icon(Icons.password_outlined),
                        onPressed: () => _resetPin(context, ref, user),
                      ),
                      if (user.id == current?.id)
                        const Chip(label: Text('You'))
                      else
                        Switch(
                          value: user.active,
                          onChanged: (active) =>
                              _setActive(context, ref, user, active),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addStaff(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final name = TextEditingController();
    final pin = TextEditingController();
    final roles = await ref.read(staffRolesProvider.future);
    if (!context.mounted) {
      name.dispose();
      pin.dispose();
      return;
    }
    var role = 'cashier';
    var pinLength = 4;
    final result = await showDialog<(String, String, String, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add staff account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final item in roles)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(_roleName(item.id, roles, s)),
                    ),
                  DropdownMenuItem(value: 'owner', child: Text('Owner')),
                ],
                onChanged: (value) => setState(() => role = value ?? 'cashier'),
              ),
              const SizedBox(height: 12),
              _pinLengthSelector(s, pinLength, (value) {
                setState(() {
                  pinLength = value;
                  pin.clear();
                });
              }),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: pinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: s.newPinLabel),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                name.text,
                role,
                pin.text,
                pinLength,
              )),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    pin.dispose();
    if (result == null) return;
    try {
      await ref
          .read(staffProvider)
          .create(
            name: result.$1,
            role: result.$2,
            pin: result.$3,
            pinLength: result.$4,
          );
      ref.invalidate(staffListProvider);
      ref.invalidate(activeStaffListProvider);
      if (context.mounted) _message(context, 'Staff account added.');
    } catch (error) {
      if (context.mounted) _message(context, _localizedErrorText(error, s));
    }
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    StaffUser user,
    AppStrings strings,
  ) async {
    final roles = await ref.read(staffRolesProvider.future);
    if (!context.mounted) return;
    var selected = user.role;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(strings.roleManagement),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            items: [
              for (final role in roles)
                DropdownMenuItem(
                  value: role.id,
                  child: Text(_roleName(role.id, roles, strings)),
                ),
              const DropdownMenuItem(value: 'owner', child: Text('Owner')),
            ],
            onChanged: (value) => setState(() => selected = value ?? selected),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.historyCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: Text(strings.save),
            ),
          ],
        ),
      ),
    );
    if (result == null || result == user.role) return;
    try {
      await ref.read(staffProvider).setRole(user.id!, result);
      ref.invalidate(staffListProvider);
      ref.invalidate(activeStaffListProvider);
      if (user.id == ref.read(activeStaffProvider)?.id) {
        ref.read(activeStaffProvider.notifier).state = null;
        if (context.mounted) context.go('/');
      }
    } catch (error) {
      if (context.mounted) _message(context, _errorText(error));
    }
  }

  String _roleName(String id, List<StaffRole> roles, AppStrings strings) {
    if (strings.isBn) {
      switch (id) {
        case 'owner':
          return 'মালিক';
        case 'cashier':
          return 'ক্যাশিয়ার';
        case 'inventory_manager':
          return 'ইনভেন্টরি ম্যানেজার';
        case 'accountant':
          return 'হিসাবরক্ষক';
      }
    }
    return roles.where((role) => role.id == id).firstOrNull?.name ?? 'Owner';
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    StaffUser user,
    bool active,
  ) async {
    try {
      await ref.read(staffProvider).setActive(user.id!, active);
      ref.invalidate(staffListProvider);
      ref.invalidate(activeStaffListProvider);
    } catch (error) {
      if (context.mounted) _message(context, _errorText(error));
    }
  }

  Future<void> _resetPin(
    BuildContext context,
    WidgetRef ref,
    StaffUser user,
  ) async {
    final controller = TextEditingController();
    final s = ref.read(stringsProvider);
    var pinLength = user.pinLength == 6 ? 6 : 4;
    final values = await showDialog<(String, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Reset ${user.name}’s PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pinLengthSelector(s, pinLength, (value) {
                setState(() {
                  pinLength = value;
                  controller.clear();
                });
              }),
              TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: pinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: s.newPinLabel),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(s.historyCancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, (controller.text, pinLength)),
              child: Text(s.resetOwnerPin),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (values == null) return;
    try {
      await ref
          .read(staffProvider)
          .resetPin(user.id!, values.$1, pinLength: values.$2);
      ref.invalidate(staffListProvider);
      ref.invalidate(activeStaffListProvider);
      if (context.mounted) _message(context, s.pinChanged);
    } catch (error) {
      if (context.mounted) _message(context, _localizedErrorText(error, s));
    }
  }

  Future<void> _changeMyPin(
    BuildContext context,
    WidgetRef ref,
    StaffUser current,
    AppStrings s,
  ) async {
    final formKey = GlobalKey<FormState>();
    final currentPin = TextEditingController();
    final newPin = TextEditingController();
    final confirmPin = TextEditingController();
    var pinLength = current.pinLength == 6 ? 6 : 4;
    final values = await showDialog<(String, String, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.changeMyPin),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pinInput(currentPin, s.currentPinLabel, s),
                  const SizedBox(height: 10),
                  _pinLengthSelector(s, pinLength, (value) {
                    setState(() {
                      pinLength = value;
                      newPin.clear();
                      confirmPin.clear();
                    });
                  }),
                  const SizedBox(height: 10),
                  _pinInput(
                    newPin,
                    s.newPinLabel,
                    s,
                    maxLength: pinLength,
                    validateFormat: true,
                    requiredLength: pinLength,
                  ),
                  const SizedBox(height: 10),
                  _pinInput(
                    confirmPin,
                    s.confirmNewPinLabel,
                    s,
                    maxLength: pinLength,
                    validate: (value) =>
                        value != newPin.text ? s.pinsDoNotMatch : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(s.historyCancel),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, (
                  currentPin.text,
                  newPin.text,
                  pinLength,
                ));
              },
              child: Text(s.changeMyPin),
            ),
          ],
        ),
      ),
    );
    currentPin.dispose();
    newPin.dispose();
    confirmPin.dispose();
    if (values == null) return;

    try {
      final changed = await ref
          .read(staffProvider)
          .changePin(
            staffId: current.id!,
            currentPin: values.$1,
            newPin: values.$2,
            newPinLength: values.$3,
          );
      if (!context.mounted) return;
      if (!changed) {
        _message(context, s.currentPinIncorrect);
      } else {
        ref.invalidate(staffListProvider);
        ref.invalidate(activeStaffListProvider);
        _message(context, s.pinChanged);
      }
    } catch (error) {
      if (context.mounted) {
        _message(
          context,
          error is ArgumentError
              ? s.pinFormatInvalid
              : s.staffAccountSaveFailed,
        );
      }
    }
  }

  Widget _pinInput(
    TextEditingController controller,
    String label,
    AppStrings s, {
    bool validateFormat = false,
    int maxLength = 8,
    int? requiredLength,
    String? Function(String?)? validate,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    obscureText: true,
    maxLength: maxLength,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.password_rounded),
    ),
    validator:
        validate ??
        (value) =>
            validateFormat &&
                (value == null ||
                    value.length != (requiredLength ?? 4) ||
                    !RegExp(r'^\d+$').hasMatch(value))
            ? s.pinFormatInvalid
            : null,
  );

  Widget _pinLengthSelector(
    AppStrings strings,
    int selectedLength,
    ValueChanged<int> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(strings.pinLengthLabel),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 4, label: Text(strings.pinDigitsLabel(4))),
          ButtonSegment(value: 6, label: Text(strings.pinDigitsLabel(6))),
        ],
        selected: {selectedLength},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    ],
  );

  Future<void> _manageRecoveryCode(
    BuildContext context,
    WidgetRef ref,
    StaffUser current,
    AppStrings s,
  ) async {
    final pin = TextEditingController();
    final confirmedPin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.manageRecoveryCode),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.recoveryCodeSetupDescription),
            const SizedBox(height: 14),
            TextField(
              controller: pin,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: s.currentPinLabel,
                prefixIcon: const Icon(Icons.password_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.historyCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, pin.text),
            child: Text(s.manageRecoveryCode),
          ),
        ],
      ),
    );
    pin.dispose();
    if (confirmedPin == null || !context.mounted) return;

    try {
      final owner = await ref
          .read(staffProvider)
          .authenticate(current.id!, confirmedPin);
      if (!context.mounted) return;
      if (owner == null) {
        _message(context, s.currentPinIncorrect);
        return;
      }
      final code = await ref
          .read(staffProvider)
          .createOwnerRecoveryCode(ownerStaffId: current.id!);
      if (context.mounted) {
        await showRecoveryCodeDialog(context: context, strings: s, code: code);
      }
    } catch (error) {
      if (context.mounted) {
        _message(
          context,
          error is ArgumentError
              ? s.pinFormatInvalid
              : s.recoveryCodeSaveFailed,
        );
      }
    }
  }

  void _message(BuildContext context, String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  String _errorText(Object error) => error is ArgumentError
      ? error.message.toString()
      : error is StateError
      ? error.message
      : 'Could not update staff account.';

  String _localizedErrorText(Object error, AppStrings strings) =>
      error is ArgumentError && error.message.toString().startsWith('PIN')
      ? strings.pinFormatInvalid
      : _errorText(error);
}
