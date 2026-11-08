import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_helper.dart';
import '../models/staff_role.dart';
import '../models/staff_user.dart';

final staffRolesProvider = FutureProvider<List<StaffRole>>(
  (ref) => StaffRoleAccess().list(),
);
final staffRoleAccessProvider = Provider<StaffRoleAccess>(
  (ref) => StaffRoleAccess(),
);

final class StaffRoleAccess {
  static const _storageKey = 'staff_role_definitions';
  final DatabaseHelper _db;

  StaffRoleAccess({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  Future<List<StaffRole>> list() async {
    final settings = await _db.getAppSettings();
    final encoded = settings[_storageKey];
    if (encoded == null || encoded.isEmpty) return StaffRole.defaults;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return StaffRole.defaults;
      final saved = decoded
          .whereType<Map>()
          .map((item) => StaffRole.fromJson(Map<String, dynamic>.from(item)))
          .where((role) => role.id != 'owner')
          .toList();
      final byId = {for (final role in saved) role.id: role};
      for (final builtIn in StaffRole.defaults) {
        byId.putIfAbsent(builtIn.id, () => builtIn);
      }
      return byId.values.toList()..sort((a, b) {
        if (a.builtIn != b.builtIn) return a.builtIn ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } catch (_) {
      return StaffRole.defaults;
    }
  }

  Future<void> save(StaffRole role, {required bool creating}) async {
    if (role.id == 'owner' || role.name.trim().isEmpty) {
      throw ArgumentError('Enter a valid role name.');
    }
    final roles = await list();
    final existing = roles.where((item) => item.id == role.id).firstOrNull;
    if (creating) {
      if (existing != null ||
          roles.any(
            (item) => item.name.toLowerCase() == role.name.trim().toLowerCase(),
          )) {
        throw ArgumentError('A role with this name already exists.');
      }
      if (!RegExp(r'^[a-z][a-z0-9_]{1,47}$').hasMatch(role.id)) {
        throw ArgumentError('Role ID is invalid.');
      }
    } else if (existing == null) {
      throw StateError('Role no longer exists.');
    } else if (roles.any(
      (item) =>
          item.id != role.id &&
          item.name.toLowerCase() == role.name.trim().toLowerCase(),
    )) {
      throw ArgumentError('A role with this name already exists.');
    }
    final updated = roles
        .map(
          (item) => item.id == role.id
              ? StaffRole(
                  id: item.id,
                  name: item.builtIn ? item.name : role.name.trim(),
                  permissions: role.permissions,
                  builtIn: item.builtIn,
                )
              : item,
        )
        .toList();
    if (creating) {
      updated.add(role.copyWith(name: role.name.trim()));
    }
    await _write(updated);
  }

  Future<void> delete(String roleId, {required bool inUse}) async {
    final role = (await list()).where((item) => item.id == roleId);
    if (role.isEmpty || role.first.builtIn) {
      throw StateError('Built-in roles cannot be deleted.');
    }
    if (inUse) throw StateError('Reassign staff before deleting this role.');
    await _write((await list()).where((item) => item.id != roleId).toList());
  }

  Future<void> _write(List<StaffRole> roles) async {
    final settings = await _db.getAppSettings();
    settings[_storageKey] = jsonEncode(
      roles.map((role) => role.toJson()).toList(),
    );
    await _db.saveAppSettings(settings);
  }
}

bool staffHasPermission(
  StaffUser? staff,
  List<StaffRole> roles,
  String permission,
) {
  if (staff == null) return false;
  if (staff.isOwner) return true;
  return roles
      .where((role) => role.id == staff.role)
      .any((role) => role.permissions.contains(permission));
}
