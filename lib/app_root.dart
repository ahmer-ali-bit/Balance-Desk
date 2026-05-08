import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/customer_provider.dart';
import 'providers/ledger_year_provider.dart';
import 'screens/app_shell_screen.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              LedgerYearProvider()..loadYears(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              CustomerProvider()..loadCustomers(),
        ),
      ],
      child: const AppShellScreen(),
    );
  }
}
