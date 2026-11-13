import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/customer_provider.dart';
import 'providers/ledger_year_provider.dart';
import 'providers/workspace_provider.dart';
class AppRoot extends StatelessWidget {
  const AppRoot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => WorkspaceProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              LedgerYearProvider()..loadYears(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              CustomerProvider()..loadCustomers(),
        ),

      ],
      child: child,
    );
  }
}
