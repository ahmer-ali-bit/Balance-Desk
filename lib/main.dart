import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_root.dart';
import 'database/app_database.dart';
import 'services/app_deep_link_service.dart';
import 'services/firebase/firebase_options.dart';
import 'services/sync/device_identity_service.dart';
import 'services/workspace_service.dart';
import 'screens/app_pin_gate_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/app_shell_screen.dart';
import 'theme/balance_desk_theme.dart';
import 'utils/platform_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize workspace service first so the database knows which file to open
  await WorkspaceService.instance.initialize();
  await AppDatabase.instance.initialize();
  await AppDeepLinkService.instance.initialize();
  await DeviceIdentityService.instance.initialize();
  await _initializeFirebase();
  runApp(const ShopDesktopApp());
}

/// Firebase powers Linked Devices only. When the build has no
/// `--dart-define` Firebase configuration the app runs exactly as a
/// local-only ledger, so a failure here must never block startup.
Future<void> _initializeFirebase() async {
  if (!DefaultFirebaseOptions.isConfigured) {
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    debugPrint('Firebase init failed — Linked Devices disabled: $error');
  }
}

class ShopDesktopApp extends StatelessWidget {
  const ShopDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformHelper.isDesktop;

    return AppRoot(
      child: MaterialApp(
        title: 'Balance Desk',
        debugShowCheckedModeBanner: false,
        theme: isDesktop
            ? BalanceDeskTheme.desktopTheme()
            : BalanceDeskTheme.lightTheme(),
        darkTheme: isDesktop
            ? BalanceDeskTheme.desktopTheme()
            : BalanceDeskTheme.darkTheme(),
        themeMode: isDesktop ? ThemeMode.light : ThemeMode.system,
        home: const SplashScreen(child: AppPinGateScreen(child: AppShellScreen())),
      ),
    );
  }
}
