import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_strings.dart';
import '../providers/staff_provider.dart';
import '../providers/staff_roles_provider.dart';
import '../providers/settings_provider.dart';

class StaffPermissionGate extends ConsumerWidget {
  final List<String> anyOf;
  final Widget child;

  const StaffPermissionGate({
    super.key,
    required this.anyOf,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(activeStaffProvider);
    if (staff?.isOwner == true) return child;
    final strings = ref.watch(stringsProvider);
    final roles = ref.watch(staffRolesProvider);
    return roles.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => _denied(context, strings),
      data: (items) =>
          anyOf.any(
            (permission) => staffHasPermission(staff, items, permission),
          )
          ? child
          : _denied(context, strings),
    );
  }

  Widget _denied(BuildContext context, AppStrings strings) => Scaffold(
    appBar: AppBar(title: Text(strings.accessDeniedTitle)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(strings.accessDeniedMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
              child: Text(strings.goBack),
            ),
          ],
        ),
      ),
    ),
  );
}
