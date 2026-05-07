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
    return '${formatAmount(balance)} Debit';
  }
  if (balance < 0) {
    return '${formatAmount(balance.abs())} Credit';
  }
  return '0';
}
