import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/linked_devices_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/linked_devices_service.dart';

class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  final TextEditingController _inviteController = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _share(LinkedDevicesProvider provider) async {
    final name = await _showWorkspaceNameDialog(context);
    if (name == null || !mounted) return;
    try {
      await provider.shareCurrentWorkspace(name);
      if (!mounted) return;
      _showMessage('Workspace sharing is ready.');
      await provider.refreshDevices();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _join(LinkedDevicesProvider provider, String value) async {
    final code = value.trim();
    if (code.isEmpty || _joining) return;
    setState(() => _joining = true);
    try {
      final workspace = await provider.joinWorkspace(code);
      _inviteController.clear();
      if (mounted) {
        _showMessage('Connected to ${workspace.name}. Downloading workspace data…');
      }
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _generateInvite(LinkedDevicesProvider provider) async {
    try {
      await provider.createInvite();
      if (mounted && provider.invite != null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => _InviteDialog(invite: provider.invite!),
        );
      }
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _confirmStopSharing(LinkedDevicesProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop sharing this workspace?'),
        content: const Text(
          'This permanently removes the shared workspace and its cloud data. '
          'Your local ledger stays on this device. Other linked devices will stop syncing '
          'and keep their existing local copies.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop sharing'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await provider.stopSharing();
      if (mounted) _showMessage('Cloud sharing stopped. Local data was kept.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _disconnect(LinkedDevicesProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect this device?'),
        content: const Text(
          'This device will no longer sync with the owner. Its local workspace data will remain on this device.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await provider.disconnect();
      if (mounted) _showMessage('Disconnected. The local copy is still available.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _setDevicePermission(
    LinkedDevicesProvider provider,
    Map<String, Object?> device,
    String permission,
  ) async {
    try {
      await provider.setDevicePermission(device['id'].toString(), permission);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _transferOwnership(
    LinkedDevicesProvider provider,
    Map<String, Object?> device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer workspace ownership?'),
        content: Text(
          '${device['name'] ?? 'This device'} becomes the owner and can manage all linked devices. '
          'This device will become a regular linked device. You can transfer ownership again later.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Transfer ownership')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await provider.transferOwnership(device['id'].toString());
      if (mounted) _showMessage('Ownership transferred.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _revokeDevice(
    LinkedDevicesProvider provider,
    Map<String, Object?> device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlink this device?'),
        content: Text(
          '${device['name'] ?? 'This device'} will lose cloud access immediately. '
          'Any local copy already downloaded remains on that device.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unlink device'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await provider.revokeDevice(device['id'].toString());
      if (mounted) _showMessage('Device unlinked.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<String?> _showWorkspaceNameDialog(BuildContext context) async {
    final controller = TextEditingController(
      text: context.read<WorkspaceProvider>().activeWorkspace.name,
    );
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Share this workspace'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Workspace name',
              hintText: 'e.g. Main Shop',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _canScan => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return Consumer<LinkedDevicesProvider>(
      builder: (context, provider, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Linked devices'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Sync now',
                onPressed: provider.isLinked && !provider.isSyncing
                    ? () => provider.syncNow().catchError((Object error) {
                        if (mounted) _showMessage(error.toString());
                      })
                    : null,
                icon: provider.isSyncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                      children: <Widget>[
                        _statusCard(context, provider),
                        const SizedBox(height: 16),
                        if (!provider.isLinked) ...<Widget>[
                          _introCard(context),
                          const SizedBox(height: 16),
                          _actionCard(
                            context,
                            icon: Icons.devices_rounded,
                            title: 'Share this workspace',
                            description: 'Make this device the owner and link other devices with a short-lived, one-use QR invite.',
                            buttonText: provider.isBusy ? 'Setting up…' : 'Share current workspace',
                            onPressed: provider.isBusy ? null : () => _share(provider),
                          ),
                          const SizedBox(height: 12),
                          _joinCard(context, provider),
                        ] else if (provider.isOwner) ...<Widget>[
                          _actionCard(
                            context,
                            icon: Icons.qr_code_2_rounded,
                            title: 'Link another device',
                            description: 'Create a one-use invite. It expires after five minutes and is invalid as soon as it is claimed.',
                            buttonText: provider.isBusy ? 'Preparing invite…' : 'Create secure invite',
                            onPressed: provider.isBusy ? null : () => _generateInvite(provider),
                          ),
                          const SizedBox(height: 16),
                          _devicesCard(context, provider),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: provider.isBusy ? null : () => _confirmStopSharing(provider),
                            icon: const Icon(Icons.cloud_off_outlined),
                            label: const Text('Stop sharing and remove cloud copy'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.error,
                              side: BorderSide(color: colors.error.withValues(alpha: 0.45)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ] else ...<Widget>[
                          _permissionCard(context, provider),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: provider.isBusy ? null : () => _disconnect(provider),
                            icon: const Icon(Icons.link_off_rounded),
                            label: const Text('Disconnect this device'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.error,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ],
                        if (provider.conflictCount > 0) ...<Widget>[
                          const SizedBox(height: 16),
                          _conflictsCard(context, provider),
                        ],
                        const SizedBox(height: 18),
                        _securityNote(context),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _statusCard(BuildContext context, LinkedDevicesProvider provider) {
    final colors = Theme.of(context).colorScheme;
    final hasError = provider.error != null;
    final color = hasError ? colors.error : colors.primary;
    final lastSync = provider.lastSyncAt;
    final lastSyncLabel = lastSync == null
        ? null
        : TimeOfDay.fromDateTime(lastSync).format(context);
    final lastSuccessDetail = lastSyncLabel == null
        ? ''
        : ' Last successful sync: $lastSyncLabel.';
    final detail = hasError
        ? provider.conflictCount > 0
            ? '${provider.error} Other records continue syncing.$lastSuccessDetail'
            : provider.isLinked
                ? '${provider.error}$lastSuccessDetail Will retry automatically.'
                : provider.error!
        : lastSyncLabel == null
            ? provider.isLinked
                ? 'Automatic sync is on. Cloud changes are checked about every 15 seconds.'
                : 'This workspace remains local until you choose to share or join.'
            : 'Last synced $lastSyncLabel'
                '${provider.lastChangeCount > 0 ? ' · ${provider.lastChangeCount} updates applied' : ''} · checking for cloud changes every 15 seconds';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(hasError ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(provider.syncLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(detail, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _introCard(BuildContext context) {
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Your books, available across your devices', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Link a phone, tablet, or computer to the same workspace. Each device keeps a local copy; changes sync in the background when online.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          const _FeatureLine(icon: Icons.offline_bolt_outlined, text: 'Keep working offline; changes queue locally.'),
          const _FeatureLine(icon: Icons.admin_panel_settings_outlined, text: 'The owner can set read-only access or unlink any device.'),
          const _FeatureLine(icon: Icons.compare_arrows_outlined, text: 'Conflicting edits are surfaced for review, not silently overwritten.'),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback? onPressed,
  }) {
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 10), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)))]),
          const SizedBox(height: 8),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: onPressed, child: Text(buttonText))),
        ],
      ),
    );
  }

  Widget _joinCard(BuildContext context, LinkedDevicesProvider provider) {
    final colors = Theme.of(context).colorScheme;
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Join an existing workspace', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Scan the owner device’s QR or paste the one-use invite code.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _inviteController,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    labelText: 'Invite code',
                    hintText: 'Paste the code from the owner',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
              ),
              if (_canScan) ...<Widget>[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Scan invite QR',
                  onPressed: provider.isBusy || _joining ? null : () async {
                    final token = await Navigator.of(context).push<String>(
                      MaterialPageRoute<String>(builder: (_) => const _InviteScannerScreen()),
                    );
                    if (token != null && mounted) await _join(provider, token);
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: provider.isBusy || _joining ? null : () => _join(provider, _inviteController.text),
              icon: _joining ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
              label: Text(_joining ? 'Joining…' : 'Join workspace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionCard(BuildContext context, LinkedDevicesProvider provider) {
    final colors = Theme.of(context).colorScheme;
    final readOnly = provider.isReadOnly;
    return _panel(
      context,
      child: Row(
        children: <Widget>[
          Icon(readOnly ? Icons.visibility_outlined : Icons.edit_note_rounded, size: 30, color: readOnly ? colors.tertiary : colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(readOnly ? 'Read-only access' : 'Edit access enabled', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(readOnly ? 'The owner changed this device to read-only. Local edits are blocked.' : 'This linked device can edit the shared workspace.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _devicesCard(BuildContext context, LinkedDevicesProvider provider) {
    final theme = Theme.of(context);
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Devices with access', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              TextButton.icon(onPressed: provider.isBusy ? null : () => provider.refreshDevices().catchError((Object error) => _showMessage(error.toString())), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
            ],
          ),
          const SizedBox(height: 8),
          if (provider.devices.isEmpty)
            Text('Loading device list…', style: theme.textTheme.bodyMedium)
          else
            ...provider.devices.map((device) => _deviceTile(context, provider, device)),
        ],
      ),
    );
  }

  Widget _deviceTile(BuildContext context, LinkedDevicesProvider provider, Map<String, Object?> device) {
    final isOwnerDevice = device['role'] == 'owner';
    final isActive = device['is_active'] == true;
    final readOnly = device['permission'] == 'read_only';
    final created = DateTime.tryParse(device['created_at']?.toString() ?? '');
    final lastSeen = DateTime.tryParse(device['last_seen_at']?.toString() ?? '');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 20,
            child: Icon(_deviceIcon(device['platform']?.toString() ?? '')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[Expanded(child: Text(device['name']?.toString() ?? 'Device', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))), if (isOwnerDevice) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified_user_outlined, size: 16))]),
                const SizedBox(height: 3),
                Text(
                  !isActive ? 'Unlinked' : isOwnerDevice ? 'Owner device' : readOnly ? 'Read-only' : 'Can edit',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (created != null) Text('Added ${_formatDate(created)}${lastSeen == null ? '' : ' · Active ${_formatDate(lastSeen)}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (isActive && !isOwnerDevice) ...<Widget>[
            PopupMenuButton<String>(
              tooltip: 'Manage device access',
              onSelected: (value) {
                if (value == 'transfer_owner') {
                  _transferOwnership(provider, device);
                } else {
                  _setDevicePermission(provider, device, value);
                }
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem(value: 'edit', child: Text('Allow editing')),
                PopupMenuItem(value: 'read_only', child: Text('Read only')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'transfer_owner', child: Text('Make workspace owner')),
              ],
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: 'Unlink device',
              onPressed: () => _revokeDevice(provider, device),
              icon: Icon(Icons.link_off_rounded, color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _conflictsCard(BuildContext context, LinkedDevicesProvider provider) {
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Review sync conflicts (${provider.conflictCount})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('The same record changed on more than one device. Choose which version to keep; neither version was silently discarded.'),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, Object?>>>(
            future: provider.getConflicts(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <Map<String, Object?>>[];
              return Column(
                children: rows.map((conflict) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text('${conflict['entity']} record'),
                  subtitle: Text('ID ${conflict['recordId']} · choose local or cloud copy'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _resolveConflict(context, provider, conflict),
                )).toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _resolveConflict(BuildContext context, LinkedDevicesProvider provider, Map<String, Object?> conflict) async {
    final localJson = jsonDecode(conflict['localPayload'] as String);
    final cloudJson = jsonDecode(conflict['cloudPayload'] as String);
    final keepLocal = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose the version to keep'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('This device', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                SelectableText(const JsonEncoder.withIndent('  ').convert(localJson)),
                const SizedBox(height: 14),
                Text('Cloud version', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                SelectableText(const JsonEncoder.withIndent('  ').convert(cloudJson)),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Decide later')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Use cloud')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Keep this device')),
        ],
      ),
    );
    if (keepLocal == null) return;
    try {
      await provider.resolveConflict(
        entity: conflict['entity'].toString(),
        recordId: conflict['recordId'].toString(),
        keepThisDevice: keepLocal,
      );
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Widget _securityNote(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.surfaceContainerHighest.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.shield_outlined, color: colors.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Security: each installation has a random device key stored in the operating system’s secure storage. Invite keys are single-use and expire in five minutes. Revoked devices are rejected by the server; no privileged database key is inside the app.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.025), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  static IconData _deviceIcon(String platform) => switch (platform) {
    'android' => Icons.phone_android_rounded,
    'ios' => Icons.phone_iphone_rounded,
    'macos' || 'windows' || 'linux' => Icons.computer_rounded,
    _ => Icons.devices_other_rounded,
  };

  static String _formatDate(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.invite});
  final LinkedInvite invite;

  @override
  Widget build(BuildContext context) {
    final expires = TimeOfDay.fromDateTime(invite.expiresAt).format(context);
    return AlertDialog(
      title: const Text('Scan to link a device'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(data: invite.token, size: 220),
            ),
            const SizedBox(height: 12),
            const Text('Or copy this one-use code to the other device:'),
            const SizedBox(height: 8),
            SelectableText(invite.token, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Expires at $expires · usable once', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invite.token));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite copied.')));
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy invite'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}

class _InviteScannerScreen extends StatefulWidget {
  const _InviteScannerScreen();

  @override
  State<_InviteScannerScreen> createState() => _InviteScannerScreenState();
}

class _InviteScannerScreenState extends State<_InviteScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan workspace invite')),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            onDetect: (capture) {
              if (_handled) return;
              final value = capture.barcodes
                  .map((barcode) => barcode.rawValue?.trim() ?? '')
                  .firstWhere((code) => code.isNotEmpty, orElse: () => '');
              if (value.isEmpty) return;
              _handled = true;
              Navigator.of(context).pop(value);
            },
          ),
          Center(
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              'Align the owner’s QR code inside the frame',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 8)]),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: <Widget>[Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 9), Expanded(child: Text(text))]),
    );
  }
}
