import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/linked_device_models.dart';
import '../providers/linked_session_provider.dart';
import '../services/linked_devices_service.dart';
import '../services/workspace_sync_service.dart';
import '../utils/linked_devices_utils.dart';
import '../widgets/qr_scanner_widget.dart';

class JoinWorkspaceScreen extends StatefulWidget {
  const JoinWorkspaceScreen({super.key});

  @override
  State<JoinWorkspaceScreen> createState() => _JoinWorkspaceScreenState();
}

class _JoinWorkspaceScreenState extends State<JoinWorkspaceScreen> {
  final _service = LinkedDevicesService.instance;
  final _tokenController = TextEditingController();

  bool _isLoading = false;
  bool _showQrScanner = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  String _extractToken(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'balancedesk' && uri.path == '/join') {
      return uri.queryParameters['token'] ?? value.trim();
    }
    if (value.contains('token=')) {
      return value.split('token=').last.trim();
    }
    return value.trim();
  }

  Future<void> _handleJoin(String rawValue) async {
    final token = _extractToken(rawValue);
    if (token.isEmpty) {
      setState(() => _errorMessage = 'Please enter a valid link or token');
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _successMessage = null;
      });
    }

    try {
      final joiningDeviceId = await LinkedDevicesUtils.getPersistentDeviceId();
      final joiningDeviceName =
          await LinkedDevicesUtils.getPersistentDeviceName();

      // ✅ BACKUP OWN WORKSPACE BEFORE JOINING
      // This ensures we can restore the local data when we disconnect later.
      await WorkspaceSyncService.instance.uploadFullSnapshot(
        LinkedSessionProvider.localBackupSnapshotId(joiningDeviceId),
      );

      final result = await _service.joinWorkspace(
        joiningDeviceId,
        token,
        joiningDeviceName: joiningDeviceName,
      );

      if (result['success']) {
        final sessionId = result['sessionId'] as String;
        final adminDeviceId = result['adminDeviceId']?.toString();

        if (mounted) {
          await context.read<LinkedSessionProvider>().saveSession(
            sessionId: sessionId,
            iAmAdmin: false,
            adminDeviceId: adminDeviceId,
            workspaceMode: WorkspaceMode.linked,
          );
        }

        if (mounted) {
          setState(() {
            _isLoading = false;
            _successMessage = 'Successfully joined workspace!';
          });

          // Wait a moment for the user to see the success message
          await Future.delayed(const Duration(seconds: 1));

          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                result['error'] ?? 'Join failed. Please check the link.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'An error occurred: $e';
        });
      }
    }
  }

  void _handleQrScanned(String rawValue) {
    setState(() => _showQrScanner = false);
    final token = _extractToken(rawValue);
    _tokenController.text = token;
    _handleJoin(token);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Workspace'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Premium Header ──
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: cs.outline, width: 1),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.hub_rounded, size: 40, color: cs.primary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Join Workspace',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Paste an invite code or scan the QR code on mobile.',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Join Module (Manual & QR) ──
            _buildSectionHeader(theme, 'INVITE CODE', Icons.link_rounded),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outline, width: 1),
              ),
              child: Column(
                children: [
                  // --- Option 1: Manual Token ---
                  TextField(
                    controller: _tokenController,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Invite Code / Link',
                      hintText: 'Paste invite code here',
                      prefixIcon: Icon(
                        Icons.vpn_key_rounded,
                        color: cs.primary,
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 20),
                  _buildPremiumActionButton(
                    onPressed: _isLoading
                        ? null
                        : () => _handleJoin(_tokenController.text),
                    isLoading: _isLoading,
                    icon: Icons.login_rounded,
                    label: 'Join',
                    cs: cs,
                  ),

                  // --- OR Divider ---
                  if (isMobile) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: cs.outline)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OR',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: cs.outline)),
                        ],
                      ),
                    ),

                    // --- Option 2: QR Scanner ---
                    if (!_showQrScanner)
                      _buildActionCard(
                        theme: theme,
                        cs: cs,
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'Scan QR Code',
                        subtitle: 'Use camera to join instantly',
                        onTap: () => setState(() => _showQrScanner = true),
                      )
                    else
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.primary, width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: QrScannerWidget(
                          onScanned: _handleQrScanned,
                          onClose: () => setState(() => _showQrScanner = false),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Feedback States ──
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: cs.error),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_successMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: Colors.green),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
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

  Widget _buildActionCard({
    required ThemeData theme,
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline, width: 1),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: cs.primary, size: 24),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
      width: double.infinity,
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
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Icon(icon, color: cs.onPrimary),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
