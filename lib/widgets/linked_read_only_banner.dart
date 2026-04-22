import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/linked_devices_controller.dart';

class LinkedReadOnlyBanner extends StatelessWidget {
  const LinkedReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller =
        context.watch<LinkedDevicesController?>() ??
        LinkedDevicesController.instance;
    if (!controller.isReadOnlyLinkedDevice) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.remove_red_eye_outlined,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              controller.readOnlyMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
