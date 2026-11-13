import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_root.dart';
import 'database/app_database.dart';
import 'services/linked_device_credentials.dart';
import 'providers/theme_provider.dart';
import 'services/workspace_service.dart';
import 'screens/app_pin_gate_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/app_shell_screen.dart';
import 'theme/balance_desk_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize workspace service first so the database knows which file to open
  await WorkspaceService.instance.initialize();
  final linkedConfig = await LinkedWorkspaceConfigStore().read(
    WorkspaceService.instance.activeWorkspaceId,
  );
  DatabaseHelper.instance.writeGuard = () =>
      linkedConfig == null || !linkedConfig.isReadOnly;
  await AppDatabase.instance.initialize();
  runApp(const ShopDesktopApp());
}

class ShopDesktopApp extends StatelessWidget {
  const ShopDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppRoot(
      child: _ThemedMaterialApp(),
    );
  }
}

/// MaterialApp lives *inside* [AppRoot] so it can follow the user's saved
/// [ThemeProvider] selection instead of forcing a platform default.
class _ThemedMaterialApp extends StatelessWidget {
  const _ThemedMaterialApp();

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().themeMode;

    return MaterialApp(
      title: 'Balance Desk',
      debugShowCheckedModeBanner: false,
      theme: BalanceDeskTheme.lightTheme(),
      darkTheme: BalanceDeskTheme.darkTheme(),
      themeMode: themeMode,
      home: const SplashScreen(
        child: AppPinGateScreen(child: AppShellScreen()),
      ),
    );
  }
}
