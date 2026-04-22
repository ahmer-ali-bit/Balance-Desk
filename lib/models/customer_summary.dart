import 'customer.dart';

class CustomerSummary {
  const CustomerSummary({
    required this.customer,
    required this.totalDebit,
    required this.totalCredit,
  });

  final Customer customer;
  final double totalDebit;
  final double totalCredit;

  double get balance => totalDebit - totalCredit;
}
