import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/biometric_login_service.dart';

final biometricLoginProvider = Provider<BiometricLoginService>(
  (ref) => BiometricLoginService(),
);
