import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/linked_session_provider.dart';
import '../../../models/linked_device_models.dart';
import '../services/linked_devices_service.dart';
import '../services/workspace_sync_service.dart';
import '../utils/linked_devices_utils.dart';
import '../../../widgets/mobile_premium.dart';

// ✅ Real sub-screen imports
import 'join_workspace_screen.dart';
import 'enter_edit_code_screen.dart';
import 'disconnect_confirm_screen.dart';

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

      // Start session listener for guest disconnect detection
      if (provider.isLinked && !provider.iAmAdmin) {
        provider.startSessionListener(() {
          if (!_isDisposed && mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Disconnected'),
                content: const Text(
                  'You have been disconnected from the workspace. Your local workspace has been restored.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    },
                    child: const Text('OK'),
                  ),
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
    final isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (!isDesktop) {
      return _buildPremiumMobileLinkedDevices(context, theme, cs, sp, isLinked);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Devices'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadSessionSafe,
            style: IconButton.styleFrom(backgroundColor: cs.surfaceContainer),
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
                  // ── Device Header ──
                  _buildPremiumDeviceHeader(theme, cs, isDesktop, isLinked),
                  const SizedBox(height: 24),

                  if (isLinked && sp != null && !sp.iAmAdmin) ...[
                    _buildGuestLinkedCard(context, theme, cs, sp),
                  ] else ...[
                    // ── Default/admin: keep Create and Join easy to reach ──
                    const SizedBox(height: 24),
                    _buildSectionHeader(theme, 'WORKSPACE', Icons.link_rounded),
                    const SizedBox(height: 12),
                    if (isLinked && sp != null && sp.iAmAdmin)
                      _buildActionCard(
                        theme: theme,
                        cs: cs,
                        icon: Icons.hub_rounded,
                        title: 'Create / Manage',
                        subtitle:
                            'Invite code, connected devices, remove, read only',
                        onTap: () =>
                            _pushScreen(const _CreateWorkspaceScreen()),
                      )
                    else
                      _buildPremiumActionButton(
                        onPressed: () =>
                            _pushScreen(const _CreateWorkspaceScreen()),
                        icon: Icons.add_circle_outline_rounded,
                        label: 'Create',
                        cs: cs,
                      ),
                    const SizedBox(height: 20),
                    _buildPremiumActionButton(
                      onPressed: () => _pushScreen(const JoinWorkspaceScreen()),
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Join',
                      cs: cs,
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildPremiumMobileLinkedDevices(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    LinkedSessionProvider? provider,
    bool isLinked,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Devices'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadSessionSafe,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorView(theme, cs)
          : SingleChildScrollView(
              child: MobilePremiumPage(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    MobilePremiumHeader(
                      icon: Icons.smartphone_rounded,
                      title: 'Mobile Instance',
                      subtitle: isLinked
                          ? 'Linked workspace'
                          : 'Standalone workspace',
                      children: <Widget>[
                        MobileMetricGrid(
                          children: <Widget>[
                            MobileMetricTile(
                              label: 'Status',
                              value: isLinked ? 'Linked' : 'Solo',
                              icon: isLinked
                                  ? Icons.cloud_done_rounded
                                  : Icons.cloud_off_rounded,
                              color: isLinked ? cs.primary : cs.secondary,
                            ),
                            MobileMetricTile(
                              label: 'Access',
                              value:
                                  provider?.permission ==
                                      SessionPermission.write
                                  ? 'Write'
                                  : 'Read',
                              icon: Icons.admin_panel_settings_outlined,
                              color: cs.tertiary,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isLinked && provider != null && !provider.iAmAdmin)
                      _buildGuestLinkedCard(context, theme, cs, provider)
                    else
                      MobilePremiumPanel(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed: () =>
                                  _pushScreen(const _CreateWorkspaceScreen()),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                              ),
                              label: Text(
                                isLinked && provider?.iAmAdmin == true
                                    ? 'Manage Workspace'
                                    : 'Create Workspace',
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _pushScreen(const JoinWorkspaceScreen()),
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              label: const Text('Join Workspace'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPremiumDeviceHeader(
    ThemeData theme,
    ColorScheme cs,
    bool isDesktop,
    bool isLinked,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isDesktop
                  ? Icons.desktop_windows_rounded
                  : Icons.smartphone_rounded,
              color: cs.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local Instance',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDesktop ? 'Windows Desktop' : 'Mobile Application',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isLinked ? Colors.green : cs.surfaceContainer).withValues(
                alpha: 0.1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isLinked ? Colors.green : cs.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isLinked ? 'LINKED' : 'STANDALONE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isLinked ? Colors.green : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
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
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildGuestLinkedCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    LinkedSessionProvider provider,
  ) {
    final isWrite = provider.permission == SessionPermission.write;
    final accentColor = isWrite ? cs.primary : const Color(0xFFF59E0B);
    final isLinkedWs = provider.workspaceMode == WorkspaceMode.linked;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.important_devices_rounded,
                    color: cs.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Linked Device',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Connected',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isWrite ? 'WRITE' : 'READ',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _buildWsToggleBtn(
                    theme: theme,
                    cs: cs,
                    label: 'My Workspace',
                    icon: Icons.person_rounded,
                    isSelected: !isLinkedWs,
                    onTap: () => _switchWorkspace(
                      provider,
                      context,
                      WorkspaceMode.local,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildWsToggleBtn(
                    theme: theme,
                    cs: cs,
                    label: 'Linked',
                    icon: Icons.cloud_sync_rounded,
                    isSelected: isLinkedWs,
                    onTap: () => _switchWorkspace(
                      provider,
                      context,
                      WorkspaceMode.linked,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (!isWrite) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _pushScreen(const EnterEditCodeScreen()),
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text('Enter Editable Code'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accentColor,
                        side: BorderSide(
                          color: accentColor.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _pushScreen(const DisconnectConfirmScreen()),
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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

  Widget _buildWsToggleBtn({
    required ThemeData theme,
    required ColorScheme cs,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.1)
              : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchWorkspace(
    LinkedSessionProvider provider,
    BuildContext context,
    WorkspaceMode mode,
  ) async {
    if (provider.workspaceMode == mode) return;
    await provider.setWorkspaceMode(mode, context);
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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 20),
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: cs.onSurfaceVariant,
            size: 20,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required ColorScheme cs,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open: $e')));
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
            Text(
              'Sync Engine Offline',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
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

// ── Simplified Create Workspace Screen ──
class _CreateWorkspaceScreen extends StatefulWidget {
  const _CreateWorkspaceScreen();

  @override
  State<_CreateWorkspaceScreen> createState() => _CreateWorkspaceScreenState();
}

class _CreateWorkspaceScreenState extends State<_CreateWorkspaceScreen> {
  static const String _inviteTokenKey = 'linked_admin_invite_token';
  static const String _inviteExpiresAtKey = 'linked_admin_invite_expires_at';
  static const String _adminDeviceIdKey = 'linked_admin_device_id';

  String? _inviteToken;
  String? _myDeviceId;
  DateTime? _inviteExpiresAt;
  bool _isLoading = false;
  bool _isIniting = true;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadExistingInvite();
  }

  Future<void> _loadExistingInvite() async {
    final sp = context.read<LinkedSessionProvider>();
    final initMounted = mounted;
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_inviteTokenKey);
    final savedExpiry = DateTime.tryParse(
      prefs.getString(_inviteExpiresAtKey) ?? '',
    );
    final savedDeviceId = prefs.getString(_adminDeviceIdKey);
    final hasValidInvite =
        savedToken != null &&
        savedDeviceId != null &&
        savedExpiry != null &&
        DateTime.now().isBefore(savedExpiry);
    if (!hasValidInvite) {
      await prefs.remove(_inviteTokenKey);
      await prefs.remove(_inviteExpiresAtKey);
    }
    if (initMounted && hasValidInvite) {
      if (sp.isLinked && sp.iAmAdmin) {
        if (mounted) {
          setState(() {
            _inviteToken = savedToken;
            _myDeviceId = savedDeviceId;
            _inviteExpiresAt = savedExpiry;
          });
        }
      }
    }
    if (mounted) {
      setState(() => _isIniting = false);
      // Auto-generate if no existing invite
      if (_inviteToken == null) {
        _generateInvite();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isIniting) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage Workspace'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (!isDesktop) {
      return _buildPremiumMobileCreateWorkspace(theme, cs);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Workspace'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            // ── Invite Card ──
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.share_rounded,
                      size: 32,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Generate Invite',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share this code or QR with the device you want to link.',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
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
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _inviteToken!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite code copied')),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'INVITE CODE',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _inviteToken!,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
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
                    if (_inviteExpiresAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Expires in ${_minutesUntil(_inviteExpiresAt!)} minutes',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildPremiumActionButton(
              onPressed: _isLoading ? null : _generateInvite,
              isLoading: _isLoading,
              icon: _inviteToken != null
                  ? Icons.refresh_rounded
                  : Icons.vpn_key_rounded,
              label: _inviteToken != null
                  ? 'Generate New Code'
                  : 'Generate Invite Code',
              cs: cs,
            ),

            // ── Linked Devices Section ──
            if (_myDeviceId != null) ...[
              const SizedBox(height: 32),
              _buildSectionHeader(
                theme,
                'CONNECTED DEVICES',
                Icons.devices_rounded,
              ),
              const SizedBox(height: 16),
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
                    return Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.sensors_off_rounded,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No devices connected yet',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: sessions
                        .map((s) => _buildDeviceCard(theme, cs, s))
                        .toList(),
                  );
                },
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumMobileCreateWorkspace(ThemeData theme, ColorScheme cs) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Workspace'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: MobilePremiumPage(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MobilePremiumHeader(
                icon: Icons.share_rounded,
                title: 'Workspace Invite',
                subtitle: _inviteToken == null
                    ? 'Generating secure invite'
                    : 'Ready to share',
                children: <Widget>[
                  MobileMetricGrid(
                    children: <Widget>[
                      MobileMetricTile(
                        label: 'Code',
                        value: _inviteToken == null ? '...' : 'Ready',
                        icon: Icons.vpn_key_rounded,
                        color: cs.primary,
                      ),
                      MobileMetricTile(
                        label: 'Expiry',
                        value: _inviteExpiresAt == null
                            ? '-'
                            : '${_minutesUntil(_inviteExpiresAt!)} min',
                        icon: Icons.schedule_rounded,
                        color: cs.secondary,
                      ),
                    ],
                  ),
                ],
              ),
              if (_inviteToken != null) ...<Widget>[
                const SizedBox(height: 12),
                MobilePremiumPanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            kMobilePremiumRadius,
                          ),
                        ),
                        child: QrImageView(
                          data: 'balancedesk://join?token=$_inviteToken',
                          version: QrVersions.auto,
                          size: 184,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: _inviteToken!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Invite code copied'),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(
                            kMobilePremiumRadius,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(
                                kMobilePremiumRadius,
                              ),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _inviteToken!,
                                      style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontFamily: 'RobotoMono',
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                  ),
                                ),
                                Icon(
                                  Icons.content_copy_rounded,
                                  color: cs.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isLoading ? null : _generateInvite,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(
                        _inviteToken != null
                            ? Icons.refresh_rounded
                            : Icons.vpn_key_rounded,
                      ),
                label: Text(
                  _inviteToken != null ? 'Generate New Code' : 'Generate Code',
                ),
              ),
              if (_myDeviceId != null) ...<Widget>[
                const SizedBox(height: 18),
                const MobileSectionHeader(title: 'Connected Devices'),
                const SizedBox(height: 10),
                StreamBuilder<List<LinkedSession>>(
                  stream: LinkedDevicesService.instance.activeSessionsStream(
                    _myDeviceId!,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const MobilePremiumPanel(
                        child: SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }
                    final sessions = snapshot.data ?? [];
                    if (sessions.isEmpty) {
                      return const MobilePremiumPanel(
                        child: SizedBox(
                          height: 120,
                          child: Center(
                            child: Text('No devices connected yet'),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: sessions
                          .map(
                            (session) => _buildDeviceCard(theme, cs, session),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ],
          ),
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
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  int _minutesUntil(DateTime value) {
    final minutes = value.difference(DateTime.now()).inMinutes;
    return minutes < 1 ? 1 : minutes;
  }

  Widget _buildDeviceCard(
    ThemeData theme,
    ColorScheme cs,
    LinkedSession session,
  ) {
    final isWrite = session.permission == SessionPermission.write;
    final hasActiveCode = session.hasActiveEditCode;
    final accentColor = isWrite ? cs.primary : const Color(0xFFF59E0B);
    final deviceTitle = session.linkedDeviceName?.isNotEmpty == true
        ? session.linkedDeviceName!
        : LinkedDevicesUtils.formatDeviceId(session.linkedDeviceId);
    final editExpiryLabel = session.editableCodeExpiresAt == null
        ? '10 min'
        : '${_minutesUntil(session.editableCodeExpiresAt!)} min';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
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
              child: Icon(
                Icons.important_devices_rounded,
                color: accentColor,
                size: 24,
              ),
            ),
            title: Text(
              deviceTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isWrite ? 'EDITABLE' : 'READ ONLY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                  ),
                ),
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.cancel_rounded,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                size: 28,
              ),
              onPressed: () => _removeDevice(session),
            ),
          ),
          if (!isWrite)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  if (hasActiveCode) ...[
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: session.editableCode!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Edit code copied')),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.key_rounded,
                              color: accentColor,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                session.editableCode!,
                                style: TextStyle(
                                  color: accentColor,
                                  fontFamily: 'RobotoMono',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                            Text(
                              editExpiryLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.content_copy_rounded,
                              color: accentColor,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _generateEditCode(session),
                      icon: Icon(
                        hasActiveCode
                            ? Icons.refresh_rounded
                            : Icons.lock_open_rounded,
                        size: 18,
                      ),
                      label: Text(
                        hasActiveCode
                            ? 'Generate New Edit Code'
                            : 'Generate Edit Code',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _revokeEditAccess(session),
                  icon: const Icon(Icons.lock_rounded, size: 18),
                  label: const Text('Make Read Only'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _removeDevice(LinkedSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device?'),
        content: Text(
          'Disconnect ${LinkedDevicesUtils.formatDeviceId(session.linkedDeviceId)}?',
        ),
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
      await LinkedDevicesService.instance.removeLinkedDevice(
        _myDeviceId!,
        session.linkedDeviceId,
        session.sessionId,
      );
    }
  }

  Future<void> _generateEditCode(LinkedSession session) async {
    if (_myDeviceId == null) return;
    final code = await LinkedDevicesService.instance.generateEditableCode(
      session.sessionId,
      _myDeviceId!,
    );
    if (mounted && code.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Edit code: $code')));
    }
  }

  Future<void> _revokeEditAccess(LinkedSession session) async {
    await LinkedDevicesService.instance.revokeEditAccess(session.sessionId);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Device set to read only')));
    }
  }

  Future<void> _generateInvite() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final deviceId = await LinkedDevicesUtils.getPersistentDeviceId();
      final deviceName = await LinkedDevicesUtils.getPersistentDeviceName();
      final result = await LinkedDevicesService.instance.registerAsAdmin(
        deviceId,
        deviceName,
      );

      if (_isDisposed) return;

      if (result['success'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['error']?.toString() ?? 'Failed to generate invite',
              ),
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      await WorkspaceSyncService.instance.uploadFullSnapshot(deviceId);

      // Save admin session so auto-sync works
      if (mounted) {
        final sp = context.read<LinkedSessionProvider>();
        final prefs = await SharedPreferences.getInstance();
        final adminSessionId =
            'admin_${deviceId}_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('linked_session_id', adminSessionId);
        await prefs.setBool('linked_i_am_admin', true);
        await sp.saveSession(sessionId: adminSessionId, iAmAdmin: true);
      }

      final token = result['inviteToken'] as String?;
      final expiryValue = result['expiresAt'];
      final expiry = expiryValue is DateTime
          ? expiryValue
          : DateTime.tryParse(expiryValue?.toString() ?? '');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _inviteToken = token;
          _myDeviceId = deviceId;
          _inviteExpiresAt = expiry;
        });
      }
      // Persist invite token for returning visits
      final prefs2 = await SharedPreferences.getInstance();
      if (token != null) await prefs2.setString(_inviteTokenKey, token);
      if (expiry != null) {
        await prefs2.setString(_inviteExpiresAtKey, expiry.toIso8601String());
      }
      await prefs2.setString(_adminDeviceIdKey, deviceId);
    } catch (e) {
      debugPrint('_CreateWorkspaceScreen error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _buildPremiumActionButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required IconData icon,
    required String label,
    required ColorScheme cs,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }
}
