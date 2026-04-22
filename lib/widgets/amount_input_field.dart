import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'decimal_text_input_formatter.dart';

class AmountInputField extends StatelessWidget {
  const AmountInputField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      scrollPadding: const EdgeInsets.only(bottom: 180),
      inputFormatters: <TextInputFormatter>[
        DecimalTextInputFormatter(decimalRange: 2),
      ],
      decoration: InputDecoration(labelText: label, prefixText: 'Rs '),
      validator: validator,
    );
  }
}
