import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_pin_service.dart';
import '../services/biometric_auth_service.dart';
import '../widgets/app_pin_dialogs.dart';

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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildGateBody(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGateBody(BuildContext context) {
    switch (_view) {
      case _AppPinGateView.loading:
        return const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        );
      case _AppPinGateView.setupPrompt:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.shield_outlined, size: 40),
            const SizedBox(height: 16),
            Text(
              'Protect This Device',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'You can set an optional 4 to 6 digit PIN for this app. If you skip it, the app will open normally.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _savePin,
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('Set App PIN'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _skipPinSetup,
                child: const Text('Continue Without PIN'),
              ),
            ),
          ],
        );
      case _AppPinGateView.unlock:
        return Form(
          key: _unlockFormKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.lock_rounded, size: 40),
              const SizedBox(height: 16),
              Text(
                'Unlock Balance Desk',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _biometricReady
                    ? 'Use $_biometricLabel or enter your PIN to continue.'
                    : 'Enter your app PIN to continue.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),

              // Biometric button — shown only when device supports it and user
              // has enabled it in settings.
              if (_biometricReady) ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _authenticateWithBiometric,
                    icon: Icon(_biometricIcon),
                    label: Text('Use $_biometricLabel'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or enter PIN',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
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
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  counterText: '',
                ),
                validator: AppPinService.validatePin,
                onFieldSubmitted: (_) => _unlock(),
              ),
              if ((_errorMessage ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _unlock,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('Unlock'),
                ),
              ),
            ],
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
