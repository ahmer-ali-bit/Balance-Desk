import 'package:flutter/services.dart';

class DecimalTextInputFormatter extends TextInputFormatter {
  DecimalTextInputFormatter({this.decimalRange = 2, this.maxDigits = 12});

  final int decimalRange;
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    if (text.isEmpty) {
      return newValue;
    }

    if (text == '.') {
      return const TextEditingValue(
        text: '0.',
        selection: TextSelection.collapsed(offset: 2),
      );
    }

    final matcher = RegExp('^\\d{0,$maxDigits}(\\.\\d{0,$decimalRange})?\$');
    if (!matcher.hasMatch(text)) {
      return oldValue;
    }

    return newValue;
  }
}
