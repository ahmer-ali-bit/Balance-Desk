import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/linked_device_models.dart';
import '../services/linked_devices_controller.dart';
import '../utils/platform_helper.dart';

class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({
    super.key,
    this.initialInviteLink,
    this.controller,
  });

  final String? initialInviteLink;
  final LinkedDevicesController? controller;

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  final TextEditingController _inviteLinkController = TextEditingController();
  bool _isSubmitting = false;
  bool _didHandleInitialInvite = false;
  LinkedInviteData? _latestInvite;

  LinkedDevicesController get _controller =>
      widget.controller ?? LinkedDevicesController.instance;

  @override
  void initState() {
    super.initState();
    _inviteLinkController.text = widget.initialInviteLink?.trim() ?? '';
    _controller.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialInvite();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _inviteLinkController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<T?> _runLoadingTask<T>(Future<T?> Function() action) async {
    if (_isSubmitting) {
      return null;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      return await action();
    } catch (error) {
      final normalizedError = '$error'.toLowerCase();
      final message =
          normalizedError.contains('permission-denied') ||
              normalizedError.contains('permission denied') ||
              normalizedError.contains('firebase')
          ? 'Linked devices could not complete that action right now. Please refresh the screen and try again.'
          : 'Linked devices action could not finish right now.';
      _showMessage(message);
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<LinkedActionResult?> _runAction(
    Future<LinkedActionResult> Function() action,
  ) async {
    final result = await _runLoadingTask<LinkedActionResult>(action);
    if (result == null) {
      return null;
    }

    _showMessage(result.message);
    return result;
  }

  Future<void> _refreshLinkedDevices(LinkedDevicesController controller) async {
    if (controller.hasLinkedWorkspace) {
      await _runAction(controller.syncNow);
      return;
    }

    final refreshed = await _runLoadingTask<bool>(() async {
      await controller.initialize();
      return true;
    });
    if (!mounted || refreshed != true) {
      return;
    }

    _showMessage(
      controller.featureAvailable
          ? 'Linked devices refreshed.'
          : (controller.availabilityMessage ??
                'Linked devices are not available right now.'),
    );
  }

  Future<LinkedInviteData?> _createInvite(
    LinkedDevicesController controller,
  ) async {
    final invite = await _runLoadingTask<LinkedInviteData?>(
      () => controller.createInvite(),
    );
    if (!mounted || invite == null) {
      return null;
    }

    setState(() {
      _latestInvite = invite;
    });
    return invite;
  }

  Future<void> _showInviteDialog(LinkedDevicesController controller) async {
    final invite = await _createInvite(controller);
    if (!mounted || invite == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Share Linked Device Invite'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Scan this QR code in the app on the second device, or copy the invite link and paste it there.',
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: QrImageView(
                      data: invite.inviteLink,
                      version: QrVersions.auto,
                      size: 220,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Use Scan QR on the second device, or paste this fresh invite link in the join box.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SelectableText(invite.inviteLink),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                final freshInvite = await _createInvite(controller);
                if (freshInvite == null) {
                  return;
                }
                await Clipboard.setData(
                  ClipboardData(text: freshInvite.inviteLink),
                );
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                if (!mounted) {
                  return;
                }
                _showMessage('Fresh invite link copied.');
              },
              child: const Text('Copy Link'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyInviteLink(LinkedDevicesController controller) async {
    final invite = await _createInvite(controller);
    if (!mounted || invite == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: invite.inviteLink));
    if (!mounted) {
      return;
    }

    _showMessage('Fresh invite link copied. Paste it on the second device.');
  }

  Future<bool> _confirmWorkspaceSwitch({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _removeLinkedDevice(
    LinkedDevicesController controller,
    LinkedDeviceMember member,
  ) async {
    final shouldRemove = await _confirmWorkspaceSwitch(
      title: 'Remove Linked Device?',
      message:
          'This will disconnect ${member.deviceName} from your shared workspace. That device will return to local mode.',
      confirmLabel: 'Remove',
    );
    if (!mounted || !shouldRemove) {
      return;
    }

    await _runAction(() => controller.revokeMember(member.uid));
  }

  Future<void> _disconnectFromWorkspace(
    LinkedDevicesController controller,
  ) async {
    final shouldDisconnect = await _confirmWorkspaceSwitch(
      title: 'Disconnect This Device?',
      message:
          'This will remove the shared workspace from this device and switch it back to local mode so you can enter your own data here.',
      confirmLabel: 'Disconnect',
    );
    if (!mounted || !shouldDisconnect) {
      return;
    }

    await _runAction(controller.disconnectCurrentDevice);
  }

  Future<void> _startSharingFromThisDevice(
    LinkedDevicesController controller,
  ) async {
    if (controller.hasLinkedWorkspace) {
      final shouldReplace = await _confirmWorkspaceSwitch(
        title: 'Make This Device Owner?',
        message:
            'This will replace the current linked workspace on this device and create a new owner workspace here.',
        confirmLabel: 'Continue',
      );
      if (!mounted || !shouldReplace) {
        return;
      }
    }

    await _runAction(
      () => controller.createOwnerWorkspace(
        replaceCurrentLink: controller.hasLinkedWorkspace,
      ),
    );
  }

  Future<void> _joinWorkspaceFromInput(
    LinkedDevicesController controller, {
    String? overrideLink,
    bool skipReplacementPrompt = false,
  }) async {
    final link = (overrideLink ?? _inviteLinkController.text).trim();
    if (link.isEmpty) {
      _showMessage('Paste the invite link first.');
      return;
    }

    if (controller.hasLinkedWorkspace && !skipReplacementPrompt) {
      final shouldReplace = await _confirmWorkspaceSwitch(
        title: 'Join Another Workspace?',
        message:
            'This will replace the current linked workspace on this device and connect it to the new invite.',
        confirmLabel: 'Join Now',
      );
      if (!mounted || !shouldReplace) {
        return;
      }
    }

    final result = await _runAction(
      () => controller.joinWorkspaceFromLink(link),
    );
    if (!mounted || result?.isSuccess != true) {
      return;
    }

    _inviteLinkController.clear();
  }

  Future<void> _pasteInviteFromClipboard(
    LinkedDevicesController controller,
  ) async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (!mounted) {
      return;
    }

    final link = clipboardData?.text?.trim() ?? '';
    if (link.isEmpty) {
      _showMessage('Clipboard is empty.');
      return;
    }

    _inviteLinkController.text = link;
    _inviteLinkController.selection = TextSelection.collapsed(
      offset: _inviteLinkController.text.length,
    );
    controller.clearLastError();

    if (!controller.looksLikeInviteLink(link)) {
      _showMessage(
        'Clipboard text pasted. If this is not a linked-device invite, replace it before joining.',
      );
      return;
    }

    _showMessage('Invite link pasted from clipboard.');
  }

  Future<void> _handleInitialInvite() async {
    if (_didHandleInitialInvite) {
      return;
    }

    final inviteLink = widget.initialInviteLink?.trim();
    if ((inviteLink ?? '').isEmpty || !mounted) {
      return;
    }

    _didHandleInitialInvite = true;

    final shouldJoin =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Open Linked Device Invite'),
              content: const Text(
                'This invite will connect this device to the shared workspace in read-only mode first. '
                'Joining will replace the current local workspace on this device.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Join Now'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!mounted || !shouldJoin) {
      return;
    }

    await _joinWorkspaceFromInput(
      _controller,
      overrideLink: inviteLink!,
      skipReplacementPrompt: true,
    );
  }

  Future<void> _showScanQrDialog(LinkedDevicesController controller) async {
    if (!PlatformHelper.supportsQrScanner) {
      _showMessage('QR scanning is available on mobile devices only.');
      return;
    }

    final scannedValue = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return const _ScanQrDialog();
      },
    );

    if (!mounted || scannedValue == null || scannedValue.trim().isEmpty) {
      return;
    }

    _inviteLinkController.text = scannedValue.trim();
    _inviteLinkController.selection = TextSelection.collapsed(
      offset: _inviteLinkController.text.length,
    );
    await _joinWorkspaceFromInput(controller, overrideLink: scannedValue);
  }

  Future<void> _showEditCodeDialog(LinkedDevicesController controller) async {
    final result = await Navigator.of(context).push<LinkedActionResult>(
      MaterialPageRoute<LinkedActionResult>(
        fullscreenDialog: true,
        builder: (_) => _EditCodeEntryScreen(controller: controller),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    _showMessage(result.message);
  }

  Future<void> _showGeneratedEditCode(
    LinkedDevicesController controller,
    LinkedDeviceMember member,
  ) async {
    final data = await _runLoadingTask<LinkedEditCodeData?>(
      () => controller.createEditCode(member.uid),
    );
    if (!mounted || data == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Edit Access Code'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Share this code with ${member.deviceName}. It expires at ${_formatDateTime(data.expiresAt)}.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  data.code,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: data.code));
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                if (!mounted) {
                  return;
                }
                _showMessage('Edit code copied.');
              },
              child: const Text('Copy Code'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Devices'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.isInitializing || _isSubmitting
                ? null
                : () => _refreshLinkedDevices(controller),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: controller.isInitializing
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  _StatusCard(controller: controller),
                  const SizedBox(height: 16),
                  if (!controller.featureAvailable)
                    _UnavailableCard(
                      message:
                          controller.availabilityMessage ??
                          'Linked devices are not configured for this platform yet.',
                    ),
                  if (controller.featureAvailable &&
                      !controller.hasLinkedWorkspace)
                    _buildSetupCards(controller),
                  if (controller.featureAvailable && controller.isOwner)
                    _buildOwnerPanel(controller),
                  if (controller.featureAvailable &&
                      controller.hasLinkedWorkspace &&
                      !controller.isOwner)
                    _buildLinkedDevicePanel(controller),
                  if (controller.featureAvailable &&
                      controller.hasLinkedWorkspace) ...<Widget>[
                    const SizedBox(height: 16),
                    _buildJoinWorkspaceCard(
                      controller,
                      actionsEnabled: !_isSubmitting,
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildSetupCards(LinkedDevicesController controller) {
    final actionsEnabled = controller.featureAvailable && !_isSubmitting;

    return Column(
      children: <Widget>[
        _ActionCard(
          icon: Icons.cloud_upload_outlined,
          title: 'Start Sharing From This Device',
          description: null,
          actions: <Widget>[
            FilledButton.icon(
              onPressed: actionsEnabled
                  ? () => _startSharingFromThisDevice(controller)
                  : null,
              icon: const Icon(Icons.cloud_done_outlined),
              label: Text(
                controller.hasLinkedWorkspace
                    ? 'Make This Device Owner'
                    : 'Enable Linked Devices',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildJoinWorkspaceCard(controller, actionsEnabled: actionsEnabled),
      ],
    );
  }

  Widget _buildJoinWorkspaceCard(
    LinkedDevicesController controller, {
    required bool actionsEnabled,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.qr_code_2_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Join Existing Workspace',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _inviteLinkController,
              enabled: actionsEnabled,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Invite link',
                alignLabelWithHint: true,
                hintText:
                    'balancedesk://link-device?workspace=...&invite=...&token=...',
              ),
              onChanged: (_) => controller.clearLastError(),
              onSubmitted: actionsEnabled
                  ? (_) => _joinWorkspaceFromInput(controller)
                  : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: actionsEnabled
                      ? () => _joinWorkspaceFromInput(controller)
                      : null,
                  icon: const Icon(Icons.link_outlined),
                  label: const Text('Join Workspace'),
                ),
                OutlinedButton.icon(
                  onPressed: actionsEnabled
                      ? () => _pasteInviteFromClipboard(controller)
                      : null,
                  icon: const Icon(Icons.content_paste_go_outlined),
                  label: const Text('Paste From Clipboard'),
                ),
                if (PlatformHelper.supportsQrScanner)
                  OutlinedButton.icon(
                    onPressed: actionsEnabled
                        ? () => _showScanQrDialog(controller)
                        : null,
                    icon: const Icon(Icons.qr_code_scanner_outlined),
                    label: const Text('Scan QR'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerPanel(LinkedDevicesController controller) {
    final linkedMembers = controller.members
        .where(
          (LinkedDeviceMember member) =>
              member.role != LinkedWorkspaceRole.owner,
        )
        .toList(growable: false);
    final latestInvite = _latestInvite;

    if (mounted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ActionCard(
            icon: Icons.devices_outlined,
            title: 'Link Another Device',
            description: null,
            actions: <Widget>[
              FilledButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _showInviteDialog(controller),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('Show QR'),
              ),
              OutlinedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _copyInviteLink(controller),
                icon: const Icon(Icons.link_outlined),
                label: const Text('Copy Invite Link'),
              ),
              OutlinedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _runAction(controller.syncNow),
                icon: const Icon(Icons.sync_outlined),
                label: const Text('Sync Now'),
              ),
            ],
          ),
          if (latestInvite != null) ...<Widget>[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Current Invite Link',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLowest,
                      ),
                      child: SelectableText(latestInvite.inviteLink),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Linked Devices (${linkedMembers.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (linkedMembers.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'No linked devices yet. Use the QR or invite link above on the second device.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ...linkedMembers.map((LinkedDeviceMember member) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LinkedMemberCard(
                  member: member,
                  isBusy: _isSubmitting,
                  onGenerateEditCode: member.role == LinkedWorkspaceRole.editor
                      ? null
                      : () => _showGeneratedEditCode(controller, member),
                  onMakeReadOnly: member.role == LinkedWorkspaceRole.editor
                      ? () => _runAction(
                          () => controller.makeMemberReadOnly(member.uid),
                        )
                      : null,
                  onRemove: () => _removeLinkedDevice(controller, member),
                ),
              );
            }),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ActionCard(
          icon: Icons.devices_outlined,
          title: 'Link Another Device',
          description: null,
          actions: <Widget>[
            FilledButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () => _showInviteDialog(controller),
              icon: const Icon(Icons.qr_code_2_outlined),
              label: const Text('Show QR'),
            ),
            OutlinedButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () => _copyInviteLink(controller),
              icon: const Icon(Icons.link_outlined),
              label: const Text('Copy Invite Link'),
            ),
            OutlinedButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () => _runAction(controller.syncNow),
              icon: const Icon(Icons.sync_outlined),
              label: const Text('Sync Now'),
            ),
          ],
        ),
        if (_latestInvite != null) ...<Widget>[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Current Invite Link',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                    ),
                    child: SelectableText(_latestInvite!.inviteLink),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Linked Devices (${linkedMembers.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        ...controller.members.map((LinkedDeviceMember member) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    member.deviceName.isEmpty
                        ? '?'
                        : member.deviceName[0].toUpperCase(),
                  ),
                ),
                title: Text(member.deviceName),
                subtitle: Text(
                  '${member.platform} • ${member.role.label} • ${member.isActive ? 'Active' : 'Revoked'}',
                ),
                trailing: member.role == LinkedWorkspaceRole.owner
                    ? const Chip(label: Text('Owner'))
                    : PopupMenuButton<String>(
                        onSelected: (String value) async {
                          if (value == 'edit') {
                            await _showGeneratedEditCode(controller, member);
                            return;
                          }
                          if (value == 'readonly') {
                            await _runAction(
                              () => controller.makeMemberReadOnly(member.uid),
                            );
                            return;
                          }
                          if (value == 'revoke') {
                            await _runAction(
                              () => controller.revokeMember(member.uid),
                            );
                          }
                        },
                        itemBuilder: (BuildContext context) {
                          return <PopupMenuEntry<String>>[
                            if (member.role != LinkedWorkspaceRole.editor)
                              const PopupMenuItem<String>(
                                value: 'edit',
                                child: Text('Generate Edit Code'),
                              ),
                            if (member.role == LinkedWorkspaceRole.editor)
                              const PopupMenuItem<String>(
                                value: 'readonly',
                                child: Text('Make Read Only'),
                              ),
                            const PopupMenuItem<String>(
                              value: 'revoke',
                              child: Text('Revoke Access'),
                            ),
                          ];
                        },
                      ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLinkedDevicePanel(LinkedDevicesController controller) {
    final isLocalWorkspace = controller.isUsingLocalWorkspace;

    if (mounted) {
      return Column(
        children: <Widget>[
          _ActionCard(
            icon: isLocalWorkspace
                ? Icons.person_outline
                : controller.isViewer
                ? Icons.remove_red_eye_outlined
                : Icons.edit_note_outlined,
            title: isLocalWorkspace
                ? 'Your Local Workspace'
                : controller.isViewer
                ? 'Read-Only Linked Device'
                : 'Editor Linked Device',
            description: null,
            actions: <Widget>[
              OutlinedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _runAction(controller.syncNow),
                icon: const Icon(Icons.sync_outlined),
                label: const Text('Sync Now'),
              ),
              if (controller.isViewer && !isLocalWorkspace)
                FilledButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _showEditCodeDialog(controller),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Enter Edit Code'),
                ),
              if (controller.canSwitchWorkspaceView)
                FilledButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _runAction(controller.switchWorkspaceView),
                  icon: Icon(
                    isLocalWorkspace
                        ? Icons.sync_alt_outlined
                        : Icons.person_outline,
                  ),
                  label: Text(
                    isLocalWorkspace
                        ? 'Use Linked Workspace'
                        : 'Use My Workspace',
                  ),
                ),
              TextButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _disconnectFromWorkspace(controller),
                icon: const Icon(Icons.link_off_outlined),
                label: const Text('Disconnect'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        _ActionCard(
          icon: controller.isViewer
              ? Icons.remove_red_eye_outlined
              : Icons.edit_note_outlined,
          title: controller.isViewer
              ? 'Read-Only Linked Device'
              : 'Editor Linked Device',
          description: null,
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () => _runAction(controller.syncNow),
              icon: const Icon(Icons.sync_outlined),
              label: const Text('Sync Now'),
            ),
            if (controller.isViewer)
              FilledButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _showEditCodeDialog(controller),
                icon: const Icon(Icons.key_outlined),
                label: const Text('Enter Edit Code'),
              ),
            TextButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () => _runAction(controller.disconnectCurrentDevice),
              icon: const Icon(Icons.link_off_outlined),
              label: const Text('Disconnect'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final LinkedDevicesController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  foregroundColor: colorScheme.primary,
                  child: const Icon(Icons.devices_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        controller.deviceName ?? 'This Device',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(controller.workspaceSubtitle),
                    ],
                  ),
                ),
                Chip(label: Text(controller.workspaceBadgeLabel)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              controller.hasLinkedWorkspace
                  ? 'Workspace ID: ${controller.workspaceId}'
                  : 'Normal app usage stays offline. Linked devices only use internet when you enable sharing.',
            ),
            if ((controller.lastError ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                controller.lastError!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Linked Devices Need Firebase Setup',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(message),
            const SizedBox(height: 12),
            const Text(
              'The rest of the app still works offline. Once Firebase Auth, Firestore, and platform config are set up, this screen will become active.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    this.description,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if ((description ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(description!),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: actions),
          ],
        ),
      ),
    );
  }
}

class _LinkedMemberCard extends StatelessWidget {
  const _LinkedMemberCard({
    required this.member,
    required this.isBusy,
    required this.onRemove,
    this.onGenerateEditCode,
    this.onMakeReadOnly,
  });

  final LinkedDeviceMember member;
  final bool isBusy;
  final VoidCallback onRemove;
  final VoidCallback? onGenerateEditCode;
  final VoidCallback? onMakeReadOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  child: Text(
                    member.deviceName.isEmpty
                        ? '?'
                        : member.deviceName[0].toUpperCase(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        member.deviceName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${member.platform} - ${member.role.label}'),
                    ],
                  ),
                ),
                Chip(label: Text(member.role.label)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                if (onGenerateEditCode != null)
                  FilledButton.icon(
                    onPressed: isBusy ? null : onGenerateEditCode,
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Generate Edit Code'),
                  ),
                if (onMakeReadOnly != null)
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : onMakeReadOnly,
                    icon: const Icon(Icons.remove_red_eye_outlined),
                    label: const Text('Make Read Only'),
                  ),
                TextButton.icon(
                  onPressed: isBusy ? null : onRemove,
                  style: TextButton.styleFrom(foregroundColor: errorColor),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove Device'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditCodeEntryScreen extends StatefulWidget {
  const _EditCodeEntryScreen({required this.controller});

  final LinkedDevicesController controller;

  @override
  State<_EditCodeEntryScreen> createState() => _EditCodeEntryScreenState();
}

class _EditCodeEntryScreenState extends State<_EditCodeEntryScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit([String? value]) async {
    final code = (value ?? _codeController.text).trim();
    if (code.isEmpty || _isSubmitting) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
    });

    final result = await widget.controller.redeemEditCode(code);
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Edit Code')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Ask the owner device to generate an edit code for this linked device, then enter it here.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                autofocus: true,
                enabled: !_isSubmitting,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Edit code',
                  hintText: 'ABCD-123456',
                ),
                onSubmitted: _submit,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('Enable Editing'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanQrDialog extends StatefulWidget {
  const _ScanQrDialog();

  @override
  State<_ScanQrDialog> createState() => _ScanQrDialogState();
}

class _ScanQrDialogState extends State<_ScanQrDialog> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan Invite QR'),
      content: SizedBox(
        width: 320,
        height: 320,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: MobileScanner(
            controller: _controller,
            onDetect: (BarcodeCapture capture) {
              if (_hasScanned) {
                return;
              }
              final rawValue = capture.barcodes.first.rawValue;
              if ((rawValue ?? '').isEmpty) {
                return;
              }

              _hasScanned = true;
              Navigator.of(context).pop(rawValue);
            },
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
