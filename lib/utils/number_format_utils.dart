import 'package:intl/intl.dart';

String formatAmount(double amount) {
  // Indian numbering format: 1,00,000 / 1,00,00,000
  final formatter = NumberFormat('#,##,##0.##', 'en_IN');
  if (amount == amount.roundToDouble()) {
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = 0;
  } else {
    formatter.minimumFractionDigits = 2;
    formatter.maximumFractionDigits = 2;
  }
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
  final formatter = NumberFormat('#,##,##0', 'en_IN');
  return formatter.format(bags.round());
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
