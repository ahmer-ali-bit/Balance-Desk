import 'package:flutter/material.dart';

/// Placeholder for sync status indicator (linked devices feature removed).
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
