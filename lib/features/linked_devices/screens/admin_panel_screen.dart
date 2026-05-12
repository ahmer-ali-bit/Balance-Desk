import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/linked_devices_utils.dart';
import '../services/linked_devices_service.dart';
import '../services/workspace_sync_service.dart';
import '../../../models/linked_device_models.dart';
import '../providers/linked_session_provider.dart';
import 'package:provider/provider.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  String? _inviteToken;
  DateTime? _expiry;
  bool _isLoading = false;
  bool _isDisposed = false;
  String? _errorMessage;
  String? _myDeviceId;

  @override
  void initState() {
    super.initState();
    _initMyDeviceId();
  }

  Future<void> _initMyDeviceId() async {
    final id = await LinkedDevicesUtils.getPersistentDeviceId();
    _safeSetState(() => _myDeviceId = id);
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) setState(fn);
  }

  Future<void> _generateLink() async {
    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final deviceId = await LinkedDevicesUtils.getPersistentDeviceId();
      final deviceName = await LinkedDevicesUtils.getPersistentDeviceName();
      final result = await LinkedDevicesService.instance.registerAsAdmin(
        deviceId,
        deviceName,
      );

      if (_isDisposed) return;

      if (result['success'] != true) {
        _safeSetState(() {
          _isLoading = false;
          _errorMessage =
              result['error']?.toString() ?? 'Failed to generate invite link';
        });
        return;
      }

      // Automatically upload the current database snapshot so the guest can immediately download it
      await WorkspaceSyncService.instance.uploadFullSnapshot(deviceId);

      final token = result['inviteToken'] as String?;
      final expiryValue = result['expiresAt'];
      final expiry = expiryValue is DateTime
          ? expiryValue
          : DateTime.tryParse(expiryValue?.toString() ?? '');

      _safeSetState(() {
        _isLoading = false;
        _inviteToken = token;
        _expiry = expiry;
      });
    } catch (e) {
      debugPrint('AdminPanel _generateLink error: $e');
      if (_isDisposed) return;
      _safeSetState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  Future<void> _removeDevice(LinkedSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device?'),
        content: Text('Are you sure you want to disconnect this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && _myDeviceId != null) {
      try {
        await LinkedDevicesService.instance.removeLinkedDevice(
          _myDeviceId!,
          session.linkedDeviceId,
          session.sessionId,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _generateEditCode(LinkedSession session) async {
    if (_myDeviceId == null) return;

    try {
      final code = await LinkedDevicesService.instance.generateEditableCode(
        session.sessionId,
        _myDeviceId!,
      );
      if (mounted && code.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Code generated: $code')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate code: $e')));
      }
    }
  }

  Future<void> _revokeEditAccess(LinkedSession session) async {
    try {
      await LinkedDevicesService.instance.revokeEditAccess(session.sessionId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Edit access revoked.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to revoke access: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sessionProvider = context.watch<LinkedSessionProvider>();
    final isLinked = sessionProvider.isLinked;

    return Scaffold(
      appBar: AppBar(
        title: Text(isLinked ? 'Session Status' : 'Workspace Controller'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. Invite Module ──
            if (!isLinked) 
              _buildPremiumInviteCard(theme, cs)
            else
              _buildLinkedSessionInfoCard(theme, cs, sessionProvider),
              
            const SizedBox(height: 32),

            // ── 2. Connected Instances (Only show if not linked, or show nothing for guests) ──
            if (!isLinked) ...[
              _buildSectionHeader(theme, 'SYNCHRONIZED INSTANCES', Icons.hub_rounded),
              const SizedBox(height: 16),

              if (_myDeviceId == null)
                const Center(child: CircularProgressIndicator())
              else
                StreamBuilder<List<LinkedSession>>(
                  stream: LinkedDevicesService.instance.activeSessionsStream(
                    _myDeviceId!,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final sessions = snapshot.data ?? [];
                    if (sessions.isEmpty) {
                      return _buildEmptyDevicesPlaceholder(cs);
                    }

                    return Column(
                      children: sessions.map((session) => _buildPremiumDeviceTile(theme, cs, session)).toList(),
                    );
                  },
                ),
              const SizedBox(height: 32),
            ],

            // ── 3. Protocol Overview ──
            _buildSectionHeader(theme, 'SECURITY PROTOCOL', Icons.security_rounded),
            const SizedBox(height: 16),
            _buildPremiumInfoTile(cs, Icons.add_link_rounded, 'Link Generation', 'Create unique encrypted access tokens for peers.'),
            const SizedBox(height: 12),
            _buildPremiumInfoTile(cs, Icons.sync_lock_rounded, 'Access Control', 'Define and manage granular permissions in real-time.'),
            const SizedBox(height: 12),
            _buildPremiumInfoTile(cs, Icons.devices_rounded, 'Instance Management', 'Monitor and terminate remote sessions instantly.'),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedSessionInfoCard(ThemeData theme, ColorScheme cs, LinkedSessionProvider provider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.outline, width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.link_rounded, size: 32, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Connected to Remote Workspace',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'You are currently operating in a synchronized session.',
            style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildPremiumInfoTile(
            cs, 
            Icons.verified_user_rounded, 
            'Permission Level', 
            provider.canEdit ? 'Administrative (Read/Write)' : 'Observer (Read-Only)'
          ),
          const SizedBox(height: 20),
          _buildPremiumActionButton(
            onPressed: () => provider.disconnect(context),
            isLoading: false,
            icon: Icons.link_off_rounded,
            label: 'Disconnect from Workspace',
            cs: cs,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumInviteCard(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.outline, width: 1),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.share_rounded, size: 32, color: cs.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  'Authorize New Session',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share this token with devices to sync your workspace.',
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_errorMessage!, style: TextStyle(color: cs.error, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_inviteToken != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: 'balancedesk://join?token=$_inviteToken',
                      version: QrVersions.auto,
                      size: 180.0,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: 'balancedesk://join?token=$_inviteToken'));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access Link Copied')));
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cs.outline, width: 1),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ACCESS TOKEN', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900, color: cs.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text(
                                  _inviteToken!,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontFamily: 'RobotoMono',
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.content_copy_rounded, color: cs.primary),
                        ],
                      ),
                    ),
                  ),
                  if (_expiry != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Temporary Token: Expires in ${(_expiry!.difference(DateTime.now()).inMinutes)} minutes',
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ],
            ),
          ),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: _buildPremiumActionButton(
              onPressed: _isLoading ? null : _generateLink,
              isLoading: _isLoading,
              icon: _inviteToken != null ? Icons.refresh_rounded : Icons.vpn_key_rounded,
              label: _inviteToken != null ? 'Refresh Access Link' : 'Initialize Access Key',
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumActionButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required IconData icon,
    required String label,
    required ColorScheme cs,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Icon(icon, color: cs.onPrimary),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Widget _buildEmptyDevicesPlaceholder(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline, width: 1, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Icon(Icons.sensors_off_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.3), size: 48),
          const SizedBox(height: 16),
          Text(
            'Zero Active Remote Sessions',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumDeviceTile(ThemeData theme, ColorScheme cs, LinkedSession session) {
    final isWrite = session.permission == SessionPermission.write;
    final hasActiveCode = session.editableCode != null;
    final accentColor = isWrite ? cs.primary : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline, width: 1),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.important_devices_rounded, color: accentColor, size: 24),
            ),
            title: Text(
              'Remote Node: ${LinkedDevicesUtils.formatDeviceId(session.linkedDeviceId)}',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, fontFamily: 'RobotoMono'),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isWrite ? 'ADMIN ACCESS' : 'OBSERVER ACCESS',
                      style: theme.textTheme.labelSmall?.copyWith(color: accentColor, fontWeight: FontWeight.w900, fontSize: 8),
                    ),
                  ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.cancel_rounded, color: cs.error, size: 28),
              onPressed: () => _removeDevice(session),
              style: IconButton.styleFrom(
                backgroundColor: cs.error.withValues(alpha: 0.1),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                if (!isWrite) ...[
                  if (hasActiveCode)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.key_rounded, size: 16, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 12),
                            Text(
                              session.editableCode!,
                              style: const TextStyle(fontFamily: 'RobotoMono', fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFFF59E0B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (hasActiveCode) const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _generateEditCode(session),
                      icon: Icon(hasActiveCode ? Icons.refresh_rounded : Icons.lock_open_rounded, size: 18),
                      label: Text(hasActiveCode ? 'Refresh Token' : 'Authorize Edit'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _revokeEditAccess(session),
                      icon: const Icon(Icons.lock_rounded, size: 18, color: Color(0xFFF59E0B)),
                      label: const Text('Revoke Administrative Permissions', style: TextStyle(color: Color(0xFFF59E0B))),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumInfoTile(ColorScheme cs, IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
