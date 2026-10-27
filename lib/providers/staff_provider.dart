import 'dart:math';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_helper.dart';
import '../models/staff_user.dart';

final staffProvider = Provider<StaffAccess>((ref) => StaffAccess());

final activeStaffProvider = StateProvider<StaffUser?>((ref) => null);

final hasStaffAccountsProvider = FutureProvider<bool>(
  (ref) => ref.watch(staffProvider).hasAccounts(),
);

final staffListProvider = FutureProvider<List<StaffUser>>(
  (ref) => ref.watch(staffProvider).list(),
);

final activeStaffListProvider = FutureProvider<List<StaffUser>>(
  (ref) => ref.watch(staffProvider).list(activeOnly: true),
);

class OwnerRecoveryLocked implements Exception {}

class OwnerRecoveryNotConfigured implements Exception {}

class StaffAccess {
  final DatabaseHelper _db;
  StaffAccess({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  Future<List<StaffUser>> list({bool activeOnly = false}) =>
      _db.getStaffUsers(activeOnly: activeOnly);

  Future<bool> hasAccounts() async => (await _db.getStaffUsers()).isNotEmpty;

  Future<int> create({
    required String name,
    required String role,
    required String pin,
    int? pinLength,
  }) async {
    final selectedPinLength = pinLength ?? pin.length;
    _validatePin(pin, selectedPinLength);
    if (name.trim().isEmpty || !{'owner', 'cashier'}.contains(role)) {
      throw ArgumentError('Enter a name and choose a valid staff role.');
    }
    if ((await _db.getStaffUsers()).isEmpty && role != 'owner') {
      throw StateError('The first staff account must be an owner.');
    }
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final salt = _toHex(bytes);
    final hash = _hash(pin, salt);
    return _db.insertStaffUser(
      name: name,
      role: role,
      pinSalt: salt,
      pinHash: hash,
      pinLength: selectedPinLength,
    );
  }

  Future<StaffUser?> authenticate(int id, String pin) async {
    _validateLoginPin(pin);
    for (final staff in await _db.getStaffUsers(activeOnly: true)) {
      if (staff.id == id &&
          (staff.pinLength == 0 || staff.pinLength == pin.length) &&
          _constantTimeEquals(_hash(pin, staff.pinSalt), staff.pinHash)) {
        if (staff.pinLength == 0) {
          final knownLength = {4, 6}.contains(pin.length) ? pin.length : 0;
          if (knownLength != 0) {
            await _db.updateStaffPinLength(id, knownLength);
          }
          return StaffUser(
            id: staff.id,
            syncId: staff.syncId,
            name: staff.name,
            role: staff.role,
            pinSalt: staff.pinSalt,
            pinHash: staff.pinHash,
            pinLength: knownLength,
            active: staff.active,
            createdAt: staff.createdAt,
          );
        }
        return staff;
      }
    }
    return null;
  }

  Future<void> setActive(int id, bool active) =>
      _db.setStaffUserActive(id, active);

  Future<void> resetPin(int id, String pin, {int? pinLength}) async {
    final selectedPinLength = pinLength ?? pin.length;
    _validatePin(pin, selectedPinLength);
    final salt = _toHex(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    await _db.updateStaffPin(id, salt, _hash(pin, salt), selectedPinLength);
  }

  Future<bool> changePin({
    required int staffId,
    required String currentPin,
    required String newPin,
    int? newPinLength,
  }) async {
    final selectedPinLength = newPinLength ?? newPin.length;
    _validatePin(newPin, selectedPinLength);
    final staff = await authenticate(staffId, currentPin);
    if (staff == null) return false;
    await resetPin(staffId, newPin, pinLength: selectedPinLength);
    return true;
  }

  Future<bool> hasOwnerRecoveryCodeFor(int ownerStaffId) async {
    final settings = await _db.getAppSettings();
    return (settings['owner_recovery_salt'] ?? '').isNotEmpty &&
        (settings['owner_recovery_hash'] ?? '').isNotEmpty &&
        settings['owner_recovery_staff_id'] == '$ownerStaffId';
  }

  Future<String> createOwnerRecoveryCode({required int ownerStaffId}) async {
    final owner = (await list()).where((staff) => staff.id == ownerStaffId);
    if (owner.isEmpty || !owner.first.isOwner) {
      throw StateError('Create an owner account before setting recovery.');
    }
    final alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final code = List.generate(
      20,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    final salt = _toHex(List<int>.generate(16, (_) => random.nextInt(256)));
    final settings = await _db.getAppSettings();
    settings.addAll({
      'owner_recovery_salt': salt,
      'owner_recovery_hash': _hash(code, salt),
      'owner_recovery_staff_id': '$ownerStaffId',
      'owner_recovery_attempts': '0',
      'owner_recovery_locked_until': '',
    });
    await _db.saveAppSettings(settings);
    return code
        .replaceAllMapped(RegExp(r'.{4}'), (match) => '${match.group(0)}-')
        .replaceFirst(RegExp(r'-$'), '');
  }

  Future<StaffUser?> recoverOwnerPin({
    required String recoveryCode,
    required String newPin,
    int? newPinLength,
  }) async {
    final selectedPinLength = newPinLength ?? newPin.length;
    _validatePin(newPin, selectedPinLength);
    final settings = await _db.getAppSettings();
    final salt = settings['owner_recovery_salt'] ?? '';
    final storedHash = settings['owner_recovery_hash'] ?? '';
    if (salt.isEmpty || storedHash.isEmpty) {
      throw OwnerRecoveryNotConfigured();
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lockedUntil = int.tryParse(
      settings['owner_recovery_locked_until'] ?? '',
    );
    if (lockedUntil != null && lockedUntil > now) {
      throw OwnerRecoveryLocked();
    }

    final normalized = recoveryCode.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    if (!_constantTimeEquals(_hash(normalized, salt), storedHash)) {
      final attempts =
          (int.tryParse(settings['owner_recovery_attempts'] ?? '') ?? 0) + 1;
      settings['owner_recovery_attempts'] = attempts >= 5 ? '0' : '$attempts';
      if (attempts >= 5) {
        settings['owner_recovery_locked_until'] =
            '${now + const Duration(minutes: 5).inMilliseconds}';
      }
      await _db.saveAppSettings(settings);
      if (attempts >= 5) throw OwnerRecoveryLocked();
      return null;
    }

    final ownerId = int.tryParse(settings['owner_recovery_staff_id'] ?? '');
    if (ownerId == null) throw OwnerRecoveryNotConfigured();
    final owner = (await _db.getStaffUsers(
      activeOnly: true,
    )).where((staff) => staff.id == ownerId && staff.isOwner);
    if (owner.isEmpty) throw OwnerRecoveryNotConfigured();
    final ownerUser = owner.first;
    await resetPin(ownerUser.id!, newPin, pinLength: selectedPinLength);

    // A recovery code can reset the owner PIN only once.
    settings.addAll({
      'owner_recovery_salt': '',
      'owner_recovery_hash': '',
      'owner_recovery_staff_id': '',
      'owner_recovery_attempts': '0',
      'owner_recovery_locked_until': '',
    });
    await _db.saveAppSettings(settings);
    return authenticate(ownerUser.id!, newPin);
  }

  static String _hash(String pin, String salt) {
    const rounds = 20000;
    final hmac = Hmac(sha256, utf8.encode(pin));
    final saltAndBlock = [...utf8.encode(salt), 0, 0, 0, 1];
    var block = hmac.convert(saltAndBlock).bytes;
    final result = List<int>.from(block);
    for (var round = 1; round < rounds; round++) {
      block = hmac.convert(block).bytes;
      for (var index = 0; index < result.length; index++) {
        result[index] ^= block[index];
      }
    }
    return _toHex(result);
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  static void _validatePin(String pin, int pinLength) {
    if (!{4, 6}.contains(pinLength) ||
        pin.length != pinLength ||
        !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('PIN must contain exactly 4 or 6 digits.');
    }
  }

  static void _validateLoginPin(String pin) {
    if (!{4, 6}.contains(pin.length) || !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('PIN must contain exactly 4 or 6 digits.');
    }
  }
}
