import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/platform_helper.dart';
import '../../../widgets/mobile_premium.dart';
import '../providers/linked_session_provider.dart';
import '../services/linked_devices_service.dart';

class EnterEditCodeScreen extends StatefulWidget {
  const EnterEditCodeScreen({super.key});

  @override
  State<EnterEditCodeScreen> createState() => _EnterEditCodeScreenState();
}

class _EnterEditCodeScreenState extends State<EnterEditCodeScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter the edit code.');
      return;
    }

    final sp = context.read<LinkedSessionProvider>();
    if (sp.sessionId == null) {
      setState(() => _errorMessage = 'No active session found.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await LinkedDevicesService.instance.verifyEditCode(
        sp.sessionId!,
        code,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Reload the session to pick up new permission
        await sp.loadSession();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Administrative access granted!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result['error']?.toString() ?? 'Verification failed.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const amber = Color(0xFFF59E0B);

    if (!PlatformHelper.isDesktop) {
      return _buildPremiumMobileEditCode(theme, cs, amber);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Authorization Code'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: cs.outline, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Icon ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.key_rounded, size: 48, color: amber),
                ),
                const SizedBox(height: 28),

                // ── Title ──
                Text(
                  'Enter Edit Authorization',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ask the admin for the one-time code to unlock write access.',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // ── Code Input ──
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                    color: amber,
                  ),
                  decoration: InputDecoration(
                    hintText: '000000',
                    counterText: '',
                    filled: true,
                    fillColor: amber.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: amber.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: amber, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _verifyCode(),
                ),
                const SizedBox(height: 16),

                // ── Error ──
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: cs.error,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
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
                  const SizedBox(height: 16),
                ],

                // ── Submit Button ──
                _buildPremiumButton(cs, amber),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumMobileEditCode(
    ThemeData theme,
    ColorScheme cs,
    Color amber,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Authorization Code'),
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
                icon: Icons.key_rounded,
                title: 'Edit Access',
                subtitle: 'Enter the one-time authorization code.',
                children: <Widget>[
                  MobileMetricGrid(
                    children: <Widget>[
                      MobileMetricTile(
                        label: 'Code',
                        value: '6 digits',
                        icon: Icons.pin_outlined,
                        color: amber,
                      ),
                      MobileMetricTile(
                        label: 'Access',
                        value: 'Write',
                        icon: Icons.edit_outlined,
                        color: cs.primary,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MobilePremiumPanel(
                accentColor: amber,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      style: TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: amber,
                      ),
                      decoration: const InputDecoration(
                        hintText: '000000',
                        counterText: '',
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                      onSubmitted: (_) => _verifyCode(),
                    ),
                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _verifyCode,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: const Text('Verify'),
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

  Widget _buildPremiumButton(ColorScheme cs, Color accent) {
    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _verifyCode,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.verified_user_rounded, color: Colors.white),
        label: const Text(
          'Verify & Unlock',
          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
