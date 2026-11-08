import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_strings.dart';
import '../../models/staff_role.dart';
import '../../models/staff_user.dart';
import '../../providers/settings_provider.dart';
import '../../providers/staff_activity_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/staff_roles_provider.dart';

class StaffActivityScreen extends ConsumerStatefulWidget {
  const StaffActivityScreen({super.key});

  @override
  ConsumerState<StaffActivityScreen> createState() =>
      _StaffActivityScreenState();
}

class _StaffActivityScreenState extends ConsumerState<StaffActivityScreen> {
  int? _staffId;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final activities = ref.watch(staffActivityProvider);
    final staff = ref.watch(staffListProvider);
    final roles =
        ref.watch(staffRolesProvider).valueOrNull ?? StaffRole.defaults;
    final dateFormat = DateFormat(
      'dd MMM yyyy · hh:mm a',
      strings.isBn ? 'bn_BD' : 'en_US',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.employeeActivity),
        actions: [
          IconButton(
            tooltip: strings.refresh,
            onPressed: () => ref.invalidate(staffActivityProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: staff.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => const SizedBox.shrink(),
              data: (users) => DropdownButtonFormField<int?>(
                initialValue: _staffId,
                decoration: InputDecoration(
                  labelText: strings.activityFilter,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(strings.activityAllStaff),
                  ),
                  for (final user in users)
                    DropdownMenuItem<int?>(
                      value: user.id,
                      child: Text(
                        '${user.name} · ${_roleName(user, roles, strings)}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _staffId = value),
              ),
            ),
          ),
          Expanded(
            child: activities.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text(strings.activityLoadFailed)),
              data: (items) {
                final visible = _staffId == null
                    ? items
                    : items.where((item) => item.staffId == _staffId).toList();
                if (visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        strings.activityEmpty,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final activity = visible[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            _iconFor(activity.action),
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          strings.staffActivityAction(activity.action),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(activity.staffName),
                            if (activity.summary.isNotEmpty)
                              Text(activity.summary),
                            Text(
                              dateFormat.format(activity.createdAt.toLocal()),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _roleName(StaffUser user, List<StaffRole> roles, AppStrings strings) {
    if (user.isOwner) return strings.staffOwnerRole;
    if (strings.isBn) {
      switch (user.role) {
        case 'cashier':
          return 'ক্যাশিয়ার';
        case 'inventory_manager':
          return 'ইনভেন্টরি ম্যানেজার';
        case 'accountant':
          return 'হিসাবরক্ষক';
      }
    }
    for (final role in roles) {
      if (role.id == user.role) return role.name;
    }
    return user.role;
  }

  IconData _iconFor(String action) => switch (action) {
    'sale_created' => Icons.point_of_sale_rounded,
    'sale_returned' => Icons.assignment_return_outlined,
    'product_added' ||
    'product_updated' ||
    'product_deleted' => Icons.inventory_2_outlined,
    'stock_received' => Icons.add_box_outlined,
    'purchase_recorded' ||
    'supplier_added' ||
    'supplier_updated' => Icons.shopping_bag_outlined,
    'customer_added' || 'baki_payment_recorded' => Icons.people_outline_rounded,
    'cash_close_saved' => Icons.account_balance_wallet_outlined,
    'signed_in' || 'signed_out' => Icons.lock_outline_rounded,
    _ => Icons.history_rounded,
  };
}
