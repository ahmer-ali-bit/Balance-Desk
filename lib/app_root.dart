import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/customer_provider.dart';
import 'providers/ledger_year_provider.dart';
import 'services/linked_devices_controller.dart';
import 'screens/app_shell_screen.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final linkedDevices = LinkedDevicesController.instance..initialize();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LinkedDevicesController>.value(
          value: linkedDevices,
        ),
        ChangeNotifierProvider(
          create: (_) =>
              LedgerYearProvider(linkedDevices: linkedDevices)..loadYears(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              CustomerProvider(linkedDevices: linkedDevices)..loadCustomers(),
        ),
      ],
      child: const AppShellScreen(),
    );
  }
}
