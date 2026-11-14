import 'dart:async';

import 'package:flutter/material.dart';

enum ExportDelivery { save, share }

Future<ExportDelivery?> showExportDeliveryDialog(BuildContext context) {
  return showDialog<ExportDelivery>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Export options'),
      content: const Text('Save a copy on this device or share the export.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              Navigator.of(dialogContext).pop(ExportDelivery.save),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Save'),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(dialogContext).pop(ExportDelivery.share),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share'),
        ),
      ],
    ),
  );
}

Future<T> withExportProgress<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() task,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: <Widget>[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 18),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    // Let the dialog paint before CPU-heavy PDF/CSV preparation begins.
    await WidgetsBinding.instance.endOfFrame;
    return await task();
  } finally {
    if (navigator.mounted && navigator.canPop()) {
      navigator.pop();
    }
  }
}
