import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/link_invite.dart';
import '../models/linked_device.dart';
import '../providers/linked_devices_provider.dart';
import '../services/app_deep_link_service.dart';
import '../services/sync/sync_engine.dart';
import '../utils/platform_helper.dart';

/// Linked Devices: pair this device with others, see who is connected and
/// manage who may edit the ledger.
///
/// Mobile-first layout — desktop gets the same screen but QR *scanning* is
/// only offered where a camera exists ([PlatformHelper.supportsQrScanner]);
/// everywhere else the paste-a-link path is the primary one.
class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  final TextEditingController _inviteInputController = TextEditingController();

  @override
  void dispose() {
    _inviteInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LinkedDevicesProvider provider =
        context.watch<LinkedDevicesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Devices'),
        actions: <Widget>[
          if (provider.isLinked)
            IconButton(
              tooltip: 'Sync now',
              icon: const Icon(Icons.refresh),
              onPressed: provider.isBusy ? null : () => provider.syncNow(),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _StatusCard(provider: provider),
            const SizedBox(height: 12),
            if (!provider.isFirebaseConfigured) ...<Widget>[
              const _NotConfiguredCard(),
              const SizedBox(height: 12),
            ],
            if (provider.hasPendingLink) ...<Widget>[
              _PendingInviteBanner(provider: provider),
              const SizedBox(height: 12),
            ],
            if (provider.isLinked) ...<Widget>[
              _InviteCard(provider: provider),
              const SizedBox(height: 16),
              _DeviceListCard(provider: provider),
              const SizedBox(height: 16),
              _DangerZoneCard(provider: provider),
            ] else ...<Widget>[
              _StartSharingCard(provider: provider),
              const SizedBox(height: 16),
              _JoinCard(
                provider: provider,
                controller: _inviteInputController,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ status

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.provider});

  final LinkedDevicesProvider provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final (IconData icon, Color color, String label) = switch (provider.status) {
      SyncStatus.disabled => (
          Icons.cloud_off_outlined,
          colors.outline,
          'Not available'
        ),
      SyncStatus.idle => (Icons.link_off, colors.outline, 'Not linked'),
      SyncStatus.synced => (Icons.cloud_done, Colors.green, 'Up to date'),
      SyncStatus.syncing => (Icons.sync, colors.primary, 'Syncing…'),
      SyncStatus.offline => (
          Icons.cloud_queue,
          Colors.orange,
          'Waiting for connection'
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
                if (provider.status == SyncStatus.syncing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              provider.statusMessage ??
                  (provider.isLinked
                      ? 'Changes on any linked device appear here automatically.'
                      : 'Link another device to keep this ledger in sync.'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text(
              'This device: ${provider.deviceName}  •  id ${provider.deviceId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (provider.isLinked) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Workspace: ${provider.workspaceId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pending uploads: ${provider.pendingCount}  •  '
                'applied from others: ${provider.appliedCount}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotConfiguredCard extends StatelessWidget {
  const _NotConfiguredCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Firebase is not configured in this build',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The ledger works fully offline. To enable Linked Devices, '
              'rebuild with FIREBASE_API_KEY, FIREBASE_PROJECT_ID and '
              'FIREBASE_APP_ID_<PLATFORM> dart-defines — see '
              'docs/firebase_auth_setup.md.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingInviteBanner extends StatelessWidget {
  const _PendingInviteBanner({required this.provider});

  final LinkedDevicesProvider provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Invite link received',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              provider.pendingLink!.rawLink,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton(
                  onPressed: provider.isBusy
                      ? null
                      : () => _accept(context, provider),
                  child: const Text('Accept & link'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: provider.dismissPendingLink,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(
    BuildContext context,
    LinkedDevicesProvider provider,
  ) async {
    final bool ok = await provider.acceptPendingLink();
    if (!context.mounted) {
      return;
    }
    _showResult(context, provider, ok);
  }
}

// --------------------------------------------------------- start / invite

class _StartSharingCard extends StatelessWidget {
  const _StartSharingCard({required this.provider});

  final LinkedDevicesProvider provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Share this ledger', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Become the owner of a shared workspace. Your existing '
              'customers, entries and summaries are published so the device '
              'you invite starts with the same data.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed:
                  provider.isBusy || !provider.isFirebaseConfigured
                      ? null
                      : () => _start(context, provider),
              icon: const Icon(Icons.hub_outlined),
              label: const Text('Start sharing'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(
    BuildContext context,
    LinkedDevicesProvider provider,
  ) async {
    final bool ok = await provider.startSharing();
    if (!context.mounted) {
      return;
    }
    _showResult(context, provider, ok);
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.provider});

  final LinkedDevicesProvider provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LinkInvite? invite = provider.activeInvite;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Invite a device', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              provider.canManageDevices
                  ? 'New devices join as view-only. You can grant edit access afterwards.'
                  : 'Only the owner can create invite links.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: provider.isBusy || !provider.canManageDevices
                      ? null
                      : () => _create(context, provider, DeviceRole.viewer),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Invite (view only)'),
                ),
                OutlinedButton.icon(
                  onPressed: provider.isBusy || !provider.canManageDevices
                      ? null
                      : () => _create(context, provider, DeviceRole.editor),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Invite (can edit)'),
                ),
              ],
            ),
            if (invite != null) ...<Widget>[
              const Divider(height: 24),
              _InviteDetails(invite: invite, provider: provider),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    LinkedDevicesProvider provider,
    DeviceRole role,
  ) async {
    final LinkInvite? invite = await provider.createInvite(role: role);
    if (!context.mounted) {
      return;
    }
    if (invite == null) {
      _showResult(context, provider, false);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Invite ready — valid for ${invite.remainingUses} device(s).',
        ),
      ),
    );
  }
}

class _InviteDetails extends StatelessWidget {
  const _InviteDetails({required this.invite, required this.provider});

  final LinkInvite invite;
  final LinkedDevicesProvider provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool expired = !invite.isUsable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              expired ? Icons.timer_off : Icons.timer_outlined,
              size: 18,
              color: expired ? theme.colorScheme.error : null,
            ),
            const SizedBox(width: 6),
            Text(
              expired
                  ? 'Invite expired or fully used'
                  : 'Expires ${_formatExpiry(invite.expiresAt)} • '
                      '${invite.remainingUses} of ${invite.maxUses} uses left',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!expired)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: invite.inviteLink,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        const SizedBox(height: 12),
        SelectableText(
          invite.inviteLink,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () => _copy(context, invite.inviteLink),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy link'),
            ),
            if (!expired)
              TextButton.icon(
                onPressed: provider.isBusy ? null : provider.revokeActiveInvite,
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Revoke'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied')),
    );
  }

  static String _formatExpiry(DateTime expiry) {
    final Duration remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) {
      return 'now';
    }
    if (remaining.inMinutes < 60) {
      return 'in ${remaining.inMinutes} min';
    }
    return 'in ${remaining.inHours} h';
  }
}

// --------------------------------------------------------------- joining

class _JoinCard extends StatelessWidget {
  const _JoinCard({
    required this.provider,
    required this.controller,
  });

  final LinkedDevicesProvider provider;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Join a shared ledger', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Paste the invite link the owner shared, or scan its QR code.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Invite link',
                hintText: 'balancedesk://link-device?w=…&t=…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: provider.isBusy || !provider.isFirebaseConfigured
                      ? null
                      : () => _join(context, provider, controller.text),
                  icon: const Icon(Icons.link),
                  label: const Text('Join'),
                ),
                if (PlatformHelper.supportsQrScanner)
                  OutlinedButton.icon(
                    onPressed: provider.isBusy || !provider.isFirebaseConfigured
                        ? null
                        : () => _scan(context, provider),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _join(
    BuildContext context,
    LinkedDevicesProvider provider,
    String input,
  ) async {
    final bool ok = await provider.joinFromUserInput(input: input);
    if (!context.mounted) {
      return;
    }
    _showResult(context, provider, ok);
  }

  Future<void> _scan(
    BuildContext context,
    LinkedDevicesProvider provider,
  ) async {
    final String? scanned = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _QrScanDialog(),
    );
    if (scanned == null || scanned.isEmpty) {
      return;
    }
    final bool ok = await provider.joinFromUserInput(input: scanned);
    if (!context.mounted) {
      return;
    }
    _showResult(context, provider, ok);
  }
}

class _QrScanDialog extends StatefulWidget {
  const _QrScanDialog();

  @override
  State<_QrScanDialog> createState() => _QrScanDialogState();
}

class _QrScanDialogState extends State<_QrScanDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan invite QR'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: MobileScanner(
          controller: _controller,
          onDetect: (BarcodeCapture capture) {
            for (final Barcode barcode in capture.barcodes) {
              final String? value = barcode.rawValue;
              if (value == null || value.isEmpty) {
                continue;
              }
              final PendingInviteLink? invite =
                  AppDeepLinkService.parseInviteLink(value);
              if (invite == null) {
                continue;
              }
              Navigator.of(context).pop(value);
              return;
            }
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- devices

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({required this.provider});

  final LinkedDevicesProvider provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<LinkedDevice> devices = provider.devices;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Linked devices (${devices.length})',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              Text(
                'No other device is linked yet.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (final LinkedDevice device in devices)
                _DeviceTile(
                  device: device,
                  canManage: provider.canManageDevices,
                  onChangedRole: (DeviceRole role) =>
                      provider.changeRole(device, role),
                  onUnlink: () => _confirmUnlink(context, provider, device),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUnlink(
    BuildContext context,
    LinkedDevicesProvider provider,
    LinkedDevice device,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Unlink ${device.displayName}?'),
        content: const Text(
          'The device keeps its local copy of the ledger but stops syncing.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await provider.unlinkDevice(device);
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.canManage,
    required this.onChangedRole,
    required this.onUnlink,
  });

  final LinkedDevice device;
  final bool canManage;
  final ValueChanged<DeviceRole> onChangedRole;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(
          device.displayName.isEmpty
              ? '?'
              : device.displayName.substring(0, 1).toUpperCase(),
        ),
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              device.displayName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (device.isCurrentDevice) ...<Widget>[
            const SizedBox(width: 6),
            Chip(
              label: const Text('This device'),
              visualDensity: VisualDensity.compact,
              labelStyle: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${device.platform} • last seen ${_lastSeen(device.lastSeenAt)}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: device.role == DeviceRole.owner
          ? Chip(
              label: const Text('Owner'),
              visualDensity: VisualDensity.compact,
              labelStyle: theme.textTheme.labelSmall,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                PopupMenuButton<DeviceRole>(
                  enabled: canManage,
                  initialValue: device.role,
                  onSelected: onChangedRole,
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<DeviceRole>>[
                    for (final DeviceRole role in <DeviceRole>[
                      DeviceRole.editor,
                      DeviceRole.viewer,
                    ])
                      PopupMenuItem<DeviceRole>(
                        value: role,
                        child: Text(role.label),
                      ),
                  ],
                  child: Chip(
                    label: Text(device.role.label),
                    visualDensity: VisualDensity.compact,
                    labelStyle: theme.textTheme.labelSmall,
                    avatar: Icon(
                      device.role == DeviceRole.editor
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                      size: 16,
                    ),
                  ),
                ),
                if (canManage)
                  IconButton(
                    tooltip: 'Unlink device',
                    icon: const Icon(Icons.link_off),
                    onPressed: onUnlink,
                  ),
              ],
            ),
    );
  }

  static String _lastSeen(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) {
      return 'unknown';
    }
    final Duration ago = DateTime.now().difference(value);
    if (ago.inMinutes < 1) {
      return 'just now';
    }
    if (ago.inMinutes < 60) {
      return '${ago.inMinutes} min ago';
    }
    if (ago.inHours < 24) {
      return '${ago.inHours} h ago';
    }
    return '${ago.inDays} d ago';
  }
}

class _DangerZoneCard extends StatelessWidget {
  const _DangerZoneCard({required this.provider});

  final LinkedDevicesProvider provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('This device', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _rename(context, provider),
              icon: const Icon(Icons.drive_file_rename_outline),
              label: const Text('Rename this device'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: provider.isBusy ? null : () => _leave(context, provider),
              icon: const Icon(Icons.logout),
              label: Text(
                provider.canManageDevices
                    ? 'Leave workspace (owner)'
                    : 'Leave workspace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    LinkedDevicesProvider provider,
  ) async {
    final TextEditingController controller =
        TextEditingController(text: provider.deviceName);

    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Device name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      await provider.renameThisDevice(name);
    }
  }

  Future<void> _leave(
    BuildContext context,
    LinkedDevicesProvider provider,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Leave this workspace?'),
        content: Text(
          provider.canManageDevices
              ? 'You are the owner. Leaving stops syncing on this device; the '
                  'other devices keep their local copies but can no longer '
                  'sync with each other through this workspace.'
              : 'Your local ledger stays on this device, but it will no '
                  'longer receive changes from the other devices.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await provider.leaveWorkspace();
  }
}

// ---------------------------------------------------------------- helpers

void _showResult(
  BuildContext context,
  LinkedDevicesProvider provider,
  bool ok,
) {
  final String? message = ok
      ? provider.infoMessage
      : (provider.errorMessage ?? 'That did not work. Try again.');

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message ?? 'Done'),
      backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
    ),
  );
  provider.clearMessages();
}
