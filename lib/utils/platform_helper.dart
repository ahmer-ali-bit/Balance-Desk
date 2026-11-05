import 'dart:io';

import 'package:flutter/foundation.dart';

class PlatformHelper {
  const PlatformHelper._();

  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;

  /// Allows widget tests to exercise the mobile layout on a desktop test host.
  /// The override is read only in debug builds.
  @visibleForTesting
  static bool? debugDesktopOverride;

  static bool get isDesktop {
    var result = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    assert(() {
      result = debugDesktopOverride ?? result;
      return true;
    }());
    return result;
  }

  static String get platformLabel {
    if (isAndroid) {
      return 'Android';
    }
    if (isIOS) {
      return 'iPhone';
    }
    if (isWindows) {
      return 'Windows';
    }
    if (isMacOS) {
      return 'macOS';
    }
    if (isLinux) {
      return 'Linux';
    }
    return 'Unknown';
  }
}
