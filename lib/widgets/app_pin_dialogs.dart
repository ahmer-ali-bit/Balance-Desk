import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_pin_service.dart';

class AppPinSetupResult {
  const AppPinSetupResult({required this.newPin, this.currentPin});

  final String newPin;
  final String? currentPin;
}

class AppPinSetupDialog extends StatefulWidget {
  const AppPinSetupDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    this.description,
    this.requireCurrentPin = false,
  });

  final String title;
  final String submitLabel;
  final String? description;
  final bool requireCurrentPin;

  @override
  State<AppPinSetupDialog> createState() => _AppPinSetupDialogState();
}

class _AppPinSetupDialogState extends State<AppPinSetupDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      AppPinSetupResult(
        currentPin: widget.requireCurrentPin
            ? _currentPinController.text.trim()
            : null,
        newPin: _newPinController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if ((widget.description ?? '').isNotEmpty) ...<Widget>[
                Text(widget.description!),
                const SizedBox(height: 16),
              ],
              if (widget.requireCurrentPin) ...<Widget>[
                _buildPinField(
                  controller: _currentPinController,
                  label: 'Current PIN',
                ),
                const SizedBox(height: 12),
              ],
              _buildPinField(
                controller: _newPinController,
                label: widget.requireCurrentPin ? 'New PIN' : 'PIN',
              ),
              const SizedBox(height: 12),
              _buildPinField(
                controller: _confirmPinController,
                label: 'Confirm PIN',
                validator: (String? value) {
                  final error = AppPinService.validatePin(value);
                  if (error != null) {
                    return error;
                  }
                  if (value?.trim() != _newPinController.text.trim()) {
                    return 'PIN confirmation does not match.';
                  }
                  return null;
                },
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }

  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      obscureText: true,
      maxLength: 6,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: validator ?? AppPinService.validatePin,
      onFieldSubmitted: onSubmitted,
    );
  }
}

class AppPinVerifyDialog extends StatefulWidget {
  const AppPinVerifyDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    this.description,
  });

  final String title;
  final String submitLabel;
  final String? description;

  @override
  State<AppPinVerifyDialog> createState() => _AppPinVerifyDialogState();
}

class _AppPinVerifyDialogState extends State<AppPinVerifyDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(_pinController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if ((widget.description ?? '').isNotEmpty) ...<Widget>[
                Text(widget.description!),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _pinController,
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
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}
