import 'package:flutter/material.dart';

import 'app_root.dart';
import 'database/app_database.dart';
import 'services/app_deep_link_service.dart';
import 'screens/app_pin_gate_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/balance_desk_theme.dart';
import 'utils/platform_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppDatabase.instance.initialize();
  await AppDeepLinkService.instance.initialize();
  runApp(const ShopDesktopApp());
}

class ShopDesktopApp extends StatelessWidget {
  const ShopDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformHelper.isDesktop;

    return MaterialApp(
      title: 'Balance Desk',
      debugShowCheckedModeBanner: false,
      theme: isDesktop
          ? BalanceDeskTheme.desktopTheme()
          : BalanceDeskTheme.lightTheme(),
      darkTheme: isDesktop
          ? BalanceDeskTheme.desktopTheme()
          : BalanceDeskTheme.darkTheme(),
      themeMode: isDesktop ? ThemeMode.light : ThemeMode.system,
      home: const SplashScreen(child: AppPinGateScreen(child: AppRoot())),
    );
  }
}
