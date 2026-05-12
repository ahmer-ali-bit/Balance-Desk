import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/linked_devices/providers/linked_session_provider.dart';

/// A compact status indicator that shows the linked session state
/// in the app bar. Displays a small dot + label when linked.
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    LinkedSessionProvider? sp;
    try {
      sp = context.watch<LinkedSessionProvider>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    if (!sp.isLinked) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final isAdmin = sp.iAmAdmin;
    final color = isAdmin ? cs.primary : Colors.green;
    final label = isAdmin ? 'HOST' : 'LINKED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
