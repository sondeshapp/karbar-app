import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricLoginService {
  final LocalAuthentication _authentication;
  final FlutterSecureStorage _storage;

  BiometricLoginService({
    LocalAuthentication? authentication,
    FlutterSecureStorage? storage,
  }) : _authentication = authentication ?? LocalAuthentication(),
       _storage = storage ?? const FlutterSecureStorage();

  Future<bool> isAvailable() async {
    try {
      return await _authentication.canCheckBiometrics &&
          (await _authentication.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled(int staffId) async =>
      await _storage.read(key: _keyFor(staffId)) == 'true';

  Future<bool> canUseFor(int staffId) async =>
      await isAvailable() && await isEnabled(staffId);

  Future<bool> enable(int staffId, String localizedReason) async {
    if (!await isAvailable()) return false;
    final authenticated = await _authentication.authenticate(
      localizedReason: localizedReason,
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
    if (!authenticated) return false;
    await _storage.write(key: _keyFor(staffId), value: 'true');
    return true;
  }

  Future<void> disable(int staffId) => _storage.delete(key: _keyFor(staffId));

  Future<bool> authenticate(String localizedReason) async {
    try {
      return await _authentication.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  String _keyFor(int staffId) => 'staff_biometric_login_$staffId';
}
