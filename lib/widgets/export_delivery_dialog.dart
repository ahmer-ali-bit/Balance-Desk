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
