import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/linked_device.dart';
import '../providers/linked_workspace_provider.dart';
import '../services/linked_workspace_service.dart';

/// Mobile screen for managing linked devices and workspace access.
/// Provides admin capability to add, remove, and edit authorized devices.
class LinkedDeviceManagementScreen extends StatefulWidget {
  const LinkedDeviceManagementScreen({super.key});

  @override
  State<LinkedDeviceManagementScreen> createState() =>
      _LinkedDeviceManagementScreenState();
}

class _LinkedDeviceManagementScreenState
    extends State<LinkedDeviceManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LinkedWorkspaceProvider>();
    final workspace = provider.currentWorkspace;
    final isAdmin = provider.isAdmin;

    if (workspace == null) {
      return const _BuildEmptyState();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Linked Devices'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_rounded),
              onPressed: _generateInvite,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (isAdmin) _BuildAdminSection(service: LinkedWorkspaceService.instance, workspace: workspace),
            _BuildDeviceList(provider: provider, workspace: workspace),
          ],
        ),
      ),
    );
  }

  Future<void> _generateInvite() async {
    final invite = await LinkedWorkspaceService.instance.generateInvite();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite generated: ${invite.token}')),
      );
    }
  }
}

class _BuildEmptyState extends StatelessWidget {
  const _BuildEmptyState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Linked Devices')),
      body: Center(
        child: Text('Not linked to any workspace yet.'),
      ),
    );
  }
}

class _BuildAdminSection extends StatelessWidget {
  const _BuildAdminSection({required this.service, required this.workspace});

  final LinkedWorkspaceService service;
  final LinkedWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Workspace Access',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _showInviteDialog(context, service),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Generate Invite Link'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showCurrentInvite(context, workspace),
              icon: const Icon(Icons.key_rounded),
              label: const Text('View Active Invite'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _leaveWorkspace(context, service, workspace),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Leave Workspace'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInviteDialog(BuildContext context, LinkedWorkspaceService service) async {
    final code = await service.generateInvite();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite code: ${code.token}')),
      );
    }
  }

  Future<void> _showCurrentInvite(BuildContext context, LinkedWorkspace workspace) async {
    if (workspace.activeInviteToken != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Active invite: ${workspace.activeInviteToken}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active invite')),
      );
    }
  }

  Future<void> _leaveWorkspace(BuildContext context, LinkedWorkspaceService service, LinkedWorkspace workspace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Workspace'),
        content: const Text('Are you sure you want to leave this linked workspace?'),
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
    if (confirmed == true) {
      await service.leaveWorkspace();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _BuildDeviceList extends StatelessWidget {
  const _BuildDeviceList({required this.provider, required this.workspace});

  final LinkedWorkspaceProvider provider;
  final LinkedWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final isAdmin = provider.isAdmin;

    if (workspace.devices.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No devices linked yet.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Authorized Devices (${workspace.devices.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        ...workspace.devices.map((device) => _BuildDeviceTile(
          device: device,
          isAdmin: isAdmin,
        )),
      ],
    );
  }
}

class _BuildDeviceTile extends StatelessWidget {
  const _BuildDeviceTile({required this.device, required this.isAdmin});

  final LinkedDevice device;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            device.status == DeviceStatus.active
                ? Icons.smartphone_outlined
                : Icons.offline_bolt_outlined,
          ),
        ),
        title: Text(device.name),
        subtitle: Text(
          '${device.platform} ${device.appVersion.isNotEmpty ? '• v${device.appVersion}' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (device.status != DeviceStatus.active)
              Chip(
                label: Text(device.status.name.toUpperCase()),
                backgroundColor: device.status == DeviceStatus.revoked
                    ? Colors.red
                    : Colors.grey.shade300,
              ),
            if (device.isAdmin)
              const Chip(
                label: Text('Admin'),
                backgroundColor: Colors.orange,
              ),
            if (device.isEditable && !device.isAdmin && isAdmin)
              PopupMenuButton<DeviceRole>(
                onSelected: (DeviceRole role) {
                  LinkedWorkspaceService.instance
                      .updateDeviceRole(device.deviceId, role);
                },
                itemBuilder: (BuildContext context) => const <PopupMenuItem<DeviceRole>>[
                  PopupMenuItem(
                    value: DeviceRole.admin,
                    child: Text('Make Admin'),
                  ),
                  PopupMenuItem(
                    value: DeviceRole.editor,
                    child: Text('Make Editor'),
                  ),
                  PopupMenuItem(
                    value: DeviceRole.viewer,
                    child: Text('Make Viewer'),
                  ),
                ],
              ),
            if (isAdmin && !device.isAdmin)
              IconButton(
                icon: const Icon(Icons.block_rounded),
                onPressed: () => _revokeDevice(context, device),
              ),
            if (isAdmin && !device.isAdmin)
              IconButton(
                icon: const Icon(Icons.person_remove_rounded),
                onPressed: () => _removeDevice(context, device),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _revokeDevice(BuildContext context, LinkedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Access'),
        content: Text('This will revoke ${device.name}\'s access to the linked workspace. The device will not be able to sync until re-authorized.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LinkedWorkspaceService.instance.revokeDevice(device.deviceId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Access revoked for ${device.name}')),
        );
      }
    }
  }

  Future<void> _removeDevice(BuildContext context, LinkedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text('Remove ${device.name} from the linked workspace?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LinkedWorkspaceService.instance.removeDevice(device.deviceId);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${device.name} from the workspace')),
        );
      }
    }
  }
}
