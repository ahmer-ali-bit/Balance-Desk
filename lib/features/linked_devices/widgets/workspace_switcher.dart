import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/linked_session_provider.dart';
import '../../../models/linked_device_models.dart';

/// A toggle widget that lets a linked guest switch between
/// their local workspace and the admin's linked workspace.
class WorkspaceSwitcher extends StatelessWidget {
  const WorkspaceSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<LinkedSessionProvider>();
    final cs = Theme.of(context).colorScheme;
    final isLinked = sp.workspaceMode == WorkspaceMode.linked;

    return Row(
      children: [
        Expanded(
          child: _ModeButton(
            label: 'Local',
            icon: Icons.storage_rounded,
            selected: !isLinked,
            cs: cs,
            onTap: () => sp.setWorkspaceMode(WorkspaceMode.local, context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeButton(
            label: 'Linked',
            icon: Icons.cloud_sync_rounded,
            selected: isLinked,
            cs: cs,
            onTap: () => sp.setWorkspaceMode(WorkspaceMode.linked, context),
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.cs,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final ColorScheme cs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? cs.primary : cs.onSurfaceVariant, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
