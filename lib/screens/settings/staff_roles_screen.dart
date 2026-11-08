import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_strings.dart';
import '../../models/staff_role.dart';
import '../../providers/staff_provider.dart';
import '../../providers/staff_roles_provider.dart';
import '../../providers/settings_provider.dart';

class StaffRolesScreen extends ConsumerWidget {
  const StaffRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(staffRolesProvider);
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.roleManagement)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editRole(context, ref, strings),
        icon: const Icon(Icons.add),
        label: Text(strings.customRole),
      ),
      body: roles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(strings.roleSaveFailed)),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            for (final role in items)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      role.builtIn ? Icons.badge_outlined : Icons.tune,
                    ),
                  ),
                  title: Text(_roleName(role, strings)),
                  subtitle: Text(
                    '${role.builtIn ? strings.builtInRole : strings.customRole} · '
                    '${role.permissions.length}/${StaffPermission.all.length} ${strings.permissionsLabel.toLowerCase()}',
                  ),
                  onTap: () => _editRole(context, ref, strings, role),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: strings.permissionsLabel,
                        onPressed: () => _editRole(context, ref, strings, role),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      if (!role.builtIn)
                        IconButton(
                          tooltip: strings.historyCancel,
                          onPressed: () =>
                              _deleteRole(context, ref, strings, role),
                          icon: const Icon(Icons.delete_outline),
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

  Future<void> _editRole(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings, [
    StaffRole? role,
  ]) async {
    final result = await showDialog<StaffRole>(
      context: context,
      builder: (context) => _RoleEditor(role: role, strings: strings),
    );
    if (result == null) return;
    try {
      await ref
          .read(staffRoleAccessProvider)
          .save(result, creating: role == null);
      ref.invalidate(staffRolesProvider);
      if (context.mounted) _message(context, strings.roleSaved);
    } catch (error) {
      if (context.mounted) {
        _message(
          context,
          error is ArgumentError
              ? error.message.toString()
              : strings.roleSaveFailed,
        );
      }
    }
  }

  Future<void> _deleteRole(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
    StaffRole role,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteRole),
        content: Text(strings.deleteRoleConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.historyCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.deleteRole),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final staff = await ref.read(staffProvider).list();
      final inUse = staff.any((person) => person.role == role.id);
      await ref.read(staffRoleAccessProvider).delete(role.id, inUse: inUse);
      ref.invalidate(staffRolesProvider);
      if (context.mounted) _message(context, strings.roleDeleted);
    } catch (error) {
      if (context.mounted) {
        _message(
          context,
          error is StateError ? strings.roleInUse : strings.roleSaveFailed,
        );
      }
    }
  }

  String _roleName(StaffRole role, AppStrings strings) {
    if (!strings.isBn) return role.name;
    return switch (role.id) {
      'cashier' => 'ক্যাশিয়ার',
      'inventory_manager' => 'ইনভেন্টরি ম্যানেজার',
      'accountant' => 'হিসাবরক্ষক',
      _ => role.name,
    };
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RoleEditor extends StatefulWidget {
  final StaffRole? role;
  final AppStrings strings;

  const _RoleEditor({required this.role, required this.strings});

  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<_RoleEditor> {
  late final TextEditingController _name;
  late final Set<String> _permissions;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.role?.name ?? '');
    _permissions = {...?widget.role?.permissions};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final strings = widget.strings;
    return AlertDialog(
      title: Text(role == null ? strings.customRole : role.name),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (role == null || !role.builtIn)
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: strings.roleName),
                ),
              const SizedBox(height: 12),
              Text(
                strings.permissionsLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final permission in StaffPermission.all)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_permissionName(permission, strings)),
                  value: _permissions.contains(permission),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _permissions.add(permission);
                    } else {
                      _permissions.remove(permission);
                    }
                  }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.historyCancel),
        ),
        FilledButton(
          onPressed: () {
            final name = role?.name ?? _name.text.trim();
            final id = role?.id ?? _roleId(name);
            if (name.isEmpty || id.isEmpty) return;
            Navigator.pop(
              context,
              StaffRole(
                id: id,
                name: name,
                permissions: _permissions,
                builtIn: role?.builtIn ?? false,
              ),
            );
          },
          child: Text(strings.save),
        ),
      ],
    );
  }

  String _roleId(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  String _permissionName(String id, AppStrings strings) => switch (id) {
    StaffPermission.pos => strings.permissionPos,
    StaffPermission.dashboard => strings.permissionDashboard,
    StaffPermission.inventory => strings.permissionInventory,
    StaffPermission.purchases => strings.permissionPurchases,
    StaffPermission.history => strings.permissionHistory,
    StaffPermission.customerCredit => strings.permissionCustomerCredit,
    StaffPermission.reports => strings.permissionReports,
    StaffPermission.cashClose => strings.permissionCashClose,
    _ => id,
  };
}
