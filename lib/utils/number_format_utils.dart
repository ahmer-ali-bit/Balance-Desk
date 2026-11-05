import 'package:intl/intl.dart';

// NumberFormat construction is comparatively expensive (pattern parsing +
// locale lookup), so the formatters are built once and reused. Building one per
// call is what made large ledger/summary tables janky while scrolling.
final NumberFormat _wholeAmountFormatter =
    NumberFormat('#,##,##0.##', 'en_IN')
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 0;

final NumberFormat _fractionAmountFormatter =
    NumberFormat('#,##,##0.##', 'en_IN')
      ..minimumFractionDigits = 2
      ..maximumFractionDigits = 2;

final NumberFormat _bagsFormatter = NumberFormat('#,##,##0', 'en_IN');

String formatAmount(double amount) {
  // Indian numbering format: 1,00,000 / 1,00,00,000
  final formatter = amount == amount.roundToDouble()
      ? _wholeAmountFormatter
      : _fractionAmountFormatter;
  return formatter.format(amount);
}

String formatBalance(double balance) {
  if (balance > 0) {
    return '${formatAmount(balance)} D';
  }
  if (balance < 0) {
    return '${formatAmount(balance.abs())} C';
  }
  return '0';
}

String formatBags(double bags) {
  // Always format bags as integers per user request
  return _bagsFormatter.format(bags.round());
}

String formatBagsString(String bags) {
  if (bags.trim().isEmpty) return '';
  final d = double.tryParse(bags);
  if (d == null) return bags; // Return original string if not a number
  return formatBags(d);
}

String formatWeight(double totalKg) {
  final isNegative = totalKg < 0;
  final absTotalKg = totalKg.abs();
  final int mund = absTotalKg ~/ 40;
  final double kg = absTotalKg % 40;
  
  final kgStr = kg == kg.toInt() ? kg.toInt().toString() : kg.toStringAsFixed(1);
  return '${isNegative ? '-' : ''}$mund-$kgStr';
}

double parseWeight(String mundKg) {
  if (mundKg.trim().isEmpty) return 0;
  
  // Strip the ' Mund-KG' suffix if present
  String cleaned = mundKg.trim().replaceAll(RegExp(r'\s*Mund-KG\s*$', caseSensitive: false), '').trim();
  
  // Handle negative sign
  bool isNegative = false;
  if (cleaned.startsWith('-')) {
    isNegative = true;
    cleaned = cleaned.substring(1);
  }
  
  // Try parsing as single number (KG)
  final d = double.tryParse(cleaned);
  if (d != null) return isNegative ? -d : d;
  
  // Try parsing as Mund-KG format (e.g. 10-20)
  if (cleaned.contains('-')) {
    final parts = cleaned.split('-');
    if (parts.length == 2) {
      final mund = double.tryParse(parts[0]) ?? 0;
      final kg = double.tryParse(parts[1]) ?? 0;
      final total = (mund * 40) + kg;
      return isNegative ? -total : total;
    }
  }
  
  return 0;
}
