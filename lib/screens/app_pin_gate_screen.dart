import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_pin_service.dart';
import '../services/biometric_auth_service.dart';
import '../utils/platform_helper.dart';
import '../widgets/app_pin_dialogs.dart';

/// Unified PIN gate.
///
/// The lock screen is part of the brand ceremony that starts on the splash —
/// deep emerald panel, glassy emblem, one crisp card. On desktop the card sits
/// beside a brand rail; on mobile it floats on the full-viewport panel.
/// Logic (PIN verify, biometric auto-prompt, skip-prompt) is unchanged.
class AppPinGateScreen extends StatefulWidget {
  const AppPinGateScreen({super.key, required this.child});

  final Widget child;

  @override
  State<AppPinGateScreen> createState() => _AppPinGateScreenState();
}

enum _AppPinGateView { loading, setupPrompt, unlock, app }

class _AppPinGateScreenState extends State<AppPinGateScreen> {
  final AppPinService _pinService = AppPinService();
  final BiometricAuthService _biometricService = BiometricAuthService();
  final TextEditingController _unlockPinController = TextEditingController();
  final FocusNode _unlockPinFocusNode = FocusNode();
  final GlobalKey<FormState> _unlockFormKey = GlobalKey<FormState>();

  _AppPinGateView _view = _AppPinGateView.loading;
  bool _isSubmitting = false;
  String? _errorMessage;

  /// Whether biometric is available on this device AND the user has it enabled.
  bool _biometricReady = false;

  /// Human-readable label for the biometric type (e.g. "Fingerprint", "Touch ID").
  String _biometricLabel = 'Biometric';

  @override
  void initState() {
    super.initState();
    _loadGateState();
  }

  @override
  void dispose() {
    _unlockPinController.dispose();
    _unlockPinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadGateState() async {
    final hasPin = await _pinService.hasPin();
    if (!mounted) {
      return;
    }

    if (hasPin) {
      // Check biometric availability and preference before showing unlock view.
      final biometricAvailable = await _biometricService.isBiometricAvailable();
      final biometricEnabled = await _biometricService.isBiometricEnabled();
      final biometricReady = biometricAvailable && biometricEnabled;

      if (biometricReady) {
        final label = await _biometricService.getBiometricLabel();
        if (!mounted) return;
        _biometricLabel = label;
      }

      if (!mounted) return;

      setState(() {
        _biometricReady = biometricReady;
        _view = _AppPinGateView.unlock;
      });

      // Auto-trigger biometric prompt if ready.
      if (biometricReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _view == _AppPinGateView.unlock) {
            _authenticateWithBiometric();
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _view == _AppPinGateView.unlock) {
            _unlockPinFocusNode.requestFocus();
          }
        });
      }
      return;
    }

    final shouldShowSetup = await _pinService.shouldShowSetupPrompt();
    if (!mounted) {
      return;
    }

    setState(() {
      _view = shouldShowSetup
          ? _AppPinGateView.setupPrompt
          : _AppPinGateView.app;
    });
  }

  Future<void> _authenticateWithBiometric() async {
    final success = await _biometricService.authenticate(
      reason: 'Unlock Balance Desk',
    );
    if (!mounted) return;

    if (success) {
      setState(() {
        _isSubmitting = false;
        _unlockPinController.clear();
        _view = _AppPinGateView.app;
      });
    } else {
      // Biometric failed/cancelled — focus PIN field for manual entry.
      _unlockPinFocusNode.requestFocus();
    }
  }

  Future<void> _savePin() async {
    final result = await showDialog<AppPinSetupResult>(
      context: context,
      builder: (BuildContext context) {
        return const AppPinSetupDialog(
          title: 'Set App PIN',
          submitLabel: 'Save PIN',
          description:
              'Set a 4 to 6 digit PIN if you want the app to ask for it every time it opens.',
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    await _pinService.savePin(result.newPin);
    if (!mounted) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _view = _AppPinGateView.app;
    });
  }

  Future<void> _skipPinSetup() async {
    await _pinService.dismissSetupPrompt();
    if (!mounted) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _view = _AppPinGateView.app;
    });
  }

  Future<void> _unlock() async {
    if (!(_unlockFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final matches = await _pinService.verifyPin(_unlockPinController.text);
    if (!mounted) {
      return;
    }

    if (matches) {
      setState(() {
        _isSubmitting = false;
        _unlockPinController.clear();
        _view = _AppPinGateView.app;
      });
      return;
    }

    setState(() {
      _isSubmitting = false;
      _errorMessage = 'Incorrect PIN. Try again.';
    });
    _unlockPinFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_view == _AppPinGateView.app) {
      return widget.child;
    }

    final width = MediaQuery.sizeOf(context).width;
    final useDesktopLayout = PlatformHelper.isDesktop && width >= 980;

    final gateCard = _buildGateCard(context);

    if (useDesktopLayout) {
      return _buildDesktopShell(context, gateCard);
    }
    return _buildMobileShell(context, gateCard);
  }

  // ─────────────────────────────────────────────────────────────
  // Shells
  // ─────────────────────────────────────────────────────────────
  Widget _buildDesktopShell(BuildContext context, Widget card) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final panelBackground =
        isLight ? const Color(0xFFF4F5F0) : const Color(0xFF121A15);

    return Scaffold(
      backgroundColor: panelBackground,
      body: Row(
        children: <Widget>[
          Expanded(
            flex: 44,
            child: const _BrandPanel(),
          ),
          Expanded(
            flex: 56,
            child: CustomPaint(
              painter: _PaperGridPainter(isLight: isLight),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: card,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileShell(BuildContext context, Widget card) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12402E), Color(0xFF081F16)],
          ),
        ),
        child: CustomPaint(
          painter: const _BrandGridPainter(),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Gate card
  // ─────────────────────────────────────────────────────────────
  Widget _buildGateCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(
                alpha: colorScheme.brightness == Brightness.light ? 0.18 : 0.45,
              ),
              blurRadius: 44,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
            child: _buildGateBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildGateBody(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    switch (_view) {
      case _AppPinGateView.loading:
        return const SizedBox(
          height: 260,
          child: Center(child: CircularProgressIndicator()),
        );
      case _AppPinGateView.setupPrompt:
        return _GateHeader(
          icon: Icons.shield_outlined,
          eyebrow: 'PROTECT THIS DEVICE',
          title: 'Set an app PIN',
          subtitle:
              'Optional 4 to 6 digit PIN. If you skip it, the app opens normally every time.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _savePin,
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Set App PIN'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _skipPinSetup,
                child: const Text('Continue without PIN'),
              ),
            ],
          ),
        );
      case _AppPinGateView.unlock:
        return _GateHeader(
          icon: Icons.lock_rounded,
          eyebrow: 'BALANCE DESK',
          title: 'Unlock your ledger',
          subtitle: _biometricReady
              ? 'Use $_biometricLabel or enter your PIN to continue.'
              : 'Enter your app PIN to continue.',
          child: Form(
            key: _unlockFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_biometricReady) ...<Widget>[
                  OutlinedButton.icon(
                    onPressed: _authenticateWithBiometric,
                    icon: Icon(_biometricIcon, size: 19),
                    label: Text('Use $_biometricLabel'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR ENTER PIN',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 1.4,
                            fontSize: 9,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _unlockPinController,
                  focusNode: _unlockPinFocusNode,
                  autofocus: !_biometricReady,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  obscureText: true,
                  maxLength: 6,
                  enableSuggestions: false,
                  autocorrect: false,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'IBM Plex Mono',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 14,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    counterText: '',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                  ),
                  validator: AppPinService.validatePin,
                  onFieldSubmitted: (_) => _unlock(),
                ),
                if ((_errorMessage ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.error_outline_rounded,
                          size: 15,
                          color: colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _isSubmitting ? null : _unlock,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 48),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('Unlock'),
                ),
              ],
            ),
          ),
        );
      case _AppPinGateView.app:
        return const SizedBox.shrink();
    }
  }

  /// Returns an appropriate icon for the biometric type.
  IconData get _biometricIcon {
    if (_biometricLabel.contains('Face')) {
      return Icons.face_rounded;
    }
    return Icons.fingerprint_rounded;
  }
}

/// Standard header for gate states — emblem, eyebrow, title, subtitle, body.
class _GateHeader extends StatelessWidget {
  const _GateHeader({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primaryContainer,
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, size: 27, color: colorScheme.primary),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          eyebrow,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.tertiary,
            letterSpacing: 2,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.42,
          ),
        ),
        const SizedBox(height: 20),
        child,
      ],
    );
  }
}

/// Deep emerald brand panel shown beside the gate card on desktop.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12402E), Color(0xFF0B241B)],
        ),
      ),
      child: CustomPaint(
        painter: const _BrandGridPainter(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.menu_book_rounded,
                        size: 14, color: Color(0xFF7CF2B4)),
                    SizedBox(width: 8),
                    Text(
                      'BALANCE DESK',
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                        color: Color(0xFFEFF6EF),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 148,
                  height: 148,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xB308150F),
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0x40A9F0CB), width: 1.2),
                    ),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
                const SizedBox(height: 26),
                const Text(
                  'Your books are\nsafe with you.',
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 32,
                    height: 1.16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                    color: Color(0xFFEFF6EF),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'PIN lock keeps your customer and stock ledgers private —\non this device only.',
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 12.5,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9DB8A8),
                  ),
                ),
                const Spacer(),
                const Text(
                  'DEVELOPED BY AHMER ABID  ·  DESIGNED FOR PRECISION',
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: Color(0x59EFF6EF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diagonal ledger dot-grid for the emerald panel.
class _BrandGridPainter extends CustomPainter {
  const _BrandGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7CF2B4).withValues(alpha: 0.05);
    const spacing = 24.0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BrandGridPainter oldDelegate) => false;
}

/// Whisper-quiet grid for the paper panel beside the card.
class _PaperGridPainter extends CustomPainter {
  const _PaperGridPainter({required this.isLight});

  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isLight ? const Color(0xFF182420) : const Color(0xFF7CF2B4))
          .withValues(alpha: isLight ? 0.05 : 0.045);
    const spacing = 24.0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.05, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGridPainter oldDelegate) =>
      oldDelegate.isLight != isLight;
}
