import 'package:flutter/material.dart';

/// Backward-compatible wrapper for older imports.
///
/// The app no longer relies on subtree restarts, but keeping this widget
/// prevents stale imports or unsaved editor tabs from breaking builds.
class AppReloader extends StatelessWidget {
  const AppReloader({super.key, required this.child});

  final Widget child;

  static void restartApp(BuildContext context) {
    // Intentionally a no-op. Current app refresh logic is handled locally.
  }

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
