import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class NumberFormatTextInputFormatter extends TextInputFormatter {
  NumberFormatTextInputFormatter({this.decimalRange = 2, this.maxDigits = 12});

  final int decimalRange;
  final int maxDigits;
  final NumberFormat _formatter = NumberFormat('#,##,##0.##', 'en_IN');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    if (text.isEmpty) {
      return newValue;
    }

    if (text == '.') {
      return const TextEditingValue(
        text: '0.',
        selection: TextSelection.collapsed(offset: 2),
      );
    }

    // Strip all non-numeric characters except '.'
    String cleaned = text.replaceAll(RegExp(r'[^\d.]'), '');

    // Handle multiple decimal points
    if (cleaned.split('.').length > 2) {
      return oldValue;
    }

    List<String> parts = cleaned.split('.');
    String integerPart = parts[0];
    String? decimalPart = parts.length > 1 ? parts[1] : null;

    if (integerPart.length > maxDigits) {
      return oldValue;
    }

    if (decimalPart != null && decimalPart.length > decimalRange) {
      return oldValue;
    }

    double? value = double.tryParse(cleaned);
    if (value == null) {
      return oldValue;
    }

    // Format the integer part with commas
    String formattedInteger = _formatter.format(double.parse(integerPart));
    // If the formatter adds decimals, strip them as we handle them separately
    if (formattedInteger.contains('.')) {
      formattedInteger = formattedInteger.split('.')[0];
    }
    
    // Handle the special case where integerPart is empty but we have a decimal
    if (integerPart.isEmpty && decimalPart != null) {
      formattedInteger = '0';
    }

    String formatted = formattedInteger + (decimalPart != null ? '.$decimalPart' : (text.endsWith('.') ? '.' : ''));

    // Calculate new cursor position
    int newSelectionIndex = formatted.length;
    
    // Attempt to maintain cursor position relative to digits
    int digitCount = 0;
    for (int i = 0; i < newValue.selection.end; i++) {
        if (RegExp(r'[\d.]').hasMatch(text[i])) {
            digitCount++;
        }
    }
    
    int newDigitCount = 0;
    for (int i = 0; i < formatted.length; i++) {
        if (RegExp(r'[\d.]').hasMatch(formatted[i])) {
            newDigitCount++;
            if (newDigitCount == digitCount) {
                newSelectionIndex = i + 1;
                break;
            }
        }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );
  }
}
