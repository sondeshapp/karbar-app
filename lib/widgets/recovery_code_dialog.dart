import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_strings.dart';

Future<void> showRecoveryCodeDialog({
  required BuildContext context,
  required AppStrings strings,
  required String code,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (dialogContext) => PopScope(
    canPop: false,
    child: AlertDialog(
      icon: const Icon(Icons.key_rounded, color: Color(0xFF2563EB), size: 30),
      title: Text(strings.recoveryCodeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(strings.recoveryCodeDescription, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withAlpha(16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2563EB).withAlpha(70)),
            ),
            child: SelectableText(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text(strings.recoveryCodeCopied)),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(strings.copyRecoveryCode),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(strings.recoveryCodeSaved),
        ),
      ],
    ),
  ),
);
