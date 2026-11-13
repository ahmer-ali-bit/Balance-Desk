import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/customer_provider.dart';
import 'providers/ledger_year_provider.dart';
import 'providers/linked_devices_provider.dart';
import 'providers/theme_provider.dart';
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
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),
        ChangeNotifierProxyProvider<WorkspaceProvider, LinkedDevicesProvider>(
          create: (_) => LinkedDevicesProvider(),
          update: (_, workspace, linkedDevices) {
            final provider = linkedDevices ?? LinkedDevicesProvider();
            provider.bindWorkspaceProvider(workspace);
            return provider;
          },
        ),
      ],
      child: child,
    );
  }
}
