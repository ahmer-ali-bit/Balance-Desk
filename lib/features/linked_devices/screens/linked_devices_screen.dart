import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/linked_session_provider.dart';
import '../../../models/linked_device_models.dart';

// ✅ Real sub-screen imports — these are now safe (dart:io removed from all)
import 'admin_panel_screen.dart';
import 'join_workspace_screen.dart';
import 'enter_edit_code_screen.dart';
import 'disconnect_confirm_screen.dart';
import '../widgets/workspace_switcher.dart';

class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  bool _isLoading = true;
  bool _isDisposed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && mounted) _loadSessionSafe();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) setState(fn);
  }

  Future<void> _loadSessionSafe() async {
    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<LinkedSessionProvider>();
      await provider.loadSession();
      if (_isDisposed) return;

      // Start session listener for admin disconnect
      if (provider.isLinked) {
        provider.startSessionListener(() {
          if (!_isDisposed && mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Disconnected'),
                content: const Text('You have been disconnected from the workspace by the admin.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                ],
              ),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('loadSession error: $e');
      _safeSetState(() => _errorMessage = '$e');
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    LinkedSessionProvider? sp;
    try {
      sp = context.watch<LinkedSessionProvider>();
    } catch (_) {}

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLinked = sp?.isLinked ?? false;
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Synchronization'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadSessionSafe,
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainer,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView(theme, cs)
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Premium Device Header ──
                      _buildPremiumDeviceHeader(theme, cs, isDesktop, isLinked),
                      const SizedBox(height: 24),

                      if (isLinked && sp != null && !sp.iAmAdmin) ...[
                        _buildPremiumSyncStatus(theme, cs, sp),
                        const SizedBox(height: 24),
                      ],

                      // ── Connection Modules ──
                      _buildSectionHeader(theme, 'ADMINISTRATION', Icons.admin_panel_settings_rounded),
                      const SizedBox(height: 12),
                      _buildActionCard(
                        theme: theme,
                        cs: cs,
                        icon: Icons.hub_rounded,
                        title: 'Central Control Hub',
                        subtitle: 'Manage all connected instances and links',
                        onTap: () => _pushScreen(const AdminPanelScreen()),
                      ),
                      const SizedBox(height: 24),

                      if (!isLinked || (sp != null && sp.iAmAdmin)) ...[
                        _buildSectionHeader(theme, 'REMOTE ACCESS', Icons.add_link_rounded),
                        const SizedBox(height: 12),
                        _buildPremiumActionButton(
                          onPressed: () => _pushScreen(const JoinWorkspaceScreen()),
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'Link with Admin Instance',
                          cs: cs,
                        ),
                        const SizedBox(height: 24),
                      ],

                      if (isLinked && sp != null && !sp.iAmAdmin && sp.sessionId != null) ...[
                        _buildSectionHeader(theme, 'WORKSPACE CONTEXT', Icons.layers_rounded),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: cs.outline, width: 1),
                          ),
                          child: Column(
                            children: [
                              const WorkspaceSwitcher(),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 14, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      sp.workspaceMode == WorkspaceMode.linked 
                                        ? 'Synchronizing with remote cloud database.'
                                        : 'Operating on local encrypted storage.',
                                      style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      if (isLinked && sp != null && !sp.iAmAdmin) ...[
                        TextButton.icon(
                          onPressed: () => _pushScreen(const DisconnectConfirmScreen()),
                          icon: const Icon(Icons.link_off_rounded, size: 18),
                          label: const Text('Terminate Active Connection'),
                          style: TextButton.styleFrom(
                            foregroundColor: cs.error,
                            padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildPremiumDeviceHeader(ThemeData theme, ColorScheme cs, bool isDesktop, bool isLinked) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isLinked ? cs.primary.withValues(alpha: 0.3) : cs.outline, width: 1),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
            child: Icon(
              isDesktop ? Icons.desktop_windows_rounded : Icons.smartphone_rounded,
              color: cs.onPrimary, size: 24,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local Instance',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  isDesktop ? 'Windows Desktop' : 'Mobile Application',
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isLinked ? Colors.green : cs.surfaceContainerHighest).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (isLinked ? Colors.green : cs.outline).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isLinked ? Colors.green : cs.onSurfaceVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLinked ? 'LINKED' : 'STANDALONE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isLinked ? Colors.green : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumSyncStatus(ThemeData theme, ColorScheme cs, LinkedSessionProvider provider) {
    final isWrite = provider.permission == SessionPermission.write;
    final color = isWrite ? cs.primary : const Color(0xFFF59E0B);
    
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(isWrite ? Icons.verified_user_rounded : Icons.visibility_rounded,
                color: color, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWrite ? 'Full Administrative Access' : 'Secure Read-Only Access',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: color),
                ),
                Text(
                  isWrite ? 'Bi-directional synchronization active' : 'Observing remote updates in real-time',
                  style: theme.textTheme.labelSmall?.copyWith(color: color.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          if (!isWrite)
            IconButton(
              onPressed: () => _pushScreen(const EnterEditCodeScreen()),
              icon: Icon(Icons.key_rounded, color: color),
              style: IconButton.styleFrom(
                backgroundColor: color.withValues(alpha: 0.1),
              ),
            ),
        ],
      ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: cs.primary, size: 20),
        ),
        title: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  Widget _buildPremiumActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required ColorScheme cs,
  }) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: cs.onPrimary),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }

  /// ✅ Safe navigation — catches any crash from sub-screen
  void _pushScreen(Widget screen) {
    try {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    } catch (e) {
      debugPrint('Navigation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open: $e')),
        );
      }
    }
  }

  Widget _buildErrorView(ThemeData theme, ColorScheme cs) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: cs.error),
            const SizedBox(height: 20),
            Text('Sync Engine Offline',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 32),
            _buildPremiumActionButton(
              onPressed: _loadSessionSafe,
              icon: Icons.refresh_rounded,
              label: 'Re-initialize Engine',
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }
}
