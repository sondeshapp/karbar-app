import 'package:flutter/material.dart';

import '../core/app_strings.dart';
import '../services/biometric_login_service.dart';

class BiometricLoginSettingsTile extends StatefulWidget {
  final int? staffId;
  final AppStrings strings;

  const BiometricLoginSettingsTile({
    super.key,
    required this.staffId,
    required this.strings,
  });

  @override
  State<BiometricLoginSettingsTile> createState() =>
      _BiometricLoginSettingsTileState();
}

class _BiometricLoginSettingsTileState
    extends State<BiometricLoginSettingsTile> {
  final BiometricLoginService _service = BiometricLoginService();
  bool? _available;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.staffId;
    var available = false;
    var enabled = false;
    try {
      available = id != null && await _service.isAvailable();
      enabled = id != null && await _service.isEnabled(id);
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    setState(() {
      _available = available;
      _enabled = enabled;
    });
  }

  Future<void> _setEnabled(bool value) async {
    final id = widget.staffId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      if (value) {
        final enabled = await _service.enable(
          id,
          widget.strings.biometricSetupReason,
        );
        if (enabled) {
          setState(() => _enabled = true);
        }
      } else {
        await _service.disable(id);
        setState(() => _enabled = false);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.strings.biometricLoginFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final available = _available;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.fingerprint_rounded),
        title: Text(strings.biometricLogin),
        subtitle: Text(
          available == null
              ? strings.pleaseWait
              : available
              ? _enabled
                    ? strings.biometricLoginEnabled
                    : strings.biometricLoginDescription
              : strings.biometricLoginUnavailable,
        ),
        trailing: available == null
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch.adaptive(
                value: _enabled,
                onChanged: available && !_busy ? _setEnabled : null,
              ),
      ),
    );
  }
}
