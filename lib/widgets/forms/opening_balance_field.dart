import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/decimal_text_input_formatter.dart';

/// Reusable opening balance input field widget.
class OpeningBalanceField extends StatelessWidget {
  const OpeningBalanceField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.readOnly,
    required this.isWeight,
    required this.onChanged,
    this.compact = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool readOnly;
  final bool isWeight;
  final VoidCallback? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: isWeight
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : const TextInputType.numberWithOptions(decimal: true),
      scrollPadding: const EdgeInsets.only(bottom: 180),
      readOnly: readOnly,
      inputFormatters: <TextInputFormatter>[
        if (isWeight)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))
        else
          DecimalTextInputFormatter(decimalRange: 2),
      ],
      onChanged: readOnly ? null : (_) => onChanged?.call(),
      decoration: InputDecoration(
        isDense: compact,
        labelText: label,
        hintText: '0',
        filled: true,
        fillColor: colorScheme.surface.withValues(alpha: 0.88),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 10 : 14,
        ),
        prefixIcon: Padding(
          padding: EdgeInsets.all(compact ? 6 : 7),
          child: Container(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: compact ? 42 : 48,
          minHeight: compact ? 42 : 48,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: BorderSide(color: accentColor, width: 1.3),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}